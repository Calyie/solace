// Review round 10 A, R10A-02 (C-08, iPhone): a key renewal cut short by the phone locking deletes the data key.
//
// C-08 moved the iPhone's data key to the keychain class "when unlocked, this device only". flutter_secure_storage_darwin
// 0.4.3 writes over an existing item with SecItemUpdate and, when that fails FOR ANY REASON, deletes the item and adds
// it again (FlutterSecureStorage.swift:680-698). While the phone is locked, an update of a "when unlocked" item fails
// (errSecInteractionNotAllowed), the delete goes through, and the add is refused: the item is gone. Before C-08 the
// class was "after first unlock", whose items stay writable while locked, so this could not happen.
//
// EncryptedFileVault._rotate (Settings > renew the key, store.dart:1047-1077) writes the old key under `.previous`,
// reads it back, then writes the new key OVER `solace_data_key_v1`. If the phone's data protection locks between those
// two steps (the side button pressed just after confirming, or auto-lock), the write over the data key deletes it and
// throws KeyStoreLocked out of _rotate. The running copy keeps the old key in memory and goes on saving under it. At
// the next opening `solace_data_key_v1` is missing, the data file exists, and _loadKey (store.dart:833-837) gives
// 'key_missing' ("its key is not in the device keychain") with Start fresh, although the working key is sitting in
// the keychain under `.previous`: _loadKey never looks there.
//
// FakeIosKeychain (from the C-08 test) models the darwin plugin, update-fails-then-delete included; this test only
// locks it at one moment. Caveat (needs an iPhone to settle): the plugin reaches the update-then-delete only when its
// containsKey (an attributes-only SecItemCopyMatching) still finds the item while the phone is locked, as the C-08
// model assumes; if iOS refuses that query too, keyExists is false, the add fails and the item survives. Either way
// _loadKey ignoring a working key under `.previous` is in the code. The test asserts the SAFE behaviour (the data still
// opens), so it fails on 2f3ce71.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

import '../unlocked_only_key_test.dart' show FakeIosKeychain, freshKey;

const keyName = EncryptedFileVault.keyName;
const secureStorage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

TestDefaultBinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// The iPhone keychain, which locks (data protection) just as the new key is written over the old one, once the old
/// key has been kept under `.previous`.
class LocksBeforeNewKey extends FakeIosKeychain {
  bool armed = false;
  @override
  Future<Object?> handle(MethodCall call) {
    final args = (call.arguments as Map).cast<String, Object?>();
    if (armed && call.method == 'write' && args['key'] == keyName && items.containsKey('$keyName.previous')) {
      armed = false;
      locked = true;
    }
    return super.handle(call);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocksBeforeNewKey keychain;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('r10a_ios_renew');
    keychain = LocksBeforeNewKey();
    messenger.setMockMethodCallHandler(secureStorage, keychain.handle);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(secureStorage, null);
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  EncryptedFileVault vault() => EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('ios'), folder: () async => dir);

  test('R10A-02: the phone locking during a key renewal never leaves the data without its key', () async {
    final running = vault();
    await running.save(AppData()..lastNote = 'mine');
    await running.load();
    final key = keychain.items[keyName]!.value;
    keychain.armed = true;
    Object? renewal;
    try {
      await running.rotateKey();
    } catch (e) {
      renewal = e;
    }
    expect(renewal, isA<KeyStoreLocked>(), reason: 'precondition: the renewal was cut short by the lock');
    await running.save(AppData()..lastNote = 'saved after, while locked'); // the key held in memory
    keychain.locked = false; // unlocked again; Solace is opened later
    expect(keychain.items['$keyName.previous']?.value, key, reason: 'the working key is still in the keychain');
    Object? next;
    final reopened = vault();
    try {
      next = (await reopened.load()).lastNote;
    } catch (e) {
      next = e;
    }
    // fix round: the opening queues the end of the renewal; it is let finish before the channel stand-in goes, so it
    // never reaches the next test's keychain
    await reopened.inKeyQueue(() async {});
    expect(next, 'saved after, while locked',
        reason: 'solace_data_key_v1 was deleted by the write the lock refused (present now: '
            '${keychain.items.containsKey(keyName)}); the working key is under .previous, but the opening says: $next');
  });

  test('control: the same renewal with the phone unlocked throughout works', () async {
    final running = vault();
    await running.save(AppData()..lastNote = 'mine');
    await running.load();
    final before = keychain.items[keyName]!.value;
    await running.rotateKey();
    expect(keychain.items[keyName]!.value, isNot(before));
    expect(keychain.items.containsKey('$keyName.previous'), isFalse);
    expect((await vault().load()).lastNote, 'mine');
    expect(freshKey(), isNotEmpty);
  });
}
