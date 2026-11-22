// Round 6 review E, E-04 (the proofs failed on 4a8da11 and pass since the round 6 fix): the old data key an earlier Linux build kept in the desktop keyring is deleted only when
// it equals the key now under the passphrase (main.dart moveKeyringKey: `keys.read(...) == old`). If its first
// delete failed (A-08: the pending marker stays) and the person then changes the passphrase, the data key is renewed
// (C-02) and can never equal the keyring copy again: the old key stays in the keyring for good, readable by any
// program of the same user, and the keyring is asked at every start (the prompt L-15 removed comes back).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/main.dart' show moveKeyringKey;

class _Keys implements KeyStore {
  final values = <String, String>{};
  int failDeletes = 0, reads = 0;
  @override
  Future<String?> read(String name) async {
    reads++;
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
  test('E-04: after a key renewal, the keyring copy is never deleted and the keyring is asked at every start',
      () async {
    final dir = Directory.systemTemp.createTempSync('r6e_ring');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/data_v1.bin').writeAsBytesSync([1, 2, 3]); // data from an earlier Linux build
    final passphrase = _Keys();
    final ring = _Keys()
      ..values[EncryptedFileVault.keyName] = 'OLD DATA KEY'
      ..failDeletes = 1;
    await moveKeyringKey(passphrase, dir, ring: ring); // first start: the move works, the keyring delete fails
    expect(passphrase.values[EncryptedFileVault.keyName], 'OLD DATA KEY');
    expect(File('${dir.path}/keys/keyring_delete_pending').existsSync(), isTrue);
    // Settings > Change passphrase renews the data key (EncryptedFileVault.rotateKey, C-02) before the next start
    passphrase.values[EncryptedFileVault.keyName] = 'NEW DATA KEY';
    final readsBefore = ring.reads;
    for (var start = 2; start <= 6; start++) {
      await moveKeyringKey(passphrase, dir, ring: ring); // the keyring answers and deletes fine now
    }
    // the safe behaviour: the old key leaves the keyring, and the keyring is no longer asked at every start
    expect(ring.values, isEmpty,
        reason: 'the old data key stays in the desktop keyring, open to any same-user program, after five starts');
    expect(File('${dir.path}/keys/keyring_delete_pending').existsSync(), isFalse,
        reason: 'the marker stays, so the keyring is asked at every start (${ring.reads - readsBefore} of 5)');
  });

  test('E-04: after Delete everything the keyring copy is never tried again (the data files are gone)', () async {
    final dir = Directory.systemTemp.createTempSync('r6e_ring2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final data = File('${dir.path}/data_v1.bin')..writeAsBytesSync([1, 2, 3]);
    final passphrase = _Keys();
    final ring = _Keys()
      ..values[EncryptedFileVault.keyName] = 'OLD DATA KEY'
      ..failDeletes = 1;
    await moveKeyringKey(passphrase, dir, ring: ring); // the keyring delete fails once
    // Delete everything: the store and the wrapped keys go; keys/ (with the pending marker) stays on Linux
    data.deleteSync();
    passphrase.values.clear();
    final readsBefore = ring.reads;
    for (var start = 2; start <= 4; start++) {
      await moveKeyringKey(passphrase, dir, ring: ring);
    }
    // the safe behaviour: Delete everything (or the next start) still removes the old key from the keyring
    expect(ring.values, isEmpty, reason: 'Delete everything leaves an old data key in the desktop keyring '
        '(asked ${ring.reads - readsBefore} times in three starts)');
  });
}
