// Round 9 review A, check of c5bfd19, 9A-11: "Forgotten your passcode?" on the lock screen runs the real Delete
// everything (AppState.wipeEverything). Part-way through, AppState._wipe replaces the data with a fresh AppData (lock
// off) and notifies (measurePictures), so AppLockGate takes the lock screen down while the wipe is still running: the
// folder wipe, the picker clear-up and, on Linux, afterWipe (moveKeyringKey: up to 5 s per keyring call). Only after
// wipeEverything returns does the dialog close the screens left open under the lock (ui/app_lock.dart
// _ForgottenPasscodeState._delete popUntil). Meanwhile those screens are on show and usable, to someone who never typed
// the passcode, and a screen that holds its own copy of a record (a memory-search result, ui/memory_search.dart:98,
// :112) still shows the person's words. Here afterWipe is held for a moment, as a slow keyring is, and a screen left
// under the lock holds a note. This test asserts the SAFE behaviour (nothing under the lock is ever shown), so it fails
// while the finding stands.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/desktop.dart' show appNavigatorKey;

import '../app_flow_test.dart' as flow;

const _note = 'what I have never told anyone';

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

  testWidgets('9A-11: Forgotten your passcode? never shows a screen that was under the lock, even for a moment',
      (tester) async {
    final vault = MemoryVault();
    final state = flow.makeState(demo: true, vault: vault);
    state.data.settings
      ..appLock = true
      ..lockAfterMinutes = 0
      ..passcode = passcode;
    await vault.save(state.data);
    final held = Completer<void>();
    state.afterWipe = () => held.future; // Linux: the keyring retry after Delete everything, which can take seconds
    await flow.pumpApp(tester, state);
    expect(find.text('Solace is locked'), findsOneWidget);
    // a screen left open under the lock that holds its own copy of the person's words, as a search result does
    appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: Center(
        child: SelectableText(_note)))));
    await tester.pumpAndSettle();
    expect(find.text(_note), findsNothing, reason: 'precondition: hidden under the lock');

    await tester.tap(find.byKey(const Key('lock_forgot')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('forgot_typed')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forgot_delete')));
    var shown = false;
    for (var i = 0; i < 40 && !shown; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      shown = find.text(_note).evaluate().isNotEmpty;
    }
    held.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(shown, isFalse,
        reason: 'while Delete everything was still running, the lock screen went and the screen left under it showed '
            'the person\'s words to someone who never typed the passcode');
  });
}
