// Round 4 review (A-09): the Linux passphrase can be changed. Every kept key is sealed again under a new salt and a
// key stretched from the new passphrase; the old passphrase then opens nothing. A change cut short at any step is
// finished or undone at the next opening, so the data always opens with exactly one of the two passphrases.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/passphrase_screen.dart';

const quick = StretchSettings(memoryKib: 8192, iterations: 1);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('passchange'));
  tearDown(() => dir.delete(recursive: true));

  Future<PassphraseKeyStore> setUpWithKeys() async {
    final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
    await keys.write(EncryptedFileVault.keyName, 'the-data-key');
    await keys.write('${EncryptedFileVault.keyName}.unreadable-2026-11-01', 'an-older-key');
    return keys;
  }

  test('after a change the new passphrase opens every key, the old one nothing, and the salt is new', () async {
    final keys = await setUpWithKeys();
    final oldSalt = keys.salt;
    await keys.changePassphrase('new phrase here');
    expect(keys.salt, isNot(oldSalt));
    // the same object keeps working: a key written after the change opens with the new passphrase
    await keys.write('later', 'written-after');
    await expectLater(PassphraseKeyStore.open(dir, 'old phrase here'), throwsA(isA<WrongPassphrase>()));
    final again = await PassphraseKeyStore.open(dir, 'new phrase here');
    expect(await again.read(EncryptedFileVault.keyName), 'the-data-key');
    expect(await again.read('${EncryptedFileVault.keyName}.unreadable-2026-11-01'), 'an-older-key');
    expect(await again.read('later'), 'written-after');
    expect(dir.listSync(recursive: true).where((f) => f.path.endsWith('.next')), isEmpty);
    expect(() => keys.changePassphrase('short'), throwsArgumentError);
  });

  test('the encrypted store opens with the new passphrase after a change', () async {
    final keys = await PassphraseKeyStore.create(dir, 'old phrase here', settings: quick);
    await EncryptedFileVault(keychain: keys, folder: () async => dir).save(AppData()..homeworkDue = 'kept');
    await keys.changePassphrase('new phrase here');
    final reopened = await PassphraseKeyStore.open(dir, 'new phrase here');
    expect((await EncryptedFileVault(keychain: reopened, folder: () async => dir).load()).homeworkDue, 'kept');
  });

  test('a change cut short before its set-up file was replaced is undone: the old passphrase still opens', () async {
    await setUpWithKeys();
    // what a change leaves when stopped just before the set-up file is replaced
    final staged = await PassphraseKeyStore.create(Directory('${dir.path}/other'), 'new phrase here', settings: quick);
    await staged.write(EncryptedFileVault.keyName, 'the-data-key');
    File('${dir.path}/other/keys/passphrase.json').copySync('${dir.path}/keys/passphrase.json.next');
    File('${dir.path}/other/keys/${EncryptedFileVault.keyName}.wrap')
        .copySync('${dir.path}/keys/${EncryptedFileVault.keyName}.wrap.next');
    final opened = await PassphraseKeyStore.open(dir, 'old phrase here');
    expect(await opened.read(EncryptedFileVault.keyName), 'the-data-key');
    expect(Directory('${dir.path}/keys').listSync().where((f) => f.path.endsWith('.next')), isEmpty);
  });

  test('a change cut short after its set-up file was replaced is finished: the new passphrase opens every key',
      () async {
    final keys = await setUpWithKeys();
    await keys.changePassphrase('new phrase here');
    // as if stopped after the set-up file was replaced but before one key followed: put an old key back beside its
    // staged copy
    final other = await PassphraseKeyStore.create(Directory('${dir.path}/b'), 'zzz old phrase', settings: quick);
    await other.write(EncryptedFileVault.keyName, 'the-data-key');
    final live = File('${dir.path}/keys/${EncryptedFileVault.keyName}.wrap');
    live.renameSync('${live.path}.next');
    File('${dir.path}/b/keys/${EncryptedFileVault.keyName}.wrap').copySync(live.path); // a key under another phrase
    final opened = await PassphraseKeyStore.open(dir, 'new phrase here');
    expect(await opened.read(EncryptedFileVault.keyName), 'the-data-key');
  });

  testWidgets('Settings > Change passphrase: a wrong current one changes nothing; the right one changes it',
      (tester) async {
    final keys = (await tester.runAsync(setUpWithKeys))!;
    await tester.pumpWidget(MaterialApp(home: ChangePassphraseScreen(dir: dir, keys: keys)));
    Future<void> fill(String current, String a, String b) async {
      await tester.enterText(find.byKey(const Key('pass_current')), current);
      await tester.enterText(find.byKey(const Key('pass_new')), a);
      await tester.enterText(find.byKey(const Key('pass_new_again')), b);
      await tester.tap(find.byKey(const Key('pass_change')));
      await tester.pump();
      for (var i = 0; i < 400; i++) { // until the stretch on its worker isolate is done (at most 20 s)
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        final m = find.byKey(const Key('pass_change_message'));
        if (m.evaluate().isNotEmpty && !(tester.widget<Text>(m).data ?? '').startsWith('Changing')) break;
      }
    }
    await fill('old phrase here', 'new phrase here', 'new phrase herE');
    expect(find.text('The two new passphrases are different.'), findsOneWidget);
    await fill('not the phrase', 'new phrase here', 'new phrase here');
    expect(find.text('That is not the current passphrase. Nothing was changed.'), findsOneWidget);
    expect(await tester.runAsync(() => PassphraseKeyStore.open(dir, 'old phrase here')), isNotNull);
    await fill('old phrase here', 'new phrase here', 'new phrase here');
    final shown = tester.widget<Text>(find.byKey(const Key('pass_change_message'))).data;
    expect(shown, 'Passphrase changed. Type the new one next time Solace opens.');
    final opened = await tester.runAsync(() => PassphraseKeyStore.open(dir, 'new phrase here'));
    expect(await tester.runAsync(() => opened!.read(EncryptedFileVault.keyName)), 'the-data-key');
  });
}
