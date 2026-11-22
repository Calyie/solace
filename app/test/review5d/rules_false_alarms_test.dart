// Review round 5 (D): everyday sentences the phrase rules treat as a crisis (the crisis screen opens at once). Found
// with hand-written probes and the 472,628 CACTUS client lines (two of these are CACTUS lines verbatim). On ca6a73b
// each opened the crisis screen; since the round 5 rules none does, except the dance partner, kept on purpose: "my
// partner would be better off without me" is a burden thought whatever the partner is for.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

const rules = SafetyCheck();

void crisis(String text) =>
    expect(rules.check(text, sessionKind: 'daily_checkin').level, SafetyLevel.crisis, reason: text);
void quiet(String text) =>
    expect(rules.check(text, sessionKind: 'daily_checkin').level, isNot(SafetyLevel.crisis), reason: text);

void main() {
  test('D-09: everyday phrases no longer open the crisis screen', () {
    quiet("I'm finally taking my life in a new direction."); // 'suicide+' lacks the "in a ..." exception 'suicide' has
    quiet('This is my final goodbye to smoking.');
    crisis('This is my final goodbye to my family.'); // a farewell to people still is // 'farewells'
    quiet("My counsellor asked if I'd ever thought about suicide, and I haven't."); // a report and a denial after it
    quiet("I used to self-harm in school but I've been clean for ten years.");
    crisis("I used to self-harm in school but I've been clean for two days."); // not over // plainly past, but no "over" word
    crisis('I start thinking that I’ll never be a good dancer and that my partner would be better off without me.');
    quiet('I picture him telling me that I’m just not good enough and that the team is better off without me.');
  });

  test('D-09: a fear of hurting oneself by accident (health anxiety, harm OCD) no longer opens the crisis screen', () {
    // CACTUS line, verbatim: an OCD-style "what if" fear while cooking
    quiet('Yes, just yesterday, I was trying to cook dinner. As soon as I started chopping vegetables, I thought, '
        '"What if I cut myself?" and then, "It\'s just a matter of time before I ruin dinner."');
    quiet("Even the smell of food sometimes triggers it. I immediately start worrying that I'll burn myself.");
    crisis("I'm scared I'll cut myself again tonight, the urges are so strong."); // a fear with an urge is not one
  });
}
