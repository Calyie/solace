// Review round 10 A, R10A-06 (beside G7-06): the pause after five wrong deep work PINs still runs on the wall clock
// alone, so setting the device clock forward ends it.
//
// G7-06 moved the app lock and the app passcode's wait onto the boot clock. The deep work PIN (which turns the trained
// safety check off, or deep work mode on; owner: off only with that PIN) has its own pause after five wrong keys, 15
// minutes doubling to 16 hours (core/full_mode_lock.dart), and it is still `until.isAfter(now)` with `now` the wall
// clock: AppState.clock (DateTime.now, app_state.dart:41) at every check in Settings (ui/settings.dart:68, 87, 561, 662,
// 758). Five wrong PINs, set the clock forward 16 hours (no Solace passcode needed for the device's own settings),
// five more, set it forward again: the pause never slows guessing. The miss is also counted only after the PIN check
// and saved after it (settings.dart:668-676), the same window as R10A-05.
//
// The test asserts the SAFE behaviour (a clock set forward does not end the pause after 3 real seconds), so it fails
// on 2f3ce71.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_lock.dart';
import 'package:solace/core/store.dart';

void main() {
  test('R10A-06: setting the clock forward does not end the deep work PIN pause', () {
    final s = Settings();
    final t = DateTime(2026, 11, 16, 14);
    for (var i = 0; i < fullModeTries; i++) {
      fullModeWrongKey(s, t);
    }
    expect(fullModeLockLeft(s, t), const Duration(minutes: 15), reason: 'precondition: the pause began');
    // three real seconds later, with the device clock set forward by a day
    final forward = t.add(const Duration(days: 1, seconds: 3));
    expect(fullModeLockLeft(s, forward) > Duration.zero, isTrue,
        reason: 'the pause ended at once: it goes by the wall clock only');
  });
}
