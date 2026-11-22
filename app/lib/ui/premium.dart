// The shared pieces of the premium pass (owner, 2026-11-14: "absolutely of premium quality ... warm, kind"): one
// spacing scale, soft depth for the cards that matter, a readable width on large screens, a section header, gentle
// haptics, and calm motion. Research behind the choices: calm, slow motion as emotional regulation (Headspace), few
// choices laid out as cards, the tab bar always in the same place, gentle haptic cues (docs/DECISIONS.md 2026-11-14).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../core/session.dart' show maxInput;
import 'calm_loop.dart';
import 'theme.dart';

/// The spacing scale: every gap in the app is one of these.
abstract final class Space {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;
}

/// Calm motion: unhurried, settling like a spring with almost no bounce (report 2026-11-14, P1 11: Apple's bounce of
/// 0.15 or less, Material's Standard damping at Expressive pace). Colour and opacity never overshoot. When the device
/// asks for less motion (Reduce Motion on the iPhone, Remove animations on Android), movement becomes an instant
/// change or a simple fade: see [reduced] and [of].
abstract final class Calm {
  static const quick = Duration(milliseconds: 180), normal = Duration(milliseconds: 320), slow = Duration(milliseconds: 520);

  /// Colour, opacity and anything that must never overshoot: a critically damped spring (bounce 0).
  static const curve = SpringCurve();

  /// Movement (a sheet rising, a card arriving, a panel opening): a spring with a tenth of a bounce, a touch brisker
  /// than [curve]; over its duration it never passes where it ends, so it feels physical without looking bouncy.
  static const spatial = SpringCurve(bounce: 0.1);

  /// Looping motion (the thinking dots, the call's listening ring and sound bars); off in tests, so screens settle.
  static bool loop = true;

  /// True when the device asks for less motion: Android's Remove animations (MediaQuery.disableAnimations), or
  /// Reduce Motion on the iPhone, which Flutter reports separately and does not fold into that flag.
  static bool reduced(BuildContext context) => (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
      (View.maybeOf(context)?.platformDispatcher.accessibilityFeatures.reduceMotion ?? false);

  /// [duration], or no time at all when the device asks for less motion.
  static Duration of(BuildContext context, Duration duration) => reduced(context) ? Duration.zero : duration;
}

/// A spring as a curve over an animation's duration: Flutter's [SpringDescription.withDurationAndBounce], the same
/// model as Apple's springs, run over one second and scaled so it ends exactly where it should.
class SpringCurve extends Curve {
  const SpringCurve({this.bounce = 0});
  final double bounce;

  static final _ends = <double, double>{};

  double _x(double t) => SpringSimulation(
      SpringDescription.withDurationAndBounce(duration: const Duration(seconds: 1), bounce: bounce), 0, 1, 0).x(t);

  @override
  double transformInternal(double t) {
    final x = _x(t) / _ends.putIfAbsent(bounce, () => _x(1));
    return bounce == 0 ? x.clamp(0.0, 1.0) : x;
  }
}

/// How a sheet rises and settles: the gentle spring over [Calm.slow], leaving over [Calm.normal]; at once when the
/// device asks for less motion.
AnimationStyle calmSheet(BuildContext context) => Calm.reduced(context)
    ? AnimationStyle.noAnimation
    : AnimationStyle(duration: Calm.slow, reverseDuration: Calm.normal, curve: Calm.spatial);

/// A card arriving: a short fade with a small rise on the gentle spring; with less motion, the fade alone.
class CalmAppear extends StatefulWidget {
  const CalmAppear({super.key, required this.child, this.rise = 12});
  final Widget child;
  final double rise;
  @override
  State<CalmAppear> createState() => _CalmAppearState();
}

class _CalmAppearState extends State<CalmAppear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Calm.normal)..forward();
  late final CurvedAnimation _fade = CurvedAnimation(parent: _c, curve: Calm.curve);
  late final CurvedAnimation _move = CurvedAnimation(parent: _c, curve: Calm.spatial);

  @override
  void dispose() {
    _fade.dispose();
    _move.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _fade, child: Calm.reduced(context) ? widget.child
      : AnimatedBuilder(animation: _move, child: widget.child, builder: (_, child) =>
          Transform.translate(offset: Offset(0, widget.rise * (1 - _move.value)), child: child)));
}

/// When the device asks for less motion, a page arrives as a fade instead of sliding (report 2026-11-14, P1 11):
/// the platform's own transition is kept but held still, so the iPhone's swipe back still works, and the page fades
/// with the swipe. Otherwise the platform's own transition, unchanged.
class CalmPageTransitions extends PageTransitionsBuilder {
  const CalmPageTransitions(this.normal);
  final PageTransitionsBuilder normal;

  @override
  Duration get transitionDuration => normal.transitionDuration;

  @override
  Duration get reverseTransitionDuration => normal.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final inner = normal.delegatedTransition;
    if (inner == null) return null;
    return (context, animation, secondary, snapshot, child) =>
        Calm.reduced(context) ? child : inner(context, animation, secondary, snapshot, child);
  }

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (!Calm.reduced(context)) return normal.buildTransitions(route, context, animation, secondaryAnimation, child);
    return FadeTransition(opacity: animation.drive(CurveTween(curve: Calm.curve)),
        child: normal.buildTransitions(route, context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation, child));
  }
}

/// Corner radii by role, the same everywhere (report 2026-11-14, P1 13): a small part inside a card (a notice, a
/// tag, a picture), a card, a large surface (Solace's card, a dialog), and the top of a sheet. Buttons, chips and text
/// boxes are pills. Each step is the one inside it plus its padding, so corners sit concentric.
abstract final class Radii {
  static const small = 12.0, card = 20.0, large = 24.0, sheet = 28.0;
}

/// A continuous corner (the squircle of Apple's shapes) for a card or a large surface, with an optional hairline.
OutlinedBorder smoothShape(double radius, [BorderSide side = BorderSide.none]) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius), side: side);

/// The side padding of every tab, and the space under its last card.
const tabPadding = EdgeInsets.fromLTRB(20, 0, 20, Space.xl);

/// The title of a tab, the same size and in the same place on every tab (report 2026-11-14, P1 9: a clear scale with
/// about four sizes a screen): an optional quiet line above it (Today's date), the title in the heading face, at most
/// two icon buttons on its right, and an optional line under it that says what the tab is for.
class TabTitle extends StatelessWidget {
  const TabTitle(this.title, {super.key, this.overline, this.subtitle, this.actions = const []});
  final String title;
  final String? overline, subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final quiet = t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final words = Semantics(header: true, child: Text(title, style: t.headlineMedium));
    return Padding(
      // compact on purpose: on a 1280 by 800 window Today's Start must stay in view without scrolling
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (overline != null) Text(overline!, style: quiet),
        if (actions.isEmpty) words else Row(children: [Expanded(child: words), ...actions]),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(subtitle!, style: quiet)),
      ]),
    );
  }
}

/// What a place shows before there is anything in it (report 2026-11-14, P1 20): what will appear here and how to
/// start, calmly, with an optional way to start. Never a bare "Nothing yet", and never shown while something loads.
class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.icon, required this.text, this.action, this.onAction});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: scheme.surfaceContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: scheme.onSurfaceVariant)),
        const SizedBox(width: Space.m),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(text, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
          if (action != null && onAction != null)
            Padding(padding: const EdgeInsets.only(top: Space.xs), child: TextButton(onPressed: onAction,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.s)),
                child: Text(action!))),
        ])),
      ]),
    );
  }
}

/// A screen's top bar held over its content on a large window (a session, Settings), so Back and the actions sit by
/// the words rather than at a 1920- or 2560-pixel window's far corners; on a phone and a small window, unchanged. The
/// bar keeps the page's colour, so nothing shows where it stops.
class BoundedBar extends StatelessWidget implements PreferredSizeWidget {
  const BoundedBar({super.key, required this.bar, required this.maxWidth});
  final PreferredSizeWidget bar;
  final double maxWidth;

  @override
  Size get preferredSize => bar.preferredSize;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: bar));
}

/// A screen's title in its top bar, never cut short on a phone (owner's design review, 2026-11-16: "Weekly ses…" at
/// 360 pixels): one line at the bar's own size when it fits; when it does not, a step smaller on up to two lines (as
/// the iPhone's own titles do), and cut only if even that cannot hold it (very large text on the smallest phone).
class BarTitle extends StatelessWidget {
  const BarTitle(this.text, {super.key, this.style});
  final String text;

  /// The title's look; by default the bar's own (AppBar sets it around its title).
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final base = style ?? DefaultTextStyle.of(context).style;
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        (bool, double) measure(TextStyle s, int lines) {
          final p = TextPainter(text: TextSpan(text: text, style: s), maxLines: lines, textDirection: direction,
              textScaler: scaler)..layout(maxWidth: box.maxWidth);
          final result = (!p.didExceedMaxLines, p.height);
          p.dispose();
          return result;
        }

        if (measure(base, 1).$1) return Text(text, style: base, maxLines: 1, overflow: TextOverflow.ellipsis);
        final small = base.copyWith(fontSize: (base.fontSize ?? 20) * 0.8, height: 1.2);
        final (_, two) = measure(small, 2);
        return Text(text, style: small, softWrap: true, overflow: TextOverflow.ellipsis,
            maxLines: two <= box.maxHeight ? 2 : 1);
      });
}

/// An icon in a soft circle, the one way a list row or an option shows its icon: the accent's tint, or a quiet grey
/// for a quieter choice.
class IconDisc extends StatelessWidget {
  const IconDisc(this.icon, {super.key, this.quiet = false, this.size = 42});
  final IconData icon;
  final bool quiet;
  final double size;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: quiet ? scheme.surfaceContainerHigh : scheme.primaryContainer),
        child: Icon(icon, size: size / 2, color: quiet ? scheme.onSurfaceVariant : scheme.onPrimaryContainer));
  }
}

/// A soft shadow for the few cards that should float (the therapist's card, a running timer); hairlines elsewhere.
List<BoxShadow> softShadow(BuildContext context) => [
      // a glow in the card's own colour, tucked under it (negative spread), never a grey shelf
      BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22), blurRadius: 30,
          spreadRadius: -10, offset: const Offset(0, 14)),
    ];

/// The layout's breakpoints, in logical pixels of width (owner, 2026-11-16: "the design should adapt to mobile and PC";
/// one adaptive design, the same components): a phone below [tablet], a tablet or a small window from [tablet] to
/// [pc], a computer above [pc]. Every screen takes its widths from here and from [Widths], so a later design pass
/// changes them in one place.
abstract final class Breakpoints {
  /// A tablet or a small window from here; a phone below (one column, the tab bar at the bottom).
  static const tablet = 600.0;

  /// A tablet in portrait or a narrow window below here; a tablet on its side or a computer from here.
  static const medium = 840.0;

  /// A computer (or a large tablet) from here: two panes where they help.
  static const pc = 1024.0;

  /// A large window: the rail shows the names beside its icons.
  static const wide = 1200.0;

  /// The content's own width (beside the rail) from which two columns sit side by side, each still a comfortable
  /// width (about 460 or more).
  static const twoPanes = 960.0;

  /// The content's own width from which three columns sit side by side, each still about 480 or more.
  static const threePanes = 1500.0;

  /// The space beside the rail from which the tabs take [Widths.threePanes] (owner's design review, 2026-11-16: at
  /// 2560 the content took less than half the window): a 1440p screen. A 1920-pixel window keeps two columns, with
  /// balanced margins.
  static const threePaneWindow = 1800.0;
}

/// The content's maximum widths, in logical pixels: nothing stretches edge to edge on a large window.
abstract final class Widths {
  /// Reading text and forms (680 to 760 is comfortable).
  static const reading = 720.0;

  /// A tab's list of cards, and a conversation.
  static const list = 760.0;

  /// A message in a conversation: about 60 to 70 characters a line at the reading size (report 2026-11-14, P1 9), so
  /// a long reply on a computer or a tablet reads like a page, not a banner.
  static const message = 560.0;

  /// Two panes side by side (every tab, and Settings, on a computer).
  static const twoPanes = 1120.0;

  /// Three panes side by side (every tab on a very large window): each column about 540, a reading width; the cards
  /// use the space, the text never runs wider.
  static const threePanes = 1680.0;

  /// A dialog.
  static const dialog = 560.0;

  /// A sheet rising from the bottom.
  static const sheet = 640.0;

  /// The first-run steps.
  static const steps = 560.0;

  /// A short form (the passphrase).
  static const form = 480.0;

  /// The lock screen.
  static const lock = 420.0;
}

/// Material's window sizes: a phone (compact), a small tablet or narrow window (medium), a tablet or the Mac
/// (expanded), a large window (large). The navigation and the layout follow them ([Breakpoints]).
enum WindowSize { compact, medium, expanded, large }

WindowSize windowSize(double width) => width < Breakpoints.tablet ? WindowSize.compact
    : width < Breakpoints.medium ? WindowSize.medium : width < Breakpoints.wide ? WindowSize.expanded
    : WindowSize.large;

/// Content no wider than a comfortable reading width, centred on large screens (Mac, tablets).
///
/// Its text can be selected and copied with the system's own menu (owner, 2026-11-19: "remove this option you have
/// that prevents ... right-clicking and copying text from solace as that is tiring and frustrating"): a long press on a
/// phone, a drag or a right-click on a computer, then Copy. Every screen that reads (her replies, notes, the journal,
/// plans, Settings) is laid out in one. [selectable] is false only where nothing is there to read and copy (the lock
/// screen, the passphrase screens, the command menu). Text boxes keep their own selection and menu.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth = Widths.reading, this.selectable = true});
  final Widget child;
  final double maxWidth;
  final bool selectable;
  @override
  Widget build(BuildContext context) {
    final box = ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child);
    return Center(child: selectable ? SelectionArea(child: box) : box);
  }
}

/// The few theme parts that depend on the window's width (MaterialApp.builder in main.dart): from a tablet up, a
/// message at the foot of the screen keeps a sensible width instead of spanning the window. A phone is unchanged.
class WindowTheme extends StatelessWidget {
  const WindowTheme({super.key, required this.child});
  final Widget child;

  static final _wide = Expando<ThemeData>();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < Breakpoints.tablet) return child;
    final theme = Theme.of(context);
    return Theme(data: _wide[theme] ??= theme.copyWith(
        snackBarTheme: theme.snackBarTheme.copyWith(width: Widths.dialog)), child: child);
  }
}

/// Two columns side by side when the space is wide enough ([Breakpoints.twoPanes]), else one after the other, in the
/// same order: the phone's single column is [first] then [second]. For a scrolling list's content.
class TwoPanes extends StatelessWidget {
  const TwoPanes({super.key, required this.first, required this.second, this.flex = const (1, 1)});
  final List<Widget> first, second;
  final (int, int) flex;

  /// Whether a box [width] wide shows two columns.
  static bool fits(double width) => width >= Breakpoints.twoPanes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        Widget column(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min, children: children);
        if (!fits(box.maxWidth)) return column([...first, ...second]);
        // each column starts level with the other: a section header at the top of one has no space above it
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: flex.$1, child: column(_atTop(first))),
          const SizedBox(width: Space.xl),
          Expanded(flex: flex.$2, child: column(_atTop(second))),
        ]);
      });
}

/// The width every tab takes in a space [width] wide beside the rail (the same for all five tabs, so a tab's title
/// never moves when the tab changes): one reading column, two panes from [Breakpoints.twoPanes], three from
/// [Breakpoints.threePaneWindow]. [padding]: the tab's own side padding, inside that width.
double tabWidth(double width, {double padding = 20}) => width - 2 * padding >= Breakpoints.threePaneWindow
    ? Widths.threePanes : TwoPanes.fits(width - 2 * padding) ? Widths.twoPanes : Widths.list;

/// Up to three columns side by side, as many as the width allows ([Breakpoints.twoPanes], [Breakpoints.threePanes]),
/// else one after the other, in the same order: the phone's single column is the [columns] in turn. With room for
/// two of three, the two that [pairFirst] names share a column: the first two (true), or the last two (false). Each
/// column starts level with the others: a section header at the top of one has no space above it.
class Panes extends StatelessWidget {
  const Panes({super.key, required this.columns, this.pairFirst = true, this.twoFlex = const (1, 1)});
  final List<List<Widget>> columns;
  final bool pairFirst;

  /// The two columns' shares of the width, when two show.
  final (int, int) twoFlex;

  /// How many columns a box [width] wide shows.
  static int count(double width) => width >= Breakpoints.threePanes ? 3 : TwoPanes.fits(width) ? 2 : 1;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        Widget column(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min, children: children);
        final all = columns;
        final n = math.min(count(box.maxWidth), all.length);
        if (n <= 1) return column([for (final c in all) ...c]);
        final shown = n >= all.length ? all : all.length == 3 && n == 2
            ? (pairFirst ? [[...all[0], ...all[1]], all[2]] : [all[0], [...all[1], ...all[2]]])
            : [all[0], [for (final c in all.skip(1)) ...c]];
        final flex = shown.length == 2 ? [twoFlex.$1, twoFlex.$2] : [for (final _ in shown) 1];
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, c) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: Space.xl),
            Expanded(flex: flex[i], child: column(_atTop(c))),
          ],
        ]);
      });
}

/// [c] without the empty space at its start, and a section header at its top with no space above it: the top of a
/// column beside another.
List<Widget> _atTop(List<Widget> c) {
  final from = c.indexWhere((w) => w is! SizedBox || w.child != null);
  final rest = from < 0 ? <Widget>[] : c.sublist(from);
  return [for (final (i, w) in rest.indexed) i == 0 && w is SectionHeader ? w.atTop() : w];
}

/// A grid of cards (not text) as wide as its place: as many to a row as keep each card at least [least] wide (and
/// at most [most] to a row), all the same width, so a large window shows more side by side instead of wider cards.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.least = 300, this.most = 4, this.gap = Space.m});
  final List<Widget> children;
  final double least, gap;
  final int most;

  /// How many cards to a row in a box [width] wide.
  static int across(double width, {double least = 300, int most = 4, double gap = Space.m}) =>
      ((width + gap) / (least + gap)).floor().clamp(1, most);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final n = across(box.maxWidth, least: least, most: most, gap: gap);
        final w = (box.maxWidth - gap * (n - 1)) / n;
        return Wrap(spacing: gap, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

/// A screen's content that fills the screen when it fits (so its spacers centre it calmly) and scrolls when it does
/// not: a small phone, a phone on its side, very large text.
class FillOrScroll extends StatelessWidget {
  const FillOrScroll({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - padding.vertical)),
            child: IntrinsicHeight(child: child)),
      ));
}

/// One section header for every list: the title, and an optional quiet link or note on the right. [top]: the space
/// above it (none when it heads a column beside another).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.top = Space.xl});
  final String title;
  final Widget? trailing;
  final double top;

  /// The same header with no space above it (the top of a column).
  SectionHeader atTop() => SectionHeader(title, key: key, trailing: trailing, top: 0);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: Space.s),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ]),
      );
}

/// Touch feedback with one meaning each, and mostly silence (report 2026-11-14, P1 12; Apple: "make haptics optional",
/// and keep vibration away from the microphone): a tick for a choice, a light tap to confirm (sending, saving,
/// starting), one success only when a session is really finished, and a soft warning, never a harsh error, when
/// something fails. Settings > Haptics turns them all off, and none play while a call's microphone is live.
abstract final class Haptics {
  /// Whether the person wants them (Settings.haptics); the app points this at the saved setting (main.dart).
  static bool Function() wanted = () => true;

  /// True while a call is listening (ui/call.dart): every haptic stays silent, so the microphone never hears one.
  static bool micLive = false;

  static void selection() => _play(HapticFeedback.selectionClick);
  static void confirm() => _play(HapticFeedback.lightImpact);
  static void success() => _play(HapticFeedback.successNotification);
  static void warning() => _play(HapticFeedback.warningNotification);

  static void _play(Future<void> Function() pattern) {
    if (micLive || !wanted()) return;
    unawaited(pattern());
  }
}

/// A choice (a mood dot, a tab, an option): the selection tick.
void feelChoice() => Haptics.selection();

/// Something done (sent, saved, started): the light confirm.
void feelDone() => Haptics.confirm();

/// Said when a privacy switch could not be saved, so it was put back as it was (round 6 review, E-01: the switch
/// showed on, and after the next start the app was unlocked, shown in the app switcher, or remembering again).
const settingNotSaved = 'This could not be saved, so the setting is as it was. The device may be full. Free some '
    'space, then try again.';

/// Shows [text] (by default [settingNotSaved]) at the bottom of the screen.
void sayNotSaved(BuildContext context, [String text = settingNotSaved]) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(key: const Key('not_saved'), content: Text(text)));

/// When something did not work (security review 2026-11-14, F-17): a short, plain, kind line at the foot of the screen
/// and the soft warning touch, and the screen stays usable. Never the error itself, which can hold private words.
void sayGently(BuildContext context, String text) {
  if (!context.mounted) return;
  Haptics.warning();
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// The soft lines while Solace prepares a reply (NN/g: 1 second keeps the flow of thought, 10 seconds is the limit of
/// attention; report 2026-11-14, P1 14).
const thinkingSoon = 'Taking a moment to think';
const thinkingLong = 'Still with you. This device is working on it';

/// What shows while Solace prepares a reply, in the chat and on the call: a quiet breathing glyph at once, a soft line
/// after 2 seconds, a reassuring one after 10. It is honest: it never says Solace is "typing". With less motion the
/// dots hold still; the lines still come.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key, this.label, this.onDark = false, this.center = false, this.bubble = false,
      this.glyphHeight = 12, this.soonLine = thinkingSoon, this.longLine = thinkingLong});
  final String? label; // a short state name beside the dots (the call's "Thinking")
  final bool onDark; // drawn over the dark call screen
  final bool center;
  final bool bubble; // the dots in a small card shaped like Solace's messages (the chat)
  final double glyphHeight;
  final String soonLine, longLine;

  static const soonAfter = Duration(seconds: 2), longAfter = Duration(seconds: 10);

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final _loop = CalmLoop(_breath); // MM-02: calm on a computer, still behind other windows (ui/calm_loop.dart)
  int _stage = 0; // 0 the dots alone, 1 the soft line, 2 the reassuring one
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    for (final (after, stage) in [(ThinkingIndicator.soonAfter, 1), (ThinkingIndicator.longAfter, 2)]) {
      _timers.add(Timer(after, () {
        if (!mounted) return;
        setState(() => _stage = stage);
        // in a list (the chat), keep the new line in view
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Scrollable.maybeOf(context) != null) {
            Scrollable.ensureVisible(context, duration: Calm.of(context, Calm.quick), curve: Calm.curve,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
          }
        });
      }));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loop.set(moving: !Calm.reduced(context) && Calm.loop, still: 0.3);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _loop.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ink = widget.onDark ? Colors.white : scheme.primary;
    final quiet = widget.onDark ? Colors.white70 : scheme.onSurfaceVariant;
    final line = switch (_stage) { 1 => widget.soonLine, 2 => widget.longLine, _ => null };
    Widget dots = RepaintBoundary(child: SizedBox(width: 34, height: widget.glyphHeight, child: CustomPaint(
        painter: _DotsPainter(_breath, ink))));
    if (widget.bubble) {
      dots = Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m + 2),
        decoration: BoxDecoration(color: scheme.surface, border: Border.all(color: scheme.outlineVariant),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20),
                bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20))),
        child: dots,
      );
    }
    return Semantics(
      key: const Key('thinking_indicator'),
      label: [widget.label ?? (line == null ? 'Solace is thinking' : null), line].nonNulls.join('. '),
      excludeSemantics: true,
      child: Column(crossAxisAlignment: widget.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          dots,
          if (widget.label != null) ...[
            const SizedBox(width: Space.s),
            Flexible(child: Text(widget.label!, style: t.titleSmall?.copyWith(color: ink))),
          ],
        ]),
        AnimatedSwitcher(
          duration: Calm.normal, switchInCurve: Calm.curve, switchOutCurve: Calm.curve, // a fade, kept with less motion
          child: line == null ? const SizedBox(key: ValueKey(0), width: 0) : Padding(
              key: ValueKey(_stage), padding: const EdgeInsets.only(top: Space.xs),
              child: Text(line, textAlign: widget.center ? TextAlign.center : TextAlign.start,
                  style: t.bodyMedium?.copyWith(color: quiet))),
        ),
      ]),
    );
  }
}

/// Three dots that brighten in turn, slowly, like a breath.
class _DotsPainter extends CustomPainter {
  _DotsPainter(this.breath, this.ink) : super(repaint: breath);
  final Animation<double> breath;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 3.6, gap = 13.0;
    final y = size.height / 2;
    for (var i = 0; i < 3; i++) {
      final phase = (breath.value - i * 0.16) % 1.0;
      final glow = 0.5 - 0.5 * math.cos(phase * 2 * math.pi);
      canvas.drawCircle(Offset(size.width / 2 + (i - 1) * gap, y), r * (0.85 + 0.15 * glow),
          Paint()..color = ink.withValues(alpha: 0.3 + 0.7 * glow));
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.ink != ink || old.breath != breath;
}

/// The mood scale's points in plain words, 0 to 10 (its meaning unchanged: 0 is very low, 10 very good).
const moodWords = ['Very low', 'Very low', 'Low', 'Low', 'A bit low', 'Okay', 'Fairly good', 'Good', 'Good',
  'Very good', 'Very good'];

/// The mood scale (0 to 10), the same on Today, in the check-in, before leaving a session and in the quick check-in:
/// one slider with word labels (owner's report, item 18). The whole row, a finger's height (48), takes a tap or a
/// slide, so no part is ever too small to hit: a tap chooses the nearest point, a slide moves through them with a
/// light tick at each and chooses where the finger lifts. The chosen point shows as its number in the scale's colour,
/// with its word above. With nothing chosen yet, no point is marked. The keyboard reaches it with Tab: the arrows move
/// one point, Home and End go to the ends, and Return or Space, with nothing chosen, chooses the middle. Screen readers
/// hear one adjustable control ("Mood, 6 out of 10, Fairly good").
class MoodScale extends StatefulWidget {
  const MoodScale({super.key, required this.value, required this.onChanged, this.name = 'mood'});
  final int? value;
  final ValueChanged<int> onChanged;
  final String name; // keys: '<name>_<n>', each the place of a point on the track

  @override
  State<MoodScale> createState() => _MoodScaleState();
}

class _MoodScaleState extends State<MoodScale> {
  final _focus = FocusNode(debugLabel: 'mood scale');
  int? _sliding; // the point under the finger while it slides; chosen when it lifts
  int? _hover; // the point under the pointer (a computer)
  bool _focused = false;

  int? get _shown => _sliding ?? widget.value;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _choose(int v) {
    feelChoice();
    widget.onChanged(v);
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final v = widget.value;
    final next = switch (k) {
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowUp => v == null ? 5 : math.min(10, v + 1),
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowDown => v == null ? 5 : math.max(0, v - 1),
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => 10,
      LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter || LogicalKeyboardKey.space => v ?? 5,
      _ => null,
    };
    if (next == null) return KeyEventResult.ignored;
    if (next != v || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) _choose(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final mood = huesOf(context).mood;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.5);
    final shown = _shown;
    final thumb = 34.0 * scale;
    const height = 48.0;
    return LayoutBuilder(builder: (context, box) {
      final inset = thumb / 2 + 2; // the ends of the track, so the chosen mark at 0 or 10 stays whole
      final step = (box.maxWidth - 2 * inset) / 10;
      double xOf(int i) => inset + i * step;
      int at(double x) => ((x - inset) / step).round().clamp(0, 10);
      void slideTo(double x) {
        final v = at(x);
        if (v != _sliding) {
          feelChoice();
          setState(() => _sliding = v);
        }
      }

      void lift() {
        final v = _sliding;
        setState(() => _sliding = null);
        if (v != null) widget.onChanged(v);
      }

      // with nothing chosen, either way chooses the middle; at an end, only the way back
      final v = widget.value;
      final up = v == null ? 5 : v < 10 ? v + 1 : null, down = v == null ? 5 : v > 0 ? v - 1 : null;
      String said(int n) => '$n out of 10, ${moodWords[n]}';
      final track = Semantics(
        container: true, slider: true, focusable: true, focused: _focused,
        label: 'Mood, from 0, very low, to 10, very good',
        value: v == null ? 'Not chosen yet' : said(v),
        increasedValue: up == null ? null : said(up),
        decreasedValue: down == null ? null : said(down),
        onIncrease: up == null ? null : () => _choose(up),
        onDecrease: down == null ? null : () => _choose(down),
        child: ExcludeSemantics(child: Focus(
          focusNode: _focus,
          onKeyEvent: _key,
          onFocusChange: (on) => setState(() => _focused = on),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (e) {
              final v = at(e.localPosition.dx);
              if (v != _hover) setState(() => _hover = v);
            },
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _choose(at(d.localPosition.dx)),
              onHorizontalDragStart: (d) => slideTo(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => slideTo(d.localPosition.dx),
              onHorizontalDragEnd: (_) => lift(),
              onHorizontalDragCancel: lift,
              child: SizedBox(height: math.max(height, thumb + 10), child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: CustomPaint(painter: _MoodTrackPainter(
                  value: shown, mood: mood, inset: inset, step: step,
                  idle: scheme.outlineVariant, stop: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  onActive: scheme.surface.withValues(alpha: 0.75),
                  ghost: shown == null ? (_hover ?? (_focused ? 5 : null)) : (_hover == shown ? null : _hover),
                  ghostColour: scheme.primary.withValues(alpha: 0.35), ghostSize: thumb,
                ))),
                // each point's place, for finding it (tests and tools); the touch is the whole row's
                for (var i = 0; i <= 10; i++)
                  Positioned(key: Key('${widget.name}_$i'), left: xOf(i) - step / 2, width: step, top: 0, bottom: 0,
                      child: const MetaData(behavior: HitTestBehavior.opaque, child: SizedBox.expand())),
                if (shown != null)
                  AnimatedPositioned(
                    duration: _sliding != null ? Duration.zero : Calm.of(context, Calm.quick), curve: Calm.curve,
                    left: xOf(shown) - thumb / 2, top: 0, bottom: 0, width: thumb,
                    child: IgnorePointer(child: Center(child: _MoodThumb(value: shown, size: thumb, colour: mood[shown], focused: _focused,
                        ink: scheme.surface, ring: scheme.primary))),
                  ),
              ])),
            ),
          ),
        )),
      );
      final quiet = t.bodySmall;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // the chosen point in words, or how to choose one
        AnimatedSwitcher(
          duration: Calm.of(context, Calm.quick), switchInCurve: Calm.curve, switchOutCurve: Calm.curve,
          layoutBuilder: (current, previous) => Stack(alignment: AlignmentDirectional.centerStart,
              children: [...previous, ?current]),
          child: shown == null
              ? Text('Tap or slide to choose', key: const ValueKey(-1), style: t.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant))
              : Text.rich(key: ValueKey(moodWords[shown]), TextSpan(children: [
                  TextSpan(text: moodWords[shown], style: t.titleSmall),
                  TextSpan(text: '  $shown out of 10', style: t.bodySmall),
                ])),
        ),
        track,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(moodWords.first, style: quiet)),
          Text(moodWords[5], style: quiet, textAlign: TextAlign.center),
          Expanded(child: Text(moodWords.last, style: quiet, textAlign: TextAlign.end)),
        ]),
      ]);
    });
  }
}

/// The chosen point: its number on a disc in the scale's colour, ringed in the page's colour, with a soft glow; a
/// focus ring around it when the keyboard is on the scale.
class _MoodThumb extends StatelessWidget {
  const _MoodThumb({required this.value, required this.size, required this.colour, required this.focused,
      required this.ink, required this.ring});
  final int value;
  final double size;
  final Color colour, ink, ring;
  final bool focused;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: Calm.of(context, Calm.quick), curve: Calm.curve, width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colour,
            border: Border.all(color: ink, width: 2.5),
            boxShadow: [
              if (focused) BoxShadow(color: ring, spreadRadius: 3),
              BoxShadow(color: colour.withValues(alpha: 0.22), blurRadius: 6, offset: const Offset(0, 1)),
            ]),
        alignment: Alignment.center,
        child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(4),
            child: Text('$value', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700,
                color: ink, fontFeatures: const [FontFeature.tabularFigures()])))),
      );
}

/// The mood scale's track: a calm line with a small mark at each point; up to the chosen point it turns through the
/// scale's colours (indigo to green). A hollow ring shows the point under the pointer, or the middle while the keyboard
/// is on a scale with nothing chosen.
class _MoodTrackPainter extends CustomPainter {
  _MoodTrackPainter({required this.value, required this.mood, required this.inset, required this.step,
      required this.idle, required this.stop, required this.onActive, required this.ghost, required this.ghostColour,
      required this.ghostSize});
  final int? value, ghost;
  final List<Color> mood;
  final double inset, step, ghostSize;
  final Color idle, stop, onActive, ghostColour;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const thick = 6.0;
    final left = inset, right = inset + 10 * step;
    final line = Paint()
      ..strokeWidth = thick
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(right, y), line..color = idle);
    // the scale's colours, faint, along the whole track: where it goes, before anything is chosen
    canvas.drawLine(Offset(left, y), Offset(right, y), Paint()
      ..strokeWidth = thick
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [for (final c in mood) c.withValues(alpha: 0.4)])
          .createShader(Rect.fromLTRB(left, y - thick, right, y + thick)));
    final v = value;
    if (v != null && v > 0) {
      final end = left + v * step;
      canvas.drawLine(Offset(left, y), Offset(end, y), Paint()
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [for (var i = 0; i <= v; i++) mood[i]])
            .createShader(Rect.fromLTRB(left, y - thick, end, y + thick)));
    }
    for (var i = 0; i <= 10; i++) {
      if (i == v) continue;
      canvas.drawCircle(Offset(left + i * step, y), 2, Paint()..color = v != null && i < v ? onActive : stop);
    }
    final g = ghost;
    if (g != null) {
      canvas.drawCircle(Offset(left + g * step, y), ghostSize / 2 - 1, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ghostColour);
    }
  }

  @override
  bool shouldRepaint(_MoodTrackPainter old) => old.value != value || old.ghost != ghost || old.inset != inset ||
      old.step != step || old.idle != idle || old.stop != stop || old.mood != mood || old.ghostColour != ghostColour;
}

/// What every text box tells the keyboard about learning (round 5 review, C-05). The iPhone's keyboard learns the
/// words typed in any box with autocorrection on: its own dictionary and predictions, outside Solace's encryption and
/// its backup exclusion, offered in other apps and kept after Delete everything. enableIMEPersonalizedLearning stops
/// that on Android only. So on the iPhone every box turns autocorrection off (which also turns off the keyboard's
/// spell checking, predictions and learning), suggestions off and spell checking off: typing on the iPhone loses
/// autocorrection, the price of keeping the words out of the keyboard. Android keeps its autocorrection, since its
/// incognito flag already stops the learning there. Every text box takes all three from here, so none can differ;
/// test/privacy_test.dart checks every one.
///
/// Round 9 review, 9A-05: and none is offered to the platform's autofill service. Flutter turns autofill on unless a
/// box's autofillHints is null, and a TextField's default is an empty list, so Android's autofill framework was told
/// of every box, its words and each change to them, and an autofill service (Google's, a password manager) could
/// offer to save the app passcode or the deep work PIN into its own store, often synced to the cloud. Every text box
/// takes [autofillHints] (null: autofill off) from here too; test/privacy_test.dart checks every one.
abstract final class PrivateKeyboard {
  static bool get _iPhone => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get autocorrect => !_iPhone;
  static bool get suggestions => !_iPhone;
  static SpellCheckConfiguration? get spellCheck => _iPhone ? const SpellCheckConfiguration.disabled() : null;
  static const List<String>? autofillHints = null;
}

/// How many characters a text box takes (owner, 2026-11-14): "large enough for people to unload what they are feeling
/// but secure so malicious large text cannot crash the app or device". A longer paste is cut by the box, never
/// frozen on. The safety rules read the whole of what is sent (core/session.dart send); the model reads at most
/// core/formats.dart maxMessage of one message. test/privacy_test.dart checks that every text box has a limit.
abstract final class TextLimit {
  static const message = maxInput; // a chat or call message: 12,000 characters, about 2,000 words
  static const long = 20000; // a long note: a story section, a feeling's note, a debrief, a task to split
  static const short = 1000; // a goal, a value, a step, a parked thought
  static const name = 500; // a search, an area's name
}

/// Where [now] differs from [old] (round 4 review, B-14 and B-15): the length of the start they share and of the end
/// they share, never overlapping, and never between the two halves of an emoji. What lies between them is what an
/// edit or a paste put in (in [now]) and what it took out (in [old]).
(int, int) editSpan(String old, String now) {
  final most = math.min(old.length, now.length);
  var start = 0;
  while (start < most && old.codeUnitAt(start) == now.codeUnitAt(start)) {
    start++;
  }
  if (start > 0 && (_lowAt(now, start) || _lowAt(old, start))) start--; // keep a pair whole
  var end = 0;
  while (end < most - start && old.codeUnitAt(old.length - 1 - end) == now.codeUnitAt(now.length - 1 - end)) {
    end++;
  }
  if (end > 0 && (_lowAt(now, now.length - end) || _lowAt(old, old.length - end))) end--; // keep a pair whole
  return (start, end);
}

/// True when the unit at [i] of [s] is the second half of an emoji's pair.
bool _lowAt(String s, int i) => i >= 0 && i < s.length && s.codeUnitAt(i) >= 0xDC00 && s.codeUnitAt(i) <= 0xDFFF;

/// The counter under a text box with a limit: nothing at all until the words come within a sixth of the limit (from
/// 10,000 of a message's 12,000), then a calm count of what is left.
Widget? quietCounter(BuildContext context,
    {required int currentLength, required bool isFocused, required int? maxLength}) {
  if (maxLength == null || currentLength < maxLength - maxLength ~/ 6) return null;
  final left = maxLength - currentLength;
  return Text(left <= 0 ? 'That is as much as fits here. You can carry on in the next one.'
      : '$left characters left', style: Theme.of(context).textTheme.bodySmall);
}
