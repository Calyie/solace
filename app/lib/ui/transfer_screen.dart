// Moving everything to another of the person's devices (TASKLIST B7; core/transfer.dart; PLAN section 11): one locked
// file, carried by AirDrop, a cable or Bluetooth, opened on the other device with a one-time code shown here. No
// network. The device's own mode never travels: each device keeps its own (owner, 2026-11-05; core/transfer.dart).
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/dates.dart';
import '../core/transfer.dart';
import 'app_lock.dart' show confirmItIsYou;
import 'crisis.dart' show SupportButton;
import 'desktop.dart' show OpenSession;
import 'premium.dart';
import 'words.dart';
import 'your_data.dart' show clearPickerCopies;

/// How long a transfer brought in, or Delete everything (ui/settings.dart), holds Back before letting it go (cycle 2
/// review, N2: the wait had no end, and the screen had no Support button). The work goes on after that, and no
/// conversation can start until it has finished (AppState.changingData), so leaving it changes nothing.
const longDataWait = Duration(minutes: 2);

/// Said when a transfer or Delete everything is asked for while one is still running (it may run on after Back).
const stillChangingData = 'Solace is still bringing in or deleting your data. Please wait until it has finished, then '
    'try again. Nothing else was changed.';

/// Said when a transfer was brought in but could not be saved on this device (round 6 review, E-01): only this run
/// holds it, so the transfer file is still needed.
const importNotSaved = 'Brought in, but not saved on this device yet. The device could not write it, and may be full. '
    'Keep the transfer file. Free some space, then tap Try again at the top. Once that warning has gone, everything is '
    'saved and you can delete the file. If Solace closes before then, this device opens with what it had before.';

/// Saves the file where the person chooses (the system's save dialog); true when it was saved.
typedef SaveBytes = Future<bool> Function(String fileName, Uint8List bytes);

/// The transfer file the person picks, or null when they cancel.
typedef PickBytes = Future<PickedTransfer?> Function();

Future<bool> _saveWithPicker(String name, Uint8List bytes) async {
  try {
    return await FilePicker.saveFile(fileName: name, bytes: bytes, dialogTitle: 'Save the transfer file') != null;
  } finally {
    await clearPickerCopies(); // the iPhone's plain copy for the export sheet (round 4 review, A-04)
  }
}

Future<PickedTransfer?> _pickWithPicker() async {
  final picked = await FilePicker.pickFiles(dialogTitle: 'Pick the transfer file');
  if (picked.isEmpty) return null;
  // the size first, so picking a 5 GB model file by mistake cannot fill the memory (F-14)
  try {
    final file = picked.first.xFile;
    if (await file.length() > TransferFile.maxFileBytes) {
      throw TransferError('That file is too large to be a Solace transfer file. Pick the .mtx file made on the other '
          'device.');
    }
    // read on a worker, never through this screen's isolate (verification round 3, R3-6)
    return file.path.isNotEmpty ? await PickedTransfer.read(file.path) : PickedTransfer.fromBytes(await file.readAsBytes());
  } finally {
    try {
      await FilePicker.clearTemporaryFiles(); // the picker's own copy (OW-M9-2)
    } catch (_) {}
  }
}

class SendToDeviceScreen extends StatefulWidget {
  const SendToDeviceScreen({super.key, this.save = _saveWithPicker});
  final SaveBytes save;
  @override
  State<SendToDeviceScreen> createState() => _SendToDeviceScreenState();
}

class _SendToDeviceScreenState extends State<SendToDeviceScreen> {
  String? _code, _message;
  bool _busy = false;

  Future<void> _make() async {
    final state = AppScope.of(context);
    setState(() => _busy = true);
    // round 9 review, 9A-02: a file with everything, and its code, only after the lock's own unlock is asked again
    // (anyone holding the unlocked app could carry the whole of it away); Cancel makes nothing
    if (!await confirmItIsYou(context, state, what: 'make a file with everything') || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    setState(() => _message = 'Locking the file...');
    final code = TransferCode.generate();
    final name = 'solace-${isoDate(state.clock())}.mtx';
    var saved = false, failed = false;
    String? why;
    try {
      saved = await widget.save(name, await TransferFile.sealInBackground(await state.dataForTransfer(), code));
    } on TransferError catch (e) {
      failed = true;
      why = e.message;
    } catch (_) {
      failed = true; // never stuck on "Locking the file..." (F-17)
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _code = saved ? code : null; // the code only for a file that exists
      _message = saved ? 'Saved as $name. Move it to the other device, then type this code there.'
          : failed ? (why != null ? '$why Nothing has left Solace.'
              : 'The file could not be made or saved. Nothing has left Solace. Try again in a moment.')
          : 'The file was not saved. Try again when you are ready.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Send to another device')),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('This makes one locked file with your sessions, notes, plans, journal and settings.'),
        const SizedBox(height: Space.s),
        const Points(['Carry it by AirDrop, a cable or Bluetooth.',
            'It opens only with the code this screen shows, typed on the other device.',
            'Each device keeps its own private settings.']),
        const SizedBox(height: 20),
        if (_code == null)
          FilledButton.icon(key: const Key('transfer_make'), onPressed: _busy ? null : _make,
              icon: const Icon(Icons.lock_outline), label: const Text('Make the file'))
        else
          Card(color: scheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(20), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The code', style: t.titleMedium),
            const SizedBox(height: 8),
            // read and typed on the other device, never copied (round 4 review, A-11): a copied code sits on the shared
            // clipboard, often beside the saved file it opens. Kept out of the screen's selection when the rest of the
            // text became copyable (owner, 2026-11-19): it is a key, not something to read
            SelectionContainer.disabled(child: Text(TransferCode.show(_code!), key: const Key('transfer_code_shown'),
                style: t.headlineSmall?.copyWith(fontFamily: t.bodyMedium?.fontFamily, fontWeight: FontWeight.w700, letterSpacing: 2,
                    fontFeatures: const [FontFeature.tabularFigures()]))),
            const SizedBox(height: 8),
            const Text('It is shown only now. Without it the file cannot be opened, by anyone.'),
            const SizedBox(height: 4),
            // screenshots are allowed (owner, 2026-11-19); a screenshot of the code syncs to the photo library, often
            // in the same cloud as the file it opens (H19-16)
            const Text('Read it out or type it. Do not keep a screenshot of it: it can end up in your photo library '
                'beside the file.', key: Key('transfer_code_screenshot_hint')),
          ]))),
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!, style: t.bodySmall)],
      ])),
    );
  }
}

class ReceiveFromDeviceScreen extends StatefulWidget {
  const ReceiveFromDeviceScreen({super.key, this.pick = _pickWithPicker});
  final PickBytes pick;
  @override
  State<ReceiveFromDeviceScreen> createState() => _ReceiveFromDeviceScreenState();
}

class _ReceiveFromDeviceScreenState extends State<ReceiveFromDeviceScreen> {
  final _code = TextEditingController();
  PickedTransfer? _file;
  bool _confirm = false, _busy = false;
  bool _long = false; // bringing the file in has taken [longDataWait]: Back is let go (N2)
  Timer? _longTimer;
  String? _message;

  @override
  void dispose() {
    _longTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _replace() async {
    final state = AppScope.of(context);
    // round 9 re-check, 9A-02: replacing every conversation, note and picture asks for the lock's own unlock again
    // first, as Delete everything does; Cancel or a wrong passcode changes nothing
    setState(() {
      _busy = true; // one at a time, set before the first await
      _message = null;
    });
    final sure = await confirmItIsYou(context, state, what: 'replace everything on this device');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!sure) return;
    // a session still open on a computer holds the old data and would write it back over the import when ended
    // (verification round 2)
    if (OpenSession.count > 0) {
      setState(() => _message = 'End the conversation that is still open first, then bring the file in.');
      return;
    }
    // one still running after Back was let go (N2): two at once could leave either one's data
    if (state.changingData) {
      setState(() => _message = stillChangingData);
      return;
    }
    // how it went is still said if the person has gone back meanwhile (N2)
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _long = false;
      _message = 'Opening the file...';
    });
    _longTimer = Timer(longDataWait, () {
      if (mounted) setState(() => _long = true);
    });
    String outcome;
    try {
      // no session can start from the moment the file is opened (seconds) until the data is replaced, and the import
      // checks again for an open one right before it replaces the data (review cycle 1, D4)
      await state.whileChangingData(() async {
        final incoming = await TransferFile.openPicked(_file!, _code.text);
        if (mounted) setState(() => _message = 'Bringing everything in...');
        await state.receiveTransfer(incoming);
      });
      outcome = 'Done. ${state.data.sessions.length} sessions and everything else are now on this device. You can '
          'delete the transfer file.';
    } on NotSaved {
      // round 6 review, E-01: brought in, but the save failed, so only this run holds it; never "Done"
      outcome = importNotSaved;
    } on TransferError catch (e) {
      outcome = e.message;
    } catch (_) {
      // anything else (F-17): a plain message, and nothing on this device has changed
      outcome = 'The file could not be opened, so nothing was changed. Try again, or make a new file on the other '
          'device.';
    }
    _longTimer?.cancel();
    if (!mounted) {
      messenger?.showSnackBar(SnackBar(content: Text('Bringing your data in: $outcome')));
      return;
    }
    setState(() {
      _message = outcome;
      _busy = false;
      _long = false;
      _confirm = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ready = _file != null && _code.text.trim().isNotEmpty && !_busy;
    // Back waits while the file is opened and brought in (review cycle 1, D4): the person stays with the screen that
    // says how it went, and cannot start a session behind it meanwhile. Not for ever (cycle 2 review, N2): after
    // [longDataWait] Back is let go, the work goes on, and Support is always at the top
    return PopScope(canPop: !_busy || _long, child: Scaffold(
      appBar: AppBar(title: const BarTitle('Bring from another device'), actions: const [SupportButton(), SizedBox(width: 8)]),
      body: Readable(maxWidth: 720, child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Pick the transfer file made on your other device and type the code it showed. What is in the file '
            'replaces what is on this device. This device keeps its own private settings.'),
        const SizedBox(height: 20),
        OutlinedButton.icon(key: const Key('transfer_pick'), onPressed: _busy ? null : () async {
          try {
            final f = await widget.pick();
            if (mounted && f != null) {
              setState(() {
                _file = f;
                _message = null;
              });
            }
          } on TransferError catch (e) {
            if (mounted) setState(() => _message = e.message);
          } catch (_) {
            if (mounted) setState(() => _message = 'That file could not be read. Try picking it again.');
          }
        }, icon: const Icon(Icons.file_open_outlined),
            label: Text(_file == null ? 'Pick the transfer file' : 'File picked (${(_file!.length / 1024).ceil()} KB)')),
        const SizedBox(height: 12),
        TextField(autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('transfer_code'), controller: _code, maxLength: 24, textCapitalization: TextCapitalization.characters,
            // a code, never words: no autocorrection or suggestions on any device (stricter than PrivateKeyboard)
            autocorrect: false, enableSuggestions: false, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'The code from the other device (16 letters and numbers)', counterText: '')),
        const SizedBox(height: 16),
        if (!_confirm)
          FilledButton(key: const Key('transfer_open'), onPressed: ready ? () => setState(() => _confirm = true) : null,
              child: const Text('Open the file'))
        else
          Card(color: scheme.errorContainer, child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This replaces every session, note, plan and journal entry on this device with the ones in the '
                'file. It cannot be undone.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton(key: const Key('transfer_replace'), style: FilledButton.styleFrom(backgroundColor: scheme.error),
                  onPressed: _busy ? null : _replace, child: const Text('Replace')),
              // the import cannot be stopped once it runs, so Cancel is not offered then (cycle 2 review)
              TextButton(key: const Key('transfer_cancel'), onPressed: _busy ? null : () => setState(() => _confirm = false),
                  child: const Text('Cancel')),
            ]),
          ]))),
        if (_message != null) ...[
          const SizedBox(height: 12),
          // while it runs, a still line (an endless animation would keep the screen busy): what it is doing now
          if (_busy)
            Row(key: const Key('transfer_progress'), crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.hourglass_empty_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(_message!, style: t.bodyMedium)),
            ])
          else
            Text(_message!, style: t.bodyMedium),
        ],
        if (_long) ...[
          const SizedBox(height: 8),
          Text('This is taking longer than usual. You can go back now: Solace carries on bringing your data in, and no '
              'conversation can start until it has finished.', key: const Key('transfer_long'), style: t.bodyMedium),
        ],
      ])),
    ));
  }
}
