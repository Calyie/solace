// The first reply after a check-in never reads its numbers back (core/check_in_guard.dart): the pattern on the
// replies the trained E2B phone files really wrote (tests/check_in_readback.py, 2026-11-13), and the guard on scripted
// models: a later sentence left out, a first sentence started again, the plain opening after every try failed.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/check_in_guard.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';

/// Writes its replies in order, a few characters at a time, and counts the tries.
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

Future<String> reply(ModelRuntime m, CheckIn c) => guardedReply(m, const [], c).join();

const mood4 = CheckIn(mood: 4, safety: 'fine');

void main() {
  modeNames();

  test('the read-backs the trained phone files wrote are caught', () {
    for (final (text, c) in [
      ("You mentioned you're feeling like a 4 today.", mood4),
      ('I noticed your mood is a bit lower than last week, sitting at a 4.', mood4),
      ("You mentioned you're feeling a bit low today, around a four out of ten.", mood4),
      ('Before we dive in, I wanted to check in on that mood of 4.', mood4),
      ('Your mood is at a 2 today.', const CheckIn(mood: 2)),
      ('You mentioned your mood was a 5 out of 10 this morning.', const CheckIn(mood: 5)),
      ('You marked 5/10 today.', const CheckIn(mood: 5)),
      ('Your distress went from 70 to 30, which is a big drop.', const CheckIn(practice: 'x', start: 70, end: 30)),
    ]) {
      expect(readsBack(text, c), isTrue, reason: text);
    }
  });

  test('numbers that are something else are not read-backs', () {
    for (final (text, c) in [
      ("It's good to see you. How have things been since we last spoke?", mood4),
      ('How did the 4 days at your sister\'s go?', mood4),
      ('Did you try the ten-minute walk?', const CheckIn(mood: 10)),
      ('Shall we take a 10-minute pause?', const CheckIn(mood: 10)),
      ('You did it four times this week.', mood4),
      ('The distress had come right down by the end. What did you notice?', const CheckIn(start: 70, end: 30)),
    ]) {
      expect(readsBack(text, c), isFalse, reason: text);
    }
  });

  test('a later sentence that reads the mood back is left out, the rest kept', () async {
    final m = ScriptedModel(['Welcome back. I noticed your mood is sitting at a 4. How have things been since we spoke?']);
    expect(await reply(m, mood4), 'Welcome back. How have things been since we spoke?');
    expect(m.tries, 1);
  });

  test('a first sentence that reads it back starts the reply again, unseen', () async {
    final m = ScriptedModel(["You're at a 4 today. How did it go?", "It's good to see you. What has been on your mind?"]);
    expect(await reply(m, mood4), "It's good to see you. What has been on your mind?");
    expect(m.tries, 2);
  });

  test('a one-sentence read-back is tried again, and the plain opening comes after three', () async {
    final m = ScriptedModel(['I noticed you marked a four for your mood this morning; how has your day been?']);
    expect(await reply(m, mood4), fallbackOpening);
    expect(m.tries, 3);
  });

  test('a clean reply passes whole, in one try', () async {
    const text = "Hi there. I've seen your check-in. What has been on your mind since we last spoke?";
    final m = ScriptedModel([text]);
    expect(await reply(m, mood4), text);
    expect(m.tries, 1);
  });

  test('only a check-in with numbers is guarded', () {
    expect(hasNumbers(null), isFalse);
    expect(hasNumbers(const CheckIn(skipped: true)), isFalse);
    expect(hasNumbers(const CheckIn(safety: 'fine')), isFalse);
    expect(hasNumbers(mood4), isTrue);
    expect(hasNumbers(const CheckIn(practice: 'x', start: 60, end: 20)), isTrue);
  });
}

void modeNames() {
  test('a reply never names a mode: the sentence is left out, the rest kept', () async {
    expect(namesMode("Since we're meeting in full mode today, let's check in."), isTrue);
    expect(namesMode('Deep work mode is on.'), isTrue);
    expect(namesMode('Your sense of being in full flow came back.'), isFalse);
    expect(namesMode('That sounds like your normal routine.'), isFalse);
    final m = ScriptedModel(["Hi Julien, good to see you. Since we're meeting in full mode today, I want to check in. "
        'How has the week been?']);
    expect(await withoutModeNames(m.generate(const [])).join(), 'Hi Julien, good to see you. How has the week been?');
    final first = ScriptedModel(["It's good to see you. We're in full mode today. What has been on your mind?"]);
    expect(await reply(first, mood4), "It's good to see you. What has been on your mind?");
  });
}
