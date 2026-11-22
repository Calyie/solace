// Round 6 flows: the owner's support card (owner, 2026-11-15, OWNER-C1: talk first, support inline) and the round 6
// review F fixes beyond the reviewer's own proof tests in test/review6f (F6-03, F6-04, F6-09, F6-10, F6-18).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/check_in_guard.dart';
import 'package:solace/core/crisis.dart' show crisisChecked;
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/help_me_start.dart';
import 'package:solace/ui/theme.dart';

import 'audit_followups_test.dart' as a;
import 'owasp_fixes_test.dart' as o;

const crisis = 'I want to kill myself tonight.';
const worry = "There's no way out of this for me anymore."; // left to the classifier by the rules
const sheet = 'You matter, and support is here';

SessionController session(AppData data, {ModelRuntime model = const StandInModel(),
        Future<bool> Function(String, String)? riskCheck, DateTime Function()? clock}) =>
    SessionController(model: model, prompts: o.prompts, data: data, vault: MemoryVault(), riskCheck: riskCheck,
        clock: clock ?? () => DateTime(2026, 11, 15, 9));

int crises(AppData d) => d.safetyEvents.where((e) => e['level'] == 'crisis').length;

/// Writes the note and the story it is given at End.
class NoteModel extends StandInModel {
  const NoteModel(this.note, this.story);
  final String note, story;
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) => asksForNote(messages)
      ? Stream.value(note) : asksForRecord(messages) ? Stream.value(story) : super.generate(messages, maxTokens: maxTokens);
}

Future<void> pumpTall(WidgetTester tester, AppState state, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 6000); // the whole conversation laid out at once
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: screen)));
  await tester.pumpAndSettle();
}

void main() {
  group('OWNER-C1: where the support card sits in the conversation', () {
    test('a crisis in a sent message: right after that message, so her reply follows it', () async {
      final data = AppData();
      final s = session(data);
      await s.start('daily_checkin');
      await s.send(crisis);
      expect(s.crisisCount, 1);
      expect(crises(data), 1);
      expect(data.safetyWatch, isNotNull, reason: 'the record and the watch are as before');
      expect(s.crisisCards, [2]);
      expect(s.turns[1], ('person', crisis));
      expect(s.turns[2].$1, 'therapist', reason: 'the reply comes after the card');
    });

    test('a crisis sent during a reply: after the reply being written; sent again later, no second card', () async {
      final data = AppData();
      final model = o.GatedModel();
      final s = session(data, model: model);
      await s.start('daily_checkin');
      model.hold();
      final first = s.send('Work was hard today.');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(s.busy, isTrue);
      await expectLater(s.send(crisis), throwsA(isA<SessionBusy>()));
      expect(s.crisisCards, [3], reason: 'after the reply still being written');
      model.release();
      await first;
      expect(s.turns[2].$1, 'therapist');
      await s.send(crisis); // the same words, sent now: acted on already
      expect(s.crisisCount, 1);
      expect(s.crisisCards, [3], reason: 'not shown again for the same crisis');
    });

    test('a classifier worry adds no card (owner, 2026-11-15); a crisis after it does, once', () async {
      final data = AppData();
      final s = session(data, riskCheck: (c, t) async => true);
      await s.start('daily_checkin');
      await s.send(worry);
      expect(s.crisisCards, isEmpty);
      await s.readLeftUnsent(['I want to die.']);
      expect(s.crisisCount, 1);
      expect(s.crisisCards, hasLength(1));
    });

    test('"Still struggling" at the opening check: after her opening words', () async {
      final data = AppData()..safetyWatch = {'since': DateTime(2026, 11, 13).toIso8601String(), 'reason': 'x'};
      final s = session(data);
      await s.start('daily_checkin');
      expect(s.openingCheck, isTrue);
      s.answerOpeningCheck('struggling');
      expect(s.crisisCards, [1]);
      expect(data.safetyWatch?['reason'], 'still struggling at the opening check');
    });
  });

  group('OWNER-C1: the card on screen', () {
    testWidgets('in the chat: after the message, her reply below it, nothing over the chat; More support and the '
        'safety plan are one tap away', (tester) async {
      final state = o.makeState();
      await pumpTall(tester, state, const ChatScreen(kind: 'daily_checkin'));
      await tester.enterText(find.byType(TextField), crisis);
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      expect(find.text(sheet), findsNothing);
      final card = find.byKey(const Key('crisis_card'));
      expect(card, findsOneWidget);
      final said = find.descendant(of: find.byType(MessageBubble), matching: find.text(crisis));
      expect(tester.getTopLeft(card).dy, greaterThanOrEqualTo(tester.getBottomLeft(said).dy));
      expect(tester.getTopLeft(find.byType(MessageBubble).last).dy, greaterThanOrEqualTo(tester.getBottomLeft(card).dy),
          reason: 'her reply follows the card');
      expect(find.descendant(of: card, matching: find.text('Numbers checked on $crisisChecked.')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('crisis_card_plan')));
      await tester.pumpAndSettle();
      expect(find.text('My safety plan'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crisis_card_more')));
      await tester.pumpAndSettle();
      expect(find.text(sheet), findsOneWidget);
    });

    testWidgets('with a safety plan the card offers to open it', (tester) async {
      final state = o.makeState();
      state.data.safetyPlan.add('people', 'Sam, my brother', '2026-11-14');
      await pumpTall(tester, state, const ChatScreen(kind: 'daily_checkin'));
      await tester.enterText(find.byType(TextField), crisis);
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('crisis_card_plan')), matching: find.text('Open my safety plan')),
          findsOneWidget);
    });

    testWidgets('while another screen covers the session, a crisis opens the full support screen as before',
        (tester) async {
      final state = o.makeState();
      final s = state.newSession();
      await s.start('daily_checkin');
      await o.pumpScreen(tester, state, CallScreen(kind: 'daily_checkin', controller: s));
      unawaited(Navigator.of(tester.element(find.byType(CallScreen))).push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('another screen')))));
      await tester.pumpAndSettle();
      s.readUnsent(crisis);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text(sheet), findsOneWidget);
      expect(s.crisisCards, isNotEmpty, reason: 'and the card is in the conversation when the person comes back');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with the app out of sight, a crisis opens the full support screen as before', (tester) async {
      final state = o.makeState();
      final s = state.newSession();
      await s.start('daily_checkin');
      await o.pumpScreen(tester, state, CallScreen(kind: 'daily_checkin', controller: s));
      void go(List<AppLifecycleState> states) {
        for (final st in states) {
          tester.binding.handleAppLifecycleStateChanged(st);
        }
      }

      go([AppLifecycleState.resumed, AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      s.readUnsent(crisis); // say, words a call had caught as the app went out of sight
      await tester.pump();
      go([AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]); // the person comes back
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text(sheet), findsOneWidget, reason: 'found while out of sight: the full screen is there on return');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on a call the card stays while the call is on what raised it, and goes after two more messages',
        (tester) async {
      final state = o.makeState();
      final s = state.newSession();
      await s.start('daily_checkin');
      await o.pumpScreen(tester, state, CallScreen(kind: 'daily_checkin', controller: s));
      await s.send(crisis);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crisis_card'), skipOffstage: false), findsOneWidget);
      expect(find.text(sheet), findsNothing);
      await s.send('Thank you, I will think about calling them.');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crisis_card'), skipOffstage: false), findsOneWidget);
      await s.send('Can we talk about something else for a bit?');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crisis_card'), skipOffstage: false), findsNothing);
      expect(s.crisisCards, [2], reason: 'still part of the session, shown in the chat');
      await tester.pumpWidget(const SizedBox());
    });
  });

  // F6-03 and F6-04 (superseded 2026-11-15, owner): there is no question to carry; a classifier worry leaves any watch
  // exactly as it was, in a session and in Help me start
  test('F6-03: a classifier worry leaves the watch as it was', () async {
    final earlier = {'since': DateTime(2026, 11, 12, 9).toIso8601String(), 'reason': 'suicide'};
    final data = AppData()..safetyWatch = Map.of(earlier);
    final s = session(data, riskCheck: (c, t) async => true);
    await s.start('daily_checkin');
    s.answerOpeningCheck('better');
    await s.send(worry);
    expect(data.safetyWatch, earlier);
    final none = AppData();
    final t = session(none, riskCheck: (c, t) async => true);
    await t.start('daily_checkin');
    await t.send(worry);
    expect(none.safetyWatch, isNull);
  });

  testWidgets('F6-04: Help me start starts no watch', (tester) async {
    final state = a.makeState(model: const a.SplittingModel());
    state.useRiskCheck((context, text) async => true, 'test classifier');
    await a.pumpScreen(tester, state, const HelpMeStartScreen(task: 'reply to the landlord'));
    await tester.tap(find.byKey(const Key('help_split')));
    await tester.pumpAndSettle();
    expect(state.data.safetyWatch, isNull);
    expect(find.text('Open the email from the landlord'), findsOneWidget);
  });

  group('F6-10: only the words already acted on are skipped', () {
    Future<(AppData, SessionController)> flagged() async {
      final data = AppData();
      final verdict = Completer<bool>();
      final s = session(data, riskCheck: (c, t) => verdict.future);
      await s.start('daily_checkin');
      final sent = s.send('Work was a lot this week.');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await expectLater(s.send(crisis), throwsA(isA<SessionBusy>()));
      verdict.complete(false);
      await sent;
      return (data, s);
    }

    test('the same words: not twice; with ordinary words beside them: nothing new', () async {
      final (data, s) = await flagged();
      expect(await s.readLeftUnsent([crisis]), isFalse);
      expect(await s.readLeftUnsent([crisis, 'I might go for a walk later.']), isFalse);
      expect(crises(data), 1);
    });

    test('a new crisis beside them is read and recorded', () async {
      final (data, s) = await flagged();
      expect(await s.readLeftUnsent([crisis, 'I took 30 tablets an hour ago.']), isTrue);
      expect(crises(data), 2);
    });
  });

  group('F6-09: links, notes and stories', () {
    test('web and e-mail addresses are caught; everyday dots are not', () {
      for (final s in ['Visit www.example.org for more.', 'You could look at samaritans.org tonight.',
          'Email jo@samaritans.org any time.', 'See ftp://example.org/help.', 'Mind.org.uk has a page on this.',
          'Try (befrienders.org) instead.', 'The forum at talk.example.com helps.']) {
        expect(linkInReply(s), isTrue, reason: s);
      }
      for (final s in ['For example, e.g. a walk.', 'The U.S. is far.', 'It was 3.5 hours.', 'At 7 a.m. I woke.',
          'She has a Ph.D. in it.', 'That is a lot.It helps.', 'I hear you.Can we slow down?', 'Open notes.txt now.',
          'Well...maybe.', 'Message @samaritans on social media.', 'It is 10.30 now.', 'I feel lost.Is that okay?']) {
        expect(linkInReply(s), isFalse, reason: s);
      }
      final groups = <String>[];
      final screen = ReplyScreen(onBlocked: groups.add);
      expect(screen.pass('Try www.example.org tonight. '), '$phoneFallback ');
      expect(groups, [linkGroup]);
    });

    test('the note: a means, a phone number and a link become plain lines; the rest stays', () {
      final groups = <String>[];
      final out = screenWritten('Session: they talked about work. Practise the breathing.\n'
          'Homework: call 116 123 if it gets heavy. Walk daily.\n'
          'Safety: they said an overdose of 40 paracetamol would be enough.\n'
          'Notes: they found samaritans.org useful.', onBlocked: groups.add);
      expect(out, 'Session: they talked about work. Practise the breathing.\n'
          '$writtenNumberLine Walk daily.\n'
          '$writtenMeansLine\n'
          '', reason: 'a second address in the same note is left out, the line with it');
      expect(groups.toSet(), {phoneGroup, 'overdose', linkGroup});
      expect(screenWritten('An ordinary note.\nHomework: walk.'), 'An ordinary note.\nHomework: walk.');
    });

    test('End screens the note and the story before they are kept, and records only the rule group', () async {
      final data = AppData();
      final s = session(data, model: const NoteModel(
          'Summary: work was hard. Homework: call 988 when it gets heavy. Breathe slowly.',
          'Hard moments: an overdose of 40 paracetamol would be enough.\nWhat helps: walking.'));
      await s.start('daily_checkin');
      await s.send('Work was hard today.');
      await s.end();
      expect(s.note, isNot(contains('988')));
      expect(s.note, contains(writtenNumberLine));
      expect(s.note, contains('Breathe slowly.'));
      expect(data.lastNote, s.note);
      expect(data.sessions.single.note, s.note);
      expect(data.story.asText(), isNot(contains('paracetamol')));
      expect(data.story.asText(), contains('walking'));
      expect(data.safetyEvents.where((e) => e['level'] == 'output').map((e) => e['reason']).toSet(),
          {phoneGroup, 'overdose'});
    });

    testWidgets('the summary shows this session\'s own note only: none off the record', (tester) async {
      final state = o.makeState();
      state.data.lastNote = 'An earlier note about the tram.';
      final s = state.newSession();
      await s.start('daily_checkin', offRecord: true);
      await s.send('Work was hard today.');
      final parsed = await s.end();
      await o.pumpScreen(tester, state, Scaffold(body: SessionSummary(controller: s, parsed: parsed)));
      expect(find.text('Session note'), findsNothing);
      expect(find.textContaining('tram'), findsNothing);
    });
  });

  test('F6-18: End never runs beside a reply; it works once the reply is done', () async {
    final data = AppData();
    final verdict = Completer<bool>();
    final s = session(data, riskCheck: (c, t) => verdict.future);
    await s.start('daily_checkin');
    final sent = s.send('Work was a lot this week.');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.busy, isTrue);
    await expectLater(s.end(), throwsA(isA<SessionBusy>()));
    expect(s.busy, isTrue);
    expect(s.ending, isFalse);
    expect(data.sessions, isEmpty);
    verdict.complete(false);
    await sent;
    await s.end();
    expect(data.sessions, hasLength(1));
    expect(data.sessions.single.turns, hasLength(3));
  });
}
