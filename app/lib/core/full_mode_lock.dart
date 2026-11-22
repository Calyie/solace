// The pause after wrong deep work mode keys (core/full_mode_key.dart): five wrong keys lock the switch for 15 minutes,
// doubling with each further wrong key to 16 hours; the counts are kept in the encrypted settings.
//
// Round 10 review A, R10A-06: the pause went by the wall clock alone, so setting the device clock forward ended it. It
// now runs as the app passcode's wait does (ui/app_lock.dart lockWait; audit 216, G7-06): on the wall clock and on the
// boot clock (core/lock_clock.dart, core/boot_clock.dart), whose reading is saved with the pause
// ([Settings.fullModeLockedBoot]). The time passed is the smaller of what the two say and never less than nothing, so
// neither a clock set forward nor one set back ends a saved pause early; a boot clock reading less than when the pause
// began means the device restarted, and the pause starts again from then; while Solace runs it also runs on the
// monotonic measure. Where the boot clock cannot be read, a saved pause goes by the wall clock once Solace is closed,
// as before.
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'lock_clock.dart';
import 'store.dart';

const fullModeTries = 5;

/// The pause after [fails] wrong keys in a row: 15 minutes after five, doubling with each further one up to 16 hours.
Duration fullModePause(int fails) => Duration(minutes: 15 * (1 << min(max(fails - fullModeTries, 0), 6)));

/// Where the pause running now ends on the monotonic measure, for the saved pause it belongs to. Kept while this copy of
/// Solace runs.
({String until, Duration mono})? _pauseEnds;

/// A fresh start, as far as the deep work pause is concerned (tests).
@visibleForTesting
void forgetFullModePauseForTest() => _pauseEnds = null;

/// How long the switch stays locked, from the counts kept (encrypted) in the settings. [mono] is the monotonic measure
/// now ([lockNow], read here when not given). A pause found over by every measure, the boot clock included, is
/// forgotten (the next wrong key starts a new one, as before).
Duration fullModeLockLeft(Settings s, DateTime now, {Duration? mono}) {
  final until = DateTime.tryParse(s.fullModeLockedUntil ?? '');
  if (until == null) return Duration.zero;
  final m = mono ?? lockNow().mono;
  final full = fullModePause(s.fullModeFails);
  final boot = bootReading(m);
  final saved = s.fullModeLockedBoot;
  var left = until.difference(now);
  if (left > full) {
    left = full; // the clock went back since the pause began: it runs in full from now, never longer
    _begin(s, now, full, boot);
  } else if (boot != null && saved != null) {
    final byBoot = boot - Duration(microseconds: saved), byWall = now.difference(until.subtract(full));
    if (byBoot.isNegative) {
      left = full; // the device restarted since the pause began: nothing counts as passed
      _begin(s, now, full, boot);
    } else {
      final passed = byBoot < byWall ? byBoot : byWall;
      final byBoth = full - (passed.isNegative ? Duration.zero : passed);
      if (byBoth > left) left = byBoth;
    }
  } else if (boot != null && left > Duration.zero) {
    // a pause saved without a boot reading (an earlier version, or no boot clock then): from now on it runs on the
    // boot clock too, as if both clocks had agreed since it began
    s.fullModeLockedBoot = (boot - (full - left)).inMicroseconds;
  }
  final w = _pauseEnds;
  if (w != null && w.until == s.fullModeLockedUntil) {
    final r = w.mono - m;
    if (r > left) left = r;
  } else if (left > Duration.zero) {
    _pauseEnds = (until: s.fullModeLockedUntil!, mono: m + left); // from now on it runs on the monotonic measure too
  }
  if (left > Duration.zero) return left;
  if (boot != null) {
    s.fullModeLockedUntil = null;
    s.fullModeLockedBoot = null;
  }
  return Duration.zero;
}

/// A wrong key: counted, and from the fifth in a row the pause begins (again) now, with the boot clock's reading.
void fullModeWrongKey(Settings s, DateTime now, {Duration? mono}) {
  final m = mono ?? lockNow().mono;
  s.fullModeFails++;
  if (s.fullModeFails >= fullModeTries) {
    final full = fullModePause(s.fullModeFails);
    _begin(s, now, full, bootReading(m));
    _pauseEnds = (until: s.fullModeLockedUntil!, mono: m + full);
  }
}

void fullModeRightKey(Settings s) {
  s.fullModeFails = 0;
  s.fullModeLockedUntil = null;
  s.fullModeLockedBoot = null;
}

/// The pause begins (again) now and runs [full]: its end by the wall clock and the boot clock's reading now ([boot];
/// none where it cannot be read).
void _begin(Settings s, DateTime now, Duration full, Duration? boot) {
  s.fullModeLockedUntil = now.add(full).toIso8601String();
  s.fullModeLockedBoot = boot?.inMicroseconds;
}

/// The wrong-key count as it stands, so a try counted before its check can be taken back ([restoreFullModeCount]).
typedef FullModeCount = ({int fails, String? until, int? boot});

FullModeCount fullModeCount(Settings s) =>
    (fails: s.fullModeFails, until: s.fullModeLockedUntil, boot: s.fullModeLockedBoot);

/// Puts back the count [c]: a try counted before its check that turned out right, or that could not be noted on the
/// device and so was not checked.
void restoreFullModeCount(Settings s, FullModeCount c) {
  s.fullModeFails = c.fails;
  s.fullModeLockedUntil = c.until;
  s.fullModeLockedBoot = c.boot;
}
