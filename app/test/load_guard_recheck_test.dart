// Round 9 review B, re-check. 9B-09: a start that simply ended during a load (Solace swiped away or its window closed,
// the phone restarted, a suspended app ended by the system) left the same marker as a crash and kept that engine, the
// safety check too, off at every later start until Try again in Settings; the chat then said the check was "not set
// up on this device". Now an engine is held back only after two loads in a row never returned (one alone is tried
// again by itself), a load does not count while Solace is in the background, only the native load is inside the
// marker (the checksums come first), and a held-back safety check is said plainly in the chat and the call, with Try
// again. The 9B-04 gaps: on a full disk the model and the voice are not loaded on their own (the classifier is), and
// a load that hangs holds back the ones after it only for a bounded wait, and is reported.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/load_guard.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/safety_classifier.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/sherpa_voice.dart';
import 'package:solace/core/trusted.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';

import 'audit_followups_test.dart' as a;

/// A loaded model stand-in, so the tests can see which file was loaded.
class _Loaded extends StandInModel {
  const _Loaded(this.file);
  final String file;
}

void main() {
  late Directory root, support, files;
  setUp(() {
    root = Directory('build/test_scratch/load_guard_recheck')..createSync(recursive: true);
    support = Directory('${root.path}/support')..createSync();
    files = Directory('${root.path}/files')..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  File marker(Engine e, [Directory? dir]) => File('${(dir ?? support).path}/loading_${e.name}');

  void addModel(String name, String content) {
    File('${files.path}/$name').writeAsStringSync(content);
    final sum = const DartSha256().hashSync(utf8.encode(content)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    testOnlyTrustedModels.add(sum);
    File('${files.path}/${name.replaceAll('.gguf', '.sha256')}').writeAsStringSync('$sum  $name\n');
  }

  group('9B-09: an engine is held back only after two stopped loads in a row', () {
    test('one leftover marker: the next start loads the model again by itself, and that try counts as the second',
        () async {
      addModel('model-standard.gguf', 'standard weights');
      marker(Engine.model).writeAsStringSync('1\nmodel-standard.gguf'); // one start ended while it loaded
      final state = a.makeState()..loadGuard = LoadGuard(support);
      String? during;
      await loadTrainedModel(state, atStart: true, files: files, support: support, memory: () async => null,
          runtime: (m) async {
        during = marker(Engine.model).readAsStringSync();
        return _Loaded(m.name);
      });
      expect((state.model as _Loaded).file, 'model-standard.gguf', reason: 'tried again, not held back');
      expect(during, '2\nmodel-standard.gguf', reason: 'if this try also never returns, the next start holds it back');
      expect(state.stoppedLoads, isEmpty);
      expect(marker(Engine.model).existsSync(), isFalse, reason: 'it returned: the count starts again');
    });

    test('across starts: two loads that never return hold the engine back at the third start', () async {
      // each "start" is a new guard on the same folder; the load never returns (Solace is killed inside it)
      void startThatDies(Engine e) =>
          unawaited(LoadGuard(support, wait: const Duration(milliseconds: 20)).run(e, '', () => Completer<void>().future));
      startThatDies(Engine.voice);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(LoadGuard(support).stops(Engine.voice), 1);
      expect(LoadGuard(support).blocked(Engine.voice), isFalse, reason: 'one stop: tried again at the next start');
      startThatDies(Engine.voice);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(LoadGuard(support).stops(Engine.voice), 2);
      expect(LoadGuard(support).blocked(Engine.voice), isTrue, reason: 'two in a row: held back, with Try again');
      // a load that returns in between starts the count again
      await LoadGuard(support).run(Engine.voice, '', () async {});
      expect(LoadGuard(support).stops(Engine.voice), 0);
    });

    test('the safety check: one leftover marker is tried again, never reported as stopped', () async {
      marker(Engine.classifier).writeAsStringSync('1\n');
      final state = a.makeState()..loadGuard = LoadGuard(support);
      await loadSafetyClassifier(state, atStart: true);
      expect(state.stoppedLoads, isEmpty);
      expect(state.safetyStatus, isNot(stoppedSafetyStatus), reason: 'the load was tried (this test has no files)');
    });

    test('the safety check: two in a row hold it back, said as failed to load, never as off or not set up', () async {
      marker(Engine.classifier).writeAsStringSync('2\n');
      final state = a.makeState()..loadGuard = LoadGuard(support);
      await loadSafetyClassifier(state, atStart: true);
      expect(state.stoppedLoads.containsKey(Engine.classifier), isTrue);
      expect(state.safetyStatus, stoppedSafetyStatus);
      expect(stoppedSafetyStatus, contains('failed to load'));
      expect(stoppedSafetyStatus, isNot(contains('not set up')));
      expect(stoppedSafetyStatus, isNot(contains('turned off')));
      expect(state.data.settings.classifierOn, isTrue, reason: 'held back is not turned off; only the PIN does that');
      // Try again clears the marker and loads it now
      await tryLoadAgain(state, Engine.classifier);
      expect(marker(Engine.classifier).existsSync(), isFalse);
      expect(state.stoppedLoads, isEmpty);
      expect(state.safetyStatus, isNot(stoppedSafetyStatus));
    });
  });

  group('9B-09: a load interrupted by the background does not count', () {
    test('in the background the marker counts nothing; back in front it counts again; returned, it goes', () async {
      final guard = LoadGuard(support);
      final release = Completer<void>();
      final load = guard.run(Engine.classifier, '', () => release.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(LoadGuard(support).stops(Engine.classifier), 1);
      for (final away in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        guard.lifecycle(away);
        expect(LoadGuard(support).stops(Engine.classifier), 0, reason: 'ended now (a swipe, the system): not a crash');
        expect(LoadGuard(support).stopped(Engine.classifier), isNull);
        guard.lifecycle(AppLifecycleState.resumed);
        expect(LoadGuard(support).stops(Engine.classifier), 1);
      }
      release.complete();
      await load;
      expect(marker(Engine.classifier).existsSync(), isFalse);
    });

    test('a retry that starts or ends in the background stays at one stop: it is tried again at the next start',
        () async {
      marker(Engine.model).writeAsStringSync('1\nmodel-standard.gguf');
      final guard = LoadGuard(support)..lifecycle(AppLifecycleState.paused);
      final release = Completer<void>();
      final load = guard.run(Engine.model, 'model-standard.gguf', () => release.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(LoadGuard(support).stops(Engine.model), 1);
      expect(LoadGuard(support).blocked(Engine.model), isFalse);
      guard.lifecycle(AppLifecycleState.resumed);
      expect(LoadGuard(support).stops(Engine.model), 2, reason: 'in front again: this try counts');
      guard.lifecycle(AppLifecycleState.detached);
      expect(LoadGuard(support).stops(Engine.model), 1);
      release.complete();
      await load;
    });
  });

  group('9B-09: only the native load is inside the marker', () {
    test('the classifier\'s checksums come first: files that fail them never reach the native load or a marker',
        () async {
      final dir = Directory('${root.path}/safety')..createSync();
      for (final f in ['safety.int8.onnx', 'tokenizer.json', 'labels.json']) {
        File('${dir.path}/$f').writeAsStringSync('not the trusted file');
      }
      final guard = LoadGuard(support);
      var native = 0;
      final markerWhileChecking = <bool>[];
      final clf = await SafetyClassifier.load(dir, File('${root.path}/safety_check.txt'), (s) {
        if (s.startsWith('Checking')) markerWhileChecking.add(marker(Engine.classifier).existsSync());
      }, native: (open) {
        native++;
        return guard.run(Engine.classifier, '', open);
      });
      expect(clf, isNull);
      expect(markerWhileChecking, [false], reason: 'no marker while the 641 MB file is hashed');
      expect(native, 0);
      expect(marker(Engine.classifier).existsSync(), isFalse);
    });

    test('the voice\'s checksums come first too', () async {
      final dir = Directory('${root.path}/voice')..createSync();
      File('${dir.path}/voice.sha256').writeAsStringSync('');
      var native = 0;
      final v = await SherpaVoice.load(dir, root, root, (_) {}, native: (open) {
        native++;
        return LoadGuard(support).run(Engine.voice, '', open);
      });
      expect(v, isNull);
      expect(native, 0);
      expect(marker(Engine.voice).existsSync(), isFalse);
    });
  });

  group('9B-04: a full disk (the marker cannot be written)', () {
    late Directory full; // under a plain file, so nothing can be written in it
    setUp(() {
      File('${root.path}/plain').writeAsStringSync('x');
      full = Directory('${root.path}/plain/support');
    });

    test('the model is not loaded on its own at start, and says why; Try again loads it', () async {
      addModel('model-standard.gguf', 'standard weights');
      final state = a.makeState()..loadGuard = LoadGuard(full);
      var loads = 0;
      Future<ModelRuntime> runtime(ModelFile m) async {
        loads++;
        return _Loaded(m.name);
      }

      await loadTrainedModel(state, atStart: true, files: files, support: support, memory: () async => null,
          runtime: runtime);
      expect(loads, 0, reason: 'without a marker, a model that killed Solace would do so at every start');
      expect(state.modelStatus, noMarkerModelStatus);
      expect(state.stoppedLoads[Engine.model]?.noMarker, isTrue, reason: 'Settings offers Try again');
      expect(File('${support.path}/model_check.txt').existsSync(), isFalse, reason: 'its checksum not run for nothing');
      expect(LoadGuard(full).canWrite(), isFalse);
      expect(LoadGuard(support).canWrite(), isTrue);
      // Try again, the person's choice: loaded now, without a marker (a later start still would not load it alone)
      state.clearStoppedLoad(Engine.model);
      await loadTrainedModel(state, files: files, support: support, memory: () async => null, runtime: runtime);
      expect(loads, 1);
      expect((state.model as _Loaded).file, 'model-standard.gguf');
    });

    test('the classifier still loads without a marker; the voice at start does not', () async {
      final guard = LoadGuard(full);
      expect(await guard.run(Engine.classifier, '', () async => 'classifier loaded'), 'classifier loaded');
      var voice = 0;
      await expectLater(guard.run(Engine.voice, '', () async => voice++, needsMarker: true),
          throwsA(isA<NoLoadMarker>()));
      expect(voice, 0);
      expect(await guard.run(Engine.voice, '', () async => 'asked for', needsMarker: false), 'asked for');
    });
  });

  group('9B-04: a load that hangs', () {
    test('holds back the next load for at most the wait, and is reported until it returns', () async {
      final guard = LoadGuard(support, wait: const Duration(milliseconds: 100));
      final said = <(Engine, bool)>[];
      guard.onSlow = (e, slow) => said.add((e, slow));
      final hung = Completer<void>();
      final first = guard.run(Engine.classifier, '', () => hung.future);
      final sw = Stopwatch()..start();
      expect(await guard.run(Engine.model, 'm', () async => 'model loaded'), 'model loaded');
      expect(sw.elapsedMilliseconds, lessThan(5000));
      await Future<void>.delayed(const Duration(milliseconds: 50)); // its own timer, started a moment after the wait
      expect(said, [(Engine.classifier, true)]);
      hung.complete();
      await first;
      expect(said, [(Engine.classifier, true), (Engine.classifier, false)]);
    });

    test('at start the later engines still start, and Settings says the safety check is still loading', () async {
      final state = a.makeState()..loadGuard = LoadGuard(support, wait: const Duration(milliseconds: 100));
      final events = <String>[];
      final hung = Completer<void>();
      await loadDeviceFiles(state,
          classifier: (s) => s.loadGuard!.run(Engine.classifier, '', () => hung.future),
          model: (s) async => events.add('model'),
          voice: (s) async => events.add('voice'));
      expect(events, ['model', 'voice']);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(state.slowLoads, {Engine.classifier});
      expect(state.safetyStatus, slowSafetyStatus);
      hung.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(state.slowLoads, isEmpty);
    });
  });

  group('9B-09: the chat and the call say the safety check failed to load, with Try again', () {
    testWidgets('chat: held back after two stops, the plain reason and Try again, which clears it', (tester) async {
      marker(Engine.classifier).writeAsStringSync('2\n');
      final state = a.makeState()..loadGuard = LoadGuard(support);
      await loadSafetyClassifier(state, atStart: true);
      await a.pumpScreen(tester, state, const ChatScreen(kind: 'daily_checkin'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(classifierStoppedNotice), findsOneWidget);
      expect(find.text(phraseRulesOnlyNotice), findsNothing, reason: 'never "not set up on this device"');
      expect(find.text(classifierOffNotice), findsNothing, reason: 'never "turned off"');
      final again = find.byKey(const Key('try_safety_check'));
      expect(again, findsOneWidget);
      await tester.tap(again);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200))); // the load tried, for real
      await tester.pump();
      expect(marker(Engine.classifier).existsSync(), isFalse, reason: 'Try again clears the marker');
      expect(state.stoppedLoads, isEmpty);
      expect(find.text(classifierStoppedNotice), findsNothing);
      expect(find.byKey(const Key('try_safety_check')), findsNothing);
    });

    testWidgets('call: the same line, with Support below, and Try again', (tester) async {
      final state = a.makeState()
        ..reportStoppedLoad(const StoppedLoad(Engine.classifier, ''))
        ..reportSafety(stoppedSafetyStatus);
      final s = state.newSession();
      await s.start('daily_checkin');
      await a.pumpScreen(tester, state, CallScreen(kind: 'daily_checkin', controller: s));
      expect(find.text(classifierStoppedNotice.replaceFirst('at the top.', 'below.')), findsOneWidget);
      expect(find.byKey(const Key('try_safety_check')), findsOneWidget);
      expect(find.text(phraseRulesOnlyNotice.replaceFirst('at the top.', 'below.')), findsNothing);
    });

    testWidgets('chat: turned off with the PIN says off, without Try again; still loading says so', (tester) async {
      final state = a.makeState()..reportStoppedLoad(const StoppedLoad(Engine.classifier, ''));
      state.data.settings.classifierOn = false;
      await a.pumpScreen(tester, state, const ChatScreen(kind: 'daily_checkin'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(classifierOffNotice), findsOneWidget);
      expect(find.byKey(const Key('try_safety_check')), findsNothing);
      state.data.settings.classifierOn = true;
      state.clearStoppedLoad(Engine.classifier);
      state.reportSlowLoad(Engine.classifier, true);
      await tester.pump();
      expect(find.text(classifierSlowNotice), findsOneWidget);
      expect(find.text(phraseRulesOnlyNotice), findsNothing);
    });
  });
}
