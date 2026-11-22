// Round 9 review A, 9A-03 (a gap in the G7-04 and E-04 fixes): on Linux, a keyring delete still owed from an earlier
// build is recorded by a marker. After "I have forgotten it" that marker sits in the set-aside folder
// keys.forgotten-<date> (G7-04), and moveKeyringKey still honours it. But Delete everything runs wipeAppFolders
// first, which deletes every set-aside folder (core/app_files.dart:33), and only then afterWipe, the promised retry
// (app_state.dart:478-483; round 6 review E-04: "retried after Delete everything"). The retry finds no marker and no
// data, so it never asks the keyring: the earlier build's data key stays in the desktop keyring for good, readable by
// any program of the same user. The marker is only in the set-aside folder while every opening since "I have
// forgotten it" found the keyring locked (its read times out before the marker is copied into the new keys/,
// main.dart:107 before :117), as on a desktop that logs in automatically and never unlocks the keyring. This drives the real AppState.wipeEverything with the app's own folder wipe and the
// app's own afterWipe, and asserts the SAFE behaviour, so it fails while the finding stands.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_files.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/main.dart' show moveKeyringKey;

import '../app_flow_test.dart' as flow;

class _Keys implements KeyStore {
  final values = <String, String>{};
  int failDeletes = 0, failReads = 0;
  @override
  Future<String?> read(String name) async {
    if (failReads > 0) {
      failReads--;
      throw const FileSystemException('keyring locked: no answer in time');
    }
    return values[name];
  }
  @override
  Future<void> write(String name, String value) async => values[name] = value;
  @override
  Future<void> delete(String name) async {
    if (failDeletes > 0) {
      failDeletes--;
      throw const FileSystemException('keyring did not answer');
    }
    values.remove(name);
  }

  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  test('9A-03: Delete everything still retries a keyring delete owed from before "I have forgotten it"', () async {
    final dir = Directory.systemTemp.createTempSync('r9a_ring');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/data_v1.bin').writeAsBytesSync([1, 2, 3]); // data from an earlier Linux build
    final ring = _Keys()
      ..values[EncryptedFileVault.keyName] = 'OLD DATA KEY'
      ..failDeletes = 1; // the delete does not go through at the first start
    await moveKeyringKey(_Keys(), dir, ring: ring); // first start: moved, the keyring delete fails
    // "I have forgotten it" > Start fresh (ui/passphrase_screen.dart _startFresh)
    for (final n in ['data_v1.bin', 'keys']) {
      final p = '${dir.path}/$n';
      FileSystemEntity.isDirectorySync(p) ? Directory(p).renameSync('$p.forgotten-x') : File(p).renameSync('$p.forgotten-x');
    }
    Directory('${dir.path}/keys').createSync(); // the new passphrase's set-up
    final keys = _Keys();
    ring.failReads = 1; // the next opening: the keyring is locked and does not answer within moveKeyringKey's 5 s
    await moveKeyringKey(keys, dir, ring: ring);
    expect(File('${dir.path}/keys.forgotten-x/keyring_delete_pending').existsSync(), isTrue,
        reason: 'precondition: the delete is still owed (G7-04)');
    expect(ring.values, isNotEmpty);

    // Delete everything, as the app wires it on Linux (main.dart: afterWipe = moveKeyringKey; the folder wipe is
    // core/app_files.dart wipeAppFolders on the app's support folder); the keyring answers now
    final state = flow.makeState(vault: MemoryVault())..afterWipe = () => moveKeyringKey(keys, dir, ring: ring);
    await state.wipeEverything(folders: () => wipeAppFolders(support: dir));

    expect(ring.values, isEmpty,
        reason: 'the folder wipe deleted the set-aside marker before the retry ran, so the earlier build\'s data key '
            'is never deleted from the desktop keyring');
  });
}
