// My safety plan (core/safety_plan.dart, ui/safety_plan.dart): the seven steps are kept in the encrypted store, the
// country's crisis lines are always in step 5, the plan is one tap from the support screen (but not from the lock
// screen), a copy can be saved as a PDF, and a move to another device never loses it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/crisis.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/safety_plan.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/safety_plan.dart';

import 'app_flow_test.dart' as flow;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  test('steps are added once, removed by place, and kept through the store', () {
    final d = AppData();
    expect(d.safetyPlan.isEmpty, isTrue);
    d.safetyPlan.add('people', '  Sam, 087 123 4567 ', '2026-11-14');
    d.safetyPlan.add('people', 'Sam, 087 123 4567', '2026-11-14'); // the same again: not added twice
    d.safetyPlan.add('people', '   ', '2026-11-14'); // nothing: not added
    d.safetyPlan.add('reasons', 'My dog, Lily', '2026-11-15');
    expect(d.safetyPlan.of('people'), ['Sam, 087 123 4567']);
    final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));
    expect(back.safetyPlan.of('reasons'), ['My dog, Lily']);
    expect(back.safetyPlan.updated, '2026-11-15');
    back.safetyPlan.remove('people', 0, '2026-11-16');
    back.safetyPlan.remove('people', 5, '2026-11-16'); // out of range: nothing happens
    expect(back.safetyPlan.of('people'), isEmpty);
    // an older file without a plan, and a damaged one, load as an empty plan
    expect(AppData.fromJson({}).safetyPlan.isEmpty, isTrue);
    expect(SafetyPlan.fromJson({'steps': {'unknown': ['x'], 'signs': 'not a list'}}).isEmpty, isTrue);
  });

  test('the crisis lines are always in step 5, in the text and the PDF', () async {
    final plan = SafetyPlan()..add('alone', 'A hot shower', '2026-11-14');
    final text = safetyPlanText(plan, crisisByCountry['Ireland']);
    expect(text, contains('1. Signs a hard moment is building'));
    expect(text, contains('A hot shower'));
    expect(text, contains('Pieta crisis helpline: 1800 247 247'));
    expect(text, contains('Emergency: 112 or 999'));
    final pdf = await safetyPlanPdf(plan, crisisByCountry['Ireland']);
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
  });

  test('a move to another device keeps the newer plan, and never loses one', () {
    final here = AppData()..safetyPlan.add('people', 'Sam', '2026-11-14');
    final emptyOther = AppData();
    expect(importInto(here, emptyOther).safetyPlan.of('people'), ['Sam']);
    final newer = AppData()..safetyPlan.add('people', 'Alex', '2026-11-20');
    final here2 = AppData()..safetyPlan.add('people', 'Sam', '2026-11-14');
    expect(importInto(here2, newer).safetyPlan.of('people'), ['Alex']);
  });

  testWidgets('written on the You tab, opened from Support, saved as a PDF', (tester) async {
    final state = flow.makeState();
    final saved = <String, Uint8List>{};
    await flow.pumpApp(tester, state);
    // Support with no plan: an offer to make one
    await tester.tap(find.byTooltip('Support').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crisis_plan')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('crisis_make_plan')), 300,
        scrollable: find.descendant(of: find.byType(CrisisSheet), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crisis_make_plan')));
    await tester.pumpAndSettle();
    expect(find.byType(SafetyPlanScreen), findsOneWidget);
    await tester.enterText(find.byKey(const Key('plan_add_alone')), 'Walk round the block');
    await tester.tap(find.byKey(const Key('plan_add_alone_go')));
    await tester.pumpAndSettle();
    expect(state.data.safetyPlan.of('alone'), ['Walk round the block']);
    expect(find.text('Walk round the block'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('plan_add_professionals')));
    await tester.pumpAndSettle();
    expect(find.textContaining('9-8-8 Suicide Crisis Helpline', findRichText: true), findsOneWidget); // Canada, the test person's country
    await flow.shot('35_safety_plan');
    // the copy, through a stand-in for the save dialog
    await tester.pumpWidget(const SizedBox()); // close everything, then open the screen with the stand-in
    await flow.pumpApp(tester, state);
    final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
    nav.push(MaterialPageRoute(builder: (_) => SafetyPlanScreen(save: (name, bytes, mime) async {
      saved[name] = bytes;
      return 'Saved as $name.';
    })));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('plan_save')), 400,
        scrollable: find.descendant(of: find.byType(SafetyPlanScreen), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('plan_save')));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(saved.keys, ['my-safety-plan.pdf']);
    expect(find.textContaining('outside Solace\'s encryption now'), findsOneWidget);
    nav.pop();
    await tester.pumpAndSettle();
    // with a plan, Support opens it in one tap
    await tester.tap(find.byTooltip('Support').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crisis_plan')));
    await tester.pumpAndSettle();
    expect(find.byType(SafetyPlanScreen), findsOneWidget);
  });

  testWidgets('the lock screen\'s Support does not open the plan', (tester) async {
    final state = flow.makeState()..data.safetyPlan.add('people', 'Sam', '2026-11-14');
    await flow.pumpApp(tester, state);
    final context = tester.element(find.byType(Scaffold).first);
    showCrisisSheet(context, plan: false);
    await tester.pumpAndSettle();
    expect(find.byType(CrisisSheet), findsOneWidget);
    expect(find.byKey(const Key('crisis_plan')), findsNothing);
    expect(find.byKey(const Key('crisis_make_plan')), findsNothing);
  });
}
