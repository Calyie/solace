// Audit 216 fix (G7-06): the boot clock read through dart:ffi (core/boot_clock.dart) and the saved passcode wait that
// runs on it (ui/app_lock.dart lockWait). On this Linux test machine the real clock_gettime(CLOCK_BOOTTIME) is read;
// the Android, iPhone and Mac paths need a device. The wait rules are checked with a boot clock the test moves.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/boot_clock.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/ui/app_lock.dart';

void main() {
  test('Linux: the boot clock is read through dart:ffi, never runs backwards, and agrees with /proc/uptime', () {
    final a = readBootClock();
    expect(a, isNotNull, reason: 'clock_gettime(CLOCK_BOOTTIME) from libc');
    final uptime = double.parse(File('/proc/uptime').readAsStringSync().split(' ').first);
    expect((a!.inMilliseconds / 1000 - uptime).abs(), lessThan(2), reason: '/proc/uptime is the boot clock too');
    final b = readBootClock()!;
    expect(b >= a, isTrue);
    expect(const LockClock().countsSleep, isTrue);
  }, skip: Platform.isLinux ? false : 'the Linux path; other systems need their own device run');

  group('the lock clock', () {
    tearDown(() => bootClock = readBootClock);

    test('the monotonic measure is the boot clock when there is one, else the stopwatch', () {
      bootClock = () => const Duration(days: 3);
      expect(const LockClock().monotonic(), const Duration(days: 3));
      expect(const LockClock().countsSleep, isTrue);
      bootClock = () => null;
      expect(const LockClock().monotonic() < const Duration(days: 1), isTrue, reason: 'the stopwatch since start');
      expect(const LockClock().countsSleep, isFalse);
    });
  });

  group('the saved passcode wait', () {
    final t = DateTime(2026, 11, 16, 14);
    var boot = const Duration(hours: 5);
    setUp(() {
      boot = const Duration(hours: 5);
      bootClock = () => boot;
      forgetLockWaitForTest();
    });
    tearDown(() {
      bootClock = readBootClock;
      forgetLockWaitForTest();
    });

    /// Five wrong passcodes at [t]: a 30-second wait, saved with the boot clock's reading.
    Settings fiveMisses() {
      final s = Settings();
      for (var i = 0; i < 5; i++) {
        recordLockFail(s, t, mono: boot);
      }
      expect(s.lockBoot, boot.inMicroseconds);
      return s;
    }

    /// Solace closed and opened again (a new process: its in-memory wait is gone), [real] later by the boot clock.
    Duration? reopened(Settings s, DateTime wall, Duration real) {
      forgetLockWaitForTest();
      boot += real;
      return lockWait(Settings.fromJson(s.toJson())..lockFails = s.lockFails, wall, mono: boot);
    }

    test('closing Solace and setting the clock forward never ends it early: the smaller of the two clocks counts', () {
      final s = fiveMisses();
      expect(reopened(s, t.add(const Duration(hours: 1)), const Duration(seconds: 5)), const Duration(seconds: 25));
      expect(reopened(s, t.add(const Duration(hours: 1)), const Duration(seconds: 26)), isNull,
          reason: 'the 30 seconds did pass by both clocks');
    });

    test('a clock set back never shortens it', () {
      final s = fiveMisses();
      final left = reopened(s, t.subtract(const Duration(hours: 1)), const Duration(seconds: 5));
      expect(left, const Duration(seconds: 30), reason: 'runs in full from now, never longer than it was set for');
      final s2 = fiveMisses();
      expect(reopened(s2, t.add(const Duration(seconds: 3)), const Duration(seconds: 20)), const Duration(seconds: 27),
          reason: 'the wall clock says less than the boot clock: the smaller counts');
    });

    test('the device restarted (the boot clock went back): nothing counts as passed, the wait starts again', () {
      final s = fiveMisses();
      forgetLockWaitForTest();
      boot = const Duration(seconds: 40); // a restart 40 s ago
      expect(lockWait(s, t.add(const Duration(days: 2)), mono: boot), const Duration(seconds: 30));
      expect(s.lockBoot, boot.inMicroseconds, reason: 'measured from now on');
      boot += const Duration(seconds: 31);
      expect(lockWait(s, t.add(const Duration(days: 2, seconds: 31)), mono: boot), isNull);
    });

    test('a wait that ran its course is forgotten, so a later restart cannot start it again', () {
      final s = fiveMisses();
      boot += const Duration(seconds: 31);
      expect(lockWait(s, t.add(const Duration(seconds: 31)), mono: boot), isNull);
      expect(s.lockUntil, isNull);
      expect(s.lockBoot, isNull);
      recordLockFail(s, t.add(const Duration(minutes: 1)), mono: boot);
      expect(lockWait(s, t.add(const Duration(minutes: 1)), mono: boot), const Duration(seconds: 60),
          reason: 'the next wrong passcode starts the next, longer wait, as before');
    });

    test('a wait saved by an earlier version (no boot reading) runs on the boot clock from the first look', () {
      final s = Settings()
        ..lockFails = 5
        ..lockUntil = t.add(const Duration(seconds: 30)).toIso8601String();
      expect(lockWait(s, t.add(const Duration(seconds: 10)), mono: boot), const Duration(seconds: 20));
      expect(s.lockBoot, (boot - const Duration(seconds: 10)).inMicroseconds);
      expect(reopened(s, t.add(const Duration(hours: 1)), const Duration(seconds: 5)), const Duration(seconds: 15));
    });

    test('with no boot clock, a saved wait goes by the wall clock once Solace is closed, as before', () {
      bootClock = () => null;
      final s = Settings();
      for (var i = 0; i < 5; i++) {
        recordLockFail(s, t, mono: const Duration(seconds: 100));
      }
      expect(s.lockBoot, isNull);
      forgetLockWaitForTest();
      expect(lockWait(s, t.add(const Duration(hours: 1)), mono: const Duration(seconds: 5)), isNull);
    });

    test('the boot reading is saved with the wait, and an import keeps this device\'s own', () {
      final s = fiveMisses();
      expect(Settings.fromJson(s.toJson()).lockBoot, s.lockBoot);
      final incoming = AppData()..settings.lockBoot = 42;
      final mine = AppData()..settings.lockBoot = s.lockBoot;
      expect(importInto(mine, incoming).settings.lockBoot, s.lockBoot);
    });
  });
}
