// Review cycle 1, conversation flows and data (D4 to D8, I3): a session is never open while a transfer or Delete
// everything replaces its data; distress sent during a reply pauses trauma work at once, and the call (which has no
// exercise Stop) is not offered there; nothing typed, kept or heard is lost after Edit or while Solace replies; a
// classifier that never answers never holds the session busy for good; and a safety question that comes after the
// person has left is asked at the next session. Every test drives the app's real code.
//
// The tests use only what the app had before these fixes, so each one can be run against the earlier code too.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/safety.dart' show SafetyLevel;
import 'package:solace/core/formats.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/core/voice.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/check_in.dart';
import 'package:solace/ui/desktop.dart';
import 'package:solace/ui/theme.dart';
import 'package:solace/ui/transfer_screen.dart';

final prompts = Prompts(
  system: File('assets/prompts/app_system_$appPromptVersion.txt').readAsStringSync(),
  note: File('assets/prompts/app_note_$appPromptVersion.txt').readAsStringSync(),
  story: File('assets/prompts/app_story_$appPromptVersion.txt').readAsStringSync(),
  split: File('assets/prompts/app_split_v1.txt').readAsStringSync(),
);
final library = parseLibrary(File('assets/practices/library_v2.json').readAsStringSync());
const crisisSentence = 'I want to kill myself tonight.';
const stopWords = 'Stop. I want to stop.';

/// A clock the test moves on by hand.
class Clock {
  DateTime now = DateTime(2026, 11, 14, 20);
  void pass(Duration d) => now = now.add(d);
}

/// Answers at once until [hold]: then a reply writes its first sentence and waits for [release] (or a stop).
class StepModel extends StandInModel implements ReplyCanceller {
  Completer<void>? _gate;
  bool silent = false; // held before her first words
  int cancels = 0;
  void hold({bool beforeWords = false}) {
    _gate = Completer<void>();
    silent = beforeWords;
  }

  void release() {
    if (!(_gate?.isCompleted ?? true)) _gate!.complete();
  }

  @override
  void cancelReply() {
    cancels++;
    release();
  }

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    final g = _gate;
    if (g == null || g.isCompleted) {
      yield* super.generate(messages, maxTokens: maxTokens);
      return;
    }
    if (!silent) yield 'That sounds really hard, thank you for telling me. ';
    await g.future;
    yield 'Tell me more about it.';
  }
}

/// A classifier the test answers by hand, one message at a time.
class HeldClassifier {
  final verdicts = <Completer<bool>>[];
  String? _last;
  Future<bool> check(String context, String text) {
    // the first message's second reading on its own (round 5 review, D-02) is answered at once and quietly, so each
    // test here still answers one verdict per message by hand
    if (context.isEmpty && text == _last) return Future.value(false);
    _last = text;
    return (verdicts..add(Completer<bool>())).last.future;
  }
}

/// A voice that speaks at once and hears what the test gives it, one answer per listen.
class HearingVoice implements VoiceService {
  HearingVoice(this.heard);
  final List<String> heard;
  int listens = 0;
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<String?> listenOnce() async => listens < heard.length ? heard[listens++] : Completer<String?>().future;
}

AppState makeState({ModelRuntime? model, Vault? vault, AppData? data, Clock? clock}) {
  final d = data ?? AppData();
  d.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true;
  final c = clock ?? Clock();
  return AppState(data: d, vault: vault ?? MemoryVault(), prompts: prompts, model: model ?? StepModel(),
      library: library, clock: () => c.now);
}

SessionController session(AppData data, {ModelRuntime? model, Future<bool> Function(String, String)? riskCheck}) =>
    SessionController(model: model ?? StepModel(), prompts: prompts, data: data, vault: MemoryVault(),
        riskCheck: riskCheck, clock: () => DateTime(2026, 11, 14, 20));

Future<void> pumpChat(WidgetTester tester, AppState state, String kind) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: ChatScreen(kind: kind))));
  await tester.pumpAndSettle();
}

String box(WidgetTester tester, [Finder? f]) =>
    tester.widget<TextField>(f ?? find.byType(TextField)).controller!.text;

/// Let real time pass (the transfer file's key stretching runs on a worker) until [until] shows, or about 30 s.
Future<void> settleReal(WidgetTester tester, Finder until) async {
  for (var i = 0; i < 150 && until.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }
}

/// A real transfer file of [other], made on a worker as the other device would, and its code.
Future<(Uint8List, String)> transferFile(WidgetTester tester, AppData other) async {
  final code = TransferCode.generate();
  final file = await tester.runAsync(() => TransferFile.sealInBackground(other, code));
  return (file!, code);
}

/// Picks the file, types the code and taps Replace on the Receive screen; the file is then being opened.
Future<void> startReplace(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(const Key('transfer_pick')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('transfer_code')), code);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('transfer_open')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('transfer_replace')));
  await tester.pump();
  expect(find.text('Opening the file...'), findsOneWidget);
}

void main() {
  group('D4: a session is never open while a transfer or Delete everything replaces its data', () {
    test('a transfer is refused, with nothing changed, while a session is open; once it has gone, it comes in',
        () async {
      final vault = MemoryVault();
      final state = makeState(vault: vault, data: AppData()..journal.add({'date': '2026-11-10', 'text': 'OLD WORDS'}));
      final old = state.data;
      final s = state.newSession();
      await s.start('daily_checkin'); // a session open on a computer, or one opened while the file was being opened
      final incoming = AppData()..journal.add({'date': '2026-11-12', 'text': 'IMPORTED WORDS'});
      Object? refused;
      try {
        await state.receiveTransfer(incoming);
      } catch (e) {
        refused = e;
      }
      expect(refused, isA<TransferError>(), reason: 'the import replaced the data under an open session');
      expect((refused as TransferError).message, contains('End the conversation'));
      expect(state.data, same(old), reason: 'nothing changed');
      expect(vault.generation, 0, reason: 'no new generation: the session\'s saves are still kept');
      // the session goes on saving as before: a crisis record is kept at once, and End keeps the conversation
      await s.send(crisisSentence);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await vault.load()).safetyEvents, isNotEmpty);
      await s.end();
      expect((await vault.load()).sessions, hasLength(1));
      s.leave(); // its screen has gone
      await state.receiveTransfer(incoming);
      expect(state.data.journal.single['text'], 'IMPORTED WORDS');
    });

    test('Delete everything is refused, with nothing deleted or let go, while a session is open', () async {
      final vault = MemoryVault();
      final model = StepModel();
      final state = makeState(model: model, vault: vault,
          data: AppData()..journal.add({'date': '2026-11-10', 'text': 'PRIVATE WORDS'}));
      await state.save();
      final s = state.newSession();
      await s.start('daily_checkin');
      var folders = 0;
      Object? refused;
      try {
        await state.wipeEverything(folders: () async => folders++);
      } catch (e) {
        refused = e;
      }
      expect(refused, isNotNull, reason: 'everything was deleted under an open session');
      expect('$refused', contains('End the conversation'));
      expect(state.model, same(model), reason: 'the model was not let go');
      expect(folders, 0);
      expect(model.cancels, 0);
      expect((await vault.load()).journal.single['text'], 'PRIVATE WORDS');
      s.leave();
      await state.wipeEverything(folders: () async => folders++);
      expect(folders, 1);
      expect((await vault.load()).journal, isEmpty);
    });

    testWidgets('while the file is opened, Back waits and no session can start; then the file comes in',
        (tester) async {
      final state = makeState();
      final (file, code) = await transferFile(tester, AppData()..journal.add({'date': '2026-11-12', 'text': 'IMPORTED'}));
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
              ReceiveFromDeviceScreen(pick: () async => PickedTransfer.fromBytes(file)))),
              child: const Text('Settings')))))));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await startReplace(tester, code);
      await tester.binding.handlePopRoute(); // Back, the system's or the arrow's
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveFromDeviceScreen), findsOneWidget, reason: 'Back left the screen during the import');
      // a session started meanwhile (a Mac's File > Start today's session) does not start, so it holds no old data
      Object? refused;
      unawaited(state.newSession().start('daily_checkin').catchError((Object e) => refused = e));
      await tester.pump();
      expect(refused, isA<GateClosed>(), reason: 'a session started beside the import');
      await settleReal(tester, find.textContaining('Done.'));
      expect(state.data.journal.single['text'], 'IMPORTED');
      await tester.binding.handlePopRoute(); // and Back works again
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveFromDeviceScreen), findsNothing);
    });

    testWidgets('on a computer, the menus open no session and close nothing while the file is opened', (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final state = makeState();
      final (file, code) = await transferFile(tester, AppData()..journal.add({'date': '2026-11-12', 'text': 'IMPORTED'}));
      await tester.pumpWidget(TherapistApp(state: state));
      await tester.pumpAndSettle();
      unawaited(appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) =>
          ReceiveFromDeviceScreen(pick: () async => PickedTransfer.fromBytes(file)))));
      await tester.pumpAndSettle();
      await startReplace(tester, code);
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await press(LogicalKeyboardKey.keyN); // Start today's session
      expect(find.byType(CheckInScreen), findsNothing, reason: 'a session was opened over the import');
      expect(find.byType(ChatScreen), findsNothing);
      await press(LogicalKeyboardKey.digit2); // a tab, which closes what is open
      expect(find.byType(ReceiveFromDeviceScreen), findsOneWidget, reason: 'the import screen was closed');
      await settleReal(tester, find.textContaining('Done.'));
      expect(state.data.journal.single['text'], 'IMPORTED');
      await press(LogicalKeyboardKey.keyN); // the first session, as the imported data has none yet
      expect(find.byType(ChatScreen), findsOneWidget, reason: 'the menus work again afterwards');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('D5: trauma work', () {
    test('distress sent during a reply pauses the exercise now: the stop is sent, the words are not', () async {
      final model = StepModel();
      final s = session(AppData(), model: model);
      await s.start('written_exposure');
      model.hold();
      final pending = s.send('I am writing about that night.');
      for (var i = 0; i < 20 && s.streaming.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(s.streaming, isNotEmpty);
      await expectLater(s.send("I can't breathe, I'm back there"), throwsA(isA<SessionBusy>()));
      expect(s.paused, isTrue, reason: 'the exercise went on after a sign of distress');
      expect(model.cancels, 1, reason: 'her words stop at once, as at the Stop button');
      await pending;
      final said = [for (final (who, x) in s.turns) if (who == 'person') x];
      expect(said, ['I am writing about that night.', stopWords], reason: 'the stop was sent once her reply ended');
      expect(s.busy, isFalse);
    });

    test('a crisis sent during a reply in trauma work pauses it too, and opens support once', () async {
      final model = StepModel();
      final s = session(AppData(), model: model);
      await s.start('written_exposure');
      model.hold(beforeWords: true); // before her first words the reply is let finish
      final pending = s.send('I am writing about that night.');
      await Future<void>.delayed(Duration.zero);
      await expectLater(s.send(crisisSentence), throwsA(isA<SessionBusy>()));
      await expectLater(s.send(crisisSentence), throwsA(isA<SessionBusy>())); // Return pressed again
      expect(s.crisisCount, 1);
      expect(s.paused, isTrue);
      expect(model.cancels, 0, reason: 'before her first words nothing is cut');
      model.release();
      await pending;
      expect(s.turns.where((t) => t.$2 == stopWords), hasLength(1));
    });

    testWidgets('on a computer: distress sent with Return during a reply shows the exercise paused at once',
        (tester) async {
      final model = StepModel();
      await pumpChat(tester, makeState(model: model), 'written_exposure');
      model.hold();
      await tester.enterText(find.byType(TextField), 'I am writing about that night.');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), "I can't breathe, I'm back there");
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(); // the paused line is at the end of the conversation (cycle 2 review, N3): in view once scrolled
      final pausedNow = find.text("The exercise is paused. Let's come back to the present together first.")
          .evaluate().isNotEmpty;
      model.release();
      await tester.pumpAndSettle();
      expect(pausedNow, isTrue);
      expect(box(tester), "I can't breathe, I'm back there", reason: 'the words stay in the box');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('trauma work offers no call, which has no exercise Stop; other sessions still do', (tester) async {
      for (final kind in ['written_exposure', 'daily_checkin']) {
        await pumpChat(tester, makeState(), kind);
        expect(find.byTooltip('Switch to a call'), kind == 'daily_checkin' ? findsOneWidget : findsNothing,
            reason: kind);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('D6: typed words are never lost after Edit', () {
    testWidgets('what was in the box before Edit and what was typed during the reply are both kept', (tester) async {
      final model = StepModel();
      await pumpChat(tester, makeState(model: model), 'daily_checkin');
      await tester.enterText(find.byType(TextField), 'Work was hard todya.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DRAFT A, not sent yet');
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      model.hold();
      await tester.enterText(find.byType(TextField), 'Work was hard today.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'TYPED DURING THE REPLY');
      model.release();
      await tester.pumpAndSettle();
      expect(box(tester), 'DRAFT A, not sent yet\nTYPED DURING THE REPLY');
    });

    testWidgets('after an edit came too late, the draft from before Edit goes with the words to a call',
        (tester) async {
      final clock = Clock();
      await pumpChat(tester, makeState(clock: clock), 'daily_checkin');
      await tester.enterText(find.byType(TextField), 'Work was hard todya.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DRAFT A, not sent yet');
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Work was hard today.');
      clock.pass(const Duration(minutes: 11)); // the edit window closes while it is being changed
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      expect(box(tester), 'Work was hard today.', reason: 'the change stays, to send as a new message');
      await tester.tap(find.byTooltip('Switch to a call'));
      await tester.pumpAndSettle();
      final carried = box(tester, find.byKey(const Key('call_text')));
      expect(carried, contains('DRAFT A, not sent yet'), reason: 'the draft from before Edit was dropped');
      expect(carried, contains('Work was hard today.'));
      await tester.pumpWidget(const SizedBox()); // the call's clock stops with it
    });
  });

  group('D7: a classifier that never answers', () {
    testWidgets('holds the session busy for at most 15 seconds, then counts as a fault, said and recorded',
        (tester) async {
      final clf = HeldClassifier();
      final data = AppData();
      final s = session(data, riskCheck: clf.check);
      await s.start('daily_checkin');
      final sent = s.send('Work was hard today.');
      await tester.pump(const Duration(seconds: 2));
      expect(s.turns.last.$1, 'therapist', reason: 'her reply is written');
      expect(s.busy, isTrue, reason: 'still waiting for the verdict');
      await tester.pump(const Duration(seconds: 14));
      expect(s.busy, isFalse, reason: 'a verdict that never comes kept the session busy for good');
      await sent;
      expect(s.classifierFailed, isTrue, reason: 'the screen says only the phrase checks are running');
      expect(data.safetyEvents.where((e) => e['level'] == 'error' && '${e['reason']}'.startsWith('classifier')),
          hasLength(1));
      // the late verdict, an alarm, is still acted on when it comes, never dropped (round 4 review, B-05; it was
      // dropped until then): its quiet support line shows (owner 2026-11-15: no question), without holding the session
      // busy again
      clf.verdicts.single.complete(true);
      await tester.pump(const Duration(seconds: 1));
      expect(s.lastSafety.level, SafetyLevel.concern);
      expect(s.busy, isFalse);
      expect(data.safetyEvents.map((e) => e['level']), ['error', 'concern']);
      // the next message is answered at once: a classifier that did not answer in time is not waited for again in
      // this session (cycle 2 review, N6), but it is still asked about the message (B-05)
      final next = s.send('I slept badly.');
      await tester.pump(const Duration(seconds: 1));
      await next;
      expect(s.busy, isFalse);
      expect(clf.verdicts, hasLength(2));
      expect(s.turns.where((t) => t.$1 == 'person'), hasLength(2));
    });

    testWidgets('a late error after the wait is never thrown anywhere', (tester) async {
      final clf = HeldClassifier();
      final s = session(AppData(), riskCheck: clf.check);
      await s.start('daily_checkin');
      final sent = s.send('Work was hard today.');
      await tester.pump(const Duration(seconds: 16));
      await sent;
      clf.verdicts.single.completeError(StateError('the classifier failed late'));
      await tester.pump(const Duration(seconds: 1));
      expect(s.busy, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('D8: words heard on a call while Solace is still busy', () {
    testWidgets('go in the box, after what is typed there, and the box shows', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final clf = HeldClassifier();
      final state = makeState()..useRiskCheck(clf.check, 'test classifier');
      // the first words are sent; the second come while the classifier is still reading the first (she speaks her
      // reply as soon as it is written, then listens), so the session is busy
      final voice = HearingVoice(['Work was hard today.', 'And I could not sleep.']);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light), home: CallScreen(kind: 'daily_checkin', voice: voice))));
      for (var i = 0; i < 20 && voice.listens < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(voice.listens, 2);
      await tester.pump(const Duration(milliseconds: 100));
      final field = find.byKey(const Key('call_text'));
      expect(field, findsOneWidget, reason: 'the words heard went into a box that is not shown');
      expect(box(tester, field), 'And I could not sleep.');
      clf.verdicts.single.complete(false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('in the call box with typed words already in it, both are kept', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final clf = HeldClassifier();
      final state = makeState()..useRiskCheck(clf.check, 'test classifier');
      final voice = HearingVoice(['Work was hard today.', 'And I could not sleep.']);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light), home: CallScreen(kind: 'daily_checkin', voice: voice,
              draft: 'Typed before the call.'))));
      for (var i = 0; i < 20 && voice.listens < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(box(tester, find.byKey(const Key('call_text'))), 'Typed before the call.\nAnd I could not sleep.');
      clf.verdicts.single.complete(false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('I3 (superseded 2026-11-15, owner): a classifier worry that comes after the person has left', () {
    test('is recorded, and nothing is carried to the next session', () async {
      final clf = HeldClassifier();
      final data = AppData();
      final s = session(data, riskCheck: clf.check);
      await s.start('daily_checkin');
      final sent = s.send('I want to find my purpose.');
      for (var i = 0; i < 50 && !s.checking; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      s.leave(); // Back, while the verdict is still awaited
      clf.verdicts.single.complete(true);
      await sent;
      // owner 2026-11-15: the worry is recorded; there is no question to carry, so no watch starts
      expect(data.safetyEvents.single, {'date': '2026-11-14', 'level': 'concern', 'reason': 'classifier'});
      expect(data.safetyWatch, isNull);
      final next = session(data);
      await next.start('daily_checkin');
      expect(next.openingCheck, isFalse);
    });

    test('a watch already running is left exactly as it was (owner, 2026-11-15)', () async {
      final clf = HeldClassifier();
      final data = AppData()..safetyWatch = {'since': '2026-11-13T09:00:00.000', 'reason': 'said yes'};
      final s = session(data, riskCheck: clf.check);
      await s.start('daily_checkin');
      final sent = s.send('I want to find my purpose.');
      for (var i = 0; i < 50 && !s.checking; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      s.leave();
      clf.verdicts.single.complete(true);
      await sent;
      // owner 2026-11-15: a classifier worry no longer starts or renews a watch; the earlier watch is left as it was
      expect(data.safetyWatch, {'since': '2026-11-13T09:00:00.000', 'reason': 'said yes'});
    });

    test('a classifier worry in the session is not carried on', () async {
      final clf = HeldClassifier();
      final data = AppData();
      final s = session(data, riskCheck: clf.check);
      await s.start('daily_checkin');
      final sent = s.send('I want to find my purpose.');
      for (var i = 0; i < 50 && !s.checking; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      clf.verdicts.single.complete(true);
      await sent;
      expect(s.lastSafety.level, SafetyLevel.concern);
      s.leave();
      expect(data.safetyWatch, isNull);
    });
  });
}
