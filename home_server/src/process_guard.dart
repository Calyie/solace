// What the gateway asks of the operating system for itself (docs/HOME_SERVER.md section 5): no core dumps, so a crash
// of the gateway or of llama-server never writes the conversations in their memory to disk (H19-10), and the user it
// runs as, so its private files can be checked as its own (H19-18). Plain libc calls through dart:ffi; nothing else.
import 'dart:ffi';
import 'dart:io';

final _libc = DynamicLibrary.process();

/// RLIMIT_CORE is 4 on Linux and macOS; struct rlimit is two 64-bit numbers (the soft and the hard limit) on both.
const _rlimitCore = 4;

/// Linux prctl options: PR_GET_DUMPABLE (3) and PR_SET_DUMPABLE (4).
const _prGetDumpable = 3, _prSetDumpable = 4;

/// What [noCoreDumps] managed: the core limit is 0 (soft and hard), and on Linux the process is not dumpable.
class CoreDumpsOff {
  const CoreDumpsOff({required this.limitZero, required this.notDumpable});
  final bool limitZero;

  /// Linux only (macOS has no such switch; its core dumps follow the limit alone).
  final bool notDumpable;
}

/// Turns core dumps off for this process: its core limit becomes 0, soft and hard, so every child it starts
/// (llama-server) inherits a limit it cannot raise; on Linux the process is also marked not dumpable. Never throws: a
/// call that fails is reported as not done.
CoreDumpsOff noCoreDumps() {
  var limit = false, dumpable = false;
  try {
    final malloc = _libc.lookupFunction<Pointer<Uint64> Function(IntPtr), Pointer<Uint64> Function(int)>('malloc');
    final free = _libc.lookupFunction<Void Function(Pointer<Uint64>), void Function(Pointer<Uint64>)>('free');
    final setrlimit = _libc.lookupFunction<Int32 Function(Int32, Pointer<Uint64>), int Function(int, Pointer<Uint64>)>(
        'setrlimit');
    final getrlimit = _libc.lookupFunction<Int32 Function(Int32, Pointer<Uint64>), int Function(int, Pointer<Uint64>)>(
        'getrlimit');
    final r = malloc(16);
    if (r.address != 0) {
      try {
        r[0] = 0;
        r[1] = 0;
        if (setrlimit(_rlimitCore, r) == 0) {
          r[0] = 1;
          r[1] = 1;
          limit = getrlimit(_rlimitCore, r) == 0 && r[0] == 0 && r[1] == 0;
        }
      } finally {
        free(r);
      }
    }
  } catch (_) {
    limit = false;
  }
  if (Platform.isLinux) {
    try {
      final prctl = _libc.lookupFunction<Int32 Function(Int32, VarArgs<(UnsignedLong,)>), int Function(int, int)>(
          'prctl');
      prctl(_prSetDumpable, 0);
      dumpable = prctl(_prGetDumpable, 0) == 0;
    } catch (_) {
      dumpable = false;
    }
  }
  return CoreDumpsOff(limitZero: limit, notDumpable: dumpable);
}

/// The id of the user this process runs as.
int currentUid() => _libc.lookupFunction<Uint32 Function(), int Function()>('getuid')();
