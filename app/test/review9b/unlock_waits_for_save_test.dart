// Review round 9 B, final verification, 9B-13: since 2026-11-15 (owner: no Face ID, Touch ID or device unlock) every
// device opens the app lock with Solace's own passcode, and that check awaits a full save of the store before it
// answers (ui/app_lock.dart checkAppPasscode: `await state.save()` before returning ok). A save encrypts, writes and
// reads back the whole store and waits behind any save already queued (1.4 s for 6 MB on this laptop, several seconds
// on a phone), so every unlock now takes that long after the right passcode, and a save that never finishes keeps the
// lock screen up for good. Before, only Linux and phones without a screen lock took this path; the device's own unlock
// saved nothing. The right passcode needs no save to open the app: the count it resets can be written after.
//
// The test asserts the SAFE behaviour: with the right passcode, the lock comes down while the save is still writing.
// It fails on 226c148 while the finding stands.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/ui/app_lock.dart';

import '../audit_followups_test.dart' as a;
import 'support_waits_for_save_test.dart' show SlowVault;

const _code = '482916';

void main() {
  late Map<String, String> passcode;
  setUpAll(() async => passcode = await hashPasscode(_code));
  setUp(forgetLockWaitForTest);

  testWidgets('9B-13: the right passcode opens the app without waiting for a save of the store', (tester) async {
    final vault = SlowVault();
    final state = a.makeState(vault: vault)
      ..data.settings.appLock = true
      ..data.settings.passcode = passcode
      ..data.settings.lockAfterMinutes = 0;
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(
        builder: (context, child) => AppLockGate(child: child!), home: const Scaffold(body: Text('under the lock')))));
    await tester.pumpAndSettle();
    expect(find.text('Solace is locked'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('lock_code')), _code);
    await tester.tap(find.byKey(const Key('lock_unlock')));
    // real time for the Argon2 check (about 0.1 s here), frames between
    for (var i = 0; i < 40 && find.text('Solace is locked').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Solace is locked'), findsNothing,
        reason: 'the right passcode was entered 4 s ago; the lock waits for a save of the store (${vault.saves} '
            'still writing)');
    vault.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('control: with a quick save the same passcode opens it (passes on 226c148)', (tester) async {
    final state = a.makeState(vault: SlowVault(quick: true))
      ..data.settings.appLock = true
      ..data.settings.passcode = passcode
      ..data.settings.lockAfterMinutes = 0;
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(
        builder: (context, child) => AppLockGate(child: child!), home: const Scaffold(body: Text('under the lock')))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lock_code')), _code);
    await tester.tap(find.byKey(const Key('lock_unlock')));
    for (var i = 0; i < 40 && find.text('Solace is locked').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Solace is locked'), findsNothing);
  });
}
