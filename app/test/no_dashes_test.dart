// owner, 2026-11-19: "remove em dashes in its responses as it is not used when communicating with humans and sounds
// so robotic". Every reply sentence passes ReplyScreen.pass, which takes the dashes out.
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/core/check_in_guard.dart';

void main() {
  test('a dash between words becomes a comma; between numbers "to"; at the edges it goes', () {
    expect(withoutDashes('You are tired — and that is real. '), 'You are tired, and that is real. ');
    expect(withoutDashes('Stand up—just for a minute.'), 'Stand up, just for a minute.');
    expect(withoutDashes('Give it 5–10 minutes.'), 'Give it 5 to 10 minutes.');
    expect(withoutDashes('Try this — '), 'Try this');
    expect(withoutDashes('— Then the curtains.'), 'Then the curtains.');
    expect(withoutDashes('A self-compassion break, well-being first, 1,000 steps.'),
        'A self-compassion break, well-being first, 1,000 steps.');
  });

  test('every reply sentence loses its dashes on the way to the screen', () {
    final screen = ReplyScreen();
    expect(screen.pass('Behavioural activation — action first — works. '), 'Behavioural activation, action first, works. ');
    expect(screen.pass('No dash here. '), 'No dash here. ');
  });
}
