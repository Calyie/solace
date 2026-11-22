// Review round 9 B, check of c5bfd19, 9B-14: "Forgotten your passcode?" on the lock screen deletes everything in a
// modal dialog that cannot be closed while the delete runs (ui/app_lock.dart _ForgottenPasscode: PopScope(canPop:
// !_busy), Cancel disabled while _busy, no timeout on AppState.wipeEverything). The dialog's barrier covers the lock
// screen's "Get support now". The delete waits behind any save already writing (1.4 s for a year of data on this
// laptop, several seconds on a phone), the engines being let go and the files deleted; if one of those never returns,
// the lock screen stays covered with Support out of reach until Solace is closed.
//
// The test holds the vault's delete open (a save still writing) and asserts the SAFE behaviour: Support can be opened
// while the delete runs. It fails on c5bfd19 while the finding stands.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/crisis.dart';

import '../audit_followups_test.dart' as a;

/// A vault whose delete waits for [release], as one queued behind a long save does.
class SlowWipeVault extends MemoryVault {
  final release = Completer<void>();
  @override
  Future<void> wipe() async {
    await release.future;
    await super.wipe();
  }
}

void main() {
  late Map<String, String> passcode;
  setUpAll(() async => passcode = await hashPasscode('482916'));
  setUp(forgetLockWaitForTest);

  testWidgets('9B-14: Support stays reachable while "Forgotten your passcode?" deletes everything', (tester) async {
    final vault = SlowWipeVault();
    final state = a.makeState(vault: vault)
      ..data.settings.appLock = true
      ..data.settings.passcode = passcode
      ..data.settings.lockAfterMinutes = 0;
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(
        builder: (context, child) => AppLockGate(child: child!), home: const Scaffold(body: Text('under the lock')))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lock_forgot')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('forgot_typed')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forgot_delete')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('forgot_progress')), findsOneWidget, reason: 'set-up: the delete is still running');
    // Changed by the lead with the fix (round 9 final): the fix takes the reviewer's first direction, a Support button
    // in the dialog itself; the lock screen's own button stays behind the dialog's barrier. Either must open support.
    final inDialog = find.byKey(const Key('forgot_support'));
    await tester.tap(inDialog.evaluate().isNotEmpty ? inDialog : find.byKey(const Key('lock_support')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(CrisisSheet), findsOneWidget,
        reason: 'the delete dialog cannot be closed while it runs, and its barrier covers "Get support now"');
    vault.release.complete();
    await tester.pumpAndSettle();
  });
}
