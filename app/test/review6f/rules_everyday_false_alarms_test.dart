// Failed at 4a8da11; passes since the round 6 rules fixes (fix/d05-precision).
// Review round 6 F (F6-06): phrase rules that open the crisis screen at once on ordinary, safe speech. Each line is an
// everyday sentence a person could say in a check-in; each is a crisis for the rules at 4a8da11 (so every test here
// fails there), which opens the full crisis screen and starts the 7-day watch with no question first. The owner's rule
// is precision first ("too many alarms make the app feel accusatory"); the classifier is held to it, the rules are
// not. Grouped by the rule that fires.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

const everyday = {
  'not wanting to live (someone else not waking up; a shift; a migraine)': [
    "The baby didn't wake up once last night, finally some sleep.",
    "My son didn't wake up in the night for the first time in weeks.",
    "I didn't wake up when my alarm went off so I was late again.",
    "I don't want to wake up for the 6am shift again.",
    "I hope I don't wake up with a migraine again.",
  ],
  'overdose (taking a prescribed dose)': [
    'I took my tablets this evening like always.',
    "I took my pills before bed and still couldn't sleep.",
    'I took a paracetamol and went to bed early.',
    'Overdosed on chocolate this weekend, no regrets.',
  ],
  'violence at home (games and sport)': [
    "She beat me at tennis again, she's so good.",
    'My dad beat me at chess.',
    'My brother beats me at every video game.',
    'He hit me with a snowball and we all laughed.',
  ],
  'warning signs, goodbyes (gifts, leaving work, travel)': [
    'I gave away my old bike to my nephew.',
    'I gave away my concert ticket to a friend because I was sick.',
    'I wrote a goodbye note to the team on my last day.',
    "I'm not going to be around much next month, I'm moving house.",
  ],
  'method seeking, means and plans, not existing': [
    'We visited the tallest building in the world on holiday.',
    "I'm going to jump! The parachute instructor says I'm ready.",
    "I'm tired of living out of a suitcase for work.",
  ],
};

void main() {
  const rules = SafetyCheck();
  everyday.forEach((group, lines) {
    for (final l in lines) {
      test('F6-06 [$group]: "$l" does not open the crisis screen', () {
        expect(rules.check(l, sessionKind: 'daily_checkin').level, isNot(SafetyLevel.crisis));
      });
    }
  });
}
