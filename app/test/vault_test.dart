// The encrypted store (security review 2026-11-14, F-01, F-02, F-05): overlapping saves never scramble the file,
// the key is made once and never over existing data, a damaged file falls back to the last good copy, a keychain
// that does not keep the key is reported, and unreadable data is set aside rather than erased.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

class FakeKeyStore implements KeyStore {
  final Map<String, String> values = {};
  int writes = 0;
  bool forgets = false; // a keychain that accepts a write but does not keep it
  @override
  Future<void> deleteAll() async => values.clear();
  @override
  Future<String?> read(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 2)); // keychains answer later, which is what races
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    writes++;
    if (!forgets) values[name] = value;
  }

  @override
  Future<void> delete(String name) async => values.remove(name);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vault_test'));
  tearDown(() => dir.deleteSync(recursive: true));
  EncryptedFileVault vault(FakeKeyStore keys) => EncryptedFileVault(keychain: keys, folder: () async => dir);

  test('fifty overlapping saves leave a file that opens, with the latest data, and one key', () async {
    final keys = FakeKeyStore();
    final v = vault(keys);
    final data = AppData();
    final saves = <Future<void>>[];
    for (var i = 0; i < 50; i++) {
      data.homeworkDue = 'step $i';
      saves.add(v.save(data)); // not awaited one by one, as the app's screens do
    }
    await Future.wait(saves);
    expect(keys.writes, 1, reason: 'the key is made exactly once');
    final again = await vault(keys).load();
    expect(again.homeworkDue, 'step 49');
    expect(dir.listSync().where((f) => f.path.contains('.tmp')), isEmpty, reason: 'no temporary file left behind');
  });

  test('a missing key with saved data is reported, never replaced by a new key', () async {
    final keys = FakeKeyStore();
    await vault(keys).save(AppData()..homeworkDue = 'keep me');
    keys.values.clear(); // the key went missing (for example a restore onto another phone)
    await expectLater(vault(keys).load(), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'key_missing')));
    await expectLater(vault(keys).save(AppData()), throwsA(isA<VaultError>()));
    expect(keys.values, isEmpty, reason: 'no new key was made over the old data');
  });

  test('a damaged file opens from the last good copy', () async {
    final keys = FakeKeyStore();
    final v = vault(keys);
    await v.save(AppData()..homeworkDue = 'first');
    await v.save(AppData()..homeworkDue = 'second');
    File('${dir.path}/data_v1.bin').writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
        19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]);
    // the last good copy is the newest checked save (round 4 review, A-02: a copy of the save before it kept deleted
    // data), so a damaged main file loses nothing
    expect((await vault(keys).load()).homeworkDue, 'second');
  });

  test('a keychain that does not keep the key is reported before anything is saved', () async {
    final keys = FakeKeyStore()..forgets = true;
    await expectLater(vault(keys).save(AppData()), throwsA(isA<VaultError>().having((e) => e.kind, 'kind', 'keychain')));
    expect(File('${dir.path}/data_v1.bin').existsSync(), isFalse);
  });

  test('starting fresh sets the unreadable data aside instead of erasing it', () async {
    final keys = FakeKeyStore();
    await vault(keys).save(AppData()..homeworkDue = 'old');
    keys.values.clear();
    final v = vault(keys);
    await v.setAside();
    expect(dir.listSync().where((f) => f.path.contains('unreadable')), isNotEmpty);
    await v.save(AppData()..homeworkDue = 'new');
    expect((await vault(keys).load()).homeworkDue, 'new');
  });
}
