// Review round 9 B, re-check, 9B-11: when the sessions change while Search is open beneath another screen (on a
// computer the menus open Settings over it, and Choose what to delete from there), the screen keeps showing the hits of
// the old index until the new one has been built in the background (ui/memory_search.dart _refreshIndex: _hits and
// _index are replaced only when the new build answers, about a second for a year of sessions). A deleted
// conversation's words stay on screen meanwhile, and a hit's index into data.sessions now names another session (or
// none, a RangeError in onTap).
//
// The test asserts the SAFE behaviour: right after the only matching session is deleted, its hit is no longer shown.
// It fails on 1373d75 while the finding stands.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/search.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/memory_search.dart';

import '../audit_followups_test.dart' as a;

void main() {
  testWidgets('9B-11: a deleted session\'s hit goes at once, not when the new index is ready', (tester) async {
    final keep = buildSearchIndexApart;
    addTearDown(() => buildSearchIndexApart = keep);
    final pending = <Completer<void>>[];
    buildSearchIndexApart = (inputs) async { // a background build that takes a moment, as the real isolate does
      final c = Completer<void>();
      pending.add(c);
      await c.future;
      return SearchIndex.build(inputs);
    };
    final state = a.makeState();
    state.data.sessions
      ..add(SessionRecord(date: '2026-11-01', kind: 'daily_checkin', note: '',
          turns: [('person', 'I told her about the zebrafish secret.')]))
      ..add(SessionRecord(date: '2026-11-02', kind: 'daily_checkin', note: '', turns: [('person', 'An ordinary day.')]));
    await a.pumpScreen(tester, state, const MemorySearchScreen());
    for (final c in pending) {
      c.complete();
    }
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('memory_search')), 'zebrafish');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('zebrafish secret'), findsOneWidget, reason: 'set-up: the hit shows');
    state.data.sessions.removeAt(0); // Choose what to delete, on a screen above
    await state.trySave(); // which notifies, as the delete does
    await tester.pump();
    expect(find.textContaining('zebrafish secret'), findsNothing,
        reason: 'the deleted conversation\'s words are still shown while the new index builds');
    for (final c in pending) {
      if (!c.isCompleted) c.complete();
    }
    await tester.pumpAndSettle();
  });
}
