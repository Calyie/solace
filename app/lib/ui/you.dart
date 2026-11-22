// What the app remembers about you, all of it visible and in your control: your values and goals (built from your
// sessions; add, change or remove any), your story so far (editable), and every past session with its note.
import 'package:flutter/material.dart' hide Step;

import '../app_state.dart';
import '../core/home_link.dart' show staysOnFor;
import '../core/dates.dart';
import '../core/exports.dart' show longDate;
import '../core/formats.dart';
import '../core/plans.dart';
import 'chat.dart';
import 'crisis.dart' show readSavedWords;
import 'help_me_start.dart';
import 'home.dart' show openSettings;
import 'memory_search.dart';
import 'premium.dart';
import 'safety_plan.dart';
import 'vision_board.dart';

class YouTab extends StatelessWidget {
  const YouTab({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = state.data;
    final t = Theme.of(context).textTheme;
    final session = state.newSession();
    return ListView(padding: tabPadding, children: [
      TabTitle('You', subtitle: 'Everything Solace remembers about you. Change or delete any of it.',
          actions: [
        IconButton(tooltip: 'Search your sessions', icon: const Icon(Icons.search), onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MemorySearchScreen()))),
        // a phone has Settings in the top bar on every tab (ui/home.dart); a wider window keeps it here too
        if (windowSize(MediaQuery.sizeOf(context).width) != WindowSize.compact)
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () =>
              openSettings(context)),
      ]),
      // a phone: one column; a computer: what Solace keeps and what matters beside your story and past sessions;
      // a very large window: three columns (ui/premium.dart Panes)
      Panes(columns: [[
      const SafetyPlanCard(),
      const MemoryControls(),
      if (d.suggestions.isNotEmpty) ...[
        const SizedBox(height: 16),
        const SectionHeader('Things Solace noticed', top: 0),
        for (final s in d.suggestions.toList()) SuggestionCard(suggestion: s,
            // a save that fails inside decide is tried again by the app's own save, which shows its banner (F-17)
            onDecide: (approve, edited) => session.decide(s, approve: approve, edited: edited)
                .catchError((Object _) {}).then((_) => state.save())),
      ],
      ], [
      const SizedBox(height: 16),
      _ChipSection(title: 'What matters to you', items: [for (final v in d.plans.values) v.text],
          onWhy: (x) {
            final v = d.plans.values.firstWhere((v) => v.text == x);
            return whyLine(v.quote, v.added);
          },
          onAdd: (x) async {
            final navigator = Navigator.of(context);
            d.plans.values.add(Value(text: x, added: isoDate(DateTime.now())));
            final saving = state.trySave(); // not waited for first: a crisis in it opens support at once (9B-02)
            // read as notes are, crisis only (round 6 review F, F6-17)
            await readSavedWords(navigator, state, x, where: 'what matters to you');
            if (!await saving && context.mounted) sayNotSaved(context, changeNotSaved); // G7-02
          },
          onRemove: (x) async {
            d.plans.values.removeWhere((v) => v.text == x);
            // round 7 review, G7-02: a removal that was not saved says so (round 6 review, E-01)
            if (!await state.trySave() && context.mounted) sayNotSaved(context, removedNotSaved);
          }),
      const VisionBoardSection(),
      const SizedBox(height: 8),
      const _GoalsSection(),
      ], [
      const SizedBox(height: 8),
      Text('Your story so far', style: t.titleMedium),
      const SizedBox(height: 2),
      Text(d.settings.memoryPaused ? 'Memory is paused, so Solace is not adding to this for now.'
          : 'Solace writes this after each session, from what you said. Tap a part to change or clear it.',
          style: t.bodySmall),
      const SizedBox(height: 4),
      for (final h in storyHeadings) Card(child: ListTile(
        title: Text(h),
        // an empty part says what comes here and how (report P1 20), not a bare "Nothing yet"
        subtitle: Text((d.story.sections[h] ?? '').isEmpty ? 'Solace adds to this after your sessions. Tap to write it '
            'yourself.' : d.story.sections[h]!),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () => _editSection(context, h),
      )),
      const SizedBox(height: 16),
      const SectionHeader('Past sessions', top: 0),
      if (d.sessions.isEmpty) const EmptyNote(icon: Icons.forum_outlined,
          text: 'Each session you finish shows here with its note, so you can look back at it. Start one from Talk.'),
      for (final s in d.sessions.reversed) Card(child: ListTile(
        // the day in words, as on the rest of the app
        title: Text('${kindTitles[s.kind] ?? s.kind}, ${DateTime.tryParse(s.date) == null ? s.date
            : dayLabel(DateTime.parse(s.date))}'),
        subtitle: Text(parseNote(s.note).homework.isEmpty ? '' : 'Next step: ${parseNote(s.note).homework}'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PastSessionView(record: s))),
      )),
      ]]),
    ]);
  }

  Future<void> _editSection(BuildContext context, String heading) async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final was = state.data.story.sections[heading] ?? '';
    final c = TextEditingController(text: was);
    final saved = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text(heading),
      content: TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.long, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, controller: c, maxLines: 6),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
      ],
    ));
    if (saved == true) {
      final now = c.text.trim();
      state.data.story.sections[heading] = now;
      // round 7 review, G7-02: a change (or a part cleared) that was not saved says so (round 6 review, E-01)
      final saving = state.trySave(); // not waited for first: a crisis in it opens support at once (9B-02)
      // only what was changed is read; a crisis in it opens support (round 4 review, B-18)
      await readSavedWords(navigator, state, now, before: was, where: 'your story');
      if (!await saving && context.mounted) sayNotSaved(context, changeNotSaved);
    }
  }
}

class _ChipSection extends StatelessWidget {
  const _ChipSection({required this.title, required this.items, required this.onAdd, required this.onRemove,
      required this.onWhy});
  final String title;
  final String Function(String) onWhy;
  final List<String> items;
  final Future<void> Function(String) onAdd;
  final Future<void> Function(String) onRemove;
  @override
  Widget build(BuildContext context) {
    final add = TextEditingController();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in items) InputChip(label: Text(v), onDeleted: () => onRemove(v), deleteButtonTooltipMessage: 'Forget',
            tooltip: 'Why does Solace know this?',
            onPressed: () => showWhy(context, v, onWhy(v), () => onRemove(v))),
        if (items.isEmpty) Text('None yet. Add your own, or Solace adds them from your sessions.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      Row(children: [
        Expanded(child: TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.short, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, controller: add, decoration: const InputDecoration(hintText: 'Add one'))),
        IconButton(tooltip: 'Add', icon: const Icon(Icons.add), onPressed: () {
          final v = add.text.trim();
          if (v.isNotEmpty && !items.contains(v)) onAdd(v);
        }),
      ]),
    ])));
  }
}

/// The goal planner (PLAN 13, TASKLIST B3): each goal with its next step, how long since it moved, one tap for
/// progress, and Help me start on the next step. Goals come from the sessions; the person can add or remove any.
class _GoalsSection extends StatefulWidget {
  const _GoalsSection();
  @override
  State<_GoalsSection> createState() => _GoalsSectionState();
}

class _GoalsSectionState extends State<_GoalsSection> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final goals = state.data.plans.goals;
    final now = state.clock();
    final t = Theme.of(context).textTheme;
    // round 7 review, G7-02: a change that was not saved says so (round 6 review, E-01); a removal says what it means
    Future<void> save([String notSaved = changeNotSaved]) async {
      if (!await state.trySave() && mounted) sayNotSaved(this.context, notSaved);
      if (mounted) setState(() {});
    }

    String since(Goal g) {
      if (g.lastProgress.isEmpty) return 'Not started yet';
      final days = now.difference(DateTime.tryParse(g.lastProgress) ?? now).inDays;
      return days == 0 ? 'Moved forward today' : days >= 14 ? 'No step in $days days. Worth raising in your next session.'
          : 'Moved forward $days day${days == 1 ? '' : 's'} ago';
    }

    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your goals', style: t.titleMedium),
      if (goals.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(
          'None yet. Add one below, or Solace adds them from your sessions.',
          style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      for (final g in goals.toList()) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: InkWell(onTap: () => showWhy(context, g.text, whyLine(g.quote, g.added), () {
            goals.remove(g);
            save(removedNotSaved);
          }), child: Text(g.text, style: t.titleSmall))),
          IconButton(tooltip: 'Remove', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18),
              onPressed: () { goals.remove(g); save(removedNotSaved); }),
        ]),
        if (g.nextStep.isNotEmpty) Text('Next step: ${g.nextStep}'),
        Text(since(g), style: t.bodySmall),
        Wrap(spacing: 4, children: [
          TextButton(onPressed: () { g.lastProgress = isoDate(now); save(); }, child: const Text('I made progress')),
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
              HelpMeStartScreen(task: g.nextStep.isNotEmpty ? g.nextStep : g.text))), child: const Text('Help me start')),
        ]),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.short, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, controller: _add, decoration: const InputDecoration(hintText: 'Add a goal'))),
        IconButton(tooltip: 'Add the goal', icon: const Icon(Icons.add), onPressed: () async {
          final x = _add.text.trim();
          if (x.isEmpty) return;
          final navigator = Navigator.of(context);
          goals.add(Goal(text: x, added: isoDate(now), lastProgress: isoDate(now)));
          _add.clear();
          final saving = save(); // not waited for first: a crisis in it opens support at once (9B-02)
          // read as notes are, crisis only (round 6 review F, F6-17)
          await readSavedWords(navigator, state, x, where: 'your goals');
          await saving;
        }),
      ]),
    ])));
  }
}

/// Said when removing something Solace remembers could not be saved (round 7 review, G7-02): it is gone here, but
/// the device still holds it until a save works.
const removedNotSaved = 'Removed here, but this could not be saved yet, so it could come back when Solace next opens. '
    'The device may be full. Free some space, then tap Try again at the top.';

/// Said when a change on the You tab could not be saved (round 7 review, G7-02).
const changeNotSaved = 'Changed here, but this could not be saved yet, so it could be as it was when Solace next '
    'opens. The device may be full. Free some space, then tap Try again at the top.';

/// Said when "Erase what Solace remembers" could not be saved (round 7 review, G7-02).
const eraseNotSaved = 'Erased here, but this could not be saved yet, so what Solace remembers could come back when '
    'Solace next opens. The device may be full. Free some space, then tap Try again at the top.';

/// Where something Solace remembers came from (research report P1 17: show where each memory came from).
String whyLine(String quote, String added) {
  final when = added.isEmpty ? '' : longDate(added);
  if (quote.trim().isNotEmpty) {
    return 'From your session${when.isEmpty ? '' : ' on $when'}. You said: \u201c${quote.trim()}\u201d';
  }
  if (when.isNotEmpty) return 'Added on $when, by you or from a session.';
  return 'Kept from before Solace noted where things came from.';
}

/// "Why does Solace know this?": where it came from, and a way to forget it.
Future<void> showWhy(BuildContext context, String item, String why, VoidCallback forget) => showModalBottomSheet<void>(
    context: context, showDragHandle: true, isScrollControlled: true,
    builder: (context) {
      final t = Theme.of(context).textTheme;
      return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Why does Solace know this?', style: t.titleLarge),
        const SizedBox(height: Space.m),
        Text(item, style: t.titleMedium),
        const SizedBox(height: Space.xs),
        Text(why, key: const Key('why_text'), style: t.bodyMedium),
        const SizedBox(height: Space.m),
        Text('Solace uses this in your sessions so you do not have to repeat yourself. It stays on ${staysOnFor(AppScope.of(context).data.settings.homeServer)}.',
            style: t.bodySmall),
        const SizedBox(height: Space.l),
        OutlinedButton.icon(key: const Key('why_forget'), onPressed: () {
          forget();
          Navigator.pop(context);
        }, icon: const Icon(Icons.delete_outline), label: const Text('Forget this')),
      ])));
    });

/// What Solace remembers, and the person's controls over it (research report P1 17, after ChatGPT's and Claude's
/// memory controls): pause memory, erase what is remembered, and the off-the-record session on the Talk tab.
class MemoryControls extends StatelessWidget {
  const MemoryControls({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.data.settings;
    return Card(margin: const EdgeInsets.only(bottom: Space.m), child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(key: const Key('memory_pause'), contentPadding: EdgeInsets.zero, value: s.memoryPaused,
            title: const Text('Pause memory'),
            subtitle: const Text('Solace starts each session fresh and adds nothing new here. Your sessions are '
                'still kept below, and safety checks always run.'),
            onChanged: (on) async {
              feelChoice();
              final was = s.memoryPaused; // round 6 review, E-01: put back (and said) when it could not be saved
              if (!await state.saveSetting(() => s.memoryPaused = on, () => s.memoryPaused = was) &&
                  context.mounted) {
                sayNotSaved(context);
              }
            }),
        Wrap(spacing: Space.s, children: [
          TextButton.icon(key: const Key('memory_erase'), icon: const Icon(Icons.auto_delete_outlined),
              label: const Text('Erase what Solace remembers'), onPressed: () => _erase(context, state)),
        ]),
      ]),
    ));
  }

  Future<void> _erase(BuildContext context, AppState state) async {
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Erase what Solace remembers?'),
      content: const Text('This erases your story so far, the last session\'s note and next step, and the things '
          'Solace noticed. Your sessions, moods, plans, goals and safety plan stay. To delete everything, go to '
          'Settings > Your data.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
        FilledButton(key: const Key('memory_erase_confirm'), onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase')),
      ],
    ));
    if (sure != true) return;
    state.data.eraseMemory();
    // round 7 review, G7-02: the done touch only once it is saved, and a save that failed is said on this screen (it
    // played the touch first and said nothing, while the device still held what was erased; round 6 review, E-01)
    if (await state.trySave()) {
      feelDone();
    } else if (context.mounted) {
      sayNotSaved(context, eraseNotSaved);
    }
  }
}
