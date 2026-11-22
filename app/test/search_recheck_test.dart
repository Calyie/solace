// Round 9 review B, re-check. 9B-10: the search that runs after the typing pauses read every query word against the
// whole vocabulary and split every line of every hit, so a pasted paragraph held the interface thread for about a
// quarter of a second over a year of sessions. Now a query reads at most its first 200 characters, 12 distinct words
// and 4 phrases (core/search.dart maxQueryChars), the longer forms of a word are one range of the sorted vocabulary,
// and only the parts of a line that hold a query word are split. 9B-11: when the sessions change while Search is open
// (beneath another screen), the old hits go at once, and a hit never opens a session other than the one it found.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/search.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/memory_search.dart';

import 'audit_followups_test.dart' as a;
import 'review9b/search_long_query_test.dart' show addYear;

/// The best line of a hit as the search chose it before 9B-10 (every line split into words), for comparison.
String referenceBestLine(List<String> lines, List<String> words, List<String> phrases) {
  final word = RegExp(r"[a-z0-9]+(?:'[a-z]+)?");
  bool matches(String q, String w) => w == q || (q.length >= 3 && w.startsWith(q));
  var best = 0, bestCount = -1;
  for (var i = 0; i < lines.length; i++) {
    final folded = foldText(lines[i]);
    final lw = [for (final m in word.allMatches(folded)) m.group(0)!];
    final n = words.where((q) => lw.any((w) => matches(q, w))).length + phrases.where(folded.contains).length;
    if (n > bestCount) {
      best = i;
      bestCount = n;
    }
  }
  return lines[best];
}

void main() {
  group('9B-10: a long query is bounded, and its results still make sense', () {
    final today = DateTime(2026, 2, 1);
    AppData data() => AppData()
      ..sessions.addAll([
        SessionRecord(date: '2026-01-10', kind: 'daily_checkin', note: '',
            turns: [('person', 'We walked by the canal and talked about my sister.')]),
        SessionRecord(date: '2026-01-11', kind: 'daily_checkin', note: '',
            turns: [('person', 'The zebrafish tank at work needs cleaning.')]),
      ]);

    test('only the first 12 distinct words are read: a match after them finds nothing; the same word first finds it',
        () {
      final twelve = List.generate(12, (i) => 'filler${String.fromCharCode(97 + i)}').join(' ');
      expect(searchMemory(data(), '$twelve zebrafish', today: today), isEmpty);
      expect(queryIsCut('$twelve zebrafish'), isTrue);
      expect(searchMemory(data(), 'zebrafish $twelve', today: today).single.index, 1);
      expect(queryIsCut(twelve), isFalse, reason: 'twelve words are read whole');
    });

    test('only the first 200 characters are read', () {
      final long = '${'x' * 199} zebrafish';
      expect(searchMemory(data(), long, today: today), isEmpty);
      expect(queryIsCut(long), isTrue);
      expect(searchMemory(data(), 'zebrafish ${'x' * 199}', today: today).single.index, 1);
    });

    test('a pasted paragraph that holds the words still finds the right session, with its words in bold', () {
      const pasted = 'I keep thinking about my sister and the canal walk, and how it felt when we talked for hours and '
          'hours without stopping, and then I went home and could not sleep at all that night or the one after it.';
      final hits = searchMemory(data(), pasted, today: today);
      expect(hits.first.index, 0);
      expect(hits.first.highlights, isNotEmpty);
      expect(queryIsCut(pasted), isTrue);
    });

    test('the best line of each hit is the one splitting every line would choose', () {
      final d = AppData();
      const lines = [
        "I don't know why the café felt so loud today.",
        'Rock\'n\'roll night with my sister, the drinks and the drinking games.',
        'Nothing much: work, then "the canal by night", then sleep.',
        "She's walking again, walks every morning; I'd like to walk too.",
        'Numbers: 42 sleeps, 7 walks, 3 drinks.',
      ];
      for (var i = 0; i < 20; i++) {
        d.sessions.add(SessionRecord(date: '2026-01-${(i % 28 + 1).toString().padLeft(2, '0')}', kind: 'daily_checkin',
            note: lines[(i + 2) % lines.length], turns: [
          for (var j = 0; j < lines.length; j++) (j.isEven ? 'person' : 'therapist', lines[(i + j) % lines.length]),
        ]));
      }
      final index = SearchIndex.build(searchInputs(d));
      for (final (query, words, phrases) in [
        ('walk', ['walk'], <String>[]),
        ("don't cafe", ["don't", 'cafe'], <String>[]),
        ('roll drink', ['roll', 'drink'], <String>[]),
        ('"the canal" sister', ['the', 'canal', 'sister'], ['the canal']),
        ('42 7 walks', ['42', '7', 'walks'], <String>[]),
        ("she's i'd", ["she's", "i'd"], <String>[]),
      ]) {
        final hits = index.search(query, today: today);
        expect(hits, isNotEmpty, reason: query);
        for (final h in hits) {
          final s = d.sessions[h.index];
          final docLines = [for (final (_, x) in s.turns) x, ...s.note.split('\n').where((l) => l.trim().isNotEmpty)];
          expect(h.snippet, referenceBestLine(docLines, words, phrases), reason: query);
        }
      }
    });

    test('a pasted paragraph over a year of sessions takes a few milliseconds, not a quarter of a second', () {
      final d = AppData();
      addYear(d);
      final index = SearchIndex.build(searchInputs(d));
      final paragraph = List.generate(125, (i) => 'qq${String.fromCharCode(97 + i % 26)}').join(' ').substring(0, 499);
      var best = 1 << 30;
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        index.search(paragraph);
        best = sw.elapsedMilliseconds < best ? sw.elapsedMilliseconds : best;
      }
      // measured here: 121 to 172 ms before (every query word against all 50,000 words), 4 to 14 ms now
      expect(best, lessThan(50), reason: 'the paragraph took $best ms');
    });
  });

  group('9B-11: hits from an index that is being replaced', () {
    testWidgets('the screen says when only the start of a long query was searched', (tester) async {
      final state = a.makeState();
      state.data.sessions.add(SessionRecord(date: '2026-11-01', kind: 'daily_checkin', note: '',
          turns: [('person', 'I told her about the zebrafish secret.')]));
      await a.pumpScreen(tester, state, const MemorySearchScreen());
      await tester.enterText(find.byKey(const Key('memory_search')), 'zebrafish ${'and more words ' * 20}');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('1 found. Only the start of what you typed was searched.'), findsOneWidget);
    });

    testWidgets('a hit tapped after the sessions changed, before the screen rebuilt, opens nothing', (tester) async {
      final state = a.makeState();
      state.data.sessions
        ..add(SessionRecord(date: '2026-11-01', kind: 'daily_checkin', note: '',
            turns: [('person', 'I told her about the zebrafish secret.')]))
        ..add(SessionRecord(date: '2026-11-02', kind: 'daily_checkin', note: '', turns: [('person', 'An ordinary day.')]));
      await a.pumpScreen(tester, state, const MemorySearchScreen());
      await tester.enterText(find.byKey(const Key('memory_search')), 'zebrafish');
      await tester.pump(const Duration(milliseconds: 250));
      final hit = find.textContaining('zebrafish secret');
      expect(hit, findsOneWidget);
      // the session is deleted and nothing has told the screen yet (the same frame): the hit's place names another
      state.data.sessions.removeAt(0);
      await tester.tap(hit);
      await tester.pumpAndSettle();
      expect(find.byType(PastSessionView), findsNothing, reason: 'it would have opened "An ordinary day."');
      // once the screen has caught up, the same search finds nothing, and a real hit opens its own session
      state.data.sessions.add(SessionRecord(date: '2026-11-03', kind: 'daily_checkin', note: '',
          turns: [('person', 'The zebrafish again.')]));
      state.reportModel('Ready'); // any notify
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.textContaining('zebrafish again'));
      await tester.pumpAndSettle();
      expect(find.text('The zebrafish again.'), findsOneWidget);
    });
  });
}
