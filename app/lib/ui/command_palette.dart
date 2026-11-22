// The command menu (⌘K on the Mac, Ctrl+K on Linux and Windows; report P1 #19, after Linear's): one search box and
// every command with its shortcut beside it, so the keyboard way is learnt by using it. The arrows move, Return
// chooses, Esc closes; the pointer works too. "Get support now" stays in reach even when nothing matches.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop.dart';
import 'premium.dart';

/// Opens the command menu over the current screen; returns the id of the command chosen, or null.
Future<String?> showCommandPalette(BuildContext context, List<DesktopCommand> commands) => showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close the command menu',
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.28),
      transitionDuration: Calm.quick,
      pageBuilder: (_, _, _) => CommandPalette(commands: commands),
      transitionBuilder: (_, animation, _, child) {
        final a = CurvedAnimation(parent: animation, curve: Calm.curve);
        return FadeTransition(opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(a), child: child));
      },
    );

/// The commands that match what was typed, best first: every word must appear in the name or its other words; a
/// name that starts with the first word comes before one that only contains it. The list's own order breaks ties.
List<DesktopCommand> filterCommands(List<DesktopCommand> all, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return all;
  int score(DesktopCommand c) {
    final name = c.label.toLowerCase();
    final everything = '$name ${c.keywords.toLowerCase()}';
    if (!words.every(everything.contains)) return -1;
    if (name.startsWith(words.first)) return 3;
    if (name.split(RegExp(r'[\s›]+')).any((w) => w.startsWith(words.first))) return 2;
    return name.contains(words.first) ? 1 : 0;
  }

  final found = [for (var i = 0; i < all.length; i++) (i, score(all[i]))].where((e) => e.$2 >= 0).toList()
    ..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return [for (final (i, _) in found) all[i]];
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.commands});
  final List<DesktopCommand> commands;
  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.by);
  final int by;
}

class _ChooseIntent extends Intent {
  const _ChooseIntent();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _selectedKey = GlobalKey();
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<DesktopCommand> get _shown {
    final found = filterCommands(widget.commands, _query.text);
    // nothing matches: support is still offered, one key away
    return found.isNotEmpty ? found : widget.commands.where((c) => c.id == 'support').toList();
  }

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + by) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _selectedKey.currentContext;
      if (row != null) Scrollable.ensureVisible(row, duration: Calm.quick, curve: Calm.curve, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final matched = filterCommands(widget.commands, _query.text).isNotEmpty;
    final shown = _shown;
    if (_selected >= shown.length) _selected = 0;
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(child: Align(
      alignment: const Alignment(0, -0.4),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Readable(maxWidth: 560, selectable: false, child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: (height * 0.72).clamp(160, 560).toDouble()),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: softShadow(context)),
            child: Material(
              color: scheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: scheme.outlineVariant)),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
                      SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
                      SingleActivator(LogicalKeyboardKey.enter): _ChooseIntent(),
                      SingleActivator(LogicalKeyboardKey.numpadEnter): _ChooseIntent(),
                      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                    },
                    child: Actions(
                      actions: {
                        _MoveIntent: CallbackAction<_MoveIntent>(onInvoke: (m) {
                          _move(m.by, shown.length);
                          return null;
                        }),
                        _ChooseIntent: CallbackAction<_ChooseIntent>(onInvoke: (_) {
                          if (shown.isNotEmpty) Navigator.pop(context, shown[_selected].id);
                          return null;
                        }),
                        DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
                          Navigator.pop(context);
                          return null;
                        }),
                      },
                      child: TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.name, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck,
                        key: const Key('palette_search'),
                        controller: _query,
                        autofocus: true,
                        textInputAction: TextInputAction.go,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                            hintText: 'What would you like to do?'),
                        onChanged: (_) => setState(() => _selected = 0),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                if (!matched)
                  Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                      child: Text('Nothing matches those words.', style: t.bodySmall)),
                Flexible(child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: Space.s),
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      _PaletteRow(
                        key: i == _selected ? _selectedKey : null,
                        command: shown[i],
                        selected: i == _selected,
                        onTap: () => Navigator.pop(context, shown[i].id),
                        onHover: (inside) {
                          if (inside && _selected != i) setState(() => _selected = i);
                        },
                      ),
                  ],
                )),
                if (onDesktop) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s + 2),
                    child: Text('↑ ↓ to move, Return to choose, Esc to close', style: t.bodySmall),
                  ),
                ],
              ]),
            ),
          ),
        )),
      ),
    ));
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({super.key, required this.command, required this.selected, required this.onTap,
      required this.onHover});
  final DesktopCommand command;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ink = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final shortcut = command.shortcutLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: Calm.quick,
          curve: Calm.curve,
          decoration: BoxDecoration(color: selected ? scheme.primaryContainer : scheme.surface,
              borderRadius: BorderRadius.circular(14)),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: Key('palette_${command.id}'),
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              onHover: onHover,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
                child: Row(children: [
                  // support keeps the heart colour of the Support button everywhere else
                  Icon(command.icon, size: 20, color: command.id == 'support' ? scheme.error
                      : selected ? scheme.onPrimaryContainer : scheme.primary),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(command.label, style: t.bodyLarge?.copyWith(color: ink))),
                  if (shortcut != null && onDesktop) ...[
                    const SizedBox(width: Space.s),
                    DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scheme.outlineVariant)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(shortcut, style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
