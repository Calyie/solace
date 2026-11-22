// Before spoken reliving: a plain warning, the readiness questions, the support person, and their guide. The Start
// button only works when the gate (core/gate.dart) is open; the session controller checks the gate again itself.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/gate.dart';
import 'chat.dart';
import 'premium.dart';

class RelivingGateScreen extends StatefulWidget {
  const RelivingGateScreen({super.key});
  @override
  State<RelivingGateScreen> createState() => _RelivingGateScreenState();
}

class _RelivingGateScreenState extends State<RelivingGateScreen> {
  // null = not answered yet
  final Map<String, bool?> _a = {'grounding': null, 'suicidal': null, 'danger': null, 'psychosis': null,
      'dissociate': null, 'support': null};

  static const _questions = [
    ('grounding', 'Have you practised grounding (like 5-4-3-2-1) in earlier sessions?', true),
    ('suicidal', 'In the last two weeks, have you had thoughts of suicide, or hurt yourself?', false),
    ('danger', 'Is the danger still part of your life, or are you in contact with the person who hurt you?', false),
    ('psychosis', 'Do you hear or see things that other people do not?', false),
    ('dissociate', 'Do you often lose touch with your surroundings, or lose chunks of time?', false),
    ('support', 'Is a support person with you right now, and will they stay for the whole session?', true),
  ];

  ReadinessAnswers? get _answers => _a.values.any((v) => v == null) ? null : ReadinessAnswers(
        practisedGrounding: _a['grounding']!, noSuicidalThoughtsOrRecentSelfHarm: !_a['suicidal']!,
        notLivingWithTheDanger: !_a['danger']!, noPsychosis: !_a['psychosis']!,
        rarelyLoseTouchWithSurroundings: !_a['dissociate']!, supportPersonPresent: _a['support']!);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final answers = _answers;
    final gate = answers == null ? null : relivingGate(state.data, answers, state.clock());
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Spoken reliving')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Before we start', style: t.headlineSmall),
        const SizedBox(height: 8),
        const Text('In this session you will go back through a traumatic memory out loud, slowly, while staying '
            'connected to the present. It can be very effective and it can be intense. A support person must be with '
            'you, and you can say stop at any moment. Your support person is not a therapist, and the app cannot '
            'check they are there, so please be honest with yourself here.'),
        const SizedBox(height: 16),
        for (final (key, q, _) in _questions) Card(key: ValueKey('gate-$key'), child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q, style: t.bodyLarge),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Yes')), ButtonSegment(value: false, label: Text('No'))],
            selected: {if (_a[key] != null) _a[key]!},
            emptySelectionAllowed: true,
            onSelectionChanged: (v) => setState(() => _a[key] = v.isEmpty ? null : v.first),
          ),
        ]))),
        const SizedBox(height: 8),
        const ExpansionTile(title: Text('Guide for your support person'), children: [
          Padding(padding: EdgeInsets.all(12), child: Text(
              'Thank you for being here. Please stay close and quiet, and let them speak without interrupting the '
              'memory. If they seem to drift away (staring, not answering, saying they feel unreal or numb), say their '
              'name gently and help them name five things they can see, four they can touch, three they can hear. If '
              'they say stop, the session stops. If they talk about harming themselves, call the crisis number shown '
              'in the app (the heart icon).')),
        ]),
        const SizedBox(height: 16),
        if (gate != null && !gate.open) ...[
          Text('Not today, and that is all right:', style: t.titleMedium),
          for (final r in gate.reasons) Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $r')),
          const SizedBox(height: 8),
          const Text('Written exposure and the grounding practices are always available.'),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: gate?.open == true
              ? () => Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(kind: 'reliving', readiness: answers)))
              : null,
          child: const Text('Start the reliving session'),
        ),
      ])),
    );
  }
}
