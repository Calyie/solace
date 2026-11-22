// What Today proposes (core/today_plan.dart, TASKLIST B3): due steps in time order, habits, never miss twice, moving a
// step, the habit's last days as gaps, and the reminders with their cap and quiet hours.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/plans.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/today_plan.dart';

final today = DateTime(2026, 11, 18, 8, 12); // a Wednesday morning

Plans plans() => Plans(steps: [
      Step(text: 'Ask Daniel for ten minutes', day: '2026-11-18', time: '10:00'),
      Step(text: 'Twenty-five minute start on Lavoie', day: '2026-11-18', time: '08:30'),
      Step(text: 'Book the dentist'), // no day yet
      Step(text: 'Call Sofia back', day: '2026-11-17', time: '18:00'), // left open yesterday
      Step(text: 'Plan the weekend', day: '2026-11-19'), // tomorrow
      Step(text: 'Already done', day: '2026-11-18', time: '09:00', status: 'done'),
    ], habits: [
      Habit(text: 'Phone across the room at night', tiny: 'face down on the shelf', missed: ['2026-11-17']),
      Habit(text: 'One doodle after dinner', tiny: 'one line', kept: ['2026-11-18']),
    ]);

void main() {
  test('due today: timed steps by time, then yesterday-left and undated; not tomorrow, not done', () {
    expect([for (final s in stepsForToday(plans(), today)) s.text], [
      'Twenty-five minute start on Lavoie', 'Ask Daniel for ten minutes', 'Call Sofia back', 'Book the dentist']);
  });

  test('habits due are the ones with nothing marked today; never miss twice offers the tiny version', () {
    final p = plans();
    expect([for (final h in habitsDue(p, today)) h.text], ['Phone across the room at night']);
    expect(neverMissTwice(p, today)?.tiny, 'face down on the shelf');
    markHabit(p.habits.first, today, kept: true);
    expect(neverMissTwice(p, today), isNull, reason: 'kept today: nothing to rescue');
  });

  test('not yet moves a step to tomorrow and counts the move', () {
    final s = Step(text: 'x', day: '2026-11-18');
    moveStep(s, today);
    expect((s.day, s.moves), ('2026-11-19', 1));
  });

  test("a habit's last days show gaps, never a broken streak", () {
    final h = Habit(text: 'x', kept: ['2026-11-16', '2026-11-18'], missed: ['2026-11-17']);
    expect(habitDays(h, today, days: 4), [null, true, false, true]);
  });

  test('reminders: steps still ahead today, at most three, none in quiet hours; the check-in and weekly times', () {
    final d = AppData(plans: Plans(steps: [
      for (final t in ['08:00', '08:30', '10:00', '12:00', '15:00', '23:00']) Step(text: 'step $t', day: '2026-11-18', time: t),
    ]))
      ..settings.dailyReminder = '19:00'
      ..settings.weeklyDay = 'Wednesday'
      ..settings.weeklyTime = '18:00';
    final n = nudgesFor(d, today);
    expect([for (final x in n) '${x.at.hour}:${x.at.minute.toString().padLeft(2, '0')} ${x.title}'], [
      '8:30 A step is coming up', '10:00 A step is coming up', '12:00 A step is coming up',
      '18:00 Your weekly session', '19:00 Your check-in']);
    expect(n.every((x) => !x.body.contains('step ')), isTrue, reason: 'the lock screen never shows what the step is');
  });
  test('session reminders point to their next time and repeat; none are kept back by quiet hours', () {
    final s = Settings()
      ..dailyReminder = '07:30' // already past at 08:12: tomorrow
      ..weeklyDay = 'Monday'
      ..weeklyTime = '18:00'; // Monday has passed this week: next Monday
    final r = sessionReminders(s, today);
    expect([for (final n in r) (n.title, n.at, n.repeat)], [
      ('Your check-in', DateTime(2026, 11, 19, 7, 30), Repeat.daily),
      ('Your weekly session', DateTime(2026, 11, 23, 18), Repeat.weekly),
    ]);
  });
}
