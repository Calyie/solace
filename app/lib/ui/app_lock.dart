// The app lock and the app-switcher cover (research report P0 6; security review 2026-11-14, F-09 and AIR-2):
// with the lock on, Solace opens to a calm lock screen and unlocks only with the app's own six-digit passcode, on every
// device (owner, 2026-11-15: never the device's own unlock, by face, touch or its passcode, for anything). It locks
// again after the chosen time away. Support is always reachable from the lock screen: crisis numbers are never behind it.
// With "Hide in the app switcher" on, a cover hides the screen whenever the app is not in front, and Android 13 and
// later show a blank recent-apps preview (MainActivity.kt). Screenshots, screen recording and screen sharing are never
// blocked, on any device (owner, 2026-11-19: "remove this option you have that prevents screenshotting on solace").
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/app_lock.dart';
import '../core/lock_clock.dart';
import '../core/store.dart';
import '../core/session.dart' show SessionStillOpen;
import 'crisis.dart';
import 'desktop.dart' show appNavigatorKey;
import 'passphrase_screen.dart' show passphraseKeyboard;
import 'premium.dart';
import 'theme.dart';

export '../core/lock_clock.dart' show LockClock, LockMoment, lockClock, lockNow;

const _privacy = MethodChannel('solace/privacy');

/// Where the privacy channel hides the app-switcher preview natively while "Hide in the app switcher" is on: Android
/// (setRecentsScreenshotEnabled on Android 13 and later, MainActivity.kt), hidden from the first frame and shown only
/// if the person chose to show Solace in the app switcher. It never blocks screenshots or screen recording (owner,
/// 2026-11-19; until then Android used FLAG_SECURE and the Mac kept the window out of capture, C-06). Elsewhere the
/// app's own cover does it (the iPhone also draws one natively, SceneDelegate.swift). [os] is Platform.operatingSystem.
bool hidesSwitcherPreviewNatively(String os) => os == 'android';

/// Turns the lock on with a new app passcode, chosen now and typed twice, on every device (owner, 2026-11-15).
/// Returns whether the lock is now on. Used by Settings and by the first-run steps.
Future<bool> turnOnLock(BuildContext context, AppState state) async {
  final s = state.data.settings;
  final previous = s.passcode, needed = s.lockNeedsPasscode;
  final code = await choosePasscode(context);
  if (code == null) return false;
  final Map<String, String> hashed;
  try {
    hashed = await hashPasscode(code);
  } catch (_) {
    return false; // the lock stays off; the person can try again (F-17)
  }
  // round 6 review, E-01: on only once saved; a lock that could not be saved stays off, and the screen says so (it
  // showed on, and the next start opened unlocked)
  final saved = await state.saveSetting(() {
    s.passcode = hashed;
    s.appLock = true;
    s.lockNeedsPasscode = false; // the Settings note about the old lock has done its work
  }, () {
    s.appLock = false;
    s.passcode = previous;
    s.lockNeedsPasscode = needed;
  });
  if (!saved) {
    if (context.mounted) {
      sayNotSaved(context, 'This could not be saved, so the lock is still off. The device may be full. Free some '
          'space, then try again.');
    }
    return false;
  }
  feelDone();
  return true;
}

/// Round 9 review, 9A-02: once past the lock nothing asked again, so anyone holding the unlocked app for half a minute
/// could turn the lock off and come back later, or carry everything away. Before turning the app lock off, a longer
/// "Lock after", turning "Hide in the app switcher" off, Send everything (its file and code), the clinician PDF, CSV
/// and Markdown exports (ui/your_data.dart), Bring everything (it replaces all the data) and Delete everything (round 9
/// re-check: the exports, "Lock after" and Bring everything were added), the person proves again it is them with the
/// app passcode, the lock's only unlock on every device (owner, 2026-11-15), checked by [checkAppPasscode] with the
/// lock screen's own count of wrong tries and its wait. With the app lock off (or no passcode set: [lockIsOn]) there
/// is nothing to ask. Time away while the dialog shows is counted as any time away is ([AppLockGate], 9A-08).
/// [what] finishes "Type your passcode to ..." (for example "turn the lock off"). True when the change may go ahead; a
/// wrong passcode or Cancel changes nothing. Wrong passcodes tried before the right one are told, as after unlocking.
Future<bool> confirmItIsYou(BuildContext context, AppState state, {required String what}) async {
  if (!lockIsOn(state.data.settings)) return true;
  final before = await showDialog<int>(context: context, builder: (_) => _ConfirmPasscode(state: state, what: what));
  if (before == null) return false;
  if (before > 0 && context.mounted) {
    sayGently(context, 'Before this, a wrong passcode was entered $before ${before == 1 ? 'time' : 'times'}. If that '
        'was not you, someone may have tried to change your privacy settings or copy your data.');
  }
  return true;
}

/// What [checkAppPasscode] found: whether [code] was right, how many wrong tries came before a right one, and what to
/// say when it was not.
typedef PasscodeCheck = ({bool ok, int before, String? message});

/// Whether the app lock is on: switched on, with an app passcode to open it. Owner, 2026-11-15: the passcode is the
/// lock's only unlock, so a lock with none never locks anyone out; Settings.fromJson reads one saved that way (a phone
/// or Mac that used the device's own unlock before) as off, and Settings says the lock needs a passcode now.
bool lockIsOn(Settings s) => s.appLock && s.passcode != null;

/// What a try says when it could not be noted on the device first, so the passcode was not checked (R10A-05).
const tryNotNoted = 'This try could not be noted, so the passcode was not checked. The device may be full. Free '
    'some space, then try again.';

/// The longest a try waits for its miss to be noted on the device before the check, and the right passcode for the
/// note to be removed (R10A-05): a write that hangs never keeps the lock screen busy for good.
const noteTryLimit = Duration(seconds: 10);

/// The app passcode checked as the lock screen checks it, for the lock screen and [confirmItIsYou] alike: no try
/// while the wait after wrong ones runs (on the monotonic measure too, so setting the clock never shortens it: round 7
/// review, G7-06); the try counts as a miss before the check starts and is taken back only if [code] matches (round 5
/// review, C-04); five misses in a row start the wait (audit 2026-11-14, F-09).
///
/// Round 10 review A, R10A-05: the counted miss, and the wait it starts, is on the device before the check begins, in
/// the vault's small wrong-passcode record ([Vault.keepLockTries]), so ending Solace at any moment after that loses
/// nothing (before it, nothing has been checked, so nothing is learnt). A try whose miss could not be noted is not
/// checked at all ([tryNotNoted]). Misses noted by a copy of Solace that was ended before its save of the store
/// finished are counted first ([applyLockTries]). The right passcode removes the record and opens at once.
Future<PasscodeCheck> checkAppPasscode(AppState state, String code) async {
  final s = state.data.settings;
  final stored = s.passcode;
  // no app passcode: nothing to check against (the lock is then off: [lockIsOn])
  if (stored == null) {
    return (ok: false, before: 0, message: 'No passcode is set. Turn the lock on in Settings to choose one.');
  }
  try {
    applyLockTries(s, await state.vault.lockTries().timeout(noteTryLimit));
  } catch (_) {} // no record that can be read: the store's own count, as before
  final at = lockNow();
  final wait = lockWait(s, at.wall, mono: at.mono);
  if (wait != null) return (ok: false, before: 0, message: 'Too many tries. Try again in ${waitWords(wait)}.');
  final untried = (fails: s.lockFails, until: s.lockUntil, boot: s.lockBoot);
  recordLockFail(s, at.wall, mono: at.mono);
  if (!await _noteTry(state)) {
    // nothing was checked, so nothing is counted: the same try can be made once the device can note it
    s
      ..lockFails = untried.fails
      ..lockUntil = untried.until
      ..lockBoot = untried.boot;
    return (ok: false, before: 0, message: tryNotNoted);
  }
  var ok = false;
  try {
    ok = await passcodeMatches(code, stored);
  } catch (_) {
    ok = false; // a damaged stored passcode never leaves the button disabled (F-17); it simply does not match
  }
  if (ok) {
    final before = s.lockFails - 1; // the misses before this try, told afterwards (OWASP review OW-A09-1)
    s.lockFails = 0;
    s.lockUntil = null;
    s.lockBoot = null;
    // the record goes first (one small file, within a time limit), so its count is never counted again over the reset
    // one (R10A-05)
    await _forgetTries(state);
    // round 9 final, 9B-13 (owner approved, 2026-11-16): the right passcode opens at once and the reset count is saved
    // without waiting; a full save of the store takes seconds on a phone, and a stuck save must never keep the lock
    // up. A failed save still shows the usual banner (AppState.save). A wrong try below is still saved before its
    // answer, and its miss was on the device before the check began (R10A-05).
    unawaited(state.save());
    return (ok: true, before: before, message: null);
  }
  await state.save();
  final after = lockNow();
  final next = lockWait(s, after.wall, mono: after.mono);
  return (ok: false, before: 0, message: next != null ? 'That passcode did not match. Try again in ${waitWords(next)}.'
      : 'That passcode did not match. Try again.');
}

/// The wrong-passcode record ([Vault.keepLockTries]; R10A-05): the lock's count as it stands, for the passcode in
/// force. Bound to that passcode by its salt (new with every passcode set), so a record left from an earlier passcode
/// (the lock turned off and on again, Start fresh) never counts against a new one. Sealed by the vault like the store.
String lockTriesRecord(Settings s) =>
    jsonEncode({'v': 1, 'for': s.passcode?['salt'], 'fails': s.lockFails, 'until': s.lockUntil, 'boot': s.lockBoot});

/// Counts the misses in [record] (from [lockTriesRecord]) into [s] when it belongs to the passcode in force and holds
/// more than [s] does: misses noted before their check by a copy of Solace that was ended before its save of the store
/// finished. The record is taken whole then (its count, the wait it started and that wait's boot reading); one that
/// holds no more misses than [s], belongs to another passcode, or is not one this app wrote changes nothing (bounded:
/// at most 1,000 misses, a date, a boot reading within about 30 years). Returns whether [s] changed.
bool applyLockTries(Settings s, String? record) {
  final salt = s.passcode?['salt'];
  if (record == null || salt == null || record.length > 1024) return false;
  try {
    final j = jsonDecode(record);
    if (j is! Map || j['v'] != 1 || j['for'] != salt) return false;
    final fails = j['fails'], until = j['until'], boot = j['boot'];
    if (fails is! int || fails < 1 || fails > 1000 || fails <= s.lockFails) return false;
    if (until != null && (until is! String || until.length > 64 || DateTime.tryParse(until) == null)) return false;
    if (boot != null && (boot is! int || boot.abs() > 1000000000000000)) return false;
    s
      ..lockFails = fails
      ..lockUntil = until as String?
      ..lockBoot = boot as int?;
    return true;
  } catch (_) {
    return false;
  }
}

/// Notes the miss just counted on the device before its check (R10A-05): the vault's record, or, if that cannot be
/// kept, a full save of the store (slower, as lasting). False when neither reached the device within [noteTryLimit].
Future<bool> _noteTry(AppState state) async {
  try {
    await state.vault.keepLockTries(lockTriesRecord(state.data.settings)).timeout(noteTryLimit);
    return true;
  } catch (_) {}
  try {
    return await state.trySave().timeout(noteTryLimit);
  } catch (_) {
    return false;
  }
}

/// Removes the record after the right passcode (R10A-05). If it cannot be removed, a record of no misses is kept in
/// its place; if neither works, the record left counts this right try once as a miss, never fewer misses than there
/// were.
Future<void> _forgetTries(AppState state) async {
  try {
    await state.vault.forgetLockTries().timeout(noteTryLimit);
    return;
  } catch (_) {}
  try {
    await state.vault.keepLockTries(lockTriesRecord(state.data.settings)).timeout(noteTryLimit);
  } catch (_) {}
}

/// The app passcode asked again before a change that undoes the lock or carries everything away ([confirmItIsYou]).
/// Closes with the wrong tries before the right one, or null (Cancel).
class _ConfirmPasscode extends StatefulWidget {
  const _ConfirmPasscode({required this.state, required this.what});
  final AppState state;
  final String what;
  @override
  State<_ConfirmPasscode> createState() => _ConfirmPasscodeState();
}

class _ConfirmPasscodeState extends State<_ConfirmPasscode> {
  final _code = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return; // one check at a time, set before the first await (C-04)
    setState(() => _busy = true);
    final result = await checkAppPasscode(widget.state, _code.text);
    _code.clear();
    if (!mounted) return;
    if (result.ok) return Navigator.pop(context, result.before);
    setState(() {
      _busy = false;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: AlertDialog(
        scrollable: true, // fits a small phone with the keyboard up and large text
        title: const Text('Confirm it is you'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Type your $appName passcode to ${widget.what}.'),
          const SizedBox(height: Space.s),
          TextField(autocorrect: PrivateKeyboard.autocorrect,
              enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck,
              autofillHints: PrivateKeyboard.autofillHints, key: const Key('confirm_passcode'), controller: _code,
              obscureText: true, keyboardType: secretDigitsKeyboard, inputFormatters: secretDigits, maxLength: 6,
              autofocus: true, enableIMEPersonalizedLearning: false,
              onSubmitted: (_) => _busy ? null : _check(),
              decoration: const InputDecoration(hintText: 'Passcode', counterText: '')),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: Space.s),
              child: Text(_message!, key: const Key('confirm_passcode_message'),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        actions: [
          TextButton(key: const Key('confirm_passcode_cancel'), onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(key: const Key('confirm_passcode_ok'), onPressed: _busy ? null : _check,
              child: const Text('Confirm')),
        ],
      ));
}

/// The keyboard type of a secret six-digit box: the app passcode and the deep work key (round 7 review, G7-07). On
/// Linux it is the passphrase boxes' type ([passphraseKeyboard], round 6 review, E-06), the only one Flutter's Linux
/// embedder passes to the input method as a password (a number is passed as an ordinary number, to be predicted from
/// or learnt); on phones the number keypad stays. [secretDigits] keeps the box to digits either way.
TextInputType get secretDigitsKeyboard =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux ? passphraseKeyboard : TextInputType.number;

/// Digits only, for the boxes of [secretDigitsKeyboard] (on Linux its keyboard type lets letters through).
final secretDigits = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

/// What choosing the passcode says first (round 9 final, 9A-10): since the owner's decision of 2026-11-15 nothing else
/// opens the lock on any device, and the data is kept out of every backup, so a forgotten passcode cannot be got back.
const forgottenPasscodeWarning = 'If you forget this passcode, nobody can open $appName or get your data back, not even '
    'by reinstalling. Keep it somewhere safe. Now and then, make a fresh transfer file in Settings > Your data > Send '
    'everything to another device.';

/// The app's own passcode, chosen and typed twice when the lock is turned on (the only place one is set or changed:
/// [turnOnLock]). The person ticks that they have read [forgottenPasscodeWarning] before it is saved (9A-10).
Future<String?> choosePasscode(BuildContext context) => showDialog<String>(context: context, builder: (context) {
      final first = TextEditingController(), second = TextEditingController();
      String? problem;
      var understood = false;
      return StatefulBuilder(builder: (context, setState) => AlertDialog(
        scrollable: true, // the warning fits a small phone with the keyboard up and large text
        title: const Text('Choose a six-digit passcode'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(forgottenPasscodeWarning, key: Key('passcode_warning')),
          const SizedBox(height: 8),
          TextField(autofillHints: PrivateKeyboard.autofillHints, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('passcode_first'), controller: first, obscureText: true, maxLength: 6,
              keyboardType: secretDigitsKeyboard, inputFormatters: secretDigits, enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(hintText: 'Passcode', counterText: '')),
          const SizedBox(height: 8),
          TextField(autofillHints: PrivateKeyboard.autofillHints, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('passcode_second'), controller: second, obscureText: true, maxLength: 6,
              keyboardType: secretDigitsKeyboard, inputFormatters: secretDigits, enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(hintText: 'The same again', counterText: '')),
          const SizedBox(height: 8),
          CheckboxListTile(key: const Key('passcode_understood'), value: understood, contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I understand that a forgotten passcode cannot be recovered'),
              onChanged: (v) => setState(() {
                understood = v ?? false;
                if (understood) problem = null;
              })),
          if (problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(problem!)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('passcode_save'), onPressed: () {
            if (!isPasscode(first.text)) return setState(() => problem = 'Use exactly six digits.');
            if (first.text != second.text) return setState(() => problem = 'The two passcodes are different.');
            if (!understood) {
              return setState(() => problem = 'Please tick the box first, to say you have read what happens if it '
                  'is forgotten.');
            }
            Navigator.pop(context, first.text);
          }, child: const Text('Save')),
        ],
      ));
    });

/// Whether [limit] has passed since [then] (round 7 review, G7-06): by the wall clock or by the monotonic measure,
/// whichever says more, and always when the wall clock went backwards meanwhile (it fell behind the monotonic measure
/// by more than a second), since a clock set back is what kept the lock from coming down.
bool timePassed(LockMoment then, Duration limit, [LockMoment? now]) {
  final n = now ?? lockNow();
  final wall = n.wall.difference(then.wall), mono = n.mono - then.mono;
  if (wall < mono - const Duration(seconds: 1)) return true;
  return wall >= limit || mono >= limit;
}

/// The wait after [fails] wrong passcodes in a row, in seconds: 30 after five, doubling to an hour.
int lockWaitSeconds(int fails) => (30 * (1 << (fails - 5).clamp(0, 7))).clamp(30, 3600);

/// Where the passcode wait running now ends on the monotonic measure, for the saved wait it belongs to (round 7
/// review, G7-06: a clock set forward ended the wait at once). Kept while this copy of Solace runs.
({String until, Duration mono})? _waitEnds;

/// A fresh start, as far as the passcode wait is concerned (tests).
@visibleForTesting
void forgetLockWaitForTest() => _waitEnds = null;

/// Wrong app passcodes (audit 2026-11-14, F-09: there was no limit): after 5 in a row, a 30-second wait, doubling with
/// each further miss up to an hour; kept in the encrypted store so closing the app does not reset it. [mono] (the
/// monotonic measure now) keeps the wait running on it while Solace runs (round 7 review, G7-06). When it is the boot
/// clock ([LockClock.countsSleep]), its reading is saved with the wait ([Settings.lockBoot]; audit 216, G7-06), so the
/// wait also runs on it after Solace is closed and opened again.
void recordLockFail(Settings s, DateTime now, {Duration? mono}) {
  s.lockFails++;
  if (s.lockFails >= 5) {
    final seconds = lockWaitSeconds(s.lockFails);
    _beginWait(s, now, Duration(seconds: seconds), _bootOf(mono));
    if (mono != null) _waitEnds = (until: s.lockUntil!, mono: mono + Duration(seconds: seconds));
  }
}

/// [mono] when it is a boot-clock reading, which means the same in the next copy of Solace; otherwise null.
Duration? _bootOf(Duration? mono) => bootReading(mono);

/// The saved wait begins (again) now and runs [full]: its end by the wall clock, and the boot clock's reading now
/// ([boot]; none when the boot clock cannot be read, and the wait then goes by the wall clock alone once Solace is
/// closed, as before).
void _beginWait(Settings s, DateTime now, Duration full, Duration? boot) {
  s.lockUntil = now.add(full).toIso8601String();
  s.lockBoot = boot?.inMicroseconds;
}

/// How long until another passcode may be tried, or null now.
///
/// Round 7 review, G7-06: while Solace runs the wait also runs on the monotonic measure ([mono]), so setting the
/// clock forward does not end it; and a saved wait whose clock was set back since it began runs in full from now:
/// never cut short, and never longer than it was set for (a clock reset to a past year must not lock Solace for
/// years).
///
/// Audit 216, G7-06: a saved wait also runs on the boot clock, which counts time asleep and cannot be set, so closing
/// Solace and setting the clock forward never ends it early. The time passed since the wait began is the smaller of
/// what the wall clock and the boot clock say, and never less than nothing (a clock set back never shortens it). When
/// the boot clock reads less than it did when the wait began, the device has restarted and nothing counts as passed:
/// the wait starts again from now. Where the boot clock cannot be read, a saved wait goes by the wall clock once
/// Solace is closed, as before.
Duration? lockWait(Settings s, DateTime now, {Duration? mono}) {
  final until = DateTime.tryParse(s.lockUntil ?? '');
  if (until == null) return null;
  final full = Duration(seconds: lockWaitSeconds(s.lockFails));
  final boot = _bootOf(mono);
  var left = until.difference(now);
  final saved = s.lockBoot;
  if (left > full) {
    left = full; // the clock went back since the wait began
    _beginWait(s, now, full, boot);
  } else if (boot != null && saved != null) {
    final byBoot = boot - Duration(microseconds: saved), byWall = now.difference(until.subtract(full));
    if (byBoot.isNegative) {
      left = full; // the device restarted since the wait began: nothing counts as passed
      _beginWait(s, now, full, boot);
    } else {
      final passed = byBoot < byWall ? byBoot : byWall;
      final byBoth = full - (passed.isNegative ? Duration.zero : passed);
      if (byBoth > left) left = byBoth;
    }
  } else if (boot != null && left > Duration.zero) {
    // a wait saved without a boot reading (by an earlier version, or with no boot clock then): from now on it runs on
    // the boot clock too, as if both clocks had agreed since it began
    s.lockBoot = (boot - (full - left)).inMicroseconds;
  }
  if (mono != null) {
    final w = _waitEnds;
    if (w != null && w.until == s.lockUntil) {
      final m = w.mono - mono;
      if (m > left) left = m;
    } else if (left > Duration.zero) {
      _waitEnds = (until: s.lockUntil!, mono: mono + left); // from now on it runs on the monotonic measure too
    }
  }
  if (left > Duration.zero) return left;
  if (boot != null) {
    // over by every measure, the boot clock included: forgotten, so a later restart of the device cannot start a wait
    // that has already run its course again (the next wrong passcode starts a new one, as before)
    s.lockUntil = null;
    s.lockBoot = null;
  }
  return null;
}

String waitWords(Duration d) => d.inSeconds < 90 ? '${d.inSeconds} seconds' : '${(d.inSeconds / 60).ceil()} minutes';

/// Wrong passcodes tried before the last unlock, passed from the lock screen to the gate.
int tried = 0;

/// Whether the lock screen is showing now; the desktop menus and shortcuts do nothing behind it (OWASP OW-M3-1), and
/// a voice call pauses (ui/call.dart; round 4 review, B-10).
final appLocked = ValueNotifier<bool>(false);

/// True while a voice call is live: listening, speaking or preparing her reply (ui/call.dart). On a computer it counts
/// as activity for the idle lock, as the mouse and keys do (round 4 review, B-10: a hands-free call has neither, so
/// the lock came down in the middle of it).
bool callLive = false;

/// The lock screen's own navigator, there only while the app is locked ([showFlaggedSupport]).
final _lockNavigator = GlobalKey<NavigatorState>();

/// The support screen for a crisis the safety checks flagged (the chat, a call). While the app is locked it opens
/// over the lock screen, as the lock screen's Get support now does, without the safety plan (round 4 review, B-10: a
/// crisis heard on a call behind the lock opened its sheet under the lock, out of sight); otherwise over the app.
Future<void> showFlaggedSupport(BuildContext context) {
  final lock = _lockNavigator.currentContext;
  if (lock != null) return showCrisisSheet(lock, flagged: true, plan: false);
  return showCrisisSheet(context, flagged: true);
}

/// Owner, 2026-11-15, OWNER-C1: a crisis a session finds is met by a support card inside the conversation (ui/crisis.dart
/// CrisisCard), and Solace's reply follows it, so nothing covers the chat. Where the conversation cannot be seen, the
/// full support screen still opens at once, as before: over the lock screen while the app is locked (round 4 review,
/// B-10), and over the app while the session's screen ([route]) is covered by another screen, the app is out of sight,
/// or the conversation is closing ([closing]). [away]: the app was out of sight when the crisis was found (appAway,
/// read then: no frame runs in the background, so this is called only once the person is back). True when it opened.
bool supportWhereUnseen(BuildContext context, {ModalRoute<dynamic>? route, bool closing = false, bool away = false}) {
  final covered = route != null && !route.isCurrent;
  if (_lockNavigator.currentContext == null && !away && !appAway() && !covered && !closing) return false;
  unawaited(showFlaggedSupport(context));
  return true;
}

/// True while the app is out of sight (in the background, hidden, or closing down).
bool appAway() {
  final life = WidgetsBinding.instance.lifecycleState;
  return life == AppLifecycleState.hidden || life == AppLifecycleState.paused || life == AppLifecycleState.detached;
}

/// Back while Solace is locked (round 5 review, C-07): Android's Back went to the app's own navigator under the lock
/// screen, so someone holding the locked phone could close the screen open under it unseen (a session left without
/// End keeps nothing of the conversation). The binding asks its observers in the order they were added, and the app's
/// navigator (MaterialApp) is one of them, so this guard sits above MaterialApp (main.dart TherapistApp) to be asked
/// first: while the lock screen shows, Back closes only what is open over the lock screen (the support sheet) and
/// otherwise does nothing; unlocked, Back works as usual. The lock screen's own route refuses to be popped
/// ([_LockScreenState.build]), so Android keeps sending Back to the app while locked rather than handling it itself
/// (which on older Android closes the app, and the session under the lock with it).
class LockBackGuard extends StatefulWidget {
  const LockBackGuard({super.key, required this.child});
  final Widget child;
  @override
  State<LockBackGuard> createState() => _LockBackGuardState();
}

class _LockBackGuardState extends State<LockBackGuard> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    final lock = _lockNavigator.currentState; // there only while the lock screen shows
    if (lock == null) return false;
    await lock.maybePop(); // the support sheet over the lock screen, if open; never the lock screen itself
    return true; // nothing under the lock is told
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = true, _covered = false;
  // Android starts with its recent-apps preview hidden (MainActivity.onCreate); shown only if chosen
  bool _previewHidden = true;
  int _tried = 0;
  LockMoment? _away; // both measures (round 7 review, G7-06)

  // On a computer the window can stay open and visible while the person is away from it: with the lock on, a minute
  // or more (the chosen time) with no mouse or keyboard locks it too (OWASP review OW-M3-1), measured as time away is
  // ([timePassed], round 7 review, G7-06)
  LockMoment _lastActivity = lockNow();
  Timer? _idle;
  static bool get _desktop => const {TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.windows}
      .contains(defaultTargetPlatform);

  bool _onKey(KeyEvent _) {
    _lastActivity = lockNow();
    return false;
  }

  void _checkIdle() {
    if (!mounted) return;
    final s = AppScope.of(context).data.settings;
    final minutes = s.lockAfterMinutes < 1 ? 1 : s.lockAfterMinutes;
    if (callLive) _lastActivity = lockNow(); // a live call is the person there, hands-free (B-10)
    if (lockIsOn(s) && !_locked && timePassed(_lastActivity, Duration(minutes: minutes))) {
      setState(() => _locked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_desktop) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _idle = Timer.periodic(const Duration(seconds: 30), (_) => _checkIdle());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context).data.settings;
    if (!lockIsOn(s)) _locked = false;
    _applyPreview(s.hideInSwitcher);
  }

  void _applyPreview(bool on) {
    if (on == _previewHidden || kIsWeb || !hidesSwitcherPreviewNatively(Platform.operatingSystem)) return;
    _previewHidden = on;
    unawaited(_privacy.invokeMethod('setRecentsHidden', on).catchError((Object _) => null));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    if (_desktop) HardwareKeyboard.instance.removeHandler(_onKey);
    appLocked.value = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = AppScope.of(context).data.settings;
    // round 9 re-check, 9A-08: time away is time away whatever is open, a passcode confirm included ([confirmItIsYou]
    // asks in Solace's own dialog, never a system prompt, so nothing here is ignored or waits for a prompt to end):
    // leaving at a confirm in Settings and coming back after "Lock after" brings the lock screen down over it
    if (state == AppLifecycleState.inactive && !_desktop) {
      // a phone's app switcher, a notification or a system sheet: cover the screen, but this is not leaving the app
      if (s.hideInSwitcher && !_covered) setState(() => _covered = true);
    } else if (state == AppLifecycleState.inactive) {
      // a computer: the window lost focus, the person may have walked away from it; counts as away (verification
      // round 2: an unfocused, visible window must lock again after the chosen time)
      _away ??= lockNow();
    } else if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _away ??= lockNow();
      if (s.hideInSwitcher && !_covered) setState(() => _covered = true);
    } else if (state == AppLifecycleState.resumed) {
      _judgeAway(s);
    }
  }

  /// Back in front: locks when the lock is on and the time away has passed "Lock after".
  void _judgeAway(Settings s) {
    final away = _away;
    _away = null;
    setState(() {
      _covered = false;
      // the wall clock or the monotonic measure, and always if the clock went back meanwhile (G7-06)
      if (lockIsOn(s) && away != null && timePassed(away, Duration(minutes: s.lockAfterMinutes))) _locked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).data.settings;
    _applyPreview(s.hideInSwitcher);
    final locked = lockIsOn(s) && _locked;
    if (appLocked.value != locked) WidgetsBinding.instance.addPostFrameCallback((_) => appLocked.value = locked);
    return Stack(children: [
      // the app stays built underneath, so a session in progress is not lost while locked
      // nothing under the lock can take the keyboard (verification round 2: a focused chat box could get typing)
      Offstage(offstage: locked, child: ExcludeFocus(excluding: locked, child: TickerMode(enabled: !locked, child: Listener(
          onPointerDown: (_) => _lastActivity = lockNow(),
          onPointerHover: (_) => _lastActivity = lockNow(),
          onPointerSignal: (_) => _lastActivity = lockNow(),
          child: widget.child)))),
      // its own navigator, so Get support can open the crisis sheet over the lock screen
      // (its own hero scope: a navigator may not share the app's, found by test/onboarding_test.dart)
      if (locked) Positioned.fill(child: HeroControllerScope.none(child: Navigator(key: _lockNavigator,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => _LockScreen(onUnlocked: () => setState(() {
                _locked = false;
                _tried = tried;
                tried = 0;
              })))))),
      if (_covered && !locked) const _Cover(),
      // wrong passcodes tried while the person was away are never silent (OWASP review OW-A09-1)
      // (above the app's navigator, so no tooltips or list tiles here: they need an overlay)
      if (!locked && !_covered && _tried > 0) Positioned(left: 12, right: 12, top: 0, child: SafeArea(child: Material(
          key: const Key('lock_tries_notice'), elevation: 2, borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s), child: Row(children: [
            const Icon(Icons.warning_amber_rounded),
            const SizedBox(width: Space.m),
            Expanded(child: Text('$_tried wrong ${_tried == 1 ? 'passcode was' : 'passcodes were'} tried since Solace '
                'was last opened.')),
            TextButton(key: const Key('lock_tries_close'), onPressed: () => setState(() => _tried = 0),
                child: const Text('Close')),
          ]))))),
    ]);
  }
}

/// What the app switcher shows while Solace is not in front: the page colour and the name, nothing private.
class _Cover extends StatelessWidget {
  const _Cover();
  @override
  Widget build(BuildContext context) => Positioned.fill(child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(child: Text(appName, style: Theme.of(context).textTheme.headlineMedium)),
      ));
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlocked});
  final VoidCallback onUnlocked;
  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _code = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _tryCode() async {
    // one check at a time (round 5 review, C-04): a code sent with Return while a check runs is ignored, never tried
    // alongside it, so the wait after five misses always holds. _busy is set below before the first await.
    if (_busy) return;
    final state = AppScope.of(context);
    setState(() => _busy = true);
    // the wait, the miss counted before the check and the saved count (C-04, G7-06): one check, shared with
    // confirmItIsYou (round 9 review, 9A-02)
    final result = await checkAppPasscode(state, _code.text);
    _code.clear();
    if (!mounted) return;
    if (result.ok) tried = result.before; // told after unlocking (OWASP review OW-A09-1)
    setState(() {
      _busy = false;
      _message = result.message;
    });
    if (result.ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // the lock screen is never popped by Back (C-07): with this, Android hands Back to the app while locked, where
    // LockBackGuard keeps it from the screens under the lock
    return PopScope(canPop: false, child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(child: Readable(maxWidth: 420, selectable: false, child: FillOrScroll(padding: const EdgeInsets.all(Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Spacer(),
        // the same mark and title size as the lock's first-run step
        const Center(child: IconDisc(Icons.lock_outline, size: 72)),
        const SizedBox(height: Space.xl),
        Text('$appName is locked', style: t.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.s),
        // the app passcode only, on every device (owner, 2026-11-15)
        Text('Enter your six-digit passcode.', style: t.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.xl),
        TextField(autofillHints: PrivateKeyboard.autofillHints, autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions, spellCheckConfiguration: PrivateKeyboard.spellCheck, key: const Key('lock_code'), controller: _code, obscureText: true, keyboardType: secretDigitsKeyboard,
            inputFormatters: secretDigits, maxLength: 6, autofocus: true, enableIMEPersonalizedLearning: false, textAlign: TextAlign.center,
            onSubmitted: (_) => _busy ? null : _tryCode(), // ignored while a check runs (C-04)
            // the digits as spaced dots; the cursor shows once typing starts, so it never sits across the word
            // Passcode in the middle of the empty box
            onChanged: (_) => setState(() {}), showCursor: _code.text.isNotEmpty,
            style: t.titleLarge?.copyWith(letterSpacing: 6), obscuringCharacter: '●',
            decoration: InputDecoration(hintText: 'Passcode', counterText: '',
                hintStyle: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: Space.s),
            child: Text(_message!, textAlign: TextAlign.center, style: t.bodySmall)),
        const SizedBox(height: Space.m),
        FilledButton(key: const Key('lock_unlock'), onPressed: _busy ? null : _tryCode, child: const Text('Unlock')),
        // round 9 final, 9A-10 and 9B-12: a forgotten passcode cannot be got back, so the only way on is to delete
        // everything and start again ([_ForgottenPasscode]); nothing under the lock is shown or opened
        TextButton(key: const Key('lock_forgot'), onPressed: _busy ? null : () => showDialog<void>(context: context,
            builder: (_) => const _ForgottenPasscode()), child: const Text('Forgotten your passcode?')),
        const Spacer(),
        // support is never behind the lock
        TextButton.icon(key: const Key('lock_support'), onPressed: () => showCrisisSheet(context, plan: false),
            icon: Icon(Icons.favorite_outline, color: Theme.of(context).colorScheme.error),
            label: const Text('Get support now')),
      ])))),
    ));
  }
}

/// "Forgotten your passcode?" on the lock screen (round 9 final, 9A-10 and 9B-12). Nothing but the passcode opens the
/// lock, so the only way back to a working app is Delete everything (AppState.wipeEverything), after a plain warning
/// and DELETE typed; Cancel deletes nothing. It never shows, opens or copies anything under the lock: the data goes,
/// and Solace starts again at its first-run steps. Someone else holding the locked device gains nothing they could not
/// already do by clearing Solace's data in the system settings or reinstalling it. Support stays on the lock screen.
class _ForgottenPasscode extends StatefulWidget {
  const _ForgottenPasscode();
  @override
  State<_ForgottenPasscode> createState() => _ForgottenPasscodeState();
}

class _ForgottenPasscodeState extends State<_ForgottenPasscode> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _confirmed => _typed.text.trim().toUpperCase() == 'DELETE';

  Future<void> _delete() async {
    if (_busy || !_confirmed) return; // one delete at a time, set before the first await
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (state.changingData) {
      return setState(() => _message = 'Solace is still bringing in or deleting data. Please wait until it has '
          'finished, then try again. Nothing was deleted.');
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    // round 9 final, 9A-11: the screens left open under the lock close BEFORE anything is deleted, so none of them is
    // seen or used while the lock comes down part-way through the wipe (this dialog is on the lock's own navigator)
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    // round 9 final, 9B-15: those screens go only once the lock is down (the app's animations are paused under it),
    // so their conversations are ended now, as leaving the screen would, instead of the delete being refused
    state.openSessions.leaveAll();
    String? problem;
    try {
      await state.wipeEverything();
    } on SessionStillOpen {
      problem = 'A conversation was still closing, so nothing was deleted yet. Tap Delete everything again.';
    } catch (_) {
      problem = 'Not everything could be deleted. Try again.';
    }
    // with the data gone the lock is off, so the lock screen (and this dialog with it) has closed: the screens left
    // open under it go too, and Solace shows its first-run steps
    if (!lockIsOn(state.data.settings)) appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    if (!mounted) {
      if (problem != null) {
        messenger?.showSnackBar(const SnackBar(content: Text('Not everything could be deleted. Open Settings and use '
            'Delete everything to try again.')));
      }
      return;
    }
    if (problem == null) return Navigator.pop(context);
    setState(() {
      _busy = false;
      _message = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(canPop: !_busy, child: AlertDialog(
      scrollable: true, // fits a small phone with the keyboard up and large text
      title: const Text('Forgotten your passcode?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Nothing but the passcode opens $appName, and nobody can get it back for you. To use $appName '
            'again, you can delete everything it keeps on this device and start afresh.'),
        const SizedBox(height: Space.s),
        const Text('This deletes every conversation, note, score and setting, and the model, voice and safety files. '
            'It cannot be undone. A transfer file you made before can bring your data back afterwards, with its code.'),
        const SizedBox(height: Space.m),
        const Text('Type DELETE to confirm.', style: TextStyle(fontWeight: FontWeight.w600)),
        TextField(autofillHints: PrivateKeyboard.autofillHints,
            autocorrect: PrivateKeyboard.autocorrect, enableSuggestions: PrivateKeyboard.suggestions,
            spellCheckConfiguration: PrivateKeyboard.spellCheck, enableIMEPersonalizedLearning: false,
            key: const Key('forgot_typed'), controller: _typed, enabled: !_busy, maxLength: 20,
            textCapitalization: TextCapitalization.characters, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'DELETE', counterText: '')),
        if (_busy) const Padding(key: Key('forgot_progress'), padding: EdgeInsets.only(top: Space.s),
            child: Text('Deleting everything. This usually takes a few seconds.')),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: Space.s),
            child: Text(_message!, key: const Key('forgot_message'), style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      actions: [
        // round 9 final, 9B-14: support is reachable from this dialog too, also while the delete runs
        TextButton.icon(key: const Key('forgot_support'), onPressed: () => showCrisisSheet(context, plan: false),
            icon: Icon(Icons.favorite_outline, color: scheme.error), label: const Text('Get support now')),
        TextButton(key: const Key('forgot_cancel'), onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(key: const Key('forgot_delete'),
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: _busy || !_confirmed ? null : _delete, child: const Text('Delete everything')),
      ],
    ));
  }
}

/// Round 9 final, 9A-09: a lock that used the device's own unlock before (or an app passcode saved by a version before
/// 2026-11-15 on a phone or Mac, 9B-12) reads as off until a passcode is chosen, and only a note in Settings said so.
/// This notice on Today says it once: Choose a passcode opens the same steps as Settings ([turnOnLock]), and Not now
/// closes it for good on this device ([Settings.lockNoticeClosed], never carried by an import). It never blocks
/// anything, and it goes once a passcode is chosen.
class LockNeedsPasscodeNotice extends StatelessWidget {
  const LockNeedsPasscodeNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.data.settings;
    if (lockIsOn(s) || !s.lockNeedsPasscode || s.lockNoticeClosed) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme, t = Theme.of(context).textTheme;
    final on = scheme.onPrimaryContainer;
    return Card(key: const Key('lock_notice'), color: scheme.primaryContainer, margin: const EdgeInsets.only(bottom: Space.m),
        child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_open_outlined, color: on),
            const SizedBox(width: Space.m),
            Expanded(child: Text('The lock is off until you choose a passcode for $appName',
                style: t.titleSmall?.copyWith(color: on))),
          ]),
          const SizedBox(height: Space.s),
          Text('After this update, the lock opens only with a six-digit passcode of $appName\'s own, never with this '
              'device\'s unlock. Until you choose one, anyone using this device can open $appName.',
              style: t.bodyMedium?.copyWith(color: on)),
          const SizedBox(height: Space.s),
          Align(alignment: AlignmentDirectional.centerEnd, child: Wrap(spacing: Space.s, alignment: WrapAlignment.end,
              children: [
            TextButton(key: const Key('lock_notice_close'), onPressed: () async {
              if (!await state.saveSetting(() => s.lockNoticeClosed = true, () => s.lockNoticeClosed = false) &&
                  context.mounted) {
                sayNotSaved(context);
              }
            }, child: const Text('Not now')),
            FilledButton(key: const Key('lock_notice_choose'), onPressed: () => turnOnLock(context, state),
                child: const Text('Choose a passcode')),
          ])),
        ])));
  }
}
