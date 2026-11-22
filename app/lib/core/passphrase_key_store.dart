// Linux: the data key protected by a passphrase, not the desktop keyring (owner, 2026-11-14, after the OWASP review
// OW-M9-1: Linux has no app sandbox, and any program running as the same user can ask the keyring for a stored key).
// The person chooses a passphrase the first time Solace starts on Linux and types it each time Solace is opened
// fresh. The key is wrapped with a key stretched from the passphrase (Argon2id, 64 MiB, 2 passes, off the interface
// thread) and sealed with AES-256-GCM in the app's private folder; the passphrase itself is never stored. Without it
// the data cannot be opened, by anyone, by design.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'store.dart';

/// Argon2id settings for the passphrase (tests pass small ones).
class StretchSettings {
  const StretchSettings({this.memoryKib = 65536, this.iterations = 2});
  final int memoryKib, iterations;
}

const minPassphraseLength = 8, maxPassphraseLength = 256;

class WrongPassphrase implements Exception {
  const WrongPassphrase();
}

/// The passphrase did change (the new set-up file is in place), but tidying the keys sealed under it failed; the
/// next opening, with the new passphrase, finishes that (round 6 review, E-11: the screen said the old one still
/// opened Solace, when only the new one does).
class PassphraseChangedNotSettled implements Exception {
  const PassphraseChangedNotSettled();
}

class PassphraseKeyStore implements KeyStore, KeyFiles {
  PassphraseKeyStore._(this._dir, this._kek, this._salt, this._settings);
  final Directory _dir;
  // changed in place by [changePassphrase], so the store holding this object keeps working with the new passphrase
  List<int> _kek;
  List<int> _salt;
  StretchSettings _settings;

  static File _saltFile(Directory dir) => File('${dir.path}/keys/passphrase.json');

  /// Whether a passphrase was ever set on this computer.
  static Future<bool> isSetUp(Directory dir) => _saltFile(dir).exists();

  static Future<List<int>> _stretch(String passphrase, List<int> salt, StretchSettings s) => Isolate.run(() async {
        final k = await Argon2id(parallelism: 1, memory: s.memoryKib, iterations: s.iterations, hashLength: 32)
            .deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
        return k.extractBytes();
      });

  /// Sets up a new passphrase (first start). Any earlier wrapped keys are left as they are (they stay unreadable).
  static Future<PassphraseKeyStore> create(Directory dir, String passphrase,
      {StretchSettings settings = const StretchSettings()}) async {
    if (passphrase.length < minPassphraseLength || passphrase.length > maxPassphraseLength) {
      throw ArgumentError('passphrase length');
    }
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final kek = await _stretch(passphrase, salt, settings);
    final store = PassphraseKeyStore._(dir, kek, salt, settings);
    // a check value, so a wrong passphrase is told apart from a damaged key file
    final check = await store._seal(utf8.encode('solace-passphrase-check'));
    final f = _saltFile(dir);
    await f.parent.create(recursive: true);
    final part = File('${f.path}.part');
    await part.writeAsString(jsonEncode({'v': 1, 'salt': base64Encode(salt), 'm': settings.memoryKib,
        't': settings.iterations, 'check': base64Encode(check)}), flush: true);
    await part.rename(f.path);
    return store;
  }

  /// Opens with the typed passphrase, or throws [WrongPassphrase].
  static Future<PassphraseKeyStore> open(Directory dir, String passphrase) async {
    final j = jsonDecode(await _saltFile(dir).readAsString()) as Map<String, dynamic>;
    final salt = base64Decode(j['salt'] as String);
    final settings = settingsFrom(j);
    final kek = await _stretch(passphrase.length > maxPassphraseLength ? '' : passphrase, salt, settings);
    final store = PassphraseKeyStore._(dir, kek, salt, settings);
    try {
      final check = await store._open(base64Decode(j['check'] as String));
      if (utf8.decode(check) != 'solace-passphrase-check') throw const WrongPassphrase();
    } on SecretBoxAuthenticationError {
      throw const WrongPassphrase();
    }
    // only once the passphrase is known to be right (round 5 review, C-01: a wrong one typed at the start screen
    // could finish a change cut short)
    await store._settleStaged();
    return store;
  }

  /// A new passphrase, and with it a new salt and wrapping key, for every key kept (round 4 review, A-09: there was no
  /// way to change it). This object then works under the new passphrase, so the encrypted store holding it saves any
  /// later key under the new one.
  ///
  /// Every key is first sealed again under the new passphrase beside the old files (`.wrap.next`), then the new
  /// set-up file is staged; replacing the old set-up file with it is the single moment the change happens. A change
  /// that fails before that moment removes everything it staged, so the old passphrase opens everything as before. A
  /// change cut short is settled at the next opening, once the passphrase typed there is known to be right: a staged
  /// key is kept only if it opens under that passphrase, so it can never replace a key the set-up file cannot open
  /// (round 5 review, C-01: a change that stopped or failed while sealing was taken as done, and locked the data away
  /// for good under a salt that was never saved).
  Future<void> changePassphrase(String newPassphrase, {StretchSettings? settings}) async {
    if (newPassphrase.length < minPassphraseLength || newPassphrase.length > maxPassphraseLength) {
      throw ArgumentError('passphrase length');
    }
    await _settleStaged(); // whatever an earlier failed or cut-short change left behind
    final keys = Directory('${_dir.path}/keys');
    final clear = <File, List<int>>{};
    await for (final e in keys.list()) {
      if (e is File && e.path.endsWith('.wrap')) clear[e] = await _open(await e.readAsBytes());
    }
    final s = settings ?? _settings;
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final next = PassphraseKeyStore._(_dir, await _stretch(newPassphrase, salt, s), salt, s);
    final setUp = _saltFile(_dir);
    final staged = File('${setUp.path}.next');
    try {
      for (final e in clear.entries) {
        await File('${e.key.path}.next').writeAsBytes(await next._seal(e.value), flush: true);
      }
      final check = await next._seal(utf8.encode('solace-passphrase-check'));
      await staged.writeAsString(jsonEncode({'v': 1, 'salt': base64Encode(salt), 'm': s.memoryKib, 't': s.iterations,
          'check': base64Encode(check)}), flush: true);
    } catch (_) {
      await _removeStaged(); // nothing changed: the old passphrase opens everything, as the screen says
      rethrow;
    }
    await staged.rename(setUp.path); // the change happens here
    _kek = next._kek;
    _salt = salt;
    _settings = s;
    try {
      await _settleStaged();
    } catch (_) {
      throw const PassphraseChangedNotSettled(); // changed all the same (E-11)
    }
  }

  /// Settles what a change left: a staged set-up file was never put in place, so it goes; a staged key replaces the
  /// kept one only if it opens under this store's passphrase (the change happened), and is removed only when it is
  /// proved not to (it did not). Only ever called once this store's passphrase is known to be right.
  ///
  /// Round 7 review, G7-05: a staged key that could not be read (a read error, a permission problem, too many open
  /// files) was deleted as if it did not open; after the commit point of a change it is the only copy of that key
  /// under the passphrase in force, so the data key was lost. Now it is kept, every other staged key is still settled,
  /// and the error is thrown afterwards (the opening, or the change, fails and is tried again).
  Future<void> _settleStaged() async {
    final keys = Directory('${_dir.path}/keys');
    if (!await keys.exists()) return;
    final staged = File('${_saltFile(_dir).path}.next');
    if (await staged.exists()) await staged.delete();
    Object? unread;
    StackTrace? where;
    await for (final e in keys.list()) {
      if (e is! File || !e.path.endsWith('.wrap.next')) continue;
      final List<int> sealed;
      try {
        sealed = await e.readAsBytes();
      } catch (error, stack) {
        unread ??= error; // kept: not read, so nothing is proved
        where ??= stack;
        continue;
      }
      if (await _opens(sealed)) {
        await e.rename(e.path.substring(0, e.path.length - '.next'.length));
      } else {
        await e.delete();
      }
    }
    if (unread != null) Error.throwWithStackTrace(unread, where!);
  }

  /// Whether [sealed], read whole, opens under this store's passphrase: false only when that is proved (the wrapping
  /// key refused it, or it is too short to be sealed at all); any other error is thrown (round 7 review, G7-05).
  Future<bool> _opens(List<int> sealed) async {
    if (sealed.length < 12 + 16) return false;
    try {
      await _open(sealed);
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    }
  }

  Future<void> _removeStaged() async {
    final keys = Directory('${_dir.path}/keys');
    try {
      await for (final e in keys.list()) {
        if (e is File && e.path.endsWith('.wrap.next')) await e.delete();
      }
      final staged = File('${_saltFile(_dir).path}.next');
      if (await staged.exists()) await staged.delete();
    } catch (_) {} // left behind, it is settled at the next opening
  }

  /// The stretch settings written in the set-up file, within bounds: a changed file must not make every start use
  /// a gigabyte of memory or a long stretch (verification round 3, DOC-1). Set-up writes 64 MiB and 2 passes; the
  /// most a file is followed to is 256 MiB and 10 passes.
  static StretchSettings settingsFrom(Map<String, dynamic> j) {
    final m = j['m'], t = j['t'];
    return StretchSettings(memoryKib: m is int ? m.clamp(8192, maxMemoryKib) : const StretchSettings().memoryKib,
        iterations: t is int ? t.clamp(1, 10) : const StretchSettings().iterations);
  }

  static const maxMemoryKib = 262144;

  Future<List<int>> _seal(List<int> clear) async {
    final box = await AesGcm.with256bits().encrypt(clear, secretKey: SecretKey(_kek));
    return box.concatenation();
  }

  Future<List<int>> _open(List<int> sealed) async {
    final box = SecretBox.fromConcatenation(sealed, nonceLength: 12, macLength: 16);
    return AesGcm.with256bits().decrypt(box, secretKey: SecretKey(_kek));
  }

  File _keyFile(String name) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${_dir.path}/keys/$safe.wrap');
  }

  /// The key kept as [name], or null if there is none. Throws [KeyFileUnreadable] when its file is there but cannot
  /// be opened under this passphrase (damaged, or sealed under another passphrase; round 6 review, E-05: it was taken
  /// for a keyring to unlock).
  @override
  Future<String?> read(String name) async {
    final f = _keyFile(name);
    if (!await f.exists()) return null;
    final sealed = await f.readAsBytes(); // a read error stays itself: trying again may work
    try {
      return utf8.decode(await _open(sealed));
    } catch (_) {
      throw const KeyFileUnreadable();
    }
  }

  /// Moves the file of [name] aside as `<name>.wrap.unreadable-<stamp>`: never opened again by this store (a change
  /// of passphrase re-seals only `.wrap` files, and could not open this one), and deleted by Delete everything
  /// (round 6 review, E-05).
  @override
  Future<void> setAsideKey(String name, String stamp) async {
    final f = _keyFile(name);
    if (await f.exists()) await f.rename('${f.path}.unreadable-$stamp');
  }

  @override
  Future<void> write(String name, String value) async {
    final f = _keyFile(name);
    await f.parent.create(recursive: true);
    final part = File('${f.path}.part');
    await part.writeAsBytes(await _seal(utf8.encode(value)), flush: true);
    await part.rename(f.path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _keyFile(name);
    if (await f.exists()) await f.delete();
  }

  /// Every key file: each wrapped key, each staged by a passphrase change (`.wrap.next`), each write cut short
  /// (`.wrap.part`) and each set aside as unreadable ([setAsideKey]), and a staged set-up file; the passphrase set-up
  /// stays, so the next start asks for the same passphrase, and so does the keyring-delete marker (round 6 review,
  /// E-04). Round 7 review, G7-01: only `.wrap` and set-aside files went, so a key staged by a change whose tidy
  /// failed survived Delete everything and the next opening put it back. Every file is tried; the first error is
  /// thrown at the end.
  @override
  Future<void> deleteAll() async {
    final dir = Directory('${_dir.path}/keys');
    if (!await dir.exists()) return;
    Object? failed;
    StackTrace? where;
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (e is! File || !(name.contains('.wrap') || name == 'passphrase.json.next')) continue;
      try {
        await e.delete();
      } catch (error, stack) {
        failed ??= error;
        where ??= stack;
      }
    }
    if (failed != null) Error.throwWithStackTrace(failed, where!);
  }

  /// The settings this store was made with (for tests).
  StretchSettings get settings => _settings;
  List<int> get salt => List.unmodifiable(_salt);
}
