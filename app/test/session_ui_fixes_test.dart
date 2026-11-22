// Verification round 3 follow-ups on the conversation screens: the trauma Stop (R3-7), Return while editing (R3-10),
// the edit window from the first send (R3-11), starters and the call keep typed words (L-3), Send before her first
// words (L-4), leaving a screen stops the reply (R3-4, the screen's part), a failing safety save is never silent
// (F-05), and the voice's sentence feed (L-2). Every test drives the app's own code.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/sherpa_voice.dart';
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

/// The first reply comes at once. After [hold], a reply says one sentence, then waits for [release]; it can be
/// stopped at once (ReplyCanceller), as the on-device model can.
class StepModel extends StandInModel implements ReplyCanceller {
  StepModel();
  Completer<void>? _gate;
  bool silent = false; // held before any words
  int cancels = 0, replies = 0;
  void hold({bool beforeWords = false}) {
    _gate = Completer<void>();
    silent = beforeWords;
  }

  void release() {
    if (!(_gate?.isCompleted ?? true)) _gate!.complete();
  }

  @override
  void cancelReply() {
    cancels++;
    release();
  }

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    replies++;
    final g = _gate;
    if (g == null) {
      yield 'Hello. How are you today? ';
      return;
    }
    if (!silent) yield 'That sounds really hard, thank you for telling me. ';
    await g.future;
    yield 'Tell me more about it.';
  }
}

/// A vault that counts saves and can be made to fail.
class CountingVault extends MemoryVault {
  int saves = 0;
  bool failing = false;
  @override
  Future<void> save(AppData data) async {
    saves++;
    if (failing) throw const FileSystemException('disk full');
    await super.save(data);
  }
}

class Clock {
  DateTime now = DateTime(2026, 11, 14, 20);
}

AppState makeState(StepModel model, {Vault? vault, Clock? clock}) {
  final data = AppData();
  data.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  final c = clock ?? Clock();
  return AppState(data: data, vault: vault ?? MemoryVault(), prompts: prompts, model: model,
      library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()), clock: () => c.now);
}

Future<void> pumpChat(WidgetTester tester, AppState state, String kind) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: ChatScreen(kind: kind))));
  await tester.pumpAndSettle();
}

String box(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;
int crises(AppState s) => s.data.safetyEvents.where((e) => e['level'] == 'crisis').length;
const pausedLine = "The exercise is paused. Let's come back to the present together first.";

void main() {
  testWidgets('R3-7: in trauma work the red Stop works during a reply, and the Stop by the box pauses the exercise',
      (tester) async {
    final model = StepModel();
    final state = makeState(model);
    await pumpChat(tester, state, 'written_exposure');
    model.hold();
    await tester.enterText(find.byType(TextField), 'I am writing about that night.');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('exercise_stop'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('chat_stop')));
    await tester.pumpAndSettle();
    expect(find.text(pausedLine), findsOneWidget, reason: 'the composer Stop pauses the exercise too');
    expect(model.cancels, 1, reason: 'her words stop at the tap');
    expect(find.text('Stop. I want to stop.'), findsOneWidget, reason: 'the stop is sent once her reply ends');
  });

  testWidgets('R3-10: in edit mode, Return on a computer during a reply reads a crisis at once and keeps the words',
      (tester) async {
    final model = StepModel();
    final state = makeState(model);
    await pumpChat(tester, state, 'written_exposure');
    await tester.enterText(find.byType(TextField), 'I am writing about that night.');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('latest_message')), buttons: 2);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_message')));
    await tester.pumpAndSettle();
    model.hold(beforeWords: true);
    await tester.tap(find.byKey(const Key('exercise_stop')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), crisisSentence);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(crises(state), 1, reason: 'read and acted on at once');
    expect(box(tester), crisisSentence, reason: 'the words stay');
    model.release();
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  test('R3-11: the edit window counts from the first send, across edits', () async {
    final clock = Clock();
    final s = SessionController(model: StepModel(), prompts: prompts, data: AppData(), vault: MemoryVault(),
        clock: () => clock.now);
    await s.start('daily_checkin');
    await s.send('one');
    clock.now = clock.now.add(const Duration(minutes: 6));
    await s.edit('two');
    expect(s.editBlocked(), isNull);
    clock.now = clock.now.add(const Duration(minutes: 5));
    expect(s.editBlocked(), EditClosed.tooLate, reason: '11 minutes after the first send');
  });

  testWidgets('R3-11: a second Edit tap keeps the half-made change', (tester) async {
    final state = makeState(StepModel());
    await pumpChat(tester, state, 'daily_checkin');
    await tester.enterText(find.byType(TextField), 'Work was hard todya.');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      if (i == 0) await tester.enterText(find.byType(TextField), 'Work was hard to');
    }
    expect(box(tester), 'Work was hard to');
  });

  testWidgets('L-3: a starter goes in front of what was typed, never in place of it', (tester) async {
    final state = makeState(StepModel());
    await pumpChat(tester, state, 'daily_checkin');
    await tester.enterText(find.byType(TextField), 'my manager again');
    await tester.tap(find.byKey(const Key('starter_1')));
    await tester.pump();
    expect(box(tester), 'Today was hard. my manager again');
  });

  testWidgets('L-4: before her first words Send works: the words stay, a crisis is read at once, a kind line shows',
      (tester) async {
    final model = StepModel();
    final state = makeState(model);
    await pumpChat(tester, state, 'daily_checkin');
    model.hold(beforeWords: true);
    await tester.enterText(find.byType(TextField), 'Work was hard today.');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), crisisSentence);
    expect(tester.widget<IconButton>(find.byKey(const Key('chat_send'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    expect(crises(state), 1);
    expect(box(tester), crisisSentence);
    await tester.pump();
    expect(find.text(stillReplying), findsOneWidget);
    model.release();
    await tester.pumpAndSettle();
  });

  testWidgets('R3-4: leaving the chat during a reply stops it at once, even before her words, and saves nothing more',
      (tester) async {
    final model = StepModel();
    final vault = CountingVault();
    final state = makeState(model, vault: vault);
    await pumpChat(tester, state, 'written_exposure');
    model.hold(beforeWords: true);
    await tester.enterText(find.byType(TextField), 'I am writing about that night.');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise_stop'))); // a stop waiting for the reply
    await tester.pump();
    final saves = vault.saves, replies = model.replies;
    await tester.pumpWidget(const SizedBox()); // the screen is gone
    await tester.pumpAndSettle();
    expect(model.cancels, 1, reason: 'the model was told to stop');
    expect(model.replies, replies, reason: 'no new reply (the waiting Stop) starts for no one');
    expect(vault.saves, saves, reason: 'nothing saved after the screen is gone');
    expect(state.data.safetyEvents.where((e) => e['level'] == 'error'), isEmpty);
  });

  test('F-05: a failing safety save is flagged, and the next save tries again and clears it', () async {
    final vault = CountingVault()..failing = true;
    final s = SessionController(model: StepModel(), prompts: prompts, data: AppData(), vault: vault,
        clock: () => DateTime(2026, 11, 14, 20));
    await s.start('daily_checkin');
    await s.send(crisisSentence);
    await Future<void>.delayed(Duration.zero);
    expect(s.safetySaveFailing, isTrue);
    vault.failing = false;
    final before = vault.saves;
    await s.send('Thank you.');
    await Future<void>.delayed(Duration.zero);
    expect(vault.saves, greaterThan(before), reason: 'the end of the next reply tries again');
    expect(s.safetySaveFailing, isFalse);
  });

  test('L-2: the speech feed gives out each sentence as soon as it is complete; short ones join the next', () {
    final feed = SpeechFeed();
    expect(feed.add('That sounds really hard, thank you for telling me. '),
        ['That sounds really hard, thank you for telling me.']);
    expect(feed.add('Mm. '), isEmpty, reason: 'too short alone');
    expect(feed.add('What part of it stayed with you most? '), ['Mm. What part of it stayed with you most?']);
    expect(feed.add('Take your time'), isEmpty);
    expect(feed.close(), ['Take your time']);
    expect(endOfTurnSilence, 0.7);
  });
}
