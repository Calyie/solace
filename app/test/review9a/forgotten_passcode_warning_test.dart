// Round 9 review A, final verification (226c148), 9A-10: since the owner's decision of 2026-11-15 the app lock opens
// only with Solace's own six-digit passcode on every device. On the iPhone, Android and the Mac the lock used to open
// with the device's own unlock, which the owner always has; now a forgotten passcode leaves every conversation, note
// and picture unreachable for good: the lock screen offers only the passcode and Support, Send everything, the exports
// and Delete everything all ask for the passcode, and the data is kept out of every backup, so a reinstall starts
// empty. Choosing the passcode (ui/app_lock.dart choosePasscode) says none of this. This test asserts the SAFE
// minimum (the person is told, when choosing it, that a forgotten passcode cannot be recovered), so it fails while the
// finding stands.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/ui/app_lock.dart';

void main() {
  testWidgets('9A-10: choosing the app passcode says a forgotten one cannot be recovered', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
        onPressed: () => choosePasscode(context), child: const Text('choose')))));
    await tester.tap(find.text('choose'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('passcode_first')), findsOneWidget, reason: 'precondition: the dialog is open');
    expect(find.textContaining(RegExp(r'forg[eo]t', caseSensitive: false)), findsWidgets,
        reason: 'nothing tells the person that a forgotten passcode locks them out of everything for good');
  });
}
