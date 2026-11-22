// Portraits outside the call (owner, 2026-11-16: "make sure the portraits are properly aligned for each device type"):
// the round pictures (Today, Talk, a session's bar, the chooser's "A portrait") and the chooser's tiles show each
// portrait's whole head, from the top of the hair to the chin, centred, at every size. The heads sit at different
// heights in the pictures (portraitHeads), so each portrait has its own alignment.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/therapist.dart';
import 'package:solace/ui/presence.dart';

import 'app_flow_test.dart' as flow;

/// The part of the picture's height a box shows when the portrait covers it with [align] (BoxFit.cover).
(double, double) shown(double aspect, Alignment align) {
  final image = portraitShape.width / portraitShape.height;
  final drawn = aspect / image; // the picture's height in box heights
  final above = (align.y + 1) / 2 * (drawn - 1);
  return (above / drawn, (above + 1) / drawn);
}

void main() {
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  test('every portrait has its head measured', () {
    expect(portraitHeads.keys.toSet(), portraits.keys.toSet());
    for (final (top, bottom) in portraitHeads.values) {
      expect(top, inInclusiveRange(portraitFace.top, 0.3));
      expect(bottom, inInclusiveRange(0.5, portraitFace.bottom));
    }
  });

  for (final (place, aspect, at) in [('a circle', 1.0, 0.5), ("the chooser's tile", portraitTile, portraitTileHead)]) {
    test('in $place, each head is whole and where it should be', () {
      for (final MapEntry(key: id, value: (top, bottom)) in portraitHeads.entries) {
        final (from, to) = shown(aspect, portraitAlignment(id, aspect, at: at));
        final span = to - from;
        // in the box's own heights: the hair's top and the chin, with room above and below
        final hair = (top - from) / span, chin = (bottom - from) / span;
        expect(hair, greaterThan(0.08), reason: '$id: room above the hair');
        expect(chin, lessThan(0.92), reason: '$id: room under the chin');
        expect((hair + chin) / 2, closeTo(at, 0.01), reason: '$id: the head where it should be');
      }
    });
  }

  test('a box narrower than the picture shows all of it', () {
    expect(portraitAlignment('p1', 0.4), Alignment.center);
  });

  // the places a portrait shows outside the call, at a phone, a tablet and a computer
  for (final (device, size) in [('phone 360', Size(360, 800)), ('phone 430', Size(430, 932)),
      ('tablet', Size(834, 1194)), ('computer 1280', Size(1280, 800)), ('computer 2560', Size(2560, 1440))]) {
    testWidgets('$device: the avatars and the chooser use each portrait\'s own framing', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final id in portraits.keys) {
        final state = flow.makeState(demo: true);
        state.data.settings
          ..presence = 'photo'
          ..portrait = id;
        await tester.pumpWidget(MaterialApp(home: AppScope(state: state, child: const Scaffold(
            body: SingleChildScrollView(child: Column(children: [PresenceAvatar(radius: 26), PresencePicker()]))))));
        await tester.pump();
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        final circle = portraitAlignment(id, 1);
        // the avatar, then the chooser's round "A portrait", then a tile for each portrait
        expect(images[0].alignment, circle, reason: '$id: the avatar');
        expect(images[1].alignment, circle, reason: '$id: the chooser\'s circle');
        for (final (i, other) in portraits.keys.indexed) {
          expect(images[2 + i].alignment, portraitAlignment(other, portraitTile, at: portraitTileHead),
              reason: '$other: its tile');
          // each tile keeps the picture's shape for its width
          final tile = tester.getSize(find.byWidget(images[2 + i]));
          expect(tile.width / tile.height, closeTo(portraitTile, 0.01));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
