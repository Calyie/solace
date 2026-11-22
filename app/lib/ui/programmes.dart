// Practice programmes (docs/PRACTICES_DESIGN.md): choosing one, the morning practice card, the one-minute evening
// debrief that closes the loop, and the evidence of change each programme builds up.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/formats.dart';
import '../core/store.dart';
import 'crisis.dart' show readSavedWords;
import 'home.dart';
import 'premium.dart';

class ProgrammeInfo {
  const ProgrammeInfo(this.title, this.promise, this.icon);
  final String title;
  final String promise;
  final IconData icon;
}

const programmeInfo = <String, ProgrammeInfo>{
  'morning focus and purpose': ProgrammeInfo('Morning focus and purpose',
      'Each morning, find what matters most today and plan the first step. Evening: did it happen?', Icons.wb_sunny_outlined),
  'courage ladder': ProgrammeInfo('Courage ladder',
      'Face fears one step at a time and learn what really happens, compared with what you feared.', Icons.stairs_outlined),
  'letting thoughts pass': ProgrammeInfo('Letting thoughts pass',
      'Unhook from worries and from urges to check or ask for reassurance.', Icons.cloud_outlined),
  'activation': ProgrammeInfo('Activation',
      'Lift low mood by doing: one pleasure, one achievement, one thing that matters, each day.', Icons.directions_walk),
  'being enough': ProgrammeInfo('Being enough',
      'Collect daily evidence for a kinder belief about yourself, and act on it.', Icons.favorite_border),
  'joy and positivity': ProgrammeInfo('Joy and positivity',
      'Notice, savour and create good moments, and see your part in them.', Icons.local_florist_outlined),
  'letting go': ProgrammeInfo('Letting go',
      'Step out of loops about the past and turn towards what you can do now.', Icons.air),
  'calm and sleep': ProgrammeInfo('Calm and sleep', 'Wind down, offload tomorrow\'s worries, and sleep better.',
      Icons.bedtime_outlined),
};

/// Open items: today's or yesterday's commitments, predictions, activities and urges that have no outcome yet.
List<(String, LogEntry)> openItems(AppData d, DateTime now) {
  if (d.programmes.isEmpty) return [];
  final log = d.programmes.first.log;
  final recent = {isoDate(now), isoDate(now.subtract(const Duration(days: 1)))};
  final answered = {for (final (_, e) in log) if (e.type == 'outcome') e.details['about'] ?? ''};
  return [
    for (final (date, e) in log)
      if (recent.contains(date) && {'commitment', 'prediction', 'activity', 'urge'}.contains(e.type) &&
          !answered.contains(e.text)) (date, e),
  ];
}

class ProgrammesSection extends StatelessWidget {
  const ProgrammesSection({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final active = state.data.programmes.map((p) => p.name).toSet();
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Programmes', style: t.titleMedium),
      const Text('Five to ten minutes each morning with Solace, one minute in the evening. The change comes from '
          'doing it over weeks.'),
      const SizedBox(height: 8),
      for (final e in programmeInfo.entries) Card(child: ListTile(
        leading: CircleAvatar(radius: 20, backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(e.value.icon, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer)),
        title: Text(e.value.title),
        subtitle: Text(e.value.promise),
        isThreeLine: true,
        trailing: active.contains(e.key)
            ? Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(99)),
                child: Text('Day ${state.data.programmes.firstWhere((p) => p.name == e.key).dayOn(state.clock())}',
                    style: t.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimary)))
            : null,
        onTap: () async {
          if (active.contains(e.key)) return;
          state.data.programmes
            ..clear() // one programme at a time keeps it focused; the earlier one's log stays in past sessions
            ..add(Programme(e.key, isoDate(state.clock())));
          await state.save();
        },
      )),
    ]);
  }
}

class MorningCard extends StatelessWidget {
  const MorningCard({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.data.programmes.isEmpty) return const SizedBox.shrink();
    final p = state.data.programmes.first;
    final info = programmeInfo[p.name]!;
    final day = p.dayOn(state.clock());
    final doneToday = state.data.sessions.any((s) => s.date == isoDate(state.clock()) && s.kind == 'practice');
    return Card(child: ListTile(
      leading: Icon(info.icon),
      title: Text(doneToday ? '${info.title}: done today' : 'This morning: ${info.title}'),
      subtitle: Text('Day $day. ${doneToday ? 'Well done.' : 'Five to ten minutes, with Solace.'}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openSession(context, 'practice', practiceName: '${p.name}, day $day'),
    ));
  }
}

class EveningDebrief extends StatefulWidget {
  const EveningDebrief({super.key});
  @override
  State<EveningDebrief> createState() => _EveningDebriefState();
}

class _EveningDebriefState extends State<EveningDebrief> {
  final _what = TextEditingController();
  String? _result;
  double _enjoyment = 5;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = openItems(state.data, state.clock());
    if (items.isEmpty) return const SizedBox.shrink();
    final (_, item) = items.first;
    final t = Theme.of(context).textTheme;
    final question = switch (item.type) {
      'prediction' => 'You feared: "${item.text}". Did it happen?',
      'activity' => 'Did you do it: "${item.text}"?',
      'urge' => 'The urge: "${item.text}". Did you hold off?',
      _ => 'Did it happen: "${item.text}"?',
    };
    final answers = item.type == 'prediction' ? ['No', 'Partly', 'Yes'] : ['Yes', 'Partly', 'Not today'];
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('One-minute debrief', style: t.titleMedium),
      const SizedBox(height: 6),
      Text(question, style: t.bodyLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final a in answers) ChoiceChip(label: Text(a), selected: _result == a, onSelected: (_) => setState(() => _result = a)),
      ]),
      if (item.type == 'activity' && _result != null && _result != 'Not today') ...[
        const SizedBox(height: 8),
        Text('How much did you enjoy it? ${_enjoyment.round()} out of 10'
            '${item.details['predicted enjoyment'] != null ? ' (you predicted ${item.details['predicted enjoyment']})' : ''}'),
        Slider(min: 0, max: 10, divisions: 10, value: _enjoyment, onChanged: (v) => setState(() => _enjoyment = v)),
      ],
      TextField(autofillHints: PrivateKeyboard.autofillHints, maxLength: TextLimit.long, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, controller: _what, decoration: const InputDecoration(hintText: 'What happened, in a line')),
      const SizedBox(height: 8),
      FilledButton(onPressed: _result == null ? null : () async {
        final navigator = Navigator.of(context), what = _what.text.trim();
        state.data.programmes.first.log.add((isoDate(state.clock()), LogEntry('outcome',
            what.isEmpty ? _result! : what, {
          'about': item.text, 'result': _result!.toLowerCase(),
          if (item.type == 'activity' && _result != 'Not today') 'enjoyment': '${_enjoyment.round()}',
        })));
        final saving = state.save(); // not waited for first: a crisis in the words opens support at once (9B-02)
        if (mounted) {
          setState(() {
            _result = null;
            _what.clear();
          });
        }
        await readSavedWords(navigator, state, what, where: 'a debrief'); // a crisis opens support (B-18)
        await saving;
      }, child: const Text('Save')),
    ])));
  }
}

/// What each programme has built up, in the person's own data.
class ProgrammeProgress extends StatelessWidget {
  const ProgrammeProgress({super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppScope.of(context).data;
    if (d.programmes.isEmpty) return const SizedBox.shrink();
    final p = d.programmes.first;
    final t = Theme.of(context).textTheme;
    final entries = [for (final (_, e) in p.log) e];
    final outcomes = entries.where((e) => e.type == 'outcome').toList();
    int count(String type) => entries.where((e) => e.type == type).length;
    bool about(LogEntry o, String type) => entries.any((e) => e.type == type && e.text == o.details['about']);
    int checked(String type) => outcomes.where((o) => about(o, type)).length;
    int answered(String type, String result) =>
        outcomes.where((o) => about(o, type) && o.details['result'] == result).length;
    final lines = <String>[
      'Day ${p.dayOn(AppScope.of(context).clock())}, ${p.sessions} morning practices',
      if (checked('commitment') > 0) 'Commitments kept: ${answered('commitment', 'yes')}, partly '
          '${answered('commitment', 'partly')}, of ${checked('commitment')} checked',
      if (checked('prediction') > 0) 'Fears that came true: ${answered('prediction', 'yes')}, partly '
          '${answered('prediction', 'partly')}, of ${checked('prediction')} checked',
      if (checked('activity') > 0) 'Activities done: ${answered('activity', 'yes') + answered('activity', 'partly')} '
          'of ${checked('activity')} checked',
      if (count('evidence') > 0) 'Evidence collected: ${count('evidence')} pieces',
      if (checked('urge') > 0) 'Urges held off: ${answered('urge', 'yes') + answered('urge', 'partly')} of ${checked('urge')} checked',
    ];
    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(programmeInfo[p.name]!.title, style: t.titleMedium),
      const SizedBox(height: 8),
      // the body size of every other card on Progress, with tabular figures so the counts line up
      for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l,
          style: t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
    ])));
  }
}
