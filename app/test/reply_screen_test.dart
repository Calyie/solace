// The model's replies are screened a sentence at a time before the person sees or hears them (security review
// 2026-11-14, AI-4; core/check_in_guard.dart ReplyScreen, core/safety.dart meansInReply): a sentence that gives a way or
// a means to die, or quotes the session's mode line, is replaced by a warm fallback that points to Support, and only
// the rule group is recorded. Caring replies, including ones about suicide, pass exactly as written. A sentence that
// gives a phone number is replaced by a pointer to Support too (round 5 review, D-12).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/check_in_guard.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/review.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

/// Writes its replies in order, a few characters at a time, like the real model streams.
class ScriptedModel implements ModelRuntime {
  ScriptedModel(this.replies);
  final List<String> replies;
  var tries = 0;
  @override
  String get name => 'scripted';
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    final r = replies[tries++ % replies.length];
    for (var i = 0; i < r.length; i += 5) {
      yield r.substring(i, i + 5 > r.length ? r.length : i + 5);
    }
  }
}

final normalLine = modeLines['normal']!, fullLine = modeLines['full']!;

/// Realistic therapist replies that must reach the person exactly as written.
const caring = [
  "It sounds like you've been having thoughts of ending your life. Thank you for telling me.",
  "I'm really glad you told me you've been thinking about suicide. That takes courage, and you don't have to carry "
      'it alone.',
  "It sounds like you've thought about an overdose, and I'm glad you told me. Are you safe right now?",
  'Have you taken anything, or done anything to hurt yourself tonight?',
  'If you have taken an overdose, please tap Support at the top now, or call emergency services.',
  "Can you tell me what you took, and how many tablets? Then please tap Support at the top.",
  "I'm so sorry about your brother's death from an overdose. Grief like that can feel unbearable.",
  'It took courage to tell me about the pills you have been saving.',
  "When the urge to cut gets strong, could we try holding an ice cube for a minute? It's a way to ride the wave.",
  "You mentioned feeling like you can't go on. What has been the hardest part of today?",
  "It sounds like you've been stuck in survival mode: always braced for the next thing.",
  'Would you like to try the written approach (Written Exposure Therapy) for that memory?',
  'For memories like this, the written approach can help, and we can go at your pace.',
  "That's a really big step, and it took a lot to get out of bed today.",
  'Count how many tablets are left in the packet, then put them back in the cupboard.',
  "It makes sense that you feel numb after everything; numbness is often the mind's way of protecting you.",
  "Since you're feeling so low, a five-minute walk might be a small kindness to yourself. How does that sound?",
  // keeping means out of reach, and getting help, said plainly
  'Would you be willing to give your tablets to your sister to look after for now?',
  'Could you put the razor blades somewhere out of reach, maybe with a friend?',
  "It's really important to get checked at A&E after taking too many tablets, even if you feel fine.",
  "Many people who survive an overdose say they're glad to be alive.",
  "You've had enough, and part of you has thought about an overdose. I'm glad you're still here talking to me.",
  "You've been thinking about an overdose for 2 weeks now, and that's a long time to carry it alone.",
  'Your dad died of carbon monoxide poisoning, and it makes sense that the anniversary is hard.',
  'Thank you for telling me you took some pills earlier. Please tap Support at the top now.',
  'Are you saving up tablets?',
];

/// Replies in a reliving session (deep work mode), where the support person is part of the plan.
const caringReliving = [
  'Before we begin, I want to check that a support person is present with you.',
  "I'm glad a support person is with you today. We'll go slowly, and you can say stop at any time.",
];

void main() {
  test('caring replies pass the screen exactly as written, in both modes', () {
    for (final text in [...caring, ...caringReliving]) {
      for (final line in [normalLine, fullLine]) {
        final screen = ReplyScreen(modeLine: line);
        expect(screen.groupOf(text), isNull, reason: text);
        expect(screen.pass(text), text, reason: text);
      }
    }
  });

  test('a caring reply streams through the session filter unchanged', () async {
    for (final text in caring) {
      final events = <String>[];
      final out = await withoutModeNames(ScriptedModel([text]).generate(const []),
          screen: ReplyScreen(modeLine: normalLine, onBlocked: events.add)).join();
      expect(out, text);
      expect(events, isEmpty, reason: text);
    }
  });

  test('a way or a means to die is caught, by its rule group', () {
    for (final (text, group) in [
      ('The lethal dose of paracetamol is lower than most people think.', 'method seeking'),
      ('Cutting along the wrist is more dangerous than across it.', 'method seeking'),
      ('The highest bridge in the city is the one by the port.', 'method seeking'),
      ('Carbon monoxide from car exhaust can kill within minutes.', 'method seeking'),
      ('Death from carbon monoxide is usually quick.', 'method seeking'),
      ('The quickest way to die would be from a height.', 'method seeking'),
      ('How long would it take to die that way? Usually hours.', 'method seeking'),
      ('Taking 30 paracetamol tablets would be enough to cause liver failure.', 'overdose'),
      ('An overdose of 20 tablets usually takes a few days to cause harm.', 'overdose'),
      ('A paracetamol overdose damages the liver over several days.', 'overdose'),
      ('How many pills would it take? About twenty.', 'overdose'),
      ('Mixing the pills you take with vodka would make them far more dangerous.', 'overdose'),
    ]) {
      expect(ReplyScreen(modeLine: normalLine).groupOf(text), group, reason: text);
    }
  });

  // Known costs, kept visible: a sentence that names a drug's overdose is replaced even when it urges help (the
  // fallback still points to Support, which carries the emergency numbers), and the person's own rule for the tallest
  // buildings applies to the model's words too.
  test('known trade-offs: these are replaced, and the fallback still points to Support', () {
    for (final text in ['Paracetamol overdose can cause serious harm even when you feel fine, so please go to A&E now.',
        'The tallest building in your city could be a lovely place for the photo you mentioned.']) {
      expect(ReplyScreen().pass(text), meansFallback, reason: text);
    }
    expect(meansFallback, contains('Support'));
  });

  test('a sentence with a means is replaced before it is shown; the rest of the reply stays', () async {
    final events = <String>[];
    final m = ScriptedModel(["I hear how much pain you're in. The lethal dose of paracetamol is lower than people "
        "think. You don't have to face this night alone."]);
    final shown = <String>[];
    await for (final piece in withoutModeNames(m.generate(const []),
        screen: ReplyScreen(modeLine: normalLine, onBlocked: events.add))) {
      shown.add(piece);
    }
    expect(shown.join(), "I hear how much pain you're in. $meansFallback You don't have to face this night alone.");
    expect(shown.any((p) => p.contains('paracetamol')), isFalse, reason: 'never shown, even for a moment');
    expect(events, ['method seeking']);
  });

  test('several such sentences bring the fallback once, and each group is reported once', () async {
    final events = <String>[];
    final m = ScriptedModel(['Okay. The lethal dose is lower than you think. An overdose of 20 tablets would do it. '
        'Cutting along the wrist is worse. Please stay safe.']);
    final out = await withoutModeNames(m.generate(const []),
        screen: ReplyScreen(modeLine: normalLine, onBlocked: events.add)).join();
    expect(out, 'Okay. $meansFallback Please stay safe.');
    expect(events, ['method seeking', 'overdose']);
  });

  test('a reply that is nothing but means becomes the fallback alone', () async {
    final out = await withoutModeNames(ScriptedModel(['The lethal dose of paracetamol is about 10 grams']).generate(const []),
        screen: ReplyScreen()).join();
    expect(out, meansFallback);
  });

  test('the screen runs on every reply even when no mode line is given', () async {
    final out = await withoutModeNames(ScriptedModel(['Death from carbon monoxide is quick. I am here.'])
        .generate(const [])).join();
    expect(out, '$meansFallback I am here.');
  });

  test('a reply that repeats its instructions never shows the mode line', () async {
    final events = <String>[];
    final m = ScriptedModel(['Sure. Mode: $normalLine What would you like to talk about?']);
    final out = await withoutModeNames(m.generate(const []),
        screen: ReplyScreen(modeLine: normalLine, onBlocked: events.add)).join();
    expect(out, 'Sure. $setupFallback What would you like to talk about?');
    expect(out.toLowerCase(), isNot(contains('reliving')));
    expect(out, isNot(contains('Mode:')));
    expect(events, ['mode line']);
  });

  test('quotes of the mode line are caught; its ordinary words are not', () {
    for (final text in ['Mode: Normal.', '**Mode:** Normal', 'My settings say mode: normal.',
        "I'm not able to lead spoken reliving here.", 'Do not lead spoken reliving.',
        'For trauma memories use only the written approach.', 'If asked, offer the written approach.']) {
      expect(quotesModeLine(text, normalLine), isTrue, reason: text);
    }
    expect(quotesModeLine('Spoken reliving is allowed only in a session the app has opened.', fullLine), isTrue);
    for (final text in ['We could use the written approach.', 'Written Exposure Therapy has good evidence.',
        'That sounds like your normal routine.', "It's normal to feel this way.", 'You were in fight-or-flight mode: '
        'your body was protecting you.']) {
      expect(quotesModeLine(text, normalLine), isFalse, reason: text);
    }
  });

  test('the first reply after a check-in is screened too', () async {
    final events = <String>[];
    final m = ScriptedModel(["It's good to see you. Carbon monoxide from a car would kill you quickly. How are you?"]);
    final out = await guardedReply(m, const [], const CheckIn(mood: 4, safety: 'fine'),
        screen: ReplyScreen(modeLine: normalLine, onBlocked: events.add)).join();
    expect(out, "It's good to see you. $meansFallback How are you?");
    expect(m.tries, 1, reason: 'a replaced sentence never starts the reply again');
    expect(events, ['method seeking']);
  });

  test('the review letter leaves such a sentence out and reports only its group', () {
    final groups = <String>[];
    final words = cleanReflection('This week held some brighter moments. The lethal dose is lower than you think. '
        'You kept showing up.', onBlocked: groups.add);
    expect(words, 'This week held some brighter moments. You kept showing up.');
    expect(groups, ['method seeking']);
  });

  // round 5 review, D-12: a number the model writes is not checked for the person's country or dated, as the app's
  // Support list is, so a sentence that gives one is replaced by a pointer to Support
  group('D-12: phone numbers in replies', () {
    const phones = [
      'If you are in the US, please call or text 988 right now.',
      'You can call the Samaritans on 116 123, day or night.',
      'Please call 999 to get an ambulance.',
      'Text HOME to 741741 to reach a counsellor.',
      'The National Suicide Prevention Lifeline is 1-800-273-8255.',
      'You could try +44 20 7946 0958, they are open late.',
      'Their number is (555) 123-4567.',
      'Childline is free on 0800 1111.',
      'Lifeline Australia: 13 11 14.',
      '988 is there for you at any hour.',
      'In an emergency, dial 112 anywhere in Europe.',
      'Ring 0800 068 41 41 if you need someone to talk to.',
      'You can reach them on 08457 90 90 90.',
      'Call 1-800-SUICIDE if you are in the States.',
    ];
    const everyday = [
      "You've rated your mood 6 out of 10 today.",
      'On a scale of 0 to 100, how strong is the urge right now?',
      'Last week you said 6/10, and today it is lower.',
      'Support is there 24/7, whenever you need it.',
      'Could you call your sister at 7.30 this evening?',
      'Maybe call the surgery when they open at 10:30.',
      'You could ring your mum at 5pm.',
      'In 2019 you moved house, and 2020 was hard too.',
      'That was back on 2026-11-14, a few days ago.',
      'The 2019-2020 school year sounds like it was really tough.',
      'Try the 5-4-3-2-1 exercise: five things you can see.',
      'Box breathing is 4-4-4-4, and 4-7-8 breathing is another.',
      'You have been sober for 100 days, and that matters.',
      'Your doctor raised the dose to 100mg last month.',
      'You spent £250 on the phone bill, and that worries you.',
      'Write about 200 words, then stop and take a breath.',
      'You could text your friend 3 things you like about her.',
      'A 12,000-step walk is a lot; maybe start with 2,000.',
      'Your PHQ-9 score went from 14 to 9 over 6 weeks.',
      'You have called 2 friends this week, and that is a real step.',
      'It is 1 000 000 times harder when you are this tired.',
      "You've been thinking about an overdose for 2 weeks now, and that's a long time to carry it alone.",
    ];

    test('a sentence with a phone number or a hotline code is caught', () {
      for (final text in phones) {
        expect(phoneInReply(text), isTrue, reason: text);
        expect(ReplyScreen().pass(text), phoneFallback, reason: text);
      }
    });

    test('everyday numbers in prose are left alone, and caring replies still pass exactly', () {
      for (final text in [...everyday, ...caring, ...caringReliving]) {
        expect(phoneInReply(text), isFalse, reason: text);
        expect(ReplyScreen(modeLine: normalLine).pass(text), text, reason: text);
      }
    });

    test('in a streamed reply only the sentence with the number is replaced, and the group is reported once', () async {
      final events = <String>[];
      final m = ScriptedModel(["I'm really glad you told me. Please call the crisis line on 0800 123 4567 tonight. "
          'You could also text 85258. You are not alone in this.']);
      final out = await withoutModeNames(m.generate(const []),
          screen: ReplyScreen(modeLine: normalLine, onBlocked: events.add)).join();
      expect(out, "I'm really glad you told me. $phoneFallback You are not alone in this.");
      expect(events, [phoneGroup]);
      expect(phoneFallback, contains('Support'));
    });

    test('the check is linear: long crafted sentences take a few milliseconds', () {
      for (final text in ['1 ' * 100000, '(1' * 100000, '+1 ' * 70000, '12.' * 70000, 'call ${'9 ' * 100000}',
          '${'a1' * 100000} call', '1,' * 100000, '${'1-' * 100000}x']) {
        final sw = Stopwatch()..start();
        phoneInReply(text);
        expect(sw.elapsedMilliseconds, lessThan(200), reason: text.substring(0, 6)); // a few ms on the laptop
      }
    });
  });

  group('in a session', () {
    final prompts = Prompts(
      system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
      note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
      story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
      split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
    );
    final now = DateTime(2026, 11, 14, 20);

    test('the stored turn holds the fallback, the event holds only the group, nothing unsafe was ever streamed',
        () async {
      final data = AppData();
      final model = ScriptedModel(['Hello. How are you today?',
          'That sounds so heavy. An overdose of 30 paracetamol tablets would damage your liver. I am here with you.']);
      final s = SessionController(model: model, prompts: prompts, data: data, vault: MemoryVault(), clock: () => now);
      final streamed = <String>[];
      s.addListener(() => streamed.add(s.streaming));
      await s.start('daily_checkin');
      await s.send('Things are really hard.');
      expect(s.turns.last, ('therapist', 'That sounds so heavy. $meansFallback I am here with you.'));
      expect(streamed.any((x) => x.contains('paracetamol')), isFalse);
      final output = data.safetyEvents.where((e) => e['level'] == 'output').toList();
      expect(output, [{'date': '2026-11-14', 'level': 'output', 'reason': 'overdose'}]);
      expect(output.single.values.join(' '), isNot(contains('paracetamol')));
    });

    test("a caring reply about suicide is stored exactly as written, with no event", () async {
      final data = AppData();
      const reply = "It sounds like you've been having thoughts of ending your life. Thank you for telling me.";
      final s = SessionController(model: ScriptedModel(['Hello. How are you today?', reply]), prompts: prompts,
          data: data, vault: MemoryVault(), clock: () => now);
      await s.start('daily_checkin');
      await s.send('I have been thinking about ending my life.');
      expect(s.turns.last, ('therapist', reply));
      expect(data.safetyEvents.where((e) => e['level'] == 'output'), isEmpty);
      // the person's own words still go through the crisis rules exactly as before
      expect(data.safetyEvents.where((e) => e['level'] == 'crisis').single['reason'], 'suicide');
      expect(s.crisisCount, 1);
    });

    test('the mode line is screened against the session’s own mode', () async {
      final data = AppData();
      final s = SessionController(model: ScriptedModel(['Mode: Normal. Do not lead spoken reliving. Hello there.']),
          prompts: prompts, data: data, vault: MemoryVault(), clock: () => now);
      await s.start('daily_checkin');
      expect(s.turns.single, ('therapist', '$setupFallback Hello there.'));
      expect(data.safetyEvents.single, {'date': '2026-11-14', 'level': 'output', 'reason': 'mode line'});
    });
  });
}
