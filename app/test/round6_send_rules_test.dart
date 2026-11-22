// Round 6 review F, F6-13: at Send, a message longer than rulesInIsolateAtSend (3,000 characters) is read by the
// phrase rules in a background isolate, never on the interface thread, and still before anything else the message
// does: a crisis is recorded and acted on before the reply starts, and a crisis in words sent during a reply is acted
// on before the screen hears it was busy. This file puts the real isolate back (test/flutter_test_config.dart runs the
// rules in place for widget tests) and tells which isolate ran the rules with a rule set that names it.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

/// The app's own rules, with the isolate that ran them in the reason when they find nothing.
class _NamesIsolate extends SafetyCheck {
  const _NamesIsolate();
  @override
  SafetyResult check(String text, {required String sessionKind}) {
    final r = super.check(text, sessionKind: sessionKind);
    return r.level == SafetyLevel.none ? SafetyResult(SafetyLevel.none, 'ran in ${Isolate.current.debugName}') : r;
  }
}

/// The stand-in, whose replies wait for [release] once [hold] is called; [asked] counts the replies begun.
class _HoldingModel extends StandInModel {
  _HoldingModel();
  Completer<void>? _gate;
  int asked = 0;
  void hold() => _gate = Completer<void>();
  void release() => _gate?.complete();
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    asked++;
    final gate = _gate;
    if (gate != null) await gate.future;
    yield* super.generate(messages, maxTokens: maxTokens);
  }
}

void main() {
  final prompts = Prompts(
    system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
    note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
    story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
    split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
  );
  setUp(() => runRulesApart = rulesInIsolate); // the app's own way, the background isolate
  final long = 'I went to the shops and then I came home and made some tea. ' * 60; // about 3,600 characters
  final main = Isolate.current.debugName;

  SessionController make(_HoldingModel model, {SafetyCheck safety = const _NamesIsolate()}) => SessionController(
      model: model, prompts: prompts, data: AppData(), vault: MemoryVault(), safety: safety,
      clock: () => DateTime(2026, 11, 15, 19));

  test('a short message is read in place, a long one in a background isolate', () async {
    expect(long.length, greaterThan(rulesInIsolateAtSend));
    final s = make(_HoldingModel());
    await s.start('daily_checkin');
    await s.send('A quiet day today.');
    expect(s.lastSafety.reason, 'ran in $main');
    await s.send(long);
    expect(s.lastSafety.reason, startsWith('ran in '));
    expect(s.lastSafety.reason, isNot('ran in $main'), reason: 'the rules ran on the interface thread');
  });

  test('a crisis at the end of a long message is acted on before the reply starts', () async {
    final model = _HoldingModel();
    final s = make(model, safety: const SafetyCheck());
    await s.start('daily_checkin');
    final askedBefore = model.asked;
    var crisisBeforeReply = false;
    s.addListener(() {
      if (s.crisisCount > 0 && model.asked == askedBefore) crisisBeforeReply = true;
    });
    await s.send('${long}I want to kill myself tonight.');
    expect(s.crisisCount, 1);
    expect(s.lastSafety.level, SafetyLevel.crisis);
    expect(crisisBeforeReply, isTrue, reason: 'the crisis came after the reply had started');
    expect(s.data.safetyEvents.where((e) => e['level'] == 'crisis'), hasLength(1));
  });

  test('a crisis in long words sent during a reply is acted on before the screen hears it was busy', () async {
    final model = _HoldingModel();
    final s = make(model, safety: const SafetyCheck());
    await s.start('daily_checkin');
    model.hold();
    final first = s.send('Work was hard today.');
    await Future<void>.delayed(Duration.zero);
    expect(s.busy, isTrue);
    var crisisAtBusy = -1;
    await expectLater(s.send('${long}I want to kill myself tonight.').catchError((Object e) {
      crisisAtBusy = s.crisisCount;
      throw e;
    }), throwsA(isA<SessionBusy>()));
    expect(crisisAtBusy, 1, reason: 'support opens from the words kept in the box, before Busy is said');
    model.release();
    await first;
    // sent again once the reply has finished: the crisis was acted on already, so it is not recorded twice
    await s.send('${long}I want to kill myself tonight.');
    expect(s.data.safetyEvents.where((e) => e['level'] == 'crisis'), hasLength(1));
  });

  test('a fault in the rules apart is recorded, never silent, and the message is still answered', () async {
    runRulesApart = (rules, text, kind) async => throw StateError('rules');
    final model = _HoldingModel();
    final s = make(model);
    await s.start('daily_checkin');
    await s.send(long);
    expect(s.data.safetyEvents.where((e) => e['level'] == 'error'), hasLength(1));
    expect(s.busy, isFalse);
    expect(s.turns.last.$1, 'therapist');
  });
}
