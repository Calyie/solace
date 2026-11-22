// Review round 4 (B): Delete everything left decrypted vision-board pictures in the running app's memory
// (AppState._pictureCache was never cleared), left the picture byte count stale (AppState.pictureBytes), which the
// "room full" check reads, and never closed the classifier. This failed on commit 5bdac57 and is fixed in round 4
// (branch fix/round4-b): the test now asserts the fixed behaviour in the same scenario.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/media.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/store.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
);

void main() {
  test('B-16: after Delete everything no deleted picture is served from memory, the room is measured again, and the '
      'classifier is closed', () async {
    final vault = MemoryVault();
    final state = AppState(data: AppData(), vault: vault, prompts: prompts, model: const StandInModel(),
        library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()));
    var closed = 0;
    state.useRiskCheck((c, t) async => false, 'test classifier', close: () async => closed++);
    final secret = Uint8List.fromList(List.generate(4096, (i) => i % 251));
    await state.setPicture('my house', secret);
    final ref = state.data.photos['my house']!;
    expect(await state.picture('my house'), secret); // decrypted and cached
    expect(state.pictureBytes, greaterThan(0));

    await state.wipeEverything(folders: () async {});
    expect(state.data.photos, isEmpty);
    expect(await vault.getMedia(mediaId(ref)), isNull, reason: 'the vault no longer has it');
    expect(state.pictureBytes, 0, reason: 'the deleted pictures no longer count against the room');
    expect(closed, 1, reason: 'the classifier (its ONNX session and tokenizer isolate) is closed, not just dropped');
    expect(state.riskCheck, isNull);

    // later data that names the same reference (an imported file can carry references) gets nothing from memory
    state.data.photos['x'] = ref;
    expect(await state.picture('x'), isNull, reason: 'the decrypted picture is no longer held in memory');
  });
}
