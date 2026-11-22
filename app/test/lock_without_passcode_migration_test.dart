// Owner, 2026-11-15: Solace never uses the device's own unlock (by face, touch or the device's passcode), for anything;
// the app lock and every "confirm it is you" use only Solace's own six-digit passcode. A phone or Mac that had the
// lock on with the device's own unlock saved the lock on with no app passcode. That saved state must never lock the
// person out, and must not force a passcode screen on opening either (anyone holding the phone could set one): it is
// read as lock off (core/store.dart Settings.fromJson), Settings says plainly that the lock now uses Solace's own
// passcode and needs one set, and turning the lock on chooses one.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/home.dart';

import 'app_flow_test.dart' as flow;

/// Lets real time pass until [done] (the Argon2id passcode hash does real work).
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  const hash = {'salt': 'c2FsdHNhbHRzYWx0c2FsdA==', 'hash': 'aGFzaGhhc2hoYXNoaGFzaGhhc2hoYXNoaGFzaA=='};

  group('reading saved settings', () {
    test('the lock saved on with no app passcode reads as off, and Settings is told it needs one', () {
      final s = Settings.fromJson({'app_lock': true, 'passcode': null});
      expect(s.appLock, isFalse);
      expect(s.lockNeedsPasscode, isTrue);
      final again = Settings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(again.appLock, isFalse, reason: 'saved again, it stays off');
      expect(again.lockNeedsPasscode, isTrue, reason: 'and the note stays until a passcode is set');
    });

    test('the lock saved on with an app passcode by this version stays on, with no note', () {
      final s = Settings.fromJson({'app_lock': true, 'passcode': hash, 'lock_passcode_only': true});
      expect(s.appLock, isTrue);
      expect(s.lockNeedsPasscode, isFalse);
      expect(Settings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>).appLock, isTrue,
          reason: 'this version marks what it saves');
    });

    // round 9 final, 9B-12: before 2026-11-15 a passcode saved on a phone or Mac could be an old, unused one (the lock
    // opened with the device's own unlock), so a lock saved then needs a new passcode there; on Linux it was the unlock
    for (final p in [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS]) {
      test('${p.name}: the lock saved on with an app passcode by an earlier version reads as off, needing a new one',
          () {
        debugDefaultTargetPlatformOverride = p;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final s = Settings.fromJson({'app_lock': true, 'passcode': hash});
        expect(s.appLock, isFalse);
        expect(s.lockNeedsPasscode, isTrue);
        expect(s.passcode, isNull, reason: 'the stale passcode goes');
      });
    }

    test('linux: the lock saved on with an app passcode by an earlier version stays on (it was always the unlock)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = Settings.fromJson({'app_lock': true, 'passcode': hash});
      expect(s.appLock, isTrue);
      expect(s.lockNeedsPasscode, isFalse);
      expect(s.passcode, hash);
    });

    test('the lock saved off stays off, with no note', () {
      final s = Settings.fromJson({'app_lock': false});
      expect(s.appLock, isFalse);
      expect(s.lockNeedsPasscode, isFalse);
    });

    test('the note belongs to this device: an import keeps this device\'s own', () {
      expect(importInto(AppData()..settings.lockNeedsPasscode = true, AppData()).settings.lockNeedsPasscode, isTrue);
      expect(importInto(AppData(), AppData()..settings.lockNeedsPasscode = true).settings.lockNeedsPasscode, isFalse);
    });
  });

  testWidgets('a saved lock with no app passcode: Solace opens, no passcode screen; Settings says the lock needs a '
      'passcode now; turning it on chooses one', (tester) async {
    final vault = MemoryVault();
    final state = flow.makeState(vault: vault);
    // the store as a phone that used its own unlock left it, read through the real load path
    final saved = state.data.toJson();
    (saved['settings'] as Map<String, dynamic>)
      ..['app_lock'] = true
      ..remove('passcode')
      ..remove('lock_needs_passcode');
    state.data = AppData.fromJson(jsonDecode(jsonEncode(saved)) as Map<String, dynamic>);

    await flow.pumpApp(tester, state);
    expect(find.text('Solace is locked'), findsNothing, reason: 'never locked out');
    expect(find.byKey(const Key('lock_code')), findsNothing);
    expect(find.byKey(const Key('passcode_first')), findsNothing, reason: 'no passcode screen forced on opening');
    expect(find.byType(HomeShell), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab_You')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final note = find.byKey(const Key('lock_needs_passcode'));
    await tester.ensureVisible(note);
    await tester.pumpAndSettle();
    expect(find.text('The lock now uses Solace\'s own passcode'), findsOneWidget);
    expect(find.textContaining('off until you choose a six-digit passcode'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('app_lock'))).value, isFalse);

    // with the lock off nothing is asked before a privacy change
    await flow.tapIn(tester, find.byKey(const Key('hide_switcher')));
    await _until(tester, () => !state.data.settings.hideInSwitcher);
    expect(find.byKey(const Key('confirm_passcode')), findsNothing);
    expect(state.data.settings.hideInSwitcher, isFalse);

    // turning the lock on chooses Solace's own passcode
    await flow.tapIn(tester, find.byKey(const Key('app_lock')));
    expect(find.text('Choose a six-digit passcode'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('passcode_first')), '246801');
    await tester.enterText(find.byKey(const Key('passcode_second')), '246801');
    await tester.tap(find.byKey(const Key('passcode_understood'))); // round 9 final, 9A-10
    await tester.pump();
    await tester.tap(find.byKey(const Key('passcode_save')));
    await _until(tester, () => state.data.settings.appLock);
    expect(state.data.settings.appLock, isTrue);
    expect(state.data.settings.passcode, isNotNull);
    expect(state.data.settings.lockNeedsPasscode, isFalse);
    expect(note, findsNothing, reason: 'the note has done its work');
    final kept = (await vault.load()).settings;
    expect(kept.appLock, isTrue);
    expect(kept.passcode, isNotNull);
    expect(kept.lockNeedsPasscode, isFalse);
  });

  testWidgets('the lock on in memory with no app passcode never shows the lock screen (lockIsOn)', (tester) async {
    final state = flow.makeState();
    state.data.settings
      ..appLock = true
      ..passcode = null;
    await flow.pumpApp(tester, state);
    expect(find.text('Solace is locked'), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
