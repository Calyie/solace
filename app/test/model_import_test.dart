// The model reaches the device with no network: picked files are copied into the app's folder and found only with
// their checksum list (core/model_import.dart).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/model_import.dart';
import 'package:solace/core/trusted.dart';

(String, Stream<List<int>>) file(String name, String text) => (name, Stream.value(utf8.encode(text)));

/// The real SHA-256 of [text] (the import now checks the copy before it replaces anything, OWASP OW-M2-1).
String sumOf(String text) =>
    const DartSha256().hashSync(utf8.encode(text)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late Directory docs;
  setUp(() async => docs = await Directory.systemTemp.createTemp('model_import'));
  tearDown(() => docs.delete(recursive: true));

  test('the phone file and its list are copied and found', () async {
    final sum = sumOf('weights');
    testOnlyTrustedModels.add(sum); // a stand-in file; the app trusts only the trained ones (core/trusted.dart)
    final msg = await importModelFiles(
        [file('therapist-e4b-Q4_K_M-imat.gguf', 'weights'), file('therapist-e4b.sha256', '$sum  therapist-e4b-Q4_K_M-imat.gguf\n')],
        docs);
    expect(msg, startsWith('Copied the Standard model'));
    // kept under a neutral name with its own one-line list (F-20): no file name says what the app is for
    expect(File('${docs.path}/model-standard.gguf').readAsStringSync(), 'weights');
    expect(File('${docs.path}/model-standard.sha256').readAsStringSync(), '$sum  model-standard.gguf\n');
    expect(docs.listSync().map((e) => e.uri.pathSegments.last), isNot(contains(contains('therapist'))));
    expect((await ModelFile.find(docs))!.sha256, sum);
    expect(docs.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
  });

  test('without its list the file is not copied', () async {
    final msg = await importModelFiles([file('therapist-e4b-Q4_K_M-imat.gguf', 'weights')], docs);
    expect(msg, contains('.sha256 list too'));
    expect(docs.listSync(), isEmpty);
  });

  test('a list that does not name the file means it is not used', () async {
    final msg = await importModelFiles([file('other.gguf', 'x'), file('therapist-e4b.sha256', '${'0' * 64}  therapist-e4b-Q4_K_M-imat.gguf\n')], docs);
    expect(msg, contains('not in the .sha256 list'));
    expect(await ModelFile.find(docs), isNull);
    expect(docs.listSync(), isEmpty, reason: 'nothing is copied for a file that would not be used');
  });

  test('a listed file this version does not trust is not copied either', () async {
    final msg = await importModelFiles([file('x.gguf', 'x'), file('x.sha256', '${'1' * 64}  x.gguf\n')], docs);
    expect(msg, contains('not a model file this version of Solace was built for'));
    expect(docs.listSync(), isEmpty);
  });

  test('picked names that could climb out of the folder are refused, and nothing is written (F-15)', () async {
    for (final bad in ['../../shared_prefs/x.sha256', r'..\\x.gguf', 'a/b.gguf', '.hidden.gguf', 'x\u0000.gguf', '..gguf']) {
      expect(safeName(bad), isNull, reason: bad);
      final msg = await importModelFiles([file(bad, 'x'), file('ok.sha256', '${'0' * 64}  ok.gguf\n')], docs);
      expect(msg, contains('name Solace cannot use'), reason: bad);
    }
    expect(docs.listSync(), isEmpty);
    expect(safeName('therapist-e4b-Q5_K_M-imat.gguf'), 'therapist-e4b-Q5_K_M-imat.gguf');
  });

  test('a list far too large is refused before it is read whole (F-14)', () async {
    final msg = await importModelFiles([file('m.gguf', 'x'), file('m.sha256', 'a' * 70000)], docs);
    expect(msg, contains('far too large'));
  });

  test('the iPhone drop zone: a trusted model and the bundle move into the private folder (PLAT-1)', () async {
    final sum = sumOf('weights');
    testOnlyTrustedModels.add(sum);
    final inbox = await Directory.systemTemp.createTemp('inbox');
    File('${inbox.path}/therapist-e2b-Q5_K_M-imat.gguf').writeAsStringSync('weights');
    File('${inbox.path}/therapist-e2b-Q5_K_M-imat.sha256').writeAsStringSync('$sum  therapist-e2b-Q5_K_M-imat.gguf\n');
    File('${inbox.path}/notes.txt').writeAsStringSync('mine');
    final msg = await importInbox(inbox, docs);
    expect(msg, contains('private folder'));
    expect((await ModelFile.find(docs))!.sha256, sum);
    expect(inbox.listSync().map((e) => e.uri.pathSegments.last), ['notes.txt'], reason: 'only what it used is moved');
    expect(await importInbox(inbox, docs), isNull, reason: 'nothing more to move');
    await inbox.delete(recursive: true);
  });

  test('other files are ignored', () async {
    expect(await importModelFiles([file('notes.txt', 'x')], docs), contains('ends in .gguf'));
  });

  /// A .zip at [to] holding [files] (name -> text); [link] adds a symbolic link entry.
  String zipOf(Directory dir, Map<String, String> files, {String? link}) {
    final a = Archive();
    files.forEach((n, t) => a.addFile(ArchiveFile.string(n, t)));
    if (link != null) a.addFile(ArchiveFile.symlink(link, '/etc/passwd'));
    final path = '${dir.path}/bundle.zip';
    File(path).writeAsBytesSync(ZipEncoder().encode(a));
    return path;
  }

  test('the voice and safety bundle unpacks into voice/ and safety/', () async {
    final src = await Directory.systemTemp.createTemp('bundle');
    final zip = zipOf(src, {'voice/voice.sha256': 'x', 'voice/kokoro-multi-lang-v1_0/model.onnx': 'm',
        'safety/safety.int8.onnx': 's', 'safety/safety.sha256': 'y'});
    expect(await importBundle(zip, docs), contains('not the voice and safety bundle this version'),
        reason: 'only the exact published bundle is opened (OWASP OW-M4-2)');
    testOnlyTrustedBundles.add(await sha256Of(File(zip)));
    final msg = await importBundle(zip, docs);
    expect(msg, startsWith('Added 4'));
    expect(File('${docs.path}/voice/kokoro-multi-lang-v1_0/model.onnx').readAsStringSync(), 'm');
    expect(File('${docs.path}/safety/safety.int8.onnx').existsSync(), isTrue);
    expect(docs.listSync(recursive: true).where((e) => e.path.endsWith('.part')), isEmpty);
    await src.delete(recursive: true);
  });

  for (final (what, files, link) in [
    ('a path that climbs out', {'voice/../../evil.txt': 'x', 'voice/a.txt': 'a'}, null),
    ('a folder outside the bundle', {'other/a.txt': 'x', 'voice/a.txt': 'a'}, null),
    ('a link', {'voice/a.txt': 'a'}, 'voice/link'),
  ]) {
    test('an archive with $what is refused and nothing is written', () async {
      final src = await Directory.systemTemp.createTemp('bundle');
      final zip = zipOf(src, files, link: link);
      testOnlyTrustedBundles.add(await sha256Of(File(zip))); // past the pin, so the entry checks themselves are tested
      final msg = await importBundle(zip, docs);
      expect(msg, contains('nothing was added'));
      expect(docs.listSync(recursive: true), isEmpty);
      expect(File('${src.parent.path}/evil.txt').existsSync(), isFalse);
      await src.delete(recursive: true);
    });
  }

  // The real bundle through the app's own importer (BUNDLE_ZIP names it; skipped otherwise): every file it unpacks must
  // match the .sha256 lists inside it, which is what the app checks before it uses the voice or the classifier.
  test('the real voice and safety bundle unpacks and every file matches its list', () async {
    final out = Directory(Platform.environment['BUNDLE_OUT']!)..createSync(recursive: true);
    expect(await importBundle(Platform.environment['BUNDLE_ZIP']!, out), startsWith('Added'));
    for (final list in ['voice/voice.sha256', 'safety/safety.sha256']) {
      final dir = File('${out.path}/$list').parent;
      for (final line in File('${out.path}/$list').readAsLinesSync()) {
        final m = RegExp(r'^([0-9a-f]{64})\s+\*?(.+)$').firstMatch(line.trim());
        if (m == null) continue;
        final f = File('${dir.path}/${m.group(2)}');
        expect(await ModelFile(f, m.group(1)!).verify(File('${out.path}/check_${f.uri.pathSegments.last}.txt')), isTrue,
            reason: m.group(2));
      }
    }
  }, skip: Platform.environment['BUNDLE_ZIP'] == null ? 'BUNDLE_ZIP not set' : null);

  test('a listed model file this version was not built for is refused (security review 2026-11-14, SC-2)', () async {
    const sum = 'b3f1c2d4e5b6a7980123456789abcdef0123456789abcdef0123456789abcdef';
    final msg = await importModelFiles(
        [file('therapist-e4b-Q5_K_M-imat.gguf', 'swapped'), file('therapist-e4b.sha256', '$sum  therapist-e4b-Q5_K_M-imat.gguf\n')],
        docs);
    expect(msg, contains('not a model file this version of Solace was built for'));
    expect(await ModelFile.find(docs), isNull);
    expect(isTrustedModel(trustedModels.keys.first), isTrue);
  });
}
