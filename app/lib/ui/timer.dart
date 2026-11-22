// The quiet timer (the premium design report, P2 item 29, as in Insight Timer and Waking Up): an unguided sit with a
// soft bell to begin and end, an optional interval bell, and an optional soundscape underneath. Full screen while it
// runs: the time left and a slow ring, nothing else; under Reduce Motion just the numbers. The time is counted from
// the clock (core/sit_timer.dart), so it is right even if frames are missed. The screen stays on while a sit runs
// (core/screen_awake.dart: the app's own few lines of platform code, no package). Also the Practices tab's entry to the timer,
// the soundscapes and the sleep wind-down.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/screen_awake.dart';
import '../core/sit_timer.dart';
import '../core/sound_player.dart';
import '../core/soundscape.dart';
import 'premium.dart';
import 'soundscapes.dart';
import 'theme.dart';

/// The lengths offered at a tap, in minutes; any other comes from "Your own".
const sitLengths = [3, 5, 10, 15, 20, 30];

/// The interval bell's choices, in minutes (0: off).
const sitIntervals = [0, 1, 2, 5, 10];

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key, this.sounds, this.clock, this.tick = const Duration(milliseconds: 250)});
  final SoundPlayer? sounds; // the tests pass a silent one; otherwise SoundPlayer.create
  final DateTime Function()? clock;
  final Duration tick;
  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  late final SoundPlayer _sounds = widget.sounds ?? SoundPlayer.create();
  bool _loaded = false;
  int _minutes = 10, _interval = 0;
  bool _startBell = true, _endBell = true;
  String _scape = 'none';
  double _volume = 0.6;

  SitTimer? _sit;
  Timer? _ticker;
  bool _scapeOn = false; // a soundscape is playing (or paused) under the sit
  bool _soundFailed = false;
  DateTime? _finishedAt;
  bool _awake = false; // holding the screen on (core/screen_awake.dart)

  void _keepAwake(bool on) {
    if (on == _awake) return;
    _awake = on;
    on ? ScreenAwake.hold() : ScreenAwake.release();
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = AppScope.of(context).data.settings; // the choices from last time
    _minutes = s.sitMinutes;
    _interval = s.sitInterval < s.sitMinutes ? s.sitInterval : 0;
    _startBell = s.sitStartBell;
    _endBell = s.sitEndBell;
    _scape = s.sitScape;
    _volume = s.scapeVolume;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _keepAwake(false);
    if (_scapeOn) unawaited(_sounds.stop());
    if (widget.sounds == null) unawaited(_sounds.dispose());
    super.dispose();
  }

  void _setLength(int m) {
    feelChoice();
    setState(() {
      _minutes = m;
      if (_interval >= m) _interval = 0; // an interval bell must fall inside the sit
    });
  }

  Future<void> _chooseOwn() async {
    feelChoice();
    final m = await showModalBottomSheet<int>(context: context, isScrollControlled: true,
        builder: (_) => _OwnLength(start: _minutes));
    if (m != null && mounted) _setLength(m);
  }

  void _begin() {
    final state = AppScope.of(context);
    state.data.settings
      ..sitMinutes = _minutes
      ..sitInterval = _interval
      ..sitStartBell = _startBell
      ..sitEndBell = _endBell
      ..sitScape = _scape
      ..scapeVolume = _volume;
    unawaited(state.save());
    feelDone();
    final sit = _sit = SitTimer(SitPlan(length: Duration(minutes: _minutes),
        interval: _interval == 0 ? null : Duration(minutes: _interval), startBell: _startBell, endBell: _endBell),
        clock: _now);
    for (final b in sit.start()) {
      unawaited(_sounds.bell(b));
    }
    final scape = soundscapeById(_scape);
    if (scape != null) {
      _scapeOn = true;
      _sounds.loop(scape, volume: _volume).then((ok) {
        if (!ok && mounted) setState(() => _soundFailed = true);
      });
    }
    _ticker = Timer.periodic(widget.tick, (_) => _onTick());
    _keepAwake(true); // the phone does not lock mid-sit, so the bells ring on time
    setState(() {});
  }

  void _onTick() {
    final sit = _sit!;
    final wasRunning = sit.running;
    for (final b in sit.poll()) {
      unawaited(_sounds.bell(b));
    }
    if (wasRunning && sit.state == SitState.finished) {
      _finishedAt = _now();
      feelDone(); // the one "finished" touch, when the time is really up
    }
    // after the end, the soundscape fades away over five seconds, then stops
    if (_finishedAt != null && _scapeOn) {
      final left = 1 - _now().difference(_finishedAt!).inMilliseconds / 5000;
      if (left <= 0) {
        _scapeOn = false;
        unawaited(_sounds.stop());
      } else {
        unawaited(_sounds.volume(_volume * left));
      }
    }
    if (sit.over && !_scapeOn) {
      _ticker?.cancel(); // nothing left to count
      _keepAwake(false);
    }
    if (mounted) setState(() {});
  }

  void _pauseOrResume() {
    final sit = _sit!;
    feelChoice();
    setState(() {
      if (sit.running) {
        sit.pause();
        if (_scapeOn) unawaited(_sounds.pause());
        _keepAwake(false); // paused: the screen may sleep as usual (OWASP review OW-M8-3)
      } else {
        sit.resume();
        if (_scapeOn) unawaited(_sounds.resume());
        _keepAwake(true);
      }
    });
  }

  void _end() {
    feelChoice();
    _ticker?.cancel();
    _keepAwake(false);
    setState(() {
      _sit!.end();
      if (_scapeOn) {
        _scapeOn = false;
        unawaited(_sounds.stop());
      }
    });
  }

  @override
  Widget build(BuildContext context) => _sit == null ? _setup(context) : _sitting(context, _sit!);

  // ---- choosing ----
  Widget _setup(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final own = !sitLengths.contains(_minutes);
    Widget chips(List<Widget> children) => Wrap(spacing: Space.s, runSpacing: Space.s, children: children);
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Quiet timer')),
      body: SafeArea(top: false, child: Readable(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text('No voice and no guidance. Just you, your breath and a soft bell.',
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SectionHeader('How long'),
        chips([
          for (final m in sitLengths)
            ChoiceChip(key: Key('sit_len_$m'), label: Text('$m min'), selected: _minutes == m,
                onSelected: (_) => _setLength(m)),
          ChoiceChip(key: const Key('sit_len_custom'), label: Text(own ? '$_minutes min, your own' : 'Your own'),
              selected: own, onSelected: (_) => _chooseOwn()),
        ]),
        const SectionHeader('Interval bell'),
        Text('A quiet bell part of the way through, to bring you back.', style: t.bodySmall),
        const SizedBox(height: Space.s),
        chips([
          for (final i in sitIntervals)
            ChoiceChip(key: Key('sit_every_$i'), label: Text(i == 0 ? 'Off' : i == 1 ? 'Every minute' : 'Every $i min'),
                selected: _interval == i,
                onSelected: i == 0 || i < _minutes ? (_) {
                  feelChoice();
                  setState(() => _interval = i);
                } : null),
        ]),
        const SectionHeader('Bells'),
        Card(child: Column(children: [
          SwitchListTile(key: const Key('sit_start_bell'), title: const Text('A bell to begin'), value: _startBell,
              onChanged: (v) {
                feelChoice();
                setState(() => _startBell = v);
              }),
          const Divider(height: 1, indent: Space.l, endIndent: Space.l),
          SwitchListTile(key: const Key('sit_end_bell'), title: const Text('A bell to end'), value: _endBell,
              onChanged: (v) {
                feelChoice();
                setState(() => _endBell = v);
              }),
        ])),
        const SectionHeader('Sound underneath'),
        chips([
          ChoiceChip(key: const Key('sit_scape_none'), label: const Text('Silence'), selected: _scape == 'none',
              onSelected: (_) {
                feelChoice();
                setState(() => _scape = 'none');
              }),
          for (final s in soundscapes)
            ChoiceChip(key: Key('sit_scape_${s.id}'), avatar: Icon(scapeIcon(s.id), size: 18), label: Text(s.name),
                selected: _scape == s.id, onSelected: (_) {
                  feelChoice();
                  setState(() => _scape = s.id);
                }),
        ]),
        if (_scape != 'none') ...[
          const SizedBox(height: Space.s),
          VolumeRow(key: const Key('sit_volume'), value: _volume, onChanged: (v) => setState(() => _volume = v)),
        ],
        const SizedBox(height: Space.xl),
        FilledButton.icon(key: const Key('timer_begin'), onPressed: _begin, icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Begin, $_minutes ${_minutes == 1 ? 'minute' : 'minutes'}')),
        const SizedBox(height: Space.m),
        Text('Your screen stays on while the timer runs, so the bells ring on time.',
            style: t.bodySmall, textAlign: TextAlign.center),
      ]))),
    );
  }

  // ---- sitting ----
  Widget _sitting(BuildContext context, SitTimer sit) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context); // Reduce Motion: no ring, just the numbers
    final screen = MediaQuery.sizeOf(context);
    final side = math.max(160.0, math.min(math.min(screen.width - 48, 340.0), screen.height * 0.45));
    final scape = soundscapeById(_scape);
    final notes = [
      if (sit.plan.interval != null)
        sit.plan.interval!.inMinutes == 1 ? 'A bell every minute' : 'A bell every ${sit.plan.interval!.inMinutes} minutes',
      if (scape != null && !_soundFailed) '${scape.name} underneath',
      if (_soundFailed) 'The sound could not play on this device',
    ];
    final secondsLeft = (sit.left.inMilliseconds / 1000).ceil();
    final clock = Semantics(
      label: sit.state == SitState.paused ? 'Paused, ${_spoken(secondsLeft)} left' : '${_spoken(secondsLeft)} left',
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: side * 0.72, child: FittedBox(fit: BoxFit.scaleDown, child: Text(_clockText(secondsLeft),
            key: const Key('timer_left'),
            style: t.displayLarge?.copyWith(fontSize: 64, fontFeatures: const [FontFeature.tabularFigures()])))),
        Text(sit.state == SitState.paused ? 'Paused' : 'of ${sit.plan.length.inMinutes} min',
            textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
    return Scaffold(
      body: SafeArea(child: Readable(child: FillOrScroll(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: IconButton(key: const Key('timer_close'), tooltip: 'Close',
            icon: const Icon(Icons.close), onPressed: () => Navigator.maybePop(context))),
        const Spacer(),
        if (sit.over)
          _finished(context, sit)
        else ...[
          Center(child: still
              ? Padding(padding: const EdgeInsets.symmetric(vertical: Space.xl), child: clock)
              : SizedBox(width: side, height: side, child: RepaintBoundary(child: CustomPaint(key: const Key('timer_ring'),
                  painter: _Ring(progress: sit.progress, track: scheme.outlineVariant, color: scheme.primary),
                  child: Center(child: clock))))),
          const SizedBox(height: Space.l),
          for (final n in notes) Text(n, textAlign: TextAlign.center, style: t.bodySmall),
        ],
        const Spacer(),
        if (sit.over)
          Center(child: FilledButton(key: const Key('timer_done'), onPressed: () => Navigator.maybePop(context),
              child: const Text('Done')))
        else
          Wrap(alignment: WrapAlignment.center, spacing: Space.m, runSpacing: Space.s, children: [
            FilledButton.tonalIcon(key: Key(sit.running ? 'timer_pause' : 'timer_resume'), onPressed: _pauseOrResume,
                icon: Icon(sit.running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(sit.running ? 'Pause' : 'Resume')),
            OutlinedButton(key: const Key('timer_end'), onPressed: _end, child: const Text('End')),
          ]),
      ])))),
    );
  }

  Widget _finished(BuildContext context, SitTimer sit) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final whole = sit.state == SitState.finished;
    final minutes = sit.elapsed.inMinutes;
    final sat = minutes < 1 ? 'less than a minute' : minutes == 1 ? 'a minute' : '$minutes minutes';
    return Column(children: [
      Icon(Icons.spa_outlined, size: 40, color: scheme.primary),
      const SizedBox(height: Space.l),
      Text(whole ? 'That was your ${sit.plan.length.inMinutes} minutes.' : 'You sat for $sat.',
          textAlign: TextAlign.center, style: voiceStyle(context, size: 30)),
      const SizedBox(height: Space.s),
      Text(whole ? 'Take a moment before you move on.' : 'That still counts. Come back whenever you like.',
          textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
    ]);
  }
}

String _clockText(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String _spoken(int seconds) {
  if (seconds < 60) return seconds == 1 ? '1 second' : '$seconds seconds';
  final m = (seconds / 60).ceil();
  return m == 1 ? '1 minute' : '$m minutes';
}

/// The slow ring: a quiet track, and the time sat drawn round it from the top.
class _Ring extends CustomPainter {
  _Ring({required this.progress, required this.track, required this.color});
  final double progress;
  final Color track, color;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 6.0;
    final rect = (Offset.zero & size).deflate(width);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (progress > 0) canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress.clamp(0, 1), false, paint..color = color);
  }

  @override
  bool shouldRepaint(_Ring old) => old.progress != progress || old.track != track || old.color != color;
}

/// Choosing one's own length: one to 120 minutes, by the minute.
class _OwnLength extends StatefulWidget {
  const _OwnLength({required this.start});
  final int start;
  @override
  State<_OwnLength> createState() => _OwnLengthState();
}

class _OwnLengthState extends State<_OwnLength> {
  late int _m = widget.start.clamp(1, 120);

  void _set(int m) {
    feelChoice();
    setState(() => _m = m.clamp(1, 120));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Your own length', style: t.headlineSmall),
      const SizedBox(height: Space.m),
      Text('$_m ${_m == 1 ? 'minute' : 'minutes'}', key: const Key('sit_custom_value'), textAlign: TextAlign.center,
          style: voiceStyle(context, size: 34)),
      Row(children: [
        IconButton(key: const Key('sit_custom_less'), tooltip: 'One minute less', onPressed: _m > 1 ? () => _set(_m - 1) : null,
            icon: const Icon(Icons.remove)),
        Expanded(child: Slider(key: const Key('sit_custom_slider'), min: 1, max: 120, divisions: 119, value: _m.toDouble(),
            semanticFormatterCallback: (v) => '${v.round()} minutes', onChanged: (v) => _set(v.round()))),
        IconButton(key: const Key('sit_custom_more'), tooltip: 'One minute more',
            onPressed: _m < 120 ? () => _set(_m + 1) : null, icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: Space.m),
      FilledButton(key: const Key('sit_custom_done'), onPressed: () => Navigator.pop(context, _m),
          child: Text('Use $_m ${_m == 1 ? 'minute' : 'minutes'}')),
    ])));
  }
}

/// The Practices tab's entry: the quiet timer, the soundscapes and the sleep wind-down, laid out like the practices
/// (one a row on a phone, two on a tablet or the Mac).
class QuietSection extends StatelessWidget {
  const QuietSection({super.key});
  @override
  Widget build(BuildContext context) {
    final tiles = [
      _QuietTile(key: const Key('open_timer'), category: 'deep', icon: Icons.timer_outlined, title: 'Quiet timer',
          meta: '3 to 30 minutes, or your own', line: 'Sit in silence, with a soft bell to begin and end.',
          open: () => const TimerScreen()),
      _QuietTile(key: const Key('open_soundscapes'), category: 'let_go', icon: Icons.graphic_eq, title: 'Soundscapes',
          meta: 'Rain, waves, wind, fire, brown noise', line: 'Made on this device as you listen. Nothing is downloaded.',
          open: () => const SoundscapesScreen()),
      _QuietTile(key: const Key('open_wind_down'), category: 'sleep', icon: Icons.bedtime_outlined,
          title: 'Sleep wind-down', meta: '15 to 60 minutes',
          line: 'A soundscape that slowly fades to silence as you fall asleep.',
          open: () => const SoundscapesScreen(windDownFirst: true)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Silence and sound'),
      CardGrid(children: tiles), // as the practices around it (ui/premium.dart)
    ]);
  }
}

class _QuietTile extends StatelessWidget {
  const _QuietTile({super.key, required this.category, required this.icon, required this.title, required this.meta,
      required this.line, required this.open});
  final String category, title, meta, line;
  final IconData icon;
  final Widget Function() open;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (fg, bg) = huesOf(context).category(category);
    return Card(child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => open())),
      child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m + 2, Space.m, Space.m + 2), child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: fg)),
        const SizedBox(width: Space.m + 2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.titleSmall),
          const SizedBox(height: 2),
          Text(meta, style: t.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
          Text(line, style: t.bodySmall),
        ])),
        const SizedBox(width: Space.s),
        Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
      ])),
    ));
  }
}
