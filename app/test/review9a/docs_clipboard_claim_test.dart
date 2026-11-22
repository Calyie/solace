// Round 9 review A, 9A-04 (F-21, docs that do not match the code): docs/SECURITY.md section 4 ("Data copied off the
// device by backups or other apps") still says that "what Solace copies leaves the clipboard after a minute", and so
// do the comments the next developer reads (ui/premium.dart privateContextMenu, ui/desktop.dart copy). Since the
// owner's decision of 2026-11-15 (A-11, "This is excessive") Solace never empties the clipboard
// (core/clipboard_guard.dart; SECURITY.md section 7 says so too). A reader of section 4 is told copied notes vanish
// after a minute when they stay until something else is copied. This test asserts the SAFE state (no such claim), so
// it fails while the finding stands.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('9A-04: nothing claims that Solace empties the clipboard after a minute', () {
    final claims = <String>[];
    for (final path in ['../docs/SECURITY.md', 'lib/ui/premium.dart', 'lib/ui/desktop.dart']) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains('clipboard after a minute')) claims.add('$path:${i + 1}');
      }
    }
    expect(claims.toSet(), isEmpty, reason: 'the code never empties the clipboard (A-11, owner 2026-11-15)');
  });
}
