// Review round 9 B, re-check, 9B-09: the 9B-04 marker cannot tell a native load that killed Solace from a start that
// simply ended while the load ran (the person swiped Solace away or closed its window in the first seconds, the phone
// restarted, the system ended a suspended app). Either way the marker stays (core/load_guard.dart run: removed only
// when the load returns), and at every later start that engine is not loaded (main.dart _loadSafetyClassifier,
// loadTrainedModel, loadVoice with atStart) until the person finds Settings and taps Try again. For the trained safety
// check, which the owner keeps on by default and lets only the deep work PIN turn off, one interrupted start turns it
// off for good; the chat then says it is "not set up on this device yet" (phraseRulesNotice with classifierOn true).
//
// The test asserts the SAFE behaviour: after ONE start that ended while the safety check was loading, the next start
// tries it again (it is not reported as stopped). It fails on 1373d75 while the finding stands.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/load_guard.dart';
import 'package:solace/main.dart';

import '../audit_followups_test.dart' as a;

void main() {
  late Directory support;
  setUp(() => support = Directory('build/test_scratch/review9b_marker')..createSync(recursive: true));
  tearDown(() => support.deleteSync(recursive: true));

  test('9B-09: one start that ended while the safety check loaded does not keep it off at the next start', () async {
    // what LoadGuard.run leaves when the app is ended during the classifier's load (its "what" is empty)
    File('${support.path}/loading_classifier').writeAsStringSync('', flush: true);
    final state = a.makeState()..loadGuard = LoadGuard(support);
    expect(state.data.settings.classifierOn, isTrue, reason: 'on by default; nobody typed the deep work PIN');
    await loadDeviceFiles(state, model: (_) async {}, voice: (_) async {});
    expect(state.stoppedLoads.containsKey(Engine.classifier), isFalse,
        reason: 'one interrupted start kept the safety check off: "${state.safetyStatus}"');
  });
}
