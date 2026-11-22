// The traffic test (security review 2026-11-14, AIR-3). The real app, started by its own main() (the real encrypted
// store and keychain, reminders, window and loaders, the stand-in model), is driven through its main flows: the
// first-run steps, a typed session ended and saved, the quiet timer with a soundscape, a soundscape alone, Settings
// with Appearance and Privacy, search, and every tab. The test only drives and checks the screens; the proof is
// recorded outside the app by tools/traffic/ (lsof, nettop and the unified log on the Mac and in the Simulator,
// strace and a network namespace on Linux, the app's uid on Android). Two ways to run it:
//   with the test harness (debug): flutter test integration_test/traffic_test.dart -d <device>
//     The harness talks to the Dart VM service on a localhost port; that socket is the harness's, not the app's.
//   alone (release, no harness, no VM service, so any socket at all is the app's):
//     flutter build <platform> --release -t integration_test/traffic_test.dart --dart-define=TRAFFIC_EXIT=true
//     and start the built app by itself. It quits when done (exit code 0 only if every flow passed).
// Each step prints "TRAFFIC STEP <name> <UTC time>" so socket samples line up with what the app was doing; at the end
// it prints "TRAFFIC FLOWS DONE" (or "TRAFFIC FLOWS FAILED") and writes traffic_result.json to the support folder.
// Options: --dart-define=TRAFFIC_IDLE=<seconds> keeps the app open and idle after the flows; TINY_GGUF=<path> also
// loads a small GGUF through the app's llama.cpp runtime (llamadart, the shipped library that carries network code)
// and generates a few words, so that library runs while sockets are watched.
// AIR-3 (2026-11-16): right after start it also checks the app's own network guards (core/network_guard.dart: a web
// client and an internet socket are refused inside the app, before any socket exists), and on Linux, in a release
// build, the operating system's block (linux/runner/net_block.h): libc's socket(AF_INET, SOCK_STREAM, 0) must fail
// with EACCES. That one refused attempt is the only internet socket call the strace checker accepts
// (tools/traffic/check_strace.py --refused-probes 1).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:solace/core/llama_model.dart';
import 'package:solace/core/network_guard.dart';
import 'package:solace/main.dart' as app;

const exitWhenDone = bool.fromEnvironment('TRAFFIC_EXIT');
const idleSeconds = int.fromEnvironment('TRAFFIC_IDLE');
const tinyModel = String.fromEnvironment('TINY_GGUF');

final steps = <Map<String, String>>[];
final notes = <String, String>{};
var flowsDone = false;
String? failure;

void step(String name, [String detail = '']) {
  final at = DateTime.now().toUtc().toIso8601String();
  steps.add({'step': name, 'at': at, if (detail.isNotEmpty) 'detail': detail});
  // ignore: avoid_print
  print('TRAFFIC STEP $name $at${detail.isEmpty ? '' : ' $detail'}');
}

/// Real frames for [ms] milliseconds (the app has endless calm animations, so nothing here waits to "settle").
Future<void> frames(WidgetTester tester, {int ms = 600}) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool showing(Finder f) => f.evaluate().isNotEmpty;

/// What is on the screen now (keys and texts), for a failure message that says where the app was.
String onScreen() {
  final keys = <String>{}, texts = <String>{};
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String>).evaluate()) {
    keys.add((e.widget.key! as ValueKey<String>).value);
  }
  for (final e in find.byType(Text).evaluate()) {
    final d = (e.widget as Text).data;
    if (d != null && d.trim().isNotEmpty) texts.add(d.length > 40 ? '${d.substring(0, 40)}...' : d);
  }
  return 'keys on screen: ${keys.take(40).join(', ')}; texts: ${texts.take(25).join(' / ')}';
}

Future<void> waitFor(WidgetTester tester, Finder f, {int seconds = 30}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!showing(f)) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out after $seconds s waiting for $f; ${onScreen()}');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> waitUntil(WidgetTester tester, bool Function() ok, String what, {int seconds = 30}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  bool check() {
    try {
      return ok();
    } catch (_) {
      return false; // what it looks at is not on the screen yet
    }
  }
  while (!check()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out after $seconds s waiting for $what');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// The first of [options] to appear, by its index.
Future<int> waitForAny(WidgetTester tester, List<Finder> options, {int seconds = 30}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (true) {
    for (final (i, f) in options.indexed) {
      if (showing(f)) return i;
    }
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out after $seconds s waiting for any of $options; on screen: ${onScreen()}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

final _vertical = find.byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical);

/// Scrolls the page's main list until [f] is built, then brings it into view.
Future<void> reveal(WidgetTester tester, Finder f) async {
  // down the page first, then back up past the top, so it is found wherever the list was left
  for (final (tries, dy) in [(15, -250.0), (40, 250.0)]) {
    for (var i = 0; i < tries && !showing(f) && showing(_vertical); i++) {
      await tester.drag(_vertical.first, Offset(0, dy), warnIfMissed: false);
      await frames(tester, ms: 300);
    }
  }
  await waitFor(tester, f, seconds: 5);
  await tester.ensureVisible(f.first);
  await frames(tester, ms: 500);
}

Future<void> tapOn(WidgetTester tester, Finder f, {int seconds = 30, bool scroll = false}) async {
  if (scroll) {
    await reveal(tester, f);
  } else {
    await waitFor(tester, f, seconds: seconds);
    await tester.ensureVisible(f.first);
    await frames(tester, ms: 400);
  }
  await tester.tap(f.first, warnIfMissed: false);
  await frames(tester, ms: 900);
}

/// Types into a text box: a tap focuses it (the device's keyboard opens), then the text goes in through the box's own
/// controller and change callback. tester.enterText cannot be used here: it sends the text as client -1, which Flutter
/// accepts only when asserts are on, so in a release build the text would never arrive.
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  await tapOn(tester, field);
  final box = tester.widget<TextField>(field.first);
  if (box.controller != null) {
    box.controller!.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
  box.onChanged?.call(text);
  await frames(tester, ms: 500);
  expect(box.controller == null || box.controller!.text == text, isTrue, reason: 'the text is in the box');
}

Future<void> back(WidgetTester tester) async {
  await tester.pageBack();
  await frames(tester, ms: 900);
}

/// AIR-3: the app's own guards, installed by app.main(), refuse a web client and an internet socket before any socket
/// is made. (Were a guard missing, the connection tried is to this device's own discard port, never off it.)
Future<String> checkGuards() async {
  var web = false, connect = false;
  try {
    HttpClient();
  } on NetworkRefused {
    web = true;
  }
  try {
    (await Socket.connect(InternetAddress.loopbackIPv4, 9, timeout: const Duration(seconds: 2))).destroy();
  } on NetworkRefused {
    connect = true;
  } catch (_) {}
  final said = 'web client ${web ? 'refused' : 'NOT REFUSED'}, internet socket ${connect ? 'refused' : 'NOT REFUSED'}';
  notes['guards'] = said;
  if (!web || !connect) throw TestFailure('the in-app network guards did not refuse: $said');
  return said;
}

/// Linux, AIR-3: libc's socket(AF_INET, SOCK_STREAM, 0) from inside the app, past every Dart guard, so only the
/// operating system's block (linux/runner/net_block.h) can refuse it. Returns the descriptor (closed at once, unused,
/// if one were ever made) and errno.
(int, int) inetSocketFromLibc() {
  final libc = DynamicLibrary.open('libc.so.6');
  final open = libc.lookupFunction<Int32 Function(Int32, Int32, Int32), int Function(int, int, int)>('socket',
      isLeaf: true);
  final errnoAt = libc.lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>('__errno_location',
      isLeaf: true);
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close', isLeaf: true);
  // errno is read by a second call, so that call is made once first: its first run (its stub being set up) could
  // itself change errno between the socket call and the read
  final errno = errnoAt()..value = 0;
  final fd = open(2, 1, 0); // AF_INET, SOCK_STREAM, the default protocol
  final err = fd < 0 ? errno.value : 0;
  if (fd >= 0) close(fd);
  return (fd, err);
}

Future<void> writeResult() async {
  final result = {
    'flows_done': flowsDone,
    'failure': failure,
    'platform': Platform.operatingSystem,
    'mode': kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug',
    'pid': pid,
    'steps': steps,
    'notes': notes,
  };
  try {
    final dir = await getApplicationSupportDirectory();
    await File('${dir.path}/traffic_result.json').writeAsString(const JsonEncoder.withIndent(' ').convert(result));
    notes['result_file'] = '${dir.path}/traffic_result.json';
  } catch (e) {
    notes['result_file'] = 'not written: $e';
  }
  // ignore: avoid_print
  print(flowsDone ? 'TRAFFIC FLOWS DONE ${jsonEncode(notes)}' : 'TRAFFIC FLOWS FAILED: $failure');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() async {
    await writeResult();
    if (exitWhenDone) Timer(const Duration(seconds: 3), () => exit(flowsDone ? 0 : 1));
  });

  testWidgets('the real app through its main flows, for the traffic recorders', (tester) async {
    // app.main() installs the app's own last-resort error handlers (core/error_log.dart); the test framework checks at
    // the end of a test that its own FlutterError.onError is back, and in a debug build (the only mode the iPhone
    // Simulator runs) the run otherwise ended in a failed assertion and never wrote its result or quit (2026-11-14)
    final testOnError = FlutterError.onError;
    final platformOnError = PlatformDispatcher.instance.onError;
    try {
      step('start', 'pid $pid');
      await app.main();
      await frames(tester, ms: 2000);

      // ---- AIR-3: the network blocks, as the running app meets them ----
      step('network_guards', await checkGuards());
      if (Platform.isLinux) {
        final env = Platform.environment['SOLACE_NET_BLOCK'] ?? 'unset';
        if (kReleaseMode) {
          final (fd, err) = inetSocketFromLibc();
          notes['linux_net_block'] = 'SOLACE_NET_BLOCK=$env; internet socket '
              '${fd < 0 ? 'refused, errno $err' : 'MADE (closed at once, unused)'}';
          step('linux_net_block', notes['linux_net_block']!);
          if (env != 'on' || fd >= 0 || err != 13) {
            throw TestFailure('the Linux network block is not on: ${notes['linux_net_block']}');
          }
        } else {
          notes['linux_net_block'] = 'SOLACE_NET_BLOCK=$env (a debug or profile build: the block is set in release '
              'builds only)';
          step('linux_net_block', notes['linux_net_block']!);
        }
      }

      // ---- Linux: the passphrase that unlocks the data key comes first (OW-M9-1; L-13: the flows stopped here) ----
      var first = await waitForAny(tester, [find.byKey(const Key('onb_next')), find.byKey(const Key('tab_You')),
          find.textContaining('could not open your saved data'), find.byKey(const Key('pass_first'))], seconds: 60);
      if (first == 3) {
        step('passphrase');
        const phrase = String.fromEnvironment('TRAFFIC_PASSPHRASE', defaultValue: 'traffic test passphrase');
        await typeInto(tester, find.byKey(const Key('pass_first')), phrase); // enterText cannot reach a real app here
        if (find.byKey(const Key('pass_second')).evaluate().isNotEmpty) {
          await typeInto(tester, find.byKey(const Key('pass_second')), phrase); // the first start: chosen twice
        }
        await tapOn(tester, find.byKey(const Key('pass_go')));
        first = await waitForAny(tester, [find.byKey(const Key('onb_next')), find.byKey(const Key('tab_You')),
            find.textContaining('could not open your saved data')], seconds: 90);
      }
      if (first == 2) throw TestFailure('the app could not open its data store on this device (recovery screen)');
      if (first == 0) {
        step('first_run');
        await tapOn(tester, find.byKey(const Key('onb_next'))); // welcome
        await tapOn(tester, find.byKey(const Key('onb_next'))); // private by design
        await tapOn(tester, find.byKey(const Key('onb_understand'))); // what Solace is and is not
        await tapOn(tester, find.byKey(const Key('onb_country')));
        await tapOn(tester, find.text('Ireland').last);
        await tapOn(tester, find.byKey(const Key('onb_next'))); // country
        await tapOn(tester, find.byKey(const Key('onb_adult')));
        await tapOn(tester, find.byKey(const Key('onb_next'))); // look and voice
        // the model files step (MM-01, 16 Nov): skipped, so the stand-in answers; an older build has no such step
        if (await waitForAny(tester, [find.byKey(const Key('onb_model_skip')), find.byKey(const Key('onb_finish'))]) == 0) {
          await tapOn(tester, find.byKey(const Key('onb_model_skip')));
        }
        await tapOn(tester, find.byKey(const Key('onb_finish'))); // the lock: not now
      } else {
        step('already_set_up');
      }
      await waitFor(tester, find.byKey(const Key('tab_You')), seconds: 20);
      step('home');
      await frames(tester, ms: 1500);

      // ---- a typed session with the stand-in model, ended and saved ----
      step('session_start');
      await tapOn(tester, find.text('Start'), scroll: true);
      if (await waitForAny(tester, [find.byType(TextField), find.text('Skip the check-in')]) == 1) {
        await tapOn(tester, find.text('Skip the check-in'), scroll: true);
      }
      // the opening line has finished when Send can be pressed
      await waitUntil(tester, () => tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Send'),
          matching: find.byType(IconButton)).first).onPressed != null, 'the opening line to finish');
      await frames(tester, ms: 1000);
      await typeInto(tester, find.byType(TextField), 'This week I went for a walk twice and slept a little better.');
      await tapOn(tester, find.byTooltip('Send'));
      await waitFor(tester, find.textContaining('Stand-in reply', findRichText: true), seconds: 30);
      step('session_reply');
      await frames(tester, ms: 1500);
      await tapOn(tester, find.widgetWithText(TextButton, 'End'));
      await tapOn(tester, find.byKey(const Key('end_confirm')), scroll: true);
      // the session is kept before its note; a note still being written offers Skip for now (16 Nov)
      if (await waitForAny(tester, [find.text('Session saved'), find.textContaining('Skip for now')], seconds: 120) == 1) {
        await tapOn(tester, find.textContaining('Skip for now').first);
      }
      await waitFor(tester, find.text('Session saved'), seconds: 60);
      step('session_saved');
      await tapOn(tester, find.widgetWithText(FilledButton, 'Done'), scroll: true);
      await waitFor(tester, find.byKey(const Key('tab_You')), seconds: 20);

      // ---- the quiet timer with a soundscape underneath, then a soundscape alone ----
      step('timer');
      await tapOn(tester, find.byKey(const Key('tab_Practices')));
      await tapOn(tester, find.byKey(const Key('open_timer')), scroll: true);
      await tapOn(tester, find.byKey(const Key('sit_len_3')), scroll: true);
      await tapOn(tester, find.byKey(const Key('sit_scape_rain')), scroll: true);
      await tapOn(tester, find.byKey(const Key('timer_begin')), scroll: true);
      await waitFor(tester, find.byKey(const Key('timer_end')));
      await frames(tester, ms: 20000); // the sound is made on the device, then plays
      notes['timer_sound'] = showing(find.text('The sound could not play on this device'))
          ? 'could not play on this device' : 'rain playing';
      step('timer_running', notes['timer_sound']!);
      await tapOn(tester, find.byKey(const Key('timer_end')));
      await tapOn(tester, find.byKey(const Key('timer_done')));
      step('soundscape');
      await tapOn(tester, find.byKey(const Key('open_soundscapes')), scroll: true);
      await tapOn(tester, find.byKey(const Key('scape_ocean')), scroll: true);
      await frames(tester, ms: 10000);
      notes['soundscape'] = showing(find.text('Playing')) ? 'playing' : 'not playing';
      step('soundscape_running', notes['soundscape']!);
      await tapOn(tester, find.byKey(const Key('scape_ocean')), scroll: true); // tap again to stop
      await back(tester);

      // ---- Settings: haptics, Appearance (dark, then the device's), Privacy ----
      step('settings');
      // a computer-sized window has Settings in the sidebar; a phone-sized one in each tab's top bar (16 Nov)
      if (showing(find.byKey(const Key('rail_settings')))) {
        await tapOn(tester, find.byKey(const Key('rail_settings')));
      } else {
        await tapOn(tester, find.byKey(const Key('tab_You')));
        await tapOn(tester, find.byTooltip('Settings'));
      }
      await tapOn(tester, find.byKey(const Key('haptics_switch')), scroll: true);
      await tapOn(tester, find.byKey(const Key('haptics_switch')), scroll: true);
      await tapOn(tester, find.byKey(const Key('open_appearance')), scroll: true);
      await tapOn(tester, find.text('Dark'));
      await frames(tester, ms: 1500);
      await tapOn(tester, find.text('Device'));
      await back(tester);
      await tapOn(tester, find.byKey(const Key('open_privacy')), scroll: true);
      await frames(tester, ms: 1500);
      await back(tester);
      await back(tester);

      // ---- search, then every tab ----
      step('search');
      if (!showing(find.byTooltip('Search your sessions'))) await tapOn(tester, find.byKey(const Key('tab_You')));
      await tapOn(tester, find.byTooltip('Search your sessions'));
      await typeInto(tester, find.byType(TextField), 'walk');
      await frames(tester, ms: 2000);
      await back(tester);
      step('tabs');
      for (final tab in ['Talk', 'Progress', 'Practices', 'Today']) {
        await tapOn(tester, find.byKey(Key('tab_$tab')));
        await frames(tester, ms: 1500);
      }

      // ---- optionally, the llama.cpp runtime itself on a small model ----
      if (tinyModel.isNotEmpty) {
        step('tiny_model_load', tinyModel.split('/').last);
        final runtime = await LlamaModelRuntime.load(ModelFile(File(tinyModel), ''), contextSize: 2048);
        final said = await runtime.generate([
          {'role': 'system', 'content': 'You are a kind, brief assistant.'},
          {'role': 'user', 'content': 'Say hello in one short sentence.'},
        ], maxTokens: 24).join();
        await runtime.dispose();
        notes['tiny_model'] = said.trim();
        step('tiny_model_said', '${said.trim().length} characters');
      }

      if (idleSeconds > 0) {
        step('idle', '$idleSeconds s');
        await frames(tester, ms: idleSeconds * 1000);
      }
      if (showing(find.text('Your last change could not be saved'))) {
        throw TestFailure('a save failed during the flows: ${notes['save'] = 'failed'}');
      }
      step('end');
      flowsDone = true;
    } catch (e) {
      failure = '$e'.split('\n').take(6).join(' | ');
      step('failed', failure!);
      rethrow;
    } finally {
      FlutterError.onError = testOnError;
      PlatformDispatcher.instance.onError = platformOnError;
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
