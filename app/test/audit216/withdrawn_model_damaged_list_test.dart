// Audit 216, auditor X, 9A-12 ("A withdrawn built-in model was trusted again after Delete everything or a failed
// kept-list check", tracker: Fixed, to verify).
//
// The Delete everything half is fixed: the newest accepted list is kept beside the floor, outside files/, and Delete
// everything keeps it (review9a/revocation_lost_test.dart first test). The second half is not: when the kept list or its
// signature is missing or fails its check while the floor shows a list was accepted, KeptModelList.read returns no list,
// whyNotTrusted gets none, and every built-in model is trusted again, the withdrawn one included. That was a choice
// made by the lead (docs/DECISIONS.md 2026-11-16, "the lead's choice: never leave the device without a model"; SECURITY.md
// section 7), not one of the owner's recorded decisions, and the existing proof test was rewritten to assert it.
//
// Scenario: the owner withdraws the built-in Standard model (list 2, with a new Light model). The old Standard file is
// still on the device. model_list.json.sig beside the floor is then lost (a damaged write, a partial restore, or on
// Linux any program of the same user). At the next start the withdrawn Standard model is the first one found, and it
// is the one loaded, ahead of the Light model the owner meant to replace it.
//
// This test asserts the SAFE behaviour (a withdrawal accepted on this device keeps holding), so it fails on c7f6680.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
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
  const unsafe = 'built-in weights, later withdrawn (audit 216 X)';
  final builtIn = _sum(unsafe);
  setUpAll(() async {
    _key = await DartEd25519().newKeyPair();
    testOnlyModelSigningKey = _hex((await _key.extractPublicKey()).bytes);
    testOnlyTrustedModels.add(builtIn); // stands in for a model in trustedModels
  });
  tearDownAll(() {
    testOnlyModelSigningKey = null;
    testOnlyTrustedModels.remove(builtIn);
  });
  setUp(() async {
    support = await Directory.systemTemp.createTemp('audit216x_withdrawn');
    files = Directory('${support.path}/files');
  });
  tearDown(() => support.delete(recursive: true));

  test('9A-12: a withdrawn built-in model is not loaded again when the kept list beside the floor is damaged',
      () async {
    expect(await importModelFiles(_picks('old.gguf', unsafe), files), startsWith('Copied the Standard'));
    final list = await _signed([_entry('new light', tier: 'light')], serial: 2, revoked: [builtIn]);
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-light.gguf'],
        reason: 'precondition: while the kept list is readable the withdrawal holds');

    File('${support.path}/$keptSignatureName').deleteSync(); // the kept signature lost or damaged

    final found = (await ModelFile.findAll(files)).map((m) => m.name).toList();
    expect(found, isNot(contains('model-standard.gguf')),
        reason: 'the model the owner withdrew is trusted again and found first: $found');
  });
}
