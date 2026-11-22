// Review round 9 B, 9B-03: the phrase rules still read up to 15,000 characters on the interface thread on several
// paths, although round 6 (F6-13) moved Send to a background isolate past 3,000 characters for exactly this cost:
//   - End and Back (core/session.dart readLeftUnsent, `fresh.length <= pastesInIsolate`: the box of up to 12,000
//     characters, plus held words, read in place up to 15,000);
//   - a paste that did not fit (checkDropped, `text.length > pastesInIsolate`: up to 15,000 characters, read twice);
//   - Help me start (ui/help_me_start.dart readTask) and saved notes, goals, story and vision board
//     (ui/crisis.dart readSavedWords), in place up to 15,000.
// On this laptop the rules take about 55 ms on 12,000 characters of ordinary prose and up to about 120 to 150 ms on
// crafted text (several times that on a phone): a visible stall at the moment someone leaves a conversation.
//
// Each test asserts the SAFE behaviour: the call returns to the interface thread within one frame (16 ms), the rules
// running elsewhere. Both fail on 3d2da1f while the finding stands.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/session.dart';
import 'package:solace/core/store.dart';

import '../audit_followups_test.dart' as a;

String fill(String unit, int n) {
  final b = StringBuffer();
  while (b.length < n) {
    b.write(unit);
  }
  return b.toString().substring(0, n);
}

const prose = 'I had a long day at work and I feel tired but okay, so I wanted to write it all down here. ';

void main() {
  test('9B-03: End or Back with a full box of ordinary words returns within one frame', () async {
    final s = a.session(AppData(), MemoryVault());
    final box = fill(prose, 12000); // a full box, typed or pasted, not sent
    s.readLeftUnsent([box]); // warm the rules' patterns once
    final sw = Stopwatch()..start();
    final pending = s.readLeftUnsent(['$box ']); // as the chat and call screens call it at End and in dispose()
    sw.stop();
    await pending;
    expect(sw.elapsedMilliseconds, lessThan(16),
        reason: 'readLeftUnsent held the interface thread for ${sw.elapsedMilliseconds} ms before returning');
  });

  test('9B-03: a paste that did not fit is read off the interface thread', () async {
    final s = a.session(AppData(), MemoryVault());
    final box = fill(prose, 12000);
    await s.checkDropped(box, fill(prose, 14000)); // warm
    final sw = Stopwatch()..start();
    final pending = s.checkDropped(box, fill(prose, 14500)); // a 26,500-character paste into an empty box
    sw.stop();
    await pending;
    expect(sw.elapsedMilliseconds, lessThan(16),
        reason: 'checkDropped held the interface thread for ${sw.elapsedMilliseconds} ms before returning');
  });
}
