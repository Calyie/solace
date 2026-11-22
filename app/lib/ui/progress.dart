// Progress you can see: mood over time, questionnaire scores, the wheel of life (first rating against the latest),
// and "then and now": your own words from the start next to your words today.
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/questionnaires.dart';
import 'insights.dart';
import 'premium.dart';
import 'programmes.dart';
import 'questionnaire.dart';
import 'showed_up.dart';
import 'theme.dart';
import 'your_data.dart';

class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = state.data;
    final now = state.clock();
    final days = [for (var i = 29; i >= 0; i--) now.subtract(Duration(days: i))];
    final moodSpots = [
      for (var i = 0; i < days.length; i++)
        if (d.moods[isoDate(days[i])] != null) FlSpot(i.toDouble(), d.moods[isoDate(days[i])]!.toDouble()),
    ];
    final n = d.sessions.length;
    return ListView(padding: tabPadding, children: [
      TabTitle('Your progress', subtitle: n == 0
          ? 'Your moods, sessions and check-ups gather here as you go. Change is rarely a straight line. The overall '
              'direction is what counts.'
          : '$n session${n == 1 ? '' : 's'} so far. Change is rarely a straight line. The overall direction is what '
              'counts.'),
      // a phone: one column; a computer: the charts beside the calendar, the wheel and the exports; a very large
      // window: the patterns and the mood, the check-ups, and the rest, side by side (ui/premium.dart Panes)
      Panes(columns: [[
      const InsightLoopCard(), // patterns worth noticing and the look back (ui/insights.dart)
      const ProgrammeProgress(),
      _ChartCard(title: 'Mood, last 30 days', empty: moodSpots.isEmpty, emptyIcon: Icons.show_chart,
          emptyText: 'Your mood over the last 30 days will show here as a line. Tap how you feel on Today to start.',
          chart: LineChart(LineChartData(minY: 0, maxY: 10, minX: 0, maxX: 29,
              gridData: _grid(context),
              titlesData: _titles(context, left: 5, bottom: (v) => v % 7 == 0 ? '${days[v.toInt()].day}/${days[v.toInt()].month}' : ''),
              borderData: FlBorderData(show: false),
              lineBarsData: [_line(context, moodSpots, mood: true)]))),
      ], [
      for (final q in questionnaires) _ScoreCard(q: q),
      ], [
      const ShowedUpCalendar(), // days you showed up, never a streak (ui/showed_up.dart)
      const _WheelCard(),
      const _ThenAndNow(),
      const YourDataCard(), // the clinician's PDF, CSV and Markdown (ui/your_data.dart)
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
          const QuestionnaireFlow(list: [phq9, gad7]))), child: const Text('Do the mood and anxiety check now')),
      ]]),
    ]);
  }
}

/// The charts' axis numbers: quiet, and in tabular figures so they line up (report 2026-11-14, P1 9).
TextStyle _axis(BuildContext context) => TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant,
    fontFeatures: const [FontFeature.tabularFigures()]);

FlTitlesData _titles(BuildContext context, {required double left, required String Function(double) bottom}) =>
    FlTitlesData(
      topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: left, reservedSize: 28,
          // the lowest label is left out so it never sits on top of the first date
          getTitlesWidget: (v, m) => v == m.min ? const SizedBox.shrink()
              : Text(m.formattedValue, style: _axis(context)))),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, interval: 1,
          getTitlesWidget: (v, m) => Text(bottom(v), style: _axis(context).copyWith(fontSize: 11)))),
    );

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.chart, required this.empty, required this.emptyText, this.footer,
      this.emptyIcon = Icons.show_chart, this.emptyAction, this.onEmptyAction});
  final String title;
  final Widget chart;
  final bool empty;
  final String emptyText;
  final IconData emptyIcon;
  final String? emptyAction;
  final VoidCallback? onEmptyAction;
  final String? footer;
  // with nothing to draw yet, what will show here and how to start, in a few lines rather than an empty chart's
  // height (report 2026-11-14, P1 20)
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: Space.m), child: Padding(
      padding: const EdgeInsets.all(Space.l), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: Space.m),
    if (empty) EmptyNote(icon: emptyIcon, text: emptyText, action: emptyAction, onAction: onEmptyAction)
    else SizedBox(height: 180, child: chart),
    if (footer != null) Padding(padding: const EdgeInsets.only(top: Space.s),
        child: Text(footer!, style: Theme.of(context).textTheme.bodyMedium)),
  ])));
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.q});
  final Questionnaire q;
  @override
  Widget build(BuildContext context) {
    final rows = AppScope.of(context).data.scores.where((s) => s['name'] == q.name).toList();
    if (rows.isEmpty && q.name == 'PCL-5') return const SizedBox.shrink();
    final spots = [for (var i = 0; i < rows.length; i++) FlSpot(i.toDouble(), (rows[i]['total'] as int).toDouble())];
    final first = rows.isEmpty ? null : rows.first['total'] as int;
    final last = rows.isEmpty ? null : rows.last['total'] as int;
    final footer = last == null ? null : 'Latest ${q.name}: $last (${q.band(last)})'
        '${rows.length > 1 ? '. First: $first. Lower is better.' : '. Lower is better.'}';
    return _ChartCard(title: q.title, empty: rows.isEmpty, footer: footer, emptyIcon: Icons.checklist,
        emptyText: 'Your ${q.name} answers will show here as a line, so you can see how they change.',
        // one way to start, on the first of the cards (the check asks both)
        emptyAction: q == questionnaires.first ? 'Do the two-minute check' : null,
        onEmptyAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
            const QuestionnaireFlow(list: [phq9, gad7]))),
        chart: LineChart(LineChartData(minY: 0, maxY: q.maxScore.toDouble(),
            gridData: _grid(context), borderData: FlBorderData(show: false),
            titlesData: _titles(context, left: max(5, (q.maxScore / 4).roundToDouble()), bottom: (v) {
              final i = v.toInt();
              if (i < 0 || i >= rows.length) return '';
              final dt = DateTime.parse(rows[i]['date'] as String);
              return '${dt.day}/${dt.month}';
            }),
            lineBarsData: [_line(context, spots)])));
  }
}

class _WheelCard extends StatelessWidget {
  const _WheelCard();
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wheel = state.data.wheel;
    final scheme = Theme.of(context).colorScheme;
    if (wheel.isEmpty) {
      return Card(margin: const EdgeInsets.only(bottom: 12), child: ListTile(
          leading: const Icon(Icons.donut_large), title: const Text('Wheel of life'),
          subtitle: const Text('Rate the areas of your life that matter to you, and watch them change.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WheelScreen()))));
    }
    final first = Map<String, int>.from(wheel.first['ratings'] as Map);
    final last = Map<String, int>.from(wheel.last['ratings'] as Map);
    final areas = last.keys.toList();
    RadarDataSet set(Map<String, int> r, Color c) => RadarDataSet(fillColor: c.withValues(alpha: 0.2), borderColor: c,
        entryRadius: 2, dataEntries: [for (final a in areas) RadarEntry(value: (r[a] ?? 0).toDouble())]);
    return _ChartCard(
      title: 'Wheel of life', empty: areas.length < 3, emptyIcon: Icons.donut_large,
      emptyText: 'Your wheel shows here once at least three areas are rated.',
      footer: wheel.length > 1 ? 'Outline: your first wheel. Filled: your latest.' : 'Rate it again next month to see the change.',
      chart: RadarChart(RadarChartData(
        dataSets: [if (wheel.length > 1) set(first, scheme.outline), set(last, scheme.primary)],
        radarShape: RadarShape.polygon, tickCount: 5, ticksTextStyle: const TextStyle(fontSize: 0),
        getTitle: (i, angle) => RadarChartTitle(text: areas[i], angle: 0),
        titleTextStyle: const TextStyle(fontSize: 12),
      )),
    );
  }
}

class WheelScreen extends StatefulWidget {
  const WheelScreen({super.key});
  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen> {
  late Map<String, int> _r;
  final _newArea = TextEditingController();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final w = AppScope.of(context).data.wheel;
    _r = w.isEmpty ? {} : Map<String, int>.from(w.last['ratings'] as Map);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const BarTitle('Wheel of life')),
        body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Name the areas of life that matter to you, and rate each from 1 to 10 as it is today.'),
          const SizedBox(height: Space.xs),
          Text('For example work, health, family, friends, creativity, money, fun, home, growth or faith.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          for (final a in _r.keys.toList()) Row(children: [
            SizedBox(width: 110, child: Text(a)),
            Expanded(child: Slider(min: 1, max: 10, divisions: 9, value: _r[a]!.toDouble(), label: '${_r[a]}',
                onChanged: (v) => setState(() => _r[a] = v.round()))),
            Text('${_r[a]}'),
            IconButton(onPressed: () => setState(() => _r.remove(a)), icon: const Icon(Icons.close)),
          ]),
          Row(children: [
            Expanded(child: TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.name, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, controller: _newArea, decoration: const InputDecoration(hintText: 'Add an area'))),
            IconButton(onPressed: () {
              final a = _newArea.text.trim();
              if (a.isNotEmpty) setState(() => _r[a] = 5);
              _newArea.clear();
            }, icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 20),
          FilledButton(onPressed: _r.length < 3 ? null : () async {
            await AppScope.of(context).saveWheel(_r);
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('Save today\'s wheel')),
        ])),
      );
}

class _ThenAndNow extends StatelessWidget {
  const _ThenAndNow();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).data.sessions;
    String? firstWords(int i) {
      final turns = s[i].turns.where((t) => t.$1 == 'person' && t.$2.split(' ').length > 6).toList();
      return turns.isEmpty ? null : turns.first.$2;
    }
    if (s.length < 4) return const SizedBox.shrink();
    final then = firstWords(0), now = firstWords(s.length - 1);
    if (then == null || now == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Then and now', style: t.titleMedium),
      const SizedBox(height: 8),
      // the day in words, as everywhere else in the app, then the person's own words
      for (final (i, (date, words)) in [(s.first.date, then), (s.last.date, now)].indexed) ...[
        if (i > 0) const SizedBox(height: Space.m),
        Text(dayLabel(DateTime.parse(date)), style: t.bodySmall),
        const SizedBox(height: 2),
        Text('"$words"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
      ],
    ])));
  }
}

/// Faint dashed lines across, none down: the shape of the line is what matters.
FlGridData _grid(BuildContext context) => FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) =>
    FlLine(color: Theme.of(context).colorScheme.outlineVariant, strokeWidth: 1, dashArray: const [4, 4]));

/// One line in the design: a soft fill under it, small open dots, the latest point filled and larger. The mood line
/// takes the mood scale's colours, from indigo when low to green when good.
LineChartBarData _line(BuildContext context, List<FlSpot> spots, {bool mood = false}) {
  final scheme = Theme.of(context).colorScheme;
  final hues = huesOf(context).mood;
  final colours = mood ? [hues[2], hues[6], hues[9]] : [scheme.primary, scheme.primary];
  return LineChartBarData(
    spots: spots, barWidth: 3, isCurved: mood, preventCurveOverShooting: true, isStrokeCapRound: true,
    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: colours),
    belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [(mood ? hues[6] : scheme.primary).withValues(alpha: 0.20), scheme.surface.withValues(alpha: 0)])),
    dotData: FlDotData(show: true, getDotPainter: (spot, _, _, i) => i == spots.length - 1
        ? FlDotCirclePainter(radius: 5, color: mood ? hues[spot.y.round().clamp(0, 10)] : scheme.primary,
            strokeWidth: 2.5, strokeColor: scheme.surface)
        : FlDotCirclePainter(radius: 3, color: scheme.surface, strokeWidth: 2,
            strokeColor: mood ? hues[spot.y.round().clamp(0, 10)] : scheme.primary)),
  );
}
