// Review round 6 F (F6-10): words left unsent at End or Back are read by the phrase rules (round 5 review, D-15), but
// readLeftUnsent returns at once whenever ANY crisis was acted on during a reply since the last sent message
// (_flaggedWhileBusy != null), whatever the words in the box are now. Someone who typed one crisis during a reply, then
// replaced it with another ("I took 30 tablets an hour ago.") and ended the session, has the second never read or
// recorded. The test failed on 4a8da11; fixed in round 6 (core/session.dart readLeftUnsent skips only the exact words
// acted on, and reads anything new beside them).
import 'package:solace/core/formats.dart';
import 'dart:io';
import 'dart:async';

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
  test('F6-10: a different crisis left unsent after an earlier one was flagged during a reply is still read', () async {
    final data = AppData();
    final verdict = Completer<bool>();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: MemoryVault(),
        riskCheck: (c, t) => verdict.future, clock: () => DateTime(2026, 11, 15, 9));
    await s.start('daily_checkin');
    final sent = s.send('Work was a lot this week.'); // the session stays busy until the classifier answers
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.busy, isTrue);
    await expectLater(s.send('I want to kill myself tonight.'), throwsA(isA<SessionBusy>())); // read at once
    expect(data.safetyEvents.where((e) => e['level'] == 'crisis').length, 1);
    verdict.complete(false);
    await sent;
    // the person deletes those words, types something else instead, and ends without sending it
    final found = await s.readLeftUnsent(['I took 30 tablets an hour ago.']);
    expect(found, isTrue, reason: 'an overdose left in the box at End is a new crisis, never read');
    expect(data.safetyEvents.where((e) => e['level'] == 'crisis').length, 2);
  });
}
