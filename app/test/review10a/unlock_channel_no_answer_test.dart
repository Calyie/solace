// Review round 10 A, R10A-04 (C-08, Android): a Keystore call that never answers keeps Solace from starting, with no
// recovery screen and no crisis numbers.
//
// UnlockKey.kt (register, lines 56-68) runs each call on a single worker thread inside
// `try { ... } catch (e: Refusal) { ... } catch (e: Exception) { ... }` and answers from main.post after it. A
// java.lang.Error is not an Exception: one thrown by Keystore framework code (flutter_secure_storage documents OEM
// builds throwing NoSuchFieldError from Keystore code and catches Throwable for that reason,
// FlutterSecureStoragePlugin.java:293-306) escapes the Runnable, so main.post never runs and the call is never
// answered; on Android an uncaught throwable on any thread also ends the process. Either way the Dart side cannot
// recover: UnlockKeyChannel.unwrap (core/unlock_key.dart:70-77) awaits invokeMethod with no time bound, and boot
// (main.dart) awaits vault.load() before it shows anything, so neither the app nor the recovery screen (the one with
// the crisis numbers, F-02) ever appears. Owner rule: never crash or freeze.
//
// The test stands in a native side that never answers and asserts the SAFE behaviour (boot shows some screen within a
// few seconds), so it fails on 2f3ce71.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/unlock_key.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/recovery.dart';

import '../review_c1_flows_test.dart' as c1;
import '../unlocked_only_key_test.dart' show FakeAndroidStorage, FakeUnlockKey;

const secureStorage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const unlockChannel = MethodChannel('app.personal.solace/unlock_key');

TestDefaultBinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeAndroidStorage storage;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('r10a_no_answer');
    storage = FakeAndroidStorage();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(secureStorage, storage.handle);
    messenger.setMockMethodCallHandler(unlockChannel, FakeUnlockKey().handle);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(unlockChannel, null);
    messenger.setMockMethodCallHandler(secureStorage, null);
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  EncryptedFileVault vault() => EncryptedFileVault(keychain: PlatformKeyStore.forPlatform('android'), folder: () async => dir);

  test('R10A-04: a Keystore call that is never answered still ends in a screen (app or recovery)', () async {
    await vault().save(AppData()..lastNote = 'mine'); // the data key kept wrapped
    // the native side: the worker's Runnable died on an Error, so this call is never answered
    messenger.setMockMethodCallHandler(unlockChannel, (call) => Completer<Object?>().future);
    final shown = <Widget>[];
    unawaited(boot(c1.prompts, c1.library, vault(), oneCopyChecked: true, run: shown.add, os: 'android'));
    // Fix round (R10A-04): the wait was 5 s; the fix puts a time limit of UnlockKeyChannel.timeLimit (10 s, as the
    // review's own fix direction suggested 15 s) on each Keystore call, so the test waits a little past that limit,
    // and checks the screen is the recovery screen (which keeps the support numbers), with a keychain error.
    expect(UnlockKeyChannel.timeLimit, lessThanOrEqualTo(const Duration(seconds: 15)));
    await Future<void>.delayed(UnlockKeyChannel.timeLimit + const Duration(seconds: 3));
    expect(shown, isNotEmpty,
        reason: 'nothing is shown: boot is still waiting on vault.load(), which waits on the unwrap');
    final recovery = shown.single;
    expect(recovery, isA<RecoveryApp>());
    expect(((recovery as RecoveryApp).error as VaultError).kind, 'keychain');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('control: an answered Keystore call boots as usual', () async {
    await vault().save(AppData()..lastNote = 'mine');
    final shown = <Widget>[];
    await tester(boot(c1.prompts, c1.library, vault(), oneCopyChecked: true, run: shown.add, os: 'android'));
    expect(shown, isNotEmpty);
  });
}

/// Runs [f], quietly bounded (the control's boot also starts background work that needs no waiting for).
Future<void> tester(Future<void> f) => f.timeout(const Duration(seconds: 20), onTimeout: () {});
