// The platform's own key storage under the app's real encrypted store (owner, 2026-11-14: "make sure the platform based
// trusted encryption works as expected"). The REAL EncryptedFileVault with the REAL PlatformKeyStore
// (core/store.dart), in the app's real support folder, on the device or desktop it runs on:
//   (a) data_v1.bin holds no plain text: not a unique marker, not the JSON field names
//   (b) a fresh vault opens it again, marker and all
//   (c) the key is in the platform store: 32 bytes, read back by a fresh key store; never printed; and it is in no file
//       of the app's own folders
//   (d) one flipped byte in data_v1.bin: it is refused and the .bak (the last good copy, which since round 4 review
//       A-02 holds the newest save, not the one before) opens instead, with nothing lost; both damaged: a clear
//       VaultError and both files still on disk
//   (e) the key gone while data is there: a clear key_missing error, no new key made over the data, nothing written
//   then everything is wiped (files and key) and checked gone.
// It refuses to run where Solace data already exists, so it never touches a real person's data.
// Built and run like the traffic test (integration_test/traffic_test.dart): under `flutter test`, or as the app's
// entry in release mode with --dart-define=TRAFFIC_EXIT=true. Desktop runs read VAULT_MODE from the environment:
//   full (default) | seed (save the marker twice and leave files and key) | no-keyring-fresh | no-keyring-existing
// The last two are for Linux with no Secret Service: what the store and the real app (its own main) do then.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/unlock_key.dart';
import 'package:solace/main.dart' as app;

const exitWhenDone = bool.fromEnvironment('TRAFFIC_EXIT');
const keyName = 'solace_data_key_v1'; // EncryptedFileVault's item in the platform store

final checks = <String, String>{};
var done = false;
String? failure;

void record(String name, String result) {
  checks[name] = result;
  // ignore: avoid_print
  print('VAULT CHECK $name: $result');
}

bool contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

Future<String> sha(File f) async => (await Sha256().hash(await f.readAsBytes())).bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> appears(WidgetTester tester, Finder f, int seconds) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) return false;
    await tester.pump(const Duration(milliseconds: 200));
  }
  return true;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  expect(await appears(tester, f, 20), isTrue, reason: 'the $key button appears');
  await tester.ensureVisible(f);
  await frames(tester, 400);
  await tester.tap(f, warnIfMissed: false);
  await frames(tester, 900);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final mode = Platform.environment['VAULT_MODE'] ?? 'full';

  tearDownAll(() async {
    final result = {'done': done, 'failure': failure, 'mode': mode, 'platform': Platform.operatingSystem,
        'build': kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug', 'checks': checks};
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/vault_result.json').writeAsString(const JsonEncoder.withIndent(' ').convert(result));
    } catch (_) {}
    // ignore: avoid_print
    print(done ? 'VAULT CHECKS DONE ($mode)' : 'VAULT CHECKS FAILED ($mode): $failure');
    if (exitWhenDone) Timer(const Duration(seconds: 3), () => exit(done ? 0 : 1));
  });

  testWidgets('the real encrypted store with the platform key store ($mode)', (tester) async {
    try {
      final support = await getApplicationSupportDirectory();
      final file = File('${support.path}/data_v1.bin'), bak = File('${file.path}.bak');
      record('folder', support.path);
      final r = Random.secure();
      final marker = 'solace-vault-marker-${List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join()}';

      if (mode == 'no-keyring-fresh') {
        // no Secret Service: the store cannot make its key, so nothing may be written; then the real app
        expect(file.existsSync() || bak.existsSync(), isFalse, reason: 'a fresh home');
        try {
          await EncryptedFileVault().save(AppData(lastNote: marker));
          record('save_without_keyring', 'UNEXPECTED: saved');
          fail('a save worked with no Secret Service');
        } on VaultError catch (e) {
          record('save_without_keyring', 'refused with VaultError(${e.kind}): ${e.message}');
        }
        expect(file.existsSync(), isFalse, reason: 'nothing written without a key');
        record('data_file_after_refusal', 'none written');
        await app.main();
        await frames(tester, 2000);
        final opened = await appears(tester, find.byKey(const Key('onb_next')), 60);
        record('app_start_without_keyring', opened ? 'the first-run steps show' : 'the first-run steps did NOT show');
        expect(opened, isTrue);
        for (final k in ['onb_next', 'onb_next', 'onb_understand', 'onb_country']) {
          await tapKey(tester, k);
        }
        await tester.tap(find.text('Ireland').last);
        await frames(tester, 900);
        for (final k in ['onb_next', 'onb_adult', 'onb_next', 'onb_finish']) {
          await tapKey(tester, k);
        }
        final warned = await appears(tester, find.text('Your last change could not be saved'), 20);
        record('app_first_save_without_keyring', warned
            ? 'the app says "Your last change could not be saved" and keeps running'
            : 'NO WARNING shown');
        expect(warned, isTrue);
        expect(file.existsSync(), isFalse);
        done = true;
        return;
      }

      if (mode == 'no-keyring-existing') {
        // data saved earlier with the Secret Service running (seed mode); now there is none
        expect(file.existsSync(), isTrue, reason: 'seeded data is there');
        final before = {for (final f in [file, bak]) if (f.existsSync()) f.path: await sha(f)};
        record('seeded_files', '${before.length} (data_v1.bin${bak.existsSync() ? ' and .bak' : ''})');
        try {
          await EncryptedFileVault().load();
          record('load_without_keyring', 'UNEXPECTED: opened');
          fail('the data opened with no Secret Service');
        } on VaultError catch (e) {
          record('load_without_keyring', 'refused with VaultError(${e.kind}): ${e.message}');
        }
        await app.main();
        await frames(tester, 2000);
        final recovery = await appears(tester, find.textContaining('could not open your saved data'), 60);
        record('app_start_without_keyring', recovery
            ? 'the recovery screen shows (crisis numbers, Try again, Start fresh)'
            : 'the recovery screen did NOT show');
        expect(recovery, isTrue);
        if (find.text('Try again').evaluate().isNotEmpty) {
          await tester.tap(find.text('Try again'));
          await frames(tester, 3000);
          record('try_again_without_keyring', find.textContaining('could not open your saved data').evaluate().isNotEmpty
              ? 'still the recovery screen' : 'left the recovery screen');
        }
        final after = {for (final f in [file, bak]) if (f.existsSync()) f.path: await sha(f)};
        record('files_unchanged', mapEquals(before, after) ? 'yes, byte for byte' : 'NO: $before -> $after');
        expect(after, before);
        done = true;
        return;
      }

      // full and seed: never where Solace data already exists
      if (file.existsSync() || bak.existsSync()) {
        fail('Solace data already exists in ${support.path}; this check runs only on a fresh install');
      }
      final keys = PlatformKeyStore();
      record('key_before', await keys.read(keyName) == null ? 'none' : 'one was already there (no data with it)');

      final vault = EncryptedFileVault();
      await vault.save(AppData(lastNote: marker, journal: [{'date': '2026-11-14', 'text': marker}]));
      final bytes = await file.readAsBytes();
      // (a) no plain text on disk
      final plain = [marker, '"last_note"', '"settings"', '"journal"'].where((s) => contains(bytes, utf8.encode(s)));
      record('a_no_plain_text', plain.isEmpty
          ? 'data_v1.bin (${bytes.length} bytes) holds neither the marker nor any JSON field name'
          : 'FOUND IN PLAIN BYTES: ${plain.join(', ')}');
      expect(plain, isEmpty);

      // (b) a fresh vault opens it
      final again = await EncryptedFileVault().load();
      record('b_reopens', again.lastNote == marker ? 'a fresh vault opens it with the marker' : 'NOT the marker');
      expect(again.lastNote, marker);

      // (c) the key in the platform store, read by a fresh key store; never printed
      final key = await PlatformKeyStore().read(keyName);
      final keyBytes = key == null ? null : base64Decode(key);
      record('c_key_in_platform_store', keyBytes?.length == 32
          ? 'present, 32 bytes, read back by a fresh key store' : 'MISSING or wrong size');
      expect(keyBytes?.length, 32);
      // (c2) Android (round 5 review, C-08): flutter_secure_storage holds the key only wrapped by the Keystore key that
      // works only while the phone is unlocked, on Android 9 and later with a screen lock; set
      // --dart-define=EXPECT_WRAPPED=true on such a device or emulator to make it a check, not only a record
      if (Platform.isAndroid) {
        final stored = await const FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false)).read(key: keyName);
        final wrapped = stored != null && stored.startsWith(UnlockKeyChannel.tag);
        record('c2_android_wrapped', wrapped ? 'kept only wrapped by the unlocked-only Keystore key'
            : 'kept plain (Android 8.1 or below, no screen lock, or the Keystore refused the key)');
        if (const bool.fromEnvironment('EXPECT_WRAPPED')) expect(wrapped, isTrue);
      }
      // the app's own folders: on a phone its support, documents and temporary folders are all private to it; on a
      // computer only the support folder is (documents and /tmp are shared with everything else)
      final mobile = Platform.isIOS || Platform.isAndroid;
      final dirs = {support, if (mobile) await getApplicationDocumentsDirectory(), if (mobile) await getTemporaryDirectory()};
      final where = <String>[];
      var scanned = 0;
      void scan(Directory d) {
        List<FileSystemEntity> items;
        try {
          items = d.listSync(followLinks: false);
        } catch (_) {
          return; // not readable: not the app's
        }
        for (final e in items) {
          if (e is Directory) {
            scan(e);
          } else if (e is File) {
            try {
              if (e.lengthSync() > 64 * 1024 * 1024) continue;
              final b = e.readAsBytesSync();
              scanned++;
              if (contains(b, keyBytes!) || contains(b, utf8.encode(key!))) where.add(e.path);
            } catch (_) {}
          }
        }
      }
      for (final d in dirs) {
        if (d.existsSync()) scan(d);
      }
      record('c_key_not_in_app_files', where.isEmpty
          ? 'in none of the $scanned files of the app\'s own folders (${mobile ? 'support, documents, temporary' : 'support'})'
          : 'FOUND IN ${where.join(', ')}');
      expect(where, isEmpty);

      // a second save makes the .bak (the last good copy)
      await vault.save(AppData(lastNote: '$marker-2'));
      expect(bak.existsSync(), isTrue);

      if (mode == 'seed') {
        record('seeded', 'data_v1.bin and .bak saved with the key in the platform store, left in place');
        done = true;
        return;
      }

      // (d) one flipped byte: the .bak opens; both flipped: a clear error and both files kept. Since round 4 review A-02
      // the .bak is written with every save as a copy of the newest one (it held the save before until then, which
      // kept deleted data readable), so the store opens from it with the newest save, nothing lost. That the flipped
      // file itself is refused is shown by the second half: with the .bak damaged too, nothing opens.
      final good = await file.readAsBytes(), goodBak = await bak.readAsBytes();
      record('d_bak_is_newest', listEquals(good, goodBak)
          ? 'the .bak is a copy of the newest save (A-02)' : 'the .bak differs from data_v1.bin');
      final bad = Uint8List.fromList(good)..[good.length ~/ 2] ^= 0x01;
      await file.writeAsBytes(bad, flush: true);
      final fallback = await EncryptedFileVault().load();
      record('d_tampered_file_uses_bak', fallback.lastNote == '$marker-2'
          ? 'one flipped byte: data_v1.bin refused, the .bak (the newest save) opened, nothing lost'
          : 'got "${fallback.lastNote == marker ? 'the save before' : 'something else'}"');
      expect(fallback.lastNote, '$marker-2');
      expect(await file.readAsBytes(), bad, reason: 'the flipped file is left as it was, never rewritten by a load');
      await bak.writeAsBytes(Uint8List.fromList(goodBak)..[goodBak.length ~/ 2] ^= 0x01, flush: true);
      try {
        await EncryptedFileVault().load();
        record('d_both_tampered', 'UNEXPECTED: opened');
        fail('tampered data opened');
      } on VaultError catch (e) {
        record('d_both_tampered', 'refused with VaultError(${e.kind}); both files still on disk: '
            '${file.existsSync() && bak.existsSync()}');
        expect(e.kind, 'unreadable');
      }
      expect(file.existsSync() && bak.existsSync(), isTrue);
      await file.writeAsBytes(good, flush: true);
      await bak.writeAsBytes(goodBak, flush: true);

      // (e) the key gone while data is there: key_missing, no new key over the data, nothing written
      await keys.delete(keyName);
      expect(await keys.read(keyName), isNull);
      final beforeMissing = await sha(file);
      try {
        await EncryptedFileVault().load();
        fail('data opened without its key');
      } on VaultError catch (e) {
        expect(e.kind, 'key_missing');
      }
      try {
        await EncryptedFileVault().save(AppData(lastNote: 'over the top'));
        fail('a save made a new key over existing data');
      } on VaultError catch (e) {
        expect(e.kind, 'key_missing');
      }
      final noNewKey = await keys.read(keyName) == null, same = await sha(file) == beforeMissing;
      record('e_key_missing', 'load and save refused with key_missing; no new key made: $noNewKey; '
          'data_v1.bin unchanged: $same');
      expect(noNewKey && same, isTrue);
      await keys.write(keyName, key!); // the key back: the data opens again
      expect((await EncryptedFileVault().load()).lastNote, '$marker-2');

      // the end: everything wiped
      await EncryptedFileVault().wipe();
      final gone = !file.existsSync() && !bak.existsSync() && await PlatformKeyStore().read(keyName) == null;
      record('wipe', gone ? 'data_v1.bin, .bak and the key are gone' : 'NOT all gone');
      expect(gone, isTrue);
      done = true;
    } catch (e) {
      failure = '$e'.split('\n').take(6).join(' | ');
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
