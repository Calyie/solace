// The safety check never delays the reply (owner, 2026-11-14: "it should not affect user experience"): the phrase
// rules run first (a fraction of a millisecond for a usual message), the classifier runs beside the reply and its
// verdict is acted on when it arrives, and the session stays busy until it is in. Stop ends a reply at once.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);

/// A classifier the test answers by hand.
class SlowClassifier {
  final asked = <String>[];
  Completer<bool>? _verdict;
  String? _last;
  Future<bool> check(String context, String text) {
    // the first message's second reading on its own (round 5 review, D-02) is answered at once and quietly, so each
    // test here still answers one verdict per message by hand
    if (context.isEmpty && text == _last) return Future.value(false);
    _last = text;
    asked.add(text);
    return (_verdict = Completer<bool>()).future;
  }

  void answer(bool alarm) => _verdict!.complete(alarm);
  void fail() => _verdict!.completeError(StateError('classifier fault'));
}

/// Writes one sentence, then keeps writing (one piece every 10 ms) until told to stop, as the on-device model does.
class EndlessModel extends StandInModel implements ReplyCanceller {
  EndlessModel();
  int cancels = 0;
  bool _cancelled = false;
  bool endless = false;
  @override
  void cancelReply() {
    cancels++;
    _cancelled = true;
  }

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    if (!endless) {
      yield* super.generate(messages, maxTokens: maxTokens);
      return;
    }
    _cancelled = false;
    yield 'I hear you, and that sounds like a long day. ';
    while (!_cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!_cancelled) yield 'And ';
    }
  }
}

SessionController session(AppData data, {ModelRuntime model = const StandInModel(),
        Future<bool> Function(String, String)? riskCheck}) =>
    SessionController(model: model, prompts: prompts, data: data, vault: MemoryVault(), riskCheck: riskCheck,
        clock: () => DateTime(2026, 11, 14, 20));

void main() {
  test('the reply starts and ends without waiting for the classifier; its worry is acted on when it arrives',
      () async {
    final clf = SlowClassifier();
    final data = AppData();
    final s = session(data, riskCheck: clf.check);
    await s.start('daily_checkin');
    final sent = s.send('I want to find my purpose.');
    for (var i = 0; i < 50 && s.turns.length < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(s.turns.length, 3, reason: 'her reply is written while the classifier is still reading');
    expect(s.turns.last.$1, 'therapist');
    expect(s.busy, isTrue, reason: 'busy until the verdict is in, so no later message overtakes it');
    expect(s.checking, isTrue);
    expect(s.streaming, isEmpty, reason: 'the reply is not shown twice');
    expect(s.lastSafety.level, SafetyLevel.none);
    await expectLater(s.send('Another thing.'), throwsA(isA<SessionBusy>()));
    clf.answer(true);
    await sent;
    expect(s.busy, isFalse);
    expect(s.checking, isFalse);
    // owner 2026-11-15: the quiet support line once the verdict is in; no question, nothing paused, edits stay open
    expect(s.lastSafety.level, SafetyLevel.concern, reason: 'the support line appears once the verdict is in');
    expect(s.paused, isFalse);
    expect(data.safetyEvents.single, {'date': '2026-11-14', 'level': 'concern', 'reason': 'classifier'});
    expect(s.editBlocked(), isNull);
  });

  test('a quiet verdict changes nothing, and a classifier fault is recorded, never stopping the conversation',
      () async {
    final clf = SlowClassifier();
    final data = AppData();
    final s = session(data, riskCheck: clf.check);
    await s.start('daily_checkin');
    var sent = s.send('Work was hard today.');
    await Future<void>.delayed(Duration.zero);
    clf.answer(false);
    await sent;
    expect(data.safetyEvents, isEmpty);
    expect(s.lastSafety.level, SafetyLevel.none);
    expect(s.editBlocked(), isNull);
    sent = s.send('And my manager moved the deadline.');
    await Future<void>.delayed(Duration.zero);
    clf.fail();
    await sent;
    expect(s.classifierFailed, isTrue);
    expect(data.safetyEvents.single['level'], 'error');
    expect(s.busy, isFalse);
  });

  test('the phrase rules still act before the reply: a crisis opens support at once, and the classifier is not asked',
      () async {
    final clf = SlowClassifier();
    final data = AppData();
    final s = session(data, riskCheck: clf.check);
    await s.start('daily_checkin');
    final sent = s.send('I want to kill myself tonight.');
    expect(s.crisisCount, 1, reason: 'before any reply');
    expect(data.safetyEvents.single['level'], 'crisis');
    await sent;
    expect(clf.asked, isEmpty);
  });

  // round 7 review, H7-02: a worry from the phrase rules is recorded and shows nothing; the classifier, when turned on,
  // may still show its quiet line once
  test('a worry from the phrase rules is recorded, showing nothing; a classifier worry after it shows its line', () async {
    final clf = SlowClassifier();
    final data = AppData();
    final s = session(data, riskCheck: clf.check);
    await s.start('daily_checkin');
    final sent = s.send("I'm scared I won't wake up tomorrow.");
    expect(s.lastSafety.level, SafetyLevel.none);
    expect(data.safetyEvents.single['level'], 'concern');
    await Future<void>.delayed(Duration.zero);
    clf.answer(true);
    await sent;
    expect(s.lastSafety.level, SafetyLevel.concern);
    expect(data.safetyEvents.map((e) => e['level']), ['concern', 'concern']);
    expect(data.safetyEvents.last['reason'], 'classifier');
  });

  test('while End writes the note the session says so (the screens show it instead of her typing; L-7)', () async {
    final model = SlowNoteModel();
    final s = session(AppData(), model: model);
    await s.start('daily_checkin');
    await s.send('Work was hard today.');
    final ended = s.end();
    await Future<void>.delayed(Duration.zero);
    expect(s.ending, isTrue);
    expect(s.busy, isTrue);
    model.note.complete();
    await ended;
    expect(s.ending, isFalse);
    expect(s.busy, isFalse);
  });

  test('a fault in the rules during a reply still answers SessionBusy, so the screens keep the words', () async {
    final model = SlowNoteModel();
    final data = AppData();
    final clf = SlowClassifier();
    final s = SessionController(model: model, prompts: prompts, data: data, vault: MemoryVault(), riskCheck: clf.check,
        safety: const _FaultyRules(), clock: () => DateTime(2026, 11, 14, 20));
    await s.start('daily_checkin');
    final sent = s.send('Work was hard today.');
    await Future<void>.delayed(Duration.zero);
    await expectLater(s.send('BOOM while she replies'), throwsA(isA<SessionBusy>()));
    expect(data.safetyEvents.last['reason'], 'rules StateError');
    clf.answer(false);
    await sent;
  });

  test('the classifier wait grows with the message: a full box on a slow phone is not a fault', () {
    expect(classifierWaitFor('short'), const Duration(seconds: 15));
    expect(classifierWaitFor('x' * 12000), const Duration(seconds: 63));
  });

  test('a classifier worry, then leaving: nothing is carried to the next session (owner, 2026-11-15)', () async {
    final clf = SlowClassifier();
    final data = AppData();
    final s = session(data, riskCheck: clf.check);
    await s.start('daily_checkin');
    final sent = s.send('I want to find my purpose.');
    await Future<void>.delayed(Duration.zero);
    clf.answer(true);
    await sent;
    s.leave();
    expect(data.safetyWatch, isNull);
    final next = session(data);
    await next.start('daily_checkin');
    expect(next.openingCheck, isFalse);
  });

  test('Stop ends the reply at once and tells the model to stop writing', () async {
    final model = EndlessModel();
    final s = session(AppData(), model: model);
    await s.start('daily_checkin');
    model.endless = true;
    final sent = s.send('Work was hard today.');
    while (s.streaming.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    s.stopReply();
    s.stopReply(); // a second tap does nothing more
    await sent.timeout(const Duration(seconds: 1));
    expect(model.cancels, 1);
    expect(s.busy, isFalse);
    expect(s.turns.last, ('therapist', 'I hear you, and that sounds like a long day.'));
    model.endless = false;
    await s.send('My manager moved the deadline again.');
    expect(s.turns.last.$1, 'therapist', reason: 'the next message is answered as usual');
  });
}

/// Holds the session note until released, as the larger model takes up to a minute to write it.
class SlowNoteModel extends StandInModel {
  SlowNoteModel();
  final note = Completer<void>();
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    if ((messages.last['content'] ?? '').startsWith('The session has ended')) await note.future;
    yield* super.generate(messages, maxTokens: maxTokens);
  }
}

class _FaultyRules extends SafetyCheck {
  const _FaultyRules();
  @override
  SafetyResult check(String text, {required String sessionKind}) {
    if (text.contains('BOOM')) throw StateError('rules fault');
    return super.check(text, sessionKind: sessionKind);
  }
}
