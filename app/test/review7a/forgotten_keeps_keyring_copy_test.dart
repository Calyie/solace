// Round 7 review A, G7-04 (the proof failed on c8e45c9 and passes since the round 7 fix): the keyring delete still owed (round 6, E-04: the marker keys/keyring_delete_pending) is
// forgotten when the person uses "I have forgotten it" on the Linux passphrase screen: that moves the whole keys/
// folder aside (ui/passphrase_screen.dart _startFresh), marker included, with the data. From then on moveKeyringKey
// finds neither data nor a marker (and later, data with a key of its own and no marker), so it never asks the keyring
// again: the earlier build's data key stays in the desktop keyring for good, readable by any program of the same user,
// and it opens the data that was set aside "still locked". This test asserts the SAFE behaviour, so it fails while the
// finding stands.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/main.dart' show moveKeyringKey;

class _Keys implements KeyStore {
  final values = <String, String>{};
  int failDeletes = 0;
  @override
  Future<String?> read(String name) async => values[name];
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
  test('G7-04: "I have forgotten it" never leaves an owed keyring delete undone', () async {
    final dir = Directory.systemTemp.createTempSync('r7a_ring');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/data_v1.bin').writeAsBytesSync([1, 2, 3]); // data from an earlier Linux build
    final passphrase = _Keys();
    final ring = _Keys()
      ..values[EncryptedFileVault.keyName] = 'OLD DATA KEY'
      ..failDeletes = 1;
    await moveKeyringKey(passphrase, dir, ring: ring); // first start: the move works, the keyring delete fails
    expect(File('${dir.path}/keys/keyring_delete_pending').existsSync(), isTrue, reason: 'precondition: delete owed');
    // later the person forgets the passphrase and taps "I have forgotten it" > Start fresh: exactly what
    // _PassphraseScreenState._startFresh renames
    const stamp = '2026-11-15T10-00-00.000';
    for (final name in ['data_v1.bin', 'data_v1.bin.bak', 'keys', 'media']) {
      final path = '${dir.path}/$name';
      final t = FileSystemEntity.typeSync(path);
      if (t == FileSystemEntityType.notFound) continue;
      t == FileSystemEntityType.directory ? Directory(path).renameSync('$path.forgotten-$stamp')
          : File(path).renameSync('$path.forgotten-$stamp');
    }
    Directory('${dir.path}/keys').createSync(); // the new passphrase's set-up (PassphraseKeyStore.create)
    final fresh = _Keys();
    await moveKeyringKey(fresh, dir, ring: ring); // the next opening, before any new data
    File('${dir.path}/data_v1.bin').writeAsBytesSync([4, 5, 6]); // the fresh data, with a key of its own
    fresh.values[EncryptedFileVault.keyName] = 'FRESH DATA KEY';
    for (var start = 2; start <= 4; start++) {
      await moveKeyringKey(fresh, dir, ring: ring); // the keyring answers and deletes fine now
    }
    expect(ring.values, isEmpty,
        reason: 'the earlier build\'s data key stays in the desktop keyring, and it opens the data set aside as '
            'data_v1.bin.forgotten-$stamp');
  });
}
