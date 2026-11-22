// Round 9 review A, 9A-05: Flutter's TextField turns autofill on unless autofillHints is null, and its default is an
// empty list, not null (flutter/lib/src/material/text_field.dart: autofillHints = const <String>[]; editable_text.dart
// textInputConfiguration: only null gives AutofillConfiguration.disabled). No box in Solace sets it, so every box,
// the app passcode and the deep work PIN included, is reported to the platform's autofill framework with its current
// words (Android engine TextInputPlugin: notifyViewEntered, onProvideAutofillVirtualStructure with the box's text,
// notifyValueChanged at every edit). On Android the passcode and PIN boxes are password-typed digit boxes, which
// autofill services (Google's, password managers) treat as credentials and may offer to save to their own, often
// cloud, store. This test asserts the SAFE configuration (autofill off: no 'autofill' sent to the engine), so it fails
// while the finding stands.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/ui/app_lock.dart';

void main() {
  testWidgets('9A-05: the app passcode boxes are never offered to the autofill service (Android)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
          onPressed: () => choosePasscode(context), child: const Text('choose')))));
      await tester.tap(find.text('choose'));
      await tester.pumpAndSettle();
      for (final key in ['passcode_first', 'passcode_second']) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
        final args = tester.testTextInput.setClientArgs!;
        expect(args['obscureText'], isTrue, reason: 'precondition: a secret box');
        expect(args['autofill'], isNull,
            reason: '$key is sent to the engine with autofill on (${args['autofill']}), so Android\'s autofill '
                'service is told of the box and every change to it');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
