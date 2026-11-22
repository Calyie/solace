// Patterns worth noticing (report recommendation 22): computed on the device from what the person has recorded, and
// never sent anywhere. Mood by weekday and by time of day, mood on days with and without each "what's affecting you"
// tag, mood before and after starting a programme, questionnaire trends with their bands, and the feelings named most.
//
// A pattern is shown only when there is enough to go on: at least [minRatings] mood ratings behind it, at least
// [minGroup] on each side of the comparison, and a difference of at least [minDifference] points on the 0 to 10
// scale. Below that, the screen says what is still needed instead of guessing. The words stay tentative throughout
// ("worth noticing, not a verdict"), following Bearable's correlation-not-causation framing and its weeks-of-data
// caveat (docs/research/research_notes/Premium wellbeing app design/features_and_engagement.md, section 4).
import 'dates.dart';
import 'emotions.dart';
import 'questionnaires.dart';
import 'store.dart';

const minRatings = 8; // mood ratings behind any mood pattern
const minGroup = 3; // ratings on each side of a comparison
const minDifference = 1.0; // points on the 0 to 10 scale
const minFeelings = 5; // named-feeling check-ins before the most-named words are shown
const windowDays = 90; // mood patterns look at the last 90 days
const programmeBeforeDays = 28; // "before a programme" is the four weeks before its first day

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The parts of the day, in order: (id, as said in a sentence).
const partsOfDay = <(String, String)>[
  ('morning', 'in the morning'), ('afternoon', 'in the afternoon'), ('evening', 'in the evening'), ('night', 'at night'),
];

/// Morning 05:00 to 11:59, afternoon 12:00 to 16:59, evening 17:00 to 21:59, night 22:00 to 04:59.
String partOfDay(int hour) => hour >= 5 && hour < 12 ? 'morning' : hour >= 12 && hour < 17 ? 'afternoon'
    : hour >= 17 && hour < 22 ? 'evening' : 'night';

/// One thing worth noticing: the sentence the person reads, and what it rests on.
class Insight {
  const Insight({required this.kind, required this.text, required this.detail, this.size = 0});
  final String kind; // weekday, time_of_day, tag, programme, questionnaire, feelings
  final String text;
  final String detail;
  final double size; // how large the difference is, for ordering (0 when there is none)
}

/// An average and how many ratings it rests on.
typedef Mean = ({double mean, int n});

class InsightReport {
  const InsightReport({required this.patterns, required this.steady, required this.waiting,
      required this.questionnaires, required this.byWeekday, required this.byPartOfDay, required this.topWords,
      required this.quadrantCounts, required this.ratings, required this.feelings});
  final List<Insight> patterns; // mood patterns that cleared the bar, largest first
  final List<String> steady; // enough data, but nothing stood out: said plainly, never hidden
  final List<String> waiting; // what is not shown yet, and what it needs
  final List<Insight> questionnaires; // trends with their bands
  final Map<int, Mean> byWeekday; // 1 (Monday) to 7, only days with ratings
  final Map<String, Mean> byPartOfDay; // only parts with ratings
  final List<(String, int)> topWords; // the feelings named most, at most five
  final Map<String, int> quadrantCounts;
  final int ratings; // mood ratings in the window
  final int feelings; // named-feeling check-ins in the window
}

Mean? _mean(Iterable<int> xs) {
  if (xs.isEmpty) return null;
  return (mean: xs.fold<int>(0, (a, b) => a + b) / xs.length, n: xs.length);
}

String _points(double d) => '${d.abs().toStringAsFixed(1)} ${d.abs().toStringAsFixed(1) == '1.0' ? 'point' : 'points'}';

String _higherLower(double d) => d > 0 ? 'higher' : 'lower';

/// "10 November" (no weekday).
String dayMonth(DateTime d) => dayLabel(d).split(' ').skip(1).join(' ');

DateTime _day(String iso) => DateTime.parse(iso);

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The ratings ([date, mood]) in the last [windowDays] days, today included.
Map<String, int> recentMoods(AppData d, DateTime now) {
  final from = isoDate(DateTime(now.year, now.month, now.day - (windowDays - 1))), to = isoDate(now);
  return {
    for (final MapEntry(:key, :value) in d.moods.entries)
      if (key.compareTo(from) >= 0 && key.compareTo(to) <= 0 && value >= 0 && value <= 10) key: value,
  };
}

/// True when at least one group has enough ratings, inside and outside it, to be compared with the rest.
bool _comparable(Map<String, List<int>> groups) {
  final all = groups.values.fold<int>(0, (a, b) => a + b.length);
  return all >= minRatings && groups.values.any((g) => g.length >= minGroup && all - g.length >= minGroup);
}

/// Compare each group with all the others; the largest difference up and down that clears the bar.
List<(String, double, int, int)> _standouts(Map<String, List<int>> groups) {
  final all = [for (final g in groups.values) ...g];
  final found = <(String, double, int, int)>[];
  for (final MapEntry(key: name, value: inside) in groups.entries) {
    final outside = [for (final MapEntry(:key, :value) in groups.entries) if (key != name) ...value];
    if (inside.length < minGroup || outside.length < minGroup || all.length < minRatings) continue;
    final diff = _mean(inside)!.mean - _mean(outside)!.mean;
    if (diff.abs() >= minDifference) found.add((name, diff, inside.length, outside.length));
  }
  found.sort((a, b) => b.$2.compareTo(a.$2));
  if (found.length <= 2) return found;
  return [found.first, found.last]; // the clearest high and the clearest low; the rest would only repeat them
}

InsightReport computeInsights(AppData d, DateTime now) {
  final moods = recentMoods(d, now);
  final patterns = <Insight>[], steady = <String>[], waiting = <String>[];

  // Mood by weekday
  final weekdays = <String, List<int>>{};
  for (final MapEntry(:key, :value) in moods.entries) {
    (weekdays['${_day(key).weekday}'] ??= []).add(value);
  }
  if (moods.length < minRatings) {
    waiting.add('Mood by weekday: shown after $minRatings mood ratings in the last $windowDays days '
        '(you have ${moods.length}).');
  } else if (!_comparable(weekdays)) {
    waiting.add('Mood by weekday: shown once one weekday has $minGroup ratings to compare with the other days.');
  } else {
    final found = _standouts(weekdays);
    for (final (w, diff, n, others) in found) {
      final name = '${weekdayNames[int.parse(w) - 1]}s';
      patterns.add(Insight(kind: 'weekday', size: diff.abs(),
          text: 'On $name your mood was ${_points(diff)} ${_higherLower(diff)} than on other days, on average. '
              'Worth noticing, not a verdict.',
          detail: 'From $n $name and $others other days you rated in the last $windowDays days.'));
    }
    if (found.isEmpty) {
      steady.add('Your mood looks much the same across the week: no weekday stands out by a point or more.');
    }
  }

  // Mood by time of day (when the day's mood was last tapped; ratings saved before times were kept have none)
  final parts = <String, List<int>>{};
  for (final MapEntry(:key, :value) in moods.entries) {
    final at = d.moodTimes[key];
    if (at == null) continue;
    (parts[partOfDay(int.parse(at.substring(0, 2)))] ??= []).add(value);
  }
  final timed = parts.values.fold<int>(0, (a, b) => a + b.length);
  if (timed < minRatings) {
    waiting.add('Mood by time of day: shown after $minRatings ratings with a time (you have $timed; ratings saved '
        'before this version have no time).');
  } else if (!_comparable(parts)) {
    waiting.add('Mood by time of day: shown once you have rated at different times of day, $minGroup times or more '
        'in one of them.');
  } else {
    final found = _standouts(parts);
    for (final (p, diff, n, others) in found) {
      final said = partsOfDay.firstWhere((x) => x.$1 == p).$2;
      patterns.add(Insight(kind: 'time_of_day', size: diff.abs(),
          text: 'When you rated your mood $said, it was ${_points(diff)} ${_higherLower(diff)} than at other times, '
              'on average. Worth noticing, not a verdict.',
          detail: 'From $n ratings made $said and $others at other times.'));
    }
    if (found.isEmpty) steady.add('No time of day stands out: your ratings look much the same morning to night.');
  }

  // Mood on days with and without each tag: compared among the days the person named a feeling, so a day with no
  // check-in (when nothing could be tagged) never counts as a day "without"
  final from = isoDate(DateTime(now.year, now.month, now.day - (windowDays - 1)));
  final recent = [for (final e in d.emotions) if (e.date.compareTo(from) >= 0 && e.date.compareTo(isoDate(now)) <= 0) e];
  final tagsByDay = <String, Set<String>>{};
  for (final e in recent) {
    (tagsByDay[e.date] ??= {}).addAll(e.tags);
  }
  final namedDays = [for (final day in tagsByDay.keys) if (moods.containsKey(day)) day];
  if (namedDays.length < minRatings) {
    waiting.add('Mood with what\'s affecting you: shown after $minRatings days with both a mood rating and a named '
        'feeling (you have ${namedDays.length}).');
  } else {
    final before = patterns.length;
    // tags always used on the same days are one pattern, not several; and a set of days that is exactly the other
    // side of one already shown is the same comparison seen from the other side, so it is not shown twice
    final sameDays = <String, List<String>>{}; // the days with the tag -> the tags used on exactly those days
    for (final (tag, label) in affectingTags) {
      final days = [for (final day in namedDays) if (tagsByDay[day]!.contains(tag)) day]..sort();
      if (days.isNotEmpty) (sameDays[days.join(',')] ??= []).add(label.toLowerCase());
    }
    final shown = <String>{};
    for (final MapEntry(key: key, value: labels) in sameDays.entries) {
      final withDays = key.split(',').toSet();
      final withoutDays = [for (final day in namedDays) if (!withDays.contains(day)) day]..sort();
      if (withDays.length < minGroup || withoutDays.length < minGroup || shown.contains(withoutDays.join(','))) continue;
      final diff = _mean([for (final day in withDays) moods[day]!])!.mean - _mean([for (final day in withoutDays) moods[day]!])!.mean;
      if (diff.abs() < minDifference) continue;
      shown.add(key);
      final named = labels.map((l) => '“$l”').toList();
      final tagged = named.length == 1 ? named.single : '${named.sublist(0, named.length - 1).join(', ')} and ${named.last}';
      patterns.add(Insight(kind: 'tag', size: diff.abs(),
          text: 'On days you tagged $tagged, your mood was ${_points(diff)} ${_higherLower(diff)} on average. '
              'Worth noticing, not a verdict.',
          detail: 'From ${withDays.length} days with ${named.length == 1 ? 'that tag' : 'those tags, always together,'} '
              'and ${withoutDays.length} other days you named a feeling.'));
    }
    if (patterns.length == before) {
      steady.add('None of the things you tagged goes with a mood difference of a point or more so far.');
    }
  }

  // Mood before and after starting a programme
  for (final p in d.programmes) {
    final start = DateTime.tryParse(p.start);
    if (start == null) continue;
    final s = isoDate(start), b = isoDate(DateTime(start.year, start.month, start.day - programmeBeforeDays));
    final beforeMoods = [for (final MapEntry(:key, :value) in d.moods.entries) if (key.compareTo(b) >= 0 && key.compareTo(s) < 0) value];
    final afterMoods = [for (final MapEntry(:key, :value) in d.moods.entries)
        if (key.compareTo(s) >= 0 && key.compareTo(isoDate(now)) <= 0) value];
    final name = _capital(p.name);
    if (beforeMoods.length < minGroup || afterMoods.length < minGroup || beforeMoods.length + afterMoods.length < minRatings) {
      waiting.add('Mood before and after $name: shown after $minGroup rated days in the four weeks before it and '
          '$minGroup since ($minRatings in all; you have ${beforeMoods.length} before and ${afterMoods.length} since).');
      continue;
    }
    final diff = _mean(afterMoods)!.mean - _mean(beforeMoods)!.mean;
    if (diff.abs() < minDifference) {
      steady.add('Your mood since you started $name is within a point of the four weeks before.');
      continue;
    }
    patterns.add(Insight(kind: 'programme', size: diff.abs(),
        text: 'Since you started $name on ${dayMonth(start)}, your mood has been ${_points(diff)} ${_higherLower(diff)} '
            'on average than in the four weeks before. Many things change at once, so this is worth noticing, not proof.',
        detail: 'From ${beforeMoods.length} rated days before and ${afterMoods.length} since.'));
  }
  patterns.sort((a, b) => b.size.compareTo(a.size));

  // Questionnaire trends, with their bands
  final trends = <Insight>[];
  for (final q in questionnaires) {
    final rows = [for (final s in d.scores) if (s['name'] == q.name && s['total'] is int && s['date'] is String) s]
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    if (rows.isEmpty) continue;
    final last = rows.last, lastTotal = last['total'] as int, lastDate = dayMonth(_day(last['date'] as String));
    if (rows.length == 1) {
      trends.add(Insight(kind: 'questionnaire',
          text: 'One ${q.name} so far: $lastTotal (${q.band(lastTotal)}) on $lastDate.',
          detail: 'A second one, two weeks or more later, shows the direction. Lower scores mean fewer difficulties.'));
      continue;
    }
    final first = rows.first, firstTotal = first['total'] as int, firstDate = dayMonth(_day(first['date'] as String));
    final change = lastTotal == firstTotal
        ? 'stayed at $lastTotal (${q.band(lastTotal)}) from $firstDate to $lastDate'
        : 'went from $firstTotal (${q.band(firstTotal)}) on $firstDate to $lastTotal (${q.band(lastTotal)}) on $lastDate';
    trends.add(Insight(kind: 'questionnaire', size: (lastTotal - firstTotal).abs().toDouble(),
        text: 'Your ${q.name} $change.',
        detail: '${rows.length} answers in all. Lower scores mean fewer difficulties; a questionnaire is a snapshot, '
            'not a diagnosis.'));
  }
  if (trends.isEmpty) waiting.add('Questionnaire trends: shown after your first mood and anxiety check (PHQ-9, GAD-7).');

  // The feelings named most
  final counts = <String, int>{}, quadrantCounts = <String, int>{};
  for (final e in recent) {
    quadrantCounts[e.quadrant] = (quadrantCounts[e.quadrant] ?? 0) + 1;
    for (final w in e.words) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
  }
  final topWords = (counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value)
      : a.key.compareTo(b.key))).take(5).map((e) => (e.key, e.value)).toList();
  if (recent.length < minFeelings) {
    waiting.add('The feelings you name most: shown after $minFeelings named-feeling check-ins (you have ${recent.length}).');
  }

  return InsightReport(patterns: patterns, steady: steady, waiting: waiting, questionnaires: trends,
      byWeekday: {for (final MapEntry(:key, :value) in weekdays.entries) int.parse(key): _mean(value)!},
      byPartOfDay: {for (final MapEntry(:key, :value) in parts.entries) key: _mean(value)!},
      topWords: recent.length < minFeelings ? const [] : topWords, quadrantCounts: quadrantCounts,
      ratings: moods.length, feelings: recent.length);
}

/// The days the person showed up: any check-in (a mood, a named feeling, a questionnaire), practice (a practice
/// session, a programme entry, a habit kept, a plan step done) or session. Never a streak: the calendar only fills
/// the days that happened.
Set<String> showedUpDates(AppData d) => {
      ...d.moods.keys,
      for (final e in d.emotions) e.date,
      for (final s in d.sessions) s.date,
      for (final s in d.scores) if (s['date'] is String) s['date'] as String,
      for (final p in d.programmes) for (final (date, _) in p.log) date,
      for (final h in d.plans.habits) ...h.kept,
      for (final s in d.plans.steps) if (s.status == 'done' && s.day.isNotEmpty) s.day,
      for (final j in d.journal) if (j['date'] is String) j['date'] as String,
    };
