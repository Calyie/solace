// The end-to-end call test's seams (core/test_seams.dart: speech handed to the call, the voice's audio kept) can never
// be reached in a release build, and are off in any build made without the define (lead, 2026-11-16).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/test_seams.dart';

void main() {
  test('off in a build made without the define: nothing can stand in for the person', () async {
    expect(testSeams, isFalse);
    expect(() => CallSeams.hear('I want to talk about work.'), throwsStateError);
    expect(await CallSeams.nextHeard(Future<void>.value()), isNull);
  });

  test('a release build can never turn them on: the switch is folded with kReleaseMode, a constant', () {
    final source = File('lib/core/test_seams.dart').readAsStringSync();
    expect(source, contains("const testSeams = !kReleaseMode && bool.fromEnvironment('SOLACE_TEST_SEAMS');"));
  });

  test('no build or release script passes the define', () {
    final root = Directory('..');
    final scripts = [
      for (final d in ['tools', 'scripts', 'app/tool', 'app/macos', 'app/ios', 'app/android', 'app/linux', 'app/windows'])
        if (Directory('${root.path}/$d').existsSync())
          ...Directory('${root.path}/$d').listSync(recursive: true).whereType<File>().where((f) =>
              ['.sh', '.py', '.json', '.yaml', '.yml', '.gradle', '.kts', '.xcconfig', '.pbxproj', '.cmake']
                  .any(f.path.endsWith)),
    ];
    expect(scripts, isNotEmpty);
    for (final f in scripts) {
      String text;
      try {
        text = f.readAsStringSync();
      } catch (_) {
        continue; // not text
      }
      expect(text.contains('SOLACE_TEST_SEAMS'), isFalse, reason: '${f.path} sets the test seams');
    }
  });

  test('only the voice reads them: no screen and no other part of the app', () {
    final readers = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.endsWith('test_seams.dart') &&
            RegExp(r'\b(testSeams|CallSeams)\b').hasMatch(f.readAsStringSync()))
          f.path.replaceAll(r'\', '/'),
    ];
    expect(readers, ['lib/core/sherpa_voice.dart']);
  });

  test('the processor-only stand-in is a seam too: off in release, set by no build script, read only by the model', () {
    expect(forceCpuOnly, isFalse);
    expect(File('lib/core/test_seams.dart').readAsStringSync(),
        contains("const forceCpuOnly = testSeams && bool.fromEnvironment('SOLACE_FORCE_CPU');"));
    final readers = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        if (f.path.replaceAll(r'\\', '/') != 'lib/core/test_seams.dart' &&
            RegExp(r'\bforceCpuOnly\b').hasMatch(f.readAsStringSync()))
          f.path.replaceAll(r'\\', '/'),
    ];
    expect(readers, ['lib/core/llama_model.dart']);
    for (final f in [...Directory('../tools').listSync(recursive: true).whereType<File>()]) {
      final text = f.readAsStringSync();
      expect(text.contains('SOLACE_FORCE_CPU'), isFalse, reason: '${f.path} sets the processor-only stand-in');
    }
  });
}
