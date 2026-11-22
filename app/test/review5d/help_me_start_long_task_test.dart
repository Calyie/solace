// Review round 5 (D): Help me start. D-16: the phrase rules read a task of up to 20,000 characters on the interface
// thread (up to 128 ms on a laptop compiled ahead of time, several times that on a phone); fixed in round 5, past
// pastesInIsolate (3,000 since round 9; 15,000 before) they read it in a background isolate, as sessions, notes and pastes do (B-17). D-12: a step
// of the split that gives a phone number is left out, and the other steps still show.
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart' show pastesInIsolate;
import 'package:solace/ui/help_me_start.dart';

import '../audit_followups_test.dart' as a;

/// Says which isolate read the text, in its reason.
class WhereRules extends SafetyCheck {
  const WhereRules();
  @override
  SafetyResult check(String text, {required String sessionKind}) =>
      SafetyResult(SafetyLevel.none, '${Isolate.current.hashCode}');
}

class PhoneSplitModel extends StandInModel {
  const PhoneSplitModel();
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    yield '1. Find the bill | 2 min\n2. Call the helpline on 0800 123 4567 | 5 min\n3. Write down the answer | 5 min';
  }
}

void main() {
  test('D-16: a task past 15,000 characters is read by the rules in another isolate; a shorter one at once', () async {
    final here = '${Isolate.current.hashCode}';
    expect((await readTask('a' * pastesInIsolate, rules: const WhereRules())).reason, here);
    expect((await readTask('a' * (pastesInIsolate + 1), rules: const WhereRules())).reason, isNot(here));
    expect((await readTask('a' * 20000, rules: const WhereRules())).reason, isNot(here));
    // and the real rules read the whole long task there, its end included
    final long = '${'I need to sort out the spare room this weekend. ' * 420}I am going to kill myself tonight.';
    expect(long.length, greaterThan(20000));
    expect((await readTask(long)).level, SafetyLevel.crisis);
  });

  testWidgets('D-16: a full task box ending in a crisis is read off the interface thread, recorded and opens support',
      (tester) async {
    final state = a.makeState(model: const a.SplittingModel());
    final task = '${'I need to sort out the spare room this weekend. ' * 400}I am going to kill myself tonight.';
    expect(task.length, inInclusiveRange(pastesInIsolate + 1, 20000));
    await a.pumpScreen(tester, state, HelpMeStartScreen(task: task));
    await tester.tap(find.byKey(const Key('help_split')));
    for (var i = 0; i < 50 && state.data.safetyWatch == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the isolate's real time
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(state.data.safetyEvents.where((e) => e['level'] == 'crisis').length, 1);
    expect(state.data.safetyWatch, isNotNull);
    expect(find.text('You matter, and support is here'), findsOneWidget);
    expect(find.text('Open the email from the landlord'), findsNothing, reason: 'never turned into timed steps');
  });

  testWidgets('D-12: a step that gives a phone number is left out; the other steps still show', (tester) async {
    final state = a.makeState(model: const PhoneSplitModel());
    await a.pumpScreen(tester, state, const HelpMeStartScreen(task: 'sort out the phone bill'));
    await tester.tap(find.byKey(const Key('help_split')));
    await tester.pumpAndSettle();
    expect(find.text('Find the bill'), findsOneWidget);
    expect(find.text('Write down the answer'), findsOneWidget);
    expect(find.textContaining('0800'), findsNothing);
    expect(find.byKey(const Key('help_support')), findsNothing, reason: 'a phone number is not a means to harm');
    expect(state.data.safetyEvents.single, {'date': '2026-11-14', 'level': 'output', 'reason': 'phone number'});
  });
}
