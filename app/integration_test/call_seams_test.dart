// End-to-end call on a Mac with no microphone (lead, 2026-11-16): the real call screen, the real session, the trained
// model and the real voice (Kokoro through the app's own SherpaVoice and audioplayers), with the person's words handed
// to the call by the test seam (CallSeams.hear, core/test_seams.dart) and every sentence she plays kept with its rate
// (CallSeams.keepAudioIn). A whole turn runs: heard, thinking, her reply spoken, listening again; then a pause and
// Resume, a second turn, and End, which writes the note. Then the kept audio is checked: the rate written equals the
// rate played (each sentence played for its own length), each sentence's length is plausible for its text, no two
// overlap, and none was cut off.
//
// The files must be where the sandboxed app can read them (its container, as after an import on the owner's Mac):
//   flutter test integration_test/call_seams_test.dart -d macos --dart-define=SOLACE_TEST_SEAMS=true \
//     --dart-define=MODEL_GGUF=<container>/therapist-e2b-Q5_K_M-imat.gguf --dart-define=VOICE_DIR=<container>/voice \
//     --dart-define=KEEP_AUDIO=<container>/kept_audio
// Without SOLACE_TEST_SEAMS (and in any release build) the seams are off and this test is skipped.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/sherpa_voice.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/test_seams.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart' show SessionSummary;
import 'package:solace/ui/theme.dart';

const modelPath = String.fromEnvironment('MODEL_GGUF');
const voiceDir = String.fromEnvironment('VOICE_DIR');
const keepDir = String.fromEnvironment('KEEP_AUDIO');

/// Pumps until [done] or [limit] (the model on a processor can take a while). A test run on a Mac whose app window
/// never comes to the front ("Failed to foreground app") is told it is in front, so the call does not pause as away.
Future<void> until(WidgetTester tester, bool Function() done, {Duration limit = const Duration(minutes: 5),
    String what = ''}) async {
  final end = DateTime.now().add(limit);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what; the call shows ${shown()}');
    if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

bool phase(String p) => find.byKey(Key('call_state_$p')).evaluate().isNotEmpty;

/// What the call shows now: its state and any card, for a failure's message.
String shown() => [
      for (final p in ['listening', 'thinking', 'speaking', 'paused', 'typing', 'ready']) if (phase(p)) p,
      for (final k in ['call_paused_card', 'call_no_mic', 'call_note_progress'])
        if (find.byKey(Key(k)).evaluate().isNotEmpty) k,
      for (final t in find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(12)) t,
    ].join(' | ');

/// The sample rate in a WAV file's header.
int wavRate(File f) => ByteData.sublistView(f.readAsBytesSync()).getUint32(24, Endian.little);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final skip = !testSeams || modelPath.isEmpty || voiceDir.isEmpty || keepDir.isEmpty
      ? 'needs --dart-define=SOLACE_TEST_SEAMS=true and MODEL_GGUF, VOICE_DIR, KEEP_AUDIO'
      : false;

  testWidgets('a whole call with the real model and voice, its audio checked', (tester) async {
    final keep = Directory(keepDir);
    if (keep.existsSync()) keep.deleteSync(recursive: true);
    keep.createSync(recursive: true);
    CallSeams.keepAudioIn = keep.path;

    // the voice's checks and spoken sentences beside the kept audio, never in the app's own folders
    final speech = await Directory('${keep.parent.path}/e2e_speech').create(recursive: true);
    final checks = await Directory('${keep.parent.path}/e2e_checks').create(recursive: true);
    final status = <String>[];
    final voice = await SherpaVoice.load(Directory(voiceDir), speech, checks, status.add);
    expect(voice, isNotNull, reason: status.join(' | '));
    final runtime = await LlamaModelRuntime.load(ModelFile(File(modelPath), ''));
    final data = AppData();
    data.settings
      ..therapistChosen = true
      ..onboarded = true
      ..ageConfirmed = true;
    Future<String> asset(String p) => DefaultAssetBundle.of(tester.binding.rootElement!).loadString(p);
    final state = AppState(data: data, vault: MemoryVault(), model: runtime,
        prompts: Prompts(system: await asset('assets/prompts/app_system_$appPromptVersion.txt'),
            note: await asset('assets/prompts/app_note_$appPromptVersion.txt'),
            story: await asset('assets/prompts/app_story_$appPromptVersion.txt'),
            split: await asset('assets/prompts/app_split_v1.txt')),
        library: parseLibrary(await asset('assets/practices/library_v2.json')));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: appTheme(Brightness.dark),
        home: CallScreen(kind: 'daily_checkin', voice: voice!))));
    // the opening: thinking, spoken, then listening
    await until(tester, () => phase('listening'), what: 'listening after the opening');
    // a turn: heard, thinking, her reply spoken, listening again
    CallSeams.hear('Not great. My manager criticised my report in front of the whole team today.');
    await until(tester, () => phase('thinking') || phase('speaking'), what: 'her reply');
    await until(tester, () => phase('listening'), what: 'listening after her reply');
    // a pause while she listens, then Resume: she listens again and never pauses herself again
    await tester.tap(find.byKey(const Key('call_pause')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(phase('paused'), isTrue);
    await tester.tap(find.byKey(const Key('call_resume')));
    await tester.pump(const Duration(seconds: 1));
    expect(phase('listening'), isTrue);
    // a second turn, then End during her reply: she stops, and the note is written
    CallSeams.hear('I felt small, and then angry with myself for being so upset about it.');
    await until(tester, () => phase('speaking'), what: 'her second reply');
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('call_end')));
    await until(tester, () => find.byType(SessionSummary).evaluate().isNotEmpty, limit: const Duration(minutes: 15),
        what: 'the summary after End');
    expect(state.data.sessions, hasLength(1));

    // the audio she played
    final clips = [for (final l in File('${keep.path}/clips.jsonl').readAsLinesSync()) jsonDecode(l) as Map];
    expect(clips.length, greaterThanOrEqualTo(3), reason: 'the opening and two replies');
    for (final c in clips) {
      final wav = File('${keep.path}/${c['file']}');
      expect(wavRate(wav), c['rate'], reason: 'the rate in the file is the rate Kokoro made it at');
      final seconds = (c['seconds'] as num).toDouble();
      final words = (c['text'] as String).split(' ').length;
      expect(seconds, inInclusiveRange(words * 0.15, words * 0.9 + 1), reason: 'length plausible for "${c['text']}"');
      final played = ((c['end_ms'] as int) - (c['start_ms'] as int)) / 1000;
      if (c['whole'] == true) {
        // played for its own length: the rate played is the rate written (twice the rate would take half the time)
        expect(played, inInclusiveRange(seconds * 0.85, seconds + 1.5), reason: 'played ${played}s of ${seconds}s');
      }
    }
    final whole = clips.where((c) => c['whole'] == true).toList();
    expect(whole.length, greaterThanOrEqualTo(clips.length - 1), reason: 'only End may cut the last sentence');
    for (var i = 1; i < clips.length; i++) {
      expect(clips[i]['start_ms'] as int, greaterThanOrEqualTo(clips[i - 1]['end_ms'] as int),
          reason: 'sentence $i began over sentence ${i - 1}');
    }
    // ignore: avoid_print
    print('E2E kept ${clips.length} sentences in ${keep.path}');
    await tester.pumpWidget(const SizedBox());
    await voice.dispose();
    await runtime.dispose();
  }, skip: skip != false, timeout: const Timeout(Duration(minutes: 30)));
}
