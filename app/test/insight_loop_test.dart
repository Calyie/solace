// The insight loop driven the way a person uses it (report recommendations 21 to 23): naming a feeling from Today,
// the patterns worth noticing from Progress, the weekly review and the year in review (the summary alone with the
// stand-in; a model's few words with any number left out), the days-you-showed-up calendar, and the exports, which
// say they leave Solace's encryption and hold only the notes ticked. New screenshots: test/goldens/25_* to 31_*.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/emotions.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/review.dart';
import 'package:solace/ui/review.dart';
import 'package:solace/ui/your_data.dart';

import 'app_flow_test.dart' as flow;

/// Nine named feelings on the demo person's rated days: "sleep" on the lower ones, so a tag pattern shows.
void addFeelings(AppState state) {
  for (final (day, sleep) in [(9, true), (11, true), (13, false), (15, true), (17, false), (19, false), (21, true),
      (23, false), (25, false)]) {
    state.data.emotions.add(EmotionEntry(at: '2026-11-${day.toString().padLeft(2, '0')}T21:00',
        quadrant: sleep ? 'low_unpleasant' : 'low_pleasant', words: sleep ? ['tired', 'flat'] : ['calm', 'hopeful'],
        tags: sleep ? ['sleep', 'work'] : ['friends'], note: day == 23 ? 'The review went better than I feared.' : ''));
  }
  state.data.journal.add({'date': '2026-11-24', 'text': 'Walked by the canal after work, felt lighter.'});
}

/// A language model on the device, as far as the review can tell: it keeps what it was asked and answers with one
/// sentence that holds a number, which must never reach the screen.
class ReflectingModel implements ModelRuntime {
  final asked = <List<Map<String, String>>>[];
  @override
  String get name => 'reflecting test model';
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    asked.add(messages);
    for (final w in 'It sounds like a month with some lighter stretches. You rated 14 days. Thank you for making '
        'room for it here.'.split(' ')) {
      yield '$w ';
    }
  }
}

/// Tap something in a sheet or screen without the helper's drag past the tab bar.
Future<void> tapHere(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  testWidgets('name the feeling from Today: a part of the grid, words from two parts, what is affecting you, a note',
      (tester) async {
    final state = flow.makeState(demo: true);
    await flow.pumpApp(tester, state);
    await flow.tapIn(tester, find.byKey(const Key('name_feeling')));
    expect(find.text('Where are you right now?'), findsOneWidget);
    await flow.shot('25_name_feeling_grid');
    await tapHere(tester, find.byKey(const Key('quadrant_high_pleasant')));
    expect(find.text('Which words fit?'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('emotion_next'))).onPressed, isNull,
        reason: 'a word first');
    await tapHere(tester, find.byKey(const Key('word_hopeful')));
    await tapHere(tester, find.byKey(const Key('emotion_others')));
    await tapHere(tester, find.byKey(const Key('word_tired')));
    tester.state<ScrollableState>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first)
        .position.jumpTo(0); // back to the top of the sheet
    await tester.pumpAndSettle();
    await flow.shot('26_name_feeling_words');
    await tapHere(tester, find.byKey(const Key('emotion_next')));
    await tapHere(tester, find.byKey(const Key('tag_sleep')));
    await tapHere(tester, find.byKey(const Key('tag_work')));
    await tester.enterText(find.byKey(const Key('emotion_note')), 'The review went better than I feared.');
    await tester.pumpAndSettle();
    await tapHere(tester, find.byKey(const Key('emotion_save')));
    final e = state.data.emotions.single;
    expect((e.at, e.quadrant, e.note), ('2026-11-26T19:30', 'high_pleasant', 'The review went better than I feared.'));
    expect(e.words, ['hopeful', 'tired']);
    expect(e.tags, ['work', 'sleep'], reason: 'in the order of the list, whatever the order tapped');
    expect(find.text('Today: hopeful, tired'), findsOneWidget);
    expect(find.text('Saved. Thank you for naming it.'), findsOneWidget);
    // and it survives the encrypted file's round trip
    await state.vault.save(state.data);
    expect((await state.vault.load()).emotions.single.words, ['hopeful', 'tired']);
  });

  testWidgets('the sheet closes with nothing saved on "Not now", and the check-in offers it too', (tester) async {
    final state = flow.makeState(demo: true);
    await flow.pumpApp(tester, state);
    await flow.tapIn(tester, find.byKey(const Key('name_feeling')));
    await tapHere(tester, find.text('Not now'));
    expect(find.text('Where are you right now?'), findsNothing);
    expect(state.data.emotions, isEmpty);
    await flow.tapIn(tester, find.text('Start'));
    expect(find.text('Before we start'), findsOneWidget);
    expect(find.byKey(const Key('name_feeling')), findsOneWidget);
  });

  testWidgets('a mood tap keeps its time, for time-of-day patterns', (tester) async {
    final state = flow.makeState(demo: true);
    await flow.pumpApp(tester, state);
    await flow.tapIn(tester, find.byKey(const Key('mood_6')));
    expect(state.data.moodTimes['2026-11-26'], '19:30');
  });

  testWidgets('Progress: patterns worth noticing at the top, the days you showed up, and Your data', (tester) async {
    final state = flow.makeState(demo: true);
    addFeelings(state);
    await flow.pumpApp(tester, state);
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    expect(find.text('Patterns worth noticing'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Days you showed up this month'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('Monday 23 November, you showed up'), findsOneWidget); // a session and a mood
    expect(find.bySemanticsLabel('Wednesday 25 November, you showed up'), findsOneWidget);
    expect(find.bySemanticsLabel('Friday 27 November'), findsOneWidget); // tomorrow: not yet
    semantics.dispose();
    expect(find.textContaining('streak'), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('open_your_data')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Your data'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('open_insights')), -300,
        scrollable: find.byType(Scrollable).first);
    await flow.tapIn(tester, find.byKey(const Key('open_insights')));
    expect(find.text('Solace noticed'), findsOneWidget);
    expect(find.textContaining('Since you started Courage ladder on 10 November, your mood has been 1.9 points higher'),
        findsOneWidget);
    expect(find.textContaining('On days you tagged “work” and “sleep”, your mood was 1.5 points lower'), findsOneWidget);
    expect(find.textContaining('tagged “friends”'), findsNothing, reason: 'the same comparison from the other side');
    await flow.shot('27_insights');
    await tester.scrollUntilVisible(find.text('Your PHQ-9 went from 14 (moderate) on 2 November to 10 (moderate) on '
        '16 November.'), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('tired · 4'), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.textContaining('Mood by weekday: shown once one weekday has 3 ratings'), 300,
        scrollable: find.byType(Scrollable).first);
  });

  testWidgets('the weekly review with the stand-in: the summary alone, counted on the device, no invented words',
      (tester) async {
    final state = flow.makeState(demo: true);
    addFeelings(state);
    await flow.pumpApp(tester, state);
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    await flow.tapIn(tester, find.byKey(const Key('open_week')));
    expect(find.text('Friday 20 November to Thursday 26 November'), findsOneWidget);
    expect(find.textContaining("When Solace's language model is on this device"), findsOneWidget);
    expect(find.byKey(const Key('review_reflect')), findsNothing);
    expect(find.text('Mood: rated on 3 of 7 days, 6.0 out of 10 on average (from 5 to 7). The week before: 5.8 on '
        'average.'), findsOneWidget);
    await flow.shot('28_your_week');
    await tapHere(tester, find.byKey(const Key('review_earlier')));
    expect(find.text('Friday 13 November to Thursday 19 November'), findsOneWidget);
  });

  testWidgets('the monthly letter: Solace is given the numbers, and a sentence with a number never shows',
      (tester) async {
    final base = flow.makeState(demo: true);
    addFeelings(base);
    final model = ReflectingModel();
    final state = AppState(data: base.data, vault: base.vault, prompts: base.prompts, model: model,
        library: base.library, clock: base.clock);
    await flow.pumpScreen(tester, state, const ReviewScreen(span: ReviewSpan.month));
    expect(find.text('A letter for your month'), findsOneWidget);
    expect(find.textContaining('The month before'), findsNothing, reason: 'October has one rating only');
    await tapHere(tester, find.byKey(const Key('review_reflect')));
    for (var i = 0; i < 20 && find.byKey(const Key('review_words')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
    expect(tester.widget<Text>(find.byKey(const Key('review_words'))).data,
        'It sounds like a month with some lighter stretches. Thank you for making room for it here.');
    final asked = model.asked.single;
    expect(asked.first['content'], startsWith('You are Solace'));
    expect(asked.last['content'], contains('- Mood: rated on 13 of 26 days'));
    expect(asked.last['content'], contains('write no numbers'));
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await flow.shot('29_month_letter');
  });

  testWidgets('the year in review: a dot for every day rated', (tester) async {
    final state = flow.makeState(demo: true);
    await flow.pumpScreen(tester, state, const ReviewScreen(span: ReviewSpan.year));
    expect(find.text('Your year in review'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('Year in dots: 14 days rated in 2026'), findsOneWidget);
    semantics.dispose();
    await flow.shot('30_your_year');
  });

  testWidgets('Your data: the warning, notes only when ticked, a PDF, a spreadsheet and a text file', (tester) async {
    final state = flow.makeState(demo: true);
    addFeelings(state);
    final saved = <String, Uint8List>{};
    String? answer = 'Saved.';
    await flow.pumpScreen(tester, state, YourDataScreen(save: (name, bytes, mime) async {
      if (answer == null) return null;
      saved[name] = bytes;
      return 'Saved as $name.';
    }));
    expect(find.text("A saved file leaves Solace's encryption"), findsOneWidget);
    expect(find.text('None unless ticked'), findsOneWidget);
    await flow.shot('31_your_data');
    await tapHere(tester, find.byKey(const Key('note_journal:0')));

    await tapHere(tester, find.byKey(const Key('export_csv')));
    final csv = utf8.decode(saved['my-records-2026-11-26.csv']!);
    expect(csv, contains('Walked by the canal after work'));
    expect(csv, isNot(contains('better than I feared')), reason: 'that note was not ticked');
    expect(csv, contains('2026-11-16,,questionnaire,PHQ-9,10,moderate'));
    expect(find.textContaining("It is outside Solace's encryption now"), findsOneWidget);

    await tapHere(tester, find.byKey(const Key('export_md')));
    final md = utf8.decode(saved['my-records-2026-11-26.md']!);
    expect(md, contains('Walked by the canal after work'));
    expect(md, isNot(contains('better than I feared')));

    await tester.ensureVisible(find.byKey(const Key('export_pdf')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export_pdf')));
    for (var i = 0; i < 40 && !saved.containsKey('wellbeing-summary-2026-11-26.pdf'); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final pdf = saved['wellbeing-summary-2026-11-26.pdf']!;
    expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(latin1.decode(pdf), contains('FontFile2'), reason: 'the bundled font is embedded, so it reads the same everywhere');
    expect(latin1.decode(pdf), isNot(contains('Helvetica')));

    answer = null; // the person cancels the save dialog
    await tapHere(tester, find.byKey(const Key('export_csv')));
    expect(find.text('Not saved. Nothing has left Solace.'), findsOneWidget);
  });
}
