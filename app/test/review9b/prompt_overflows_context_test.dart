// Review round 9 B, 9B-05: the conversation budget is counted in UTF-8 bytes (core/formats.dart turnBudget = 14,000,
// "about 3,500 tokens of its 8,192 in English"), but some ordinary text costs a token per byte. Gemma's tokenizer
// splits numbers into single digits, so a pasted log of numbers (sleep times, a mood list, a spreadsheet column) is at
// least one token per digit; text the vocabulary lacks falls back to one token per byte. The model's context is 8,192
// tokens (core/llama_model.dart contextSize) and llamadart refuses a longer prompt ("prompt too long"), which the
// session turns into "I lost my place" (core/session.dart _reply). Nothing drops the dense turns until the
// conversation passes 14,000 bytes again, so every reply in between fails, and the note at End too.
//
// The test asserts the SAFE behaviour: the digits sent to the model in one prompt (each at least one token), together
// with a lower bound on the system prompt's tokens and the reply's 220, fit in 8,192. It fails on 3d2da1f.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';

void main() {
  test('9B-05: three pasted number lists never make a prompt longer than the model reads', () {
    final system = File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync();
    final digits = List.generate(4000, (i) => '${(i * 7) % 10}').join(); // 4,000 digits: what one message reaches
    final turns = <(String, String)>[
      ('therapist', 'Hello. How are you today?'),
      ('person', digits), ('therapist', "I'm sorry, I lost my place for a moment. Could you tell me that again?"),
      ('person', digits), ('therapist', "I'm sorry, I lost my place for a moment. Could you tell me that again?"),
      ('person', digits),
    ];
    final prompt = sessionMessages(system, turns);
    final sentDigits = prompt.skip(2).map((m) => RegExp(r'\d').allMatches(m['content']!).length).fold(0, (a, b) => a + b);
    final systemTokensAtLeast = system.length ~/ 6; // a generous lower bound for English prose
    expect(sentDigits + systemTokensAtLeast + 220, lessThanOrEqualTo(8192),
        reason: 'one prompt carries $sentDigits digits (at least that many tokens) plus the instructions: past the '
            "model's 8,192 tokens, so every reply is \"I lost my place\"");
  });
}
