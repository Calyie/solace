// Review round 4, A: Linux moves an earlier build's data key from the desktop keyring under the passphrase. If the
// keyring delete fails or times out once (a locked or slow keyring), the key stays in the keyring, readable by every
// program of the same user (OW-M9-1), and no later start ever tries the delete again, because the move returns early
// once the passphrase store holds the key. Failed on 5bdac57; passes since the round 4 fix.
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
      throw const FileSystemException('keyring did not answer'); // or a 5 s timeout
    }
    values.remove(name);
  }

  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  test('a keyring copy that could not be deleted once is deleted at a later start', () async {
    final dir = Directory.systemTemp.createTempSync('r4a_ring');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/data_v1.bin').writeAsBytesSync([1, 2, 3]); // data from an earlier Linux build
    final passphraseStore = _Keys();
    final ring = _Keys()
      ..values[EncryptedFileVault.keyName] = 'THE DATA KEY'
      ..failDeletes = 1;
    await moveKeyringKey(passphraseStore, dir, ring: ring); // first start after the update: delete fails
    expect(passphraseStore.values[EncryptedFileVault.keyName], 'THE DATA KEY');
    for (var start = 2; start <= 5; start++) {
      await moveKeyringKey(passphraseStore, dir, ring: ring); // later starts: the keyring answers now
    }
    print('keyring after five starts: ${ring.values}');
    expect(ring.values, isEmpty, reason: 'the data key is still in the desktop keyring, open to any same-user program');
  });
}
