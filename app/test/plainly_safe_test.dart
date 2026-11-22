// Owner, 2026-11-15, on round 5 review D-05: "This should never happen. Precision must be prioritised over recall."
// A plainly safe sentence the phrase rules read as safe ("I cut myself shaving this morning") never asks the
// classifier's safety question, in a session or in Help me start. A worry anywhere else in the message, a mood that sets
// it off or a nightly habit still leaves the question to the classifier, and every rule crisis stays a crisis.
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
import 'package:solace/ui/help_me_start.dart';
import 'package:solace/ui/theme.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

const plainlySafe = [
  'I cut myself shaving this morning.', // the review's own example
  "I don't want to wake up early on Saturday.",
  "I'm saying goodbye to everyone at my leaving party on Friday.",
  'I bought rope for the tent.',
  "I'm going to hang the pictures this weekend.",
  'What if I cut myself while chopping onions?',
  "I'm going to take my life back this year.",
];

// a worry left once the safe words are set aside, a mood that sets it off, or a nightly habit: not plainly safe
const notPlainly = [
  "I bought rope for the tent. Nobody would notice if I didn't come back.",
  "I'm saying goodbye to everyone at my leaving party, then I'm going to disappear for good.",
  "I'm going to hang the pictures, sort my will and then it's done.",
  "I cut myself shaving. Honestly I can't see a reason to keep going.",
  "I don't want to wake up early on Saturday, or ever again really.",
  'I burn myself with the kettle when things get bad.',
  "I cut myself with a can opener when I'm sad.",
  'Most nights I cut myself in the gym changing room.',
  'Work was long today.', // nothing set aside at all
  // round 10 review B (R10B-01): a comma starts a second part, so the classifier reads it ("..., that's not true")
  'No thoughts of suicide, just need a break.',
];

void main() {
  const rules = SafetyCheck();

  test('the rules mark plainly safe sentences, and only those', () {
    for (final t in plainlySafe) {
      final r = rules.check(t, sessionKind: 'daily_checkin');
      expect(r.level, SafetyLevel.none, reason: t);
      expect(r.plainlySafe, isTrue, reason: t);
    }
    for (final t in notPlainly) {
      expect(rules.check(t, sessionKind: 'daily_checkin').plainlySafe, isFalse, reason: t);
    }
    for (final t in ["I'm going to hang myself.", 'I cut myself again last night.', "I don't want to wake up at all.",
        'I want to end it with him tonight using my pills.', 'I cut myself while cooking because I deserve it.']) {
      final r = rules.check(t, sessionKind: 'daily_checkin');
      expect(r.level, SafetyLevel.crisis, reason: t);
      expect(r.plainlySafe, isFalse, reason: t);
    }
  });

  test('a long hostile paste is read in bounded time and is never plainly safe by accident', () {
    for (final n in [12000, 50000, 200000]) {
      for (final unit in ['I cut myself shaving. rope for the tent. hang the pictures. wake up early. ',
          'rope for the tent. hang the pictures. wake up early. I bought it. ']) {
        final paste = (unit * (n ~/ unit.length + 1)).substring(0, n);
        final watch = Stopwatch()..start();
        final r = rules.check(paste, sessionKind: 'daily_checkin');
        // linear in the length: about 0.1 s per 12,000 characters on the development laptop, and no different from
        // main's rules on the same pastes (measured side by side, 2026-11-15); the bound leaves room for a busy machine
        expect(watch.elapsedMilliseconds, lessThan(n ~/ 20), reason: '$n characters');
        // more than 30 "cut myself" is never all accidents (a crisis, as before); more than 30 of one safe phrase:
        // the rest stay in, so the classifier still reads them
        expect(r.level, unit.contains('cut') ? SafetyLevel.crisis : SafetyLevel.none, reason: '$n characters');
        expect(r.plainlySafe, isFalse, reason: '$n characters');
      }
    }
  });

  group('a classifier that worries about every message', () {
    final asked = <String>[];
    Future<bool> worried(String context, String text) async {
      asked.add(text);
      return true;
    }

    setUp(asked.clear);

    test('a session never puts a plainly safe sentence to the classifier, and still reads the rest', () async {
      final s = SessionController(model: const StandInModel(), prompts: prompts, data: AppData(),
          vault: MemoryVault(), riskCheck: worried, clock: () => DateTime(2026, 11, 15, 9));
      await s.start('daily_checkin');
      await s.send('I cut myself shaving this morning.');
      expect(asked, isEmpty, reason: 'not put to the classifier');
      expect(s.lastSafety.level, SafetyLevel.none);
      expect(s.data.safetyEvents, isEmpty);
      await s.send("I bought rope for the tent. Nobody would notice if I didn't come back.");
      expect(asked, isNotEmpty);
      expect(s.lastSafety.level, SafetyLevel.concern, reason: 'the quiet support line (owner, 2026-11-15: no question)');
    });

    Future<AppState> pump(WidgetTester tester, String task) async {
      final data = AppData();
      data.settings
        ..therapistChosen = true
        ..onboarded = true
        ..ageConfirmed = true;
      final state = AppState(data: data, vault: MemoryVault(), prompts: prompts,
          model: const _Steps(), library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
          clock: () => DateTime(2026, 11, 15, 9))
        ..useRiskCheck(worried, 'test classifier');
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light), home: HelpMeStartScreen(task: task))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('help_split')));
      await tester.pumpAndSettle();
      return state;
    }

    // owner 2026-11-15: Help me start no longer asks the classifier at all
    testWidgets('Help me start splits a task without asking the classifier', (tester) async {
      final state = await pump(tester, "I'm going to hang the pictures, sort my will and then it's done.");
      expect(asked, isEmpty);
      expect(find.text('Find the hammer'), findsOneWidget, reason: 'the steps are shown');
      expect(state.data.safetyEvents, isEmpty);
    });
  });
}

/// Writes two steps for any task.
class _Steps extends StandInModel {
  const _Steps();
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    yield '1. Find the hammer | 2 min\n2. Mark the wall | 3 min';
  }
}
