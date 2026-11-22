// Review round 5, reviewer C: proof tests for the Linux passphrase change (core/passphrase_key_store.dart).
// Each test states the safe behaviour; each failed on ca6a73b and passes since the round 5 fixes (C-02 with the key
// renewal Settings runs after a change, EncryptedFileVault.rotateKey).
//
// C-01: a change stopped or failing while the keys are being sealed again (before the staged set-up file exists) is
//       "finished" at the next opening (or at the next try, which opens the store first): the old passphrase still
//       passes its check, but the data key is now sealed under a salt that was never written anywhere, so neither
//       passphrase can open the data again.
// C-02: a change seals the same data key again; a copy of keys/ taken before the change (a home-folder backup, for
//       example) with the old passphrase still opens everything saved after it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';

const quick = StretchSettings(memoryKib: 8192, iterations: 1);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('r5c_pass'));
  tearDown(() => dir.delete(recursive: true));

  Future<PassphraseKeyStore> withData() async {
    final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData()..homeworkDue = 'my private words');
    // a set-aside key, as "Start fresh" on the recovery screen leaves one
    await keys.write('${EncryptedFileVault.keyName}.unreadable-2026-11-01', 'an-older-key');
    return keys;
  }

  Future<String?> homeworkWith(String passphrase) async {
    final keys = await PassphraseKeyStore.open(dir, passphrase);
    return (await EncryptedFileVault(keychain: keys, folder: () async => dir).load()).homeworkDue;
  }

  Future<String?> homeworkWithEither() async {
    for (final p in ['old phrase here', 'new phrase here']) {
      try {
        return await homeworkWith(p);
      } catch (_) {}
    }
    return null;
  }

  // A write failure on one staged key (a full disk, an I/O error, a quota), forced by a folder of that name on the key
  // listed LAST, so every key listed before it has already been staged. Listing order depends on the file system
  // (tmpfs lists the newest first), so the data key is written again until a set-aside key is listed after it.
  Future<Directory> blockLastStagedKey(PassphraseKeyStore keys) async {
    List<String> listed() => [for (final e in Directory('${dir.path}/keys').listSync().whereType<File>())
      if (e.path.endsWith('.wrap')) e.path];
    for (var i = 0; i < 10 && listed().last.endsWith('${EncryptedFileVault.keyName}.wrap'); i++) {
      final v = (await keys.read(EncryptedFileVault.keyName))!;
      await keys.delete(EncryptedFileVault.keyName);
      await keys.write(EncryptedFileVault.keyName, v);
    }
    expect(listed().last.endsWith('${EncryptedFileVault.keyName}.wrap'), isFalse);
    return Directory('${listed().last}.next')..createSync();
  }

  test('control: the helper sees the data after a change that completes (so the failures below are not the helper)',
      () async {
    final keys = await withData();
    await keys.changePassphrase('new phrase here');
    expect(await homeworkWithEither(), 'my private words');
    expect(await homeworkWith('new phrase here'), 'my private words');
  });

  test('C-01 (stopped): a change stopped after sealing the keys, before the staged set-up file, keeps the data',
      () async {
    await withData();
    // Exactly what changePassphrase leaves on disk when stopped after its first loop and before
    // `staged.writeAsString`: a real change on a copy of keys/, carried back as .wrap.next files only.
    final copy = Directory('${dir.path}_copy')..createSync();
    addTearDown(() => copy.delete(recursive: true));
    Directory('${copy.path}/keys').createSync();
    for (final e in Directory('${dir.path}/keys').listSync().whereType<File>()) {
      e.copySync('${copy.path}/keys/${e.uri.pathSegments.last}');
    }
    await (await PassphraseKeyStore.open(copy, 'old phrase here')).changePassphrase('new phrase here');
    for (final e in Directory('${copy.path}/keys').listSync().whereType<File>().where((f) => f.path.endsWith('.wrap'))) {
      e.copySync('${dir.path}/keys/${e.uri.pathSegments.last}.next');
    }
    expect(File('${dir.path}/keys/passphrase.json.next').existsSync(), isFalse);
    // next start: one of the two passphrases must still open the data
    expect(await homeworkWithEither(), 'my private words');
  });

  test('C-01 (failed): a change that fails while sealing the keys leaves the old passphrase working, as the screen says',
      () async {
    final keys = await withData();
    final blocker = await blockLastStagedKey(keys);
    await expectLater(keys.changePassphrase('new phrase here'), throwsA(isA<FileSystemException>()));
    // ChangePassphraseScreen now says: "The passphrase could not be changed just now, so the old one still opens Solace."
    blocker.deleteSync();
    expect(await homeworkWithEither(), 'my private words');
  });

  test('C-01 (retry): trying again after a failed change does not destroy the data key', () async {
    final keys = await withData();
    final blocker = await blockLastStagedKey(keys);
    await expectLater(keys.changePassphrase('new phrase here'), throwsA(isA<FileSystemException>()));
    blocker.deleteSync(); // the person frees some space and tries again from Settings
    try {
      await PassphraseKeyStore.open(dir, 'old phrase here'); // ChangePassphraseScreen's check of the current one
      await keys.changePassphrase('new phrase here');
    } catch (_) {}
    expect(await homeworkWithEither(), 'my private words');
  });

  test('C-02: a copy of keys/ from before a change, with the old passphrase, cannot open data saved after it',
      () async {
    final keys = await withData();
    final stolen = Directory('${dir.path}_stolen')..createSync();
    addTearDown(() => stolen.delete(recursive: true));
    Directory('${stolen.path}/keys').createSync();
    for (final e in Directory('${dir.path}/keys').listSync().whereType<File>()) {
      e.copySync('${stolen.path}/keys/${e.uri.pathSegments.last}');
    }
    // the person changes the passphrase because they think it is known (Settings then renews the data key, as
    // ChangePassphraseScreen does through EncryptedFileVault.rotateKey), then keeps using Solace
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.load();
    await keys.changePassphrase('new phrase here');
    await vault.rotateKey();
    await vault.save(AppData()..homeworkDue = 'after the change');
    final old = await PassphraseKeyStore.open(stolen, 'old phrase here');
    await expectLater(EncryptedFileVault(keychain: old, folder: () async => dir).load(), throwsA(anything),
        reason: 'the old passphrase and an old copy of keys/ must open nothing written after the change');
  });
}
