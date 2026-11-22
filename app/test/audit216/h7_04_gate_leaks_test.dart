// Audit 216, auditor Y (2026-11-16): H7-04 re-checked against c7f6680.
//
// H7-04 (round 7 review B): the D-05 gate (SafetyResult.plainlySafe) skipped the classifier for a whole message when
// its only worrying words were an everyday phrase, so a plan after it was never read. The fix (core/safety.dart
// _check): plainly safe only when at most 8 words are left once the safe phrases are set aside and none of them is in
// _riskLeft. The review suggested "no second sentence" or "the everyday phrase is the whole message"; a short second
// sentence still passes:
// - "Hanging up the washing, then I'm off to the railway line." is the sixth example in the finding's own table, and it
//   is still never put to the classifier: "railway" and "line" are not in _riskLeft (which has "train" and "tracks").
// - "I don't want to wake up early on Saturday. Or at all." turns the everyday phrase into a wish not to wake up, and
//   _everyday's own comment says "never 'at all'"; it is still plainly safe.
// (The denials taken back in a second sentence, test/audit216y/s3_retraction_hidden_test.dart, pass the same gate.)
//
// Each test asserts the classifier is asked (not plainly safe), so each fails on c7f6680. The five examples the fix
// covered are the controls.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

const covered = [
  'Said goodbye to everyone at my leaving do. Tomorrow I take the whole bottle with vodka.',
  'Said goodbye to everyone at my leaving party. Now I can finally take the whole bottle.',
  "I wake up early on Saturday, then I'm taking the whole bottle.",
  'Rope for the tent is sorted, the tree in the woods is perfect.',
  "Bought cord for the washing line, it's strong enough to hold my weight.",
];

const stillSkipped = [
  "Hanging up the washing, then I'm off to the railway line.",
  "I don't want to wake up early on Saturday. Or at all.",
];

void main() {
  const rules = SafetyCheck();
  for (final m in covered) {
    test('H7-04 control: "$m" is put to the classifier', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').plainlySafe, isFalse);
    });
  }
  for (final m in stillSkipped) {
    test('H7-04: "$m" is put to the classifier', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').plainlySafe, isFalse,
          reason: 'read as plainly safe: the classifier is never asked and the rules show nothing');
    });
  }
}
