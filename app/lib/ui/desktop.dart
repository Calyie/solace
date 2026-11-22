// Desktop-class polish for the Mac and Linux (report P1 #19 and P2 #27; docs/research/research_notes/Premium
// wellbeing app design/interaction_craft.md, section 9): the real Mac menu bar with Apple's standard items and
// shortcuts (Command first, no standard shortcut given a new meaning), the same shortcuts with Ctrl on Linux and
// Windows, a command menu (Cmd+K or Ctrl+K), Return to send in a session, right-click to copy a message, a quick
// "how are you right now?" from anywhere, and Settings > On this Mac. The research's warning was the phone screens
// shipped to the computer unchanged; this is the keyboard and pointer layer on top of them.
//
// Phones and tablets are untouched: every piece here hands back its child as it is there.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/session.dart' show dataChangingReason;
import 'appearance.dart';
import 'command_palette.dart';
import 'app_lock.dart';
import 'crisis.dart';
import 'desktop_host.dart';
import 'home.dart' show openSession;
import 'memory_search.dart';
import 'practices.dart' show openPractice;
import 'premium.dart';
import 'settings.dart';
import 'theme.dart';

/// A computer with a keyboard and a pointer: the Mac, Linux or Windows.
bool get onDesktop => switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.linux || TargetPlatform.windows => true,
      _ => false,
    };

bool get onMac => defaultTargetPlatform == TargetPlatform.macOS;

/// The navigator the menus, the shortcuts and the menu-bar icon act on (MaterialApp.navigatorKey in main.dart).
final appNavigatorKey = GlobalKey<NavigatorState>();

/// One thing the person can do from the menus, the keyboard or the command menu.
class DesktopCommand {
  const DesktopCommand(this.id, this.label, this.icon, {required this.menuLabel, this.key, this.shift = false,
      this.keywords = ''});
  final String id;
  final String label; // the command menu's words (sentence case, like the rest of the app)
  final String menuLabel; // the Mac menu bar's words (title case, as Apple's menus are written)
  final IconData icon;
  final LogicalKeyboardKey? key; // with Command on the Mac, Ctrl elsewhere
  final bool shift;
  final String keywords; // other words the command menu finds it by

  SingleActivator? get activator => key == null ? null : SingleActivator(key!, meta: onMac, control: !onMac, shift: shift);

  /// The shortcut as each platform writes it: ⇧⌘H on the Mac, Ctrl+Shift+H elsewhere.
  String? get shortcutLabel {
    final k = key;
    if (k == null) return null;
    final name = k == LogicalKeyboardKey.equal ? '+' : k == LogicalKeyboardKey.minus ? (onMac ? '−' : '-')
        : k == LogicalKeyboardKey.comma ? ',' : k.keyLabel.toUpperCase();
    return onMac ? '${shift ? '⇧' : ''}⌘$name' : 'Ctrl+${shift ? 'Shift+' : ''}$name';
  }
}

const tabNames = ['Today', 'Talk', 'Practices', 'Progress', 'You']; // home.dart's tabs, in order
const _tabIcons = [Icons.wb_sunny_outlined, Icons.chat_bubble_outline, Icons.self_improvement, Icons.insights_outlined,
    Icons.person_outline];
const _digits = [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5];

/// Every command, in the command menu's order. Support is near the top and found by the words people in distress
/// type; its shortcut (⇧⌘H, "help") is not one of Apple's standard ones.
final desktopCommands = <DesktopCommand>[
  const DesktopCommand('session', "Start today's session", Icons.play_circle_outline,
      menuLabel: "Start Today's Session", key: LogicalKeyboardKey.keyN,
      keywords: 'new conversation talk check-in begin solace'),
  const DesktopCommand('mood', 'Log how I feel', Icons.mood_outlined, menuLabel: 'Log How I Feel',
      keywords: 'mood check-in feeling today right now'),
  const DesktopCommand('breathe', 'Breathe for a minute', Icons.air, menuLabel: 'Breathe for a Minute',
      keywords: 'calm sigh cyclic breathing relax anxious stress'),
  const DesktopCommand('support', 'Get support now', Icons.favorite_outline, menuLabel: 'Get Support Now',
      key: LogicalKeyboardKey.keyH, shift: true,
      keywords: 'crisis help emergency urgent danger unsafe harm suicide hotline numbers call'),
  const DesktopCommand('find', 'Find in past sessions', Icons.search, menuLabel: 'Find in Past Sessions…',
      key: LogicalKeyboardKey.keyF, keywords: 'search memory journal look'),
  for (var i = 0; i < tabNames.length; i++)
    DesktopCommand('tab$i', 'Go to ${tabNames[i]}', _tabIcons[i], menuLabel: tabNames[i], key: _digits[i],
        keywords: 'tab'),
  const DesktopCommand('bigger', 'Larger text', Icons.text_increase, menuLabel: 'Larger Text',
      key: LogicalKeyboardKey.equal, keywords: 'zoom in bigger font size'),
  const DesktopCommand('smaller', 'Smaller text', Icons.text_decrease, menuLabel: 'Smaller Text',
      key: LogicalKeyboardKey.minus, keywords: 'zoom out font size'),
  const DesktopCommand('actual', 'Standard text size', Icons.format_size, menuLabel: 'Standard Text Size',
      key: LogicalKeyboardKey.digit0, keywords: 'actual reset zoom font'),
  const DesktopCommand('settings', 'Settings', Icons.settings_outlined, menuLabel: 'Settings…',
      key: LogicalKeyboardKey.comma,
      // what people look for in Settings, so the command menu finds it by any of them
      keywords: 'preferences options model files voice portrait face lock passcode privacy reminders notifications '
          'country safety export data delete transfer devices space'),
  const DesktopCommand('appearance', 'Settings › Appearance', Icons.palette_outlined, menuLabel: 'Appearance…',
      keywords: 'theme dark light colour color font serif'),
];

/// The command menu itself: ⌘K on the Mac, Ctrl+K elsewhere.
const paletteCommand = DesktopCommand('palette', 'Command menu', Icons.keyboard_command_key, menuLabel: 'Command Menu…',
    key: LogicalKeyboardKey.keyK);

DesktopCommand commandFor(String id) => [...desktopCommands, paletteCommand].firstWhere((c) => c.id == id);

/// A command asked for from the keyboard.
class DesktopIntent extends Intent {
  const DesktopIntent(this.id);
  final String id;
}

/// Lets the menus and shortcuts switch the home tabs (DesktopTabSwitch in home.dart listens).
class DesktopTabs extends ChangeNotifier {
  int tab = 0;
  void go(int i) {
    tab = i;
    notifyListeners();
  }
}

/// What the desktop layer offers the screens under it: the tab requests, and running a command by its id.
class DesktopScope extends InheritedWidget {
  const DesktopScope({super.key, required this.tabs, required this.run, required super.child});
  final DesktopTabs tabs;
  final Future<void> Function(String id) run;

  static DesktopScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DesktopScope>();

  @override
  bool updateShouldNotify(DesktopScope oldWidget) => tabs != oldWidget.tabs;
}

/// Wraps the home tabs (home.dart): switches to the tab the menus or shortcuts ask for.
class DesktopTabSwitch extends StatefulWidget {
  const DesktopTabSwitch({super.key, required this.onTab, required this.child});
  final void Function(int tab) onTab;
  final Widget child;
  @override
  State<DesktopTabSwitch> createState() => _DesktopTabSwitchState();
}

class _DesktopTabSwitchState extends State<DesktopTabSwitch> {
  DesktopTabs? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DesktopScope.maybeOf(context)?.tabs;
    if (tabs == _tabs) return;
    _tabs?.removeListener(_asked);
    _tabs = tabs?..addListener(_asked);
  }

  void _asked() => widget.onTab(_tabs!.tab);

  @override
  void dispose() {
    _tabs?.removeListener(_asked);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Marks a session that is running (chat.dart, call.dart). A session is saved only when it ends, so the menus
/// never close one to switch tabs or start another; they say so kindly instead.
class OpenSession extends StatefulWidget {
  const OpenSession({super.key, required this.child});
  final Widget child;
  static int count = 0;
  @override
  State<OpenSession> createState() => _OpenSessionState();
}

class _OpenSessionState extends State<OpenSession> {
  @override
  void initState() {
    super.initState();
    OpenSession.count++;
  }

  @override
  void dispose() {
    OpenSession.count--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The desktop layer, around every screen (MaterialApp.builder in main.dart): the Mac menu bar, the shortcuts, the
/// command menu, the window's kept place and the menu-bar icon. On a phone it is only its child.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _tabs = DesktopTabs();
  final _open = <String>{}; // the command menu and the sheets already showing, so a shortcut never stacks a second
  late final List<PlatformMenuItem> _menus = _macMenus();
  late AppState _state;
  bool? _trayShown;

  @override
  void initState() {
    super.initState();
    if (onDesktop) DesktopHost.instance.onBoundsChanged = _keepBounds;
  }

  @override
  void dispose() {
    if (onDesktop) DesktopHost.instance.onBoundsChanged = null;
    _tabs.dispose();
    super.dispose();
  }

  // The window's place, kept with the rest of the settings (encrypted); nothing redraws for it.
  void _keepBounds(Rect b) {
    if (!mounted) return;
    _state.data.settings
      ..windowLeft = b.left
      ..windowTop = b.top
      ..windowWidth = b.width
      ..windowHeight = b.height;
    unawaited(_state.save()); // a failed save shows the usual banner, never silent (verification round 2, F-05)
  }

  // The menu-bar icon follows its switch in Settings > On this Mac.
  void _syncTray() {
    final on = _state.data.settings.trayOn;
    if (on == _trayShown) return;
    _trayShown = on;
    unawaited(DesktopHost.instance.setTray(on, _trayPick));
  }

  void _trayPick(String id) {
    final host = DesktopHost.instance;
    switch (id) {
      case 'quit':
        unawaited(host.quit());
      case 'open':
        unawaited(host.bringToFront());
      default:
        unawaited(() async {
          await host.bringToFront();
          await run(id);
        }());
    }
  }

  /// Runs a command by its id, from a menu, a shortcut, the command menu or the menu-bar icon.
  Future<void> run(String id) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null || !mounted) return;
    // behind the lock screen nothing runs (OWASP OW-M3-1); its own Support button stays there
    if (appLocked.value) return;
    if (_open.contains('palette')) {
      if (id == 'palette') unawaited(nav.maybePop()); // the shortcut again closes the command menu
      return;
    }
    final at = nav.overlay?.context ?? nav.context; // below the navigator: where screens and sheets open
    final state = _state;
    // while a transfer is brought in or everything is deleted, nothing opens a screen over it or closes it, and no
    // session starts (review cycle 1, D4); Support, the quick mood and the text size still work
    if (_screenCommands.contains(id) || id.startsWith('tab')) {
      if (_dataChanging(at)) return;
    }
    switch (id) {
      case 'settings':
        unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())));
      case 'appearance': // over Settings, so Back goes to Settings
        unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())));
        unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const AppearanceScreen())));
      case 'find':
        unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const MemorySearchScreen())));
      case 'support':
        await _once(id, () => showCrisisSheet(at));
      case 'mood':
        await _once(id, () => showQuickMood(at));
      case 'breathe':
        final practice = state.library.where((p) => p.id == 'cyclic-sighing').firstOrNull;
        // a guided practice is a sheet over what is open; one that is a session waits, as a session does
        if (practice != null && (practice.guided || (!_dataChanging(at) && !_sessionRunning(at)))) {
          openPractice(at, practice);
        }
      case 'session':
        if (!_sessionRunning(at)) openSession(at, state.todaysKind());
      case 'bigger' || 'smaller' || 'actual':
        await _textSize(id);
      case 'palette':
        await _once(id, () async {
          final picked = await showCommandPalette(at, desktopCommands);
          _open.remove(id);
          if (picked != null) await run(picked);
        });
      default:
        if (id.startsWith('tab') && !_sessionRunning(at)) {
          nav.popUntil((r) => r.isFirst);
          _tabs.go(int.parse(id.substring(3)));
        }
    }
  }

  Future<void> _once(String id, Future<void> Function() show) async {
    if (!_open.add(id)) return;
    try {
      await show();
    } finally {
      _open.remove(id);
    }
  }

  /// The commands that open a screen or start a session; the tabs too, which close what is open.
  static const _screenCommands = {'settings', 'appearance', 'find', 'session'};

  bool _dataChanging(BuildContext at) {
    if (!_state.changingData) return false;
    ScaffoldMessenger.maybeOf(at)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(dataChangingReason)));
    return true;
  }

  bool _sessionRunning(BuildContext at) {
    if (OpenSession.count == 0) return false;
    ScaffoldMessenger.maybeOf(at)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Your session is still open. End it when you are ready, then try again.')));
    return true;
  }

  // Steps through the app's text sizes (theme.dart), as Settings > Appearance does, and keeps the choice.
  Future<void> _textSize(String id) async {
    final s = _state.data.settings;
    final sizes = [for (final (f, _) in textSizes) f];
    var at = 0;
    for (var i = 1; i < sizes.length; i++) {
      if ((sizes[i] - s.textSize).abs() < (sizes[at] - s.textSize).abs()) at = i;
    }
    final next = switch (id) {
      'bigger' => sizes[math.min(at + 1, sizes.length - 1)],
      'smaller' => sizes[math.max(at - 1, 0)],
      _ => 1.0,
    };
    if (next == s.textSize) return;
    s.textSize = next;
    await _state.save();
  }

  // The Mac menu bar: Apple's own items where the system provides them, the app's commands with their shortcuts.
  List<PlatformMenuItem> _macMenus() {
    PlatformMenuItem item(String id) {
      final c = commandFor(id);
      return PlatformMenuItem(label: c.menuLabel, shortcut: c.activator, onSelected: () => unawaited(run(id)));
    }

    PlatformMenuItem provided(PlatformProvidedMenuItemType type) => PlatformProvidedMenuItem(type: type);
    // the standard Edit items act on the text box that has the focus, through Flutter's own text actions
    PlatformMenuItem edit(String label, LogicalKeyboardKey key, Intent intent, {bool shift = false}) => PlatformMenuItem(
        label: label, shortcut: SingleActivator(key, meta: true, shift: shift), onSelected: () {
          final focused = primaryFocus?.context;
          if (focused != null) Actions.maybeInvoke(focused, intent);
        });
    const cause = SelectionChangedCause.keyboard;
    return [
      // no Services submenu (round 9 review, 9A-06): it offers the selection in a text box to other apps and
      // services ("Search With Google", "New Email With Selection"); kept off when copying became the system's own
      // (owner, 2026-11-19), as it is not part of copying
      PlatformMenu(label: appName, menus: [
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.about)]),
        PlatformMenuItemGroup(members: [item('settings')]),
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.hide),
            provided(PlatformProvidedMenuItemType.hideOtherApplications),
            provided(PlatformProvidedMenuItemType.showAllApplications)]),
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.quit)]),
      ]),
      PlatformMenu(label: 'File', menus: [
        PlatformMenuItemGroup(members: [item('session'), item('mood'), item('breathe')]),
      ]),
      PlatformMenu(label: 'Edit', menus: [
        PlatformMenuItemGroup(members: [edit('Undo', LogicalKeyboardKey.keyZ, const UndoTextIntent(cause)),
            edit('Redo', LogicalKeyboardKey.keyZ, const RedoTextIntent(cause), shift: true)]),
        PlatformMenuItemGroup(members: [
          edit('Cut', LogicalKeyboardKey.keyX, const CopySelectionTextIntent.cut(cause)),
          edit('Copy', LogicalKeyboardKey.keyC, CopySelectionTextIntent.copy),
          edit('Paste', LogicalKeyboardKey.keyV, const PasteTextIntent(cause)),
          edit('Select All', LogicalKeyboardKey.keyA, const SelectAllTextIntent(cause)),
        ]),
        PlatformMenuItemGroup(members: [item('find')]),
      ]),
      PlatformMenu(label: 'View', menus: [
        PlatformMenuItemGroup(members: [item('bigger'), item('smaller'), item('actual')]),
        PlatformMenuItemGroup(members: [item('palette'), item('appearance')]),
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.toggleFullScreen)]),
      ]),
      PlatformMenu(label: 'Go', menus: [for (var i = 0; i < tabNames.length; i++) item('tab$i')]),
      PlatformMenu(label: 'Window', menus: [
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.minimizeWindow),
            provided(PlatformProvidedMenuItemType.zoomWindow)]),
        PlatformMenuItemGroup(members: [provided(PlatformProvidedMenuItemType.arrangeWindowsInFront)]),
      ]),
      PlatformMenu(label: 'Help', menus: [item('support')]),
    ];
  }

  // The same shortcuts in the window (Linux and Windows have no menu bar; on the Mac the window answers first and
  // the menu bar only when the window did not, so a shortcut never runs twice).
  Map<ShortcutActivator, Intent> get _shortcuts {
    SingleActivator mod(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: onMac, control: !onMac, shift: shift);
    return {
      for (final c in [...desktopCommands, paletteCommand])
        if (c.activator != null) c.activator!: DesktopIntent(c.id),
      // + where it needs Shift, and the number pad
      mod(LogicalKeyboardKey.equal, shift: true): const DesktopIntent('bigger'),
      mod(LogicalKeyboardKey.numpadAdd): const DesktopIntent('bigger'),
      mod(LogicalKeyboardKey.numpadSubtract): const DesktopIntent('smaller'),
      mod(LogicalKeyboardKey.numpad0): const DesktopIntent('actual'),
    };
  }

  static final _hoverThemes = Expando<ThemeData>();

  @override
  Widget build(BuildContext context) {
    // copy and cut are Flutter's own everywhere, as in any other app (owner, 2026-11-19; until then they went through a
    // clipboard guard, round 8, A-11)
    if (!onDesktop) return widget.child;
    _state = AppScope.of(context);
    _syncTray();
    final theme = Theme.of(context);
    // a pointer hovers: cards clip their hover tint to their rounded corners (a phone never shows hover)
    final hoverTheme = _hoverThemes[theme] ??=
        theme.copyWith(cardTheme: theme.cardTheme.copyWith(clipBehavior: Clip.antiAlias));
    Widget child = Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: {DesktopIntent: CallbackAction<DesktopIntent>(onInvoke: (i) {
          unawaited(run(i.id));
          return null;
        })},
        child: DesktopScope(tabs: _tabs, run: run, child: Theme(data: hoverTheme, child: widget.child)),
      ),
    );
    if (onMac) child = PlatformMenuBar(menus: _menus, child: child);
    return child;
  }
}

/// "How are you right now?" from anywhere (the menus, the command menu, the menu-bar icon): the same mood scale as
/// Today, saved for today with one click, over whatever is open, so nothing is closed to reach it.
Future<void> showQuickMood(BuildContext context) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    sheetAnimationStyle: calmSheet(context), builder: (_) => const QuickMood());

class QuickMood extends StatefulWidget {
  const QuickMood({super.key});
  @override
  State<QuickMood> createState() => _QuickMoodState();
}

class _QuickMoodState extends State<QuickMood> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final mood = state.data.moods[isoDate(state.clock())];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How are you right now?', style: t.headlineSmall),
        const SizedBox(height: Space.xs),
        Text('Choose a number. It is saved for today, on this device only.', style: t.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: Space.l),
        MoodScale(value: mood, name: 'quick_mood', onChanged: (i) async {
          await state.saveMood(i);
          feelDone();
          if (mounted) setState(() => _saved = true);
        }),
        const SizedBox(height: Space.l),
        Row(children: [
          Expanded(child: AnimatedOpacity(opacity: _saved ? 1 : 0, duration: Calm.normal, curve: Calm.curve,
              child: Text('Saved for today', style: t.bodySmall))),
          FilledButton.tonal(key: const Key('quick_mood_done'), onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ]),
      ]),
    );
  }
}

/// A session's message box on a computer: Return sends, Shift+Return starts a new line, and Esc stops the reply being
/// written, as the Stop beside the box does (report 2026-11-14, P1 19), or, with nothing to stop, leaves the box. On a
/// phone the box is unchanged.
class ComposerKeys extends StatelessWidget {
  const ComposerKeys({super.key, required this.controller, required this.onSend, required this.child, this.onStop});
  final TextEditingController controller;
  final VoidCallback? onSend; // null while a reply is being written: Return then does nothing and the words stay
  final VoidCallback? onStop; // while Solace's words are coming: what the Stop beside the box does
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!onDesktop) return child;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _SendIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _SendIntent(),
        SingleActivator(LogicalKeyboardKey.enter, shift: true): _NewLineIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _LeaveIntent(),
      },
      child: Actions(actions: {
        _SendIntent: _ComposerAction<_SendIntent>(controller, () => onSend?.call()),
        _NewLineIntent: _ComposerAction<_NewLineIntent>(controller, () {
          final v = controller.value;
          final at = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
          controller.value = v.replaced(at, '\n');
        }),
        _LeaveIntent: CallbackAction<_LeaveIntent>(onInvoke: (_) {
          if (onStop case final stop?) {
            stop();
          } else {
            primaryFocus?.unfocus();
          }
          return null;
        }),
      }, child: child),
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _NewLineIntent extends Intent {
  const _NewLineIntent();
}

class _LeaveIntent extends Intent {
  const _LeaveIntent();
}

class _ComposerAction<T extends Intent> extends Action<T> {
  _ComposerAction(this.controller, this.act);
  final TextEditingController controller;
  final VoidCallback act;

  // while an input method is composing a word (Japanese, Chinese, accents), Return belongs to it
  @override
  bool isEnabled(T intent) => !controller.value.composing.isValid || controller.value.composing.isCollapsed;

  @override
  Object? invoke(T intent) {
    act();
    return null;
  }
}

/// The person's latest message (ui/chat.dart): a right-click or a long press offers Copy and Edit, on every device. Every
/// other message is plain text inside the screen's selection area (ui/premium.dart Readable), so it is selected and
/// copied with the system's own menu, as in any other app (owner, 2026-11-19: "right-clicking and copying text from
/// solace" had been "tiring and frustrating"; a phone had offered no copy at all).
class CopyMenu extends StatefulWidget {
  const CopyMenu({super.key, required this.text, required this.child, this.onEdit});
  final String text;
  final Widget child;
  /// The person's latest message: Edit is offered beside Copy.
  final VoidCallback? onEdit;
  @override
  State<CopyMenu> createState() => _CopyMenuState();
}

class _CopyMenuState extends State<CopyMenu> {
  final _menu = MenuController();

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } catch (_) {
      if (mounted) sayGently(context, 'That could not be copied just now. Please try again.');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.onEdit;
    if (edit == null) return widget.child; // selected and copied with the system's menu
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(key: const Key('copy_message'),
            leadingIcon: const Icon(Icons.copy_outlined, size: 18), onPressed: _copy, child: const Text('Copy')),
        MenuItemButton(key: const Key('edit_message'),
            leadingIcon: const Icon(Icons.edit_outlined, size: 18), onPressed: edit, child: const Text('Edit')),
      ],
      child: Semantics(onLongPressHint: 'copy or edit this message', child: GestureDetector(
        onSecondaryTapUp: (d) => _menu.open(position: d.localPosition),
        onLongPressStart: (d) => _menu.open(position: d.localPosition),
        child: widget.child,
      )),
    );
  }
}

/// Settings > On this Mac (On this computer on Linux and Windows): the menu-bar icon, and the keyboard's commands.
/// Shown only on a computer.
class DesktopSettingsSection extends StatefulWidget {
  const DesktopSettingsSection({super.key});
  @override
  State<DesktopSettingsSection> createState() => _DesktopSettingsSectionState();
}

class _DesktopSettingsSectionState extends State<DesktopSettingsSection> {
  @override
  Widget build(BuildContext context) {
    if (!onDesktop) return const SizedBox.shrink();
    final state = AppScope.of(context);
    final s = state.data.settings;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(onMac ? 'On this Mac' : 'On this computer'),
      Card(margin: EdgeInsets.zero, child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the Mac and Linux (tray_manager's Windows icon needs an .ico file, which the app does not ship)
          if (defaultTargetPlatform != TargetPlatform.windows) SwitchListTile(
            key: const Key('tray_switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(onMac ? '$appName in the menu bar' : '$appName in the system tray'),
            subtitle: const Text('A small icon for a quick check-in, with Log how I feel, Breathe and Open $appName. It '
                'never shows anything you have written.'),
            value: s.trayOn,
            onChanged: (v) async {
              s.trayOn = v;
              await state.save();
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            key: const Key('open_commands'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.keyboard_command_key),
            title: const Text('Keyboard shortcuts'),
            subtitle: Text('Everything you can do from the keyboard, with a search. Press '
                '${paletteCommand.shortcutLabel} anywhere.'),
            onTap: () => DesktopScope.maybeOf(context)?.run('palette'),
          ),
          const SizedBox(height: Space.xs),
          Text('The window opens where you left it, at the same size.', style: t.bodySmall),
        ]),
      )),
    ]);
  }
}
