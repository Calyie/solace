// Round 9 re-check, 9A-08: the confirm before a privacy change (ui/app_lock.dart confirmItIsYou, from 9A-02) must not
// keep the app lock from coming down after time away. Then it was a system prompt, and leaving the app at it was never
// time away. Since 2026-11-15 Solace asks only for its own six-digit passcode, in its own dialog, on every device
// (owner: never the device's own unlock, for anything), so no system prompt exists and nothing in AppLockGate waits
// for one: leaving the app at the passcode dialog is time away like any other, and once "Lock after" has passed the
// lock screen comes down over the dialog. Driven here with the passcode dialog open and the lock's clocks set by the
// test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/ui/app_lock.dart';

import 'app_flow_test.dart' as flow;

/// The app lock's clocks, moved by the test.
class _Clock extends LockClock {
  DateTime wallNow = DateTime(2026, 11, 15, 12);
  Duration monoNow = const Duration(hours: 3);
  @override
  DateTime wall() => wallNow;
  @override
  Duration monotonic() => monoNow;
  void pass(Duration d) {
    monoNow += d;
    wallNow = wallNow.add(d);
  }
}

const _code = '482916';
final _locked = find.text('Solace is locked');
final _lockSwitch = find.byKey(const Key('app_lock'));
final _box = find.byKey(const Key('confirm_passcode'));

/// Waits (real time: the Argon2 check does real work) until [done], pumping frames.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50)); // and the dialog's closing animation runs on
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
  late Map<String, String> passcode;
  setUpAll(() async => passcode = await hashPasscode(_code));

  late _Clock clock;
  setUp(() {
    clock = _Clock();
    lockClock = clock;
    forgetLockWaitForTest();
  });
  tearDown(() => lockClock = const LockClock());

  Future<void> life(WidgetTester tester, List<AppLifecycleState> states) async {
    for (final st in states) {
      tester.binding.handleAppLifecycleStateChanged(st);
      await tester.pump();
    }
  }

  const leave = [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
  const back = [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed];

  /// Solace open in Settings with the app lock on and its passcode set.
  Future<AppState> inSettings(WidgetTester tester, int minutes) async {
    final state = flow.makeState(demo: true);
    await flow.pumpApp(tester, state); // the lock off at the start, so it opens unlocked
    state.data.settings
      ..appLock = true
      ..passcode = passcode
      ..lockAfterMinutes = minutes;
    await tester.tap(find.byKey(const Key('tab_You')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(_lockSwitch, findsOneWidget);
    return state;
  }

  /// Taps "Lock Solace" off: Solace's own passcode dialog opens, never a system prompt.
  Future<void> askToTurnOff(WidgetTester tester) async {
    await flow.tapIn(tester, _lockSwitch);
    expect(_box, findsOneWidget);
    expect(find.text('Type your Solace passcode to turn the lock off.'), findsOneWidget);
  }

  /// Types [code] at the passcode dialog and presses Confirm.
  Future<void> confirm(WidgetTester tester, String code) async {
    await tester.enterText(_box, code);
    await tester.tap(find.byKey(const Key('confirm_passcode_ok')));
    await _until(tester, () => _box.evaluate().isEmpty ||
        find.byKey(const Key('confirm_passcode_message')).evaluate().isNotEmpty);
  }

  for (final minutes in [0, 1]) {
    testWidgets('the passcode dialog left open, back after two minutes: the lock screen comes down over it, and '
        'Cancel after unlocking changes nothing ("Lock after: $minutes")', (tester) async {
      final state = await inSettings(tester, minutes);
      await askToTurnOff(tester);
      await life(tester, leave); // Home, or the phone put down, at the dialog
      clock.pass(const Duration(minutes: 2));
      await life(tester, back); // someone opens Solace
      await tester.pumpAndSettle();
      expect(_locked, findsOneWidget, reason: 'the time away had passed "Lock after"');
      expect(_box, findsNothing, reason: 'the dialog is under the lock: nothing can be confirmed there');
      expect(_lockSwitch, findsNothing, reason: 'Settings is under the lock');
      expect(state.data.settings.appLock, isTrue);
      // the lock screen asks for the same passcode
      await tester.enterText(find.byKey(const Key('lock_code')), _code);
      await tester.tap(find.byKey(const Key('lock_unlock')));
      await _until(tester, () => _locked.evaluate().isEmpty);
      expect(_locked, findsNothing);
      expect(_box, findsOneWidget, reason: 'the dialog is still where it was left');
      await tester.tap(find.byKey(const Key('confirm_passcode_cancel')));
      await tester.pumpAndSettle();
      expect(state.data.settings.appLock, isTrue, reason: 'Cancel changed nothing');
    });
  }

  testWidgets('the passcode dialog left open, no Cancel: still locks on coming back (no prompt to wait for)',
      (tester) async {
    await inSettings(tester, 1);
    await askToTurnOff(tester);
    await life(tester, leave);
    clock.pass(const Duration(minutes: 2));
    await life(tester, back);
    await tester.pumpAndSettle();
    expect(_locked, findsOneWidget);
  });

  testWidgets('control: a glance at a notification at the dialog is not leaving: no lock ("at once"), and the '
      'right passcode then turns the lock off', (tester) async {
    final state = await inSettings(tester, 0);
    await askToTurnOff(tester);
    await life(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pumpAndSettle();
    expect(_locked, findsNothing);
    expect(_box, findsOneWidget);
    await confirm(tester, _code);
    await _until(tester, () => !state.data.settings.appLock);
    expect(state.data.settings.appLock, isFalse, reason: 'the confirmed change went through');
    expect(_locked, findsNothing);
  });

  testWidgets('control: less time away than "Lock after" (10 s of 1 minute): no lock, a wrong passcode changes '
      'nothing', (tester) async {
    final state = await inSettings(tester, 1);
    await askToTurnOff(tester);
    await life(tester, leave);
    clock.pass(const Duration(seconds: 10));
    await life(tester, back);
    await tester.pumpAndSettle();
    expect(_locked, findsNothing);
    expect(_box, findsOneWidget);
    await confirm(tester, '111111');
    expect(find.text('That passcode did not match. Try again.'), findsOneWidget);
    expect(state.data.settings.appLock, isTrue);
  });

  testWidgets('the lock screen on the iPhone, Android and the Mac: the app passcode box only, opened by the right '
      'passcode', (tester) async {
    final state = flow.makeState()
      ..data.settings.appLock = true
      ..data.settings.passcode = passcode
      ..data.settings.lockAfterMinutes = 0;
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(
        builder: (context, child) => AppLockGate(child: child!), home: const Scaffold(body: Text('under the lock')))));
    await tester.pumpAndSettle();
    expect(_locked, findsOneWidget);
    expect(find.text('Enter your six-digit passcode.'), findsOneWidget);
    expect(find.byKey(const Key('lock_code')), findsOneWidget);
    expect(find.byIcon(Icons.fingerprint), findsNothing);
    await tester.enterText(find.byKey(const Key('lock_code')), _code);
    await tester.tap(find.byKey(const Key('lock_unlock')));
    await _until(tester, () => _locked.evaluate().isEmpty);
    expect(find.text('under the lock'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // the gate goes while this platform is still the one set (its timer)
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS}));
}
