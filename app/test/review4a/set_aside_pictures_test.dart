// Review round 4, A: "Start fresh" on the recovery screen promises the unreadable data is set aside, never deleted,
// with its key kept so it can be opened later (store.dart setAside, F-02). The pictures are not set aside: they stay in
// media/ under the old key, and the first tidy after the fresh start deletes them as strays. Failed on 5bdac57; passes since the round 4 fix.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';

import '../app_flow_test.dart' as flow;

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
  late Directory dir;
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('r4a_aside'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('pictures of data set aside by Start fresh survive the fresh start', () async {
    final keys = _Keys();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    final state = flow.makeState(vault: vault);
    await state.setPicture('My daughter', Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 9, 9, 9]));
    final pictures = Directory('${dir.path}/media').listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(pictures, hasLength(1));

    // the store becomes unreadable (both copies), so the app opens on the recovery screen
    for (final name in ['data_v1.bin', 'data_v1.bin.bak']) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) f.writeAsBytesSync(List.filled(200, 7));
    }
    final again = EncryptedFileVault(keychain: keys, folder: () async => dir);
    await expectLater(again.load(), throwsA(isA<VaultError>()));
    // Start fresh: set aside, then boot again (main.dart boot -> load -> keepPicturesApart, tidyPictures)
    await again.setAside();
    final fresh = flow.makeState(vault: again)..data = await again.load();
    await fresh.keepPicturesApart();
    await fresh.tidyPictures();

    final all = dir.listSync(recursive: true).map((e) => e.path.substring(dir.path.length)).toList()..sort();
    print('files after Start fresh: $all; keys kept: ${keys.values.keys.toList()}');
    final survived = all.where((p) => p.contains(pictures.single.replaceAll('.bin', ''))).toList();
    expect(survived, isNotEmpty, reason: 'the set-aside data keeps its key, but its picture was deleted as a stray');
  });
}
