// Round 9 review B fixes made by the lead (fix/round9-flows): 9B-01 memory search, 9B-02 support before saves,
// 9B-03 the phrase rules off the interface thread, 9B-07 "Saved." only after a save, 9B-08 the classifier-off notice.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/search.dart';
import 'package:solace/core/session.dart';
import 'package:solace/ui/memory_search.dart';

import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/emotion_sheet.dart' show feelingNotSaved;

import 'app_flow_test.dart' as flow;
import 'audit_followups_test.dart' as a;
import 'insight_loop_test.dart' show tapHere;
import 'review9b/search_freezes_screen_test.dart' show addSessions;

/// A vault whose saves fail once [failing] is set (a full disk).
class _FailingVault extends MemoryVault {
  bool failing = false;
  @override
  Future<void> save(AppData data) async {
    if (failing) throw const FileSystemException('No space left on device');
    return super.save(data);
  }
}

Future<void> _nameAFeeling(WidgetTester tester, AppState state, String note) async {
  await flow.pumpApp(tester, state);
  await flow.tapIn(tester, find.byKey(const Key('name_feeling')));
  await tapHere(tester, find.byKey(const Key('quadrant_high_pleasant')));
  await tapHere(tester, find.byKey(const Key('word_hopeful')));
  await tapHere(tester, find.byKey(const Key('emotion_next')));
  await tester.enterText(find.byKey(const Key('emotion_note')), note);
  await tester.pumpAndSettle();
  await tapHere(tester, find.byKey(const Key('emotion_save')));
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  group('9B-07 naming a feeling', () {
    testWidgets('a save that failed never says "Saved."; it says it was not saved', (tester) async {
      final vault = _FailingVault();
      final state = flow.makeState(demo: true, vault: vault);
      vault.failing = true;
      await _nameAFeeling(tester, state, 'A slow day.');
      expect(find.text('Saved. Thank you for naming it.'), findsNothing);
      expect(find.text(feelingNotSaved), findsOneWidget);
    });

    testWidgets('a save that worked still says "Saved."', (tester) async {
      final state = flow.makeState(demo: true);
      await _nameAFeeling(tester, state, 'A slow day.');
      expect(find.text('Saved. Thank you for naming it.'), findsOneWidget);
      expect(find.text(feelingNotSaved), findsNothing);
    });
  });

  group('9B-08 why only the phrase checks are running', () {
    testWidgets('turned off in Settings: the chat says so, never "not set up on this device"', (tester) async {
      final state = a.makeState();
      state.data.settings.classifierOn = false;
      await a.pumpScreen(tester, state, const ChatScreen(kind: 'daily_checkin'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(classifierOffNotice), findsOneWidget);
      expect(find.text(phraseRulesOnlyNotice), findsNothing);
    });

    testWidgets('on but not on this device: the chat says it is not set up', (tester) async {
      final state = a.makeState();
      expect(state.data.settings.classifierOn, isTrue);
      await a.pumpScreen(tester, state, const ChatScreen(kind: 'daily_checkin'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(phraseRulesOnlyNotice), findsOneWidget);
      expect(find.text(classifierOffNotice), findsNothing);
    });
  });

  group('9B-01 memory search', () {
    test('a query over the built index of a year of sessions takes well under 100 ms', () {
      final state = a.makeState();
      addSessions(state.data, 365);
      final index = SearchIndex.build(searchInputs(state.data));
      index.search('tire', today: DateTime(2026, 11, 1)); // warm up
      final sw = Stopwatch()..start();
      final hits = index.search('tired sister', today: DateTime(2026, 11, 1));
      sw.stop();
      expect(hits, hasLength(30));
      expect(sw.elapsedMilliseconds, lessThan(100), reason: 'query took ${sw.elapsedMilliseconds} ms');
    });

    test('the index answers exactly as a fresh search does', () {
      final state = a.makeState();
      addSessions(state.data, 40);
      state.data.journal.add({'date': '2026-01-03', 'text': 'A walk by the canal, "café" after.'});
      final index = SearchIndex.build(searchInputs(state.data));
      for (final q in ['tired', 'sis', '"the argument"', 'cafe', 'canal walk', 'zzz', 'a']) {
        final x = index.search(q, today: DateTime(2026, 2, 1)), y = searchMemory(state.data, q, today: DateTime(2026, 2, 1));
        expect([for (final h in x) (h.index, h.source, h.snippet)], [for (final h in y) (h.index, h.source, h.snippet)], reason: q);
      }
    });

    test('the index builds in a real background isolate', () async {
      final state = a.makeState();
      addSessions(state.data, 30);
      final inputs = searchInputs(state.data);
      final index = await Isolate.run(() => SearchIndex.build(inputs));
      expect(index.length, 30);
      expect(index.search('tired'), isNotEmpty);
    });

    testWidgets('results appear once the typing pauses, and the screen says it is searching meanwhile', (tester) async {
      final state = a.makeState();
      addSessions(state.data, 20);
      await a.pumpScreen(tester, state, const MemorySearchScreen());
      await tester.enterText(find.byKey(const Key('memory_search')), 'sister');
      await tester.pump();
      expect(find.text('Searching...'), findsOneWidget);
      await tester.pump(_MemoryPause.pause);
      expect(find.text('20 found'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('memory_search')), 'qqqq');
      await tester.pump(_MemoryPause.pause);
      expect(find.text('Nothing found. Try another word.'), findsOneWidget);
    });

    testWidgets('a session added while the screen is open is found', (tester) async {
      final state = a.makeState();
      addSessions(state.data, 3);
      await a.pumpScreen(tester, state, const MemorySearchScreen());
      await tester.enterText(find.byKey(const Key('memory_search')), 'sister');
      await tester.pump(_MemoryPause.pause);
      expect(find.text('3 found'), findsOneWidget);
      addSessions(state.data, 1);
      state.reportModel('Ready'); // any notify
      await tester.pump();
      await tester.pump(_MemoryPause.pause);
      expect(find.text('4 found'), findsOneWidget);
    });
  });
}

abstract final class _MemoryPause {
  static const pause = Duration(milliseconds: 250);
}
