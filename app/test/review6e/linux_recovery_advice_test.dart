// Round 6 review E, E-05 (the proof failed on 4a8da11 and passes since the round 6 fix, with its premise adjusted: the
// failure now has its own kind, 'key_unreadable', as the report suggested): on Linux a data key that cannot be unwrapped (its .wrap file damaged, or sealed under
// another passphrase) is reported as a "keychain" problem. The recovery screen then tells the person to "unlock your
// keyring" (Linux no longer keeps the key in the keyring: the passphrase does) and offers no Start fresh, so Try again
// is the only button and it can never work. The way out ("I have forgotten it" on the passphrase screen) is not
// mentioned, and the person typed the right passphrase.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/recovery.dart';

import '../review_c1_flows_test.dart' as c1;

const quick = StretchSettings(memoryKib: 8192, iterations: 1);

void main() {
  testWidgets('E-05: a damaged wrapped key on Linux: right advice and a way forward', (tester) async {
    final dir = Directory.systemTemp.createTempSync('r6e_rec');
    addTearDown(() => dir.deleteSync(recursive: true));
    final shown = <Widget>[];
    await tester.runAsync(() async {
      final keys = await PassphraseKeyStore.create(dir, 'my good passphrase', settings: quick);
      await EncryptedFileVault(keychain: keys, folder: () async => dir).save(AppData()..homeworkDue = 'mine');
      // one byte of the wrapped data key changes (a disk error, a bad copy back from a backup)
      final wrap = File('${dir.path}/keys/${EncryptedFileVault.keyName}.wrap');
      final b = wrap.readAsBytesSync();
      b[b.length - 1] ^= 1;
      wrap.writeAsBytesSync(b);
      // the next start: the right passphrase opens the set-up check, then the store is opened
      final again = await PassphraseKeyStore.open(dir, 'my good passphrase');
      await boot(c1.prompts, c1.library, EncryptedFileVault(keychain: again, folder: () async => dir),
          oneCopyChecked: true, run: shown.add, os: 'linux', passphrase: again, passphraseDir: dir);
    });
    expect(shown.single, isA<RecoveryApp>());
    final error = (shown.single as RecoveryApp).error;
    // the kind of failure: on 4a8da11 'keychain' (a keychain to unlock); since round 6 its own kind, as this
    // report's fix suggested, so the screen can offer Start fresh (adjusted with the fix: the premise named the bug)
    expect(error, isA<VaultError>().having((e) => e.kind, 'kind', 'key_unreadable'));
    await tester.pumpWidget(shown.single);
    await tester.pumpAndSettle();
    // the safe behaviour: no advice that cannot help (the key is under the passphrase, not in a keyring), and a way
    // forward other than Try again, which can never work here (Start fresh, or the way to "I have forgotten it")
    expect(find.textContaining('unlock your keyring'), findsNothing);
    expect(find.text('Start fresh').evaluate().isNotEmpty || find.textContaining('forgotten').evaluate().isNotEmpty,
        isTrue, reason: 'Try again is the only button, and it fails every time');
  });
}
