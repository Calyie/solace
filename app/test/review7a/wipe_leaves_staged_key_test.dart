// Round 7 review A, G7-01 (the proof failed on c8e45c9 and passes since the round 7 fix): Delete everything on Linux deletes `*.wrap` key files only (PassphraseKeyStore.deleteAll),
// not a staged copy of the data key (`*.wrap.next`) that a passphrase change leaves when its tidy fails after the
// commit point (round 6 review, E-11: "the next opening finishes the tidy"). At that next opening the staged copy is
// settled back into place, so the data key deleted by Delete everything returns, and the fresh data saved afterwards
// is sealed under the old key: "every key Solace kept" was not removed (docs/SECURITY.md section 4), and a copy of
// keys/ from before the wipe opens what is saved after it. This test asserts the SAFE behaviour, so it fails while
// the finding stands.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';

const quick = StretchSettings(memoryKib: 8192, iterations: 1);

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
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('r7a_wipe'));
  tearDown(() => dir.delete(recursive: true));

  test('G7-01: Delete everything leaves no staged data key that the next opening puts back', () async {
    const name = EncryptedFileVault.keyName;
    final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData()..homeworkDue = 'private words');
    final before = (await keys.read(name))!;
    await keys.changePassphrase('new phrase here');
    // The state round 6's E-11 fix handles: the change passed its commit point (the set-up file is the new one), but
    // the tidy failed before the staged key replaced the kept one (PassphraseChangedNotSettled; the screen says the
    // next opening finishes it). The staged copy is sealed under the new passphrase; the kept one under the old.
    final live = File('${dir.path}/keys/$name.wrap');
    live.renameSync('${live.path}.next');
    final old = await PassphraseKeyStore.create(Directory('${dir.path}/b'), 'old phrase here', settings: quick);
    await old.write(name, before);
    File('${dir.path}/b/keys/$name.wrap').copySync(live.path);
    // In the same run the person uses Delete everything (AppState.wipeEverything calls vault.wipe; wipeAppFolders
    // keeps keys/ on Linux so the passphrase set-up stays)
    await vault.wipe();
    final left = [for (final e in Directory('${dir.path}/keys').listSync()) e.uri.pathSegments.last];
    // Next start: the passphrase screen opens the store, which settles what the change left
    final reopened = await PassphraseKeyStore.open(dir, 'new phrase here');
    final fresh = EncryptedFileVault(keychain: reopened, folder: () async => dir);
    expect((await fresh.load()).homeworkDue, isEmpty, reason: 'the data itself is gone, as it should be');
    await fresh.save(AppData()..homeworkDue = 'saved after Delete everything');
    // the safe behaviour: no key from before Delete everything is kept, and nothing saved after it opens with one
    final problems = [
      if (left.any((n) => n.contains('.wrap'))) 'Delete everything left a wrapped copy of the data key in keys/: $left',
      if (await reopened.read(name) == before) 'the data key deleted by Delete everything came back at the next opening',
      if (await _opensWith(File('${dir.path}/data_v1.bin'), before))
        'what was saved after Delete everything opens with the key from before it',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
