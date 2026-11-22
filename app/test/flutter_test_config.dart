// Every test in this folder: the phrase rules a session runs apart at Send (core/session.dart runRulesApart, round 6
// review F, F6-13) and the memory search index (core/search.dart buildSearchIndexApart, round 9 review B, 9B-01) run in place, the same rules on the same text, because a widget test's simulated clock cannot wait
// on another isolate. test/round6_send_rules_test.dart puts the background isolate back and tests it.
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solace/core/search.dart';
import 'package:solace/core/session.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  runRulesApart = (rules, text, sessionKind) async => rules.check(text, sessionKind: sessionKind);
  buildSearchIndexApart = (inputs) async => SearchIndex.build(inputs); // round 9 review B, 9B-01
  // the phrase rules on long text off the interface thread (round 9 review B, 9B-03): in place inside a widget test,
  // in a real isolate in a plain test
  runWorkApart = <R>(R Function() work) async => _inWidgetTest() ? work() : await Isolate.run(work);
  // Every screen's text is in a selection area since 2026-11-19 (ui/premium.dart Readable). A selection area asks the
  // platform once for its text actions (SystemChannels.processText); a device answers at once (Android's engine, or an
  // empty reply elsewhere), but the test engine never does, so every screen a test had shown stayed in memory and the
  // largest test files ran out of their 4 GB (responsive_test.dart: 4.7 GB). Answered here as a device without
  // text actions answers.
  setUp(() {
    try {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.processText, (_) async => null);
    } catch (_) {} // no binding: a plain test, which shows no screen
  });
  await testMain();
}

/// True while a testWidgets body runs (its clock is simulated); false in a plain test.
bool _inWidgetTest() {
  try {
    return TestWidgetsFlutterBinding.instance.inTest;
  } catch (_) {
    return false; // no binding yet: a plain test
  }
}
