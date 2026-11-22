// Review round 7 B (H7-01, the consequence): one plainly safe sentence the rules call a crisis does more than show a
// card. It is kept as a crisis in the safety records, starts the 7-day watch, and every session in the next 7 days opens
// with "Last time things felt very heavy. How are you doing today?" (core/session.dart _crisis, start). Someone leaving
// their job, said in a daily check-in, is met that way for a week. The test asserts the safe behaviour (no crisis
// record, no watch, no opening check), so it fails on c8e45c9.
import 'package:solace/core/formats.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';


final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
);

void main() {
  test('H7-01: a plainly safe goodbye at work is not kept as a crisis and does not change the next week', () async {
    final data = AppData();
    final vault = MemoryVault();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: vault,
        riskCheck: (c, t) async => false, clock: () => DateTime(2026, 11, 15, 9));
    await s.start('daily_checkin');
    await s.send("I'm saying goodbye to everyone on Friday, it's my last day.");
    expect(s.crisisCards, isEmpty, reason: 'a support card for leaving a job');
    expect(data.safetyEvents.where((e) => e['level'] == 'crisis'), isEmpty, reason: 'kept as a crisis');
    expect(data.safetyWatch, isNull, reason: 'the 7-day watch started');
    final next = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: vault,
        clock: () => DateTime(2026, 11, 18, 9));
    await next.start('daily_checkin');
    expect(next.openingCheck, isFalse, reason: 'three days later the session opens with "Last time things felt very '
        'heavy"');
  });
}
