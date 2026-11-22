// The vision board (PLAN 13, TASKLIST B3): the person's own pictures and words, each with a WOOP on its back (wish,
// best outcome, obstacle, if-then plan; Oettingen) so it never stands alone, as imagining alone can lower effort. One
// picture comes up each morning with its plan; a picture with nothing done for a month is something the therapist
// notices (core/plans.dart noticed). Photos stay on the device, encrypted (core/photos.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/photos.dart';
import '../core/plans.dart';
import '../core/storage.dart';
import 'crisis.dart' show readSavedWords;
import 'premium.dart';

typedef PickPhoto = Future<Uint8List?> Function();

Future<Uint8List?> _pickWithPicker() async {
  final picked = await FilePicker.pickFiles(dialogTitle: 'Choose a photo', type: FileType.image);
  if (picked.isEmpty) return null;
  try {
    // the size first, so a huge file is never read whole into memory (F-14); shrinkPhoto refuses it as unreadable
    if (await picked.first.xFile.length() > maxPhotoBytes) return Uint8List(0);
    return await picked.first.xFile.readAsBytes();
  } finally {
    // the picker's own copy of the full-size photo (with its location data, on Android) is removed (OW-M9-2)
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
  }
}

Widget _photoOrWords(BuildContext context, Picture p, {double height = 120}) {
  final has = AppScope.of(context).data.photos.containsKey(p.title);
  final scheme = Theme.of(context).colorScheme;
  return ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(height: height, width: double.infinity,
      child: has
          ? _PictureView(title: p.title)
          : DecoratedBox(decoration: BoxDecoration(color: scheme.primaryContainer),
              child: Center(child: Icon(Icons.image_outlined, color: scheme.onPrimaryContainer)))));
}

class VisionBoardSection extends StatelessWidget {
  const VisionBoardSection({super.key, this.pick = _pickWithPicker});
  final PickPhoto pick;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pictures = state.data.plans.pictures;
    final t = Theme.of(context).textTheme;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Vision board', style: t.titleMedium)),
        Text('${pictures.length} picture${pictures.length == 1 ? '' : 's'}', style: t.bodySmall),
      ]),
      const SizedBox(height: 4),
      const Text('Each picture keeps its plan on the back.'),
      const SizedBox(height: 12),
      if (pictures.isNotEmpty)
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9, children: [
          for (final p in pictures)
            InkWell(key: ValueKey('picture_${p.title}'), borderRadius: BorderRadius.circular(16),
                onTap: () => _open(context, p),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _photoOrWords(context, p, height: double.infinity)),
                  const SizedBox(height: 6),
                  Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                ])),
        ]),
      TextButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('Add a picture')),
    ])));
  }

  void _open(BuildContext context, Picture p) => showModalBottomSheet(context: context, isScrollControlled: true,
      sheetAnimationStyle: calmSheet(context), builder: (_) => PictureSheet(picture: p, pick: pick));

  Future<void> _add(BuildContext context) async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final title = TextEditingController(), wish = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Add a picture'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, controller: title, autofocus: true, maxLength: 200, decoration: const InputDecoration(hintText: 'A few words for it')),
        const SizedBox(height: 8),
        TextField(autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, controller: wish, maxLength: 1000, decoration: const InputDecoration(hintText: 'What you wish for')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
      ],
    ));
    final name = title.text.trim(), wished = wish.text.trim();
    if (ok == true && name.isNotEmpty) {
      final day = isoDate(state.clock());
      state.data.plans.pictures.add(Picture(title: name, wish: wished, added: day, lastAction: day));
      final saving = state.save(); // not waited for first: a crisis in the words opens support at once (9B-02)
      // read as notes are, crisis only (round 6 review F, F6-17: the wish was saved unread by the phrase rules)
      await readSavedWords(navigator, state, '$name\n$wished'.trim(), where: 'your vision board');
      await saving;
    }
    title.dispose();
    wish.dispose();
  }
}

/// The back of a picture: its WOOP, a photo to add or change, and one tap to say something was done for it.
class PictureSheet extends StatefulWidget {
  const PictureSheet({super.key, required this.picture, this.pick = _pickWithPicker});
  final Picture picture;
  final PickPhoto pick;
  @override
  State<PictureSheet> createState() => _PictureSheetState();
}

class _PictureSheetState extends State<PictureSheet> {
  String? _message;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = widget.picture;
    final t = Theme.of(context).textTheme;
    Widget line(String label, String text) => text.isEmpty ? const SizedBox.shrink() : Padding(
        padding: const EdgeInsets.only(top: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(text),
        ]));
    return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _photoOrWords(context, p, height: 180),
      const SizedBox(height: 12),
      Text(p.title, style: t.headlineSmall),
      if (p.quote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
          child: Text('"${p.quote}"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic))),
      line('Wish', p.wish),
      line('The best outcome', p.outcome),
      line('What could get in the way', p.obstacle),
      line('The plan', p.plan),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(key: const Key('picture_did'), onPressed: () async {
          p.lastAction = isoDate(state.clock());
          await state.save();
          if (mounted) setState(() => _message = 'Noted. One step closer.');
        }, child: const Text('I did something for this')),
        OutlinedButton.icon(key: const Key('picture_photo'), onPressed: () async {
          // no new pictures when Solace's own room is full (core/storage.dart; the device's space is never read)
          if (!mayAddPicture(state.vault.savedBytes, state.pictureBytes)) {
            if (mounted) {
              setState(() => _message = 'Solace\'s own space is full, so there is no room for another picture just '
                  'now. Settings > Space Solace uses shows how to make room.');
            }
            return;
          }
          String? photo;
          try {
            final bytes = await widget.pick();
            if (bytes == null) return;
            photo = await shrinkPhoto(bytes);
          } catch (_) {
            photo = null; // a picker or file error: the same plain message (F-17)
          }
          if (photo == null) {
            if (mounted) {
              setState(() => _message = 'That file could not be read as a photo, or it is very large. Try a smaller '
                  'photo.');
            }
            return;
          }
          try {
            await state.setPicture(p.title, base64Decode(photo)); // its own encrypted file (core/store.dart putMedia)
          } on NotSaved {
            // round 6 review, E-01: on the board for now, but the device still holds the board as it was
            if (mounted) {
              setState(() => _message = 'The photo is on your board, but it could not be saved yet, so it could be '
                  'gone when Solace next opens. The device may be full. Free some space, then tap Try again at the '
                  'top.');
            }
            return;
          } catch (_) {
            // the picture's own file could not be written (the device may be full): said plainly (H19-14)
            if (mounted) {
              setState(() => _message = 'The photo could not be saved on this device, so it was not added. The '
                  'device may be full. Free some space, then try again.');
            }
            return;
          }
          if (mounted) setState(() => _message = 'Photo added. It stays on this device, encrypted.');
        }, icon: const Icon(Icons.photo_outlined),
            label: Text(state.data.photos.containsKey(p.title) ? 'Change the photo' : 'Add a photo')),
        TextButton(onPressed: () async {
          state.data.plans.pictures.remove(p);
          try {
            await state.deletePicture(p.title);
          } on NotSaved {
            // round 6 review, E-01: removed here, but the device still holds it until a save works
            if (context.mounted) {
              sayNotSaved(context, 'Removed here, but this could not be saved yet, so it could come back when Solace '
                  'next opens. The device may be full. Free some space, then tap Try again at the top.');
            }
          }
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('Remove')),
      ]),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_message!, style: t.bodySmall)),
    ])));
  }
}

/// Mornings on Today: one picture, a different one each day, with its plan (PLAN 13).
class VisionMorningCard extends StatelessWidget {
  const VisionMorningCard({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final now = state.clock();
    final pictures = state.data.plans.pictures;
    if (now.hour >= 12 || pictures.isEmpty) return const SizedBox.shrink();
    final p = pictures[now.difference(DateTime(2026)).inDays % pictures.length];
    final t = Theme.of(context).textTheme;
    return Padding(padding: const EdgeInsets.only(top: 12), child: Card(child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showModalBottomSheet(context: context, isScrollControlled: true,
            sheetAnimationStyle: calmSheet(context), builder: (_) => PictureSheet(picture: p)),
        child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          SizedBox(width: 72, height: 72, child: _photoOrWords(context, p, height: 72)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, style: t.titleSmall),
            Text(p.plan.isNotEmpty ? p.plan : p.wish, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
          ])),
        ])))));
  }
}

/// A picture from its encrypted file, decoded at card size; a plain tile while it loads or if it cannot be read
/// (F-14: a damaged picture never breaks the screen).
class _PictureView extends StatefulWidget {
  const _PictureView({required this.title});
  final String title;
  @override
  State<_PictureView> createState() => _PictureViewState();
}

class _PictureViewState extends State<_PictureView> {
  Future<Uint8List?>? _bytes;
  String? _ref;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final ref = state.data.photos[widget.title];
    if (ref != _ref) {
      _ref = ref;
      _bytes = state.picture(widget.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = DecoratedBox(decoration: BoxDecoration(color: scheme.primaryContainer));
    return FutureBuilder<Uint8List?>(future: _bytes, builder: (context, snap) {
      final b = snap.data;
      if (b == null || !pictureFits(b)) return tile; // never decode a picture too large to draw (OW-M4-1)
      return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: photoWidth,
          errorBuilder: (_, _, _) => tile);
    });
  }
}
