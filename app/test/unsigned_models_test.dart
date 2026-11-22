// 1.3.0 (owner, 2026-11-17): a model the maker of Solace did not sign may be used once the person accepts that exact
// file after a plain warning ("remove the signing enforcement ... warn the user that they are loading a model that is
// unsigned by the maker of Solace and ask if they want to continue ... User has to explicitly accept loading that
// particular model files which then allows it"). What must hold:
// - a model Solace knows (built in, or on the signed list) is used as before, with no question;
// - a model it does not know is used only after the person says yes to that file (its SHA-256), asked before anything
//   is copied when a .sha256 list names it, and after the copy is checked when there is none (the list is optional);
//   a no leaves the model in use as it was and nothing of the picked file on the device;
// - a model the signed list withdrew, or one listed for another version of the app, is refused, never asked about;
// - the yes is kept in the encrypted settings, on this device only (never in a transfer file), and a model is found at
//   the next start only while its yes is kept; a build without the option, or a pinned-only build, never asks;
// - the warning cannot be accepted without ticking that the person understands; Settings and every session say the
//   model is not from the maker, and Settings > Stop using it removes it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/model_import.dart';
import 'package:solace/core/model_manifest.dart';
import 'package:solace/core/session.dart' show unsignedModelNotice;
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/core/trusted.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/home.dart';
import 'package:solace/ui/model_files.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/theme.dart';
import 'package:solace/core/formats.dart' show appPromptVersion;

import 'app_flow_test.dart' as flow;

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
String sumOf(String text) => _hex(const DartSha256().hashSync(utf8.encode(text)).bytes);

/// A picked file whose contents are read only when listened to, so a test can tell whether anything was read yet.
class Picked {
  Picked(this.text);
  final String text;
  bool read = false;
  Stream<List<int>> get stream {
    late final StreamController<List<int>> c;
    c = StreamController<List<int>>(onListen: () {
      read = true;
      c
        ..add(utf8.encode(text))
        ..close();
    });
    return c.stream;
  }
}

(String, Stream<List<int>>) file(String name, String text) => (name, Stream.value(utf8.encode(text)));

late SimpleKeyPair _key;

Future<(List<int>, List<int>)> signed(List<Map<String, Object?>> models, {List<String> revoked = const []}) async {
  final bytes = utf8.encode(jsonEncode({'schema': 1, 'serial': 1, 'issued': '2026-11-17', 'models': models,
      'revoked': revoked}));
  final sig = await DartEd25519().sign(bytes, keyPair: _key);
  return (bytes, utf8.encode('${base64.encode(sig.bytes)}\n'));
}

Map<String, Object?> entry(String content, {String prompt = appPromptVersion}) => {'sha256': sumOf(content),
    'size': utf8.encode(content).length, 'tier': 'standard', 'prompt_version': prompt, 'context': 8192,
    'family': 'gemma4', 'name': 'therapist-new.gguf'};

void main() {
  late Directory dir;
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
    _key = await DartEd25519().newKeyPair();
    testOnlyModelSigningKey = _hex((await _key.extractPublicKey()).bytes);
  });
  tearDownAll(() => testOnlyModelSigningKey = null);
  setUp(() async => dir = Directory('${(await Directory.systemTemp.createTemp('unsigned')).path}/files'));
  tearDown(() async {
    testOnlyUnsignedModelsOn = null;
    testOnlySignedModelsOn = null;
    await dir.parent.delete(recursive: true);
  });
  List<String> kept() => dir.existsSync() ? (dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort()) : [];

  group('the import', () {
    test('a model Solace does not know, named in a .sha256 list: asked about before anything is read; yes copies it',
        () async {
      final weights = Picked('my better model');
      UnsignedModel? asked;
      final msg = await importModelFiles(
          [('my-model.gguf', weights.stream), file('my-model.sha256', '${sumOf('my better model')}  my-model.gguf\n')],
          dir, sizes: {'my-model.gguf': 15}, confirmUnsigned: (m) async {
        expect(weights.read, isFalse, reason: 'asked before the model is read or copied');
        asked = m;
        return true;
      });
      expect(asked, (name: 'my-model.gguf', size: 15, sha256: sumOf('my better model')));
      expect(msg, startsWith('Copied the Standard model'));
      expect(File('${dir.path}/model-standard.gguf').readAsStringSync(), 'my better model');
      // found at the next start only with the yes kept
      expect(await ModelFile.find(dir), isNull);
      expect((await ModelFile.find(dir, accepted: {sumOf('my better model')}))!.sha256, sumOf('my better model'));
    });

    test('a no copies nothing, and the model in use stays as it was', () async {
      testOnlyTrustedModels.add(sumOf('the shipped model'));
      addTearDown(() => testOnlyTrustedModels.remove(sumOf('the shipped model')));
      await importModelFiles([file('a.gguf', 'the shipped model'), file('a.sha256', '${sumOf('the shipped model')}  a.gguf\n')],
          dir);
      final weights = Picked('stranger');
      final msg = await importModelFiles(
          [('s.gguf', weights.stream), file('s.sha256', '${sumOf('stranger')}  s.gguf\n')], dir,
          confirmUnsigned: (_) async => false);
      expect(msg, unsignedDeclined);
      expect(weights.read, isFalse);
      expect(File('${dir.path}/model-standard.gguf').readAsStringSync(), 'the shipped model');
      expect(kept(), ['model-standard.gguf', 'model-standard.sha256']);
    });

    test('with no .sha256 list (optional for such a model) the copy is checked, then asked about with its own SHA-256',
        () async {
      final weights = Picked('no list here');
      String? askedSum;
      final msg = await importModelFiles([('custom.gguf', weights.stream)], dir, confirmUnsigned: (m) async {
        expect(weights.read, isTrue, reason: 'without a list the SHA-256 comes from the copy');
        askedSum = m.sha256;
        return true;
      });
      expect(askedSum, sumOf('no list here'));
      expect(msg, startsWith('Copied the Standard model'));
      expect(File('${dir.path}/model-standard.sha256').readAsStringSync(), '${sumOf('no list here')}  model-standard.gguf\n');
    });

    test('with no list and a no, the copy is deleted: no model, no part file', () async {
      final msg = await importModelFiles([file('custom.gguf', 'declined after the copy')], dir,
          confirmUnsigned: (_) async => false);
      expect(msg, unsignedDeclined);
      expect(kept(), isEmpty);
    });

    test('a model Solace trusts is never asked about, with or without its list', () async {
      testOnlyTrustedModels.add(sumOf('built in'));
      addTearDown(() => testOnlyTrustedModels.remove(sumOf('built in')));
      var asked = 0;
      final msg = await importModelFiles([file('therapist-e2b.gguf', 'built in')], dir,
          confirmUnsigned: (_) async => ++asked > 0);
      expect(msg, startsWith('Copied the Light model'));
      expect(asked, 0);
    });

    test('a model the signed list withdrew is refused, never asked about', () async {
      var asked = 0;
      final list = await signed([], revoked: [sumOf('withdrawn')]);
      final msg = await importModelFiles([file('w.gguf', 'withdrawn'), file('w.sha256', '${sumOf('withdrawn')}  w.gguf\n'),
          ('solace-models.json', Stream.value(list.$1)), ('solace-models.json.sig', Stream.value(list.$2))], dir,
          confirmUnsigned: (_) async => ++asked > 0);
      expect(msg, withdrawn);
      expect(asked, 0);
      expect(kept(), isEmpty);
      expect(unknownOnly(sumOf('withdrawn'), (await readModelList(list.$1, list.$2)).$1), isFalse);
    });

    test('a model listed for another version of the app is refused, never asked about', () async {
      var asked = 0;
      final list = await signed([entry('other version', prompt: 'v0')]);
      final msg = await importModelFiles([file('o.gguf', 'other version'),
          file('o.sha256', '${sumOf('other version')}  o.gguf\n'),
          ('solace-models.json', Stream.value(list.$1)), ('solace-models.json.sig', Stream.value(list.$2))], dir,
          confirmUnsigned: (_) async => ++asked > 0);
      expect(msg, isNot(unsignedDeclined));
      expect(msg, isNot(startsWith('Copied')));
      expect(asked, 0);
    });

    test('without the question (or in a build without the option, or a pinned-only build) it is refused as before',
        () async {
      final pick = [file('x.gguf', 'x'), file('x.sha256', '${sumOf('x')}  x.gguf\n')];
      expect(await importModelFiles(pick, dir), contains('not a model file this version of Solace was built for'));
      for (final off in [() => testOnlyUnsignedModelsOn = false, () => testOnlySignedModelsOn = false]) {
        off();
        var asked = 0;
        final msg = await importModelFiles([file('x.gguf', 'x'), file('x.sha256', '${sumOf('x')}  x.gguf\n')], dir,
            confirmUnsigned: (_) async => ++asked > 0);
        expect(msg, isNot(startsWith('Copied')));
        expect(asked, 0);
        expect(unknownOnly(sumOf('x'), null), isFalse);
        testOnlyUnsignedModelsOn = null;
        testOnlySignedModelsOn = null;
      }
      expect(kept(), isEmpty);
    });

    test('the tier of such a model comes from its name, as the shipped names do (e2b: Light)', () async {
      await importModelFiles([file('my-e2b-finetune.gguf', 'small')], dir, confirmUnsigned: (_) async => true);
      expect(kept(), ['model-light.gguf', 'model-light.sha256']);
    });

    test('a file changed after the yes is a different file: it is not found until accepted again', () async {
      await importModelFiles([file('m.gguf', 'first')], dir, confirmUnsigned: (_) async => true);
      // someone swaps the file and its list on the device
      File('${dir.path}/model-standard.gguf').writeAsStringSync('swapped');
      File('${dir.path}/model-standard.sha256').writeAsStringSync('${sumOf('swapped')}  model-standard.gguf\n');
      expect(await ModelFile.find(dir, accepted: {sumOf('first')}), isNull);
      // and a file swapped with its old list in place fails its own check before it is ever loaded
      File('${dir.path}/model-standard.sha256').writeAsStringSync('${sumOf('first')}  model-standard.gguf\n');
      final found = await ModelFile.find(dir, accepted: {sumOf('first')});
      expect(await found!.verify(File('${dir.parent.path}/check.txt')), isFalse);
    });
  });

  group('the yes is kept on this device only', () {
    test('settings keep well-formed choices only, at most 16, the newest', () {
      final good = {for (var i = 0; i < 20; i++) sumOf('m$i'): {'name': 'm$i.gguf', 'size': i, 'date': '2026-11-${(i + 1).toString().padLeft(2, '0')}'}};
      final read = AcceptedModel.allFrom({
        ...good,
        'not a sha': {'name': 'x', 'size': 1, 'date': '2026-11-17'},
        sumOf('bad size'): {'name': 'x', 'size': -1, 'date': '2026-11-17'},
        sumOf('bad date'): {'name': 'x', 'size': 1, 'date': 'yesterday'},
      });
      expect(read.length, AcceptedModel.most);
      expect(read.containsKey(sumOf('m19')), isTrue, reason: 'the newest kept');
      expect(read.containsKey(sumOf('m0')), isFalse, reason: 'the oldest dropped');
      final s = Settings()..acceptedModels = {sumOf('a'): const AcceptedModel(name: 'a.gguf', size: 3, date: '2026-11-17')};
      final back = Settings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.acceptedModels[sumOf('a')]!.name, 'a.gguf');
    });

    test('a transfer file never carries a yes, and an import keeps this device\'s own', () async {
      final code = TransferCode.generate(Random(31));
      final other = AppData()
        ..settings.acceptedModels = {sumOf('theirs'): const AcceptedModel(name: 't.gguf', size: 1, date: '2026-11-17')};
      final opened = await TransferFile.open(await TransferFile.seal(other, code, random: Random(32)), code);
      expect(opened.settings.acceptedModels, isEmpty, reason: 'not in the file');
      final here = AppData()
        ..settings.acceptedModels = {sumOf('mine'): const AcceptedModel(name: 'm.gguf', size: 1, date: '2026-11-17')};
      expect(importInto(here, opened).settings.acceptedModels.keys, [sumOf('mine')]);
    });
  });

  group('on screen', () {
    /// Adding files with a stand-in picker that offers [text] as model.gguf (with its list when [withList]).
    List<int> pickModel(Directory into, String text, {bool withList = true}) {
      final loads = <int>[];
      deviceFiles = DeviceFilesIO(
        pick: () async => [
          (name: 'better-model.gguf', size: utf8.encode(text).length, path: null,
              open: () => Stream.value(utf8.encode(text))),
          if (withList)
            (name: 'better-model.sha256', size: 80, path: null,
                open: () => Stream.value(utf8.encode('${sumOf(text)}  better-model.gguf\n'))),
        ],
        clearPicked: () async {},
        files: () async => into,
        support: () async => into.parent,
        space: () async => null,
        afterModel: (_) async => loads.add(1),
        afterBundle: (_) async {},
      );
      addTearDown(() => deviceFiles = DeviceFilesIO.real);
      return loads;
    }

    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 500 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'it never happened');
      await tester.pump();
    }

    Future<AppState> openSettings(WidgetTester tester) async {
      final state = flow.makeState();
      await flow.pumpApp(tester, state);
      Navigator.of(tester.element(find.byType(HomeShell)))
          .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('the warning: Use this model only once "I understand" is ticked; the yes is kept; the model loads',
        (tester) async {
      final into = (await tester.runAsync(() async => Directory('${(await Directory.systemTemp.createTemp('u')).path}/files')))!;
      addTearDown(() => tester.runAsync(() => into.parent.delete(recursive: true)));
      final loads = pickModel(into, 'a better model');
      final state = await openSettings(tester);
      final add = find.byKey(const Key('add_device_files'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await settle(tester, () => find.byKey(const Key('unsigned_dialog')).evaluate().isNotEmpty);
      expect(find.textContaining('is not signed by the maker of Solace'), findsOneWidget);
      expect(find.textContaining('safety check still reads every message'), findsOneWidget);
      expect(find.textContaining('The original model files signed by the maker of Solace are the safer choice'),
          findsOneWidget);
      expect(find.textContaining(sumOf('a better model').substring(0, 16)), findsOneWidget);
      final use = find.byKey(const Key('unsigned_use'));
      expect(tester.widget<ButtonStyleButton>(use).onPressed, isNull, reason: 'not before "I understand"');
      await tester.tap(find.byKey(const Key('unsigned_understand')));
      await tester.pump();
      expect(tester.widget<ButtonStyleButton>(use).onPressed, isNotNull);
      await tester.tap(use);
      await settle(tester, () => !state.imports.running);
      await tester.pumpAndSettle();
      expect(find.textContaining('Copied the Standard model'), findsWidgets);
      expect(state.acceptedModels, {sumOf('a better model')});
      expect(state.data.settings.acceptedModels[sumOf('a better model')]!.name, 'better-model.gguf');
      expect(loads, [1]);
    });

    testWidgets('Cancel is a no: nothing copied, nothing kept', (tester) async {
      final into = (await tester.runAsync(() async => Directory('${(await Directory.systemTemp.createTemp('u')).path}/files')))!;
      addTearDown(() => tester.runAsync(() => into.parent.delete(recursive: true)));
      final loads = pickModel(into, 'not this one', withList: true);
      final state = await openSettings(tester);
      final add = find.byKey(const Key('add_device_files'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await settle(tester, () => find.byKey(const Key('unsigned_dialog')).evaluate().isNotEmpty);
      await tester.tap(find.byKey(const Key('unsigned_cancel')));
      await settle(tester, () => !state.imports.running);
      await tester.pumpAndSettle();
      expect(state.acceptedModels, isEmpty);
      expect(loads, isEmpty);
      expect(await tester.runAsync(() async => into.existsSync() ? into.listSync().length : 0), 0);
    });

    testWidgets('Settings says the model in use is not from the maker, and Stop using it removes it', (tester) async {
      final into = (await tester.runAsync(() async => Directory('${(await Directory.systemTemp.createTemp('u')).path}/files')))!;
      addTearDown(() => tester.runAsync(() => into.parent.delete(recursive: true)));
      final loads = pickModel(into, 'in use');
      await tester.runAsync(() => importModelFiles([file('m.gguf', 'in use')], into, confirmUnsigned: (_) async => true));
      final state = flow.makeState()
        ..data.settings.acceptedModels = {sumOf('in use'): const AcceptedModel(name: 'm.gguf', size: 6, date: '2026-11-17')}
        ..modelSha = sumOf('in use');
      await flow.pumpApp(tester, state);
      Navigator.of(tester.element(find.byType(HomeShell)))
          .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await tester.pumpAndSettle();
      final note = find.byKey(const Key('model_unsigned_note'));
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(note).data, 'Not from the maker of Solace. You chose to use m.gguf on 17 November 2026. '
          'Solace\'s own safety check still reads every message.');
      await tester.tap(find.byKey(const Key('stop_unsigned_model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stop_unsigned_confirm')));
      await settle(tester, () => find.byKey(const Key('stop_unsigned_said')).evaluate().isNotEmpty);
      expect(state.acceptedModels, isEmpty);
      expect(state.modelSha, isNull);
      expect(await tester.runAsync(() async => into.listSync().map((e) => e.uri.pathSegments.last).toList()), isEmpty);
      expect(loads, [1], reason: 'whatever trusted model is left is loaded');
      expect(find.byKey(const Key('model_unsigned_note')), findsNothing);
    });

    testWidgets('every session says so at the top while such a model is in use', (tester) async {
      final state = flow.makeState()
        ..data.settings.acceptedModels = {sumOf('in use'): const AcceptedModel(name: 'm.gguf', size: 6, date: '2026-11-17')}
        ..modelSha = sumOf('in use');
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.light),
          home: const ChatScreen(kind: 'daily_checkin'))));
      await tester.pumpAndSettle();
      expect(find.text(unsignedModelNotice), findsOneWidget);
      state.modelSha = null;
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text(unsignedModelNotice), findsNothing);
    });
  });
}
