// Playing the sounds made on the device (core/soundscape.dart, core/bell.dart) with audioplayers, the package that
// already speaks the replies (core/sherpa_voice.dart). Each sound is made once, on another isolate so the screen never
// stutters, and kept as a WAV in a sounds/ folder inside the app's support folder: never the temporary folder (the
// security review flagged /tmp on Linux). The files hold nothing personal, only generated sound. Nothing touches the
// network. The screens talk to SoundPlayer, so the tests use a silent one.
//
// The device's audio settings are left as they are (shared with the voice), so the bells and soundscapes play with
// the silent switch on, as meditation timers usually do. Solace cannot keep the screen awake without another package;
// if the phone locks, the timer keeps the right time from the clock, but the iPhone may hold a bell back until the app
// is opened again (docs/DECISIONS.md, 2026-11-14).
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'bell.dart';
import 'soundscape.dart';

/// What the timer and soundscape screens ask of the sound. Volumes are on the slider's scale, 0 to 1.
abstract class SoundPlayer {
  /// Plays [scape] round and round in place of any other; false if it could not play on this device.
  Future<bool> loop(Soundscape scape, {required double volume});
  Future<void> volume(double v);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> bell(BellKind kind);
  Future<void> dispose();

  /// How the screens get a player; the tests put a silent one here.
  static SoundPlayer Function() create = DeviceSoundPlayer.new;
}

/// Plays nothing and remembers what it was asked: for the tests, and anywhere sound is not wanted.
class SilentSoundPlayer implements SoundPlayer {
  final events = <String>[];
  double? lastVolume;
  @override
  Future<bool> loop(Soundscape scape, {required double volume}) async {
    events.add('loop ${scape.id}');
    lastVolume = volume;
    return true;
  }

  @override
  Future<void> volume(double v) async => lastVolume = v;
  @override
  Future<void> pause() async => events.add('pause');
  @override
  Future<void> resume() async => events.add('resume');
  @override
  Future<void> stop() async => events.add('stop');
  @override
  Future<void> bell(BellKind kind) async => events.add('bell ${kind.name}');
  @override
  Future<void> dispose() async => events.add('dispose');
}

/// Bump when a sound's recipe changes, so the kept files are made again.
const soundsVersion = 1;

/// The made sounds, kept in the support folder: each made once, checked by its size, written whole or not at all.
class SoundCache {
  SoundCache({Future<Directory> Function()? folder}) : _folder = folder ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _folder;
  final _making = <String, Future<File>>{};

  Future<File> scape(Soundscape s, {int seed = 1}) =>
      _get('${s.id}_$seed', scapeFileBytes(s), () => _makeScape(s.id, seed));

  Future<File> bell(BellKind kind) => _get('bell_${kind.name}', bellFileBytes(kind), () => _makeBell(kind));

  Future<File> _get(String name, int size, Future<Uint8List> Function() make) {
    final f = _making[name] ??= _fetch(name, size, make);
    f.then((_) {}, onError: (Object _) {
      _making.remove(name); // a failure is tried again next time
    });
    return f;
  }

  Future<File> _fetch(String name, int size, Future<Uint8List> Function() make) async {
    final dir = Directory('${(await _folder()).path}/sounds');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${name}_v$soundsVersion.wav');
    if (await file.exists() && await file.length() == size) return file;
    final bytes = await make();
    final part = File('${file.path}.part'); // a half-written file is never mistaken for a whole one
    await part.writeAsBytes(bytes, flush: true);
    return part.rename(file.path);
  }
}

// Top-level, so the work sent to the other isolate carries only its two small arguments.
Future<Uint8List> _makeScape(String id, int seed) => Isolate.run(() => renderScape(id, seed: seed));
Future<Uint8List> _makeBell(BellKind kind) => Isolate.run(() => renderBell(kind));

/// The real player: one audioplayers player for the soundscape (looping) and one for the bells, made on first use so
/// opening a screen touches no audio at all.
class DeviceSoundPlayer implements SoundPlayer {
  DeviceSoundPlayer({SoundCache? cache}) : _cache = cache ?? SoundCache();
  final SoundCache _cache;
  AudioPlayer? _scape, _bell;
  int _asked = 0; // the newest choice wins when two overlap
  bool _disposed = false; // a sound still being made when its screen closes is never played

  // the slider's scale to the player's: the square, so each step of the slider sounds about the same
  static double _gain(double v) => (v * v).clamp(0.0, 1.0);

  @override
  Future<bool> loop(Soundscape scape, {required double volume}) async {
    final asked = ++_asked;
    try {
      final file = await _cache.scape(scape);
      if (asked != _asked || _disposed) return true; // something else was chosen meanwhile, or the screen closed
      final p = _scape ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(DeviceFileSource(file.path), volume: _gain(volume));
      return true;
    } catch (_) {
      return false; // the screen says so; the timer itself still works
    }
  }

  @override
  Future<void> volume(double v) => _quietly(() async => _scape?.setVolume(_gain(v)));
  @override
  Future<void> pause() => _quietly(() async => _scape?.pause());
  @override
  Future<void> resume() => _quietly(() async => _scape?.resume());
  @override
  Future<void> stop() {
    _asked++;
    return _quietly(() async => _scape?.stop());
  }

  @override
  Future<void> bell(BellKind kind) => _quietly(() async {
        final file = await _cache.bell(kind);
        if (_disposed) return;
        final p = _bell ??= AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.play(DeviceFileSource(file.path), volume: 1);
      });

  @override
  Future<void> dispose() async {
    _asked++;
    _disposed = true;
    await _quietly(() async => _scape?.dispose());
    await _quietly(() async => _bell?.dispose());
  }

  // A sound that cannot play (no audio device, a plugin missing) never breaks a screen.
  Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}
