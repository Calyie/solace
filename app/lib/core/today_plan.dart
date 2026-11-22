// What Today proposes (PLAN 13, TASKLIST B3): proactive, never another list to keep. The steps due today (and the
// ones still open from before), in time order; the habits not yet marked today; never miss twice after a missed day
// (Lally et al. 2010: one missed day did not undo the habit, so the tiny version counts in full); and the gentle
// reminders for today's timed steps and the chosen session times, within a daily cap and outside quiet hours.
import 'dates.dart';
import 'plans.dart';
import 'store.dart';

/// Open steps for today, the ones left open from earlier days, and those with no day yet; timed ones first, by time.
List<Step> stepsForToday(Plans p, DateTime today) {
  final iso = isoDate(today);
  final due = [for (final s in p.steps) if (s.status == 'open' && (s.day.isEmpty || s.day.compareTo(iso) <= 0)) s];
  due.sort((a, b) {
    if (a.time.isEmpty != b.time.isEmpty) return a.time.isEmpty ? 1 : -1;
    return a.time.compareTo(b.time);
  });
  return due;
}

/// Habits with nothing marked for today yet.
List<Habit> habitsDue(Plans p, DateTime today) {
  final iso = isoDate(today);
  return [for (final h in p.habits) if (!h.kept.contains(iso) && !h.missed.contains(iso)) h];
}

/// The habit to rescue today: missed yesterday, nothing marked today, and a tiny version to offer.
Habit? neverMissTwice(Plans p, DateTime today) {
  final yesterday = isoDate(DateTime(today.year, today.month, today.day - 1)), iso = isoDate(today);
  for (final h in p.habits) {
    if (h.missed.contains(yesterday) && !h.kept.contains(iso) && !h.missed.contains(iso) && h.tiny.isNotEmpty) {
      return h;
    }
  }
  return null;
}

void markStep(Step s, String status) => s.status = status; // done or dropped

/// Not yet: the step moves to tomorrow and the move is counted (three moves is something the therapist notices).
void moveStep(Step s, DateTime today) {
  s.day = isoDate(DateTime(today.year, today.month, today.day + 1));
  s.moves++;
}

void markHabit(Habit h, DateTime today, {required bool kept}) {
  final iso = isoDate(today);
  h.kept.remove(iso);
  h.missed.remove(iso);
  (kept ? h.kept : h.missed).add(iso);
}

/// The habit's last [days] days, oldest first: true kept, false missed, null nothing marked (a gap, never a broken
/// streak).
List<bool?> habitDays(Habit h, DateTime today, {int days = 7}) => [
      for (var k = days - 1; k >= 0; k--)
        switch (isoDate(DateTime(today.year, today.month, today.day - k))) {
          final d when h.kept.contains(d) => true,
          final d when h.missed.contains(d) => false,
          _ => null,
        },
    ];

class Nudge {
  const Nudge(this.at, this.title, this.body, {this.repeat = Repeat.none});
  final DateTime at;
  final String title, body; // generic on the lock screen: the detail shows only after unlocking (PLAN 13)
  final Repeat repeat;
}

enum Repeat { none, daily, weekly }

const quietFrom = 22, quietTo = 8; // no step reminders from 22:00 to 08:00
const dailyCap = 3; // at most three step reminders a day

bool _quiet(DateTime t) => t.hour >= quietFrom || t.hour < quietTo;

DateTime? _at(DateTime day, String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  return m == null ? null : DateTime(day.year, day.month, day.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
}

/// Today's timed steps still ahead of [now], at most [dailyCap], none in quiet hours.
List<Nudge> stepNudges(Plans p, DateTime now) {
  final out = <Nudge>[];
  for (final s in stepsForToday(p, now)) {
    final at = s.day == isoDate(now) ? _at(now, s.time) : null;
    if (at == null || !at.isAfter(now) || _quiet(at)) continue;
    if (out.length < dailyCap) out.add(Nudge(at, 'A step is coming up', 'Open the app when you are ready.'));
  }
  return out;
}

/// The daily check-in and the weekly session at the times the person chose, each at its next time, repeating.
List<Nudge> sessionReminders(Settings s, DateTime now) {
  final out = <Nudge>[];
  final daily = _at(now, s.dailyReminder);
  if (daily != null) {
    out.add(Nudge(daily.isAfter(now) ? daily : daily.add(const Duration(days: 1)), 'Your check-in',
        'A few minutes, whenever suits you.', repeat: Repeat.daily));
  }
  final day = weekdays.indexWhere((w) => w.toLowerCase() == s.weeklyDay.toLowerCase());
  final weekly = _at(now, s.weeklyTime);
  if (day >= 0 && weekly != null) {
    var at = weekly.add(Duration(days: (day - (now.weekday - 1)) % 7));
    if (!at.isAfter(now)) at = at.add(const Duration(days: 7));
    out.add(Nudge(at, 'Your weekly session', 'Ready when you are.', repeat: Repeat.weekly));
  }
  return out;
}

/// Everything to schedule from [now], in time order.
List<Nudge> nudgesFor(AppData d, DateTime now) =>
    [...stepNudges(d.plans, now), ...sessionReminders(d.settings, now)]..sort((a, b) => a.at.compareTo(b.at));
