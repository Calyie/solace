// Review round 10 A, G7-06 verification: the saved passcode wait is never shortened by any mix of clock changes,
// device restarts and Solace being killed (the claim of bd55460 and cbcd4a6).
//
// A random walk over the events the brief names, driven through the real lockWait/recordLockFail and the real Settings
// JSON round trip:
//   - real time passes (the boot clock moves with it, asleep or not);
//   - the wall clock is set anywhere from 2 hours back to 2 days forward;
//   - Solace is killed: a new process, and the settings are what the store last saved (a wait checked while one runs
//     is never saved: checkAppPasscode returns before its save);
//   - the device restarts: real time passes while it is off, the boot clock starts again from a few seconds (so a
//     reading from the last boot can be smaller OR larger than the saved one), and Solace starts fresh;
//   - something else saves the store while the wait runs, keeping what lockWait's last look left in memory.
// At every check where a passcode may be tried again (lockWait null), the real time since the wait began must be at
// least the full wait. This passes on 2f3ce71: no shortening found. (The count of misses itself can be lost by a kill:
// R10A-05, review10a/passcode_miss_lost_on_kill_test.dart.)
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/boot_clock.dart';
import 'package:solace/core/store.dart';
import 'package:solace/ui/app_lock.dart';

class _Clock extends LockClock {
  _Clock(this.wallNow);
  DateTime Function() wallNow;
  @override
  DateTime wall() => wallNow();
}

Settings _roundTrip(Settings s) => Settings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);

void main() {
  tearDown(() {
    lockClock = const LockClock();
    bootClock = readBootClock;
    forgetLockWaitForTest();
  });

  test('G7-06: no mix of clock changes, restarts and kills ends a saved wait before it has really run', () {
    final base = DateTime(2026, 11, 16, 14);
    var checks = 0, allowed = 0;
    for (var seed = 0; seed < 3000; seed++) {
      final r = Random(seed);
      var real = Duration.zero, uptime = Duration(seconds: 5 + r.nextInt(200000)), offset = Duration.zero;
      bootClock = () => uptime;
      lockClock = _Clock(() => base.add(real).add(offset));
      forgetLockWaitForTest();
      // the misses, then the save that checkAppPasscode makes after each
      var s = Settings();
      final fails = 5 + r.nextInt(9);
      for (var i = 0; i < fails; i++) {
        final at = lockNow();
        recordLockFail(s, at.wall, mono: at.mono);
      }
      final full = Duration(seconds: lockWaitSeconds(s.lockFails));
      var saved = _roundTrip(s);
      for (var step = 0; step < 60; step++) {
        switch (r.nextInt(6)) {
          case 0: // real time passes
            final d = Duration(seconds: r.nextInt(1200));
            real += d;
            uptime += d;
          case 1: // the wall clock is set
            offset = Duration(minutes: -120 + r.nextInt(60 * 50));
          case 2: // Solace killed and opened again
            forgetLockWaitForTest();
            s = _roundTrip(saved);
          case 3: // the device restarts
            real += Duration(seconds: r.nextInt(900));
            uptime = Duration(seconds: 3 + r.nextInt(400));
            forgetLockWaitForTest();
            s = _roundTrip(saved);
          case 4: // something else saves the store now, with whatever the wait's last look left in memory
            saved = _roundTrip(s);
          default: // the lock screen asks
            break;
        }
        final at = lockNow();
        final left = lockWait(s, at.wall, mono: at.mono);
        checks++;
        if (left == null) {
          allowed++;
          expect(real >= full, isTrue,
              reason: 'seed $seed step $step: a try allowed after ${real.inSeconds} s of a ${full.inSeconds} s wait');
          break;
        }
      }
    }
    expect(checks, greaterThan(10000));
    expect(allowed, greaterThan(100), reason: 'the walks do reach the end of the wait');
  });
}
