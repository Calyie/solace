// Review round 9 B, 9B-02: outside a session, a crisis answer opens the support sheet only AFTER a full save of the
// store has finished (ui/check_in.dart _start: saveMood, then noteCrisis, then `await state.save()`, then the sheet;
// ui/questionnaire.dart _answer: `await state.saveScores(...)` before the sheet; ui/crisis.dart readSavedWords: `await
// state.save()` before the sheet). A save encrypts the whole store, writes it and reads it back (core/store.dart
// _write; about 4 s of background work at 16 MB, tracker L-14), and waits behind any save, picture write or key
// renewal already queued. A person who taps "I need help now" waits for all of that before any number shows; a save
// that never finishes (a hung disk, a stuck queue) means the sheet never shows.
//
// Each test holds the save open (it is still writing) and asserts the SAFE behaviour: the support sheet is on screen
// within two seconds, while the crisis is already recorded in memory. Each fails on 3d2da1f while the finding stands;
// the control (a save that finishes at once) passes, so the taps themselves are right.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/questionnaires.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/check_in.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/questionnaire.dart';

import '../audit_followups_test.dart' as a;

/// A vault whose saves take as long as the test says: each save waits for [release].
class SlowVault extends MemoryVault {
  SlowVault({bool quick = false}) {
    if (quick) release.complete(); // the control: saves finish at once
  }
  final release = Completer<void>();
  int saves = 0;
  @override
  Future<void> save(AppData data) async {
    saves++;
    await release.future;
    await super.save(data);
  }
}

void main() {
  testWidgets('9B-02: "I need help now" at the check-in shows support while the save is still writing',
      (tester) async {
    final vault = SlowVault();
    final state = a.makeState(vault: vault);
    await a.pumpScreen(tester, state, const CheckInScreen(kind: 'daily_checkin'));
    await tester.tap(find.text('I need help now'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('check_in_start')));
    await tester.tap(find.byKey(const Key('check_in_start')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CrisisSheet), findsOneWidget,
        reason: 'the support sheet waited for a full save of the store (${vault.saves} save(s) still writing)');
    vault.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('9B-02: a mood and "I need help now": support does not wait for two saves in a row', (tester) async {
    final vault = SlowVault();
    final state = a.makeState(vault: vault);
    await a.pumpScreen(tester, state, const CheckInScreen(kind: 'daily_checkin'));
    await tester.tap(find.byKey(const Key('checkin_mood_3'))); // a mood: saved first, before the crisis is noted
    await tester.pump();
    await tester.tap(find.text('I need help now'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('check_in_start')));
    await tester.tap(find.byKey(const Key('check_in_start')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CrisisSheet), findsOneWidget, reason: 'the support sheet waited for the saves');
    expect(state.data.safetyEvents.where((e) => e['level'] == 'crisis'), isNotEmpty,
        reason: 'the crisis was not even recorded in memory while the mood was being saved');
    vault.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('9B-02: PHQ-9 question 9 above zero shows support while the save is still writing', (tester) async {
    final vault = SlowVault();
    final state = a.makeState(vault: vault);
    await a.pumpScreen(tester, state, const QuestionnaireFlow(list: [phq9]));
    for (var i = 0; i < phq9.items.length; i++) {
      // 0 for the first eight questions, then 1 ("several days") for question 9
      final option = phq9.options[i == phq9.alertItem ? 1 : 0];
      await tester.tap(find.text(option));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CrisisSheet), findsOneWidget, reason: 'the support sheet waited for a full save of the store');
    vault.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('control: with a quick save the same taps show the support sheet (passes on 3d2da1f)', (tester) async {
    final state = a.makeState(vault: SlowVault(quick: true));
    await a.pumpScreen(tester, state, const CheckInScreen(kind: 'daily_checkin'));
    await tester.tap(find.text('I need help now'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('check_in_start')));
    await tester.tap(find.byKey(const Key('check_in_start')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CrisisSheet), findsOneWidget);
  });
}
