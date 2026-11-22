// Review round 5, reviewer C, C-03 (the first test FAILS on ca6a73b; the second documents the consequence and
// passes): main.dart boot() takes the one-copy lock (running.lock) only on Linux and
// Windows. A Mac can run two copies of Solace (`open -n Solace.app`, or a second copy of the bundle), and both share
// the same sandbox container, so two EncryptedFileVaults write the same data_v1.bin. This shows what that does to a
// crisis record: the copy that did not see it writes over it, and the last good copy (.bak) follows.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/recovery.dart';

import '../review_c1_flows_test.dart' as c1;

class _Keys extends KeyStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String name) async => m[name];
  @override
  Future<void> write(String name, String value) async => m[name] = value;
  @override
  Future<void> delete(String name) async => m.remove(name);
}

void main() {
  // Fix (round 5, C-03): the decision moved into main.dart takesOneCopyLock, so this proof now checks that decision and
  // what boot() does on a Mac while another copy holds running.lock, instead of reading the source line for "isMacOS".
  test('C-03: the one-copy lock (running.lock) is taken on the Mac too', () async {
    expect(takesOneCopyLock('macos'), isTrue,
        reason: 'boot() skips the one-copy lock on the Mac, where two copies share one container');
    final dir = await Directory.systemTemp.createTemp('r5c_mac');
    addTearDown(() => dir.delete(recursive: true));
    var touched = 0, asked = 0;
    final shown = <Widget>[];
    await boot(c1.prompts, c1.library, EncryptedFileVault(keychain: _Keys(), folder: () async {
      touched++;
      return dir;
    }), os: 'macos', onlyCopy: () async {
      asked++;
      return false; // the first copy holds the lock
    }, run: shown.add);
    expect(asked, 1, reason: 'the second copy on a Mac did not ask for the one-copy lock');
    expect(shown.single, isA<AlreadyOpenApp>());
    expect(touched, 0, reason: 'the second copy touched the store');
  });

  test('C-03: two running copies over one container lose a crisis record, the .bak included', () async {
    final dir = await Directory.systemTemp.createTemp('r5c_two');
    addTearDown(() => dir.delete(recursive: true));
    final keychain = _Keys(); // one login keychain item, shared by both copies
    Future<Directory> folder() async => dir;
    final first = EncryptedFileVault(keychain: keychain, folder: folder);
    await first.save(AppData()..homeworkDue = 'start');

    // copy 1 is open; the person opens Solace again (a second copy) and it loads the same file
    final copy1 = await first.load();
    final copy2Vault = EncryptedFileVault(keychain: keychain, folder: folder);
    final copy2 = await copy2Vault.load();

    // in copy 1 the person says they are not safe: the crisis is recorded and saved at once
    copy1.safetyEvents.add({'date': '2026-11-14', 'level': 'crisis', 'reason': 'rules'});
    copy1.safetyWatch = {'since': '2026-11-14T22:00:00', 'reason': 'rules'};
    await first.save(copy1);
    expect((await EncryptedFileVault(keychain: keychain, folder: folder).load()).safetyEvents, hasLength(1));

    // copy 2, still open in another window, saves anything (a mood, the window's place)
    copy2.moods['2026-11-14'] = 6;
    await copy2Vault.save(copy2);

    final after = await EncryptedFileVault(keychain: keychain, folder: folder).load();
    expect(after.safetyEvents, isEmpty, reason: 'the crisis record is gone');
    expect(after.safetyWatch, isNull, reason: 'the 7-day safety check is gone');
    // and the last good copy holds the same overwritten data, so nothing can bring it back
    File('${dir.path}/data_v1.bin').deleteSync();
    final fromBak = await EncryptedFileVault(keychain: keychain, folder: folder).load();
    expect(fromBak.safetyEvents, isEmpty);
  });
}
