// The sounds made on the device (core/soundscape.dart, core/bell.dart), the timer's counting (core/sit_timer.dart),
// the kept files (core/sound_player.dart) and the new settings: every soundscape is a valid WAV of exactly its length
// that never clips, loops without a seam, is the same for the same seed and is made quickly; every bell begins softly
// and dies away to silence.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/bell.dart';
import 'package:solace/core/sit_timer.dart';
import 'package:solace/core/sound_player.dart';
import 'package:solace/core/soundscape.dart';
import 'package:solace/core/store.dart';

/// The samples of a WAV file, after checking every field of its header.
Int16List samplesOf(Uint8List wav, {required int length}) {
  final b = ByteData.sublistView(wav);
  String tag(int at) => String.fromCharCodes(wav.sublist(at, at + 4));
  expect(tag(0), 'RIFF');
  expect(b.getUint32(4, Endian.little), wav.length - 8);
  expect(tag(8), 'WAVE');
  expect(tag(12), 'fmt ');
  expect(b.getUint32(16, Endian.little), 16);
  expect(b.getUint16(20, Endian.little), 1, reason: 'plain PCM');
  expect(b.getUint16(22, Endian.little), 1, reason: 'mono');
  expect(b.getUint32(24, Endian.little), soundRate);
  expect(b.getUint32(28, Endian.little), soundRate * 2);
  expect(b.getUint16(32, Endian.little), 2);
  expect(b.getUint16(34, Endian.little), 16);
  expect(tag(36), 'data');
  expect(b.getUint32(40, Endian.little), length * 2);
  expect(wav.length, 44 + length * 2);
  return Int16List.fromList([for (var i = 0; i < length; i++) b.getInt16(44 + i * 2, Endian.little)]);
}

double rms(Int16List x, int from, int to) {
  var s = 0.0;
  for (var i = from; i < to; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / (to - from));
}

int peak(Int16List x, int from, int to) {
  var p = 0;
  for (var i = from; i < to; i++) {
    p = math.max(p, x[i].abs());
  }
  return p;
}

void main() {
  group('soundscapes', () {
    final made = <String, Uint8List>{};
    setUpAll(() {
      for (final s in soundscapes) {
        made[s.id] = renderScape(s.id);
      }
    });

    test('there are at least rain, ocean waves, brown noise, and wind or fire, each 20 to 60 seconds', () {
      expect(soundscapes.map((s) => s.id), containsAll(['rain', 'ocean', 'brown']));
      expect(soundscapes.map((s) => s.id).toSet().intersection({'wind', 'fire'}), isNotEmpty);
      for (final s in soundscapes) {
        expect(s.seconds, inInclusiveRange(20, 60), reason: s.id);
      }
    });

    for (final s in soundscapes) {
      test('${s.name}: a valid WAV of exactly ${s.seconds} seconds that never clips and is never silent', () {
        final x = samplesOf(made[s.id]!, length: s.seconds * soundRate);
        expect(made[s.id]!.length, scapeFileBytes(s));
        final top = peak(x, 0, x.length);
        expect(top, lessThan((0.9 * 32767).ceil() + 1), reason: 'the limiter keeps every peak below 90 percent');
        expect(x.where((v) => v.abs() >= 32767).length, 0, reason: 'no sample at full scale');
        expect(rms(x, 0, x.length), greaterThan(0.05 * 32767), reason: 'clearly audible');
        // no offset from zero, which would click when the sound starts or stops
        final mean = x.fold<int>(0, (a, b) => a + b) / x.length;
        expect(mean.abs(), lessThan(0.02 * 32767));
      });

      test('${s.name}: the loop seam is continuous, in the samples and in loudness', () {
        final x = samplesOf(made[s.id]!, length: s.seconds * soundRate);
        final n = x.length;
        final steps = [for (var i = 1; i < n; i++) (x[i] - x[i - 1]).abs()]..sort();
        final seam = (x[0] - x[n - 1]).abs();
        // the step from the last sample back to the first is an ordinary one: no larger than 999 in 1000 of the rest
        expect(seam, lessThanOrEqualTo(steps[(steps.length * 0.999).floor()]),
            reason: 'seam step $seam, median step ${steps[steps.length ~/ 2]}');
        // and the level just before the seam matches the level just after it
        final quarter = soundRate ~/ 4;
        final before = rms(x, n - quarter, n), after = rms(x, 0, quarter);
        expect(math.max(before, after) / math.min(before, after), lessThan(1.6),
            reason: 'before ${before.round()}, after ${after.round()}');
      });
    }

    test('the same seed makes the same sound; another seed makes another', () {
      for (final s in soundscapes) {
        expect(renderScape(s.id), made[s.id], reason: s.id);
      }
      expect(renderScape('rain', seed: 2), isNot(made['rain']));
      expect(renderScape('brown', seed: 1), isNot(made['rain']));
    });

    test('each soundscape is made in well under a second', () {
      renderScape('rain'); // warm up the code first, as it is on a phone after the first sound
      for (final s in soundscapes) {
        final watch = Stopwatch()..start();
        renderScapeSamples(s);
        final ms = watch.elapsedMilliseconds;
        // ignore: avoid_print
        print('${s.id}: made in $ms ms');
        expect(ms, lessThan(1000), reason: s.id);
      }
    });

    test('the limiter rounds peaks off smoothly and never reaches full scale', () {
      expect(softLimit(0.3), 0.3);
      expect(softLimit(-0.6), -0.6);
      for (final v in [0.7, 1.0, 2.0, 10.0, 1e6]) {
        expect(softLimit(v), lessThanOrEqualTo(0.9));
        expect(softLimit(-v), -softLimit(v));
      }
      expect(softLimit(0.61) - softLimit(0.6), closeTo(0.01, 0.001), reason: 'no corner at the knee');
    });

    test('the settings know every soundscape', () {
      expect(Settings.scapeIds, {'none', ...soundscapes.map((s) => s.id)});
    });
  });

  group('bells', () {
    for (final kind in BellKind.values) {
      test('the ${kind.name} bell: a valid WAV, soft at the start, quieter every second, silent at the end', () {
        final spec = bellSpecs[kind]!;
        final wav = renderBell(kind);
        expect(wav.length, bellFileBytes(kind));
        final x = samplesOf(wav, length: spec.seconds * soundRate);
        final top = peak(x, 0, x.length);
        expect(top / 32767, lessThanOrEqualTo(0.33), reason: 'soft, never startling');
        expect(top / 32767, greaterThan(0.15), reason: 'still clearly heard');
        // a felt beater, not a strike: the first 10 ms stay well below the bell's height
        expect(peak(x, 0, soundRate ~/ 100), lessThan(0.3 * top));
        final seconds = [for (var s = 0; s < spec.seconds; s++) rms(x, s * soundRate, (s + 1) * soundRate)];
        for (var s = 1; s < seconds.length; s++) {
          expect(seconds[s], lessThan(seconds[s - 1]), reason: 'second $s is not quieter than the one before');
        }
        expect(peak(x, x.length - soundRate ~/ 20, x.length), lessThan(33), reason: 'the last 50 ms are silent (-60 dB)');
        expect(renderBell(kind), wav, reason: 'the same every time');
      });
    }

    test('the interval bell is higher and shorter than the starting bell, the ending bell lower and longer', () {
      final start = bellSpecs[BellKind.start]!, interval = bellSpecs[BellKind.interval]!, end = bellSpecs[BellKind.end]!;
      expect(interval.hz, greaterThan(start.hz));
      expect(interval.seconds, lessThan(start.seconds));
      expect(end.hz, lessThan(start.hz));
      expect(end.seconds, greaterThan(start.seconds));
    });
  });

  group('the quiet timer counts from the clock', () {
    late DateTime now;
    setUp(() => now = DateTime(2026, 11, 14, 7));

    test('the bells: start, every two minutes, never at the very end, then the end', () {
      final sit = SitTimer(const SitPlan(length: Duration(minutes: 10), interval: Duration(minutes: 2)), clock: () => now);
      expect(sit.plan.intervalTimes, [for (final m in [2, 4, 6, 8]) Duration(minutes: m)]);
      expect(sit.start(), [BellKind.start]);
      final rung = <(int, BellKind)>[];
      for (var s = 1; s <= 600; s++) {
        now = now.add(const Duration(seconds: 1));
        for (final b in sit.poll()) {
          rung.add((s, b));
        }
      }
      expect(rung, [(120, BellKind.interval), (240, BellKind.interval), (360, BellKind.interval),
          (480, BellKind.interval), (600, BellKind.end)]);
      expect(sit.state, SitState.finished);
      expect(sit.left, Duration.zero);
      expect(sit.progress, 1);
    });

    test('a pause stops the time and the bells; resuming carries on where it was', () {
      final sit = SitTimer(const SitPlan(length: Duration(minutes: 5), interval: Duration(minutes: 1)), clock: () => now);
      sit.start();
      now = now.add(const Duration(seconds: 50));
      expect(sit.poll(), isEmpty);
      sit.pause();
      now = now.add(const Duration(minutes: 30));
      expect(sit.poll(), isEmpty);
      expect(sit.elapsed, const Duration(seconds: 50));
      expect(sit.left, const Duration(minutes: 4, seconds: 10));
      sit.resume();
      now = now.add(const Duration(seconds: 9));
      expect(sit.poll(), isEmpty);
      now = now.add(const Duration(seconds: 1));
      expect(sit.poll(), [BellKind.interval]);
    });

    test('after a long gap only one interval bell rings, and past the end only the ending bell', () {
      final sit = SitTimer(const SitPlan(length: Duration(minutes: 20), interval: Duration(minutes: 1)), clock: () => now);
      sit.start();
      now = now.add(const Duration(minutes: 7, seconds: 30));
      expect(sit.poll(), [BellKind.interval]);
      expect(sit.poll(), isEmpty);
      now = now.add(const Duration(minutes: 30));
      expect(sit.poll(), [BellKind.end]);
      expect(sit.poll(), isEmpty);
    });

    test('bells that are turned off do not ring, and ending early rings nothing', () {
      final quiet = SitTimer(const SitPlan(length: Duration(minutes: 3), startBell: false, endBell: false),
          clock: () => now);
      expect(quiet.start(), isEmpty);
      now = now.add(const Duration(minutes: 4));
      expect(quiet.poll(), isEmpty);
      expect(quiet.state, SitState.finished);
      final early = SitTimer(const SitPlan(length: Duration(minutes: 10)), clock: () => now);
      early.start();
      now = now.add(const Duration(minutes: 3));
      early.end();
      now = now.add(const Duration(minutes: 30));
      expect(early.poll(), isEmpty);
      expect(early.state, SitState.ended);
      expect(early.elapsed, const Duration(minutes: 3));
    });

    test('an interval as long as the sit never rings', () {
      expect(const SitPlan(length: Duration(minutes: 5), interval: Duration(minutes: 5)).intervalTimes, isEmpty);
      expect(const SitPlan(length: Duration(minutes: 5)).intervalTimes, isEmpty);
    });
  });

  group('the sleep wind-down', () {
    test('steady for two thirds, then an even fade to silence at the end', () {
      const w = WindDown(Duration(minutes: 30));
      expect(w.fade, const Duration(minutes: 10));
      expect(w.volumeAt(Duration.zero, 0.6), 0.6);
      expect(w.volumeAt(const Duration(minutes: 20), 0.6), 0.6);
      expect(w.volumeAt(const Duration(minutes: 25), 0.6), closeTo(0.3, 1e-9));
      expect(w.volumeAt(const Duration(minutes: 30), 0.6), 0);
      var last = 1.0;
      for (var s = 0; s <= 1800; s += 10) {
        final v = w.volumeAt(Duration(seconds: s), 0.6);
        expect(v, lessThanOrEqualTo(last));
        last = v;
      }
    });

    test('the fade lasts at least five minutes', () {
      expect(const WindDown(Duration(minutes: 15)).fade, const Duration(minutes: 5));
      expect(const WindDown(Duration(minutes: 60)).fade, const Duration(minutes: 20));
    });
  });

  group('kept sound files', () {
    late Directory folder;
    setUp(() async => folder = await Directory.systemTemp.createTemp('solace_sounds_test'));
    tearDown(() => folder.delete(recursive: true));

    test('made once into sounds/ in the folder given, whole, then reused', () async {
      final cache = SoundCache(folder: () async => folder);
      final rain = soundscapeById('rain')!;
      final file = await cache.scape(rain);
      expect(file.path, '${folder.path}/sounds/rain_1_v$soundsVersion.wav');
      expect(await file.length(), scapeFileBytes(rain));
      expect(await file.readAsBytes(), renderScape('rain'));
      expect(folder.listSync(recursive: true).where((f) => f.path.endsWith('.part')), isEmpty);
      final made = (await file.stat()).modified;
      final again = await SoundCache(folder: () async => folder).scape(rain);
      expect(again.path, file.path);
      expect((await again.stat()).modified, made, reason: 'the kept file is used, not made again');
      final bell = await cache.bell(BellKind.end);
      expect(await bell.length(), bellFileBytes(BellKind.end));
    });

    test('a file of the wrong size (cut short) is made again', () async {
      final brown = soundscapeById('brown')!;
      Directory('${folder.path}/sounds').createSync();
      final f = File('${folder.path}/sounds/brown_1_v$soundsVersion.wav')..writeAsBytesSync([1, 2, 3]);
      final file = await SoundCache(folder: () async => folder).scape(brown);
      expect(file.path, f.path);
      expect(await file.length(), scapeFileBytes(brown));
    });
  });

  group('settings', () {
    test('the timer and soundscape choices are kept, with safe defaults for anything missing or odd', () {
      final fresh = Settings.fromJson({});
      expect((fresh.sitMinutes, fresh.sitInterval, fresh.sitStartBell, fresh.sitEndBell, fresh.sitScape),
          (10, 0, true, true, 'none'));
      expect((fresh.scape, fresh.scapeVolume, fresh.windDownMinutes), ('rain', 0.6, 30));
      final s = Settings()
        ..sitMinutes = 45
        ..sitInterval = 5
        ..sitStartBell = false
        ..sitScape = 'ocean'
        ..scape = 'fire'
        ..scapeVolume = 0.35
        ..windDownMinutes = 60;
      final back = Settings.fromJson(s.toJson());
      expect((back.sitMinutes, back.sitInterval, back.sitStartBell, back.sitEndBell, back.sitScape),
          (45, 5, false, true, 'ocean'));
      expect((back.scape, back.scapeVolume, back.windDownMinutes), ('fire', 0.35, 60));
      final odd = Settings.fromJson({'sit_minutes': 900, 'sit_interval': 7, 'sit_scape': 'traffic', 'scape': 'none',
          'scape_volume': double.nan, 'wind_down_minutes': 20, 'sit_start_bell': 'yes'});
      expect((odd.sitMinutes, odd.sitInterval, odd.sitScape, odd.scape, odd.scapeVolume, odd.windDownMinutes),
          (120, 0, 'none', 'rain', 0.6, 30));
      expect(odd.sitStartBell, isTrue);
    });
  });
}
