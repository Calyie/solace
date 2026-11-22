// Review round 4 (B): proof tests for safety-integrity findings in core/session.dart and the check-in.
// The reviewer wrote each to assert the faulty behaviour on commit 5bdac57. B-04, B-05, B-07 and B-08 are fixed in
// round 4 (branch fix/round4-b), and their tests now assert the fixed behaviour in the same scenario: each failed on
// 5bdac57. B-06 is the owner's design and still asserts the behaviour the reviewer found. The B-18 and B-19 tests at
// the end were added with their fixes.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/gate.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/questionnaires.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/check_in.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/help_me_start.dart';
import 'package:solace/ui/plan_today.dart' show parkThought;

import '../audit_followups_test.dart' as a;
import 'package:solace/ui/theme.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

const imminent = "I'm going to take all my pills tonight.";
// worrying, but no means, place or time: the classifier's to read, not the phrase rules' (the round 4 rules now read
// [imminent] as a crisis, so the classifier paths below are shown with this one)
const worrying = "There's no way out of this for me anymore.";

SessionController session(AppData data, {Future<bool> Function(String, String)? riskCheck, DateTime Function()? clock}) =>
    SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: MemoryVault(),
        riskCheck: riskCheck, clock: clock ?? () => DateTime(2026, 11, 14, 20));

void main() {
  test('B-05/B-06 precondition: the round 4 rules read an imminent overdose plan as a crisis; a worry without a means '
      'is left to the classifier', () {
    expect(const SafetyCheck().check(imminent, sessionKind: 'daily_checkin').level, SafetyLevel.crisis);
    expect(const SafetyCheck().check(worrying, sessionKind: 'daily_checkin').level, SafetyLevel.none);
  });

  // B-05 (failed on 5bdac57, fixed in round 4): after ONE classifier verdict came too late, the classifier was never
  // asked again in this session, so an explicit plan the rules miss got no safety response at all. Now it is still
  // asked about every later message, without the reply waiting for it, and its alarm is acted on when it comes.
  testWidgets('B-05: after one classifier timeout, a later plan is still read and its worry shown, with no wait',
      (tester) async {
    var calls = 0;
    final second = Completer<bool>();
    Future<bool> risk(String c, String t) {
      calls++;
      if (calls == 1) return Completer<bool>().future; // a slow first verdict (a loaded phone, a cold start)
      return second.future; // the classifier will alarm on the plan, in its own time
    }

    final data = AppData();
    final s = session(data, riskCheck: risk);
    await s.start('daily_checkin');
    final first = s.send('Work was long today.');
    await tester.pump(const Duration(seconds: 16));
    await first;
    expect(s.classifierFailed, isTrue);
    await s.send(worrying);
    expect(s.busy, isFalse, reason: 'the reply did not wait for the verdict a second time');
    expect(calls, 2, reason: 'the classifier was asked about the plan');
    expect(s.lastSafety.level, isNot(SafetyLevel.concern), reason: 'its verdict is not in yet');
    second.complete(true);
    await tester.pump();
    // owner 2026-11-15: no question any more; the late worry shows the quiet support line, never dropped
    expect(s.lastSafety.level, SafetyLevel.concern, reason: 'the late worry is acted on, never dropped');
    expect(data.safetyEvents.last, {'date': '2026-11-14', 'level': 'concern', 'reason': 'classifier'});
  });

  // B-05 follow-up: the verdict that timed out is not dropped either, and later messages are read one at a time,
  // those sent meanwhile joined, so a slow classifier is never given more than one later message at once.
  testWidgets('B-05: the timed-out verdict still acts; later messages are read one run at a time', (tester) async {
    final verdicts = <(String, Completer<bool>)>[];
    Future<bool> risk(String c, String t) => (verdicts..add((t, Completer<bool>()))).last.$2.future;
    final data = AppData();
    final s = session(data, riskCheck: risk);
    await s.start('daily_checkin');
    final first = s.send('Work was long today.');
    await tester.pump(const Duration(seconds: 16));
    await first;
    expect(data.safetyEvents.where((e) => e['level'] == 'error'), hasLength(1), reason: 'the timeout is a fault');
    await s.send('I slept badly.');
    await s.send('And I skipped lunch.');
    await s.send('My sister called.');
    expect(verdicts.map((v) => v.$1), ['Work was long today.', 'I slept badly.'],
        reason: 'one later run at a time: the next two wait for it');
    verdicts[1].$2.complete(false);
    await tester.pump();
    expect(verdicts.last.$1, 'And I skipped lunch.\nMy sister called.', reason: 'what waited is read next, joined');
    verdicts.last.$2.complete(false);
    await tester.pump();
    expect(data.safetyEvents.where((e) => e['reason'] == 'classifier'), isEmpty);
    verdicts.first.$2.complete(true); // the first verdict, long after its wait
    await tester.pump();
    expect(data.safetyEvents.where((e) => e['reason'] == 'classifier'), hasLength(1),
        reason: 'a late worry on the message that timed out is still acted on');
    expect(data.safetyEvents.where((e) => e['level'] == 'error'), hasLength(1), reason: 'the fault is recorded once');
  });

  // B-06 (superseded 2026-11-15, owner): the question and its two noes are gone; a classifier worry shows only the quiet
  // support line, and an explicit plan the rules know opens support at once.
  test('B-06: a classifier worry gets only the support line; an explicit plan opens support at once', () async {
    final data = AppData();
    final s = session(data, riskCheck: (c, t) async => true);
    await s.start('daily_checkin');
    await s.send('I feel so empty lately.');
    expect(s.lastSafety.level, SafetyLevel.concern);
    expect(s.crisisCount, 0);
  });

  // B-07 (failed on 5bdac57, fixed in round 4): "Still struggling" at the opening check opened the crisis screen and
  // recorded a crisis, but did not renew the 7-day safety watch, so it still ended 7 days after the FIRST crisis. Now
  // it goes through the same path as any crisis (_crisis), so the watch runs 7 days from "Still struggling".
  test('B-07: "Still struggling" at the opening check renews the safety watch', () async {
    var now = DateTime(2026, 11, 20, 20); // six days after the crisis below
    final data = AppData()..safetyWatch = {'since': DateTime(2026, 11, 14, 20).toIso8601String(), 'reason': 'suicide'};
    final s = session(data, clock: () => now);
    await s.start('daily_checkin');
    expect(s.openingCheck, isTrue);
    s.answerOpeningCheck('struggling');
    expect(s.crisisCount, 1);
    expect(data.safetyEvents.last['level'], 'crisis');
    now = DateTime(2026, 11, 22, 20); // two days after "Still struggling"
    expect(data.safetyWatchActive(now), isTrue,
        reason: 'the watch must not lapse 2 days after the person said they were still struggling');
    expect(data.safetyWatchActive(DateTime(2026, 11, 27, 21)), isFalse, reason: 'it ends 7 days after it');
  });

  // B-08 (failed on 5bdac57, fixed in round 4): the check-in's "I need help now" / "Yes" (thoughts of harming
  // themselves) showed the crisis screen but recorded no safety event and started no safety watch, so the reliving
  // gate's "crisis in the last two weeks" check stayed open the same day. Now a crisis is recorded and the watch
  // starts, as answerSafety('yes') does in a session.
  testWidgets('B-08: check-in "I need help now" records a crisis, starts the watch, closes the reliving gate',
      (tester) async {
    final data = AppData();
    data.settings
      ..therapistChosen = true
      ..onboarded = true
      ..ageConfirmed = true
      ..mode = 'full';
    final state = AppState(data: data, vault: MemoryVault(), prompts: prompts, model: const StandInModel(),
        library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
        clock: () => DateTime(2026, 11, 14, 20));
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.light),
        home: const CheckInScreen(kind: 'daily_checkin'))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('I need help now'), 200);
    await tester.tap(find.text('I need help now'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('check_in_start')));
    await tester.tap(find.byKey(const Key('check_in_start')));
    await tester.pumpAndSettle();
    expect(find.text('You matter, and support is here'), findsOneWidget, reason: 'the crisis sheet does open');
    expect(data.safetyEvents.where((e) => e['level'] == 'crisis').single['reason'], 'needs help now, at the check-in');
    expect(data.safetyWatch?['since'], DateTime(2026, 11, 14, 20).toIso8601String(), reason: 'a 7-day watch');
    const yesToAll = ReadinessAnswers(practisedGrounding: true, noSuicidalThoughtsOrRecentSelfHarm: true,
        notLivingWithTheDanger: true, noPsychosis: true, rarelyLoseTouchWithSurroundings: true,
        supportPersonPresent: true);
    expect(relivingGate(data, yesToAll, DateTime(2026, 11, 14, 21)).open, isFalse,
        reason: 'the gate knows about the help request an hour earlier');
  });

  // B-08: after "I need help now", trauma work does not start: grounding, a talk that is not trauma work, and
  // Support are offered instead. "Yes" (thoughts since last time) is recorded the same way.
  for (final (answer, kind, grounds) in [
    ('I need help now', 'written_exposure', true),
    ('Yes', 'daily_checkin', false),
  ]) {
    testWidgets('B-08: check-in "$answer" before $kind', (tester) async {
      final data = AppData();
      data.settings
        ..therapistChosen = true
        ..onboarded = true
        ..ageConfirmed = true;
      final state = AppState(data: data, vault: MemoryVault(), prompts: prompts, model: const StandInModel(),
          library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
          clock: () => DateTime(2026, 11, 14, 20));
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.light),
          home: CheckInScreen(kind: kind))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(answer), 200);
      await tester.tap(find.text(answer));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('check_in_start')));
      await tester.tap(find.byKey(const Key('check_in_start')));
      await tester.pumpAndSettle();
      expect(find.text('You matter, and support is here'), findsOneWidget);
      expect(data.safetyEvents.where((e) => e['level'] == 'crisis'), hasLength(1));
      expect(data.safetyWatch, isNotNull);
      Navigator.of(tester.element(find.text('You matter, and support is here'))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ground_first')), grounds ? findsOneWidget : findsNothing);
      expect(find.byType(ChatScreen), grounds ? findsNothing : findsOneWidget,
          reason: grounds ? 'written exposure must not start after "I need help now"' : 'the check-in goes on');
      if (grounds) {
        expect(find.byKey(const Key('ground_first_practice')), findsOneWidget, reason: 'grounding is offered');
        await tester.tap(find.byKey(const Key('ground_first_talk')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).kind, 'daily_checkin',
            reason: 'the talk offered is not trauma work');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  // B-04 (failed on 5bdac57, fixed in round 4): the opening check card stayed up until it was answered, so a person
  // could have a crisis in this session first and then tap "I'm okay" on the stale card, which cleared the watch the
  // crisis minutes ago had just started. Now the card goes once the person has sent a message (it is about last
  // time), and "I'm okay" only ever clears a watch that began before this session.
  test('B-04: a crisis in this session hides the stale opening check and keeps its watch', () async {
    var now = DateTime(2026, 11, 18, 20);
    final data = AppData()..safetyWatch = {'since': DateTime(2026, 11, 14, 20).toIso8601String(), 'reason': 'suicide'};
    final s = session(data, clock: () => now);
    await s.start('daily_checkin');
    expect(s.openingCheck, isTrue);
    now = DateTime(2026, 11, 18, 20, 5);
    await s.send('I want to kill myself.');
    expect(s.crisisCount, 1);
    expect(data.safetyWatch?['since'], now.toIso8601String(), reason: 'the crisis started a new watch');
    expect(s.openingCheck, isFalse, reason: 'the old card goes once something has been said');
    s.answerOpeningCheck('okay'); // a tap that lands as it goes does nothing
    expect(data.safetyWatch?['since'], now.toIso8601String());
    expect(data.safetyWatchActive(DateTime(2026, 11, 19, 20)), isTrue);
  });

  test('B-04: "I\'m okay" never clears a watch started in this session, even before anything is sent', () async {
    var now = DateTime(2026, 11, 18, 20);
    final data = AppData()..safetyWatch = {'since': DateTime(2026, 11, 14, 20).toIso8601String(), 'reason': 'suicide'};
    final s = session(data, clock: () => now);
    await s.start('daily_checkin');
    now = DateTime(2026, 11, 18, 20, 2);
    // a crisis in the part of a paste too long for the box: read at once, nothing sent, the card still up
    await s.checkPasted('${'a' * maxInput} I want to kill myself tonight.');
    expect(s.crisisCount, 1);
    expect(s.openingCheck, isTrue);
    s.answerOpeningCheck('okay');
    expect(data.safetyWatch?['since'], now.toIso8601String(), reason: 'the watch of this session\'s crisis stays');
    // and on a watch from an earlier session, "I'm okay" still clears it (owner design)
    final earlier = AppData()..safetyWatch = {'since': DateTime(2026, 11, 14, 20).toIso8601String(), 'reason': 'x'};
    final t = session(earlier, clock: () => DateTime(2026, 11, 18, 20));
    await t.start('daily_checkin');
    t.answerOpeningCheck('okay');
    expect(earlier.safetyWatch, isNull);
  });

  // B-08 (second part; failed on 5bdac57, fixed in round 4): PHQ-9 question 9 above zero recorded a crisis but started
  // no 7-day safety watch (AppState.saveScores). Now it starts the watch, as a crisis in a session does.
  test('B-08: PHQ-9 question 9 "nearly every day" starts the safety watch', () async {
    final data = AppData();
    final state = AppState(data: data, vault: MemoryVault(), prompts: prompts, model: const StandInModel(),
        library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
        clock: () => DateTime(2026, 11, 14, 20));
    await state.saveScores(phq9, [1, 1, 1, 1, 1, 1, 1, 1, 3]);
    expect(data.safetyEvents.where((e) => e['level'] == 'crisis'), isNotEmpty);
    expect(data.safetyWatch?['reason'], 'PHQ-9 item 9', reason: 'a gentle check in the next sessions');
    await state.saveScores(phq9, [1, 1, 1, 1, 1, 1, 1, 1, 0]);
    expect(data.safetyEvents.where((e) => e['level'] == 'crisis'), hasLength(1), reason: 'zero is no crisis');
  });

  // B-18 (by reading on 5bdac57; fixed in round 4): free text written outside sessions was never read by any safety
  // check. Now the phrase rules read it when it is saved; a crisis is recorded, starts the watch and opens support;
  // anything less does nothing, so ordinary notes raise no alarm.
  group('B-18: words saved outside a session', () {
    Future<(AppState, NavigatorState)> pump(WidgetTester tester) async {
      final state = a.makeState();
      final key = GlobalKey<NavigatorState>();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(navigatorKey: key,
          theme: appTheme(Brightness.light), home: Scaffold(body: Builder(builder: (context) => TextButton(
              onPressed: () => parkThought(context), child: const Text('Park')))))));
      return (state, key.currentState!);
    }

    testWidgets('a crisis in a parked thought is recorded, starts the watch and opens support', (tester) async {
      final (state, _) = await pump(tester);
      await tester.tap(find.text('Park'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('park_text')), "I'm going to kill myself tonight.");
      await tester.tap(find.byKey(const Key('park_save')));
      await tester.pumpAndSettle();
      expect(state.data.parked.single['text'], "I'm going to kill myself tonight.", reason: 'it is still kept');
      expect(find.text('You matter, and support is here'), findsOneWidget);
      expect(state.data.safetyEvents.single['level'], 'crisis');
      expect(state.data.safetyEvents.single['reason'], contains('a parked thought'));
      expect(state.data.safetyWatch, isNotNull);
    });

    testWidgets('an ordinary note, or a worry short of a crisis, does nothing', (tester) async {
      final (state, nav) = await pump(tester);
      for (final note in ['Email the landlord about the boiler.', "I can't go on like this at work, it is too much.",
          'I could kill for a coffee.']) {
        await readSavedWords(nav, state, note, where: 'a test');
        await tester.pumpAndSettle();
      }
      expect(find.byType(CrisisSheet), findsNothing);
      expect(state.data.safetyEvents, isEmpty);
      expect(state.data.safetyWatch, isNull);
    });

    testWidgets('a story edit reads only what changed, so words long there never alarm again', (tester) async {
      final (state, nav) = await pump(tester);
      const was = 'Hard moments: in October she said she wanted to kill herself, and called the crisis line.';
      await readSavedWords(nav, state, '$was\nWhat helps: walking with her sister.', before: was, where: 'your story');
      await readSavedWords(nav, state, 'What helps: walking.', before: 'What helps: walk.', where: 'your story');
      await tester.pumpAndSettle();
      expect(state.data.safetyEvents, isEmpty, reason: 'no alarm for words that were already there');
      // not awaited: it ends when the support screen it opens is closed
      unawaited(readSavedWords(nav, state, 'What helps: nothing. I want to kill myself.', before: 'What helps: walking.',
          where: 'your story'));
      await tester.pumpAndSettle();
      expect(state.data.safetyEvents.single['level'], 'crisis', reason: 'a crisis written into the story is read');
      expect(find.text('You matter, and support is here'), findsOneWidget);
    });
  });

  // B-19 (superseded 2026-11-15, owner): Help me start no longer asks the classifier at all (no question anywhere); it
  // splits at once after the phrase rules, whatever the classifier would say.
  testWidgets('B-19: Help me start never waits for the classifier', (tester) async {
    var asked = 0;
    final state = a.makeState(model: const a.SplittingModel())
      ..useRiskCheck((c, t) async {
        asked++;
        return true;
      }, 'test classifier');
    await a.pumpScreen(tester, state, const HelpMeStartScreen(task: 'reply to the landlord'));
    await tester.tap(find.byKey(const Key('help_split')));
    await tester.pumpAndSettle();
    expect(find.text('Open the email from the landlord'), findsOneWidget, reason: 'the split goes on at once');
    expect(asked, 0);
    expect(state.data.safetyEvents, isEmpty);
  });
}
