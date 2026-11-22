// Meditate (listen-only: press play, nothing to fill in), practices with the therapist, and the optional programmes.
// Also the entry to trauma work. Meditations are quietly personalised from memory (core/personal.dart).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/library.dart';
import '../core/personal.dart';
import '../core/store.dart' show fewestBreaths, mostBreaths, usualBreaths;
import '../core/voice.dart';
import 'home.dart';
import 'premium.dart';
import 'programmes.dart';
import 'reliving_gate.dart';
import 'theme.dart';
import 'timer.dart';

class PracticesTab extends StatelessWidget {
  const PracticesTab({super.key});
  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).library;
    final cats = categoryNames.keys.where((c) => c != 'tools' && lib.any((p) => p.category == c));
    // a phone: one card per row; a tablet or a computer: two, three, or four on a very large window, never wider
    // cards (ui/premium.dart CardGrid)
    Widget group(Iterable<Practice> ps) => CardGrid(children: [for (final p in ps) PracticeTile(practice: p)]);
    // titled as its tab is (it said Meditate under the tab Practices)
    return ListView(padding: tabPadding, children: [
      const TabTitle('Practices',
          subtitle: 'Press play and listen. There is nothing to fill in, and each one is shaped a little around you.'),
      for (final (i, c) in cats.indexed) ...[
        SectionHeader(categoryNames[c]!, top: i == 0 ? 0 : Space.xl),
        group(lib.where((p) => p.category == c)),
        if (c == 'calm') const QuietSection(), // the quiet timer, soundscapes and sleep wind-down (ui/timer.dart)
      ],
      SectionHeader(categoryNames['tools']!),
      group(lib.where((p) => p.category == 'tools')),
      const SizedBox(height: Space.l),
      // words, so a reading width, even on a large window
      Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.list - 40), child: const Card(child: ExpansionTile(
        shape: Border(), collapsedShape: Border(),
        leading: Icon(Icons.route_outlined),
        title: Text('Programmes'),
        subtitle: Text('Daily exercises over a few weeks, to work on something specific.'),
        childrenPadding: EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [ProgrammesSection()],
      )))),
    ]);
  }
}

String practiceMinutes(Practice p) => p.guided
    ? p.versions.values.map((v) => '${v.minutes} min').join(' or ')
    : '${p.minutes} min, with Solace';

class PracticeTile extends StatelessWidget {
  const PracticeTile({super.key, required this.practice});
  final Practice practice;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(child: InkWell(
      customBorder: smoothShape(Radii.card),
      onTap: () => openPractice(context, practice),
      child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m + 2, Space.m, Space.m + 2), child: Row(children: [
        PracticeBadge(category: practice.category, size: 42),
        const SizedBox(width: Space.m + 2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(practice.title, style: t.titleSmall),
          const SizedBox(height: 2),
          Text(practiceMinutes(practice), style: t.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
          if (practice.when.isNotEmpty) Text(practice.when, style: t.bodySmall),
        ])),
        const SizedBox(width: Space.s),
        // listen (a guided recording) or talk it through (with the therapist)
        Icon(practice.guided ? Icons.headphones_outlined : Icons.forum_outlined, size: 20, color: scheme.onSurfaceVariant),
      ])),
    ));
  }
}

class QuickPracticeCard extends StatelessWidget {
  const QuickPracticeCard({super.key, required this.practice});
  final Practice practice;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(width: 168, child: Card(margin: EdgeInsets.zero, child: InkWell(
        customBorder: smoothShape(Radii.card),
        onTap: () => openPractice(context, practice),
        child: Padding(padding: const EdgeInsets.all(Space.m + 2), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          PracticeBadge(category: practice.category),
          const Spacer(),
          Text(practice.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(practiceMinutes(practice), style: t.bodySmall),
        ])),
      )));
  }
}

/// The kind of practice at a glance: its icon in its own hue.
class PracticeBadge extends StatelessWidget {
  const PracticeBadge({super.key, required this.category, this.size = 34});
  final String category;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = huesOf(context).category(category);
    return Container(width: size, height: size, decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(practiceIcon(category), size: size * 0.53, color: fg));
  }
}

/// One quiet icon for each kind of practice.
IconData practiceIcon(String category) => const {
      'morning': Icons.wb_twilight, 'calm': Icons.air, 'kindness': Icons.favorite_outline, 'direction': Icons.explore_outlined,
      'let_go': Icons.cloud_outlined, 'urges': Icons.waves, 'deep': Icons.spa_outlined, 'sleep': Icons.bedtime_outlined,
      'feel_good': Icons.wb_sunny_outlined, 'safe': Icons.shield_outlined, 'tools': Icons.forum_outlined,
    }[category] ?? Icons.self_improvement;

/// Opens a practice: interactive ones start a session; spoken ones show a short card (what it is for, the honest
/// evidence, and any caution) with the play button.
void openPractice(BuildContext context, Practice p) {
  if (!p.guided) {
    openSession(context, 'practice', practiceName: p.practiceName);
    return;
  }
  final t = Theme.of(context).textTheme;
  showModalBottomSheet(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => SafeArea(
      child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(p.title, style: t.headlineSmall),
    const SizedBox(height: 6),
    Text(p.when, style: t.bodyLarge),
    if (p.evidence.isNotEmpty) ...[
      const SizedBox(height: 10),
      Text('Why it helps', style: t.titleSmall),
      Text(p.evidence, style: t.bodyMedium),
    ],
    const SizedBox(height: 16),
    for (final k in p.versions.keys) Padding(padding: const EdgeInsets.only(bottom: 8), child: FilledButton.icon(
      icon: const Icon(Icons.play_arrow),
      label: Text(p.versions.length == 1 ? 'Play, ${p.versions[k]!.minutes} minutes'
          : '${k == 'short' ? 'Short' : 'Longer'}, ${p.versions[k]!.minutes} minutes'),
      onPressed: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => PracticePlayer(practice: p, version: k)));
      },
    )),
  ]))));
}

class PracticePlayer extends StatefulWidget {
  const PracticePlayer({super.key, required this.practice, required this.version, this.voice = const StubVoice()});
  final Practice practice;
  final String version;
  final VoiceService voice;
  @override
  State<PracticePlayer> createState() => _PracticePlayerState();
}

class _PracticePlayerState extends State<PracticePlayer> {
  int _step = 0;
  int _left = 0;
  bool _paused = false;
  bool _done = false;
  Timer? _timer;
  Map<String, String> _words = const {};
  bool _voiceFailed = false; // said once, not at every step

  List<PracticeStep> get _steps => widget.practice.versions[widget.version]!.steps;
  String _text(int i) => fillPersonal(_steps[i].text, _words);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { // after the first frame, when AppScope is reachable
      final state = AppScope.of(context);
      _words = personalWords(state.data, state.clock());
      _run();
    });
  }

  Future<void> _run() async {
    final settings = AppScope.of(context).data.settings;
    var spoken = false;
    if (widget.voice.available && settings.voiceOn) {
      try {
        await widget.voice.speak(_text(_step), voice: settings.voice);
        spoken = true;
      } catch (_) {
        // the voice failed: the words stay on screen with reading time, and the practice carries on (F-17)
        if (mounted && !_voiceFailed) {
          _voiceFailed = true;
          sayGently(context, 'The voice could not play just now, so the words are on the screen instead.');
        }
      }
    }
    if (!mounted) return;
    // without voice, give reading time (about 140 words a minute) before the silence
    final reading = spoken ? 0 : (_text(_step).split(' ').length * 60 / 140).ceil();
    setState(() => _left = reading + _steps[_step].pause);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      if (_left > 1) {
        setState(() => _left--);
      } else {
        _timer?.cancel();
        _next();
      }
    });
  }

  void _next() {
    if (_step + 1 >= _steps.length) {
      setState(() => _done = true);
      return;
    }
    setState(() => _step++);
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(widget.voice.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pacing = !_done && _steps[_step].pacer && widget.practice.pacer.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: BarTitle(widget.practice.title)),
      body: Readable(maxWidth: 720, child: FillOrScroll(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LinearProgressIndicator(value: (_step + (_done ? 1 : 0)) / _steps.length, borderRadius: BorderRadius.circular(8)),
        const Spacer(),
        if (pacing) Center(child: BreathPacer(pattern: widget.practice.pacer, running: !_paused)),
        if (pacing) const SizedBox(height: 24),
        // the practice's words in the therapist's voice: calm, never bold
        Text(_done ? 'Take a moment before you go on with your day.' : _text(_step),
            style: voiceStyle(context, size: pacing ? 24 : 28), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (!_done && _left > 0 && !pacing)
          Text(_paused ? 'Paused' : '$_left', textAlign: TextAlign.center, style: t.titleMedium?.copyWith(color: scheme.outline)),
        const Spacer(),
        if (_done) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))
        else Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(iconSize: 32, tooltip: _paused ? 'Resume' : 'Pause',
              onPressed: () => setState(() => _paused = !_paused), icon: Icon(_paused ? Icons.play_arrow : Icons.pause)),
          const SizedBox(width: 16),
          IconButton.filledTonal(iconSize: 32, tooltip: 'Next', onPressed: () {
            _timer?.cancel();
            _next();
          }, icon: const Icon(Icons.skip_next)),
        ]),
      ]))),
    );
  }
}

/// A breathing guide: a soft sphere that grows on the in-breath and settles on the out-breath, with the phase named.
/// The pace is the person's own, saved in Settings: 4 to 10 breaths a minute, 6 by default (resonance breathing sits
/// at 6 to 6.5 a minute, and Apple's Breathe offers 4 to 10; report 2026-11-14, P1 11). One breath lasts 60 / pace
/// seconds and the practice's own shape is stretched to fit it: 4 seconds in and 6 out by default, the sigh's two sips
/// and long breath out, slow breathing's even five and five. When the device asks for less motion the sphere keeps
/// one size: its colour turns and the phase is counted down in words instead, because the pacing is the content.
/// (The soft rising and falling tones come with the sound engine.)
class BreathPacer extends StatefulWidget {
  const BreathPacer({super.key, this.pattern = standardBreath, this.running = true});
  final List<(String, int)> pattern;
  final bool running;

  /// Four seconds in and six out: ten seconds a breath, six a minute.
  static const standardBreath = [('in', 4), ('out', 6)];

  @override
  State<BreathPacer> createState() => _BreathPacerState();
}

class _BreathPacerState extends State<BreathPacer> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int _phase = 0;
  int _rate = usualBreaths;

  /// The app, when the pacer is inside it: the pace is read from and saved to Settings there.
  AppState? get _app => context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;

  int get _prev => (_phase - 1 + widget.pattern.length) % widget.pattern.length;

  /// A phase's length: its share of the pattern, of one breath at the chosen pace.
  Duration _len(int i) {
    final total = widget.pattern.fold<int>(0, (a, p) => a + p.$2);
    return Duration(milliseconds: (60000 * widget.pattern[i].$2 / (math.max(total, 1) * _rate)).round());
  }

  /// Circle size for the end of a phase: in-breaths grow it step by step, the out-breath returns it to rest.
  double _size(int i) {
    if (widget.pattern[i].$1.contains('out')) return 0.5;
    final ins = [for (var k = 0; k < widget.pattern.length; k++) if (!widget.pattern[k].$1.contains('out')) k];
    return 0.5 + 0.5 * (ins.indexOf(i) + 1) / ins.length;
  }

  @override
  void initState() {
    super.initState();
    // the timing is the content: kept as it is when Android removes animations (which otherwise runs a controller
    // twenty times faster)
    _c = AnimationController(vsync: this, duration: _len(0), animationBehavior: AnimationBehavior.preserve)
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        setState(() => _phase = (_phase + 1) % widget.pattern.length);
        _c.duration = _len(_phase);
        _c.forward(from: 0);
      });
    if (widget.running) _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rate = (_app?.data.settings.breathsPerMinute ?? usualBreaths).clamp(fewestBreaths, mostBreaths);
    if (rate != _rate) {
      _rate = rate;
      _retime();
    }
  }

  /// The current phase at the new pace, carrying on from where it is (no jump in the sphere).
  void _retime() {
    _c.duration = _len(_phase);
    if (_c.isAnimating) _c.forward(from: _c.value);
  }

  void _setRate(int rate) {
    feelChoice();
    setState(() => _rate = rate);
    _retime();
    final app = _app;
    if (app == null) return;
    app.data.settings.breathsPerMinute = rate;
    unawaited(app.save());
  }

  @override
  void didUpdateWidget(BreathPacer old) {
    super.didUpdateWidget(old);
    if (widget.running && !_c.isAnimating) _c.forward();
    if (!widget.running) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final still = Calm.reduced(context);
    // how deep the colour is at the end of a phase: light when full of breath, deeper at rest
    double depth(int i) => 1 - (_size(i) - 0.5) / 0.5;
    final sphere = AnimatedBuilder(animation: _c, builder: (_, _) {
      final f = Curves.easeInOut.transform(_c.value);
      final size = 220 * (still ? 0.78 : _size(_prev) + (_size(_phase) - _size(_prev)) * f);
      final tone = still ? depth(_prev) + (depth(_phase) - depth(_prev)) * f : 0.0;
      final left = ((_c.duration ?? Duration.zero).inMilliseconds * (1 - _c.value) / 1000).ceil().clamp(1, 99);
      final label = Text(widget.pattern[_phase].$1, textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(color: scheme.onPrimaryContainer, letterSpacing: 0.4));
      // a soft sphere that breathes: lighter at the top, a halo that grows with it
      return Container(
        key: const Key('pacer_sphere'),
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(center: const Alignment(-0.3, -0.4), radius: 1.0, colors: [
              Color.lerp(scheme.primaryContainer, scheme.primary, 0.15 * tone)!,
              Color.lerp(scheme.primaryContainer, scheme.primary, 0.35 + 0.2 * tone)!,
            ]),
            boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.18 + 0.12 * (still ? 1 - tone : f)),
                blurRadius: 24 + 16 * (still ? 1 - tone : f), spreadRadius: 2)]),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(Space.l),
        child: FittedBox(fit: BoxFit.scaleDown, child: still
            // with less motion: the phase and its seconds counted down, in place of the movement
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                label,
                Text('$left', key: const Key('pacer_count'), style: t.headlineMedium?.copyWith(
                    color: scheme.onPrimaryContainer, fontFeatures: const [FontFeature.tabularFigures()])),
              ])
            : label),
      );
    });
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 240, height: 240, child: Center(child: sphere)),
      const SizedBox(height: Space.s),
      // the pace, slower or faster, kept for next time
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(key: const Key('pacer_slower'), tooltip: 'Slower breathing', icon: const Icon(Icons.remove),
            onPressed: _rate > fewestBreaths ? () => _setRate(_rate - 1) : null),
        Flexible(child: Text('$_rate breaths a minute', key: const Key('pacer_rate'), textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
        IconButton(key: const Key('pacer_faster'), tooltip: 'Faster breathing', icon: const Icon(Icons.add),
            onPressed: _rate < mostBreaths ? () => _setRate(_rate + 1) : null),
      ]),
    ]);
  }
}

/// Written exposure is always available; spoken reliving only in deep work mode (internally 'full'), behind the gate.
class TraumaCards extends StatelessWidget {
  const TraumaCards({super.key});
  @override
  Widget build(BuildContext context) {
    final full = AppScope.of(context).data.settings.mode == 'full';
    return Column(children: [
      // the same rows as Talk's ways to start: the icon in its soft circle, the words, a chevron
      Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
          leading: const IconDisc(Icons.edit_note), title: const Text('Written exposure'),
          subtitle: const Text('A gentle, proven way to work on a trauma memory by writing about it for 30 minutes.'),
          trailing: const Icon(Icons.chevron_right), onTap: () => openSession(context, 'written_exposure'))),
      // only in deep work mode (owner, 2026-11-05: tucked away, so it is not shown at all otherwise)
      if (full) Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
          leading: const IconDisc(Icons.record_voice_over_outlined),
          title: const Text('Spoken reliving'),
          subtitle: const Text('Readiness questions and a support person are needed first.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RelivingGateScreen())))),
    ]);
  }
}
