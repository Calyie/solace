// Round 6 review F, F6-11: the classifier's work for one message is a token budget (core/bpe_tokenizer.dart
// tokenBudget, 24 windows), not the 12 windows D-06 kept, so a full box of ordinary non-English text is read whole
// while English prose costs exactly what it did. With the app's real tokenizer (SAFETY_CLF_DIR, the classifier's runs/
// folder) it prints, for a full box (12,000 characters) of each kind, the tokens, the windows the whole box makes, the
// windows read before (D-06) and now, the tokenizer's time, and the classifier's time on this laptop at the measured
// 0.29 s a window (3.5 s for 12 windows, core/session.dart classifierTimeout).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/bpe_tokenizer.dart';
import 'package:solace/core/safety_classifier.dart' show forClassifier;
import 'package:solace/core/session.dart' show classifierWaitFor;

import 'round6_budget_texts.dart';

void main() {
  final dir = Platform.environment['SAFETY_CLF_DIR'];

  test('a full box of every ordinary language is read whole; prose costs what it did; digits keep both ends', () {
    final tok = BpeTokenizer.fromJson(File('$dir/safety_v5_base_s9/model/tokenizer.json').readAsStringSync());
    const before = 12; // round 5's cap (D-06)
    final lines = <String>[];
    final windowsOf = <String, int>{};
    for (final e in fullBoxes.entries) {
      final text = forClassifier(e.value);
      final sw = Stopwatch()..start();
      final kept = tok.windows('', text);
      final ms = sw.elapsedMicroseconds / 1000;
      final all = tok.windows('', text, maxWindowCount: 1 << 20);
      final tokens = tok.encode(text).length;
      windowsOf[e.key] = all.length;
      final readBefore = all.length < before ? all.length : before;
      lines.add('${e.key.padRight(18)} ${'$tokens'.padLeft(5)} tokens ${'${all.length}'.padLeft(3)} windows; read '
          'before ${'$readBefore'.padLeft(2)} (${(100 * readBefore / all.length).round()} %), now '
          '${'${kept.length}'.padLeft(2)} (${(100 * kept.length / all.length).round()} %); tokenizer '
          '${ms.toStringAsFixed(1)} ms; classifier about ${(0.29 * kept.length).toStringAsFixed(1)} s here; '
          'waited for ${classifierWaitFor(text).inSeconds} s');
      if (all.length <= BpeTokenizer.maxWindows) {
        expect(kept, all, reason: '${e.key}: the whole box is read');
      } else {
        expect(kept, [all.first, ...all.sublist(all.length - BpeTokenizer.maxWindows + 1)], reason: e.key);
      }
    }
    // ignore: avoid_print
    print(lines.join('\n'));
    // prose is under the old cap too, so it costs what it did; every ordinary language fits the budget
    expect(windowsOf['English prose'], lessThanOrEqualTo(before));
    for (final language in ['Polish', 'Russian', 'Greek', 'Arabic', 'Hindi', 'Emoji']) {
      expect(windowsOf[language], lessThanOrEqualTo(BpeTokenizer.maxWindows), reason: language);
    }
    expect(windowsOf['Digits (mood log)'], greaterThan(BpeTokenizer.maxWindows)); // still bounded, at twice prose
  }, skip: dir == null ? 'set SAFETY_CLF_DIR to the classifier folder (runs/)' : false);

  test('the budget is twice the windows of a full box of prose, and never no window at all', () {
    expect(BpeTokenizer.maxWindows, 24);
    expect(BpeTokenizer.tokenBudget, 24 * 253);
  });

  // the session's wait for the verdict grows with the text's density as the windows do, so a slow phone reading a
  // whole full box of Greek or Hindi is not counted a fault while one of prose waits exactly as before
  test('the wait for a full box: prose as before, denser text longer, never more than twice', () {
    final waits = {for (final e in fullBoxes.entries) e.key: classifierWaitFor(e.value).inSeconds};
    // ignore: avoid_print
    print(waits);
    expect(waits['English prose'], 63);
    expect(classifierWaitFor('x' * 12000).inSeconds, 63);
    for (final dense in ['Greek', 'Hindi', 'Arabic', 'Russian', 'Emoji', 'Digits (mood log)']) {
      expect(waits[dense], greaterThan(63), reason: dense);
    }
    expect(waits.values.every((w) => w <= 15 + 4 * 24), isTrue);
  });
}
