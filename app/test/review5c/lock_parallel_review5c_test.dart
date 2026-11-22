// Review round 5, reviewer C, C-04 (FAILS on ca6a73b; passes once fixed): the lock screen's passcode box submits on Return (onSubmitted) even while a
// check is running (_busy only disables the Unlock button), and the wait after five wrong codes is read before a
// check starts and written only after it ends. So codes submitted while a check runs are all tried, past the wait.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';

import '../app_flow_test.dart' as flow;
import '../onboarding_test.dart' show waitFor;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  testWidgets('C-04: codes sent with Return while a check runs are not tried past the wait',
      (tester) async {
    final stored = (await tester.runAsync(() => hashPasscode('135791')))!;
    final state = flow.makeState();
    state.data.settings
      ..appLock = true
      ..lockAfterMinutes = 0
      ..passcode = stored
      ..lockFails = 4; // the next wrong code starts a 30-second wait
    await flow.pumpApp(tester, state);
    expect(find.text('Solace is locked'), findsOneWidget);
    // three codes, each sent with Return while the check before it is still running (no time passes between them)
    for (final code in ['000001', '000002', '000003']) {
      await tester.enterText(find.byKey(const Key('lock_code')), code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    await waitFor(tester, () => state.data.settings.lockFails >= 7 || find.textContaining('Try again in').evaluate().isNotEmpty,
        tries: 200);
    await waitFor(tester, () => state.data.settings.lockFails >= 7, tries: 100);
    // only one code may be tried: the first miss starts the wait, so the second and third must not be checked
    expect(state.data.settings.lockFails, 5, reason: 'codes sent with Return during a check were all tried');
  });

  testWidgets('control: codes sent one after another (each after the last check ends) stop at the wait', (tester) async {
    final stored = (await tester.runAsync(() => hashPasscode('135791')))!;
    final state = flow.makeState();
    state.data.settings
      ..appLock = true
      ..lockAfterMinutes = 0
      ..passcode = stored
      ..lockFails = 4;
    await flow.pumpApp(tester, state);
    for (final code in ['000001', '000002', '000003']) {
      await tester.enterText(find.byKey(const Key('lock_code')), code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(tester, () => find.textContaining('Try again').evaluate().isNotEmpty, tries: 100);
    }
    expect(state.data.settings.lockFails, 5);
  });
}
