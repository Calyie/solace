// Owner, 2026-11-15: "Is there an option for me to change the 6 digit pin? Let's say if it gets compromised in the
// future?" Settings > Change deep work PIN asks for the current PIN (checked by the key in force, counted toward the
// same pause as deep work mode and the safety check), then a new one twice; a weak new PIN or one the same as the
// current is refused, and said why. The new PIN is kept only as a fresh salted Argon2id fingerprint, in its own file
// beside the store (PinKeep); it never goes into a transfer file, an import keeps this device's own, and Delete
// everything, Start fresh and "I have forgotten it" leave it, so the built PIN never comes back once replaced (round
// 9 review, 9A-01; a fresh install starts from the built PIN). From then on deep work mode and the safety check use
// the new PIN.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_files.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/full_mode_lock.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/settings.dart';

import 'app_flow_test.dart' as flow;

const _built = '135790', _newPin = '246813';
final _change = find.byKey(const Key('change_pin'));
final _classifier = find.byKey(const Key('classifier_switch'));
final _deep = find.widgetWithText(TextButton, 'Deep work mode');
const _deepGo = 'I understand, turn on deep work mode';

Future<void> _open(WidgetTester tester, AppState state, Finder target) async {
  await flow.pumpScreen(tester, state, const SettingsScreen());
  await tester.scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

/// Presses [button]; the key checks run outside the test's simulated clock.
Future<void> _press(WidgetTester tester, Finder button) async {
  await tester.runAsync(() async {
    await tester.tap(button);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pumpAndSettle();
}

/// Fills the Change deep work PIN boxes (already open) and presses Change PIN.
Future<void> _fill(WidgetTester tester, String current, String next, [String? again]) async {
  await tester.enterText(find.byKey(const Key('change_pin_current')), current);
  await tester.enterText(find.byKey(const Key('change_pin_new')), next);
  await tester.enterText(find.byKey(const Key('change_pin_confirm')), again ?? next);
  await _press(tester, find.byKey(const Key('change_pin_save')));
}

/// Opens Change deep work PIN from Settings and changes the built PIN to [_newPin].
Future<void> _changeToNew(WidgetTester tester, AppState state) async {
  await _open(tester, state, _change);
  await flow.tapIn(tester, _change);
  await _fill(tester, _built, _newPin);
  expect(find.byKey(const Key('change_pin_current')), findsNothing, reason: 'the dialog has closed');
}

/// Types [key] in the deep work mode box and presses its button (the card already open).
Future<void> _deepKey(WidgetTester tester, String key) async {
  await tester.enterText(find.byKey(const Key('full_mode_key')), key);
  final go = find.text(_deepGo);
  await tester.ensureVisible(go);
  await tester.pumpAndSettle();
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -400)); // clear of the foot of the screen
  await tester.pumpAndSettle();
  await _press(tester, go);
}

/// A keychain in memory (the encrypted store's key).
class _Keys implements KeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async => values[name] = value;
  @override
  Future<void> delete(String name) async => values.remove(name);
  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf(_built, salt, memoryKib: 64, iterations: 1));
  });

  group('the new PIN must be a fair one', () {
    test('one digit six times, a straight run up or down, or not six digits is refused', () {
      for (final weak in ['000000', '777777', '123456', '654321', '012345', '567890', '098765', '901234']) {
        expect(FullModeKey.weakKeyReason(weak), isNotNull, reason: weak);
      }
      expect(FullModeKey.weakKeyReason('12345'), contains('exactly six digits'));
      expect(FullModeKey.weakKeyReason('12a456'), contains('exactly six digits'));
      expect(FullModeKey.weakKeyReason('111111'), contains('one digit six times'));
      expect(FullModeKey.weakKeyReason('345678'), contains('straight run'));
      for (final fine in [_built, _newPin, '112233', '135791']) {
        expect(FullModeKey.weakKeyReason(fine), isNull, reason: fine);
      }
    });
  });

  group('how the new PIN is kept', () {
    test('a fresh salted fingerprint with the built key\'s settings, never the PIN', () async {
      final a = await flow.testKey.saved(_newPin), b = await flow.testKey.saved(_newPin);
      expect(a['salt'], isNot(b['salt']), reason: 'a new random salt each time');
      expect(base64Decode(a['salt'] as String).length, 16);
      expect(a['memory'], flow.testKey.memoryKib);
      expect(a['iterations'], flow.testKey.iterations);
      expect(jsonEncode(a), isNot(contains(_newPin)));
      final key = FullModeKey.fromSaved(a)!;
      expect(await key.matches(_newPin), isTrue);
      expect(await key.matches(_built), isFalse);
    });

    test('a damaged value is never used, and never asks for a huge amount of memory', () async {
      final good = await flow.testKey.saved(_newPin, random: Random(1));
      expect(FullModeKey.fromSaved(good), isNotNull);
      expect(FullModeKey.fromSaved(null), isNull);
      expect(FullModeKey.fromSaved('a string'), isNull);
      expect(FullModeKey.fromSaved({...good, 'memory': 4000000}), isNull);
      expect(FullModeKey.fromSaved({...good, 'iterations': 1000}), isNull);
      expect(FullModeKey.fromSaved({...good, 'salt': 'AAEC'}), isNull);
      expect(FullModeKey.fromSaved({...good, 'hash': 'not base64!'}), isNull);
    });

    test('it survives a save and load; a damaged one reads as none', () async {
      final data = AppData()..settings.fullModePin = await flow.testKey.saved(_newPin);
      final back = AppData.fromJson(jsonDecode(jsonEncode(data.toJson())));
      expect(back.settings.fullModePin, data.settings.fullModePin);
      final damaged = data.toJson();
      (damaged['settings'] as Map)['full_mode_pin'] = {'salt': 'x', 'hash': 'y', 'memory': 64, 'iterations': 1};
      expect(AppData.fromJson(jsonDecode(jsonEncode(damaged))).settings.fullModePin, isNull);
    });

    test('the key in force: the changed one, else the built one; a build without a key has none', () async {
      final state = flow.makeState();
      expect(await state.fullModeKey.matches(_built), isTrue);
      state.data.settings.fullModePin = await state.builtInKey.saved(_newPin);
      expect(await state.fullModeKey.matches(_newPin), isTrue);
      expect(await state.fullModeKey.matches(_built), isFalse);
      final keep = flow.testKey;
      flow.testKey = const FullModeKey(salt: '', fingerprint: '');
      final bare = flow.makeState()..data.settings.fullModePin = state.data.settings.fullModePin;
      flow.testKey = keep;
      expect(bare.fullModeKey.isSetUp, isFalse, reason: 'a build without a key cannot be opened by a kept one');
    });

    test('never in a transfer file, and an import keeps this device\'s own', () async {
      final code = TransferCode.generate(Random(31));
      final mine = await flow.testKey.saved(_newPin, random: Random(2));
      final theirs = await flow.testKey.saved('135791', random: Random(3));
      final other = AppData()..settings.fullModePin = theirs;
      final opened = await TransferFile.open(await TransferFile.seal(other, code, random: Random(32)), code);
      expect(opened.settings.fullModePin, isNull, reason: 'not in the sealed file');
      final here = AppData()..settings.fullModePin = mine;
      expect(importInto(here, opened).settings.fullModePin, mine);
      final direct = importInto(AppData()..settings.fullModePin = mine, AppData()..settings.fullModePin = theirs);
      expect(direct.settings.fullModePin, mine);
      expect(importInto(AppData(), AppData()..settings.fullModePin = theirs).settings.fullModePin, isNull);
    });

    test('Delete everything never goes back to the built PIN once it was changed (round 9 review, 9A-01)', () async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault)..data.settings.fullModePin = await flow.testKey.saved(_newPin);
      await state.save();
      await state.wipeEverything(folders: () async {});
      expect(state.data.sessions, isEmpty, reason: 'everything else went');
      expect(await state.fullModeKey.matches(_newPin), isTrue);
      expect(await state.fullModeKey.matches(_built), isFalse);
      // never changed: Delete everything leaves the built PIN, as before
      final fresh = flow.makeState(vault: MemoryVault());
      await fresh.wipeEverything(folders: () async {});
      expect(await fresh.fullModeKey.matches(_built), isTrue);
    });
  });

  group('the changed PIN is kept beside the store (round 9 review, 9A-01)', () {
    late Directory dir;
    late _Keys keys; // the device keychain, the same at every start
    setUp(() {
      dir = Directory.systemTemp.createTempSync('pin_keep');
      keys = _Keys();
    });
    tearDown(() => dir.deleteSync(recursive: true));
    File keptFile() => File('${dir.path}/${PinKeep.fileName}');

    /// The app as it starts (main.dart boot): the store and the PIN keep in [dir].
    Future<AppState> started({Vault? vault}) async {
      final state = flow.makeState(vault: vault ?? EncryptedFileVault(keychain: keys, folder: () async => dir));
      state.data = await state.vault.load();
      await state.keepPinBeside(() async => dir);
      return state;
    }

    test('Change deep work PIN writes only the fingerprint, in its own file, and the settings hold none', () async {
      final state = await started();
      expect(await state.changeFullModePin(await flow.testKey.saved(_newPin)), isTrue);
      final kept = jsonDecode(keptFile().readAsStringSync()) as Map;
      expect(kept.keys.toSet(), {'salt', 'hash', 'memory', 'iterations'});
      expect(keptFile().readAsStringSync(), isNot(contains(_newPin)));
      expect(state.data.settings.fullModePin, isNull, reason: 'one place only');
      expect(await state.fullModeKey.matches(_newPin), isTrue);
      expect(await state.fullModeKey.matches(_built), isFalse);
      // the next start reads it
      final again = await started();
      expect(await again.fullModeKey.matches(_newPin), isTrue);
      expect(await again.fullModeKey.matches(_built), isFalse);
    });

    test('a PIN that could not be kept changes nothing, and the old one still works', () async {
      final state = await started();
      Directory('${dir.path}/${PinKeep.fileName}.part').createSync(); // the part file cannot be written
      expect(await state.changeFullModePin(await flow.testKey.saved(_newPin)), isFalse);
      expect(keptFile().existsSync(), isFalse);
      expect(await state.fullModeKey.matches(_built), isTrue);
    });

    test('Delete everything with the real folder wipe keeps it; then Send, wipe and Bring back keep it too', () async {
      final state = await started();
      await state.changeFullModePin(await flow.testKey.saved(_newPin));
      state.data.sessions.add(SessionRecord(date: '2026-11-15', kind: 'intake', note: 'private', turns: []));
      await state.save();
      final code = TransferCode.generate(Random(5));
      final file = await TransferFile.seal(await state.dataForTransfer(), code, random: Random(6));
      await state.wipeEverything(folders: () => wipeAppFolders(support: dir, temp: dir, inbox: dir));
      expect(keptFile().existsSync(), isTrue, reason: 'Delete everything leaves the changed PIN');
      expect(File('${dir.path}/data_v1.bin').existsSync(), isFalse, reason: 'and deletes the data');
      await state.receiveTransfer(await TransferFile.open(file, code));
      expect(state.data.sessions, hasLength(1));
      expect(await state.fullModeKey.matches(_newPin), isTrue);
      expect(await state.fullModeKey.matches(_built), isFalse);
      final restarted = await started();
      expect(await restarted.fullModeKey.matches(_built), isFalse, reason: 'and so does the next start');
      expect(await restarted.fullModeKey.matches(_newPin), isTrue);
    });

    test('Start fresh (the recovery screen) and Linux\'s "I have forgotten it" leave it', () async {
      final state = await started();
      await state.changeFullModePin(await flow.testKey.saved(_newPin));
      await state.save();
      await (state.vault as EncryptedFileVault).setAside(); // RecoveryApp's Start fresh
      // ui/passphrase_screen.dart _startFresh: the same four names, moved aside
      for (final name in ['data_v1.bin', 'data_v1.bin.bak', 'keys', 'media']) {
        final p = '${dir.path}/$name';
        final t = FileSystemEntity.typeSync(p);
        if (t == FileSystemEntityType.notFound) continue;
        t == FileSystemEntityType.directory ? Directory(p).renameSync('$p.forgotten-x') : File(p).renameSync('$p.forgotten-x');
      }
      final again = await started();
      expect(again.data.sessions, isEmpty, reason: 'the data was set aside');
      expect(await again.fullModeKey.matches(_built), isFalse);
      expect(await again.fullModeKey.matches(_newPin), isTrue);
    });

    test('a PIN changed with an earlier version (in the settings only) is moved into the file at the next start',
        () async {
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      await vault.save(AppData()..settings.fullModePin = await flow.testKey.saved(_newPin));
      final state = await started(vault: vault);
      expect(keptFile().existsSync(), isTrue);
      await state.wipeEverything(folders: () => wipeAppFolders(support: dir, temp: dir, inbox: dir));
      final again = await started(vault: vault);
      expect(await again.fullModeKey.matches(_newPin), isTrue);
      expect(await again.fullModeKey.matches(_built), isFalse);
    });

    test('Linux: a key renewal and a passphrase change leave it', () async {
      const quick = StretchSettings(memoryKib: 8192, iterations: 1);
      final phrase = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
      final vault = EncryptedFileVault(keychain: phrase, folder: () async => dir);
      final state = await started(vault: vault);
      await state.changeFullModePin(await flow.testKey.saved(_newPin));
      await state.save();
      await vault.rotateKey();
      await phrase.changePassphrase('new phrase here', settings: quick);
      final reopened = EncryptedFileVault(keychain: await PassphraseKeyStore.open(dir, 'new phrase here'),
          folder: () async => dir);
      final again = await started(vault: reopened);
      expect(await again.fullModeKey.matches(_built), isFalse);
      expect(await again.fullModeKey.matches(_newPin), isTrue);
    });

    test('a kept file that cannot be read: no PIN works, never the built one, and nothing is counted', () async {
      for (final bad in ['not json', '{"salt": "x", "hash": "y", "memory": 64, "iterations": 1}', 'x' * 5000]) {
        keptFile().writeAsStringSync(bad);
        final state = await started();
        expect(state.keptPinUnreadable, isTrue, reason: bad);
        expect(state.fullModeKey.isSetUp, isFalse);
        expect(await state.fullModeKey.matches(_built), isFalse);
        await state.wipeEverything(folders: () => wipeAppFolders(support: dir, temp: dir, inbox: dir));
        expect(keptFile().readAsStringSync(), bad, reason: 'never written over or deleted');
        expect(await state.fullModeKey.matches(_built), isFalse);
      }
    });

    testWidgets('Change deep work PIN in Settings keeps it in the file', (tester) async {
      final state = flow.makeState()..pinKeep = PinKeep(() async => dir);
      await _changeToNew(tester, state);
      expect(keptFile().existsSync(), isTrue);
      expect(state.data.settings.fullModePin, isNull);
      expect(await tester.runAsync(() => state.fullModeKey.matches(_newPin)), isTrue);
    });
  });

  group('Change deep work PIN in Settings', () {
    testWidgets('the right current PIN changes it: saved, and the old PIN no longer opens deep work mode',
        (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      await vault.save(state.data);
      await _changeToNew(tester, state);
      expect(state.data.settings.fullModePin, isNotNull);
      expect((await vault.load()).settings.fullModePin, state.data.settings.fullModePin);
      expect(jsonEncode(state.data.toJson()), isNot(contains(_newPin)), reason: 'only the fingerprint is kept');
      expect(find.textContaining('Your deep work PIN is changed'), findsOneWidget);
      // gone before deep work mode's own line replaces it (a replacement started inside runAsync finishes after the
      // test, outside its simulated clock)
      ScaffoldMessenger.of(tester.element(find.byType(SettingsScreen))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(_deep, 300, scrollable: find.byType(Scrollable).first);
      await flow.tapIn(tester, _deep);
      await _deepKey(tester, _built);
      expect(state.data.settings.mode, 'normal');
      expect(find.text('That key is not right. 4 tries left before a pause.'), findsOneWidget);
      await _deepKey(tester, _newPin);
      expect(state.data.settings.mode, 'full');
      expect(state.data.settings.fullModeFails, 0);
    });

    testWidgets('after a change the safety check turns off only with the new PIN', (tester) async {
      final state = flow.makeState();
      await _changeToNew(tester, state);
      await tester.scrollUntilVisible(_classifier, -300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await flow.tapIn(tester, _classifier);
      await tester.enterText(find.byKey(const Key('classifier_pin')), _built);
      await _press(tester, find.byKey(const Key('classifier_pin_ok')));
      expect(state.data.settings.classifierOn, isTrue);
      expect(state.data.settings.fullModeFails, 1);
      await tester.enterText(find.byKey(const Key('classifier_pin')), _newPin);
      await _press(tester, find.byKey(const Key('classifier_pin_ok')));
      expect(state.data.settings.classifierOn, isFalse);
    });

    testWidgets('a wrong current PIN changes nothing and counts toward the pause', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      await vault.save(state.data);
      await _open(tester, state, _change);
      await flow.tapIn(tester, _change);
      await _fill(tester, '135791', _newPin);
      expect(state.data.settings.fullModePin, isNull);
      expect(state.data.settings.fullModeFails, 1);
      expect((await vault.load()).settings.fullModeFails, 1);
      expect(find.text('That current PIN is not right. 4 tries left before a pause.'), findsOneWidget);
      for (final box in ['change_pin_current', 'change_pin_new', 'change_pin_confirm']) {
        expect(tester.widget<TextField>(find.byKey(Key(box))).controller!.text, isEmpty, reason: box);
      }
      expect(await state.fullModeKey.matches(_built), isTrue);
    });

    testWidgets('after the limit of wrong PINs it cannot be changed, and says until when', (tester) async {
      final state = flow.makeState()..data.settings.fullModeFails = fullModeTries - 1;
      await _open(tester, state, _change);
      await flow.tapIn(tester, _change);
      await _fill(tester, '135791', _newPin);
      expect(find.text('Too many wrong PINs. The PIN cannot be changed until 19:45.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('change_pin_save'))).onPressed, isNull);
      expect(state.data.settings.fullModePin, isNull);
    });

    testWidgets('a different second PIN, a weak PIN, or the same PIN again is refused, and nothing is counted',
        (tester) async {
      final state = flow.makeState();
      await _open(tester, state, _change);
      await flow.tapIn(tester, _change);
      await _fill(tester, _built, _newPin, '246814');
      expect(find.textContaining('The new PIN and the second one are different'), findsOneWidget);
      await _fill(tester, _built, '123456');
      expect(find.textContaining('cannot be a straight run'), findsOneWidget);
      await _fill(tester, _built, '000000');
      expect(find.textContaining('cannot be one digit six times'), findsOneWidget);
      await _fill(tester, _built, _built);
      expect(find.textContaining('the same as the current one'), findsOneWidget);
      expect(state.data.settings.fullModePin, isNull);
      expect(state.data.settings.fullModeFails, 0);
      await tester.tap(find.byKey(const Key('change_pin_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change_pin_current')), findsNothing);
    });

    testWidgets('a build without a key says the PIN is set by the build and offers no change', (tester) async {
      final keep = flow.testKey;
      flow.testKey = const FullModeKey(salt: '', fingerprint: '');
      final state = flow.makeState();
      flow.testKey = keep;
      final line = find.byKey(const Key('change_pin_unavailable'));
      await _open(tester, state, line);
      expect(_change, findsNothing);
      expect(find.textContaining('set up when the app is built'), findsOneWidget);
    });

    testWidgets('the PIN boxes on Linux reach the input method as passwords, digits only', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _open(tester, flow.makeState(), _change);
        await flow.tapIn(tester, _change);
        for (final key in ['change_pin_current', 'change_pin_new', 'change_pin_confirm']) {
          final box = find.byKey(Key(key));
          await tester.tap(box);
          await tester.pump();
          final args = tester.testTextInput.setClientArgs!;
          expect((args['inputType'] as Map)['name'], 'TextInputType.visiblePassword', reason: key);
          expect(args['obscureText'], isTrue, reason: key);
          await tester.enterText(box, '12ab34');
          expect(tester.widget<TextField>(box).controller!.text, '1234', reason: key);
        }
        await tester.tap(find.byKey(const Key('change_pin_cancel')));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the dialog fits a small phone with the keyboard up and large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final state = flow.makeState();
      await flow.pumpScreen(tester, state, const SettingsScreen());
      tester.view.physicalSize = const Size(640, 1136); // 320 by 568 points
      tester.view.devicePixelRatio = 2;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(_change, 300, scrollable: find.byType(Scrollable).first);
      await flow.tapIn(tester, _change);
      tester.view.viewInsets = const FakeViewPadding(bottom: 520);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('change_pin_current')), findsOneWidget);
    });
  });
}
