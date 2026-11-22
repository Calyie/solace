// The plan, in view during a session and on Today (owner, 2026-11-19: "the plan should be visible in their sessions
// and actively maintained by you so you both know you are making progress towards a holistic solution"). It shows
// what the therapist keeps in the therapy record (core/formats.dart storyHeadings, prompt v5): the plan with its
// phases, where the two of them are in it, the tasks in hand and the progress so far. The person can change any of
// it in You, like the rest of what Solace remembers.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/formats.dart' show storyHeadings;
import '../core/store.dart' show AppData;
import '../core/therapist.dart' show therapistNameFor;
import 'premium.dart';

/// The parts of the therapy record that make up the plan, in reading order.
const planHeadings = ['What we are working on', 'The plan', 'Where we are in the plan', 'Activities and tasks', 'Progress'];

String _part(AppData data, String heading) {
  final text = (data.story.sections[heading] ?? '').trim();
  return text.toLowerCase() == 'nothing yet' ? '' : text;
}

/// Whether a plan has been made yet (the first session makes it; core/formats.dart promptKindFor reads the same).
bool hasPlan(AppData data) => storyHeadings.contains('The plan') && _part(data, 'The plan').isNotEmpty;

Future<void> showPlan(BuildContext context) => showModalBottomSheet<void>(context: context, showDragHandle: true,
    isScrollControlled: true, useSafeArea: true, builder: (_) => const PlanSheet());

class PlanSheet extends StatelessWidget {
  const PlanSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data, t = Theme.of(context).textTheme, scheme = Theme.of(context).colorScheme;
    final name = therapistNameFor(data.settings.portrait);
    final parts = [for (final h in planHeadings) if (_part(data, h).isNotEmpty) (h, _part(data, h))];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        key: const Key('plan_sheet'),
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Your plan with $name', style: t.titleLarge),
          const SizedBox(height: Space.s),
          if (!hasPlan(data))
            Text('You and $name build your plan in your first session: what you want to change, the method for it, '
                'the steps over the coming weeks, and how you will both see progress. It shows here from then on.',
                key: const Key('plan_none'), style: t.bodyLarge)
          else ...[
            for (final (heading, text) in parts) ...[
              const SizedBox(height: Space.l),
              Text(heading, style: t.labelLarge?.copyWith(color: scheme.primary)),
              const SizedBox(height: Space.xs),
              SelectableText(text, style: t.bodyLarge),
            ],
            const SizedBox(height: Space.xl),
            Text('$name keeps this up to date after every session. You can change any of it in You.',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
}

/// Today: where the two of them are in the plan, once there is one; a tap opens the whole plan.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data;
    if (!hasPlan(data)) return const SizedBox.shrink();
    final where = _part(data, 'Where we are in the plan');
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Card(child: ListTile(
        key: const Key('plan_card'),
        leading: const Icon(Icons.flag_outlined),
        title: const Text('Your plan'),
        subtitle: Text(where.isEmpty ? _part(data, 'The plan') : where, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showPlan(context),
      )),
    );
  }
}
