// The support screen: crisis numbers stored on the device, the person's country first. Opened automatically when
// the safety check flags a crisis, and at any time from the heart icon. Numbers are shown as text to dial; the app
// never places calls or sends anything itself.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/crisis.dart';
import '../core/dates.dart';
import '../core/safety.dart';
import '../core/session.dart' show maxPasteChecked, pastesInIsolate, runWorkApart;
import 'safety_plan.dart';
import 'premium.dart';

/// [plan]: whether the person's safety plan can be opened from the sheet (not from the lock screen or before the
/// first-run steps are done, where it would show private words to whoever holds the device).
Future<void> showCrisisSheet(BuildContext context, {bool flagged = false, bool plan = true}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: calmSheet(context), // rises on the gentle spring; at once with less motion
      builder: (_) => CrisisSheet(flagged: flagged, plan: plan),
    );

/// Words the person writes outside a session, read by the safety checks when they are saved (round 4 review, B-18: a
/// feeling's note, a debrief, a parked thought or a story section reached no check). Only the phrase rules read them,
/// which is cheap (never the classifier), and only a crisis is acted on, as a session's crisis is: it is recorded,
/// starts the 7-day watch (AppState.noteCrisis) and opens the support screen over [navigator]. A worry or anything less
/// does nothing, so an ordinary note never raises an alarm (the owner: precision first).
///
/// For a text that was changed ([before]: as it was), only the change is read, with a little of the words around it,
/// and nothing is done when the same words read before the change were a crisis already, so words long there (a story
/// section can quote a hard week) never alarm again. Bounded: at most [maxPasteChecked] characters, read in a
/// background isolate past [pastesInIsolate]. Never throws; a fault of the rules is recorded, never silent.
Future<void> readSavedWords(NavigatorState navigator, AppState state, String text,
    {required String where, String before = ''}) async {
  var now = text, was = '';
  if (before.isNotEmpty) {
    final (start, end) = editSpan(before, text);
    if (start + end >= text.length) return; // only words taken out
    const around = 120;
    final from = math.max(0, start - around);
    now = text.substring(from, math.min(text.length, text.length - end + around));
    was = before.substring(from, math.min(before.length, before.length - end + around));
  }
  if (now.trim().isEmpty) return;
  if (now.length > maxPasteChecked) now = now.substring(now.length - maxPasteChecked);
  if (was.length > maxPasteChecked) was = was.substring(was.length - maxPasteChecked);
  final SafetyResult result;
  final SafetyLevel old;
  try {
    final texts = (now, was);
    (result, old) = now.length + was.length > pastesInIsolate
        ? await runWorkApart(() => _readWords(texts)) : _readWords(texts);
  } catch (e) {
    state.data.safetyEvents.add({'date': isoDate(state.clock()), 'level': 'error', 'reason': 'rules ${e.runtimeType}'});
    await state.save();
    return;
  }
  if (result.level != SafetyLevel.crisis || old == SafetyLevel.crisis) return;
  state.noteCrisis('${result.reason} (written in $where)');
  unawaited(state.save()); // round 9 review B, 9B-02: support never waits for the store to be written
  if (navigator.mounted) await showCrisisSheet(navigator.context, flagged: true);
}

/// The phrase rules on saved words (now, as they were): the level now, and the level before when now is a crisis.
(SafetyResult, SafetyLevel) _readWords((String, String) texts) {
  const rules = SafetyCheck();
  final (now, was) = texts;
  final result = rules.check(now, sessionKind: 'daily_checkin');
  final old = result.level != SafetyLevel.crisis || was.trim().isEmpty ? SafetyLevel.none
      : rules.check(was, sessionKind: 'daily_checkin').level;
  return (result, old);
}

class CrisisSheet extends StatelessWidget {
  const CrisisSheet({super.key, this.flagged = false, this.plan = true});
  final bool flagged, plan;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final saved = state.data.settings.country;
    final home = crisisByCountry.containsKey(saved) ? saved : crisisByCountry.keys.first;
    final order = [home, ...crisisByCountry.keys.where((c) => c != home)];
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(flagged ? 'You matter, and support is here' : 'Support, any time', style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(
            flagged
                ? 'What you said sounds serious. If you might act on thoughts of harming yourself or someone else, or '
                    'you are in danger, please call one of these numbers now. You can keep talking to me as well.'
                : 'If you are in danger or might harm yourself or someone else, call one of these numbers.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 16),
          // the person's own plan, one tap away (report 2026-11-14, P0 4)
          if (plan && !state.data.safetyPlan.isEmpty) ...[
            FilledButton.icon(key: const Key('crisis_plan'), onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SafetyPlanScreen())),
                icon: const Icon(Icons.health_and_safety_outlined), label: const Text('Open my safety plan')),
            const SizedBox(height: 16),
          ],
          for (final c in order) CountryCrisisCard(info: crisisByCountry[c]!, highlight: c == home),
          const SizedBox(height: 8),
          Text('Numbers checked on $crisisChecked.', style: t.bodySmall),
          const SizedBox(height: 16),
          // never a dead end: the person can go back to the conversation (report 2026-11-14, P0 3)
          FilledButton.tonal(onPressed: () => Navigator.pop(context), child: const Text('Stay and keep talking')),
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('I am safe right now')),
          if (plan && state.data.safetyPlan.isEmpty) TextButton(key: const Key('crisis_make_plan'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyPlanScreen())),
              child: const Text('Make a safety plan for harder moments')),
        ],
      ),
    );
  }
}

class CountryCrisisCard extends StatelessWidget {
  const CountryCrisisCard({super.key, required this.info, required this.highlight, this.onDark = false});
  final CountryCrisis info;
  final bool highlight;
  final bool onDark; // on the call's dark portrait (CrisisCard): light words on a faint light card

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ink = onDark ? Colors.white : null, soft = onDark ? Colors.white70 : null;
    Widget line(CrisisLine l, {bool emergency = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(l.number, style: t.titleLarge?.copyWith(
                color: onDark ? (emergency ? const Color(0xFFFFB4A9) : Colors.white)
                    : emergency ? scheme.error : scheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: t.titleSmall?.copyWith(color: ink)),
              if (l.detail.isNotEmpty) Text(l.detail, style: t.bodySmall?.copyWith(color: soft)),
            ])),
          ]),
        );
    return Card(
      color: onDark ? const Color(0x26FFFFFF) : highlight ? scheme.primaryContainer : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(info.country, style: t.titleMedium?.copyWith(color: ink)),
          for (final l in info.lines) line(l),
          Divider(color: onDark ? Colors.white24 : null),
          for (final l in info.emergency) line(l, emergency: true),
        ]),
      ),
    );
  }
}

/// The support card's words (owner, 2026-11-15, OWNER-C1).
const crisisCardTitle = 'You are not alone in this';
const crisisCardLine = 'If you might act on these thoughts, or you are in danger, please call one of these numbers now. '
    'You can keep talking with Solace too.';

/// Owner, 2026-11-15, OWNER-C1 ("the therapist model talking to the user and trying to talk them out of it would do
/// more than popping up a couple hotline numbers"): when a session finds a crisis, support is a calm card inside the
/// conversation, right after the words that raised it, and Solace's reply follows it; nothing covers the chat. It
/// carries a warm line, the person's country's numbers exactly as the support screen shows them (the same data and
/// date), their safety plan (or making one), and More support, which opens the full support screen. The Support button
/// is unchanged, and the full screen still opens on its own where the conversation cannot be seen (ui/app_lock.dart
/// supportWhereUnseen).
class CrisisCard extends StatelessWidget {
  const CrisisCard({super.key = const Key('crisis_card'), this.onDark = false});
  final bool onDark; // on the call's dark portrait

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final saved = state.data.settings.country;
    final home = crisisByCountry.containsKey(saved) ? saved : crisisByCountry.keys.first;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ink = onDark ? Colors.white : scheme.onSurface, soft = onDark ? Colors.white70 : scheme.onSurfaceVariant;
    final hasPlan = !state.data.safetyPlan.isEmpty;
    void openPlan() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyPlanScreen()));
    final light = onDark ? FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0B1B33))
        : null;
    return Semantics(container: true, liveRegion: true, child: Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: onDark ? const Color(0xB3000000) : scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: onDark ? Colors.white24 : scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.favorite_outline, size: 20, color: onDark ? const Color(0xFFFFB4A9) : scheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(crisisCardTitle, style: t.titleMedium?.copyWith(color: ink))),
        ]),
        const SizedBox(height: 6),
        Text(crisisCardLine, style: t.bodyMedium?.copyWith(color: soft)),
        const SizedBox(height: 12),
        CountryCrisisCard(info: crisisByCountry[home]!, highlight: true, onDark: onDark),
        Text('Numbers checked on $crisisChecked.', style: t.bodySmall?.copyWith(color: soft)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.tonalIcon(key: const Key('crisis_card_plan'), style: light, onPressed: openPlan,
              icon: const Icon(Icons.health_and_safety_outlined, size: 18),
              label: Text(hasPlan ? 'Open my safety plan' : 'Make a safety plan')),
          TextButton(key: const Key('crisis_card_more'),
              style: onDark ? TextButton.styleFrom(foregroundColor: Colors.white) : null,
              onPressed: () => showCrisisSheet(context, flagged: true), child: const Text('More support')),
        ]),
      ]),
    ));
  }
}


/// Said on a call after a question it shows (round 4 review, B-09): the answer is a tap, so the microphone rests.
const tapToAnswerLine = 'You can tap your answer on the screen.';

/// The quiet support line when the phrase rules or the classifier are worried, but not enough for the support screen
/// (SafetyLevel.concern): in the chat, and on a call, where it is spoken once too (round 4 review, B-13).
const concernLine = 'If things feel like too much, support is here any time.';

/// [concernLine] with a Support button, in the conversation (the chat's list, the call's words).
class ConcernLine extends StatelessWidget {
  const ConcernLine({super.key, this.onDark = false});
  final bool onDark; // on the call's dark portrait
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
      decoration: BoxDecoration(color: onDark ? const Color(0x99000000) : scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(concernLine, style: TextStyle(color: onDark ? Colors.white : scheme.onSecondaryContainer)),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => showCrisisSheet(context),
            style: onDark ? TextButton.styleFrom(foregroundColor: Colors.white) : null, child: const Text('Support'))),
      ]),
    );
  }
}

/// The safety question (core/session.dart send), shown when the trained classifier alone is worried: a direct question,
/// as a therapist would ask it. Yes or Not sure opens the support screen; No lets the session go on.

const openingAfterCrisisLine = 'Last time things felt very heavy. How are you doing today?';
const openingAfterQuestionLine = "Last time I wanted to check how you were, and we didn't get to talk about it. How are "
    'you doing today?';

/// The gentle check at the start of a session after a recent crisis (core/session.dart answerOpeningCheck).
class OpeningCheck extends StatelessWidget {
  const OpeningCheck({super.key, required this.onAnswer, this.afterQuestion = false});
  final void Function(String answer) onAnswer;
  /// The watch came from a safety question that was not answered, not from a crisis (core/session.dart
  /// openingAfterQuestion; cycle 2 review, N11): it is worded as that.
  final bool afterQuestion;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('opening_check'),
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(afterQuestion ? openingAfterQuestionLine : openingAfterCrisisLine),
            Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
              TextButton(onPressed: () => onAnswer('struggling'), child: const Text('Still struggling')),
              TextButton(onPressed: () => onAnswer('better'), child: const Text('A bit better')),
              TextButton(onPressed: () => onAnswer('okay'), child: const Text("I'm okay")),
            ]),
          ]),
        ),
      );
}

/// A small, steady label beside Solace's name: what is speaking is an AI (report 2026-11-14, P0 1).
class AiTag extends StatelessWidget {
  const AiTag({super.key, this.onDark = false});
  final bool onDark;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(label: 'AI', excludeSemantics: true, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: onDark ? Colors.white24 : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('AI', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700,
          letterSpacing: 0.6, color: onDark ? Colors.white : scheme.onPrimaryContainer)),
    ));
  }
}

/// A line the app adds to the conversation itself (not Solace's words): the AI notice.
class AppNotice extends StatelessWidget {
  const AppNotice(this.text, {super.key, this.onDark = false, this.action, this.onAction, this.actionKey});
  final String text;
  final bool onDark; // on the call's dark portrait

  /// A button under the words (for example Try again), shown when both are given.
  final String? action;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = onDark ? Colors.white70 : scheme.onSurfaceVariant;
    // what Solace is and what checks each message: a step above the smallest size, so the notice reads at a glance
    // and in sunlight (it was 12 pixels of grey); unchanged on the call's dark portrait
    final small = Theme.of(context).textTheme.bodySmall;
    // its own node for screen readers, read as one line (and measured on its own words by the contrast check)
    final words = Semantics(container: true, child: Text(text,
        style: onDark ? small?.copyWith(color: ink) : small?.copyWith(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: ink),
        const SizedBox(width: 8),
        Expanded(child: action == null || onAction == null ? words
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                words,
                TextButton(key: actionKey, onPressed: onAction,
                    style: onDark ? TextButton.styleFrom(foregroundColor: Colors.white) : null, child: Text(action!)),
              ])),
      ]),
    );
  }
}

/// The support button of the approved design: a heart in a white circle, top right on every tab.
class SupportButton extends StatelessWidget {
  const SupportButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(tooltip: 'Support', onPressed: () => showCrisisSheet(context),
        style: IconButton.styleFrom(backgroundColor: scheme.surface, side: BorderSide(color: scheme.outlineVariant)),
        icon: Icon(Icons.favorite_outline, color: scheme.error, size: 20));
  }
}
