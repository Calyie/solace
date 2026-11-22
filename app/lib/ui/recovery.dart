// When the saved data cannot be opened (security review 2026-11-14, F-02): the app still starts, says plainly what
// happened, keeps every crisis number one glance away, and offers to try again or to start fresh with the unreadable
// file set aside (never deleted), so nothing is lost for good by a single tap.
import 'package:flutter/material.dart';

import '../core/crisis.dart';
import '../core/store.dart';
import 'premium.dart';
import 'theme.dart';

class RecoveryApp extends StatelessWidget {
  const RecoveryApp({super.key, required this.error, required this.retry, required this.startFresh});
  final Object error;
  final Future<void> Function() retry;
  final Future<void> Function() startFresh;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: themeFor(Brightness.light, const Look()),
        darkTheme: themeFor(Brightness.dark, const Look()),
        home: _RecoveryScreen(error: error, retry: retry, startFresh: startFresh),
      );
}

class _RecoveryScreen extends StatefulWidget {
  const _RecoveryScreen({required this.error, required this.retry, required this.startFresh});
  final Object error;
  final Future<void> Function() retry;
  final Future<void> Function() startFresh;
  @override
  State<_RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<_RecoveryScreen> {
  bool _confirm = false, _busy = false;
  String? _problem;
  AppLifecycleListener? _life;

  static bool _locked(Object e) => e is VaultError && e.kind == 'locked';

  @override
  void initState() {
    super.initState();
    // C-08: the phone locked as Solace opened. Once it is unlocked and Solace is in front again, it tries by itself.
    _life = AppLifecycleListener(onResume: () {
      if (mounted && !_busy && _locked(widget.error)) _run(widget.retry);
    });
  }

  @override
  void dispose() {
    _life?.dispose();
    super.dispose();
  }

  /// Runs [action]; whatever happens the screen comes back (audit 2026-11-14, F-02: it hung on a keychain error).
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _problem = e is VaultError ? e.message
            : 'That did not work. Nothing has been deleted. Try again in a moment.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final e = widget.error;
    final why = e is VaultError ? e.message : 'Solace could not open your saved data just now.';
    // a keychain problem is not unreadable data: allow Solace when asked (or unlock the device) and try again;
    // starting fresh would only set good data aside. Linux keeps no key in a keyring (round 6 review, E-05 and E-09:
    // the advice to unlock one could never help there)
    final keychain = e is VaultError && e.kind == 'keychain';
    // Linux: the passphrase is right but the key's own file cannot be opened; Try again cannot help, so Start fresh
    // is offered, as "I have forgotten it" offers it on the passphrase screen (round 6 review, E-05)
    final keyFile = e is VaultError && e.kind == 'key_unreadable';
    // C-08: the phone is locked, so the key cannot be read just now; nothing is wrong with the data or its key
    final locked = _locked(e);
    // C-08, Android: the key that unwraps the data key is gone from the phone; trying again cannot help
    final keyLost = e is VaultError && e.kind == 'key_lost';
    return Scaffold(
      body: SafeArea(child: Readable(child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
        Text('$appName could not open your saved data', style: t.headlineSmall),
        const SizedBox(height: Space.m),
        Text(locked
            ? '$why Nothing has been deleted.'
            : keychain
            ? '$why Nothing has been deleted. If this device asked whether Solace may use its keychain, choose Allow, '
                'or unlock the device. Then try again.'
            : keyLost
                ? '$why Nothing has been deleted. Trying again will not help. Start fresh sets your saved data aside '
                    'on this phone under a dated name and opens Solace empty; without that key it cannot be opened '
                    'again, so a transfer file you made earlier is the way to bring your data back.'
            : keyFile
                ? '$why Nothing has been deleted. Trying again will not help unless you put back a good copy of '
                    'Solace\'s folder from a backup. Start fresh sets your data and this key file aside on this '
                    'computer under dated names, not erased, and opens Solace empty, as "I have forgotten it" on the '
                    'passphrase screen does.'
                : '$why Nothing has been deleted. You can try again, or start fresh: your unreadable data and its key '
                    'are then set aside on this device, not erased.',
            key: const Key('recovery_advice')),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: Space.s),
            child: Text(_problem!, style: t.bodyMedium?.copyWith(color: scheme.error))),
        const SizedBox(height: Space.l),
        Wrap(spacing: Space.s, runSpacing: Space.s, children: [
          FilledButton(onPressed: _busy ? null : () => _run(widget.retry), child: const Text('Try again')),
          if (keychain || locked)
            const SizedBox.shrink()
          else if (!_confirm)
            OutlinedButton(onPressed: _busy ? null : () => setState(() => _confirm = true), child: const Text('Start fresh'))
          else
            FilledButton(style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                onPressed: _busy ? null : () => _run(widget.startFresh), child: const Text('Yes, start fresh')),
        ]),
        const SectionHeader('If you need support now'),
        for (final c in crisisByCountry.values) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Card(
          child: Padding(padding: const EdgeInsets.all(Space.l), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.country, style: t.titleSmall),
            for (final line in [...c.emergency, ...c.lines]) Padding(padding: const EdgeInsets.only(top: Space.xs),
                child: Text('${line.name}: ${line.number}', style: t.bodyMedium)),
          ])),
        )),
        Text('Numbers checked on $crisisChecked.', style: t.bodySmall),
      ]))),
    );
  }
}

/// Shown by a second copy of Solace on a computer, which then touches nothing (main.dart boot).
class AlreadyOpenApp extends StatelessWidget {
  const AlreadyOpenApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeFor(Brightness.light, const Look()),
        darkTheme: themeFor(Brightness.dark, const Look()),
        home: Scaffold(body: SafeArea(child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
          Text('$appName is already open in another window. Close this one and use that window.',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SectionHeader('If you need support now'),
          for (final c in crisisByCountry.values) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Text(
              '${c.country}: ${[...c.lines, ...c.emergency].map((l) => '${l.name} ${l.number}').join(', ')}')),
        ]))),
      );
}
