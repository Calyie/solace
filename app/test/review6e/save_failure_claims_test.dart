// Round 6 review E, E-01 (the proofs failed on 4a8da11 and pass since the round 6 fix; the control passes): screens that say
// data was deleted or brought in when the save that does it failed. AppState.save never throws (it sets
// saveProblem), so a caller that relies on an exception to say "not deleted" never learns of the failure: Choose what
// to delete says "Deleted", and a transfer says "Done ... You can delete the transfer file", while the device still
// holds the old data, which comes back at the next start. After the failed import save, the picture tidy also deletes
// this device's own picture, which the data still on disk names.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/choose_to_delete.dart';
import 'package:solace/ui/desktop.dart' show appNavigatorKey;
import 'package:solace/ui/transfer_screen.dart';

import '../app_flow_test.dart' as flow;

/// A vault whose saves fail once [failing] is set (a full disk, a keychain that stopped answering).
class _FailingVault extends MemoryVault {
  bool failing = false;
  @override
  Future<void> save(AppData data) async {
    if (failing) throw const FileSystemException('No space left on device', '', OSError('', 28));
    return super.save(data);
  }
}

Future<void> _deleteNewestConversation(WidgetTester tester) async {
  appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ChooseToDeleteScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('choose_conversations')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('choose_item_0')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('choose_delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('choose_delete_confirm')));
  await flow.frames(tester, ms: 600);
}


/// Brings in a transfer file while every save fails; returns the vault, the state and this device's picture id.
Future<(_FailingVault, String)> _importWhileSavesFail(WidgetTester tester) async {
  final from = flow.makeState(demo: true);
  const code = 'ABCDEFGHJKMNPQRS';
  final file = (await tester.runAsync(() => TransferFile.seal(from.data, code)))!;
  final vault = _FailingVault();
  final to = flow.makeState(vault: vault);
  // this device: no sessions yet, and one picture on its vision board (a separate encrypted file)
  final id = await vault.putMedia(Uint8List.fromList(List<int>.filled(64, 7)));
  to.data.photos['My calm place'] = 'media:$id';
  await vault.save(to.data);
  vault.failing = true;
  await flow.pumpScreen(tester, to, ReceiveFromDeviceScreen(pick: () async => PickedTransfer.fromBytes(
      Uint8List.fromList(file))));
  await tester.tap(find.byKey(const Key('transfer_pick')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('transfer_code')), code);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('transfer_open')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('transfer_replace')));
  // until the import has finished, whatever it then says
  await flow.settleReal(tester, find.byKey(const Key('transfer_open')));
  await flow.frames(tester, ms: 1000);
  final onDisk = await vault.load();
  // the precondition: nothing of the import reached the disk, so the next start shows the old data again
  expect(onDisk.sessions, isEmpty);
  expect(onDisk.photos['My calm place'], 'media:$id');
  expect(to.saveProblem, isNotNull);
  return (vault, id);
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  testWidgets('control: with saves working, Choose what to delete says "Deleted" and the disk agrees', (tester) async {
    final vault = _FailingVault();
    final state = flow.makeState(demo: true, vault: vault);
    await vault.save(state.data);
    final before = state.data.sessions.length;
    await flow.pumpApp(tester, state);
    await _deleteNewestConversation(tester);
    expect(find.text('Deleted 1 item.'), findsOneWidget);
    expect((await vault.load()).sessions.length, before - 1);
  });

  testWidgets('E-01: a delete that was not saved is never reported as done', (tester) async {
    final vault = _FailingVault();
    final state = flow.makeState(demo: true, vault: vault);
    await vault.save(state.data); // what is on the device now
    final before = state.data.sessions.length;
    vault.failing = true;
    await flow.pumpApp(tester, state);
    await _deleteNewestConversation(tester);
    // the precondition: the save failed, so the device still holds the conversation and it returns at the next start
    expect((await vault.load()).sessions.length, before);
    expect(state.saveProblem, isNotNull);
    // the safe behaviour: the screen says the delete did not reach the device (on 4a8da11 it says "Deleted 1 item.")
    expect(find.text('Deleted 1 item.'), findsNothing,
        reason: 'the deleted conversation is still in the saved data on the device');
  });

  testWidgets('E-01: an import that was not saved is never "Done ... You can delete the transfer file"',
      (tester) async {
    await _importWhileSavesFail(tester);
    expect(find.textContaining('You can delete the transfer file'), findsNothing,
        reason: 'the import is in memory only; deleting the file as told loses it when the app closes');
  });

  testWidgets('E-01: after an import that was not saved, this device\'s pictures are not tidied away', (tester) async {
    final (vault, id) = await _importWhileSavesFail(tester);
    expect((await vault.mediaIndex()).$1, contains(id),
        reason: 'the tidy after the import deleted the picture of the data that comes back at the next start');
  });
}
