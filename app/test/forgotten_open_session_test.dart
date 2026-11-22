// Round 9 final, 9B-15: with a conversation open under the lock, "Forgotten your passcode?" closes it and then waits
// for it to go before deleting, so the first tap deletes everything (before, it was refused at once with "close Solace
// completely" and only a second tap worked).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/desktop.dart' show appNavigatorKey;

import 'app_flow_test.dart' as flow;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  late Map<String, String> passcode;
  setUpAll(() async => passcode = await hashPasscode('482916'));
  setUp(forgetLockWaitForTest);

  testWidgets('9B-15: Forgotten your passcode? with a conversation open under the lock deletes at the first tap',
      (tester) async {
    final vault = MemoryVault();
    final state = flow.makeState(demo: true, vault: vault);
    state.data.settings
      ..appLock = true
      ..lockAfterMinutes = 0
      ..passcode = passcode;
    await vault.save(state.data);
    await flow.pumpApp(tester, state);
    expect(find.text('Solace is locked'), findsOneWidget, reason: 'precondition: locked');
    // a conversation open under the lock (as one left open when the lock came down)
    appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ChatScreen(kind: 'daily_checkin')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(state.openSessions.count, 1, reason: 'precondition: a conversation is open under the lock');

    await tester.tap(find.byKey(const Key('lock_forgot')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('forgot_typed')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forgot_delete')));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final msg = find.byKey(const Key('forgot_message'));
    expect(msg, findsNothing, reason: 'the first tap was refused: ${msg.evaluate().isEmpty ? '' : (tester.widget<Text>(msg).data)} '
        '(open sessions ${state.openSessions.count})');
    expect(state.openSessions.count, 0);
    expect(state.data.settings.passcode, isNull, reason: 'everything was deleted, the passcode with it');
    expect(state.data.sessions, isEmpty);
    expect(find.text('Solace is locked'), findsNothing);
  });
}
