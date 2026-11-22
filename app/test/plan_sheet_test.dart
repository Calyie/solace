// owner, 2026-11-19: "the plan should be visible in their sessions and actively maintained by you so you both know
// you are making progress". The plan from the therapy record is one tap away in a session and on Today.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/plan_sheet.dart';

import 'app_flow_test.dart' as flow;
import 'review_c2_responsive_test.dart' as rr;

void main() {
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  Future<void> pump(WidgetTester tester, void Function(AppData) fill, Widget child) async {
    final data = rr.dataFor(1.0, 'inter', 'light');
    fill(data);
    final state = rr.stateFor(data, MemoryVault(), const StandInModel());
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)))));
    await tester.pump();
  }

  void plan(AppData d) {
    d.story.sections['What we are working on'] = 'The tiredness and the days in bed.';
    d.story.sections['The plan'] = 'Behavioural activation with a steady body clock, about twelve weeks.';
    d.story.sections['Where we are in the plan'] = 'Week 2 of the first phase. Next: lunch at the table.';
    d.story.sections['Activities and tasks'] = 'Up at 9:30 with the curtains open.';
    d.story.sections['Progress'] = 'Up by 9:30 on four of the last seven days.';
  }

  test('a plan exists only when the record holds one', () {
    if (appPromptVersion != 'v5') return;
    final d = AppData();
    expect(hasPlan(d), isFalse);
    d.story.sections['The plan'] = 'nothing yet';
    expect(hasPlan(d), isFalse);
    plan(d);
    expect(hasPlan(d), isTrue);
  });

  testWidgets('no plan yet: the sheet says the first session builds it, and Today shows no plan card', (tester) async {
    if (appPromptVersion != 'v5') return;
    await pump(tester, (_) {}, const Column(children: [PlanCard(), PlanSheet()]));
    expect(find.byKey(const Key('plan_card')), findsNothing);
    expect(find.byKey(const Key('plan_none')), findsOneWidget);
    expect(find.textContaining('build your plan in your first session'), findsOneWidget);
  });

  testWidgets('with a plan: the sheet shows the plan, where they are, the tasks and the progress', (tester) async {
    if (appPromptVersion != 'v5') return;
    await pump(tester, plan, const PlanSheet());
    expect(find.text('Your plan with Maya'), findsOneWidget);
    for (final h in planHeadings) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('Behavioural activation with a steady body clock, about twelve weeks.'), findsOneWidget);
    expect(find.text('Up by 9:30 on four of the last seven days.'), findsOneWidget);
    expect(find.byKey(const Key('plan_none')), findsNothing);
  });

  testWidgets("Today's card shows where they are in the plan and opens the whole plan", (tester) async {
    if (appPromptVersion != 'v5') return;
    await pump(tester, plan, const PlanCard());
    expect(find.text('Your plan'), findsOneWidget);
    expect(find.text('Week 2 of the first phase. Next: lunch at the table.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan_card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_sheet')), findsOneWidget);
    expect(find.text('Activities and tasks'), findsOneWidget);
  });
}
