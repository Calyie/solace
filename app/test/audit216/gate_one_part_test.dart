// Audit 216 fix (H7-04 and S3): a message is plainly safe, and so skips the classifier, only when nothing follows the
// plainly safe words: no second sentence and no second clause ("then", "and then", "but", "or", "or at all"), and
// "railway", "line", "platform" and "at all" are risk words. Each part is checked on its own here, so a later change
// to one of them is caught. The effect is only that the classifier reads more messages: what the rules show is
// unchanged, so every message below keeps its rule level.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

void main() {
  const rules = SafetyCheck();
  SafetyResult read(String m) => rules.check(m, sessionKind: 'daily_checkin');

  test('single plainly safe phrases still skip the classifier', () {
    for (final m in [
      'I cut myself shaving this morning.',
      'I cut myself shaving at 7.30 this morning.', // a decimal point is not a sentence end
      "I don't want to wake up early on Saturday.",
      'I bought rope for the tent.',
      "I'm going to hang the pictures this weekend.",
      'What if I cut myself while chopping onions?',
      "I'm not suicidal.",
    ]) {
      expect(read(m).plainlySafe, isTrue, reason: m);
      expect(read(m).level, SafetyLevel.none, reason: m);
    }
  });

  test('a second sentence after the plainly safe words is read by the classifier', () {
    for (final m in [
      "I cut myself shaving this morning. Whatever.",
      "I'm not suicidal. Actually, I am.",
      "I bought rope for the tent! It's for Sunday.",
      "I don't want to wake up early on Saturday; I'd sleep in.",
      "I'm not suicidal... honestly.",
      // round 10 review B (R10B-01): a comma starts a second part too, so the classifier tells "just need a break"
      // from "that's not true"
      'No thoughts of suicide, just need a break.',
      'No thoughts of suicide, that\'s not true.',
    ]) {
      expect(read(m).plainlySafe, isFalse, reason: m);
    }
  });

  test('a second clause after the plainly safe words is read by the classifier', () {
    for (final m in [
      'Hanging up the washing, then off out.',
      'Hanging up the washing and then off out.',
      "I bought rope for the tent but it's too short.",
      "I don't want to wake up early on Saturday or Sunday.",
    ]) {
      expect(read(m).plainlySafe, isFalse, reason: m);
    }
  });

  test('railway left over is a risk word; line, platform and "at all" are not (round 10 review B, R10B-02)', () {
    expect(read('Hanging up the washing near the railway').plainlySafe, isFalse);
    for (final m in [
      'Hanging up the washing on the line',
      'Hanging up the washing by the platform',
      "I'm not suicidal at all.",
    ]) {
      expect(read(m).plainlySafe, isTrue, reason: m);
    }
    // the second-part check still reads the H7-04 examples
    for (final m in ["I don't want to wake up early on Saturday. Or at all.",
        "Hanging up the washing, then I'm off to the railway line."]) {
      expect(read(m).plainlySafe, isFalse, reason: m);
    }
  });

  test('the rule levels are unchanged: the gate only decides whether the classifier reads', () {
    expect(read("I don't want to kill myself but I will").level, SafetyLevel.crisis);
    expect(read("I'm not suicidal. Actually, I am.").level, SafetyLevel.none);
    expect(read('Hanging up the washing, then I\'m off to the railway line.').level, SafetyLevel.none);
  });
}
