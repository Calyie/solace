// Round 9 final verification (226c148): the lock after the owner's decision of 2026-11-15 (Solace's own passcode only,
// on every device).
// - 9A-09: a lock that used the device's own unlock reads as off until a passcode is chosen, and only Settings said
//   so. A one-time notice on Today now says it, with a way to choose one; Not now closes it for good on this device,
//   and an import never carries that.
// - 9A-10: a forgotten passcode cannot be got back, so choosing one says so, and it is saved only once the person has
//   ticked that they understand.
// - 9B-12: a passcode saved by an earlier version on a phone or Mac may be stale (turning the lock off kept it), so
//   such a lock reads as off and needing a new passcode (Linux keeps it: it was always the unlock there); turning the
//   lock off now clears the passcode; and "Forgotten your passcode?" on the lock screen leads only to Delete
//   everything, after DELETE is typed.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/desktop.dart' show appNavigatorKey;
import 'package:solace/ui/home.dart';
import 'package:solace/ui/onboarding.dart';
import 'package:solace/ui/settings.dart';

import 'app_flow_test.dart' as flow;

const _code = '482916';
const _stale = {'salt': 'c2FsdHNhbHRzYWx0c2FsdA==', 'hash': 'aGFzaGhhc2hoYXNoaGFzaGhhc2hoYXNoaGFzaA=='};

/// Lets real time pass until [done] (the Argon2id passcode hash and Delete everything do real work).
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// [state]'s data as an earlier version saved it: no `lock_passcode_only` mark, the lock on, and [passcode] (none for
/// a phone or Mac that used the device's own unlock), read back through the real load path.
void _savedByEarlierVersion(AppState state, {Map<String, String>? passcode}) {
  final saved = state.data.toJson();
  (saved['settings'] as Map<String, dynamic>)
    ..['app_lock'] = true
    ..['passcode'] = passcode
    ..remove('lock_passcode_only')
    ..remove('lock_needs_passcode')
    ..remove('lock_notice_closed');
  state.data = AppData.fromJson(jsonDecode(jsonEncode(saved)) as Map<String, dynamic>);
}

final _notice = find.byKey(const Key('lock_notice'));

Future<void> _choose(WidgetTester tester, String code) async {
  expect(find.text('Choose a six-digit passcode'), findsOneWidget);
  await tester.enterText(find.byKey(const Key('passcode_first')), code);
  await tester.enterText(find.byKey(const Key('passcode_second')), code);
  await tester.ensureVisible(find.byKey(const Key('passcode_understood')));
  await tester.tap(find.byKey(const Key('passcode_understood')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('passcode_save')));
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
  setUp(forgetLockWaitForTest);

  group('9A-09: the notice on Today', () {
    testWidgets('a lock that used the device\'s own unlock: Solace opens, Today says the lock is off; Not now closes '
        'it for good', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      _savedByEarlierVersion(state);
      await flow.pumpApp(tester, state);
      expect(find.text('Solace is locked'), findsNothing, reason: 'never locked out');
      expect(find.byKey(const Key('passcode_first')), findsNothing, reason: 'nothing forced on opening');
      expect(find.byType(HomeShell), findsOneWidget);
      expect(_notice, findsOneWidget);
      expect(find.text('The lock is off until you choose a passcode for Solace'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lock_notice_close')));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      expect(state.data.settings.lockNoticeClosed, isTrue);
      expect(state.data.settings.lockNeedsPasscode, isTrue, reason: 'Settings still says the lock needs one');
      final kept = await vault.load();
      expect(kept.settings.lockNoticeClosed, isTrue, reason: 'saved, so it does not come back at the next start');

      final again = flow.makeState(vault: vault)..data = kept;
      await tester.pumpWidget(const SizedBox());
      await flow.pumpApp(tester, again);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(_notice, findsNothing, reason: 'closed once, it stays closed');
    });

    testWidgets('Choose a passcode opens the passcode steps; once chosen the lock is on and the notice is gone',
        (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      _savedByEarlierVersion(state);
      await flow.pumpApp(tester, state);
      await tester.tap(find.byKey(const Key('lock_notice_choose')));
      await tester.pumpAndSettle();
      expect(find.text(forgottenPasscodeWarning), findsOneWidget, reason: 'the warning comes with it (9A-10)');
      await _choose(tester, '246801');
      await _until(tester, () => state.data.settings.appLock);
      expect(lockIsOn(state.data.settings), isTrue);
      expect(state.data.settings.lockNeedsPasscode, isFalse);
      expect(_notice, findsNothing);
      expect((await vault.load()).settings.lockNeedsPasscode, isFalse);
    });

    testWidgets('no notice with the lock simply off or with the lock on; shown only while it needs a passcode',
        (tester) async {
      await flow.pumpApp(tester, flow.makeState());
      expect(_notice, findsNothing, reason: 'the lock simply off (or a fresh start): nothing to say');
      final on = flow.makeState();
      on.data.settings
        ..lockNeedsPasscode = true
        ..appLock = true
        ..lockAfterMinutes = 15
        ..passcode = passcode;
      await tester.pumpWidget(const SizedBox());
      await flow.pumpApp(tester, on);
      expect(_notice, findsNothing, reason: 'the lock is on: nothing to say (nor anything shown under the lock)');
      await tester.pumpWidget(const SizedBox());
      await flow.pumpApp(tester, flow.makeState()..data.settings.lockNeedsPasscode = true);
      expect(_notice, findsOneWidget, reason: 'control: the lock off and needing a passcode shows it');
    });

    test('the notice closed is this device\'s own: an import never carries it', () {
      expect(importInto(AppData()..settings.lockNoticeClosed = true, AppData()).settings.lockNoticeClosed, isTrue);
      expect(importInto(AppData(), AppData()..settings.lockNoticeClosed = true).settings.lockNoticeClosed, isFalse);
    });
  });

  group('9A-10: choosing the passcode', () {
    testWidgets('says a forgotten passcode cannot be recovered; nothing is saved until that is ticked; Cancel saves '
        'nothing', (tester) async {
      String? chosen = 'not yet';
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
          onPressed: () async => chosen = await choosePasscode(context), child: const Text('choose')))));
      await tester.tap(find.text('choose'));
      await tester.pumpAndSettle();
      expect(find.textContaining('nobody can open Solace or get your data back, not even by reinstalling'),
          findsOneWidget);
      expect(find.textContaining('Keep it somewhere safe'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('passcode_first')), '246801');
      await tester.enterText(find.byKey(const Key('passcode_second')), '246801');
      await tester.tap(find.byKey(const Key('passcode_save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Please tick the box first'), findsOneWidget);
      expect(chosen, 'not yet', reason: 'not saved before the warning is acknowledged');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(chosen, isNull, reason: 'Cancel chooses nothing');

      await tester.tap(find.text('choose'));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('passcode_understood'))).value, isFalse,
          reason: 'asked afresh each time');
      await _choose(tester, '135791');
      await tester.pumpAndSettle();
      expect(chosen, '135791');
    });
  });

  group('9B-12: a stale passcode never locks the owner out', () {
    testWidgets('an earlier version\'s lock with a passcode, on a phone or the Mac: Solace opens, with the notice',
        (tester) async {
      final state = flow.makeState();
      _savedByEarlierVersion(state, passcode: _stale);
      expect(state.data.settings.appLock, isFalse);
      expect(state.data.settings.passcode, isNull);
      expect(state.data.settings.lockNeedsPasscode, isTrue);
      await flow.pumpApp(tester, state);
      expect(find.text('Solace is locked'), findsNothing);
      expect(find.byKey(const Key('lock_code')), findsNothing);
      expect(_notice, findsOneWidget);
    }, variant: TargetPlatformVariant(const {TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS}));

    testWidgets('the same on Linux keeps the lock: the passcode was always the unlock there', (tester) async {
      final state = flow.makeState();
      _savedByEarlierVersion(state, passcode: passcode);
      expect(lockIsOn(state.data.settings), isTrue);
      expect(state.data.settings.lockNeedsPasscode, isFalse);
      await flow.pumpApp(tester, state);
      expect(find.text('Solace is locked'), findsOneWidget);
      expect(_notice, findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('turning the lock off clears its passcode; on again chooses a new one', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(vault: vault);
      state.data.settings
        ..appLock = true
        ..passcode = passcode;
      await flow.pumpScreen(tester, state, const SettingsScreen());
      await flow.tapIn(tester, find.byKey(const Key('app_lock')));
      await tester.enterText(find.byKey(const Key('confirm_passcode')), _code);
      await tester.tap(find.byKey(const Key('confirm_passcode_ok')));
      await _until(tester, () => !state.data.settings.appLock);
      expect(state.data.settings.appLock, isFalse);
      expect(state.data.settings.passcode, isNull);
      final kept = (await vault.load()).settings;
      expect(kept.appLock, isFalse);
      expect(kept.passcode, isNull, reason: 'gone from the device too');
      await flow.tapIn(tester, find.byKey(const Key('app_lock')));
      expect(find.byKey(const Key('passcode_first')), findsOneWidget, reason: 'a new passcode is chosen');
    });

    testWidgets('Forgotten your passcode?: Cancel deletes nothing; DELETE typed deletes everything and starts the '
        'first-run steps', (tester) async {
      final vault = MemoryVault();
      final state = flow.makeState(demo: true, vault: vault);
      state.data.settings
        ..appLock = true
        ..lockAfterMinutes = 0
        ..passcode = passcode;
      await vault.save(state.data);
      final sessions = state.data.sessions.length;
      expect(sessions, greaterThan(0));
      await flow.pumpApp(tester, state);
      expect(find.text('Solace is locked'), findsOneWidget);
      // a screen left open under the lock
      appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Solace is locked'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lock_forgot')));
      await tester.pumpAndSettle();
      final delete = find.byKey(const Key('forgot_delete'));
      expect(tester.widget<FilledButton>(delete).onPressed, isNull, reason: 'nothing can be deleted before DELETE');
      await tester.enterText(find.byKey(const Key('forgot_typed')), 'delete it');
      await tester.pump();
      expect(tester.widget<FilledButton>(delete).onPressed, isNull);
      expect(find.byKey(const Key('lock_support')), findsOneWidget, reason: 'Support stays on the lock screen');
      await tester.tap(find.byKey(const Key('forgot_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forgot_typed')), findsNothing);
      expect(state.data.sessions, hasLength(sessions), reason: 'Cancel deletes nothing');
      expect((await vault.load()).sessions, hasLength(sessions));
      expect(lockIsOn(state.data.settings), isTrue);
      expect(find.text('Solace is locked'), findsOneWidget, reason: 'and opens nothing');
      expect(state.data.settings.lockFails, 0, reason: 'and is not a passcode try');

      await tester.tap(find.byKey(const Key('lock_forgot')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('forgot_typed')), 'DELETE');
      await tester.pump();
      await tester.tap(delete);
      await _until(tester, () => state.data.sessions.isEmpty && find.byType(OnboardingFlow).evaluate().isNotEmpty);
      expect(state.data.sessions, isEmpty);
      expect(state.data.settings.onboarded, isFalse);
      expect(state.data.settings.passcode, isNull);
      expect(lockIsOn(state.data.settings), isFalse);
      expect((await vault.load()).sessions, isEmpty, reason: 'deleted from the device');
      expect(find.text('Solace is locked'), findsNothing);
      expect(find.byType(OnboardingFlow), findsOneWidget, reason: 'Solace starts again at its first-run steps');
      expect(find.byType(SettingsScreen), findsNothing, reason: 'the screen left under the lock is gone');
      expect(find.byType(HomeShell), findsNothing);
    });
  });
}
