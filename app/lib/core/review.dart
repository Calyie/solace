// The weekly review, the monthly letter and the year in review (report recommendation 22): the summary is counted
// here, in code, from what the person recorded; the local model may then add two or three warm sentences from that
// summary. The model reflects and never counts: it is given the numbers, asked to write none, and any sentence of its
// reply that still holds a digit is left out (cleanReflection), so a number on the screen always comes from here.
import 'check_in_guard.dart' show ReplyScreen;
import 'dates.dart';
import 'emotions.dart';
import 'formats.dart' show neutraliseControlTokens;
import 'insights.dart' show Mean, dayMonth;
import 'questionnaires.dart';
import 'store.dart';

enum ReviewSpan { week, month, year }

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December'];

String monthName(int month) => _monthNames[month - 1];

/// Calendar days from [from] to [to], both included.
typedef Period = ({DateTime from, DateTime to});

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// Calendar days from [a] to [b], both included (counted in UTC, so a clock change never loses a day).
int daysIn(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays + 1;

/// The period a review covers: the last seven days, this calendar month so far, or this year so far; [back] steps
/// to the ones before (1 is last week, last month or last year).
Period periodFor(ReviewSpan span, DateTime now, {int back = 0}) {
  final today = _date(now);
  switch (span) {
    case ReviewSpan.week:
      final to = DateTime(today.year, today.month, today.day - 7 * back);
      return (from: DateTime(to.year, to.month, to.day - 6), to: to);
    case ReviewSpan.month:
      final from = DateTime(today.year, today.month - back, 1);
      final end = DateTime(from.year, from.month + 1, 0);
      return (from: from, to: end.isAfter(today) ? today : end);
    case ReviewSpan.year:
      final from = DateTime(today.year - back, 1, 1);
      final end = DateTime(from.year, 12, 31);
      return (from: from, to: end.isAfter(today) ? today : end);
  }
}

/// One line of the summary: what it is about (for its icon) and the sentence.
class ReviewFact {
  const ReviewFact(this.kind, this.text);
  final String kind; // mood, feelings, affecting, sessions, steps, programme, questionnaire
  final String text;
}

class ReviewSummary {
  ReviewSummary({required this.span, required this.from, required this.to, required this.moods,
      required this.facts, required this.previousMood});
  final ReviewSpan span;
  final DateTime from, to;
  final Map<String, int> moods; // ISO date -> mood, inside the period
  final List<ReviewFact> facts;
  final Mean? previousMood;

  String get noun => const {ReviewSpan.week: 'week', ReviewSpan.month: 'month', ReviewSpan.year: 'year'}[span]!;
  String get title => 'Your $noun';
  String get range => switch (span) {
        ReviewSpan.week => '${dayLabel(from)} to ${dayLabel(to)}',
        ReviewSpan.month => '${monthName(from.month)} ${from.year}',
        ReviewSpan.year => '${from.year}',
      };
  int get days => daysIn(from, to);
  bool get isEmpty => facts.isEmpty;

  /// Average mood for each month (year in review): month 1 to 12 -> mean, only months with ratings.
  Map<int, Mean> get moodByMonth {
    final groups = <int, List<int>>{};
    for (final MapEntry(:key, :value) in moods.entries) {
      (groups[int.parse(key.substring(5, 7))] ??= []).add(value);
    }
    return {
      for (final MapEntry(:key, :value) in groups.entries)
        key: (mean: value.fold<int>(0, (a, b) => a + b) / value.length, n: value.length),
    };
  }

  /// The summary as the model is shown it: one fact per line.
  String get factsText => [for (final f in facts) '- ${f.text}'].join('\n');
}

String _list(List<String> xs) => xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
String _times(int n, String one, [String? many]) => '$n ${n == 1 ? one : many ?? '${one}s'}';
String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

ReviewSummary buildReview(AppData d, ReviewSpan span, DateTime now, {int back = 0}) {
  final p = periodFor(span, now, back: back);
  final from = isoDate(p.from), to = isoDate(p.to);
  bool inside(String iso) => iso.compareTo(from) >= 0 && iso.compareTo(to) <= 0;
  final days = daysIn(p.from, p.to);
  final facts = <ReviewFact>[];

  // Mood, and the period before for comparison
  final moods = {for (final MapEntry(:key, :value) in d.moods.entries) if (inside(key)) key: value};
  final prev = periodFor(span, now, back: back + 1);
  final prevMoods = [for (final MapEntry(:key, :value) in d.moods.entries)
      if (key.compareTo(isoDate(prev.from)) >= 0 && key.compareTo(isoDate(prev.to)) <= 0) value];
  // the period before is mentioned only when it rests on a few ratings, not one stray day
  final Mean? previous = prevMoods.length < 3 ? null
      : (mean: prevMoods.fold<int>(0, (a, b) => a + b) / prevMoods.length, n: prevMoods.length);
  final noun = const {ReviewSpan.week: 'week', ReviewSpan.month: 'month', ReviewSpan.year: 'year'}[span]!;
  if (moods.isNotEmpty) {
    final values = moods.values.toList()..sort();
    final mean = values.fold<int>(0, (a, b) => a + b) / values.length;
    final spread = values.first == values.last ? '' : ' (from ${values.first} to ${values.last})';
    final before = previous == null ? '' : ' The $noun before: ${previous.mean.toStringAsFixed(1)} on average.';
    facts.add(ReviewFact('mood', 'Mood: rated on ${moods.length} of ${_times(days, 'day')}, '
        '${mean.toStringAsFixed(1)} out of 10 on average$spread.$before'));
  }

  // Feelings named, and what was affecting them
  final named = [for (final e in d.emotions) if (inside(e.date)) e];
  if (named.isNotEmpty) {
    final words = <String, int>{}, tags = <String, int>{};
    for (final e in named) {
      for (final w in e.words) {
        words[w] = (words[w] ?? 0) + 1;
      }
      for (final t in e.tags) {
        tags[t] = (tags[t] ?? 0) + 1;
      }
    }
    List<String> top(Map<String, int> m, int k) => (m.entries.toList()
          ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key)))
        .take(k).map((e) => e.key).toList();
    facts.add(ReviewFact('feelings', 'Feelings named: ${_times(named.length, 'time')}; most often '
        '${_list(top(words, 3))}.'));
    if (tags.isNotEmpty) {
      facts.add(ReviewFact('affecting', 'What was affecting you most: '
          '${_list([for (final t in top(tags, 3)) tagLabel(t).toLowerCase()])}.'));
    }
  }

  // Sessions and practice sessions
  final sessions = d.sessions.where((s) => inside(s.date) && s.kind != 'practice').length;
  final practices = d.sessions.where((s) => inside(s.date) && s.kind == 'practice').length;
  if (sessions + practices > 0) {
    facts.add(ReviewFact('sessions', [
      if (sessions > 0) 'Sessions with Solace: $sessions.',
      if (practices > 0) 'Practice sessions: $practices.',
    ].join(' ')));
  }

  // Plan steps done and habits kept
  final steps = d.plans.steps.where((s) => s.status == 'done' && s.day.isNotEmpty && inside(s.day)).length;
  final habitDays = {for (final h in d.plans.habits) for (final k in h.kept) if (inside(k)) k}.length;
  if (steps + habitDays > 0) {
    facts.add(ReviewFact('steps', [
      if (steps > 0) 'Plan steps done: $steps.',
      if (habitDays > 0) 'Habits kept on ${_times(habitDays, 'day')}.',
    ].join(' ')));
  }

  // Programme progress
  for (final pr in d.programmes) {
    final start = DateTime.tryParse(pr.start);
    if (start == null || isoDate(start).compareTo(to) > 0) continue;
    final entries = pr.log.where((e) => inside(e.$1)).length;
    facts.add(ReviewFact('programme', '${_capital(pr.name)}: day ${pr.dayOn(p.to)}, '
        '${_times(pr.sessions, 'session')} done in all'
        '${entries > 0 ? ', ${_times(entries, 'entry', 'entries')} in its log this $noun' : ''}.'));
  }

  // Questionnaire changes: the answers inside the period, with the one before it for comparison
  for (final q in questionnaires) {
    final rows = [for (final s in d.scores) if (s['name'] == q.name && s['total'] is int && s['date'] is String) s]
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    final within = [for (final r in rows) if (inside(r['date'] as String)) r];
    if (within.isEmpty) continue;
    final earlier = [for (final r in rows) if ((r['date'] as String).compareTo(from) < 0) r];
    String said(Map<String, dynamic> r) =>
        '${r['total']} (${q.band(r['total'] as int)}) on ${dayMonth(DateTime.parse(r['date'] as String))}';
    final shown = within.length > 3 ? [within.first, within.last] : within;
    facts.add(ReviewFact('questionnaire', '${q.name}: ${shown.map(said).join(', then ')}'
        '${earlier.isEmpty ? '' : '; before that ${said(earlier.last)}'}.'));
  }

  return ReviewSummary(span: span, from: p.from, to: p.to, moods: moods, facts: facts, previousMood: previous);
}

/// The messages for the local model: the template's first paragraph as the system message, the rest (with the
/// period and the facts filled in) as the request.
List<Map<String, String>> reviewMessages(String template, ReviewSummary s) {
  // the facts carry words from the person's records, which an imported file could fill: never control tokens (AI-1)
  final filled = template.replaceAll('{period}', s.noun)
      .replaceAll('{facts}', neutraliseControlTokens(s.factsText)).trim();
  final split = filled.indexOf('\n\n');
  return [
    {'role': 'system', 'content': split < 0 ? filled : filled.substring(0, split).trim()},
    {'role': 'user', 'content': split < 0 ? 'Write the few words now.' : filled.substring(split).trim()},
  ];
}

/// The model's words, with any sentence that holds a digit left out (the numbers on screen come only from the
/// summary), and at most four sentences. Empty when nothing usable is left. A sentence that gives a way or a means to
/// harm, or quotes how the app set the model up, is left out too, and its rule group (never the sentence) goes to
/// [onBlocked] (core/check_in_guard.dart ReplyScreen; security review 2026-11-14, AI-4).
String cleanReflection(String text, {void Function(String group)? onBlocked}) {
  final screen = ReplyScreen();
  final sentences = text.replaceAll(RegExp(r'\s+'), ' ').trim().split(RegExp(r'(?<=[.!?])\s+'));
  final kept = <String>[];
  for (final s in sentences) {
    if (s.trim().isEmpty || RegExp(r'\d').hasMatch(s)) continue;
    final group = screen.groupOf(s);
    if (group != null) {
      onBlocked?.call(group);
      continue;
    }
    kept.add(s.trim());
  }
  return kept.take(4).join(' ');
}
