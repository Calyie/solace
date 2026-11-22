// Search through older sessions and the journal (core/search.dart, TASKLIST B7): longer forms, accents, phrases,
// the highlighted words, and which session or journal entry each hit opens.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/search.dart';
import 'package:solace/core/store.dart';

AppData sample() => AppData(sessions: [
      SessionRecord(date: '2026-10-01', kind: 'weekly_session', note: 'Talked about: drinking less at weekends',
          turns: [('therapist', 'How has the drinking been this week?'), ('person', 'I had one drink at the Café with Marc.')]),
      SessionRecord(date: '2026-11-20', kind: 'daily_checkin', note: '',
          turns: [('therapist', 'How are you?'), ('person', 'I went for a walk by the canal after work.')]),
    ], journal: [
      {'date': '2026-11-21', 'text': 'Felt calm after the walk, slept better.'},
    ]);

final today = DateTime(2026, 11, 26);

void main() {
  test('a word finds its longer forms, and the hit opens the right session', () {
    final hits = searchMemory(sample(), 'drink', today: today);
    expect(hits.length, 1);
    expect(hits.single.source, 'weekly_session');
    expect(hits.single.index, 0);
  });

  test('accents do not matter, and the matched word is highlighted in the snippet', () {
    final hit = searchMemory(sample(), 'cafe', today: today).single;
    final (s, e) = hit.highlights.single;
    expect(hit.snippet.substring(s, e), 'Café');
  });

  test('words in quotes must appear together', () {
    expect(searchMemory(sample(), '"by the canal"', today: today).map((h) => h.index), [1]);
    expect(searchMemory(sample(), '"the canal by"', today: today), isEmpty);
  });

  test('a word in a session and in the journal finds both; a journal hit points into the journal', () {
    final hits = searchMemory(sample(), 'walk', today: today);
    expect({for (final h in hits) (h.source, h.index)}, {('daily_checkin', 1), ('journal', 0)});
  });

  test('short words match only whole words; an empty search finds nothing', () {
    expect(searchMemory(sample(), 'wa', today: today), isEmpty);
    expect(searchMemory(sample(), '   ', today: today), isEmpty);
    expect(searchMemory(AppData(), 'walk', today: today), isEmpty);
  });
}
