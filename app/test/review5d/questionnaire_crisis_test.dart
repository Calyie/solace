// Review round 5 (D): the questionnaire's crisis item and its last answer. Both tests failed on ca6a73b (they were
// written to show the fault) and were turned round when the faults were fixed in round 5: D-07 now records and saves
// the crisis before the support sheet shows, D-08 now saves once and pops once.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/questionnaires.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/questionnaire.dart';
import 'package:solace/ui/theme.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

/// A vault whose save takes as long as an encrypted save of a year of data can on a phone.
class SlowVault extends MemoryVault {
  int saves = 0;
  @override
  Future<void> save(AppData data) async {
    saves++;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await super.save(data);
  }
}

/// A vault that keeps a copy of what it last wrote, as the file on the device would hold it.
class WrittenVault extends MemoryVault {
  AppData? written;
  @override
  Future<void> save(AppData data) async {
    await super.save(data);
    written = AppData.fromJson(jsonDecode(jsonEncode(data.toJson())));
  }
}

AppState makeState(Vault vault) {
  final data = AppData();
  data.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  return AppState(data: data, vault: vault, prompts: prompts, model: const StandInModel(),
      library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
      clock: () => DateTime(2026, 11, 14, 20));
}

Future<void> pumpFlow(WidgetTester tester, AppState state, List<Questionnaire> list) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.light),
      home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionnaireFlow(list: list))),
          child: const Text('open'))))))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('D-07: PHQ-9 question 9 above zero records and saves the crisis and the answers before support shows',
      (tester) async {
    final vault = WrittenVault();
    final state = makeState(vault);
    await pumpFlow(tester, state, [phq9]);
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('Not at all'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Several days')); // question 9: thoughts of being better off dead
    await tester.pumpAndSettle();
    expect(find.text('You matter, and support is here'), findsOneWidget); // the support sheet is up
    // on ca6a73b nothing was recorded while the sheet showed, so an app closed or killed here (iOS often ends a
    // backgrounded app holding a 3 GB model) lost the answer and the crisis; now both are in memory and in the file
    expect(state.data.safetyEvents.where((e) => e['level'] == 'crisis').length, 1);
    expect(state.data.safetyWatch, isNotNull);
    expect(state.data.scores.single['items'], [0, 0, 0, 0, 0, 0, 0, 0, 1]);
    final written = vault.written!;
    expect(written.safetyEvents.where((e) => e['level'] == 'crisis').length, 1);
    expect(written.safetyWatch, isNotNull);
    expect(written.scores.length, 1);
    // closing the sheet finishes the questionnaire without a second record of either
    Navigator.of(tester.element(find.text('You matter, and support is here'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(state.data.safetyEvents.where((e) => e['level'] == 'crisis').length, 1);
    expect(state.data.scores.length, 1);
  });

  testWidgets('D-08: a double tap on the last answer saves the questionnaire once and pops only its own screen',
      (tester) async {
    final vault = SlowVault();
    final state = makeState(vault);
    await pumpFlow(tester, state, [gad7]);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('Not at all'));
      await tester.pumpAndSettle();
    }
    // the last question: two quick taps, the second before the first save has finished (a double tap is ~150 ms)
    await tester.tap(find.text('Several days'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Several days'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final gad = state.data.scores.where((s) => s['name'] == 'GAD-7').toList();
    expect(gad.length, 1, reason: 'on ca6a73b the questionnaire answered once was kept twice');
    expect((gad.single['items'] as List).length, 7, reason: 'GAD-7 has 7 questions');
    expect(vault.saves, 1);
    // on ca6a73b the second pop took the screen that opened the questionnaire too
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('D-08 in the PHQ-9 then GAD-7 flow: a double tap on PHQ-9\'s last answer moves on to GAD-7 once',
      (tester) async {
    final vault = SlowVault();
    final state = makeState(vault);
    await pumpFlow(tester, state, [phq9, gad7]);
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('Not at all'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Not at all'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Not at all'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(state.data.scores.single['name'], 'PHQ-9');
    expect((state.data.scores.single['items'] as List).length, 9);
    expect(find.text(gad7.title), findsOneWidget);
    expect(find.text('Question 1 of 7'), findsOneWidget);
  });
}
