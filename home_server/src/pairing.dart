// The pairing window (docs/HOME_SERVER.md section 3): opened on the server by `solace-home pair`, which shows a
// one-time code. It lasts at most 10 minutes and pairs one device. The code never crosses the network; both sides prove
// they know it (app/home/home_protocol.dart pairProof).
//
// Limits are per address (H19-09: a stranger used to be able to hold every nonce, or close the window with five
// made-up proofs, so the owner's phone could not pair): each address may hold two unexpired nonces at once, and after
// five wrong proofs (a nonce left unused until it expires counts as one) that address may not try again while this
// window is open. Others still may. The window closes after 100 wrong proofs in all, far beyond any person's typing,
// and the owner can always open a new one with `solace-home pair` (a new code). Guessing the 60-bit code online is out
// of reach either way.
import 'dart:math';

import '../../app/home/home_protocol.dart';

class PairingWindow {
  PairingWindow(this.code, this.until);
  final String code;
  final DateTime until;
  int wrong = 0;

  /// Wrong proofs by address in this window.
  final wrongBy = <String, int>{};

  /// The unexpired nonces: when each expires, and the address it was given to.
  final nonces = <String, (DateTime, String)>{};
}

/// What a right proof gives the gateway: the phone's nonce and name, to finish with a new device.
class PairingProof {
  PairingProof(this.code, this.serverNonce, this.phoneNonce, this.name);
  final String code, serverNonce, phoneNonce, name;
}

/// Why a pairing step was refused: no window is open; this address has tried too often; or every nonce is taken by
/// others for the moment (pairing is busy: try again in a minute).
enum PairRefused { closed, tooMany, busy, wrong }

class Pairing {
  Pairing(this.random, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final Random random;
  final DateTime Function() clock;
  PairingWindow? _window;

  static const lasts = Duration(minutes: 10), nonceLasts = Duration(minutes: 2);
  static const mostWrongPerAddress = 5, mostWrong = 100, mostNoncesPerAddress = 2, mostNonces = 64;

  bool get isOpen {
    final w = _window;
    if (w == null) return false;
    if (clock().isAfter(w.until)) {
      _window = null;
      return false;
    }
    return true;
  }

  /// Opens a window and returns its code (any earlier window closes, with its counts).
  String open() {
    final code = newPairingCode(random);
    _window = PairingWindow(code, clock().add(lasts));
    return code;
  }

  void close() => _window = null;

  /// Expired nonces go; each counts as a wrong try for the address it was given to.
  void _sweep(PairingWindow w) {
    final now = clock();
    final gone = [for (final e in w.nonces.entries) if (now.isAfter(e.value.$1)) e.key];
    for (final n in gone) {
      final from = w.nonces.remove(n)!.$2;
      _wrong(w, from);
    }
  }

  void _wrong(PairingWindow w, String from) {
    w.wrongBy[from] = (w.wrongBy[from] ?? 0) + 1;
    if (++w.wrong >= mostWrong) _window = null;
  }

  bool _shutOut(PairingWindow w, String from) => (w.wrongBy[from] ?? 0) >= mostWrongPerAddress;

  /// A server nonce for a phone at [from] starting to pair, or why not.
  (String?, PairRefused?) start(String from) {
    if (!isOpen) return (null, PairRefused.closed);
    final w = _window!;
    _sweep(w);
    if (!isOpen) return (null, PairRefused.closed);
    if (_shutOut(w, from)) return (null, PairRefused.tooMany);
    if (w.nonces.values.where((v) => v.$2 == from).length >= mostNoncesPerAddress) return (null, PairRefused.tooMany);
    if (w.nonces.length >= mostNonces) return (null, PairRefused.busy);
    final n = randomText(random, 32);
    w.nonces[n] = (clock().add(nonceLasts), from);
    return (n, null);
  }

  /// Checks a phone's proof from [from] over the certificate [fingerprint] this server shows. A right proof closes the
  /// window (one device per code) and is returned; a wrong one counts against [from] (and toward the window's total).
  (PairingProof?, PairRefused?) check({required String serverNonce, required String phoneNonce, required String name,
      required String proof, required String fingerprint, required String from}) {
    if (!isOpen) return (null, PairRefused.closed);
    final w = _window!;
    _sweep(w);
    if (!isOpen) return (null, PairRefused.closed);
    if (_shutOut(w, from)) return (null, PairRefused.tooMany);
    final issued = w.nonces.remove(serverNonce);
    if (issued == null || phoneNonce.length < 16 || phoneNonce.length > 128) {
      _wrong(w, from);
      return (null, PairRefused.wrong);
    }
    final expected = pairProof(w.code, 'phone', fingerprint: fingerprint, serverNonce: serverNonce,
        phoneNonce: phoneNonce);
    if (!sameText(expected, proof)) {
      _wrong(w, from);
      return (null, PairRefused.wrong);
    }
    _window = null;
    return (PairingProof(w.code, serverNonce, phoneNonce, name), null);
  }
}
