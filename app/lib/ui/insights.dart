// Patterns worth noticing (report recommendation 22): what Solace noticed in the person's own records, worked out on
// this device (core/insights.dart), in plain and tentative words; what was checked and found steady; what is still
// gathering, with the minimum it needs; and the way into the weekly, monthly and yearly look back.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/home_link.dart' show staysOnFor;
import '../core/emotions.dart';
import '../core/insights.dart';
import '../core/review.dart';
import 'emotion_sheet.dart' show quadrantHues;
import 'premium.dart';
import 'review.dart';
import 'theme.dart';

/// The card at the top of Progress: the clearest pattern so far, and the way into the look back.
class InsightLoopCard extends StatelessWidget {
  const InsightLoopCard({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final report = computeInsights(state.data, state.clock());
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final first = report.patterns.isNotEmpty ? report.patterns.first.text
        : report.questionnaires.isNotEmpty ? report.questionnaires.first.text
        : 'Solace will point out patterns here once there is enough to go on.';
    void review(ReviewSpan span) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(span: span)));
    return Card(margin: const EdgeInsets.only(bottom: Space.m), clipBehavior: Clip.antiAlias, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(key: const Key('open_insights'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InsightsScreen())),
          child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.m, Space.s), child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 20, backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.auto_awesome_outlined, size: 20, color: scheme.onPrimaryContainer)),
            const SizedBox(width: Space.m),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Patterns worth noticing', style: t.titleMedium),
              const SizedBox(height: Space.xs),
              Text(first, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
            ])),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ]))),
      Padding(padding: const EdgeInsets.fromLTRB(Space.s + 2, 0, Space.s, Space.s), child: Wrap(children: [
        TextButton(key: const Key('open_week'), onPressed: () => review(ReviewSpan.week), child: const Text('Your week')),
        TextButton(key: const Key('open_month'), onPressed: () => review(ReviewSpan.month), child: const Text('Your month')),
        TextButton(key: const Key('open_year'), onPressed: () => review(ReviewSpan.year), child: const Text('Your year')),
      ])),
    ]));
  }
}

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = computeInsights(state.data, state.clock());
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    void review(ReviewSpan span) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(span: span)));
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Patterns worth noticing')),
      body: Readable(child: ListView(padding: const EdgeInsets.fromLTRB(20, Space.s, 20, Space.xxl), children: [
        Text('Solace looks for patterns in what you have recorded, here on this device. A pattern shows what tends to '
            'go together, not what causes what. It is worth noticing, not a verdict.',
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SectionHeader('Solace noticed'),
        if (r.patterns.isEmpty)
          _Note(icon: Icons.spa_outlined, text: r.ratings < minRatings
              ? 'Nothing to point out yet. There is not enough to go on until you have rated your mood a little more.'
              : 'Nothing stands out by a point or more right now. Steady is a pattern too.')
        else
          for (final p in r.patterns) _InsightCard(insight: p),
        if (r.steady.isNotEmpty) ...[
          const SectionHeader('Checked, and steady'),
          for (final s in r.steady) _Note(icon: Icons.horizontal_rule, text: s),
        ],
        if (r.ratings >= minRatings && r.byWeekday.length >= 2) ...[
          const SectionHeader('Mood by weekday'),
          _Bars(labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
              values: [for (var w = 1; w <= 7; w++) r.byWeekday[w]],
              footer: 'The average of each weekday\'s ratings in the last $windowDays days. Paler bars rest on fewer '
                  'than $minGroup ratings.'),
        ],
        if (r.byPartOfDay.values.fold<int>(0, (a, b) => a + b.n) >= minRatings) ...[
          const SectionHeader('Mood by time of day'),
          _Bars(labels: const ['Morning', 'Afternoon', 'Evening', 'Night'],
              values: [for (final (id, _) in partsOfDay) r.byPartOfDay[id]],
              footer: 'By when you rated your mood. Morning is 5:00 to 11:59, afternoon 12:00 to 16:59, evening 17:00 '
                  'to 21:59, night 22:00 to 4:59.'),
        ],
        if (r.questionnaires.isNotEmpty) ...[
          const SectionHeader('Questionnaires'),
          for (final q in r.questionnaires) _InsightCard(insight: q, icon: Icons.checklist),
        ],
        if (r.topWords.isNotEmpty) ...[
          const SectionHeader('The feelings you named most'),
          Wrap(spacing: Space.s - 2, runSpacing: Space.s - 2, children: [
            for (final (w, n) in r.topWords)
              Chip(label: Text('$w · $n'),
                  backgroundColor: quadrantHues(context, quadrantOfWord[w] ?? 'low_pleasant').$2,
                  side: BorderSide.none),
          ]),
          const SizedBox(height: Space.s),
          Text('From ${r.feelings} named-feeling check-ins in the last $windowDays days.', style: t.bodySmall),
        ],
        if (r.waiting.isNotEmpty) ...[
          const SectionHeader('Still gathering'),
          for (final w in r.waiting) _Note(icon: Icons.timelapse, text: w),
        ],
        const SectionHeader('Look back'),
        Card(child: Column(children: [
          for (final (span, title, sub, icon) in [
            (ReviewSpan.week, 'Your week', 'The last seven days, counted on this device', Icons.view_week_outlined),
            (ReviewSpan.month, 'Your month', 'This month so far, with a few words from Solace', Icons.calendar_month_outlined),
            (ReviewSpan.year, 'Your year', 'Your year in review, a dot for every day you rated', Icons.grid_view),
          ])
            ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(sub),
                trailing: const Icon(Icons.chevron_right), onTap: () => review(span)),
        ])),
        const SizedBox(height: Space.l),
        Text('How this works: Solace shows a mood pattern only with at least $minRatings ratings behind it, at least '
            '$minGroup on each side of the comparison, and a difference of at least 1 point on the 0 to 10 scale. '
            'Everything is worked out on this device and never leaves ${staysOnFor(AppScope.of(context).data.settings.homeServer)}.', style: t.bodySmall),
      ])),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, this.icon});
  final Insight insight;
  final IconData? icon;
  static const _icons = {'weekday': Icons.calendar_view_week, 'time_of_day': Icons.schedule,
    'tag': Icons.label_outline, 'programme': Icons.route_outlined, 'questionnaire': Icons.checklist};
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(margin: const EdgeInsets.only(bottom: Space.s + 2), child: Padding(padding: const EdgeInsets.all(Space.l),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 17, backgroundColor: scheme.primaryContainer,
          child: Icon(icon ?? _icons[insight.kind] ?? Icons.lightbulb_outline, size: 18, color: scheme.onPrimaryContainer)),
      const SizedBox(width: Space.m),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(insight.text, style: t.bodyLarge),
        const SizedBox(height: Space.xs),
        Text(insight.detail, style: t.bodySmall),
      ])),
    ])));
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: Space.s + 2), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    const SizedBox(width: Space.m),
    Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
  ]));
}

/// Calm bars on the 0 to 10 scale, each in the mood colour of its average; pale when it rests on few ratings.
class _Bars extends StatelessWidget {
  const _Bars({required this.labels, required this.values, required this.footer});
  final List<String> labels;
  final List<Mean?> values;
  final String footer;
  @override
  Widget build(BuildContext context) {
    final mood = huesOf(context).mood;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 150, child: BarChart(BarChartData(
        minY: 0, maxY: 10, alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(drawVerticalLine: false, horizontalInterval: 5, getDrawingHorizontalLine: (_) =>
            FlLine(color: scheme.outlineVariant, strokeWidth: 1, dashArray: const [4, 4])),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 5, reservedSize: 24,
              getTitlesWidget: (v, m) => Text(m.formattedValue, style: const TextStyle(fontSize: 11)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22,
              getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 4), child: FittedBox(
                  fit: BoxFit.scaleDown, child: Text(labels[v.toInt()], style: const TextStyle(fontSize: 11)))))),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: values[i]?.mean ?? 0, width: labels.length > 4 ? 16 : 28,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  color: values[i] == null ? Colors.transparent
                      : mood[values[i]!.mean.round().clamp(0, 10)].withValues(alpha: values[i]!.n < minGroup ? 0.35 : 0.9)),
            ]),
        ],
      ))),
      const SizedBox(height: Space.s),
      Text(footer, style: t.bodySmall),
    ])));
  }
}
