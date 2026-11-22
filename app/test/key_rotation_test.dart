// Round 5 review (C-02): a new data key after the Linux passphrase changes. The old key is kept under a second name
// and the new one is kept, each confirmed; every read tries both; the store and every picture are sealed again under
// the new key; then the old key is deleted. Stopped anywhere, both keys remain and the next opening finishes it. A
// copy of the old key then opens nothing written after the change.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

import 'vault_test.dart' show FakeKeyStore;

Future<bool> opensWith(File f, String b64) async {
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
  setUp(() async => dir = await Directory.systemTemp.createTemp('rotate'));
  tearDown(() => dir.delete(recursive: true));
  const name = EncryptedFileVault.keyName;
  final picture = Uint8List.fromList(List.generate(300, (i) => i % 251));

  test('after a key change the store, its last good copy and every picture open only with the new key', () async {
    final keys = FakeKeyStore();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData()..homeworkDue = 'before');
    final id = await vault.putMedia(picture);
    final oldKey = keys.values[name]!;
    await vault.rotateKey();
    final newKey = keys.values[name]!;
    expect(newKey, isNot(oldKey));
    expect(keys.values.containsKey('$name.previous'), isFalse, reason: 'the old key is deleted once all is resealed');
    for (final f in [File('${dir.path}/data_v1.bin'), File('${dir.path}/data_v1.bin.bak'),
      File('${dir.path}/media/$id.bin')]) {
      expect(await opensWith(f, newKey), isTrue, reason: f.path);
      expect(await opensWith(f, oldKey), isFalse, reason: f.path);
    }
    await vault.save(AppData()..homeworkDue = 'after');
    expect(await opensWith(File('${dir.path}/data_v1.bin'), oldKey), isFalse);
    final again = EncryptedFileVault(keychain: keys, folder: () async => dir);
    expect((await again.load()).homeworkDue, 'after');
    expect(await again.getMedia(id), picture);
  });

  test('a key change stopped after the new key was kept, before anything was resealed, is finished at the next '
      'opening; nothing is lost on the way', () async {
    final keys = FakeKeyStore();
    final first = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await first.save(AppData()..homeworkDue = 'kept');
    final id = await first.putMedia(picture);
    // what a stop right after the new key was kept leaves: both keys, everything still under the old one
    final oldKey = keys.values[name]!;
    keys.values['$name.previous'] = oldKey;
    keys.values[name] = base64Encode(List<int>.generate(32, (i) => (i * 7 + 3) % 256));
    final next = EncryptedFileVault(keychain: keys, folder: () async => dir);
    expect((await next.load()).homeworkDue, 'kept', reason: 'read with the previous key');
    expect(await next.getMedia(id), picture, reason: 'pictures too, before they are resealed');
    await next.save(AppData()..homeworkDue = 'kept'); // runs after the resealing the opening queued
    expect(keys.values.containsKey('$name.previous'), isFalse);
    expect(await opensWith(File('${dir.path}/media/$id.bin'), keys.values[name]!), isTrue);
    expect(await opensWith(File('${dir.path}/media/$id.bin'), oldKey), isFalse);
  });

  test('a key change stopped after the old key was copied but before the new one: the next opening tidies it', () async {
    final keys = FakeKeyStore();
    final first = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await first.save(AppData()..homeworkDue = 'kept');
    keys.values['$name.previous'] = keys.values[name]!; // the same key under both names
    final next = EncryptedFileVault(keychain: keys, folder: () async => dir);
    expect((await next.load()).homeworkDue, 'kept');
    await next.save(AppData()..homeworkDue = 'kept');
    expect(keys.values.containsKey('$name.previous'), isFalse);
  });

  test('a keychain that does not keep the new key changes nothing', () async {
    final keys = FakeKeyStore();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData()..homeworkDue = 'kept');
    final oldKey = keys.values[name]!;
    keys.forgets = true;
    await expectLater(vault.rotateKey(), throwsA(isA<VaultError>()));
    keys.forgets = false;
    expect(keys.values[name], oldKey);
    expect((await EncryptedFileVault(keychain: keys, folder: () async => dir).load()).homeworkDue, 'kept');
  });

  test('Delete everything removes a waiting previous key too', () async {
    final keys = FakeKeyStore();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await vault.save(AppData());
    keys.values['$name.previous'] = keys.values[name]!;
    await vault.wipe();
    expect(keys.values, isEmpty);
  });
}
