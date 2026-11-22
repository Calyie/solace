// The gateway checks the model with the app's own trust code before serving (src/model_check.dart): the .sha256 list,
// then built in, signed (with a test key here, as test/signed_models_test.dart does in the app), or named by the
// server's owner in accept_unsigned. A withdrawn model, a model for another app version, a damaged file or a list not
// signed by the key are refused.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:test/test.dart';

import '../../app/lib/core/formats.dart' show appPromptVersion, contextTokens;
import '../../app/lib/core/trusted.dart' show testOnlyModelSigningKey;
import '../src/model_check.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
String sumOf(List<int> bytes) => hex(const DartSha256().hashSync(bytes).bytes);

void main() {
  late Directory dir;
  late SimpleKeyPair key, other;
  final content = utf8.encode('not really a model, but a file with a checksum');
  final sum = sumOf(content);

  setUpAll(() async {
    key = await DartEd25519().newKeyPair();
    other = await DartEd25519().newKeyPair();
    testOnlyModelSigningKey = hex((await key.extractPublicKey()).bytes);
  });
  tearDownAll(() => testOnlyModelSigningKey = null);
  setUp(() async => dir = await Directory.systemTemp.createTemp('solace_home_model'));
  tearDown(() => dir.delete(recursive: true));

  Future<File> model({String name = 'therapist-new-e4b.gguf', bool list = true, String? listedSum}) async {
    final f = File('${dir.path}/$name')..writeAsBytesSync(content);
    if (list) File('${dir.path}/${name.replaceAll('.gguf', '.sha256')}').writeAsStringSync('${listedSum ?? sum}  $name\n');
    return f;
  }

  Future<void> signedList({List<String> revoked = const [], String prompt = appPromptVersion,
      SimpleKeyPair? by, int? size}) async {
    final bytes = utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': '2026-11-19', 'models': [
      {'sha256': sum, 'size': size ?? content.length, 'tier': 'standard', 'prompt_version': prompt,
        'context': contextTokens, 'family': 'gemma4', 'name': 'therapist-new-e4b.gguf'},
    ], 'revoked': revoked}));
    final sig = await DartEd25519().sign(bytes, keyPair: by ?? key);
    File('${dir.path}/solace-models.json').writeAsBytesSync(bytes);
    File('${dir.path}/solace-models.json.sig').writeAsStringSync('${base64.encode(sig.bytes)}\n');
  }

  test('a model on the signed list is served, by its checksum and size', () async {
    await signedList();
    final m = await checkModel(await model());
    expect(m.sha256, sum);
    expect(m.trustedBy, 'signed');
    expect(m.light, isFalse);
    expect(m.toJson()['tier'], 'standard');
  });

  test('without a .sha256 list naming it, or with one that does not match, nothing is served', () async {
    await signedList();
    await expectLater(checkModel(await model(list: false)), throwsA(isA<ModelRefused>()));
    await expectLater(checkModel(await model(listedSum: 'a' * 64)),
        throwsA(predicate((e) => '$e'.contains('does not match'))));
  });

  test('a model neither built in nor signed is refused unless the server\'s owner accepted its checksum', () async {
    final f = await model();
    await expectLater(checkModel(f), throwsA(predicate((e) => '$e'.contains('accept_unsigned'))));
    final m = await checkModel(f, acceptUnsigned: [sum]);
    expect(m.trustedBy, 'accepted');
  });

  test('a list signed by another key, a withdrawn model, another app version or the wrong size is refused', () async {
    final f = await model();
    await signedList(by: other);
    await expectLater(checkModel(f), throwsA(predicate((e) => '$e'.contains('refused'))));
    await signedList(revoked: [sum]);
    await expectLater(checkModel(f, acceptUnsigned: [sum]), throwsA(predicate((e) => '$e'.contains('withdrawn'))));
    await signedList(prompt: 'v0');
    await expectLater(checkModel(f), throwsA(isA<ModelRefused>()));
    await signedList(size: content.length + 1);
    await expectLater(checkModel(f), throwsA(isA<ModelRefused>()));
  });

  test('the checksum is the file\'s SHA-256, with or without the system\'s tool', () async {
    final f = await model();
    expect(await sha256OfFile(f), sum);
  });
}
