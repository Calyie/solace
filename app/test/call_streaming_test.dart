// Calls speak a reply while it is being written (L-2): she starts at her first screened sentence instead of after the
// whole reply; a pause part way says the whole reply again on Resume; a tap stops the writing too; the call's Send
// works while she replies (L-4); a reply written while paused is spoken on Resume even while its check runs (L-11).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/voice.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/theme.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

/// Says one sentence, then waits (when held) before the rest.
class HalfwayModel extends StandInModel implements ReplyCanceller {
  HalfwayModel();
  Completer<void>? _rest, _held;
  int cancels = 0;
  void holdHalfway() => _rest = _held = Completer<void>();
  void release() {
    if (!(_held?.isCompleted ?? true)) _held!.complete();
  }

  @override
  void cancelReply() {
    cancels++;
    release();
  }

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    final rest = _rest;
    if (rest == null) {
      yield* super.generate(messages, maxTokens: maxTokens);
      return;
    }
    _rest = null;
    yield 'I hear you, and that sounds like a long day. ';
    await rest.future;
    yield 'What part of it stayed with you most?';
  }
}

/// A voice that can speak as words come; records what it is given and when.
class FeedVoice implements VoiceService, StreamingVoice {
  final events = <String>[];
  final fed = <String>[];
  Completer<void>? _speaking;
  bool Function()? stillWriting;
  bool firstWhileWriting = false;
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async {
    events.add('speak:$text');
    _speaking = Completer<void>();
    await _speaking!.future;
  }

  @override
  Future<void> speakAll(Stream<String> words, {required String voice}) async {
    events.add('speakAll');
    _speaking = Completer<void>();
    final sub = words.listen((w) {
      if (fed.isEmpty) firstWhileWriting = stillWriting?.call() ?? false;
      fed.add(w);
    }, onDone: () {});
    await Future.any([_speaking!.future, sub.asFuture<void>()]);
    await sub.cancel();
  }

  void finish() {
    if (!(_speaking?.isCompleted ?? true)) _speaking!.complete();
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    finish();
    final h = _hearing;
    if (h != null && !h.isCompleted) h.complete(null);
  }

  Completer<String?>? _hearing;

  /// The microphone stays open until stop(), as a real one does while the person is quiet (since 2026-11-16 a call
  /// carried on from the chat listens at once: before, it returned at once, which now rested the call at its start).
  @override
  Future<String?> listenOnce() async {
    events.add('listen');
    return (_hearing = Completer<String?>()).future;
  }
}

AppState makeState(ModelRuntime model) {
  final data = AppData();
  data.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  return AppState(data: data, vault: MemoryVault(), prompts: prompts, model: model,
      library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
      clock: () => DateTime(2026, 11, 14, 20));
}

Future<void> pumpCall(WidgetTester tester, AppState state, FeedVoice voice, dynamic session, {String draft = ''}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      home: CallScreen(kind: 'daily_checkin', voice: voice, controller: session, draft: draft))));
  await tester.pump();
}

void main() {
  testWidgets('she starts speaking at her first sentence, while the rest is still being written', (tester) async {
    final model = HalfwayModel();
    final state = makeState(model);
    final s = state.newSession();
    await s.start('daily_checkin');
    final voice = FeedVoice()..stillWriting = () => s.busy && !s.checking;
    await pumpCall(tester, state, voice, s);
    voice.finish(); // the opening, if it is being spoken
    await tester.pump();
    voice.events.clear();
    model.holdHalfway();
    final sent = s.send('Work was hard today.');
    await tester.pump();
    await tester.pump();
    expect(voice.events, contains('speakAll'));
    expect(voice.fed.join(), 'I hear you, and that sounds like a long day. ');
    expect(voice.firstWhileWriting, isTrue, reason: 'the first sentence reached the voice before the reply was done');
    model.release();
    await tester.runAsync(() => sent);
    await tester.pump();
    expect(voice.fed.join(), 'I hear you, and that sounds like a long day. What part of it stayed with you most?');
    expect(voice.events.where((e) => e.startsWith('speak:')), isEmpty, reason: 'not said a second time');
    voice.finish();
    await tester.pump();
    await tester.pump();
    expect(voice.events, contains('listen'), reason: 'then she listens (and, hearing nothing, the call rests)');
    expect(voice.events.indexOf('listen'), greaterThan(voice.events.indexOf('speakAll')));
  });

  testWidgets('a pause part way says the whole reply again on Resume', (tester) async {
    final model = HalfwayModel();
    final state = makeState(model);
    final s = state.newSession();
    await s.start('daily_checkin');
    final voice = FeedVoice();
    await pumpCall(tester, state, voice, s);
    voice.finish();
    await tester.pump();
    model.holdHalfway();
    final sent = s.send('Work was hard today.');
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('call_pause')));
    await tester.pump();
    model.release();
    await tester.runAsync(() => sent);
    await tester.pump();
    voice.events.clear();
    await tester.tap(find.byKey(const Key('call_resume')));
    await tester.pump();
    expect(voice.events.first,
        'speak:I hear you, and that sounds like a long day. What part of it stayed with you most?');
  });

  testWidgets('a tap while she speaks a reply still being written stops the writing too', (tester) async {
    final model = HalfwayModel();
    final state = makeState(model);
    final s = state.newSession();
    await s.start('daily_checkin');
    final voice = FeedVoice();
    await pumpCall(tester, state, voice, s);
    voice.finish();
    await tester.pump();
    model.holdHalfway();
    final sent = s.send('Work was hard today.');
    await tester.pump();
    await tester.pump();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(model.cancels, 1, reason: 'the model was told to stop');
    await tester.runAsync(() => sent);
    await tester.pump();
    expect(s.turns.last, ('therapist', 'I hear you, and that sounds like a long day.'));
  });

  testWidgets('End with words still in the box asks first; Keep talking keeps the call and the words', (tester) async {
    final state = makeState(HalfwayModel());
    final s = state.newSession();
    await s.start('daily_checkin');
    final voice = FeedVoice();
    await pumpCall(tester, state, voice, s, draft: 'There is one more thing I wanted to say');
    voice.finish();
    await tester.pump();
    await tester.tap(find.byKey(const Key('call_end')));
    await tester.pump();
    expect(find.text('End the call?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call_end_keep')));
    await tester.pump();
    expect(find.text('End the call?'), findsNothing);
    expect(find.byKey(const Key('call_end')), findsOneWidget, reason: 'still on the call');
    expect(tester.widget<TextField>(find.byKey(const Key('call_text'))).controller!.text,
        'There is one more thing I wanted to say');
  });
}
