// Space Solace uses (owner, 2026-11-14): its own data stays within a limit with room for a great many conversations;
// near and at the limit it says so; older conversations can be deleted after keeping a copy, and nothing else goes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/media.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/storage.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/choose_to_delete.dart';
import 'package:solace/ui/model_files.dart' show notEnoughSpace;
import 'package:solace/ui/storage.dart';

import 'app_flow_test.dart' as flow;

class SizedVault extends MemoryVault {
  SizedVault(this.size);
  int size;
  @override
  int get savedBytes => size;
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  const gb = 1024 * 1024 * 1024;
  // owner, 2026-11-19 (MM-11): "the app should not read the device memory and say the memory is full. That is private
  // and should not be read or at least not reported": Solace's own room is a fixed 2 GB, and how full it is depends
  // on Solace's own data only
  test('Solace\'s own room is a fixed 2 GB; it warns at 80 percent and is full at the limit, whatever the device has',
      () {
    expect(solaceAllowance, 2 * gb);
    expect(spaceState(1024, 0), SpaceState.fine);
    expect(spaceState(1024, (solaceAllowance * 0.85).round()), SpaceState.nearlyFull);
    expect(spaceState(1024, solaceAllowance), SpaceState.full);
    expect(spaceState(storeCeiling, 0), SpaceState.full, reason: 'the conversation store stays quick to save');
    expect(mayAddPicture(1024, 0), isTrue);
    expect(mayAddPicture(1024, solaceAllowance), isFalse, reason: 'no new pictures once Solace\'s own room is full');
    expect(megabytes(5 * 1024 * 1024 + 300000), '5.3 MB');
    expect(megabytes(2 * gb), '2.0 GB');
  });

  test('nothing but the silent check before a model or bundle copy reads the device\'s space (MM-11)', () {
    // readSpace (core/media.dart) is the one reader; only the add-files step uses it, and its message has no numbers
    final uses = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('core/media.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trimLeft().startsWith('//') && lines[i].contains('readSpace')) uses.add(f.path);
      }
    }
    expect(uses.toSet(), {'lib/ui/model_files.dart'});
    expect(notEnoughSpace, "There isn't enough free space to add this file.");
    for (final f in ['lib/ui/storage.dart', 'lib/ui/home.dart', 'lib/ui/settings.dart', 'lib/ui/vision_board.dart']) {
      expect(File(f).readAsStringSync(), isNot(matches(RegExp(r'This device(:| itself)|low on space|free of'))),
          reason: f);
    }
  });

  test('pictures live in their own encrypted files; transfers carry them inline; strays are tidied', () async {
    final state = flow.makeState();
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5]);
    await state.setPicture('Sea', png);
    expect(state.data.photos['Sea'], startsWith(mediaPrefix));
    expect(state.data.toJson().toString(), isNot(contains('iVBOR')), reason: 'not inside the store');
    expect(await state.picture('Sea'), png);
    final copy = await state.dataForTransfer();
    expect(base64Decode(copy.photos['Sea']!), png);
    expect(state.data.photos['Sea'], startsWith(mediaPrefix), reason: 'the copy, not the data, is changed');
    // an older store with an inline picture is moved apart
    state.data.photos['Old'] = base64Encode(png);
    await state.keepPicturesApart();
    expect(state.data.photos['Old'], startsWith(mediaPrefix));
    final orphan = await state.vault.putMedia(png);
    await state.tidyPictures();
    expect((await state.vault.mediaIndex()).$1, isNot(contains(orphan)));
    await state.deletePicture('Sea');
    expect(state.data.photos.containsKey('Sea'), isFalse);
    expect((await state.vault.mediaIndex()).$1, hasLength(1));
  });

  test('when the room is full a conversation to keep cannot start, but one off the record can', () async {
    final state = flow.makeState(vault: SizedVault(storeCeiling));
    await expectLater(state.newSession().start('daily_checkin'), throwsA(isA<GateClosed>()));
    await state.newSession().start('daily_checkin', offRecord: true);
  });

  test('deleting older conversations keeps moods, scores, plans and the safety plan', () {
    final d = AppData()
      ..sessions.addAll([
        SessionRecord(date: '2025-01-10', kind: 'daily_checkin', turns: [], note: 'old'),
        SessionRecord(date: '2026-10-01', kind: 'daily_checkin', turns: [], note: 'recent'),
      ])
      ..moods['2025-01-10'] = 4
      ..scores.add({'date': '2025-01-10', 'name': 'PHQ-9', 'total': 9, 'items': []})
      ..safetyPlan.add('people', 'Sam', '2025-01-10');
    final cutoff = DateTime(2026, 5, 14);
    expect(conversationsBefore(d, cutoff), 1);
    expect(deleteConversationsBefore(d, cutoff), 1);
    expect(d.sessions.single.note, 'recent');
    expect(d.moods, hasLength(1));
    expect(d.scores, hasLength(1));
    expect(d.safetyPlan.of('people'), ['Sam']);
  });

  testWidgets('nearly full: a gentle note on Today; the screen shows the room and deletes older conversations',
      (tester) async {
    final state = flow.makeState(demo: true, vault: SizedVault((storeCeiling * 0.9).round()));
    state.data.sessions.add(SessionRecord(date: '2024-03-01', kind: 'daily_checkin', turns: [], note: 'x'));
    await flow.pumpApp(tester, state);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('space_note')), findsOneWidget);
    expect(find.text('Solace\'s space is nearly full'), findsOneWidget);
    await tester.tap(find.byKey(const Key('space_note')));
    await flow.frames(tester, ms: 600);
    expect(find.byType(StorageScreen), findsOneWidget);
    for (var i = 0; i < 20 && find.text('Conversations').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); // the measuring isolate
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Conversations'), findsOneWidget);
    expect(find.textContaining('Solace\'s own space is nearly full'), findsOneWidget);
    expect(find.textContaining('This device'), findsNothing, reason: 'nothing about the device\'s own space');
    await tester.scrollUntilVisible(find.byKey(const Key('storage_older_12')), 300,
        scrollable: find.descendant(of: find.byType(StorageScreen), matching: find.byType(Scrollable)).first);
    // built is not the same as on screen: bring the whole row into view (with Inter's line heights it was built with
    // its middle on the screen's bottom edge)
    await tester.ensureVisible(find.byKey(const Key('storage_older_12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('storage_older_12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('storage_delete_confirm')));
    await flow.frames(tester, ms: 600);
    expect(find.textContaining('Deleted 1 older conversation'), findsOneWidget);
  });

  testWidgets('MM-11: a device that is nearly full shows no note when Solace\'s own data is small', (tester) async {
    // the owner's Mac at 98 percent full had "Solace's space is nearly full" on Today; the device's space is no longer
    // read for any note, so a nearly full device with little Solace data shows none
    spaceForTests = () async => (500 * gb, 10 * gb);
    addTearDown(() => spaceForTests = null);
    final state = flow.makeState(demo: true, vault: SizedVault(20 * 1024 * 1024));
    await flow.pumpApp(tester, state);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('space_note')), findsNothing);
    expect(find.textContaining('nearly full'), findsNothing);
  });

  testWidgets('choose what to delete: tick two conversations and delete exactly those', (tester) async {
    final state = flow.makeState(demo: true);
    state.data.sessions
      ..clear()
      ..addAll([
        for (var i = 1; i <= 3; i++) SessionRecord(date: '2026-11-0$i', kind: 'daily_checkin', turns: [('person', 'day $i')],
            note: ''),
      ]);
    await flow.pumpApp(tester, state);
    final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
    nav.push(MaterialPageRoute(builder: (_) => const ChooseToDeleteScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose_conversations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose_item_0'))); // newest first: day 3
    await tester.tap(find.byKey(const Key('choose_item_2'))); // day 1
    await tester.pump();
    expect(find.text('Delete 2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('choose_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose_delete_confirm')));
    await flow.frames(tester, ms: 600);
    expect(state.data.sessions.map((s) => s.date), ['2026-11-02']);
    expect(find.textContaining('Deleted 2 items'), findsOneWidget);
  });
}
