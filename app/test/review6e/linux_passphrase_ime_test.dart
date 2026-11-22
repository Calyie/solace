// Round 6 review E, E-06 (the proof failed on 4a8da11 and passes since the round 6 fix): what the Linux passphrase box tells the input method. Flutter's Linux embedder picks the
// GTK input purpose from the field's keyboard type only (engine: shell/platform/linux/fl_text_input_channel.cc, the
// input-type switch): obscureText, autocorrect and enableIMEPersonalizedLearning are not passed on. The passphrase box
// is a plain text field (TextInputType.text), so GTK's input method (IBus, Fcitx) is told it is ordinary free-form
// text, not GTK_INPUT_PURPOSE_PASSWORD: an input method that predicts or learns (ibus-typing-booster, Fcitx5
// prediction, the CJK engines' user dictionaries) may keep the passphrase outside Solace. TextInputType.visiblePassword
// is the type the embedder maps to GTK_INPUT_PURPOSE_PASSWORD.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/ui/passphrase_screen.dart';

void main() {
  testWidgets('E-06: the passphrase box reaches the input method as a password', (tester) async {
    final dir = Directory.systemTemp.createTempSync('r6e_ime');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(PassphraseApp(dir: dir, onReady: (_) async {}));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pass_first')));
    await tester.pump();
    final args = tester.testTextInput.setClientArgs!;
    expect(args['obscureText'], isTrue, reason: 'hidden on screen');
    // the safe behaviour: described to the Linux input method as a password (GTK_INPUT_PURPOSE_PASSWORD); on
    // 4a8da11 it is TextInputType.text, which the embedder passes on as ordinary free-form text
    expect((args['inputType'] as Map)['name'], 'TextInputType.visiblePassword');
  });
}
