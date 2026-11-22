// Free space on the Mac and the iPhone (the user journey, 2026-11-16): macOS reported 0 bytes for "important usage"
// while 146.8 GB were free, so Solace refused every import as "not enough free space". Both platforms now report the
// larger of that figure and the plain free space. Swift does not run in this suite, so the source is pinned here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final f in ['macos/Runner/MainFlutterWindow.swift', 'ios/Runner/AppDelegate.swift']) {
    test('$f reports the larger of the two free-space figures', () {
      final s = File(f).readAsStringSync();
      expect(s, contains('.volumeAvailableCapacityKey'), reason: 'the plain free space is read');
      expect(s, contains('.volumeAvailableCapacityForImportantUsageKey'));
      expect(s, contains('"free": max(important, plain)'));
      expect(s, isNot(contains('let free = values?.volumeAvailableCapacityForImportantUsage')),
          reason: 'never the important-usage figure alone');
    });
  }
}
