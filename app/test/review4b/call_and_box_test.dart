// Review round 4 (B): proof tests for the call's safety question, the message box limit and the desktop app lock.
// The reviewer wrote each to assert the faulty behaviour on commit 5bdac57. B-09, B-10, B-13, B-14, B-15 and B-17 are
// fixed in round 4 (branch fix/round4-b), and their tests now assert the fixed behaviour in the same scenario: each
// failed on 5bdac57.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/voice.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/premium.dart';
import 'package:solace/ui/theme.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

/// A hands-free voice: speaks at once, and "hears" the next line of [said] each time it listens.
class ScriptVoice implements VoiceService {
  ScriptVoice(this.said, {this.holdBefore = -1});
  final List<String> said;
  final int holdBefore; // the line (0-based) that waits for [go] before it is "heard"
  final go = Completer<void>();
  final spoken = <String>[];
  var listens = 0;
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async => spoken.add(text);
  @override
  Future<void> stop() async {}
  @override
  Future<String?> listenOnce() async {
    listens++;
    if (listens - 1 == holdBefore) await go.future;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return listens <= said.length ? said[listens - 1] : null;
  }
}

/// A voice whose microphone stops when told to, as the device's does: a listen still waiting returns nothing heard.
/// The first listens hear [said]; after them it listens until stopped.
class StoppingVoice implements VoiceService {
  StoppingVoice(this.said);
  final List<String> said;
  final spoken = <String>[];
  var listens = 0;
  Completer<String?>? _open;
  bool get listening => _open != null;
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async => spoken.add(text);
  @override
  Future<void> stop() async {
    final open = _open;
    _open = null;
    if (open != null && !open.isCompleted) open.complete(null);
  }

  @override
  Future<String?> listenOnce() async {
    listens++;
    if (listens <= said.length) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return said[listens - 1];
    }
    return (_open = Completer<String?>()).future;
  }
}

AppState makeState() {
  final data = AppData();
  data.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  return AppState(data: data, vault: MemoryVault(), prompts: prompts, model: const StandInModel(),
      library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
      clock: () => DateTime(2026, 11, 14, 20));
}

Future<void> pumpCall(WidgetTester tester, AppState state, VoiceService voice) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.light),
      home: CallScreen(kind: 'daily_checkin', voice: voice))));
}

Future<void> frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // B-09 (superseded 2026-11-15, owner): the safety question is gone. On a call a classifier worry shows the quiet
  // support line and says it once; nothing waits for a tap, and the call goes on listening.
  testWidgets('B-09: a classifier worry on a call is the support line, said once; the call goes on', (tester) async {
    final state = makeState();
    var n = 0;
    state.useRiskCheck((c, t) async => ++n == 1, 'test classifier'); // worried about the first message only
    final voice = ScriptVoice(['I feel so empty lately.', 'Anyway. Work was fine I suppose.']);
    await pumpCall(tester, state, voice);
    await frames(tester, 80);
    expect(voice.spoken.where((x) => x.contains(concernLine)), hasLength(1), reason: 'the support line is said once');
    expect(voice.spoken.where((x) => x.contains('Can I check something with you')), isEmpty, reason: 'no question');
    expect(n, 2, reason: 'the next words were heard and sent; nothing waited for a tap');
    expect(state.data.safetyEvents.where((e) => e['reason'] == 'classifier'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  // B-09: the opening check after a recent crisis was likewise only drawn on a call. Now it is said after her opening
  // words, and the call listens once it is answered.
  testWidgets('B-09: the opening check after a recent crisis is spoken on a call', (tester) async {
    final state = makeState();
    state.data.safetyWatch = {'since': DateTime(2026, 11, 13, 20).toIso8601String(), 'reason': 'suicide'};
    final voice = ScriptVoice(['Work was long.']);
    await pumpCall(tester, state, voice);
    await frames(tester, 20);
    expect(find.byKey(const Key('opening_check')), findsOneWidget);
    expect(voice.spoken.last, '$openingAfterCrisisLine $tapToAnswerLine');
    expect(voice.listens, 0, reason: 'nothing listens until it is answered');
    await tester.tap(find.text('A bit better'));
    await frames(tester, 10);
    expect(voice.listens, greaterThanOrEqualTo(1), reason: 'answered: the call listens');
    expect(state.data.safetyEvents.last['reason'], 'opening check: better');
    expect(state.data.safetyWatch, isNotNull, reason: 'a bit better keeps the watch');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  // B-14 (failed on 5bdac57, fixed in round 4): a paste into a FULL box with the cursor not at its end was dropped by
  // MessageLimit, but checkPasted read the end of the combined text, which was the box's old words, so a crisis in the
  // paste was never read by any check. Now the box hands the rules exactly what it did not add.
  test('B-14: a crisis pasted at the start or middle of a full box is read and acted on', () async {
    for (final at in [0, 5000]) {
      final data = AppData();
      final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: MemoryVault(),
          clock: () => DateTime(2026, 11, 14, 20));
      await s.start('daily_checkin');
      final full = 'a' * TextLimit.message;
      const paste = 'I want to kill myself tonight. ';
      String? before, dropped;
      final limit = MessageLimit((b, d) => (before, dropped) = (b, d));
      final out = limit.formatEditUpdate(
          TextEditingValue(text: full, selection: TextSelection.collapsed(offset: at)),
          TextEditingValue(text: '${full.substring(0, at)}$paste${full.substring(at)}',
              selection: TextSelection.collapsed(offset: at + paste.length)));
      expect(out.text, full, reason: 'the paste is not in the box');
      expect(dropped, paste, reason: 'what was left out is handed on');
      expect(before, full.substring(0, at));
      await s.checkDropped(before!, dropped!);
      expect(s.crisisCount, 1, reason: 'the pasted crisis is read (cursor at $at)');
      expect(data.safetyEvents.single['level'], 'crisis');
    }
    expect(pasteTooLong, contains('The safety checks read all of it'));
  });

  // B-15 (failed on 5bdac57, fixed in round 4): a paste in the MIDDLE of a nearly full box kept the paste and dropped
  // the END of the person's own earlier words. Now only the paste is cut: every typed word stays.
  test('B-15: a paste near the start of a nearly full box keeps all the person\'s own words', () {
    final typed = '${'b' * 10990}MY LAST WORDS';
    final paste = 'x' * 2000;
    String? dropped;
    final limit = MessageLimit((_, d) => dropped = d);
    final out = limit.formatEditUpdate(
        TextEditingValue(text: typed, selection: const TextSelection.collapsed(offset: 0)),
        TextEditingValue(text: '$paste$typed', selection: TextSelection.collapsed(offset: paste.length)));
    expect(out.text.length, TextLimit.message);
    expect(out.text.endsWith(typed), isTrue, reason: 'every word the person typed is still in the box');
    expect(out.text, '${'x' * (TextLimit.message - typed.length)}$typed', reason: 'as much of the paste as fits');
    expect(out.selection.baseOffset, TextLimit.message - typed.length, reason: 'the cursor after what went in');
    expect(dropped, 'x' * (paste.length - (TextLimit.message - typed.length)));
    // an emoji is never cut in half at the edge of what fits
    final emoji = MessageLimit((_, _) {}).formatEditUpdate(
        TextEditingValue(text: 'b' * (TextLimit.message - 1), selection: const TextSelection.collapsed(offset: 0)),
        TextEditingValue(text: '😀😀${'b' * (TextLimit.message - 1)}',
            selection: const TextSelection.collapsed(offset: 4)));
    expect(emoji.text, 'b' * (TextLimit.message - 1), reason: 'half an emoji does not fit, so none of it goes in');
    // text that fits is never touched
    expect(MessageLimit((_, _) {}).formatEditUpdate(const TextEditingValue(text: 'abc'),
        const TextEditingValue(text: 'aXYZc')).text, 'aXYZc');
  });

  // B-17 (failed on 5bdac57, fixed in round 4): pastes up to 50,000 characters were read on the interface thread. Now
  // anything past 15,000 (3,000 since round 9 review B, 9B-03) is read in a background isolate, and still acted on.
  test('B-17: a 20,000-character overflow is read off the interface thread and still acted on', () async {
    expect(pastesInIsolate, lessThanOrEqualTo(3000));
    final data = AppData();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: MemoryVault(),
        clock: () => DateTime(2026, 11, 14, 20));
    await s.start('daily_checkin');
    await s.checkDropped('a' * 300, '${'Work was long. ' * 1300}I want to kill myself tonight.');
    expect(s.crisisCount, 1);
    expect(data.safetyEvents.single['reason'], contains('paste'));
  });

  // B-10 (failed on 5bdac57, fixed in round 4): on a computer, the app lock came down over a running voice call (the
  // window lost focus and came back with "lock at once", or N minutes with no mouse or keys, the normal state of a
  // hands-free call), but the call kept listening, sending and speaking behind the lock screen, and the crisis sheet
  // it opened was pushed under the lock, out of sight. Now the call pauses when the lock comes down, a live call
  // counts as activity for the idle lock, and a crisis read meanwhile shows its support over the lock screen.
  testWidgets('B-10: a desktop lock pauses the call, and a crisis heard shows its support over the lock',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final state = makeState();
      final voice = ScriptVoice(['Hello.', 'I want to kill myself.'], holdBefore: 1);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.light),
          builder: (context, child) => AppLockGate(child: child!),
          home: CallScreen(kind: 'daily_checkin', voice: voice))));
      await frames(tester, 20);
      expect(find.text('Solace is locked'), findsNothing);
      expect(callLive, isTrue, reason: 'a listening call is activity for the idle lock');
      // the person turns the lock on ("at once"), then the window loses focus and comes back
      state.data.settings
        ..appLock = true
        ..passcode = {'x': 'y'} // the lock needs a passcode to be on (owner, 2026-11-15); never typed here
        ..lockAfterMinutes = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text('Solace is locked'), findsOneWidget, reason: 'the lock screen is up');
      expect(find.byKey(const Key('call_paused_card'), skipOffstage: false), findsOneWidget,
          reason: 'the call paused when the lock came down');
      expect(callLive, isFalse);
      final spokenBefore = voice.spoken.length;
      voice.go.complete(); // the person, hands-free, says it now (recognition already under way)
      await frames(tester, 30);
      expect(voice.listens, 2, reason: 'the microphone did not listen again behind the lock');
      expect(voice.spoken.length, spokenBefore, reason: 'she did not speak behind the lock');
      expect(state.data.safetyEvents.where((e) => e['level'] == 'crisis'), hasLength(1),
          reason: 'what was heard is still read');
      expect(find.text('You matter, and support is here'), findsOneWidget,
          reason: 'its support shows over the lock screen');
      expect(find.byKey(const Key('crisis_plan')), findsNothing, reason: 'no safety plan over the lock');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(callLive, isFalse, reason: 'a call that has gone is not live');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // B-13 (failed on 5bdac57, fixed in round 4): a worry (SafetyLevel.concern: "I can't go on", "I'm going to hurt
  // myself", or any classifier alarm after two noes) showed the chat's "support is here" banner, but on a call nothing
  // at all was shown or said. Now the call shows the support line, says it once, and its state line says so.
  // round 7 review, H7-02 (owner, 2026-11-15: nothing under 90 percent precision shows): a worry from the phrase rules is
  // recorded but shows and says nothing on a call (the classifier's line, when it is turned on, is B-09)
  testWidgets('B-13: a worry from the phrase rules on a call is recorded and shows nothing', (tester) async {
    final state = makeState();
    final voice = ScriptVoice(["I'm going to hurt myself tonight.", 'I just want to disappear.']);
    await pumpCall(tester, state, voice);
    await frames(tester, 40);
    expect(state.data.safetyEvents.where((e) => e['level'] == 'concern'), hasLength(2), reason: 'two worries');
    expect(find.byKey(const Key('call_concern')), findsNothing);
    expect(voice.spoken.where((x) => x.contains(concernLine)), isEmpty);
    expect(state.data.safetyEvents.where((e) => e['level'] == 'crisis'), isEmpty, reason: 'no extra alarm');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
