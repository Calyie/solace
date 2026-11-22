// Review cycle 2 usability (N3, and the lines N2 and N8 added): the paused trauma chat fits every phone at every text
// look, with the keyboard down and up, with Send and the red Stop on screen above the keyboard; and the states added
// since 6dcd583 fit as well (the editing bar, "Writing your session note" in the chat and on a call, the Delete
// everything card with its message, its progress line and the line after a long wait, the Receive screen's
// confirmation, progress and long-wait lines). Any overflow fails.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/model.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/call.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/home.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/transfer_screen.dart';

import 'app_flow_test.dart' as flow;
import 'responsive_test.dart' as r;
import 'review_c1_flows_test.dart' as c1;
import 'review_c2_flows_test.dart' as c2;

/// Delete everything fails the first time (a file in use); after [slow] is set it waits for it.
class SweepVault extends MemoryVault {
  Completer<void>? slow;
  @override
  Future<void> wipe() async {
    final s = slow;
    if (s == null) throw StateError('a file in use');
    await s.future;
    await super.wipe();
  }
}

/// Every phone size the app is tested at (responsive_test.dart).
final phones = {for (final e in r.sizes.entries) if (e.value.shortestSide < 500) e.key: e.value};

AppState stateFor(AppData data, Vault vault, ModelRuntime model) => AppState(data: data, vault: vault,
    prompts: c1.prompts, model: model, library: parseLibrary(File('assets/practices/library_v2.json').readAsStringSync()),
    clock: () => DateTime(2026, 11, 14, 20), fullModeKey: flow.testKey);

AppData dataFor(double appText, String font, String mode) {
  final data = AppData();
  data.settings
    ..therapistChosen = true
    ..onboarded = true
    ..ageConfirmed = true
    ..textSize = appText
    ..font = font
    ..themeMode = mode;
  return data;
}

late Uint8List transfer;
late String transferCode;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
    transferCode = TransferCode.generate();
    transfer = await TransferFile.sealInBackground(AppData()..journal.add({'date': '2026-11-12', 'text': 'X'}),
        transferCode);
  });

  for (final MapEntry(key: device, value: size) in phones.entries) {
    final portrait = size.height > size.width;
    for (final (look, deviceText, appText, font, mode) in r.looks) {
      for (final keyboard in [0.0, (size.height * (portrait ? 0.42 : 0.5)).roundToDouble()]) {
        testWidgets('$device, $look, keyboard ${keyboard == 0 ? 'down' : 'up'}: the paused trauma chat fits, Send '
            'and Stop on screen', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          tester.platformDispatcher.textScaleFactorTestValue = deviceText;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final state = stateFor(dataFor(appText, font, mode), MemoryVault(), const StandInModel());
          await tester.pumpWidget(TherapistApp(state: state));
          await tester.pumpAndSettle();
          Navigator.of(tester.element(find.byType(HomeShell))).push(MaterialPageRoute(builder: (_) =>
              const ChatScreen(kind: 'written_exposure')));
          await flow.frames(tester, ms: 800);
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3); // the keyboard comes up for the box
          await flow.frames(tester, ms: 400);
          await tester.enterText(find.byType(TextField).last, "I can't breathe, I'm back there");
          await tester.tap(find.byKey(const Key('chat_send')), warnIfMissed: false);
          await flow.frames(tester, ms: 800);
          expect(tester.takeException(), isNull, reason: 'the paused trauma chat does not fit');
          // the paused line is at the end of the conversation, in view whenever the conversation has any room (a
          // phone on its side with the keyboard up and the largest text leaves it a sliver of about 17 points)
          final list = tester.state<ScrollableState>(find.descendant(of: find.byType(ChatScreen),
              matching: find.byType(Scrollable)).first).position;
          if (list.viewportDimension >= 100) {
            expect(find.byKey(const Key('chat_paused')), findsOneWidget, reason: 'the paused line is in view');
          }
          final bottom = size.height - keyboard;
          final send = tester.getRect(find.byKey(const Key('chat_send')));
          final stop = tester.getRect(find.byKey(const Key('exercise_stop')));
          expect(send.bottom, lessThanOrEqualTo(bottom + 0.5), reason: 'Send is pushed off the screen ($send)');
          expect(stop.top, greaterThanOrEqualTo(0));
          expect(stop.bottom, lessThanOrEqualTo(bottom + 0.5), reason: 'the red Stop is off the screen ($stop)');
          await r.scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('$device, $look: the new flow states fit', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = deviceText;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final model = c2.SlowNoteModel();
        final vault = SweepVault();
        final state = stateFor(dataFor(appText, font, mode), vault, model);
        await tester.pumpWidget(TherapistApp(state: state));
        await tester.pumpAndSettle();
        final nav = Navigator.of(tester.element(find.byType(HomeShell)));
        Future<void> reveal(Finder f, Type screen) async {
          final pos = tester.state<ScrollableState>(find.descendant(of: find.byType(screen),
              matching: find.byType(Scrollable)).first).position;
          for (var y = 0.0; f.evaluate().isEmpty && y <= pos.maxScrollExtent + 80; y += 60) {
            pos.jumpTo(y.clamp(0, pos.maxScrollExtent));
            await tester.pump();
          }
          await tester.ensureVisible(f);
          await flow.frames(tester, ms: 300);
        }
        Future<void> fits(String what) async {
          await r.scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: '$what does not fit');
        }

        // a session: the editing bar, then End's "Writing your session note", then the summary
        nav.push(MaterialPageRoute(builder: (_) => const ChatScreen(kind: 'daily_checkin')));
        await flow.frames(tester, ms: 800);
        await tester.enterText(find.byType(TextField).last, 'Work was hard todya.');
        await tester.tap(find.byKey(const Key('chat_send')));
        await flow.frames(tester, ms: 800);
        final sent = find.text('Work was hard todya.');
        final pos = tester.state<ScrollableState>(find.descendant(of: find.byType(ChatScreen),
            matching: find.byType(Scrollable)).first).position;
        for (var y = 0.0; sent.evaluate().isEmpty && y <= pos.maxScrollExtent + 80; y += 60) {
          pos.jumpTo(y.clamp(0, pos.maxScrollExtent));
          await tester.pump();
        }
        await tester.ensureVisible(sent);
        await flow.frames(tester, ms: 400);
        await tester.longPress(sent);
        await flow.frames(tester, ms: 600);
        await tester.tap(find.byKey(const Key('edit_message')));
        await flow.frames(tester, ms: 600);
        expect(find.byKey(const Key('chat_editing')), findsOneWidget);
        await fits('the editing bar');
        await tester.tap(find.byKey(const Key('chat_edit_cancel')));
        await flow.frames(tester, ms: 600);
        await tester.tap(find.text('End'));
        await flow.frames(tester, ms: 800);
        await tester.ensureVisible(find.byKey(const Key('end_confirm')));
        await flow.frames(tester, ms: 400);
        await tester.tap(find.byKey(const Key('end_confirm')));
        await flow.frames(tester, ms: 800);
        expect(find.byKey(const Key('chat_writing_note')), findsOneWidget);
        await fits('"Writing your session note" in the chat, the box closed');
        model.release();
        await flow.frames(tester, ms: 1200);
        await fits('the summary after End');
        Navigator.of(tester.element(find.byType(SessionSummary))).pop();
        await flow.frames(tester, ms: 1200);

        // a call (no voice on this device) while End writes the note, with words waiting for room in its box
        final model2 = c2.SlowNoteModel();
        final s = SessionController(model: model2, prompts: c1.prompts, data: state.data, vault: state.vault,
            clock: state.clock);
        await s.start('daily_checkin');
        await s.send('Work was hard today.');
        nav.push(MaterialPageRoute(builder: (_) => CallScreen(kind: 'daily_checkin', controller: s,
            draft: 'D' * 7000, heldDraft: ['N' * 6000])));
        await flow.frames(tester, ms: 800);
        expect(find.byKey(const Key('call_held')), findsOneWidget);
        await fits('the call with words waiting');
        await tester.tap(find.byKey(const Key('call_end')));
        await flow.frames(tester, ms: 600);
        // words are waiting: End asks first, and that question must fit too
        expect(find.text('End the call?'), findsOneWidget);
        await fits('the call asking before unsent words are lost');
        await tester.tap(find.byKey(const Key('call_end_anyway')));
        await flow.frames(tester, ms: 800);
        expect(find.textContaining('Writing your session note'), findsWidgets);
        await fits('the call writing its note');
        model2.release();
        await flow.frames(tester, ms: 1200);
        Navigator.of(tester.element(find.byType(SessionSummary))).pop();
        await flow.frames(tester, ms: 1200);

        // Settings: the Delete everything card, its message when it could not finish, its progress line, and the
        // line after a long wait
        nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        await flow.frames(tester, ms: 800);
        final open = find.text('Delete everything the app knows about me');
        await tester.scrollUntilVisible(open, 300,
            scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
        await tester.ensureVisible(open);
        await flow.frames(tester, ms: 400);
        await tester.tap(open);
        await flow.frames(tester, ms: 600);
        await tester.ensureVisible(find.byKey(const Key('wipe_confirm')));
        await flow.frames(tester, ms: 400);
        await tester.tap(find.byKey(const Key('wipe_confirm')));
        await flow.frames(tester, ms: 800);
        expect(find.byKey(const Key('wipe_message')), findsOneWidget);
        await fits('the Delete everything card with its message');
        vault.slow = Completer<void>();
        await reveal(find.byKey(const Key('wipe_confirm')), SettingsScreen);
        await tester.tap(find.byKey(const Key('wipe_confirm')));
        await flow.frames(tester, ms: 400);
        await reveal(find.byKey(const Key('wipe_progress')), SettingsScreen);
        expect(find.byKey(const Key('wipe_progress')), findsOneWidget);
        expect(find.byTooltip('Support'), findsOneWidget);
        await fits('the Delete everything progress line');
        await tester.pump(longDataWait);
        await flow.frames(tester, ms: 400);
        await reveal(find.textContaining('You can go back now'), SettingsScreen);
        expect(find.textContaining('You can go back now'), findsOneWidget);
        await fits('the Delete everything line after a long wait');
        await tester.binding.handlePopRoute();
        await flow.frames(tester, ms: 800);
        expect(find.byType(SettingsScreen), findsNothing);

        // Receive: the confirmation card (a file that is not a transfer file)
        nav.push(MaterialPageRoute(builder: (_) =>
            ReceiveFromDeviceScreen(pick: () async => PickedTransfer.fromBytes(Uint8List(64)))));
        await flow.frames(tester, ms: 800);
        await reveal(find.byKey(const Key('transfer_pick')), ReceiveFromDeviceScreen);
        await tester.tap(find.byKey(const Key('transfer_pick')));
        await flow.frames(tester, ms: 400);
        await reveal(find.byKey(const Key('transfer_code')), ReceiveFromDeviceScreen);
        await tester.enterText(find.byKey(const Key('transfer_code')), 'ABCD EFGH JKLM NPQR');
        await flow.frames(tester, ms: 400);
        await reveal(find.byKey(const Key('transfer_open')), ReceiveFromDeviceScreen);
        await tester.tap(find.byKey(const Key('transfer_open')));
        await flow.frames(tester, ms: 600);
        expect(find.byKey(const Key('transfer_replace')), findsOneWidget);
        await fits('the Receive confirmation');
        nav.pop();
        await flow.frames(tester, ms: 800);
        // the Delete everything left running ends; the app starts again at its first steps
        vault.slow!.complete();
        await flow.frames(tester, ms: 1200);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$device, $look: the Receive progress and long-wait lines fit', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = deviceText;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final vault = c2.SlowSaveVault();
        final state = stateFor(dataFor(appText, font, mode), vault, const StandInModel());
        await tester.pumpWidget(TherapistApp(state: state));
        await tester.pumpAndSettle();
        final nav = Navigator.of(tester.element(find.byType(HomeShell)));
        nav.push(MaterialPageRoute(builder: (_) =>
            ReceiveFromDeviceScreen(pick: () async => PickedTransfer.fromBytes(transfer))));
        await flow.frames(tester, ms: 800);
        Future<void> reveal(Finder f) => tester.scrollUntilVisible(f, 120, scrollable: find.descendant(
            of: find.byType(ReceiveFromDeviceScreen), matching: find.byType(Scrollable)).first);
        Future<void> tapShown(Key key) async {
          await reveal(find.byKey(key));
          await tester.ensureVisible(find.byKey(key));
          await flow.frames(tester, ms: 300);
          await tester.tap(find.byKey(key));
          await flow.frames(tester, ms: 400);
        }

        await tapShown(const Key('transfer_pick'));
        await reveal(find.byKey(const Key('transfer_code')));
        await tester.enterText(find.byKey(const Key('transfer_code')), transferCode);
        await flow.frames(tester, ms: 300);
        await tapShown(const Key('transfer_open'));
        vault.gate = Completer<void>(); // the save of what comes in waits
        await tapShown(const Key('transfer_replace'));
        for (var i = 0; i < 100 && state.data.journal.isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump();
        }
        await reveal(find.byKey(const Key('transfer_progress')));
        expect(find.byKey(const Key('transfer_progress')), findsOneWidget);
        await r.scrollThrough(tester);
        expect(tester.takeException(), isNull, reason: 'the Receive progress line does not fit');
        await tester.pump(longDataWait);
        await flow.frames(tester, ms: 300);
        await reveal(find.byKey(const Key('transfer_long')));
        expect(find.byKey(const Key('transfer_long')), findsOneWidget);
        await r.scrollThrough(tester);
        expect(tester.takeException(), isNull, reason: 'the Receive long-wait line does not fit');
        vault.gate!.complete();
        for (var i = 0; i < 50 && find.byKey(const Key('transfer_progress')).evaluate().isNotEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await flow.frames(tester, ms: 400);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a phone on its side with the keyboard up: the side rail scrolls instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 2.75;
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(tester.view.reset);
    final state = flow.makeState();
    await tester.pumpWidget(TherapistApp(state: state));
    await flow.frames(tester, ms: 1500);
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}
