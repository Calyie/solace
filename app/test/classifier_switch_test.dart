// Owner, 2026-11-15: "create a feature to enable/disable off the safety classifier. It should use the same 6 digit pin
// as deep work mode. The classifier should be on by default but can be disabled in the settings." The trained safety
// classifier is on for a new install and for data saved by any earlier version; turning the Safety check off in
// Settings needs the deep work mode key, checked by the same FullModeKey and sharing its wrong-key count and pause;
// turning it on needs nothing. Off, it is never loaded; turned off, it is let go at once; each device keeps its own
// choice when data is brought in from another; Delete everything puts it back on.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/full_mode_lock.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/main.dart' show loadSafetyClassifier;
import 'package:solace/ui/settings.dart';

import 'app_flow_test.dart' as flow;

final _tile = find.byKey(const Key('classifier_switch'));

Future<void> _openSettings(WidgetTester tester, AppState state) async {
  await flow.pumpScreen(tester, state, const SettingsScreen());
  await tester.scrollUntilVisible(_tile, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester) => tester.widget<SwitchListTile>(_tile).value;

/// Types [pin] in the PIN box and presses Turn off; the key check runs outside the test's simulated clock.
Future<void> _tryPin(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(const Key('classifier_pin')), pin);
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('classifier_pin_ok')));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

/// A loaded classifier stand-in, so the tests can see whether it is let go.
void _useFake(AppState state) => state.useRiskCheck((c, t) async => false, 'ready', close: () async {});

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  test('on by default: a new install, data from earlier versions, and the never-released switch saved off', () {
    expect(AppData().settings.classifierOn, isTrue);
    expect(AppData.fromJson({...AppData().toJson()}..['settings'] = {}).settings.classifierOn, isTrue,
        reason: 'data from a version before the switch: on');
    expect(AppData.fromJson({...AppData().toJson()}..['settings'] = {'classifier_on': false}).settings.classifierOn,
        isTrue, reason: 'the never-released build saved it off by default: on now');
    final off = AppData()..settings.classifierOn = false;
    final json = off.toJson();
    expect((json['settings'] as Map)['safety_check_on'], isFalse);
    expect((json['settings'] as Map).containsKey('classifier_on'), isFalse);
    expect(AppData.fromJson(jsonDecode(jsonEncode(json))).settings.classifierOn, isFalse,
        reason: 'turned off with the key, it stays off after a restart');
  });

  test('on, it is loaded at start (here the test has no files folder, so it says it could not be)', () async {
    final state = flow.makeState();
    await loadSafetyClassifier(state);
    expect(state.safetyStatus, isNot(classifierOffStatus));
    expect(state.safetyStatus, contains('could not be loaded'));
  });

  test('off, the classifier is never loaded', () async {
    final state = flow.makeState()..data.settings.classifierOn = false;
    await loadSafetyClassifier(state);
    expect(state.riskCheck, isNull);
    expect(state.safetyStatus, classifierOffStatus);
  });

  test('turned off, the classifier is let go at once and Settings says so', () async {
    final state = flow.makeState();
    var closed = 0;
    state.useRiskCheck((c, t) async => true, 'ready', close: () async => closed++);
    await state.stopRiskCheck();
    expect(state.riskCheck, isNull);
    expect(closed, 1);
    expect(state.safetyStatus, classifierOffStatus);
  });

  test('a session open when it is turned off stops asking it at the next message', () async {
    final state = flow.makeState();
    var asked = 0;
    state.useRiskCheck((c, t) async {
      asked++;
      return false;
    }, 'ready');
    final s = state.newSession();
    await s.start('daily_checkin');
    await s.send('Work was long today.');
    final before = asked;
    expect(before, greaterThan(0));
    await state.stopRiskCheck();
    await s.send('And I skipped lunch.');
    expect(asked, before);
  });

  test('a transfer keeps this device\'s own choice, either way', () {
    final on = importInto(AppData()..settings.classifierOn = true, AppData()..settings.classifierOn = false);
    expect(on.settings.classifierOn, isTrue);
    final off = importInto(AppData()..settings.classifierOn = false, AppData()..settings.classifierOn = true);
    expect(off.settings.classifierOn, isFalse);
  });

  test('Delete everything puts it back on', () async {
    final vault = MemoryVault();
    final state = flow.makeState(vault: vault)..data.settings.classifierOn = false;
    await state.save();
    await state.wipeEverything(folders: () async {});
    expect(state.data.settings.classifierOn, isTrue);
    expect((await vault.load()).settings.classifierOn, isTrue);
    expect(state.safetyStatus, classifierMissingStatus, reason: 'its files went too, so it is not on this device');
  });

  group('the switch in Settings', () {
    testWidgets('on at first, and says what it does', (tester) async {
      await _openSettings(tester, flow.makeState());
      expect(_switchValue(tester), isTrue);
      expect(find.text('Safety check'), findsOneWidget);
      expect(find.textContaining('Turning it off needs your deep work PIN'), findsOneWidget);
    });

    testWidgets('cancelling the PIN leaves it on, loaded, and counts nothing', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      await vault.save(state.data);
      _useFake(state);
      await _openSettings(tester, state);
      await flow.tapIn(tester, _tile);
      expect(find.byKey(const Key('classifier_pin')), findsOneWidget);
      await tester.tap(find.byKey(const Key('classifier_pin_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('classifier_pin')), findsNothing);
      expect(_switchValue(tester), isTrue);
      expect(state.data.settings.classifierOn, isTrue);
      expect(state.data.settings.fullModeFails, 0);
      expect(state.riskCheck, isNotNull);
      expect((await vault.load()).settings.classifierOn, isTrue);
    });

    testWidgets('a wrong PIN, or none, leaves it on and counts a wrong key, saved', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      await vault.save(state.data);
      _useFake(state);
      await _openSettings(tester, state);
      await flow.tapIn(tester, _tile);
      await _tryPin(tester, '135791');
      expect(state.data.settings.classifierOn, isTrue);
      expect(state.data.settings.fullModeFails, 1);
      expect((await vault.load()).settings.fullModeFails, 1, reason: 'a restart does not reset the count');
      expect(find.text('That PIN is not right. 4 tries left before a pause.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('classifier_pin'))).controller!.text, isEmpty,
          reason: 'the PIN is not kept in the box');
      await _tryPin(tester, ''); // Turn off with no PIN typed is a try, as it is for deep work mode
      expect(state.data.settings.fullModeFails, 2);
      expect(find.text('That PIN is not right. 3 tries left before a pause.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('classifier_pin_cancel')));
      await tester.pumpAndSettle();
      expect(_switchValue(tester), isTrue);
      expect(state.riskCheck, isNotNull);
      expect(jsonEncode(state.data.toJson()), isNot(contains('135791')), reason: 'no PIN is ever stored');
    });

    testWidgets('the right PIN turns it off, saves, lets the classifier go and resets the count', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      await vault.save(state.data);
      var closed = 0;
      state.useRiskCheck((c, t) async => false, 'ready', close: () async => closed++);
      await _openSettings(tester, state);
      await flow.tapIn(tester, _tile);
      await _tryPin(tester, '135791');
      await _tryPin(tester, '135790');
      expect(find.byKey(const Key('classifier_pin')), findsNothing);
      expect(_switchValue(tester), isFalse);
      expect(state.data.settings.classifierOn, isFalse);
      expect((await vault.load()).settings.classifierOn, isFalse);
      expect(state.data.settings.fullModeFails, 0);
      expect((await vault.load()).settings.fullModeFails, 0);
      expect(state.riskCheck, isNull);
      expect(closed, 1);
      expect(state.safetyStatus, classifierOffStatus);
      // the wrong PIN before it is told, as deep work mode tells it (OWASP review OW-A09-1)
      expect(find.textContaining('a wrong deep work PIN was entered 1 time'), findsOneWidget);
      expect(jsonEncode(state.data.toJson()), isNot(contains('135790')), reason: 'no PIN is ever stored');
    });

    testWidgets('turning it back on needs no PIN, saves and loads it again', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault)..data.settings.classifierOn = false;
      await vault.save(state.data);
      await _openSettings(tester, state);
      expect(_switchValue(tester), isFalse);
      await tester.runAsync(() async {
        await tester.tap(_tile);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('classifier_pin')), findsNothing);
      expect(_switchValue(tester), isTrue);
      expect(state.data.settings.classifierOn, isTrue);
      expect((await vault.load()).settings.classifierOn, isTrue);
      expect(state.safetyStatus, isNot(classifierOffStatus), reason: 'it was asked to load again');
    });

    testWidgets('after the deep work limit of wrong PINs it stays on and says until when', (tester) async {
      final state = flow.makeState();
      _useFake(state);
      await _openSettings(tester, state);
      await flow.tapIn(tester, _tile);
      for (var i = 0; i < fullModeTries; i++) {
        await _tryPin(tester, '000000');
      }
      expect(state.data.settings.fullModeFails, fullModeTries);
      const line = 'Too many wrong PINs. The safety check cannot be turned off until 19:45.'; // the clock says 19:30
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(line)), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('classifier_pin_ok'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('classifier_pin_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('classifier_message')), findsOneWidget);
      expect(find.text(line), findsOneWidget);
      // tapped again while paused: no PIN box, still on
      await flow.tapIn(tester, _tile);
      expect(find.byKey(const Key('classifier_pin')), findsNothing);
      expect(_switchValue(tester), isTrue);
      expect(state.data.settings.classifierOn, isTrue);
      expect(state.riskCheck, isNotNull);
      // the pause is deep work mode's own: its key is paused too
      final deep = find.widgetWithText(TextButton, 'Deep work mode');
      await tester.scrollUntilVisible(deep, 300, scrollable: find.byType(Scrollable).first);
      await flow.tapIn(tester, deep);
      await tester.enterText(find.byKey(const Key('full_mode_key')), '135790');
      await flow.tapIn(tester, find.text('I understand, turn on deep work mode'));
      expect(find.textContaining('Too many wrong keys. Try again in'), findsOneWidget);
      expect(state.data.settings.mode, 'normal');
    });

    testWidgets('wrong deep work keys count toward the same pause', (tester) async {
      final state = flow.makeState()..data.settings.fullModeFails = fullModeTries - 1;
      await _openSettings(tester, state);
      final deep = find.widgetWithText(TextButton, 'Deep work mode');
      await tester.scrollUntilVisible(deep, 300, scrollable: find.byType(Scrollable).first);
      await flow.tapIn(tester, deep);
      await tester.enterText(find.byKey(const Key('full_mode_key')), '135791');
      final button = find.text('I understand, turn on deep work mode');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400)); // clear of the foot of the screen
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(button);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(state.data.settings.fullModeFails, fullModeTries);
      await tester.scrollUntilVisible(_tile, -200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Too many wrong PINs. The safety check cannot be turned off until 19:45.'), findsOneWidget);
      await flow.tapIn(tester, _tile);
      expect(find.byKey(const Key('classifier_pin')), findsNothing);
      expect(state.data.settings.classifierOn, isTrue);
    });

    testWidgets('a build without the deep work key cannot turn it off, and says so', (tester) async {
      final keep = flow.testKey;
      flow.testKey = const FullModeKey(salt: '', fingerprint: '');
      final state = flow.makeState();
      flow.testKey = keep;
      await _openSettings(tester, state);
      await flow.tapIn(tester, _tile);
      expect(find.byKey(const Key('classifier_pin')), findsNothing);
      expect(state.data.settings.classifierOn, isTrue);
      expect(find.textContaining('has no deep work PIN to turn it off with'), findsOneWidget);
    });

    testWidgets('the PIN box on Linux reaches the input method as a password, digits only', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _openSettings(tester, flow.makeState());
        await flow.tapIn(tester, _tile);
        final box = find.byKey(const Key('classifier_pin'));
        await tester.tap(box);
        await tester.pump();
        final args = tester.testTextInput.setClientArgs!;
        expect((args['inputType'] as Map)['name'], 'TextInputType.visiblePassword');
        expect(args['obscureText'], isTrue);
        await tester.enterText(box, '12ab34');
        expect(tester.widget<TextField>(box).controller!.text, '1234');
        await tester.tap(find.byKey(const Key('classifier_pin_cancel')));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('the PIN box fits a small phone with the keyboard up and large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = flow.makeState();
    await flow.pumpScreen(tester, state, const SettingsScreen());
    tester.view.physicalSize = const Size(640, 1136); // 320 by 568 points, the smallest phone
    tester.view.devicePixelRatio = 2;
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(_tile, 200, scrollable: find.byType(Scrollable).first);
    await flow.tapIn(tester, _tile);
    tester.view.viewInsets = const FakeViewPadding(bottom: 520); // the keyboard, 260 points
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('classifier_pin')), findsOneWidget);
    await tester.tap(find.byKey(const Key('classifier_pin_cancel')));
    await tester.pumpAndSettle();
  });

  test('the pause end in plain words', () {
    final now = DateTime(2026, 11, 26, 19, 30);
    expect(pauseEndWords(DateTime(2026, 11, 26, 19, 45), now), '19:45');
    expect(pauseEndWords(DateTime(2026, 11, 26, 19, 45, 20), now), '19:46', reason: 'never before the pause ends');
    expect(pauseEndWords(DateTime(2026, 11, 27, 8, 15), now), '08:15 tomorrow');
    expect(pauseEndWords(DateTime(2026, 11, 29, 8, 15), now), contains('08:15 on'));
  });
}
