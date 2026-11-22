// The insight loop's arithmetic and files (core/emotions.dart, insights.dart, review.dart, exports.dart,
// clinician_pdf.dart): a pattern appears only above its minimum, the words stay tentative, the named feelings survive
// the saved file (and older files without them still open), the review counts in code and the model's numbers never
// reach the screen, and the exports hold only what the person ticked.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/clinician_pdf.dart';
import 'package:solace/core/dates.dart';
import 'package:solace/core/emotions.dart';
import 'package:solace/core/exports.dart';
import 'package:solace/core/insights.dart';
import 'package:solace/core/plans.dart';
import 'package:solace/core/questionnaires.dart';
import 'package:solace/core/review.dart';
import 'package:solace/core/store.dart';

final now = DateTime(2026, 11, 26, 19, 30); // a Thursday evening

String daysAgo(int n) => isoDate(DateTime(now.year, now.month, now.day - n));

EmotionEntry feeling(String date, {String time = '20:00', String q = 'low_pleasant', List<String> words = const ['calm'],
        List<String> tags = const [], String note = ''}) =>
    EmotionEntry(at: '${date}T$time', quadrant: q, words: words, tags: tags, note: note);

void main() {
  group('the emotion words', () {
    test('about 100 to 150 words, each in one part of the grid only, and every tag named', () {
      final all = [for (final w in emotionWords.values) ...w];
      expect(all.length, inInclusiveRange(100, 150));
      expect(all.toSet().length, all.length, reason: 'a word in two parts of the grid');
      expect(emotionWords.keys.toSet(), quadrantIds);
      for (final words in emotionWords.values) {
        expect(words.length, greaterThanOrEqualTo(25));
      }
      expect(affectingTags.map((t) => t.$1).toSet(), tagIds);
      expect(all.where((w) => w.contains(RegExp('[A-Z]'))), isEmpty);
    });
  });

  group('saving named feelings', () {
    test('a check-in comes back exactly from the saved file', () {
      final d = AppData(moods: {'2026-11-26': 6}, moodTimes: {'2026-11-26': '19:30'}, emotions: [
        feeling('2026-11-26', time: '19:30', q: 'high_pleasant', words: ['hopeful', 'chuffed'], tags: ['work', 'sleep'],
            note: 'Café after the review, naïve résumé “done”'),
      ]);
      final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
      final e = back.emotions.single;
      expect((e.date, e.hour, e.quadrant), ('2026-11-26', 19, 'high_pleasant'));
      expect(e.words, ['hopeful', 'chuffed']);
      expect(e.tags, ['work', 'sleep']);
      expect(back.moodTimes, {'2026-11-26': '19:30'});
    });

    test('a file saved before named feelings existed still opens, with none', () {
      final old = AppData(moods: {'2026-11-01': 5}).toJson()
        ..remove('emotions')
        ..remove('mood_times');
      final back = AppData.fromJson(jsonDecode(jsonEncode(old)));
      expect(back.emotions, isEmpty);
      expect(back.moodTimes, isEmpty);
      expect(back.moods, {'2026-11-01': 5});
    });

    test('a damaged entry is left out instead of stopping the app from opening', () {
      final j = AppData().toJson()
        ..['emotions'] = [
          {'at': '2026-11-26T19:30', 'quadrant': 'low_pleasant', 'words': ['calm'], 'tags': ['sleep', 'aliens'],
            'note': 'x' * (maxNoteLength + 400)},
          {'at': '2026-11-26', 'quadrant': 'low_pleasant', 'words': ['calm']}, // no time
          {'at': '2026-11-26T19:30', 'quadrant': 'red', 'words': ['calm']}, // not a part of the grid
          {'at': '2026-11-26T19:30', 'quadrant': 'low_pleasant', 'words': []}, // no word
          {'at': '2026-13-40T99:99', 'quadrant': 'low_pleasant', 'words': ['calm']}, // not a date
          'not even a map',
          {'at': '2026-11-25T08:00', 'quadrant': 'high_unpleasant', 'words': [' tense ', 'tense', 3]},
        ]
        ..['mood_times'] = {'2026-11-26': '19:30', '2026-11-25': 'teatime', '2026-11-24': '25:00'};
      final back = AppData.fromJson(jsonDecode(jsonEncode(j)));
      expect(back.emotions.length, 2);
      expect(back.emotions.first.tags, ['sleep'], reason: 'an unknown tag is dropped');
      expect(back.emotions.first.note.length, maxNoteLength);
      expect(back.emotions.last.words, ['tense']);
      expect(back.moodTimes, {'2026-11-26': '19:30'});
      expect(AppData.fromJson(jsonDecode(jsonEncode(AppData().toJson()..['emotions'] = 'oops'))).emotions, isEmpty);
    });
  });

  group('patterns worth noticing', () {
    test('a weekday that differs by a point or more is noticed, in tentative words', () {
      final d = AppData();
      for (var i = 0; i < 28; i++) {
        final day = DateTime(now.year, now.month, now.day - i);
        d.moods[isoDate(day)] = day.weekday == DateTime.sunday ? 8 : 5;
      }
      final r = computeInsights(d, now);
      final weekday = r.patterns.where((p) => p.kind == 'weekday').toList();
      expect(weekday.length, 1, reason: 'the other days differ from the rest by half a point only');
      expect(weekday.single.text, 'On Sundays your mood was 3.0 points higher than on other days, on average. '
          'Worth noticing, not a verdict.');
      expect(weekday.single.detail, 'From 4 Sundays and 24 other days you rated in the last 90 days.');
      expect(r.byWeekday[7]!.mean, 8);
    });

    test('below the minimum nothing is guessed: the screen says what is still needed', () {
      final d = AppData();
      for (var i = 0; i < minRatings - 1; i++) {
        d.moods[daysAgo(i)] = i.isEven ? 2 : 9;
      }
      final r = computeInsights(d, now);
      expect(r.patterns, isEmpty);
      expect(r.waiting.first, 'Mood by weekday: shown after 8 mood ratings in the last 90 days (you have 7).');
    });

    test('a difference under a point is steady, said plainly and not shown as a pattern', () {
      final d = AppData();
      for (var i = 0; i < 28; i++) {
        final day = DateTime(now.year, now.month, now.day - i);
        d.moods[isoDate(day)] = day.weekday == DateTime.sunday && day.day.isEven ? 6 : 5; // Sundays half a point up
      }
      final r = computeInsights(d, now);
      expect(r.patterns.where((p) => p.kind == 'weekday'), isEmpty);
      expect(r.steady, contains(startsWith('Your mood looks much the same across the week')));
    });

    test('enough ratings but no weekday with three of them: still gathering, never called steady', () {
      final d = AppData();
      for (var i = 0; i < 26; i += 2) {
        d.moods[daysAgo(i)] = i % 4 == 0 ? 2 : 9; // every other day: each weekday twice at most
      }
      final r = computeInsights(d, now);
      expect(r.patterns.where((p) => p.kind == 'weekday'), isEmpty);
      expect(r.steady, isEmpty);
      expect(r.waiting, contains(startsWith('Mood by weekday: shown once one weekday has 3 ratings')));
    });

    test('ratings older than 90 days are left out', () {
      final d = AppData();
      for (var i = 100; i < 140; i++) {
        d.moods[daysAgo(i)] = 5;
      }
      expect(computeInsights(d, now).ratings, 0);
    });

    test('a tag is compared among the days a feeling was named; a day without a check-in never counts as "without"', () {
      final d = AppData();
      for (var i = 0; i < 10; i++) {
        d.moods[daysAgo(i)] = i < 4 ? 3 : 6;
        d.emotions.add(feeling(daysAgo(i), tags: i < 4 ? ['sleep', 'work'] : ['work']));
      }
      for (var i = 10; i < 30; i++) {
        d.moods[daysAgo(i)] = 1; // rated, but no feeling named: not part of the comparison
      }
      final tags = computeInsights(d, now).patterns.where((p) => p.kind == 'tag').toList();
      expect(tags.length, 1, reason: 'work is on every day, so it has no "without" side');
      expect(tags.single.text, 'On days you tagged “sleep”, your mood was 3.0 points lower on average. '
          'Worth noticing, not a verdict.');
      expect(tags.single.detail, 'From 4 days with that tag and 6 other days you named a feeling.');
    });

    test('tags always used together are one pattern, and the mirror of a shown pattern is not shown again', () {
      final d = AppData();
      for (var i = 0; i < 10; i++) {
        d.moods[daysAgo(i)] = i < 4 ? 3 : 6;
        d.emotions.add(feeling(daysAgo(i), tags: i < 4 ? ['sleep', 'work'] : ['friends']));
      }
      final tags = computeInsights(d, now).patterns.where((p) => p.kind == 'tag').toList();
      expect(tags.single.text, 'On days you tagged “work” and “sleep”, your mood was 3.0 points lower on average. '
          'Worth noticing, not a verdict.');
      expect(tags.single.detail, 'From 4 days with those tags, always together, and 6 other days you named a feeling.');
    });

    test('a tag on only two days is not enough for a pattern', () {
      final d = AppData();
      for (var i = 0; i < 10; i++) {
        d.moods[daysAgo(i)] = i < 2 ? 1 : 8;
        d.emotions.add(feeling(daysAgo(i), tags: i < 2 ? ['money'] : []));
      }
      expect(computeInsights(d, now).patterns.where((p) => p.kind == 'tag'), isEmpty);
    });

    test('the time of day comes from when the mood was tapped', () {
      final d = AppData();
      for (var i = 0; i < 12; i++) {
        d.moods[daysAgo(i)] = i.isEven ? 3 : 7;
        d.moodTimes[daysAgo(i)] = i.isEven ? '08:15' : '20:40';
      }
      final r = computeInsights(d, now);
      final times = r.patterns.where((p) => p.kind == 'time_of_day').map((p) => p.text).toList();
      expect(times, [
        'When you rated your mood in the evening, it was 4.0 points higher than at other times, on average. '
            'Worth noticing, not a verdict.',
        'When you rated your mood in the morning, it was 4.0 points lower than at other times, on average. '
            'Worth noticing, not a verdict.',
      ]);
      expect(r.byPartOfDay['morning']!.n, 6);
      expect(partOfDay(4), 'night');
      expect(partOfDay(5), 'morning');
      expect(partOfDay(12), 'afternoon');
      expect(partOfDay(17), 'evening');
      expect(partOfDay(22), 'night');
    });

    test('mood before and after a programme: the four weeks before against the days since', () {
      final d = AppData(programmes: [Programme('courage ladder', daysAgo(10))]);
      for (var i = 0; i <= 9; i++) {
        d.moods[daysAgo(i)] = 6;
      }
      for (var i = 11; i <= 20; i++) {
        d.moods[daysAgo(i)] = 4;
      }
      d.moods[daysAgo(40)] = 0; // more than four weeks before: left out
      final p = computeInsights(d, now).patterns.firstWhere((p) => p.kind == 'programme');
      expect(p.text, 'Since you started Courage ladder on 16 November, your mood has been 2.0 points higher on '
          'average than in the four weeks before. Many things change at once, so this is worth noticing, not proof.');
      expect(p.detail, 'From 10 rated days before and 10 since.');
    });

    test('questionnaire trends carry their bands; one answer asks for a second', () {
      final d = AppData(scores: [
        {'date': '2026-11-16', 'name': 'PHQ-9', 'total': 10, 'items': []},
        {'date': '2026-11-02', 'name': 'PHQ-9', 'total': 14, 'items': []},
        {'date': '2026-11-02', 'name': 'GAD-7', 'total': 12, 'items': []},
      ]);
      final r = computeInsights(d, now);
      expect(r.questionnaires.map((q) => q.text), [
        'Your PHQ-9 went from 14 (moderate) on 2 November to 10 (moderate) on 16 November.',
        'One GAD-7 so far: 12 (moderate) on 2 November.',
      ]);
    });

    test('the feelings named most, once there are five check-ins', () {
      final d = AppData();
      for (var i = 0; i < 4; i++) {
        d.emotions.add(feeling(daysAgo(i), words: ['tired', if (i < 2) 'hopeful']));
      }
      expect(computeInsights(d, now).topWords, isEmpty);
      d.emotions.add(feeling(daysAgo(5), words: ['calm']));
      expect(computeInsights(d, now).topWords, [('tired', 4), ('hopeful', 2), ('calm', 1)]);
    });

    test('every day with a check-in, practice or session counts as showing up', () {
      final d = AppData(moods: {'2026-11-01': 5}, emotions: [feeling('2026-11-02')],
          sessions: [SessionRecord(date: '2026-11-03', kind: 'daily_checkin', turns: const [], note: '')],
          scores: [{'date': '2026-11-04', 'name': 'PHQ-9', 'total': 3}],
          plans: Plans(habits: [Habit(text: 'walk', kept: ['2026-11-05'], missed: ['2026-11-06'])],
              steps: [Step(text: 'email', day: '2026-11-07', status: 'done'), Step(text: 'call', day: '2026-11-08')]));
      expect(showedUpDates(d), {'2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-07'});
    });
  });

  group('the weekly review, the monthly letter and the year in review', () {
    test('periods: the last seven days, this month so far, this year so far, and the ones before', () {
      final week = periodFor(ReviewSpan.week, now);
      expect((isoDate(week.from), isoDate(week.to)), ('2026-11-20', '2026-11-26'));
      final lastWeek = periodFor(ReviewSpan.week, now, back: 1);
      expect((isoDate(lastWeek.from), isoDate(lastWeek.to)), ('2026-11-13', '2026-11-19'));
      final month = periodFor(ReviewSpan.month, now, back: 11);
      expect((isoDate(month.from), isoDate(month.to)), ('2025-12-01', '2025-12-31'));
      final year = periodFor(ReviewSpan.year, now);
      expect((isoDate(year.from), isoDate(year.to)), ('2026-01-01', '2026-11-26'));
      expect(daysIn(DateTime(2026, 3, 1), DateTime(2026, 3, 31)), 31, reason: 'a clock change loses no day');
    });

    test('the summary is counted in code, with the week before for comparison', () {
      final d = AppData(
        moods: {'2026-11-26': 7, '2026-11-24': 4, '2026-11-21': 5, '2026-11-15': 3, '2026-11-14': 2, '2026-11-13': 4},
        emotions: [
          feeling('2026-11-26', words: ['hopeful', 'tired'], tags: ['work']),
          feeling('2026-11-24', words: ['tired'], tags: ['work', 'sleep']),
        ],
        sessions: [SessionRecord(date: '2026-11-23', kind: 'weekly_session', turns: const [], note: ''),
            SessionRecord(date: '2026-11-25', kind: 'practice', turns: const [], note: '')],
        scores: [{'date': '2026-11-02', 'name': 'PHQ-9', 'total': 14}, {'date': '2026-11-23', 'name': 'PHQ-9', 'total': 9}],
        plans: Plans(steps: [Step(text: 'email', day: '2026-11-25', status: 'done')],
            habits: [Habit(text: 'walk', kept: ['2026-11-22', '2026-11-25', '2026-11-01'])]),
        programmes: [Programme('courage ladder', '2026-11-10', sessions: 9)],
      );
      final s = buildReview(d, ReviewSpan.week, now);
      expect(s.range, 'Friday 20 November to Thursday 26 November');
      expect(s.facts.map((f) => f.text), [
        'Mood: rated on 3 of 7 days, 5.3 out of 10 on average (from 4 to 7). The week before: 3.0 on average.',
        'Feelings named: 2 times; most often tired and hopeful.',
        'What was affecting you most: work and sleep.',
        'Sessions with Solace: 1. Practice sessions: 1.',
        'Plan steps done: 1. Habits kept on 2 days.',
        'Courage ladder: day 17, 9 sessions done in all.',
        'PHQ-9: 9 (mild) on 23 November; before that 14 (moderate) on 2 November.',
      ]);
      expect(s.isEmpty, isFalse);
      expect(buildReview(AppData(), ReviewSpan.month, now).isEmpty, isTrue);
      expect(buildReview(d, ReviewSpan.year, now).moodByMonth[11]!.n, 6);
    });

    test('the model is given the numbers and asked to write none; its sentences with digits are left out', () {
      final s = buildReview(AppData(moods: {'2026-11-26': 7}), ReviewSpan.week, now);
      final template = File('assets/prompts/app_review_v1.txt').readAsStringSync();
      final messages = reviewMessages(template, s);
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], startsWith('You are Solace'));
      expect(messages.last['content'], contains('- Mood: rated on 1 of 7 days, 7.0 out of 10 on average.'));
      expect(messages.last['content'], contains('write no numbers'));
      expect(messages.last['content'], isNot(contains('{')));
      expect(cleanReflection('This week held some brighter moments.  You rated 7 days! It sounds like work weighed '
          'on you, and you kept going anyway.'), 'This week held some brighter moments. It sounds like work weighed on '
          'you, and you kept going anyway.');
      expect(cleanReflection('Your average was 5.3.'), '');
    });
  });

  group('exports', () {
    AppData sample() => AppData(
          moods: {'2026-11-26': 6, '2026-11-25': 4},
          moodTimes: {'2026-11-26': '19:30'},
          emotions: [
            feeling('2026-11-25', time: '08:10', q: 'high_unpleasant', words: ['tense'], tags: ['work'],
                note: '=HYPERLINK("x") said, "fine"'),
            feeling('2026-11-26', time: '19:30', words: ['calm'], note: 'Private, not ticked'),
          ],
          scores: [{'date': '2026-11-16', 'name': 'PHQ-9', 'total': 10, 'items': [0, 1, 1, 2, 1, 1, 1, 0, 0]}],
          journal: [{'date': '2026-11-20', 'text': 'Walked by the canal | felt lighter'}],
          programmes: [Programme('courage ladder', '2026-11-10', sessions: 9)],
        );

    test('a CSV cell can never run as a formula, and commas, quotes and line breaks are quoted', () {
      expect(csvCell('=SUM(A1)'), "'=SUM(A1)");
      expect(csvCell('+1'), "'+1");
      expect(csvCell('@me'), "'@me");
      expect(csvCell('a, "b"\nc'), '"a, ""b""\nc"');
      expect(csvCell(7), '7');
      expect(csvCell(null), '');
    });

    test('the CSV holds moods, feelings and scores, and only the ticked notes', () {
      final d = sample();
      final ticked = exportNotes(d).where((n) => n.text.startsWith('=') || n.source == 'Journal').map((n) => n.id).toSet();
      final csv = exportCsv(d, notes: ticked);
      final lines = csv.substring(1).trimRight().split('\r\n');
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(lines.first, 'date,time,record,name,value,band,words,affecting,note');
      expect(lines, contains('2026-11-26,19:30,mood,Mood (0 to 10),6,,,,'));
      expect(lines, contains('2026-11-16,,questionnaire,PHQ-9,10,moderate,,,'));
      expect(lines, contains('2026-11-25,08:10,feelings,"High energy, unpleasant",,,tense,Work,'
          '"\'=HYPERLINK(""x"") said, ""fine"""'));
      expect(lines, contains('2026-11-20,,note,Journal,,,,,Walked by the canal | felt lighter'));
      expect(csv, isNot(contains('Private, not ticked')));
      expect(exportCsv(d), isNot(contains('HYPERLINK')), reason: 'no note unless ticked');
    });

    test('the Markdown page holds the same, newest first, ticked notes only', () {
      final d = sample();
      final journal = exportNotes(d).firstWhere((n) => n.source == 'Journal').id;
      final md = exportMarkdown(d, now, notes: {journal});
      expect(md, startsWith('# My records from Solace'));
      expect(md, contains("outside Solace's encryption"));
      expect(md, contains('| Thursday 26 November 2026 | 19:30 | 6 |'));
      expect(md.indexOf('Thursday 26 November 2026 | 19:30'), lessThan(md.indexOf('Wednesday 25 November 2026 |')));
      expect(md, contains('| Monday 16 November 2026 | PHQ-9 | 10 of 27 | moderate |'));
      expect(md, contains('- **Wednesday 25 November 2026, 08:10**: high energy, unpleasant; tense. Affecting: work.'));
      expect(md, contains('  > Walked by the canal | felt lighter'));
      expect(md, isNot(contains('Private, not ticked')));
      expect(md, isNot(contains('HYPERLINK')));
    });

    test('the clinician PDF is a real PDF, with the bundled font and without it', () async {
      final d = sample();
      final regular = ByteData.sublistView(File('assets/fonts/Figtree-Regular.ttf').readAsBytesSync());
      final bold = ByteData.sublistView(File('assets/fonts/Figtree-Bold.ttf').readAsBytesSync());
      final pdf = await clinicianPdf(d, now, notes: exportNotes(d).map((n) => n.id).toSet(), regular: regular, bold: bold);
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(latin1.decode(pdf.sublist(pdf.length - 8)), contains('%%EOF'));
      expect(latin1.decode(pdf), contains('FontFile2'), reason: 'Figtree embedded');
      final plain = await clinicianPdf(AppData(), now);
      expect(ascii.decode(plain.sublist(0, 5)), '%PDF-');
      expect(pdfText('calm 🙂 ok ✨'), 'calm  ok ');
      expect(bandKey(phq9), '0 to 4 minimal, 5 to 9 mild, 10 to 14 moderate, 15 to 19 moderately severe, '
          '20 to 27 severe');
    });

    test('programme progress reads as on the Progress tab', () {
      expect(programmeLines(sample().programmes.single, now), ['Started Tuesday 10 November 2026; day 17, 9 sessions done']);
    });
  });
}
