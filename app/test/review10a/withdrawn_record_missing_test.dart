// Review round 10 A, R10A-07 (9A-12): a MISSING record of withdrawn models is read as "nothing withdrawn", although the
// floor shows a list was accepted, so a withdrawn built-in model is trusted again (fail open).
//
// keepModelList always writes `model_withdrawn` with the list, "withdrawn 0" included (core/model_manifest.dart:325-326,
// WithdrawnKeep.write), so on a device that accepted any list under this version the record can only be missing by
// loss. But _withdrawals (model_manifest.dart:405-426) treats a missing record like an empty one when no usable list
// can rebuild it: `saved == null ... ? Withdrawals.none`. Only a DAMAGED record fails closed (allBuiltIn). So when the
// kept list is unusable (damaged or missing signature: the 9A-12 case itself) and the record is missing too (lost with
// it, an update from d583360 or earlier where the kept list was already damaged at the first start of this version,
// a partial restore of the support folder), the withdrawn built-in model is trusted and loaded again, while Settings
// says the opposite: keptListFailed, "never one that list withdrew" (and keptFloorUnreadable, "never one withdrawn on
// this device", when the floor is damaged as well).
//
// The floor (> 0) is right there to tell "a list was accepted here" from "never any list". The test asserts the SAFE
// behaviour (the withdrawn built-in model is refused), so it fails on 2f3ce71.
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
  const unsafe = 'built-in weights, withdrawn (review 10 A)';
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
    support = await Directory.systemTemp.createTemp('r10a_withdrawn');
    files = Directory('${support.path}/files');
  });
  tearDown(() => support.delete(recursive: true));

  Future<void> withdrawBuiltIn() async {
    expect(await importModelFiles(_picks('old.gguf', unsafe), files), startsWith('Copied the Standard'));
    final list = await _signed([_entry('new light', tier: 'light')], serial: 2, revoked: [builtIn]);
    expect(await importModelFiles(_picks('n.gguf', 'new light', list), files), startsWith('Copied the Light'));
    expect(File('${support.path}/$withdrawnName').readAsStringSync(), 'withdrawn 1\n$builtIn\n');
  }

  test('R10A-07: kept list unusable and the record missing: the withdrawn built-in model stays refused', () async {
    await withdrawBuiltIn();
    File('${support.path}/$keptSignatureName').deleteSync(); // the kept list unusable (the 9A-12 case)
    File('${support.path}/$withdrawnName').deleteSync(); // and the record lost with it
    final kept = await KeptModelList.read(files);
    expect(File('${support.path}/$serialFloorName').readAsStringSync().trim(), '2',
        reason: 'the floor shows a list was accepted on this device');
    // Fix round (R10A-07): the note was keptListFailed ("uses only the models built into it, and never one that list
    // withdrew"), which described the old behaviour. A missing record now fails closed, as a damaged one does, so
    // Settings says that no built-in model is used for now: the note the review's fix direction names.
    expect(kept.note, keptWithdrawalsUnreadable);
    expect(kept.whyNot(builtIn), isNotNull,
        reason: 'Settings says "${kept.note}", yet the withdrawn built-in model is trusted again');
    expect((await ModelFile.findAll(files)).map((m) => m.name), isNot(contains('model-standard.gguf')));
  });

  test('R10A-07: the floor damaged too: "never one withdrawn on this device" holds', () async {
    await withdrawBuiltIn();
    File('${support.path}/$keptSignatureName').deleteSync();
    File('${support.path}/$withdrawnName').deleteSync();
    File('${support.path}/$serialFloorName').writeAsStringSync('garbled');
    final kept = await KeptModelList.read(files);
    // Fix round (R10A-07): keptFloorUnreadable became the note for both records being unusable, as for a damaged
    // record (the fail-closed note; see the test above)
    expect(kept.note, keptFloorAndWithdrawalsUnreadable);
    expect(kept.whyNot(builtIn), isNotNull, reason: 'Settings says "${kept.note}"');
  });

  test('control: a DAMAGED record with the list unusable fails closed, as claimed', () async {
    await withdrawBuiltIn();
    File('${support.path}/$keptSignatureName').deleteSync();
    File('${support.path}/$withdrawnName').writeAsStringSync('withdrawn 9\n');
    expect((await KeptModelList.read(files)).whyNot(builtIn), withdrawn);
  });
}
