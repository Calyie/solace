// Bounded input and a complete wipe (security review 2026-11-14, F-14 and F-19; owner: never crash or freeze the
// device on an input that was not size-checked): a photo is refused by its size or its pixel count before it is
// decoded; "Delete everything" removes Solace's own files and nothing else, cancels its reminders and lets go of the
// loaded model, voice and classifier.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_files.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/photos.dart';

import 'app_flow_test.dart' as flow;

Future<Uint8List> png(int w, int h) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFF3366AA));
  final image = await rec.endRecording().toImage(w, h);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  image.dispose();
  return bytes;
}

/// [bytes] (a PNG) with its header claiming [w] x [h] pixels (the IHDR width and height), as a crafted file would.
Uint8List claiming(Uint8List bytes, int w, int h) {
  final out = Uint8List.fromList(bytes);
  ByteData.sublistView(out)
    ..setUint32(16, w)
    ..setUint32(20, h);
  return out;
}

void main() {
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  testWidgets('photos: shrunk to card width; refused by file size or pixel count before decoding (F-14)', (tester) async {
    await tester.runAsync(() async {
      final ok = await shrinkPhoto(await png(1600, 900));
      expect(ok, isNotNull);
      expect(await shrinkPhoto(Uint8List(maxPhotoBytes + 1)), isNull, reason: 'too large a file');
      expect(await shrinkPhoto(claiming(await png(8, 8), 30000, 30000)), isNull, reason: '900 megapixels claimed');
      expect(await shrinkPhoto(Uint8List.fromList(List.filled(1000, 7))), isNull, reason: 'not a picture');
    });
  });

  test("Delete everything removes Solace's own files and nothing else (F-19)", () async {
    final support = await Directory.systemTemp.createTemp('support'), temp = await Directory.systemTemp.createTemp('tmp'),
        inbox = await Directory.systemTemp.createTemp('docs');
    Directory('${support.path}/files/voice').createSync(recursive: true);
    File('${support.path}/files/model-standard.gguf').writeAsStringSync('m');
    File('${support.path}/model_check.txt').writeAsStringSync('c');
    File('${support.path}/data_v1.bin.tmp3').writeAsStringSync('t');
    File('${temp.path}/bundle.zip').writeAsStringSync('z');
    File('${temp.path}/someone-elses.txt').writeAsStringSync('keep');
    File('${inbox.path}/model.gguf').writeAsStringSync('g');
    File('${inbox.path}/my-letter.pdf').writeAsStringSync('keep');
    await wipeAppFolders(support: support, temp: temp, inbox: inbox);
    expect(support.listSync(), isEmpty);
    expect(temp.listSync().map((e) => e.uri.pathSegments.last), ['someone-elses.txt']);
    expect(inbox.listSync().map((e) => e.uri.pathSegments.last), ['my-letter.pdf']);
    for (final d in [support, temp, inbox]) {
      await d.delete(recursive: true);
    }
  });

  test('Delete everything also lets go of the loaded classifier and model, and starts again at the first steps', () async {
    final state = flow.makeState(demo: true)
      ..useRiskCheck((context, text) async => false, 'test classifier')
      ..data.safetyPlan.add('people', 'Sam', '2026-11-14');
    var folders = 0;
    await state.wipeEverything(folders: () async => folders++);
    expect(folders, 1);
    expect(state.riskCheck, isNull);
    expect(state.model, isA<StandInModel>());
    expect(state.data.sessions, isEmpty);
    expect(state.data.safetyPlan.isEmpty, isTrue);
    expect(state.data.settings.onboarded, isFalse);
  });
}
