// Choose what to delete (owner, 2026-11-14: "can users also choose which data they want to delete?"): one kind at a
// time (conversations, pictures, journal entries, feelings, questionnaires, moods), each a list to tick and delete,
// built lazily so thousands of entries never slow the screen. Safety history is not offered: it keeps crisis care
// working (the next sessions' gentle check, the reliving gate). Delete everything stays in Settings.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/store.dart' show SessionRecord;
import 'chat.dart' show kindTitles;
import 'premium.dart';

/// One entry that can be ticked: a stable key, what it is, and a line of detail.
class _Entry {
  const _Entry(this.key, this.title, this.detail);
  final Object key;
  final String title, detail;
}

String _short(String s, [int n = 90]) {
  final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length <= n ? one : '${one.substring(0, n)}...';
}

class ChooseToDeleteScreen extends StatelessWidget {
  const ChooseToDeleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = state.data;
    final t = Theme.of(context).textTheme;
    Widget kind(String id, IconData icon, String title, int count, List<_Entry> Function() entries,
        Future<void> Function(Set<Object>) delete, {String? alsoSay}) => Card(margin: const EdgeInsets.only(bottom: Space.s),
        child: ListTile(key: Key('choose_$id'), leading: Icon(icon), title: Text(title), subtitle: Text('$count kept'),
            trailing: const Icon(Icons.chevron_right), enabled: count > 0,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                _PickToDelete(title: title, entries: entries(), delete: delete, alsoSay: alsoSay)))));
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Choose what to delete')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Pick exactly what to delete. Keep a copy first with Export if any of it matters to you.', style: t.bodyLarge),
        const SizedBox(height: Space.l),
        kind('conversations', Icons.chat_bubble_outline, 'Conversations', d.sessions.length, () => [
          for (final s in d.sessions.reversed) _Entry(s, '${kindTitles[s.kind] ?? 'Session'}, ${s.date}',
              _short(s.turns.where((x) => x.$1 == 'person').map((x) => x.$2).firstOrNull ?? s.note)),
        ], (keys) async {
          // their words go from the plans and the last note too (round 5 review, C-11: core/store.dart deleteSessions)
          d.deleteSessions({for (final k in keys) k as SessionRecord});
          await state.saveOrThrow(); // round 6 review, E-01: never "Deleted" unless saved
        }, alsoSay: conversationsDeleteNote),
        kind('pictures', Icons.image_outlined, 'Pictures', d.photos.length, () => [
          for (final title in d.photos.keys) _Entry(title, title, 'On your vision board'),
        ], (keys) async {
          var unsaved = false; // round 6 review, E-01: each one is still removed; the screen says it is not saved
          for (final k in keys) {
            try {
              await state.deletePicture(k as String);
            } on NotSaved {
              unsaved = true;
            }
          }
          if (unsaved) throw const NotSaved();
        }),
        kind('journal', Icons.edit_note_outlined, 'Journal entries', d.journal.length, () => [
          for (final j in d.journal.reversed) _Entry(j, '${j['date'] ?? ''}', _short('${j['text'] ?? ''}')),
        ], (keys) async {
          d.journal.removeWhere(keys.contains);
          await state.saveOrThrow(); // round 6 review, E-01: never "Deleted" unless saved
        }),
        kind('feelings', Icons.favorite_border, 'Feelings check-ins', d.emotions.length, () => [
          for (final e in d.emotions.reversed) _Entry(e, e.at.replaceFirst('T', ' '), _short(e.words.join(', '))),
        ], (keys) async {
          d.emotions.removeWhere(keys.contains);
          await state.saveOrThrow(); // round 6 review, E-01: never "Deleted" unless saved
        }),
        kind('questionnaires', Icons.fact_check_outlined, 'Questionnaire results', d.scores.length, () => [
          for (final s in d.scores.reversed) _Entry(s, '${s['name']}, ${s['date']}', 'Score ${s['total']}'),
        ], (keys) async {
          d.scores.removeWhere(keys.contains);
          await state.saveOrThrow(); // round 6 review, E-01: never "Deleted" unless saved
        }),
        kind('moods', Icons.mood_outlined, 'Moods', d.moods.length, () => [
          for (final e in (d.moods.entries.toList()..sort((a, b) => b.key.compareTo(a.key))))
            _Entry(e.key, dayLabel(DateTime.tryParse(e.key) ?? DateTime(2000)), 'Mood ${e.value} of 10'),
        ], (keys) async {
          for (final k in keys) {
            d.moods.remove(k);
            d.moodTimes.remove(k);
          }
          await state.saveOrThrow(); // round 6 review, E-01: never "Deleted" unless saved
        }),
        const SizedBox(height: Space.m),
        Text('Your safety history is not offered here: it keeps crisis care working, such as the gentle check at the '
            'start of the next sessions. Delete everything in Settings removes it with everything else.',
            style: t.bodySmall),
      ])),
    );
  }
}

/// What deleting a conversation also removes, and what it cannot (round 5 review, C-11), said before it is done.
const conversationsDeleteNote = 'Your words quoted in goals, values and steps made in them are deleted too, and so '
    'is the last session note if it is theirs.\n\nYour story so far sums up all your conversations and cannot be '
    'split by conversation, so it stays as it is. To change or clear any part of it, go to You > Your story so far, or '
    'use Erase what Solace remembers there.';

/// Said when a delete could not be saved on the device (round 6 review, E-01); Space Solace uses says it too.
const deleteNotSaved = 'This could not be saved, so it is not deleted yet. It could come back when Solace next opens. '
    'The device may be full. Free some space, then try again.';

class _PickToDelete extends StatefulWidget {
  const _PickToDelete({required this.title, required this.entries, required this.delete, this.alsoSay});
  final String title;
  final List<_Entry> entries;
  final Future<void> Function(Set<Object> keys) delete;
  final String? alsoSay; // what else the delete removes or keeps, in the confirmation
  @override
  State<_PickToDelete> createState() => _PickToDeleteState();
}

class _PickToDeleteState extends State<_PickToDelete> {
  final _picked = <Object>{};
  late List<_Entry> _left = widget.entries;
  bool _busy = false;
  String? _message;

  Future<void> _delete() async {
    final n = _picked.length;
    final sure = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Delete $n ${n == 1 ? 'item' : 'items'}?'),
      content: Text(['They are deleted from this device. This cannot be undone.', ?widget.alsoSay].join('\n\n'),
          key: const Key('choose_delete_words')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep them')),
        FilledButton(key: const Key('choose_delete_confirm'), onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete')),
      ],
    ));
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.delete(Set.of(_picked));
      feelDone();
      if (!mounted) return;
      setState(() {
        _left = [for (final e in _left) if (!_picked.contains(e.key)) e];
        _message = 'Deleted $n ${n == 1 ? 'item' : 'items'}.';
        _picked.clear();
      });
    } on NotSaved {
      // round 6 review, E-01: the delete is made in this run but the device still holds the old data, which would
      // come back at the next start; the entries stay listed and ticked, so Delete can be tapped again
      if (mounted) setState(() => _message = deleteNotSaved);
    } catch (_) {
      if (mounted) setState(() => _message = 'Not everything could be deleted. Try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = _left.isNotEmpty && _picked.length == _left.length;
    return Scaffold(
      appBar: AppBar(title: BarTitle(widget.title), actions: [
        TextButton(key: const Key('choose_all'), onPressed: _left.isEmpty ? null : () => setState(() {
          all ? _picked.clear() : _picked.addAll(_left.map((e) => e.key));
        }), child: Text(all ? 'Select none' : 'Select all')),
      ]),
      body: Readable(maxWidth: 720, child: Column(children: [
        if (_message != null) Padding(padding: const EdgeInsets.all(Space.m), child: Text(_message!)),
        Expanded(child: _left.isEmpty
            ? const Center(child: Text('Nothing left here.'))
            : ListView.builder(itemCount: _left.length, itemBuilder: (context, i) {
                final e = _left[i];
                return CheckboxListTile(key: Key('choose_item_$i'), value: _picked.contains(e.key),
                    title: Text(e.title), subtitle: e.detail.isEmpty ? null : Text(e.detail, maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    onChanged: (v) => setState(() => v == true ? _picked.add(e.key) : _picked.remove(e.key)));
              })),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(Space.m), child: SizedBox(
            width: double.infinity, child: FilledButton(key: const Key('choose_delete'),
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: _picked.isEmpty || _busy ? null : _delete,
                child: Text(_picked.isEmpty ? 'Tick what to delete' : 'Delete ${_picked.length} selected'))))),
      ])),
    );
  }
}
