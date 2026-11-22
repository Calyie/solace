// Days you showed up (report recommendation 23): a calm month of dots on the Progress tab. Any check-in, practice or
// session softly fills its day (core/insights.dart showedUpDates). No counter, no streak, nothing "broken": a quiet
// day is simply an empty dot. Highlighting a broken streak lowers later engagement (Silverman and Barasch, 2023) and
// streaks and badges are discouraged for people in distress (Common Sense Media, 2026), so the calendar only compares
// the person with nobody and counts nothing.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/insights.dart';
import '../core/review.dart' show monthName;
import 'premium.dart';

class ShowedUpCalendar extends StatefulWidget {
  const ShowedUpCalendar({super.key});
  @override
  State<ShowedUpCalendar> createState() => _ShowedUpCalendarState();
}

class _ShowedUpCalendarState extends State<ShowedUpCalendar> {
  int _back = 0; // months before this one

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final now = state.clock();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(now.year, now.month - _back, 1);
    final days = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final showed = showedUpDates(state.data);
    final today = isoDate(now);
    final title = _back == 0 ? 'Days you showed up this month' : 'Days you showed up';
    return Card(margin: const EdgeInsets.only(bottom: Space.m), child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: t.titleMedium),
      Row(children: [
        IconButton(key: const Key('showed_up_earlier'), tooltip: 'Earlier month', icon: const Icon(Icons.chevron_left),
            onPressed: _back >= 23 ? null : () => setState(() => _back++)),
        Expanded(child: Text('${monthName(first.month)} ${first.year}', textAlign: TextAlign.center,
            style: t.titleSmall)),
        IconButton(key: const Key('showed_up_later'), tooltip: 'Later month', icon: const Icon(Icons.chevron_right),
            onPressed: _back == 0 ? null : () => setState(() => _back--)),
      ]),
      LayoutBuilder(builder: (context, box) {
        final cell = (box.maxWidth / 7).floorToDouble();
        final dot = math.min(34.0, cell - 6);
        return Column(children: [
          Row(children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              SizedBox(width: cell, child: Center(child: FittedBox(fit: BoxFit.scaleDown,
                  child: Text(d, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant))))),
          ]),
          const SizedBox(height: Space.xs),
          AnimatedSwitcher(duration: Calm.normal, switchInCurve: Calm.curve, switchOutCurve: Calm.curve,
              child: Wrap(key: ValueKey(_back), children: [
            for (var i = 0; i < lead; i++) SizedBox(width: cell, height: dot + 6),
            for (var day = 1; day <= days; day++)
              _day(context, DateTime(first.year, first.month, day), showed, today, cell, dot),
          ])),
        ]);
      }),
      const SizedBox(height: Space.s),
      Text('Any check-in, practice or session fills its day. Quiet days are simply quiet.', style: t.bodySmall),
    ])));
  }

  Widget _day(BuildContext context, DateTime date, Set<String> showed, String today, double cell, double dot) {
    final scheme = Theme.of(context).colorScheme;
    final iso = isoDate(date);
    final filled = showed.contains(iso);
    final future = iso.compareTo(today) > 0;
    final isToday = iso == today;
    return Semantics(container: true, label: '${dayLabel(date)}${filled ? ', you showed up' : ''}', excludeSemantics: true,
        child: SizedBox(key: Key('day_$iso'), width: cell, height: dot + 6, child: Center(child: AnimatedContainer(
          duration: Calm.normal, curve: Calm.curve, width: dot, height: dot, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: filled ? scheme.primaryContainer : null,
              border: isToday ? Border.all(color: scheme.primary, width: 1.5)
                  : filled ? null : Border.all(color: scheme.outlineVariant.withValues(alpha: future ? 0.4 : 1))),
          child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(3), child: Text(
              '${date.day}', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: filled ? FontWeight.w700 : FontWeight.w400,
                  color: filled ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant.withValues(alpha: future ? 0.5 : 1))))),
        ))));
  }
}
