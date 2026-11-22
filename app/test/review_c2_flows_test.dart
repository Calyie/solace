// Review cycle 2, flows (N1 to N13): words a call hears are never dropped unread; Settings and the Receive screen keep
// Support one tap away and let Back go after a long wait; a call says again a reply a pause cut short, and never an
// older one after a newer; a safety question carried over extends a watch about to end; a classifier that timed out
// once is not waited for again; End on a call says it is writing the note; a draft held back is never cut; the chat
// box is closed while End writes the note; a session that cannot start just now says so plainly; the opening check
// says why it asks; the Linux keyring move looks for the last good copy and runs again on Try again; and the small
// fixes beside them. Every test drives the app's real code (the screens and the session controller), and was run
// against the code before these fixes, where it fails.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/core/voice.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/recovery.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/theme.dart';
import 'package:solace/ui/transfer_screen.dart';

import 'call_streaming_test.dart' as cs;
import 'review_c1_flows_test.dart' as c1;

/// A voice without speakAll: speak() lasts until stop(); listening never hears anything.
class LongVoice implements VoiceService {
  final events = <String>[];
  Completer<void>? _speech;
  bool get speaking => _speech != null && !_speech!.isCompleted;
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async {
    events.add('speak');
    _speech = Completer<void>();
    await _speech!.future;
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    if (speaking) _speech!.complete();
  }

  @override
  Future<String?> listenOnce() {
    events.add('listen');
    return Completer<String?>().future;
  }
}

/// A voice whose recognition is already under way when stop() comes (Sherpa: the speech was caught, the words are
/// being worked out; stop() then has nothing left to cancel): listenOnce answers what the test gives it.
class AsrVoice implements VoiceService {
  Completer<String?>? ear;
  int listens = 0;
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<String?> listenOnce() {
    listens++;
    return (ear = Completer<String?>()).future;
  }
}

/// A voice that speaks as words come and falls quiet at once on stop(); it records each whole reply it is asked to
/// say, and hears nothing (the call then rests).
class QuickFeedVoice implements VoiceService, StreamingVoice {
  final events = <String>[];
  Completer<void>? _speaking;
  @override
  bool get available => true;
  @override
  Future<void> speak(String text, {required String voice}) async {
    events.add('speak:$text');
    _speaking = Completer<void>();
    await _speaking!.future;
  }

  @override
  Future<void> speakAll(Stream<String> words, {required String voice}) async {
    events.add('speakAll');
    final speaking = _speaking = Completer<void>();
    final sub = words.listen((_) {}, onDone: () {
      if (!speaking.isCompleted) speaking.complete();
    });
    await speaking.future;
    unawaited(sub.cancel());
  }

  void finish() {
    if (!(_speaking?.isCompleted ?? true)) _speaking!.complete();
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    finish();
    final h = _hearing;
    if (h != null && !h.isCompleted) h.complete(null);
  }

  /// The first listen, at the start of a call carried on from the chat (since 2026-11-16 it listens at once), stays
  /// open until stop(): the person has not spoken yet. Later ones hear nothing, and the call rests.
  @override
  Future<String?> listenOnce() async {
    events.add('listen');
    if (!events.contains('speakAll')) return (_hearing = Completer<String?>()).future;
    return null;
  }

  Completer<String?>? _hearing;
}

/// Each reply is numbered; when held, a reply writes its first sentence and waits for [release].
class NumberedModel extends StandInModel implements ReplyCanceller {
  int replies = 0;
  Completer<void>? _gate;
  void hold() => _gate = Completer<void>();
  void release() {
    if (!(_gate?.isCompleted ?? true)) _gate!.complete();
  }

  @override
  void cancelReply() => release();

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    if (asksForNote(messages) || asksForRecord(messages)) {
      yield* super.generate(messages, maxTokens: maxTokens);
      return;
    }
    final n = ++replies;
    yield 'Reply $n begins here. ';
    final g = _gate;
    if (g != null && !g.isCompleted) await g.future;
    yield 'Reply $n ends here.';
  }
}

/// The stand-in, but the session note (End) waits until [release].
class SlowNoteModel extends StandInModel {
  final note = Completer<void>();
  void release() {
    if (!note.isCompleted) note.complete();
  }

  @override
  Stream<String> generate(List<Map<String, String>> messages, {int maxTokens = 220}) async* {
    if (asksForNote(messages) || asksForRecord(messages)) await note.future; // the note and the story
    yield* super.generate(messages, maxTokens: maxTokens);
  }
}

/// A vault whose Delete everything waits until [finish] (a keychain call that takes a long time).
class SlowWipeVault extends MemoryVault {
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  @override
  Future<void> wipe() async {
    await done.future;
    await super.wipe();
  }
}

/// A vault whose saves wait for [gate] (a large store: about 4 s at 16 MB, 11 s at 42 MB with pure-Dart AES-GCM).
class SlowSaveVault extends MemoryVault {
  Completer<void>? gate;
  @override
  Future<void> save(AppData data) async {
    final g = gate;
    if (g != null) await g.future;
    return super.save(data);
  }
}

/// A vault whose saves fail (a full disk): End cannot save.
class FailingSaveVault extends MemoryVault {
  bool failing = false;
  @override
  Future<void> save(AppData data) async {
    if (failing) throw StateError('disk full');
    return super.save(data);
  }
}

class MemoryKeys implements KeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String name) async => values[name];
  @override
  Future<void> write(String name, String value) async => values[name] = value;
  @override
  Future<void> delete(String name) async => values.remove(name);
  @override
  Future<void> deleteAll() async => values.clear();
}

Future<void> pumpCallScreen(WidgetTester tester, AppState state, Widget call) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: call)));
}

/// A screen pushed over a plain first page, so Back has somewhere to go.
Future<void> pushOver(WidgetTester tester, AppState state, Widget Function() screen) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen())),
          child: const Text('Open')))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

int crises(AppState s) => s.data.safetyEvents.where((e) => e['level'] == 'crisis').length;

void main() {
  group('N1: words a call hears are never dropped unread', () {
    testWidgets('typed words sent while the microphone listens: what it had just heard is read and kept in the box',
        (tester) async {
      final state = c1.makeState();
      final voice = AsrVoice();
      await pumpCallScreen(tester, state, CallScreen(kind: 'daily_checkin', voice: voice,
          draft: 'Something I typed earlier.'));
      for (var i = 0; i < 20 && voice.listens == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(voice.listens, 1, reason: 'she greeted, then listens');
      // the person has just spoken (recognition under way) and sends the typed words
      await tester.tap(find.byKey(const Key('call_send')));
      await tester.pump();
      voice.ear!.complete(c1.crisisSentence); // what they had said
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(crises(state), 1, reason: 'the spoken crisis was dropped without the safety rules reading it');
      // owner, 2026-11-15, OWNER-C1: support shows at once as the card on the call screen; nothing covers the call
      expect(find.byKey(const Key('crisis_card'), skipOffstage: false), findsOneWidget, reason: 'support shows at once');
      expect(find.text('You matter, and support is here'), findsNothing);
      expect(c1.box(tester, find.byKey(const Key('call_text'))), c1.crisisSentence,
          reason: 'what was heard waits in the box, to send or change');
      final s = state.data.safetyEvents;
      expect(s.where((e) => e['level'] == 'crisis').single['reason'], isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('words caught right before a pause are read at once, not sent, and wait in the box for Resume',
        (tester) async {
      final state = c1.makeState();
      final s = state.newSession();
      await s.start('daily_checkin');
      final voice = AsrVoice();
      await pumpCallScreen(tester, state, CallScreen(kind: 'daily_checkin', voice: voice, controller: s));
      // since 2026-11-16 a call carried on from the chat listens at once (listen 1); the reply sent here stops it
      await s.send('Work was hard today.'); // she answers; the call speaks it, then listens (listen 2)
      for (var i = 0; i < 20 && voice.listens < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(voice.listens, 2);
      await tester.tap(find.byKey(const Key('call_pause')));
      await tester.pump();
      final people = s.turns.where((t) => t.$1 == 'person').length;
      voice.ear!.complete(c1.crisisSentence); // caught just before the pause
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(crises(state), 1, reason: 'words caught before a pause were dropped unread');
      expect(s.turns.where((t) => t.$1 == 'person'), hasLength(people), reason: 'nothing is sent while paused');
      // OWNER-C1: the support card on the call screen, nothing over the call
      expect(find.byKey(const Key('crisis_card'), skipOffstage: false), findsOneWidget);
      expect(find.text('You matter, and support is here'), findsNothing);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call_resume')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(c1.box(tester, find.byKey(const Key('call_text'))), c1.crisisSentence,
          reason: 'the words wait in the box after Resume');
      expect(voice.listens, 3, reason: 'and she listens again');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('N2: Support stays reachable while data changes, and the wait ends', () {
    testWidgets('Settings: Delete everything shows its progress and Support; Back is let go after two minutes',
        (tester) async {
      final vault = SlowWipeVault();
      final state = c1.makeState(vault: vault);
      state.data.journal.add({'date': '2026-11-14', 'text': 'PRIVATE'});
      await pushOver(tester, state, () => const SettingsScreen());
      final open = find.text('Delete everything the app knows about me');
      await tester.scrollUntilVisible(open, 400, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle(); // Settings builds every section at once: the scroll lands with this frame
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('wipe_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wipe_confirm')));
      await tester.pump();
      expect(find.byTooltip('Support'), findsOneWidget, reason: 'the crisis numbers stay one tap away');
      expect(find.byKey(const Key('wipe_progress')), findsOneWidget, reason: 'the screen says what it is doing');
      await tester.pump(const Duration(seconds: 90));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget, reason: 'Back waits while deleting, for a while');
      await tester.pump(const Duration(seconds: 31));
      expect(find.textContaining('You can go back now'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing, reason: 'Back is let go after two minutes');
      // the guards stay: no session starts, and a second Delete everything is refused while this one runs
      Object? refused;
      unawaited(state.newSession().start('daily_checkin').catchError((Object e) => refused = e));
      await tester.pump();
      expect(refused, isA<GateClosed>());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(open, 400, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle(); // Settings builds every section at once: the scroll lands with this frame
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('wipe_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wipe_confirm')));
      await tester.pump();
      expect(find.text(stillChangingData), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // the first one finishes in the background, and says so
      vault.finish();
      for (var i = 0; i < 20 && find.text('Everything Solace kept has been deleted.').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.data.journal, isEmpty);
      expect(find.text('Everything Solace kept has been deleted.'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('Receive: the import shows its progress and Support, Cancel is not offered, Back is let go later',
        (tester) async {
      final vault = SlowSaveVault();
      final state = c1.makeState(vault: vault);
      final (file, code) = await c1.transferFile(tester, AppData()..journal.add({'date': '2026-11-12', 'text': 'X'}));
      await pushOver(tester, state, () => ReceiveFromDeviceScreen(pick: () async => PickedTransfer.fromBytes(file)));
      vault.gate = Completer<void>(); // the save of what came in takes a while
      await c1.startReplace(tester, code);
      expect(find.byTooltip('Support'), findsOneWidget, reason: 'the crisis numbers stay one tap away');
      expect(find.byKey(const Key('transfer_progress')), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const Key('transfer_cancel'))).onPressed, isNull,
          reason: 'Cancel cannot stop an import that is running, so it is not offered');
      for (var i = 0; i < 100 && state.data.journal.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(state.data.journal, isNotEmpty, reason: 'the data is replaced; its save is waiting');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveFromDeviceScreen), findsOneWidget, reason: 'Back waits, for a while');
      await tester.pump(longDataWait);
      expect(find.byKey(const Key('transfer_long')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveFromDeviceScreen), findsNothing, reason: 'Back is let go after two minutes');
      vault.gate!.complete();
      for (var i = 0; i < 50 && find.textContaining('Bringing your data in: Done.').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(find.textContaining('Bringing your data in: Done.'), findsOneWidget, reason: 'how it went is still said');
      expect((await vault.load()).journal.single['text'], 'X');
      await tester.pumpAndSettle();
    });
  });

  group('N4: a call says again the reply a pause cut short', () {
    testWidgets('Resume while she is still writing: the reply cut by the pause is said, then she listens',
        (tester) async {
      final model = cs.HalfwayModel();
      final state = cs.makeState(model);
      final s = state.newSession();
      await s.start('daily_checkin');
      final voice = cs.FeedVoice();
      await cs.pumpCall(tester, state, voice, s);
      voice.finish();
      await tester.pump();
      model.holdHalfway();
      final sent = s.send('Work was hard today.');
      await tester.pump();
      await tester.pump();
      expect(voice.events, contains('speakAll'), reason: 'she speaks as she writes');
      await tester.tap(find.byKey(const Key('call_pause')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('call_resume'))); // a short pause: Resume while she is still writing
      await tester.pump();
      voice.events.clear();
      model.release();
      await tester.runAsync(() => sent);
      await tester.pump();
      await tester.pump();
      expect(voice.events.first,
          'speak:I hear you, and that sounds like a long day. What part of it stayed with you most?',
          reason: 'the reply broken off by the pause was never said: the call went straight to listening');
    });

    testWidgets('a reply cut by an earlier pause is never said after a newer one', (tester) async {
      final model = NumberedModel();
      final state = cs.makeState(model);
      final s = state.newSession();
      await s.start('daily_checkin'); // reply 1, the greeting, already said
      final voice = QuickFeedVoice();
      await pumpCallScreen(tester, state, CallScreen(kind: 'daily_checkin', voice: voice, controller: s));
      await tester.pump();
      model.hold();
      final first = s.send('Work was hard today.'); // reply 2, spoken as it is written
      await tester.pump();
      await tester.pump();
      expect(voice.events, contains('speakAll'));
      await tester.tap(find.byKey(const Key('call_pause')));
      await tester.pump();
      model.release();
      await first; // reply 2 is written while paused: it is said on Resume
      await tester.pump();
      model.hold();
      final second = s.send('And I slept badly.'); // reply 3, still being written when Resume comes
      await tester.pump();
      await tester.tap(find.byKey(const Key('call_resume')));
      await tester.pump();
      await tester.pump();
      model.release();
      await second;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // reply 3 was spoken as it came; the call then heard nothing and rests. Resume again:
      await tester.tap(find.byKey(const Key('call_resume')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(voice.events.where((e) => e.contains('Reply 2')), isEmpty,
          reason: 'the older reply was said after the newer one: ${voice.events}');
      await tester.pumpWidget(const SizedBox());
    });
  });

  // N5 and N11 (superseded 2026-11-15, owner): there is no safety question to carry. A classifier worry never starts
  // or renews a watch, so a watch near its end runs out on its own time, and a crisis keeps its own watch.
  group('N5 (superseded): a classifier worry never extends a watch', () {
    test('a worry after Back, near the end of an old watch: the old watch still ends on time', () async {
      final clf = c1.HeldClassifier();
      var now = DateTime(2026, 11, 14, 20);
      final data = AppData()
        ..safetyWatch = {'since': now.subtract(const Duration(days: 6, hours: 23)).toIso8601String(), 'reason': 'x'};
      final s = SessionController(model: c1.StepModel(), prompts: c1.prompts, data: data, vault: MemoryVault(),
          riskCheck: clf.check, clock: () => now);
      await s.start('daily_checkin');
      s.answerOpeningCheck('better');
      final sent = s.send('I want to find my purpose.');
      for (var i = 0; i < 50 && clf.verdicts.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      s.leave();
      clf.verdicts.single.complete(true);
      await sent;
      now = now.add(const Duration(hours: 2));
      final next = SessionController(model: c1.StepModel(), prompts: c1.prompts, data: data, vault: MemoryVault(),
          clock: () => now);
      await next.start('daily_checkin');
      expect(next.openingCheck, isFalse, reason: 'the old watch ran out; the worry carried nothing');
    });

    test('a crisis earlier in the same session keeps its own watch', () async {
      final clf = c1.HeldClassifier();
      final data = AppData();
      final s = c1.session(data, riskCheck: clf.check);
      await s.start('daily_checkin');
      await s.send(c1.crisisSentence); // the phrase rules: a crisis, the watch starts
      final sent = s.send('I want to find my purpose.');
      for (var i = 0; i < 50 && clf.verdicts.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      clf.verdicts.single.complete(true);
      await sent;
      s.leave();
      final next = c1.session(data);
      await next.start('daily_checkin');
      expect(next.openingCheck, isTrue);
      expect(next.openingAfterQuestion, isFalse);
    });
  });

  group('N6: a classifier that timed out is not waited for again (but still asked: round 4, B-05)', () {
    testWidgets('after the first timeout, later messages are not each held busy for another 15 s', (tester) async {
      final clf = c1.HeldClassifier();
      final s = c1.session(AppData(), riskCheck: clf.check);
      await s.start('daily_checkin');
      final waits = <int>[];
      for (final m in ['Work was hard today.', 'I slept badly.', 'And I skipped lunch.']) {
        final sent = s.send(m);
        var ms = 0;
        await tester.pump(const Duration(milliseconds: 100));
        while (s.busy && ms < 70000) {
          await tester.pump(const Duration(milliseconds: 500));
          ms += 500;
        }
        await sent;
        waits.add(ms);
      }
      expect(waits.first, greaterThanOrEqualTo(14000), reason: 'the first wait is the full one');
      expect(waits.skip(1).every((w) => w < 1000), isTrue,
          reason: 'every message waits the full 15 s again for a classifier already known not to answer: $waits');
      // still asked, never waited for (round 4 review, B-05: not asking left plans the rules miss unread), one later
      // message at a time: the third waits for the second's run, which this classifier never ends
      expect(clf.verdicts, hasLength(2), reason: 'asked about the second message, without waiting for it');
      expect(s.classifierFailed, isTrue, reason: 'the screen says only the phrase checks are running');
      clf.verdicts[1].complete(false);
      await tester.pump();
      expect(clf.verdicts, hasLength(3), reason: 'the third message is read once the second is done');
    });

    testWidgets('an error, which comes at once, does not stop the classifier being asked', (tester) async {
      final clf = c1.HeldClassifier();
      final s = c1.session(AppData(), riskCheck: clf.check);
      await s.start('daily_checkin');
      final sent = s.send('Work was hard today.');
      await tester.pump();
      clf.verdicts.single.completeError(StateError('a fault'));
      await tester.pump(const Duration(seconds: 1));
      await sent;
      final next = s.send('I slept badly.');
      await tester.pump(const Duration(seconds: 1));
      expect(clf.verdicts, hasLength(2));
      clf.verdicts.last.complete(false);
      await tester.pump(const Duration(seconds: 1));
      await next;
    });

    testWidgets('the chat shows a quiet "Checking" while the verdict is awaited, and nothing after', (tester) async {
      final clf = c1.HeldClassifier();
      final state = c1.makeState()..useRiskCheck(clf.check, 'test classifier');
      await c1.pumpChat(tester, state, 'daily_checkin');
      await tester.enterText(find.byType(TextField), 'Work was hard today.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('chat_checking')), findsOneWidget, reason: 'nothing showed while it was checked');
      clf.verdicts.single.complete(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_checking')), findsNothing);
    });
  });

  group('N7: End on a call says it is writing the note', () {
    testWidgets('End tapped while she is speaking shows the note being written, not "Speaking"', (tester) async {
      final model = SlowNoteModel();
      final state = c1.makeState(model: model);
      final s = state.newSession();
      await s.start('daily_checkin');
      final voice = LongVoice();
      await pumpCallScreen(tester, state, CallScreen(kind: 'daily_checkin', voice: voice, controller: s));
      await tester.pump();
      await s.send('Work was hard today.');
      await tester.pump();
      await tester.pump();
      expect(voice.speaking, isTrue, reason: 'she is saying her reply');
      await tester.tap(find.byKey(const Key('call_end')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.ending, isTrue);
      expect(find.byKey(const Key('call_state_speaking')), findsNothing);
      expect(find.byKey(const Key('call_state_thinking')), findsOneWidget);
      expect(find.text('Writing your session note'), findsOneWidget);
      model.release();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('N8: a draft held back after an edit is never cut', () {
    /// Holds a draft back: [draft] was in the box at Edit, [typedDuring] was typed while the edit was answered, and
    /// the two together pass a box, so the box keeps what was typed during the reply and the draft waits.
    Future<void> holdDraft(WidgetTester tester, c1.StepModel model, String draft, String typedDuring) async {
      await tester.enterText(find.byType(TextField), 'Work was hard todya.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), draft);
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      model.hold();
      await tester.enterText(find.byType(TextField), 'Work was hard today.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), typedDuring);
      model.release();
      await tester.pumpAndSettle();
      expect(c1.box(tester), typedDuring);
    }

    Future<String> sendAndRead(WidgetTester tester, Finder box, Finder send) async {
      final sent = c1.box(tester, box);
      await tester.tap(send);
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('Edit tapped again, then Cancel: every word of the held draft and the box comes back', (tester) async {
      final model = c1.StepModel();
      await c1.pumpChat(tester, c1.makeState(model: model), 'daily_checkin');
      await holdDraft(tester, model, 'D' * 7000, 'N' * 6000);
      final heldBefore = find.byKey(const Key('chat_held')).evaluate().length;
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_edit_cancel')));
      await tester.pumpAndSettle();
      final heldAfterCancel = find.byKey(const Key('chat_held')).evaluate().length;
      // the box is sent; what waited comes back after it
      final first = await sendAndRead(tester, find.byType(TextField), find.byKey(const Key('chat_send')));
      final both = first + c1.box(tester);
      final ds = 'D'.allMatches(both).length, ns = 'N'.allMatches(both).length;
      expect(ds + ns, 13000, reason: '${13000 - ds - ns} typed characters were cut and lost');
      expect(heldBefore, 1, reason: 'the person is told words are waiting');
      expect(heldAfterCancel, 1, reason: 'what does not fit after Cancel waits, and says so');
      expect(find.byKey(const Key('chat_held')), findsNothing, reason: 'nothing waits now');
    });

    testWidgets('switching to a call carries every word of the held draft and the box', (tester) async {
      final model = c1.StepModel();
      await c1.pumpChat(tester, c1.makeState(model: model), 'daily_checkin');
      await holdDraft(tester, model, 'D' * 7000, 'N' * 6000);
      await tester.tap(find.byTooltip('Switch to a call'));
      await tester.pumpAndSettle();
      final box = find.byKey(const Key('call_text'));
      final first = c1.box(tester, box);
      final heldShown = find.byKey(const Key('call_held')).evaluate().length;
      await tester.tap(find.byKey(const Key('call_send')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final second = c1.box(tester, box);
      final ds = 'D'.allMatches(first + second).length, ns = 'N'.allMatches(first + second).length;
      expect(ds + ns, 13000, reason: '${13000 - ds - ns} typed characters were cut and lost on the way to the call');
      expect(heldShown, 1, reason: 'the call says more words are waiting');
      expect(find.byKey(const Key('call_held')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an Edit that would leave more than two boxes waiting is refused kindly, and nothing is lost',
        (tester) async {
      final model = c1.StepModel();
      await c1.pumpChat(tester, c1.makeState(model: model), 'daily_checkin');
      await holdDraft(tester, model, 'D' * 12000, 'N' * 12000); // D waits, N in the box
      // a second Edit holds N too (two boxes waiting); its answer comes while X is typed
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      model.hold();
      await tester.enterText(find.byType(TextField), 'Work was hard, today.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'X' * 12000);
      model.release();
      await tester.pumpAndSettle();
      expect(c1.box(tester), 'X' * 12000);
      // a third Edit would leave three boxes waiting
      await tester.longPress(find.byKey(const Key('latest_message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_message')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Some of your earlier words are still waiting'), findsOneWidget);
      expect(find.byKey(const Key('chat_editing')), findsNothing);
      expect(c1.box(tester), 'X' * 12000);
      await tester.pump(const Duration(seconds: 5)); // the kind line goes, so it no longer covers Send
      await tester.pumpAndSettle();
      // every word comes back, a box at a time, as each is sent
      final seen = StringBuffer();
      for (var i = 0; i < 3; i++) {
        seen.write(await sendAndRead(tester, find.byType(TextField), find.byKey(const Key('chat_send'))));
      }
      final all = seen.toString();
      expect(['D', 'N', 'X'].map((c) => c.allMatches(all).length), [12000, 12000, 12000]);
    });
  });

  group('N9: during End the chat box is closed, with a line saying why', () {
    testWidgets('words cannot be typed into a box End then throws away; it opens again if End cannot save',
        (tester) async {
      final model = SlowNoteModel();
      final vault = FailingSaveVault();
      final state = c1.makeState(model: model, vault: vault);
      await c1.pumpChat(tester, state, 'daily_checkin');
      await tester.enterText(find.byType(TextField), 'Work was hard today.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('end_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('chat_writing_note')), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.enabled, isFalse, reason: 'the box took words that End then threw away');
      expect(find.text('Closed while your note is written'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('chat_send'))).onPressed, isNull);
      vault.failing = true;
      model.release();
      await tester.pumpAndSettle();
      expect(find.text(endProblem), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).last).enabled, isNot(false),
          reason: 'the session is still open, so the box opens again');
    });

    testWidgets('End with words still in the box says they have not been sent', (tester) async {
      await c1.pumpChat(tester, c1.makeState(), 'daily_checkin');
      await tester.enterText(find.byType(TextField), 'Work was hard today.');
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'One more thing.');
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('end_unsent')), findsOneWidget);
      await tester.tap(find.byKey(const Key('end_keep_talking')));
      await tester.pumpAndSettle();
      expect(c1.box(tester), 'One more thing.');
    });
  });

  group('N10: a session that cannot start just now says so plainly, with Support', () {
    testWidgets('while data changes: "Not just now", never the reliving gate\'s "Not today"', (tester) async {
      final state = c1.makeState();
      final hold = Completer<void>();
      unawaited(state.whileChangingData(() => hold.future));
      await c1.pumpChat(tester, state, 'daily_checkin');
      expect(find.text('Not just now'), findsOneWidget);
      expect(find.text('Not today'), findsNothing);
      expect(find.textContaining('written approach and the grounding practices'), findsNothing);
      expect(find.text('Support is always one tap away, at the top.'), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('with Solace\'s room full: "Not just now" and Support', (tester) async {
      final state = c1.makeState();
      state.pictureBytes = 1 << 40; // more than Solace's room holds: a conversation that would be kept cannot start
      await c1.pumpChat(tester, state, 'daily_checkin');
      expect(find.textContaining('space is full'), findsOneWidget);
      expect(find.text('Not just now'), findsOneWidget);
      expect(find.text('Support is always one tap away, at the top.'), findsOneWidget);
    });
  });

  group('N11: the opening check says why it asks', () {
    for (final (reason, line) in [
      (watchUnanswered, openingAfterQuestionLine),
      (watchLateQuestion, openingAfterQuestionLine),
      ('said yes to the safety question', openingAfterCrisisLine),
    ]) {
      testWidgets('a watch from "$reason"', (tester) async {
        final state = c1.makeState();
        state.data.safetyWatch = {'since': DateTime(2026, 11, 14, 9).toIso8601String(), 'reason': reason};
        await c1.pumpChat(tester, state, 'daily_checkin');
        expect(find.byKey(const Key('opening_check')), findsOneWidget);
        expect(find.text(line), findsOneWidget);
      });
    }
  });

  group('N12: Linux, the keyring key move', () {
    test('runs when only the last good copy (data_v1.bin.bak) is there', () async {
      final dir = Directory.systemTemp.createTempSync('solace_ring');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/data_v1.bin.bak').writeAsBytesSync([1, 2, 3]);
      final keys = MemoryKeys(), ring = MemoryKeys()..values[EncryptedFileVault.keyName] = 'OLD KEY';
      await moveKeyringKey(keys, dir, ring: ring);
      expect(keys.values[EncryptedFileVault.keyName], 'OLD KEY', reason: 'the key stayed in the keyring');
      expect(ring.values, isEmpty);
    });

    test('a fresh install never touches the keyring', () async {
      final dir = Directory.systemTemp.createTempSync('solace_ring');
      addTearDown(() => dir.deleteSync(recursive: true));
      final keys = MemoryKeys(), ring = MemoryKeys()..values[EncryptedFileVault.keyName] = 'OLD KEY';
      await moveKeyringKey(keys, dir, ring: ring);
      expect(keys.values, isEmpty);
      expect(ring.values, hasLength(1));
    });

    test('Try again on the recovery screen runs the move again before opening', () async {
      final dir = Directory.systemTemp.createTempSync('solace_ring');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/data_v1.bin').writeAsBytesSync(utf8.encode('not readable without its key'));
      var moves = 0;
      final shown = <Widget>[];
      await boot(c1.prompts, c1.library, EncryptedFileVault(keychain: MemoryKeys(), folder: () async => dir),
          oneCopyChecked: true, beforeOpen: () async => moves++, run: shown.add);
      expect(moves, 1);
      expect(shown.single, isA<RecoveryApp>());
      await (shown.single as RecoveryApp).retry();
      expect(moves, 2, reason: 'Try again did not run the keyring move again');
      expect(shown.last, isA<RecoveryApp>(), reason: 'still no key: the recovery screen again');
    });
  });

  group('Info items', () {
    test('a pause sign in the part of a paste that does not fit, during a reply in trauma work, stops the exercise',
        () async {
      final model = c1.StepModel();
      final s = c1.session(AppData(), model: model);
      await s.start('written_exposure');
      model.hold();
      final sent = s.send('I am writing about that night.');
      await Future<void>.delayed(Duration.zero);
      expect(s.busy, isTrue);
      expect(s.streaming, isNotEmpty, reason: 'her words show');
      await s.checkPasted('${'a ' * (maxInput ~/ 2 + 100)}I can\'t breathe, I\'m back there');
      expect(s.paused, isTrue);
      expect(model.cancels, 1, reason: 'her words stop at once, as for distress sent during a reply');
      await sent;
      expect(s.turns.where((t) => t.$2 == c1.stopWords), hasLength(1), reason: 'the stop is sent once her reply ends');
    });
  });
}
