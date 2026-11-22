// Round 9 review, 9A-02: once past the lock nothing asked again. Now turning the app lock off, turning "Hide in the
// app switcher" off, Send everything (its file and code) and Delete everything first ask for the lock's own unlock
// (ui/app_lock.dart confirmItIsYou): the app passcode, the lock's only unlock on every device (owner, 2026-11-15),
// checked as the lock screen checks it, with the same count of wrong tries and the same wait. The right passcode lets
// the change through; a wrong one or Cancel changes nothing; with the app lock off nothing is asked. (The reviewer's
// own tests, test/review9a/lock_off_without_passcode_test.dart, check that nothing changes before a passcode.)
// Round 9 re-check: the clinician PDF, CSV and Markdown exports, a longer "Lock after" and Bring everything ask too
// (test/review9a/export_without_passcode_test.dart is the reviewer's proof for the exports).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart' show PickedTransfer;
import 'package:solace/ui/app_lock.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/transfer_screen.dart';
import 'package:solace/ui/your_data.dart';

import 'app_flow_test.dart' as flow;

const _code = '482916';
final _box = find.byKey(const Key('confirm_passcode'));

/// Types [code] and presses Confirm. The check (Argon2, about 0.2 s) runs in real time, outside the test's simulated
/// clock, until it has saved its count (or, during the wait, at most a second).
Future<void> _confirm(WidgetTester tester, AppState state, String code) async {
  await tester.enterText(_box, code);
  var saved = false;
  void heard() => saved = true;
  state.addListener(heard);
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('confirm_passcode_ok')));
    for (var i = 0; i < 20 && !saved; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  state.removeListener(heard);
  await tester.pumpAndSettle();
}

/// Waits (real time) until [done], pumping frames.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  setUpAll(flow.loadFonts);
  late Map<String, String> passcode;
  setUpAll(() async => passcode = await hashPasscode(_code));
  setUp(forgetLockWaitForTest);

  AppState locked({bool demo = false, Vault? vault}) {
    final state = flow.makeState(demo: demo, vault: vault ?? MemoryVault());
    state.data.settings
      ..appLock = true
      ..passcode = passcode
      ..hideInSwitcher = true;
    return state;
  }

  testWidgets('the lock: a wrong passcode leaves it on and counts a miss; the right one turns it off', (tester) async {
    final vault = MemoryVault();
    final state = locked(vault: vault);
    await flow.pumpScreen(tester, state, const SettingsScreen());
    await flow.tapIn(tester, find.byKey(const Key('app_lock')));
    expect(_box, findsOneWidget, reason: 'the passcode is asked for');
    expect(find.text('Type your Solace passcode to turn the lock off.'), findsOneWidget);
    await _confirm(tester, state, '111111');
    expect(find.text('That passcode did not match. Try again.'), findsOneWidget);
    expect(state.data.settings.appLock, isTrue);
    expect(state.data.settings.lockFails, 1, reason: 'the lock screen\'s own count');
    expect((await vault.load()).settings.lockFails, 1, reason: 'and saved, so closing the app does not reset it');
    await _confirm(tester, state, _code);
    await _until(tester, () => !state.data.settings.appLock);
    expect(_box, findsNothing);
    expect(state.data.settings.appLock, isFalse);
    expect((await vault.load()).settings.appLock, isFalse);
    expect(state.data.settings.lockFails, 0);
    expect(find.textContaining('a wrong passcode was entered 1 time'), findsOneWidget,
        reason: 'wrong tries before the right one are told, as after unlocking');
  });

  testWidgets('the lock: Cancel leaves it on', (tester) async {
    final state = locked();
    await flow.pumpScreen(tester, state, const SettingsScreen());
    await flow.tapIn(tester, find.byKey(const Key('app_lock')));
    await tester.tap(find.byKey(const Key('confirm_passcode_cancel')));
    await tester.pumpAndSettle();
    expect(_box, findsNothing);
    expect(state.data.settings.appLock, isTrue);
    expect(state.data.settings.lockFails, 0);
  });

  testWidgets('after five wrong passcodes the wait holds here too, the right one included', (tester) async {
    final state = locked();
    await flow.pumpScreen(tester, state, const SettingsScreen());
    await flow.tapIn(tester, find.byKey(const Key('app_lock')));
    for (var i = 0; i < 5; i++) {
      await _confirm(tester, state, '11111$i');
      expect(state.data.settings.lockFails, i + 1);
    }
    expect(state.data.settings.lockUntil, isNotNull, reason: 'the lock screen\'s wait started');
    await _confirm(tester, state, _code);
    expect(find.textContaining('Too many tries. Try again in'), findsOneWidget);
    expect(state.data.settings.appLock, isTrue, reason: 'not even the right passcode during the wait');
  });

  testWidgets('Hide in the app switcher: off with the right passcode; on again needs nothing', (tester) async {
    final state = locked();
    await flow.pumpScreen(tester, state, const SettingsScreen());
    await flow.tapIn(tester, find.byKey(const Key('hide_switcher')));
    expect(find.text('Type your Solace passcode to show Solace in the app switcher.'), findsOneWidget);
    await _confirm(tester, state, _code);
    await _until(tester, () => !state.data.settings.hideInSwitcher);
    expect(state.data.settings.hideInSwitcher, isFalse);
    await flow.tapIn(tester, find.byKey(const Key('hide_switcher')));
    expect(_box, findsNothing);
    expect(state.data.settings.hideInSwitcher, isTrue);
  });

  testWidgets('Send everything: Cancel makes nothing; the right passcode makes the file and shows its code',
      (tester) async {
    final state = locked(demo: true);
    Uint8List? file;
    await flow.pumpScreen(tester, state, SendToDeviceScreen(save: (name, bytes) async {
      file = bytes;
      return true;
    }));
    await tester.tap(find.byKey(const Key('transfer_make')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_passcode_cancel')));
    await tester.pumpAndSettle();
    expect(file, isNull);
    expect(find.byKey(const Key('transfer_code_shown')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('transfer_make'))).onPressed, isNotNull,
        reason: 'it can be asked for again');
    await tester.tap(find.byKey(const Key('transfer_make')));
    await tester.pumpAndSettle();
    expect(find.text('Type your Solace passcode to make a file with everything.'), findsOneWidget);
    await _confirm(tester, state, _code);
    await flow.settleReal(tester, find.byKey(const Key('transfer_code_shown')));
    expect(file, isNotNull);
    expect(find.byKey(const Key('transfer_code_shown')), findsOneWidget);
  });

  testWidgets('Delete everything: Cancel deletes nothing; the right passcode deletes everything', (tester) async {
    final state = locked(demo: true);
    final sessions = state.data.sessions.length;
    await flow.pumpScreen(tester, state, const SettingsScreen());
    final open = find.text('Delete everything the app knows about me');
    await tester.scrollUntilVisible(open, 300, scrollable: find.byType(Scrollable).first);
    await flow.tapIn(tester, open);
    await flow.tapIn(tester, find.byKey(const Key('wipe_confirm')));
    expect(find.text('Type your Solace passcode to delete everything.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_passcode_cancel')));
    await tester.pumpAndSettle();
    expect(state.data.sessions, hasLength(sessions));
    await flow.tapIn(tester, find.byKey(const Key('wipe_confirm')));
    await _confirm(tester, state, _code);
    await _until(tester, () => state.data.sessions.isEmpty);
    expect(state.data.sessions, isEmpty);
  });

  for (final (key, what, name) in [
    ('export_pdf', 'make the summary for a clinician', 'wellbeing-summary-'),
    ('export_csv', 'make a spreadsheet of your records', 'my-records-'),
    ('export_md', 'make a text file of your records', 'my-records-'),
  ]) {
    testWidgets('Your data, $key: Cancel makes nothing; the right passcode makes the file', (tester) async {
      final state = locked(demo: true);
      state.data.journal.add({'date': '2026-11-20', 'text': 'my most private words'});
      final made = <String, Uint8List>{};
      await flow.pumpScreen(tester, state, YourDataScreen(save: (name, bytes, mime) async {
        made[name] = bytes;
        return 'Saved as $name.';
      }));
      await flow.tapIn(tester, find.byKey(const Key('note_journal:0')));
      await flow.tapIn(tester, find.byKey(Key(key)));
      expect(find.text('Type your Solace passcode to $what.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_passcode_cancel')));
      await tester.pumpAndSettle();
      expect(made, isEmpty, reason: 'nothing made or handed to the save dialog');
      expect(find.byKey(const Key('export_message')), findsNothing);
      expect(state.data.settings.lockFails, 0);
      await flow.tapIn(tester, find.byKey(Key(key)));
      await _confirm(tester, state, _code);
      await flow.settleReal(tester, find.byKey(const Key('export_message')));
      expect(made.keys.single, startsWith(name));
      if (key != 'export_pdf') expect(utf8.decode(made.values.single), contains('my most private words'));
      expect(find.textContaining('Saved as $name'), findsOneWidget);
    });
  }

  testWidgets('Lock after: longer only with the right passcode (Cancel keeps it); shorter needs nothing',
      (tester) async {
    final vault = MemoryVault();
    final state = locked(vault: vault);
    state.data.settings.lockAfterMinutes = 1;
    await flow.pumpScreen(tester, state, const SettingsScreen());
    final menu = find.descendant(of: find.widgetWithText(ListTile, 'Lock after'),
        matching: find.byType(DropdownButton<int>));
    Future<void> choose(String label) async {
      await flow.tapIn(tester, menu);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('15 minutes');
    expect(find.text('Type your Solace passcode to keep Solace unlocked longer.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_passcode_cancel')));
    await tester.pumpAndSettle();
    expect(state.data.settings.lockAfterMinutes, 1, reason: 'Cancel changes nothing');
    await choose('15 minutes');
    await _confirm(tester, state, '111111');
    expect(find.text('That passcode did not match. Try again.'), findsOneWidget);
    expect(state.data.settings.lockAfterMinutes, 1, reason: 'nor does a wrong passcode');
    await _confirm(tester, state, _code);
    await _until(tester, () => state.data.settings.lockAfterMinutes == 15);
    expect(state.data.settings.lockAfterMinutes, 15);
    expect((await vault.load()).settings.lockAfterMinutes, 15);
    await choose('At once');
    expect(_box, findsNothing, reason: 'locking sooner asks nothing');
    expect(state.data.settings.lockAfterMinutes, 0);
  });

  testWidgets('Bring everything: Cancel and a wrong passcode change nothing; the right one brings it in',
      (tester) async {
    final from = flow.makeState(demo: true); // the other device, its lock off
    Uint8List? file;
    await flow.pumpScreen(tester, from, SendToDeviceScreen(save: (name, bytes) async {
      file = bytes;
      return true;
    }));
    await tester.tap(find.byKey(const Key('transfer_make')));
    await flow.settleReal(tester, find.byKey(const Key('transfer_code_shown')));
    final code = tester.widget<Text>(find.byKey(const Key('transfer_code_shown'))).data!;

    final state = locked();
    expect(state.data.sessions, isEmpty);
    await flow.pumpScreen(tester, state, ReceiveFromDeviceScreen(pick: () async => PickedTransfer.fromBytes(file!)));
    await tester.tap(find.byKey(const Key('transfer_pick')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('transfer_code')), code);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transfer_open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transfer_replace')));
    await tester.pumpAndSettle();
    expect(find.text('Type your Solace passcode to replace everything on this device.'), findsOneWidget);
    await _confirm(tester, state, '111111');
    expect(find.text('That passcode did not match. Try again.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_passcode_cancel')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500))); // time for a wrong import
    await tester.pumpAndSettle();
    expect(state.data.sessions, isEmpty, reason: 'nothing brought in');
    expect(find.byKey(const Key('transfer_progress')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('transfer_replace'))).onPressed, isNotNull,
        reason: 'it can be asked for again');
    await tester.tap(find.byKey(const Key('transfer_replace')));
    await tester.pumpAndSettle();
    await _confirm(tester, state, _code);
    await flow.settleReal(tester, find.textContaining('Done.'));
    expect(state.data.sessions, hasLength(from.data.sessions.length));
    expect(state.data.settings.appLock, isTrue, reason: 'this device keeps its own lock');
  });

  testWidgets('with the app lock off nothing is asked', (tester) async {
    final state = flow.makeState(vault: MemoryVault())..data.settings.hideInSwitcher = true;
    await flow.pumpScreen(tester, state, const SettingsScreen());
    await flow.tapIn(tester, find.byKey(const Key('hide_switcher')));
    await _until(tester, () => !state.data.settings.hideInSwitcher);
    expect(_box, findsNothing);
    expect(state.data.settings.hideInSwitcher, isFalse);
  });
}
