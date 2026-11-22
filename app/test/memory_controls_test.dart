// What Solace remembers, and the person's controls (research report P1 17): Pause memory starts each session fresh
// and learns nothing new; an off-the-record session keeps nothing from the conversation while its safety events are
// still kept; Erase clears the story, the last note and the things noticed but keeps sessions, plans and the safety
// plan; each value and goal says where it came from and can be forgotten.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/plans.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/chat.dart';

import 'app_flow_test.dart' as flow;

void main() {
  final prompts = Prompts(
    system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
    note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
    story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
    split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
  );
  SessionController make(AppData data, Vault vault) => SessionController(model: const StandInModel(),
      prompts: prompts, data: data, vault: vault, clock: () => DateTime(2026, 11, 5, 19));

  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  test('memory paused: the session starts fresh, is kept, and nothing new is learned from it', () async {
    final vault = MemoryVault();
    final data = AppData()
      ..homeworkDue = 'a ten-minute walk after lunch'
      ..lastNote = 'Session: an older note'
      ..settings.memoryPaused = true;
    final s = make(data, vault);
    await s.start('daily_checkin');
    expect(s.turns.first.$2, isNot(contains('a ten-minute walk after lunch')));
    await s.send('I did it twice.');
    await s.end();
    final saved = await vault.load();
    expect(saved.sessions, hasLength(1)); // the session itself is kept
    expect(saved.lastNote, 'Session: an older note'); // but not learned from
    expect(saved.homeworkDue, 'a ten-minute walk after lunch');
    // and with memory on again, the next session remembers as before
    data.settings.memoryPaused = false;
    final again = make(data, vault);
    await again.start('daily_checkin');
    expect(again.turns.first.$2, contains('a ten-minute walk after lunch'));
  });

  test('off the record: nothing from the conversation is kept, but its safety events are', () async {
    final vault = MemoryVault();
    final data = AppData()..lastNote = 'Session: an older note';
    final s = make(data, vault);
    await s.start('daily_checkin', offRecord: true);
    expect(s.offRecord, isTrue);
    await s.send('I want to kill myself');
    await s.end();
    final saved = await vault.load();
    expect(saved.sessions, isEmpty);
    expect(saved.lastNote, 'Session: an older note');
    expect(saved.toJson().toString(), isNot(contains('kill myself')));
    expect(saved.safetyEvents, isNotEmpty); // safety is never off the record
    expect(saved.safetyWatch, isNotNull);
  });

  test('erase keeps sessions, moods, plans, goals and the safety plan', () {
    final d = AppData()
      ..lastNote = 'Session: x'
      ..homeworkDue = 'walk'
      ..moods['2026-11-05'] = 6
      ..suggestions.add(PendingSuggestion('value', 'kindness', 'I like being kind', '2026-11-05'))
      ..sessions.add(SessionRecord(date: '2026-11-05', kind: 'daily_checkin', turns: [], note: 'n'))
      ..plans.values.add(Value(text: 'creativity'))
      ..safetyPlan.add('people', 'Sam', '2026-11-05');
    d.story.sections[storyHeadings.first] = 'Works long hours';
    d.eraseMemory();
    expect(d.lastNote, isEmpty);
    expect(d.homeworkDue, isEmpty);
    expect(d.suggestions, isEmpty);
    expect(d.story.sections.values.every((v) => v.isEmpty), isTrue);
    expect(d.sessions, hasLength(1));
    expect(d.moods, hasLength(1));
    expect(d.plans.values, hasLength(1));
    expect(d.safetyPlan.of('people'), ['Sam']);
  });

  testWidgets('the You tab: pause, erase with a confirmation, and why Solace knows a value', (tester) async {
    final state = flow.makeState();
    state.data.plans.values.add(Value(text: 'fairness', quote: 'it matters that things are fair', added: '2026-11-03'));
    state.data.lastNote = 'Session: x';
    await flow.pumpApp(tester, state);
    await tester.tap(find.byKey(const Key('tab_You')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memory_pause')));
    await tester.pumpAndSettle();
    expect(state.data.settings.memoryPaused, isTrue);
    await tester.tap(find.byKey(const Key('memory_erase')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(state.data.lastNote, 'Session: x');
    await tester.tap(find.byKey(const Key('memory_erase')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memory_erase_confirm')));
    await tester.pumpAndSettle();
    expect(state.data.lastNote, isEmpty);
    await tester.ensureVisible(find.text('fairness'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fairness'));
    await tester.pumpAndSettle();
    expect(find.text('Why does Solace know this?'), findsOneWidget);
    expect(find.textContaining('it matters that things are fair'), findsOneWidget);
    expect(find.textContaining('3 November'), findsOneWidget);
    await tester.tap(find.byKey(const Key('why_forget')));
    await tester.pumpAndSettle();
    expect(state.data.plans.values.where((v) => v.text == 'fairness'), isEmpty);
  });

  testWidgets('the Talk tab opens an off-the-record session that says so', (tester) async {
    final state = flow.makeState();
    await flow.pumpApp(tester, state);
    await tester.tap(find.byKey(const Key('tab_Talk')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('talk_off_record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('talk_off_record')));
    await flow.frames(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text(offRecordNotice), findsOneWidget);
    expect(find.text('Off the record'), findsWidgets);
    // the trained safety check is not loaded in tests, and the session says so
    expect(find.text(phraseRulesOnlyNotice), findsOneWidget);
  });
}
