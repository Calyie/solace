// Review round 9 B, signed models (c680eb7), 9B-16 and 9B-17.
//
// 9B-16: importModelFiles (core/model_import.dart) renames the new model over the one in use (model-standard.gguf)
// BEFORE it keeps the signed list that trusts it (keepModelList) and before it writes the model's new .sha256 line.
// When keeping the list fails (a write refused, the app ended in between), it returns at once: the old model is gone,
// model-standard.sha256 still names the old model's checksum, and the new model is trusted by no kept list. At the next
// start ModelFile.find pairs the new file with the old checksum and verify refuses it: no usable model, where before
// the import there was one. The same state follows a kill anywhere between the rename and the .sha256 write, a window
// the list keeping (two flushed writes, the floor raised and read back) has made longer.
//
// 9B-17: a damaged floor file (model_serial) makes every list refused and the kept list unused, and Delete everything
// keeps that file on purpose (core/app_files.dart wipeAppFolders), so a model made after this version can never be used
// again on the device until Solace is reinstalled (which deletes its data).
//
// Each test asserts the SAFE behaviour and fails on c680eb7 while the finding stands.
//
// Fixed (feat/signed-models after c680eb7). 9B-16: the list is kept and the new checksum line written (part files, then
// renames) before the model's own rename, which is the last step; the test now makes the list keeping fail where the
// list is kept since 9A-12 (beside the floor in the support folder, not in files/). 9B-17: the lead's decision is to
// rebuild a damaged floor from the kept list when that list passes its signature check, and to keep refusing lists
// when there is none (fail closed; a reinstall is then the way back); the test is changed to that policy.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_files.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/model_import.dart';
import 'package:solace/core/model_manifest.dart';
import 'package:solace/core/trusted.dart';
import 'package:solace/core/formats.dart' show appPromptVersion;

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
String _sum(String text) => _hex(const DartSha256().hashSync(utf8.encode(text)).bytes);

void main() {
  late Directory support, files;
  late SimpleKeyPair key;
  setUpAll(() async {
    key = await DartEd25519().newKeyPair();
    testOnlyModelSigningKey = _hex((await key.extractPublicKey()).bytes);
  });
  tearDownAll(() => testOnlyModelSigningKey = null);
  setUp(() async {
    support = await Directory.systemTemp.createTemp('review9b_signed');
    files = Directory('${support.path}/files')..createSync();
  });
  tearDown(() => support.delete(recursive: true));

  Future<(List<int>, List<int>)> signedList(String content, {int serial = 2}) async {
    final bytes = utf8.encode(jsonEncode({'schema': 1, 'serial': serial, 'issued': '2026-11-16', 'models': [
      {'sha256': _sum(content), 'size': utf8.encode(content).length, 'tier': 'standard', 'prompt_version': appPromptVersion,
        'context': 8192, 'family': 'gemma4', 'name': 'therapist-new.gguf'}], 'revoked': []}));
    final sig = await DartEd25519().sign(bytes, keyPair: key);
    return (bytes, utf8.encode('${base64.encode(sig.bytes)}\n'));
  }

  List<(String, Stream<List<int>>)> picks(String content, (List<int>, List<int>) list) => [
        ('therapist-new.gguf', Stream.value(utf8.encode(content))),
        ('therapist-new.sha256', Stream.value(utf8.encode('${_sum(content)}  therapist-new.gguf\n'))),
        (modelListName, Stream.value(list.$1)),
        (modelSignatureName, Stream.value(list.$2)),
      ];

  test('9B-16: when the signed list cannot be kept, a usable model is still there', () async {
    // the model in use: a trusted Standard model with its checksum line, as an earlier import left it
    const old = 'the standard model in use';
    testOnlyTrustedModels.add(_sum(old));
    addTearDown(() => testOnlyTrustedModels.remove(_sum(old)));
    File('${files.path}/model-standard.gguf').writeAsStringSync(old);
    File('${files.path}/model-standard.sha256').writeAsStringSync('${_sum(old)}  model-standard.gguf\n');
    expect(await (await ModelFile.find(files))!.verify(File('${support.path}/check0.txt')), isTrue, reason: 'set-up');

    // keeping the list will fail (here its part file's name is taken; on a device: a refused write, or a kill)
    Directory('${support.path}/$keptListName.part').createSync();
    final msg = await importModelFiles(picks('a newer standard model', await signedList('a newer standard model')), files);
    expect(msg, contains('could not be kept'), reason: 'set-up: the list keeping failed');

    final found = await ModelFile.find(files);
    expect(found != null && await found.verify(File('${support.path}/check1.txt')), isTrue,
        reason: 'no usable model is left: the old one was replaced, and the new one is paired with the old checksum '
            '(${File('${files.path}/model-standard.sha256').readAsStringSync().trim()})');
  });

  test('9B-17: after Delete everything, a damaged floor file is rebuilt from the kept list, so lists work again',
      () async {
    // a list (number 2) accepted earlier, kept beside the floor
    const first = 'a standard model on list 2';
    expect(await importModelFiles(picks(first, await signedList(first)), files), startsWith('Copied'));
    File('${support.path}/$serialFloorName').writeAsStringSync('\u0000\u0000garbled'); // damaged, as by a bad write
    await wipeAppFolders(support: support, temp: Directory('${support.path}/tmp')..createSync());
    final list = await signedList('a newer standard model', serial: 5);
    final (checked, why) = await checkPickedList(list.$1, list.$2, files);
    expect(checked, isNotNull, reason: 'every list is refused until Solace is reinstalled: $why');
    expect(File('${support.path}/$serialFloorName').readAsStringSync().trim(), '2', reason: 'rebuilt from the kept list');
    final older = await signedList('an older model', serial: 1);
    expect((await checkPickedList(older.$1, older.$2, files)).$2, olderList(1, 2),
        reason: 'the rebuilt floor still refuses an older list');
  });

  test('9B-17: with no checked list to rebuild it from, a damaged floor keeps refusing lists (fail closed)', () async {
    File('${support.path}/$serialFloorName').writeAsStringSync('\u0000\u0000garbled');
    await wipeAppFolders(support: support, temp: Directory('${support.path}/tmp')..createSync());
    final list = await signedList('a newer standard model', serial: 5);
    expect((await checkPickedList(list.$1, list.$2, files)).$2, floorUnreadable);
    expect(floorUnreadable, contains('reinstalling'));
  });
}
