// "Name the feeling" (report recommendation 21): an optional, calm sheet beside the 0 to 10 tap. Three short steps:
// where you are on the energy by pleasantness grid, the words that fit (several, from any part of the grid, because
// feelings come mixed), and, if you like, what is affecting you and a note. Muted colours from the theme, never red;
// nothing to get right; it can be closed at any step.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/home_link.dart' show staysOnFor;
import '../core/dates.dart';
import '../core/emotions.dart';
import 'crisis.dart' show readSavedWords;
import 'premium.dart';
import 'theme.dart';

/// Said when naming a feeling could not be saved (round 9 review B, 9B-07).
const feelingNotSaved = 'This feeling could not be saved. The device may be full. Free some space, then name it '
    'again.';

/// Each quarter of the grid takes one of the theme's muted practice hues: (ink, soft fill).
(Color, Color) quadrantHues(BuildContext context, String quadrant) => huesOf(context).category(const {
      'high_unpleasant': 'kindness', 'high_pleasant': 'feel_good', 'low_unpleasant': 'sleep', 'low_pleasant': 'calm',
    }[quadrant] ?? 'tools');

/// Opens the sheet. Returns true when a check-in was saved.
Future<bool> showEmotionSheet(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true,
      sheetAnimationStyle: calmSheet(context), builder: (_) => const EmotionSheet());
  return saved ?? false;
}

/// The quiet link on Today's mood card and in the check-in, with today's words once some are named.
class NameFeelingLink extends StatelessWidget {
  const NameFeelingLink({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final today = isoDate(state.clock());
    final named = <String>{for (final e in state.data.emotions) if (e.date == today) ...e.words}.toList();
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      TextButton.icon(key: const Key('name_feeling'), onPressed: () => showEmotionSheet(context),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.s)),
          icon: const Icon(Icons.bubble_chart_outlined, size: 18), label: const Text('Name the feeling')),
      if (named.isNotEmpty)
        Padding(padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Text('Today: ${named.take(4).join(', ')}', style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class EmotionSheet extends StatefulWidget {
  const EmotionSheet({super.key});
  @override
  State<EmotionSheet> createState() => _EmotionSheetState();
}

class _EmotionSheetState extends State<EmotionSheet> {
  int _step = 0; // 0 the grid, 1 the words, 2 what is affecting you and a note
  String? _quadrant;
  final _words = <String>[]; // in the order chosen
  final _tags = <String>{};
  bool _others = false; // the other parts of the grid shown too
  bool _saving = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _pick(String q) {
    feelChoice();
    setState(() {
      _quadrant = q;
      _step = 1;
    });
  }

  Future<void> _save() async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    final note = _note.text.trim();
    state.data.emotions.add(EmotionEntry(at: stampOf(state.clock()), quadrant: _quadrant!, words: _words,
        tags: [for (final (id, _) in affectingTags) if (_tags.contains(id)) id], note: note));
    // Round 9 review B: the save runs while the note is read, so a crisis in it opens support at once (9B-02), and
    // "Saved." is said only when the save worked (9B-07, as E-01 and G7-02 for the other screens).
    final saving = state.trySave();
    navigator.pop(true);
    // the note is read by the phrase rules; a crisis in it opens support (round 4 review, B-18)
    await readSavedWords(navigator, state, note, where: "a feeling's note");
    if (await saving) {
      feelDone();
      messenger?.showSnackBar(const SnackBar(content: Text('Saved. Thank you for naming it.')));
    } else {
      messenger?.showSnackBar(const SnackBar(key: Key('not_saved'), content: Text(feelingNotSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final steps = [_grid(context), _wordsStep(context), _contextStep(context)];
    final titles = ['Where are you right now?', 'Which words fit?', 'What\'s affecting you?'];
    final subtitles = ['Pick the part that fits best. There is no wrong answer.',
        'Choose one or more. Feelings often come mixed.', 'Optional. Choose any that apply, or none.'];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: size.height * 0.92),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s), child: Row(children: [
            Expanded(child: Text('Name the feeling', style: t.titleLarge)),
            _Dots(step: _step),
          ])),
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.l),
            child: AnimatedSwitcher(duration: Calm.normal, switchInCurve: Calm.curve, switchOutCurve: Calm.curve,
                child: Column(key: ValueKey(_step), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(titles[_step], style: t.titleMedium),
                  const SizedBox(height: Space.xs),
                  Text(subtitles[_step], style: t.bodySmall),
                  const SizedBox(height: Space.l),
                  steps[_step],
                ])),
          )),
          const Divider(),
          Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l), child: Wrap(
              alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s, runSpacing: Space.s, children: [
            TextButton(key: const Key('emotion_back'),
                onPressed: () => _step == 0 ? Navigator.pop(context, false) : setState(() => _step--),
                child: Text(_step == 0 ? 'Not now' : 'Back')),
            if (_step == 1)
              FilledButton(key: const Key('emotion_next'), onPressed: _words.isEmpty ? null : () => setState(() => _step = 2),
                  child: const Text('Next')),
            if (_step == 2)
              FilledButton(key: const Key('emotion_save'), onPressed: _saving ? null : _save, child: const Text('Save')),
          ])),
        ]),
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget tile(String id) {
      final (title, examples) = (quadrantTitle(id), quadrants.firstWhere((q) => q.$1 == id).$3);
      final (ink, soft) = quadrantHues(context, id);
      final chosen = _quadrant == id;
      return Expanded(child: Semantics(button: true, selected: chosen, label: '$title, $examples',
          excludeSemantics: true, child: Material(
            color: soft, borderRadius: BorderRadius.circular(20),
            child: InkWell(key: Key('quadrant_$id'), borderRadius: BorderRadius.circular(20), onTap: () => _pick(id),
                child: AnimatedContainer(duration: Calm.quick, curve: Calm.curve,
                    constraints: const BoxConstraints(minHeight: 112),
                    padding: const EdgeInsets.all(Space.m),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: chosen ? ink : Colors.transparent, width: 1.5)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                      Text(title, style: t.titleSmall?.copyWith(color: ink)),
                      const SizedBox(height: Space.xs),
                      Text(examples, style: t.bodySmall?.copyWith(color: ink.withValues(alpha: 0.85))),
                    ]))),
          )));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [tile('high_unpleasant'), const SizedBox(width: Space.s), tile('high_pleasant')])),
      const SizedBox(height: Space.s),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [tile('low_unpleasant'), const SizedBox(width: Space.s), tile('low_pleasant')])),
      const SizedBox(height: Space.s),
      Text('More energy at the top, more pleasant to the right.', style: t.bodySmall, textAlign: TextAlign.center),
    ]);
  }

  Widget _chips(String quadrant) {
    final (ink, soft) = quadrantHues(context, quadrant);
    return Wrap(spacing: Space.s - 2, runSpacing: Space.s - 2, children: [
      for (final w in emotionWords[quadrant]!)
        FilterChip(key: Key('word_$w'), label: Text(w), selected: _words.contains(w), selectedColor: soft,
            side: BorderSide(color: _words.contains(w) ? ink : Theme.of(context).colorScheme.outlineVariant),
            onSelected: (on) {
              feelChoice();
              setState(() => on ? _words.add(w) : _words.remove(w));
            }),
    ]);
  }

  Widget _wordsStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _quadrant ?? quadrants.first.$1;
    final picked = _words.where((w) => quadrantOfWord[w] != q).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(quadrantTitle(q), style: t.labelLarge?.copyWith(color: quadrantHues(context, q).$1)),
      const SizedBox(height: Space.s),
      _chips(q),
      const SizedBox(height: Space.m),
      if (!_others)
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(key: const Key('emotion_others'),
            onPressed: () => setState(() => _others = true), icon: const Icon(Icons.expand_more, size: 18),
            label: Text(picked.isEmpty ? 'Words from the other parts too' : 'Words from the other parts too '
                '(${picked.length} chosen)')))
      else
        for (final (other, title, _) in quadrants)
          if (other != q) ...[
            const SizedBox(height: Space.m),
            Text(title, style: t.labelLarge?.copyWith(color: quadrantHues(context, other).$1)),
            const SizedBox(height: Space.s),
            _chips(other),
          ],
    ]);
  }

  Widget _contextStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: Space.s - 2, runSpacing: Space.s - 2, children: [
        for (final (id, label) in affectingTags)
          FilterChip(key: Key('tag_$id'), label: Text(label), selected: _tags.contains(id), onSelected: (on) {
            feelChoice();
            setState(() => on ? _tags.add(id) : _tags.remove(id));
          }),
      ]),
      const SizedBox(height: Space.xl),
      Text('A note, if you like', style: t.titleSmall),
      const SizedBox(height: Space.s),
      TextField(autofillHints: PrivateKeyboard.autofillHints, buildCounter: quietCounter, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('emotion_note'), controller: _note, minLines: 2, maxLines: 5,
          maxLength: maxNoteLength, textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What is behind it?')),
      Text('Only you see this. It stays on ${staysOnFor(AppScope.of(context).data.settings.homeServer)} unless you choose to put it in a file.', style: t.bodySmall),
      const SizedBox(height: Space.m),
      Text('You chose: ${_words.join(', ')}', style: t.bodySmall),
    ]);
  }
}

/// Three small dots: where you are in the sheet, without a counter.
class _Dots extends StatelessWidget {
  const _Dots({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(label: 'Step ${step + 1} of 3', child: Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 3; i++)
        AnimatedContainer(duration: Calm.normal, curve: Calm.curve, margin: const EdgeInsets.only(left: Space.xs),
            width: i == step ? 18 : 6, height: 6,
            decoration: BoxDecoration(color: i <= step ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(3))),
    ]));
  }
}
