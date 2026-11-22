// Round 7 review A, G7-06 device proof (Android emulator, a throwaway test build): the real app shell (TherapistApp,
// AppLockGate, the real lock screen) over a memory store with the app lock already on, an app passcode of 123456 and
// "Lock after: 1 minute", so the lock can be driven by adb without going through the first-run steps. Nothing else is
// changed. Built only with `flutter build apk -t test/review7a/lock_clock_main.dart` for the emulator; never shipped.
// Not a test (no _test suffix), so the suite never runs it. Since the round 7 fix the lock takes its clocks from
// ui/app_lock.dart lockClock, and test/round7_data_fixes_test.dart covers G7-06 with set clocks.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/app_lock.dart';
import 'package:solace/core/library.dart';
import 'package:solace/core/formats.dart' show Prompts;
import 'package:solace/core/model.dart';
import 'package:solace/core/store.dart';
import 'package:solace/main.dart' show TherapistApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prompts = Prompts(
    system: await rootBundle.loadString('assets/prompts/app_system_v4.txt'),
    note: await rootBundle.loadString('assets/prompts/app_note_v4.txt'),
    story: await rootBundle.loadString('assets/prompts/app_story_v4.txt'),
    split: await rootBundle.loadString('assets/prompts/app_split_v1.txt'),
  );
  final library = parseLibrary(await rootBundle.loadString('assets/practices/library_v2.json'));
  final data = AppData()
    ..settings.onboarded = true
    ..settings.ageConfirmed = true
    ..settings.therapistChosen = true
    ..settings.remindersOn = false
    ..settings.appLock = true
    ..settings.lockAfterMinutes = 1
    ..settings.passcode = await hashPasscode('123456')
    ..lastNote = 'Talked about: PRIVATE SESSION NOTE';
  final state = AppState(data: data, vault: MemoryVault(), prompts: prompts, model: const StandInModel(),
      library: library);
  runApp(TherapistApp(state: state));
}
