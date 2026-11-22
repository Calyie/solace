// Round 6 review E, E-13 (the proof failed on 4a8da11 and passes since the round 6 fix): a key renewal that fails part way (EncryptedFileVault.rotateKey: the re-seal could not
// write) leaves the previous key waiting. A second passphrase change in the same run then makes no new data key
// (`_rotate` only makes one when no previous key is waiting): it re-seals under the key made by the first change. A
// copy of keys/ taken between the two changes (with the passphrase of then) still opens everything saved after the
// second change, which C-02 and docs/SECURITY.md section 7 say cannot happen.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

import '../vault_test.dart' show FakeKeyStore;

Future<bool> _opensWith(File f, String b64) async {
  try {
    await AesGcm.with256bits().decrypt(
        SecretBox.fromConcatenation(f.readAsBytesSync(), nonceLength: 12, macLength: 16),
        secretKey: SecretKey(base64Decode(b64)));
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('E-13: after a renewal that failed, the next change still renews the data key', () async {
    final dir = Directory.systemTemp.createTempSync('r6e_rot');
    addTearDown(() => dir.deleteSync(recursive: true));
    const name = EncryptedFileVault.keyName;
    final keys = FakeKeyStore();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData()..homeworkDue = 'before'); // its temporary file was data_v1.bin.tmp0
    final k0 = keys.values[name]!;
    // first change: the re-seal's write fails (here a folder where its temporary file goes; on a device a full disk)
    final blocker = Directory('${dir.path}/data_v1.bin.tmp1')..createSync();
    await expectLater(vault.rotateKey(), throwsA(anything));
    final k1 = keys.values[name]!;
    expect(k1, isNot(k0));
    expect(keys.values['$name.previous'], k0, reason: 'both kept: "Solace finishes renewing its key then"');
    blocker.deleteSync();
    final copyBetween = k1; // a home-folder backup of keys/ taken now holds k1 (under the passphrase of then)
    // second change, same run: Settings calls rotateKey again
    await vault.rotateKey();
    await vault.save(AppData()..homeworkDue = 'after the second change');
    // the safe behaviour: a new data key for the second change, so the copy taken between the changes opens nothing
    // saved after it (on 4a8da11 the key is still k1)
    expect(keys.values[name], isNot(k1), reason: 'no new data key was made for the second change');
    expect(await _opensWith(File('${dir.path}/data_v1.bin'), copyBetween), isFalse,
        reason: 'the copy taken between the changes opens what was saved after the second one');
  });
}
