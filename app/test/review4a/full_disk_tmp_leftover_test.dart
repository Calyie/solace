// Review round 4, A: a save that fails because the device is full leaves its partial temporary file behind (and a
// failed .bak copy leaves a truncated last-good copy), so the space it took stays used until Solace restarts.
// Needs a small separate filesystem; run it as tools in review4a describe:
//   unshare -rm sh -c 'mount -t tmpfs -o size=1m tmpfs <dir> && SOLACE_FULL_DIR=<dir> flutter test <this file>'
// Without SOLACE_FULL_DIR it is skipped. It failed on 5bdac57 and passes since the round 4 fix.
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

int freeBytes(String path) {
  final r = Process.runSync('df', ['-B1', '--output=avail', path]);
  return int.parse('${r.stdout}'.trim().split('\n').last.trim());
}

void main() {
  final root = Platform.environment['SOLACE_FULL_DIR'];
  test('a save that fails for lack of space gives the space back', () async {
    final dir = Directory('$root/store')..createSync(recursive: true);
    final keys = _Keys();
    final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
    final data = AppData();
    data.journal.add({'date': '2026-11-14', 'text': 'x' * 150000}); // about 150 KB of the person's words
    await vault.save(data); // main file
    await vault.save(data); // and its .bak
    // the device fills up (other apps, photos): leave about 100 KB free
    final filler = File('$root/filler');
    final free = freeBytes(root!);
    filler.writeAsBytesSync(List.filled(free - 100 * 1024, 0));
    final before = freeBytes(root);
    data.journal.add({'date': '2026-11-15', 'text': 'y' * 150000});
    Object? error;
    try {
      await vault.save(data);
    } catch (e) {
      error = e;
    }
    final left = dir.listSync().map((e) => '${e.uri.pathSegments.last} ${(e as File).lengthSync()}').toList();
    print('save failed with: ${error.runtimeType}; free before $before, after ${freeBytes(root)}; files: $left');
    expect(error, isNotNull, reason: 'the save cannot fit');
    expect(dir.listSync().where((e) => e.path.contains('.tmp')), isEmpty,
        reason: 'a failed save must not keep its partial temporary file (the device stays full until a restart)');
    expect(freeBytes(root), greaterThanOrEqualTo(before - 4096), reason: 'the free space it found is given back');
  }, skip: root == null ? 'needs SOLACE_FULL_DIR on a small filesystem' : false);
}
