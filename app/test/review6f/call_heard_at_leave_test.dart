// Review round 6 F (F6-05): words a call's microphone had already caught are read by the phrase rules when the call
// pauses, when the person types, or when a safety question appears (cycle 2 review, N1), and words typed and left in
// the box are read when the call screen goes (round 5 review, D-15). Words the recogniser was still working out when
// the screen goes are dropped unread: _listen returns at "!mounted" before reading them. Someone who says "I want to
// kill myself tonight" and swipes the call away in the same moment meets no response and leaves no record. The first
// test failed on 4a8da11; fixed in round 6 (ui/call.dart _listen reads the words caught as the screen goes or the call
// ends, and opens support over the screen beneath when it has gone).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/ui/call.dart';

import '../review_c1_flows_test.dart' as c1;
import '../review_c2_flows_test.dart' as c2;

void main() {
  testWidgets('F6-05: words heard as the call screen goes are read by the phrase rules', (tester) async {
    final state = c1.makeState();
    final voice = c2.AsrVoice();
    await c2.pumpCallScreen(tester, state, CallScreen(kind: 'daily_checkin', voice: voice));
    for (var i = 0; i < 20 && voice.listens == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(voice.listens, 1, reason: 'she greeted, then listens');
    await tester.pumpWidget(const SizedBox()); // the call screen goes (Back, a swipe) while the person speaks
    voice.ear!.complete(c1.crisisSentence); // what the recogniser had caught
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c2.crises(state), 1, reason: 'a crisis said as the call closed was dropped unread');
  });

  testWidgets('F6-05 control: the same words caught as the call pauses are read (N1)', (tester) async {
    final state = c1.makeState();
    final voice = c2.AsrVoice();
    await c2.pumpCallScreen(tester, state, CallScreen(kind: 'daily_checkin', voice: voice));
    for (var i = 0; i < 20 && voice.listens == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('call_pause')));
    await tester.pump();
    voice.ear!.complete(c1.crisisSentence);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c2.crises(state), 1);
    await tester.pumpWidget(const SizedBox());
  });
}
