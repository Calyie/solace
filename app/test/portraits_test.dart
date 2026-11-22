// The portraits offered (owner, 2026-11-16): three women and three men; the South Asian woman (p4) was removed, and a
// saved setting or a transfer that still names her falls back to Portrait 1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/therapist.dart';

void main() {
  test('three women and three men are offered, each with its picture in the app', () {
    expect(portraits.keys, ['p1', 'p2', 'p3', 'p5', 'p6', 'p7']);
    for (final asset in portraits.values) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(File('assets/therapist/portrait_4.jpg').existsSync(), isFalse);
  });

  test('a saved choice of the removed portrait falls back to Portrait 1; the others are kept', () {
    expect(Settings.fromJson({'portrait': 'p4'}).portrait, 'p1');
    expect(Settings.fromJson({'portrait': 'nonsense'}).portrait, 'p1');
    expect(Settings.fromJson({}).portrait, 'p1');
    for (final id in ['p1', 'p2', 'p3', 'p5', 'p6', 'p7']) {
      expect(Settings.fromJson({'portrait': id}).portrait, id);
    }
    expect(portraitFor('p4'), portraits['p1']);
  });
}
