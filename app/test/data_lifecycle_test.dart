// Verification round 3 (2026-11-14), the data's life cycle: deleted or replaced data never comes back (R3-4), what an
// import may bring is bounded and never stalls the screen (R3-6), Delete everything removes refused drop-zone files
// (R3-9), an interrupted keychain move never loses the key (N11), a changed passphrase file cannot make every start
// use a gigabyte (DOC-1), and a Markdown export can never fetch anything (OWASP Info OW-I3).
// Every test drives the app's real code; the stores are the real EncryptedFileVault over a stand-in keychain.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_files.dart';
import 'package:solace/core/emotions.dart';
import 'package:solace/core/exports.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/media.dart' show mediaPrefix;
import 'package:solace/core/model.dart';
import 'package:solace/core/passphrase_key_store.dart';
import 'package:solace/core/storage.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';

/// A keychain stand-in that answers later, as keychains do (which is what races).
class Keys implements KeyStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async => values.remove(name);
  @override
  Future<void> deleteAll() async => values.clear();
}

/// A keychain over [values] that stops working (the app was killed) after [lives] operations.
class DyingKeys implements KeyStore {
  DyingKeys(this.values, this.lives);
  final Map<String, String> values;
  int lives;
  void _op() {
    if (lives-- <= 0) throw StateError('killed');
  }

  @override
  Future<String?> read(String name) async {
    _op();
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    _op();
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    _op();
    values.remove(name);
  }

  @override
  Future<void> deleteAll() async {
    _op();
    values.clear();
  }
}

/// Answers at once until [hold] is called; then each reply waits until [fail] (the engine was disposed).
class GatedModel extends StandInModel {
  Completer<void>? _gate;
  bool _fail = false;
  void hold() => _gate = Completer<void>();
  void fail() {
    _fail = true;
    _gate?.complete();
  }

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    final g = _gate;
    if (g != null) await g.future;
    if (_fail) throw StateError('the engine was disposed');
    yield 'I hear you. Tell me more.';
  }
}

/// A model that can be told to stop, recording when it was.
class StoppableModel extends StandInModel implements ReplyCanceller {
  StoppableModel(this.events);
  final List<String> events;
  @override
  void cancelReply() => events.add('reply stopped');
}

class RecordingVault extends MemoryVault {
  RecordingVault(this.events);
  final List<String> events;
  @override
  Future<void> wipe() {
    events.add('data deleted');
    return super.wipe();
  }
}

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);
final library = parseLibrary(File('assets/practices/library_v2.json').readAsStringSync());
final now = DateTime(2026, 11, 14, 20);

AppState makeState({ModelRuntime model = const StandInModel(), required Vault vault, AppData? data}) {
  final d = data ?? AppData();
  d.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  return AppState(data: d, vault: vault, prompts: prompts, model: model, library: library, clock: () => now);
}

/// Waits for an unawaited save to land, if one is coming.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lifecycle'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  File store() => File('${dir.path}/data_v1.bin');

  group('R3-4: deleted or replaced data never comes back', () {
    test('a reply still running after Back cannot write the old data back after Delete everything', () async {
      final keys = Keys();
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      final model = GatedModel();
      final state = makeState(model: model, vault: vault,
          data: AppData()..journal.add({'date': '2026-11-10', 'text': 'PRIVATE WORDS'}));
      await state.save();
      final verdict = Completer<bool>();
      state.useRiskCheck((context, text) => verdict.future, 'test classifier');
      final s = state.newSession();
      await s.start('daily_checkin');
      model.hold();
      final pending = s.send('Work was hard today.'); // she is replying; the person presses Back
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s.leave(); // the screen has gone (ChatScreen.dispose); an open session would refuse the wipe (review c1, D4)
      await state.wipeEverything(folders: () async {}); // Settings > Delete everything
      expect(store().existsSync(), isFalse, reason: 'wiped');
      model.fail(); // the engine goes
      verdict.complete(true); // the classifier's verdict, still due after leave
      await pending;
      await settle();
      // owner 2026-11-15 (no question; D-11): after Delete everything a late worry is recorded nowhere, stricter still
      expect(s.data.safetyEvents.where((e) => e['reason'] == 'classifier'), isEmpty,
          reason: 'nothing from before the wipe is written, not even in memory');
      expect(s.turns, isNotEmpty, reason: 'the orphaned session did run to its end');
      expect(store().existsSync(), isFalse, reason: 'the old data was never written again');
      expect(File('${dir.path}/data_v1.bin.bak').existsSync(), isFalse);
      expect(keys.values, isEmpty, reason: 'no new key was made for the old data');
      // the new start still saves as normal, under a new key
      state.data.journal.add({'date': '2026-11-14', 'text': 'a fresh start'});
      await state.save();
      expect(state.saveProblem, isNull);
      final back = await EncryptedFileVault(keychain: keys, folder: () async => dir).load();
      expect(back.journal.single['text'], 'a fresh start');
      expect(jsonEncode(back.toJson()), isNot(contains('PRIVATE WORDS')));
    });

    test('the same orphaned reply cannot overwrite an import, and the imported data (made on a worker) still saves',
        () async {
      final keys = Keys();
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      final model = GatedModel();
      final state = makeState(model: model, vault: vault,
          data: AppData()..journal.add({'date': '2026-11-10', 'text': 'OLD WORDS'}));
      await state.save();
      final verdict = Completer<bool>();
      state.useRiskCheck((context, text) => verdict.future, 'test classifier');
      final s = state.newSession();
      await s.start('daily_checkin');
      model.hold();
      final pending = s.send('Work was hard today.');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s.leave(); // Back: an open session would refuse the import (review c1, D4)
      // a real transfer file, opened on a worker isolate as the screen does
      final code = TransferCode.generate();
      final other = AppData()..journal.add({'date': '2026-11-12', 'text': 'IMPORTED WORDS'});
      final incoming = await TransferFile.openInBackground(await TransferFile.sealInBackground(other, code), code);
      await state.receiveTransfer(incoming);
      model.fail();
      verdict.complete(true); // still due after leave: it records a question in the old data and saves it
      await pending;
      await settle();
      // owner 2026-11-15 (no question; D-11): the late worry is recorded on the data the app holds now, never the old copy
      expect(state.data.safetyEvents.where((e) => e['reason'] == 'classifier'), hasLength(1),
          reason: 'recorded on the imported data');
      expect(s.data.safetyEvents.where((e) => e['reason'] == 'classifier'), isEmpty, reason: 'not on the stale copy');
      final back = await EncryptedFileVault(keychain: keys, folder: () async => dir).load();
      expect(back.journal.single['text'], 'IMPORTED WORDS', reason: 'the import was not overwritten');
      // the imported object is the data from now on: its saves are written, although it was made on another isolate
      await state.saveMood(6);
      expect(state.saveProblem, isNull);
      final again = await EncryptedFileVault(keychain: keys, folder: () async => dir).load();
      expect(again.moods.values.single, 6);
      expect(again.journal.single['text'], 'IMPORTED WORDS');
    });

    test('in the vault: a save queued before Delete everything is dropped; one asked for during it runs after it',
        () async {
      final keys = Keys();
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      final old = AppData()..lastNote = 'old words';
      await vault.save(old);
      final firstKey = keys.values[EncryptedFileVault.keyName];
      final writing = vault.save(old);
      await Future<void>.delayed(Duration.zero); // that save has begun writing
      final queued = vault.save(old); // and this one waits for it
      final wiping = vault.wipe(); // not awaited, as a screen might not
      final fresh = AppData()..lastNote = 'new words';
      final after = vault.save(fresh);
      final stale = vault.save(old); // the old data again, after the wipe began
      await Future.wait([writing, queued, wiping, after, stale]);
      expect(vault.generation, 1);
      final back = await EncryptedFileVault(keychain: keys, folder: () async => dir).load();
      expect(back.lastNote, 'new words', reason: 'the new data was written after the wipe, not deleted by it');
      expect(keys.values[EncryptedFileVault.keyName], isNot(firstKey), reason: 'under a new key');
      await vault.save(old);
      final last = await EncryptedFileVault(keychain: keys, folder: () async => dir).load();
      expect(last.lastNote, 'new words', reason: 'old data is never written again');
    });

    test('in the vault: an import names the data that may be saved; older data is dropped, newer is kept', () async {
      for (final vault in <Vault>[MemoryVault(), EncryptedFileVault(keychain: Keys(), folder: () async => dir)]) {
        final before = AppData()..lastNote = 'before';
        final heir = AppData()..lastNote = 'imported';
        final between = AppData()..lastNote = 'made before the import began';
        await vault.save(before);
        vault.startGeneration(heir);
        await vault.save(between);
        await vault.save(before);
        expect((await vault.load()).lastNote, 'before', reason: '${vault.runtimeType}: nothing older was written');
        await vault.save(heir);
        expect((await vault.load()).lastNote, 'imported');
        await vault.save(AppData()..lastNote = 'made later');
        expect((await vault.load()).lastNote, 'made later');
        await vault.wipe();
        await vault.save(heir);
        expect((await vault.load()).lastNote, '', reason: '${vault.runtimeType}: after a wipe, the imported data is old too');
      }
    });

    test('Delete everything stops the reply being written before the data goes', () async {
      final events = <String>[];
      final state = makeState(model: StoppableModel(events), vault: RecordingVault(events));
      await state.wipeEverything(folders: () async {});
      expect(events, ['reply stopped', 'data deleted']);
      expect(state.model, isA<StandInModel>());
    });
  });

  group('R3-6: what an import may bring', () {
    AppData bigText() {
      final big = AppData();
      final text = 'I keep thinking about the move and the job and what comes next. ' * 900; // 58,500 characters
      for (var i = 0; i < 1000; i++) {
        big.journal.add({'date': '2026-11-01', 'text': '$i $text'});
      }
      return big;
    }

    AppData manyValues(int sessions, int turns) {
      final d = AppData();
      for (var s = 0; s < sessions; s++) {
        d.sessions.add(SessionRecord(date: '2026-11-01', kind: 'daily_checkin',
            turns: [for (var i = 0; i < turns; i++) (i.isEven ? 'person' : 'therapist', 'hi there $i')], note: ''));
      }
      return d;
    }

    test('a 200 KB file that opens to 58 MB of text is refused kindly, and this device never makes one', () async {
      final big = bigText();
      expect(TransferFile.sealProblem(big), contains('more in it than another device can take'));
      final code = TransferCode.generate();
      final file = await TransferFile.seal(big, code, checkFirst: false); // as a hostile or older device would
      expect(file.length, lessThan(512 * 1024));
      await expectLater(TransferFile.openInBackground(file, code),
          throwsA(isA<TransferError>().having((e) => e.message, 'message', TransferFile.tooMuch)));
      expect(TransferFile.tooMuch, isNot(contains('damaged')), reason: 'plain and kind: nothing is wrong with them');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a file of more than 300,000 values is refused kindly; a year of daily sessions is far inside both limits',
        () async {
      final code = TransferCode.generate();
      final many = manyValues(110, 1000); // 330,000 values
      expect(TransferFile.sealProblem(many), isNotNull);
      await expectLater(TransferFile.openInBackground(await TransferFile.seal(many, code, checkFirst: false), code),
          throwsA(isA<TransferError>().having((e) => e.message, 'message', TransferFile.tooMuch)));
      final year = AppData();
      for (var i = 0; i < 365; i++) {
        year.sessions.add(SessionRecord(date: '2026-01-01', kind: 'daily_checkin', note: 'Session: a note. ' * 20,
            turns: [for (var t = 0; t < 40; t++) (t.isEven ? 'person' : 'therapist', 'A sentence or two of what was said. ' * 4)]));
      }
      expect(TransferFile.sealProblem(year), isNull);
      final back = await TransferFile.openInBackground(await TransferFile.seal(year, code), code);
      expect(back.sessions.length, 365);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('an import that would take the store past its 100 MB ceiling is refused, and nothing changes', () async {
      final keys = Keys();
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      final state = makeState(vault: vault, data: AppData()..journal.add({'date': '2026-11-10', 'text': 'mine'}));
      await state.save();
      final before = store().readAsBytesSync();
      final huge = AppData();
      final text = 'x' * 59000; // one string, many times: the test itself stays small
      for (var i = 0; i < 1800; i++) {
        huge.journal.add({'date': '2026-11-01', 'text': text});
      }
      expect(await storeBytesOf(huge), greaterThan(storeCeiling));
      await expectLater(state.receiveTransfer(huge),
          throwsA(isA<TransferError>().having((e) => e.message, 'message', contains('nothing was changed'))));
      expect(state.data.journal.single['text'], 'mine');
      expect(vault.generation, 0, reason: 'no new generation for a refused import');
      expect(store().readAsBytesSync(), before, reason: 'nothing written');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('pictures in an import count against Solace\'s own room: too many are refused, and nothing changes',
        () async {
      final vault = EncryptedFileVault(keychain: Keys(), folder: () async => dir);
      final state = makeState(vault: vault, data: AppData()..journal.add({'date': '2026-11-10', 'text': 'mine'}));
      await state.save();
      final crafted = AppData();
      final junk = base64Encode(List.filled(6 * 1024 * 1024, 7)); // 6 MB each
      crafted.photos['one'] = junk;
      crafted.photos['two'] = junk;
      // Solace's room nearly taken by pictures already: the two more would pass its fixed 2 GB (owner, 2026-11-19: the
      // device's own space is never read for this)
      state.pictureBytes = solaceAllowance - 10 * 1024 * 1024;
      crafted.photos['kept'] = '${mediaPrefix}0';
      await expectLater(state.receiveTransfer(crafted),
          throwsA(isA<TransferError>().having((e) => e.message, 'message', contains('nothing was changed'))));
      expect(state.data.journal.single['text'], 'mine');
      expect((await vault.mediaIndex()).$1, isEmpty, reason: 'no picture file written');
      state.pictureBytes = 0;
      crafted.photos.remove('kept');
      await state.receiveTransfer(crafted);
      expect((await vault.mediaIndex()).$1, hasLength(2), reason: 'both pictures kept, each in its own file');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a picture asked for just before Delete everything never survives it under the old key (L-12)', () async {
      final keys = Keys();
      final vault = EncryptedFileVault(keychain: keys, folder: () async => dir);
      await vault.save(AppData()..journal.add({'date': '2026-11-10', 'text': 'mine'}));
      final picture = vault.putMedia(Uint8List.fromList(List.filled(200000, 3)));
      final wiped = vault.wipe();
      await picture;
      await wiped;
      final media = Directory('${dir.path}/media');
      expect(!media.existsSync() || media.listSync().isEmpty, isTrue, reason: 'the wipe ran after it and removed it');
      final later = await vault.putMedia(Uint8List.fromList(List.filled(1000, 4)));
      expect(await vault.getMedia(later), hasLength(1000), reason: 'a picture after the wipe is kept, with the new key');
    });

    test('storeBytesOf is the size the vault then writes, with pictures kept apart', () async {
      final vault = EncryptedFileVault(keychain: Keys(), folder: () async => dir);
      final d = manyValues(20, 200)..photos['a'] = 'media:${'1' * 32}';
      final expected = await storeBytesOf(d);
      await vault.save(d);
      expect(vault.savedBytes, expected);
    });

  });

  test('R3-9: Delete everything removes refused drop-zone files, and still nothing else', () async {
    final support = Directory('${dir.path}/support')..createSync(), temp = Directory('${dir.path}/tmp')..createSync(),
        inbox = Directory('${dir.path}/Documents')..createSync();
    for (final name in ['x.gguf.refused', 'bundle.zip.refused', 'x.sha256.refused', 'model.gguf', 'model.sha256',
        'bundle.zip', 'my-letter.pdf', 'notes.refused', 'holiday.zip.txt']) {
      File('${inbox.path}/$name').writeAsBytesSync(List.filled(1000, 1));
    }
    await wipeAppFolders(support: support, temp: temp, inbox: inbox);
    expect(inbox.listSync().map((e) => e.uri.pathSegments.last).toSet(), {'my-letter.pdf', 'notes.refused', 'holiday.zip.txt'});
  });

  group('N11: an interrupted keychain move never loses the key', () {
    const name = EncryptedFileVault.keyName;

    test('a key left only in its temporary copy is found, put back and the move finished', () async {
      final store = Keys()..values['$name.moving'] = 'the key';
      final keys = PlatformKeyStore.over(store, Keys(), moveClass: true);
      expect(await keys.read(name), 'the key');
      expect(store.values, {name: 'the key', '$name.class': PlatformKeyStore.classMark});
    });

    test('the store opens after the app was killed between the delete and the write', () async {
      final store = Keys();
      final vault = EncryptedFileVault(keychain: PlatformKeyStore.over(store, Keys(), moveClass: true),
          folder: () async => dir);
      await vault.save(AppData()..lastNote = 'kept');
      final key = store.values.remove(name)!; // killed after the delete: only the copy is left
      store.values['$name.moving'] = key;
      store.values.remove('$name.class');
      final back = await EncryptedFileVault(keychain: PlatformKeyStore.over(store, Keys(), moveClass: true),
          folder: () async => dir).load();
      expect(back.lastNote, 'kept');
    });

    test('killed at any step of the move, the next start reads the same key', () async {
      for (var lives = 0; lives < 16; lives++) {
        final values = {name: 'the key'}; // saved by an older build: no class mark yet
        try {
          await PlatformKeyStore.over(DyingKeys(values, lives), DyingKeys({}, 1 << 20), moveClass: true).read(name);
        } catch (_) {} // killed
        final next = PlatformKeyStore.over(DyingKeys(values, 1 << 20), DyingKeys({}, 1 << 20), moveClass: true);
        expect(await next.read(name), 'the key', reason: 'killed after $lives keychain steps');
        expect(values[name], 'the key');
        expect(values.containsKey('$name.moving'), isFalse, reason: 'after $lives steps the move was finished');
        expect(values['$name.class'], PlatformKeyStore.classMark);
      }
    });

    test('deleting a key also deletes its temporary copy, so a deleted key never comes back', () async {
      final store = Keys()..values.addAll({name: 'the key', '$name.moving': 'the key'});
      final keys = PlatformKeyStore.over(store, Keys(), moveClass: true);
      await keys.delete(name);
      expect(await keys.read(name), isNull);
    });
  });

  group('DOC-1: the passphrase file cannot ask for more than 256 MiB', () {
    test('the settings read from the file are bounded', () {
      StretchSettings of(Object? m, Object? t) => PassphraseKeyStore.settingsFrom({'m': m, 't': t});
      expect(of(1048576, 2).memoryKib, 262144, reason: 'the old bound, 1 GiB');
      expect(of(1 << 40, 2).memoryKib, 262144);
      expect(of(65536, 2).memoryKib, 65536, reason: 'what set-up writes is kept');
      expect(of(16, 2).memoryKib, 8192);
      expect(of('lots', 'many').memoryKib, 65536, reason: 'not a number: the default, never an error');
      expect(of(65536, 1000).iterations, 10);
    });

    test('a tampered file opens no harder than 256 MiB, and a store set up within the bounds opens as before',
        () async {
      const quick = StretchSettings(memoryKib: 8192, iterations: 1);
      await PassphraseKeyStore.create(dir, 'a long enough phrase', settings: quick);
      final opened = await PassphraseKeyStore.open(dir, 'a long enough phrase');
      expect(opened.settings.memoryKib, 8192);
      final f = File('${dir.path}/keys/passphrase.json');
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      f.writeAsStringSync(jsonEncode(j..['m'] = 1048576));
      expect(PassphraseKeyStore.settingsFrom(j).memoryKib, 262144);
    });
  });

  group('OW-I3: a Markdown export never fetches anything', () {
    // what a Markdown viewer could act on, once escapes and code spans are set aside
    String active(String md) => md
        .replaceAll(RegExp(r'\\.'), ' ') // an escaped character is plain text
        .replaceAll('&lt;', ' ') // so is an entity
        .replaceAll(RegExp(r'`[^`\n]*`'), ' '); // so is a code span

    const hostile = [
      '![x](https://track.example/p.png)',
      '<img src="https://track.example/q.png">',
      '[click me](https://track.example/r)',
      '![ref]',
      '[ref]: https://track.example/s.png',
      '<https://track.example/t>',
      'see https://track.example/u and www.track.example/v',
      r'\![y](https://track.example/w.png)',
      '`code` ![z](http://track.example/x.png) `more`',
      '<iframe src=//track.example/y></iframe>',
    ];

    test('notes, journal text and feeling words cannot form a picture, link, reference or HTML tag', () {
      final d = AppData()
        ..moods['2026-11-10'] = 5
        ..journal.add({'date': '2026-11-10', 'text': hostile.join('\n')})
        ..emotions.add(EmotionEntry(at: '2026-11-10T19:30', quadrant: emotionWords.keys.first,
            words: ['![a](https://track.example/z.png)', '<b>'], note: hostile.join('\n')));
      final ids = {for (final n in exportNotes(d)) n.id};
      final md = exportMarkdown(d, now, notes: ids);
      expect(md, contains('track.example'), reason: 'the words are kept');
      final left = active(md);
      for (final bad in ['![', '](', '<img', '<iframe', '<https', 'https://', 'http://', 'www.', '[ref]']) {
        expect(left, isNot(contains(bad)), reason: '"$bad" would still be active');
      }
      expect(RegExp(r'<[A-Za-z!/?]').hasMatch(left), isFalse, reason: 'no HTML tag can open');
      expect(RegExp(r'\[').hasMatch(left), isFalse, reason: 'no link or picture can open');
    });

    test('ordinary words come through unchanged', () {
      expect(mdText('A good day: walked 5 km > 3 km & slept well (finally).'),
          'A good day: walked 5 km > 3 km & slept well (finally).');
      expect(mdText('see https://example.org/a.'), 'see `https://example.org/a`.');
      expect(mdText('(at www.example.org/b), then'), '(at `www.example.org/b`), then');
      expect(mdText(r'a [b] <c> \ `d`'), r'a \[b\] &lt;c> \\ \`d\`');
    });
  });
}
