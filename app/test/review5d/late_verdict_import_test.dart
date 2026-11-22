// Review round 5 (D-11): a classifier question that arrives after the person left the session is carried to the next
// session as the gentle check (I3), but a transfer brought in meanwhile (allowed once the screen has gone: D4) made
// the session's data stale, so the carried watch was written to the old data and its save was dropped. This test
// failed on ca6a73b (it was written to show the fault); fixed in round 5: the question is carried onto the data the
// app holds when it arrives (SessionController.currentData, AppState.data), and that data is saved.
// Owner, 2026-11-15: there is no safety question any more and a classifier worry starts no watch; the worry's record
// still lands on the data the app holds when it arrives, and is saved, never on the stale copy.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
);

AppState makeState(MemoryVault vault) => AppState(data: AppData(), vault: vault, prompts: prompts,
    model: const StandInModel(), library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
    clock: () => DateTime(2026, 11, 14, 20));

void main() {
  test('D-11: a late classifier alarm for a left session is kept when a transfer is brought in first', () async {
    final vault = MemoryVault();
    final data = AppData();
    var current = data; // what AppState.data is: the import replaces it (app_state.dart _receive)
    final verdict = Completer<bool>();
    final open = OpenSessions();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: vault,
        riskCheck: (c, t) => verdict.future, openSessions: open, clock: () => DateTime(2026, 11, 14, 20),
        currentData: () => current);
    await s.start('daily_checkin');
    final sent = s.send("There's no way out of this for me anymore."); // a worry the rules leave to the classifier (the belt to a door handle is a rule crisis since round 5); the classifier is slow
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.leave(); // Back, before the verdict
    expect(open.count, 0); // so a transfer may be brought in now (D4 only guards open sessions)
    // the transfer, as AppState.receiveTransfer does it: startGeneration, the app's data replaced, then saved
    final imported = AppData();
    vault.startGeneration(imported);
    current = imported;
    await vault.save(imported);
    verdict.complete(true); // the alarm arrives
    await sent;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(imported.safetyEvents.where((e) => e['reason'] == 'classifier').length, 1,
        reason: 'recorded on the data the app holds now');
    expect(imported.safetyWatch, isNull, reason: 'no question, so no watch');
    final stored = await vault.load();
    expect(stored.safetyEvents.where((e) => e['reason'] == 'classifier' && e['level'] == 'concern').length, 1);
  });

  test('D-11: with no transfer, a late worry is recorded on the session\'s own data', () async {
    final vault = MemoryVault();
    final data = AppData();
    final verdict = Completer<bool>();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: vault,
        riskCheck: (c, t) => verdict.future, clock: () => DateTime(2026, 11, 14, 20), currentData: () => data);
    await s.start('daily_checkin');
    final sent = s.send("There's no way out of this for me anymore.");
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.leave();
    verdict.complete(true);
    await sent;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stored = await vault.load();
    expect(stored.safetyWatch, isNull);
    expect(stored.safetyEvents.where((e) => e['reason'] == 'classifier' && e['level'] == 'concern').length, 1);
  });

  test('D-11 through the app: a transfer brought in before the verdict keeps the worry\'s record; Delete everything does not',
      () async {
    for (final wipe in [false, true]) {
      final vault = MemoryVault();
      final state = makeState(vault);
      final verdict = Completer<bool>();
      state.useRiskCheck((c, t) => verdict.future, 'ready', close: () async {});
      final s = state.newSession();
      await s.start('daily_checkin');
      final sent = s.send("There's no way out of this for me anymore.");
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.leave();
      if (wipe) {
        await state.wipeEverything(folders: () async {});
      } else {
        await state.receiveTransfer(AppData()..journal.add({'date': '2026-11-12', 'text': 'IMPORTED WORDS'}));
      }
      verdict.complete(true);
      await sent;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final stored = await vault.load();
      if (wipe) {
        // everything was deleted on purpose: nothing from before it comes back, the late worry included
        expect(state.data.safetyEvents, isEmpty);
        expect(stored.safetyEvents, isEmpty);
      } else {
        expect(state.data.journal.single['text'], 'IMPORTED WORDS');
        expect(state.data.safetyEvents.where((e) => e['reason'] == 'classifier').length, 1);
        expect(stored.safetyEvents.where((e) => e['reason'] == 'classifier').length, 1);
        expect(stored.safetyWatch, isNull);
      }
    }
  });
}
