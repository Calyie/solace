// Vision board photos are made small on the device before they are kept (core/photos.dart).
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/photos.dart';

Future<Uint8List> blueImage(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF1D5BD8));
  final png = await (await rec.endRecording().toImage(w, h)).toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

Future<ui.Image> decode(String b64) async => (await (await ui.instantiateImageCodec(base64Decode(b64))).getNextFrame()).image;

void main() {
  testWidgets('a large photo is kept at 720 pixels wide, its shape unchanged', (tester) async {
    final out = await tester.runAsync(() async => decode((await shrinkPhoto(await blueImage(1500, 1000)))!));
    expect((out!.width, out.height), (720, 480));
  });

  testWidgets('a small photo is not enlarged; a file that is not an image is refused', (tester) async {
    final small = await tester.runAsync(() async => decode((await shrinkPhoto(await blueImage(400, 300)))!));
    expect((small!.width, small.height), (400, 300));
    expect(await tester.runAsync(() => shrinkPhoto(Uint8List.fromList(utf8.encode('not a photo')))), isNull);
  });
}
