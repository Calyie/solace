// Today's plan, built from the sessions (PLAN 13 Day planner and Habits, TASKLIST B3; the approved design's "Your plan
// for today"): every step and habit is one tap to mark, a step can move to tomorrow without blame or get Help me
// start; never miss twice after a missed habit; and what the app noticed, so nothing is only a list.
import 'package:flutter/material.dart' hide Step;

import '../app_state.dart';
import '../core/plans.dart';
import '../core/today_plan.dart';
import 'crisis.dart' show readSavedWords;
import 'help_me_start.dart';
import 'premium.dart';

class PlanTodayCard extends StatefulWidget {
  const PlanTodayCard({super.key});
  @override
  State<PlanTodayCard> createState() => _PlanTodayCardState();
}

class _PlanTodayCardState extends State<PlanTodayCard> {
  bool _keepFull = false; // the person chose the full habit over the tiny version today

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.data.plans;
    final now = state.clock();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final steps = stepsForToday(p, now), habits = habitsDue(p, now), rescue = _keepFull ? null : neverMissTwice(p, now);
    final noticed = p.noticed(now).take(3).toList();
    Future<void> save() async {
      await state.save();
      if (mounted) setState(() {});
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rescue != null) ...[
        Card(color: scheme.primaryContainer, child: Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 10), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Never miss twice', style: t.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
          const SizedBox(height: 6),
          Text('${rescue.text} slipped yesterday. Today the tiny version counts in full: ${rescue.tiny}.'),
          Wrap(spacing: 4, children: [
            TextButton(key: const Key('rescue_tiny'), onPressed: () {
              markHabit(rescue, now, kept: true);
              save();
            }, child: const Text('I did the tiny version')),
            TextButton(onPressed: () => setState(() => _keepFull = true), child: const Text('Keep the full one')),
          ]),
        ]))),
        const SizedBox(height: 12),
      ],
      Row(children: [
        Expanded(child: Text('Your plan for today', style: t.titleMedium)),
        Text('From your sessions', style: t.bodySmall),
      ]),
      const SizedBox(height: 8),
      Card(child: steps.isEmpty && habits.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nothing planned for today yet. Steps and habits are added from your sessions.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  onPressed: () => _helpMeStart(context, ''), label: const Text('Help me start something')),
            ]))
          : Column(children: [
              for (final s in steps)
                ListTile(
                  key: ValueKey('step_${s.text}'),
                  leading: IconButton(tooltip: 'Done', icon: const Icon(Icons.radio_button_unchecked), onPressed: () {
                    markStep(s, 'done');
                    save();
                  }),
                  title: Text(s.text),
                  subtitle: Text([
                    if (s.time.isNotEmpty) s.time,
                    if (s.ifthen.isNotEmpty) s.ifthen,
                    if (s.day.isNotEmpty && s.day.compareTo(_iso(now)) < 0) 'still open from before',
                  ].join(' · ')),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) {
                      if (v == 'start') return _helpMeStart(context, s.text);
                      v == 'later' ? moveStep(s, now) : markStep(s, 'dropped');
                      save();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'start', child: Text('Help me start')),
                      PopupMenuItem(value: 'later', child: Text('Not yet: tomorrow')),
                      PopupMenuItem(value: 'drop', child: Text('Drop it')),
                    ],
                  ),
                ),
              for (final h in habits)
                ListTile(
                  key: ValueKey('habit_${h.text}'),
                  leading: IconButton(tooltip: 'Kept today', icon: const Icon(Icons.radio_button_unchecked), onPressed: () {
                    markHabit(h, now, kept: true);
                    save();
                  }),
                  title: Text(h.text),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (h.tiny.isNotEmpty) Text('Tiny version: ${h.tiny}'),
                    const SizedBox(height: 4),
                    _HabitDays(days: habitDays(h, now)),
                  ]),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (_) {
                      markHabit(h, now, kept: false);
                      save();
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'missed', child: Text('Not today'))],
                  ),
                ),
            ])),
      if (noticed.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('I noticed', style: t.titleSmall),
          const SizedBox(height: 4),
          for (final n in noticed) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_sentence(n))),
          const SizedBox(height: 6),
          Text('We can talk about it in your next session.', style: t.bodySmall),
        ]))),
      ],
    ]);
  }

  void _helpMeStart(BuildContext context, String task) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => HelpMeStartScreen(task: task)));
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _sentence(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}.';

/// The last seven days as dots: filled for kept, crossed for missed, hollow for nothing marked (a gap, not a break).
class _HabitDays extends StatelessWidget {
  const _HabitDays({required this.days});
  final List<bool?> days;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      for (final d in days)
        Padding(padding: const EdgeInsets.only(right: 5), child: Icon(
            d == true ? Icons.circle : d == false ? Icons.close : Icons.circle_outlined, size: 12,
            color: d == true ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.6))),
    ]);
  }
}

/// Park a thought (distractibility delay, Safren et al.): one line, kept for later, so the task in hand can go on.
Future<void> parkThought(BuildContext context) async {
  final state = AppScope.of(context);
  final navigator = Navigator.of(context);
  final text = TextEditingController();
  final saved = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: const Text('Park a thought'),
    content: TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.short, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('park_text'), controller: text, autofocus: true, maxLines: 3,
        decoration: const InputDecoration(hintText: 'It will wait here until later.')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
      FilledButton(key: const Key('park_save'), onPressed: () => Navigator.pop(c, true), child: const Text('Park it')),
    ],
  ));
  final words = text.text.trim();
  if (saved == true && words.isNotEmpty) {
    state.data.parked.add({'date': _iso(state.clock()), 'text': words});
    final saving = state.save(); // not waited for first: a crisis in the words opens support at once (9B-02)
    await readSavedWords(navigator, state, words, where: 'a parked thought'); // a crisis opens support (B-18)
    await saving;
  }
  text.dispose();
}

/// The thoughts parked earlier: each becomes a step for tomorrow, is done, or is let go.
class ParkedThoughtsCard extends StatelessWidget {
  const ParkedThoughtsCard({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final parked = state.data.parked;
    if (parked.isEmpty) return const SizedBox.shrink();
    final now = state.clock();
    Future<void> drop(Map<String, dynamic> p) async {
      parked.remove(p);
      await state.save();
    }

    return Padding(padding: const EdgeInsets.only(top: 12), child: Card(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text('Parked thoughts', style: Theme.of(context).textTheme.titleSmall),
      for (final p in parked.toList())
        Row(children: [
          Expanded(child: Text('${p['text']}')),
          PopupMenuButton<String>(tooltip: 'What to do with it', onSelected: (v) async {
            if (v == 'plan') {
              state.data.plans.steps.add(Step(text: '${p['text']}', day: _iso(now.add(const Duration(days: 1))),
                  added: _iso(now)));
            }
            await drop(p);
          }, itemBuilder: (_) => const [
            PopupMenuItem(value: 'plan', child: Text('Plan it for tomorrow')),
            PopupMenuItem(value: 'done', child: Text('Done')),
            PopupMenuItem(value: 'go', child: Text('Let it go')),
          ]),
        ]),
    ]))));
  }
}

/// The evening shutdown (PLAN 13): about two minutes to choose tomorrow's first step, offered once each evening.
class EveningShutdownCard extends StatefulWidget {
  const EveningShutdownCard({super.key});
  @override
  State<EveningShutdownCard> createState() => _EveningShutdownCardState();
}

class _EveningShutdownCardState extends State<EveningShutdownCard> {
  Step? _pick;
  final _other = TextEditingController();
  String _time = '09:00';
  String? _done;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final now = state.clock();
    final t = Theme.of(context).textTheme;
    if (_done == null && (now.hour < 17 || state.data.lastShutdown == _iso(now))) return const SizedBox.shrink();
    if (_done != null) {
      return Padding(padding: const EdgeInsets.only(top: 12), child: Card(child: Padding(
          padding: const EdgeInsets.all(16), child: Text(_done!, key: const Key('shutdown_done')))));
    }
    final open = stepsForToday(state.data.plans, now);
    Future<void> save() async {
      final tomorrow = _iso(now.add(const Duration(days: 1)));
      final step = _pick ?? Step(text: _other.text.trim(), added: _iso(now));
      if (step.text.isEmpty) return;
      if (_pick == null) state.data.plans.steps.add(step);
      step
        ..day = tomorrow
        ..time = _time == 'none' ? '' : _time;
      state.data.lastShutdown = _iso(now);
      await state.save();
      if (mounted) {
        setState(() => _done = 'Tomorrow starts with: ${step.text}${step.time.isEmpty ? '' : ' at ${step.time}'}. '
            'The rest can wait until then.');
      }
    }

    return Padding(padding: const EdgeInsets.only(top: 12), child: Card(child: Padding(
        padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Close the day', style: t.titleMedium),
      const SizedBox(height: 4),
      const Text('Choose the first thing for tomorrow, so the day starts on its own.'),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in open.take(4))
          ChoiceChip(label: Text(s.text), selected: _pick == s, onSelected: (_) => setState(() => _pick = s)),
      ]),
      const SizedBox(height: 8),
      TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.short, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('shutdown_other'), controller: _other, onChanged: (_) => setState(() => _pick = null),
          decoration: const InputDecoration(hintText: 'Or something else')),
      const SizedBox(height: 10),
      Wrap(spacing: 6, children: [
        for (final (label, v) in const [('08:30', '08:30'), ('09:00', '09:00'), ('10:00', '10:00'), ('Any time', 'none')])
          ChoiceChip(label: Text(label), selected: _time == v, onSelected: (_) => setState(() => _time = v)),
      ]),
      const SizedBox(height: 10),
      FilledButton(key: const Key('shutdown_save'),
          onPressed: _pick != null || _other.text.trim().isNotEmpty ? save : null, child: const Text('Set for tomorrow')),
    ]))));
  }
}
