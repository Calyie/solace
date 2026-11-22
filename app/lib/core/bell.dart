// The timer's bells, made on the device like a singing bowl: a few inharmonic partials (the bowl's own overtones, not
// a piano's), each a pair of close tones that beat slowly (the bowl's shimmer), each dying away at its own rate, the
// higher ones sooner. A soft start, like a felt beater, never a strike: the report asks for one soft chime when the
// eyes may be closed, never startling. Pure Dart, like core/soundscape.dart, so the tests can check every sample.
import 'dart:math' as math;
import 'dart:typed_data';

import 'soundscape.dart' show soundRate, toPcm16, wavBytes;

enum BellKind { start, interval, end }

/// One bell: its lowest note, how long it rings, how loud at its height (full scale 1), and how slowly it dies away.
class BellSpec {
  const BellSpec(this.hz, this.seconds, this.peak, this.decay);
  final double hz;
  final int seconds;
  final double peak;
  final double decay; // stretches every partial's dying away
}

/// The starting bell; the interval bell a fourth higher, shorter and quieter (a reminder, not an ending); the ending
/// bell a fourth lower and the longest, to settle on.
const bellSpecs = <BellKind, BellSpec>{
  BellKind.start: BellSpec(216, 8, 0.30, 1.0),
  BellKind.interval: BellSpec(288, 5, 0.22, 0.7),
  BellKind.end: BellSpec(162, 10, 0.32, 1.25),
};

// The partials of a small bowl: (ratio to the lowest note, level, seconds to fall to a third, how fast it beats in Hz)
const _partials = [(1.0, 1.0, 2.6, 0.8), (2.71, 0.42, 1.6, 1.4), (5.12, 0.18, 0.9, 2.2), (8.37, 0.07, 0.5, 3.1)];

/// The bell's samples, from -1 to 1: [BellSpec.seconds] long, softly begun, fading to silence at the very end.
Float64List renderBellSamples(BellKind kind) {
  final spec = bellSpecs[kind]!;
  final n = spec.seconds * soundRate;
  final out = Float64List(n);
  const attack = 0.03; // seconds: a felt beater, not a strike
  const release = 1.5; // the last second and a half fades all the way out
  for (final (ratio, level, tau, beat) in _partials) {
    final f = spec.hz * ratio;
    final w1 = 2 * math.pi * f / soundRate, w2 = 2 * math.pi * (f + beat) / soundRate;
    final r = math.exp(-1 / (tau * spec.decay * soundRate));
    var env = level;
    for (var i = 0; i < n; i++) {
      out[i] += env * (math.sin(w1 * i) + 0.35 * math.sin(w2 * i + 1.1));
      env *= r;
    }
  }
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / soundRate;
    var shape = 1.0;
    if (t < attack) shape = 0.5 - 0.5 * math.cos(math.pi * t / attack);
    final left = spec.seconds - t;
    if (left < release) shape *= 0.5 - 0.5 * math.cos(math.pi * left / release);
    out[i] *= shape;
    peak = math.max(peak, out[i].abs());
  }
  final gain = peak > 0 ? spec.peak / peak : 0.0;
  for (var i = 0; i < n; i++) {
    out[i] *= gain;
  }
  return out;
}

/// The bell as a WAV file's bytes. A plain function of its argument, so it can run on another isolate.
Uint8List renderBell(BellKind kind) => wavBytes(toPcm16(renderBellSamples(kind)));

/// The size of the bell's WAV file in bytes.
int bellFileBytes(BellKind kind) => 44 + bellSpecs[kind]!.seconds * soundRate * 2;
