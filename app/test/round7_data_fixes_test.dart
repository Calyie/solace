// Round 7 review A fixes beyond the reviewer's own proofs (test/review7a/): G7-03 (a key renewal deletes the previous
// key only once every file was written again under the new key and read back, or proved to open with neither key: a
// case for each place it can fail), G7-05 (a staged key is deleted only when proved not to open), G7-01 (Delete
// everything removes every key file), G7-04 (an owed keyring delete survives "I have forgotten it"), G7-09 (the
// passphrase change runs in the store's queue), G7-06 (the app lock and the passcode wait are not fooled by the
// device clock), G7-07 (secret digit boxes reach the Linux input method as passwords), G7-02 (You tab changes say
// when they were not saved) and G7-08 (the bundle is checked and unpacked from one private copy).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/model_import.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/trusted.dart';
import 'package:solace/main.dart' show moveKeyringKey;
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/passphrase_screen.dart';
import 'package:solace/ui/premium.dart' show Haptics;
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/you.dart';

import 'app_flow_test.dart' as flow;
import 'vault_test.dart' show FakeKeyStore;

const quick = StretchSettings(memoryKib: 8192, iterations: 1);
const name = EncryptedFileVault.keyName;

Future<bool> opensWith(File f, String b64) async {
  try {
    await AesGcm.with256bits().decrypt(
        SecretBox.fromConcatenation(f.readAsBytesSync(), nonceLength: 12, macLength: 16),
        secretKey: SecretKey(base64Decode(b64)));
    return true;
  } catch (_) {
    return false;
  }
}

void chmod(String mode, String path) => Process.runSync('chmod', [mode, path]);

/// A vault whose saves fail once [failing] is set (a full disk), as round 6's tests use.
class _FailingVault extends MemoryVault {
  bool failing = false;
  @override
  Future<void> save(AppData data) async {
    if (failing) throw const FileSystemException('No space left on device', '', OSError('', 28));
    return super.save(data);
  }
}

class _Keys implements KeyStore {
  final values = <String, String>{};
  int failDeletes = 0;
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async => values[name] = value;
  @override
  Future<void> delete(String name) async {
    if (failDeletes > 0) {
      failDeletes--;
      throw const FileSystemException('keyring did not answer');
    }
    values.remove(name);
  }

  @override
  Future<void> deleteAll() async => values.clear();
}

/// The app lock's clocks, set by the test (G7-06).
class _Clock extends LockClock {
  DateTime wallNow = DateTime(2026, 11, 15, 12);
  Duration monoNow = const Duration(hours: 3);
  @override
  DateTime wall() => wallNow;
  @override
  Duration monotonic() => monoNow;
  void pass(Duration d, {Duration? wallMoves}) {
    monoNow += d;
    wallNow = wallNow.add(wallMoves ?? d);
  }
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  group('G7-03: a renewal never deletes the only key that opens the data', () {
    late Directory dir;
    late FakeKeyStore keys;
    late EncryptedFileVault vault;
    final picture = Uint8List.fromList(List.generate(300, (i) => i % 251));
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('r7_renew');
      keys = FakeKeyStore();
      vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    });
    tearDown(() async {
      EncryptedFileVault.debugBeforeReadBack = null;
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
      await dir.delete(recursive: true);
    });
    File main() => File('${dir.path}/data_v1.bin');

    Future<void> expectBothKeysAndOpens(String words, {String? pictureId}) async {
      expect(keys.values.containsKey('$name.previous'), isTrue, reason: 'the previous key is kept');
      final reopened = EncryptedFileVault(keychain: keys, folder: () async => dir);
      expect((await reopened.load()).homeworkDue, words, reason: 'the next start opens everything');
      // round 8: opening queues the re-seal the renewal left unfinished. Wait for the store's queue, so the picture is
      // read after that re-seal and the folder is deleted only once its writes are done (under load, tearDown once
      // deleted the folder while the re-seal was still writing: "Directory not empty")
      await reopened.inKeyQueue(() async {});
      if (pictureId != null) expect(await reopened.getMedia(pictureId), picture);
    }

    test('only the main file unreadable: it fails and keeps both keys, never putting the older last good copy over '
        'the newest save', () async {
      await vault.save(AppData()..homeworkDue = 'older');
      final olderBak = File('${dir.path}/data_v1.bin.bak').readAsBytesSync();
      await vault.save(AppData()..homeworkDue = 'newest');
      File('${dir.path}/data_v1.bin.bak').writeAsBytesSync(olderBak); // a save that stopped before its last good copy
      chmod('000', main().path);
      await expectLater(vault.rotateKey(), throwsA(isA<VaultError>()));
      chmod('600', main().path);
      await expectBothKeysAndOpens('newest');
    });

    test('the write under the new key fails: both keys kept', () async {
      await vault.save(AppData()..homeworkDue = 'kept');
      chmod('500', dir.path); // no new file can be made in the folder
      await expectLater(vault.rotateKey(), throwsA(anything));
      chmod('700', dir.path);
      await expectBothKeysAndOpens('kept');
    });

    test('the store written under the new key cannot be read back: both keys kept', () async {
      await vault.save(AppData()..homeworkDue = 'kept');
      EncryptedFileVault.debugBeforeReadBack = (f) async {
        if (f.path == main().path) chmod('000', f.path);
      };
      await expectLater(vault.rotateKey(), throwsA(anything));
      EncryptedFileVault.debugBeforeReadBack = null;
      chmod('600', main().path);
      await expectBothKeysAndOpens('kept');
    });

    test('a picture that cannot be read: both keys kept, the picture still opens', () async {
      await vault.save(AppData()..homeworkDue = 'kept');
      final id = await vault.putMedia(picture);
      final file = File('${dir.path}/media/$id.bin');
      chmod('000', file.path);
      await expectLater(vault.rotateKey(), throwsA(anything));
      chmod('600', file.path);
      await expectBothKeysAndOpens('kept', pictureId: id);
    });

    test('a picture written under the new key that cannot be read back: the picture stays as it was, its part file '
        'goes, both keys kept', () async {
      await vault.save(AppData()..homeworkDue = 'kept');
      final id = await vault.putMedia(picture);
      final before = File('${dir.path}/media/$id.bin').readAsBytesSync();
      EncryptedFileVault.debugBeforeReadBack = (f) async {
        if (f.path.endsWith('.part')) chmod('000', f.path);
      };
      await expectLater(vault.rotateKey(), throwsA(anything));
      EncryptedFileVault.debugBeforeReadBack = null;
      expect(File('${dir.path}/media/$id.bin').readAsBytesSync(), before);
      expect(Directory('${dir.path}/media').listSync().where((e) => e.path.endsWith('.part')), isEmpty);
      await expectBothKeysAndOpens('kept', pictureId: id);
    });

    test('the re-seal the next opening queues, with the store unreadable then, keeps both keys too', () async {
      await vault.save(AppData()..homeworkDue = 'kept');
      EncryptedFileVault.debugBeforeReadBack = (f) async => throw const FileSystemException('stopped here');
      await expectLater(vault.rotateKey(), throwsA(anything)); // a renewal cut short: both keys waiting
      EncryptedFileVault.debugBeforeReadBack = null;
      final next = EncryptedFileVault(keychain: keys, folder: () async => dir);
      expect((await next.load()).homeworkDue, 'kept'); // queues the re-seal
      for (final f in [main(), File('${main().path}.bak')]) {
        chmod('000', f.path);
      }
      await next.save(AppData()..homeworkDue = 'kept'); // runs after the queued re-seal, which could not read
      for (final f in [main(), File('${main().path}.bak')]) {
        chmod('600', f.path);
      }
      expect(keys.values.containsKey('$name.previous'), isTrue);
    });

    test('control: a store proved to open with neither key does not hold the renewal back', () async {
      await vault.save(AppData()..homeworkDue = 'kept');
      final rnd = List<int>.generate(200, (i) => (i * 37) % 256);
      main().writeAsBytesSync(rnd);
      File('${main().path}.bak').writeAsBytesSync(rnd);
      await vault.rotateKey();
      expect(keys.values.containsKey('$name.previous'), isFalse);
    });

    test('control: a renewal that reads everything still deletes the previous key, and only the new key opens',
        () async {
      await vault.save(AppData()..homeworkDue = 'kept');
      final id = await vault.putMedia(picture);
      final old = keys.values[name]!;
      await vault.rotateKey();
      expect(keys.values.containsKey('$name.previous'), isFalse);
      expect(await opensWith(main(), old), isFalse);
      expect(await opensWith(File('${dir.path}/media/$id.bin'), old), isFalse);
      expect((await EncryptedFileVault(keychain: keys, folder: () async => dir).load()).homeworkDue, 'kept');
    });
  });

  group('G7-05 and G7-01: staged and set-aside key files', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('r7_keys'));
    tearDown(() async {
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
      await dir.delete(recursive: true);
    });

    test('G7-05: a change whose leftover staged key cannot be read changes nothing and keeps it', () async {
      final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
      await keys.write(name, 'the-data-key');
      final staged = File('${dir.path}/keys/$name.wrap.next')..writeAsBytesSync(List.filled(60, 7));
      chmod('000', staged.path);
      await expectLater(keys.changePassphrase('new phrase here'), throwsA(isA<FileSystemException>()));
      chmod('600', staged.path);
      expect(staged.existsSync(), isTrue, reason: 'kept, not deleted');
      final again = await PassphraseKeyStore.open(dir, 'old phrase here'); // the old one still opens, as said
      expect(await again.read(name), 'the-data-key');
      expect(staged.existsSync(), isFalse, reason: 'once read, proved not to open, and tidied');
    });

    test('G7-05: a staged key cut short (too short to be sealed) is removed, so the opening never fails for good',
        () async {
      final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
      await keys.write(name, 'the-data-key');
      File('${dir.path}/keys/$name.wrap.next').writeAsBytesSync([1, 2, 3]);
      final again = await PassphraseKeyStore.open(dir, 'old phrase here');
      expect(await again.read(name), 'the-data-key');
      expect(File('${dir.path}/keys/$name.wrap.next').existsSync(), isFalse);
    });

    test('G7-01: Delete everything removes every key file, staged, cut short or set aside, and keeps the set-up '
        'file and the keyring-delete marker', () async {
      final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
      await keys.write(name, 'k');
      final k = '${dir.path}/keys';
      for (final n in ['$name.wrap.next', '$name.wrap.part', '$name.previous.wrap', '$name.wrap.unreadable-2026',
        'passphrase.json.next', 'keyring_delete_pending']) {
        File('$k/$n').writeAsStringSync('x');
      }
      await keys.deleteAll();
      final left = [for (final e in Directory(k).listSync()) e.uri.pathSegments.last]..sort();
      expect(left, ['keyring_delete_pending', 'passphrase.json']);
    });
  });

  group('G7-04: an owed keyring delete survives "I have forgotten it"', () {
    test('a delete that fails again after Start fresh is still owed, and tried until it works', () async {
      final dir = Directory.systemTemp.createTempSync('r7_ring');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/data_v1.bin').writeAsBytesSync([1, 2, 3]);
      final ring = _Keys()
        ..values[name] = 'OLD DATA KEY'
        ..failDeletes = 2;
      await moveKeyringKey(_Keys(), dir, ring: ring); // the move works, the keyring delete fails
      for (final n in ['data_v1.bin', 'keys']) {
        final p = '${dir.path}/$n';
        FileSystemEntity.isDirectorySync(p) ? Directory(p).renameSync('$p.forgotten-x') : File(p).renameSync('$p.forgotten-x');
      }
      Directory('${dir.path}/keys').createSync();
      await moveKeyringKey(_Keys(), dir, ring: ring); // fails again
      expect(ring.values, isNotEmpty);
      expect(File('${dir.path}/keys.forgotten-x/keyring_delete_pending').existsSync(), isTrue, reason: 'still owed');
      await moveKeyringKey(_Keys(), dir, ring: ring); // works now
      expect(ring.values, isEmpty);
      expect(File('${dir.path}/keys.forgotten-x/keyring_delete_pending').existsSync(), isFalse);
      expect(File('${dir.path}/keys/keyring_delete_pending').existsSync(), isFalse);
    });
  });

  group('G7-09: the passphrase change runs in the store\'s queue', () {
    test('a Delete everything asked for while a change runs waits for it, so no key comes back', () async {
      final dir = await Directory.systemTemp.createTemp('r7_queue');
      addTearDown(() => dir.delete(recursive: true));
      final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      await vault.save(AppData()..homeworkDue = 'private words');
      final order = <String>[];
      final change = vault.inKeyQueue(() async {
        order.add('change starts');
        await keys.changePassphrase('new phrase here');
        order.add('change ends');
      });
      final wipe = vault.wipe().then((_) => order.add('wipe ends'));
      await Future.wait([change, wipe]);
      expect(order, ['change starts', 'change ends', 'wipe ends']);
      expect(Directory('${dir.path}/keys').listSync().where((e) => e.path.contains('.wrap')), isEmpty);
      final reopened = await PassphraseKeyStore.open(dir, 'new phrase here');
      expect(await reopened.read(name), isNull, reason: 'the data key deleted by Delete everything stays deleted');
    });

    testWidgets('the screen checks the current passphrase and changes it inside the queue it is given',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('r7_screen');
      addTearDown(() => dir.deleteSync(recursive: true));
      final keys = (await tester.runAsync(() => PassphraseKeyStore.create(dir, 'the current one', settings: quick)))!;
      var queued = 0;
      var done = false;
      await tester.pumpWidget(MaterialApp(home: ChangePassphraseScreen(dir: dir, keys: keys,
          inQueue: (work) async {
            queued++;
            await work();
            done = true;
          })));
      await tester.enterText(find.byKey(const Key('pass_current')), 'the current one');
      await tester.enterText(find.byKey(const Key('pass_new')), 'a brand new one');
      await tester.enterText(find.byKey(const Key('pass_new_again')), 'a brand new one');
      await tester.tap(find.byKey(const Key('pass_change')));
      for (var i = 0; i < 200 && find.textContaining('Passphrase changed').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(queued, 1);
      expect(done, isTrue);
      expect(find.textContaining('Passphrase changed'), findsOneWidget);
      await tester.runAsync(() => PassphraseKeyStore.open(dir, 'a brand new one'));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('G7-06: the app lock is not fooled by the device clock', () {
    late _Clock clock;
    setUp(() {
      clock = _Clock();
      lockClock = clock;
      forgetLockWaitForTest();
    });
    tearDown(() {
      lockClock = const LockClock();
      forgetLockWaitForTest();
    });

    Future<void> awayAndBack(WidgetTester tester, Duration away, {Duration? wallMoves}) async {
      for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(st);
        await tester.pump();
      }
      clock.pass(away, wallMoves: wallMoves);
      for (final st in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(st);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> unlockedWithLock(WidgetTester tester, int minutes) async {
      final state = flow.makeState();
      await flow.pumpApp(tester, state); // lock off at the start, so it opens unlocked
      state.data.settings
        ..appLock = true
        ..lockAfterMinutes = minutes
        ..passcode = {'x': 'y'};
      expect(find.text('Solace is locked'), findsNothing);
    }

    for (final minutes in [1, 0]) {
      testWidgets('75 s away with the clock set back two hours locks ("Lock after: $minutes")', (tester) async {
        await unlockedWithLock(tester, minutes);
        await awayAndBack(tester, const Duration(seconds: 75), wallMoves: const Duration(hours: -2));
        expect(find.text('Solace is locked'), findsOneWidget);
      });
    }

    testWidgets('the clock set back by less than the time away still locks (it fell behind the stopwatch)',
        (tester) async {
      await unlockedWithLock(tester, 1);
      await awayAndBack(tester, const Duration(seconds: 75), wallMoves: const Duration(seconds: 10));
      expect(find.text('Solace is locked'), findsOneWidget);
    });

    testWidgets('the device asleep (the stopwatch paused) while the wall clock says time passed: locks',
        (tester) async {
      await unlockedWithLock(tester, 1);
      await awayAndBack(tester, const Duration(seconds: 5), wallMoves: const Duration(minutes: 10));
      expect(find.text('Solace is locked'), findsOneWidget);
    });

    testWidgets('control: 10 s away with the clock untouched stays open ("Lock after: 1 minute")', (tester) async {
      await unlockedWithLock(tester, 1);
      await awayAndBack(tester, const Duration(seconds: 10));
      expect(find.text('Solace is locked'), findsNothing);
    });

    testWidgets('the desktop idle lock: two minutes idle with the clock set back locks; 20 s idle does not',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await unlockedWithLock(tester, 1);
        clock.pass(const Duration(seconds: 20));
        await tester.pump(const Duration(seconds: 30)); // the idle check
        expect(find.text('Solace is locked'), findsNothing);
        clock.pass(const Duration(minutes: 2), wallMoves: const Duration(hours: -1));
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
        expect(find.text('Solace is locked'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('the passcode wait is not ended by setting the clock forward while Solace runs', () {
      final s = Settings();
      final t = clock.wallNow;
      for (var i = 0; i < 5; i++) {
        recordLockFail(s, t, mono: const Duration(seconds: 100));
      }
      expect(lockWait(s, t, mono: const Duration(seconds: 100)), const Duration(seconds: 30));
      final forward = t.add(const Duration(hours: 1));
      expect(lockWait(s, forward, mono: const Duration(seconds: 105)), const Duration(seconds: 25));
      expect(lockWait(s, forward, mono: const Duration(seconds: 131)), isNull, reason: 'the 30 s did pass');
    });

    test('the passcode wait is not cut short by setting the clock back while Solace runs', () {
      final s = Settings();
      final t = clock.wallNow;
      for (var i = 0; i < 5; i++) {
        recordLockFail(s, t, mono: const Duration(seconds: 100));
      }
      final back = t.subtract(const Duration(hours: 1)).add(const Duration(seconds: 10));
      final left = lockWait(s, back, mono: const Duration(seconds: 110))!;
      expect(left >= const Duration(seconds: 20) && left <= const Duration(seconds: 30), isTrue, reason: '$left');
      expect(lockWait(s, back.add(const Duration(seconds: 15)), mono: const Duration(seconds: 125)), isNotNull);
    });

    test('a saved wait whose clock was set back since runs in full from now, never for a year, and counts down', () {
      final s = Settings()
        ..lockFails = 5
        ..lockUntil = DateTime(2026, 11, 15, 12, 0, 30).toIso8601String(); // saved before Solace was closed
      final back = DateTime(2025, 11, 15, 12);
      expect(lockWait(s, back, mono: const Duration(seconds: 10)), const Duration(seconds: 30));
      expect(lockWait(s, back.add(const Duration(seconds: 10)), mono: const Duration(seconds: 20)),
          const Duration(seconds: 20));
      expect(lockWait(s, back.add(const Duration(seconds: 31)), mono: const Duration(seconds: 41)), isNull);
      expect(timePassed((wall: back, mono: Duration.zero), const Duration(minutes: 1),
          (wall: back.subtract(const Duration(seconds: 5)), mono: const Duration(seconds: 2))), isTrue,
          reason: 'a wall clock that went back counts as time passed');
    });
  });

  group('G7-07: the secret digit boxes', () {
    Future<Map<String, dynamic>> argsOf(WidgetTester tester, Finder box) async {
      await tester.tap(box);
      await tester.pump();
      return tester.testTextInput.setClientArgs!;
    }

    for (final (platform, type) in [
      (TargetPlatform.linux, 'TextInputType.visiblePassword'),
      (TargetPlatform.android, 'TextInputType.number'),
      (TargetPlatform.iOS, 'TextInputType.number'),
    ]) {
      testWidgets('choosing the app passcode on ${platform.name}: $type, digits only', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
              onPressed: () => choosePasscode(context), child: const Text('choose')))));
          await tester.tap(find.text('choose'));
          await tester.pumpAndSettle();
          for (final key in ['passcode_first', 'passcode_second']) {
            final args = await argsOf(tester, find.byKey(Key(key)));
            expect((args['inputType'] as Map)['name'], type, reason: key);
            expect(args['obscureText'], isTrue);
          }
          await tester.enterText(find.byKey(const Key('passcode_first')), '12ab34');
          expect(tester.widget<TextField>(find.byKey(const Key('passcode_first'))).controller!.text, '1234');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('the deep work key on Linux reaches the input method as a password', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await flow.pumpScreen(tester, flow.makeState(), const SettingsScreen());
        final deep = find.widgetWithText(TextButton, 'Deep work mode');
        await tester.scrollUntilVisible(deep, 400, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle(); // Settings builds every section at once: the scroll lands with this frame
        await tester.tap(deep);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('full_mode_key')));
        await tester.pumpAndSettle();
        final args = await argsOf(tester, find.byKey(const Key('full_mode_key')));
        expect((args['inputType'] as Map)['name'], 'TextInputType.visiblePassword');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('G7-02: You tab changes say when they were not saved', () {
    late int haptics;
    setUp(() {
      haptics = 0;
      Haptics.wanted = () {
        haptics++;
        return false;
      };
    });
    tearDown(() => Haptics.wanted = () => true);

    testWidgets('Erase plays the done touch only after a save that worked', (tester) async {
      final vault = _FailingVault()..failing = true;
      final state = flow.makeState(demo: true, vault: vault);
      await flow.pumpScreen(tester, state, const Scaffold(body: SingleChildScrollView(child: MemoryControls())));
      await tester.tap(find.byKey(const Key('memory_erase')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('memory_erase_confirm')));
      await tester.pumpAndSettle();
      expect(haptics, 0, reason: 'no done touch for a save that failed');
      expect(find.text(eraseNotSaved), findsOneWidget);
      vault.failing = false;
      ScaffoldMessenger.of(tester.element(find.byType(MemoryControls))).removeCurrentSnackBar();
      await tester.tap(find.byKey(const Key('memory_erase')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('memory_erase_confirm')));
      await tester.pumpAndSettle();
      expect(haptics, 1);
      expect(find.text(eraseNotSaved), findsNothing);
    });

    testWidgets('removing a value, removing a goal and changing the story say so when not saved', (tester) async {
      final vault = _FailingVault();
      final state = flow.makeState(demo: true, vault: vault);
      expect(state.data.plans.values, isNotEmpty, reason: 'precondition: the demo person has values');
      expect(state.data.plans.goals, isNotEmpty, reason: 'precondition: and goals');
      vault.failing = true;
      await flow.pumpScreen(tester, state, const Scaffold(body: YouTab())); // inside the app's Scaffold, as in HomeShell
      final value = state.data.plans.values.first.text;
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.widgetWithText(InputChip, value), 300, scrollable: list);
      await tester.pumpAndSettle();
      final chip = tester.widget<InputChip>(find.widgetWithText(InputChip, value));
      chip.onDeleted!();
      await tester.pumpAndSettle();
      expect(find.text(removedNotSaved), findsOneWidget, reason: 'value');
      ScaffoldMessenger.of(tester.element(find.byType(YouTab))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      final remove = find.byTooltip('Remove').first;
      await tester.scrollUntilVisible(remove, 300, scrollable: list);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text(removedNotSaved), findsOneWidget, reason: 'goal');
      ScaffoldMessenger.of(tester.element(find.byType(YouTab))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      final part = find.byIcon(Icons.edit_outlined).first;
      await tester.scrollUntilVisible(part, 300, scrollable: list);
      await tester.pumpAndSettle();
      await tester.tap(part);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text(changeNotSaved), findsOneWidget, reason: 'story');
    });
  });

  group('G7-08: the bundle is checked and unpacked from one private copy', () {
    late Directory src, files;
    setUp(() async {
      src = await Directory.systemTemp.createTemp('r7_bundle_src');
      files = await Directory.systemTemp.createTemp('r7_bundle_files');
    });
    tearDown(() async {
      debugBundleChecked = null;
      await src.delete(recursive: true);
      await files.delete(recursive: true);
    });
    List<int> zipOf(Map<String, String> entries) {
      final a = Archive();
      entries.forEach((n, t) => a.addFile(ArchiveFile.string(n, t)));
      return ZipEncoder().encode(a);
    }

    test('the picked file changed after the check is not what is unpacked', () async {
      final picked = File('${src.path}/bundle.zip')..writeAsBytesSync(zipOf({'voice/voice.sha256': 'trusted'}));
      testOnlyTrustedBundles.add(await sha256Of(picked));
      debugBundleChecked = () async {
        // another program swaps the person's file between the check and the unpack
        File('${src.path}/swap.zip').writeAsBytesSync(zipOf({'voice/voice.sha256': 'SWAPPED', 'voice/x': 'x'}));
        File('${src.path}/swap.zip').renameSync(picked.path);
      };
      final msg = await importBundle(picked.path, files);
      expect(msg, startsWith('Added 1'));
      expect(File('${files.path}/voice/voice.sha256').readAsStringSync(), 'trusted');
      expect(partsIn(files), isEmpty, reason: 'the private copy is removed');
    });

    test('the iPhone drop zone: moved in, unpacked, and a refused one goes back as .refused', () async {
      final inbox = Directory('${src.path}/inbox')..createSync();
      File('${inbox.path}/good.zip').writeAsBytesSync(zipOf({'voice/voice.sha256': 'trusted'}));
      testOnlyTrustedBundles.add(await sha256Of(File('${inbox.path}/good.zip')));
      expect(await importInbox(inbox, files), startsWith('Added 1'));
      expect(File('${inbox.path}/good.zip').existsSync(), isFalse);
      expect(partsIn(files), isEmpty);
      File('${inbox.path}/other.zip').writeAsBytesSync(zipOf({'voice/voice.sha256': 'unknown'}));
      expect(await importInbox(inbox, files), contains('not the voice and safety bundle'));
      expect(File('${inbox.path}/other.zip.refused').existsSync(), isTrue);
      expect(partsIn(files), isEmpty);
    });
  });
}

/// The part files left in [files] (MM-01: each import has its own, so none may be left behind).
List<String> partsIn(Directory files) => [
      for (final e in files.listSync())
        if (e.path.endsWith('.part') || e.uri.pathSegments.where((x) => x.isNotEmpty).last.startsWith('.incoming')) e.path,
    ];
