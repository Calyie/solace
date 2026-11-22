// Deep work mode lives in the person's Settings and nowhere else (owner, 2026-11-13: "The deep work should be in the
// user setting and only activated in using the pin from there"). The flow test checks the switch itself (warning, key,
// wrong-key pause); this one checks that no other screen shows the mode's name. The reliving gate's reason list names it
// too, but that screen opens only from the Spoken reliving card, which exists only once deep work mode is on.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only Settings (and the gate reachable from deep work mode) show the words deep work', () {
    const allowed = {'lib/ui/settings.dart', 'lib/core/gate.dart'};
    final shown = RegExp(r"""['"][^'"]*deep work[^'"]*['"]""", caseSensitive: false);
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (!line.startsWith('//') && !line.startsWith('///') && shown.hasMatch(line) && !allowed.contains(f.path)) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
