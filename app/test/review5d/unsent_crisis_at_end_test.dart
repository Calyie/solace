// Review round 5 (D-15): words left in the chat box were never read when the session ended, though the call read
// heard words it kept in its box (session.dart readUnsent) and words sent during a reply were read at once. The first
// test failed on ca6a73b (it was written to show the fault); fixed in round 5: at End, and when the screen goes (Back),
// the words in the box and any waiting for room are read by the phrase rules (SessionController.readLeftUnsent), and
// a crisis there is recorded, starts the 7-day watch and opens support, as a sent one does. The call does the same
// with words typed in its box. Round 6 (owner, 2026-11-15, OWNER-C1): where the conversation shows, support is the card
// in it, the full support screen one tap away; after Back it still opens over the screen beneath.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/theme.dart';

import '../call_streaming_test.dart' as cs;
import '../review_c1_flows_test.dart' as c1;

const crisis = "I'm going to kill myself tonight.";
const support = 'You matter, and support is here';

int crises(AppState state) => state.data.safetyEvents.where((e) => e['level'] == 'crisis').length;

void main() {
  testWidgets('D-15: a crisis typed in the box and left there when End is tapped is read, recorded and opens support',
      (tester) async {
    final state = c1.makeState();
    await c1.pumpChat(tester, state, 'daily_checkin');
    await tester.enterText(find.byType(TextField), 'Work was hard today.');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();
    // typed, not sent; the person taps End instead
    await tester.enterText(find.byType(TextField), crisis);
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    // on ca6a73b nothing read the words: no crisis was recorded and no 7-day watch started
    expect(crises(state), 1);
    expect(state.data.safetyWatch, isNotNull);
    expect((await state.vault.load()).safetyWatch, isNotNull, reason: 'kept at once, as a sent crisis is');
    // owner, 2026-11-15, OWNER-C1: support shows as the card in the conversation, as for a sent crisis, and the full
    // support screen is one tap away
    expect(find.byKey(const Key('crisis_card')), findsOneWidget, reason: 'support shows, as for a sent crisis');
    expect(find.text(support), findsNothing, reason: 'nothing covers the conversation');
    expect(find.byKey(const Key('end_unsent')), findsNothing, reason: 'support comes before the close');
    await tester.ensureVisible(find.byKey(const Key('crisis_card_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crisis_card_more')));
    await tester.pumpAndSettle();
    expect(find.text(support), findsOneWidget);
    // support closed: the words are still in the box, and End goes on to the close this time, with no second record
    Navigator.of(tester.element(find.text(support))).pop();
    await tester.pumpAndSettle();
    expect(c1.box(tester), crisis);
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('end_unsent')), findsOneWidget); // "has not been sent" is said
    await tester.ensureVisible(find.byKey(const Key('end_confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('end_confirm')));
    await tester.pumpAndSettle();
    expect(crises(state), 1);
    expect(find.text(support), findsNothing);
  });

  testWidgets('D-15: ordinary words left in the box change nothing at End', (tester) async {
    final state = c1.makeState();
    await c1.pumpChat(tester, state, 'daily_checkin');
    await tester.enterText(find.byType(TextField), 'Work was hard today.');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'I might go for a walk later.');
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('end_unsent')), findsOneWidget);
    expect(find.text(support), findsNothing);
    expect(state.data.safetyEvents.where((e) => e['level'] != 'output'), isEmpty);
  });

  testWidgets('D-15: a crisis left in the box when the person goes Back is recorded and opens support beneath',
      (tester) async {
    final state = c1.makeState();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.light),
        home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChatScreen(kind: 'daily_checkin'))),
            child: const Text('open'))))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), crisis);
    await tester.pageBack(); // Back, without sending
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(crises(state), 1);
    expect(state.data.safetyWatch, isNotNull);
    expect((await state.vault.load()).safetyWatch, isNotNull);
    expect(find.text(support), findsOneWidget, reason: 'over the screen the person went back to');
  });

  testWidgets('D-15: on a call, a crisis typed in the box and left there at End is read and opens support',
      (tester) async {
    final state = cs.makeState(cs.HalfwayModel());
    final s = state.newSession();
    await s.start('daily_checkin');
    final voice = cs.FeedVoice();
    await cs.pumpCall(tester, state, voice, s, draft: crisis);
    voice.finish();
    await tester.pump();
    await tester.tap(find.byKey(const Key('call_end')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(crises(state), 1);
    expect(state.data.safetyWatch, isNotNull);
    // OWNER-C1: the support card on the call screen, nothing over the call
    expect(find.byKey(const Key('crisis_card'), skipOffstage: false), findsOneWidget);
    expect(find.text(support), findsNothing);
    expect(find.text('End the call?'), findsNothing, reason: 'support comes before the end');
    expect(find.byKey(const Key('call_end')), findsOneWidget, reason: 'still on the call');
  });
}
