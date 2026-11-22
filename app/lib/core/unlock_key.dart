// Round 5 review, C-08: on Android the data key can be read only while the phone is unlocked.
//
// flutter_secure_storage keeps its values readable whenever the phone has been unlocked once since it started, and its
// one stricter mode needs the device's own unlock prompt, which Solace never uses (owner, 2026-11-15: Solace's own
// six-digit passcode only). So what Solace keeps there is wrapped first, with an AES-256-GCM key in the Android
// Keystore that works only while the phone is unlocked (setUnlockedDeviceRequired, Android 9 and later; no user
// authentication; in StrongBox when the phone has one). The native side is
// android/app/src/main/kotlin/app/personal/solace/UnlockKey.kt.
//
// A running Solace keeps working while the phone is locked: it read the data key once, when it opened, and holds it in
// memory (core/store.dart EncryptedFileVault), so saves and pictures need no key store. Android 8.1 and below, a phone
// with no screen lock, and a phone whose Keystore refuses to make such a key keep the key as before (unwrapped).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'store.dart';

/// The Keystore key that works only while the phone is unlocked, through the method channel
/// `app.personal.solace/unlock_key`. Errors from the native side: `unavailable` (this phone cannot keep such a key),
/// `locked` (the Keystore refused and the phone really is locked), `gone` (the key that wrapped a value is no longer
/// in the Keystore, the value is not one it wrapped, or the Keystore refused the key on an unlocked phone that has no
/// screen lock left: round 10 review A, R10A-04), anything else a failure to try again. A call not answered within
/// [timeLimit] is such a failure too.
class UnlockKeyChannel {
  const UnlockKeyChannel([this._channel = const MethodChannel('app.personal.solace/unlock_key')]);
  final MethodChannel _channel;

  /// The mark at the start of a wrapped value (version 1: the IV, then the AES-GCM ciphertext and tag, in base64).
  static const tag = 'u1:';

  /// The longest value wrapped (a data key is 44 characters): bounded input both ways.
  static const maxValue = 4096;

  /// The IV (12 bytes) and the GCM tag (16 bytes) around the ciphertext.
  static const _overhead = 12 + 16;

  /// The longest Solace waits for the native side to answer one call (round 10 review A, R10A-04: a Keystore call that
  /// was never answered kept Solace from starting, with neither the app nor the recovery screen and its support
  /// numbers). A Keystore operation takes well under a second; past this the call counts as failed: a key that could
  /// not be read gives the recovery screen (Try again), and nothing is written, made or deleted because of it.
  @visibleForTesting
  static Duration timeLimit = const Duration(seconds: 10);

  /// One call to the native side, answered within [timeLimit] or failed with a [TimeoutException].
  Future<T?> _call<T>(String method, [Object? arguments]) => _channel.invokeMethod<T>(method, arguments).timeout(
      timeLimit, onTimeout: () => throw TimeoutException('The Keystore did not answer.', timeLimit));

  /// [value] wrapped, starting with [tag]; null when this phone cannot keep such a key (Android 8.1 and below, no
  /// screen lock, or the Keystore refused to make it), so the value is kept as before. Throws [KeyStoreLocked] while
  /// the phone is locked.
  Future<String?> wrap(String value) async {
    final clear = utf8.encode(value);
    if (clear.length > maxValue) throw ArgumentError('A value longer than Solace keeps.');
    final Uint8List? sealed;
    try {
      sealed = await _call<Uint8List>('wrap', clear);
    } on MissingPluginException {
      return null; // no native side (not Android): kept as before
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return null;
      if (e.code == 'locked') throw const KeyStoreLocked();
      rethrow;
    }
    if (sealed == null || sealed.length != clear.length + _overhead) {
      throw const FormatException('The Keystore gave back something other than a wrapped value.');
    }
    return '$tag${base64Encode(sealed)}';
  }

  /// The value inside [stored] (which starts with [tag]). Throws [KeyStoreLocked] while the phone is locked, and
  /// [KeyWrapLost] when it can never be opened on this phone (its Keystore key is gone, or the stored form is
  /// damaged); any other error is a failure that a later try may not have.
  Future<String> unwrap(String stored) async {
    if (!stored.startsWith(tag)) throw ArgumentError('Not a wrapped value.');
    final Uint8List sealed;
    try {
      sealed = base64Decode(stored.substring(tag.length));
    } on FormatException {
      throw const KeyWrapLost();
    }
    if (sealed.length <= _overhead || sealed.length > maxValue + _overhead) throw const KeyWrapLost();
    final Uint8List? clear;
    try {
      clear = await _call<Uint8List>('unwrap', sealed);
    } on PlatformException catch (e) {
      if (e.code == 'locked') throw const KeyStoreLocked();
      if (e.code == 'gone') throw const KeyWrapLost();
      rethrow;
    }
    if (clear == null || clear.length != sealed.length - _overhead) {
      throw const FormatException('The Keystore gave back something other than the wrapped value.');
    }
    return utf8.decode(clear);
  }

  /// Deletes the Keystore key (Delete everything, once every value it wrapped is gone); quiet if it cannot.
  Future<void> forget() async {
    try {
      await _call<void>('forget');
    } catch (_) {}
  }
}

/// A key store over [_inner] (flutter_secure_storage on Android) whose values are kept wrapped by [_wrap] (C-08).
///
/// A value kept before this build (or while the phone could not make the key) is plain; with [upgrade] it is wrapped
/// when it is next read: wrapped, opened again in memory, written over the plain form, read back and opened again.
/// Only then is the plain form gone; a step that fails puts the plain form back (or never replaced it), and the next
/// opening tries again. A value that cannot be wrapped just now (the phone locked meanwhile) is still returned, as it
/// opens without the Keystore. A wrapped value that cannot be opened because the phone is locked throws
/// [KeyStoreLocked], never "none".
class UnlockWrappedKeyStore implements KeyStore, KeyFiles {
  UnlockWrappedKeyStore(this._inner, this._wrap, {this.upgrade = true});
  final KeyStore _inner;
  final UnlockKeyChannel _wrap;
  final bool upgrade;

  @override
  Future<String?> read(String name) async {
    final stored = await _inner.read(name);
    if (stored == null) return null;
    if (stored.startsWith(UnlockKeyChannel.tag)) return _wrap.unwrap(stored);
    if (upgrade) await _upgrade(name, stored);
    return stored;
  }

  Future<void> _upgrade(String name, String plain) async {
    final String wrapped;
    try {
      final w = await _wrap.wrap(plain);
      if (w == null || await _wrap.unwrap(w) != plain) return; // kept as before on this phone
      wrapped = w;
    } catch (_) {
      return; // the phone locked meanwhile, or the Keystore refused: kept as it is, tried at the next opening
    }
    try {
      await _inner.write(name, wrapped);
      final back = await _inner.read(name);
      if (back == wrapped && await _wrap.unwrap(back!) == plain) return;
    } catch (_) {}
    try {
      await _inner.write(name, plain); // the plain form back: nothing is lost
    } catch (_) {} // the wrapped form stays, and it was proved to open before it was written
  }

  /// Wraps [value] before it is kept (plain on a phone that cannot keep the key); while the phone is locked nothing is
  /// written and [KeyStoreLocked] is thrown.
  @override
  Future<void> write(String name, String value) async {
    final wrapped = await _wrap.wrap(value);
    await _inner.write(name, wrapped ?? value);
  }

  @override
  Future<void> delete(String name) => _inner.delete(name);

  /// Every value, then the Keystore key that wrapped them (only once the values are gone).
  @override
  Future<void> deleteAll() async {
    await _inner.deleteAll();
    await _wrap.forget();
  }

  /// Start fresh after [KeyWrapLost]: the stored form is kept, as it is, under a dated name, then removed from [name].
  @override
  Future<void> setAsideKey(String name, String stamp) async {
    final stored = await _inner.read(name);
    if (stored == null) return;
    final aside = '$name.unreadable-$stamp';
    await _inner.write(aside, stored);
    if (await _inner.read(aside) != stored) throw StateError('The key could not be kept aside.');
    await _inner.delete(name);
  }
}
