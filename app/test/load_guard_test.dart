// Round 9 review, 9B-04: a model too large for the device (or a driver llama.cpp aborts on) used to crash Solace at
// every start, a few seconds after the screen appeared, because the model, the classifier and the voice all loaded at
// once at each start and nothing remembered that a load was under way. Now each native load runs inside a marker in
// the app's private support folder (core/load_guard.dart); a marker still there at the next start means the load
// never returned; after two in a row (9B-09: one alone is tried again, test/load_guard_recheck_test.dart) that engine
// is not loaded on its own, Settings says why with a button to try again (and the Light
// model when the Standard one was the cause); the loads run one after the other, the classifier first; and the
// Standard model is passed over when the device's memory clearly cannot hold it. The phrase rules and the support card
// never wait for any engine.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/load_guard.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety.dart' show SafetyLevel;
import 'package:solace/core/trusted.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/settings.dart';

import 'app_flow_test.dart' as flow;

/// A loaded model stand-in, so the tests can see which file was loaded.
class _Loaded extends StandInModel {
  const _Loaded(this.file);
  final String file;
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  late Directory root, support, files;
  setUp(() {
    root = Directory('build/test_scratch/load_guard')..createSync(recursive: true);
    support = Directory('${root.path}/support')..createSync();
    files = Directory('${root.path}/files')..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A trusted stand-in model file of [bytes] bytes named [name] (model-standard.gguf or model-light.gguf).
  void addModel(String name, String content) {
    File('${files.path}/$name').writeAsStringSync(content);
    final sum = const DartSha256().hashSync(utf8.encode(content)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    testOnlyTrustedModels.add(sum);
    File('${files.path}/${name.replaceAll('.gguf', '.sha256')}').writeAsStringSync('$sum  $name\n');
  }

  group('the marker', () {
    test('is on the disk while a load runs and gone once it returns, worked or failed', () async {
      final guard = LoadGuard(support);
      final marker = File('${support.path}/loading_model');
      final release = Completer<String>();
      final load = guard.run(Engine.model, 'model-standard.gguf', () => release.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(marker.readAsStringSync(), '1\nmodel-standard.gguf',
          reason: 'written before the native load: one load in a row not returned yet, and what is loading');
      // the process dies here: the next start sees what was loading
      expect(LoadGuard(support).stopped(Engine.model), 'model-standard.gguf');
      release.complete('loaded');
      expect(await load, 'loaded');
      expect(marker.existsSync(), isFalse);
      expect(LoadGuard(support).stopped(Engine.model), isNull);
      await expectLater(guard.run(Engine.voice, '', () async => throw StateError('no voice')), throwsStateError);
      expect(guard.stopped(Engine.voice), isNull, reason: 'a load that failed returned: no marker');
      expect(support.listSync().map((e) => e.uri.pathSegments.last), isNot(contains(contains('loading'))));
    });

    test('one native load at a time: a load asked for meanwhile waits for the first to return', () async {
      final guard = LoadGuard(support);
      final events = <String>[];
      final first = Completer<void>();
      final a = guard.run(Engine.model, 'm', () async {
        events.add('model start');
        await first.future;
        events.add('model end');
      });
      final b = guard.run(Engine.classifier, '', () async => events.add('classifier start'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, ['model start']);
      first.complete();
      await Future.wait([a, b]);
      expect(events, ['model start', 'model end', 'classifier start']);
    });
  });

  group('the model at start', () {
    test('(a) after two stopped loads in a row, the load is not attempted, the reason is shown, and Light is offered',
        () async {
      addModel('model-standard.gguf', 'standard weights');
      addModel('model-light.gguf', 'light weights');
      // Solace died loading it, and again when it tried once more by itself (9B-09: one alone is retried)
      File('${support.path}/loading_model').writeAsStringSync('2\nmodel-standard.gguf');
      final state = flow.makeState()..loadGuard = LoadGuard(support);
      var loads = 0;
      Future<ModelRuntime> runtime(ModelFile m) async {
        loads++;
        return _Loaded(m.name);
      }

      await loadTrainedModel(state, atStart: true, files: files, support: support, memory: () async => null,
          runtime: runtime);
      expect(loads, 0, reason: 'never loaded on its own again');
      expect(state.modelStatus, stoppedModelStatus);
      expect(state.modelStatus, contains('Solace stopped twice in a row while loading the model'));
      expect(state.stoppedLoads[Engine.model]?.light, 'model-light.gguf');
      expect(state.model, isNot(isA<_Loaded>()), reason: 'the stand-in answers');
      // Try again, asked for in Settings: loaded now, inside a new marker that goes once it returns
      state.loadGuard!.clear(Engine.model);
      await loadTrainedModel(state, files: files, support: support, memory: () async => null, runtime: runtime);
      expect(loads, 1);
      expect((state.model as _Loaded).file, 'model-standard.gguf');
      expect(File('${support.path}/loading_model').existsSync(), isFalse);
    });

    test('the Light model, once chosen, is loaded at later starts; the Standard one only when asked again', () async {
      addModel('model-standard.gguf', 'standard weights');
      addModel('model-light.gguf', 'light weights');
      final state = flow.makeState()..loadGuard = LoadGuard(support);
      state.loadGuard!.setPrefersLight(true);
      await loadTrainedModel(state, atStart: true, files: files, support: support, memory: () async => null,
          runtime: (m) async => _Loaded(m.name));
      expect((state.model as _Loaded).file, 'model-light.gguf');
      expect(state.lightChosen, isTrue);
      expect(state.modelStatus, contains('as chosen after the Standard model stopped Solace'));
      tryStandardAgain(state);
      expect(state.loadGuard!.prefersLight, isFalse);
      expect(state.modelStatus, contains('next time Solace starts'));
      expect((state.model as _Loaded).file, 'model-light.gguf', reason: 'never both models in memory at once');
    });

    test('a Standard model that clearly cannot fit is passed over for the Light one, or not loaded, and it says so',
        () async {
      addModel('model-standard.gguf', 'standard weights, the larger file');
      addModel('model-light.gguf', 'light');
      final state = flow.makeState()..loadGuard = LoadGuard(support);
      final small = modelHeadroom + 10; // room for the 5-byte Light file and its headroom, not the Standard one
      await loadTrainedModel(state, atStart: true, files: files, support: support, memory: () async => small,
          runtime: (m) async => _Loaded(m.name));
      expect((state.model as _Loaded).file, 'model-light.gguf');
      expect(state.modelStatus, contains('needs more memory than this device has'));
      File('${files.path}/model-light.gguf').deleteSync();
      final alone = flow.makeState()..loadGuard = LoadGuard(support);
      var loads = 0;
      await loadTrainedModel(alone, atStart: true, files: files, support: support, memory: () async => small,
          runtime: (m) async {
        loads++;
        return _Loaded(m.name);
      });
      expect(loads, 0);
      expect(alone.modelStatus, contains('does not have enough memory for model-standard.gguf'));
    });

    test('the choice of model by memory, and the memory read from /proc/meminfo', () async {
      final std = ModelFile(File('model-standard.gguf'), ''), light = ModelFile(File('model-light.gguf'), '');
      const gb = 1 << 30;
      final both = [(std, 5720 * 1024 * 1024), (light, 3400 * 1024 * 1024)];
      expect(chooseModel(both, 5 * gb + gb ~/ 2).$1, light, reason: 'a 6 GB phone');
      expect(chooseModel(both, 12 * gb).$1, std, reason: 'a 12 GB phone');
      expect(chooseModel(both, null).$1, std, reason: 'unknown: tried, the marker guards it');
      expect(chooseModel([both.first], 5 * gb).$1, isNull);
      expect(chooseModel(both, 12 * gb, preferLight: true).$1, light);
      final meminfo = File('${root.path}/meminfo')..writeAsStringSync('MemTotal:        7864320 kB\nMemFree: 1 kB\n');
      expect(await deviceMemory(os: 'android', meminfo: meminfo), 7864320 * 1024);
      expect(await deviceMemory(os: 'linux', meminfo: File('${root.path}/none')), isNull);
      expect(await deviceMemory(os: 'ios', meminfo: meminfo), isNull, reason: 'no total without native code');
    });
  });

  test('(c) the engines load one after the other: the classifier, then the model, then the voice', () async {
    final events = <String>[];
    Future<void> Function(AppState) step(String name) => (_) async {
          events.add('$name start');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          events.add('$name end');
        };
    await loadDeviceFiles(flow.makeState(), classifier: step('classifier'), model: step('model'), voice: step('voice'));
    expect(events, ['classifier start', 'classifier end', 'model start', 'model end', 'voice start', 'voice end']);
  });

  test('with every engine stopped twice in a row nothing loads at start, and the phrase rules and support still work',
      () async {
    for (final e in Engine.values) {
      File('${support.path}/loading_${e.name}').writeAsStringSync(e == Engine.model ? '2\nmodel-standard.gguf' : '2\n');
    }
    final state = flow.makeState()..loadGuard = LoadGuard(support);
    await loadDeviceFiles(state);
    expect(state.stoppedLoads.keys, unorderedEquals(Engine.values));
    expect(state.safetyStatus, stoppedSafetyStatus);
    expect(state.voiceStatus, stoppedVoiceStatus);
    expect(state.modelStatus, stoppedModelStatus);
    expect(state.riskCheck, isNull);
    final s = state.newSession();
    await s.start('daily_checkin');
    await s.send('I want to kill myself.');
    expect(s.lastSafety.level, SafetyLevel.crisis, reason: 'the phrase rules need no engine');
    expect(s.crisisCount, 1);
  });

  testWidgets('(b) Settings says why, and Try again clears the marker; Use the Light model is offered', (tester) async {
    File('${support.path}/loading_model').writeAsStringSync('model-standard.gguf');
    File('${support.path}/loading_voice').writeAsStringSync('');
    final state = flow.makeState()
      ..loadGuard = LoadGuard(support)
      ..reportStoppedLoad(const StoppedLoad(Engine.model, 'model-standard.gguf', light: 'model-light.gguf'))
      ..reportModel(stoppedModelStatus)
      ..reportStoppedLoad(const StoppedLoad(Engine.voice, ''))
      ..reportVoice(stoppedVoiceStatus);
    await flow.pumpScreen(tester, state, const SettingsScreen());
    final again = find.byKey(const Key('try_load_model'));
    await tester.scrollUntilVisible(again, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    // the model's line says it in short, with its state; the full words are under Details (design review 2026-11-16)
    expect(find.descendant(of: find.byKey(const Key('file_model')), matching: find.text('Not loaded')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('files_details')));
    await tester.tap(find.byKey(const Key('files_details')));
    await tester.pumpAndSettle();
    expect(find.text(stoppedModelStatus), findsOneWidget);
    expect(find.byKey(const Key('use_light_model')), findsOneWidget);
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    await tester.tap(again);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200))); // the load tried, for real
    await tester.pumpAndSettle();
    expect(File('${support.path}/loading_model').existsSync(), isFalse, reason: 'Try again clears the marker');
    expect(state.stoppedLoads.containsKey(Engine.model), isFalse);
    expect(find.byKey(const Key('try_load_model')), findsNothing);
    expect(find.text(stoppedModelStatus), findsNothing, reason: 'the load was tried (this test has no model files)');
    // the voice's own button
    final voice = find.byKey(const Key('try_load_voice'));
    await tester.scrollUntilVisible(voice, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text(stoppedVoiceStatus), findsOneWidget);
    await tester.tap(voice);
    await tester.pumpAndSettle();
    expect(File('${support.path}/loading_voice').existsSync(), isFalse);
    expect(find.byKey(const Key('try_load_voice')), findsNothing);
  });

  testWidgets('(b) Use the Light model clears the marker and keeps the choice for later starts', (tester) async {
    File('${support.path}/loading_model').writeAsStringSync('model-standard.gguf');
    final state = flow.makeState()
      ..loadGuard = LoadGuard(support)
      ..reportStoppedLoad(const StoppedLoad(Engine.model, 'model-standard.gguf', light: 'model-light.gguf'))
      ..reportModel(stoppedModelStatus);
    await flow.pumpScreen(tester, state, const SettingsScreen());
    final light = find.byKey(const Key('use_light_model'));
    await tester.scrollUntilVisible(light, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(light);
    await tester.pumpAndSettle();
    expect(File('${support.path}/loading_model').existsSync(), isFalse);
    expect(LoadGuard(support).prefersLight, isTrue);
    expect(state.stoppedLoads, isEmpty);
  });
}
