// My safety plan (research report P0 4; core/safety_plan.dart): seven steps to work down in a hard moment, written by
// the person while they feel steadier, with their country's crisis lines always in step 5. One tap from the support
// screen and from the You tab. "Save a copy" makes a PDF to print or keep; like every export it says plainly that the
// file is outside Solace's encryption.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/crisis.dart';
import '../core/dates.dart';
import '../core/exports.dart' show longDate;
import '../core/safety_plan.dart';
import 'premium.dart';
import 'your_data.dart' show SaveExport, saveWithDialog;

class SafetyPlanScreen extends StatefulWidget {
  const SafetyPlanScreen({super.key, this.save = saveWithDialog});
  final SaveExport save;
  @override
  State<SafetyPlanScreen> createState() => _SafetyPlanScreenState();
}

class _SafetyPlanScreenState extends State<SafetyPlanScreen> {
  final _fields = {for (final s in planSteps) s.id: TextEditingController()};
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _add(String id) async {
    final state = AppScope.of(context);
    final text = _fields[id]!.text;
    if (text.trim().isEmpty) return;
    state.data.safetyPlan.add(id, text, isoDate(state.clock()));
    _fields[id]!.clear();
    feelChoice();
    setState(() {});
    await state.save();
  }

  Future<void> _remove(String id, int i) async {
    final state = AppScope.of(context);
    state.data.safetyPlan.remove(id, i, isoDate(state.clock()));
    setState(() {});
    await state.save();
  }

  Future<void> _saveCopy() async {
    final state = AppScope.of(context);
    final accent = Theme.of(context).colorScheme.primary.toARGB32();
    final bundle = DefaultAssetBundle.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    String said;
    try {
      Future<ByteData?> font(String path) async {
        try {
          return await bundle.load(path);
        } catch (_) {
          return null;
        }
      }
      final bytes = await safetyPlanPdf(state.data.safetyPlan, crisisByCountry[state.data.settings.country],
          regular: await font('assets/fonts/Figtree-Regular.ttf'), bold: await font('assets/fonts/Figtree-Bold.ttf'),
          accent: accent);
      final where = await widget.save('my-safety-plan.pdf', Uint8List.fromList(bytes), 'application/pdf');
      said = where == null ? 'Not saved. Nothing has left Solace.'
          : '$where It is outside Solace\'s encryption now, so keep it somewhere private.';
      if (where != null) feelDone();
    } catch (_) {
      said = 'The file could not be made or saved. Nothing has left Solace. Try again in a moment.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = said;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final plan = state.data.safetyPlan;
    final country = crisisByCountry[state.data.settings.country];
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const BarTitle('My safety plan')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('A plan for hard moments, made while you feel steadier. When things get difficult, work down the steps '
            'until you feel safe.', style: t.bodyLarge),
        if (plan.updated != null) Padding(padding: const EdgeInsets.only(top: Space.xs),
            child: Text('Last changed ${longDate(plan.updated!)}', style: t.bodySmall)),
        const SizedBox(height: Space.l),
        for (var i = 0; i < planSteps.length; i++) _step(context, i, planSteps[i], plan, country, t, scheme),
        const SizedBox(height: Space.s),
        OutlinedButton.icon(key: const Key('plan_save'), onPressed: _busy ? null : _saveCopy,
            icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Save a copy to print or keep')),
        const SizedBox(height: Space.xs),
        Text(_message ?? 'A saved copy is outside Solace\'s encryption, so keep it somewhere private.',
            style: t.bodySmall),
        const SizedBox(height: Space.l),
        Text('The steps follow the Safety Planning Intervention of Stanley and Brown (2012), in our own words.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ])),
    );
  }

  Widget _step(BuildContext context, int i, PlanStep step, SafetyPlan plan, CountryCrisis? country, TextTheme t,
      ColorScheme scheme) {
    final items = plan.of(step.id);
    return Card(margin: const EdgeInsets.only(bottom: Space.m), child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.s, Space.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the steps are an order to follow, so they are numbered
          CircleAvatar(radius: 14, backgroundColor: scheme.primaryContainer, child: Text('${i + 1}',
              style: t.labelLarge?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700))),
          const SizedBox(width: Space.m),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.title, style: t.titleSmall),
            const SizedBox(height: 2),
            Text(step.hint, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ])),
        ]),
        const SizedBox(height: Space.s),
        for (var k = 0; k < items.length; k++) Padding(padding: const EdgeInsets.only(left: 40), child: Row(children: [
          Expanded(child: Text(items[k], style: t.bodyLarge)),
          IconButton(key: Key('plan_remove_${step.id}_$k'), tooltip: 'Remove', visualDensity: VisualDensity.compact,
              onPressed: () => _remove(step.id, k), icon: const Icon(Icons.close, size: 18)),
        ])),
        if (step.id == 'professionals' && country != null)
          for (final l in [...country.lines, ...country.emergency]) Padding(
            padding: const EdgeInsets.only(left: 40, top: 2, bottom: 2, right: Space.s),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${l.number}  ', style: t.titleSmall?.copyWith(color: scheme.primary)),
              TextSpan(text: l.name, style: t.bodyMedium),
            ])),
          ),
        Padding(padding: const EdgeInsets.only(left: 40), child: Row(children: [
          Expanded(child: TextField(autofillHints: PrivateKeyboard.autofillHints, key: Key('plan_add_${step.id}'), controller: _fields[step.id],
              enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck,
              textCapitalization: TextCapitalization.sentences, maxLength: 500,
              onSubmitted: (_) => _add(step.id),
              decoration: InputDecoration(hintText: step.example, counterText: ''))),
          IconButton(key: Key('plan_add_${step.id}_go'), tooltip: 'Add', onPressed: () => _add(step.id),
              icon: const Icon(Icons.add)),
        ])),
      ]),
    ));
  }
}

/// The way into the plan from the You tab and the support screen.
class SafetyPlanCard extends StatelessWidget {
  const SafetyPlanCard({super.key});
  @override
  Widget build(BuildContext context) {
    final plan = AppScope.of(context).data.safetyPlan;
    final scheme = Theme.of(context).colorScheme;
    return Card(margin: const EdgeInsets.only(bottom: Space.m), child: ListTile(
      key: const Key('open_safety_plan'),
      leading: CircleAvatar(backgroundColor: scheme.errorContainer,
          child: Icon(Icons.health_and_safety_outlined, color: scheme.onErrorContainer)),
      title: const Text('My safety plan'),
      subtitle: Text(plan.isEmpty ? 'Steps for hard moments, written while you feel steadier'
          : 'Your steps for hard moments, and who to call'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyPlanScreen())),
    ));
  }
}
