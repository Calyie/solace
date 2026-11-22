// Round 9 review A, re-check of 9A-02 (the fix in 18855ff guards turning the lock off, turning "Hide in the app
// switcher" off, Send everything and Delete everything, ui/app_lock.dart confirmItIsYou): the exports were part of the
// finding ("The CSV, Markdown and clinician PDF exports are the same") and are still made with nothing asked
// (ui/your_data.dart _export, reached from Settings, the Progress tab, Private by design and Space Solace uses). With
// every note ticked they carry every journal entry and feeling note, the moods, and every questionnaire answer
// (PHQ-9's item 9 included), outside Solace's encryption. This test asserts the SAFE behaviour (the passcode is asked
// first and nothing is made before it), so it fails while the gap stands.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/your_data.dart';

import '../app_flow_test.dart' as flow;

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  late Map<String, String> passcode;
  setUpAll(() async => passcode = await hashPasscode('482916'));

  for (final what in ['export_csv', 'export_md']) {
    testWidgets('9A-02 re-check: $what is not made without the passcode', (tester) async {
      final state = flow.makeState(demo: true, vault: MemoryVault());
      state.data.settings
        ..appLock = true
        ..passcode = passcode;
      state.data.journal.add({'date': '2026-11-20', 'text': 'my most private words'});
      Uint8List? made;
      await flow.pumpScreen(tester, state, YourDataScreen(save: (name, bytes, mime) async {
        made = bytes;
        return 'Saved as $name.';
      }));
      await flow.tapIn(tester, find.byKey(const Key('note_journal:0'))); // every note may be ticked
      await flow.tapIn(tester, find.byKey(Key(what)));
      await flow.settleReal(tester, find.byKey(const Key('export_message')));
      expect(made == null && find.byKey(const Key('confirm_passcode')).evaluate().isNotEmpty, isTrue,
          reason: 'the file was made and handed to the save dialog with no passcode asked'
              '${made == null ? '' : ' (${made!.length} bytes; holds the journal entry: '
                  '${utf8.decode(made!).contains('my most private words')})'}');
    });
  }
}
