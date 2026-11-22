// Review round 5, reviewer C, C-09 (FAILS on ca6a73b; passes once fixed): importInto keeps this device's lock, deep work mode, country and window, but
// takes the other device's privacy switches: "Pause memory" (Solace neither uses nor adds to what it remembers) and
// the reminders. A person who paused memory on this phone finds it learning again after bringing in a file from a
// device where it was not paused, with no word about it.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';

void main() {
  test('C-09: an import keeps this device\'s memory pause and reminders switch', () {
    final here = AppData()
      ..settings.memoryPaused = true
      ..settings.remindersOn = false;
    final incoming = AppData(); // the other device: defaults (memory on, reminders on)
    final after = importInto(here, incoming);
    expect(after.settings.memoryPaused, isTrue, reason: 'this device\'s memory pause was turned off by the import');
    expect(after.settings.remindersOn, isFalse, reason: 'this device\'s reminders were turned back on by the import');
    // for comparison, what an import does keep from this device
    expect(after.settings.appLock, here.settings.appLock);
    expect(after.settings.hideInSwitcher, here.settings.hideInSwitcher);
  });
}
