// The weekly review, the monthly letter and the year in review (report recommendation 22). The summary is counted on
// the device (core/review.dart). When Solace's language model is on the device, the person can ask it for two or
// three warm sentences written from that summary; the model is told to reflect and not count, its words are shown
// only once complete, and any sentence holding a digit is left out, so every number shown comes from the records.
// Without the model (the stand-in), the summary stands alone and says so.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/model.dart';
import '../core/review.dart';
import 'premium.dart';
import 'theme.dart';

const reviewPromptAsset = 'assets/prompts/app_review_v1.txt';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.span});
  final ReviewSpan span;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _back = 0; // 0 this week (month, year), 1 the one before ...
  String? _words; // the model's cleaned words for the period shown
  bool _busy = false, _failed = false;
  bool _onServer = false; // Solace Home: the words came from the home server (H19-05)

  /// Whether the words being written now are expected from the home server.
  static bool _writingOnServer(ModelRuntime m) => m is WritesElsewhere && (m as WritesElsewhere).writesOnServer;

  void _go(int back) {
    feelChoice();
    setState(() {
      _back = back;
      _words = null;
      _failed = false;
    });
  }

  Future<void> _reflect(ReviewSummary summary) async {
    final state = AppScope.of(context);
    final bundle = DefaultAssetBundle.of(context);
    setState(() {
      _busy = true;
      _failed = false;
    });
    var clean = '';
    final blocked = <String>{};
    try {
      final template = await bundle.loadString(reviewPromptAsset);
      final m = state.model;
      final reply = await m.generate(reviewMessages(template, summary), maxTokens: 160).join();
      clean = cleanReflection(reply, onBlocked: blocked.add);
      // Solace Home: said where the words were written (H19-05), the home server or the model on this device
      _onServer = m is WritesElsewhere && (m as WritesElsewhere).lastOnServer;
    } catch (_) {
      clean = '';
    }
    if (blocked.isNotEmpty) { // a sentence was left out by the reply screen: only its rule group is kept (AI-4)
      for (final g in blocked) {
        state.data.safetyEvents.add({'date': isoDate(state.clock()), 'level': 'output', 'reason': g});
      }
      unawaited(state.save());
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _words = clean.isEmpty ? null : clean;
      _failed = clean.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = buildReview(state.data, widget.span, state.clock(), back: _back);
    final t = Theme.of(context).textTheme;
    final title = switch (widget.span) {
      ReviewSpan.week => 'Your week',
      ReviewSpan.month => 'Your month',
      ReviewSpan.year => 'Your year in review',
    };
    final earliest = widget.span == ReviewSpan.year ? 10 : widget.span == ReviewSpan.month ? 24 : 104;
    return Scaffold(
      appBar: AppBar(title: BarTitle(title)),
      body: Readable(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, Space.xxl), children: [
        Row(children: [
          IconButton(key: const Key('review_earlier'), tooltip: 'Earlier', icon: const Icon(Icons.chevron_left),
              onPressed: _back >= earliest ? null : () => _go(_back + 1)),
          Expanded(child: Text(s.range, key: const Key('review_range'), textAlign: TextAlign.center, style: t.titleSmall)),
          IconButton(key: const Key('review_later'), tooltip: 'Later', icon: const Icon(Icons.chevron_right),
              onPressed: _back == 0 ? null : () => _go(_back - 1)),
        ]),
        const SizedBox(height: Space.s),
        _wordsCard(context, s),
        const SectionHeader('Mood'),
        Card(child: Padding(padding: const EdgeInsets.all(Space.l), child: _MoodDays(summary: s))),
        const SectionHeader('Counted on this device'),
        Card(child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m), child: s.isEmpty
            ? Text('Nothing recorded in this ${s.noun} yet. That is all right. It will be here when you want it.',
                style: t.bodyMedium)
            : Column(children: [for (final f in s.facts) _FactRow(fact: f)]))),
        const SizedBox(height: Space.l),
        Text('A snapshot of what you recorded, not a judgement. Hard ${s.noun}s belong here too.', style: t.bodySmall),
      ])),
    );
  }

  Widget _wordsCard(BuildContext context, ReviewSummary s) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final model = AppScope.of(context).model;
    if (model is StandInModel || s.isEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(Space.l), child: Row(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.edit_note, color: scheme.onSurfaceVariant),
        const SizedBox(width: Space.m),
        Expanded(child: Text(s.isEmpty
            ? 'Once there is something recorded for this ${s.noun}, Solace can add a few words about it here.'
            : 'When Solace\'s language model is on this device, it can add a few words about your ${s.noun} here. '
                'The summary below is complete without them.', style: t.bodyMedium)),
      ])));
    }
    const white = Colors.white; // on the gradient card, as on Today's session card
    final caption = t.bodySmall?.copyWith(color: Colors.white70);
    return AnimatedSize(duration: Calm.normal, curve: Calm.curve, child: Container(
      padding: const EdgeInsets.all(Space.xl - 4),
      decoration: BoxDecoration(gradient: huesOf(context).therapist, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.span == ReviewSpan.month ? 'A letter for your month' : 'A few words from Solace',
            style: t.titleMedium?.copyWith(color: white)),
        const SizedBox(height: Space.m),
        AnimatedSwitcher(duration: Calm.slow, switchInCurve: Calm.curve, switchOutCurve: Calm.curve, child: _busy
            ? Column(key: const ValueKey('busy'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_writingOnServer(model) ? 'Solace is writing, on your home server...'
                    : 'Solace is writing, here on your device...', style: voiceStyle(context, size: 20, color: white)),
                const SizedBox(height: Space.m),
                const LinearProgressIndicator(color: white, backgroundColor: Colors.white24, minHeight: 2),
              ])
            : _words != null
                ? Column(key: const ValueKey('words'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_words!, key: const Key('review_words'), style: voiceStyle(context, size: 21, color: white)),
                    const SizedBox(height: Space.m),
                    Text(_onServer ? 'Written by the model on your home server from the summary below, which is '
                        'what was sent to it. Every number comes from your own records.'
                        : 'Written on this device from the summary below. Every number comes from your own records.',
                        key: const Key('review_written_where'), style: caption),
                  ])
                : Column(key: ValueKey('ask$_failed'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_failed ? 'Solace\'s words did not come out right this time. The summary below is complete '
                        'without them.' : 'Would you like a few words about your ${s.noun}?',
                        style: voiceStyle(context, size: 21, color: white)),
                    const SizedBox(height: Space.l),
                    FilledButton.icon(key: const Key('review_reflect'),
                        style: FilledButton.styleFrom(backgroundColor: white, foregroundColor: scheme.onPrimaryContainer),
                        onPressed: () => _reflect(s), icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(_failed ? 'Try again' : 'Ask Solace')),
                  ])),
      ]),
    ));
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});
  final ReviewFact fact;
  static const _icons = {'mood': Icons.wb_sunny_outlined, 'feelings': Icons.bubble_chart_outlined,
    'affecting': Icons.label_outline, 'sessions': Icons.chat_bubble_outline, 'steps': Icons.check_circle_outline,
    'programme': Icons.route_outlined, 'questionnaire': Icons.checklist};
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(_icons[fact.kind] ?? Icons.circle_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: Space.m),
    Expanded(child: Text(fact.text, style: Theme.of(context).textTheme.bodyMedium)),
  ]));
}

/// The period's moods as dots in the mood colours: a row for a week, a month as a calendar, a year as twelve rows
/// of up to 31 days (Daylio's "year in pixels"). A day without a rating is just an empty dot, never a mark against.
class _MoodDays extends StatelessWidget {
  const _MoodDays({required this.summary});
  final ReviewSummary summary;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = summary;
    final legend = Text(switch (s.span) {
      ReviewSpan.year => 'Each dot is a day, coloured by that day\'s mood, from indigo when low to green when good.',
      _ => 'Each dot is a day, coloured by its mood, from indigo when low to green when good.',
    }, style: t.bodySmall);
    if (s.moods.isEmpty) return Text('No moods rated in this ${s.noun}.', style: t.bodyMedium);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      switch (s.span) {
        ReviewSpan.week => _week(context),
        ReviewSpan.month => _month(context),
        ReviewSpan.year => _YearPixels(summary: s),
      },
      const SizedBox(height: Space.m),
      legend,
    ]);
  }

  Widget _dot(BuildContext context, String iso, double size, {String? label}) {
    final scheme = Theme.of(context).colorScheme;
    final mood = huesOf(context).mood;
    final m = summary.moods[iso];
    return Semantics(container: true, label: '${dayLabel(DateTime.parse(iso))}: ${m == null ? 'no rating' : 'mood $m'}',
        excludeSemantics: true, child: Container(width: size, height: size, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: m == null ? null : mood[m.clamp(0, 10)],
                border: m == null ? Border.all(color: scheme.outlineVariant) : null),
            child: label == null ? null : FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(3),
                child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: m == null ? scheme.onSurfaceVariant : scheme.surface, fontWeight: FontWeight.w600))))));
  }

  Widget _week(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final days = [for (var i = 0; i < 7; i++) DateTime(summary.from.year, summary.from.month, summary.from.day + i)];
    return LayoutBuilder(builder: (context, box) {
      final size = math.min(40.0, box.maxWidth / 7 - 6);
      return Row(children: [
        for (final d in days)
          Expanded(child: Column(children: [
            _dot(context, isoDate(d), size, label: summary.moods[isoDate(d)]?.toString()),
            const SizedBox(height: Space.xs),
            FittedBox(fit: BoxFit.scaleDown, child: Text(dayLabel(d).substring(0, 3), style: t.labelSmall)),
          ])),
      ]);
    });
  }

  Widget _month(BuildContext context) {
    final first = summary.from;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    return LayoutBuilder(builder: (context, box) {
      final cell = (box.maxWidth / 7).floorToDouble();
      final size = math.min(36.0, cell - 6);
      return Wrap(children: [
        for (var i = 0; i < lead; i++) SizedBox(width: cell, height: size + 6),
        for (var day = 1; day <= daysInMonth; day++)
          SizedBox(width: cell, height: size + 6, child: Center(child: _dot(context,
              isoDate(DateTime(first.year, first.month, day)), size, label: '$day'))),
      ]);
    });
  }
}

class _YearPixels extends StatelessWidget {
  const _YearPixels({required this.summary});
  final ReviewSummary summary;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      final labelWidth = math.max(18.0, MediaQuery.textScalerOf(context).scale(11) * 1.3);
      final cell = (box.maxWidth - labelWidth) / 31;
      return Semantics(container: true, label: 'Year in dots: ${summary.moods.length} days rated in ${summary.from.year}',
          excludeSemantics: true, child: Column(children: [
        for (var m = 1; m <= 12; m++)
          SizedBox(height: cell, child: Row(children: [
            SizedBox(width: labelWidth, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(monthName(m)[0], style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)))),
            Expanded(child: CustomPaint(size: Size(cell * 31, cell), painter: _MonthRow(
                year: summary.from.year, month: m, moods: summary.moods, until: summary.to,
                mood: huesOf(context).mood, empty: scheme.outlineVariant))),
          ])),
      ]));
    });
  }
}

class _MonthRow extends CustomPainter {
  _MonthRow({required this.year, required this.month, required this.moods, required this.until, required this.mood,
      required this.empty});
  final int year, month;
  final Map<String, int> moods;
  final DateTime until;
  final List<Color> mood;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 31;
    final days = DateTime(year, month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final date = DateTime(year, month, d);
      if (date.isAfter(until)) break;
      final m = moods[isoDate(date)];
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH((d - 1) * cell + cell * 0.12, cell * 0.12, cell * 0.76,
          cell * 0.76), Radius.circular(cell * 0.22));
      canvas.drawRRect(rect, Paint()..color = m == null ? empty : mood[m.clamp(0, 10)]);
    }
  }

  @override
  bool shouldRepaint(_MonthRow old) => old.moods != moods || old.year != year || old.until != until ||
      old.mood != mood || old.empty != empty;
}
