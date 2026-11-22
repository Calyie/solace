// Round 7 review A, G7-05 (the proof failed on c8e45c9 and passes since the round 7 fix): PassphraseKeyStore._settleStaged keeps a staged key (`<name>.wrap.next`) only if it opens
// under the passphrase just proved, and deletes it otherwise; but a staged key that cannot be READ (an I/O error, a
// permission problem, a file briefly held) is treated as one that does not open, and deleted. After the commit point
// of a change (the set-up file already holds the new passphrase), the staged copy is the only copy of the data key
// sealed under that passphrase; the kept `.wrap` is under the old one, whose salt is gone. Deleting it locks every
// piece of data away for good: the case round 5's C-01 fix set out to make impossible. Reached at the next opening
// after a change stopped between its commit and its tidy, or in the tidy of the change itself. The unreadable moment
// is made with file permissions (the test does not run as root). This test asserts the SAFE behaviour, so it fails
// while the finding stands.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';

const quick = StretchSettings(memoryKib: 8192, iterations: 1);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('r7a_settle'));
  tearDown(() => dir.delete(recursive: true));

  test('G7-05: a staged key that could not be read is kept, not deleted', () async {
    const name = EncryptedFileVault.keyName;
    final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
    await keys.write(name, 'the-data-key');
    await keys.changePassphrase('new phrase here');
    // as passphrase_change_test.dart builds it: stopped after the set-up file was replaced, before the key followed
    // (the kept key is still under the old passphrase, the staged one under the new)
    final live = File('${dir.path}/keys/$name.wrap');
    live.renameSync('${live.path}.next');
    final other = await PassphraseKeyStore.create(Directory('${dir.path}/b'), 'old phrase here', settings: quick);
    await other.write(name, 'the-data-key');
    File('${dir.path}/b/keys/$name.wrap').copySync(live.path);
    // the next opening, while the staged file cannot be read for a moment
    final staged = File('${live.path}.next');
    Process.runSync('chmod', ['000', staged.path]);
    Object? firstOpen;
    try {
      await PassphraseKeyStore.open(dir, 'new phrase here');
      firstOpen = 'opened';
    } catch (e) {
      firstOpen = e;
    }
    if (staged.existsSync()) Process.runSync('chmod', ['600', staged.path]);
    // a later opening, once the file reads again
    String? key;
    Object? why;
    try {
      key = await (await PassphraseKeyStore.open(dir, 'new phrase here')).read(name);
    } catch (e) {
      why = e;
    }
    expect(key, 'the-data-key',
        reason: 'first opening: $firstOpen; the staged key was ${staged.existsSync() ? 'kept' : 'deleted'}; the data '
            'key can no longer be read under the passphrase ($why), so every piece of data is locked away');
  });
}
