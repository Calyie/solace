// Audit 216, auditor X, G7-06 ("Setting the clock back kept the app lock open", tracker: Fixed).
//
// The fix measures time away by the wall clock and by a Dart Stopwatch, whichever says more, and treats a wall clock
// that fell behind the stopwatch as time passed (ui/app_lock.dart timePassed). The tracker's own note says the part
// that needs the platform's boot clock was not done: the Stopwatch does not count time the device spends asleep
// (CLOCK_MONOTONIC on Android and Linux stops in suspend). So on a phone that slept while Solace was in the background,
// both measures can be made to say "no time passed": the stopwatch because the device slept, the wall clock because
// someone set it back to just after the owner left. SECURITY.md section 4 says without that caveat that "setting the
// device clock neither keeps the lock from coming down ...".
//
// Scenario: lock on, "Lock after" 5 minutes. The owner leaves Solace at 14:00 and puts the phone down; it sleeps. At
// 14:10 someone who knows the phone's own passcode (not Solace's) unlocks the phone, sets its clock to 14:00:30 and
// opens Solace. The stopwatch moved about 2 seconds (asleep), the wall clock 30 seconds: Solace opens unlocked.
//
// The second half of G7-06 ("the passcode wait follows the clock too") holds only while Solace runs: the code says "A
// clock set forward while Solace was closed can still end a saved wait early" (ui/app_lock.dart lockWait). At the
// locked app, after five wrong passcodes, closing Solace from the app switcher and setting the clock forward (no phone
// passcode is asked for either) ends the wait, so the wait never slows guessing.
//
// These tests assert the SAFE behaviour, so they fail on c7f6680 while the gaps stand.
//
// Fix (audit 216): the lock's monotonic measure is now the device's boot clock where it can be read (core/boot_clock.dart:
// it counts time asleep and cannot be set). The second test first gave the two LockMoments literal numbers for the
// stopwatch (100 s, then 102 s); with the boot clock those numbers can no longer happen (that clock would read 700 s),
// and timePassed sees only the two moments, so the scenario is now driven through the clocks themselves: the wall
// clock set by the test, the boot clock swapped for one the test moves. Its assertion is unchanged. A control shows
// that where no boot clock can be read, the lock falls back to the stopwatch and the gap stays, as before.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/boot_clock.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/app_lock.dart';

/// The wall clock set by the test; the monotonic measure is the real LockClock's (the boot clock, or the stopwatch).
class _Wall extends LockClock {
  _Wall(this.now);
  DateTime now;
  @override
  DateTime wall() => now;
}

void main() {
  test('G7-06: the passcode wait after five misses is not ended by closing Solace and setting the clock forward', () {
    final s = Settings();
    final t = DateTime(2026, 11, 16, 14, 0);
    for (var i = 0; i < 5; i++) {
      recordLockFail(s, t, mono: const Duration(seconds: 100));
    }
    expect(lockWait(s, t, mono: const Duration(seconds: 100)), const Duration(seconds: 30), reason: 'precondition');
    forgetLockWaitForTest(); // Solace closed from the app switcher and opened again: a new process, a new stopwatch
    final forward = t.add(const Duration(hours: 1)); // the clock set forward meanwhile; 5 real seconds have passed
    expect(lockWait(s, forward, mono: const Duration(seconds: 5)), isNotNull,
        reason: 'the saved 30-second wait ended at once, so the next passcode can be tried straight away');
  });

  group('the phone asleep', () {
    final left = DateTime(2026, 11, 16, 14, 0);
    late _Wall wall;
    setUp(() => lockClock = wall = _Wall(left));
    tearDown(() {
      lockClock = const LockClock();
      bootClock = readBootClock;
    });

    test('G7-06: ten real minutes away with the phone asleep, then the clock set back, still brings the lock down', () {
      var boot = const Duration(seconds: 100);
      bootClock = () => boot;
      final away = lockNow();
      // 10 minutes later in real time; the device slept (the stopwatch would have moved ~2 s, the boot clock counts
      // all 600 s); the clock was set to 14:00:30
      boot += const Duration(minutes: 10);
      wall.now = left.add(const Duration(seconds: 30));
      final back = lockNow();
      expect(timePassed(away, const Duration(minutes: 5), back), isTrue,
          reason: 'neither measure saw the 10 minutes: the stopwatch does not count sleep and the wall clock was set '
              'back, so the 5-minute lock stays open (the fix note: "Time asleep on a phone needs the platform\'s boot '
              'clock (native; not done)")');
    });

    test('control: where no boot clock can be read, the stopwatch and the wall clock are used, as before', () {
      bootClock = () => null;
      final away = lockNow();
      wall.now = left.add(const Duration(seconds: 30)); // the stopwatch moves only the test's own few milliseconds
      expect(timePassed(away, const Duration(minutes: 5), lockNow()), isFalse,
          reason: 'the fallback is the old behaviour; the gap stays only on a device with no boot clock');
    });
  });
}
