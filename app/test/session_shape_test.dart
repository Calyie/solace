// The shape of a session (research report P1: session start and close): starters offer a gentle way in until the
// person has said something, and ending goes through "Before you go", where they can note how they feel now (it
// updates today's mood) or keep talking.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/safety.dart' show SafetyLevel;
import 'package:solace/core/dates.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/ui/chat.dart';

import 'app_flow_test.dart' as flow;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  Future<void> openChat(WidgetTester tester, dynamic state) async {
    await flow.pumpApp(tester, state);
    final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
    nav.push(MaterialPageRoute(builder: (_) => const ChatScreen(kind: 'daily_checkin')));
    await flow.frames(tester);
  }

  testWidgets('starters fill the message box, then step aside once the person has spoken', (tester) async {
    final state = flow.makeState();
    await openChat(tester, state);
    expect(find.byKey(const Key('starter_1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('starter_1')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Today was hard. ');
    await tester.enterText(find.byType(TextField), 'Today was hard. Work was a lot.');
    await tester.tap(find.byTooltip('Send'));
    await flow.frames(tester);
    expect(find.byKey(const Key('starter_1')), findsNothing);
  });

  testWidgets('Before you go: keep talking goes back; ending saves the mood and the session', (tester) async {
    final state = flow.makeState();
    final sessions = state.data.sessions.length;
    await openChat(tester, state);
    await tester.enterText(find.byType(TextField), 'I slept badly.');
    await tester.tap(find.byTooltip('Send'));
    await flow.frames(tester);
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    expect(find.text('Before you go'), findsOneWidget);
    await flow.shot('36_before_you_go');
    await tester.tap(find.byKey(const Key('end_keep_talking')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(state.data.sessions.length, sessions);
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('before_go_7')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('end_confirm')));
    await flow.frames(tester, ms: 2400);
    expect(state.data.moods[isoDate(state.clock())], 7);
    expect(state.data.sessions.length, sessions + 1);
    expect(find.text('Session saved'), findsOneWidget);
  });

  test('a session started before the classifier loaded uses it from the next message on', () async {
    final state = flow.makeState();
    final s = state.newSession();
    await s.start('daily_checkin');
    await s.send('Work was busy today.');
    expect(s.lastSafety.level, SafetyLevel.none);
    state.useRiskCheck((context, text) async => text.contains('heavy'), 'test classifier'); // loads mid-session
    await s.send('Everything feels heavy and pointless.');
    expect(s.lastSafety.level, SafetyLevel.concern, reason: 'the quiet support line (owner, 2026-11-15: no question)');
  });
}
