// The quiet timer, the soundscapes and the sleep wind-down, driven the way a person uses them, with a clock the test
// moves and a silent player that remembers what it was asked: the bells ring at the right times, pause holds the time
// and the bells, ending early rings nothing, the soundscape fades after the end, the wind-down fades to silence and
// rings nothing, and Reduce Motion leaves just the numbers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/screen_awake.dart';
import 'package:solace/core/sound_player.dart';
import 'package:solace/core/soundscape.dart';
import 'package:solace/ui/soundscapes.dart';
import 'package:solace/ui/theme.dart';
import 'package:solace/ui/timer.dart';

import 'app_flow_test.dart' as flow;

late DateTime now;

Future<void> pumpScreen(WidgetTester tester, AppState state, Widget screen, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!),
      home: screen)));
  await tester.pumpAndSettle();
}

/// Let [d] pass on the test's clock, a quarter of a second at a time, as the timer's ticks do.
Future<void> advance(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 250);
  for (var t = Duration.zero; t < d; t += step) {
    now = now.add(step);
    await tester.pump(step);
  }
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

int count(SilentSoundPlayer p, String event) => p.events.where((e) => e == event).length;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    SoundPlayer.create = SilentSoundPlayer.new; // nothing in these tests touches real audio
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  setUp(() => now = DateTime(2026, 11, 14, 7));

  testWidgets('the Practices tab offers the timer, the soundscapes and the wind-down', (tester) async {
    await flow.pumpApp(tester, flow.makeState(demo: true));
    await tester.tap(find.text('Practices'));
    await tester.pumpAndSettle();
    expect(find.text('Silence and sound'), findsNothing, reason: 'below the first screen, which keeps its screenshot');
    for (final (key, shows) in [('open_timer', 'sit_len_10'), ('open_soundscapes', 'scape_rain'),
        ('open_wind_down', 'wind_down_start')]) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 300, scrollable: find.byType(Scrollable).first);
      await flow.tapIn(tester, find.byKey(Key(key)));
      expect(find.byKey(Key(shows)), findsOneWidget);
      if (key == 'open_wind_down') {
        expect(tester.getRect(find.byKey(const Key('wind_down_start'))).bottom, lessThan(851),
            reason: 'opened from the wind-down card, the wind-down is brought into view');
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('interval bells ring on time, pause holds the time and the bells, then the ending bell', (tester) async {
    final state = flow.makeState();
    final sounds = SilentSoundPlayer();
    await pumpScreen(tester, state, TimerScreen(sounds: sounds, clock: () => now));
    await tap(tester, 'sit_len_5');
    await tap(tester, 'sit_every_1');
    await tap(tester, 'sit_scape_rain');
    await tap(tester, 'timer_begin');
    expect(sounds.events, ['bell start', 'loop rain']);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.byKey(const Key('timer_ring')), findsOneWidget);
    final s = state.data.settings;
    expect((s.sitMinutes, s.sitInterval, s.sitScape, s.sitStartBell, s.sitEndBell), (5, 1, 'rain', true, true),
        reason: 'the choices are kept for next time');

    await advance(tester, const Duration(seconds: 59));
    expect(count(sounds, 'bell interval'), 0);
    expect(find.text('4:01'), findsOneWidget);
    await advance(tester, const Duration(seconds: 1));
    expect(count(sounds, 'bell interval'), 1, reason: 'one minute in');

    await advance(tester, const Duration(seconds: 30));
    await tap(tester, 'timer_pause');
    expect(sounds.events.last, 'pause');
    expect(find.text('Paused'), findsOneWidget);
    await advance(tester, const Duration(minutes: 3)); // a long pause: the time and the bells wait
    expect(find.text('3:30'), findsOneWidget);
    expect(count(sounds, 'bell interval'), 1);
    await tap(tester, 'timer_resume');
    expect(sounds.events.last, 'resume');

    // sat 90 s so far: the next bells at 120, 180 and 240 s, and the ending bell at 300 s
    var sat = const Duration(seconds: 90);
    for (final (at, bells) in [(119, 1), (120, 2), (179, 2), (180, 3), (239, 3), (240, 4), (299, 4)]) {
      await advance(tester, Duration(seconds: at) - sat);
      sat = Duration(seconds: at);
      expect(count(sounds, 'bell interval'), bells, reason: 'at $at seconds');
      expect(count(sounds, 'bell end'), 0);
    }
    await advance(tester, const Duration(seconds: 1));
    expect(count(sounds, 'bell interval'), 4, reason: 'never one at the very end');
    expect(count(sounds, 'bell end'), 1);
    expect(find.text('That was your 5 minutes.'), findsOneWidget);
    expect(find.byKey(const Key('timer_done')), findsOneWidget);
    // the soundscape fades away over five seconds, then stops
    expect(sounds.events, isNot(contains('stop')));
    await advance(tester, const Duration(seconds: 3));
    expect(sounds.lastVolume, lessThan(s.scapeVolume));
    await advance(tester, const Duration(seconds: 3));
    expect(sounds.events.last, 'stop');
    await advance(tester, const Duration(minutes: 5));
    expect(count(sounds, 'bell end'), 1, reason: 'the ending bell rings once');
    await tester.pumpAndSettle(); // nothing is counting any more
  });

  testWidgets('ending early rings no bell and says how long you sat', (tester) async {
    final sounds = SilentSoundPlayer();
    await pumpScreen(tester, flow.makeState(), TimerScreen(sounds: sounds, clock: () => now));
    await tap(tester, 'sit_len_10');
    await tap(tester, 'sit_every_0');
    await tap(tester, 'sit_scape_none');
    await tap(tester, 'timer_begin');
    await advance(tester, const Duration(minutes: 3, seconds: 10));
    await tap(tester, 'timer_end');
    expect(find.text('You sat for 3 minutes.'), findsOneWidget);
    await advance(tester, const Duration(minutes: 10));
    expect(sounds.events, ['bell start'], reason: 'no ending bell, no soundscape');
  });

  testWidgets('bells can be turned off', (tester) async {
    final sounds = SilentSoundPlayer();
    await pumpScreen(tester, flow.makeState(), TimerScreen(sounds: sounds, clock: () => now));
    await tap(tester, 'sit_len_3');
    await tap(tester, 'sit_start_bell');
    await tap(tester, 'sit_end_bell');
    await tap(tester, 'timer_begin');
    await advance(tester, const Duration(minutes: 3, seconds: 1));
    expect(find.text('That was your 3 minutes.'), findsOneWidget);
    expect(sounds.events, isEmpty);
  });

  testWidgets('Reduce Motion: no ring, just the numbers', (tester) async {
    await pumpScreen(tester, flow.makeState(), TimerScreen(sounds: SilentSoundPlayer(), clock: () => now),
        reduceMotion: true);
    await tap(tester, 'sit_len_5');
    await tap(tester, 'timer_begin');
    expect(find.byKey(const Key('timer_ring')), findsNothing);
    expect(find.text('5:00'), findsOneWidget);
    await advance(tester, const Duration(seconds: 2));
    expect(find.text('4:58'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // closes the screen, which stops its ticking
  });

  testWidgets('your own length, and interval bells only inside the sit', (tester) async {
    await pumpScreen(tester, flow.makeState(), TimerScreen(sounds: SilentSoundPlayer(), clock: () => now));
    await tap(tester, 'sit_len_3');
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('sit_every_5'))).onSelected, isNull);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('sit_every_2'))).onSelected, isNotNull);
    await tap(tester, 'sit_len_custom');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sit_custom_more')));
    await tester.tap(find.byKey(const Key('sit_custom_more')));
    await tester.pump();
    expect(find.text('5 minutes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sit_custom_less')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sit_custom_done')));
    await tester.pumpAndSettle();
    expect(find.text('4 min, your own'), findsOneWidget);
    expect(find.text('Begin, 4 minutes'), findsOneWidget);
  });

  testWidgets('soundscapes: one at a time, tap again to stop, the volume follows the slider', (tester) async {
    final state = flow.makeState();
    final sounds = SilentSoundPlayer();
    await pumpScreen(tester, state, SoundscapesScreen(sounds: sounds, clock: () => now));
    await tap(tester, 'scape_ocean');
    await tester.pump();
    expect(sounds.events, ['loop ocean']);
    expect(find.text('Playing'), findsOneWidget);
    expect(state.data.settings.scape, 'ocean');
    await tap(tester, 'scape_fire');
    await tester.pump();
    expect(sounds.events.last, 'loop fire');
    expect(find.text('Playing'), findsOneWidget);
    await tester.drag(find.descendant(of: find.byKey(const Key('scape_volume')), matching: find.byType(Slider)),
        const Offset(-80, 0));
    await tester.pump();
    expect(sounds.lastVolume, lessThan(0.6));
    expect(state.data.settings.scapeVolume, sounds.lastVolume, reason: 'kept when the slider is let go');
    await tap(tester, 'scape_fire');
    expect(sounds.events.last, 'stop');
    expect(find.text('Playing'), findsNothing);
  });

  testWidgets('the wind-down: steady, then a fade to silence, a dimmed screen, and no bell', (tester) async {
    final state = flow.makeState();
    final sounds = SilentSoundPlayer();
    await pumpScreen(tester, state, SoundscapesScreen(sounds: sounds, clock: () => now));
    await tap(tester, 'scape_rain');
    await tester.pump();
    await tap(tester, 'wind_down_15');
    await tap(tester, 'wind_down_start');
    await tester.pumpAndSettle();
    expect(state.data.settings.windDownMinutes, 15);
    expect(sounds.events, ['loop rain', 'stop', 'loop rain']);
    expect(find.text('Rest now. Let the sound carry you.'), findsOneWidget);
    double opacity() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 1);
    Future<void> wait(Duration d) async { // the clock jumps; the screen ticks once a second
      for (var t = Duration.zero; t < d; t += const Duration(seconds: 30)) {
        now = now.add(const Duration(seconds: 30));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    await wait(const Duration(seconds: 30));
    expect(opacity(), lessThan(0.5), reason: 'dims after ten seconds without a touch');
    await tester.tap(find.byKey(const Key('wind_down_stop')), warnIfMissed: false); // dim: the button is not reached
    await tester.pump();
    expect(opacity(), 1, reason: 'the first touch only wakes the screen');
    expect(find.byKey(const Key('wind_down_stop')), findsOneWidget);
    await wait(const Duration(minutes: 9, seconds: 30)); // ten minutes in: still steady
    expect(sounds.lastVolume, 0.6);
    await wait(const Duration(seconds: 150)); // half way through the five-minute fade
    expect(sounds.lastVolume, closeTo(0.3, 0.02));
    await wait(const Duration(seconds: 150));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds.events.last, 'stop');
    expect(find.text('Sleep well.'), findsOneWidget);
    expect(sounds.events.where((e) => e.startsWith('bell')), isEmpty, reason: 'it ends silently');
    await tester.pump(const Duration(seconds: 5));
    expect(sounds.events.last, 'stop', reason: 'nothing more after the end');
  });

  group('the screen stays on only while a sit or the wind-down runs', () {
    late List<Object?> calls;
    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ScreenAwake.channel,
          (call) async {
        if (call.method == 'setKeepAwake') calls.add(call.arguments);
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenAwake.channel, null));

    testWidgets('the timer: on at Begin, off when it ends early or the screen closes', (tester) async {
      final state = flow.makeState();
      await pumpScreen(tester, state, TimerScreen(sounds: SilentSoundPlayer(), clock: () => now));
      await tap(tester, 'sit_len_5');
      await tap(tester, 'sit_scape_rain');
      expect(calls, isEmpty, reason: 'choosing a length does not hold the screen');
      await tap(tester, 'timer_begin');
      expect(calls, [true]);
      expect(ScreenAwake.holds, 1);
      await advance(tester, const Duration(seconds: 5));
      await tap(tester, 'timer_end');
      expect(calls, [true, false]);
      expect(ScreenAwake.holds, 0);
      await tester.pumpWidget(const SizedBox());
      expect(calls, [true, false], reason: 'released once, not twice');
    });

    testWidgets('the timer: off by itself when the time is up', (tester) async {
      final state = flow.makeState();
      await pumpScreen(tester, state, TimerScreen(sounds: SilentSoundPlayer(), clock: () => now));
      await tap(tester, 'sit_len_3');
      await tap(tester, 'sit_scape_rain');
      await tap(tester, 'timer_begin');
      await advance(tester, const Duration(minutes: 3, seconds: 8));
      expect(calls, [true, false]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the wind-down: on while it plays, off when it has faded out', (tester) async {
      final state = flow.makeState();
      await pumpScreen(tester, state, WindDownScreen(scape: soundscapes.first, minutes: 15, volume: 0.6,
          sounds: SilentSoundPlayer(), clock: () => now));
      expect(calls, [true]);
      await advance(tester, const Duration(minutes: 15, seconds: 1));
      expect(calls, [true, false]);
      await tester.pumpWidget(const SizedBox());
      expect(ScreenAwake.holds, 0);
    });
  });
}
