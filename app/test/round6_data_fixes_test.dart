// Round 6 review E fixes beyond the reviewer's own proofs (test/review6e/): E-01 (a save that failed is never reported
// as done: Delete older conversations, the privacy switches, the app lock, pictures), E-03 (the file picker's leftover
// copies and its Android record cleared), E-04 (Delete everything tries the keyring copy again at once), E-05 (Start
// fresh when a Linux key file cannot be opened), E-11 (the passphrase change after its commit point), and reviewer F's
// F6-17 (the vision board, goals and values read by the phrase rules on save).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_files.dart';
import 'package:solace/core/app_lock.dart' show hashPasscode;
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/plans.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/crisis.dart' show CrisisSheet;
import 'package:solace/ui/passphrase_screen.dart';
import 'package:solace/ui/privacy.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/storage.dart';
import 'package:solace/ui/vision_board.dart';
import 'package:solace/ui/you.dart';

import 'app_flow_test.dart' as flow;

/// A vault whose saves fail once [failing] is set (a full disk).
class _FailingVault extends MemoryVault {
  bool failing = false;
  @override
  Future<void> save(AppData data) async {
    if (failing) throw const FileSystemException('No space left on device', '', OSError('', 28));
    return super.save(data);
  }
}

/// The real passphrase store on disk for [PassphraseKeyStore.open], but a change that fails after its commit point.
class _ChangedNotSettled implements PassphraseKeyStore {
  @override
  Future<void> changePassphrase(String newPassphrase, {StretchSettings? settings}) async =>
      throw const PassphraseChangedNotSettled();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const quick = StretchSettings(memoryKib: 8192, iterations: 1);

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  group('E-01: a change that was not saved is never reported as done', () {
    testWidgets('Delete older conversations says it is not deleted yet; once saves work it deletes, words and note too',
        (tester) async {
      final vault = _FailingVault();
      final state = flow.makeState(vault: vault);
      final old = SessionRecord(date: '2020-03-02', kind: 'daily_checkin', note: 'the old note',
          turns: [('person', 'Honesty matters to me more than anything.')]);
      state.data.sessions.add(old);
      state.data.lastNote = 'the old note';
      state.data.plans.values.add(Value(text: 'Honesty', quote: 'Honesty matters to me', added: '2020-03-02'));
      await vault.save(state.data);
      vault.failing = true;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: StorageScreen())));
      for (var i = 0; i < 30 && find.text('Conversations').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); // the measuring isolate
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('storage_older_6')), 300,
          scrollable: find.descendant(of: find.byType(StorageScreen), matching: find.byType(Scrollable)).first);
      await tester.tap(find.byKey(const Key('storage_older_6')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('storage_delete_words')), findsOneWidget);
      expect(find.textContaining('Your words quoted in goals, values and steps'), findsOneWidget, reason: 'E-02 line');
      await tester.tap(find.byKey(const Key('storage_delete_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Deleted 1 older'), findsNothing);
      expect(find.textContaining('not deleted yet'), findsOneWidget);
      expect((await vault.load()).sessions, hasLength(1), reason: 'the precondition: the device still holds it');
      // the banner's Try again, once there is room: the delete reaches the device, with its words and note (E-02)
      vault.failing = false;
      expect(await state.trySave(), isTrue);
      final saved = await vault.load();
      expect(saved.sessions, isEmpty);
      expect(saved.lastNote, '');
      expect(saved.plans.values.single.quote, '');
    });

    testWidgets('Pause memory and Hide in the app switcher are put back, and say so, when not saved', (tester) async {
      final vault = _FailingVault();
      final state = flow.makeState(vault: vault);
      await vault.save(state.data);
      vault.failing = true;
      await flow.pumpScreen(tester, state, const Scaffold(body: SingleChildScrollView(child: MemoryControls())));
      await tester.tap(find.byKey(const Key('memory_pause')));
      await tester.pumpAndSettle();
      expect(state.data.settings.memoryPaused, isFalse, reason: 'the switch shows what the device holds');
      expect(find.byKey(const Key('not_saved')), findsOneWidget);
      expect((await vault.load()).settings.memoryPaused, isFalse);
      vault.failing = false;
      await tester.tap(find.byKey(const Key('memory_pause')));
      await tester.pumpAndSettle();
      expect(state.data.settings.memoryPaused, isTrue);
      expect((await vault.load()).settings.memoryPaused, isTrue);

      vault.failing = true;
      await flow.pumpScreen(tester, state, const SettingsScreen());
      final before = state.data.settings.hideInSwitcher;
      await flow.tapIn(tester, find.byKey(const Key('hide_switcher')));
      await tester.pumpAndSettle();
      expect(state.data.settings.hideInSwitcher, before);
      expect((await vault.load()).settings.hideInSwitcher, before);
    });

    testWidgets('the app lock: turned on only once saved, and turning it off that fails keeps it on', (tester) async {
      final vault = _FailingVault();
      final state = flow.makeState(vault: vault);
      await vault.save(state.data);
      vault.failing = true;
      await flow.pumpScreen(tester, state, const SettingsScreen());
      await flow.tapIn(tester, find.byKey(const Key('app_lock')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('passcode_first')), '246801');
      await tester.enterText(find.byKey(const Key('passcode_second')), '246801');
      await tester.tap(find.byKey(const Key('passcode_understood'))); // round 9 final, 9A-10
      await tester.pump();
      await tester.tap(find.byKey(const Key('passcode_save')));
      for (var i = 0; i < 60 && find.byKey(const Key('not_saved')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.textContaining('so the lock is still off'), findsOneWidget);
      expect(state.data.settings.appLock, isFalse);
      expect(state.data.settings.passcode, isNull, reason: 'the passcode chosen is not kept either');
      expect((await vault.load()).settings.appLock, isFalse);
      // on and saved; then turning it off cannot be saved, so it stays on
      vault.failing = false;
      state.data.settings
        ..appLock = true
        ..passcode = await tester.runAsync(() => hashPasscode('246801'));
      await state.save();
      vault.failing = true;
      await flow.pumpScreen(tester, state, const SettingsScreen());
      await flow.tapIn(tester, find.byKey(const Key('app_lock')));
      // round 9 review, 9A-02: turning it off asks for the passcode first; the right one, then the save fails
      await tester.enterText(find.byKey(const Key('confirm_passcode')), '246801');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('confirm_passcode_ok')));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm_passcode')), findsNothing, reason: 'the passcode was taken');
      expect(state.data.settings.appLock, isTrue);
      expect(state.data.settings.passcode, isNotNull, reason: 'its passcode is put back with it (9B-12)');
      expect((await vault.load()).settings.appLock, isTrue);
    });

    test('pictures: the earlier file is kept while the data on the device names it, and goes after a save that works',
        () async {
      final vault = _FailingVault();
      final state = flow.makeState(vault: vault);
      await state.setPicture('Sea', Uint8List.fromList([1, 2, 3]));
      final first = mediaIdOf(state.data.photos['Sea']!);
      vault.failing = true;
      await expectLater(state.setPicture('Sea', Uint8List.fromList([4, 5, 6])), throwsA(isA<NotSaved>()));
      final second = mediaIdOf(state.data.photos['Sea']!);
      expect((await vault.mediaIndex()).$1, containsAll([first, second]), reason: 'the device still names the first');
      expect((await vault.load()).photos['Sea'], 'media:$first');
      await expectLater(state.deletePicture('Sea'), throwsA(isA<NotSaved>()));
      expect((await vault.mediaIndex()).$1, containsAll([first, second]), reason: 'nothing deleted yet');
      vault.failing = false;
      expect(await state.trySave(), isTrue);
      expect((await vault.mediaIndex()).$1, isEmpty, reason: 'both go once a save no longer names them');
      expect((await vault.load()).photos, isEmpty);
    });
  });

  group('E-03: the file picker\'s leftovers', () {
    late Directory cache;
    final calls = <String>[];
    setUp(() {
      cache = Directory.systemTemp.createTempSync('r6_cache');
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pickerChannel,
          (call) async {
        calls.add(call.method);
        if (call.method == 'retrieveLostData') return {'files': <Object?>[]};
        return null;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pickerChannel, null);
      cache.deleteSync(recursive: true);
    });
    TestWidgetsFlutterBinding.ensureInitialized();

    test('Android: the lost pick is taken (its record goes), then the picker\'s folder, and only that', () async {
      final copy = File('${cache.path}/file_picker/12f19ead/photo.png')..createSync(recursive: true);
      final other = File('${cache.path}/other/keep.bin')..createSync(recursive: true);
      await clearPickerLeftovers(os: 'android', clear: () async => calls.add('clear'),
          cache: () async => cache);
      expect(calls, ['retrieveLostData', 'clear'], reason: 'the record is taken first, then the copies cleared');
      expect(copy.existsSync(), isFalse);
      expect(Directory('${cache.path}/file_picker').existsSync(), isFalse);
      expect(other.existsSync(), isTrue, reason: 'nothing else in the cache is touched');
    });

    test('iPhone and Mac: the plugin clears its own folder; Linux: nothing is touched; faults are quiet', () async {
      final kept = File('${cache.path}/file_picker/x.png')..createSync(recursive: true);
      for (final os in ['ios', 'macos']) {
        calls.clear();
        await clearPickerLeftovers(os: os, clear: () async => calls.add('clear'), cache: () async => cache);
        expect(calls, ['clear'], reason: os);
      }
      calls.clear();
      await clearPickerLeftovers(os: 'linux', clear: () async => calls.add('clear'), cache: () async => cache);
      expect(calls, isEmpty);
      expect(kept.existsSync(), isTrue, reason: 'no folder deleted from here except on Android');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pickerChannel,
          (call) async => throw PlatformException(code: 'no_activity'));
      await clearPickerLeftovers(os: 'android', clear: () async => throw StateError('x'), cache: () async => cache);
      expect(Directory('${cache.path}/file_picker').existsSync(), isFalse, reason: 'cleared from here all the same');
    });
  });

  test('E-04: Delete everything runs the keyring retry at once', () async {
    final state = flow.makeState();
    var ran = 0;
    state.afterWipe = () async => ran++;
    await state.wipeEverything(folders: () async {});
    expect(ran, 1);
  });

  test('E-05: Start fresh with a key file that cannot be opened sets data and key file aside, never deletes', () async {
    final dir = Directory.systemTemp.createTempSync('r6_aside');
    addTearDown(() => dir.deleteSync(recursive: true));
    final keys = await PassphraseKeyStore.create(dir, 'my good passphrase', settings: quick);
    await EncryptedFileVault(keychain: keys, folder: () async => dir).save(AppData()..homeworkDue = 'mine');
    final wrap = File('${dir.path}/keys/${EncryptedFileVault.keyName}.wrap');
    final b = wrap.readAsBytesSync();
    b[b.length - 1] ^= 1;
    wrap.writeAsBytesSync(b);
    final again = await PassphraseKeyStore.open(dir, 'my good passphrase');
    final vault = EncryptedFileVault(keychain: again, folder: () async => dir);
    await expectLater(vault.load(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'key_unreadable')));
    await vault.setAside();
    final names = dir.listSync(recursive: true).map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last).toList();
    expect(names.where((n) => n.startsWith('data_v1.bin') && n.contains('.unreadable-')), hasLength(2),
        reason: 'the data and its last good copy');
    expect(names.where((n) => n.startsWith('${EncryptedFileVault.keyName}.wrap.unreadable-')), hasLength(1));
    expect(wrap.existsSync(), isFalse);
    // Solace opens empty, with a fresh key; the passphrase can still be changed (the set-aside file is not re-sealed)
    expect((await vault.load()).homeworkDue, '');
    await vault.save(AppData()..homeworkDue = 'fresh');
    expect((await EncryptedFileVault(keychain: again, folder: () async => dir).load()).homeworkDue, 'fresh');
    await again.changePassphrase('another good phrase', settings: quick);
    // Delete everything deletes the key file set aside too
    await again.deleteAll();
    expect(Directory('${dir.path}/keys').listSync().where((e) => e.path.contains('.wrap')), isEmpty);
  });

  testWidgets('E-11: a change that failed after its commit point never says the old passphrase still opens Solace',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('r6_change');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.runAsync(() => PassphraseKeyStore.create(dir, 'the current one', settings: quick));
    var renewed = 0;
    await tester.pumpWidget(MaterialApp(home: ChangePassphraseScreen(dir: dir, keys: _ChangedNotSettled(),
        renewKey: () async => renewed++)));
    await tester.enterText(find.byKey(const Key('pass_current')), 'the current one');
    await tester.enterText(find.byKey(const Key('pass_new')), 'a brand new one');
    await tester.enterText(find.byKey(const Key('pass_new_again')), 'a brand new one');
    await tester.tap(find.byKey(const Key('pass_change')));
    for (var i = 0; i < 100 && find.textContaining('Passphrase changed').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('Only the new one opens Solace'), findsOneWidget);
    expect(find.textContaining('the old one still opens'), findsNothing);
    expect(renewed, 0, reason: 'the keys are not yet under the new passphrase, so no renewal is tried');
    await tester.pumpWidget(const SizedBox()); // the screen's wait timer goes with it
  });

  testWidgets('E-07 and E-10: Private by design says the keyboard\'s dictation and clipboard sync are the device\'s',
      (tester) async {
    await flow.pumpScreen(tester, flow.makeState(), const PrivacyScreen());
    await tester.scrollUntilVisible(find.byKey(const Key('privacy_device_note')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('microphone button (dictation)'), findsOneWidget);
  });

  group('F6-17: words saved on the vision board, as goals or as values are read by the phrase rules', () {
    testWidgets('a crisis in a vision board wish opens support and is recorded', (tester) async {
      final state = flow.makeState();
      await flow.pumpScreen(tester, state, const Scaffold(body: SingleChildScrollView(child: VisionBoardSection())));
      await tester.tap(find.text('Add a picture'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Somewhere quiet');
      await tester.enterText(find.byType(TextField).at(1), 'I want to kill myself tonight.');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(state.data.plans.pictures.single.wish, 'I want to kill myself tonight.', reason: 'still kept');
      expect(state.data.safetyEvents.single['level'], 'crisis');
      expect(state.data.safetyEvents.single['reason'], contains('your vision board'));
      expect(find.byType(CrisisSheet), findsOneWidget);
    });

    testWidgets('goals and values: a crisis is read; an ordinary one does nothing', (tester) async {
      final state = flow.makeState();
      await flow.pumpScreen(tester, state, const Scaffold(body: YouTab()));
      final scroll = find.byType(Scrollable).first;
      Future<void> addFrom(Finder box) async {
        final add = find.descendant(of: find.ancestor(of: box, matching: find.byType(Row)).first,
            matching: find.byIcon(Icons.add));
        await Scrollable.ensureVisible(tester.element(add), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(add);
      }
      final goalBox = find.widgetWithText(TextField, 'Add a goal');
      await tester.scrollUntilVisible(goalBox, 300, scrollable: scroll);
      await tester.enterText(goalBox, 'Run a 5k in spring');
      await addFrom(goalBox);
      await tester.pumpAndSettle();
      expect(state.data.plans.goals.map((g) => g.text), contains('Run a 5k in spring'));
      expect(state.data.safetyEvents, isEmpty);
      final valueBox = find.widgetWithText(TextField, 'Add one');
      await tester.scrollUntilVisible(valueBox, -300, scrollable: scroll);
      await tester.enterText(valueBox, "I'm going to kill myself tonight.");
      await addFrom(valueBox);
      await tester.pumpAndSettle();
      expect(state.data.plans.values.map((v) => v.text), contains("I'm going to kill myself tonight."));
      expect(state.data.safetyEvents.single['level'], 'crisis');
      expect(state.data.safetyEvents.single['reason'], contains('what matters to you'));
    });
  });
}

String mediaIdOf(String ref) => ref.substring('media:'.length);
