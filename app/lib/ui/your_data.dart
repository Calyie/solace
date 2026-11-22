// Your data (report recommendation 23): a summary for a clinician (PDF), and the person's records as a spreadsheet
// (CSV) or a plain-text page (Markdown). Notes go in only when ticked. Each file is saved where the person chooses
// with the system's save dialog (file_picker writes the bytes on iOS, Android, macOS, Linux and Windows); where no
// save dialog is available, it goes into the app's documents folder and the screen says where. Every way out says
// plainly that a saved file is outside Solace's encryption.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/clinician_pdf.dart';
import '../core/dates.dart';
import '../core/exports.dart';
import 'app_lock.dart' show confirmItIsYou;
import 'premium.dart';
import 'words.dart';

/// Saves a file the person makes; returns what to tell them (where it went), or null when they cancelled.
typedef SaveExport = Future<String?> Function(String fileName, Uint8List bytes, String mimeType);

Future<String?> saveWithDialog(String name, Uint8List bytes, String mime) async {
  try {
    final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime, dialogTitle: 'Save $name');
    return uri == null ? null : 'Saved as $name.';
  } catch (_) {
    // no save dialog here (a Linux desktop without its file portal, for example): nothing is written anywhere the
    // person did not choose (OWASP review OW-M8-1: a plain copy in Documents would sit outside the encryption)
    throw StateError('no save dialog');
  } finally {
    await clearPickerCopies();
  }
}

/// The picker's own plain copies (round 4 review, A-04): on the iPhone, a file being saved is first written to the
/// app's temporary folder for the export sheet, and stays there whether the person saves or cancels. The sheet has made
/// its copy by the time the save returns.
Future<void> clearPickerCopies() async {
  try {
    await FilePicker.clearTemporaryFiles();
  } catch (_) {} // a platform with nothing to clear
}

/// The way into Your data from the Progress tab.
class YourDataCard extends StatelessWidget {
  const YourDataCard({super.key});
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: Space.m), child: ListTile(
      key: const Key('open_your_data'),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
      leading: const Icon(Icons.folder_shared_outlined), title: const Text('Your data'),
      subtitle: const Text('A summary for a clinician, or your records as a spreadsheet or text file'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YourDataScreen()))));
}

class YourDataScreen extends StatefulWidget {
  const YourDataScreen({super.key, this.save = saveWithDialog});
  final SaveExport save;
  @override
  State<YourDataScreen> createState() => _YourDataScreenState();
}

class _YourDataScreenState extends State<YourDataScreen> {
  final _ticked = <String>{};
  bool _busy = false, _allNotes = false;
  bool _asking = false; // the lock's own unlock is being asked for: the buttons wait, no progress is shown yet
  String? _message;

  Future<void> _export(String what) async {
    final state = AppScope.of(context);
    final accent = Theme.of(context).colorScheme.primary.toARGB32();
    final bundle = DefaultAssetBundle.of(context);
    setState(() {
      _busy = _asking = true;
      _message = null;
    });
    // round 9 re-check, 9A-02: a saved file is outside Solace's encryption, so, as for Send everything, the lock's own
    // unlock is asked again before anything is made (anyone holding the unlocked app could carry the records away);
    // Cancel or a wrong passcode makes nothing. Every way here (Settings, Progress, Private by design, Space Solace
    // uses) is this screen.
    final sure = await confirmItIsYou(context, state, what: switch (what) {
      'pdf' => 'make the summary for a clinician',
      'csv' => 'make a spreadsheet of your records',
      _ => 'make a text file of your records',
    });
    if (!mounted) return;
    setState(() {
      _asking = false;
      _busy = sure;
    });
    if (!sure) return;
    String? said;
    try {
      final now = state.clock(), day = isoDate(now);
      final (name, bytes, mime) = switch (what) {
        'pdf' => ('wellbeing-summary-$day.pdf', await clinicianPdf(state.data, now, notes: _ticked,
            regular: await _font(bundle, 'assets/fonts/Figtree-Regular.ttf'),
            bold: await _font(bundle, 'assets/fonts/Figtree-Bold.ttf'), accent: accent), 'application/pdf'),
        'csv' => ('my-records-$day.csv', Uint8List.fromList(utf8.encode(exportCsv(state.data, notes: _ticked))),
            'text/csv'),
        _ => ('my-records-$day.md', Uint8List.fromList(utf8.encode(exportMarkdown(state.data, now, notes: _ticked))),
            'text/markdown'),
      };
      said = await widget.save(name, bytes, mime);
      said = said == null ? 'Not saved. Nothing has left Solace.'
          : '$said It is outside Solace\'s encryption now, so keep it somewhere private.';
      if (said.startsWith('Saved')) feelDone();
    } on StateError {
      said = 'This device offers no save dialog, so nothing was saved. Nothing has left Solace.';
    } catch (_) {
      said = 'The file could not be made or saved. Nothing has left Solace. Try again in a moment.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = said;
    });
  }

  static Future<ByteData?> _font(AssetBundle bundle, String path) async {
    try {
      return await bundle.load(path);
    } catch (_) {
      return null; // the PDF falls back to its own font
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final notes = exportNotes(state.data);
    final shown = _allNotes || notes.length <= 12 ? notes : notes.sublist(0, 12);
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Your data')),
      body: Readable(child: ListView(padding: const EdgeInsets.fromLTRB(20, Space.s, 20, Space.xxl), children: [
        Text('Your records belong to you. Make a file to keep, or to show someone you trust, such as your GP, a '
            'counsellor or a psychologist.', style: t.bodyMedium),
        const SizedBox(height: Space.l),
        Card(key: const Key('export_warning'), color: scheme.secondaryContainer, child: Padding(
            padding: const EdgeInsets.all(Space.l), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_open_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: Space.m),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('A saved file leaves Solace\'s encryption',
                style: t.titleSmall?.copyWith(color: scheme.onSecondaryContainer)),
            const SizedBox(height: Space.xs),
            Text('Inside Solace everything is locked with a key only this device holds. A saved file is not locked. '
                'Anyone who can open it can read it. Keep it somewhere private, and delete it when you no longer '
                'need it.', style: t.bodyMedium?.copyWith(color: scheme.onSecondaryContainer)),
          ])),
        ]))),
        const SectionHeader('For a clinician'),
        Card(child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('A PDF summary with:', style: t.bodyMedium),
          const SizedBox(height: Space.xs),
          Points(const ['Your PHQ-9 and GAD-7 answers, and PCL-5 if you have done it, with their bands and dates.',
              'A chart of your mood.', 'Your programme progress.', 'Only the notes you tick below.'],
              style: t.bodyMedium),
          const SizedBox(height: Space.m),
          FilledButton.icon(key: const Key('export_pdf'), onPressed: _busy ? null : () => _export('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Make the PDF')),
        ]))),
        SectionHeader('Notes to include', trailing: Text('None unless ticked', style: t.bodySmall)),
        if (notes.isEmpty)
          Text('No notes yet. The notes you add when you name a feeling, and your journal entries, can be included '
              'here.', style: t.bodyMedium)
        else
          Card(child: Column(children: [
            for (final n in shown)
              CheckboxListTile(key: Key('note_${n.id}'), value: _ticked.contains(n.id),
                  onChanged: (on) => setState(() => on == true ? _ticked.add(n.id) : _ticked.remove(n.id)),
                  title: Text(n.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${dayLabel(DateTime.parse(n.date))} · ${n.source}')),
            if (shown.length < notes.length)
              TextButton(onPressed: () => setState(() => _allNotes = true),
                  child: Text('Show all ${notes.length} notes')),
          ])),
        const SectionHeader('Your records as files'),
        Card(child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your moods, named feelings and questionnaire scores, with the notes you ticked. A spreadsheet opens '
              'in Numbers, Excel or LibreOffice. A text file opens anywhere.', style: t.bodyMedium),
          const SizedBox(height: Space.m),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            OutlinedButton.icon(key: const Key('export_csv'), onPressed: _busy ? null : () => _export('csv'),
                icon: const Icon(Icons.table_chart_outlined), label: const Text('Spreadsheet (CSV)')),
            OutlinedButton.icon(key: const Key('export_md'), onPressed: _busy ? null : () => _export('md'),
                icon: const Icon(Icons.description_outlined), label: const Text('Text file (Markdown)')),
          ]),
        ]))),
        if (_busy && !_asking) const Padding(padding: EdgeInsets.only(top: Space.l), child: LinearProgressIndicator()),
        AnimatedSwitcher(duration: Calm.normal, child: _message == null ? const SizedBox.shrink()
            : Padding(key: ValueKey(_message), padding: const EdgeInsets.only(top: Space.l),
                child: Text(_message!, key: const Key('export_message'), style: t.bodyMedium))),
      ])),
    );
  }
}
