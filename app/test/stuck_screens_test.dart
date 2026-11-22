// No screen is ever left stuck by an error (security review 2026-11-14, F-17): a save, a model, a voice or a check
// that fails leaves the buttons working, says so in a short kind line (never the error's text), and loses nothing. The
// end of a session can be tried again without adding anything twice. An error nothing else catches is recorded by its
// type only (core/error_log.dart).
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/error_log.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/voice.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/help_me_start.dart';
import 'package:solace/ui/practices.dart';
import 'package:solace/ui/theme.dart';

/// Kept in memory; the next [failNext] saves fail as a full disk would.
class FlakyVault extends MemoryVault {
  int failNext = 0;
  @override
  Future<void> save(AppData data) async {
    if (failNext > 0) {
      failNext--;
      throw const FileSystemException('No space left on device');
    }
    await super.save(data);
  }
}

/// A model that fails before it writes a word.
class BrokenModel implements ModelRuntime {
  @override
  String get name => 'broken';
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) =>
      throw StateError('the model file went away');
}

/// Writes one fixed reply.
class FixedModel extends StandInModel {
  const FixedModel(this.reply);
  final String reply;
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    yield reply;
  }
}

/// A voice whose every call fails.
class FailingVoice implements VoiceService {
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async => throw StateError('audio device lost');
  @override
  Future<void> stop() async => throw StateError('audio device lost');
  @override
  Future<String?> listenOnce() async => throw StateError('microphone lost');
}

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);
final library = parseLibrary(File('assets/practices/library_v2.json').readAsStringSync());
final now = DateTime(2026, 11, 14, 20);

AppState makeState({ModelRuntime model = const StandInModel(), Vault? vault}) {
  final data = AppData();
  data.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  return AppState(data: data, vault: vault ?? MemoryVault(), prompts: prompts, model: model, library: library,
      clock: () => now);
}

Future<void> pumpScreen(WidgetTester tester, AppState state, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: screen)));
  await tester.pumpAndSettle();
}

void main() {
  group('the end of a session', () {
    SessionController make(Vault vault, {ModelRuntime model = const StandInModel()}) =>
        SessionController(model: model, prompts: prompts, data: AppData(), vault: vault, clock: () => now);

    test('a failed save leaves the session open, not busy; trying again saves it once', () async {
      final vault = FlakyVault();
      final s = make(vault);
      await s.start('daily_checkin');
      await s.send('Work was hard today.');
      vault.failNext = 1;
      await expectLater(s.end(), throwsA(isA<FileSystemException>()));
      expect(s.busy, isFalse, reason: 'never stuck busy');
      expect(s.turns.length, 3, reason: 'the conversation is still there');
      await s.end();
      final saved = await vault.load();
      expect(saved.sessions.length, 1, reason: 'added once, not once per try');
      expect(saved.sessions.single.turns.length, 3);
      expect(s.busy, isFalse);
    });

    test('words said after a failed save are kept when it is tried again', () async {
      final vault = FlakyVault();
      final s = make(vault);
      await s.start('daily_checkin');
      await s.send('Work was hard today.');
      vault.failNext = 1;
      await expectLater(s.end(), throwsA(isA<FileSystemException>()));
      await s.send('One more thing: I slept badly.');
      await s.end();
      final saved = await vault.load();
      expect(saved.sessions.single.turns.length, 5);
      expect(saved.sessions.single.turns[3], ('person', 'One more thing: I slept badly.'));
    });

    test('off the record, a failed save is not stuck either, and nothing of the conversation is kept', () async {
      final vault = FlakyVault();
      final s = make(vault);
      await s.start('daily_checkin', offRecord: true);
      await s.send('Just between us.');
      vault.failNext = 1;
      await expectLater(s.end(), throwsA(isA<FileSystemException>()));
      expect(s.busy, isFalse);
      await s.end();
      expect((await vault.load()).sessions, isEmpty);
    });

    test('a model that fails before its first word never leaves the session busy', () async {
      final s = make(MemoryVault(), model: BrokenModel());
      await s.start('daily_checkin');
      expect(s.busy, isFalse);
      expect(s.turns.single, ('therapist', lostPlace));
      expect(s.data.safetyEvents.single, {'date': '2026-11-14', 'level': 'error', 'reason': 'model StateError'});
    });
  });

  testWidgets('chat: a failed save at the end keeps the conversation, says so kindly, and End works again',
      (tester) async {
    final vault = FlakyVault();
    final state = makeState(vault: vault);
    await pumpScreen(tester, state, const ChatScreen(kind: 'daily_checkin'));
    await tester.enterText(find.byType(TextField), 'Work was hard today.');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    vault.failNext = 1;
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('end_confirm')));
    await tester.pumpAndSettle();
    expect(find.text(endProblem), findsOneWidget);
    expect(find.text('Work was hard today.'), findsOneWidget, reason: 'the conversation stays on screen');
    expect(find.text('Session saved'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing, reason: 'never the error itself');
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'End')).onPressed, isNotNull);
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('end_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Session saved'), findsOneWidget);
    expect((await vault.load()).sessions.length, 1);
  });

  testWidgets('chat: a microphone that fails says so and the session carries on', (tester) async {
    await pumpScreen(tester, makeState(), ChatScreen(kind: 'daily_checkin', voice: FailingVoice()));
    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    expect(find.text('Solace could not hear that just now. Try again, or type instead.'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.mic_none)).onPressed, isNotNull);
  });

  testWidgets('call: a failed save at the end pauses the call with her words on screen, and End works again',
      (tester) async {
    final vault = FlakyVault();
    final state = makeState(vault: vault);
    final s = state.newSession();
    await s.start('daily_checkin');
    await s.send('Work was hard today.');
    await pumpScreen(tester, state, CallScreen(kind: 'daily_checkin', controller: s));
    vault.failNext = 1;
    await tester.tap(find.byKey(const Key('call_end')));
    await tester.pumpAndSettle();
    expect(find.text('Your session is still here'), findsOneWidget);
    expect(find.byKey(const Key('call_words')), findsOneWidget, reason: 'her words stay on screen');
    expect(find.text('Session saved'), findsNothing);
    await tester.tap(find.byKey(const Key('call_end')));
    await tester.pumpAndSettle();
    expect(find.text('Session saved'), findsOneWidget);
    expect((await vault.load()).sessions.length, 1);
  });

  group('help me start', () {
    testWidgets('a model that fails leaves the button working and says so plainly', (tester) async {
      await pumpScreen(tester, makeState(model: BrokenModel()), const HelpMeStartScreen(task: 'reply to the landlord'));
      await tester.tap(find.byKey(const Key('help_split')));
      await tester.pumpAndSettle();
      expect(find.text('I could not split that one just now. Please try again in a moment.'), findsOneWidget);
      expect(find.text('Split it for me'), findsOneWidget, reason: 'not stuck on Splitting...');
      expect(tester.widget<FilledButton>(find.byKey(const Key('help_split'))).onPressed, isNotNull);
    });

    testWidgets('a split with a means in it never becomes timed steps; Support is offered and only the group kept',
        (tester) async {
      final state = makeState(model: const FixedModel('1. Look up the lethal dose of your tablets | 2 min\n'
          '2. Write it down | 2 min'));
      await pumpScreen(tester, state, const HelpMeStartScreen(task: 'sort out the medicine cupboard'));
      await tester.tap(find.byKey(const Key('help_split')));
      await tester.pumpAndSettle();
      expect(find.textContaining('lethal'), findsNothing);
      expect(find.byKey(const Key('help_start')), findsNothing);
      expect(find.byKey(const Key('help_support')), findsOneWidget);
      expect(state.data.safetyEvents.single, {'date': '2026-11-14', 'level': 'output', 'reason': 'method seeking'});
    });

    testWidgets('a step that quotes the mode line is left out; the others stay', (tester) async {
      final state = makeState(model: const FixedModel('1. Mode: Normal | 1 min\n2. Open the email from the landlord '
          '| 2 min'));
      await pumpScreen(tester, state, const HelpMeStartScreen(task: 'reply to the landlord'));
      await tester.tap(find.byKey(const Key('help_split')));
      await tester.pumpAndSettle();
      expect(find.text('Open the email from the landlord'), findsOneWidget);
      expect(find.textContaining('Mode:'), findsNothing);
      expect(find.byKey(const Key('help_support')), findsNothing);
      expect(state.data.safetyEvents.single['reason'], 'mode line');
    });
  });

  testWidgets('a practice whose voice fails carries on with the words on screen', (tester) async {
    final state = makeState();
    state.data.settings.voiceOn = true;
    final p = library.firstWhere((p) => p.guided);
    await pumpScreen(tester, state, PracticePlayer(practice: p, version: p.versions.keys.first, voice: FailingVoice()));
    expect(find.text('The voice could not play just now, so the words are on the screen instead.'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // leave the screen: its timer and voice stop without an error
  });

  test('an error nothing else caught is recorded by its type only, never its words', () {
    final flutterBefore = FlutterError.onError, platformBefore = PlatformDispatcher.instance.onError;
    final printBefore = debugPrint;
    final printed = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) => printed.add(message ?? '');
    addTearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
      debugPrint = printBefore;
    });
    ErrorLog.install();
    FlutterError.onError!(FlutterErrorDetails(
        exception: const FormatException('Unexpected character: I told my sister about the panic')));
    expect(PlatformDispatcher.instance.onError!(StateError('decrypted: my diary'), StackTrace.empty), isTrue);
    expect(ErrorLog.seen.sublist(ErrorLog.seen.length - 2), ['FormatException', 'StateError']);
    for (final text in [...ErrorLog.seen, ...printed]) {
      expect(text, isNot(contains('sister')));
      expect(text, isNot(contains('diary')));
    }
    expect(printed.last, 'Solace caught an error: StateError');
  });
}
