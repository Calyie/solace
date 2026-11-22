// Round 5 review, C-08: on the phones the data key can be read only while the phone is unlocked, and a running Solace
// keeps working while it is locked.
//   - iPhone: the key is kept "when unlocked, this device only"; a key kept by an earlier build ("after first unlock")
//     is moved into that class, through flutter_secure_storage as its darwin plugin (0.4.3) really behaves.
//   - Android: the key is kept in flutter_secure_storage only wrapped by a Keystore key that works only while the phone
//     is unlocked (core/unlock_key.dart; native side UnlockKey.kt, stood in for here); a plain key from an earlier
//     build is wrapped, checked and only then replaced; a phone that cannot keep such a key (Android 8.1 and below)
//     keeps it as before.
//   - A locked phone gives VaultError 'locked' ("Unlock your phone with its PIN, pattern or password, then open Solace again."), and never a reset: no
//     new key, nothing set aside, nothing deleted, no Start fresh.
//   - Saves, pictures and a key renewal while locked: saves and pictures use the key held in memory; nothing reads the
//     key store again.
// Every test drives the app's real code (PlatformKeyStore, UnlockWrappedKeyStore, EncryptedFileVault, boot and the
// recovery screen); only the platform channels are stand-ins.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/unlock_key.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/recovery.dart';

import 'review_c1_flows_test.dart' as c1;

const keyName = EncryptedFileVault.keyName;
const secureStorage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const unlockChannel = MethodChannel('app.personal.solace/unlock_key');

TestDefaultBinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

PlatformException lockedKeychain() => PlatformException(code: 'Unexpected security result code',
    message: 'Code: -25308, Message: User interaction is not allowed.', details: -25308);

/// The iPhone keychain as flutter_secure_storage_darwin 0.4.3 handles it (FlutterSecureStorage.swift): one item per
/// name whatever its class; a read finds it in any class; a write over an item of the same class updates it, and over
/// an item of another class fails to update (the query names the new class), deletes it and adds it again with the new
/// class; an update that fails for any other reason also deletes the item before the add. While the phone is locked, a
/// "when unlocked" item cannot be read or added (errSecInteractionNotAllowed), while an "after first unlock" one still
/// can be read.
class FakeIosKeychain {
  final items = <String, ({String value, String cls})>{};
  bool locked = false;
  final classesAskedFor = <String>{};
  static const whenUnlocked = {'unlocked', 'unlocked_this_device', 'passcode'};

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final cls = (args['options'] as Map)['accessibility'] as String? ?? 'unlocked';
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        final it = items[key];
        if (it == null) return null;
        if (locked && whenUnlocked.contains(it.cls)) throw lockedKeychain();
        return it.value;
      case 'write':
        classesAskedFor.add(cls);
        final value = args['value'] as String, it = items[key];
        final refused = locked && whenUnlocked.contains(cls);
        if (it != null) {
          if (it.cls == cls && !refused) {
            items[key!] = (value: value, cls: cls);
            return null;
          }
          items.remove(key); // the plugin deletes it when the update fails
        }
        if (refused) throw lockedKeychain();
        items[key!] = (value: value, cls: cls);
        return null;
      case 'delete':
        items.remove(key);
        return null;
      case 'deleteAll':
        items.clear();
        return null;
      case 'containsKey':
        return items.containsKey(key);
    }
    return null;
  }
}

/// flutter_secure_storage on Android: a plain map of names to values (its own encryption is not the point here).
class FakeAndroidStorage {
  final values = <String, String>{};
  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final key = args['key'] as String?;
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

/// UnlockKey.kt as seen from Dart: AES-256-GCM under one key, IV (12) + ciphertext + tag (16); `locked` while the
/// phone is locked, `unavailable` where the phone cannot keep such a key (Android 8.1 and below, no screen lock), `gone`
/// once the key is no longer in the Keystore or the value is not one it wrapped.
class FakeUnlockKey {
  SecretKey _key = SecretKey(List.generate(32, (i) => i));
  bool locked = false, unavailable = false, present = false;
  int wraps = 0, unwraps = 0, forgets = 0;

  /// The Keystore lost the key (a screen lock removed on some Android versions, a Keystore reset).
  void lose() {
    present = false;
    _key = SecretKey(List.generate(32, (_) => Random.secure().nextInt(256)));
  }

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'wrap':
        if (unavailable) throw PlatformException(code: 'unavailable');
        if (locked) throw PlatformException(code: 'locked');
        wraps++;
        present = true;
        final box = await AesGcm.with256bits().encrypt(call.arguments as Uint8List, secretKey: _key);
        return Uint8List.fromList(box.concatenation());
      case 'unwrap':
        if (locked) throw PlatformException(code: 'locked');
        if (!present) throw PlatformException(code: 'gone');
        unwraps++;
        try {
          final box = SecretBox.fromConcatenation(call.arguments as Uint8List, nonceLength: 12, macLength: 16);
          return Uint8List.fromList(await AesGcm.with256bits().decrypt(box, secretKey: _key));
        } on SecretBoxAuthenticationError {
          throw PlatformException(code: 'gone');
        }
      case 'forget':
        forgets++;
        lose();
        return null;
    }
    throw MissingPluginException();
  }
}

/// A key store stand-in (flutter_secure_storage's values) that can be made to fail on any use.
class MemKeys implements KeyStore {
  final values = <String, String>{};
  bool refuse = false;
  int uses = 0;
  void _use() {
    uses++;
    if (refuse) throw StateError('the key store was used');
  }

  @override
  Future<String?> read(String name) async {
    _use();
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    _use();
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    _use();
    values.remove(name);
  }

  @override
  Future<void> deleteAll() async {
    _use();
    values.clear();
  }
}

String freshKey() => base64Encode(List.generate(32, (_) => Random.secure().nextInt(256)));

/// The files the store keeps in [dir], with their bytes, to show nothing was changed, moved or set aside.
Map<String, List<int>> filesIn(Directory dir) => {
      for (final f in dir.listSync(recursive: true).whereType<File>()) f.path.substring(dir.path.length): f.readAsBytesSync(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeUnlockKey unlock;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('c08');
    unlock = FakeUnlockKey();
    messenger.setMockMethodCallHandler(unlockChannel, unlock.handle);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(unlockChannel, null);
    messenger.setMockMethodCallHandler(secureStorage, null);
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  group('iPhone: "when unlocked, this device only"', () {
    late FakeIosKeychain keychain;
    setUp(() {
      keychain = FakeIosKeychain();
      messenger.setMockMethodCallHandler(secureStorage, keychain.handle);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test('a new key is kept in the unlocked-only class', () async {
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir);
      await vault.save(AppData()..lastNote = 'mine');
      expect(keychain.items[keyName]?.cls, 'unlocked_this_device');
      expect(keychain.classesAskedFor, {'unlocked_this_device'}, reason: 'no write ever asks for another class');
    });

    test('a key kept "after first unlock" by the earlier build is moved into the unlocked-only class, value kept',
        () async {
      // what the build before C-08 left: the key, and the mark of its earlier move, in "after first unlock"
      final key = freshKey();
      await EncryptedFileVault(keychain: PlatformKeyStore.over(MemKeys()..values[keyName] = key, MemKeys(),
          moveClass: false), folder: () async => dir).save(AppData()..lastNote = 'from the older build');
      keychain.items[keyName] = (value: key, cls: 'first_unlock_this_device');
      keychain.items['$keyName.class'] = (value: 'this-device', cls: 'first_unlock_this_device');
      final back = await EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir).load();
      expect(back.lastNote, 'from the older build');
      expect(keychain.items[keyName], (value: key, cls: 'unlocked_this_device'));
      expect(keychain.items['$keyName.class'], (value: PlatformKeyStore.classMark, cls: 'unlocked_this_device'));
      expect(keychain.items.containsKey('$keyName.moving'), isFalse, reason: 'the temporary copy is gone');
    });

    test('the previous key (a renewal not yet finished) is moved too', () async {
      final key = freshKey(), previous = freshKey();
      keychain.items[keyName] = (value: key, cls: 'first_unlock_this_device');
      keychain.items['$keyName.previous'] = (value: previous, cls: 'first_unlock_this_device');
      final keys = PlatformKeyStore.forPlatform('ios');
      expect(await keys.read(keyName), key);
      expect(await keys.read('$keyName.previous'), previous);
      expect(keychain.items['$keyName.previous']?.cls, 'unlocked_this_device');
      expect(keychain.items['$keyName.previous.class']?.value, PlatformKeyStore.classMark);
    });

    test('the phone locked while the old key is moved: the data opens, the key stays, the move finishes later',
        () async {
      final key = freshKey();
      await EncryptedFileVault(keychain: PlatformKeyStore.over(MemKeys()..values[keyName] = key, MemKeys(),
          moveClass: false), folder: () async => dir).save(AppData()..lastNote = 'kept');
      keychain.items[keyName] = (value: key, cls: 'first_unlock_this_device');
      keychain.locked = true; // still readable "after first unlock"; the new class cannot be written now
      final back = await EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir).load();
      expect(back.lastNote, 'kept');
      expect(keychain.items[keyName], (value: key, cls: 'first_unlock_this_device'), reason: 'never missing');
      keychain.locked = false;
      expect(await PlatformKeyStore.forPlatform('ios').read(keyName), key);
      expect(keychain.items[keyName]?.cls, 'unlocked_this_device');
    });

    test('a locked phone gives "locked", never a missing key: no new key, nothing set aside, nothing deleted',
        () async {
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir);
      await vault.save(AppData()..lastNote = 'mine');
      final kept = Map.of(keychain.items), files = filesIn(dir);
      keychain.locked = true;
      final next = EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir);
      await expectLater(next.load(), throwsA(isA<VaultError>()
          .having((e) => e.kind, 'kind', 'locked')
          .having((e) => e.message, 'message', 'Unlock your phone with its PIN, pattern or password, then open Solace again.')));
      // Start fresh is refused too, before anything moves (the recovery screen does not offer it)
      await expectLater(next.setAside(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'locked')));
      expect(keychain.items, kept);
      expect(filesIn(dir).keys, files.keys);
      for (final f in files.entries) {
        expect(filesIn(dir)[f.key], f.value, reason: f.key);
      }
      keychain.locked = false;
      expect((await next.load()).lastNote, 'mine', reason: 'once unlocked, the same store opens with the same key');
    });

    test('saves and pictures while the phone is locked use the key held in memory', () async {
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir);
      await vault.save(AppData()..lastNote = 'before');
      await vault.load();
      keychain.locked = true;
      await vault.save(AppData()..lastNote = 'while locked');
      final id = await vault.putMedia(Uint8List.fromList(List.filled(500, 9)));
      expect(await vault.getMedia(id), hasLength(500));
      keychain.locked = false;
      expect((await EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir).load())
          .lastNote, 'while locked');
    });
  });

  group('Android: the data key kept wrapped by an unlocked-only Keystore key', () {
    test('round trip: what is kept is wrapped, what is read is the key', () async {
      final inner = MemKeys(), keys = UnlockWrappedKeyStore(inner, const UnlockKeyChannel());
      final key = freshKey();
      await keys.write(keyName, key);
      expect(inner.values[keyName], startsWith(UnlockKeyChannel.tag));
      expect(inner.values[keyName], isNot(contains(key)));
      expect(await keys.read(keyName), key);
      expect(unlock.wraps, 1);
    });

    test('a plain key from the earlier build is wrapped, checked, rewritten, and the data still opens', () async {
      final inner = MemKeys(), key = freshKey();
      inner.values[keyName] = key; // what the build before C-08 kept
      await EncryptedFileVault(keychain: MemKeys()..values[keyName] = key, folder: () async => dir)
          .save(AppData()..lastNote = 'from the older build');
      final keys = PlatformKeyStore.over(UnlockWrappedKeyStore(inner, const UnlockKeyChannel()), MemKeys(),
          moveClass: false);
      final back = await EncryptedFileVault(keychain: keys, folder: () async => dir).load();
      expect(back.lastNote, 'from the older build');
      final stored = inner.values[keyName]!;
      expect(stored, startsWith(UnlockKeyChannel.tag), reason: 'the plain form is gone');
      expect(await const UnlockKeyChannel().unwrap(stored), key);
      expect(unlock.unwraps, greaterThanOrEqualTo(2), reason: 'opened in memory before, and after it was written');
    });

    test('the migration never loses the key: a write that does not stick puts the plain form back', () async {
      final key = freshKey();
      final inner = _ForgetfulKeys()..values[keyName] = key;
      final keys = UnlockWrappedKeyStore(inner, const UnlockKeyChannel());
      expect(await keys.read(keyName), key);
      expect(inner.values[keyName], key, reason: 'the wrapped form did not read back, so the plain form is back');
    });

    test('the phone locked during the migration: the plain key opens the data and stays until the next try',
        () async {
      final inner = MemKeys(), key = freshKey();
      inner.values[keyName] = key;
      unlock.locked = true;
      final keys = UnlockWrappedKeyStore(inner, const UnlockKeyChannel());
      expect(await keys.read(keyName), key);
      expect(inner.values[keyName], key);
      unlock.locked = false;
      expect(await keys.read(keyName), key);
      expect(inner.values[keyName], startsWith(UnlockKeyChannel.tag));
    });

    test('a locked phone gives "locked", never a missing key: no new key, nothing set aside, nothing deleted',
        () async {
      final inner = MemKeys();
      PlatformKeyStore keys() => PlatformKeyStore.over(UnlockWrappedKeyStore(inner, const UnlockKeyChannel()),
          MemKeys(), moveClass: false);
      await EncryptedFileVault(keychain: keys(), folder: () async => dir).save(AppData()..lastNote = 'mine');
      final kept = Map.of(inner.values), files = filesIn(dir);
      unlock.locked = true;
      final next = EncryptedFileVault(keychain: keys(), folder: () async => dir);
      await expectLater(next.load(), throwsA(isA<VaultError>()
          .having((e) => e.kind, 'kind', 'locked')
          .having((e) => e.message, 'message', 'Unlock your phone with its PIN, pattern or password, then open Solace again.')));
      await expectLater(next.setAside(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'locked')));
      await expectLater(next.rotateKey(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'locked')));
      expect(inner.values, kept);
      expect(filesIn(dir).keys, files.keys);
      unlock.locked = false;
      expect((await next.load()).lastNote, 'mine');
    });

    test('a first save after Delete everything while the phone is locked waits: no key is kept unwrapped', () async {
      final inner = MemKeys();
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.over(
          UnlockWrappedKeyStore(inner, const UnlockKeyChannel()), MemKeys(), moveClass: false), folder: () async => dir);
      unlock.locked = true;
      await expectLater(vault.save(AppData()..lastNote = 'x'),
          throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'locked')));
      expect(inner.values, isEmpty);
    });

    test('saves, pictures and a reload while the phone is locked never touch the key store', () async {
      final inner = MemKeys();
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.over(
          UnlockWrappedKeyStore(inner, const UnlockKeyChannel()), MemKeys(), moveClass: false), folder: () async => dir);
      await vault.save(AppData()..lastNote = 'before');
      await vault.load();
      unlock.locked = true;
      inner.refuse = true; // any use of the key store now fails the test's save
      await vault.save(AppData()..lastNote = 'while locked');
      final id = await vault.putMedia(Uint8List.fromList(List.filled(500, 9)));
      expect(await vault.getMedia(id), hasLength(500));
      expect((await vault.load()).lastNote, 'while locked');
      inner.refuse = false;
      unlock.locked = false;
    });

    test('Android 8.1 and below (or no screen lock): the key is kept as before, and nothing is rewritten', () async {
      unlock.unavailable = true;
      final inner = MemKeys(), keys = UnlockWrappedKeyStore(inner, const UnlockKeyChannel());
      final key = freshKey();
      await keys.write(keyName, key);
      expect(inner.values[keyName], key);
      expect(await keys.read(keyName), key);
      expect(inner.values[keyName], key);
    });

    test('no native side at all (not Android): kept as before', () async {
      messenger.setMockMethodCallHandler(unlockChannel, null);
      final inner = MemKeys(), keys = UnlockWrappedKeyStore(inner, const UnlockKeyChannel());
      await keys.write(keyName, 'k');
      expect(inner.values[keyName], 'k');
      expect(await keys.read(keyName), 'k');
    });

    test('the Keystore lost its key: its own kind, and Start fresh sets the data and the wrapped key aside', () async {
      final inner = MemKeys();
      PlatformKeyStore keys() => PlatformKeyStore.over(UnlockWrappedKeyStore(inner, const UnlockKeyChannel()),
          MemKeys(), moveClass: false);
      await EncryptedFileVault(keychain: keys(), folder: () async => dir).save(AppData()..lastNote = 'mine');
      final wrapped = inner.values[keyName]!;
      unlock.lose();
      final next = EncryptedFileVault(keychain: keys(), folder: () async => dir);
      await expectLater(next.load(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'key_lost')));
      await next.setAside();
      expect(inner.values.containsKey(keyName), isFalse);
      expect(inner.values.entries.where((e) => e.key.startsWith('$keyName.unreadable-')).map((e) => e.value),
          [wrapped], reason: 'kept as it was, under a dated name');
      expect(dir.listSync().any((e) => e.path.contains('data_v1.bin.unreadable-')), isTrue);
      final fresh = EncryptedFileVault(keychain: keys(), folder: () async => dir);
      expect((await fresh.load()).lastNote, isNot('mine'));
      await fresh.save(AppData()..lastNote = 'new start');
      expect(inner.values[keyName], startsWith(UnlockKeyChannel.tag));
      expect((await EncryptedFileVault(keychain: keys(), folder: () async => dir).load()).lastNote, 'new start');
    });

    test('Delete everything removes every value, then the Keystore key', () async {
      final inner = MemKeys();
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.over(
          UnlockWrappedKeyStore(inner, const UnlockKeyChannel()), MemKeys(), moveClass: false), folder: () async => dir);
      await vault.save(AppData()..lastNote = 'mine');
      await vault.wipe();
      expect(inner.values, isEmpty);
      expect(unlock.forgets, greaterThanOrEqualTo(1));
    });

    test('the real Android wiring: flutter_secure_storage holds only the wrapped key', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final storage = FakeAndroidStorage();
      messenger.setMockMethodCallHandler(secureStorage, storage.handle);
      final key = freshKey();
      storage.values[keyName] = key; // the earlier build's plain key
      expect(await PlatformKeyStore.forPlatform('android').read(keyName), key);
      expect(storage.values[keyName], startsWith(UnlockKeyChannel.tag));
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('android'), folder: () async => dir);
      await vault.save(AppData()..lastNote = 'x');
      expect(storage.values.values.every((v) => v.startsWith(UnlockKeyChannel.tag)), isTrue);
    });

    test('wrapping is bounded: a value longer than a key is refused before the channel', () async {
      await expectLater(const UnlockKeyChannel().wrap('x' * (UnlockKeyChannel.maxValue + 1)), throwsArgumentError);
      await expectLater(const UnlockKeyChannel().unwrap('${UnlockKeyChannel.tag}${'A' * 20000}'),
          throwsA(isA<KeyWrapLost>()));
      expect(unlock.wraps + unlock.unwraps, 0);
    });
  });

  group('the recovery screen', () {
    testWidgets('locked: the plain message, Try again, no Start fresh; it tries again when Solace is back in front',
        (tester) async {
      var tries = 0;
      await tester.pumpWidget(RecoveryApp(error: lockedError, retry: () async => tries++, startFresh: () async {
        fail('Start fresh must never run for a locked phone');
      }));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unlock your phone with its PIN, pattern or password, then open Solace again.'), findsOneWidget);
      expect(find.textContaining('Nothing has been deleted.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Start fresh'), findsNothing);
      // the phone locked and unlocked again: Solace goes to the background and comes back in front
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
          AppLifecycleState.hidden, AppLifecycleState.inactive]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      expect(tries, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tries, 1);
    });

    testWidgets('boot on a locked iPhone shows that screen, and the store is untouched', (tester) async {
      final keychain = FakeIosKeychain();
      messenger.setMockMethodCallHandler(secureStorage, keychain.handle);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final shown = <Widget>[];
      try {
        await tester.runAsync(() async {
          await EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir)
              .save(AppData()..lastNote = 'mine');
          keychain.locked = true;
          await boot(c1.prompts, c1.library, EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'),
              folder: () async => dir), oneCopyChecked: true, run: shown.add, os: 'ios');
        });
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(shown.single, isA<RecoveryApp>());
      expect((shown.single as RecoveryApp).error, isA<VaultError>().having((e) => e.kind, 'kind', 'locked'));
      expect(keychain.items.containsKey(keyName), isTrue);
    });

    testWidgets('key lost on Android: Start fresh is offered, and the advice says why', (tester) async {
      await tester.pumpWidget(RecoveryApp(
          error: const VaultError('key_lost', 'Your saved data is here, but the key that opens it can no longer be '
              'opened on this phone.'),
          retry: () async {}, startFresh: () async {}));
      await tester.pumpAndSettle();
      expect(find.text('Start fresh'), findsOneWidget);
      expect(find.textContaining('transfer file'), findsOneWidget);
    });
  });
}

/// A key store whose writes do not stick (a store that answers but keeps the old value).
class _ForgetfulKeys extends MemKeys {
  @override
  Future<void> write(String name, String value) async {
    if (value.startsWith(UnlockKeyChannel.tag)) return;
    values[name] = value;
  }
}
