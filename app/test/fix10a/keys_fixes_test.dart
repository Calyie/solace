// Round 10 review A fixes for the data key (beyond the reviewer's proof tests in test/review10a/):
//   R10A-01: no flutter_secure_storage call on any device ever carries resetOnError true, and a read that fails on
//            Android is an error to try again, never a missing key, and deletes nothing.
//   R10A-02: a data key missing over data that its previous key opens is put back (any device), and only then.
//   R10A-03: a previous key that could not be read is never "none": the opening says try again rather than
//            "unreadable", and a renewal never writes over it.
//   R10A-04: a Keystore call that is never answered ends within the time limit: nothing kept, nothing set aside.
// Every test drives the app's real PlatformKeyStore, UnlockWrappedKeyStore and EncryptedFileVault; only the platform
// channels are stand-ins.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/unlock_key.dart';

import '../unlocked_only_key_test.dart' show FakeAndroidStorage, FakeIosKeychain, FakeUnlockKey, filesIn, freshKey;

const keyName = EncryptedFileVault.keyName;
const previousName = '$keyName.previous';
const secureStorage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const unlockChannel = MethodChannel('app.personal.solace/unlock_key');

TestDefaultBinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// flutter_secure_storage as a plain map that records every call's resetOnError, and can be made to fail reads.
class RecordingStorage extends FakeAndroidStorage {
  final resetOnError = <String?>[];
  bool failReads = false;
  @override
  Future<Object?> handle(MethodCall call) {
    final args = (call.arguments as Map).cast<String, Object?>();
    resetOnError.add((args['options'] as Map?)?['resetOnError'] as String?);
    if (failReads && call.method == 'read') throw PlatformException(code: 'Exception encountered', message: 'read');
    return super.handle(call);
  }
}

/// UnlockKey.kt as Dart sees it, with one 'failed' answer on the [failAt]-th unwrap from now.
class FlakyUnlockKey extends FakeUnlockKey {
  int? failAt;
  int _seen = 0;
  void failOnUnwrap(int n) {
    failAt = n;
    _seen = 0;
  }

  @override
  Future<Object?> handle(MethodCall call) {
    if (call.method == 'unwrap' && failAt != null && ++_seen == failAt) {
      failAt = null;
      throw PlatformException(code: 'failed');
    }
    return super.handle(call);
  }
}

/// [text] sealed as the store seals its file, under [key] (base64).
Future<List<int>> sealed(String text, String key) async =>
    (await AesGcm.with256bits().encrypt(utf8.encode(text), secretKey: SecretKey(base64Decode(key)))).concatenation();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fix10a_keys'));
  tearDown(() {
    messenger.setMockMethodCallHandler(unlockChannel, null);
    messenger.setMockMethodCallHandler(secureStorage, null);
    debugDefaultTargetPlatformOverride = null;
    EncryptedFileVault.debugBeforeReadBack = null;
    UnlockKeyChannel.timeLimit = const Duration(seconds: 10);
    dir.deleteSync(recursive: true);
  });

  EncryptedFileVault vaultFor(String os) =>
      EncryptedFileVault(keychain: PlatformKeyStore.forPlatform(os), folder: () async => dir);

  group('R10A-01: no read deletes anything', () {
    for (final os in ['android', 'ios', 'macos', 'linux']) {
      test('$os: no call carries resetOnError true, through first save, opening, a key read from the older '
          'settings, renewal, Start fresh and Delete everything', () async {
        // the plugin sends the options of the platform it runs on
        debugDefaultTargetPlatformOverride = const {'android': TargetPlatform.android, 'ios': TargetPlatform.iOS,
            'macos': TargetPlatform.macOS, 'linux': TargetPlatform.linux}[os];
        final storage = os == 'ios' ? null : RecordingStorage();
        final keychain = os == 'ios' ? FakeIosKeychain() : null;
        final seen = <String?>[];
        messenger.setMockMethodCallHandler(secureStorage, (call) {
          seen.add((((call.arguments as Map)['options'] as Map?) ?? {})['resetOnError'] as String?);
          return storage != null ? storage.handle(call) : keychain!.handle(call);
        });
        messenger.setMockMethodCallHandler(unlockChannel, FakeUnlockKey().handle);
        final vault = vaultFor(os);
        await vault.save(AppData()..lastNote = 'mine');
        expect((await vaultFor(os).load()).lastNote, 'mine');
        await vault.rotateKey();
        expect((await vaultFor(os).load()).lastNote, 'mine');
        await vaultFor(os).setAside();
        await vaultFor(os).save(AppData()..lastNote = 'fresh');
        await vaultFor(os).wipe();
        expect(seen, isNotEmpty);
        expect(seen.where((r) => r == 'true'), isEmpty, reason: 'a call with resetOnError true deletes every value on '
            'any fault');
        if (os == 'android') expect(seen, everyElement('false'), reason: 'Android sends it with every call');
      });
    }

    test('Android: a read that fails is an error to try again, never a missing key, and every value stays', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final storage = RecordingStorage();
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
      messenger.setMockMethodCallHandler(unlockChannel, FakeUnlockKey().handle);
      await vaultFor('android').save(AppData()..lastNote = 'mine');
      final kept = Map.of(storage.values), files = filesIn(dir);
      storage.failReads = true;
      await expectLater(vaultFor('android').load(),
          throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'keychain')));
      await expectLater(vaultFor('android').setAside(),
          throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'keychain')));
      expect(storage.values, kept);
      expect(filesIn(dir).keys, files.keys, reason: 'nothing set aside');
      storage.failReads = false;
      expect((await vaultFor('android').load()).lastNote, 'mine');
    });
  });

  group('R10A-02: a data key lost in a renewal is put back from the previous key', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('Android: the data key missing, the previous key opens the data: put back, the data opens, renewal '
        'finished', () async {
      final storage = FakeAndroidStorage();
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
      messenger.setMockMethodCallHandler(unlockChannel, FakeUnlockKey().handle);
      await vaultFor('android').save(AppData()..lastNote = 'mine');
      // as a renewal cut short where the data key's name was lost: the working key only under the previous name
      storage.values[previousName] = storage.values.remove(keyName)!;
      final vault = vaultFor('android');
      expect((await vault.load()).lastNote, 'mine');
      expect(storage.values.containsKey(keyName), isTrue, reason: 'kept under its own name again');
      await vault.rotateKey(); // waits behind the re-seal the opening queued
      expect(storage.values.containsKey(previousName), isFalse, reason: 'the renewal finished');
      expect((await vaultFor('android').load()).lastNote, 'mine');
    });

    test('the previous key opens neither file: still key_missing, and nothing is written', () async {
      final storage = FakeAndroidStorage();
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
      messenger.setMockMethodCallHandler(unlockChannel, FakeUnlockKey().handle);
      await vaultFor('android').save(AppData()..lastNote = 'mine');
      storage.values.remove(keyName);
      await PlatformKeyStore.forPlatform('android').write(previousName, freshKey()); // some other key
      final kept = Map.of(storage.values), files = filesIn(dir);
      await expectLater(vaultFor('android').load(),
          throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'key_missing')));
      expect(storage.values, kept);
      expect(filesIn(dir), files);
    });

    test('iPhone: locked while the previous key is read: "locked", nothing written, then opens once unlocked',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final keychain = FakeIosKeychain();
      messenger.setMockMethodCallHandler(secureStorage, keychain.handle);
      await vaultFor('ios').save(AppData()..lastNote = 'mine');
      final item = keychain.items.remove(keyName)!;
      keychain.items[previousName] = item;
      keychain.locked = true;
      await expectLater(vaultFor('ios').load(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'locked')));
      expect(keychain.items.containsKey(keyName), isFalse, reason: 'nothing written while locked');
      keychain.locked = false;
      final vault = vaultFor('ios');
      expect((await vault.load()).lastNote, 'mine');
      expect(keychain.items[keyName]?.value, item.value);
      await vault.inKeyQueue(() async {}); // the renewal it finishes, before the channel stand-in goes
      expect(keychain.items.containsKey(previousName), isFalse);
    });
  });

  group('R10A-03: a previous key not read just now is never "none"', () {
    late FlakyUnlockKey unlock;
    late FakeAndroidStorage storage;
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      unlock = FlakyUnlockKey();
      storage = FakeAndroidStorage();
      messenger.setMockMethodCallHandler(unlockChannel, unlock.handle);
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
    });

    /// A renewal cut short before the store was sealed again: the store under key 1 (the previous key), key 2 kept.
    Future<(String, String)> storeUnderPrevious() async {
      final k1 = freshKey(), k2 = freshKey();
      final keys = PlatformKeyStore.forPlatform('android');
      await keys.write(keyName, k2);
      await keys.write(previousName, k1);
      File('${dir.path}/data_v1.bin')
          .writeAsBytesSync(await sealed(jsonEncode((AppData()..lastNote = 'mine').toJson()), k1));
      return (k1, k2);
    }

    test('the store needs it and it fails once: "try again" (keychain), never "unreadable"; nothing changed', () async {
      await storeUnderPrevious();
      final kept = Map.of(storage.values), files = filesIn(dir);
      unlock.failOnUnwrap(2); // unwrap 1 is the data key, unwrap 2 the previous key
      await expectLater(vaultFor('android').load(),
          throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'keychain')));
      expect(storage.values, kept);
      expect(filesIn(dir), files);
      final vault = vaultFor('android');
      expect((await vault.load()).lastNote, 'mine', reason: 'it opens at the next try');
      await vault.inKeyQueue(() async {}); // the renewal it finishes, before the channel stand-in goes
    });

    test('a renewal never writes over a previous key it could not read', () async {
      final (k1, _) = await storeUnderPrevious();
      final vault = vaultFor('android');
      expect((await vault.load()).lastNote, 'mine'); // opens with key 1; the re-seal is queued
      await vault.rotateKey(); // the earlier renewal is finished first, then a new key
      final kept = Map.of(storage.values);
      // a second renewal in the session, with the previous name now holding a key again and its read failing
      await PlatformKeyStore.forPlatform('android').write(previousName, k1);
      unlock.failOnUnwrap(1);
      await expectLater(vault.rotateKey(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'keychain')));
      expect(storage.values[keyName], kept[keyName], reason: 'nothing renewed');
      expect(await PlatformKeyStore.forPlatform('android').read(previousName), k1, reason: 'never written over');
    });
  });

  group('R10A-04: a Keystore call that is never answered', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      UnlockKeyChannel.timeLimit = const Duration(milliseconds: 300); // the limit itself: 10 s
    });

    test('the first save: a keychain error within the limit, nothing kept, no data file', () async {
      final storage = FakeAndroidStorage();
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
      messenger.setMockMethodCallHandler(unlockChannel, (call) => Completer<Object?>().future);
      final watch = Stopwatch()..start();
      await expectLater(vaultFor('android').save(AppData()..lastNote = 'mine'),
          throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'keychain')));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(storage.values, isEmpty);
      expect(File('${dir.path}/data_v1.bin').existsSync(), isFalse);
    });

    test('an opening: "try again" (keychain), never a missing key; nothing set aside or deleted', () async {
      final storage = FakeAndroidStorage();
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
      messenger.setMockMethodCallHandler(unlockChannel, FakeUnlockKey().handle);
      await vaultFor('android').save(AppData()..lastNote = 'mine');
      final kept = Map.of(storage.values), files = filesIn(dir);
      messenger.setMockMethodCallHandler(unlockChannel, (call) => Completer<Object?>().future);
      await expectLater(vaultFor('android').load(),
          throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'keychain')));
      expect(storage.values, kept);
      expect(filesIn(dir), files);
    });

    test('the limit in force is bounded', () {
      UnlockKeyChannel.timeLimit = const Duration(seconds: 10);
      expect(UnlockKeyChannel.timeLimit, greaterThan(const Duration(seconds: 2)), reason: 'room for a slow StrongBox');
      expect(UnlockKeyChannel.timeLimit, lessThanOrEqualTo(const Duration(seconds: 15)));
    });
  });
}
