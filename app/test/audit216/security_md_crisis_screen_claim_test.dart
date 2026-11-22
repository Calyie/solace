// Audit 216, auditor X, F-21 ("SECURITY.md claims that did not match the code", tracker: Fixed; round 8 docs pass).
//
// Since 15 November (OWNER-C1, commit 85f2f0b) a crisis the phrase rules find is met by a support card inside the
// conversation (ui/crisis.dart CrisisCard, ui/chat.dart and ui/call.dart), with the full support screen one tap away;
// the full screen opens by itself only where the conversation cannot be seen (ui/app_lock.dart supportWhereUnseen).
// The round 8 docs pass (later than 85f2f0b) rewrote the classifier half of SECURITY.md section 4 "A crisis is missed"
// but left "The rules open the crisis screen at once". A reader is told a full screen covers the chat when the app shows
// an inline card.
//
// This test asserts the SAFE state (the doc does not claim the old behaviour while the code shows the card), so it
// fails on c7f6680.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F-21: SECURITY.md does not say the rules open the crisis screen while the chat shows an inline card', () {
    final chat = File('lib/ui/chat.dart').readAsStringSync();
    expect(chat, contains('CrisisCard('), reason: 'precondition: the chat meets a rules crisis with an inline card');
    final lines = File('../docs/SECURITY.md').readAsLinesSync();
    final claims = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].contains('The rules open the crisis screen at once')) 'docs/SECURITY.md:${i + 1}',
    ];
    expect(claims, isEmpty, reason: 'the rules open a support card in the conversation (OWNER-C1), not the screen');
  });
}
