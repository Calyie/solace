// Round 9 review A, 9A-02: once past the lock, nothing in Solace asks the person to prove it is them again. Settings
// turns the app lock off, and "Hide in the app switcher" off (Android's screenshot block with it), with one tap: no
// passcode, and nothing tells the owner later (ui/settings.dart:187-215); turning the lock on asks for a new passcode
// (ui/app_lock.dart turnOnLock), turning it off asks for nothing.
// Send everything to another device seals every session, note and picture into one file and shows its code, also with
// nothing asked (ui/transfer_screen.dart _make). So anyone who has the unlocked app for half a minute (handed the
// phone to show a photo, a computer left open) can switch the lock off and come back later, or carry a complete copy
// away, and the owner is not told. This test asserts the SAFE behaviour (each waits for the app passcode, the lock's
// only unlock since 2026-11-15), so it fails while the finding stands.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/transfer_screen.dart';

import '../app_flow_test.dart' as flow;

void main() {
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  setUpAll(flow.loadFonts);
  late Map<String, String> passcode;
  setUpAll(() async => passcode = await hashPasscode('482916'));

  testWidgets('9A-02: the app lock is not turned off without the passcode', (tester) async {
    final state = flow.makeState(vault: MemoryVault());
    state.data.settings
      ..appLock = true
      ..passcode = passcode
      ..hideInSwitcher = true;
    await flow.pumpScreen(tester, state, const SettingsScreen());
    await flow.tapIn(tester, find.byKey(const Key('app_lock')));
    expect(state.data.settings.appLock, isTrue,
        reason: 'one tap turned the app lock off, with no passcode asked and nothing said to the owner later');
  });

  testWidgets('9A-02: "Hide in the app switcher" (Android: the screenshot block) is not turned off without it either',
      (tester) async {
    final state = flow.makeState(vault: MemoryVault());
    state.data.settings
      ..appLock = true
      ..passcode = passcode
      ..hideInSwitcher = true;
    await flow.pumpScreen(tester, state, const SettingsScreen());
    await flow.tapIn(tester, find.byKey(const Key('hide_switcher')));
    expect(state.data.settings.hideInSwitcher, isTrue,
        reason: 'one tap let the screen be captured and shown in the app switcher, with no passcode asked');
  });

  testWidgets('9A-02: a complete copy of everything (Send to another device) is not made without it either',
      (tester) async {
    final state = flow.makeState(demo: true, vault: MemoryVault());
    state.data.settings
      ..appLock = true
      ..passcode = passcode;
    Uint8List? file;
    await flow.pumpScreen(tester, state, SendToDeviceScreen(save: (name, bytes) async {
      file = bytes;
      return true;
    }));
    await tester.tap(find.byKey(const Key('transfer_make')));
    await flow.settleReal(tester, find.byKey(const Key('transfer_code_shown')));
    expect(file == null && find.byKey(const Key('transfer_code_shown')).evaluate().isEmpty, isTrue,
        reason: 'every session, note and picture was sealed into a file and its code shown, with no passcode asked: '
            'someone with the unlocked app for half a minute can carry the whole of it away');
  });
}
