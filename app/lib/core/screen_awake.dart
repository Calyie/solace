// Keeping the screen on while the quiet timer or the sleep wind-down runs (owner, 2026-11-14), without a package:
// the app's own channel to a few lines of platform code (iPhone: the idle timer; Android: FLAG_KEEP_SCREEN_ON on the
// window; Mac: a "no display sleep" power assertion). On the iPhone this matters most: when the screen locks, Solace
// is paused, so a bell would wait and the wind-down would stop. Linux keeps running with the screen off, so there it
// does nothing. Held and released in pairs, counted, so two screens cannot switch each other's hold off; any failure
// (tests, a platform without the code) is ignored: the timer still keeps the right time.
import 'dart:async';

import 'package:flutter/services.dart';

class ScreenAwake {
  ScreenAwake._();

  static const channel = MethodChannel('solace/screen');
  static int _holds = 0;

  /// How many screens are holding the screen on now (for tests).
  static int get holds => _holds;

  static void hold() {
    if (_holds++ == 0) _set(true);
  }

  static void release() {
    if (_holds == 0) return;
    if (--_holds == 0) _set(false);
  }

  static void _set(bool on) =>
      unawaited(channel.invokeMethod<void>('setKeepAwake', on).catchError((Object _) {}));
}
