// The Mac and Linux layer (ui/desktop.dart, ui/command_palette.dart, ui/desktop_host.dart; report P1 #19, P2 #27):
// the shortcuts with Command on the Mac and Ctrl on Linux, the Mac menu bar, the command menu, Return to send,
// right-click to copy, the menu-bar icon's switch, and the window's kept place. Phones stay as they were.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/app_state.dart';
import 'package:solace/core/dates.dart';
import 'package:solace/core/full_mode_key.dart';
import 'package:solace/core/store.dart';
import 'package:solace/core/transfer.dart';
import 'package:solace/main.dart';
import 'package:solace/ui/chat.dart';
import 'package:solace/ui/check_in.dart';
import 'package:solace/ui/command_palette.dart';
import 'package:solace/ui/crisis.dart';
import 'package:solace/ui/desktop.dart';
import 'package:solace/ui/desktop_host.dart';
import 'package:solace/ui/home.dart';
import 'package:solace/ui/memory_search.dart';
import 'package:solace/ui/practices.dart';
import 'package:solace/ui/progress.dart';
import 'package:solace/ui/settings.dart';
import 'package:solace/ui/theme.dart';

import 'app_flow_test.dart' as flow;

final desktops = TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.linux});
final linux = TargetPlatformVariant.only(TargetPlatform.linux);
final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

final menuCalls = <String>[];

/// The app in a desktop-sized window. The Mac menu bar's channel answers as the Mac would.
Future<void> pumpDesktop(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(2560, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.menu, (call) async {
    menuCalls.add(call.method);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.menu, null));
  await tester.pumpWidget(TherapistApp(state: state));
  await tester.pumpAndSettle();
}

/// Command (the Mac) or Ctrl (elsewhere) with a key.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  final mod = defaultTargetPlatform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(mod);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(mod);
  await tester.pumpAndSettle();
}

Future<void> openChat(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(HomeShell))).push(MaterialPageRoute<void>(
      builder: (_) => const ChatScreen(kind: 'weekly_session')));
  await tester.pumpAndSettle();
}

Future<void> closeSheet(WidgetTester tester, Finder inside) async {
  Navigator.of(tester.element(inside)).pop();
  await tester.pumpAndSettle();
}

Finder settingsList() => find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;

Iterable<PlatformMenuItem> flatten(List<PlatformMenuItem> items) sync* {
  for (final i in items) {
    yield i;
    if (i is PlatformMenu) yield* flatten(i.menus);
    if (i is PlatformMenuItemGroup) yield* flatten(i.members);
  }
}

void main() {
  setUpAll(flow.loadFonts);
  setUpAll(() async {
    final salt = List<int>.generate(16, (i) => i);
    flow.testKey = FullModeKey(salt: 'AAECAwQFBgcICQoLDA0ODw==', memoryKib: 64, iterations: 1,
        fingerprint: await FullModeKey.fingerprintOf('135790', salt, memoryKib: 64, iterations: 1));
  });

  testWidgets('shortcuts open Settings, search, support and today\'s session, and switch tabs', (tester) async {
    await pumpDesktop(tester, flow.makeState(demo: true));
    await press(tester, LogicalKeyboardKey.comma);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await press(tester, LogicalKeyboardKey.digit2); // closes Settings and opens Talk
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(TalkTab), findsOneWidget);
    await press(tester, LogicalKeyboardKey.digit3);
    expect(find.byType(PracticesTab), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyF);
    expect(find.byType(MemorySearchScreen), findsOneWidget);
    await press(tester, LogicalKeyboardKey.digit1);
    expect(find.byType(TodayTab), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyH, shift: true);
    expect(find.byType(CrisisSheet), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyH, shift: true); // never a second sheet over the first
    expect(find.byType(CrisisSheet), findsOneWidget);
    await closeSheet(tester, find.byType(CrisisSheet));
    await press(tester, LogicalKeyboardKey.keyN);
    expect(find.byType(CheckInScreen), findsOneWidget);
  }, variant: desktops);

  testWidgets('the text size steps with the keyboard, through the app\'s sizes, and is saved', (tester) async {
    final state = flow.makeState(demo: true);
    await pumpDesktop(tester, state);
    double scale() => MediaQuery.textScalerOf(tester.element(find.byType(HomeShell))).scale(10) / 10;
    final sizes = <double>[];
    for (final (key, shift) in [(LogicalKeyboardKey.equal, false), (LogicalKeyboardKey.equal, true),
        (LogicalKeyboardKey.minus, false), (LogicalKeyboardKey.digit0, false), (LogicalKeyboardKey.minus, false),
        (LogicalKeyboardKey.minus, false)]) {
      await press(tester, key, shift: shift);
      sizes.add(state.data.settings.textSize);
    }
    expect(sizes, [1.15, 1.3, 1.15, 1.0, 0.9, 0.9]);
    expect(scale(), closeTo(0.9, 0.001));
    expect((await state.vault.load()).settings.textSize, 0.9);
  }, variant: desktops);

  testWidgets('the command menu: search, arrows, Return, Esc, and support even when nothing matches', (tester) async {
    await pumpDesktop(tester, flow.makeState(demo: true));
    await press(tester, LogicalKeyboardKey.keyK);
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.text(onMac ? '⌘N' : 'Ctrl+N'), findsOneWidget); // each shortcut written beside its command
    await tester.enterText(find.byKey(const Key('palette_search')), 'breat');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('palette_breathe')), findsOneWidget);
    expect(find.byKey(const Key('palette_settings')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(find.text('Why it helps'), findsOneWidget); // the cyclic sighing practice, ready to play
    await closeSheet(tester, find.text('Why it helps'));

    await press(tester, LogicalKeyboardKey.keyK);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // session, mood, breathe, then support
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CrisisSheet), findsOneWidget);
    await closeSheet(tester, find.byType(CrisisSheet));

    await press(tester, LogicalKeyboardKey.keyK);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);

    await press(tester, LogicalKeyboardKey.keyK);
    await tester.enterText(find.byKey(const Key('palette_search')), 'xyzzy');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches those words.'), findsOneWidget);
    expect(find.byKey(const Key('palette_support')), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyK); // the shortcut again closes it
    expect(find.byType(CommandPalette), findsNothing);
  }, variant: desktops);

  test('the command menu finds commands by their other words, best match first', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(filterCommands(desktopCommands, '').length, desktopCommands.length);
    expect(filterCommands(desktopCommands, 'crisis').first.id, 'support');
    expect(filterCommands(desktopCommands, 'suicide').first.id, 'support');
    expect(filterCommands(desktopCommands, 'text').map((c) => c.id), ['bigger', 'smaller', 'actual']);
    expect(filterCommands(desktopCommands, 'go pra').single.id, 'tab2');
    expect(filterCommands(desktopCommands, 'settings').first.id, 'settings');
  });

  testWidgets('a session on a computer: Return sends, Shift+Return adds a line, Esc leaves the box', (tester) async {
    await pumpDesktop(tester, flow.makeState(demo: true));
    await openChat(tester);
    await tester.enterText(find.byType(TextField), 'I slept badly');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'I slept badly\n');
    field.controller!.text += 'and woke early';
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('I slept badly\nand woke early'), findsOneWidget);
    expect(field.controller!.text, isEmpty);
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isFalse);
  }, variant: desktops);

  testWidgets('on a phone the message box is unchanged: the Enter key does not send', (tester) async {
    await flow.pumpApp(tester, flow.makeState(demo: true));
    await openChat(tester);
    await tester.enterText(find.byType(TextField), 'still typing');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'still typing');
    expect(find.byType(PlatformMenuBar), findsNothing);
    expect(find.byType(Shortcuts).evaluate().where((e) => (e.widget as Shortcuts).shortcuts.keys
        .any((a) => a is SingleActivator && a.trigger == LogicalKeyboardKey.keyK)), isEmpty);
  });

  testWidgets('right-click on a message offers the system\'s Copy (owner, 2026-11-19); an open session is never closed '
      'by a shortcut', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpDesktop(tester, flow.makeState(demo: true));
    await openChat(tester);
    // her reply: plain text in the screen's selection area, so a right-click shows the standard menu (on Linux, Select
    // all while nothing is selected yet), and Ctrl+C copies the selection
    final bubble = find.byType(MessageBubble).first;
    final words = tester.widget<MessageBubble>(bubble).text;
    expect(tester.widget<MessageBubble>(bubble).mine, isFalse);
    await tester.tap(find.descendant(of: bubble, matching: find.byType(Text)).first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy_message')), findsNothing, reason: 'the standard menu, not a whole-message copy');
    // (the label is "Select All" when an earlier Mac variant's theme is reused in this run: the same button)
    await tester.tap(find.textContaining(RegExp(r'^Select [Aa]ll$')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copied, contains(words));
    await tester.tapAt(const Offset(5, 5)); // the selection goes; nothing else changes
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.digit2);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.textContaining('Your session is still open'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyN);
    expect(find.byType(CheckInScreen), findsNothing);
  }, variant: linux);

  testWidgets('On this Mac: the menu-bar icon is off at first, follows its switch, and opens a quick check-in',
      (tester) async {
    final host = NoDesktopHost();
    DesktopHost.instance = host;
    addTearDown(() => DesktopHost.instance = NoDesktopHost());
    final state = flow.makeState(demo: true);
    await pumpDesktop(tester, state);
    expect(state.data.settings.trayOn, isFalse);
    expect(host.trayShown, isFalse);
    await press(tester, LogicalKeyboardKey.comma);
    final toggle = find.byKey(const Key('tray_switch'));
    await tester.scrollUntilVisible(toggle, 300, scrollable: settingsList());
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(find.text(onMac ? 'On this Mac' : 'On this computer'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.data.settings.trayOn, isTrue);
    expect(host.trayShown, isTrue);
    expect((await state.vault.load()).settings.trayOn, isTrue);

    host.trayPick!('mood'); // "Log how I feel" in the menu-bar icon's menu
    await tester.pumpAndSettle();
    expect(host.broughtToFront, 1);
    expect(find.byType(QuickMood), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick_mood_7')));
    await tester.pumpAndSettle();
    expect(state.data.moods[isoDate(flow.now)], 7);
    expect(find.text('Saved for today'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick_mood_done')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickMood), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(host.trayShown, isFalse);
  }, variant: desktops);

  testWidgets('on a phone Settings has no On this Mac section', (tester) async {
    await flow.pumpApp(tester, flow.makeState(demo: true));
    await flow.tapIn(tester, find.text('You'));
    await flow.tapIn(tester, find.byTooltip('Settings'));
    await tester.scrollUntilVisible(find.byKey(const Key('settings_about')), 300, scrollable: settingsList());
    expect(find.text('On this Mac'), findsNothing);
    expect(find.byKey(const Key('tray_switch')), findsNothing);
  });

  testWidgets('the Mac menu bar: Apple\'s items, Command shortcuts that are not Apple\'s own, and items that work',
      (tester) async {
    menuCalls.clear();
    await pumpDesktop(tester, flow.makeState(demo: true));
    expect(menuCalls, contains('Menu.setMenus'));
    final menus = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus;
    expect([for (final m in menus) m.label], [appName, 'File', 'Edit', 'View', 'Go', 'Window', 'Help']);
    final items = flatten(menus).toList();
    final provided = items.whereType<PlatformProvidedMenuItem>().map((i) => i.type).toSet();
    expect(provided, containsAll([PlatformProvidedMenuItemType.about, PlatformProvidedMenuItemType.quit,
        PlatformProvidedMenuItemType.hide, PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.toggleFullScreen]));
    // round 9 review, 9A-06: no Services submenu, which sends a text box's selection to other apps and services
    expect(provided, isNot(contains(PlatformProvidedMenuItemType.servicesSubmenu)));
    PlatformMenuItem named(String label) => items.firstWhere((i) => i.label == label);
    final settings = named('Settings…').shortcut as SingleActivator;
    expect((settings.trigger, settings.meta, settings.control), (LogicalKeyboardKey.comma, true, false));
    // the app's own commands use Command and never one of Apple's standard shortcuts (Hide, Quit, Close, Minimise,
    // Save, Print, Open, New Tab, and the Edit items, which keep their usual meaning in the Edit menu)
    const apple = {'H', 'Q', 'W', 'M', 'S', 'P', 'O', 'T', 'C', 'V', 'X', 'Z', 'A'};
    for (final c in [...desktopCommands, paletteCommand]) {
      final a = c.activator;
      if (a == null) continue;
      expect(a.meta && !a.control, isTrue, reason: c.id);
      if (!a.shift) expect(apple.contains(a.trigger.keyLabel.toUpperCase()), isFalse, reason: c.id);
    }
    named('Get Support Now').onSelected!();
    await tester.pumpAndSettle();
    expect(find.byType(CrisisSheet), findsOneWidget);
    await closeSheet(tester, find.byType(CrisisSheet));
    named('Find in Past Sessions…').onSelected!();
    await tester.pumpAndSettle();
    expect(find.byType(MemorySearchScreen), findsOneWidget);
    named('Progress').onSelected!();
    await tester.pumpAndSettle();
    expect(find.byType(MemorySearchScreen), findsNothing);
    expect(find.byType(ProgressTab), findsOneWidget);
    named('Log How I Feel').onSelected!();
    await tester.pumpAndSettle();
    expect(find.byType(QuickMood), findsOneWidget);
  }, variant: mac);

  testWidgets('Linux and Windows have no native menu bar, so none is drawn (the shortcuts and Ctrl+K stand in)',
      (tester) async {
    menuCalls.clear();
    await pumpDesktop(tester, flow.makeState(demo: true));
    expect(find.byType(PlatformMenuBar), findsNothing);
    expect(menuCalls, isEmpty);
  }, variant: linux);

  group('the window', () {
    test('its place is kept with the settings, checked when read back, and off until it has moved', () {
      final fresh = Settings.fromJson({});
      expect((fresh.trayOn, fresh.windowLeft, fresh.windowTop, fresh.windowWidth, fresh.windowHeight),
          (false, null, null, 1100.0, 760.0));
      final odd = Settings.fromJson({'tray_on': 'yes', 'window_left': 'x', 'window_top': 1e9, 'window_width': 100,
          'window_height': 99999});
      expect((odd.trayOn, odd.windowLeft, odd.windowTop, odd.windowWidth, odd.windowHeight),
          (false, null, null, 400.0, 20000.0));
      final kept = Settings(trayOn: true, windowLeft: -1440, windowTop: 30, windowWidth: 900, windowHeight: 700);
      final back = Settings.fromJson(kept.toJson());
      expect((back.trayOn, back.windowLeft, back.windowTop, back.windowWidth, back.windowHeight),
          (true, -1440.0, 30.0, 900.0, 700.0));
    });

    test('it opens where it was, if that is still on a screen, else centred at the default size', () {
      const laptop = Rect.fromLTWH(0, 25, 1440, 875);
      const second = Rect.fromLTWH(1440, 0, 1920, 1080);
      Settings at(double x, double y, double w, double h) =>
          Settings(windowLeft: x, windowTop: y, windowWidth: w, windowHeight: h);
      expect(restoredBounds(Settings(), [laptop]), isNull); // never moved: the default, centred
      expect(restoredBounds(at(100, 80, 1000, 700), [laptop]), const Rect.fromLTWH(100, 80, 1000, 700));
      expect(restoredBounds(at(1600, 100, 1000, 700), [laptop, second]), const Rect.fromLTWH(1600, 100, 1000, 700));
      expect(restoredBounds(at(1600, 100, 1000, 700), [laptop]), isNull); // the second screen was unplugged
      // larger than the screen it is on: shrunk to it and moved inside it
      expect(restoredBounds(at(-50, 0, 3000, 2000), [laptop]), laptop);
      expect(restoredBounds(at(100, 80, 1000, 700), []), const Rect.fromLTWH(100, 80, 1000, 700));
    });

    test("another device's data keeps this computer's window and menu-bar icon", () {
      final here = AppData(settings: Settings(trayOn: true, windowLeft: 10, windowTop: 20, windowWidth: 800,
          windowHeight: 650));
      final there = AppData(settings: Settings(windowLeft: 3000, windowTop: 900));
      final merged = importInto(here, there).settings;
      expect((merged.trayOn, merged.windowLeft, merged.windowTop, merged.windowWidth, merged.windowHeight),
          (true, 10.0, 20.0, 800.0, 650.0));
    });
  });

  // Owner, 2026-11-16: "the design should adapt to mobile and PC": with a mouse and a keyboard, Settings is one click
  // from the rail, Esc closes a dialog or a sheet, and a mood mark can be reached and chosen from the keyboard.
  testWidgets('the mouse and the keyboard: Settings from the rail, Esc closes dialogs and sheets, the mood by keyboard',
      (tester) async {
    final state = flow.makeState(demo: true);
    await pumpDesktop(tester, state);
    await tester.tap(find.byKey(const Key('rail_settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Model, voice and safety files'), findsOneWidget);
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();
    final home = tester.element(find.byType(HomeShell));
    showDialog<void>(context: home, builder: (_) => const AlertDialog(title: Text('A question')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: 'Esc closes a dialog');
    showQuickMood(home);
    await tester.pumpAndSettle();
    expect(find.byType(QuickMood), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QuickMood), findsNothing, reason: 'Esc closes a sheet');
    final mark = find.byKey(const Key('mood_5'));
    // reached and chosen from the keyboard
    Focus.of(tester.element(find.descendant(of: mark, matching: find.byType(SizedBox)).first)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(state.data.moods[isoDate(state.clock())], 5);
  }, variant: desktops);
}
