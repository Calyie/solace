// What every screen shares: the person's data, where it is kept, the prompts, the model and the practice library.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'core/dates.dart';
import 'core/emotions.dart' show stampOf;
import 'core/formats.dart';
import 'core/full_mode_key.dart';
import 'core/full_mode_lock.dart' show fullModeCount, fullModeRightKey, restoreFullModeCount;
import 'core/library.dart';
import 'core/app_files.dart';
import 'core/media.dart';
import 'core/passphrase_key_store.dart';
import 'core/llama_model.dart';
import 'core/load_guard.dart';
import 'core/model_import.dart' show FileImports;
import 'core/sherpa_voice.dart';
import 'core/home_link.dart' show homeLink;
import 'core/model.dart';
import 'core/nudge_scheduler.dart';
import 'core/questionnaires.dart';
import 'core/session.dart';
import 'core/storage.dart';
import 'core/store.dart';
import 'core/transfer.dart';
import 'core/voice.dart';

/// What Settings says while the classifier is turned off (owner, 2026-11-15: on by default, off only with the deep
/// work mode key).
const classifierOffStatus = 'Safety: the phrase checks read every message. The safety check (a trained model) is off.';

/// What Settings says while no trained model file is on this device (a new install, or after Delete everything).
const noModelStatus = 'No trained model file yet: the stand-in answers.';

/// What Settings says while the voice's files are not on this device.
const noVoiceStatus = 'Voice: not on this device yet. Sessions work by text.';

/// What Settings says while the classifier's files are not on this device (a new install, or after Delete everything).
const classifierMissingStatus =
    'Safety: the phrase rules check every message; the trained classifier is not on this device yet.';

class AppState extends ChangeNotifier {
  AppState({required this.data, required this.vault, required this.prompts, required this.model,
      required this.library, DateTime Function()? clock, FullModeKey? fullModeKey, this.nudges})
      : clock = clock ?? DateTime.now,
        builtInKey = fullModeKey ?? FullModeKey.fromEnvironment();

  AppData data;
  final Vault vault;
  /// Linux: the passphrase that protects the data key, so Settings can change it (round 4 review, A-09).
  PassphraseKeyStore? passphrase;
  Directory? passphraseDir;

  /// Run once Delete everything has finished (Linux: the old keyring copy of the data key, if its delete is still
  /// owed, is tried again at once rather than at the next start: round 6 review, E-04).
  Future<void> Function()? afterWipe;
  final Prompts prompts;
  ModelRuntime model;

  /// What the person sees in Settings about the model: checking, loading, ready, or why the stand-in is answering.
  String modelStatus = noModelStatus;

  /// Swaps in the trained model once its file is checked and loaded (main.dart); sessions started later use it.
  /// The SHA-256 of the trained model in use, when one is loaded (1.3.0: Settings and the chat say when it is a model
  /// the maker of Solace did not sign).
  String? modelSha;

  /// The models the maker did not sign that the person chose to use on this device (1.3.0).
  Set<String> get acceptedModels => data.settings.acceptedModels.keys.toSet();

  /// The person's choice behind the model in use, when it is one the maker did not sign; null otherwise.
  AcceptedModel? get modelAccepted => modelSha == null ? null : data.settings.acceptedModels[modelSha];

  /// Keeps the person's choice to use the model file [sha256] (its picked [name] and [size]) on this device, saved
  /// before the model is copied or used (1.3.0). False when it could not be saved: the model is then not used.
  Future<bool> acceptModel(String sha256, String name, int size) {
    final s = data.settings, before = Map.of(s.acceptedModels);
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
    return saveSetting(() {
      s.acceptedModels = AcceptedModel.allFrom({
        for (final e in before.entries) e.key: e.value.toJson(),
        sha256: AcceptedModel(name: name.length > 255 ? name.substring(0, 255) : name, size: size, date: date).toJson(),
      });
      notifyListeners();
    }, () => s.acceptedModels = before);
  }

  /// Forgets the choice to use the model [sha256] (Settings > Stop using it), saved; false when it could not be saved.
  Future<bool> forgetAcceptedModel(String sha256) {
    final s = data.settings, before = Map.of(s.acceptedModels);
    return saveSetting(() {
      s.acceptedModels = Map.of(before)..remove(sha256);
      notifyListeners();
    }, () => s.acceptedModels = before);
  }

  /// Lets go of the trained model in use (a reply being written is stopped first), so the stand-in answers until
  /// another model is loaded (1.3.0, Stop using it).
  Future<void> letGoOfModel() async {
    final m = model;
    model = const StandInModel();
    modelSha = null;
    modelStatus = noModelStatus;
    notifyListeners();
    try {
      if (m is ReplyCanceller) (m as ReplyCanceller).cancelReply();
      if (m is LlamaModelRuntime) await m.dispose();
      if (m is ReleasableRuntime) await (m as ReleasableRuntime).release();
    } catch (_) {}
  }

  void useModel(ModelRuntime m, String status) {
    model = m;
    modelStatus = status;
    notifyListeners();
  }

  void reportModel(String status) {
    modelStatus = status;
    notifyListeners();
  }

  /// Whether a trained model file is in Solace's private folder (true), is not (false: Today and the first-run steps
  /// offer to add it), or is not known yet (null: the start has not looked, so nothing is offered meanwhile).
  bool? modelInPlace;

  void reportModelInPlace(bool there) {
    if (modelInPlace == there) return;
    modelInPlace = there;
    notifyListeners();
  }

  /// The one import of model, voice or safety files that may run at a time, with its progress and its outcome (MM-01;
  /// core/model_import.dart FileImports). Settings, Today, the first-run steps and the iPhone's drop zone all use it.
  final imports = FileImports();

  /// Signed models (core/model_manifest.dart): why the model list kept on this device is not used at this start (it
  /// failed its check, so only the built-in models are trusted), or null. Settings shows it under the model's status.
  String? modelListNote;

  void reportModelList(String? note) {
    if (note == modelListNote) return;
    modelListNote = note;
    notifyListeners();
  }

  /// The markers written around each native load (core/load_guard.dart; main.dart sets it at start), or null in tests
  /// that load nothing.
  LoadGuard? loadGuard;

  /// Engines not loaded at this start because Solace stopped while loading them last time (round 9 review, 9B-04);
  /// Settings says why and offers to try again.
  final stoppedLoads = <Engine, StoppedLoad>{};

  /// Whether the Light model answers because the person chose it after the Standard one stopped Solace (Settings
  /// offers the Standard one again).
  bool lightChosen = false;

  void reportStoppedLoad(StoppedLoad stop) {
    stoppedLoads[stop.engine] = stop;
    notifyListeners();
  }

  void clearStoppedLoad(Engine e) {
    if (stoppedLoads.remove(e) != null) notifyListeners();
  }

  /// Engines whose native load has run far longer than it should (core/load_guard.dart loadWait; 9B-04): the ones
  /// after them went ahead. Settings says so, and for the classifier the chat and the call do.
  final slowLoads = <Engine>{};

  /// From the load guard: [e]'s native load is still running after the guard's wait ([slow]), or has now returned.
  void reportSlowLoad(Engine e, bool slow) {
    if (!slow) {
      if (slowLoads.remove(e)) notifyListeners(); // its own status follows, from where it was loaded
      return;
    }
    slowLoads.add(e);
    switch (e) {
      case Engine.classifier:
        safetyStatus = slowSafetyStatus;
      case Engine.model:
        modelStatus = slowModelStatus;
      case Engine.voice:
        voiceStatus = slowVoiceStatus;
    }
    notifyListeners();
  }

  final List<Practice> library;
  final DateTime Function() clock;
  /// The owner's key for deep work mode as built into the app (core/full_mode_key.dart).
  final FullModeKey builtInKey;

  /// The deep work key in force, the one place that decides it (owner, 2026-11-15): the PIN changed in Settings, kept
  /// as a salted fingerprint beside the store ([pinKeep]; an earlier version kept it in this device's settings), or
  /// else the built key. A build without a key never has one in force, whatever is kept, so such a build still cannot
  /// turn deep work mode on. While a kept PIN's file is there but cannot be read, no key is in force (deep work mode
  /// stays off and the safety check on), never the built one (round 9 review, 9A-01).
  FullModeKey get fullModeKey {
    if (!builtInKey.isSetUp) return builtInKey;
    if (keptPinUnreadable) return const FullModeKey(salt: '', fingerprint: '');
    return FullModeKey.fromSaved(_changedPin) ?? builtInKey;
  }

  /// Where a PIN changed on this device is kept, beyond Delete everything, Start fresh and an import (core/
  /// full_mode_key.dart PinKeep; round 9 review, 9A-01). Set at start (main.dart); none in most tests, where the
  /// changed PIN stays in the settings and, across Delete everything, in memory.
  PinKeep? pinKeep;

  /// The PIN changed on this device as [pinKeep] holds it (read at start, or written by Change deep work PIN), or null.
  Map<String, dynamic>? _keptPin;

  /// True while a kept PIN's file is there but could not be read (at start, or read back after a change): no deep
  /// work key is in force until it can be (Solace opened again), rather than the built one it replaced.
  bool keptPinUnreadable = false;

  /// The PIN changed on this device (a FullModeKey.saved record) wherever it is held now, or null for none.
  Map<String, dynamic>? get _changedPin {
    if (FullModeKey.fromSaved(_keptPin) != null) return _keptPin;
    final legacy = data.settings.fullModePin; // changed with an earlier version, or kept here without [pinKeep]
    return FullModeKey.fromSaved(legacy) != null ? legacy : null;
  }

  /// Keeps a changed PIN in [folder] (the store's own: main.dart boot) and reads it, before the first screen, so the
  /// built PIN is never in force meanwhile.
  Future<void> keepPinBeside(Future<Directory> Function() folder) async {
    pinKeep = PinKeep(folder);
    await loadKeptPin();
  }

  /// Reads [pinKeep] before the first screen (main.dart boot). A PIN changed with an earlier version, kept only in the
  /// encrypted settings, is copied into it; if that cannot be done now it is tried again at the next start and
  /// before Delete everything, and the settings still hold it meanwhile.
  Future<void> loadKeptPin() async {
    final keep = pinKeep;
    if (keep == null) return;
    try {
      _keptPin = await keep.read();
      keptPinUnreadable = false;
    } catch (_) {
      _keptPin = null;
      keptPinUnreadable = true;
      return;
    }
    await _keepLegacyPin(keep);
  }

  /// Copies a PIN kept only in the settings into [keep]; true when [keep] holds the PIN in force afterwards.
  Future<bool> _keepLegacyPin(PinKeep keep) async {
    if (_keptPin != null) return true;
    final legacy = _changedPin;
    if (legacy == null) return true; // nothing changed here: nothing to keep
    try {
      await keep.write(legacy);
      _keptPin = legacy;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Change deep work PIN (ui/settings.dart): [record] (FullModeKey.saved) is kept beside the store first, where
  /// Delete everything, Start fresh and an import leave it (round 9 review, 9A-01), and from then on it alone opens
  /// deep work mode and turns off the safety check; the wrong-key count starts again. False, with nothing changed,
  /// when it could not be kept. Without [pinKeep] (tests) it is kept in the encrypted settings, as before.
  Future<bool> changeFullModePin(Map<String, Object> record) async {
    final s = data.settings;
    final keep = pinKeep;
    if (keep == null) {
      final before = s.fullModePin, count = fullModeCount(s);
      return saveSetting(() {
        s.fullModePin = record;
        fullModeRightKey(s);
      }, () {
        s.fullModePin = before;
        restoreFullModeCount(s, count);
      });
    }
    try {
      await keep.write(record);
    } catch (_) {
      // the file on the device still holds the PIN in force before (it is replaced whole, or not at all), unless it
      // was replaced and then could not be read back: what is in force follows the file either way
      await loadKeptPin();
      return false;
    }
    _keptPin = record;
    keptPinUnreadable = false;
    s.fullModePin = null; // the kept file is the one place from now on (an earlier version's copy goes)
    fullModeRightKey(s);
    await trySave(); // the PIN is changed either way; a failed save shows the banner and loses only the count reset
    return true;
  }

  /// The voice once its files are checked and loaded (main.dart); the stub (text only) until then.
  VoiceService voice = const StubVoice();
  String voiceStatus = noVoiceStatus;

  void useVoice(VoiceService v, String status) {
    voice = v;
    voiceStatus = status;
    notifyListeners();
  }

  void reportVoice(String status) {
    voiceStatus = status;
    notifyListeners();
  }

  /// Safety layer 2 once its files are checked and loaded (main.dart); null until then.
  Future<bool> Function(String context, String text)? riskCheck;
  String safetyStatus = classifierMissingStatus;

  /// [close] lets the classifier go (its ONNX session and tokenizer isolate): Delete everything calls it (round 4
  /// review, B-16: it was only dropped, never closed).
  void useRiskCheck(Future<bool> Function(String context, String text) check, String status,
      {Future<void> Function()? close}) {
    riskCheck = check;
    _closeRiskCheck = close;
    safetyStatus = status;
    notifyListeners();
  }

  Future<void> Function()? _closeRiskCheck;

  /// The classifier turned off in Settings: it is let go (its ONNX session and tokenizer isolate) and reads nothing more;
  /// a session already open asks [riskCheck] at each message, so it stops at the next one.
  Future<void> stopRiskCheck() async {
    final close = _closeRiskCheck;
    riskCheck = null;
    _closeRiskCheck = null;
    safetyStatus = classifierOffStatus;
    notifyListeners();
    try {
      await close?.call();
    } catch (_) {}
  }

  void reportSafety(String status) {
    safetyStatus = status;
    notifyListeners();
  }

  /// A session asks for the classifier at each message, so one started before it finished loading (it loads in the
  /// background at start) still gets it from the next message on; until then only the phrase rules check.
  ///
  /// A safety question that comes after the session's screen has gone is carried onto the data held then (round 5
  /// review, D-11: a transfer brought in meanwhile replaced it), but never across Delete everything.
  SessionController newSession() {
    final wipes = _wipes;
    return SessionController(model: model, prompts: prompts, data: data, vault: vault,
        riskCheck: (context, text) async {
          final check = riskCheck;
          return check != null && await check(context, text);
        }, clock: clock, roomFull: () => spaceState(vault.savedBytes, pictureBytes) == SpaceState.full,
        openSessions: openSessions, currentData: () => _wipes == wipes ? data : null);
  }

  int _wipes = 0; // how many times everything has been deleted while the app ran (newSession)

  /// The data the app holds whenever the result is called, or null once everything has been deleted since this call,
  /// as a session's currentData (round 6 review, F6-04: a Help me start question that comes after its screen has gone).
  AppData? Function() dataUntilWiped() {
    final wipes = _wipes;
    return () => _wipes == wipes ? data : null;
  }

  /// The sessions open now, from their start until their screen has gone (core/session.dart OpenSessions): a transfer
  /// or Delete everything never replaces the data under one of them (review cycle 1, D4).
  final openSessions = OpenSessions();

  /// True while a transfer is brought in or everything is deleted: no session starts, and the desktop menus open
  /// nothing over the screen doing it (ui/desktop.dart).
  bool get changingData => openSessions.changing;

  /// Runs [work] with no session able to start meanwhile: a transfer from the moment its file is opened (ui/
  /// transfer_screen.dart), and Delete everything.
  Future<T> whileChangingData<T>(Future<T> Function() work) async {
    notifyListeners();
    try {
      return await openSessions.whileChanging(work);
    } finally {
      notifyListeners();
    }
  }

  /// Today's main session: the weekly session on the chosen day (or if none in the last week), else a check-in.
  String todaysKind() {
    if (data.sessions.isEmpty) return 'intake';
    final now = clock();
    final lastWeekly = data.sessions.where((s) => s.kind == 'weekly_session' || s.kind == 'intake')
        .map((s) => DateTime.parse(s.date)).fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final isWeeklyDay = dayLabel(now).startsWith(data.settings.weeklyDay);
    if (isWeeklyDay || lastWeekly == null || now.difference(lastWeekly).inDays >= 7) return 'weekly_session';
    return 'daily_checkin';
  }

  Future<void> saveMood(int mood) async {
    recordMood(mood);
    await save();
  }

  /// Today's mood in the data, unsaved: the caller saves.
  void recordMood(int mood) {
    data.moods[isoDate(clock())] = mood;
    data.moodTimes[isoDate(clock())] = stampOf(clock()).substring(11); // when, for time-of-day insights
  }

  /// PHQ-9's question about thoughts of being better off dead or of self-harm, above zero, is a crisis, and starts the
  /// 7-day watch as a session's crisis does (round 4 review, B-08). [crisisNoted]: the screen recorded that crisis
  /// already, when the item was answered (round 5 review, D-07), so it is not recorded twice.
  Future<void> saveScores(Questionnaire q, List<int> answers, {bool crisisNoted = false}) async {
    data.scores.add({'date': isoDate(clock()), 'name': q.name, 'total': answers.fold<int>(0, (a, b) => a + b),
        'items': answers});
    final item = q.alertItem;
    if (!crisisNoted && item != null && item < answers.length && answers[item] > 0) noteCrisis(alertReason(q));
    await save();
  }

  /// A crisis met outside a session (round 4 review, B-08 and B-18): the check-in's "Yes" or "I need help now", PHQ-9's
  /// last question above zero, a crisis in words written in a note. Recorded as a session's crisis is, and the next
  /// sessions in the coming 7 days open with the gentle check (core/session.dart _crisis); the reliving gate reads
  /// the record too. The caller saves.
  void noteCrisis(String reason) {
    final now = clock();
    data.safetyEvents.add({'date': isoDate(now), 'level': 'crisis', 'reason': reason});
    data.safetyWatch = {'since': now.toIso8601String(), 'reason': reason};
  }

  Future<void> saveWheel(Map<String, int> ratings) async {
    data.wheel.add({'date': isoDate(clock()), 'ratings': ratings});
    await save();
  }

  /// The device's reminders (core/nudge_scheduler.dart), rescheduled whenever something is saved; none in tests.
  final NudgeScheduler? nudges;

  /// Why the last save failed, shown at the top of every screen until a save works (main.dart); null when fine.
  String? saveProblem;

  /// Saves the data. A failure never throws here: it sets [saveProblem], which the banner at the top shows with Try
  /// again, and the next save that works writes everything still unsaved (F-05).
  Future<void> save() async {
    await trySave();
  }

  /// Like [save], and says whether the data reached the device (round 6 review, E-01: a delete, an import or a
  /// privacy switch was reported as done when its save had failed, so the old data came back at the next start). A
  /// failed save leaves the file on the device exactly as it was (core/store.dart: the checked temporary file
  /// replaces it in one rename, or nothing does).
  Future<bool> trySave() async {
    // picture files the person deleted or replaced while saves were failing; they go once a save that worked no
    // longer names them (taken before the save, so only names already gone from the data saved are deleted)
    final owed = _deleteAfterSave.toList();
    var saved = false;
    try {
      await vault.save(data);
      saveProblem = null;
      saved = true;
    } catch (e) {
      saveProblem = e is VaultError ? e.message : 'The device could not write the file (${e.runtimeType}).';
    }
    notifyListeners();
    unawaited(nudges?.reschedule(data, clock()));
    if (saved && owed.isNotEmpty) await _deleteOwedPictures(owed);
    return saved;
  }

  /// [trySave] for a person's own action that must not be reported as done unless it was saved: throws [NotSaved].
  Future<void> saveOrThrow() async {
    if (!await trySave()) throw const NotSaved();
  }

  /// A privacy switch (the app lock, Hide in the app switcher, Pause memory): [change] is made and saved, and undone
  /// with [undo] if the save failed, so the switch never shows what the device will not hold after the next start
  /// (round 6 review, E-01). Returns whether it was saved.
  Future<bool> saveSetting(void Function() change, void Function() undo) async {
    change();
    if (await trySave()) return true;
    undo();
    notifyListeners();
    return false;
  }

  /// Everything from another of the person's devices (core/transfer.dart): this device keeps its own deep work mode.
  /// Refused, with nothing changed, when the store would pass its ceiling (verification round 3, R3-6: every later
  /// save would be slow). The import starts a new generation of the data (R3-4), so a session still holding the old
  /// data (a reply still running in a screen the person left) can never write it over what came in.
  ///
  /// Refused too, with nothing changed, while a session is open (review cycle 1, D4): its saves would be of the old
  /// data, so the vault would drop them, the conversation at End included. The check is made right before the data
  /// is replaced, after the file has been opened (seconds), and no session can start while this runs.
  Future<void> receiveTransfer(AppData incoming) => whileChangingData(() => _receive(incoming));

  Future<void> _receive(AppData incoming) async {
    if (openSessions.count > 0) throw TransferError(sessionStillOpen);
    final next = importInto(data, incoming);
    final storeBytes = await storeBytesOf(next);
    if (storeBytes >= storeCeiling) {
      throw TransferError(TransferFile.tooMuch);
    }
    // pictures in the file become files of their own: they count against Solace's room like any picture (cycle 1
    // review: a crafted file could bring about 190 MB of "pictures" and leave the room full). The device's own free
    // space is not read (owner, 2026-11-19); a save that cannot be written says so, as every failed save does
    var newPictures = 0;
    var keepsOld = false;
    for (final v in next.photos.values) {
      isMediaRef(v) ? keepsOld = true : newPictures += v.length * 3 ~/ 4;
    }
    if (storeBytes + newPictures + (keepsOld ? pictureBytes : 0) >= solaceAllowance) {
      throw TransferError(TransferFile.tooMuch);
    }
    if (openSessions.count > 0) throw TransferError(sessionStillOpen); // right before the data is replaced (D4)
    vault.startGeneration(next);
    data = next;
    await keepPicturesApart(); // the file carries pictures inline; here they become separate encrypted files
    // round 6 review, E-01: the screen says whether the import reached the device, and pictures are tidied only after
    // a save that worked: after a failed one the data still on the device names this device's own pictures, which the
    // tidy (reading the import in memory) would have deleted. Strays left now are tidied at the next start.
    if (!await trySave()) throw const NotSaved();
    await tidyPictures();
  }

  // ---- pictures (core/storage.dart; owner 2026-11-14: data must never slow or crowd the device) ----
  /// Bytes of pictures kept beside the store; refreshed by [measurePictures].
  int pictureBytes = 0;
  final _pictureCache = <String, Uint8List>{}; // the last few decoded, so scrolling the board does not decrypt again

  /// The picture for [title]: from its encrypted file, or (data saved before 2026-11-14) inline.
  Future<Uint8List?> picture(String title) async {
    final v = data.photos[title];
    if (v == null) return null;
    if (!isMediaRef(v)) {
      try {
        return base64Decode(v);
      } catch (_) {
        return null;
      }
    }
    final cached = _pictureCache[v];
    if (cached != null) return cached;
    final bytes = await vault.getMedia(mediaId(v));
    if (bytes != null) {
      if (_pictureCache.length >= 12) _pictureCache.remove(_pictureCache.keys.first);
      _pictureCache[v] = bytes;
    }
    return bytes;
  }

  /// Keeps [png] as the picture for [title], replacing (and deleting) any earlier one. Throws [NotSaved] when the
  /// save failed: the new picture then shows in this run, and the earlier one's file is kept, as the data still on
  /// the device names it (round 6 review, E-01: it was deleted at once); it goes after the next save that works.
  ///
  /// The data, its safety records included, is saved first, while there is still room (H19-14: the device's space is
  /// never read, so a picture could take its last free space and leave the next safety record unsaved). A save that
  /// fails is said at the top as always, and the picture is still kept in this run as above.
  Future<void> setPicture(String title, Uint8List png) async {
    await trySave();
    final id = await vault.putMedia(png);
    final old = data.photos[title];
    data.photos[title] = '$mediaPrefix$id';
    final saved = await trySave();
    if (old != null && isMediaRef(old)) {
      _pictureCache.remove(old);
      saved ? await vault.deleteMedia(mediaId(old)) : _deleteAfterSave.add(mediaId(old));
    }
    await measurePictures();
    if (!saved) throw const NotSaved();
  }

  /// Removes the picture for [title]. Throws [NotSaved] when the save failed: its file is kept until a save that
  /// works no longer names it (round 6 review, E-01).
  Future<void> deletePicture(String title) async {
    final old = data.photos.remove(title);
    final saved = await trySave();
    if (old != null && isMediaRef(old)) {
      saved ? await vault.deleteMedia(mediaId(old)) : _deleteAfterSave.add(mediaId(old));
    }
    _pictureCache.remove(old);
    await measurePictures();
    if (!saved) throw const NotSaved();
  }

  final _deleteAfterSave = <String>{}; // picture ids removed while saves failed ([trySave])

  Future<void> _deleteOwedPictures(List<String> owed) async {
    final inUse = {for (final v in data.photos.values) if (isMediaRef(v)) mediaId(v)};
    for (final id in owed) {
      _deleteAfterSave.remove(id);
      if (inUse.contains(id)) continue; // named again meanwhile: kept
      try {
        await vault.deleteMedia(id);
      } catch (_) {} // left for the tidy at the next start
    }
    try {
      await measurePictures();
    } catch (_) {}
  }

  /// Pictures still kept inline in the store become separate encrypted files (data from before 2026-11-14, imports).
  Future<void> keepPicturesApart() async {
    var moved = false;
    for (final e in data.photos.entries.toList()) {
      if (isMediaRef(e.value)) continue;
      try {
        data.photos[e.key] = '$mediaPrefix${await vault.putMedia(base64Decode(e.value))}';
        moved = true;
      } catch (_) {
        // an unreadable picture stays as it was; it shows a plain tile
      }
    }
    if (moved) await save();
  }

  /// Deletes picture files nothing refers to any more (after an import or an interrupted change). Through the vault's
  /// queue, after any picture being written, and with the pictures in use read only once the folder is listed (round
  /// 5 review, C-10: a picture added at the same moment was deleted before the data named it).
  Future<void> tidyPictures() async {
    await vault.tidyMedia(() => {for (final v in data.photos.values) if (isMediaRef(v)) mediaId(v)});
    await measurePictures();
  }

  Future<void> measurePictures() async {
    pictureBytes = (await vault.mediaIndex()).$2;
    notifyListeners();
  }

  /// A copy of the data with every picture inline, for the transfer file (which carries everything in one file).
  Future<AppData> dataForTransfer() async {
    final copy = AppData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    for (final title in data.photos.keys) {
      final bytes = await picture(title);
      if (bytes == null) {
        copy.photos.remove(title);
      } else {
        copy.photos[title] = base64Encode(bytes);
      }
    }
    return copy;
  }

  /// Delete everything the app knows (F-19): the encrypted store and its key, the scheduled reminders, and every file
  /// Solace keeps (core/app_files.dart wipeAppFolders); the loaded model, voice and classifier are let go too, so the
  /// app starts again as on its first day. [folders] is replaced in tests.
  ///
  /// Throws [SessionStillOpen], with nothing deleted and nothing let go, while a session is open (review cycle 1, D4):
  /// its saves would be of the deleted data, so they would be dropped. It is checked first, before anything is let
  /// go; no session can start while this runs, so none can open before the data goes.
  Future<void> wipeEverything({Future<void> Function()? folders}) =>
      whileChangingData(() => _wipe(folders: folders));

  Future<void> _wipe({Future<void> Function()? folders}) async {
    // the one check for an open session, before anything is let go (cycle 2 review: a second check, after the engines
    // had been let go, would have left the app without its model and classifier had it ever refused). No session can
    // start while this runs (OpenSessions.changing), so the count can only fall from here.
    if (openSessions.count > 0) throw const SessionStillOpen();
    // Solace Home (HOME-05, owner 2026-11-19): the home server is told to forget this device when it can be reached
    // (a few seconds at most, so Delete everything never waits on a server that is off), and the pairing is forgotten
    // here either way with everything else; from then on nothing can be reached
    final paired = data.settings.homeServer, link = homeLink;
    if (paired != null && link != null) {
      try {
        await link.unpair(paired).timeout(const Duration(seconds: 5));
      } catch (_) {
        // not reached: the computer can remove it with solace-home unpair
      }
      link.allowOnly(null);
    }
    // round 9 review, 9A-01: a deep work PIN changed on this device outlives Delete everything, so the built PIN it
    // replaced never comes back (with a transfer file made before, it came back with every conversation). One changed
    // with an earlier version and still only in the settings is kept beside the store before anything goes; while it
    // cannot be kept it stays in force in the fresh settings, so the next save or start keeps it
    final pin = _changedPin, keep = pinKeep;
    var kept = keep != null && (keptPinUnreadable || await _keepLegacyPin(keep));
    // decrypted pictures are let go at once, so none can be served from memory after this (round 4 review, B-16)
    _pictureCache.clear();
    // the model and engines first (verification round 3, R3-4): a reply still being written, perhaps for a screen the
    // person has left, is stopped before the data goes. The vault also drops any save of the old data from then on.
    final m = model, v = voice, closeClassifier = _closeRiskCheck;
    model = const StandInModel();
    modelSha = null;
    modelStatus = noModelStatus;
    modelInPlace = false; // the model files go with everything else
    imports.result = null;
    modelListNote = null; // read again at the next load (the kept list and its number floor outlive Delete everything)
    stoppedLoads.clear(); // the load markers go with the support folder (9B-04)
    slowLoads.clear();
    lightChosen = false;
    voice = const StubVoice();
    voiceStatus = noVoiceStatus;
    riskCheck = null;
    _closeRiskCheck = null;
    // the switch is back on (its default) and the classifier's files are deleted, so it is not on this device
    safetyStatus = classifierMissingStatus;
    try {
      if (m is ReplyCanceller) (m as ReplyCanceller).cancelReply();
      if (m is LlamaModelRuntime) await m.dispose();
      if (m is ReleasableRuntime) await (m as ReleasableRuntime).release();
      if (v is SherpaVoice) await v.dispose();
    } catch (_) {}
    try {
      await closeClassifier?.call(); // its ONNX session and tokenizer isolate (B-16)
    } catch (_) {}
    await vault.wipe();
    _deleteAfterSave.clear(); // their folder went with everything else
    _wipes++;
    data = AppData();
    if (pin != null && !kept) data.settings.fullModePin = pin; // still in force (9A-01)
    // the pictures' size is measured again, now nothing, so the "room full" check never reads the deleted ones (B-16)
    _pictureCache.clear();
    pictureBytes = 0;
    try {
      await measurePictures();
    } catch (_) {}
    try {
      await nudges?.reschedule(AppData()..settings.remindersOn = false, clock()); // cancels every reminder
    } catch (_) {}
    try {
      await (folders ?? wipeAppFolders)();
      // any copy the file picker kept, and its Android record of a pick (round 6 review, E-03)
      if (folders == null) await clearPickerLeftovers();
    } catch (_) {}
    // the files gone, a PIN that could not be kept at first is tried once more (9A-01)
    if (!kept && keep != null && pin != null) {
      kept = await _keepLegacyPin(keep);
      if (kept) data.settings.fullModePin = null;
    }
    try {
      await afterWipe?.call();
    } catch (_) {}
    notifyListeners();
  }
}

/// A person's own change that could not be saved on the device (round 6 review, E-01): the screen says so instead of
/// reporting it done. [AppState.saveProblem] holds why, for the banner at the top.
class NotSaved implements Exception {
  const NotSaved();
  @override
  String toString() => 'NotSaved';
}


class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
