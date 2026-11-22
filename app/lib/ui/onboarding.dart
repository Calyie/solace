// The first-run steps (research report P0 2 and the owner's choices, 2026-11-14): welcome; private by design; what
// Solace is and is not (an AI, not a person, a therapist or an emergency service); where the person lives, so the
// right support numbers come first; an 18-or-older confirmation (under 18: lines made for young people, and no way
// on); how Solace looks and sounds (the calm light or a portrait marked AI, and the voice); and an offer of the lock.
// Support is one tap away on every step. Nothing is asked that the app does not use, and every choice can be changed
// later in Settings.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/crisis.dart';
import 'app_lock.dart';
import 'crisis.dart';
import 'model_files.dart';
import 'premium.dart';
import 'presence.dart';
import 'privacy.dart';
import 'theme.dart';

/// The crisis-directory country for a locale's region code (e.g. IE for Ireland), if the directory has it.
String? countryForRegion(String? region) => switch (region?.toUpperCase()) {
      'IE' => 'Ireland',
      'GB' || 'UK' => 'United Kingdom',
      'NG' => 'Nigeria',
      'FR' => 'France',
      'CA' => 'Canada',
      'US' => 'United States',
      'MY' => 'Malaysia',
      'TH' => 'Thailand',
      _ => null,
    };

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _step = 0;
  bool _under18 = false;
  bool _guessed = false;

  /// Whether the step for the model files is offered: decided once, when the steps open, so the steps never change
  /// under the person (a model added on that step does not take the step away).
  bool _offerModel = false;
  int get _steps => _offerModel ? 8 : 7;
  static const _modelStep = 6;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_guessed) return;
    _guessed = true;
    _offerModel = AppScope.of(context).modelInPlace != true; // not known yet at a first start: offered
    // the device's region chooses the first country shown; the person can change it on that step
    final guess = countryForRegion(WidgetsBinding.instance.platformDispatcher.locale.countryCode);
    if (guess != null) AppScope.of(context).data.settings.country = guess;
  }

  void _go(int step) {
    feelChoice();
    setState(() {
      _step = step;
      _under18 = false;
    });
  }

  Future<void> _finish() async {
    final state = AppScope.of(context);
    final s = state.data.settings;
    s.therapistChosen = true;
    s.onboarded = true;
    feelDone();
    await state.save();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: SafeArea(child: Column(children: [
        // on a computer the top row stays over the step, not at the window's far corners
        Readable(maxWidth: Widths.reading, child: Padding(padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
            child: Row(children: [
          // Back and Support share the sides equally, so the dots sit in the middle of the screen, over the words
          Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: SizedBox(width: 48, height: 48,
              child: _step == 0 ? null : IconButton(key: const Key('onb_back'), tooltip: 'Back',
                  onPressed: () => _go(_step - 1), icon: const Icon(Icons.arrow_back))))),
          // the dots shrink rather than overflow beside very large text on the smallest phone
          Flexible(child: Semantics(label: 'Step ${_step + 1} of $_steps', excludeSemantics: true,
              child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < _steps; i++) AnimatedContainer(
              duration: still ? Duration.zero : Calm.normal, curve: Calm.curve,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _step ? 18 : 6, height: 6,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
                  color: i <= _step ? scheme.primary : scheme.outlineVariant),
            ),
          ]))))),
          // support is never more than one tap away, even before the app has started; with very large text on the
          // smallest phone it shrinks rather than crowd the dots
          Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: FittedBox(fit: BoxFit.scaleDown,
              child: TextButton.icon(key: const Key('onb_support'), onPressed: () => showCrisisSheet(context, plan: false),
                  icon: Icon(Icons.favorite_outline, size: 18, color: scheme.error), label: const Text('Support'))))),
        ]))),
        Expanded(child: AnimatedSwitcher(
          duration: still ? Duration.zero : Calm.slow,
          switchInCurve: Calm.curve, switchOutCurve: Calm.curve,
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(
              position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a), child: child)),
          child: KeyedSubtree(key: ValueKey('$_step$_under18'), child: _bounded(context, Readable(
              maxWidth: Widths.steps, child: _step == 0 ? _welcome(context, t) : _layout(_page(context, t, scheme))))),
        )),
      ])),
    );
  }

  /// On a tablet or a computer, a step's words and its buttons stay together in the middle of the window, never a
  /// screen's height apart; a phone keeps its buttons at the bottom, in reach of the thumb.
  Widget _bounded(BuildContext context, Widget step) => LayoutBuilder(builder: (context, box) =>
      box.maxWidth < Breakpoints.tablet ? step
          : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 720), child: step)));

  Widget _next(String label, {Key key = const Key('onb_next'), VoidCallback? onPressed}) => FilledButton(
      key: key, onPressed: onPressed ?? () => _go(_step + 1),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: Text(label));

  /// The step's words scroll when they do not fit (small phones, very large text); its buttons stay in reach below.
  Widget _layout(({List<Widget> content, List<Widget> buttons, bool centred}) page, {Widget? body}) => Column(children: [
        Expanded(child: body ?? LayoutBuilder(builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.l),
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight - 2 * Space.l),
              child: Align(alignment: page.centred ? Alignment.center : Alignment.topCenter, child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: page.content))),
        ))),
        // a phone: the buttons span the width, in reach of the thumb; a tablet or a computer: a sensible width, centred
        if (page.buttons.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.l),
            child: Center(child: ConstrainedBox(constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width < Breakpoints.tablet ? double.infinity : 380),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: page.buttons)))),
      ]);

  /// The welcome (owner's design review, 2026-11-16: on a phone, a lot of empty space above the light): the light is
  /// the picture, as large as the room left by the words allows (140 to 340), and the light and the words stay one
  /// group a little above the middle, so the screen is balanced on every phone from 568 to 956 high and on a computer
  /// (where the step keeps at most 720 of height, _bounded). With very large text on a small phone the light keeps
  /// its smallest size and the words scroll.
  Widget _welcome(BuildContext context, TextTheme t) {
    const about = 'A calm, private place to talk things through, practise skills that help, and notice how you are '
        'doing over time.';
    final title = 'Welcome to $appName';
    const pad = EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.xl);
    const gap = Space.l + Space.xs; // between the light and the words (its soft edge adds to it)
    final scaler = MediaQuery.textScalerOf(context);
    return _layout((centred: true, content: const [], buttons: [_next('Begin')]), body: LayoutBuilder(
        builder: (context, box) {
      final width = box.maxWidth - pad.horizontal;
      double measure(String text, TextStyle? style) {
        final p = TextPainter(text: TextSpan(text: text, style: style), textAlign: TextAlign.center,
            textDirection: Directionality.of(context), textScaler: scaler)..layout(maxWidth: width);
        final h = p.height;
        p.dispose();
        return h;
      }

      final words = measure(title, t.displaySmall) + Space.m + measure(about, t.bodyLarge);
      final space = box.maxHeight - pad.vertical;
      final light = (math.min(space - words - gap, width) * 0.86).clamp(140.0, 340.0);
      // the light and the words as one group, a little above the middle of the room (its optical centre)
      final above = math.max(0.0, (space - light - gap - words) * 0.45);
      return SingleChildScrollView(padding: pad, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        SizedBox(height: above),
        Center(child: AbstractPresence(size: light)),
        const SizedBox(height: gap),
        Text(title, style: t.displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: Space.m),
        Text(about, style: t.bodyLarge, textAlign: TextAlign.center),
      ]));
    }));
  }

  Widget _title(TextTheme t, String text) => Text(text, style: t.headlineMedium, textAlign: TextAlign.start);

  ({List<Widget> content, List<Widget> buttons, bool centred}) _page(BuildContext context, TextTheme t, ColorScheme scheme) {
    final state = AppScope.of(context);
    final s = state.data.settings;
    switch (_step) {
      case 1: // private by design
        return (centred: false, content: [
          _title(t, 'Private by design'),
          const SizedBox(height: Space.s),
          Text('What you share stays with you.', style: t.bodyLarge),
          const SizedBox(height: Space.m),
          const PrivacyPromises(lockInSettings: false),
        ], buttons: [
          _next('Continue'),
        ]);
      case 2: // what Solace is and is not
        Widget item(IconData icon, String text, Color colour) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 20, color: colour),
                const SizedBox(width: Space.m),
                Expanded(child: Text(text, style: t.bodyMedium)),
              ]),
            );
        return (centred: false, content: [
          Row(children: [
            Flexible(child: _title(t, 'What $appName is, and is not')),
            const SizedBox(width: Space.s),
            const AiTag(),
          ]),
          const SizedBox(height: Space.l),
          Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$appName can', style: t.titleSmall),
            const SizedBox(height: Space.xs),
            // owner, 2026-11-19: solution-based, a plan from the first session, worked through for as long as it takes
            item(Icons.flag_outlined, 'Build a plan with you in your first session, using methods that research '
                'shows work.', scheme.primary),
            item(Icons.chat_bubble_outline, 'Work through that plan with you, session by session, for as long as '
                'you need.', scheme.primary),
            item(Icons.insights_outlined, 'Keep track of your tasks and your progress, and of what helps.',
                scheme.primary),
          ]))),
          const SizedBox(height: Space.m),
          Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$appName is not', style: t.titleSmall),
            const SizedBox(height: Space.xs),
            item(Icons.smart_toy_outlined, 'A person. It is an AI, and it can get things wrong.', scheme.onSurfaceVariant),
            item(Icons.medical_services_outlined, 'A licensed therapist or a doctor. It cannot diagnose or prescribe.',
                scheme.onSurfaceVariant),
            item(Icons.emergency_outlined, 'An emergency service. If you are in danger, call your local emergency '
                'number, or tap Support at the top.', scheme.error),
          ]))),
        ], buttons: [
          _next('I understand', key: const Key('onb_understand')),
        ]);
      case 3: // where you live
        final info = crisisByCountry[s.country];
        return (centred: false, content: [
          _title(t, 'Where do you live?'),
          const SizedBox(height: Space.s),
          Text('Solace uses it only to show the right support numbers first.', style: t.bodyLarge),
          const SizedBox(height: Space.l),
          DropdownButtonFormField<String>(key: const Key('onb_country'), initialValue: s.country, isExpanded: true,
              items: [for (final c in crisisByCountry.keys) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => s.country = v!)),
          if (info != null && info.lines.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            Text('If you ever need it', style: t.labelLarge),
            const SizedBox(height: Space.xs),
            Text('${info.lines.first.name}: ${info.lines.first.number}', style: t.titleMedium?.copyWith(
                color: scheme.primary)),
          ],
        ], buttons: [
          _next('Continue'),
        ]);
      case 4: // 18 or older
        if (_under18) {
          final youth = youthLines[s.country] ?? const <CrisisLine>[];
          return (centred: false, buttons: const <Widget>[], content: [
            _title(t, '$appName is made for adults'),
            const SizedBox(height: Space.s),
            Text('So it is not the right place for you yet. These people are there for you, free and in confidence. '
                'Talking to an adult you trust can help too.', style: t.bodyLarge),
            const SizedBox(height: Space.l),
            for (final l in youth) Card(margin: const EdgeInsets.only(bottom: Space.m), color: scheme.primaryContainer,
                child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText(l.number, style: t.titleLarge?.copyWith(color: scheme.primary,
                      fontWeight: FontWeight.w700)),
                  Text(l.name, style: t.titleSmall),
                  Text(l.detail, style: t.bodySmall),
                ]))),
            if (crisisByCountry[s.country] case final info?) CountryCrisisCard(info: info, highlight: youth.isEmpty),
            const SizedBox(height: Space.m),
            TextButton(key: const Key('onb_wrong'), onPressed: () => setState(() => _under18 = false),
                child: const Text('I tapped the wrong button')),
          ]);
        }
        return (centred: false, content: [
          _title(t, '$appName is for adults'),
          const SizedBox(height: Space.s),
          Text('Please confirm that you are 18 or older.', style: t.bodyLarge),
        ], buttons: [
          _next('I am 18 or older', key: const Key('onb_adult'), onPressed: () {
            s.ageConfirmed = true;
            _go(_step + 1);
          }),
          const SizedBox(height: Space.s),
          OutlinedButton(key: const Key('onb_under18'), onPressed: () => setState(() => _under18 = true),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('I am under 18')),
        ]);
      case 5: // how Solace looks and sounds
        return (centred: false, content: [
          _title(t, 'How $appName looks and sounds'),
          const SizedBox(height: Space.s),
          Text('A calm light, or an illustrative portrait that is always marked AI. You can change this later in '
              'Settings.', style: t.bodyLarge),
          const SizedBox(height: Space.l),
          const PresencePicker(),
        ], buttons: [
          _next('Continue'),
        ]);
      case _modelStep when _offerModel: // the model, voice and safety files, or not now
        return (centred: false, content: [
          _title(t, "Add $appName's model files"),
          const SizedBox(height: Space.s),
          Text('With these files, $appName answers, speaks and checks each message, here on this device. Until you '
              'add them, a simple stand-in answers.', style: t.bodyLarge),
          const SizedBox(height: Space.l),
          // each file, its state and what it does, at a glance (ui/model_files.dart)
          const Card(margin: EdgeInsets.zero, child: Padding(padding: EdgeInsets.all(Space.l),
              child: FilesStatus(details: false))),
          const SizedBox(height: Space.l),
          const ModelFilesPanel(prominent: true), // its progress shows under it while a copy runs
        ], buttons: [
          // a copy running or done: Continue (it carries on meanwhile); otherwise the step can be skipped
          ListenableBuilder(listenable: state.imports, builder: (context, _) =>
              state.imports.running || state.imports.result != null
                  ? _next('Continue')
                  : OutlinedButton(key: const Key('onb_model_skip'), onPressed: () => _go(_step + 1),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: const Text('Not now'))),
          const SizedBox(height: Space.s),
          Text('You can add them later, from Today or from Settings.', style: t.bodySmall, textAlign: TextAlign.center),
        ]);
      default: // the lock
        return (centred: true, content: [
          Center(child: CircleAvatar(radius: 36, backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.lock_outline, size: 32, color: scheme.onPrimaryContainer))),
          const SizedBox(height: Space.xl),
          Text('Keep it just for you', style: t.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.s),
          Text('Lock $appName with its own six-digit passcode, so only you can open it. Support stays reachable on '
              'the lock screen.', style: t.bodyLarge, textAlign: TextAlign.center),
        ], buttons: [
          _next('Turn on the lock', key: const Key('onb_lock'), onPressed: () async {
            if (await turnOnLock(context, state) && mounted) await _finish(); // cancelled: stay on this step
          }),
          const SizedBox(height: Space.s),
          TextButton(key: const Key('onb_finish'), onPressed: _finish, child: const Text('Not now')),
          Text('You can change this in Settings.', style: t.bodySmall, textAlign: TextAlign.center),
        ]);
    }
  }
}
