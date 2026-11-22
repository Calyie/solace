// Superseded 2026-11-15 (round 7 review, H7-05). Round 5 review (D-02): the first message of a session follows the app's own opening line, which says nothing about
// the person; after it the classifier missed plain plans it catches anywhere else. The first message is also read on
// its own (the higher risk counting); later messages are read only with the therapist's last words, as before.
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
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

void main() {
  // a classifier that, like the real one after an ordinary opening, alarms on this sentence only when read on its own
  const plan = "There's no way out of this for me anymore.";
  final asked = <String>[];
  Future<bool> riskCheck(String context, String text) async {
    asked.add(context.isEmpty ? 'alone' : 'with context');
    return context.isEmpty && text == plan;
  }

  SessionController session() => SessionController(model: const StandInModel(), prompts: prompts, data: AppData(),
      vault: MemoryVault(), riskCheck: riskCheck, clock: () => DateTime(2026, 11, 15, 9));

  setUp(asked.clear);

  // round 7 review, H7-05 (owner, 2026-11-15: precision first): the reading on its own (round 5 review, D-02) nearly
  // quadrupled plainly safe worries on a first message, so every message is read once, with the therapist's last words
  test('the first message is read once, with the opening line, never on its own', () async {
    final s = session();
    await s.start('daily_checkin');
    await s.send(plan);
    expect(asked, ['with context']);
    expect(s.lastSafety.level, SafetyLevel.none);
  });

  test('later messages are read only with the therapist\'s last words too', () async {
    final s = session();
    await s.start('daily_checkin');
    await s.send('Work was long today.');
    asked.clear();
    await s.send(plan);
    expect(asked, ['with context']);
  });
}
