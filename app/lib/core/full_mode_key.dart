// Deep work mode (internally 'full': spoken reliving, PLAN section 5) is switched on only with the owner's 6-digit
// key (owner, 2026-11-05: "better controlled"). The app holds a salted Argon2id fingerprint of the key, never the key itself; it is given at
// build time with --dart-define-from-file=<secrets>/therapist_full_mode_key.json, which tool/full_mode_key.dart
// writes from the key in the secrets folder. A build without it cannot turn deep work mode on. Five wrong keys lock the
// switch for 15 minutes, doubling with each further wrong key. Six digits stop a person at the screen; someone who
// copies the app file off the device could still try every key offline, so this is a firm control, not a vault.
//
// The key can be changed on the device (owner, 2026-11-15: "Is there an option for me to change the 6 digit pin?
// Let's say if it gets compromised in the future?"): the new one is kept only as a fresh salted Argon2id fingerprint
// ([saved], [fromSaved]), with the built key's memory and passes, never the key itself, in a small file of its own
// beside the store ([PinKeep]) that Delete everything, Start fresh and an import all leave, so the built key never
// comes back once it has been replaced (round 9 review, 9A-01). AppState.fullModeKey decides which key is in force.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class FullModeKey {
  const FullModeKey({required this.salt, required this.fingerprint, this.memoryKib = 65536, this.iterations = 3});

  factory FullModeKey.fromEnvironment() => const FullModeKey(
      salt: String.fromEnvironment('FULL_MODE_KEY_SALT'),
      fingerprint: String.fromEnvironment('FULL_MODE_KEY_HASH'),
      memoryKib: int.fromEnvironment('FULL_MODE_KEY_MEMORY', defaultValue: 65536),
      iterations: int.fromEnvironment('FULL_MODE_KEY_ITERATIONS', defaultValue: 3));

  final String salt, fingerprint; // base64
  final int memoryKib, iterations;

  bool get isSetUp => salt.isNotEmpty && fingerprint.isNotEmpty;

  /// A key changed on the device, as kept in the settings ({salt, hash, memory, iterations}), or null when there is
  /// none or it is not one this app could have written: a 16-byte salt, a 32-byte fingerprint, and Argon2 settings
  /// within bounds, so a damaged value can never ask for a huge amount of memory or time.
  static FullModeKey? fromSaved(Object? saved) {
    if (saved is! Map) return null;
    final salt = saved['salt'], hash = saved['hash'], memory = saved['memory'], iterations = saved['iterations'];
    if (salt is! String || hash is! String || memory is! int || iterations is! int) return null;
    if (memory < 8 || memory > maxSavedMemoryKib || iterations < 1 || iterations > 10) return null;
    try {
      if (base64Decode(salt).length != 16 || base64Decode(hash).length != 32) return null;
    } on FormatException {
      return null;
    }
    return FullModeKey(salt: salt, fingerprint: hash, memoryKib: memory, iterations: iterations);
  }

  /// The most memory a key kept on the device may ask Argon2 for: 256 MiB (the built key uses 64).
  static const maxSavedMemoryKib = 262144;

  /// [key] as it is kept once changed on the device: a fresh random 16-byte salt and its Argon2id fingerprint, with
  /// this key's memory and passes (owner, 2026-11-15). The key itself is not in it.
  Future<Map<String, Object>> saved(String key, {Random? random}) async {
    final r = random ?? Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final m = memoryKib.clamp(8, maxSavedMemoryKib), i = iterations.clamp(1, 10);
    return {'salt': base64Encode(salt), 'hash': await fingerprintOf(key, salt, memoryKib: m, iterations: i),
        'memory': m, 'iterations': i};
  }

  /// Why [key] cannot be the new key, in plain words, or null when it can (owner, 2026-11-15): six digits, not one
  /// digit six times (000000), not a straight run up or down (123456, 654321, 567890).
  static String? weakKeyReason(String key) {
    if (!RegExp(r'^\d{6}$').hasMatch(key)) return 'The new PIN must be exactly six digits.';
    if (key.split('').toSet().length == 1) return 'The new PIN cannot be one digit six times. Choose a harder one.';
    final d = key.codeUnits.map((c) => c - 48).toList();
    bool run(int step) => [for (var i = 1; i < 6; i++) (d[i] - d[i - 1]) % 10 == step % 10].every((x) => x);
    if (run(1) || run(-1)) return 'The new PIN cannot be a straight run of digits. Choose a harder one.';
    return null;
  }

  static Future<String> fingerprintOf(String key, List<int> salt, {int memoryKib = 65536, int iterations = 3}) async {
    final k = await Argon2id(parallelism: 1, memory: memoryKib, iterations: iterations, hashLength: 32)
        .deriveKey(secretKey: SecretKey(utf8.encode(key)), nonce: salt);
    return base64Encode(await k.extractBytes());
  }

  /// True only for the right six digits (spaces ignored); compared in constant time.
  Future<bool> matches(String typed) async {
    final key = typed.replaceAll(RegExp(r'\s'), '');
    if (!isSetUp || !RegExp(r'^\d{6}$').hasMatch(key)) return false;
    final got = base64Decode(await fingerprintOf(key, base64Decode(salt), memoryKib: memoryKib, iterations: iterations));
    final want = base64Decode(fingerprint);
    if (got.length != want.length) return false;
    var diff = 0;
    for (var i = 0; i < got.length; i++) {
      diff |= got[i] ^ want[i];
    }
    return diff == 0;
  }
}

/// A kept PIN's file is there but cannot be read, or is not one this app wrote ([PinKeep.read]).
class PinKeepUnreadable implements Exception {
  const PinKeepUnreadable();
  @override
  String toString() => 'PinKeepUnreadable';
}

/// Where a deep work PIN changed on this device is kept (round 9 review, 9A-01: with the changed PIN in the encrypted
/// settings, Send everything, Delete everything and Bring everything back put the replaced built PIN back in force,
/// with every conversation kept). A small file in the app's private support folder, beside the store but not inside
/// it, holding only what [FullModeKey.saved] makes: a random salt and the Argon2id fingerprint, never the PIN. Delete
/// everything leaves it (core/app_files.dart wipeAppFolders), and so do "Start fresh" on the recovery screen
/// (EncryptedFileVault.setAside), Linux's "I have forgotten it", a key renewal and a passphrase change, none of which
/// touch it; a transfer file never carries it and an import never reads it. Only Change deep work PIN writes it.
/// Removing the app removes it, so a fresh install starts from the built PIN (docs/SECURITY.md section 4). It is in
/// the folder every platform keeps out of backups (iPhone, Mac: AppDelegate.swift; Android: no backup).
class PinKeep {
  PinKeep(this._folder);
  final Future<Directory> Function() _folder;

  static const fileName = 'deep_work_pin.json';

  /// A kept record is about 150 bytes; anything far larger is not one this app wrote, and is never read whole.
  static const _most = 4096;

  Future<File> _file() async => File('${(await _folder()).path}/$fileName');

  /// The kept record, or null when no PIN was changed on this device. Throws [PinKeepUnreadable] when the file is
  /// there but cannot be read or is not a record this app could have written, so the caller can refuse every PIN
  /// rather than fall back to the built one.
  Future<Map<String, dynamic>?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      if (await f.length() > _most) throw const PinKeepUnreadable();
      final record = jsonDecode(await f.readAsString());
      if (FullModeKey.fromSaved(record) == null) throw const PinKeepUnreadable();
      return Map<String, dynamic>.from(record as Map);
    } on PinKeepUnreadable {
      rethrow;
    } catch (_) {
      throw const PinKeepUnreadable();
    }
  }

  /// Keeps [record] (FullModeKey.saved): written to a part file, flushed, put in place by one rename (so the file on
  /// the device is always the old record or the new one, whole), and read back. Throws when it could not be kept.
  Future<void> write(Map<String, Object?> record) async {
    if (FullModeKey.fromSaved(record) == null) throw ArgumentError('not a kept PIN');
    final f = await _file();
    await f.parent.create(recursive: true);
    final part = File('${f.path}.part');
    await part.writeAsString(jsonEncode(record), flush: true);
    await part.rename(f.path);
    if ((await read())?['hash'] != record['hash']) throw const PinKeepUnreadable();
  }
}
