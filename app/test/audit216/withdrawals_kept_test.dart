// Audit 216 fix (9A-12): the built-in models a signed list withdraws are kept on their own beside the rollback floor
// (core/model_manifest.dart WithdrawnKeep), so a kept list that is damaged or missing never brings one back. These
// check the record itself: written with the list, kept by Delete everything, rebuilt with a damaged floor (9B-17) and
// after an update from a version without it, and failing closed when it is damaged and nothing can rebuild it.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
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
(String, Stream<List<int>>) _file(String name, String text) => (name, Stream.value(utf8.encode(text)));
(String, Stream<List<int>>) _bytes(String name, List<int> b) => (name, Stream.value(b));

late SimpleKeyPair _key;

Future<(List<int>, List<int>)> _signed(List<Map<String, Object?>> models, {required int serial,
    List<String> revoked = const []}) async {
  final bytes = utf8.encode(
      jsonEncode({'schema': 1, 'serial': serial, 'issued': '2026-11-16', 'models': models, 'revoked': revoked}));
  final sig = await DartEd25519().sign(bytes, keyPair: _key);
  return (bytes, utf8.encode('${base64.encode(sig.bytes)}\n'));
}

Map<String, Object?> _entry(String content, {String tier = 'standard'}) => {'sha256': _sum(content),
    'size': utf8.encode(content).length, 'tier': tier, 'prompt_version': appPromptVersion, 'context': 8192, 'family': 'gemma4',
    'name': 'therapist-new.gguf'};

List<(String, Stream<List<int>>)> _picks(String name, String content, [(List<int>, List<int>)? list]) => [
      _file(name, content),
      _file(name.replaceAll('.gguf', '.sha256'), '${_sum(content)}  $name\n'),
      if (list != null) ...[_bytes(modelListName, list.$1), _bytes(modelSignatureName, list.$2)],
    ];

void main() {
  late Directory support, files;
  const unsafe = 'built-in weights, withdrawn (audit 216 fix)', other = 'the other built-in weights';
  final builtIn = _sum(unsafe), otherBuiltIn = _sum(other);
  setUpAll(() async {
    _key = await DartEd25519().newKeyPair();
    testOnlyModelSigningKey = _hex((await _key.extractPublicKey()).bytes);
    testOnlyTrustedModels.addAll([builtIn, otherBuiltIn]); // stand in for the two models in trustedModels
  });
  tearDownAll(() {
    testOnlyModelSigningKey = null;
    testOnlyTrustedModels.removeAll([builtIn, otherBuiltIn]);
  });
  setUp(() async {
    support = await Directory.systemTemp.createTemp('audit216_withdrawals');
    files = Directory('${support.path}/files');
  });
  tearDown(() => support.delete(recursive: true));

  File record() => File('${support.path}/$withdrawnName');
  File floor() => File('${support.path}/$serialFloorName');
  File keptSig() => File('${support.path}/$keptSignatureName');
  File keptList() => File('${support.path}/$keptListName');

  /// The built-in Standard model on the device, then list 2 (a new Light model) withdrawing it and a model only listed.
  Future<(List<int>, List<int>)> withdraw() async {
    expect(await importModelFiles(_picks('old.gguf', unsafe), files), startsWith('Copied the Standard'));
    final list = await _signed([_entry('new light', tier: 'light')], serial: 2,
        revoked: [builtIn, _sum('a listed model, withdrawn')]);
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    return list;
  }

  test('the record is written with the list: only the built-in models it withdraws', () async {
    await withdraw();
    expect(record().readAsStringSync(), 'withdrawn 1\n$builtIn\n');
    expect(await WithdrawnKeep.beside(files).read(), {builtIn});
  });

  test('Delete everything keeps the record, so a later damaged list still refuses the withdrawn model', () async {
    await withdraw();
    await wipeAppFolders(support: support, temp: support);
    expect(record().existsSync(), isTrue, reason: 'kept beside the floor');
    keptList().deleteSync();
    keptSig().deleteSync();
    expect(await importModelFiles(_picks('old.gguf', unsafe), files), withdrawn);
    expect((await KeptModelList.read(files)).note, keptListFailed);
  });

  test('a damaged kept list: the withdrawn built-in model is refused, one not withdrawn is still trusted', () async {
    await withdraw();
    keptSig().writeAsStringSync('damaged\n');
    final kept = await KeptModelList.read(files);
    expect(kept.list, isNull);
    expect(kept.whyNot(builtIn), withdrawn);
    expect(kept.whyNot(otherBuiltIn), isNull, reason: 'a built-in model the list did not withdraw is still trusted');
    expect(kept.whyNot(_sum('new light')), isNotNull, reason: 'a model only on the lost list needs the list');
  });

  test('a damaged floor is rebuilt from the checked list, and the withdrawals come back with it (9B-17)', () async {
    await withdraw();
    floor().writeAsStringSync('garbled');
    record().deleteSync();
    final kept = await KeptModelList.read(files);
    expect(kept.note, isNull);
    expect(floor().readAsStringSync().trim(), '2');
    expect(await WithdrawnKeep.beside(files).read(), {builtIn}, reason: 'rewritten from the checked list');
    // and they now hold without the list too
    keptSig().deleteSync();
    expect((await KeptModelList.read(files)).whyNot(builtIn), withdrawn);
  });

  test('an update from a version without the record: written from the kept list at the next start', () async {
    await withdraw();
    record().deleteSync(); // as kept by d583360, which had no record
    expect((await KeptModelList.read(files)).note, isNull);
    expect(record().readAsStringSync(), 'withdrawn 1\n$builtIn\n');
  });

  test('a damaged record is rebuilt from a checked list; with none, no built-in model is trusted (fail closed)',
      () async {
    final list = await withdraw();
    for (final bad in ['withdrawn 2\n$builtIn\n', 'withdrawn 1\nnot a sum\n', '', 'x' * 70000]) {
      record().writeAsStringSync(bad);
      expect(() => WithdrawnKeep.beside(files).read(), throwsA(isA<WithdrawnUnreadable>()), reason: bad);
    }
    record().writeAsStringSync('withdrawn 2\n$builtIn\n'); // cut short or changed
    expect((await KeptModelList.read(files)).note, isNull);
    expect(await WithdrawnKeep.beside(files).read(), {builtIn}, reason: 'rebuilt from the checked list');
    // damaged, with no checked list to rebuild it from: every built-in model is refused, and Settings says so
    record().writeAsStringSync('withdrawn 9\n');
    keptSig().deleteSync();
    final kept = await KeptModelList.read(files);
    expect(kept.note, keptWithdrawalsUnreadable);
    expect(kept.whyNot(otherBuiltIn), withdrawn);
    expect(await ModelFile.findAll(files), isEmpty);
    // adding the files again with the list puts it right
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    final again = await KeptModelList.read(files);
    expect(again.note, isNull);
    expect(again.whyNot(otherBuiltIn), isNull);
    expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-light.gguf']);
  });

  test('a newer list that no longer withdraws a model governs (the owner may take a withdrawal back)', () async {
    await withdraw();
    final three = await _signed([_entry('new light', tier: 'light')], serial: 3);
    // the old Standard file still on the device is trusted again at once, so it is the one named
    expect(await importModelFiles(_picks('n.gguf', 'new light', three), files), startsWith('Copied the Standard'));
    expect(await WithdrawnKeep.beside(files).read(), isEmpty);
    expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-standard.gguf', 'model-light.gguf']);
  });
}
