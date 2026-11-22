// The last line for errors nothing else caught (security review 2026-11-14, F-17). Without it, Flutter prints an
// uncaught error in full to the system log, even in a release build, and an error's message can hold the person's own
// decrypted words: a FormatException from jsonDecode quotes the text it could not read. So only the error's type is
// kept, never its message or its stack: printed with debugPrint in a debug build, and in a release build nothing is
// printed at all. The types stay in memory for this run only (for tests), and are never saved or sent anywhere.

import 'package:flutter/foundation.dart';

abstract final class ErrorLog {
  /// The types of the errors caught in this run, oldest first, at most [keep] of them.
  static final List<String> seen = [];
  static const keep = 20;

  /// Called once from main(): framework errors (a build, a layout, a gesture) and errors from futures nobody awaited.
  static void install() {
    FlutterError.onError = (details) => record(details.exception);
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error);
      return true; // handled: nothing more is printed
    };
  }

  static void record(Object error) {
    final type = error.runtimeType.toString();
    seen.add(type);
    if (seen.length > keep) seen.removeAt(0);
    if (kDebugMode) debugPrint('Solace caught an error: $type');
  }
}
