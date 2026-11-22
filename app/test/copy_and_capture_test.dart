// Owner, 2026-11-19: "remove this option you have that prevents screenshotting on solace or right-clicking and copying
// text from solace as that is tiring and frustrating". So:
// - no device blocks screenshots, screen recording or screen sharing (Android FLAG_SECURE and the Mac's sharingType
//   are gone); "Hide in the app switcher" hides only the switcher's preview (the app's cover, and on Android 13 and
//   later setRecentsScreenshotEnabled, which leaves screenshots alone);
// - the text the person reads is selectable and copied with the system's own menu (ui/premium.dart Readable is a
//   SelectionArea), and every text box keeps the standard menu;
// - copies are Flutter's own: no clipboard guard, no native copy with privacy marks (tracker A-11).
// The native files cannot be built here; these checks keep them as they are meant to be.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/ui/premium.dart';

String _code(String path) =>
    [for (final l in File(path).readAsLinesSync()) if (!l.trimLeft().startsWith('//')) l].join('\n');

void main() {
  test('no native code blocks screen capture on any device', () {
    final android = _code('android/app/src/main/kotlin/app/personal/solace/MainActivity.kt');
    expect(android, isNot(contains('FLAG_SECURE')));
    expect(android, contains('setRecentsScreenshotEnabled(!hidden)'), reason: 'the switcher preview only');
    expect(android, contains('Build.VERSION.SDK_INT >= 33'));
    final mac = _code('macos/Runner/MainFlutterWindow.swift');
    expect(mac, isNot(contains('sharingType')));
    for (final f in ['ios/Runner/AppDelegate.swift', 'ios/Runner/SceneDelegate.swift',
        'macos/Runner/AppDelegate.swift']) {
      final c = _code(f);
      // UIScreen capture hiding (isSecureTextEntry tricks, capturedDidChange covers) would block or blank recordings
      expect(c, isNot(matches(RegExp(r'sharingType|isSecureTextEntry|capturedDidChange|isCaptured'))), reason: f);
    }
    for (final f in Directory('linux/runner').listSync().whereType<File>()) {
      expect(f.readAsStringSync(), isNot(matches(RegExp('gtk_window_set_.*capture|XCompositeRedirect'))),
          reason: f.path);
    }
  });

  test('copies are Flutter\'s own: no clipboard guard and no native copy (A-11, removed 2026-11-19)', () {
    expect(File('lib/core/clipboard_guard.dart').existsSync(), isFalse);
    expect(_code('android/app/src/main/kotlin/app/personal/solace/MainActivity.kt'),
        isNot(matches(RegExp(r'ClipboardManager|setPrimaryClip|EXTRA_IS_SENSITIVE|"copy"'))));
    expect(_code('ios/Runner/AppDelegate.swift'), isNot(matches(RegExp(r'UIPasteboard|"copy"'))));
    expect(_code('macos/Runner/MainFlutterWindow.swift'),
        isNot(matches(RegExp(r'NSPasteboard|ConcealedType|TransientType|"copy"'))));
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(f.readAsStringSync(), isNot(matches(RegExp(r"invokeMethod<void>\('copy'|'clearCopy'"))), reason: f.path);
    }
  });

  testWidgets('text in a Readable is selected with a long press and copied with the standard Copy', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Readable(child: Column(children: [
      Text('Breathing slowly helps the body settle.'),
    ])))));
    expect(find.byType(SelectionArea), findsOneWidget);
    await tester.longPress(find.text('Breathing slowly helps the body settle.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    expect('Breathing slowly helps the body settle.', contains(copied!));
  });

  testWidgets('select all and copy takes the whole text', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Readable(child: Column(children: [
      Text('One calm line.'),
      Text('And another.'),
    ])))));
    await tester.tap(find.text('One calm line.'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One calm line.'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, allOf(contains('One calm line.'), contains('And another.')));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a Readable made unselectable (the lock screen) has no selection area', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Readable(selectable: false, child: Text('Locked')))));
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('a text box keeps the standard menu, Copy and Paste included', (tester) async {
    final c = TextEditingController(text: 'my own words');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextField(controller: c,
        autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false))));
    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Copy').evaluate().isNotEmpty || find.text('Select all').evaluate().isNotEmpty, isTrue);
  });
}
