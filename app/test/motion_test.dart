// The call's states, the latency lines, haptics and calm motion (report 2026-11-14, P1 11, 12, 14 and 15): the call
// shows what it is doing as a shape and a word, with her words as captions from the start; Pause keeps the session and
// Resume carries on; going out of sight or a failing voice pauses calmly and offers to pick up again; while a reply is
// prepared a soft line comes at 2 seconds and a reassuring one at 10, on the call and in the chat; no haptic plays
// while the microphone is live, and Settings turns them all off; the breathing guide keeps the person's pace, 6 a
// minute by default, and holds still with a countdown when the device asks for less motion.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/voice.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/practices.dart';
import 'package:solace/ui/premium.dart';
import 'package:solace/ui/theme.dart';

import 'app_flow_test.dart' as flow;

/// A voice that holds each step until the test moves it on: she speaks until stopped or finished, and the microphone
/// listens until stopped or until something is said. It can fail once on speaking, as a lost audio device would.
class HeldVoice implements VoiceService {
  HeldVoice({this.failOnce = false});
  bool failOnce;
  final events = <String>[];
  Completer<void>? _speech;
  Completer<String?>? _ear;

  bool get speaking => _speech != null && !_speech!.isCompleted;
  bool get listening => _ear != null && !_ear!.isCompleted;

  @override
  bool get available => true;

  @override
  Future<void> speak(String text, {required String voice}) async {
    events.add('speak');
    if (failOnce) {
      failOnce = false;
      throw StateError('the audio device went away');
    }
    _speech = Completer<void>();
    await _speech!.future;
  }

  void finishSpeaking() => _speech!.complete();

  @override
  Future<void> stop() async {
    events.add('stop');
    if (speaking) _speech!.complete();
    if (listening) _ear!.complete(null);
  }

  @override
  Future<String?> listenOnce() {
    events.add('listen');
    _ear = Completer<String?>();
    return _ear!.future;
  }

  void say(String words) => _ear!.complete(words);
}

/// The stand-in, but each reply waits until the test lets it through, as a slow device would.
class GatedModel extends StandInModel {
  GatedModel();
  final gate = Completer<void>();
  void open() => gate.complete();
  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    await gate.future;
    yield* super.generate(messages, maxTokens: maxTokens);
  }
}

/// Every haptic the app asks the platform for, by type.
List<String> recordHaptics(WidgetTester tester) {
  final felt = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') felt.add(call.arguments as String);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return felt;
}

const selection = 'HapticFeedbackType.selectionClick', confirm = 'HapticFeedbackType.lightImpact',
    warning = 'HapticFeedbackType.warningNotification';

/// A screen on a phone-sized view, without waiting for it to settle (a reply may be on its way).
Future<void> show(WidgetTester tester, AppState state, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(key: UniqueKey(), state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: screen))); // a fresh app each time, with nothing left open
  await tester.pump();
}

/// Let the call move on: the microtasks, the frame that shows the change, then the state's short fade.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

String clockOf(WidgetTester tester) =>
    tester.widget<Text>(find.textContaining(RegExp(r'^\d\d:\d\d$'))).data!;

CallPhase glyphOf(WidgetTester tester) => tester.widget<CallStateGlyph>(find.byType(CallStateGlyph)).phase;

/// A call with [voice] that has spoken its opening line and is listening.
Future<void> listeningCall(WidgetTester tester, AppState state, HeldVoice voice) async {
  await show(tester, state, CallScreen(kind: 'daily_checkin', voice: voice));
  await settle(tester);
  voice.finishSpeaking();
  await settle(tester);
  expect(voice.listening, isTrue);
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  tearDown(() {
    Haptics.wanted = () => true;
    Haptics.micLive = false;
  });

  group('the call', () {
    testWidgets('shows what it is doing as a shape and a word: thinking, speaking, listening; words on from the start',
        (tester) async {
      final model = GatedModel();
      final state = flow.makeState(demo: true)..useModel(model, 'test');
      final voice = HeldVoice();
      final sessions = state.data.sessions.length;
      await show(tester, state, CallScreen(kind: 'daily_checkin', voice: voice));
      await settle(tester);
      expect(find.byKey(const Key('call_state_thinking')), findsOneWidget);
      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('Hide words'), findsOneWidget, reason: 'captions are on by default');

      model.open();
      await settle(tester);
      expect(find.byKey(const Key('call_state_speaking')), findsOneWidget);
      expect(glyphOf(tester), CallPhase.speaking); // the sound bars, not only a colour
      expect(find.text('Speaking'), findsOneWidget);
      expect(find.text(tapToInterrupt), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('call_words')), matching: find.textContaining('Hello again')),
          findsOneWidget, reason: 'her words show without asking');

      voice.finishSpeaking();
      await settle(tester);
      expect(find.byKey(const Key('call_state_listening')), findsOneWidget);
      expect(glyphOf(tester), CallPhase.listening); // the ring
      expect(find.text('Listening'), findsOneWidget);
      expect(Haptics.micLive, isTrue);

      voice.say('I sketched on the tram twice.');
      await settle(tester);
      expect(Haptics.micLive, isFalse);
      expect(state.data.sessions.length, sessions);
      expect(voice.events, ['speak', 'listen', 'speak'], reason: 'what was heard was answered, then spoken');
      expect(find.textContaining('Stand-in reply'), findsOneWidget);

      await tester.tap(find.byKey(const Key('call_captions')));
      await settle(tester);
      expect(find.byKey(const Key('call_words')), findsNothing);
      expect(find.text('Show words'), findsOneWidget);
    });

    testWidgets('Pause keeps the session and its clock; Resume carries on and says again what was cut short',
        (tester) async {
      final state = flow.makeState(demo: true);
      final voice = HeldVoice();
      final sessions = state.data.sessions.length;
      await show(tester, state, CallScreen(kind: 'daily_checkin', voice: voice));
      await settle(tester);
      expect(voice.speaking, isTrue);

      await tester.tap(find.byKey(const Key('call_pause')));
      await settle(tester);
      expect(find.byKey(const Key('call_state_paused')), findsOneWidget);
      expect(glyphOf(tester), CallPhase.paused);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Take your time'), findsOneWidget);
      expect(find.byKey(const Key('call_resume')), findsOneWidget);
      expect(voice.speaking || voice.listening, isFalse, reason: 'paused: she is quiet and nothing listens');
      expect(voice.events, ['speak', 'stop']);
      final clock = clockOf(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(clockOf(tester), clock, reason: 'the clock waits too');
      expect(find.text('End'), findsOneWidget, reason: 'End stays separate');
      expect(state.data.sessions.length, sessions, reason: 'pausing never ends the session');

      await tester.tap(find.byKey(const Key('call_resume')));
      await settle(tester);
      expect(voice.events, ['speak', 'stop', 'speak'], reason: 'she says again the reply that was cut short');
      expect(find.byKey(const Key('call_state_speaking')), findsOneWidget);
      expect(find.byKey(const Key('call_paused_card')), findsNothing);

      voice.finishSpeaking();
      await settle(tester);
      expect(voice.listening, isTrue);
      // paused while listening: the microphone closes; the Pause button itself resumes, listening again
      await tester.tap(find.byKey(const Key('call_pause')));
      await settle(tester);
      expect(voice.listening, isFalse);
      expect(find.text('Resume'), findsNWidgets(2)); // the button and the card
      await tester.tap(find.byKey(const Key('call_pause')));
      await settle(tester);
      expect(voice.listening, isTrue);
      expect(voice.events, ['speak', 'stop', 'speak', 'listen', 'stop', 'listen']);
    });

    testWidgets('going out of sight pauses the call; coming back offers to pick up where it left off', (tester) async {
      final voice = HeldVoice();
      await listeningCall(tester, flow.makeState(demo: true), voice);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); // an alarm, a phone call
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(voice.listening, isFalse, reason: 'nothing listens while Solace is out of sight');
      expect(find.text('Pick up where we left off?'), findsOneWidget);
      expect(find.textContaining('while you were away'), findsOneWidget);
      await tester.tap(find.byKey(const Key('call_resume')));
      await settle(tester);
      expect(voice.listening, isTrue);
      expect(find.byKey(const Key('call_state_listening')), findsOneWidget);
    });

    testWidgets('a voice that fails pauses calmly with a soft warning, and Resume tries again', (tester) async {
      final felt = recordHaptics(tester);
      final voice = HeldVoice(failOnce: true);
      await show(tester, flow.makeState(demo: true), CallScreen(kind: 'daily_checkin', voice: voice));
      await settle(tester);
      expect(find.text('Pick up where we left off?'), findsOneWidget);
      expect(find.textContaining('The voice stopped unexpectedly'), findsOneWidget);
      expect(felt, [warning], reason: 'a soft warning, never a harsh error');
      await tester.tap(find.byKey(const Key('call_resume')));
      await settle(tester);
      expect(voice.speaking, isTrue);
      expect(voice.events, ['speak', 'stop', 'speak']);
      expect(felt, [warning, confirm]);
    });

    testWidgets('nothing heard for a while: the microphone rests until Resume', (tester) async {
      final voice = HeldVoice();
      await listeningCall(tester, flow.makeState(demo: true), voice);
      await voice.stop(); // what the real voice's 25-second quiet ends with: nothing heard
      voice.events.removeLast();
      await settle(tester);
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(voice.listening, isFalse);
      await tester.tap(find.byKey(const Key('call_resume')));
      await settle(tester);
      expect(voice.listening, isTrue);
    });

    // owner, 2026-11-15, OWNER-C1: a crisis on a call shows the support card on the call screen, above the controls
    // and never over them, and the full support screen is one tap away (it used to open over the call)
    testWidgets('a crisis on a call shows the support card, leaves the controls free, keeps the AI tag; full support '
        'is one tap away', (tester) async {
      final state = flow.makeState(demo: true);
      final voice = HeldVoice();
      await listeningCall(tester, state, voice);
      expect(find.byType(AiTag), findsOneWidget);
      voice.say('Some nights I think everyone would be better off without me.');
      await tester.pumpAndSettle();
      expect(state.data.safetyEvents.where((e) => e['level'] == 'crisis'), hasLength(1));
      expect(state.data.safetyWatch, isNotNull);
      expect(find.byKey(const Key('crisis_card')), findsOneWidget, reason: 'support is a card on the call screen');
      expect(find.text('You matter, and support is here'), findsNothing, reason: 'nothing covers the call');
      for (final control in ['call_pause', 'call_captions', 'call_support', 'call_end']) {
        expect(find.byKey(Key(control)).hitTestable(), findsOneWidget, reason: 'the card never covers $control');
      }
      await tester.ensureVisible(find.byKey(const Key('crisis_card_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crisis_card_more')));
      await tester.pumpAndSettle();
      expect(find.text('You matter, and support is here'), findsOneWidget);
      Navigator.of(tester.element(find.text('You matter, and support is here'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Support is one tap away'), findsOneWidget);
      expect(find.byType(AiTag), findsOneWidget);
    });
  });

  group('while a reply is prepared', () {
    Future<void> lines(WidgetTester tester) async {
      expect(find.byKey(const Key('thinking_indicator')), findsOneWidget);
      expect(find.text(thinkingSoon), findsNothing);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text(thinkingSoon), findsNothing);
      await tester.pump(const Duration(milliseconds: 200)); // 2.1 seconds
      expect(find.text(thinkingSoon), findsOneWidget);
      expect(find.text(stillWorking), findsNothing);
      await tester.pump(const Duration(milliseconds: 7700)); // 9.8 seconds
      expect(find.text(stillWorking), findsNothing);
      await tester.pump(const Duration(milliseconds: 300)); // 10.1 seconds
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(stillWorking), findsOneWidget); // Stop is there all along (report P1 14)
      expect(find.text(thinkingSoon), findsNothing);
    }

    testWidgets('on the call: the thinking state, a soft line at 2 seconds, a reassuring one at 10', (tester) async {
      final model = GatedModel();
      await show(tester, flow.makeState(demo: true)..useModel(model, 'test'),
          CallScreen(kind: 'daily_checkin', voice: HeldVoice()));
      expect(find.byKey(const Key('call_state_thinking')), findsOneWidget);
      await lines(tester);
      model.open();
      await settle(tester);
      expect(find.byKey(const Key('thinking_indicator')), findsNothing);
      expect(find.byKey(const Key('call_state_speaking')), findsOneWidget);
    });

    testWidgets('in the chat: the same breathing dots and lines in place of a spinner', (tester) async {
      final model = GatedModel();
      await show(tester, flow.makeState(demo: true)..useModel(model, 'test'),
          const ChatScreen(kind: 'daily_checkin'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await lines(tester);
      model.open();
      await settle(tester);
      expect(find.byKey(const Key('thinking_indicator')), findsNothing);
      expect(find.textContaining('Hello again'), findsOneWidget);
    });
  });

  group('haptics', () {
    testWidgets('none while the microphone is live on a call; they come back when it closes', (tester) async {
      final felt = recordHaptics(tester);
      final voice = HeldVoice();
      await listeningCall(tester, flow.makeState(demo: true), voice);
      await tester.tap(find.byKey(const Key('call_captions')));
      await settle(tester);
      expect(find.text('Show words'), findsOneWidget, reason: 'the tap worked');
      feelDone();
      Haptics.success();
      expect(felt, isEmpty, reason: 'the microphone is live: no haptic of any kind');
      await tester.tap(find.byKey(const Key('call_pause'))); // the tap that closes the microphone is silent too
      await settle(tester);
      expect(felt, isEmpty);
      expect(Haptics.micLive, isFalse);
      await tester.tap(find.byKey(const Key('call_captions')));
      await settle(tester);
      expect(felt, [selection]);
    });

    testWidgets('the Haptics switch in Settings turns them all off, and on again', (tester) async {
      final felt = recordHaptics(tester);
      final state = flow.makeState(demo: true);
      await flow.pumpApp(tester, state);
      await tester.tap(find.byKey(const Key('tab_Practices')));
      await tester.pumpAndSettle();
      expect(felt, [selection], reason: 'a tab change ticks, on by default');
      await tester.tap(find.byKey(const Key('tab_You')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('haptics_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('haptics_switch')));
      await tester.pumpAndSettle();
      expect(state.data.settings.haptics, isFalse);
      felt.clear();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tab_Today')));
      await tester.pumpAndSettle();
      expect(felt, isEmpty, reason: 'turned off: nothing, anywhere');

      await tester.tap(find.byKey(const Key('tab_You')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('haptics_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('haptics_switch')));
      await tester.pumpAndSettle();
      expect(state.data.settings.haptics, isTrue);
      expect(felt, [confirm], reason: 'turning them on lets the person feel one');
    });

    test('the setting and the breathing pace are kept, and odd saved values fall back safely', () {
      final s = Settings.fromJson((Settings()
            ..haptics = false
            ..breathsPerMinute = 8)
          .toJson());
      expect((s.haptics, s.breathsPerMinute), (false, 8));
      expect(Settings().haptics, isTrue);
      expect(Settings().breathsPerMinute, 6);
      expect(Settings.fromJson({'breaths_per_minute': 30}).breathsPerMinute, mostBreaths);
      expect(Settings.fromJson({'breaths_per_minute': 1}).breathsPerMinute, fewestBreaths);
      expect(Settings.fromJson({'breaths_per_minute': 'fast', 'haptics': 'yes'}).breathsPerMinute, usualBreaths);
      expect(Settings.fromJson({}).haptics, isTrue);
    });
  });

  group('the breathing guide', () {
    Future<void> pacer(WidgetTester tester, AppState state, {List<(String, int)>? pattern}) async {
      await show(tester, state, Scaffold(body: Center(child: pattern == null
          ? BreathPacer(key: UniqueKey()) : BreathPacer(key: UniqueKey(), pattern: pattern))));
    }

    /// Let time pass in 20 ms frames, as a screen does (a phase ends on the first frame after its time), checking
    /// the phase named after each step.
    Future<void> breathe(WidgetTester tester, List<(int, String)> steps) async {
      for (final (ms, phase) in steps) {
        for (var t = 0; t < ms; t += 20) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.text(phase), findsOneWidget, reason: '$phase after $ms ms more');
      }
    }

    testWidgets('6 breaths a minute by default (4 seconds in, 6 out), 4 to 10 by the buttons, kept in Settings',
        (tester) async {
      final state = flow.makeState();
      await pacer(tester, state);
      expect(find.text('6 breaths a minute'), findsOneWidget);
      final start = tester.getSize(find.byKey(const Key('pacer_sphere')));
      await breathe(tester, [(3840, 'in'), (320, 'out'), (5680, 'out'), (320, 'in')]); // 4 in, 6 out
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getSize(find.byKey(const Key('pacer_sphere'))), isNot(start), reason: 'the sphere breathes');

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('pacer_faster')));
        await tester.pump();
      }
      expect(find.text('10 breaths a minute'), findsOneWidget, reason: 'no faster than 10');
      expect(state.data.settings.breathsPerMinute, 10);
      await pacer(tester, state); // a new practice at the kept pace: 6 seconds a breath, 2.4 in and 3.6 out
      await breathe(tester, [(2280, 'in'), (240, 'out'), (3360, 'out'), (240, 'in')]);

      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(const Key('pacer_slower')));
        await tester.pump();
      }
      expect(find.text('4 breaths a minute'), findsOneWidget, reason: 'no slower than 4');
      expect(state.data.settings.breathsPerMinute, 4);
      await pacer(tester, state); // 15 seconds a breath: 6 in, 9 out
      await breathe(tester, [(5880, 'in'), (240, 'out')]);
    });

    testWidgets("a practice's own shape is stretched to the pace: the sigh's two sips and long breath out",
        (tester) async {
      await pacer(tester, flow.makeState(), pattern: const [('in', 2), ('and in again', 1), ('slowly out', 6)]);
      // 6 a minute: 10 seconds a breath, so 2.2 in, 1.1 in again, 6.7 out
      await breathe(tester, [(2100, 'in'), (240, 'and in again'), (880, 'and in again'), (240, 'slowly out'),
          (6420, 'slowly out'), (240, 'in')]);
    });

    testWidgets('with less motion the sphere keeps one size and a countdown names the phase, at the same pace',
        (tester) async {
      // Android's Remove animations, which also runs ordinary animations twenty times faster
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pacer(tester, flow.makeState());
      final size = tester.getSize(find.byKey(const Key('pacer_sphere')));
      String count() => tester.widget<Text>(find.byKey(const Key('pacer_count'))).data!;
      expect((find.text('in').evaluate().length, count()), (1, '4'));
      await breathe(tester, [(1500, 'in')]);
      expect(count(), '3');
      await breathe(tester, [(2600, 'out')]);
      expect(count(), '6');
      expect(tester.getSize(find.byKey(const Key('pacer_sphere'))), size, reason: 'no scaling with less motion');
    });
  });

  group('calm motion', () {
    test('the springs end exactly, the calm one never overshoots, the moving one by under half a percent', () {
      for (final c in [Calm.curve, Calm.spatial]) {
        expect((c.transform(0), c.transform(1)), (0.0, 1.0));
      }
      var last = 0.0, peak = 0.0;
      for (var i = 1; i < 100; i++) {
        final x = Calm.curve.transform(i / 100);
        expect(x, greaterThanOrEqualTo(last));
        expect(x, lessThanOrEqualTo(1.0));
        last = x;
        peak = Calm.spatial.transform(i / 100) > peak ? Calm.spatial.transform(i / 100) : peak;
      }
      expect(peak, lessThan(1.005));
      expect(Calm.curve.transform(0.5), greaterThan(0.75), reason: 'it eases out: most of the way by half time');
    });

    testWidgets('with less motion a sheet is there at once; otherwise it rises on the spring', (tester) async {
      Future<double> topAfterOneFrame() async {
        await show(tester, flow.makeState(), Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
            onPressed: () => showCrisisSheet(context), child: const Text('Open'))))));
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final top = tester.getTopLeft(find.byType(CrisisSheet)).dy;
        await tester.pumpAndSettle();
        final rest = tester.getTopLeft(find.byType(CrisisSheet)).dy;
        Navigator.of(tester.element(find.byType(CrisisSheet))).pop();
        await tester.pumpAndSettle();
        return top - rest; // how far it still had to go after one frame
      }

      expect(await topAfterOneFrame(), greaterThan(50), reason: 'with motion, the sheet is still rising');
      // the iPhone's Reduce Motion, which Flutter reports apart from Android's Remove animations
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      expect(await topAfterOneFrame(), 0, reason: 'with less motion, the sheet is in place at once');
    });
  });
}
