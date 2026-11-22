// Review round 4, A: a selective delete leaves the deleted text readable in data_v1.bin.bak until another save.
// Proof test: it failed on commit 5bdac57, passes since the round 4 fix (the deleted session is still in the .bak, under the same key).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';

class _Keys implements KeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async => values[name] = value;
  @override
  Future<void> delete(String name) async => values.remove(name);
  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  late Directory dir, other;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('r4a_bak');
    other = Directory.systemTemp.createTempSync('r4a_bak_open');
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
    other.deleteSync(recursive: true);
  });

  test('a session the person deleted is not still readable in the .bak copy', () async {
    final keys = _Keys();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    final data = AppData();
    data.sessions.add(SessionRecord(date: '2026-11-10', kind: 'session',
        turns: [('person', 'SECRET: what happened to me that night')], note: 'SECRET note'));
    await vault.save(data);
    data.moods['2026-11-11'] = 4; // an ordinary later save, so a .bak exists
    await vault.save(data);

    // Settings > Space Solace uses > Choose what to delete: the session goes, and the data is saved once
    data.sessions.clear();
    await vault.save(data);

    expect((await EncryptedFileVault(keychain: keys, folder: () async => dir).load()).sessions, isEmpty,
        reason: 'the main file no longer has it');
    // anyone who can open the main file (same key) can open the .bak beside it
    File('${dir.path}/data_v1.bin.bak').copySync('${other.path}/data_v1.bin');
    final fromBak = await EncryptedFileVault(keychain: keys, folder: () async => other).load();
    final leftover = fromBak.sessions.expand((s) => s.turns.map((t) => t.$2)).toList();
    print('sessions still readable in data_v1.bin.bak after the delete: $leftover');
    expect(leftover, isEmpty, reason: 'deleted words must not survive in the last-good copy');
  });
}
