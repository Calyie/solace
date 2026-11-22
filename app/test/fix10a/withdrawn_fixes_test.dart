// Round 10 review A fix R10A-07 (beyond the reviewer's proof test in test/review10a/): a missing record of withdrawn
// built-in models fails closed only where a list was accepted on this device (the floor above 0 or damaged, or a kept
// list there); a first run is not affected, and adding the files again with the list restores the models it did not
// withdraw.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
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
  const unsafe = 'built-in weights, withdrawn (fix 10a)', other = 'the other built-in weights (fix 10a)';
  final builtIn = _sum(unsafe), otherBuiltIn = _sum(other);
  setUpAll(() async {
    _key = await DartEd25519().newKeyPair();
    testOnlyModelSigningKey = _hex((await _key.extractPublicKey()).bytes);
    testOnlyTrustedModels.addAll([builtIn, otherBuiltIn]);
  });
  tearDownAll(() {
    testOnlyModelSigningKey = null;
    testOnlyTrustedModels.removeAll([builtIn, otherBuiltIn]);
  });
  setUp(() async {
    support = await Directory.systemTemp.createTemp('fix10a_withdrawn');
    files = Directory('${support.path}/files');
  });
  tearDown(() => support.delete(recursive: true));

  test('a first run (no floor, no list, no record): the built-in models are trusted and nothing is said', () async {
    final kept = await KeptModelList.read(files);
    expect(kept.note, isNull);
    expect(kept.whyNot(builtIn), isNull);
    expect(File('${support.path}/$withdrawnName').existsSync(), isFalse, reason: 'nothing is written');
  });

  test('a first list whose import was cut short before its record and floor: fails closed, and says so', () async {
    final list = await _signed([_entry('new light', tier: 'light')], serial: 1, revoked: [builtIn]);
    await support.create(recursive: true);
    File('${support.path}/$keptListName').writeAsBytesSync(list.$1); // the signature was never written
    final kept = await KeptModelList.read(files);
    expect(kept.note, keptWithdrawalsUnreadable);
    expect(kept.whyNot(otherBuiltIn), withdrawn, reason: 'no built-in model is trusted until the list is added');
  });

  test('failed closed, then the files added again with the list: only the withdrawn model stays refused', () async {
    expect(await importModelFiles(_picks('old.gguf', unsafe), files), startsWith('Copied the Standard'));
    final list = await _signed([_entry('new light', tier: 'light')], serial: 2, revoked: [builtIn]);
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    File('${support.path}/$keptSignatureName').deleteSync();
    File('${support.path}/$withdrawnName').deleteSync();
    expect((await KeptModelList.read(files)).whyNot(otherBuiltIn), withdrawn, reason: 'fails closed');
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    final kept = await KeptModelList.read(files);
    expect(kept.note, isNull);
    expect(kept.whyNot(builtIn), withdrawn);
    expect(kept.whyNot(otherBuiltIn), isNull);
    expect(File('${support.path}/$withdrawnName').readAsStringSync(), 'withdrawn 1\n$builtIn\n');
  });
}
