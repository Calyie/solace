// Review round 7 B (H7-01, H7-02 in Help me start): Help me start turns a rules verdict into the full support sheet
// over the screen (ui/help_me_start.dart _split): a crisis opens the flagged sheet ("You matter, and support is here.
// What you said sounds serious...") and starts the 7-day watch; a worry, which a session meets with a quiet line, opens
// the sheet too (recorded as 'ask'). Ordinary tasks the rules misread are never split into steps. Each test asserts the
// safe behaviour (no sheet, no watch, the task is split), so each fails on c8e45c9.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/help_me_start.dart';

import '../audit_followups_test.dart' as a;

void main() {
  for (final task in [
    'Cut my arm day workout plan into steps', // rule 'self-harm': flagged sheet and the 7-day watch
    'Say goodbye to everyone at work on Friday and give away my desk plants', // 'goodbyes and arrangements'
    "Write my essay, I can't keep going with it", // 'cannot go on' (a worry): the sheet all the same
  ]) {
    testWidgets('H7-01/H7-02: Help me start splits "$task" without a support sheet or a watch', (tester) async {
      final state = a.makeState(model: const a.SplittingModel());
      state.useRiskCheck((context, text) async => false, 'test classifier'); // the classifier is not worried
      await a.pumpScreen(tester, state, HelpMeStartScreen(task: task));
      await tester.tap(find.byKey(const Key('help_split')));
      await tester.pumpAndSettle();
      expect(find.byType(CrisisSheet), findsNothing, reason: 'the support sheet opened over an ordinary task');
      expect(state.data.safetyWatch, isNull, reason: 'the 7-day watch started');
      expect(state.data.safetyEvents.where((e) => e['reason'] == 'help me start'), isEmpty,
          reason: 'kept as a safety event');
    });
  }
}
