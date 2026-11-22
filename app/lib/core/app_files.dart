// Where the model, voice and safety files live (security review 2026-11-14, PLAT-1 and PLAT-2): the app's private
// support folder, not Documents. On the iPhone, Documents is open to the Files app and Finder (and was in backups);
// on Linux it is the shared ~/Documents. Application Support is private to the app everywhere (and excluded from
// iPhone backups, AppDelegate.swift). These files are the same for everyone, never the person's own words: those are
// in the encrypted store (core/store.dart).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'full_mode_key.dart' show PinKeep;
import 'model_manifest.dart' show keptListName, keptSignatureName, modelListName, serialFloorName, withdrawnName;

Future<Directory> appFiles() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/files').create(recursive: true);

/// "Delete everything" beyond the encrypted store (security review 2026-11-14, F-19): everything in the app's private
/// support folder (the model, voice and safety files, their check caches, the sound cache, spoken clips, any leftover
/// save copies), the bundle copy in the temporary folder, and on the iPhone the drop zone in Documents. Only Solace's
/// own files: on Linux the temporary folder is the shared /tmp, so nothing else there is touched. Files the person
/// saved outside Solace (exports, transfer files) are theirs to delete; the confirmation says so.
Future<void> wipeAppFolders({Directory? support, Directory? temp, Directory? inbox}) async {
  Future<void> quietly(FileSystemEntity e) async {
    try {
      await e.delete(recursive: true);
    } catch (_) {} // one file in use must not stop the rest
  }
  final s = support ?? await getApplicationSupportDirectory();
  if (await s.exists()) {
    await for (final e in s.list()) {
      // Linux: the passphrase set-up stays (its wrapped keys are deleted by the vault), so the app that is still
      // running and the next start keep the same passphrase; the lock file is this running copy's own
      final name = e.uri.pathSegments.where((x) => x.isNotEmpty).last;
      // and a deep work PIN changed here stays changed (round 9 review, 9A-01: the built PIN it replaced came back);
      // so do the highest signed model list number accepted, the newest accepted list and the built-in models it
      // withdrew, so neither an older list nor no list at all can bring back a withdrawn model after Delete everything
      // (core/model_manifest.dart, 9A-12; the withdrawals: audit 216)
      if (const {'keys', 'running.lock', PinKeep.fileName, serialFloorName, keptListName, keptSignatureName,
          withdrawnName}.contains(name)) {
        continue;
      }
      // Linux, round 9 review, 9A-03: a keyring delete owed from before "I have forgotten it" is recorded only in its
      // set-aside folder (keys.forgotten-<date>, G7-04). It is carried into keys/, which stays, before that folder
      // goes, so the retry after Delete everything (AppState.afterWipe, main.dart moveKeyringKey) still makes it, and
      // every start after it until it works; a folder whose marker could not be carried is kept, never dropped
      if (e is Directory && name.startsWith('keys.forgotten-') && !await _carryKeyringMarker(e, s)) continue;
      await quietly(e);
    }
  }
  // a bundle copy older phone builds made in their own temporary folder; on Linux that folder is the shared /tmp,
  // where Solace never wrote it, so a file of that name there is someone else's (round 4 review, A-15)
  final t = temp ?? (!kIsWeb && Platform.isLinux ? null : await getTemporaryDirectory());
  final bundle = t == null ? null : File('${t.path}/bundle.zip');
  if (bundle != null && await bundle.exists()) await quietly(bundle);
  final drop = inbox ?? (!kIsWeb && Platform.isIOS ? await getApplicationDocumentsDirectory() : null);
  if (drop != null && await drop.exists()) {
    await for (final e in drop.list()) {
      // a model, checksum list, signed model list or bundle copied in, and any the app refused and renamed
      // (core/model_import.dart; a refused model can be several gigabytes: verification round 3, R3-9)
      final dropped = e.uri.pathSegments.last;
      if (e is File && (_dropped.hasMatch(dropped) || _droppedList.hasMatch(dropped))) await quietly(e);
    }
  }
}

final _dropped = RegExp(r'\.(gguf|sha256|zip)(\.refused)?$');
final _droppedList = RegExp('^${RegExp.escape(modelListName)}(\\.sig)?(\\.refused)?\$');

/// Carries the keyring-delete marker of the set-aside folder [aside] into [support]'s keys/ (9A-03). True when the
/// folder holds none or it was carried, so the folder may go.
Future<bool> _carryKeyringMarker(Directory aside, Directory support) async {
  try {
    if (!await File('${aside.path}/$_keyringDeletePending').exists()) return true;
    final marker = File('${support.path}/keys/$_keyringDeletePending');
    await marker.create(recursive: true);
    return await marker.exists();
  } catch (_) {
    return false;
  }
}

/// The marker of a keyring delete still owed from an earlier Linux build (main.dart moveKeyringKey).
const _keyringDeletePending = 'keyring_delete_pending';

/// The file picker's own channel (file_picker 13.3.0: android_file_picker 2.1.6 and file_picker_darwin 2.5.1 both
/// answer on it), used here only for the Android lost-pick record, which the package's public API does not reach.
const pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

/// The file picker's plain copies and its record of them, cleared at every start and by Delete everything (round 6
/// review, E-03: when Android ended Solace while its full-screen picker was open, the picker copied the chosen file
/// into Solace's cache, `cache/file_picker/<id>/`, and recorded it in its own shared preferences,
/// `flutter_file_picker_lost_data.xml`, for a later "lost data" call Solace never makes; on the iPhone an export copy
/// in `tmp/flutter_file_picker/` stays if Solace is ended while the export sheet is open). Only the picker's own
/// paths inside Solace's sandbox: on Android the lost pick is read (which removes its record, and waits for a copy
/// still being made) and dropped unread, then the picker's folder is cleared by the plugin and, should the plugin not
/// be attached, from here; on the iPhone and the Mac the plugin's clear removes its own folder in the app's temporary
/// folder; on Linux the picker keeps no copies (and the temporary folder is the shared /tmp, never touched).
/// [os], [channel], [clear] and [cache] are replaced in tests.
Future<void> clearPickerLeftovers({String? os, MethodChannel channel = pickerChannel, Future<void> Function()? clear,
    Future<Directory> Function()? cache}) async {
  final system = os ?? (kIsWeb ? 'web' : Platform.operatingSystem);
  if (system == 'linux' || system == 'web') return;
  if (system == 'android') {
    try {
      await channel.invokeMethod<Object?>('retrieveLostData'); // what it returns is never read
    } catch (_) {} // no record, or no plugin
  }
  try {
    await (clear ?? FilePicker.clearTemporaryFiles)();
  } catch (_) {} // a platform with nothing to clear
  if (system == 'android') {
    try {
      final folder = Directory('${(await (cache ?? getTemporaryDirectory)()).path}/file_picker');
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {}
  }
}
