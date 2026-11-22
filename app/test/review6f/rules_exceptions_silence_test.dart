// Review round 6 F (F6-01, F6-02): two exceptions added in round 5 (D-09) silence explicit statements. Each message
// below is a crisis by any reading; the phrase rules return none. The F6-01 messages also stay under the classifier's
// threshold in every app context (risk 0.0000000 for three of the four; "I didn't say no" alarms only after a reply);
// the F6-02 messages are caught by the classifier today (risk 1.0), so they ask the safety question instead of opening
// the crisis screen, and once the owner's D-05 change stops sending the classifier a message whose only worrying words
// the rules read as plainly safe, nothing reads them (docs/security/review_round6_F_2026-11-15.md, section 2). These
// tests failed at 4a8da11 and pass since the round 6 rules fixes (fix/d05-precision).
//
// F6-01, "asked about ... and I didn't ...": _deniedAfter takes any "and I" + a negative word in the rest of the
// sentence as the person answering no ("and I haven't"), so "and I didn't deny it", "and I didn't say no", "and no, I
// haven't stopped" and "and I didn't know what to say because I am" all read as a denial.
//
// F6-02, the accident and fear exceptions read only the sentence the words are in: _onlyAccidents tests its "meant"
// words on the sentence of the match, and _onlyFears (the harm-OCD exception added in round 5) its _wanted words on the
// sentence of the fear, so "I burned myself on the kettle. I did it on purpose." or "I'm scared I'll cut myself. I
// really want to." is read as an accident or a fear; "can't stop thinking about the razor" in the same sentence is not
// one of _wanted's words either. Four of the accident messages below reach neither layer today (classifier at most
// 0.9984, 0.0013, 0.0002 and 0.026 in the app's contexts); the rest are caught by the classifier today and would be
// read by nothing once the D-05 change skips the classifier for words the rules read as plainly safe.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

const askedAbout = [
  'My therapist asked me about suicide and I didn\'t deny it.',
  'She asked if I wanted to kill myself and I didn\'t say no.',
  'My mum asked if I was suicidal and I didn\'t know what to say because I am.',
  'They asked about self-harm and no, I haven\'t stopped.',
];

const accidents = [
  'I burned myself on the kettle. I did it on purpose.',
  'I cut myself while cooking. I wanted to see the blood.',
  'I cut myself chopping onions. Then I kept going, deeper.',
  'I cut myself shaving. Every morning. It\'s the only thing that helps.',
];

/// Everyday-phrase exceptions (round 4 and 5 precision fixes) that also hide a crisis; the classifier catches each
/// today (risk 0.99999 to 1.0 in the app's contexts), so they ask the question rather than open the crisis screen, and
/// are exposed the same way once the D-05 change skips the classifier for words the rules read as safe.
const everydayPhrases = [
  "I'm going to end it here for good.", // "here for" is excepted ("end it here for today")
  "I'm ready to end it for now and for always.", // "for now" is excepted
  'This is my final goodbye to this life.', // "goodbye to" anything but a listed word is excepted
  "After his suicide I've been planning mine.", // "his suicide" is a bereavement
  "I've taken my life into my own hands, the pills are next to me.", // "take my life into" is excepted
];

const fears = [
  'I\'m scared I\'ll cut myself. I really want to.',
  'I\'m afraid I\'ll burn myself. I think I deserve it.',
  'I worry I\'ll cut myself. I\'ve bought new blades.',
  'I\'m frightened I\'ll cut myself, I can\'t stop thinking about the razor.',
  'What if I cut myself? It would make the pain stop.',
];

void main() {
  const rules = SafetyCheck();
  for (final m in askedAbout) {
    test('F6-01: "$m" is a crisis', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').level, SafetyLevel.crisis);
    });
  }
  for (final m in accidents) {
    test('F6-02 (accident exception): "$m" is a crisis', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').level, SafetyLevel.crisis);
    });
  }
  test('F6-02 (accident exception, concern): "I fell and hurt myself. Well, I didn\'t fall. I did it myself." is at '
      'least a worry', () {
    expect(rules.check("I fell and hurt myself. Well, I didn't fall. I did it myself.", sessionKind: 'daily_checkin').level,
        isNot(SafetyLevel.none));
  });
  for (final m in everydayPhrases) {
    test('F6-02 (everyday-phrase exception): "$m" is a crisis', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').level, SafetyLevel.crisis);
    });
  }
  for (final m in fears) {
    test('F6-02: "$m" is a crisis', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').level, SafetyLevel.crisis);
    });
  }
  // the exceptions' own purpose still holds after a fix: these stay quiet
  for (final m in [
    'My counsellor asked if I\'d ever thought about suicide, and I haven\'t.',
    'What if I cut myself while chopping vegetables? I worry about it all the time.',
  ]) {
    test('control: "$m" stays quiet', () {
      expect(rules.check(m, sessionKind: 'daily_checkin').level, SafetyLevel.none);
    });
  }
}
