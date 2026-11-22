// Review round 5, reviewer C, C-05 (the first test FAILS on ca6a73b; passes once fixed): "every text field has keyboard learning off" (docs/SECURITY.md section 4) holds
// on Android only. enableIMEPersonalizedLearning is an Android flag; on the iPhone the system keyboard learns typed
// words (its dynamic dictionary, outside Solace's encryption and backup exclusion) unless autocorrection is off
// (Flutter: autocorrect: false; enableSuggestions only affects Android). This lists the text boxes that leave it on,
// using the same source scan as test/privacy_test.dart, and checks the chat box itself through its widget.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C-05: text boxes that leave iOS keyboard learning (autocorrection) on', () {
    final open = <String>[], all = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\b(TextField|TextFormField)\(').allMatches(src)) {
        final call = src.substring(m.end, (m.end + 600).clamp(0, src.length));
        final at = '${f.path}:${'\n'.allMatches(src.substring(0, m.start)).length + 1}';
        all.add(at);
        // fix (round 5, C-05): the owner wants autocorrection off on the iPhone only, so a box may take it from the
        // shared PrivateKeyboard.autocorrect (false on iOS; checked in test/privacy_test.dart) instead of a literal false
        if (!call.contains('autocorrect: false') && !call.contains('autocorrect: PrivateKeyboard.autocorrect') &&
            !call.contains('obscureText: true')) {
          open.add(at);
        }
      }
    }
    // ignore: avoid_print
    print('${open.length} of ${all.length} text boxes leave autocorrection (and so iOS keyboard learning) on:\n'
        '${open.join('\n')}');
    expect(open, isEmpty, reason: 'every text box should turn autocorrection off (iOS keyboard learning)');
  });

  testWidgets('C-05: Flutter defaults: a TextField without autocorrect: false gives the keyboard autocorrection on',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Material(child: TextField(enableIMEPersonalizedLearning: false))));
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.autocorrect, isTrue); // what the iOS keyboard is told (UITextAutocorrectionTypeYes)
    expect(editable.enableIMEPersonalizedLearning, isFalse); // Android only
  });
}
