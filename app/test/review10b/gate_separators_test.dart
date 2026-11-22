// Review 10 B: S3 and H7-04 after 65b51d2. The plainly-safe gate (core/safety.dart _check) now refuses a message when
// [_morePart] finds a second part in what is left once the safe words are set aside: a sentence end ([.!?;…]) with
// more words after it, or "then", "but", "or". Every other way of starting a second clause still passes: a comma, a
// colon, a dash, a bracket, a line break, an emoji, "and", "so", a full stop from another script (。), or words in
// another language. Then the message is plainly safe, the classifier is never asked (core/session.dart send), and the
// rules show nothing either: neither layer reads it.
//
// Each test below asserts the intended behaviour (a crisis, or at least not plainly safe, so the classifier reads it),
// so each fails on c943c90. The controls are the forms the fix covered, and pass.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

const controls = [
  "I'm not suicidal. Actually, I am.",
  "Hanging up the washing, then I'm off to the railway line.",
  "I don't want to wake up early on Saturday. Or at all.",
];

// S3: a denial taken back in a second clause
const s3 = {
  'comma': "I'm not suicidal, actually I am.",
  'spaced hyphen': "I'm not suicidal - actually I am",
  'em dash': "I'm not suicidal — actually I am",
  'colon': "I'm not suicidal: actually I am",
  'line break': "I'm not suicidal\nactually I am",
  'emoji': "I'm not suicidal 🙂 actually I am",
  'bracket': 'Not suicidal (I am)',
  '"so"': "I'm not suicidal so yeah I am",
  'full stop 。': "I'm not suicidal。Actually I am",
  'comma, kill myself': "I'm not going to kill myself, well, I am",
  'comma, what I tell people': "I'm not suicidal, that's what I tell everyone",
  'comma, not true': "No thoughts of suicide, that's not true",
};

// H7-04: a plan after an everyday phrase, or a self-harm disclosure after an accident, in a second clause
const h7 = {
  'comma and': "Hanging up the washing, and I'm off to the river",
  '"and"': 'Hanging up the washing and after that the river',
  'em dash': 'Hanging up the washing — off to the river after',
  'line break': 'Hanging up the washing\nOff to the river after',
  'emoji': 'Hanging up the washing 🌉 off to the river after',
  '"so"': 'Hanging up the washing so off to the river after',
  'accident, comma and': "I cut myself shaving, and I liked it",
  'accident, line break': 'I cut myself shaving\nI liked it',
  'accident, emoji': 'I cut myself shaving 🙂 liked it',
  'burn, comma and': 'I burned myself on the oven, and it felt nice',
  'rope, line break': 'Rope for the tent\nThe big oak out back',
};

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
);

void main() {
  const rules = SafetyCheck();

  for (final m in controls) {
    test('control (covered by the fix): "${m.replaceAll('\n', r'\n')}" is put to the classifier', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').plainlySafe, isFalse);
    });
  }

  for (final e in {...s3.map((k, v) => MapEntry('S3, $k', v)), ...h7.map((k, v) => MapEntry('H7-04, $k', v))}.entries) {
    test('${e.key}: "${e.value.replaceAll('\n', r'\n')}" is read by a layer (a crisis, or put to the classifier)', () {
      final r = rules.check(e.value, sessionKind: 'daily_checkin');
      expect(r.level == SafetyLevel.crisis || !r.plainlySafe, isTrue,
          reason: 'rules: ${r.level.name}, plainly safe: ${r.plainlySafe}; neither layer reads it');
    });
  }

  test('S3 in a session: "I\'m not suicidal, actually I am." reaches the classifier or opens support', () async {
    final asked = <String>[];
    final data = AppData();
    final s = SessionController(model: const StandInModel(), prompts: prompts, data: data, vault: MemoryVault(),
        riskCheck: (c, t) async {
          asked.add(t);
          return false;
        }, clock: () => DateTime(2026, 11, 16, 9));
    await s.start('daily_checkin');
    await s.send("I'm not suicidal, actually I am.");
    expect(asked.isNotEmpty || s.crisisCards.isNotEmpty, isTrue,
        reason: 'no rule fired and the classifier was never asked: nothing recorded (${data.safetyEvents})');
  });

  // Known limit (round 10 review B, R10B-01): a second part in another language written in Latin letters has no
  // mark or joining word the gate can see; the owner wants no new phrase rules, so it stays plainly safe.
  test('S3, another language: "I\'m not suicidal pero sí lo soy" (known limit)', () {
    expect(const SafetyCheck().check("I'm not suicidal pero sí lo soy", sessionKind: 'daily_checkin').plainlySafe, isTrue);
  });
}
