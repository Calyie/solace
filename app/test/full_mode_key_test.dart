// The owner's deep work mode key (lib/core/full_mode_key.dart): only the right six digits open it, a build without a
// fingerprint never does, and wrong keys lock the switch for longer each time.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/full_mode_lock.dart';
import 'package:solace/core/store.dart';

void main() {
  late FullModeKey key;
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    key = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('482913', salt, memoryKib: 64, iterations: 1));
  });

  test('only the right six digits match; spaces do not matter', () async {
    expect(await key.matches('482913'), isTrue);
    expect(await key.matches(' 482 913 '), isTrue);
    expect(await key.matches('482914'), isFalse);
    expect(await key.matches('48291'), isFalse);
    expect(await key.matches('48291a'), isFalse);
    expect(await key.matches(''), isFalse);
  });

  test('a build without a fingerprint can never turn deep work mode on', () async {
    const none = FullModeKey(salt: '', fingerprint: '');
    expect(none.isSetUp, isFalse);
    expect(await none.matches('482913'), isFalse);
  });

  // Round 10 review A, R10A-06: the pause runs on the boot clock as well as the wall clock, so time passing is given on
  // both (the boot clock as [mono]); before, 16 minutes on the wall clock alone ended it, which is what the finding was.
  test('five wrong keys lock for 15 minutes, then longer; the right key resets', () {
    forgetFullModePauseForTest();
    final s = Settings();
    final t0 = DateTime(2026, 11, 5, 22);
    const m0 = Duration(hours: 3); // the boot clock at t0
    const later = Duration(minutes: 16);
    for (var i = 0; i < 4; i++) {
      fullModeWrongKey(s, t0, mono: m0);
    }
    expect(fullModeLockLeft(s, t0, mono: m0), Duration.zero);
    fullModeWrongKey(s, t0, mono: m0);
    expect(fullModeLockLeft(s, t0, mono: m0), const Duration(minutes: 15));
    expect(fullModeLockLeft(s, t0.add(later), mono: m0 + later), Duration.zero);
    fullModeWrongKey(s, t0.add(later), mono: m0 + later);
    expect(fullModeLockLeft(s, t0.add(later), mono: m0 + later), const Duration(minutes: 30));
    fullModeRightKey(s);
    expect(s.fullModeFails, 0);
    expect(s.fullModeLockedBoot, isNull);
    expect(fullModeLockLeft(s, t0, mono: m0), Duration.zero);
  });

  test('the counts survive a save and load', () {
    final s = Settings()..fullModeFails = 6..fullModeLockedUntil = '2026-11-05T22:30:00.000';
    final back = Settings.fromJson(s.toJson());
    expect(back.fullModeFails, 6);
    expect(back.fullModeLockedUntil, '2026-11-05T22:30:00.000');
  });
}
