// The encrypted transfer file (lib/core/transfer.dart): everything comes back exactly, and a wrong code, a changed
// byte anywhere, or a file that is not a transfer file is refused with a plain message.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/photos.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';

AppData sample() => AppData(
      settings: Settings(country: 'Ireland', voice: 'af_heart', portrait: 'p3', therapistChosen: true),
      lastNote: 'Session: weekly_session, Sunday 1 November\nSafety: no concerns',
      homeworkDue: 'Walk for ten minutes after lunch on three days',
      moods: {'2026-11-01': 6, '2026-11-02': 4},
      sessions: [
        SessionRecord(date: '2026-11-01', kind: 'weekly_session', note: 'Talked about work.',
            turns: [('therapist', 'How has the week been?'), ('person', 'Better than last week, honestly.')]),
      ],
      journal: [
        {'date': '2026-11-02', 'text': 'Café on Grafton Street, naïve résumé ✓'}
      ],
    );

Future<void> expectRefused(Future<void> Function() f, String containing) async {
  try {
    await f();
    fail('expected the file to be refused');
  } on TransferError catch (e) {
    expect(e.message, contains(containing));
  }
}

void main() {
  test('a code is 16 unambiguous characters, shown in groups of four, and typed loosely', () {
    final code = TransferCode.generate(Random(1));
    expect(code.length, 16);
    expect(code.split('').every(TransferCode.alphabet.contains), isTrue);
    expect(TransferCode.show(code).split('-').map((g) => g.length), [4, 4, 4, 4]);
    expect(TransferCode.normalise(' ${TransferCode.show(code).toLowerCase()} '), code);
    expect(TransferCode.normalise('O0IL-1111-0000-ABCD'), '001111110000ABCD');
    expect(() => TransferCode.normalise('ABC'), throwsA(isA<TransferError>()));
    expect(() => TransferCode.normalise('UUUU-UUUU-UUUU-UUUU'), throwsA(isA<TransferError>())); // U is not used
  });

  test('everything comes back exactly with the right code', () async {
    final code = TransferCode.generate(Random(2));
    final file = await TransferFile.seal(sample(), code, random: Random(3));
    final back = await TransferFile.open(file, TransferCode.show(code).toLowerCase());
    expect(jsonEncode(back.toJson()), jsonEncode(sample().toJson()));
  });

  test('the content is not readable in the file', () async {
    final file = await TransferFile.seal(sample(), TransferCode.generate(Random(4)), random: Random(5));
    expect(latin1.decode(file, allowInvalid: true), isNot(contains('Grafton')));
  });

  test('a wrong code is refused', () async {
    final file = await TransferFile.seal(sample(), TransferCode.generate(Random(6)), random: Random(7));
    await expectRefused(() => TransferFile.open(file, TransferCode.generate(Random(8))), 'does not open this file');
  });

  test('a changed byte in the header or the body is refused', () async {
    final code = TransferCode.generate(Random(9));
    final file = await TransferFile.seal(sample(), code, random: Random(10));
    for (final i in [13, 30, 45, file.length - 1]) { // salt, nonce, body, the seal itself
      final bad = Uint8List.fromList(file)..[i] ^= 1;
      await expectRefused(() => TransferFile.open(bad, code), 'does not open this file');
    }
  });

  test('a file that is not a transfer file, a newer one, or one asking for too much work is refused', () async {
    final code = TransferCode.generate(Random(11));
    await expectRefused(() => TransferFile.open(utf8.encode('hello, this is a photo'), code), 'not a Solace');
    final file = await TransferFile.seal(sample(), code, random: Random(12));
    await expectRefused(() => TransferFile.open(Uint8List.fromList(file)..[4] = 9, code), 'newer version');
    final greedy = Uint8List.fromList(file);
    ByteData.sublistView(greedy).setUint32(6, 4000000); // 4 GB of memory
    await expectRefused(() => TransferFile.open(greedy, code), 'damaged');
  });

  test('each device keeps its own deep work mode: an import never switches it on or off', () async {
    final code = TransferCode.generate(Random(13));
    final other = sample()
      ..settings.mode = 'full'
      ..settings.fullModeSince = '2026-11-05'
      ..settings.fullModeFails = 3;
    final here = AppData()..settings.fullModeFails = 1..settings.fullModeLockedUntil = '2026-11-06T09:00:00.000';
    final merged = importInto(here, await TransferFile.open(await TransferFile.seal(other, code, random: Random(14)), code));
    expect(merged.settings.mode, 'normal');
    expect(merged.settings.fullModeSince, isNull);
    expect(merged.settings.fullModeFails, 1);
    expect(merged.settings.fullModeLockedUntil, '2026-11-06T09:00:00.000');
    expect(merged.sessions.length, 1); // everything else comes across
    final on = AppData()..settings.mode = 'full'..settings.fullModeSince = '2026-11-04';
    final kept = importInto(on, await TransferFile.open(await TransferFile.seal(AppData(), code, random: Random(15)), code));
    expect(kept.settings.mode, 'full');
    expect(kept.settings.fullModeSince, '2026-11-04');
  });

  test('deep work mode stays on through saving and loading', () async {
    final vault = MemoryVault();
    await vault.save(AppData()..settings.mode = 'full');
    expect((await vault.load()).settings.mode, 'full');
  });

  group('a received file is checked before anything changes (security review F-07, F-14)', () {
    final code = TransferCode.generate(Random(21));

    test('a file far too large is refused before it is opened', () async {
      await expectLater(TransferFile.open(Uint8List(TransferFile.maxFileBytes + 1), code),
          throwsA(isA<TransferError>().having((e) => e.message, 'message', contains('too large'))));
    });

    test('decompression stops at its ceiling (no zip bomb)', () {
      final bomb = gzip.encode(Uint8List(1 << 20)); // a megabyte of zeros packs into about a kilobyte
      expect(bomb.length, lessThan(5000));
      expect(() => TransferFile.gunzipCapped(bomb, 100000), throwsA(isA<TransferError>()));
      expect(TransferFile.gunzipCapped(bomb, 2 << 20).length, 1 << 20);
    });

    test('a date the screens would choke on is refused, and nothing is imported', () async {
      final bad = AppData()..scores.add({'date': 'yesterday', 'name': 'PHQ-9', 'total': 4, 'items': []});
      await expectLater(TransferFile.open(await TransferFile.seal(bad, code, random: Random(22), checkFirst: false), code),
          throwsA(isA<TransferError>().having((e) => e.message, 'message', contains('nothing was changed'))));
      final badSession = AppData()..sessions.add(SessionRecord(date: '31/12/2026', kind: 'daily_checkin', turns: [], note: ''));
      await expectLater(TransferFile.open(await TransferFile.seal(badSession, code, random: Random(23), checkFirst: false), code),
          throwsA(isA<TransferError>()));
      final badMood = AppData()..moods['2026-11-05'] = 99;
      await expectLater(TransferFile.open(await TransferFile.seal(badMood, code, random: Random(24), checkFirst: false), code),
          throwsA(isA<TransferError>()));
    });

    test('text and lists beyond their limits are refused', () async {
      final long = AppData()..journal.add({'date': '2026-11-05', 'text': 'x' * (TransferFile.maxString + 1)});
      await expectLater(TransferFile.open(await TransferFile.seal(long, code, random: Random(25), checkFirst: false), code),
          throwsA(isA<TransferError>()));
      expect(TransferFile.shapeProblem({'a': List.filled(TransferFile.maxList + 1, 0)}), isNotNull);
      Object deep = 'x';
      for (var i = 0; i < 20; i++) {
        deep = [deep];
      }
      expect(TransferFile.shapeProblem({'a': deep}), isNotNull);
      expect(TransferFile.shapeProblem(sample().toJson()), isNull, reason: 'real data passes');
    });

    test('a picture that is not a picture is refused', () async {
      final bad = AppData()..photos['x'] = base64Encode(utf8.encode('<svg>not a photo</svg>'));
      await expectLater(TransferFile.open(await TransferFile.seal(bad, code, random: Random(26), checkFirst: false), code),
          throwsA(isA<TransferError>()));
    });

    test("this device's country stays, for its crisis numbers", () async {
      final other = sample()..settings.country = 'France';
      final here = AppData()..settings.country = 'Ireland';
      final merged = importInto(here, await TransferFile.open(await TransferFile.seal(other, code, random: Random(27)), code));
      expect(merged.settings.country, 'Ireland');
    });
  });

  // Round 9 review, 9B-06: a received file never opens past what a real one of its size can, and the strings are
  // measured before they are built; the largest real file still comes across.
  group('opened size and strings are checked before anything is built (9B-06)', () {
    final code = TransferCode.generate(Random(31));

    /// A PNG of [w] x [h] made by the engine, as Solace makes every picture (photos.dart shrinkPhoto), with the
    /// colour of each pixel from [px] (red, green and blue by [c]).
    Future<Uint8List> enginePng(int w, int h, int Function(int x, int y, int c, Random r) px) async {
      final r = Random(5), rgba = Uint8List(w * h * 4);
      for (var y = 0, i = 0; y < h; y++) {
        for (var x = 0; x < w; x++, i += 4) {
          for (var c = 0; c < 3; c++) {
            rgba[i + c] = px(x, y, c, r).clamp(0, 255);
          }
          rgba[i + 3] = 255;
        }
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
      final image = await done.future;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return png!.buffer.asUint8List();
    }

    int photo(int x, int y, int c, Random r) => x * 200 ~/ 480 + y * 60 ~/ 360 + c * 25 + r.nextInt(12); // with noise

    testWidgets('a picture opens to at most twice its packed size plus the allowance, so real ones always pass',
        (tester) async {
      await tester.runAsync(() async {
        final kinds = <String, int Function(int, int, int, Random)>{
          'photo': photo,
          'flat gradient': (x, y, c, r) => x * 200 ~/ 1440 + y * 50 ~/ 4000 + c * 30,
          'screenshot': (x, y, c, r) => (y % 24 < 14 && (x * 7 + y * 3) % 11 < 4 && x % 300 < 260) ? 30 : 245,
          'stripes': (x, y, c, r) => ((x ~/ 7 + y ~/ 5) % 3) * 100,
        };
        for (final k in kinds.entries) {
          final b64 = base64Encode(await enginePng(maxPictureWidth, maxPictureHeight, k.value)); // the largest allowed
          final packed = gzip.encode(utf8.encode(b64)).length;
          // ignore: avoid_print
          print('9B-06 engine PNG 1440 x 4000, ${k.key}: ${b64.length ~/ 1024} KB of base64, gzip ${packed ~/ 1024} KB '
              '(ratio ${(b64.length / packed).toStringAsFixed(2)}); twice that plus the allowance: '
              '${(2 * packed + TransferFile.pictureSlack) ~/ 1024} KB');
          expect(b64.length, lessThan(2 * packed + TransferFile.pictureSlack ~/ 2), reason: 'with a margin of 2');
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('a real file at the 16 MB text cap with 100 pictures still comes across', (tester) async {
      await tester.runAsync(() async {
        final png = await enginePng(480, 360, photo);
        expect(pictureFits(png), isTrue);
        final d = AppData(photos: {for (var i = 0; i < 100; i++) 'picture $i': base64Encode(png)});
        // text that packs as well as text can (the case where the pictures must carry the limit on their own)
        final line = 'I slept badly again and the morning felt heavy, but I went for the walk anyway. ' * 24;
        int textBytes() => utf8.encode(jsonEncode(d.toJson())).length - TransferFile.pictureChars(d.toJson());
        const room = TransferFile.maxTextBytes - 4096 - 64 * 1024; // what sealProblem allows, less one turn or two
        final perTurn = utf8.encode(jsonEncode(['therapist', line])).length + 1;
        var day = 0;
        while (room - textBytes() > 2000 * perTurn + 1000) {
          d.sessions.add(SessionRecord(date: '2026-01-${(day++ % 28 + 1).toString().padLeft(2, '0')}',
              kind: 'weekly_session', note: '', turns: [for (var i = 0; i < 2000; i++) (i.isEven ? 'person' : 'therapist', line)]));
        }
        final last = <(String, String)>[];
        d.sessions.add(SessionRecord(date: '2026-02-01', kind: 'weekly_session', note: '', turns: last));
        last.addAll([for (var i = (room - textBytes()) ~/ perTurn; i > 0; i--) ('therapist', line)]);
        final text = textBytes();
        expect(text, lessThanOrEqualTo(room));
        expect(text, greaterThan(TransferFile.maxTextBytes - 256 * 1024), reason: 'at the cap');
        expect(TransferFile.sealProblem(d), isNull, reason: 'a file this device would make');
        final file = await TransferFile.seal(d, code, random: Random(32));
        final opened = utf8.encode(jsonEncode({'format': TransferFile.format})).length + text +
            TransferFile.pictureChars(d.toJson());
        // ignore: avoid_print
        print('9B-06 real file: ${text ~/ 1024} KB of text, 100 pictures of ${png.length ~/ 1024} KB; file '
            '${file.length ~/ 1024} KB, opens to about ${opened ~/ 1024} KB, limit '
            '${TransferFile.openedLimit(file.length - 56) ~/ 1024} KB');
        final back = await TransferFile.open(file, code);
        expect(back.photos.length, 100);
        expect(back.photos['picture 99'], base64Encode(png));
        expect(back.sessions.length, d.sessions.length);
        expect(back.sessions.last.turns.length, last.length);
      });
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('pictures that pack far smaller than photos do are refused before anything is read, and never made', () async {
      final header = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
        0, 0, 2, 0xD0, 0, 0, 1, 0x68, 8, 6, 0, 0, 0, 0, 0, 0, 0];
      final flat = base64Encode([...header, ...Uint8List(2900 * 1024)]); // a PNG header, then 2.9 MB of zeros
      final d = AppData(photos: {for (var i = 0; i < 12; i++) 'p$i': flat}); // 46 MB of base64 that packs to 50 KB
      await expectRefused(() => TransferFile.seal(d, code), 'pack far smaller');
      final file = await TransferFile.seal(d, code, random: Random(33), checkFirst: false);
      expect(file.length, lessThan(256 * 1024));
      await expectRefused(() => TransferFile.open(file, code), 'more in this file');
    });

    test('the outline measures the pictures as the store does and refuses strings past their limits', () {
      final d = sample()..photos.addAll({'a': 'QUJD' * 1000, 'b': 'REVG' * 10});
      final bytes = utf8.encode(jsonEncode({'format': TransferFile.format, 'app_data': d.toJson()}));
      final scan = JsonScan(maxDepth: 14, maxValues: 300000, checkStrings: true)..add(bytes);
      expect(scan.result, JsonOutline.fine);
      expect(scan.pictureBytes, TransferFile.pictureChars(d.toJson()));
      expect(scan.pictures, 2);
      // the same, fed one byte at a time (pieces split strings, escapes and keys anywhere)
      final pieces = JsonScan(maxDepth: 14, maxValues: 300000, checkStrings: true);
      for (final b in bytes) {
        pieces.add([b]);
      }
      expect((pieces.result, pieces.pictureBytes, pieces.pictures), (scan.result, scan.pictureBytes, scan.pictures));

      JsonOutline outline(String json) =>
          (JsonScan(maxDepth: 14, maxValues: 300000, checkStrings: true)..add(utf8.encode(json))).result;
      final big = 'A' * (TransferFile.maxPhotoChars + 1);
      expect(outline('{"app_data":{"photos":{"p":"$big"}}}'), JsonOutline.stringTooLong);
      expect(outline('{"app_data":{"journal":[{"text":"${'x' * (6 * TransferFile.maxString + 1)}"}]}}'),
          JsonOutline.stringTooLong);
      expect(outline('{"app_data":{"journal":[{"text":"${'x' * 60000}"}]}}'), JsonOutline.fine);
      final many = [for (var i = 0; i <= TransferFile.maxPhotos; i++) '"p$i":"QUJD"'].join(',');
      expect(outline('{"app_data":{"photos":{$many}}}'), JsonOutline.tooManyPictures);
      // a picture-sized string anywhere else, or under a key written with escapes, counts as text
      final escaped = JsonScan(maxDepth: 14, maxValues: 300000, checkStrings: true)
        ..add(utf8.encode('{"app_data":{"ph\\u006ftos":{"p":"QUJD"},"journal":{"photos":{"p":"QUJD"}}}}'));
      expect((escaped.result, escaped.pictureBytes), (JsonOutline.fine, 0));
    });
  });
}
