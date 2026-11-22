// Round 9 review A, 9A-01: the deep work PIN changed on this device (owner, 2026-11-15, OWNER-C3: "a way to change
// the deep work PIN if it is compromised") can be put back to the PIN built into the app, with every conversation,
// note and plan kept, by anyone holding the unlocked app and knowing no PIN at all: Settings > Send everything to
// another device (no PIN asked; the file is saved on this device and the code shown), then Delete everything (no PIN
// asked; it restores the built PIN, core/full_mode_key.dart, app_state.dart _wipe), then Bring everything from another
// device with that file and code (no PIN asked; importInto keeps "this device's" PIN, which is now none,
// core/transfer.dart:29). From then on the built PIN, the one the owner replaced because it was found out, turns the
// safety check off and deep work mode on again. This test asserts the SAFE behaviour, so it fails while the finding
// stands.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';

import '../app_flow_test.dart' as flow;

const _built = '135790', _changed = '246813';

void main() {
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf(_built, salt, memoryKib: 64, iterations: 1));
  });

  test('9A-01: a transfer round trip through Delete everything never brings the replaced built PIN back', () async {
    final vault = MemoryVault();
    final state = flow.makeState(demo: true, vault: vault);
    // the owner changed the PIN because the built one was found out (Settings > Change deep work PIN)
    state.data.settings.fullModePin = await flow.testKey.saved(_changed, random: Random(1));
    await state.save();
    expect(await state.fullModeKey.matches(_built), isFalse, reason: 'precondition: the built PIN no longer works');
    final sessions = state.data.sessions.length;
    expect(sessions, greaterThan(0));

    // someone holding the unlocked app, who knows only the old built PIN:
    // 1. Send everything to another device (ui/transfer_screen.dart _make: no PIN), saved on this device
    final code = TransferCode.generate(Random(2));
    final file = await TransferFile.seal(await state.dataForTransfer(), code, random: Random(3));
    // 2. Delete everything (ui/settings.dart: no PIN)
    await state.wipeEverything(folders: () async {});
    // 3. Bring everything from another device with that file and code (ui/transfer_screen.dart: no PIN)
    await state.receiveTransfer(await TransferFile.open(file, code));

    expect(state.data.sessions.length, sessions, reason: 'every conversation is back, so nothing looks wrong');
    expect(await state.fullModeKey.matches(_built), isFalse,
        reason: 'the PIN built into the app, which the owner replaced, opens deep work mode and turns off the safety '
            'check again, and the PIN the owner chose no longer does');
    expect(await state.fullModeKey.matches(_changed), isTrue);
  });
}
