// Review round 10 A, R10A-01 (C-08 wiring, Android): every opening asks flutter_secure_storage with resetOnError: true.
//
// PlatformKeyStore.forPlatform('android') keeps a "legacy" store, `_SecureKeys(const FlutterSecureStorage())`, wrapped
// as UnlockWrappedKeyStore(upgrade: false) "so its keys are moved into [store], wrapped" (core/store.dart:627-631). On
// Android the two option sets differ only in resetOnError, so they are the SAME SharedPreferences file under the SAME
// key prefix (FlutterSecureStorageConfig.java:16-17, 72-73; the plugin even shares one FlutterSecureStorage object for
// both, FlutterSecureStoragePlugin.java:86-103): the legacy store can never hold anything the main store does not. But
// the legacy option set is AndroidOptions() with its default resetOnError = true (android_options.dart:51, sent as the
// string 'true', :232-233). PlatformKeyStore.read consults it whenever the main store has no value for a name, which is
// EVERY opening: EncryptedFileVault.load reads `solace_data_key_v1.previous`, absent unless a key renewal is half done
// (store.dart:797-808, 661-673). PlatformKeyStore.delete calls it too (store.dart:717-719).
//
// With resetOnError = true, the plugin answers ANY failure of that call (its per-call cipher set-up hitting an
// InvalidKeyException / BadPaddingException from the Keystore, FlutterSecureStorage.java:421-430 -> handleKeyMismatch
// -> deleteAllDataAndKeys :1040-1062; or the read itself throwing, FlutterSecureStoragePlugin.java:271-281) by deleting
// EVERY value under the prefix, the wrapped data key included, and returning the string "Data has been reset" as the
// value read. One transient Keystore fault on that one call, after the main store's own calls on the same opening
// worked, therefore deletes the working data key. The opening itself still succeeds (the key was read a moment before
// and is held in memory), so nothing is noticed; the next opening finds no key over existing data: 'key_missing', and
// the data can never be opened again. (PlatformKeyStore then "moves" the "Data has been reset" text across as if it were
// a legacy key, store.dart:669-672, and deletes it again through the legacy option set: the same file.)
//
// This is the F-02 resetOnError hazard left on the legacy option set, which C-08 rewired but did not remove. The first
// test is pure Dart (the app's real calls, recorded); the second stands in for the plugin's documented resetOnError
// path for one fault. Both assert the SAFE behaviour, so both fail on 2f3ce71 while the finding stands.
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

const keyName = EncryptedFileVault.keyName;
const secureStorage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const unlockChannel = MethodChannel('app.personal.solace/unlock_key');

TestDefaultBinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// UnlockKey.kt as Dart sees it (the same stand-in as test/unlocked_only_key_test.dart): AES-GCM, IV + ciphertext + tag.
class FakeUnlockKey {
  final _key = SecretKey(List.generate(32, (i) => i));
  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'wrap':
        final box = await AesGcm.with256bits().encrypt(call.arguments as Uint8List, secretKey: _key);
        return Uint8List.fromList(box.concatenation());
      case 'unwrap':
        try {
          final box = SecretBox.fromConcatenation(call.arguments as Uint8List, nonceLength: 12, macLength: 16);
          return Uint8List.fromList(await AesGcm.with256bits().decrypt(box, secretKey: _key));
        } on SecretBoxAuthenticationError {
          throw PlatformException(code: 'gone');
        }
      case 'forget':
        return null;
    }
    throw MissingPluginException();
  }
}

/// flutter_secure_storage on Android: ONE SharedPreferences file whatever resetOnError says (both option sets name the
/// same file and prefix). [calls] records each call's method, name and resetOnError. When [faultOnResetCall] is set,
/// the next call made with resetOnError 'true' meets a Keystore fault and the plugin does what its resetOnError path
/// does: every value deleted, and "Data has been reset" answered as the value.
class AndroidSecureStorage {
  final values = <String, String>{};
  final calls = <(String, String?, String?)>[];
  bool faultOnResetCall = false;

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final key = args['key'] as String?;
    final reset = (args['options'] as Map?)?['resetOnError'] as String?;
    calls.add((call.method, key, reset));
    if (reset == 'true' && faultOnResetCall) {
      faultOnResetCall = false;
      values.clear(); // FlutterSecureStoragePlugin.java:276-278 / FlutterSecureStorage.java:1061-1062
      return 'Data has been reset';
    }
    switch (call.method) {
      case 'read':
        return values[key];
      case 'write':
        values[key!] = args['value'] as String;
        return null;
      case 'delete':
        values.remove(key);
        return null;
      case 'deleteAll':
        values.clear();
        return null;
      case 'containsKey':
        return values.containsKey(key);
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AndroidSecureStorage storage;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('r10a_legacy');
    storage = AndroidSecureStorage();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(unlockChannel, FakeUnlockKey().handle);
    messenger.setMockMethodCallHandler(secureStorage, storage.handle);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(unlockChannel, null);
    messenger.setMockMethodCallHandler(secureStorage, null);
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  EncryptedFileVault vault() => EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('android'), folder: () async => dir);

  test('R10A-01: an ordinary Android opening never asks flutter_secure_storage with resetOnError true', () async {
    await vault().save(AppData()..lastNote = 'mine');
    storage.calls.clear();
    expect((await vault().load()).lastNote, 'mine');
    final risky = [for (final c in storage.calls) if (c.$3 == 'true') '${c.$1} ${c.$2}'];
    expect(risky, isEmpty,
        reason: 'each of these calls, on any Keystore fault, makes the plugin delete every value, the wrapped data '
            'key included: $risky');
  });

  test('R10A-01: one Keystore fault on that call does not cost the data key (stand-in for the plugin)', () async {
    await vault().save(AppData()..lastNote = 'mine');
    expect(storage.values[keyName], isNotNull);
    storage.faultOnResetCall = true; // a single transient fault, on the legacy option set's call
    final first = await vault().load();
    expect(first.lastNote, 'mine', reason: 'this opening works: the key was read just before and is held in memory');
    final kept = storage.values.containsKey(keyName);
    Object? next; // the next opening
    try {
      next = (await vault().load()).lastNote;
    } catch (e) {
      next = e;
    }
    expect((kept, next), (true, 'mine'),
        reason: 'the working data key was deleted by the one fault (left in the store: ${storage.values.keys.toList()}), '
            'and the next opening says: $next');
  });

  test('control: the main option set is resetOnError false, as F-02 asked', () async {
    await vault().save(AppData()..lastNote = 'mine');
    final writes = [for (final c in storage.calls) if (c.$1 == 'write') c.$3];
    expect(writes, everyElement('false'));
    expect(storage.values.keys, contains(keyName));
  });
}
