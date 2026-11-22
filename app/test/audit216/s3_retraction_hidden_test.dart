// Audit 216, auditor Y (2026-11-16): S3 re-checked against c7f6680.
//
// S3 (cycle 2 review): a denial followed by the truth silenced a crisis ("I don't want to kill myself but I will").
// The fix (80e0e56) lists words after a denial that say the risk is still there (core/safety.dart _stillThere: "but i
// am", "i am though", "lie", "wrong", ...). A denial taken back in a sentence of its own is not in that list, so the
// rules read the message as denied, and since the owner's D-05 gate (15 November) a message whose only risk words were
// denied is "plainly safe" (SafetyResult.plainlySafe: at most 8 words left and none in _riskLeft), so the classifier is
// not asked either (core/session.dart send). These messages reach neither layer: nothing is recorded or shown, and
// the trained check, on by default, never reads them. Before D-05 the classifier still read them.
//
// Each test asserts the intended behaviour (a crisis, or at the least the classifier asked), so each fails on c7f6680.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

const takenBack = [
  "I'm not suicidal. Actually, I am.",
  "I'm not going to kill myself. Well, I am.",
  'No thoughts of suicide. That\'s not true.',
  "I'm not suicidal. That's what I tell everyone.",
  "I'm not suicidal. Okay, I am.",
];

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
);

void main() {
  const rules = SafetyCheck();

  test('S3 control: the fixed form, a denial with "but I will", is a crisis', () {
    expect(rules.check("I don't want to kill myself but I will", sessionKind: 'daily_checkin').level,
        SafetyLevel.crisis);
  });

  for (final m in takenBack) {
    test('S3: "$m" is not read as plainly safe (a crisis, or at least put to the classifier)', () {
      final r = rules.check(m, sessionKind: 'daily_checkin');
      expect(r.level == SafetyLevel.crisis || !r.plainlySafe, isTrue,
          reason: 'rules: ${r.level.name}, plainly safe: ${r.plainlySafe}; neither layer reads it');
    });
  }

  test('S3 in a session: a denial taken back is at least put to the classifier', () async {
    final asked = <String>[];
    final data = AppData();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: MemoryVault(),
        riskCheck: (c, t) async {
          asked.add(t);
          return false;
        }, clock: () => DateTime(2026, 11, 16, 9));
    await s.start('daily_checkin');
    await s.send("I'm not suicidal. Actually, I am.");
    expect(asked.isNotEmpty || s.crisisCards.isNotEmpty, isTrue,
        reason: 'no rule fired and the classifier was never asked: nothing recorded (${data.safetyEvents})');
  });
}
