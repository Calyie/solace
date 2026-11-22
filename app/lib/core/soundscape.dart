// Soundscapes made on the device in plain Dart: no recorded audio and nothing downloaded (the premium design report,
// P1 item 12 and P2 item 29). Each one is a loop of 16-bit mono sound at 22,050 Hz, made a little longer than it
// plays so that its end can be crossfaded into its start: it repeats without a seam or a click. Slow changes (the
// waves, the gusts of wind, the rain growing and easing) repeat exactly once per loop, so they meet themselves at the
// seam too. The same seed always makes the same sound, on every device. Kept free of Flutter and plugins so the
// tests can check every sample; core/sound_player.dart writes it to a file and plays it.
import 'dart:math' as math;
import 'dart:typed_data';

/// Samples a second: plenty for soft, low sounds, and half the size of CD quality.
const soundRate = 22050;

/// One soundscape: the id kept in Settings, the name shown, a short line about it, how long its loop is, and how it
/// is made.
class Soundscape {
  const Soundscape(this.id, this.name, this.line, this._make, this._salt, {this.seconds = 40, this.loudness = 0.14});
  final String id;
  final String name;
  final String line;
  final int seconds; // the length of the loop
  final double loudness; // the level it is set to (root mean square, full scale 1), before the gentle limiter
  final void Function(Float64List out, Grain grain, int warm, int loop) _make;
  final int _salt; // so two soundscapes with the same seed never share their noise

  int get samples => seconds * soundRate;
}

/// Every soundscape, in the order they are offered.
const soundscapes = <Soundscape>[
  Soundscape('rain', 'Rain', 'A steady shower, soft and close.', _rain, 11),
  Soundscape('ocean', 'Ocean waves', 'Slow waves rolling in and drawing back.', _ocean, 23),
  Soundscape('brown', 'Brown noise', 'A deep, even hush that covers other sounds.', _brown, 37, loudness: 0.16),
  Soundscape('wind', 'Wind in the trees', 'A gentle wind rising and falling in the leaves.', _wind, 41, loudness: 0.12),
  Soundscape('fire', 'Fire', 'A low fire with the odd quiet crackle.', _fire, 53, loudness: 0.12),
];

Soundscape? soundscapeById(String id) {
  for (final s in soundscapes) {
    if (s.id == id) return s;
  }
  return null;
}

/// A small, fast random source (xorshift32): the same seed gives the same numbers on every device, which the
/// library's own Random does not promise.
class Grain {
  Grain(int seed) : _s = ((seed * 0x9E3779B1) ^ 0x6D2B79F5) & 0xFFFFFFFF {
    if (_s == 0) _s = 0x1234567;
  }
  int _s;

  /// A number from 0 up to (not including) 1.
  double next() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x;
    return x / 4294967296.0;
  }

  /// White noise: a number from -1 up to 1.
  double white() => next() * 2 - 1;
}

/// The samples of [scape], ready to write: exactly [Soundscape.samples] long, from -1 to 1, the loop seam crossfaded.
Float64List renderScapeSamples(Soundscape scape, {int seed = 1}) {
  final n = scape.samples;
  const warm = soundRate ~/ 2; // half a second first, so every filter has settled before the loop begins
  const fade = 2 * soundRate; // the crossfade at the seam
  final raw = Float64List(warm + n + fade);
  scape._make(raw, Grain(seed * 7919 + scape._salt), warm, n);
  // The seam: the loop's first two seconds are a crossfade from what follows its last sample (which carries straight
  // on from it) into its own start. Equal power, since the two are unrelated noise: the level never dips.
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = raw[warm + i];
  }
  for (var i = 0; i < fade; i++) {
    final t = (i + 0.5) / fade * math.pi / 2;
    out[i] = raw[warm + i] * math.sin(t) + raw[warm + n + i] * math.cos(t);
  }
  // the level: each soundscape set to its own loudness, then a gentle limiter that can never reach full scale
  var sum = 0.0;
  for (final v in out) {
    sum += v * v;
  }
  final rms = math.sqrt(sum / n);
  final gain = rms > 0 ? scape.loudness / rms : 0.0;
  for (var i = 0; i < n; i++) {
    out[i] = softLimit(out[i] * gain);
  }
  return out;
}

/// Unchanged up to 0.6, then rounded off smoothly towards 0.9: peaks are softened, never clipped.
double softLimit(double x) {
  final a = x.abs();
  if (a <= 0.6) return x;
  final y = 0.6 + 0.3 * _tanh((a - 0.6) / 0.3);
  return x < 0 ? -y : y;
}

double _tanh(double x) {
  if (x > 20) return 1; // exp would overflow; tanh is 1 to every digit a double holds
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// [scape] as a WAV file's bytes. A plain function of its arguments, so it can run on another isolate.
Uint8List renderScape(String id, {int seed = 1}) => wavBytes(toPcm16(renderScapeSamples(soundscapeById(id)!, seed: seed)));

/// The size of [scape]'s WAV file in bytes: the 44-byte header and two bytes a sample.
int scapeFileBytes(Soundscape scape) => 44 + scape.samples * 2;

/// -1 to 1 as 16-bit whole numbers.
Int16List toPcm16(Float64List x) {
  final out = Int16List(x.length);
  for (var i = 0; i < x.length; i++) {
    out[i] = (x[i] * 32767).round().clamp(-32767, 32767);
  }
  return out;
}

/// A mono 16-bit WAV file: the standard 44-byte header, then the samples, little-endian.
Uint8List wavBytes(Int16List pcm, {int rate = soundRate}) {
  final data = pcm.length * 2;
  final b = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // the size of the format block
  b.setUint16(20, 1, Endian.little); // plain PCM
  b.setUint16(22, 1, Endian.little); // one channel
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little); // bytes a second
  b.setUint16(32, 2, Endian.little); // bytes a sample
  b.setUint16(34, 16, Endian.little); // bits a sample
  tag(36, 'data');
  b.setUint32(40, data, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    b.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

// ---------------------------------------------------------------------------------------------------------------
// The makers. Each fills [out] (the half-second warm-up, the loop, then the crossfade's two seconds); sample i sits at
// (i - warm) in the loop, so anything periodic in the loop's length uses that.

/// How far a one-pole filter moves towards its input each sample, for a corner at [hz].
double _alpha(double hz) => 1 - math.exp(-2 * math.pi * hz / soundRate);

/// Where sample [i] falls in the loop, from 0 up to 1.
double _phase(int i, int warm, int loop) => ((i - warm) % loop) / loop;

/// Pink noise (equal energy in every octave, softer than white): Paul Kellet's three-pole filter, about unit level.
class _Pink {
  double _b0 = 0, _b1 = 0, _b2 = 0;
  double next(double w) {
    _b0 = 0.99765 * _b0 + w * 0.0990460;
    _b1 = 0.96300 * _b1 + w * 0.2965164;
    _b2 = 0.57000 * _b2 + w * 1.0526913;
    return (_b0 + _b1 + _b2 + w * 0.1848) * 0.45;
  }
}

/// Brown noise: white noise summed with a slow leak, so it falls by half with each octave up; about unit level.
class _Brown {
  double _b = 0;
  double next(double w) => (_b = 0.996 * _b + 0.04 * w) * 2.2;
}

/// A short ringing tone that dies away (a drop, a pop), added into [out] at [at]: [hz], [tau] seconds to fall to a
/// third, [amp] at its height. Made by a two-term recurrence, so it costs a few multiplications a sample.
void _ping(Float64List out, int at, double hz, double tau, double amp) {
  final w = 2 * math.pi * hz / soundRate;
  final r = math.exp(-1 / (tau * soundRate));
  final c = 2 * r * math.cos(w), r2 = r * r;
  final len = math.min((6.9 * tau * soundRate).ceil(), out.length - at); // until it is a thousandth of its height
  var y1 = 0.0, y2 = 0.0;
  for (var k = 0; k < len; k++) {
    final y = k == 0 ? amp * math.sin(w) : (k == 1 ? amp * r * math.sin(2 * w) : c * y1 - r2 * y2);
    out[at + k] += y;
    y2 = y1;
    y1 = y;
  }
}

/// Brown noise: deep and even, softened at the top.
void _brown(Float64List out, Grain g, int warm, int loop) {
  final brown = _Brown();
  final a = _alpha(1400);
  var lp = 0.0;
  for (var i = 0; i < out.length; i++) {
    lp += a * (brown.next(g.white()) - lp);
    out[i] = lp;
  }
}

/// Rain: the hush of a shower (pink noise without its lowest and highest parts, with a little low body, as on a
/// roof), and thousands of small drops, now and then a nearer, rounder one. It grows and eases a little, once a loop.
void _rain(Float64List out, Grain g, int warm, int loop) {
  final pink = _Pink(), brown = _Brown();
  final aLow = _alpha(450), aHigh = _alpha(5200);
  var low = 0.0, high = 0.0;
  for (var i = 0; i < out.length; i++) {
    final p = pink.next(g.white());
    low += aLow * (p - low);
    high += aHigh * (p - high);
    final swell = 1 + 0.12 * math.sin(2 * math.pi * _phase(i, warm, loop) + 0.7);
    out[i] = swell * (0.8 * (high - low) + 0.25 * brown.next(g.white()));
  }
  // the drops: random times (about 170 a second, more when the shower swells), mostly tiny and high, a few rounder
  var t = 0.0;
  while (true) {
    final at = t.floor();
    if (at >= out.length) break;
    final ph = _phase(at, warm, loop);
    final rate = 170 * (1 + 0.25 * math.sin(2 * math.pi * ph + 0.7) + 0.08 * math.sin(6 * math.pi * ph + 2.1));
    final near = g.next() < 0.03;
    final u = g.next();
    if (near) {
      _ping(out, at, 650 + 900 * g.next(), 0.008 + 0.010 * g.next(), 0.10 + 0.12 * u);
    } else {
      _ping(out, at, 1700 + 4000 * g.next(), 0.0012 + 0.0035 * g.next(), 0.22 * u * u * u);
    }
    t += -math.log(1 - g.next()) * soundRate / rate;
  }
  // a last soft roll-off above about 3.8 kHz: rain heard through a window, never a hiss
  final aSoft = _alpha(3800);
  var soft = 0.0;
  for (var i = 0; i < out.length; i++) {
    out[i] = soft += aSoft * (out[i] - soft);
  }
}

/// Ocean waves: each wave between 8 and 12 seconds (stretched so they fill the loop exactly), its own height. The sea
/// swells as a wave rises, brightens as it breaks, and washes back; it never quite falls silent.
void _ocean(Float64List out, Grain g, int warm, int loop) {
  final count = math.max(2, (loop / soundRate / 10).round());
  final lens = [for (var k = 0; k < count; k++) 8 + 4 * g.next()];
  final total = lens.fold<double>(0, (a, b) => a + b);
  final starts = <double>[];
  var at = 0.0;
  for (var k = 0; k < count; k++) {
    lens[k] = lens[k] / total * loop;
    starts.add(at);
    at += lens[k];
  }
  final heights = [for (var k = 0; k < count; k++) 0.65 + 0.35 * g.next()];
  final pink = _Pink(), brown = _Brown();
  var lp = 0.0, hpLow = 0.0, a = _alpha(300), level = 0.0, foam = 0.0;
  final aFoam = _alpha(1800);
  for (var i = 0; i < out.length; i++) {
    if (i % 32 == 0) { // the slow shape, worked out every 32 samples (1.5 ms): smooth to the ear, and quick
      final tt = ((i - warm) % loop).toDouble();
      var k = count - 1;
      while (k > 0 && starts[k] > tt) {
        k--;
      }
      final p = ((tt - starts[k]) / lens[k]).clamp(0.0, 1.0);
      // up slowly for the first 38 percent, then down: zero at both ends, so each wave meets the next
      final e = heights[k] * (p < 0.38
          ? 0.5 - 0.5 * math.cos(math.pi * p / 0.38)
          : math.pow(0.5 + 0.5 * math.cos(math.pi * (p - 0.38) / 0.62), 1.5).toDouble());
      level = 0.28 + 0.72 * e;
      a = _alpha(280 + 2400 * e * e);
      foam = p < 0.38 ? 0 : e * e;
    }
    final w = g.white();
    lp += a * (pink.next(w) - lp);
    hpLow += aFoam * (w - hpLow);
    out[i] = level * (0.9 * lp + 0.5 * brown.next(g.white())) + 0.10 * foam * (w - hpLow);
  }
}

/// Wind in the trees: noise through a soft band filter whose pitch and strength follow slow gusts (swells whose
/// periods divide the loop), with the leaves rustling more as it gusts.
void _wind(Float64List out, Grain g, int warm, int loop) {
  final ph = [for (var k = 0; k < 4; k++) 2 * math.pi * g.next()];
  final brown = _Brown();
  var low = 0.0, band = 0.0, f = 0.1, gust = 0.5, body = 0.5, rustle = 0.25;
  var leafLow = 0.0, flutter = 0.0;
  final aLeaf = _alpha(2400), aFlutter = _alpha(5);
  const damp = 0.9; // a wide, soft band: a breath of wind, never a whistle
  for (var i = 0; i < out.length; i++) {
    if (i % 32 == 0) {
      final x = 2 * math.pi * _phase(i, warm, loop);
      gust = (0.5 + 0.22 * math.sin(2 * x + ph[0]) + 0.15 * math.sin(5 * x + ph[1]) + 0.08 * math.sin(9 * x + ph[2]) +
              0.05 * math.sin(17 * x + ph[3]))
          .clamp(0.05, 1.0);
      f = 2 * math.sin(math.pi * (220 + 700 * gust) / soundRate);
      body = math.pow(gust, 1.5).toDouble();
      rustle = gust * gust;
    }
    final w = g.white();
    // the state-variable filter (Chamberlin): its band output
    low += f * band;
    final high = w - low - damp * band;
    band += f * high;
    leafLow += aLeaf * (w - leafLow);
    flutter += aFlutter * (g.white() - flutter); // the leaves stir in little flurries, a few a second
    final leaves = (w - leafLow) * rustle * (0.6 + 30 * flutter).clamp(0.1, 1.6);
    out[i] = body * band * 2.6 + 0.10 * leaves + 0.18 * (0.5 + 0.5 * gust) * brown.next(g.white());
  }
}

/// Fire: the low roar of the flames, flickering, a faint hiss, and the odd crackle (small clusters of tiny clicks)
/// or soft pop.
void _fire(Float64List out, Grain g, int warm, int loop) {
  final brown = _Brown(), pink = _Pink();
  final aRoar = _alpha(600), aFlicker = _alpha(0.8), aHissLow = _alpha(1500), aHissHigh = _alpha(5000);
  var roar = 0.0, flicker = 0.0, hissLow = 0.0, hissHigh = 0.0;
  for (var i = 0; i < out.length; i++) {
    roar += aRoar * (brown.next(g.white()) - roar);
    flicker += aFlicker * (g.white() - flicker);
    final p = pink.next(g.white());
    hissLow += aHissLow * (p - hissLow);
    hissHigh += aHissHigh * (p - hissHigh);
    out[i] = roar * (0.9 + 25 * flicker).clamp(0.4, 1.5) + 0.06 * (hissHigh - hissLow);
  }
  // crackles: about five a second, each a cluster of one to five clicks within 40 ms
  var t = 0.0;
  while (true) {
    final at = t.floor();
    if (at >= out.length) break;
    final clicks = 1 + (g.next() * g.next() * 5).floor();
    for (var c = 0; c < clicks; c++) {
      final start = at + (g.next() * 0.04 * soundRate).floor();
      final len = ((0.0004 + 0.0025 * g.next()) * soundRate).ceil();
      final u = g.next();
      final amp = 0.04 + 0.30 * u * u * u;
      var prev = 0.0;
      for (var k = 0; k < len && start + k < out.length; k++) {
        final w = g.white();
        out[start + k] += amp * (w - prev) * math.exp(-4 * k / len); // a difference of noise: crisp, not boomy
        prev = w;
      }
    }
    t += -math.log(1 - g.next()) * soundRate / 5;
  }
  // a soft pop now and then
  t = -math.log(1 - g.next()) * soundRate / 0.35;
  while (t < out.length) {
    _ping(out, t.floor(), 120 + 180 * g.next(), 0.012 + 0.012 * g.next(), 0.12 + 0.12 * g.next());
    t += -math.log(1 - g.next()) * soundRate / 0.35;
  }
}
