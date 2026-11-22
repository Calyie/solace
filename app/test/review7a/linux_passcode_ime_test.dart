// Round 7 review A, G7-07 (the proof failed on c8e45c9 and passes since the round 7 fix): round 6's E-06 fix describes the Linux passphrase boxes to the input method as passwords
// (TextInputType.visiblePassword, which the Linux embedder maps to GTK_INPUT_PURPOSE_PASSWORD:
// engine/src/flutter/shell/platform/linux/fl_text_input_channel.cc), but the app lock's own passcode, which on Linux is
// the only way to unlock (on every device since 2026-11-15: ui/app_lock.dart), is typed in boxes of
// TextInputType.number, which the embedder passes on as GTK_INPUT_PURPOSE_NUMBER with no sign that the text is
// hidden: an input method that predicts or learns is told an ordinary number. The same holds for the boxes where it is
// chosen, and for the deep work key. This test asserts the SAFE behaviour (on Linux), so it fails while the finding
// stands.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';

import '../app_flow_test.dart' as flow;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  testWidgets('G7-07: on Linux the lock screen passcode reaches the input method as a password', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final state = flow.makeState(demo: true);
      final code = (await tester.runAsync(() => hashPasscode('123456')))!;
      state.data.settings
        ..appLock = true
        ..passcode = code;
      await flow.pumpApp(tester, state);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lock_code')), findsOneWidget, reason: 'precondition: the passcode lock screen');
      await tester.tap(find.byKey(const Key('lock_code')));
      await tester.pump();
      final args = tester.testTextInput.setClientArgs!;
      expect(args['obscureText'], isTrue, reason: 'hidden on screen');
      // the safe behaviour, as E-06 made it for the passphrase: described to the Linux input method as a password
      expect((args['inputType'] as Map)['name'], 'TextInputType.visiblePassword',
          reason: 'the Linux embedder tells the input method this is an ordinary number (GTK_INPUT_PURPOSE_NUMBER)');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
