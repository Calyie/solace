// The Linux start screen (core/passphrase_key_store.dart): choose a passphrase the first time, type it each time
// Solace is opened fresh. Support is reachable before anything is typed. Nothing else runs until the data key opens.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/crisis.dart';
import '../core/passphrase_key_store.dart';
import 'crisis.dart' show SupportButton;
import 'premium.dart';
import 'theme.dart';
import 'transfer_screen.dart' show longDataWait;

/// The keyboard type of every passphrase box (round 6 review, E-06). Flutter's Linux embedder tells the input method
/// (IBus, Fcitx) what a box holds from its keyboard type alone (engine: shell/platform/linux/fl_text_input_channel.cc):
/// `obscureText`, `autocorrect` and `enableIMEPersonalizedLearning` are not passed on, and this type is the only one
/// it sends as GTK_INPUT_PURPOSE_PASSWORD, which input methods are expected not to predict from or learn. No input
/// hint (such as GTK_INPUT_HINT_PRIVATE) can be set from Dart; docs/SECURITY.md section 7 says what is left to the
/// desktop. The box stays hidden on screen (`obscureText`).
const passphraseKeyboard = TextInputType.visiblePassword;

class PassphraseApp extends StatelessWidget {
  const PassphraseApp({super.key, required this.dir, required this.onReady, this.settings = const StretchSettings()});
  final Directory dir; // the app's private support folder
  final Future<void> Function(PassphraseKeyStore keys) onReady;
  final StretchSettings settings;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: themeFor(Brightness.light, const Look()),
        darkTheme: themeFor(Brightness.dark, const Look()),
        home: PassphraseScreen(dir: dir, onReady: onReady, settings: settings),
      );
}

class PassphraseScreen extends StatefulWidget {
  const PassphraseScreen({super.key, required this.dir, required this.onReady, this.settings = const StretchSettings()});
  final Directory dir;
  final Future<void> Function(PassphraseKeyStore keys) onReady;
  final StretchSettings settings;
  @override
  State<PassphraseScreen> createState() => _PassphraseScreenState();
}

class _PassphraseScreenState extends State<PassphraseScreen> {
  final _first = TextEditingController(), _second = TextEditingController();
  bool? _setUp; // null while checking
  bool _busy = false, _forgot = false;
  String? _message;
  int _wrong = 0;
  DateTime? _waitUntil;

  @override
  void initState() {
    super.initState();
    PassphraseKeyStore.isSetUp(widget.dir).then((v) {
      if (mounted) setState(() => _setUp = v);
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final now = DateTime.now();
    if (_waitUntil != null && _waitUntil!.isAfter(now)) {
      setState(() => _message = 'Too many tries. Try again in ${_waitUntil!.difference(now).inSeconds + 1} seconds.');
      return;
    }
    final a = _first.text;
    if (_setUp == false) {
      if (a.length < minPassphraseLength) {
        setState(() => _message = 'Use at least $minPassphraseLength characters. A few words you will remember work well.');
        return;
      }
      if (a != _second.text) {
        setState(() => _message = 'The two passphrases are different.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _message = _setUp == false ? 'Setting it up (a few seconds)...' : 'Opening (a few seconds)...';
    });
    try {
      final keys = _setUp == false
          ? await PassphraseKeyStore.create(widget.dir, a, settings: widget.settings)
          : await PassphraseKeyStore.open(widget.dir, a);
      _first.clear();
      _second.clear();
      await widget.onReady(keys);
    } on WrongPassphrase {
      _wrong++;
      if (_wrong >= 5) _waitUntil = DateTime.now().add(Duration(seconds: (30 * (1 << (_wrong - 5).clamp(0, 6)))));
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'That passphrase did not open your data. Try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Solace could not open its data just now. Try again.';
        });
      }
    }
  }

  /// Forgotten: the locked data and its wrapped key are set aside (never deleted), and a new passphrase is chosen.
  Future<void> _startFresh() async {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    try {
      for (final name in ['data_v1.bin', 'data_v1.bin.bak', 'keys', 'media']) {
        final path = '${widget.dir.path}/$name';
        final t = FileSystemEntity.typeSync(path);
        if (t == FileSystemEntityType.notFound) continue;
        final target = '$path.forgotten-$stamp';
        t == FileSystemEntityType.directory ? await Directory(path).rename(target) : await File(path).rename(target);
      }
    } catch (_) {
      setState(() => _message = 'That did not work. Nothing has been deleted. Try again.');
      return;
    }
    setState(() {
      _forgot = false;
      _setUp = false;
      _message = 'Your earlier data is set aside on this computer, still locked. Choose a new passphrase.';
    });
  }

  void _support() => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (context) {
        final t = Theme.of(context).textTheme;
        return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          Text('Support, any time', style: t.headlineSmall),
          const SizedBox(height: Space.s),
          const Text('If you are in danger or might harm yourself or someone else, call one of these numbers.'),
          for (final c in crisisByCountry.values) ...[
            const SizedBox(height: Space.m),
            Text(c.country, style: t.titleSmall),
            for (final l in [...c.lines, ...c.emergency]) Text('${l.name}: ${l.number}', style: t.bodyMedium),
          ],
        ]));
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final setUp = _setUp;
    Widget field(TextEditingController c, String label, Key key) => TextField(autofillHints: PrivateKeyboard.autofillHints, key: key, controller: c, obscureText: true,
        keyboardType: passphraseKeyboard, // told to the Linux input method as a password (round 6 review, E-06)
        maxLength: maxPassphraseLength, enableIMEPersonalizedLearning: false, autocorrect: false,
        enableSuggestions: false, onSubmitted: (_) => _busy ? null : _go(),
        decoration: InputDecoration(labelText: label, counterText: ''));
    return Scaffold(
      body: SafeArea(child: Readable(maxWidth: 480, selectable: false, child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
        Align(alignment: Alignment.centerRight, child: TextButton.icon(key: const Key('pass_support'), onPressed: _support,
            icon: Icon(Icons.favorite_outline, size: 18, color: scheme.error), label: const Text('Support'))),
        const SizedBox(height: Space.l),
        Icon(Icons.lock_outline, size: 40, color: scheme.primary),
        const SizedBox(height: Space.l),
        if (setUp == null)
          const Center(child: CircularProgressIndicator())
        else if (_forgot) ...[
          Text('Forgotten your passphrase?', style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: Space.m),
          const Text('Without it, nobody can open your data. That is what keeps it safe from other programs on this '
              'computer. You can start fresh. Your locked data is set aside on this computer, not deleted, in case you '
              'remember the passphrase later.'),
          const SizedBox(height: Space.l),
          FilledButton(key: const Key('pass_start_fresh'), onPressed: _startFresh, child: const Text('Start fresh')),
          TextButton(onPressed: () => setState(() => _forgot = false), child: const Text('Go back')),
        ] else ...[
          Text(setUp ? '$appName is locked' : 'Choose a passphrase', style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: Space.s),
          Text(setUp ? 'Type your passphrase to open your data.'
              : 'On this computer $appName keeps your data locked with a passphrase only you know, so other programs '
                  'cannot open it. You will type it each time you open $appName. If you forget it, your data cannot be '
                  'opened, by anyone.', style: t.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.l),
          field(_first, setUp ? 'Passphrase' : 'Passphrase (at least $minPassphraseLength characters)',
              const Key('pass_first')),
          if (!setUp) ...[const SizedBox(height: Space.s), field(_second, 'The same again', const Key('pass_second'))],
          const SizedBox(height: Space.m),
          FilledButton(key: const Key('pass_go'), onPressed: _busy ? null : _go,
              child: Text(setUp ? 'Open' : 'Set the passphrase')),
          if (setUp) TextButton(key: const Key('pass_forgot'), onPressed: _busy ? null : () => setState(() => _forgot = true),
              child: const Text('I have forgotten it')),
        ],
        if (_message != null) Padding(padding: const EdgeInsets.only(top: Space.m),
            child: Text(_message!, textAlign: TextAlign.center, style: t.bodyMedium)),
      ]))),
    );
  }
}

/// Settings > Change passphrase, on Linux (round 4 review, A-09): the current passphrase, then the new one twice. Every
/// key Solace keeps is sealed again under the new one, then the data key itself is renewed ([renewKey], round 5
/// review, C-02), so the old passphrase opens nothing here, and an old copy of the keys opens nothing saved after it.
class ChangePassphraseScreen extends StatefulWidget {
  const ChangePassphraseScreen({super.key, required this.dir, required this.keys, this.renewKey, this.inQueue});
  final Directory dir;
  final PassphraseKeyStore keys;
  /// Seals everything again under a new data key once the passphrase has changed (round 5 review, C-02).
  final Future<void> Function()? renewKey;
  /// Runs the check of the current passphrase and the change in the encrypted store's queue (EncryptedFileVault
  /// inKeyQueue), the queue the renewal and Delete everything run in, so they never interleave (round 7 review, G7-09).
  final Future<void> Function(Future<void> Function() work)? inQueue;
  @override
  State<ChangePassphraseScreen> createState() => _ChangePassphraseScreenState();
}

class _ChangePassphraseScreenState extends State<ChangePassphraseScreen> {
  final _current = TextEditingController(), _first = TextEditingController(), _second = TextEditingController();
  bool _busy = false, _done = false;
  bool _long = false; // it has run for longDataWait: Back is let go, and the work goes on (round 6 review, E-11)
  Timer? _longTimer;
  String? _message;
  int _wrong = 0;
  DateTime? _waitUntil;

  @override
  void dispose() {
    _longTimer?.cancel();
    _current.dispose();
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final now = DateTime.now();
    if (_waitUntil != null && _waitUntil!.isAfter(now)) {
      setState(() => _message = 'Too many tries. Try again in ${_waitUntil!.difference(now).inSeconds + 1} seconds.');
      return;
    }
    final next = _first.text;
    if (next.length < minPassphraseLength) {
      setState(() => _message = 'Use at least $minPassphraseLength characters. A few words you will remember work well.');
      return;
    }
    if (next != _second.text) {
      setState(() => _message = 'The two new passphrases are different.');
      return;
    }
    // how it ended is still said if Back was let go meanwhile (round 6 review, E-11)
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _long = false;
      _message = 'Changing it (a few seconds)...';
    });
    _longTimer?.cancel();
    _longTimer = Timer(longDataWait, () {
      if (mounted) setState(() => _long = true);
    });
    void finish(String outcome) {
      _longTimer?.cancel();
      if (!mounted) {
        messenger?.showSnackBar(SnackBar(content: Text(outcome)));
        return;
      }
      setState(() {
        _busy = false;
        _long = false;
        _done = true;
        _message = outcome;
      });
    }
    var changed = false;
    final current = _current.text;
    try {
      try {
        // in the store's queue, so a renewal, Delete everything or a second change waits for it (G7-09)
        await (widget.inQueue ?? (work) => work())(() async {
          await PassphraseKeyStore.open(widget.dir, current); // the current one, checked first
          await widget.keys.changePassphrase(next);
        });
      } on PassphraseChangedNotSettled {
        // round 6 review, E-11: changed all the same, so never "the old one still opens Solace". The keys are
        // sealed under the new passphrase only at the next opening, so the data key cannot be renewed now
        _current.clear();
        _first.clear();
        _second.clear();
        finish('Passphrase changed. Only the new one opens Solace from now on. Type it next time Solace opens, which '
            'also finishes this change. To give your data a new key as well, change the passphrase once more after '
            'that.');
        return;
      }
      changed = true;
      _current.clear();
      _first.clear();
      _second.clear();
      var renewed = true;
      if (mounted) setState(() => _message = 'Passphrase changed. Locking your data again under a new key...');
      try {
        await widget.renewKey?.call(); // a copy of the old keys and the old passphrase then open nothing new (C-02)
      } catch (_) {
        renewed = false; // both keys are kept; the next opening finishes it
      }
      finish(renewed
          ? 'Passphrase changed. Type the new one next time Solace opens.'
          : 'Passphrase changed. Type the new one next time Solace opens. Solace finishes renewing its key then.');
    } on WrongPassphrase {
      _longTimer?.cancel();
      _wrong++;
      if (_wrong >= 5) _waitUntil = DateTime.now().add(Duration(seconds: (30 * (1 << (_wrong - 5).clamp(0, 6)))));
      if (mounted) {
        setState(() {
          _busy = false;
          _long = false;
          _message = 'That is not the current passphrase. Nothing was changed.';
        });
      } else {
        messenger?.showSnackBar(const SnackBar(content: Text('That was not the current passphrase. Nothing was '
            'changed.')));
      }
    } catch (_) {
      _longTimer?.cancel();
      // reached only before the change happened (after it, every failure is handled above, and [changed] guards
      // that), so the old one does still open Solace
      final outcome = changed ? 'Passphrase changed. Type the new one next time Solace opens.'
          : 'The passphrase could not be changed just now, so the old one still opens Solace. Try again.';
      if (mounted) {
        setState(() {
          _busy = false;
          _long = false;
          _done = changed;
          _message = outcome;
        });
      } else {
        messenger?.showSnackBar(SnackBar(content: Text(outcome)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, Key key) => TextField(autofillHints: PrivateKeyboard.autofillHints, key: key, controller: c, obscureText: true,
        keyboardType: passphraseKeyboard, // told to the Linux input method as a password (round 6 review, E-06)
        maxLength: maxPassphraseLength, enableIMEPersonalizedLearning: false, autocorrect: false,
        enableSuggestions: false, enabled: !_busy && !_done,
        decoration: InputDecoration(labelText: label, counterText: ''));
    // Back waits while the passphrase is changed and the data sealed again under a new key (round 6 review, E-11:
    // leaving said nothing of how it ended), with Support always at the top; after [longDataWait] it is let go, the
    // work goes on, and how it ended is said at the bottom of the screen
    return PopScope(canPop: !_busy || _long, child: Scaffold(
      appBar: AppBar(title: const BarTitle('Change passphrase'), actions: const [SupportButton(), SizedBox(width: 8)]),
      body: SafeArea(child: Readable(maxWidth: 480, selectable: false, child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
        const Text('Your passphrase protects everything Solace keeps on this computer. There is no way to recover a '
            'forgotten one, so choose words you will remember.'),
        const SizedBox(height: Space.l),
        field(_current, 'Current passphrase', const Key('pass_current')),
        const SizedBox(height: Space.m),
        field(_first, 'New passphrase', const Key('pass_new')),
        const SizedBox(height: Space.m),
        field(_second, 'New passphrase again', const Key('pass_new_again')),
        const SizedBox(height: Space.l),
        if (_message != null) Padding(padding: const EdgeInsets.only(bottom: Space.m),
            child: Text(_message!, key: const Key('pass_change_message'))),
        if (!_done) FilledButton(key: const Key('pass_change'), onPressed: _busy ? null : _change,
            child: const Text('Change passphrase')),
      ]))),
    ));
  }
}
