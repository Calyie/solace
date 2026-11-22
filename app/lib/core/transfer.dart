// Moving everything the app knows to another of the owner's devices (PLAN section 11: memory across devices only by
// an encrypted file moved by AirDrop, USB or Bluetooth; no network). The file is locked with a one-time code the app
// shows on screen (16 characters, 80 bits, typed on the other device), stretched with Argon2id and sealed with
// AES-256-GCM. The header (format, key-stretching settings, salt, nonce) is authenticated too, so changing any byte
// of the file makes it refuse to open rather than open wrongly.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'photos.dart';
import 'store.dart';

/// What the other device's data becomes on this one. Deep work mode is switched on separately on each device, with
/// the same key (owner, 2026-11-05: "Each device keeps its own deep work mode, so a transfer from another device can
/// never switch it on or off"), so an import keeps this device's mode, its start date and its wrong-key counts. Its
/// lock, its window, its memory pause and its reminders switch stay this device's own too.
AppData importInto(AppData current, AppData incoming) {
  final c = current.settings;
  incoming.settings
    ..country = c.country // this device's country, for its crisis numbers (F-07); changed in Settings if wanted
    ..mode = c.mode
    ..fullModeSince = c.fullModeSince
    ..fullModeFails = c.fullModeFails
    ..fullModeLockedUntil = c.fullModeLockedUntil
    ..fullModeLockedBoot = c.fullModeLockedBoot // measured on this device's boot clock (R10A-06)
    ..fullModePin = c.fullModePin // and the deep work key changed on it (owner, 2026-11-15)
    // the models not signed by Solace's maker that were accepted here: a file from another device never approves one
    ..acceptedModels = c.acceptedModels
    // and the home server this device paired with (Solace Home): its token is this device's alone
    ..homeServer = c.homeServer
    // the window's place and the menu-bar icon belong to this computer, not the one the data came from
    ..trayOn = c.trayOn
    ..windowLeft = c.windowLeft
    ..windowTop = c.windowTop
    ..windowWidth = c.windowWidth
    ..windowHeight = c.windowHeight
    // how this device is locked and what it shows stays this device's own
    ..appLock = c.appLock
    ..lockAfterMinutes = c.lockAfterMinutes
    ..hideInSwitcher = c.hideInSwitcher
    ..passcode = c.passcode
    ..lockFails = c.lockFails
    ..lockUntil = c.lockUntil
    ..lockBoot = c.lockBoot // the boot clock it was measured on is this device's (audit 216, G7-06)
    ..lockNeedsPasscode = c.lockNeedsPasscode
    ..lockNoticeClosed = c.lockNoticeClosed // the Today notice closed here (round 9 final, 9A-09)
    // and so do this device's privacy switches (round 5 review, C-09): memory paused here stays paused, and reminders
    // turned off here stay off, whatever the other device had
    ..memoryPaused = c.memoryPaused
    ..remindersOn = c.remindersOn
    // and whether the safety check runs here (on by default, off only with the deep work key: owner, 2026-11-15)
    ..classifierOn = c.classifierOn;
  // this device's safety history is kept and joined with the other device's, never replaced: replacing it would
  // erase a recent crisis and reopen the reliving gate (security review 2026-11-14, F-07)
  final seen = {for (final e in incoming.safetyEvents) '${e['date']}|${e['level']}|${e['reason']}'};
  incoming.safetyEvents.insertAll(0, [for (final e in current.safetyEvents)
    if (!seen.contains('${e['date']}|${e['level']}|${e['reason']}')) e]);
  final keep = current.safetyWatch, other = incoming.safetyWatch;
  if (keep != null && (other == null || '${keep['since']}'.compareTo('${other['since']}') > 0)) incoming.safetyWatch = keep;
  // a safety plan is never lost in a move: the newer one is kept, and this device's if the other has none
  final mine = current.safetyPlan, theirs = incoming.safetyPlan;
  if (!mine.isEmpty && (theirs.isEmpty || (mine.updated ?? '').compareTo(theirs.updated ?? '') > 0)) {
    incoming.safetyPlan = mine;
  }
  return incoming;
}

class TransferError implements Exception {
  TransferError(this.message);
  final String message; // shown to the person as it is
  @override
  String toString() => message;
}

/// The one-time code: Crockford base32, so 0/O and 1/I/L can never be confused when it is typed.
class TransferCode {
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const length = 16;

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return String.fromCharCodes(List.generate(length, (_) => alphabet.codeUnitAt(r.nextInt(32))));
  }

  /// "4K7Q-9XDM-2HTR-P8WL": groups of four, for reading out and typing.
  static String show(String code) =>
      [for (var i = 0; i < code.length; i += 4) code.substring(i, min(i + 4, code.length))].join('-');

  /// What the person typed, as the code: case, spaces and dashes do not matter; O reads as 0, I and L as 1.
  static String normalise(String typed) {
    final s = typed.toUpperCase().replaceAll(RegExp(r'[\s-]'), '').replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
    if (s.length != length || s.split('').any((c) => !alphabet.contains(c))) {
      throw TransferError('That code does not look right. It has 16 letters and numbers, as shown on the other device.');
    }
    return s;
  }
}

class TransferFile {
  static const magic = [0x4D, 0x54, 0x58, 0x46]; // "MTXF"
  static const version = 1;
  static const _kdfArgon2id = 1;
  // OWASP's minimum for Argon2id (19 MiB, 2 passes): ample with an 80-bit random code, and quick on an older phone.
  static const memoryKib = 19456, iterations = 2, parallelism = 1;
  // Limits on what a received file may ask for, so a damaged or hostile file cannot make the device stall.
  static const _maxMemoryKib = 262144, _maxIterations = 10, _maxParallelism = 4;
  static const _headerLength = 4 + 1 + 1 + 4 + 1 + 1 + 16 + 12;
  // Size limits (security review 2026-11-14, F-07 and F-14): a real transfer file is a few megabytes; a bigger one is
  // the wrong file or a hostile one, and decompression stops at a ceiling so a "zip bomb" cannot exhaust memory.
  static const maxFileBytes = 128 * 1024 * 1024, maxOpenedBytes = 192 * 1024 * 1024;
  static const format = 'solace_transfer', _oldFormat = 'my_therapist_transfer';
  // What one file may bring (verification round 3, R3-6): a 189 KB file had opened to a 54 MB store, after which
  // every save took 13 to 15 seconds of the processor, and 1.8 million small values froze the screen for 590 ms at
  // each save. A year of daily sessions is about 6 MB and 50,000 values, far below either limit. Pictures are not
  // counted in the text: they are kept apart from the store.
  // 16 MB of text outside pictures (a year of daily sessions is about 6 MB): near 48 MB every later save cost about 11 s
  // of background work (pure-Dart AES-GCM and the read-back check), against the owner's rule never to slow the device
  static const maxValues = 300000, maxTextBytes = 16 * 1024 * 1024;
  static const tooMuch = 'There is more in this file than Solace can keep on one device, so nothing was changed. On '
      'the other device, delete some older conversations (Settings > Space Solace uses), then make a new file.';

  /// [open] on a worker isolate, so a large or hostile file never freezes the screen (OW-M4-4). The bytes are copied
  /// once here; the screen uses [openPicked], which never copies them on its isolate.
  static Future<AppData> openInBackground(Uint8List bytes, String typedCode) =>
      openPicked(PickedTransfer.fromBytes(bytes), typedCode);

  /// [open] on a worker isolate, for a file read by [PickedTransfer.read]: its bytes move to the worker without being
  /// copied on the calling isolate (R3-6: copying a 128 MB file into the worker stalled the screen for 0.37 to
  /// 0.40 s), and come back the same way, so a wrong code can be tried again.
  static Future<AppData> openPicked(PickedTransfer file, String typedCode) async {
    final handle = file._take();
    final (AppData? data, TransferableTypedData back, String? refused, bool failed) = await Isolate.run(() async {
      final bytes = handle.materialize().asUint8List();
      try {
        final data = await open(bytes, typedCode);
        return (data, TransferableTypedData.fromList([bytes]), null, false);
      } on TransferError catch (e) {
        return (null, TransferableTypedData.fromList([bytes]), e.message, false);
      } catch (_) {
        return (null, TransferableTypedData.fromList([bytes]), null, true);
      }
    });
    file._bytes = back;
    if (refused != null) throw TransferError(refused);
    if (failed) throw StateError('The transfer file could not be opened.');
    return data!;
  }

  /// [seal] on a worker isolate; refuses (with a plain message) data too large for one transfer file.
  static Future<Uint8List> sealInBackground(AppData data, String code) async {
    final json = data.toJson();
    final sealed = await Isolate.run(() => seal(AppData.fromJson(json), code));
    if (sealed.length > maxFileBytes) {
      throw TransferError('There is too much to fit in one transfer file. Delete some older conversations or pictures '
          '(Settings > Space Solace uses), then try again.');
    }
    return sealed;
  }

  static final _aead = AesGcm.with256bits();

  static Future<SecretKey> _key(String code, List<int> salt, int memory, int passes, int lanes) =>
      Argon2id(parallelism: lanes, memory: memory, iterations: passes, hashLength: 32)
          .deriveKey(secretKey: SecretKey(utf8.encode(code)), nonce: salt);

  /// The sealed file for [data]. [code] comes from [TransferCode.generate] and is shown to the person.
  /// [checkFirst] is false only in tests, to make the damaged files open() must refuse.
  static Future<Uint8List> seal(AppData data, String code, {Random? random, bool checkFirst = true}) async {
    final problem = checkFirst ? sealProblem(data) : null; // OW-A10-1: never a file that open() would refuse
    if (problem != null) throw TransferError(problem);
    final r = random ?? Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final nonce = List<int>.generate(12, (_) => r.nextInt(256));
    final header = BytesBuilder()
      ..add(magic)
      ..addByte(version)
      ..addByte(_kdfArgon2id)
      ..add((ByteData(4)..setUint32(0, memoryKib)).buffer.asUint8List())
      ..addByte(iterations)
      ..addByte(parallelism)
      ..add(salt)
      ..add(nonce);
    final head = header.toBytes();
    final opened = utf8.encode(jsonEncode({
      'format': format,
      'version': version,
      'created': DateTime.now().toUtc().toIso8601String(),
      'app_data': _withoutDeviceSettings(data.toJson()),
    }));
    final payload = gzip.encode(opened);
    // open() refuses a file that opens to more than a real one of its size can (9B-06), so none is made (OW-A10-1)
    if (checkFirst && opened.length > openedLimit(payload.length)) {
      throw TransferError('This device\'s data cannot go into a transfer file as it is: its pictures pack far smaller '
          'than photos do. Remove some from the vision board, then try again.');
    }
    final key = await _key(TransferCode.normalise(code), salt, memoryKib, iterations, parallelism);
    final box = await _aead.encrypt(payload, secretKey: key, nonce: nonce, aad: head);
    return Uint8List.fromList([...head, ...box.cipherText, ...box.mac.bytes]);
  }

  /// What belongs to this device stays on it (round 4 review, A-10): the receiving device keeps its own (importInto),
  /// and the app passcode's salted hash in the file would let whoever holds the file and its code try the million
  /// six-digit codes offline.
  static Map<String, dynamic> _withoutDeviceSettings(Map<String, dynamic> app) {
    final settings = Map<String, dynamic>.from(app['settings'] as Map);
    settings
      ..['passcode'] = null
      ..['lock_fails'] = 0
      ..['lock_until'] = null
      ..['lock_boot'] = null
      ..['full_mode_fails'] = 0
      ..['full_mode_locked_until'] = null
      ..['full_mode_pin'] = null // the deep work key changed here, a salted fingerprint (owner, 2026-11-15)
      ..['accepted_models'] = null // the models accepted on this device stay on it (1.3.0)
      ..['home_server'] = null // Solace Home: the pairing and its token stay on this device
      ..['window_left'] = null
      ..['window_top'] = null;
    return {...app, 'settings': settings};
  }

  // ---- OWASP review 2026-11-14, OW-A10-1: seal() runs the checks open() runs ----
  /// Why this device's own [data] would be refused by [open] on the other device, in plain words, or null. A device
  /// never makes a transfer file it would itself refuse ("start 12/10" stored as a mood made every file "damaged"):
  /// the same shape and content checks run first, and the person is told what to change instead of getting a file.
  static String? sealProblem(AppData data) {
    const start = 'This device\'s data cannot go into a transfer file as it is: ';
    final text = jsonEncode(data.toJson());
    var values = 0;
    final raw = jsonDecode(text, reviver: (k, v) { // exactly what open() will read
      values++;
      return v;
    }) as Map<String, dynamic>;
    // open() also counts the file's own few fields and bytes, so a margin keeps every file this makes inside them
    if (values > maxValues - 64 || utf8.encode(text).length - pictureChars(raw) > maxTextBytes - 4096) {
      return '${start}there is more in it than another device can take in one file. Delete some older conversations '
          '(Settings > Space Solace uses), then try again.';
    }
    for (final e in raw.entries) {
      final p = shapeProblem(e.value, 1, e.key);
      if (p != null) {
        final what = _sealNames[e.key] ?? 'part of it';
        return p == 'text too long'
            ? '$start$what holds a text longer than $maxString characters. Shorten it, then make the file again.'
            : '$start$what is larger than a transfer file can carry. Remove some of it, then make the file again.';
      }
    }
    final String? content;
    try {
      content = contentProblem(AppData.fromJson(raw));
    } catch (_) {
      return '${start}some of it could not be read back. Nothing was made.';
    }
    if (content == null) return null;
    return switch (content) {
      'mood' => '${start}a mood rating is outside 0 to 10.',
      'photos' => '${start}there are more than 100 pictures. Remove some from the vision board, then try again.',
      'photo' => '${start}a picture is not a PNG or JPEG image. Remove it from the vision board, then try again.',
      'session length' => '${start}a session has more than 2,000 messages.',
      _ => '${start}a date in it (${content.replaceAll('_', ' ')}) cannot be read.',
    };
  }

  static const _sealNames = {
    'journal': 'your journal', 'sessions': 'your sessions', 'story': 'what Solace remembers', 'plans': 'your plans',
    'photos': 'your pictures', 'scores': 'your questionnaire answers', 'safety_events': 'the safety record',
    'emotions': 'your named feelings', 'programmes': 'your programmes', 'last_note': 'the last session note',
  };
  // ---- end of the seal() checks ----

  /// Opens a received file with the code typed by the person. Throws [TransferError] with a plain message.
  static Future<AppData> open(List<int> bytes, String typedCode) async {
    if (bytes.length > maxFileBytes) {
      throw TransferError('This file is too large to be a Solace transfer file, so nothing was changed.');
    }
    if (bytes.length < _headerLength + 16 || !_startsWith(bytes, magic)) {
      throw TransferError('This is not a Solace transfer file.');
    }
    // views, not copies, of a file that may be 128 MB (R3-6: each copy is memory that a hostile file chooses)
    final file = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final b = ByteData.sublistView(file);
    if (bytes[4] > version) {
      throw TransferError('This file was made by a newer version of the app. Update the app on this device first.');
    }
    final memory = b.getUint32(6), passes = bytes[10], lanes = bytes[11];
    // only the key-stretching settings this version writes (OW-M4-4: a hostile file could otherwise ask for a long,
    // memory-hungry stretch before the code is even checked)
    if (bytes[5] != _kdfArgon2id || memory != memoryKib || passes != iterations || lanes != parallelism ||
        memory > _maxMemoryKib || passes > _maxIterations || lanes > _maxParallelism) {
      throw TransferError('This transfer file is damaged.');
    }
    final head = file.sublist(0, _headerLength);
    final salt = file.sublist(12, 28), nonce = file.sublist(28, 40);
    final box = SecretBox(Uint8List.sublistView(file, _headerLength, file.length - 16), nonce: nonce,
        mac: Mac(file.sublist(file.length - 16)));
    List<int> clear;
    try {
      clear = await _aead.decrypt(box, secretKey: await _key(TransferCode.normalise(typedCode), salt, memory, passes, lanes),
          aad: head);
    } on SecretBoxAuthenticationError {
      throw TransferError('The code does not open this file. Check the code on the other device, or make a new file.');
    }
    final Object? json;
    final int openedBytes;
    try {
      // a count of values as they are read: a small file of millions of tiny values is refused before it fills
      // the memory (OW-M4-4), and one of more values than a store should hold is refused kindly (R3-6)
      var values = 0;
      // opened in pieces, and never past what a real file of this size can open to (round 9 review, 9B-06: a 180 KB
      // file of 45 "pictures" of one repeated letter opened to 189 MB and grew the process by about 550 MB before
      // anything refused it)
      final limit = openedLimit(clear.length);
      var pieces = gunzipPieces(clear, limit, refusal: limit < maxOpenedBytes ? tooMuch : null);
      clear = const <int>[]; // the decrypted gzip is no longer needed
      openedBytes = pieces.fold(0, (n, p) => n + p.length);
      // the nesting, the number of values and the bytes inside strings are counted before anything is built (round 4
      // review, A-01: the reviver below runs only once a value is finished, so a 7 KB file of millions of '[' had the
      // decoder build a list for each of them first; 9B-06: the text and the pictures are measured here too)
      final scan = JsonScan(maxDepth: maxDepth + 2, maxValues: maxValues, checkStrings: true);
      for (final p in pieces) {
        if (scan.add(p) != JsonOutline.fine) break;
      }
      switch (scan.result) {
        case JsonOutline.tooDeep || JsonOutline.stringTooLong || JsonOutline.tooManyPictures:
          throw TransferError(damaged);
        case JsonOutline.tooMany:
          throw TransferError(tooMuch);
        case JsonOutline.fine:
          break;
      }
      if (openedBytes - scan.pictureBytes > maxTextBytes) throw TransferError(tooMuch);
      // read straight from the UTF-8 bytes (no second copy of everything as one string), each piece let go once read
      Object? decoded;
      final reader = const Utf8Decoder().fuse(JsonDecoder((k, v) {
        if (++values > maxValues) throw TransferError(tooMuch);
        return v;
      })).startChunkedConversion(ChunkedConversionSink<Object?>.withCallback((r) => decoded = r.single));
      final read = Uint8List(0);
      for (var i = 0; i < pieces.length; i++) {
        final p = pieces[i];
        pieces[i] = read;
        reader.add(p);
      }
      pieces = const [];
      reader.close();
      json = decoded;
    } on TransferError {
      rethrow;
    } catch (_) {
      throw TransferError(damaged);
    }
    if (json is! Map || (json['format'] != format && json['format'] != _oldFormat) || json['app_data'] is! Map) {
      throw TransferError(damaged);
    }
    final raw = Map<String, dynamic>.from(json['app_data'] as Map);
    final shape = shapeProblem(raw);
    if (shape != null) throw TransferError(damaged);
    // the text that would go into the store: everything but the pictures (R3-6)
    if (openedBytes - pictureChars(raw) > maxTextBytes) throw TransferError(tooMuch);
    final AppData data;
    try {
      data = AppData.fromJson(raw);
    } catch (_) {
      throw TransferError(damaged);
    }
    if (contentProblem(data) != null) throw TransferError(damaged);
    return data;
  }

  static const damaged = 'This transfer file is damaged or was not made by Solace, so nothing was changed.';

  /// The characters of the pictures carried inline in [appData] (base64, one byte each in the file).
  static int pictureChars(Map<String, dynamic> appData) {
    final photos = appData['photos'];
    var n = 0;
    if (photos is Map) {
      for (final v in photos.values) {
        if (v is String) n += v.length;
      }
    }
    return n;
  }

  /// The most a real transfer file of [compressed] bytes (its gzip, the sealed body's length) can open to (round 9
  /// review, 9B-06). The text, everything but the pictures, may be at most [maxTextBytes] however well it compresses.
  /// The pictures are PNGs (deflate-compressed) carried as base64, which gzip packs to about 3/4 (six bits a
  /// character) when they are large: a photo opens to 1.33 times its share of the file. Only a picture PNG already
  /// packed small (a flat colour, a gradient, a screenshot) packs further, and it stays small: measured on PNGs the
  /// engine made up to the largest size allowed, 1,440 x 4,000, none opened to more than twice its share plus 110 KB,
  /// so [pictureSlack] for each picture leaves room for every real one. Anything larger is refused before it is read:
  /// a 180 KB file of repeated letters had opened to 189 MB.
  static int openedLimit(int compressed) =>
      min(maxOpenedBytes, maxTextBytes + maxPhotos * pictureSlack + 2 * compressed);
  static const pictureSlack = 256 * 1024;

  /// gzip [data] opened through a counting sink that stops at [cap] bytes (F-07: no decompression bomb).
  static List<int> gunzipCapped(List<int> data, int cap) {
    final whole = BytesBuilder(copy: false);
    gunzipPieces(data, cap).forEach(whole.add);
    return whole.takeBytes();
  }

  /// gzip [data] opened through a counting sink that stops at [cap] bytes, as the pieces the decoder gave, so the
  /// opened text is never copied into one block as well (9B-06). [refusal] is the message when [cap] is passed.
  static List<Uint8List> gunzipPieces(List<int> data, int cap, {String? refusal}) {
    final out = _CappedSink(cap, refusal);
    final input = gzip.decoder.startChunkedConversion(out);
    final whole = data is Uint8List ? data : Uint8List.fromList(data);
    for (var i = 0; i < whole.length; i += 65536) {
      input.add(Uint8List.sublistView(whole, i, min(i + 65536, whole.length)));
    }
    input.close();
    return out.pieces;
  }

  // Structural limits on the received data, checked before it is read into the app's types (F-07).
  static const maxString = 60000, maxList = 20000, maxDepth = 12, maxPhotoChars = 4 * 1024 * 1024, maxPhotos = 100;

  /// Why [value] has an impossible shape (too deep, a list or text too long), or null when it is fine.
  static String? shapeProblem(Object? value, [int depth = 0, String key = '']) {
    if (depth > maxDepth) return 'too deep';
    if (value is String) {
      final limit = key == 'photos' ? maxPhotoChars : maxString;
      return value.length > limit ? 'text too long' : null;
    }
    if (value is List) {
      if (value.length > maxList) return 'list too long';
      for (final v in value) {
        final p = shapeProblem(v, depth + 1, key);
        if (p != null) return p;
      }
      return null;
    }
    if (value is Map) {
      if (value.length > maxList) return 'too many entries';
      for (final e in value.entries) {
        if (e.key is! String || (e.key as String).length > 200) return 'bad key';
        final p = shapeProblem(e.value, depth + 1, key.isEmpty && depth == 0 ? e.key as String : key);
        if (p != null) return p;
      }
      return null;
    }
    return value == null || value is num || value is bool ? null : 'unknown type';
  }

  /// Why [d] would break the app after it is saved (dates the screens read, numbers they compute with, pictures they
  /// draw), or null when it is fine (F-07: a file that imported but broke session start or Home for good).
  static String? contentProblem(AppData d) {
    // a strict calendar date, optionally with a time ("2026-11-14" or "2026-11-14T19:30..."), never "+002026-..."
    // (verification round 2: tryParse alone accepted odd forms, and unchecked plan dates broke session start)
    final strict = RegExp(r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])(T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d{1,6})?)?)?$');
    bool date(Object? v) => v is String && strict.hasMatch(v) && DateTime.tryParse(v) != null;
    bool dateOrEmpty(Object? v) => v is String && (v.isEmpty || date(v));
    final hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    const weekdays = {'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'};
    final st = d.settings;
    if (!hhmm.hasMatch(st.dailyReminder) || !hhmm.hasMatch(st.weeklyTime) || !weekdays.contains(st.weeklyDay)) {
      return 'reminder';
    }
    if (!RegExp(r'^p[1-9]$').hasMatch(st.portrait)) return 'portrait';
    final pl = d.plans;
    for (final x in pl.steps) {
      if (!dateOrEmpty(x.day) || !dateOrEmpty(x.added) || (x.time.isNotEmpty && !hhmm.hasMatch(x.time))) return 'step';
    }
    for (final h in pl.habits) {
      if (!dateOrEmpty(h.start) || !h.kept.every(date) || !h.missed.every(date)) return 'habit';
    }
    for (final g in pl.goals) {
      if (!dateOrEmpty(g.added) || !dateOrEmpty(g.lastProgress)) return 'goal';
    }
    for (final v in pl.values) {
      if (!dateOrEmpty(v.added)) return 'value';
    }
    for (final x in pl.pictures) {
      if (!dateOrEmpty(x.added) || !dateOrEmpty(x.lastAction)) return 'picture';
    }
    for (final w in d.wheel) {
      if (!date(w['date']) || w['ratings'] is! Map) return 'wheel';
      for (final r in (w['ratings'] as Map).values) {
        if (r is! int || r < 0 || r > 10) return 'wheel rating';
      }
    }
    for (final p in d.programmes) {
      if (p.name.length > 200 || p.sessions < 0 || p.sessions > 10000) return 'programme';
      for (final (day, _) in p.log) {
        if (!date(day)) return 'programme log';
      }
    }
    if (d.scores.map((s) => s['date']).toSet().length > 5000) return 'scores';
    for (final s in d.scores) {
      final items = s['items'];
      if (items != null && (items is! List || items.length > 50 || items.any((i) => i is! int || i < 0 || i > 10))) {
        return 'score items';
      }
    }
    for (final s in d.sessions) {
      if (!date(s.date)) return 'session date';
      if (s.turns.length > 2000) return 'session length';
    }
    for (final s in d.scores) {
      if (!date(s['date']) || s['name'] is! String || s['total'] is! int) return 'score';
    }
    for (final e in d.moods.entries) {
      if (!date(e.key) || e.value < 0 || e.value > 10) return 'mood';
    }
    for (final k in d.moodTimes.keys) {
      if (!date(k)) return 'mood time';
    }
    for (final p in d.programmes) {
      if (!date(p.start)) return 'programme';
    }
    for (final e in d.emotions) {
      if (!date(e.at)) return 'feeling';
    }
    for (final j in d.journal) {
      if (j['date'] != null && !date(j['date'])) return 'journal';
    }
    for (final e in d.safetyEvents) {
      if (e['date'] is! String) return 'safety event';
    }
    if (d.safetyWatch != null && !date(d.safetyWatch!['since'])) return 'safety watch';
    if (d.photos.length > maxPhotos) return 'photos';
    for (final b64 in d.photos.values) {
      final List<int> bytes;
      try {
        bytes = base64Decode(b64);
      } catch (_) {
        return 'photo';
      }
      // a real PNG or JPEG of a size Solace draws, read from its header (OW-M4-1), never decoded here
      if (!pictureFits(bytes)) return 'photo';
    }
    return null;
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}

/// Collects decompressed bytes and stops as soon as there are more than [cap].
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.cap, [this.refusal]);
  final int cap;
  final String? refusal;
  final pieces = <Uint8List>[];
  var length = 0;

  @override
  void add(List<int> chunk) {
    if (length + chunk.length > cap) {
      pieces.clear(); // let go of what was opened before refusing
      throw TransferError(refusal ??
          'This file opens to something far too large for a Solace transfer file, so nothing was changed.');
    }
    length += chunk.length;
    pieces.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
  }

  @override
  void close() {}
}

/// A transfer file picked on this device, held so that its bytes never pass through the screen's isolate
/// (verification round 3, R3-6): [read] reads it on a worker, and [TransferFile.openPicked] moves the bytes to the
/// worker that opens them and back again, without a copy here.
class PickedTransfer {
  PickedTransfer._(this._bytes, this.length);
  TransferableTypedData? _bytes;

  /// The file's size in bytes.
  final int length;

  /// Reads the file at [path] on a worker isolate: at most [TransferFile.maxFileBytes], whatever its size says.
  static Future<PickedTransfer> read(String path) async {
    final (TransferableTypedData? bytes, int length) = await Isolate.run(() {
      final f = File(path).openSync();
      try {
        final n = f.lengthSync();
        if (n > TransferFile.maxFileBytes) return (null, n);
        final bytes = f.readSync(n); // never more than the size checked, even if the file grows meanwhile
        return (TransferableTypedData.fromList([bytes]), bytes.length);
      } finally {
        f.closeSync();
      }
    });
    if (bytes == null) {
      throw TransferError('That file is too large to be a Solace transfer file. Pick the .mtx file made on the other '
          'device.');
    }
    return PickedTransfer._(bytes, length);
  }

  /// A file already in memory (tests, or a picker that gives no path): its bytes are copied once, here.
  factory PickedTransfer.fromBytes(Uint8List bytes) =>
      PickedTransfer._(TransferableTypedData.fromList([bytes]), bytes.length);

  TransferableTypedData _take() {
    final b = _bytes;
    if (b == null) throw StateError('The transfer file is being opened already.');
    _bytes = null;
    return b;
  }
}

enum JsonOutline { fine, tooDeep, tooMany, stringTooLong, tooManyPictures }

/// [JsonScan] over [bytes] in one piece: the depth of brackets and the number of values.
JsonOutline jsonOutline(List<int> bytes, {required int maxDepth, required int maxValues}) =>
    (JsonScan(maxDepth: maxDepth, maxValues: maxValues)..add(bytes)).result;

/// One pass over JSON text as UTF-8 bytes, fed in pieces, that allocates nothing (round 4 review, A-01): the depth of
/// brackets and the number of values. Every comma separates two values and every bracket opens one, so opening
/// brackets plus commas never exceed the values a reviver would count, and a file refused here would have been
/// refused by it, only later and after building everything. [maxDepth] counts the outermost bracket as 1.
///
/// With [checkStrings] (round 9 review, 9B-06) it also measures the bytes inside strings: the pictures (the text
/// values directly under `app_data` > `photos`, which [pictureBytes] adds up, as [TransferFile.pictureChars] does
/// after reading) and every other string. A picture longer than [TransferFile.maxPhotoChars], more than
/// [TransferFile.maxPhotos] pictures, or another string longer than 6 bytes for each of [TransferFile.maxString]
/// characters (the most any character takes in JSON, as `\uXXXX`) is refused here, before the strings are built.
/// A file Solace made writes those keys plainly and its base64 pictures need no escapes, so it is measured exactly; a
/// key written with escapes is not taken for a picture, which can only make a crafted file look larger.
class JsonScan {
  JsonScan({required this.maxDepth, required this.maxValues, this.checkStrings = false})
      : _isObject = List<bool>.filled(maxDepth + 1, false);
  final int maxDepth, maxValues;
  final bool checkStrings;

  /// The outcome so far; once it is not [JsonOutline.fine] the rest is not read.
  JsonOutline result = JsonOutline.fine;

  /// The bytes inside the pictures' strings, and how many pictures there are (with [checkStrings]).
  int pictureBytes = 0, pictures = 0;

  final List<bool> _isObject; // by depth: an object (true) or a list
  var _depth = 0, _values = 0;
  var _inString = false, _escape = false, _expectKey = false;
  var _stringIsKey = false, _stringIsPicture = false, _from = 0, _stringBytes = 0;
  // the last key read in the outermost object ("app_data"?) and in the one under it ("photos"?)
  var _readingKey = false, _keyOk = false, _keyPos = 0, _rootKeyIsAppData = false, _appKeyIsPhotos = false;
  var _photosOpen = false;
  List<int> _target = _appData;
  static final _appData = utf8.encode('app_data'), _photos = utf8.encode('photos');

  JsonOutline add(List<int> bytes) {
    if (result != JsonOutline.fine) return result;
    if (_inString) _from = 0;
    for (var i = 0; i < bytes.length; i++) {
      final c = bytes[i];
      if (_inString) {
        if (_escape) {
          _escape = false;
          _keyOk = false; // a key with an escape is never taken for "app_data" or "photos"
        } else if (c == 0x5c) {
          _escape = true;
        } else if (c == 0x22) {
          _inString = false;
          _stringBytes += i - _from;
          final r = _endString();
          if (r != JsonOutline.fine) return result = r;
        } else if (_readingKey) {
          if (_keyPos >= _target.length || _target[_keyPos] != c) _keyOk = false;
          _keyPos++;
        }
        continue;
      }
      if (c == 0x22) {
        _inString = true;
        _from = i + 1;
        _stringBytes = 0;
        _stringIsKey = _expectKey;
        _readingKey = _stringIsKey && (_depth == 1 || _depth == 2);
        _target = _depth == 1 ? _appData : _photos;
        _keyPos = 0;
        _keyOk = true;
        _stringIsPicture = !_stringIsKey && _photosOpen && _depth == 3;
      } else if (c == 0x5b || c == 0x7b) {
        if (++_depth > maxDepth) return result = JsonOutline.tooDeep;
        if (++_values > maxValues) return result = JsonOutline.tooMany;
        final object = c == 0x7b;
        _isObject[_depth] = object;
        _expectKey = object;
        if (_depth == 2) _appKeyIsPhotos = false;
        if (_depth == 3) {
          _photosOpen = object && _isObject[1] && _isObject[2] && _rootKeyIsAppData && _appKeyIsPhotos;
        }
      } else if (c == 0x5d || c == 0x7d) {
        if (_depth == 3) _photosOpen = false;
        if (_depth > 0) _depth--;
        _expectKey = false;
      } else if (c == 0x2c) {
        if (++_values > maxValues) return result = JsonOutline.tooMany;
        _expectKey = _depth > 0 && _isObject[_depth];
      } else if (c == 0x3a) {
        _expectKey = false;
      }
    }
    if (_inString) _stringBytes += bytes.length - _from;
    return result;
  }

  JsonOutline _endString() {
    if (_readingKey) {
      final match = _keyOk && _keyPos == _target.length;
      if (_depth == 1) {
        _rootKeyIsAppData = match;
      } else {
        _appKeyIsPhotos = match;
      }
      _readingKey = false;
    }
    if (!checkStrings) return JsonOutline.fine;
    if (_stringIsPicture) {
      if (_stringBytes > TransferFile.maxPhotoChars) return JsonOutline.stringTooLong;
      if (++pictures > TransferFile.maxPhotos) return JsonOutline.tooManyPictures;
      pictureBytes += _stringBytes;
    } else if (_stringBytes > 6 * TransferFile.maxString) {
      return JsonOutline.stringTooLong;
    }
    return JsonOutline.fine;
  }
}
