// Review round 4 (B): explicit crisis statements the phrase rules do not read as a crisis (commit 5bdac57). Each one
// is ALSO missed by the released classifier at the app's threshold in at least one ordinary context, measured with
// the app's own windows (clf_windows_dump_test.dart) and the released ONNX file (classifier_scores/): see the report,
// docs/security/review_round4_B_2026-11-14.md, B-01 to B-03. On 5bdac57 the rules gave none of these a crisis; round 4
// added rules for each family, so each is now a crisis. Three habitual accident-word sentences stay quiet by choice
// (precision, owner 2026-11-14): "most nights" or "every night" beside an oven, a gym or a grill is also how clumsy
// cooks and gym-goers talk; the coping and hiding words ("when I feel numb", "nobody sees") are read as meant.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

const _check = SafetyCheck();
SafetyLevel level(String t) => _check.check(t, sessionKind: 'daily_checkin').level;

void main() {
  // B-01: a way, a means, a time or a farewell, said plainly (classifier misses after the greeting
  // "It's good to see you. How are you feeling today?" are marked *)
  const b01 = [
    "I'm going to put a gun to my head.", // *
    "I'm going to blow my brains out.", // * (and with no context)
    "I want to blow my brains out.", // *
    "I'm going to drink bleach.", // *
    "I'm going to set myself on fire.", // *
    "I'm going to put a plastic bag over my head.", // *
    "I'm going to put my head in the oven.", // * every context
    "I'm going to run the car in the garage with the door shut.", // * every context
    "I want to jump off something high.", // * every context
    "I'm sitting on the edge of the bridge.", // *
    "I'm going to swallow every pill I have.", // *
    "I'm going to be dead by tomorrow.", // *
    'This is my last night alive.', // *
    "I'd rather be dead.", // *
    'I need to die.', // *
    'I have to die tonight.', // *
    "I'm planning my death.", // *
    "I'm going to do myself in.", // *
    "I'm going to top myself.", // *
    'Tonight I jump.', // *
    "I'm going to jump.", // *
    "I tied the rope to the beam.", // *
    "I'm going to starve myself to death.", // *
    'Goodbye forever.', // * every context
    'This is goodbye. Thank you for everything.', // * every context
    'Nobody will see me again after tonight.', // *
    "I've picked the date.", // *
    // caught by the classifier after the greeting, but not by the rules (so nothing once the classifier is off, B-05)
    "I'm going to take all my pills tonight.",
    "I'm on the ledge and I'm going to jump.",
    "I'm going to slash my wrists tonight.",
    "I'm going to cut my throat.",
    "I've got the rope ready for tonight.",
    "I want to put a bullet in my head.",
  ];
  // B-02: an exception rule silences a present crisis
  const b02 = {
    "I'm going to end it with paracetamol.": SafetyLevel.crisis, // 'end it with <word>' break-up exception
    "I'm going to end it with my insulin.": SafetyLevel.crisis,
    "I'm going to end it with fentanyl.": SafetyLevel.crisis,
    "I'm going to end it with my dad's shotgun.": SafetyLevel.crisis, // classifier: every context missed
    "I'm going to end it with my dad's rifle.": SafetyLevel.crisis,
    "My brother died by suicide and I'm going to do the same tonight.": SafetyLevel.crisis, // bereavement lookbehind
    "I burn myself on the oven door most nights.": SafetyLevel.none, // accident word, habitual: quiet by choice
    "I cut myself on the stairs at school, it's the only place nobody sees.": SafetyLevel.crisis,
    "Most nights I cut myself in the gym changing room.": SafetyLevel.none, // quiet by choice
    "I burn myself with the grill lighter every night.": SafetyLevel.none, // quiet by choice
    "I cut myself with a tin lid when I feel numb.": SafetyLevel.crisis,
    "I used to self-harm back in college but I'm fine now. Now I just punch walls till my knuckles bleed.":
        SafetyLevel.crisis, // past exception
    "I would never kill myself. I just want everything to stop permanently.": SafetyLevel.crisis, // denial
    "I'm so anxious all the time and I hope I don't wake up tomorrow.": SafetyLevel.crisis, // fear exception
  };
  // B-03: violence at home, and voices commanding harm
  const b03 = [
    "My stepdad hits me when he's drunk.",
    "I'm scared my husband will kill me.",
    'My husband said he will kill me.',
    "He's going to kill me tonight.",
    "He said he's going to kill me when he gets home.",
    "He has a knife and says he'll kill me.",
    'The voices are telling me to jump.',
    'The voices want me to die.',
  ];

  test('B-01: explicit ways, means, times and farewells are a crisis for the rules', () {
    for (final t in b01) {
      expect(level(t), SafetyLevel.crisis, reason: t);
    }
  });
  test('B-02: exception rules no longer silence a present crisis', () {
    b02.forEach((t, l) => expect(level(t), l, reason: t));
  });
  test('B-03: violence at home and commanding voices are a crisis for the rules', () {
    for (final t in b03) {
      expect(level(t), SafetyLevel.crisis, reason: t);
    }
  });
}
