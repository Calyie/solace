// Review round 9 B, 9B-01: memory search runs on the interface thread, inside build(), over the whole store, at every
// keystroke (ui/memory_search.dart:25 calls core/search.dart searchMemory from build; searchMemory rebuilds every
// document, folds every character of every session with split('')/map/join, tokenises it all and scores it, with no
// index, no cache, no debounce and no isolate). The screen also rebuilds, and so searches again, whenever AppState
// notifies (a save finishing, the model or voice status, the pictures measured), because it reads AppScope.of.
//
// A year of daily sessions is about 6 MB (core/transfer.dart; the tracker calls it ordinary). On this laptop, in the
// test runner, one keystroke over such a store blocks the screen for about 0.75 to 1.2 s; a phone is slower.
//
// Each test asserts the SAFE behaviour: one keystroke, or one unrelated AppState change, blocks the interface thread
// for less than 100 ms. Both fail on 3d2da1f while the finding stands.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/memory_search.dart';

import '../audit_followups_test.dart' as a;

/// [days] daily sessions of 40 turns of 400 characters: 365 days is about 6 MB, the tracker's "year of daily sessions".
void addSessions(AppData d, int days) {
  const line = 'Today I felt tired after work, and I kept thinking about my sister and the argument we had. ';
  final start = DateTime(2025, 11, 1);
  for (var i = 0; i < days; i++) {
    final date = start.add(Duration(days: i)).toIso8601String().substring(0, 10);
    final turns = <(String, String)>[];
    for (var j = 0; j < 40; j++) {
      final b = StringBuffer();
      while (b.length < 400) {
        b.write(line);
      }
      turns.add((j.isEven ? 'therapist' : 'person', b.toString().substring(0, 400)));
    }
    d.sessions.add(SessionRecord(date: date, kind: 'daily_checkin', turns: turns, note: 'Talked about: work'));
  }
}

void main() {
  testWidgets('9B-01: one keystroke in memory search over a year of sessions blocks the screen < 100 ms',
      (tester) async {
    final state = a.makeState();
    addSessions(state.data, 365);
    await a.pumpScreen(tester, state, const MemorySearchScreen());
    await tester.enterText(find.byKey(const Key('memory_search')), 'tire');
    await tester.pump();
    final sw = Stopwatch()..start();
    await tester.enterText(find.byKey(const Key('memory_search')), 'tired'); // one more letter
    await tester.pump();
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(100),
        reason: 'one keystroke held the interface thread for ${sw.elapsedMilliseconds} ms');
  });

  testWidgets('9B-01: an unrelated app change (a status line) does not search the whole store again on screen',
      (tester) async {
    final state = a.makeState();
    addSessions(state.data, 365);
    await a.pumpScreen(tester, state, const MemorySearchScreen());
    await tester.enterText(find.byKey(const Key('memory_search')), 'tired');
    await tester.pump();
    final sw = Stopwatch()..start();
    state.reportModel('Loading the model...'); // any AppState notify: a save, a status, the pictures measured
    await tester.pump();
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(100),
        reason: 'a status change re-ran the search and held the interface thread for ${sw.elapsedMilliseconds} ms');
  });
}
