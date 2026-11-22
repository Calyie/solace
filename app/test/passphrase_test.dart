// Linux: the data key under a passphrase, not the desktop keyring (OWASP review OW-M9-1, owner 2026-11-14): set once,
// typed at each fresh start, never stored; a wrong passphrase opens nothing; the vault works through it; Delete
// everything keeps the passphrase set-up.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/passphrase_screen.dart';

import 'app_flow_test.dart' as flow;

const quick = StretchSettings(memoryKib: 8192, iterations: 1); // fast for tests; the app uses 64 MiB, 2 passes

void main() {
  setUpAll(flow.loadFonts);
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('pass'));
  tearDown(() => dir.delete(recursive: true));

  test('set once, opened with the same passphrase, refused with another; the passphrase is never stored', () async {
    expect(await PassphraseKeyStore.isSetUp(dir), isFalse);
    final keys = await PassphraseKeyStore.create(dir, 'blue kettle morning', settings: quick);
    await keys.write(EncryptedFileVault.keyName, 'the-data-key');
    expect(await PassphraseKeyStore.isSetUp(dir), isTrue);
    final again = await PassphraseKeyStore.open(dir, 'blue kettle morning');
    expect(await again.read(EncryptedFileVault.keyName), 'the-data-key');
    await expectLater(PassphraseKeyStore.open(dir, 'blue kettle evening'), throwsA(isA<WrongPassphrase>()));
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final text = String.fromCharCodes(f.readAsBytesSync());
      expect(text, isNot(contains('blue kettle')), reason: f.path);
      expect(text, isNot(contains('the-data-key')), reason: f.path);
    }
    expect(() => PassphraseKeyStore.create(dir, 'short', settings: quick), throwsArgumentError);
  });

  test('the encrypted store works through the passphrase; Delete everything keeps the set-up', () async {
    final keys = await PassphraseKeyStore.create(dir, 'a long enough phrase', settings: quick);
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData()..lastNote = 'Session: private words');
    final reopened = EncryptedFileVault(keychain: await PassphraseKeyStore.open(dir, 'a long enough phrase'),
        folder: () async => dir);
    expect((await reopened.load()).lastNote, 'Session: private words');
    await reopened.wipe();
    expect(await PassphraseKeyStore.isSetUp(dir), isTrue);
    expect(await keys.read(EncryptedFileVault.keyName), isNull);
  });

  testWidgets('the start screen: choose, then open; Support before anything', (tester) async {
    PassphraseKeyStore? opened;
    await tester.pumpWidget(PassphraseApp(dir: dir, settings: quick, onReady: (k) async => opened = k));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Choose a passphrase'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pass_support')));
    await tester.pumpAndSettle();
    expect(find.text('Support, any time'), findsOneWidget);
    Navigator.of(tester.element(find.text('Support, any time'))).pop();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pass_first')), 'short');
    await tester.enterText(find.byKey(const Key('pass_second')), 'short');
    await tester.tap(find.byKey(const Key('pass_go')));
    await tester.pump();
    expect(find.textContaining('at least 8 characters'), findsWidgets);
    await tester.enterText(find.byKey(const Key('pass_first')), 'quiet river stones');
    await tester.enterText(find.byKey(const Key('pass_second')), 'quiet river stones');
    await tester.tap(find.byKey(const Key('pass_go')));
    for (var i = 0; i < 50 && opened == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(opened, isNotNull);
  });
}
