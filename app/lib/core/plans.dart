// Plans, habits, goals, values and the vision board: kept by the app and built from the session notes.
// The text rendered here must match pipeline/plans.py exactly, because it is what the model was trained on;
// test/plans_test.dart checks it against renderings made by Python (test/fixtures/plans_v2.json).
import 'dates.dart';

const weekdays = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const planHeadings = <String>['Plan steps', 'Habits', 'Goals', 'Values', 'Vision board'];
const maxNoticed = 3;

/// A calendar day with no time or time zone, as an ISO date ("2026-11-18").
/// Never throws (verification round 2: a plan date of "soon" in an imported file made every session start fail): a
/// date it cannot read counts as long ago, 1 January 2000.
DateTime dayOf(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (m == null) return DateTime.utc(2000);
  return DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}
DateTime _minus(DateTime d, int days) => DateTime.utc(d.year, d.month, d.day - days);
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day)).inDays;

const cueWords = <String>['after ', 'before ', 'when ', 'at ', 'on ', 'every ', 'once ', 'as soon as '];

/// 'coffee' -> 'after coffee'; a cue that already says when stays as it is (same as cue_text in plans.py).
String cueText(String cue) =>
    cue.isEmpty ? '' : cueWords.any((w) => cue.toLowerCase().startsWith(w)) ? cue : 'after $cue';

/// Lower case, letters (accented too), digits and apostrophes only (same as norm in pipeline/plans.py).
String norm(String s) => s
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r"[^\p{L}\p{N}']", unicode: true), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .join(' ');

/// True when the quote (two words or more) is something the person said, ignoring case and punctuation. A quote
/// shortened with "..." counts when every piece appears in what they said, in order (same as plans.py).
bool grounded(String quote, String personText) {
  final pieces = [for (final x in quote.split(RegExp(r'\.\.\.|…'))) norm(x)].where((x) => x.isNotEmpty).toList();
  if (pieces.fold<int>(0, (n, x) => n + x.split(' ').length) < 2) return false;
  final said = norm(personText);
  var at = 0;
  for (final x in pieces) {
    final i = said.indexOf(x, at);
    if (i < 0) return false;
    at = i + x.length;
  }
  return true;
}

String _stripChars(String s, String chars, {bool left = true, bool right = true}) {
  var a = 0, b = s.length;
  while (left && a < b && chars.contains(s[a])) {
    a++;
  }
  while (right && b > a && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(a, b);
}

class Step {
  Step({required this.text, this.day = '', this.time = '', this.ifthen = '', this.quote = '', this.added = '',
      this.status = 'open', this.moves = 0});
  String text, day, time, ifthen, quote, added, status; // status: open, done or dropped
  int moves;

  Map<String, dynamic> toJson() => {'text': text, 'day': day, 'time': time, 'ifthen': ifthen, 'quote': quote,
        'added': added, 'status': status, 'moves': moves};
  factory Step.fromJson(Map<String, dynamic> j) => Step(text: j['text'] ?? '', day: j['day'] ?? '', time: j['time'] ?? '',
      ifthen: j['ifthen'] ?? '', quote: j['quote'] ?? '', added: j['added'] ?? '', status: j['status'] ?? 'open',
      moves: j['moves'] ?? 0);
}

class Habit {
  Habit({required this.text, this.cue = '', this.tiny = '', this.quote = '', this.start = '', List<String>? kept,
      List<String>? missed})
      : kept = kept ?? [],
        missed = missed ?? [];
  String text, cue, tiny, quote, start;
  final List<String> kept, missed; // ISO dates

  Map<String, dynamic> toJson() =>
      {'text': text, 'cue': cue, 'tiny': tiny, 'quote': quote, 'start': start, 'kept': kept, 'missed': missed};
  factory Habit.fromJson(Map<String, dynamic> j) => Habit(text: j['text'] ?? '', cue: j['cue'] ?? '', tiny: j['tiny'] ?? '',
      quote: j['quote'] ?? '', start: j['start'] ?? '', kept: List<String>.from(j['kept'] ?? []),
      missed: List<String>.from(j['missed'] ?? []));
}

class Goal {
  Goal({required this.text, this.nextStep = '', this.quote = '', this.added = '', this.lastProgress = ''});
  String text, nextStep, quote, added, lastProgress;

  Map<String, dynamic> toJson() =>
      {'text': text, 'next_step': nextStep, 'quote': quote, 'added': added, 'last_progress': lastProgress};
  factory Goal.fromJson(Map<String, dynamic> j) => Goal(text: j['text'] ?? '', nextStep: j['next_step'] ?? '',
      quote: j['quote'] ?? '', added: j['added'] ?? '', lastProgress: j['last_progress'] ?? '');
}

class Value {
  Value({required this.text, this.quote = '', this.added = ''});
  String text, quote, added;

  Map<String, dynamic> toJson() => {'text': text, 'quote': quote, 'added': added};
  factory Value.fromJson(Map<String, dynamic> j) =>
      Value(text: j['text'] ?? '', quote: j['quote'] ?? '', added: j['added'] ?? '');
}

class Picture {
  Picture({required this.title, this.wish = '', this.outcome = '', this.obstacle = '', this.plan = '', this.quote = '',
      this.added = '', this.lastAction = ''});
  String title, wish, outcome, obstacle, plan, quote, added, lastAction;

  Map<String, dynamic> toJson() => {'title': title, 'wish': wish, 'outcome': outcome, 'obstacle': obstacle,
        'plan': plan, 'quote': quote, 'added': added, 'last_action': lastAction};
  factory Picture.fromJson(Map<String, dynamic> j) => Picture(title: j['title'] ?? '', wish: j['wish'] ?? '',
      outcome: j['outcome'] ?? '', obstacle: j['obstacle'] ?? '', plan: j['plan'] ?? '', quote: j['quote'] ?? '',
      added: j['added'] ?? '', lastAction: j['last_action'] ?? '');
}

/// One item from a note, and whether it was added (only items whose quote the person really said are).
class PlanItemLog {
  const PlanItemLog(this.heading, this.kind, this.item, this.quote, this.added, this.why, {this.text = ''});
  final String heading, kind, item, quote, why;
  final bool added;
  final String text; // what to show the person: the step for a plan step, otherwise the item
}

class Plans {
  Plans({List<Step>? steps, List<Habit>? habits, List<Goal>? goals, List<Value>? values, List<Picture>? pictures})
      : steps = steps ?? [],
        habits = habits ?? [],
        goals = goals ?? [],
        values = values ?? [],
        pictures = pictures ?? [];
  final List<Step> steps;
  final List<Habit> habits;
  final List<Goal> goals;
  final List<Value> values;
  final List<Picture> pictures;

  Map<String, dynamic> toJson() => {
        'steps': [for (final x in steps) x.toJson()], 'habits': [for (final x in habits) x.toJson()],
        'goals': [for (final x in goals) x.toJson()], 'values': [for (final x in values) x.toJson()],
        'pictures': [for (final x in pictures) x.toJson()],
      };
  factory Plans.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String k) => [for (final x in (j[k] as List? ?? [])) Map<String, dynamic>.from(x)];
    return Plans(steps: l('steps').map(Step.fromJson).toList(), habits: l('habits').map(Habit.fromJson).toList(),
        goals: l('goals').map(Goal.fromJson).toList(), values: l('values').map(Value.fromJson).toList(),
        pictures: l('pictures').map(Picture.fromJson).toList());
  }

  // ---- what the model is shown ----
  String asText(DateTime today) {
    final t = isoDate(today);
    String step(Step s, bool withDay) {
      final when = [if (withDay && s.day.isNotEmpty) dayLabel(dayOf(s.day)), if (s.time.isNotEmpty) s.time].join(' ');
      var out = (when.isNotEmpty ? '$when ' : '') + s.text;
      if (s.ifthen.isNotEmpty) out += ' (${s.ifthen})';
      if (s.status == 'done') out += ', done';
      if (s.moves > 0) out += ', moved ${s.moves} time${s.moves > 1 ? 's' : ''}';
      return out;
    }

    int byTime(Step a, Step b) {
      final c = (a.time.isEmpty ? '99:99' : a.time).compareTo(b.time.isEmpty ? '99:99' : b.time);
      return c != 0 ? c : a.text.compareTo(b.text);
    }

    final todaySteps = steps.where((s) => s.day == t && s.status != 'dropped').toList()..sort(byTime);
    final coming = steps.where((s) => s.day.compareTo(t) > 0 && s.status == 'open').toList()
      ..sort((a, b) => a.day != b.day ? a.day.compareTo(b.day) : byTime(a, b));
    final missed = steps.where((s) => s.day.isNotEmpty && s.day.compareTo(t) < 0 && s.status == 'open').toList();
    _stableSort(missed, (a, b) => a.day.compareTo(b.day));
    final anytime = steps.where((s) => s.day.isEmpty && s.status == 'open').toList();
    final weekAgo = isoDate(_minus(today, 7));
    final doneRecent = steps.where((s) => s.day.isNotEmpty && s.day.compareTo(weekAgo) >= 0 && s.day.compareTo(t) < 0 &&
        s.status == 'done').toList();
    _stableSort(doneRecent, (a, b) => a.day.compareTo(b.day));

    String habit(Habit h) {
      final days = [for (var k = 7; k >= 1; k--) isoDate(_minus(today, k))];
      final marks = [for (final d in days) h.kept.contains(d) ? 'yes' : h.missed.contains(d) ? 'no' : '-'];
      final nKept = marks.where((m) => m == 'yes').length, nKnown = marks.where((m) => m != '-').length;
      final extra = [if (h.cue.isNotEmpty) cueText(h.cue), if (h.tiny.isNotEmpty) 'tiny version: ${h.tiny}'].join('; ');
      var out = h.text + (extra.isNotEmpty ? ' ($extra)' : '');
      out += nKnown > 0 ? ': kept $nKept of $nKnown days in the last week' : ': new';
      return out + (nKnown > 0 ? ' (${marks.join(', ')})' : '');
    }

    String goal(Goal g) => g.text + (g.nextStep.isNotEmpty ? ', next step: ${g.nextStep}' : '') +
        (g.lastProgress.isNotEmpty ? ', last progress ${dayLabel(dayOf(g.lastProgress))}' : '');
    String picture(Picture p) => p.title + (p.plan.isNotEmpty ? ' (plan: ${p.plan})' : '');

    final rows = <(String, List<String>, bool)>[
      ("Today's plan", [for (final s in todaySteps) step(s, false)], true),
      ('Done in the last 7 days', [for (final s in doneRecent.skip(doneRecent.length > 5 ? doneRecent.length - 5 : 0)) step(s, true)], false),
      ('Coming up', [for (final s in coming.take(4)) step(s, true)], false),
      ('Missed and not re-planned', [for (final s in missed.skip(missed.length > 3 ? missed.length - 3 : 0)) step(s, true)], false),
      ('This week, no day set', [for (final s in anytime.take(3)) step(s, false)], false),
      ('Habits', [for (final h in habits) habit(h)], true),
      ('Goals', [for (final g in goals) goal(g)], true),
      ('Values', [for (final v in values) v.text], true),
      ('Vision board', [for (final p in pictures) picture(p)], true),
      ('Noticed by the app', noticed(today), true),
    ];
    return 'Plans kept by the app (the person can change them):\n${[
      for (final (name, items, always) in rows)
        if (items.isNotEmpty || always) '$name: ${items.isEmpty ? 'none' : items.join('; ')}'
    ].join('\n')}';
  }

  // ---- fixed rules, in priority order ----
  List<String> noticed(DateTime today) {
    final out = <String>[];
    for (final s in steps) {
      if (s.status == 'open' && s.moves >= 3) out.add('"${s.text}" has been moved ${s.moves} times');
    }
    for (final h in habits) {
      var fired = false;
      for (var wd = 0; wd < 7; wd++) {
        final lastTwo = [for (var k = 1; k < 15; k++) _minus(today, k)].where((d) => d.weekday - 1 == wd);
        if (lastTwo.every((d) => h.missed.contains(isoDate(d)))) {
          out.add('${h.text} was missed on the last two ${weekdays[wd]}s');
          fired = true;
          break;
        }
      }
      if (!fired && h.missed.contains(isoDate(_minus(today, 1)))) out.add('${h.text} was missed yesterday');
    }
    for (final g in goals) {
      if (g.lastProgress.isNotEmpty && _daysBetween(dayOf(g.lastProgress), today) >= 14) {
        out.add('goal "${g.text}": no progress in ${_daysBetween(dayOf(g.lastProgress), today)} days');
      }
    }
    for (final h in habits) {
      final n = [for (var k = 1; k < 15; k++) isoDate(_minus(today, k))].where(h.kept.contains).length;
      if (h.start.isNotEmpty && _daysBetween(dayOf(h.start), today) >= 14 && n >= 12) {
        out.add('${h.text} was kept on $n of the last 14 days');
      }
    }
    for (final p in pictures) {
      final ref = p.lastAction.isNotEmpty ? p.lastAction : p.added;
      if (ref.isNotEmpty && _daysBetween(dayOf(ref), today) >= 30) {
        out.add('vision board "${p.title}": nothing done in ${_daysBetween(dayOf(ref), today)} days');
      }
    }
    return out.take(maxNoticed).toList();
  }

  // ---- built from the note ----
  List<PlanItemLog> applyNote(Map<String, String> sections, DateTime today, String personText) {
    final log = <PlanItemLog>[];
    for (final heading in planHeadings) {
      for (final row in parseItems(sections[heading] ?? '')) {
        final kind = row['kind']!, item = row['item']!, quote = row['they said'] ?? '';
        final hasItem = item.isNotEmpty && (kind != 'when' || (row['step'] ?? '').isNotEmpty);
        final ok = hasItem && grounded(quote, personText);
        log.add(PlanItemLog(heading, kind, item, quote, ok,
            ok ? '' : (!hasItem ? 'no item' : 'quote not found in what they said'),
            text: kind == 'when' ? (row['step'] ?? '') : item));
        if (!ok) continue;
        final iso = isoDate(today);
        switch (kind) {
          case 'when':
            final (day, time) = parseWhen(item, today);
            final text = row['step'] ?? '';
            final again = steps.where((x) => x.status == 'open' && norm(x.text) == norm(text)).firstOrNull;
            if (again == null) {
              steps.add(Step(text: text, day: day, time: time, ifthen: row['if-then'] ?? '', quote: quote, added: iso));
            } else {
              again
                ..day = day
                ..time = time
                ..moves += 1
                ..ifthen = row['if-then'] ?? again.ifthen;
            }
          case 'habit':
            final h = habits.where((x) => norm(x.text) == norm(item)).firstOrNull;
            if (h == null) {
              habits.add(Habit(text: item, cue: row['cue'] ?? '', tiny: row['tiny version'] ?? '', quote: quote, start: iso));
            } else {
              h
                ..cue = row['cue'] ?? h.cue
                ..tiny = row['tiny version'] ?? h.tiny;
            }
          case 'goal':
            final g = goals.where((x) => norm(x.text) == norm(item)).firstOrNull;
            final next = row['next step'] ?? '';
            if (g == null) {
              goals.add(Goal(text: item, nextStep: next, quote: quote, added: iso, lastProgress: iso));
            } else if (next.isNotEmpty && norm(next) != norm(g.nextStep)) {
              g
                ..nextStep = next
                ..lastProgress = iso;
            }
          case 'value':
            if (!values.any((v) => norm(v.text) == norm(item))) values.add(Value(text: item, quote: quote, added: iso));
          case 'picture':
            final p = pictures.where((x) => norm(x.title) == norm(item)).firstOrNull;
            final f = {for (final k in ['wish', 'outcome', 'obstacle', 'plan']) k: row[k] ?? ''};
            if (p == null) {
              pictures.add(Picture(title: item, quote: quote, added: iso, wish: f['wish']!, outcome: f['outcome']!,
                  obstacle: f['obstacle']!, plan: f['plan']!));
            } else {
              if (f['wish']!.isNotEmpty) p.wish = f['wish']!;
              if (f['outcome']!.isNotEmpty) p.outcome = f['outcome']!;
              if (f['obstacle']!.isNotEmpty) p.obstacle = f['obstacle']!;
              if (f['plan']!.isNotEmpty) p.plan = f['plan']!;
            }
        }
      }
    }
    return log;
  }
}

/// List.sort is not guaranteed stable; Python's sorted is, and the order of equal days must match it.
void _stableSort<T>(List<T> list, int Function(T, T) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

/// 'kind: item | key: value | they said: "words"' lines -> maps; 'none' and other lines are skipped.
List<Map<String, String>> parseItems(String text) {
  final head = RegExp(r'^(when|habit|goal|value|picture)\s*:\s*(.*)$', caseSensitive: false, dotAll: true);
  final out = <Map<String, String>>[];
  for (final raw in text.split('\n')) {
    final parts = _stripChars(raw.trim(), '-*• ', right: false).split('|').map((p) => p.trim()).toList();
    final m = head.firstMatch(parts.first);
    if (m == null) continue;
    final row = {'kind': m.group(1)!.toLowerCase(), 'item': _stripChars(m.group(2)!.trim(), '"').trim()};
    for (final p in parts.skip(1)) {
      final i = p.indexOf(':');
      if (i < 0) continue;
      final k = p.substring(0, i).trim(), v = p.substring(i + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) row[k.toLowerCase()] = v;
    }
    if (row.containsKey('they said')) row['they said'] = _stripChars(row['they said']!.trim(), '"“”').trim();
    out.add(row);
  }
  return out;
}

/// 'today 10:00', 'tomorrow', 'Wednesday 18:30', 'this week' -> (ISO day or '', 'HH:MM' or '').
(String, String) parseWhen(String text, DateTime today) {
  final low = text.toLowerCase();
  final m = RegExp(r'\b(\d{1,2})[:.h](\d{2})\b').firstMatch(low);
  var time = '';
  if (m != null && int.parse(m.group(1)!) < 24 && int.parse(m.group(2)!) < 60) {
    time = '${int.parse(m.group(1)!).toString().padLeft(2, '0')}:${m.group(2)}';
  }
  if (low.contains('today') || low.contains('tonight')) return (isoDate(today), time);
  if (low.contains('tomorrow')) return (isoDate(_minus(today, -1)), time);
  for (var i = 0; i < 7; i++) {
    if (low.contains(weekdays[i].toLowerCase())) {
      var ahead = (i - (today.weekday - 1)) % 7;
      if (ahead == 0) ahead = 7;
      return (isoDate(_minus(today, -ahead)), time);
    }
  }
  return ('', time);
}
