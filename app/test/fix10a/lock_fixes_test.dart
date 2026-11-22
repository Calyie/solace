// Round 10 review A fixes for the try limits (beyond the reviewer's proof tests in test/review10a/):
//   R10A-05: each wrong app passcode is noted on the device before its slow check, in the vault's own sealed record;
//            the real EncryptedFileVault keeps it in its own file, a copy of Solace ended once the check is over still
//            leaves the wait in force, a try that cannot be noted is not checked, and the right passcode clears it.
//   R10A-06: the deep work PIN's pause runs on the boot clock too, across a restart of Solace, and each PIN try is
//            counted and saved before its check.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_lock.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/settings.dart' show countPinTry;

import '../audit_followups_test.dart' as a;
import '../unlocked_only_key_test.dart' show MemKeys;

const _code = '482916';

/// The real store, whose save of the whole store can be made never to finish (Solace ended while it writes).
class EndedVault extends EncryptedFileVault {
  EndedVault(Directory dir, KeyStore keys, {this.ended = false}) : super(keychain: keys, folder: () async => dir);
  final bool ended;
  final saveStarted = Completer<void>();
  @override
  Future<void> save(AppData data) {
    if (!saveStarted.isCompleted) saveStarted.complete();
    return ended ? Completer<void>().future : super.save(data);
  }
}

/// A store whose record and saves can be made to fail, and which notes what each save held.
class FailingVault extends MemoryVault {
  bool recordFails = false, saveFails = false;
  final savedFails = <int>[];
  @override
  Future<void> keepLockTries(String record) async {
    if (recordFails) throw const FileSystemException('no space');
    await super.keepLockTries(record);
  }

  @override
  Future<void> save(AppData data) async {
    if (saveFails) throw const VaultError('full', 'This device is out of space.');
    savedFails.add(data.settings.lockFails);
    await super.save(data);
  }
}

void main() {
  late Map<String, String> passcode;
  final library = parseLibrary(File('assets/practices/library_v2.json').readAsStringSync());
  setUpAll(() async => passcode = await hashPasscode(_code));
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fix10a_lock'));
  tearDown(() => dir.deleteSync(recursive: true));

  AppData locked() => AppData()
    ..settings.therapistChosen = true
    ..settings.onboarded = true
    ..settings.ageConfirmed = true
    ..settings.appLock = true
    ..settings.passcode = passcode;

  AppState stateOf(Vault vault, AppData data) {
    forgetLockWaitForTest(); // a new copy of Solace
    return AppState(data: data, vault: vault, prompts: a.prompts, model: const StandInModel(), library: library);
  }

  group('R10A-05: the wrong-passcode record', () {
    test('the real store: five guesses each ended once their check is over still start the wait, and the right '
        'passcode then waits too', () async {
      final keys = MemKeys();
      await EncryptedFileVault(keychain: keys, folder: () async => dir).save(locked());
      for (var guess = 0; guess < 5; guess++) {
        final vault = EndedVault(dir, keys, ended: true);
        final state = stateOf(vault, await vault.load());
        unawaited(checkAppPasscode(state, '00000$guess'));
        await vault.saveStarted.future; // the check is over and the lock did not open: Solace is ended now
      }
      final file = File('${dir.path}/${EncryptedFileVault.lockTriesName}');
      expect(file.existsSync(), isTrue);
      final vault = EndedVault(dir, keys);
      final data = await vault.load();
      expect(data.settings.lockFails, 0, reason: 'the store itself never got a save: only the record holds them');
      final state = stateOf(vault, data);
      final r = await checkAppPasscode(state, _code);
      expect((r.ok, r.message?.startsWith('Too many tries')), (false, true));
      expect(state.data.settings.lockFails, 5);
    });

    test('the record file is sealed: no field, no salt, no count in plain bytes, and opens only as a record', () async {
      final keys = MemKeys();
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      await vault.save(locked());
      final s = (await vault.load()).settings..lockFails = 3;
      await vault.keepLockTries(lockTriesRecord(s));
      final bytes = File('${dir.path}/${EncryptedFileVault.lockTriesName}').readAsBytesSync();
      final text = latin1.decode(bytes);
      for (final plain in ['fails', 'until', '"v"', passcode['salt']!]) {
        expect(text.contains(plain), isFalse, reason: '"$plain" is in the record in plain bytes');
      }
      expect(await EncryptedFileVault(keychain: keys, folder: () async => dir).lockTries(), lockTriesRecord(s));
      // the store's own file put in its place is not read as a record (another purpose under the same key)
      File('${dir.path}/data_v1.bin').copySync('${dir.path}/${EncryptedFileVault.lockTriesName}');
      expect(await vault.lockTries(), isNull);
    });

    test('a record for another passcode, one with fewer misses, or one not written by Solace changes nothing', () {
      final s = Settings()
        ..passcode = passcode
        ..lockFails = 2;
      final other = Settings()
        ..passcode = {'salt': base64Encode(List.filled(16, 7)), 'hash': passcode['hash']!}
        ..lockFails = 9;
      expect(applyLockTries(s, lockTriesRecord(other)), isFalse);
      expect(applyLockTries(s, lockTriesRecord(Settings()..passcode = passcode..lockFails = 2)), isFalse);
      for (final bad in ['', '{', '[]', '{"v":1}', jsonEncode({'v': 1, 'for': passcode['salt'], 'fails': 'nine'}),
          jsonEncode({'v': 1, 'for': passcode['salt'], 'fails': 99999}), 'x' * 5000]) {
        expect(applyLockTries(s, bad), isFalse, reason: bad.length > 40 ? '${bad.substring(0, 40)}...' : bad);
      }
      expect(s.lockFails, 2);
      final more = Settings()
        ..passcode = passcode
        ..lockFails = 6
        ..lockUntil = '2026-11-16T12:00:00.000'
        ..lockBoot = 123;
      expect(applyLockTries(s, lockTriesRecord(more)), isTrue);
      expect((s.lockFails, s.lockUntil, s.lockBoot), (6, '2026-11-16T12:00:00.000', 123));
    });

    test('the record cannot be written: the store is saved before the check instead', () async {
      final vault = FailingVault()..recordFails = true;
      final state = stateOf(vault, locked());
      final r = await checkAppPasscode(state, '000000');
      expect(r.ok, isFalse);
      expect(vault.savedFails, [1, 1], reason: 'saved with the miss before the check, and again after it');
    });

    test('neither can be kept: nothing is checked and nothing counted, the right passcode included', () async {
      final vault = FailingVault()
        ..recordFails = true
        ..saveFails = true;
      final state = stateOf(vault, locked());
      final r = await checkAppPasscode(state, _code);
      expect((r.ok, r.message), (false, tryNotNoted));
      expect(state.data.settings.lockFails, 0);
      vault
        ..recordFails = false
        ..saveFails = false;
      expect((await checkAppPasscode(state, _code)).ok, isTrue, reason: 'once the device can note it');
    });

    test('the right passcode removes the record, and tells the misses it held', () async {
      final vault = MemoryVault();
      final state = stateOf(vault, locked());
      for (final guess in ['000001', '000002']) {
        expect((await checkAppPasscode(state, guess)).ok, isFalse);
      }
      expect(await vault.lockTries(), isNotNull);
      final r = await checkAppPasscode(state, _code);
      expect((r.ok, r.before), (true, 2));
      expect(await vault.lockTries(), isNull);
    });

    test('Delete everything and Start fresh remove the record file', () async {
      final keys = MemKeys();
      final file = File('${dir.path}/${EncryptedFileVault.lockTriesName}');
      for (final step in ['wipe', 'setAside']) {
        final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
        await vault.save(locked());
        await vault.keepLockTries(lockTriesRecord((await vault.load()).settings..lockFails = 1));
        expect(file.existsSync(), isTrue);
        step == 'wipe' ? await vault.wipe() : await vault.setAside();
        expect(file.existsSync(), isFalse, reason: step);
      }
    });
  });

  group('R10A-06: the deep work PIN pause', () {
    setUp(forgetFullModePauseForTest);
    final t = DateTime(2026, 11, 16, 14);
    const m = Duration(hours: 5); // the boot clock at t

    Settings paused() {
      final s = Settings();
      for (var i = 0; i < fullModeTries; i++) {
        fullModeWrongKey(s, t, mono: m);
      }
      return s;
    }

    test('saved and read back, then the clock set a day forward after 3 real seconds: still paused', () {
      final s = Settings.fromJson(jsonDecode(jsonEncode(paused().toJson())));
      expect(s.fullModeLockedBoot, m.inMicroseconds);
      forgetFullModePauseForTest(); // Solace opened again
      final left = fullModeLockLeft(s, t.add(const Duration(days: 1, seconds: 3)), mono: m + const Duration(seconds: 3));
      expect(left, const Duration(minutes: 15) - const Duration(seconds: 3));
    });

    test('the clock set back: the pause runs in full from then, never longer', () {
      final s = paused();
      forgetFullModePauseForTest();
      expect(fullModeLockLeft(s, t.subtract(const Duration(days: 30)), mono: m + const Duration(seconds: 1)),
          const Duration(minutes: 15));
    });

    test('the device restarted (the boot clock reads less): the pause starts again', () {
      final s = paused();
      forgetFullModePauseForTest();
      expect(fullModeLockLeft(s, t.add(const Duration(minutes: 10)), mono: const Duration(minutes: 1)),
          const Duration(minutes: 15));
    });

    test('over by both clocks: it ends, and is forgotten', () {
      final s = paused();
      expect(fullModeLockLeft(s, t.add(const Duration(minutes: 15)), mono: m + const Duration(minutes: 15)),
          Duration.zero);
      expect((s.fullModeLockedUntil, s.fullModeLockedBoot), (null, null));
      expect(s.fullModeFails, fullModeTries, reason: 'the next wrong key still doubles the pause');
    });

    test('a pause saved by an earlier version (no boot reading) runs on the boot clock from now on', () {
      final s = Settings()
        ..fullModeFails = fullModeTries
        ..fullModeLockedUntil = t.add(const Duration(minutes: 10)).toIso8601String();
      forgetFullModePauseForTest();
      expect(fullModeLockLeft(s, t, mono: m), const Duration(minutes: 10));
      forgetFullModePauseForTest();
      expect(fullModeLockLeft(s, t.add(const Duration(days: 1)), mono: m + const Duration(seconds: 5)),
          const Duration(minutes: 10) - const Duration(seconds: 5));
    });

    test('damaged saved values are bounded when read back', () {
      final s = Settings.fromJson({'full_mode_fails': 'x', 'full_mode_locked_until': 5,
          'full_mode_locked_boot': 1 << 62});
      expect((s.fullModeFails, s.fullModeLockedUntil, s.fullModeLockedBoot), (0, null, null));
      expect(Settings.fromJson({'full_mode_fails': 1 << 40}).fullModeFails, 1000);
    });

    test('an import keeps this device\'s pause and its boot reading', () {
      final here = AppData()..settings.fullModeLockedBoot = 42;
      final there = AppData()..settings.fullModeLockedBoot = 7;
      expect(importInto(here, there).settings.fullModeLockedBoot, 42);
    });

    test('a PIN try is counted and saved before its check; one that cannot be saved counts nothing', () async {
      final vault = FailingVault();
      final state = stateOf(vault, AppData());
      final untried = await countPinTry(state, t);
      expect(untried?.fails, 0);
      expect(state.data.settings.fullModeFails, 1);
      expect((await vault.load()).settings.fullModeFails, 1, reason: 'on the device before the check');
      vault.saveFails = true;
      expect(await countPinTry(state, t), isNull);
      expect(state.data.settings.fullModeFails, 1, reason: 'not counted: the PIN is not checked');
    });
  });
}
