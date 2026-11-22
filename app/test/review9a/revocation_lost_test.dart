// Round 9 review A, signed models (c680eb7), 9A-12: a signed list can withdraw (revoke) a built-in model, and the docs
// say "Revocation in a list also untrusts the built-in models". But the withdrawal exists only inside the list kept in
// the model files folder (files/solace-models.json). Whenever that list is not there or fails its check, whyNotTrusted
// is given no list and every built-in model is trusted again (core/model_manifest.dart whyNotTrusted: "if (list ==
// null) ... isTrustedModel"), the withdrawn one included:
// - Delete everything deletes files/ (the kept list with it) and keeps only the number floor (core/app_files.dart), so
//   the withdrawn built-in model can be added again with no list at all and is used;
// - a kept list or signature that is damaged, missing or cannot be read at a start (KeptModelList.read: keptListFailed,
//   keptListIncomplete, keptFloorUnreadable) makes a withdrawn built-in model still in files/ the one that loads.
// The serial floor stops an older list, but not the absence of one. These tests assert the SAFE behaviour (a
// withdrawal, once accepted on this device, keeps holding), so they fail while the finding stands.
//
// Fixed (feat/signed-models after c680eb7): the newest accepted list is kept beside the floor in the support folder,
// not in files/, so Delete everything keeps it and its withdrawals hold (first test, unchanged). The second test was
// written for the old place of the list (files/). It was then changed to the lead's policy for a kept list that is
// missing or fails its check while the floor shows one was accepted (the built-in models stayed trusted, the withdrawn
// one included). Audit 216 (9A-12, partly fixed) removed that policy on purpose: the withdrawn built-in models are kept
// on their own beside the floor, so a damaged kept list still refuses them (fail closed). The second test now asserts
// that: the withdrawn model is not loaded, Settings says plainly the list needs adding again, and adding the files
// again with the list restores the Light model.
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
  final builtIn = _sum('built-in weights, later found unsafe');
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
    support = await Directory.systemTemp.createTemp('r9a_revoke');
    files = Directory('${support.path}/files');
  });
  tearDown(() => support.delete(recursive: true));

  /// The owner withdraws the built-in model with list number 2, which brings a new Light model.
  Future<void> withdraw() async {
    expect(await importModelFiles(_picks('old.gguf', 'built-in weights, later found unsafe'), files),
        startsWith('Copied the Standard'));
    final list = await _signed([_entry('new light', tier: 'light')], serial: 2, revoked: [builtIn]);
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-light.gguf'],
        reason: 'precondition: the withdrawn built-in model is passed over');
    expect(await importModelFiles(_picks('old.gguf', 'built-in weights, later found unsafe'), files), withdrawn,
        reason: 'precondition: and cannot be added again');
  }

  test('9A-12: after Delete everything the withdrawn built-in model cannot be added and used again', () async {
    await withdraw();
    await wipeAppFolders(support: support); // Delete everything: files/ goes, the floor (2) stays
    expect(File('${support.path}/$serialFloorName').readAsStringSync().trim(), '2');
    final said = await importModelFiles(_picks('old.gguf', 'built-in weights, later found unsafe'), files);
    expect(said, withdrawn,
        reason: 'the model the owner withdrew is copied again with no list ("$said") and is the one loaded: '
            '${(await ModelFile.findAll(files)).map((m) => m.name)}');
  });

  test('9A-12: losing the model files folder never loses a withdrawal; a damaged kept list is said, and re-adding '
      'the files with the list restores it', () async {
    await withdraw();
    // the withdrawn file is still on the device (it was the Standard model; the new one is Light)
    expect(File('${files.path}/model-standard.gguf').existsSync(), isTrue);
    expect(File('${files.path}/$modelListName').existsSync() || File('${files.path}/$modelSignatureName').existsSync(),
        isFalse, reason: 'no list is kept with the model files, so nothing there can lose a withdrawal');
    // the kept list itself damaged at a start (beside the floor): the withdrawal still holds (audit 216), plainly said
    File('${support.path}/$keptSignatureName').deleteSync();
    final kept = await KeptModelList.read(files);
    expect(kept.note, keptListFailed);
    expect(kept.note, contains('Add the model files again'));
    expect((await ModelFile.findAll(files)).map((m) => m.name), isEmpty,
        reason: 'the withdrawn built-in model stays withdrawn, and the Light model needs its list');
    expect(await importModelFiles(_picks('old.gguf', 'built-in weights, later found unsafe'), files), withdrawn,
        reason: 'and it cannot be added again without the list either');
    // adding the files again with the list restores the withdrawal at once
    final list = await _signed([_entry('new light', tier: 'light')], serial: 2, revoked: [builtIn]);
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    expect((await KeptModelList.read(files)).note, isNull);
    expect((await ModelFile.findAll(files)).map((m) => m.name), ['model-light.gguf']);
  });
}
