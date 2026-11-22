// The boot clock (lib/core/boot_clock.dart, audit 216, G7-06) on a real device: the app lock and the passcode wait
// count time through it, and its native calls (clock_gettime with CLOCK_BOOTTIME on Android and Linux,
// mach_continuous_time on iPhone and Mac) are proven by unit tests on Linux only. Run on each platform before a release:
//   flutter test integration_test/boot_clock_device_test.dart -d <device>
// It must read (not null: the fallback would mean the native call failed) and move forward with real time.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solace/core/boot_clock.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the boot clock reads on this device and moves forward with real time', () async {
    final first = readBootClock();
    expect(first, isNotNull, reason: 'the native boot clock must read on this device');
    expect(first!.isNegative, isFalse);
    final watch = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final second = readBootClock();
    watch.stop();
    expect(second, isNotNull);
    final moved = second! - first;
    // within 250 ms of a stopwatch over the same 1.5 s (the device does not sleep during the test)
    expect((moved - watch.elapsed).inMilliseconds.abs(), lessThan(250), reason: 'moved $moved, stopwatch ${watch.elapsed}');
    // ignore: avoid_print
    print('BOOT_CLOCK_DEVICE ok: up ${first.inSeconds} s, moved ${moved.inMilliseconds} ms over ${watch.elapsedMilliseconds} ms');
  });
}
