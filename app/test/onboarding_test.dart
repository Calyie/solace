// The first-run steps (ui/onboarding.dart) and the app lock (ui/app_lock.dart): a new person is told what Solace is
// and is not, confirms they are an adult (or is shown lines for young people and cannot go on), picks the country,
// the presence and the voice, and is offered the lock; Support opens from every step. The lock opens only with the
// right passcode, keeps Support reachable, and locks again after time away.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/home.dart';
import 'package:solace/ui/onboarding.dart';

import 'app_flow_test.dart' as flow;

/// Lets real (not fake) time pass until [done], for the Argon2id passcode hash, which does real work.
Future<void> waitFor(WidgetTester tester, bool Function() done, {int tries = 60}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  test('the device region picks a country the crisis screen knows', () {
    expect(countryForRegion('IE'), 'Ireland');
    expect(countryForRegion('gb'), 'United Kingdom');
    expect(countryForRegion('US'), 'United States');
    expect(countryForRegion('DE'), isNull);
    expect(countryForRegion(null), isNull);
  });

  testWidgets('a new person goes through the first-run steps and lands on Today', (tester) async {
    final state = flow.makeState(chosen: false);
    state.data.settings
      ..onboarded = false
      ..ageConfirmed = false;
    await flow.pumpApp(tester, state);
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.text('Welcome to Solace'), findsOneWidget);
    await flow.shot('32_first_run_welcome');
    await tapKey(tester, 'onb_next');
    expect(find.text('Private by design'), findsOneWidget);
    expect(find.textContaining('aeroplane mode'), findsOneWidget);
    await tapKey(tester, 'onb_next');
    expect(find.text('What Solace is, and is not'), findsOneWidget);
    expect(find.textContaining('It is an AI'), findsOneWidget);
    expect(find.textContaining('cannot diagnose'), findsOneWidget);
    await flow.shot('33_first_run_what_solace_is');
    await tapKey(tester, 'onb_understand');
    // the test device's region is the United States, so the United States comes first
    expect(state.data.settings.country, 'United States');
    expect(find.textContaining('988'), findsOneWidget);
    await tapKey(tester, 'onb_country');
    await tester.tap(find.text('Ireland').last);
    await tester.pumpAndSettle();
    expect(state.data.settings.country, 'Ireland');
    expect(find.textContaining('1800 247 247'), findsOneWidget);
    await tapKey(tester, 'onb_next');
    expect(state.data.settings.ageConfirmed, isFalse);
    await tapKey(tester, 'onb_adult');
    expect(state.data.settings.ageConfirmed, isTrue);
    expect(find.text('How Solace looks and sounds'), findsOneWidget);
    await tapKey(tester, 'presence_abstract');
    expect(state.data.settings.presence, 'abstract');
    await flow.shot('34_first_run_look_and_voice');
    await tapKey(tester, 'onb_next');
    // while no model is in place, the files are offered, and may be skipped (owner, 2026-11-16)
    expect(find.text("Add Solace's model files"), findsOneWidget);
    await tapKey(tester, 'onb_model_skip');
    expect(find.text('Keep it just for you'), findsOneWidget);
    await tapKey(tester, 'onb_finish');
    expect(state.data.settings.onboarded, isTrue);
    expect(state.data.settings.therapistChosen, isTrue);
    expect(state.data.settings.appLock, isFalse);
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    // the steps are kept: a later start opens on Today
    expect(state.data.settings.toJson()['onboarded'], isTrue);
  });

  testWidgets('under 18: lines for young people, and no way on', (tester) async {
    final state = flow.makeState(chosen: false);
    state.data.settings
      ..onboarded = false
      ..ageConfirmed = false;
    await flow.pumpApp(tester, state);
    for (final k in ['onb_next', 'onb_next', 'onb_understand']) {
      await tapKey(tester, k);
    }
    await tapKey(tester, 'onb_country');
    await tester.tap(find.text('Canada').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'onb_next');
    await tapKey(tester, 'onb_under18');
    expect(find.text('Solace is made for adults'), findsOneWidget);
    expect(find.text('Kids Help Phone'), findsOneWidget);
    expect(find.text('1-800-668-6868'), findsOneWidget);
    expect(find.byKey(const Key('onb_next')), findsNothing);
    expect(find.byKey(const Key('onb_adult')), findsNothing);
    expect(state.data.settings.ageConfirmed, isFalse);
    expect(state.data.settings.onboarded, isFalse);
    await tapKey(tester, 'onb_wrong');
    expect(find.byKey(const Key('onb_adult')), findsOneWidget);
  });

  testWidgets('Support opens from the first step, before anything is chosen', (tester) async {
    final state = flow.makeState(chosen: false);
    state.data.settings.onboarded = false;
    await flow.pumpApp(tester, state);
    await tester.tap(find.byKey(const Key('onb_support')));
    await tester.pumpAndSettle();
    expect(find.byType(CrisisSheet), findsOneWidget);
  });

  testWidgets('the lock offered at the end: a six-digit passcode, on every device', (tester) async {
    final state = flow.makeState(chosen: false);
    state.data.settings
      ..onboarded = false
      ..ageConfirmed = false;
    await flow.pumpApp(tester, state);
    for (final k in ['onb_next', 'onb_next', 'onb_understand', 'onb_next', 'onb_adult', 'onb_next', 'onb_model_skip']) {
      await tapKey(tester, k);
    }
    await tapKey(tester, 'onb_lock');
    await tester.enterText(find.byKey(const Key('passcode_first')), '24680');
    await tester.enterText(find.byKey(const Key('passcode_second')), '24680');
    await tester.tap(find.byKey(const Key('passcode_save')));
    await tester.pumpAndSettle();
    expect(find.text('Use exactly six digits.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('passcode_first')), '246801');
    await tester.enterText(find.byKey(const Key('passcode_second')), '246801');
    // round 9 final, 9A-10: the warning that a forgotten passcode cannot be recovered is ticked before it is saved
    await tester.tap(find.byKey(const Key('passcode_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please tick the box first'), findsOneWidget);
    expect(state.data.settings.appLock, isFalse);
    await tester.ensureVisible(find.byKey(const Key('passcode_understood')));
    await tester.tap(find.byKey(const Key('passcode_understood')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('passcode_save')));
    await waitFor(tester, () => state.data.settings.onboarded);
    expect(state.data.settings.appLock, isTrue);
    expect(state.data.settings.passcode, isNotNull);
    expect(state.data.settings.passcode.toString(), isNot(contains('246801')));
    expect(find.byType(HomeShell), findsOneWidget);
  });

  group('the lock', () {
    late Map<String, String> stored;
    setUpAll(() async => stored = await hashPasscode('135791'));

    test('a passcode is checked against its salted hash, never kept as typed', () async {
      expect(await passcodeMatches('135791', stored), isTrue);
      expect(await passcodeMatches('135790', stored), isFalse);
      expect(stored.values.join(), isNot(contains('135791')));
      expect(isPasscode('12345'), isFalse);
      expect(isPasscode('12345a'), isFalse);
      expect(isPasscode('123456'), isTrue);
    });

    testWidgets('opens only with the right passcode; Support stays reachable; locks again after time away',
        (tester) async {
      final state = flow.makeState();
      state.data.settings
        ..appLock = true
        ..lockAfterMinutes = 0
        ..passcode = stored;
      await flow.pumpApp(tester, state);
      expect(find.text('Solace is locked'), findsOneWidget);
      expect(find.byType(HomeShell, skipOffstage: true), findsNothing);
      await tester.tap(find.byKey(const Key('lock_support')));
      await tester.pumpAndSettle();
      expect(find.byType(CrisisSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(CrisisSheet))).pop();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock_code')), '000000');
      await tester.tap(find.byKey(const Key('lock_unlock')));
      await waitFor(tester, () => find.text('That passcode did not match. Try again.').evaluate().isNotEmpty);
      expect(find.text('Solace is locked'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('lock_code')), '135791');
      await tester.tap(find.byKey(const Key('lock_unlock')));
      await waitFor(tester, () => find.text('Solace is locked').evaluate().isEmpty);
      expect(find.text('Solace is locked'), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      // the wrong try before this unlock is told, never silent (OWASP OW-A09-1)
      expect(find.textContaining('1 wrong passcode was tried'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lock_tries_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lock_tries_notice')), findsNothing);
      // away and back: locked again (lock after: at once), and the switcher cover while away
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Solace'), findsWidgets); // the cover shows only the name
      // a glance at the switcher (inactive, then back) is not leaving: no lock (and no prompt loop with "at once")
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Solace is locked'), findsNothing);
      for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
          AppLifecycleState.hidden, AppLifecycleState.inactive]) {
        tester.binding.handleAppLifecycleStateChanged(st);
        await tester.pump();
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Solace is locked'), findsOneWidget);
    });
  });

  // Audit F-09 had a lock with no way to confirm it is you stay locked. Since 2026-11-15 (owner) the app passcode is
  // the lock's only unlock, so a lock with no passcode (the device's own unlock before) reads as off and Solace opens:
  // never a lockout. test/lock_without_passcode_migration_test.dart checks the saved state and what Settings says.
  testWidgets('with the lock on but no app passcode, Solace opens: the lock is off, never a lockout', (tester) async {
    final state = flow.makeState();
    state.data.settings
      ..appLock = true
      ..passcode = null;
    await flow.pumpApp(tester, state);
    expect(find.text('Solace is locked'), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  test('wrong passcodes: a wait after five, doubling, kept in the store', () {
    final s = Settings();
    final t = DateTime(2026, 11, 14, 12);
    for (var i = 0; i < 4; i++) {
      recordLockFail(s, t);
    }
    expect(lockWait(s, t), isNull);
    recordLockFail(s, t);
    expect(lockWait(s, t), const Duration(seconds: 30));
    recordLockFail(s, t);
    expect(lockWait(s, t), const Duration(seconds: 60));
    for (var i = 0; i < 20; i++) {
      recordLockFail(s, t);
    }
    expect(lockWait(s, t), const Duration(hours: 1), reason: 'never more than an hour');
    expect(Settings.fromJson(s.toJson()).lockFails, s.lockFails);
    expect(lockWait(s, t.add(const Duration(hours: 2))), isNull);
  });
}
