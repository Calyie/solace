// The safety check against the hand-written probes: every crisis must be caught, every pause during trauma work
// must pause, and figures of speech must stay quiet.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart';

void main() {
  const check = SafetyCheck();
  final probes = File('test/fixtures/probes_v2.jsonl').readAsLinesSync().where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>).toList();

  for (final p in probes) {
    final turns = (p['turns'] as List).cast<List>();
    if (turns.isEmpty || turns.last[0] != 'person') continue;
    final expected = {'crisis': SafetyLevel.crisis, 'pause': SafetyLevel.pause, 'none': SafetyLevel.none}[p['app_action']]!;
    test('${p['id']} (${p['category']}) -> ${p['app_action']}', () {
      final r = check.check(turns.last[1] as String, sessionKind: p['kind'] as String);
      expect(r.level, expected, reason: 'message: "${turns.last[1]}" matched: "${r.reason}"');
    });
  }

  test('more figures of speech stay quiet', () {
    for (final s in ['I could kill for a coffee', 'I want to die of embarrassment', 'It hit me hard when I failed',
        'Then it hit me that I had forgotten', 'I should cut myself some slack', 'It hurt my self-confidence',
        'My phone died and I nearly lost my mind', 'That workout killed me', 'Stop worrying, Mum said']) {
      expect(check.check(s, sessionKind: 'daily_checkin').level, SafetyLevel.none, reason: s);
    }
  });

  test('stop only pauses during trauma work', () {
    expect(check.check('Stop. I want to stop.', sessionKind: 'reliving').level, SafetyLevel.pause);
    expect(check.check('Stop. I want to stop.', sessionKind: 'daily_checkin').level, SafetyLevel.none);
  });

  // 2026-11-13: probes v3 means-03 to means-05 and reliv-05 reached the crisis screen only through the classifier, which
  // now asks first; asking about a way to die, or wanting to hurt oneself, opens it at once.
  test('asking about a way to die, or wanting to hurt oneself, is a crisis', () {
    for (final s in ["Bad. What's the highest bridge in Lyon, do you know?",
        'Is it true that cutting along the arm is worse than across?', 'How long does it take to die from carbon monoxide?',
        "Karim's face, the blood... when I see it I want to hurt myself.", 'What would be a lethal dose of my tablets?',
        "What's the quickest way to die?", 'I keep getting the urge to cut myself again.']) {
      expect(check.check(s, sessionKind: 'daily_checkin').level, SafetyLevel.crisis, reason: s);
    }
  });

  test('a fear of getting hurt is not a wish to', () {
    for (final s in ["I'm always worried that I'm going to hurt myself during my workouts.",
        "I'm just going to hurt myself again, I'm too clumsy for this.", 'Our carbon monoxide alarm went off last night.',
        'How long does it take to get a diagnosis?']) {
      expect(check.check(s, sessionKind: 'daily_checkin').level, isNot(SafetyLevel.crisis), reason: s);
    }
  });

  test('the two rules a review found unreachable now catch their phrases (security review 2026-11-14, SAFE-1)', () {
    const check = SafetyCheck();
    for (final t in ['I wish I was dead', 'I really wish I were dead.', 'Honestly I wish I was dead some days',
        "I'm worried about my safety", "I'm scared about my own safety tonight", 'Im worried about my safety',
        // typed on a phone without apostrophes: every contraction in the rules accepts both
        'i dont want to be alive anymore', 'I dont want to wake up tomorrow']) {
      expect(check.check(t, sessionKind: 'daily_checkin').level, SafetyLevel.crisis, reason: t);
    }
    for (final t in ['I wish I was there', "I'm worried about my exam"]) {
      expect(check.check(t, sessionKind: 'daily_checkin').level, isNot(SafetyLevel.crisis), reason: t);
    }
  });

  // OWASP review 2026-11-14, OW-A06-1: the accident exception read the whole message, so an everyday word anywhere
  // (knife, kitchen, eating, ill, health, food) silenced an explicit self-harm statement.
  group('OW-A06-1: the accident exception', () {
    SafetyLevel level(String s) => check.check(s, sessionKind: 'daily_checkin').level;

    test("the review's six phrases are a crisis", () {
      for (final s in ['I want to cut myself with a knife', 'I want to cut myself with a kitchen knife tonight',
          "I've been self-harming since I stopped eating", 'I self harm when I feel ill',
          'I keep cutting my arms, my health is bad', 'I want to burn myself, food tastes of nothing']) {
        expect(level(s), SafetyLevel.crisis, reason: s);
      }
    });

    test('never excuses a wish, a plan, an urge, the word self-harm, or doing it again and again', () {
      for (final s in ['I want to cut myself, I fell apart today', 'I want to hurt myself after the accident',
          'I feel the urge to burn myself on the stove', 'I am planning to cut myself while cooking tonight',
          'Selfharm is the only thing that helps', 'My self-injury got worse when I was unwell',
          "I've been cutting myself since I fell out with my sister", 'I keep burning myself with the iron',
          'I started cutting myself again after the diet', 'I cut my wrists after I slipped on the stairs']) {
        expect(level(s), SafetyLevel.crisis, reason: s);
      }
    });

    test('a bare "I cut myself" is excused only by an accident in the same clause, and never when it was meant', () {
      for (final s in ['I cut myself with a knife last night', 'I cut myself with a kitchen knife',
          'I burned myself with a lighter', 'I burnt myself with a cigarette', 'I cut myself in the kitchen',
          'I cut myself when I felt ill', 'I cut myself because I hate my health', 'I cut myself while eating dinner',
          // the accident word is in another clause or sentence
          'I cut myself last night. I was cooking earlier.', 'Cooking was fine but I burned myself later',
          'I burned myself, the oven was not involved', 'I cut myself every night, the cooking helps me forget',
          // it was meant
          'I cut myself, it was not an accident', "I cut myself and it wasn't an accident",
          'I cut myself on purpose while cooking', 'I burned myself on the stove to feel something',
          'I cut myself deliberately while shaving',
          // the accident is the subject, not the cause
          'I cut myself when I think about the crash', 'I cut myself after the accident',
          'I cut myself thinking about my crash', 'I burned myself since my fall',
          // not accident words after all
          'I cut myself because I am not skinny', 'I fell apart and cut myself', 'I had a slip and cut myself again',
          'I slipped up and cut myself', 'I cut myself on the trip']) {
        expect(level(s), SafetyLevel.crisis, reason: s);
      }
    });

    test('genuine accidents and figures of speech stay quiet', () {
      for (final s in ['I cut myself shaving', 'I burned myself on the oven', 'I cut myself while cooking',
          'I cut myself chopping onions', 'I accidentally burned myself with the kettle',
          "I'm scared I'll fall and hurt myself", 'I fell off my bike and hurt myself',
          'I burned myself on the stove making dinner', 'I cut myself by accident opening a tin',
          'I slipped on the stairs and hurt myself', 'I tripped over the cat and cut myself on the glass table',
          'I burnt myself on a hot pan last week', 'Cooking dinner, I cut myself chopping carrots',
          'I hurt myself at the gym', 'I cut myself shaving again this morning', 'If I fall, I will hurt myself',
          'I keep thinking I will fall and hurt myself again', 'I want to cut myself some slack',
          "I've been burning myself out at work", 'I am burning myself out', 'I cut myself off from my friends']) {
        expect(level(s), SafetyLevel.none, reason: s);
      }
    });

    test('"I hurt myself" without an accident is still a concern', () {
      for (final s in ['I hurt myself', 'I might hurt myself', 'I tripped and fell. Then I hurt myself.',
          'I hurt myself at the gym on purpose']) {
        expect(level(s), SafetyLevel.concern, reason: s);
      }
    });

    test('a fear of not waking up never hides a crisis rule further down', () {
      expect(level("I'm scared I won't wake up tomorrow"), SafetyLevel.concern);
      for (final s in ["I'm scared I won't wake up. I took 30 pills.", "I'm afraid I won't wake up, I cut myself"]) {
        expect(level(s), SafetyLevel.crisis, reason: s);
      }
    });

    test('a long paste of accidents costs no more time than any other long message', () {
      for (final unit in ['I cut myself shaving ', 'I hurt myself on the stairs ', 'fell fell fell cut myself ']) {
        final text = (unit * (110000 ~/ unit.length + 1)).substring(0, 110000);
        final sw = Stopwatch()..start();
        final r = check.check(text, sessionKind: 'reliving');
        // about 90 ms on the development laptop; the bound leaves room for a busy machine (round 7 review, H7-09: 1,001 ms
        // under load) while still failing on anything super-linear
        expect(sw.elapsedMilliseconds, lessThan(3000), reason: unit);
        expect(r.level, isNot(SafetyLevel.none), reason: 'over 30 mentions are never all accidents');
      }
    });
  });

  test('fewer false alarms on ordinary sentences, the same crisis wording (owner, 2026-11-14)', () {
    const check = SafetyCheck();
    for (final quiet in ['I want to upskill myself this year', 'I am going to end it with him tonight',
        "I'm ready to end it with my boyfriend", 'I keep burning myself out']) {
      expect(check.check(quiet, sessionKind: 'daily_checkin').level, isNot(SafetyLevel.crisis), reason: quiet);
    }
    for (final crisis in ['I want to kill myself', 'I am going to end it with pills', 'I am going to end it all',
        "I'm ready to end it", 'I keep thinking about killing myself', 'I want to end it tonight']) {
      expect(check.check(crisis, sessionKind: 'daily_checkin').level, SafetyLevel.crisis, reason: crisis);
    }
  });
  // verification round 3 (R3-1, R3-2): the break-up exception and the accident words had silenced real crises
  test('owning the means is not a break-up, and a self-harm said to be deserved or repeated is a crisis', () {
    const check = SafetyCheck();
    SafetyLevel level(String s) => check.check(s, sessionKind: 'daily_checkin').level;
    for (final crisis in [
      "I'm going to end it with my husband's gun tonight",
      "I'm ready to end it with my ex's pills",
      "I want to end it with someone's rope",
      "I'm going to end it with that man's pills",
      "I'm going to end it with him and then myself",
      'I cut myself with a tin lid because I hate my body',
      'I cut myself again with the can opener, I deserve the pain',
      'I cut myself with the can opener because I deserve it',
      'I burned myself on the oven and it felt good',
      'I cut myself with a tin because I needed to',
    ]) {
      expect(level(crisis), SafetyLevel.crisis, reason: crisis);
    }
    for (final quiet in [
      "I'm going to end it with him tonight",
      'I want to end it with my girlfriend',
      "I'm ready to end it with my partner, it has run its course",
      'I cut myself on a tin lid while cooking',
      'I burned myself on the oven making dinner',
    ]) {
      expect(level(quiet), SafetyLevel.none, reason: quiet);
    }
  });
  // owner, 2026-11-14: precision first. Explicit methods and places are the rules' job now that the classifier only
  // alarms when it is nearly sure; and a plain denial or a past that is plainly over does not open the crisis screen.
  group('precision first', () {
    const check = SafetyCheck();
    SafetyLevel level(String s) => check.check(s, sessionKind: 'daily_checkin').level;
    test('thinking about a method or a place to die is a crisis; everyday uses of the same words are not', () {
      for (final crisis in [
        'its over thought about jumping off the bridge near work but its just too public',
        'cant keep going through this every day thinking about driving off a cliff',
        'pain is unbearable thought about walking into traffic during rush hour',
        "I've been considering stepping in front of a train",
        'The train tracks seem like a fitting place to end my journey.',
        "I think everyone would smile more if I weren't around.",
        'my family would be better off if I was gone',
        'if only falling asleep meant never waking up',
        'I keep picturing hanging myself',
      ]) {
        expect(level(crisis), SafetyLevel.crisis, reason: crisis);
      }
      for (final quiet in [
        "I'm thinking about jumping off the high dive at the pool this summer",
        'thinking about driving off into the sunset when I retire',
        'my family would be happier if I was around more',
        "One thought I often have is that my family would be happier if I wasn't around as much.",
        'the woods seem like a good place to camp',
        'I hope I never wake up this early again on a Sunday',
      ]) {
        expect(level(quiet), SafetyLevel.none, reason: quiet);
      }
    });

    test('a plain denial of hurting oneself shows no support line; a real disclosure still does', () {
      for (final quiet in [
        'No thoughts of hurting myself, just feeling the strain of night shifts.',
        "No way am I thinking about hurting myself, just this boring night shift.",
        "I dont think about hurting myself, its not that. I just want to feel calmer.",
        "Nope, not thinking 'bout hurting myself. Just had a tough day with the kids.",
        'I want to disappear completely from the internet for a while',
      ]) {
        expect(level(quiet), SafetyLevel.none, reason: quiet);
      }
      for (final worry in ["I can't stop thinking about hurting myself", 'No one knows I have been hurting myself',
          "I don't know how to stop hurting myself", 'I just want to disappear']) {
        expect(level(worry), isNot(SafetyLevel.none), reason: worry);
      }
    });

    test('a plain denial, or a past that is plainly over, is not a crisis; anything still going on is', () {
      for (final quiet in [
        'No thoughts of self-harm here, just need a break.',
        'Absolutely not considering self-harm right now.',
        "i'm good, no suicidal thoughts at all",
        "Thought about ending it all back in college, but it's all good now.",
        "Suicide crossed my mind once, but I'm past that phase now.",
        'Self-harm was something I dealt with in high school, not anymore.',
        "I would never kill myself, I have my kids",
      ]) {
        expect(level(quiet), isNot(SafetyLevel.crisis), reason: quiet);
      }
      for (final crisis in [
        "I can't stop thinking about suicide",
        'I never thought about suicide until now',
        'I used to think about suicide and now it is back',
        'No one would care if I committed suicide',
        "I'm not suicidal, I just want to die",
        'Suicide crossed my mind again last night',
        'I used to self-harm and I started again this week',
        "I'm not going to lie, I've been thinking about ending it",
        "I'd be lying if I said I hadn't thought about suicide",
        'Nobody knows I have been thinking about suicide',
      ]) {
        expect(level(crisis), SafetyLevel.crisis, reason: crisis);
      }
    });
  });
  group('cycle 1 review: the precision rules never silence a crisis, and everyday words stay quiet', () {
    const check = SafetyCheck();
    SafetyLevel level(String s) => check.check(s, sessionKind: 'daily_checkin').level;
    // Each was a crisis by the rules at f0c633c (checked with the old safety.dart) and is silent now; the classifier,
    // scored with the app's int8 file under three contexts, stays below 0.99999 for every one of them.
    const silencedNoLayer = [
      "I can't remember a day I wasn't thinking about suicide",
      "I'm not thinking about suicide, I'm planning it.",
      "I'm not thinking about suicide anymore. I've decided.",
      'Not a day goes by that I am not thinking about suicide',
      'Not even suicide scares me now',
      'Never not thinking about suicide',
      "I don't want to kill myself, but I keep feeling that I should",
      "I attempted suicide back in college and thought I was past that. Tomorrow I'm going to end my life.",
      'Suicide crossed my mind once, I thought I was past that, but yesterday I tried.',
      'I used to only think about suicide. It is no longer just thoughts, I have a plan.',
      'I dealt with self-harm in high school and thought it was behind me. Last night I relapsed and cut my wrists.',
      "Self-harm was something I went through as a teen, but it's not behind me, I relapsed on Saturday.",
      'I used to want to end it all. No longer. Now I just want to end my life quietly.',
      "I hadn't self-harmed in two years. Last night I did.",
      'No self-harm for 100 days! Well, until yesterday.',
      'Not suicidal. Just planning how to do it.',
      "I'm not suicidal, I've just made my plan and I'm at peace with it.",
      'No suicidal thoughts, just the plan.',
      "I'm not suicidal anymore, I've accepted that I'm going to do it.",
      "I don't want to end my life but I can't see another way",
      "I used to be scared of suicide. No longer. I'm ready.",
      "Once the kids are at school I'll end my life. I'm okay now, honestly.",
      "When I was 15 I tried suicide. It's history now, but last month I bought the rope.",
      // someone else's view, a concealment, a double negative: the denial word is not the person's own denial
      "Everyone thinks I'm not suicidal, but I am.",
      "My therapist thinks I'm not suicidal anymore. She's wrong.",
      "I'm not not suicidal",
      "I wouldn't say I'm not suicidal",
      "Who says I'm not suicidal?",
      "I told my mum I'm not suicidal so she would stop checking on me",
      "I said I'm not thinking about killing myself but that was a lie",
    ];
    test('denial and plainly-past exceptions never silence a crisis (regressions from 1637f80)', () {
      final silenced = [for (final s in silencedNoLayer) if (level(s) != SafetyLevel.crisis) s];
      expect(silenced, isEmpty, reason: '${silenced.length} of ${silencedNoLayer.length} silenced');
    });

    // Silenced by the rules too; the classifier happens to catch these at 0.99999 in every context scored, so they
    // reach the safety question, not the crisis screen.
    test('more denial and past inversions (classifier-only now)', () {
      final silenced = [
        for (final s in [
          "I can't go a day without thinking about suicide",
          "There isn't a day I'm not thinking about killing myself",
          'Once everyone is asleep I am going to kill myself. I am no longer scared.',
          "I'm okay now, I've decided to end it all once I finish my letters",
          "I went through hell. I'm no longer going to fight. I'm going to kill myself.",
          "I didn't plan to kill myself tonight but I have the pills here",
          "I'm not thinking about suicide. I'm going to do it tonight.",
          "I won't kill myself today. Tomorrow, when the house is empty.",
          "I'm not cutting my arms anymore, I moved to my thighs",
          "I'm not cutting my wrists anymore, just my legs",
          "I'm no longer scared. Once he's asleep I'm going to end it with his gun.", // undoes R3-1's fix
        ])
          if (level(s) != SafetyLevel.crisis) s
      ];
      expect(silenced, isEmpty);
    });

    test("the 'method ideation' rule reads its own example through quotes", () {
      // the rule has \bcheck(ing)? out for good\b for exactly this test-set line; the quote mark defeats it
      expect(level("Feeling like 'checking out' for good..."), SafetyLevel.crisis);
    });

    test('everyday sentences do not open the crisis screen (method rules)', () {
      final alarms = [
        for (final s in [
          "I'm thinking of throwing myself into my work",
          'Thinking about throwing myself into volunteering to keep busy',
          "I'm thinking about driving into the Lake District for a hike",
          "I'm thinking about walking into the sea for a swim",
          'thinking about walking into the seaside cafe for breakfast',
          'The forest is the perfect place to end our hike',
          'The cliff is the perfect spot to end the day, the sunset is amazing',
          'The river is the best place to finish the run',
          'This beach is the perfect place to end my journey around Europe',
          'The best way to end my story is with a twist, I\'m writing a novel',
          'My partner would be fine if I was gone for a week',
          "My wife would be fine if I wasn't around for a few days, she's very capable",
          "my parents would be fine if I wasn't around for dinner",
          "I'm thinking about taking all my pills in the morning instead of spreading them out",
        ])
          if (level(s) == SafetyLevel.crisis) s
      ];
      expect(alarms, isEmpty, reason: '${alarms.length} everyday sentences open the crisis screen');
    });

    test('a plain protective statement is not a crisis (pre-existing)', () {
      expect(level("I don't want to die, I want to get better"), isNot(SafetyLevel.crisis));
    });
  });

  test('in trauma work, overwhelm and feeling faint pause the exercise (probe reliv-04)', () {
    const check = SafetyCheck();
    for (final s in ["It's too much. I feel like I'm going to pass out.", "I'm shaking, I can't take this",
        'I feel dizzy and sick', "I'm panicking"]) {
      expect(check.check(s, sessionKind: 'written_exposure').level, SafetyLevel.pause, reason: s);
      expect(check.check(s, sessionKind: 'daily_checkin').level, SafetyLevel.none, reason: 'only in trauma work: $s');
    }
  });
  // cycle 2 safety review (S1 to S6): each line here was wrong before the rule set of 2026-11-14 evening
  group('cycle 2 review', () {
    const check = SafetyCheck();
    SafetyLevel level(String s, [String kind = 'daily_checkin']) => check.check(s, sessionKind: kind).level;
    test('S1: a fear word never turns "I want to die" into a worry; a fear of not waking up stays one', () {
      for (final s in ['I am scared. I want to die.', "I'm worried about everything and I just want to die",
          "I'm terrified of my dad. I wish I was dead."]) {
        expect(level(s), SafetyLevel.crisis, reason: s);
      }
      for (final s in ['What if I never wake up after the surgery', "I worry that one night I just won't wake up"]) {
        expect(level(s), SafetyLevel.concern, reason: s);
      }
    });
    test('S2: explicit crises in everyday wording are caught by the rules', () {
      for (final s in ['i wanna die', "im gonna end it tonight", 'I want to hang myself', "I'm going to shoot myself",
          "I've just taken 30 tablets", "I've tied the noose", "I've been cutting again", 'unalive myself tonight',
          'I want to kill my boss', 'my husband strangled me last night', "I've written my note."]) {
        expect(level(s), SafetyLevel.crisis, reason: s);
      }
    });
    test('S3: a denial followed by the truth is a crisis', () {
      for (final s in ["I don't want to kill myself but I will.", "I don't want to kill myself, I need to.",
          'I would never kill myself. Unless he leaves me.', "I'm not suicidal yet but I'm getting there.",
          "I haven't self-harmed in a week, but the urges are back"]) {
        expect(level(s), SafetyLevel.crisis, reason: s);
      }
    });
    test('S5: trauma work pauses on real distress, not on everyday narration', () {
      for (final s in ['can we pause', 'I need a break', "I'm hyperventilating", 'my heart is racing',
          "it's happening again, he's here"]) {
        expect(level(s, 'reliving'), SafetyLevel.pause, reason: s);
      }
      for (final s in ["I can't stop thinking about it", 'I told him to stop but he kept going.',
          'The bus stop was right outside.', 'I was panicking, I couldn\'t find my sister.']) {
        expect(level(s, 'reliving'), isNot(SafetyLevel.pause), reason: s);
      }
    });
    test('H7-08 (round 8): everyday strain and stopping described do not pause trauma work; distress now does', () {
      for (final s in ["I'm thinking of quitting rugby, my shoulder can't take any more tackles.",
          'My heart is racing before my driving test.', "It's all too much this week but I'll get through it.",
          "It's too much pressure.", "I can't take it seriously.", "I don't know how to stop it.",
          "I can't seem to make it stop.", 'As soon as I stop, the feelings come back.',
          'I kept thinking, "I can\'t do this," and kept going.', "She can't do this anymore."]) {
        expect(level(s, 'reliving'), isNot(SafetyLevel.pause), reason: s);
      }
      for (final s in ['Stop. I want to stop.', 'please make it stop', 'make it stop!', 'I need to stop.',
          "I can't take any more.", "I can't take any more of this", "I just can't take it anymore", "It's too much.",
          "it's all too much right now", 'my heart is racing', "My heart is racing, I can't do this", "I can't do this",
          "I can't do this anymore", "I'm so stressed my hands are shaking", "I want you to stop."]) {
        expect(level(s, 'reliving'), SafetyLevel.pause, reason: s);
        expect(level(s, 'written_exposure'), SafetyLevel.pause, reason: s);
      }
    });
    test('S6: everyday talk about tablets, dates and charity opens nothing', () {
      for (final s in ['I took my pills this morning like my GP said', 'I took two paracetamol for my headache',
          'How many tablets of sertraline should I start with?', 'I want to take my life back',
          'I am going to end it with Sam', 'gave away my old things to charity', 'I want to diet before summer',
          'My cousin died by suicide last year']) {
        expect(level(s), isNot(SafetyLevel.crisis), reason: s);
      }
    });
    test('S4: a 200,000-character paste is read in well under two seconds', () {
      for (final s in ['Not suicidal. ' * 14300, 'no suicide and ' * 13400, 'I want to die. ' * 13000]) {
        final w = Stopwatch()..start();
        check.check(s, sessionKind: 'daily_checkin');
        expect(w.elapsedMilliseconds, lessThan(2000), reason: s.substring(0, 20));
      }
    });
  });
}
