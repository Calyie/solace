// Review round 4 (B): the safety cards (the opening check after a recent crisis, the classifier's safety question and
// the concern banner) were pinned ABOVE the conversation in the chat, outside any scroll view (ui/chat.dart build).
// On a phone on its side or a small phone, with the keyboard up and the largest text, do they still fit, and can the
// person reach the question's answers? Reports overflow and where the answer buttons are. 6 of the 12 layouts failed
// on commit 5bdac57; fixed in round 4 (branch fix/round4-b): the cards are now at the end of the scrolling list,
// right above the message box, and all 12 pass. (Since the same fix round, the opening check goes once a message is
// sent, B-04, so after the send only the question is showing.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/home.dart';

import '../app_flow_test.dart' as flow;
import '../responsive_test.dart' as r;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  for (final device in ['iPhone 16 on its side', 'iPhone SE (1st)']) {
    final size = r.sizes[device]!;
    final portrait = size.height > size.width;
    for (final (look, deviceText, appText, font, mode) in r.looks) {
     for (final up in [false, true]) {
      testWidgets('B-11 $device, $look, keyboard ${up ? 'up' : 'down'}: the opening check and the safety question fit',
          (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = deviceText;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final state = flow.makeState();
        state.data.settings
          ..textSize = appText
          ..font = font
          ..themeMode = mode;
        state.data.safetyWatch = {'since': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
            'reason': 'suicide'};
        state.useRiskCheck((c, t) async => true, 'test classifier');
        await tester.pumpWidget(TherapistApp(state: state));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(HomeShell))).push(MaterialPageRoute(builder: (_) =>
            const ChatScreen(kind: 'daily_checkin')));
        await flow.frames(tester, ms: 800);
        final keyboard = up ? (size.height * (portrait ? 0.42 : 0.5)).roundToDouble() : 0.0;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
        await flow.frames(tester, ms: 400);
        await tester.enterText(find.byType(TextField).last, 'I feel so empty lately.');
        await tester.tap(find.byKey(const Key('chat_send')), warnIfMissed: false);
        await flow.frames(tester, ms: 1200);
        final error = tester.takeException();
        // owner 2026-11-15: no safety question; the classifier's worry is the quiet support line, whose Support button
        // must still be on screen above the keyboard
        final q = find.byKey(const Key('chat_concern'));
        final yes = find.descendant(of: q, matching: find.text('Support'));
        final bottom = size.height - keyboard;
        final yesRect = yes.evaluate().isEmpty ? null : tester.getRect(yes);
        // ignore: avoid_print
        print('B-11 $device | $look | keyboard ${up ? 'up' : 'down'} | overflow: ${error != null} | line on screen: ${q.evaluate().isNotEmpty} | '
            'Support at $yesRect, visible bottom $bottom');
        expect(error, isNull, reason: 'the safety cards overflow');
        expect(yesRect, isNotNull);
        expect(yesRect!.bottom, lessThanOrEqualTo(bottom + 0.5), reason: 'Support is under the keyboard or off screen');
      });
     }
    }
  }
}
