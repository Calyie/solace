// Review round 10 A, R10A-05 (G7-06 "killing the app"; the try limit of F-09/C-04/9B-13): a wrong passcode is saved
// only after the Argon2 check and a full save of the store, so ending Solace in that window throws the miss away and
// the wait after five never starts.
//
// checkAppPasscode (ui/app_lock.dart:105-141) counts the try in memory (recordLockFail) before the check, runs the
// Argon2id check (19 MiB, 2 passes), and only then, for a wrong passcode, awaits state.save(), a full encrypted save of
// the store ("seconds on a phone", 9B-13). The right passcode opens the lock the moment the check ends (the save is
// not awaited). So whoever is guessing knows a guess was wrong as soon as the lock has not opened when the check
// should have finished, while the miss is still only in memory: swiping Solace away then (or killing it on a computer)
// loses it. Opened again, the store says no try was missed, and the guessing goes on with no wait at all: about one
// guess per restart instead of one an hour once the wait has doubled to its cap. The saved wait itself is sound
// (review10a/g7_06_wait_never_shortened_test.dart); it is the count that never reaches the disk.
//
// "Disk" below is what the store holds between copies of Solace; a save cut short by the kill never changes it (the
// real store writes a temporary file and renames it last). The test asserts the SAFE behaviour (ten wrong guesses,
// each followed by a kill, still leave a wait in force), so it fails on 2f3ce71.
//
// Fix round (R10A-05): the fix notes each counted miss in the vault's own small record (Vault.keepLockTries), written
// and flushed before the Argon2 check begins. So "Disk" now holds that record as well as the store, as the device does
// (EncryptedFileVault writes it to its own file beside the store; test/fix10a covers that file), and OneCopyVault
// keeps it there. The kill is modelled at the same moment as before (the check is over and the store's save is
// writing; that save still never finishes). Two consequences changed the loop: once five misses are noted the next
// guess is refused at once, with no check and so no save, so each guess now waits for whichever comes first, its
// answer or its save; and the end checks the wait through the app's own path, checkAppPasscode, with the RIGHT
// passcode, which must be refused while the wait runs (the record is counted there, before the wait is read).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/app_lock.dart';

import '../audit_followups_test.dart' as a;

const _code = '482916';

/// What the store holds on the device between copies of Solace.
class Disk {
  String? json;
  String? tries; // the vault's wrong-passcode record (R10A-05), on the device beside the store
}

/// The store of one copy of Solace. With [killed], that copy is ended while its save writes: the save never finishes
/// and the disk keeps what it had.
class OneCopyVault extends MemoryVault {
  OneCopyVault(this.disk, {required this.killed});
  final Disk disk;
  final bool killed;
  final saveStarted = Completer<void>();

  @override
  Future<AppData> load() async => disk.json == null ? AppData() : AppData.fromJson(jsonDecode(disk.json!));

  @override
  Future<void> save(AppData data) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    if (killed) return Completer<void>().future;
    disk.json = jsonEncode(data.toJson());
  }

  // the record is on the disk once this returns (the real vault flushes it and renames it into place), which is before
  // the check begins, so before the kill
  @override
  Future<void> keepLockTries(String record) async => disk.tries = record;
  @override
  Future<String?> lockTries() async => disk.tries;
  @override
  Future<void> forgetLockTries() async => disk.tries = null;
}

void main() {
  late Map<String, String> passcode;
  final library = parseLibrary(File('assets/practices/library_v2.json').readAsStringSync());
  setUpAll(() async => passcode = await hashPasscode(_code));

  Future<Disk> lockedDevice() async {
    final data = AppData();
    data.settings
      ..therapistChosen = true
      ..onboarded = true
      ..ageConfirmed = true
      ..appLock = true
      ..passcode = passcode;
    return Disk()..json = jsonEncode(data.toJson());
  }

  /// A fresh copy of Solace opened from [disk].
  Future<AppState> open(OneCopyVault vault) async {
    forgetLockWaitForTest(); // a new process
    return AppState(data: await vault.load(), vault: vault, prompts: a.prompts, model: const StandInModel(),
        library: library);
  }

  test('R10A-05: a wrong passcode still counts when Solace is ended before its save finishes', () async {
    final disk = await lockedDevice();
    int? refusedFrom;
    for (var guess = 0; guess < 10; guess++) {
      final vault = OneCopyVault(disk, killed: true);
      final state = await open(vault);
      expect(lockIsOn(state.data.settings), isTrue, reason: 'precondition: the lock is on');
      final check = checkAppPasscode(state, '00000$guess');
      // the guess is answered at once (refused: the wait runs), or its check ends and the save starts
      final answered = await Future.any<PasscodeCheck?>([check, vault.saveStarted.future.then((_) => null)]);
      if (answered != null) {
        expect(answered.ok, isFalse);
        expect(answered.message, startsWith('Too many tries'), reason: 'refused before any check');
        refusedFrom ??= guess;
        continue;
      }
      // the Argon2 check is over: the lock did not open, so the guess was wrong ... and Solace is swiped away now,
      // while that save writes
    }
    expect(refusedFrom, 5, reason: 'ten wrong guesses, each followed by a kill, and the wait never began');
    final state = await open(OneCopyVault(disk, killed: false));
    final r = await checkAppPasscode(state, _code);
    expect((r.ok, r.message?.startsWith('Too many tries')), (false, true),
        reason: 'the store says ${state.data.settings.lockFails} were missed: no wait, guessing goes on');
    expect(state.data.settings.lockFails, 5);
    final at = lockNow();
    expect(lockWait(state.data.settings, at.wall, mono: at.mono), isNotNull);
  });

  test('control: the same ten wrong guesses, each allowed to finish its save, start the wait', () async {
    final disk = await lockedDevice();
    for (var guess = 0; guess < 10; guess++) {
      final state = await open(OneCopyVault(disk, killed: false));
      final r = await checkAppPasscode(state, '00000$guess');
      expect(r.ok, isFalse);
      if (r.message!.startsWith('Too many')) break;
    }
    final state = await open(OneCopyVault(disk, killed: false));
    final at = lockNow();
    expect(state.data.settings.lockFails, greaterThanOrEqualTo(5));
    expect(lockWait(state.data.settings, at.wall, mono: at.mono), isNotNull);
  });
}
