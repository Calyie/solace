// Audit 216, auditor Y (2026-11-16): H7-02 re-checked against c7f6680.
//
// H7-02 (owner, 2026-11-15: nothing under 90 percent precision may show): a worry from the phrase rules ("I can't keep
// going", "I hurt myself") is recorded and shows nothing. The fix is in SessionController._sendNow only
// (core/session.dart, `if (level == SafetyLevel.concern) lastSafety = none`). The other path that reads words with the
// rules and sets lastSafety, checkDropped (the part of a paste a full box could not take), still sets lastSafety to the
// rule's concern (core/session.dart, the `whole.level == SafetyLevel.concern` branch), and the chat shows ConcernLine
// whenever lastSafety is a concern (ui/chat.dart `chat_concern`). So the support line the owner removed for rule
// worries still shows when the worry is in the dropped part of an overlong paste.
//
// Each test asserts the intended behaviour (recorded, nothing shown), so it fails on c7f6680.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
);

void main() {
  test('H7-02 control: the same worry typed and sent shows nothing (the fixed path)', () async {
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: AppData(), vault: MemoryVault(),
        clock: () => DateTime(2026, 11, 16, 9));
    await s.start('daily_checkin');
    await s.send("I can't keep going at this pace at work.");
    expect(s.lastSafety.level, SafetyLevel.none);
  });

  test('H7-02: a rule worry in the dropped part of an overlong paste is recorded but shows no support line', () async {
    final data = AppData();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: MemoryVault(),
        clock: () => DateTime(2026, 11, 16, 9));
    await s.start('daily_checkin');
    // a long paste of ordinary notes whose end, past the 12,000 characters a box takes, holds a rule worry
    final paste = '${'Notes from the week, work was busy and the trains were late. ' * 200}'
        "Honestly I can't keep going at this pace at work.";
    expect(paste.length, greaterThan(maxInput));
    await s.checkPasted(paste);
    expect(data.safetyEvents.where((e) => e['level'] == 'concern'), isNotEmpty, reason: 'the worry is recorded');
    expect(s.lastSafety.level, SafetyLevel.none, reason: 'the support line (ConcernLine) shows for a rule worry');
  });
}
