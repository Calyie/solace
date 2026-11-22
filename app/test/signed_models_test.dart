// Signed models (owner, 2026-11-16: "Remove the edit [adding each new model's SHA-256 to trusted.dart] but document how
// I can go back to the other mode"). A model made after this version of Solace is trusted when it is on the owner's
// model list (solace-models.json), signed with the key whose public half is built in (core/model_manifest.dart): the
// signature is checked before the list is read, the list's number never goes back (not even after Delete everything),
// the model must be on it, not withdrawn, made for this version and exactly the size listed, and the list is checked
// again at every start. With SOLACE_SIGNED_MODELS=false only the built-in models are trusted, as before. These tests
// use their own key pair, made here; the owner's key is never used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_files.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/model_import.dart';
import 'package:solace/core/model_manifest.dart';
import 'package:solace/core/trusted.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/core/formats.dart' show appPromptVersion;

import 'app_flow_test.dart' as flow;

/// A loaded model stand-in, so the tests can see which file was loaded.
class _Loaded extends StandInModel {
  const _Loaded(this.file);
  final String file;
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String sumOf(String text) => _hex(const DartSha256().hashSync(utf8.encode(text)).bytes);

(String, Stream<List<int>>) file(String name, String text) => (name, Stream.value(utf8.encode(text)));
(String, Stream<List<int>>) bytesFile(String name, List<int> bytes) => (name, Stream.value(bytes));

late SimpleKeyPair _key, _otherKey;

/// One model entry as tools/models/sign_models.py writes it.
Map<String, Object?> entry(String content, {String tier = 'standard', String prompt = appPromptVersion, int? size,
        String family = 'gemma4', int context = 8192, String name = 'therapist-new.gguf'}) =>
    {'sha256': sumOf(content), 'size': size ?? utf8.encode(content).length, 'tier': tier, 'prompt_version': prompt,
        'context': context, 'family': family, 'name': name};

/// A list's exact bytes, and its signature (base64, with a line end) by [by] (the test key unless given).
Future<(List<int>, List<int>)> signed(List<Map<String, Object?>> models, {int serial = 1, List<String> revoked = const [],
    SimpleKeyPair? by, List<int>? raw}) async {
  final bytes = raw ??
      utf8.encode(jsonEncode({'schema': 1, 'serial': serial, 'issued': '2026-11-16', 'models': models, 'revoked': revoked}));
  final sig = await DartEd25519().sign(bytes, keyPair: by ?? _key);
  return (bytes, utf8.encode('${base64.encode(sig.bytes)}\n'));
}

/// The picked files: the model and its .sha256 list, with the signed list and its signature when given.
List<(String, Stream<List<int>>)> picks(String name, String content, [(List<int>, List<int>)? list]) => [
      file(name, content),
      file(name.replaceAll('.gguf', '.sha256'), '${sumOf(content)}  $name\n'),
      if (list != null) ...[bytesFile(modelListName, list.$1), bytesFile(modelSignatureName, list.$2)],
    ];

void main() {
  late Directory support, files;
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
    _key = await DartEd25519().newKeyPair();
    _otherKey = await DartEd25519().newKeyPair();
    testOnlyModelSigningKey = _hex((await _key.extractPublicKey()).bytes);
  });
  tearDownAll(() {
    testOnlyModelSigningKey = null;
    testOnlySignedModelsOn = null;
  });
  setUp(() async {
    support = await Directory.systemTemp.createTemp('signed_models');
    files = Directory('${support.path}/files'); // as on the device: the floor sits beside it, in the support folder
  });
  tearDown(() async {
    testOnlySignedModelsOn = null;
    await support.delete(recursive: true);
  });

  File floorFile() => File('${support.path}/$serialFloorName');
  File keptList() => File('${support.path}/$keptListName'); // beside the floor, not with the models (9A-12)
  File keptSig() => File('${support.path}/$keptSignatureName');
  List<String> kept() => files.existsSync() ? (files.listSync().map((e) => e.uri.pathSegments.last).toList()..sort()) : [];

  /// Nothing copied and nothing kept: no model, no list, no part file, and the floor as it was.
  void nothingCopied({String? floor}) {
    expect(kept(), isEmpty);
    expect(floorFile().existsSync() ? floorFile().readAsStringSync().trim() : null, floor);
    if (floor == null) expect(keptList().existsSync() || keptSig().existsSync(), isFalse);
  }

  test('the built-in switch and key: signed models on by default, a well-formed public key, the built-in models kept',
      () {
    expect(signedModelsOn, isTrue, reason: 'SOLACE_SIGNED_MODELS defaults to true');
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(modelSigningKey), isTrue);
    expect(trustedModels, hasLength(2), reason: 'the two shipped files stay trusted');
    expect(keptModelName(trustedModels.keys.firstWhere((k) => trustedModels[k]!.contains('e2b'))), 'model-light.gguf');
  });

  test('a valid list and model are accepted, the list kept, the floor raised, and the tier taken from the list', () async {
    // the names say the opposite of the tiers: the list decides, not "e2b" in the name
    final list = await signed([entry('light weights', tier: 'light', name: 'therapist-e4b-new.gguf'),
        entry('standard weights', name: 'therapist-e2b-new.gguf')], serial: 3);
    final msg = await importModelFiles(picks('therapist-e4b-new.gguf', 'light weights', list), files);
    expect(msg, 'Copied the Light model. The app checks it, then loads it.');
    expect(File('${files.path}/model-light.gguf').readAsStringSync(), 'light weights');
    expect(keptList().readAsBytesSync(), list.$1, reason: 'the exact bytes kept, beside the floor');
    expect(keptSig().readAsBytesSync(), list.$2);
    expect(floorFile().readAsStringSync().trim(), '3');
    expect(kept(), ['model-light.gguf', 'model-light.sha256'], reason: 'no list and no part file with the models');
    // at the next start the kept list is checked again and the model is trusted, as the Light one
    final again = await KeptModelList.read(files);
    expect(again.note, isNull);
    expect(again.list!.serial, 3);
    final found = await ModelFile.findAll(files);
    expect(found.map((m) => m.name), ['model-light.gguf']);
    expect(found.single.isStandard, isFalse);
    // the Standard one on the same list, added later without picking the list again: the kept list counts
    final std = await importModelFiles(picks('therapist-e2b-new.gguf', 'standard weights'), files);
    expect(std, startsWith('Copied the Standard model'));
    expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-standard.gguf', 'model-light.gguf']);
  });

  test('the same serial again is accepted (at least the floor), and a higher one raises the floor', () async {
    await importModelFiles(picks('a.gguf', 'a', await signed([entry('a')], serial: 5)), files);
    expect(await importModelFiles(picks('a.gguf', 'a', await signed([entry('a')], serial: 5)), files), startsWith('Copied'));
    expect(await importModelFiles(picks('a.gguf', 'a', await signed([entry('a')], serial: 9)), files), startsWith('Copied'));
    expect(floorFile().readAsStringSync().trim(), '9');
  });

  group('refused, with a plain message, and nothing copied', () {
    test('a list changed after it was signed (a bad signature)', () async {
      final (bytes, sig) = await signed([entry('weights')]);
      final changed = List<int>.from(bytes);
      changed[changed.length - 3] ^= 1;
      expect(await importModelFiles(picks('m.gguf', 'weights', (changed, sig)), files), notSigned);
      nothingCopied();
    });

    test('a list signed by another key', () async {
      expect(await importModelFiles(picks('m.gguf', 'weights', await signed([entry('weights')], by: _otherKey)), files),
          notSigned);
      nothingCopied();
    });

    test('a signature that is not one (not base64, or not 64 bytes, or far too large)', () async {
      final (bytes, _) = await signed([entry('weights')]);
      for (final sig in [utf8.encode('not a signature!'), utf8.encode(base64.encode(List.filled(32, 1))),
          List.filled(5000, 65), [0xff, 0xfe]]) {
        expect(await importModelFiles(picks('m.gguf', 'weights', (bytes, sig)), files), signatureUnreadable);
      }
      nothingCopied();
    });

    test('a model whose checksum is not on the list', () async {
      expect(await importModelFiles(picks('m.gguf', 'other weights', await signed([entry('weights')])), files), notOnList);
      nothingCopied();
    });

    test('a model file not the size the list gives: before copying when the size is known, else while copying',
        () async {
      final list = await signed([entry('weights', size: 99)]);
      final msg = await importModelFiles(picks('m.gguf', 'weights', list), files, sizes: {'m.gguf': 7});
      expect(msg, wrongSize(7, 99));
      nothingCopied();
      expect(await importModelFiles(picks('m.gguf', 'weights', list), files),
          'The copied model is not the size the signed model list gives, so it was not used. Copy the file again.');
      nothingCopied();
      // a stream far longer than listed is never copied past the listed size
      var pulled = 0;
      Stream<List<int>> endless() async* {
        while (true) {
          pulled++;
          yield List.filled(1000, 1);
        }
      }
      final big = await signed([entry('weights', size: 5000)]);
      final picked = [('m.gguf', endless()), file('m.sha256', '${sumOf('weights')}  m.gguf\n'),
          bytesFile(modelListName, big.$1), bytesFile(modelSignatureName, big.$2)];
      expect(await importModelFiles(picked, files), contains('not the size the signed model list gives'));
      expect(pulled, lessThanOrEqualTo(7));
      nothingCopied();
    });

    test('a withdrawn model, a built-in one too, at import and at every start', () async {
      final builtIn = sumOf('built-in weights');
      testOnlyTrustedModels.add(builtIn); // stands in for a model in trustedModels
      addTearDown(() => testOnlyTrustedModels.remove(builtIn));
      // trusted before any list withdraws it
      expect(await importModelFiles(picks('old.gguf', 'built-in weights'), files), startsWith('Copied the Standard'));
      expect(await ModelFile.find(files), isNotNull);
      final list = await signed([entry('new light', tier: 'light')], serial: 2, revoked: [builtIn, sumOf('withdrawn')]);
      // a listed-then-withdrawn model and the built-in one are both refused with the list
      expect(await importModelFiles(picks('w.gguf', 'withdrawn', list), files), withdrawn);
      expect(await importModelFiles(picks('old.gguf', 'built-in weights', list), files), withdrawn);
      expect(floorFile().existsSync(), isFalse, reason: 'nothing accepted, so the floor is not raised');
      // once the list arrives with a new model, the built-in model already on the device is no longer used
      expect(await importModelFiles(picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
      expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-light.gguf'],
          reason: 'the withdrawn built-in Standard model is passed over at start');
      // and it cannot be added again without a list: the kept one still withdraws it
      expect(await importModelFiles(picks('old.gguf', 'built-in weights'), files), withdrawn);
    });

    test('a list older than one already accepted (rollback), also after Delete everything', () async {
      expect(await importModelFiles(picks('m.gguf', 'weights', await signed([entry('weights')], serial: 5)), files),
          startsWith('Copied'));
      final older = await signed([entry('weights'), entry('withdrawn later')], serial: 4);
      expect(await importModelFiles(picks('m.gguf', 'weights', older), files), olderList(4, 5));
      // Delete everything removes the model files and the kept list, but not the floor beside the store
      final inbox = await Directory.systemTemp.createTemp('signed_inbox');
      File('${inbox.path}/$modelListName').writeAsStringSync('x');
      File('${inbox.path}/$modelSignatureName.refused').writeAsStringSync('x');
      File('${inbox.path}/my-notes.json').writeAsStringSync('mine');
      await wipeAppFolders(support: support, temp: support, inbox: inbox);
      expect(files.existsSync(), isFalse);
      expect(floorFile().readAsStringSync().trim(), '5');
      expect(keptList().existsSync() && keptSig().existsSync(), isTrue, reason: 'the accepted list stays too (9A-12)');
      expect(inbox.listSync().map((e) => e.uri.pathSegments.last), ['my-notes.json'],
          reason: 'the drop zone loses only its model lists');
      await inbox.delete(recursive: true);
      expect(await importModelFiles(picks('w.gguf', 'withdrawn later', older), files), olderList(4, 5));
      nothingCopied(floor: '5');
    });

    test('a model made for a different prompt version, family or context', () async {
      expect(await importModelFiles(picks('m.gguf', 'w', await signed([entry('w', prompt: 'v0')])), files),
          'This model was made for a different version of Solace (prompt version v0; this version uses $appPromptVersion), so it was '
          'not copied.');
      expect(await importModelFiles(picks('m.gguf', 'w', await signed([entry('w', family: 'llama3')])), files),
          contains('(llama3) this version of Solace cannot run'));
      expect(await importModelFiles(picks('m.gguf', 'w', await signed([entry('w', context: 4096)])), files),
          contains('context of 4096 tokens'));
      nothingCopied();
    });

    test('a list larger than 64 KB, refused before it is read whole (even signed)', () async {
      var pulled = 0;
      Stream<List<int>> huge() async* {
        for (var i = 0; i < 200; i++) {
          pulled++;
          yield List.filled(1024, 32);
        }
      }
      final sig = (await signed([entry('w')])).$2;
      final picked = [...picks('m.gguf', 'w'), ('solace-models.json', huge()), bytesFile(modelSignatureName, sig)];
      expect(await importModelFiles(picked, files), listTooLarge);
      expect(pulled, lessThanOrEqualTo(65), reason: 'never read past the limit');
      final padded = await signed([], raw: utf8.encode('{"schema":1,"pad":"${' ' * 65536}"}'));
      expect(await importModelFiles(picks('m.gguf', 'w', padded), files), listTooLarge);
      nothingCopied();
    });

    test('signed garbage: not UTF-8, not JSON, the wrong shape, nested too deeply; no crash', () async {
      final good = entry('w');
      final garbage = <List<int>>[
        [0xff, 0xfe, 0x00, 0x7b],
        utf8.encode('not json at all'),
        utf8.encode('{"schema":1,"serial":1'),
        utf8.encode('null'),
        utf8.encode('[1,2,3]'),
        utf8.encode('{"schema":"1"}'),
        utf8.encode('[' * 30000 + ']' * 30000),
        utf8.encode('{"schema":1,"serial":0,"issued":"x","models":[],"revoked":[]}'),
        utf8.encode('{"schema":1,"serial":1.5,"issued":"x","models":[],"revoked":[]}'),
        utf8.encode('{"schema":1,"serial":99999999999999999999,"issued":"x","models":[],"revoked":[]}'),
        utf8.encode('{"schema":1,"serial":1,"issued":"x","models":{},"revoked":[]}'),
        utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': 'x', 'models': [good, good], 'revoked': []})),
        utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': 'x', 'revoked': [],
            'models': [{...good, 'sha256': (good['sha256'] as String).toUpperCase()}]})),
        utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': 'x', 'revoked': [],
            'models': [{...good, 'tier': 'huge'}]})),
        utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': 'x', 'revoked': [],
            'models': [{...good, 'size': -1}]})),
        utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': 'x', 'revoked': [],
            'models': [{...good, 'size': maxModelBytes + 1}]})),
        utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': 'x', 'revoked': ['nope'], 'models': [good]})),
        utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': 'x', 'revoked': [], 'models': [
            {...good}..remove('context')]})),
      ];
      for (final raw in garbage) {
        expect(await importModelFiles(picks('m.gguf', 'w', await signed([], raw: raw)), files), listUnreadable,
            reason: utf8.decode(raw.take(60).toList(), allowMalformed: true));
      }
      final newer = await signed([], raw: utf8.encode('{"schema":2,"serial":1}'));
      expect(await importModelFiles(picks('m.gguf', 'w', newer), files), newerFormat(2));
      nothingCopied();
    });

    test('a list without its signature, a signature without its list, or two lists', () async {
      final (bytes, sig) = await signed([entry('w')]);
      expect(await importModelFiles([...picks('m.gguf', 'w'), bytesFile(modelListName, bytes)], files), listAndSignature);
      expect(await importModelFiles([...picks('m.gguf', 'w'), bytesFile(modelSignatureName, sig)], files),
          listAndSignature);
      expect(await importModelFiles([...picks('m.gguf', 'w', (bytes, sig)), bytesFile('solace-models (1).json', bytes)],
          files), oneListOnly);
      expect(await importModelFiles([bytesFile(modelListName, bytes), bytesFile(modelSignatureName, sig)], files),
          contains('Pick the model file'));
      nothingCopied();
    });

    test('a damaged floor file refuses every list rather than start again from none', () async {
      support.createSync(recursive: true);
      floorFile().writeAsStringSync('not a number');
      expect(await importModelFiles(picks('m.gguf', 'w', await signed([entry('w')], serial: 1)), files), floorUnreadable);
      nothingCopied(floor: 'not a number');
    });
  });

  group('at every start the kept list is checked again', () {
    /// A built-in stand-in Standard model and a Light one on the signed list, both on the device.
    Future<void> both() async {
      testOnlyTrustedModels.add(sumOf('built-in'));
      addTearDown(() => testOnlyTrustedModels.remove(sumOf('built-in')));
      await importModelFiles(picks('std.gguf', 'built-in'), files);
      await importModelFiles(picks('l.gguf', 'listed', await signed([entry('listed', tier: 'light')], serial: 2)), files);
      expect((await ModelFile.findAll(files)).length, 2);
    }

    test('a changed kept list: only the built-in models are trusted, and Settings is told', () async {
      await both();
      // still well-formed JSON, so only the signature check can catch it
      final kept = keptList();
      kept.writeAsStringSync(kept.readAsStringSync().replaceFirst('"issued":"2026-11-16"', '"issued":"2026-11-17"'));
      expect(kept.readAsStringSync(), contains('2026-11-17'));
      final read = await KeptModelList.read(files);
      expect(read.list, isNull);
      expect(read.note, keptListFailed);
      expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-standard.gguf']);
      final state = flow.makeState();
      await loadTrainedModel(state, files: files, support: support, memory: () async => null,
          runtime: (m) async => _Loaded(m.name));
      expect(state.modelListNote, keptListFailed);
      expect((state.model as _Loaded).file, 'model-standard.gguf', reason: 'the built-in model still works');
    });

    test('a missing signature, a missing list, an older list put back: each said, the built-in models kept', () async {
      await both();
      final sig = keptSig(), saved = sig.readAsBytesSync();
      sig.deleteSync();
      expect((await KeptModelList.read(files)).note, keptListFailed);
      expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-standard.gguf']);
      // both files gone while the floor shows a list was accepted: said too, never silently "no list"
      final listBytes = keptList().readAsBytesSync();
      keptList().deleteSync();
      expect((await KeptModelList.read(files)).note, keptListFailed);
      expect(await importModelFiles(picks('l.gguf', 'listed'), files), contains('not a model file'),
          reason: 'a model only on the lost list is not trusted');
      keptList().writeAsBytesSync(listBytes);
      sig.writeAsBytesSync(saved);
      floorFile().writeAsStringSync('3\n'); // a newer list was accepted since: the kept one is a rollback
      expect((await KeptModelList.read(files)).note, keptListOlder);
      floorFile().writeAsStringSync('2\n');
      expect((await KeptModelList.read(files)).note, isNull);
      expect((await ModelFile.findAll(files)).length, 2);
    });

    test('a damaged floor is rebuilt from the kept list when it passes its check, else lists stay refused (9B-17)',
        () async {
      await both();
      floorFile().writeAsStringSync('x' * 100);
      final read = await KeptModelList.read(files);
      expect(read.note, isNull);
      expect(read.list!.serial, 2);
      expect(floorFile().readAsStringSync().trim(), '2', reason: 'rebuilt from the kept list');
      floorFile().writeAsStringSync('garbled');
      expect(await importModelFiles(picks('l.gguf', 'listed', await signed([entry('listed')], serial: 1)), files),
          olderList(1, 2), reason: 'rebuilt before a picked list is checked, so rollback protection holds');
      // with no checked list to rebuild from, every list is refused (a reinstall is the way back)
      floorFile().writeAsStringSync('garbled');
      keptSig().writeAsBytesSync((await signed([entry('x')], by: _otherKey)).$2);
      expect((await KeptModelList.read(files)).note, keptFloorUnreadable);
      expect(await importModelFiles(picks('l.gguf', 'listed', await signed([entry('listed')], serial: 9)), files),
          floorUnreadable);
      expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-standard.gguf']);
    });

    test('a floor left behind by an interrupted import is raised to the kept list at start', () async {
      await both();
      floorFile().writeAsStringSync('1\n');
      expect((await KeptModelList.read(files)).note, isNull);
      expect(floorFile().readAsStringSync().trim(), '2');
    });

    test('a kept model whose file was swapped for another size is not trusted', () async {
      await both();
      File('${files.path}/model-light.gguf').writeAsStringSync('listed but longer');
      expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-standard.gguf']);
    });

    testWidgets('Settings shows the note under the model status', (tester) async {
      final state = flow.makeState();
      await tester.runAsync(() async {
        await importModelFiles(picks('l.gguf', 'listed', await signed([entry('listed', tier: 'light')])), files);
        keptSig().writeAsBytesSync((await signed([entry('x')], by: _otherKey)).$2);
        await loadTrainedModel(state, files: files, support: support, memory: () async => null,
            runtime: (m) async => _Loaded(m.name));
      });
      expect(state.model, isNot(isA<_Loaded>()), reason: 'the listed model is not used');
      await flow.pumpScreen(tester, state, const SettingsScreen());
      final note = find.byKey(const Key('model_list_note'));
      await tester.scrollUntilVisible(note, 300, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<Text>(note).data, keptListFailed);
      expect(keptListFailed, contains('uses only the models built into it'));
    });
  });

  group('SOLACE_SIGNED_MODELS=false: only the built-in models, as before', () {
    test('picked list files are ignored, built-in models still work, and a list kept earlier is not read', () async {
      testOnlyTrustedModels.add(sumOf('built-in'));
      addTearDown(() => testOnlyTrustedModels.remove(sumOf('built-in')));
      // kept under the signed mode: a listed model, and a list that withdraws the built-in one
      final list = await signed([entry('listed', tier: 'light')], revoked: [sumOf('built-in')]);
      expect(await importModelFiles(picks('l.gguf', 'listed', list), files), startsWith('Copied the Light'));
      testOnlySignedModelsOn = false;
      // the list files are ignored, as before signed models (9B-18): a model only on the list is not one it trusts
      expect(await importModelFiles(picks('l.gguf', 'listed', list), files),
          'This is not a model file this version of Solace was built for, so it was not copied.');
      expect(await importModelFiles(picks('l.gguf', 'listed'), files),
          'This is not a model file this version of Solace was built for, so it was not copied.');
      expect(await importModelFiles(picks('b.gguf', 'built-in', list), files), startsWith('Copied the Standard'),
          reason: 'the list files picked with it are ignored, and the list kept earlier is not read, so its withdrawal '
              'does not count either');
      expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-standard.gguf']);
      expect(await KeptModelList.read(files), same(KeptModelList.none));
    });
  });

  group('the iPhone drop zone', () {
    test('a model with its signed list moves in, the list is kept and leaves the drop zone', () async {
      final inbox = await Directory.systemTemp.createTemp('signed_inbox');
      addTearDown(() => inbox.delete(recursive: true));
      final (bytes, sig) = await signed([entry('listed', tier: 'light', name: 'r3.gguf')], serial: 4);
      File('${inbox.path}/r3.gguf').writeAsStringSync('listed');
      File('${inbox.path}/r3.sha256').writeAsStringSync('${sumOf('listed')}  r3.gguf\n');
      File('${inbox.path}/$modelListName').writeAsBytesSync(bytes);
      File('${inbox.path}/$modelSignatureName').writeAsBytesSync(sig);
      expect(await importInbox(inbox, files), contains('private folder'));
      expect(inbox.listSync(), isEmpty);
      expect(kept(), ['model-light.gguf', 'model-light.sha256']);
      expect(keptList().readAsBytesSync(), bytes);
      expect(floorFile().readAsStringSync().trim(), '4');
      expect((await ModelFile.find(files))!.name, 'model-light.gguf');
    });

    test('a list that fails its check is set aside with the reason, and the model is left unused', () async {
      final inbox = await Directory.systemTemp.createTemp('signed_inbox');
      addTearDown(() => inbox.delete(recursive: true));
      final (bytes, sig) = await signed([entry('listed')], by: _otherKey);
      File('${inbox.path}/r3.gguf').writeAsStringSync('listed');
      File('${inbox.path}/r3.sha256').writeAsStringSync('${sumOf('listed')}  r3.gguf\n');
      File('${inbox.path}/$modelListName').writeAsBytesSync(bytes);
      File('${inbox.path}/$modelSignatureName').writeAsBytesSync(sig);
      expect(await importInbox(inbox, files), notSigned);
      expect(inbox.listSync().map((e) => e.uri.pathSegments.last).toSet(),
          {'r3.gguf', 'r3.sha256', '$modelListName.refused', '$modelSignatureName.refused'});
      nothingCopied();
      // the list is never read again; the model left there is not from the maker as far as Solace can tell, so from
      // 1.3.0 Solace says how it could be used (picked in Settings, where it asks first), and still uses nothing
      expect(await importInbox(inbox, files), unsignedFromFinder, reason: 'the list never read again');
      nothingCopied();
    });
  });

  test('a list signed by tools/models/sign_models.py is read the same way here (test key, test fixture)', () async {
    final dir = Directory('test/fixtures/signed_models');
    testOnlyModelSigningKey = File('${dir.path}/test_signing_public.hex').readAsStringSync().trim();
    addTearDown(() async => testOnlyModelSigningKey = _hex((await _key.extractPublicKey()).bytes));
    final bytes = File('${dir.path}/$modelListName').readAsBytesSync();
    final sig = File('${dir.path}/$modelSignatureName').readAsBytesSync();
    final (list, why) = await readModelList(bytes, sig);
    expect(why, isNull);
    expect(list!.serial, 7);
    expect(list.revoked, {'a' * 64});
    final light = list.models[sumOf('fixture light weights')]!;
    expect((light.light, light.size, light.name), (true, 21, 'therapist-e2b-fixture.gguf'));
    expect(list.models[sumOf('fixture standard weights')]!.light, isFalse);
    expect(await importModelFiles(picks('therapist-e2b-fixture.gguf', 'fixture light weights', (bytes, sig)), files),
        startsWith('Copied the Light'));
    final (_, changed) = await readModelList([...bytes]..[10] ^= 1, sig);
    expect(changed, notSigned);
  });
}
