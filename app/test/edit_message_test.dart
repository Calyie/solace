// Editing a sent message (owner, 2026-11-14: "you can also edit sent messages, but editing is limited to a 5-10
// minute window"): the person's latest message can be changed for 10 minutes; it and Solace's reply are replaced and
// the new words go through every safety check. A message that raised a safety step, the Stop of trauma work, and
// anything once the session has ended stay as they are.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/theme.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

const crisisSentence = 'I want to kill myself tonight.';

/// A clock the test moves on by hand.
class Clock {
  DateTime now = DateTime(2026, 11, 14, 20);
  void pass(Duration d) => now = now.add(d);
}

/// Answers each message by quoting it, so a test can see which words were answered.
class EchoModel extends StandInModel {
  EchoModel();
  Completer<void>? _gate;
  void hold() => _gate = Completer<void>();
  void release() => _gate?.complete();
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    final last = messages.last['content'] ?? '';
    if (last.startsWith('The session has ended') || last.startsWith('Update the person')) {
      yield* super.generate(messages, maxTokens: maxTokens);
      return;
    }
    final g = _gate;
    if (g != null) await g.future;
    yield 'You said: ${last.split('\n').last}';
  }
}

/// The phrase rules, except that a message containing BOOM makes them fail.
class FailingCheck extends SafetyCheck {
  const FailingCheck();
  @override
  SafetyResult check(String text, {required String sessionKind}) {
    if (text.contains('BOOM')) throw StateError('the rules failed');
    return super.check(text, sessionKind: sessionKind);
  }
}

SessionController session(Clock clock, {ModelRuntime? model, AppData? data, SafetyCheck safety = const SafetyCheck(),
        Future<bool> Function(String, String)? riskCheck}) =>
    SessionController(model: model ?? EchoModel(), prompts: prompts, data: data ?? AppData(), vault: MemoryVault(),
        clock: () => clock.now, safety: safety, riskCheck: riskCheck);

List<String> said(SessionController s) => [for (final (who, x) in s.turns) if (who == 'person') x];

AppState makeState(Clock clock, {ModelRuntime? model}) {
  final data = AppData();
  data.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  return AppState(data: data, vault: MemoryVault(), prompts: prompts, model: model ?? EchoModel(),
      library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()), clock: () => clock.now);
}

Future<void> pumpChat(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: const ChatScreen(kind: 'daily_checkin'))));
  await tester.pumpAndSettle();
}

Future<void> sendText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('Send'));
  await tester.pumpAndSettle();
}

String box(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  group('the session', () {
    test('the latest message can be changed: it and her reply are replaced, and the new words are answered',
        () async {
      final clock = Clock();
      final s = session(clock);
      await s.start('daily_checkin');
      await s.send('Work was hard todya.');
      expect(s.editBlocked(), isNull);
      await s.edit('Work was hard today.');
      expect(said(s), ['Work was hard today.']);
      expect(s.turns, hasLength(3));
      expect(s.turns.last, ('therapist', 'You said: Work was hard today.'));
      expect(s.editBlocked(), isNull, reason: 'the changed message can be changed again, within its own window');
    });

    test('only for 10 minutes after it was sent', () async {
      final clock = Clock();
      final s = session(clock);
      await s.start('daily_checkin');
      await s.send('Work was hard todya.');
      clock.pass(const Duration(minutes: 9, seconds: 59));
      expect(s.editBlocked(), isNull);
      clock.pass(const Duration(seconds: 2));
      expect(s.editBlocked(), EditClosed.tooLate);
      await expectLater(s.edit('Work was hard today.'), throwsA(isA<EditRefused>()));
      expect(said(s), ['Work was hard todya.'], reason: 'nothing changed');
      expect(s.turns, hasLength(3));
    });

    test('only the latest message; never while she is replying; never once the session has ended', () async {
      final clock = Clock();
      final model = EchoModel();
      final s = session(clock, model: model);
      await s.start('daily_checkin');
      await s.send('First thing.');
      await s.send('Second thing.');
      expect(s.lastTyped, 3);
      await s.edit('Second thing, put better.');
      expect(said(s), ['First thing.', 'Second thing, put better.']);
      model.hold();
      final reply = s.send('Third thing.');
      expect(s.editBlocked(), EditClosed.replying);
      model.release();
      await reply;
      expect(s.editBlocked(), isNull);
      model._gate = null;
      await s.end();
      expect(s.editBlocked(), EditClosed.ended);
    });

    test('a message that raised a safety step stays as it was said; the record and the watch are kept', () async {
      final clock = Clock();
      final data = AppData();
      final s = session(clock, data: data);
      await s.start('daily_checkin');
      await s.send(crisisSentence);
      expect(s.crisisCount, 1);
      expect(s.editBlocked(), EditClosed.flagged);
      await expectLater(s.edit('I am fine.'), throwsA(isA<EditRefused>()));
      expect(said(s), [crisisSentence]);
      expect(data.safetyEvents.where((e) => e['level'] == 'crisis'), hasLength(1));
      expect(data.safetyWatch, isNotNull);
    });

    test('the changed words go through every check: a crisis in an edit opens support and is recorded', () async {
      final clock = Clock();
      final data = AppData();
      final s = session(clock, data: data);
      await s.start('daily_checkin');
      await s.send('Work was hard.');
      await s.edit(crisisSentence);
      expect(s.crisisCount, 1);
      expect(data.safetyEvents.single['level'], 'crisis');
      expect(data.safetyWatch, isNotNull);
      expect(s.editBlocked(), EditClosed.flagged, reason: 'and from then on it stays as it was said');
    });

    // owner 2026-11-15: no safety question; a classifier worry (the quiet support line) does not lock the message
    test('a classifier worry leaves the message open to a change within the window', () async {
      final clock = Clock();
      final s = session(clock, riskCheck: (context, text) async => true);
      await s.start('daily_checkin');
      await s.send('I want to find my purpose.');
      expect(s.lastSafety.level, SafetyLevel.concern);
      expect(s.editBlocked(), isNull);
    });

    test('the Stop of trauma work is never taken back', () async {
      final clock = Clock();
      final s = session(clock);
      await s.start('written_exposure');
      await s.send('I am writing about that night.');
      await s.stopExercise();
      expect(said(s).last, 'Stop. I want to stop.');
      expect(s.lastTyped, isNull);
      expect(s.editBlocked(), EditClosed.ended);
      expect(s.paused, isTrue);
    });

    test("the app's own notes on a changed message go with it, and come back if the new words need them", () async {
      final clock = Clock();
      final s = session(clock);
      await s.start('daily_checkin');
      await s.send('Are you a real person?');
      expect(s.notices.map((n) => n.$2), contains(aiNotice));
      await s.edit('Work was hard today.');
      expect(s.notices, isEmpty);
      await s.edit('Am I talking to a bot?');
      expect(s.notices.map((n) => n.$2), contains(aiNotice));
    });

    test('a fault in the phrase rules never leaves the session busy: the change is answered and the fault recorded',
        () async {
      final clock = Clock();
      final data = AppData();
      final s = session(clock, data: data, safety: const FailingCheck());
      await s.start('daily_checkin');
      await s.send('Work was hard today.');
      await s.edit('BOOM, work was hard today.');
      expect(s.busy, isFalse);
      expect(said(s), ['BOOM, work was hard today.']);
      expect(s.turns.last.$1, 'therapist');
      expect(data.safetyEvents.single['reason'], 'rules StateError');
      await s.send('BOOM again');
      expect(s.busy, isFalse, reason: 'a plain send too');
    });

    test('an empty change does nothing', () async {
      final clock = Clock();
      final s = session(clock);
      await s.start('daily_checkin');
      await s.send('Work was hard today.');
      await s.edit('   ');
      expect(said(s), ['Work was hard today.']);
    });
  });

  group('the chat screen', () {
    testWidgets('a long press on the latest message offers Edit; the change replaces it and her reply',
        (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'Work was hard todya.');
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_editing')), findsOneWidget);
      expect(box(tester), 'Work was hard todya.');
      await sendText(tester, 'Work was hard today.');
      expect(find.byKey(const Key('chat_editing')), findsNothing);
      expect(find.text('Work was hard todya.'), findsNothing);
      expect(find.text('You said: Work was hard todya.'), findsNothing);
      expect(find.text('Work was hard today.'), findsOneWidget);
      expect(find.text('You said: Work was hard today.'), findsOneWidget);
    });

    testWidgets('Cancel leaves the message as it was and gives back what was being typed', (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'Work was hard todya.');
      await tester.enterText(find.byType(TextField), 'And then');
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      expect(box(tester), 'Work was hard todya.');
      await tester.tap(find.byKey(const Key('chat_edit_cancel')));
      await tester.pumpAndSettle();
      expect(box(tester), 'And then');
      expect(find.text('Work was hard todya.'), findsOneWidget);
      expect(find.byKey(const Key('chat_editing')), findsNothing);
    });

    testWidgets('what was being typed comes back after the change is sent', (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'Work was hard todya.');
      await tester.enterText(find.byType(TextField), 'And then');
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      await sendText(tester, 'Work was hard today.');
      expect(box(tester), 'And then');
    });

    testWidgets('after 10 minutes Edit explains why, and nothing changes', (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'Work was hard todya.');
      clock.pass(const Duration(minutes: 11));
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 minutes after you send it'), findsOneWidget);
      expect(find.byKey(const Key('chat_editing')), findsNothing);
      expect(box(tester), isEmpty);
    });

    testWidgets('a change sent after the 10 minutes ran out keeps the words, to send as a new message',
        (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'Work was hard todya.');
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      clock.pass(const Duration(minutes: 11));
      await sendText(tester, 'Work was hard today.');
      expect(box(tester), 'Work was hard today.');
      expect(find.textContaining('send them as a new message'), findsOneWidget);
      expect(find.text('Work was hard todya.'), findsOneWidget, reason: 'the sent message is as it was');
      expect(find.byKey(const Key('chat_editing')), findsNothing);
    });

    testWidgets('an earlier message offers no Edit on a phone, and the system\'s Copy (owner, 2026-11-19)',
        (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'First thing.');
      await sendText(tester, 'Second thing.');
      await tester.longPress(find.text('First thing.'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit_message')), findsNothing);
      expect(find.text('Copy'), findsOneWidget, reason: 'a long press selects and offers the standard Copy');
    });

    testWidgets('on a phone, a long press on the latest message offers Copy and Edit (owner, 2026-11-19)',
        (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'Work was hard todya.');
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('copy_message')), findsOneWidget);
      expect(find.byKey(const Key('edit_message')), findsOneWidget);
    });

    testWidgets('on a computer, right-click on the latest message offers Copy and Edit', (tester) async {
      final clock = Clock();
      final state = makeState(clock);
      await pumpChat(tester, state);
      await sendText(tester, 'Work was hard todya.');
      await tester.tap(find.byKey(const Key('latest_message')), buttons: 2);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('copy_message')), findsOneWidget);
      expect(find.byKey(const Key('edit_message')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
