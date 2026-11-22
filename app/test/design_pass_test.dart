// The design pass (2026-11-16, research report P1 9, 11 and 19): what the screenshots cannot show by themselves.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/crisis.dart' show SupportButton;
import 'package:solace/ui/premium.dart';
import 'package:solace/ui/theme.dart';

import 'app_flow_test.dart' as flow;
import 'session_ui_fixes_test.dart' show StepModel, makeState;

Future<void> _chat(WidgetTester tester, AppState state, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light), home: const ChatScreen(kind: 'daily_checkin'))));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });
  testWidgets('on a computer, Esc stops the reply being written, as the Stop beside the box does', (tester) async {
    final model = StepModel();
    await _chat(tester, makeState(model), const Size(1440, 900));
    model.hold();
    await tester.enterText(find.byType(TextField), 'Work has been a lot this week.');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('chat_stop')), findsOneWidget, reason: 'her words are coming');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(model.cancels, 1, reason: 'Esc stopped her words');
    expect(find.byKey(const Key('chat_stop')), findsNothing);
    expect(find.byKey(const Key('chat_send')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('on a computer, a long reply keeps a reading width; on a phone it takes four fifths', (tester) async {
    for (final (size, most) in [(const Size(1440, 900), Widths.message), (const Size(390, 844), 390 * 0.8)]) {
      final model = StepModel();
      await _chat(tester, makeState(model), size);
      final bubble = find.ancestor(of: find.textContaining('How are you today'), matching: find.byType(Container)).first;
      expect(tester.getSize(bubble).width, lessThanOrEqualTo(most), reason: '$size');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('with less motion, a new page fades in where it ends, without sliding', (tester) async {
    Future<Offset> midway(bool reduced) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MediaQuery(data: MediaQueryData(disableAnimations: reduced), child: MaterialApp(
          navigatorKey: key, theme: appTheme(Brightness.light), home: const Scaffold(body: Text('first')))));
      key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('second'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final at = tester.getTopLeft(find.text('second'));
      final fade = tester.widgetList<FadeTransition>(find.ancestor(of: find.text('second'),
          matching: find.byType(FadeTransition))).fold(1.0, (a, f) => a * f.opacity.value);
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(find.text('second'));
      if (reduced) expect(fade, lessThan(1), reason: 'it fades in');
      return at - end;
    }

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(await midway(false), isNot(Offset.zero), reason: '$platform: the usual transition moves the page');
      expect(await midway(true), Offset.zero, reason: '$platform: with less motion it does not move');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  // report 2026-11-14, P1 18: Support early in the focus order. The first press of Tab reaches it, on a phone with a
  // keyboard and on a computer, before the tabs and before anything on Today.
  for (final (where, size, platform) in [('a phone', const Size(390, 844), TargetPlatform.iOS),
      ('a computer', const Size(1440, 900), TargetPlatform.macOS)]) {
    testWidgets('on $where, the first Tab reaches Support', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.menu, null));
      await tester.pumpWidget(TherapistApp(state: flow.makeState(demo: true)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(find.ancestor(of: find.byElementPredicate((e) => e == focused), matching: find.byType(SupportButton)),
          findsOneWidget, reason: 'the first Tab went to ${focused?.widget}');
    }, variant: TargetPlatformVariant.only(platform));
  }

  test('on Solace\'s card, the white pill keeps its deep ink in dark as in light', () {
    for (final b in Brightness.values) {
      final pill = appTheme(b).extension<Hues>()!.onPill;
      expect(pill, accents['ocean']!.deep, reason: b.name);
    }
  });
}
