// Round 7 review A, G7-02 (the proof failed on c8e45c9 and passes since the round 7 fix): the round 6 fix for E-01 (a delete whose save failed is never reported as done) covers
// Choose what to delete, Delete older conversations, pictures, the transfer import and the three privacy switches,
// but not "Erase what Solace remembers" on the You tab: it confirms with the done haptic before saving, uses
// AppState.save (which never says whether the data reached the device) and shows nothing on its screen when the save
// fails. The story, the last note and the noticed things are still in the store on the device and come back at the
// next start. These tests assert the SAFE behaviour, so they fail while the finding stands.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/you.dart';

import '../app_flow_test.dart' as flow;

/// A vault whose saves fail once [failing] is set (a full disk), as round 6's save_failure_claims_test uses.
class _FailingVault extends MemoryVault {
  bool failing = false;
  @override
  Future<void> save(AppData data) async {
    if (failing) throw const FileSystemException('No space left on device', '', OSError('', 28));
    return super.save(data);
  }
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  testWidgets('control: with saves working, Erase clears what Solace remembers on the device', (tester) async {
    final vault = _FailingVault();
    final state = flow.makeState(demo: true, vault: vault);
    state.data.lastNote = 'Talked about: my brother and the money';
    await vault.save(state.data);
    await flow.pumpScreen(tester, state, const Scaffold(body: SingleChildScrollView(child: MemoryControls())));
    await tester.tap(find.byKey(const Key('memory_erase')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memory_erase_confirm')));
    await tester.pumpAndSettle();
    expect((await vault.load()).lastNote, isEmpty);
  });

  testWidgets('G7-02: an Erase that was not saved says so on its screen', (tester) async {
    final vault = _FailingVault();
    final state = flow.makeState(demo: true, vault: vault);
    state.data.lastNote = 'Talked about: my brother and the money';
    await vault.save(state.data); // what is on the device now
    vault.failing = true;
    await flow.pumpScreen(tester, state, const Scaffold(body: SingleChildScrollView(child: MemoryControls())));
    await tester.tap(find.byKey(const Key('memory_erase')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memory_erase_confirm')));
    await tester.pumpAndSettle();
    // the precondition: the save failed, so the device still holds what was "erased", and it returns at the next start
    expect((await vault.load()).lastNote, isNotEmpty);
    expect(state.saveProblem, isNotNull);
    expect(state.data.lastNote, isEmpty, reason: 'erased in this run only');
    // the safe behaviour, as the other deletes since E-01: the screen itself says it is not erased yet (this screen
    // has no banner of its own; the app's general banner is outside it)
    expect(find.textContaining('could not be saved'), findsWidgets,
        reason: 'Erase what Solace remembers said nothing although the device still holds the story and the note');
  });
}
