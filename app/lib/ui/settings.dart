// Settings, grouped the way people look for things (owner, 2026-11-16: "isn't hard to find things especially
// settings"): the model, voice and safety files first (the button had been inside the profile's settings, "just too
// complicated"; ui/model_files.dart); Look and sound (Appearance, Face and voice, practices read aloud, haptics);
// Privacy and lock; Safety (the country for crisis numbers, and the safety check); Reminders; Words for your
// meditations; Your data (export, space, moving to another device, deleting everything); On this Mac; and at the very
// end, tucked away, deep work mode (internally 'full'), which shows its warning first and needs the owner's 6-digit
// key (core/full_mode_key.dart), with Change deep work PIN beside it. The Safety check switch needs the same key to be
// turned off (owner, 2026-11-15).
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/crisis.dart';
import '../core/dates.dart';
import '../core/full_mode_lock.dart';
import '../core/home_link.dart' show aboutLine, homeBuild;
import '../core/session.dart' show SessionStillOpen, sessionStillOpen;
import '../core/storage.dart';
import '../core/therapist.dart' show portraits;
import '../core/voice.dart' show voices;
import '../main.dart' show loadSafetyClassifier;
import 'app_lock.dart';
import 'appearance.dart';
import 'crisis.dart' show SupportButton;
import 'desktop.dart';
import 'passphrase_screen.dart' show ChangePassphraseScreen;
import '../core/full_mode_key.dart';
import '../core/store.dart' show EncryptedFileVault, Settings;
import 'premium.dart';
import 'model_files.dart';
import 'presence.dart';
import 'privacy.dart';
import 'storage.dart';
import 'home_server.dart';
import 'transfer_screen.dart';
import 'words.dart';
import 'your_data.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirmFull = false;
  bool _confirmWipe = false;
  final _key = TextEditingController();
  String? _keyMessage;
  bool _checking = false;
  bool _wiping = false; // Delete everything is running: Back waits, and the button is not tapped twice (D4)
  bool _wipeLong = false; // it has run for longDataWait: Back is let go, and the work goes on (cycle 2 review, N2)
  Timer? _wipeTimer;
  String? _wipeMessage; // why Delete everything did not run, shown beside its button

  String? _classifierMessage; // why the safety check could not be turned off, shown under its switch

  @override
  void dispose() {
    _wipeTimer?.cancel();
    _key.dispose();
    super.dispose();
  }

  /// What is said under the safety check's switch: while wrong keys have paused the deep work key, that it cannot be
  /// turned off and until when; otherwise why it last could not be.
  String? _classifierLine(AppState state) {
    final s = state.data.settings, now = state.clock();
    if (s.classifierOn && fullModeLockLeft(s, now) > Duration.zero) return keyPausedLine(s, now);
    return s.classifierOn ? _classifierMessage : null;
  }

  /// The safety check's switch (owner, 2026-11-15): turning it on needs nothing and loads the classifier; turning it
  /// off needs the deep work mode key (_ClassifierPinDialog), and then the classifier is let go at once.
  Future<void> _switchClassifier(AppState state, bool on) async {
    final s = state.data.settings;
    if (on) {
      _classifierMessage = null;
      if (!await state.saveSetting(() => s.classifierOn = true, () => s.classifierOn = false)) {
        if (mounted) sayNotSaved(context);
      } else {
        await loadSafetyClassifier(state);
      }
      if (mounted) setState(() {});
      return;
    }
    // paused after wrong keys: it stays on, and the line under the switch says until when
    if (fullModeLockLeft(s, state.clock()) > Duration.zero) return setState(() {});
    if (!state.fullModeKey.isSetUp) {
      return setState(() => _classifierMessage = state.builtInKey.isSetUp && state.keptPinUnreadable
          ? keptPinUnreadableLine
          : 'The safety check stays on: this version of the app has no deep work PIN to turn it off with.');
    }
    setState(() => _classifierMessage = null);
    final tried = await showDialog<int>(context: context, builder: (_) => _ClassifierPinDialog(state: state));
    if (tried == null || !mounted) { // cancelled, or a wrong key: it stays on
      if (mounted) setState(() {});
      return;
    }
    final count = fullModeCount(s);
    if (!await state.saveSetting(() {
      fullModeRightKey(s);
      s.classifierOn = false;
    }, () {
      s.classifierOn = true;
      restoreFullModeCount(s, count);
    })) {
      if (mounted) sayNotSaved(context);
    } else {
      await state.stopRiskCheck();
      if (tried > 0 && mounted) {
        sayGently(context, 'The safety check is off. Before this, a wrong deep work PIN was entered $tried '
            '${tried == 1 ? 'time' : 'times'}. If that was not you, someone may have tried to turn the safety check '
            'off or deep work mode on.');
      }
    }
    if (mounted) setState(() {});
  }

  /// Changing the deep work PIN (_ChangePinDialog); told plainly when it is done.
  Future<void> _changePin(AppState state) async {
    final tried = await showDialog<int>(context: context, builder: (_) => _ChangePinDialog(state: state));
    if (tried == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tried == 0
        ? 'Your deep work PIN is changed. The old one no longer works.'
        : 'Your deep work PIN is changed. Before this, a wrong PIN was entered $tried '
            '${tried == 1 ? 'time' : 'times'}. If that was not you, someone may have tried your PIN.')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.data.settings;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Future<void> set(void Function() f) async {
      f();
      await state.save();
      setState(() {});
    }

    Future<void> pickTime(String current, void Function(String) save) async {
      final parts = current.split(':');
      final picked = await showTimePicker(context: context,
          initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
      if (picked != null) {
        await set(() => save('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
      }
    }

    // Back waits while Delete everything runs (D4), but not for ever (N2), and Support is always at the top
    return PopScope(canPop: !_wiping || _wipeLong, child: Scaffold(
      appBar: BoundedBar(maxWidth: Widths.twoPanes + 2 * Space.xl,
          bar: AppBar(title: const BarTitle('Settings'), actions: const [SupportButton(), SizedBox(width: 8)])),
      // grouped the way people look for things (owner, 2026-11-16: "isn't hard to find things especially settings"):
      // Solace's files first, then how it looks and sounds, privacy and the lock, safety, reminders, meditations and
      // your data; deep work mode stays tucked away at the very end. A phone: one column; a computer: two panes
      // (_SettingsLayout)
      body: _SettingsLayout(first: [
        // owner, 2026-11-16: near the top, never inside the profile; the one way in (ui/model_files.dart)
        const SectionHeader('Model, voice and safety files', key: Key('files_section'), top: 0),
        const _Group([
          // each file on its own line, its state at a glance, the full words on demand (ui/model_files.dart)
          FilesStatus(),
          SizedBox(height: Space.m),
          ModelFilesPanel(),
        ]),
        // Solace Home only (docs/HOME_SERVER.md): pair with the model on the person's own computer
        if (homeOffered) ...[
          const SectionHeader('Home server', key: Key('home_section')),
          const _Group([HomeServerTile()]),
        ],
        const SectionHeader('Look and sound'),
        Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: Column(children: [
          ListTile(
            key: const Key('open_appearance'),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            subtitle: Text(appearanceSummary(s)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceScreen()));
              if (mounted) setState(() {});
            },
          ),
          const Divider(indent: Space.l, endIndent: Space.l),
          ListTile(
            key: const Key('open_face_voice'),
            leading: const Icon(Icons.face_outlined),
            title: const Text('Face and voice'),
            subtitle: Text(faceAndVoiceSummary(s)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const FaceAndVoiceScreen()));
              if (mounted) setState(() {});
            },
          ),
          const Divider(indent: Space.l, endIndent: Space.l),
          SwitchListTile(
            key: const Key('voice_on_switch'),
            secondary: const Icon(Icons.volume_up_outlined),
            // it is the guided practices that speak (ui/practices.dart); a call always speaks
            title: const Text('Read practices aloud'),
            subtitle: const Text('Guided practices speak each step in the voice you chose. When off, you read them.'),
            value: s.voiceOn,
            onChanged: (v) => set(() => s.voiceOn = v),
          ),
          const Divider(indent: Space.l, endIndent: Space.l),
          // gentle taps with one meaning each, never while a call is listening (ui/premium.dart Haptics)
          SwitchListTile(
            key: const Key('haptics_switch'),
            secondary: const Icon(Icons.vibration_outlined),
            title: const Text('Haptics'),
            subtitle: const Text('A gentle tap when you choose or finish something. Never while the microphone is '
                'listening.'),
            value: s.haptics,
            onChanged: (on) async {
              await set(() => s.haptics = on);
              if (on) Haptics.confirm(); // so the person feels what they turned on
            },
          ),
        ])),
        const SectionHeader('Privacy and lock'),
        _Group([
          ListTile(contentPadding: EdgeInsets.zero, key: const Key('open_privacy'), leading: const Icon(Icons.shield_outlined),
              title: const Text('Private by design'), subtitle: const Text('What Solace keeps, and how you control it'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen()))),
          SwitchListTile(contentPadding: EdgeInsets.zero, key: const Key('app_lock'), title: const Text('Lock Solace'),
              subtitle: const Text('Asks for its own six-digit passcode when Solace opens and before privacy changes. '
                  'Support stays reachable on the lock screen.'),
              value: lockIsOn(s), onChanged: (on) async {
                if (!on) {
                  // round 9 review, 9A-02: off only with the lock's own unlock, asked again; Cancel leaves it on
                  if (!await confirmItIsYou(context, state, what: 'turn the lock off') || !context.mounted) {
                    if (mounted) setState(() {});
                    return;
                  }
                  // round 6 review, E-01: put back on (and said) when turning it off could not be saved. Round 9
                  // final, 9B-12: the passcode goes with it, so an old one never comes back into use; turning the
                  // lock on again always chooses a new one
                  final code = s.passcode;
                  if (!await state.saveSetting(() {
                    s.appLock = false;
                    s.passcode = null;
                  }, () {
                    s.appLock = true;
                    s.passcode = code;
                  }) && context.mounted) {
                    sayNotSaved(context);
                  }
                } else {
                  await turnOnLock(context, state);
                }
                if (mounted) setState(() {});
              }),
          // owner, 2026-11-15: the lock uses only Solace's own passcode; a lock that used this device's own unlock
          // before is off until a passcode is chosen (core/store.dart lockNeedsPasscode), and says so here
          if (!lockIsOn(s) && s.lockNeedsPasscode) ListTile(contentPadding: EdgeInsets.zero,
              key: const Key('lock_needs_passcode'), leading: const Icon(Icons.info_outline),
              title: const Text('The lock now uses Solace\'s own passcode'),
              subtitle: const Text('It no longer uses this device\'s own unlock, so it is off until you choose a '
                  'six-digit passcode for Solace. Turn on Lock Solace to choose one.')),
          if (lockIsOn(s)) ListTile(contentPadding: EdgeInsets.zero, title: const Text('Lock after'),
              trailing: DropdownButton<int>(value: s.lockAfterMinutes, items: const [
                DropdownMenuItem(value: 0, child: Text('At once')),
                DropdownMenuItem(value: 1, child: Text('1 minute')),
                DropdownMenuItem(value: 5, child: Text('5 minutes')),
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
              ], onChanged: (v) async {
                // round 9 re-check, 9A-02: longer before the lock comes down needs the lock's own unlock, asked
                // again; shorter needs nothing. Cancel or a wrong passcode leaves it as it was
                if (v! > s.lockAfterMinutes &&
                    (!await confirmItIsYou(context, state, what: 'keep Solace unlocked longer') || !context.mounted)) {
                  if (mounted) setState(() {});
                  return;
                }
                await set(() => s.lockAfterMinutes = v);
              })),
          SwitchListTile(contentPadding: EdgeInsets.zero, key: const Key('hide_switcher'),
              title: const Text('Hide Solace in the app switcher'),
              subtitle: const Text('A calm cover instead of your screen in the app switcher. Screenshots still work.'),
              value: s.hideInSwitcher, onChanged: (v) async {
                // round 9 review, 9A-02: showing Solace in the app switcher needs the lock's own unlock, asked again;
                // hiding it needs nothing (screenshots are never blocked: owner, 2026-11-19)
                if (!v && (!await confirmItIsYou(context, state, what: 'show Solace in the app switcher') ||
                    !context.mounted)) {
                  if (mounted) setState(() {});
                  return;
                }
                final was = s.hideInSwitcher; // round 6 review, E-01: put back (and said) when it could not be saved
                if (!await state.saveSetting(() => s.hideInSwitcher = v, () => s.hideInSwitcher = was) &&
                    context.mounted) {
                  sayNotSaved(context);
                }
                if (mounted) setState(() {});
              }),
          if (state.passphrase != null && state.passphraseDir != null)
            ListTile(contentPadding: EdgeInsets.zero, key: const Key('change_passphrase'),
                leading: const Icon(Icons.password_outlined), title: const Text('Change passphrase'),
                subtitle: const Text('The passphrase you type when Solace opens on this computer'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                    ChangePassphraseScreen(dir: state.passphraseDir!, keys: state.passphrase!,
                        renewKey: state.vault is EncryptedFileVault ? (state.vault as EncryptedFileVault).rotateKey
                            : null,
                        // in the vault's queue, never beside a renewal or Delete everything (round 7 review, G7-09)
                        inQueue: state.vault is EncryptedFileVault ? (state.vault as EncryptedFileVault).inKeyQueue
                            : null)))),
        ]),
        const SectionHeader('Safety'),
        _Group([
          Text('Your country', style: t.titleSmall),
          const SizedBox(height: 2),
          Text('Support shows its crisis numbers first.', style: t.bodySmall),
          const SizedBox(height: Space.s),
          DropdownButtonFormField<String>(  // seven countries no longer fit a row of segments on a phone
            key: const Key('settings_country'),
            initialValue: s.country, isExpanded: true,
            items: [for (final c in crisisByCountry.keys) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => set(() => s.country = v!),
          ),
          const SizedBox(height: Space.s),
          // owner, 2026-11-15: "create a feature to enable/disable off the safety classifier. It should use the same 6
          // digit pin as deep work mode. The classifier should be on by default but can be disabled in the settings."
          // Turning it off needs the deep work mode key, checked as deep work mode checks it and sharing its wrong-key
          // count and pause; turning it on needs nothing.
          SwitchListTile(contentPadding: EdgeInsets.zero, key: const Key('classifier_switch'),
              title: const Text('Safety check'),
              subtitle: const Text('A small trained model reads each message and shows a quiet support line when it is '
                  'worried. Turning it off needs your deep work PIN.'),
              value: s.classifierOn, onChanged: (on) => _switchClassifier(state, on)),
          if (_classifierLine(state) case final line?)
            Text(line, key: const Key('classifier_message'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ], second: [
        const SectionHeader('Reminders'),
        _Group([
          // core/nudge_scheduler.dart: the times below, and today's planned steps (at most three, none 22:00 to 08:00)
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Gentle reminders'),
              subtitle: const Text('Your session times and today\'s planned steps. The lock screen never shows what '
                  'they are about.'),
              value: s.remindersOn, onChanged: (v) async {
                s.remindersOn = v;
                await state.save();
              }),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Daily check-in'), trailing: Text(s.dailyReminder),
              onTap: () => pickTime(s.dailyReminder, (v) => s.dailyReminder = v)),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Weekly session'),
              trailing: Text(s.weeklyTime), onTap: () => pickTime(s.weeklyTime, (v) => s.weeklyTime = v)),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Weekly session day'),
              trailing: DropdownButton<String>(value: s.weeklyDay, underline: const SizedBox.shrink(), items: [
                for (final d in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'])
                  DropdownMenuItem(value: d, child: Text(d)),
              ], onChanged: (v) => set(() => s.weeklyDay = v!))),
        ]),
        const SectionHeader('Words for your meditations'),
        _Group([
          // a title and a line under it, read together, as a list tile's are
          MergeSemantics(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All optional', style: t.titleSmall),
            const SizedBox(height: 2),
            Text('Without them, meditations use your values and today\'s focus.', style: t.bodySmall),
          ])),
          for (final (key, label, hint) in [
            // labels short enough for the smallest phone; the examples wrap rather than cut (design review 2026-11-16)
            ('kind_phrase', 'Kind words to yourself', "I'm doing my best, and that is enough for today"),
            ('calm_word', 'Your calm word', 'steady'),
            ('intention', 'Intention for deep rest', 'I am safe, and I am enough'),
          ]) Padding(padding: const EdgeInsets.only(top: 8), child: TextFormField(autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, maxLength: 200, 
            initialValue: s.words[key] ?? '',
            minLines: 1, maxLines: 3, keyboardType: TextInputType.text, textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: label, hintText: hint, hintMaxLines: 2),
            onChanged: (v) async {
              s.words[key] = v;
              await state.save();
            },
          )),
        ]),
        const SectionHeader('Your data'),
        _Group([
          ListTile(contentPadding: EdgeInsets.zero, key: const Key('open_your_data'), leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Export your data'), subtitle: const Text('A summary for you or your clinician'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YourDataScreen()))),
          ListTile(contentPadding: EdgeInsets.zero, key: const Key('open_storage'), leading: const Icon(Icons.storage_outlined),
              title: const Text('Space Solace uses'), subtitle: Text('${megabytes(state.vault.savedBytes + state.pictureBytes)} of '
                  '${megabytes(solaceAllowance)}'), trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageScreen()))),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Send everything to another device'), trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendToDeviceScreen()))),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.download_outlined),
              title: const Text('Bring everything from another device'), trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiveFromDeviceScreen()))),
        ]),
        const SizedBox(height: Space.m),
        if (!_confirmWipe)
          OutlinedButton(onPressed: () => setState(() => _confirmWipe = true),
              child: const Text('Delete everything the app knows about me'))
        else
          Card(color: scheme.errorContainer, child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            // the same warning as before, laid out as a list (content pass, 2026-11-16)
            Text('Delete everything?', style: t.titleMedium?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: Space.s),
            Text('This deletes from this device:', style: t.titleSmall?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: Space.xs),
            Points(['Every session, note, score and setting.', 'The model, voice and safety files Solace keeps.',
                'Its reminders.',
                // Solace Home (HOME-05): the pairing goes too, and the server is told
                if (homeBuild && s.homeServer != null) 'The pairing with your home server. The server is told to '
                    'forget this device if it can be reached; if not, run "solace-home unpair" on it.'],
                style: t.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: Space.s),
            Text('It does not delete:', style: t.titleSmall?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: Space.xs),
            Points(const ['Files you saved outside Solace, such as exports and transfer files. Delete those yourself.',
                'A deep work PIN you changed. It stays as you set it.'],
                style: t.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: Space.s),
            Text('This cannot be undone.', style: t.bodyMedium?.copyWith(color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: Space.m),
            Wrap(spacing: 8, children: [
              FilledButton(key: const Key('wipe_confirm'), style: FilledButton.styleFrom(backgroundColor: scheme.error),
                  onPressed: _wiping ? null : () async {
                // round 9 review, 9A-02: the lock's own unlock is asked again first; Cancel deletes nothing
                if (!await confirmItIsYou(context, state, what: 'delete everything') || !context.mounted) return;
                if (OpenSession.count > 0) {
                  setState(() => _wipeMessage = sessionStillOpen);
                  return;
                }
                // model, voice or safety files still being copied in (MM-01): they would come back after the delete
                if (state.imports.running) {
                  setState(() => _wipeMessage = 'Files are still being added. Wait until that has finished, then try '
                      'again.');
                  return;
                }
                // a transfer or an earlier Delete everything still running after Back was let go (N2)
                if (state.changingData) {
                  setState(() => _wipeMessage = stillChangingData);
                  return;
                }
                // how it went is still said if the person has gone back meanwhile (N2)
                final messenger = ScaffoldMessenger.maybeOf(context);
                setState(() {
                  _wiping = true;
                  _wipeLong = false;
                  _wipeMessage = null;
                });
                _wipeTimer = Timer(longDataWait, () {
                  if (mounted) setState(() => _wipeLong = true);
                });
                String? problem;
                try {
                  // it checks again for an open session right before the data goes, and none can start meanwhile
                  await state.wipeEverything();
                } on SessionStillOpen {
                  problem = sessionStillOpen;
                } catch (_) {
                  problem = 'Not everything could be deleted. Try again.';
                }
                _wipeTimer?.cancel();
                if (!mounted) {
                  messenger?.showSnackBar(SnackBar(content: Text(problem == null
                      ? 'Everything Solace kept has been deleted.'
                      : 'Not everything could be deleted. Open Settings to try again.')));
                  return;
                }
                // Support opened over Settings meanwhile stays open: only this screen goes back to the start
                final here = context.mounted && (ModalRoute.of(context)?.isCurrent ?? true);
                setState(() {
                  _wiping = false;
                  _wipeLong = false;
                  _wipeMessage = problem ?? (here ? null : 'Everything Solace kept has been deleted.');
                });
                if (problem == null && here && context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
              }, child: const Text('Delete everything')),
              TextButton(onPressed: _wiping ? null : () => setState(() => _confirmWipe = false),
                  child: const Text('Cancel')),
            ]),
            // while it runs, a still line (an endless animation would keep the screen busy), and after a long wait
            // that Back works and the deleting goes on (N2)
            if (_wiping) Padding(key: const Key('wipe_progress'), padding: const EdgeInsets.only(top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.hourglass_empty_rounded, size: 18, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_wipeLong
                      ? 'This is taking longer than usual. You can go back now: Solace carries on deleting, and no '
                          'conversation can start until it has finished.'
                      : 'Deleting everything. This usually takes a few seconds. Support stays one tap away, at the '
                          'top.')),
                ])),
            if (_wipeMessage != null) Padding(padding: const EdgeInsets.only(top: 8),
                child: Text(_wipeMessage!, key: const Key('wipe_message'))),
          ]))),
        const DesktopSettingsSection(), // On this Mac, shown only on a computer (ui/desktop.dart)
      ], tail: [
        const SectionHeader('About', key: Key('settings_about')),
        Text(aboutLine(s.homeServer), key: const Key('settings_about_text'), style: t.bodyMedium),
        // Deep work mode (internally mode 'full'; owner, 2026-11-05): tucked away at the very end, opened only with the
        // owner's key. The everyday mode is never named to the person.
        const SizedBox(height: Space.l),
        if (s.mode == 'full') ...[
          Text('Deep work mode', style: t.titleSmall),
          const Text('On. Spoken reliving sessions are available, each behind readiness questions and a support '
              'person.'),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => set(() => s.mode = 'normal'),
              child: const Text('Turn off deep work mode'))),
        ] else if (!_confirmFull)
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
              icon: const Icon(Icons.lock_outline, size: 18), label: const Text('Deep work mode'),
              onPressed: () => setState(() => _confirmFull = true))),
        // changing the deep work PIN (owner, 2026-11-15: "Is there an option for me to change the 6 digit pin? Let's
        // say if it gets compromised in the future?"); a build without a key has nothing to change
        if (!_confirmFull)
          if (state.builtInKey.isSetUp)
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(key: const Key('change_pin'),
                icon: const Icon(Icons.password_outlined, size: 18), label: const Text('Change deep work PIN'),
                onPressed: () => _changePin(state)))
          else
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('The deep work PIN is set up when the app is '
                'built, so it cannot be changed in this version.', key: Key('change_pin_unavailable'))),
        if (_confirmFull) Card(color: scheme.errorContainer, margin: const EdgeInsets.only(top: 12), child: Padding(
            padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Before you turn on deep work mode', style: t.titleMedium),
          const SizedBox(height: 6),
          const Text('Spoken reliving means going back through a traumatic memory out loud. It can help a great deal, '
              'and it can be overwhelming. A support person must be with you for every reliving session. They are not '
              'a therapist, and the app cannot check they are there. If you have a trauma therapist, working with them '
              'is the safest way to do this.'),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          TextField(autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck,
            key: const Key('full_mode_key'),
            controller: _key,
            keyboardType: secretDigitsKeyboard, // a password to the Linux input method (round 7 review, G7-07)
            inputFormatters: secretDigits,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Deep work mode key (6 digits)', counterText: ''),
          ),
          if (_keyMessage != null) Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(_keyMessage!, style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _checking ? null : () async {
              final now = state.clock();
              final left = fullModeLockLeft(s, now);
              if (left > Duration.zero) {
                setState(() => _keyMessage = 'Too many wrong keys. Try again in ${left.inMinutes + 1} minutes.');
                return;
              }
              if (!state.fullModeKey.isSetUp) {
                setState(() => _keyMessage = state.builtInKey.isSetUp && state.keptPinUnreadable
                    ? keptPinUnreadableLine : 'Deep work mode is not set up in this version of the app.');
                return;
              }
              setState(() => _checking = true);
              // counted as a wrong key and saved before the check (R10A-06), taken back if the key is right
              final untried = await countPinTry(state, now);
              if (untried == null) {
                _key.clear();
                if (mounted) {
                  setState(() {
                    _checking = false;
                    _keyMessage = pinTryNotNoted;
                  });
                }
                return;
              }
              var ok = false;
              try {
                ok = await state.fullModeKey.matches(_key.text);
              } catch (_) {
                ok = false; // never leaves the button disabled (F-17)
              }
              _key.clear();
              _checking = false;
              if (ok) {
                final tried = untried.fails; // told after the right key, as wrong passcodes are (OW-A09-1)
                await set(() {
                  fullModeRightKey(s);
                  s.mode = 'full';
                  s.fullModeSince = isoDate(now);
                  _confirmFull = false;
                  _keyMessage = null;
                });
                if (tried > 0 && context.mounted) {
                  sayGently(context, 'Deep work mode is on. Before this, a wrong key was entered $tried '
                      '${tried == 1 ? 'time' : 'times'}. If that was not you, someone may have tried to turn it on.');
                }
              } else if (mounted) {
                // already counted and saved before the check (R10A-06)
                setState(() => _keyMessage = s.fullModeFails >= fullModeTries
                    ? 'Too many wrong keys. Deep work mode is locked for ${fullModeLockLeft(s, now).inMinutes} minutes.'
                    : 'That key is not right. ${fullModeTries - s.fullModeFails} tries left before a pause.');
              }
            }, child: const Text('I understand, turn on deep work mode')),
            TextButton(onPressed: () => setState(() {
              _confirmFull = false;
              _keyMessage = null;
              _key.clear();
            }), child: const Text('Not now')),
          ]),
        ]))),
      ]),
    ));
  }
}

/// Settings' layout (owner, 2026-11-16: one adaptive design for the phone and the computer): on a phone one column,
/// [first], [second] then [tail], at a reading width; on a computer [first] and [second] side by side
/// (core layout tokens, ui/premium.dart), each column starting level with the other, and [tail] (deleting
/// everything, deep work mode) below them at a reading width.
class _SettingsLayout extends StatelessWidget {
  const _SettingsLayout({required this.first, required this.second, required this.tail});
  final List<Widget> first, second, tail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        const pad = EdgeInsets.all(20);
        // every section is built at once (one column, not a lazy list): Settings is short, and so each setting can
        // be scrolled to and is there for a screen reader from the start
        if (!TwoPanes.fits(box.maxWidth - pad.horizontal)) {
          return Readable(child: ListView(key: const Key('settings_list'), padding: pad, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...first, ...second, ...tail]),
          ]));
        }
        return Readable(maxWidth: Widths.twoPanes, child: ListView(key: const Key('settings_list'), padding: pad,
            children: [
          TwoPanes(first: first, second: second),
          Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.dialog),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: tail))),
        ]));
      });
}

/// Said where the deep work PIN is asked for while a changed PIN's file is there but cannot be read (round 9 review,
/// 9A-01; AppState.keptPinUnreadable): no PIN works until it can, never the built one it replaced.
const keptPinUnreadableLine = 'Your changed deep work PIN could not be read on this device just now, so no PIN works '
    'until it can. Close Solace and open it again.';

/// Until when wrong keys pause the deep work key, in plain words: "19:45", "08:15 tomorrow", or the day.
String pauseEndWords(DateTime until, DateTime now) {
  // shown to the minute, never before the pause ends
  final exact = until.second == 0 && until.millisecond == 0 && until.microsecond == 0;
  final u = DateTime(until.year, until.month, until.day, until.hour, until.minute)
      .add(Duration(minutes: exact ? 0 : 1));
  final hm = '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}';
  // whole days between the dates, rounded so a clock change (a 23 or 25 hour day) does not miscount
  final days =
      (DateTime(u.year, u.month, u.day).difference(DateTime(now.year, now.month, now.day)).inHours / 24).round();
  return days <= 0 ? hm : days == 1 ? '$hm tomorrow' : '$hm on ${dayLabel(u)}';
}

/// What is said while wrong keys (for deep work mode, the safety check or changing the PIN: one count) pause the deep
/// work key: [what] cannot be done until when.
String keyPausedLine(Settings s, DateTime now, [String what = 'The safety check cannot be turned off']) =>
    'Too many wrong PINs. $what until ${pauseEndWords(now.add(fullModeLockLeft(s, now)), now)}.';

/// What a deep work PIN try says when it could not be saved on the device first, so the PIN was not checked (R10A-06).
const pinTryNotNoted = 'This try could not be saved, so the PIN was not checked. The device may be full. Free some '
    'space, then try again.';

/// Round 10 review A, R10A-06: a deep work PIN try (deep work mode, turning the safety check off, changing the PIN)
/// counts as a wrong key, and the count is saved, before the slow check begins, as the app passcode's tries are noted
/// first (R10A-05): ending Solace during the check, or once its answer shows, never loses the miss (before, it was
/// counted only after the check). A full save is fine here: these are rare steps. Returns the count before the try,
/// to put back if the PIN is right; null when the save did not reach the device within [noteTryLimit], and then
/// nothing is counted and the PIN must not be checked.
Future<FullModeCount?> countPinTry(AppState state, DateTime now) async {
  final s = state.data.settings;
  final untried = fullModeCount(s);
  fullModeWrongKey(s, now);
  try {
    if (await state.trySave().timeout(noteTryLimit)) return untried;
  } catch (_) {}
  restoreFullModeCount(s, untried);
  return null;
}

/// The deep work mode key, asked before the safety check is turned off (owner, 2026-11-15: "It should use the same 6
/// digit pin as deep work mode"). The same box as deep work mode's (digits only, hidden, a password to the Linux input
/// method, nothing learnt or suggested), checked by the same FullModeKey, and a wrong key counts toward the same
/// pause (core/full_mode_lock.dart), saved at once, even if the box has gone meanwhile. The key itself is never kept:
/// the box is emptied after each try. Closes with the number of wrong keys before the right one, or null.
class _ClassifierPinDialog extends StatefulWidget {
  const _ClassifierPinDialog({required this.state});
  final AppState state;
  @override
  State<_ClassifierPinDialog> createState() => _ClassifierPinDialogState();
}

class _ClassifierPinDialogState extends State<_ClassifierPinDialog> {
  final _pin = TextEditingController();
  String? _message;
  bool _checking = false;

  @override
  void dispose() {
    _pin.clear();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final state = widget.state, s = state.data.settings, now = state.clock();
    if (fullModeLockLeft(s, now) > Duration.zero) return setState(() => _message = keyPausedLine(s, now));
    setState(() => _checking = true);
    // counted as a wrong key and saved before the check (R10A-06), taken back if the PIN is right
    final untried = await countPinTry(state, now);
    if (untried == null) {
      if (!mounted) return;
      _pin.clear();
      return setState(() {
        _checking = false;
        _message = pinTryNotNoted;
      });
    }
    final tried = untried.fails;
    var ok = false;
    try {
      ok = await state.fullModeKey.matches(_pin.text);
    } catch (_) {
      ok = false; // never leaves the button disabled (F-17)
    }
    if (mounted) _pin.clear();
    // the right PIN: the try is taken back (the switch then clears the count and saves); a wrong one is already saved
    if (ok) restoreFullModeCount(s, untried);
    if (!mounted) return;
    if (ok) return Navigator.pop(context, tried);
    setState(() {
      _checking = false;
      final left = fullModeTries - s.fullModeFails;
      _message = left <= 0 ? keyPausedLine(s, now)
          : 'That PIN is not right. $left ${left == 1 ? 'try' : 'tries'} left before a pause.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final paused = fullModeLockLeft(widget.state.data.settings, widget.state.clock()) > Duration.zero;
    return PopScope(canPop: !_checking, child: AlertDialog(
      scrollable: true, // fits a small phone with the keyboard up and large text
      title: const Text('Turn off the safety check?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('The phrase checks stay on. Type your deep work PIN to turn the trained safety check off.'),
        const SizedBox(height: 10),
        TextField(autofillHints: PrivateKeyboard.autofillHints, enableIMEPersonalizedLearning: false, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck,
          key: const Key('classifier_pin'),
          controller: _pin,
          keyboardType: secretDigitsKeyboard, // a password to the Linux input method, as the deep work key (G7-07)
          inputFormatters: secretDigits,
          obscureText: true,
          maxLength: 6,
          autofocus: true,
          enabled: !paused,
          decoration: const InputDecoration(labelText: 'Deep work PIN (6 digits)', counterText: ''),
          onSubmitted: (_) => _checking || paused ? null : _check(),
        ),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(_message!, key: const Key('classifier_pin_message'),
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      actions: [
        TextButton(key: const Key('classifier_pin_cancel'), onPressed: _checking ? null : () => Navigator.pop(context),
            child: const Text('Keep it on')),
        FilledButton(key: const Key('classifier_pin_ok'), onPressed: _checking || paused ? null : _check,
            child: const Text('Turn off')),
      ],
    ));
  }
}

/// Changing the deep work PIN (owner, 2026-11-15). The current PIN first, checked by the key in force
/// (AppState.fullModeKey) and counted toward the same pause as deep work mode and the safety check; then the new PIN
/// twice. A weak new PIN (one digit six times, a straight run) or one the same as the current is refused, and said
/// why, before any key is tried. The new PIN is kept only as a fresh salted Argon2id fingerprint (FullModeKey.saved),
/// with the built key's memory and passes, in its own file beside the store, which Delete everything, Start fresh and
/// an import leave (AppState.changeFullModePin; round 9 review, 9A-01); every box is emptied after each try. Closes
/// with the number of wrong keys before the right one, or null.
class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog({required this.state});
  final AppState state;
  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _current = TextEditingController(), _next = TextEditingController(), _again = TextEditingController();
  String? _message;
  bool _checking = false;

  @override
  void dispose() {
    for (final c in [_current, _next, _again]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  void _clear() {
    for (final c in [_current, _next, _again]) {
      c.clear();
    }
  }

  Future<void> _save() async {
    final state = widget.state, s = state.data.settings, now = state.clock();
    if (fullModeLockLeft(s, now) > Duration.zero) {
      return setState(() => _message = keyPausedLine(s, now, 'The PIN cannot be changed'));
    }
    if (state.keptPinUnreadable) return setState(() => _message = keptPinUnreadableLine); // no try is counted
    final current = _current.text, next = _next.text;
    // what the new PIN must be is checked first, so a mistyped new PIN never costs a try
    final problem = FullModeKey.weakKeyReason(next) ??
        (next != _again.text ? 'The new PIN and the second one are different. Type the same new PIN twice.' : null) ??
        (next == current ? 'The new PIN is the same as the current one. Choose a different one.' : null);
    if (problem != null) {
      _next.clear();
      _again.clear();
      return setState(() => _message = problem);
    }
    setState(() => _checking = true);
    // counted as a wrong key and saved before the check (R10A-06), taken back if the current PIN is right
    final untried = await countPinTry(state, now);
    if (untried == null) {
      if (!mounted) return;
      _clear();
      return setState(() {
        _checking = false;
        _message = pinTryNotNoted;
      });
    }
    final tried = untried.fails;
    var ok = false;
    try {
      ok = await state.fullModeKey.matches(current);
    } catch (_) {
      ok = false; // never leaves the button disabled (F-17)
    }
    if (mounted) _current.clear();
    if (!ok) {
      // counted and saved before the check, even if the box has gone meanwhile (R10A-06)
      if (!mounted) return;
      _clear();
      final left = fullModeTries - s.fullModeFails;
      return setState(() {
        _checking = false;
        _message = left <= 0 ? keyPausedLine(s, now, 'The PIN cannot be changed')
            : 'That current PIN is not right. $left ${left == 1 ? 'try' : 'tries'} left before a pause.';
      });
    }
    restoreFullModeCount(s, untried); // the right PIN: the try is taken back (the change clears the count)
    Map<String, Object>? saved;
    try {
      saved = await state.builtInKey.saved(next);
    } catch (_) {}
    if (!mounted) return; // the box went meanwhile: nothing is changed
    _clear();
    // kept beside the store, where Delete everything, Start fresh and an import leave it (round 9 review, 9A-01)
    final stored = saved != null && await state.changeFullModePin(saved);
    if (!mounted) return;
    if (!stored) {
      return setState(() {
        _checking = false;
        _message = state.keptPinUnreadable ? keptPinUnreadableLine
            : 'The new PIN could not be saved on this device, so the current PIN still works. Try again.';
      });
    }
    Navigator.pop(context, tried);
  }

  Widget _box(String key, TextEditingController c, String label, bool enabled, {bool first = false}) => TextField(autofillHints: PrivateKeyboard.autofillHints,
        enableIMEPersonalizedLearning: false,
        autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions,
        spellCheckConfiguration: PrivateKeyboard.spellCheck,
        key: Key(key),
        controller: c,
        keyboardType: secretDigitsKeyboard, // a password to the Linux input method, as the deep work key (G7-07)
        inputFormatters: secretDigits,
        obscureText: true,
        maxLength: 6,
        autofocus: first,
        enabled: enabled,
        decoration: InputDecoration(labelText: label, counterText: ''),
      );

  @override
  Widget build(BuildContext context) {
    final paused = fullModeLockLeft(widget.state.data.settings, widget.state.clock()) > Duration.zero;
    final open = !paused && !_checking;
    return PopScope(canPop: !_checking, child: AlertDialog(
      scrollable: true, // fits a small phone with the keyboard up and large text
      title: const Text('Change deep work PIN'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Type your current PIN, then a new six-digit PIN twice. The new PIN opens deep work mode and turns '
            'off the safety check from then on.'),
        const SizedBox(height: 10),
        _box('change_pin_current', _current, 'Current PIN', open, first: true),
        _box('change_pin_new', _next, 'New PIN (6 digits)', open),
        _box('change_pin_confirm', _again, 'The new PIN again', open),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(_message!, key: const Key('change_pin_message'),
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      actions: [
        TextButton(key: const Key('change_pin_cancel'), onPressed: _checking ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(key: const Key('change_pin_save'), onPressed: open ? _save : null,
            child: const Text('Change PIN')),
      ],
    ));
  }
}

/// One settings section: its controls together on one card.
class _Group extends StatelessWidget {
  const _Group(this.children);
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(margin: EdgeInsets.zero, child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)));
}

/// Settings' line for the face and the voice: "Portrait 2 · Heart", or "A calm light · Bella".
String faceAndVoiceSummary(Settings s) {
  final face = s.presence == 'abstract' ? 'A calm light' : 'Portrait ${portraits.keys.toList().indexOf(s.portrait) + 1}';
  return '$face · ${(voices[s.voice] ?? '').split(':').first}';
}

/// Settings > Face and voice: the light or a portrait, and the voice (the same chooser as the first-run step).
class FaceAndVoiceScreen extends StatelessWidget {
  const FaceAndVoiceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // the chooser saves each choice itself; this screen rebuilds with it (AppScope listens to the state)
    return Scaffold(
      appBar: AppBar(title: const BarTitle('Face and voice')),
      body: Readable(child: ListView(padding: const EdgeInsets.fromLTRB(Space.xl - 4, Space.s, Space.xl - 4, Space.xxl),
          children: [
        Text('What you see and hear in calls and practices. Each portrait is illustrative and marked AI.',
            style: t.bodyMedium),
        const SizedBox(height: Space.l),
        const PresencePicker(),
      ])),
    );
  }
}
