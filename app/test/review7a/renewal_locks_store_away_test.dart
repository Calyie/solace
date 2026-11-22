// Round 7 review A, G7-03 (the proof failed on c8e45c9 and passes since the round 7 fix): a key renewal (EncryptedFileVault.rotateKey, Linux Settings > Change passphrase, and the
// re-seal the next opening queues) deletes the previous data key even when it could not read the store to seal it
// again: `_reseal` skips the write when neither data_v1.bin nor its .bak opens (`if (data != null)`), re-seals the
// pictures, then deletes `<key>.previous` and reports success. A store that could not be read at that moment (an I/O
// error, a permission change, a file briefly held) is still sealed under the deleted key, so it never opens again,
// although the design says "a change cut short anywhere leaves both keys, and the next opening finishes it, so nothing
// can be locked away" (store.dart rotateKey). This test asserts the SAFE behaviour, so it fails while the finding
// stands. The unreadable moment is made with file permissions (the test does not run as root).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

import '../vault_test.dart' show FakeKeyStore;

void main() {
  test('G7-03: a renewal that could not read the store keeps the key that opens it', () async {
    final dir = Directory.systemTemp.createTempSync('r7a_rot');
    addTearDown(() => dir.deleteSync(recursive: true));
    final keys = FakeKeyStore();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData()..homeworkDue = 'call my sister on Sunday');
    final main = File('${dir.path}/data_v1.bin'), bak = File('${dir.path}/data_v1.bin.bak');
    // the store cannot be read just while the renewal runs
    for (final f in [main, bak]) {
      Process.runSync('chmod', ['000', f.path]);
    }
    Object? outcome;
    try {
      await vault.rotateKey();
      outcome = 'renewal reported success';
    } catch (e) {
      outcome = e;
    }
    for (final f in [main, bak]) {
      Process.runSync('chmod', ['600', f.path]);
    }
    // the next start, with the keys as the renewal left them
    final reopened = EncryptedFileVault(keychain: keys, folder: () async => dir);
    String? opened;
    try {
      opened = (await reopened.load()).homeworkDue;
    } catch (e) {
      opened = null;
    }
    expect(opened, 'call my sister on Sunday',
        reason: 'renewal outcome: $outcome; the previous key was deleted '
            '(${keys.values.containsKey('${EncryptedFileVault.keyName}.previous') ? 'still kept' : 'gone'}) '
            'while the store was still sealed under it, so the store no longer opens');
  });
}
