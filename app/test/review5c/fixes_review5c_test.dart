// Round 5 review, reviewer C: tests for the fixes beyond the reviewer's own proofs in this folder (C-03, C-04, C-06,
// C-07, C-10, C-11). Each states the behaviour the fix promises.
import 'dart:io';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/formats.dart' show Story;
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/plans.dart';
import 'package:solace/core/store.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/choose_to_delete.dart';
import 'package:solace/ui/desktop.dart' show appNavigatorKey;
import 'package:solace/ui/recovery.dart';

import '../app_flow_test.dart' as flow;
import '../onboarding_test.dart' show waitFor;
import '../review_c1_flows_test.dart' as c1;

class _Keys extends KeyStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String name) async => m[name];
  @override
  Future<void> write(String name, String value) async => m[name] = value;
  @override
  Future<void> delete(String name) async => m.remove(name);
}

/// Lock the app over whatever is open: the lock on, away for two minutes, and back.
Future<void> _lockNow(WidgetTester tester, Settings s, Map<String, String> stored) async {
  s
    ..appLock = true
    ..lockAfterMinutes = 0
    ..passcode = stored;
  for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(st);
  }
  await tester.pump(const Duration(minutes: 2));
  for (final st in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(st);
  }
  await tester.pumpAndSettle();
  expect(find.text('Solace is locked'), findsOneWidget);
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  group('C-03, one copy at a time', () {
    test('the computers take the lock; the phones never ask for it', () {
      for (final os in ['linux', 'windows', 'macos']) {
        expect(takesOneCopyLock(os), isTrue, reason: os);
      }
      for (final os in ['ios', 'android', 'web', 'fuchsia']) {
        expect(takesOneCopyLock(os), isFalse, reason: os);
      }
    });

    test('boot on an iPhone never asks; on a Mac with the lock free it goes on to open the store', () async {
      final dir = Directory.systemTemp.createTempSync('r5c_boot');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/data_v1.bin').writeAsBytesSync([1, 2, 3]); // unreadable: boot stops at the recovery screen
      for (final (os, free, asks) in [('ios', true, 0), ('macos', true, 1)]) {
        var asked = 0;
        final shown = <Widget>[];
        await boot(c1.prompts, c1.library, EncryptedFileVault(keychain: _Keys(), folder: () async => dir), os: os,
            onlyCopy: () async {
              asked++;
              return free;
            }, run: shown.add);
        expect(asked, asks, reason: os);
        expect(shown.single, isA<RecoveryApp>(), reason: '$os: the store was opened (and could not be read)');
        // Try again on the recovery screen keeps the lock this copy holds: it does not ask again
        await (shown.single as RecoveryApp).retry();
        expect(asked, asks, reason: '$os: Try again asked for the lock again');
      }
    });
  });

  group('C-06, screen capture', () {
    // owner, 2026-11-19: "remove this option you have that prevents screenshotting on solace": capture is never
    // blocked; "Hide in the app switcher" hides the recent-apps preview natively on Android only
    test('no device keeps Solace out of screenshots, sharing or recording; Android hides only its switcher preview', () {
      expect(hidesSwitcherPreviewNatively('android'), isTrue);
      for (final os in ['macos', 'ios', 'linux', 'windows']) {
        expect(hidesSwitcherPreviewNatively(os), isFalse, reason: os);
      }
      final mac = File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();
      final code = [for (final l in mac.split('\n')) if (!l.trimLeft().startsWith('//')) l].join('\n');
      expect(code, isNot(contains('sharingType')));
      expect(code, isNot(contains('solace/privacy')));
    });
  });

  group('C-04, one passcode check at a time', () {
    testWidgets('a try counts as a miss while its check runs, and a right code takes it back', (tester) async {
      final stored = (await tester.runAsync(() => hashPasscode('135791')))!;
      final state = flow.makeState();
      final s = state.data.settings;
      await flow.pumpApp(tester, state);
      await _lockNow(tester, s, stored);
      s.lockFails = 2;
      await tester.enterText(find.byKey(const Key('lock_code')), '135791');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(s.lockFails, 3, reason: 'the try was not counted before its check');
      await waitFor(tester, () => find.text('Solace is locked').evaluate().isEmpty, tries: 100);
      expect(find.text('Solace is locked'), findsNothing);
      expect(s.lockFails, 0);
      expect(s.lockUntil, isNull);
      expect(find.textContaining('2 wrong passcodes were tried'), findsOneWidget, reason: 'the misses before it');
    });
  });

  group('C-07, Back while locked', () {
    testWidgets('while locked the app keeps Back (so Android never closes it), and Back closes only the support sheet',
        (tester) async {
      final stored = (await tester.runAsync(() => hashPasscode('135791')))!;
      final handlesBack = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') handlesBack.add(call.arguments as bool);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final state = flow.makeState();
      await flow.pumpApp(tester, state);
      var popped = false;
      appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => PopScope(
          onPopInvokedWithResult: (didPop, _) => popped = popped || didPop,
          child: const Scaffold(body: Text('private screen')))));
      await tester.pumpAndSettle();
      handlesBack.clear();
      await _lockNow(tester, state.data.settings, stored);
      expect(handlesBack, isNotEmpty);
      expect(handlesBack.last, isTrue, reason: 'locked, Android would handle Back itself (older Android closes the app)');
      // the support sheet over the lock screen: Back closes it, and only it
      await tester.tap(find.byKey(const Key('lock_support')));
      await tester.pumpAndSettle();
      final sheets = find.byType(BottomSheet).evaluate().length;
      expect(sheets, greaterThan(0), reason: 'the support sheet opened');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing, reason: 'Back did not close the support sheet');
      expect(find.text('Solace is locked'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Solace is locked'), findsOneWidget);
      expect(popped, isFalse);
      expect(appNavigatorKey.currentState!.canPop(), isTrue);
      // unlocked again, Back works as usual
      await tester.enterText(find.byKey(const Key('lock_code')), '135791');
      await tester.tap(find.byKey(const Key('lock_unlock')));
      await waitFor(tester, () => find.text('Solace is locked').evaluate().isEmpty, tries: 100);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(popped, isTrue, reason: 'unlocked, Back no longer reached the app');
    });
  });

  group('C-10, picture tidy', () {
    test('the tidy waits for a picture being written, and asks what is in use only after listing', () async {
      final dir = await Directory.systemTemp.createTemp('r5c_media');
      addTearDown(() => dir.delete(recursive: true));
      final vault = EncryptedFileVault(keychain: _Keys(), folder: () async => dir);
      final named = <String>{};
      var written = false;
      final put = vault.putMedia(Uint8List.fromList(List<int>.filled(64, 7))).then((id) {
        written = true; // the data names it now, as AppState.setPicture does after putMedia
        named.add(id);
        return id;
      });
      var askedEarly = false;
      final tidy = vault.tidyMedia(() {
        askedEarly = !written;
        return named;
      });
      final id = await put;
      await tidy;
      expect(askedEarly, isFalse, reason: 'the tidy read what is in use before the picture being added was named');
      expect((await vault.mediaIndex()).$1, contains(id), reason: 'the picture being added was deleted as a stray');
      expect(await vault.getMedia(id), isNotNull);
    });

    test('a listing never deletes a picture write in flight; only the queued tidy removes a write cut short', () async {
      final dir = await Directory.systemTemp.createTemp('r5c_part');
      addTearDown(() => dir.delete(recursive: true));
      final vault = EncryptedFileVault(keychain: _Keys(), folder: () async => dir);
      final part = File('${dir.path}/media/${'a' * 32}.part')..createSync(recursive: true);
      await vault.mediaIndex();
      expect(part.existsSync(), isTrue, reason: 'measuring the pictures deleted a write in flight');
      await vault.tidyMedia(() => {});
      expect(part.existsSync(), isFalse);
    });
  });

  group('C-11, deleting a conversation', () {
    AppData data() {
      final d = AppData()
        ..lastNote = 'note of the second'
        ..homeworkDue = 'call my sister';
      d.sessions.addAll([
        SessionRecord(date: '2026-11-01', kind: 'daily_checkin', note: 'note of the first',
            turns: [('person', 'I want to sleep before midnight every night.'), ('therapist', 'That sounds kind.')]),
        SessionRecord(date: '2026-11-02', kind: 'daily_checkin', note: 'note of the second',
            turns: [('person', 'Honesty matters to me more than anything. I will call my sister on Sunday.')]),
      ]);
      d.plans.goals.add(Goal(text: 'Sleep earlier', quote: 'sleep before midnight', added: '2026-11-01'));
      d.plans.values.add(Value(text: 'Honesty', quote: 'Honesty matters to me', added: '2026-11-02'));
      d.plans.steps.add(Step(text: 'Call my sister', quote: 'call my sister on Sunday', added: '2026-11-02'));
      d.plans.habits.add(Habit(text: 'Bed by midnight', quote: 'sleep before midnight', start: '2026-11-01'));
      d.plans.pictures.add(Picture(title: 'A calm evening', quote: 'Honesty matters', added: '2026-11-02'));
      // the same words, but from a session on another day: not from the deleted conversation, so kept
      d.plans.goals.add(Goal(text: 'Be honest', quote: 'Honesty matters to me', added: '2026-10-20'));
      d.suggestions.add(PendingSuggestion('value', 'Family', 'call my sister', '2026-11-02'));
      return d;
    }

    test('its quoted words and its note go; the items, other conversations\' words and the story stay', () {
      final d = data()..story = Story.parse('## Who they are\nSomeone who values honesty.', [], []);
      final story = d.story.toJson().toString();
      d.deleteSessions({d.sessions[1]});
      expect(d.sessions.map((s) => s.date), ['2026-11-01']);
      expect(d.plans.values.single.quote, '', reason: 'a value quoted the deleted conversation');
      expect(d.plans.steps.single.quote, '');
      expect(d.plans.pictures.single.quote, '');
      expect(d.suggestions.single.quote, '');
      expect(d.suggestions.single.item, 'Family', reason: 'the noticed thing stays, without the words');
      expect(d.plans.values.single.text, 'Honesty', reason: 'the item itself stays');
      expect(d.plans.goals.first.quote, 'sleep before midnight', reason: 'another conversation\'s words were removed');
      expect(d.plans.habits.single.quote, 'sleep before midnight');
      expect(d.plans.goals.last.quote, 'Honesty matters to me', reason: 'same words, another day: not from it');
      expect(d.lastNote, '', reason: 'the deleted conversation\'s note would reach the model at the next session');
      expect(d.homeworkDue, '');
      expect(d.story.toJson().toString(), story, reason: 'the story cannot be split by conversation, so it stays');
    });

    test('deleting an older conversation keeps the last note, which is not its own', () {
      final d = data();
      d.deleteSessions({d.sessions[0]});
      expect(d.lastNote, 'note of the second');
      expect(d.homeworkDue, 'call my sister');
      expect(d.plans.goals.first.quote, '');
      expect(d.plans.habits.single.quote, '');
      expect(d.plans.values.single.quote, 'Honesty matters to me');
    });

    testWidgets('the confirmation says what else goes and that the story stays, and where to change it',
        (tester) async {
      final state = flow.makeState(demo: true);
      final d = data();
      state.data.sessions
        ..clear()
        ..addAll(d.sessions);
      state.data.plans.values.add(Value(text: 'Honesty', quote: 'Honesty matters to me', added: '2026-11-02'));
      state.data.lastNote = 'note of the second';
      await flow.pumpApp(tester, state);
      appNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ChooseToDeleteScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose_conversations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose_item_0'))); // newest first: the second
      await tester.pump();
      await tester.tap(find.byKey(const Key('choose_delete')));
      await tester.pumpAndSettle();
      final words = tester.widget<Text>(find.byKey(const Key('choose_delete_words'))).data!;
      expect(words, contains('cannot be undone'));
      expect(words, contains(conversationsDeleteNote));
      expect(words, contains('Your story so far'));
      await tester.tap(find.byKey(const Key('choose_delete_confirm')));
      await flow.frames(tester, ms: 600);
      expect(state.data.sessions.map((s) => s.date), ['2026-11-01']);
      expect(state.data.plans.values.last.quote, '');
      expect(state.data.lastNote, '');
    });
  });
}
