// What the app lock and the deep work PIN's pause measure time with (round 7 review, G7-06; audit 216, G7-06; round 10
// review A, R10A-06). In core, so both the app lock (ui/app_lock.dart, which passes it on) and the deep work pause
// (core/full_mode_lock.dart) go by the same clocks, and tests replace both at once ([lockClock]).
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'boot_clock.dart';

/// What the app lock measures time with (round 7 review, G7-06: it went by the wall clock alone, so a device clock set
/// back while Solace was away kept it unlocked, "at once" included): the wall clock, which anyone holding the device
/// can set, and a monotonic measure that setting the clock cannot move. Tests replace it ([lockClock]).
class LockClock {
  const LockClock();
  DateTime wall() => DateTime.now();

  /// The device's boot clock where it can be read (core/boot_clock.dart; audit 216, G7-06): it counts time asleep,
  /// never runs backwards and cannot be set by hand. Otherwise time since this copy of Solace first asked, from a
  /// stopwatch: it never runs backwards and setting the device clock does not move it, but it may not count time the
  /// device spends asleep, which the wall clock does. The lock goes by whichever of the two (this and the wall clock)
  /// says more.
  Duration monotonic() => bootClock() ?? _sinceStart.elapsed;

  /// Whether [monotonic] is the boot clock, whose readings still mean the same after Solace is closed and opened
  /// again (until the device restarts), so a saved passcode wait or deep work pause can be measured by it.
  bool get countsSleep => bootClock() != null;
}

final _sinceStart = Stopwatch()..start();

@visibleForTesting
LockClock lockClock = const LockClock();

/// One moment, as the wall clock and the monotonic measure saw it.
typedef LockMoment = ({DateTime wall, Duration mono});

LockMoment lockNow() => (wall: lockClock.wall(), mono: lockClock.monotonic());

/// [mono] when it is a boot-clock reading, which means the same in the next copy of Solace; otherwise null.
Duration? bootReading(Duration? mono) => mono != null && lockClock.countsSleep ? mono : null;
