// Review round 7 B (H7-01): the phrase rules open the support card (a crisis: the card in the conversation, a crisis
// record and the 7-day watch, so the next sessions open with "Last time things felt very heavy") on plainly safe
// everyday sentences none of the rules' exceptions anticipate. Each line was written by hand for this review (never
// seen by the rules' authors), except the last, a real CACTUS client line (one of the 47 CACTUS lines the rules call a
// crisis). Every test asserts the safe behaviour, so each fails on c8e45c9. Grouped by the rule that fires.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

const plainlySafe = {
  'violence at home (feeling unsafe at home for a reason that is not a person)': [
    "I don't feel safe at home since the burglary, I keep checking the locks.",
    "I don't feel safe at home with all the black mould, the landlord won't fix it.",
  ],
  'violence at home (a child asleep, play)': [
    'My daughter kicked me in her sleep all night.',
    'My brother punched me on the arm for winning at FIFA.',
  ],
  'unsafe alone (safety in the street or at work)': [
    "I'm worried about my safety walking home at night in the dark.",
    "I'm worried about my safety at work, the scaffolding looks dodgy.",
  ],
  'goodbyes and arrangements (leaving work; someone else dying)': [
    "I'm saying goodbye to everyone on Friday, it's my last day.",
    'Gran is not going to be around much longer, the hospice says weeks.',
  ],
  'self-harm (a workout; an accident with a door)': [
    'I need to cut my arm workout short because of my elbow.',
    'I hit myself on the head with the cupboard door, ouch.',
  ],
  'overdose, method seeking (vitamins, coffee)': [
    'The nurse said the overdose of vitamin D was nothing to worry about.',
    'I had a lethal dose of caffeine today, four espressos.',
  ],
  'means and plans (a tax return, a view, a punch bag, climbing)': [
    "I'm going to do it tonight when the kids are asleep, finally sort the tax return.",
    "I'm standing on the edge of the cliff path taking photos, the view is amazing.",
    'I tied a rope to the beam in the garage to hang the punch bag.',
    "I've got the rope ready for the climbing trip tomorrow.",
  ],
  'not existing (paperwork)': [
    "I'm tired of life admin, there's always another form.",
  ],
  'self-harm (a fear of an accident while cooking: CACTUS client line)': [
    'Sure. Just last week, I was chopping vegetables and kept thinking I was going to cut myself. My hands were '
        'trembling because I was so worried. I kept thinking, "What if I get hurt? I\'m so careless."',
  ],
};

void main() {
  const rules = SafetyCheck();
  plainlySafe.forEach((group, lines) {
    for (final l in lines) {
      test('H7-01 [$group]: "$l" does not open the support card', () {
        final r = rules.check(l, sessionKind: 'daily_checkin');
        expect(r.level, isNot(SafetyLevel.crisis), reason: 'rule "${r.reason}" calls a plainly safe sentence a crisis');
      });
    }
  });
}
