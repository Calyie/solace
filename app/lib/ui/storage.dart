// Space Solace uses (owner, 2026-11-14): how much room its own data takes against its own fixed limit
// (core/storage.dart), what takes it, a way to keep a copy of what matters first, and a way to make room by deleting
// older conversations. Nothing here reads or shows the device's own space (owner, 2026-11-19).
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/storage.dart';
import 'premium.dart';
import 'choose_to_delete.dart';
import 'transfer_screen.dart';
import 'your_data.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, int>? _kinds;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kinds == null) _measure();
  }

  Future<void> _measure() async {
    final state = AppScope.of(context);
    try {
      await state.measurePictures();
    } catch (_) {}
    if (!mounted) return;
    try {
      final kinds = await spaceByKind(state.data);
      if (mounted) setState(() => _kinds = kinds);
    } catch (_) {
      if (mounted) setState(() => _kinds = const {});
    }
  }

  Future<void> _deleteOlder(int months) async {
    final state = AppScope.of(context);
    final now = state.clock();
    final cutoff = DateTime(now.year, now.month - months, now.day);
    final n = conversationsBefore(state.data, cutoff);
    if (n == 0) {
      setState(() => _message = 'There are no conversations older than that.');
      return;
    }
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Delete $n older ${n == 1 ? 'conversation' : 'conversations'}?'),
      // what else goes and what stays, as Choose what to delete says it (round 6 review, E-02)
      content: const Text('Their words and notes are deleted from this device. Your moods, scores, plans, safety plan '
          'and safety history stay. If any of them matter to you, keep a copy first with Export or Send to another '
          'device.\n\n$conversationsDeleteNote', key: Key('storage_delete_words')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep them')),
        FilledButton(key: const Key('storage_delete_confirm'), onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete')),
      ],
    ));
    if (sure != true || !mounted) return;
    final removed = deleteConversationsBefore(state.data, cutoff);
    if (!await state.trySave()) {
      // round 6 review, E-01: never "Deleted" when the device still holds them. They are gone from this run, so
      // asking again finds none: the banner's Try again saves the delete
      if (mounted) {
        setState(() => _message = 'This could not be saved, so they are not deleted yet. They could come back when '
            'Solace next opens. The device may be full. Free some space, then tap Try again at the top.');
      }
      return;
    }
    feelDone();
    if (!mounted) return;
    setState(() {
      _message = 'Deleted $removed older ${removed == 1 ? 'conversation' : 'conversations'}.';
      _kinds = null;
    });
    _measure();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    const allowance = solaceAllowance;
    final used = state.vault.savedBytes + state.pictureBytes;
    final fraction = (used / allowance).clamp(0.0, 1.0);
    final space = spaceState(state.vault.savedBytes, state.pictureBytes);
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Space Solace uses')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('${megabytes(used)} of ${megabytes(allowance)}', style: t.headlineSmall),
        const SizedBox(height: Space.s),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(key: const Key('storage_bar'),
            value: fraction, minHeight: 10,
            color: space == SpaceState.fine ? scheme.primary : scheme.error)),
        const SizedBox(height: Space.s),
        Text(switch (space) {
          SpaceState.fine => 'Room for a great many more conversations and pictures. Solace keeps its own data '
              'within ${megabytes(solaceAllowance)}, so it never crowds your device or other apps.',
          SpaceState.nearlyFull => 'Solace\'s own space is nearly full. Keep a copy of what matters, then delete some '
              'older conversations to make room.',
          SpaceState.full => 'Solace\'s own space is full. A new conversation can start once there is room. Keep a '
              'copy of what matters, then delete older conversations. Support and your safety plan always work.',
        }, key: const Key('storage_state'), style: t.bodyMedium),
        const SectionHeader('What takes the room'),
        Card(child: Padding(padding: const EdgeInsets.all(Space.l), child: _kinds == null
            ? const Center(child: Padding(padding: EdgeInsets.all(Space.s), child: CircularProgressIndicator()))
            : Column(children: [
                for (final e in {..._kinds!, 'Pictures': state.pictureBytes}.entries) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(
                    children: [
                  Expanded(child: Text(e.key)),
                  Text(megabytes(e.value), style: t.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
                ])),
                Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(
                    '${state.data.sessions.length} conversations kept. The model, voice and safety files are separate '
                    'and do not count.', style: t.bodySmall)),
              ]))),
        const SectionHeader('Keep a copy first'),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.ios_share_outlined), title: const Text('Export for you or your clinician'),
              subtitle: const Text('A PDF, a spreadsheet file or a readable page'), trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YourDataScreen()))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.upload_file_outlined), title: const Text('Move everything to another device'),
              subtitle: const Text('A locked file, opened only with its one-time code'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendToDeviceScreen()))),
        ])),
        const SectionHeader('Make room'),
        Card(child: ListTile(key: const Key('storage_choose'), leading: const Icon(Icons.checklist_rtl_outlined),
            title: const Text('Choose what to delete'),
            subtitle: const Text('Pick conversations, pictures, journal entries, feelings, questionnaires or moods'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ChooseToDeleteScreen()));
              if (mounted) {
                setState(() => _kinds = null);
                _measure();
              }
            })),
        Card(child: Column(children: [
          for (final (months, label) in const [(6, 'older than 6 months'), (12, 'older than a year'),
              (24, 'older than 2 years')])
            ListTile(key: Key('storage_older_$months'), leading: const Icon(Icons.auto_delete_outlined),
                title: Text('Delete conversations $label'), onTap: () => _deleteOlder(months)),
        ])),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: Space.s),
            child: Text(_message!, style: t.bodyMedium)),
      ])),
    );
  }
}

/// The Today tab's gentle note when Solace's own space is nearly full or full; nothing otherwise, and never anything
/// about the device's space (owner, 2026-11-19).
class SpaceNote extends StatelessWidget {
  const SpaceNote({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final space = spaceState(state.vault.savedBytes, state.pictureBytes);
    if (space == SpaceState.fine) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(color: scheme.errorContainer, margin: const EdgeInsets.only(bottom: Space.m), child: ListTile(
      key: const Key('space_note'),
      leading: Icon(Icons.storage_outlined, color: scheme.onErrorContainer),
      title: Text(space == SpaceState.full ? 'Solace\'s space is full' : 'Solace\'s space is nearly full'),
      subtitle: const Text('Keep a copy of what matters, then make room by deleting older conversations.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageScreen())),
    ));
  }
}
