// Review round 5, reviewer C, C-07 (both tests FAIL on ca6a73b; pass once fixed): while Solace is locked, the system Back (Android's back button or gesture) is
// handled by the app's own navigator under the lock screen, not by the lock screen. So someone holding the locked
// phone can close whatever screen is open behind the lock without unlocking it, unseen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/ui/desktop.dart' show appNavigatorKey;

import '../app_flow_test.dart' as flow;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  testWidgets('C-07: Back pressed on the lock screen leaves the screen under it alone', (tester) async {
    final stored = (await tester.runAsync(() => hashPasscode('135791')))!;
    final state = flow.makeState();
    await flow.pumpApp(tester, state);
    // the person is in a screen (here a stand-in page pushed on the app's navigator) when the lock comes down
    var popped = false;
    appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => PopScope(
        onPopInvokedWithResult: (didPop, _) => popped = didPop,
        child: const Scaffold(body: Text('private screen')))));
    await tester.pumpAndSettle();
    state.data.settings
      ..appLock = true
      ..lockAfterMinutes = 0
      ..passcode = stored;
    // away and back: the lock comes down over the open screen
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Solace is locked'), findsOneWidget);
    // Back on the lock screen
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Solace is locked'), findsOneWidget);
    expect(popped, isFalse, reason: 'Back on the lock screen closed the screen open under the lock');
    expect(appNavigatorKey.currentState!.canPop(), isTrue);
  });

  testWidgets('C-07: Back on the lock screen keeps the session open under it',
      (tester) async {
    final stored = (await tester.runAsync(() => hashPasscode('135791')))!;
    final state = flow.makeState(demo: true);
    await flow.pumpApp(tester, state);
    final before = state.data.sessions.length;
    await flow.startSession(tester);
    await tester.enterText(find.byType(TextField), 'Something I have never told anyone.');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Something I have never told anyone.'), findsOneWidget);
    state.data.settings
      ..appLock = true
      ..lockAfterMinutes = 0
      ..passcode = stored;
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(minutes: 2));
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    expect(find.text('Solace is locked'), findsOneWidget);
    await tester.binding.handlePopRoute(); // someone else, holding the locked phone, presses Back
    await tester.pumpAndSettle();
    // the owner unlocks: the session is gone and nothing of it was kept
    await tester.enterText(find.byKey(const Key('lock_code')), '135791');
    await tester.tap(find.byKey(const Key('lock_unlock')));
    for (var i = 0; i < 60 && find.text('Solace is locked').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Solace is locked'), findsNothing);
    expect(state.data.sessions.length, before); // not ended, so not saved yet: it must still be open
    expect(find.text('Something I have never told anyone.'), findsOneWidget,
        reason: 'Back on the lock screen threw away the session open under it');
  });
  testWidgets('control: without Back, the session is still there after unlocking (so the failure above is Back)',
      (tester) async {
    final stored = (await tester.runAsync(() => hashPasscode('135791')))!;
    final state = flow.makeState(demo: true);
    await flow.pumpApp(tester, state);
    final before = state.data.sessions.length;
    await flow.startSession(tester);
    await tester.enterText(find.byType(TextField), 'Something I have never told anyone.');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Something I have never told anyone.'), findsOneWidget);
    state.data.settings
      ..appLock = true
      ..lockAfterMinutes = 0
      ..passcode = stored;
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(minutes: 2));
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    expect(find.text('Solace is locked'), findsOneWidget);
    await tester.pumpAndSettle();
    // the owner unlocks: the session is gone and nothing of it was kept
    await tester.enterText(find.byKey(const Key('lock_code')), '135791');
    await tester.tap(find.byKey(const Key('lock_unlock')));
    for (var i = 0; i < 60 && find.text('Solace is locked').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Solace is locked'), findsNothing);
    expect(state.data.sessions.length, before); // not ended, so not saved yet: it must still be open
    expect(find.text('Something I have never told anyone.'), findsOneWidget,
        reason: 'Back on the lock screen threw away the session open under it');
  });
}
