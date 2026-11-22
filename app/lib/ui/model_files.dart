// Adding Solace's model, voice and safety files (owner, 2026-11-16: the button sat inside Settings, inside the profile,
// "just too complicated"; and tracker MM-01: a 5.7 GB copy showed nothing for two or three minutes on an Intel Mac,
// so a second tap started a second import over the first). One way in, used from three places: Today's card when no
// model is in place, the first-run step, and Settings > Model, voice and safety files. One import runs at a time
// (AppState.imports), the button is off while it runs, each step is said as it happens, and leaving the screen never
// stops it: the outcome is kept and shown when the person comes back. The import itself is core/model_import.dart.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../core/app_files.dart';
import '../core/llama_model.dart' show ModelFile;
import '../core/load_guard.dart';
import '../core/media.dart' show readSpace;
import '../core/model.dart' show StandInModel;
import '../core/model_import.dart';
import '../core/review.dart' show monthName;
import '../core/session.dart' show classifierFaultStatus;
import '../core/store.dart' show AcceptedModel;
import '../main.dart' show loadSafetyClassifier, loadTrainedModel, loadVoice, tryLoadAgain, tryStandardAgain;
import 'desktop.dart' show appNavigatorKey;
import 'premium.dart';

/// A file the person picked: its name, its size, its path when the platform gives one, and a way to read it.
typedef PickedFile = ({String name, int size, String? path, Stream<List<int>> Function() open});

/// The device's side of adding files: the picker, the folders, the free space, and what loads afterwards. Tests
/// replace it ([deviceFiles]); the app uses [DeviceFilesIO.real].
class DeviceFilesIO {
  const DeviceFilesIO({required this.pick, required this.clearPicked, required this.files, required this.support,
      required this.space, required this.afterModel, required this.afterBundle, this.confirmUnsigned});

  final Future<List<PickedFile>> Function() pick;
  final Future<void> Function() clearPicked; // the picker's own copies (Android keeps every picked file; OW-M9-2)
  final Future<Directory> Function() files; // the app's private files folder (PLAT-1)
  final Future<Directory> Function() support;
  final Future<(int, int)?> Function() space; // (total, free) bytes, when the platform says
  final Future<void> Function(AppState state) afterModel; // a model was copied: check and load it
  final Future<void> Function(AppState state) afterBundle; // voice and safety files were added: load them
  /// Asks the person about a model the maker did not sign (1.3.0); null: the warning on screen, [askUnsignedModel].
  final Future<bool> Function(UnsignedModel model)? confirmUnsigned;

  static final real = DeviceFilesIO(
    pick: () async => [
      for (final f in await FilePicker.pickFiles(dialogTitle: 'Pick the .gguf model with its .sha256 list, '
          'solace-models.json and its .sig, or the .zip voice and safety bundle'))
        (name: f.name, size: await f.xFile.length(), path: f.path, open: f.xFile.openRead),
    ],
    clearPicked: FilePicker.clearTemporaryFiles,
    files: appFiles,
    support: getApplicationSupportDirectory,
    space: readSpace,
    afterModel: loadTrainedModel,
    afterBundle: (state) async {
      await loadVoice(state);
      await loadSafetyClassifier(state);
    },
  );
}

/// What adding files uses on this device; replaced in tests.
@visibleForTesting
DeviceFilesIO deviceFiles = DeviceFilesIO.real;

/// Said when the device has too little room for the picked files (owner, 2026-11-14: never fill the device). The one
/// place Solace still reads the device's free space, silently and only before a copy, so it never stops half-way; it
/// says no numbers about the device (owner, 2026-11-19: the device's space is private).
const notEnoughSpace = "There isn't enough free space to add this file.";

/// Lets the person pick the model, voice or safety files and copies them in, unless an import is already running (then
/// nothing happens: the button that called this is off meanwhile). Each step shows wherever a [ModelFilesPanel] is,
/// and the outcome stays in [AppState.imports] after the screen that started it has gone; if none is showing it then,
/// it is said at the foot of whatever screen is open. A model copied is checked and loaded, voice and safety files are
/// loaded, by the app itself, not by the screen.
Future<void> addDeviceFiles(AppState state) async {
  final io = deviceFiles;
  var copied = false, added = false;
  final said = await state.imports.run((report) async {
    final picked = await io.pick();
    if (picked.isEmpty) return null; // cancelled: nothing to say
    try {
      // room first: never fill the device; a gigabyte stays free beyond the copy
      final need = picked.fold<int>(0, (n, f) => n + f.size);
      final space = await io.space();
      if (space != null && space.$2 < need * 2 + 1024 * 1024 * 1024) return notEnoughSpace;
      final files = await io.files(); // private to the app, not the Files app's Documents (PLAT-1)
      final zips = [for (final f in picked) if (f.name.endsWith('.zip')) f];
      final rest = [for (final f in picked) if (!f.name.endsWith('.zip')) f];
      if (zips.length > 1) return 'Pick one voice and safety bundle (.zip) at a time, so nothing was added.';
      final lines = <String>[];
      // the bundle and the model may be picked together: the bundle first, then the model
      if (zips case [final zip]) {
        // a picker that gives no path: the copy goes in Solace's private folder as a part file of its own, removed
        // after the import or at the next start (round 4 review, A-15; MM-01)
        File? copy;
        try {
          final path = zip.path ?? await copyToFile(zip.open(), copy = bundleCopyIn(files));
          final msg = await importBundle(path, files, progress: report);
          added = msg.startsWith('Added');
          lines.add(msg);
        } finally {
          if (copy != null && await copy.exists()) await copy.delete();
        }
      }
      if (zips.isEmpty || rest.isNotEmpty) {
        final support = await io.support();
        final msg = await importModelFiles([for (final f in rest) (f.name, f.open())], files,
            checkCache: File('${support.path}/model_check.txt'), sizes: {for (final f in rest) f.name: f.size},
            progress: report, accepted: state.acceptedModels,
            // a model the maker did not sign (1.3.0): the warning, and the person's yes kept before it is used
            confirmUnsigned: (m) async => await (io.confirmUnsigned ?? askUnsignedModel)(m) &&
                await state.acceptModel(m.sha256, m.name, m.size ?? 0));
        copied = msg.startsWith('Copied');
        lines.add(msg);
      }
      return lines.join(' ');
    } finally {
      try {
        await io.clearPicked();
      } catch (_) {}
    }
  });
  if (said == null) return; // already running, or cancelled
  // said at the foot of the screen when no panel shows it, or when the panel on Today goes with the copied model
  if (ModelFilesPanel._showing == 0 || copied) {
    final at = appNavigatorKey.currentContext;
    if (at != null && at.mounted) {
      ScaffoldMessenger.maybeOf(at)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(key: const Key('import_said'), content: Text(said)));
    }
  }
  // loaded by the app, whatever screen is open now
  if (copied) {
    state.reportModelInPlace(true);
    await io.afterModel(state);
  }
  if (added) await io.afterBundle(state);
}

/// The button and what is happening: off while an import runs, with each step ("Copying the model… 42%", then
/// "Checking the model… (about a minute)"), then the outcome. The same on Today, in the first-run steps and in
/// Settings.
class ModelFilesPanel extends StatefulWidget {
  const ModelFilesPanel({super.key, this.prominent = false});

  /// The main thing on its card (Today, the first-run step): a filled button; in Settings, a quieter one.
  final bool prominent;

  /// How many panels are on screen: when none is, the outcome is said at the foot of the screen instead.
  static int _showing = 0;

  @override
  State<ModelFilesPanel> createState() => _ModelFilesPanelState();
}

class _ModelFilesPanelState extends State<ModelFilesPanel> {
  @override
  void initState() {
    super.initState();
    ModelFilesPanel._showing++;
  }

  @override
  void dispose() {
    ModelFilesPanel._showing--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final imports = state.imports;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(listenable: imports, builder: (context, _) {
      final running = imports.running;
      final step = imports.step;
      const label = Text('Add files');
      const icon = Icon(Icons.file_open_outlined, size: 18);
      final press = running ? null : () => unawaited(addDeviceFiles(state));
      final button = widget.prominent
          ? FilledButton.icon(key: const Key('add_device_files'), onPressed: press, icon: icon, label: label)
          : FilledButton.tonalIcon(key: const Key('add_device_files'), onPressed: press, icon: icon, label: label);
      final percent = step?.percent;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: AlignmentDirectional.centerStart, child: button),
        if (running) Padding(key: const Key('import_progress'), padding: const EdgeInsets.only(top: Space.m),
            child: Semantics(liveRegion: true, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // still marks, never an endless animation (it would keep the screen busy for minutes)
                Icon(step?.stage == ImportStage.copying ? Icons.downloading_rounded : Icons.hourglass_empty_rounded,
                    size: 18, color: scheme.primary),
                const SizedBox(width: Space.s),
                Expanded(child: Text(step?.words ?? 'Choose the files to add.', key: const Key('import_step'),
                    style: t.bodyMedium)),
              ]),
              if (percent != null) Padding(padding: const EdgeInsets.only(top: Space.s),
                  child: LinearProgressIndicator(value: percent / 100, minHeight: 6,
                      borderRadius: BorderRadius.circular(3))),
              if (step != null) Padding(padding: const EdgeInsets.only(top: Space.xs),
                  child: Text('You can leave this screen. Solace carries on and shows the result here.',
                      style: t.bodySmall)),
            ]))),
        if (!running && imports.result != null) Padding(padding: const EdgeInsets.only(top: Space.s),
            child: Text(imports.result!, key: const Key('import_result'), style: t.bodyMedium)),
      ]);
    });
  }
}

/// Today's card while no trained model is in place: what to add, in one sentence, and the button.
class ModelFilesCard extends StatelessWidget {
  const ModelFilesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.modelInPlace != false) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: Space.m), child: Card(key: const Key('model_files_card'),
        margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        CircleAvatar(radius: 18, backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.download_for_offline_outlined, size: 20, color: scheme.onPrimaryContainer)),
        const SizedBox(width: Space.m),
        Expanded(child: Text("Add Solace's model files", style: t.titleMedium)),
      ]),
      const SizedBox(height: Space.s),
      // short and scannable (design review, 2026-11-16): what happens meanwhile, then what to pick, quieter
      Text('Until then, a simple stand-in answers.', style: t.bodyMedium),
      const SizedBox(height: Space.xs),
      Text(filesToPick, style: t.bodySmall),
      const SizedBox(height: Space.m),
      const ModelFilesPanel(prominent: true),
    ]))));
  }
}

/// What to pick, in one short line (Today's card, Settings and the first-run step, while a file is not added yet).
const filesToPick = 'Pick the .gguf model file with its .sha256 list, and the .zip voice and safety bundle.';

/// Where one of Solace's files is: ready, getting ready, not added yet, turned off, or not loaded (with why).
enum FileState {
  ready('Ready', Icons.check_circle_rounded),
  loading('Getting ready', Icons.hourglass_top_rounded),
  missing('Not added', Icons.add_circle_outline_rounded),
  off('Off', Icons.toggle_off_outlined),
  notLoaded('Not loaded', Icons.error_outline_rounded);

  const FileState(this.word, this.icon);
  final String word;
  final IconData icon;
}

/// One of Solace's files as the person sees it: its name, where it is, and one short plain sentence.
typedef FileLine = ({Engine engine, String name, IconData icon, FileState state, String words});

/// The model's line, from what the app knows: loaded or not, its file there or not, and what its load last said.
FileLine modelLine(AppState s) {
  final status = s.modelStatus;
  final stop = s.stoppedLoads[Engine.model];
  final (FileState, String) at = s.model is! StandInModel || status.startsWith('Ready')
      ? (FileState.ready, 'Solace answers with it, on this device.')
      : s.slowLoads.contains(Engine.model)
          ? (FileState.loading, 'Taking much longer than usual. The stand-in answers meanwhile.')
          : status.startsWith('Checking ') || status.startsWith('Loading ')
              ? (FileState.loading, 'Checking and loading it. The first time takes a minute.')
              : stop != null
                  ? (FileState.notLoaded, stop.noMarker
                      ? 'Not loaded this time. This device may be full. The stand-in answers.'
                      : 'Solace stopped while loading it, perhaps for lack of memory. The stand-in answers.')
                  : s.modelInPlace == false || status == noModelStatus
                      ? (s.modelInPlace == true
                          ? (FileState.loading, 'Getting it ready. The stand-in answers meanwhile.')
                          : (FileState.missing, 'Solace answers with it. Until then, a simple stand-in answers.'))
                      : status.contains('does not match its checksum')
                          ? (FileState.notLoaded, 'This copy did not pass its check. Copy the file again.')
                          : status.startsWith('This device does not have enough memory')
                              ? (FileState.notLoaded, 'This device does not have enough memory for it.')
                              : (FileState.notLoaded, status);
  return (engine: Engine.model, name: 'The model', icon: Icons.psychology_outlined, state: at.$1, words: at.$2);
}

/// The voice's line.
FileLine voiceLine(AppState s) {
  final status = s.voiceStatus;
  final stop = s.stoppedLoads[Engine.voice];
  final (FileState, String) at = s.voice.available
      ? (FileState.ready, 'Solace speaks and writes down what you say, on this device.')
      : s.slowLoads.contains(Engine.voice)
          ? (FileState.loading, 'Taking much longer than usual. Sessions work by text meanwhile.')
          : status.contains('Checking the voice') || status.endsWith('ready.')
              ? (FileState.loading, 'Checking and loading it.')
              : stop != null
                  ? (FileState.notLoaded, stop.noMarker
                      ? 'Not loaded this time. This device may be full. Sessions work by text.'
                      : 'Solace stopped while loading it, so it was not loaded. Sessions work by text.')
                  : status == noVoiceStatus
                      ? (FileState.missing, 'Solace speaks with it. Until then, sessions work by text.')
                      : (FileState.notLoaded, _plain(status, 'Voice: '));
  return (engine: Engine.voice, name: 'The voice', icon: Icons.record_voice_over_outlined, state: at.$1, words: at.$2);
}

/// The safety check's line (the trained classifier; the phrase rules always run).
FileLine safetyLine(AppState s) {
  final status = s.safetyStatus;
  final stop = s.stoppedLoads[Engine.classifier];
  final (FileState, String) at = !s.data.settings.classifierOn
      ? (FileState.off, 'Turned off. The phrase rules still check every message.')
      : s.riskCheck != null
          ? (FileState.ready, 'It and the phrase rules check every message.')
          : s.slowLoads.contains(Engine.classifier)
              ? (FileState.loading, 'Taking much longer than usual. The phrase rules check every message meanwhile.')
              : status.contains('Checking the safety') || status.endsWith('ready.')
                  ? (FileState.loading, 'Checking and loading it. The phrase rules check every message meanwhile.')
                  : stop != null
                      ? (FileState.notLoaded, 'Solace stopped while loading it, so it was not loaded. The phrase '
                          'rules check every message.')
                      : status == classifierMissingStatus
                          ? (FileState.missing, 'A trained check of each message. Until then, the phrase rules '
                              'check every message.')
                          : status == classifierFaultStatus
                              ? (FileState.notLoaded, 'It stopped working on a message. The phrase rules check every '
                                  'message.')
                              : (FileState.notLoaded, _plain(status, 'Safety: '));
  return (engine: Engine.classifier, name: 'The safety check', icon: Icons.health_and_safety_outlined, state: at.$1,
      words: at.$2);
}

/// [status] without its [prefix], starting with a capital.
String _plain(String status, String prefix) {
  final rest = status.startsWith(prefix) ? status.substring(prefix.length) : status;
  return rest.isEmpty ? rest : rest[0].toUpperCase() + rest.substring(1);
}

/// Solace's three files at a glance (owner, 2026-11-16: the status was "a dense block of text"): each on its own line
/// with a clear state and one short plain sentence, a way to try again under any that stopped Solace while loading,
/// and the full words on demand (Details). In Settings, and on the first-run step for the files.
class FilesStatus extends StatefulWidget {
  const FilesStatus({super.key, this.details = true});

  /// Whether the full words can be shown (Settings); the first-run step shows the lines alone.
  final bool details;

  @override
  State<FilesStatus> createState() => _FilesStatusState();
}

class _FilesStatusState extends State<FilesStatus> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lines = [modelLine(state), voiceLine(state), safetyLine(state)];
    Widget again(String key, String label, VoidCallback onPressed) => TextButton(key: Key(key), onPressed: onPressed,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.s)), child: Text(label));
    // the ways to try again, under the file they are for (round 9 review, 9B-04)
    List<Widget> actions(Engine e) => [
          if (e == Engine.model) ...[
            if (state.stoppedLoads[Engine.model] case final stop?) ...[
              again('try_load_model', 'Try again', () => tryLoadAgain(state, Engine.model)),
              if (stop.light != null)
                again('use_light_model', 'Use the Light model', () => tryLoadAgain(state, Engine.model, light: true)),
            ],
            if (state.lightChosen)
              again('try_standard_model', 'Try the Standard model again', () => tryStandardAgain(state)),
          ],
          if (e == Engine.voice && state.stoppedLoads.containsKey(Engine.voice))
            again('try_load_voice', 'Try the voice again', () => tryLoadAgain(state, Engine.voice)),
          if (e == Engine.classifier && state.stoppedLoads.containsKey(Engine.classifier))
            again('try_load_classifier', 'Try the safety check again', () => tryLoadAgain(state, Engine.classifier)),
        ];
    final quiet = t.bodySmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final (i, line) in lines.indexed) ...[
        if (i > 0) const Divider(height: Space.l),
        _FileRow(line: line, key: Key('file_${line.engine.name}')),
        // signed models: the kept model list failed its check at this start (core/model_manifest.dart)
        if (line.engine == Engine.model && state.modelListNote != null)
          Padding(padding: const EdgeInsets.only(left: _FileRow.indent, top: Space.xs),
              child: Text(state.modelListNote!, key: const Key('model_list_note'), style: quiet)),
        // a model the maker did not sign, which the person chose (1.3.0): said here, with the way back
        if (state.modelAccepted case final chosen? when line.engine == Engine.model) ...[
          Padding(padding: const EdgeInsets.only(left: _FileRow.indent, top: Space.xs),
              child: Text(unsignedInUse(chosen), key: const Key('model_unsigned_note'), style: quiet)),
          Padding(padding: const EdgeInsets.only(left: _FileRow.indent - Space.s),
              child: Align(alignment: AlignmentDirectional.centerStart, child: TextButton(
                  key: const Key('stop_unsigned_model'), onPressed: () => stopUsingUnsignedModel(state),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.s)),
                  child: const Text('Stop using it')))),
        ],
        if (actions(line.engine) case final buttons when buttons.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: _FileRow.indent - Space.s),
              child: Wrap(spacing: Space.xs, children: buttons)),
      ],
      // what to pick, while any is not added yet
      if (lines.any((l) => l.state == FileState.missing))
        // its own node, so a screen reader (and the contrast check) reads it apart from the card around it
        Padding(padding: const EdgeInsets.only(top: Space.m),
            child: Semantics(container: true, child: Text(filesToPick,
                style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)))),
      if (widget.details) ...[
        const SizedBox(height: Space.s),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('files_details'),
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.s)),
            icon: AnimatedRotation(turns: _open ? 0.5 : 0, duration: Calm.of(context, Calm.quick), curve: Calm.curve,
                child: const Icon(Icons.expand_more_rounded, size: 20)),
            label: Text(_open ? 'Hide details' : 'Details'))),
        AnimatedSize(duration: Calm.of(context, Calm.normal), curve: Calm.curve, alignment: Alignment.topCenter,
            child: !_open ? const SizedBox(width: double.infinity) : Container(
              key: const Key('files_details_text'),
              margin: const EdgeInsets.only(top: Space.xs),
              padding: const EdgeInsets.all(Space.m),
              decoration: ShapeDecoration(color: scheme.surfaceContainer, shape: smoothShape(Radii.small)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Model: ${state.model.name}', style: t.labelLarge),
                Text(state.modelStatus, key: const Key('model_status'), style: quiet),
                const SizedBox(height: Space.s),
                Text(state.voiceStatus, style: quiet),
                const SizedBox(height: Space.s),
                Text(state.safetyStatus, style: quiet),
                const SizedBox(height: Space.s),
                Text('They stay in Solace\'s private folder on this device. Nothing is downloaded.', style: quiet),
              ]),
            )),
      ],
    ]);
  }
}

/// One file: its icon, its name, its state as a small tag, and the sentence under them.
class _FileRow extends StatelessWidget {
  const _FileRow({super.key, required this.line});
  final FileLine line;

  /// Where the words start, after the icon: notes and buttons under a row line up with them.
  static const indent = 36.0 + Space.m;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (line.state) {
      FileState.ready => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      FileState.loading => (scheme.primaryContainer, scheme.onPrimaryContainer),
      FileState.notLoaded => (scheme.errorContainer, scheme.onErrorContainer),
      FileState.missing || FileState.off => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    final tag = Container(
      padding: const EdgeInsets.fromLTRB(Space.s, 3, Space.s + 2, 3),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(line.state.icon, size: 14, color: fg),
        const SizedBox(width: Space.xs),
        Flexible(child: Text(line.state.word, style: t.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700))),
      ]),
    );
    return MergeSemantics(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      IconDisc(line.icon, size: 36, quiet: line.state != FileState.ready),
      const SizedBox(width: Space.m),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // the name and its state on one line; the state goes under the name when there is no room beside it
        Wrap(spacing: Space.s, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(line.name, style: t.titleSmall),
          tag,
        ]),
        const SizedBox(height: 2),
        Text(line.words, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      ])),
    ]));
  }
}

// ---- 1.3.0 (owner, 2026-11-17): a model the maker of Solace did not sign ----

/// What Settings says under the model while it is one the maker did not sign.
String unsignedInUse(AcceptedModel chosen) => 'Not from the maker of Solace. You chose to use ${chosen.name} on '
    '${_day(chosen.date)}. Solace\'s own safety check still reads every message.';

String _day(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${monthName(d.month)} ${d.year}';
}

/// "5.7 GB", "820 MB": a size for people.
String _size(int? bytes) {
  if (bytes == null || bytes <= 0) return 'size unknown';
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  return '${(bytes / (1 << 20)).round()} MB';
}

/// The warning before a model the maker did not sign is used (1.3.0): who made it cannot be known, what that means,
/// that Solace's own safety check still runs, the recommendation to use the original signed files, and that file's
/// SHA-256. Nothing is used unless the person ticks that they understand and presses Use this model; Cancel, Escape or
/// closing it means no. False when no screen can show it.
Future<bool> askUnsignedModel(UnsignedModel m) async {
  final context = appNavigatorKey.currentContext;
  if (context == null || !context.mounted) return false;
  final chosen = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (context) => _UnsignedModelDialog(model: m));
  return chosen == true;
}

class _UnsignedModelDialog extends StatefulWidget {
  const _UnsignedModelDialog({required this.model});
  final UnsignedModel model;
  @override
  State<_UnsignedModelDialog> createState() => _UnsignedModelDialogState();
}

class _UnsignedModelDialogState extends State<_UnsignedModelDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final m = widget.model;
    Widget point(String text) => Padding(padding: const EdgeInsets.only(top: Space.s), child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 7, right: Space.s),
          child: Icon(Icons.circle, size: 6, color: scheme.onSurfaceVariant)),
      Expanded(child: Text(text, style: t.bodyMedium)),
    ]));
    final sum = m.sha256;
    return AlertDialog(key: const Key('unsigned_dialog'),
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
        title: const Text('Use a model that is not from Solace\'s maker?'),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Widths.form), child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${m.name} (${_size(m.size)}) is not signed by the maker of Solace, so Solace cannot tell who made it '
              'or what it was trained to say.', style: t.bodyMedium),
          point('It has not been tested with Solace. Its answers may be wrong, unkind or unsafe, and it may not follow '
              'the way Solace talks with you.'),
          point('Solace\'s own safety check still reads every message, and Support stays one tap away.'),
          point('The original model files signed by the maker of Solace are the safer choice. If you are going '
              'through a hard time, use those.'),
          const SizedBox(height: Space.m),
          Text('Use it only if you trust where this file came from.', style: t.titleSmall),
          const SizedBox(height: Space.s),
          // the file's checksum, selectable with the system's text menu (owner, 2026-11-19)
          SelectableText('Checksum (SHA-256): ${sum.substring(0, 16)}…${sum.substring(48)}',
              key: const Key('unsigned_checksum'),
              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: Space.s),
          CheckboxListTile(key: const Key('unsigned_understand'), value: _understood, contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _understood = v ?? false),
              title: const Text('I understand the risks and choose to use this file')),
        ]))),
        actions: [
          TextButton(key: const Key('unsigned_cancel'), autofocus: true,
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('unsigned_use'), onPressed: _understood ? () => Navigator.pop(context, true) : null,
              child: const Text('Use this model')),
        ]);
  }
}

/// Settings > Stop using it (1.3.0): after a yes, the choice is forgotten, the model is let go and its files removed
/// from this device, and whatever trusted model is left is loaded (otherwise the stand-in answers until the original
/// files are added again).
Future<void> stopUsingUnsignedModel(AppState state) async {
  final context = appNavigatorKey.currentContext;
  final sha = state.modelSha;
  if (context == null || !context.mounted || sha == null) return;
  final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      key: const Key('stop_unsigned_dialog'),
      title: const Text('Stop using this model?'),
      content: const Text('Solace removes it from this device. Until you add the original model files again, a simple '
          'stand-in answers. Your sessions and notes stay as they are.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const Key('stop_unsigned_confirm'), onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop using it')),
      ]));
  if (yes != true) return;
  String said;
  if (!await state.forgetAcceptedModel(sha)) {
    said = 'Solace could not save that change, so the model is still in use. Try again.';
  } else {
    await state.letGoOfModel();
    final io = deviceFiles;
    final dir = await io.files();
    for (final name in ['model-standard', 'model-light']) {
      final list = File('${dir.path}/$name.sha256');
      try {
        if (await list.exists() && (await list.readAsString()).contains(sha)) {
          final model = File('${dir.path}/$name.gguf');
          if (await model.exists()) await model.delete();
          await list.delete();
        }
      } catch (_) {}
    }
    state.reportModelInPlace(await ModelFile.find(dir, accepted: state.acceptedModels) != null);
    await io.afterModel(state);
    said = 'Solace stopped using that model and removed it from this device.';
  }
  final at = appNavigatorKey.currentContext;
  if (at != null && at.mounted) {
    ScaffoldMessenger.maybeOf(at)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: const Key('stop_unsigned_said'), content: Text(said)));
  }
}

