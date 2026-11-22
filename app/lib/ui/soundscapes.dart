// Soundscapes and the sleep wind-down (the premium design report, P1 item 12 and P2 item 29). Rain, ocean waves, brown
// noise, wind in the trees and a fire, each made on the device the first time it is played (core/soundscape.dart)
// and kept, never downloaded. One plays at a time, round and round, while this screen is open. The wind-down plays
// one steadily, then lets it fade to silence over the last third and stops, on a dimmed screen; nothing rings at the
// end.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/screen_awake.dart';
import '../core/sit_timer.dart';
import '../core/sound_player.dart';
import '../core/soundscape.dart';
import 'premium.dart';
import 'theme.dart';

/// One quiet icon for each soundscape.
IconData scapeIcon(String id) => const {
      'rain': Icons.water_drop_outlined, 'ocean': Icons.waves, 'brown': Icons.graphic_eq, 'wind': Icons.air,
      'fire': Icons.local_fire_department_outlined,
    }[id] ?? Icons.music_note_outlined;

/// The wind-down's lengths, in minutes.
const windDownLengths = [15, 30, 45, 60];

/// A volume slider between a quiet and a loud speaker.
class VolumeRow extends StatelessWidget {
  const VolumeRow({super.key, required this.value, required this.onChanged, this.onChangeEnd});
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(children: [
      Icon(Icons.volume_down_outlined, color: muted),
      Expanded(child: Slider(value: value, onChanged: onChanged, onChangeEnd: onChangeEnd,
          semanticFormatterCallback: (v) => 'Volume ${(v * 100).round()} percent')),
      Icon(Icons.volume_up_outlined, color: muted),
    ]);
  }
}

class SoundscapesScreen extends StatefulWidget {
  const SoundscapesScreen({super.key, this.windDownFirst = false, this.sounds, this.clock});
  final bool windDownFirst; // opened from the Sleep wind-down card: the wind-down is brought into view
  final SoundPlayer? sounds; // the tests pass a silent one; otherwise SoundPlayer.create
  final DateTime Function()? clock;
  @override
  State<SoundscapesScreen> createState() => _SoundscapesScreenState();
}

class _SoundscapesScreenState extends State<SoundscapesScreen> {
  late final SoundPlayer _sounds = widget.sounds ?? SoundPlayer.create();
  final _windDownKey = GlobalKey();
  bool _loaded = false;
  String? _playing; // the soundscape playing now
  bool _preparing = false; // being made, the first time it is played
  bool _failed = false;
  int _asked = 0;
  String _scape = 'rain'; // the last chosen, used by the wind-down
  double _volume = 0.6;
  int _windDown = 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = AppScope.of(context).data.settings;
    _scape = s.scape;
    _volume = s.scapeVolume;
    _windDown = s.windDownMinutes;
    if (widget.windDownFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _windDownKey.currentContext;
        if (c != null && c.mounted) {
          Scrollable.ensureVisible(c, duration: MediaQuery.disableAnimationsOf(c) ? Duration.zero : Calm.slow,
              curve: Calm.curve);
        }
      });
    }
  }

  @override
  void dispose() {
    if (_playing != null) unawaited(_sounds.stop());
    if (widget.sounds == null) unawaited(_sounds.dispose());
    super.dispose();
  }

  void _keep() {
    final state = AppScope.of(context);
    state.data.settings
      ..scape = _scape
      ..scapeVolume = _volume
      ..windDownMinutes = _windDown;
    unawaited(state.save());
  }

  Future<void> _toggle(Soundscape s) async {
    feelChoice();
    final asked = ++_asked;
    if (_playing == s.id) {
      setState(() {
        _playing = null;
        _preparing = false;
      });
      await _sounds.stop();
      return;
    }
    setState(() {
      _playing = s.id;
      _scape = s.id;
      _preparing = true;
      _failed = false;
    });
    _keep();
    final ok = await _sounds.loop(s, volume: _volume);
    if (!mounted || asked != _asked) return;
    setState(() {
      _preparing = false;
      if (!ok) {
        _failed = true;
        _playing = null;
      }
    });
  }

  Future<void> _startWindDown() async {
    feelDone();
    _keep();
    if (_playing != null) {
      _asked++;
      setState(() => _playing = null);
      await _sounds.stop();
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WindDownScreen(
        scape: soundscapeById(_scape) ?? soundscapes.first, minutes: _windDown, volume: _volume,
        sounds: widget.sounds, clock: widget.clock)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final chosen = soundscapeById(_scape) ?? soundscapes.first;
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Soundscapes')),
      body: SafeArea(top: false, child: Readable(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text('Made on this device as you listen. Nothing is downloaded. Tap one to play it, and again to stop.',
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: Space.l),
        LayoutBuilder(builder: (context, box) {
          final two = box.maxWidth >= 600;
          final w = two ? (box.maxWidth - Space.m) / 2 : box.maxWidth;
          return Wrap(spacing: Space.m, children: [
            for (final s in soundscapes) SizedBox(width: w, child: _ScapeTile(scape: s, playing: _playing == s.id,
                preparing: _preparing && _playing == s.id, onTap: () => _toggle(s))),
          ]);
        }),
        if (_failed)
          Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(
              'The sound could not play on this device. The rest of Solace works as usual.', style: t.bodySmall)),
        const SizedBox(height: Space.s),
        VolumeRow(key: const Key('scape_volume'), value: _volume, onChanged: (v) {
          setState(() => _volume = v);
          if (_playing != null) unawaited(_sounds.volume(v));
        }, onChangeEnd: (_) => _keep()),
        Text('The sound plays while this screen is open.', style: t.bodySmall, textAlign: TextAlign.center),
        SectionHeader('Sleep wind-down', key: _windDownKey),
        Text('${chosen.name} plays steadily, then fades to silence over the last stretch. The screen dims, and nothing '
            'rings at the end. Choose another sound above if you like.', style: t.bodyMedium),
        const SizedBox(height: Space.m),
        Wrap(spacing: Space.s, runSpacing: Space.s, children: [
          for (final m in windDownLengths)
            ChoiceChip(key: Key('wind_down_$m'), label: Text('$m min'), selected: _windDown == m, onSelected: (_) {
              feelChoice();
              setState(() => _windDown = m);
            }),
        ]),
        const SizedBox(height: Space.l),
        FilledButton.icon(key: const Key('wind_down_start'), onPressed: _startWindDown,
            icon: const Icon(Icons.bedtime_outlined), label: const Text('Start the wind-down')),
      ]))),
    );
  }
}

class _ScapeTile extends StatelessWidget {
  const _ScapeTile({required this.scape, required this.playing, required this.preparing, required this.onTap});
  final Soundscape scape;
  final bool playing, preparing;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(button: true, selected: playing, label: playing ? '${scape.name}, playing' : scape.name,
        excludeSemantics: true, child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: playing ? scheme.primary : scheme.outlineVariant, width: playing ? 1.5 : 1)),
      child: InkWell(key: Key('scape_${scape.id}'), borderRadius: BorderRadius.circular(20), onTap: onTap,
          child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m + 2, Space.m, Space.m + 2), child: Row(children: [
        AnimatedContainer(duration: Calm.quick, curve: Calm.curve, width: 42, height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, color: playing ? scheme.primary : scheme.primaryContainer),
            child: Icon(scapeIcon(scape.id), size: 22, color: playing ? scheme.onPrimary : scheme.onPrimaryContainer)),
        const SizedBox(width: Space.m + 2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(scape.name, style: t.titleSmall),
          const SizedBox(height: 2),
          Text(preparing ? 'Making the sound...' : playing ? 'Playing' : scape.line,
              style: playing || preparing
                  ? t.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600) : t.bodySmall),
        ])),
        const SizedBox(width: Space.s),
        if (preparing)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded, size: 26,
              color: playing ? scheme.primary : scheme.onSurfaceVariant),
      ]))),
    ));
  }
}

/// The sleep wind-down: always dark (the palette's own dark colours), and after ten seconds without a touch it dims
/// further; a tap brings it back. The sound fades out (core/sit_timer.dart, WindDown) and stops; nothing rings.
class WindDownScreen extends StatefulWidget {
  const WindDownScreen({super.key, required this.scape, required this.minutes, required this.volume, this.sounds,
      this.clock, this.tick = const Duration(seconds: 1)});
  final Soundscape scape;
  final int minutes;
  final double volume;
  final SoundPlayer? sounds;
  final DateTime Function()? clock;
  final Duration tick;
  @override
  State<WindDownScreen> createState() => _WindDownScreenState();
}

class _WindDownScreenState extends State<WindDownScreen> {
  late final SoundPlayer _sounds = widget.sounds ?? SoundPlayer.create();
  late final WindDown _plan = WindDown(Duration(minutes: widget.minutes));
  late final DateTime _start;
  late DateTime _touched;
  late double _set = widget.volume; // the volume last given to the player
  Timer? _ticker;
  bool _over = false, _dim = false, _playing = false, _failed = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _start = _touched = _now();
    _playing = true;
    _sounds.loop(widget.scape, volume: widget.volume).then((ok) {
      if (!ok && mounted) setState(() => _failed = true);
    });
    _ticker = Timer.periodic(widget.tick, (_) => _tick());
    ScreenAwake.hold(); // dimmed but on: an iPhone that locks would pause Solace and stop the sound
    _awake = true;
  }

  bool _awake = false;

  void _letSleep() {
    if (!_awake) return;
    _awake = false;
    ScreenAwake.release();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _letSleep();
    if (_playing) unawaited(_sounds.stop());
    if (widget.sounds == null) unawaited(_sounds.dispose());
    super.dispose();
  }

  void _tick() {
    final now = _now();
    final elapsed = now.difference(_start);
    if (elapsed >= _plan.length) {
      _ticker?.cancel();
      _playing = false;
      unawaited(_sounds.stop()); // silence, then nothing more: no bell
      _letSleep(); // and the phone may sleep as usual
      setState(() => _over = true);
      return;
    }
    final v = _plan.volumeAt(elapsed, widget.volume);
    if ((v - _set).abs() >= 0.004) { // small steps, far below what the ear can tell apart
      _set = v;
      unawaited(_sounds.volume(v));
    }
    setState(() => _dim = now.difference(_touched) >= const Duration(seconds: 10));
  }

  void _touch() {
    _touched = _now();
    if (_dim) setState(() => _dim = false);
  }

  void _stop() {
    feelChoice();
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).data.settings;
    final dark = themeFor(Brightness.dark, Look(font: s.font, accent: s.accent, serif: s.serif));
    final still = MediaQuery.disableAnimationsOf(context);
    final left = _plan.length - _now().difference(_start);
    final minutesLeft = (left.inSeconds / 60).ceil().clamp(0, widget.minutes);
    return Theme(data: dark, child: Builder(builder: (context) {
      final t = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      // light status bar icons on the dark screen, whatever the app's own theme
      return AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        // any touch wakes the screen; while it is dim, that first touch only wakes it
        body: Listener(key: const Key('wind_down_wake'), behavior: HitTestBehavior.opaque, onPointerDown: (_) => _touch(),
            child: IgnorePointer(ignoring: _dim,
                child: AnimatedOpacity(opacity: _dim ? 0.2 : 1, duration: still ? Duration.zero : const Duration(seconds: 2),
                    curve: Calm.curve, child: SafeArea(child: Readable(child: FillOrScroll(padding: const EdgeInsets.all(Space.xl),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(),
          Icon(Icons.bedtime_outlined, size: 36, color: scheme.primary),
          const SizedBox(height: Space.l),
          Text(_over ? 'Sleep well.' : 'Rest now. Let the sound carry you.', textAlign: TextAlign.center,
              style: voiceStyle(context, size: 30)),
          const SizedBox(height: Space.m),
          Text(_over ? 'The sound has faded.' : _failed ? 'The sound could not play on this device.'
              : '${widget.scape.name}, fading to silence over ${widget.minutes} minutes',
              textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          if (!_over) ...[
            const SizedBox(height: Space.xs),
            Text(minutesLeft <= 1 ? 'About a minute left' : '$minutesLeft minutes left', key: const Key('wind_down_left'),
                textAlign: TextAlign.center, style: t.bodySmall),
          ],
          const Spacer(),
          Center(child: _over
              ? TextButton(key: const Key('wind_down_done'), onPressed: _stop, child: const Text('Close'))
              : TextButton.icon(key: const Key('wind_down_stop'), onPressed: _stop, icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'))),
        ]))))))),
      ));
    }));
  }
}
