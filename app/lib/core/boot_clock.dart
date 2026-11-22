// The device's boot clock (audit 216, G7-06): time since the device started, counting the time it spends asleep, and
// never set by hand, so neither sleep nor a changed device clock moves it. The app lock measures time away, the idle
// lock and the passcode wait with it (ui/app_lock.dart LockClock). Read through dart:ffi only, with no plugin and no
// platform channel, from libraries already in the process:
// - Linux and Android: clock_gettime(CLOCK_BOOTTIME) from libc;
// - iOS and macOS: mach_continuous_time(), scaled to nanoseconds by mach_timebase_info.
// Where neither can be read (Windows, a system without CLOCK_BOOTTIME, any failure), [bootClock] gives null and the
// lock falls back to what it used before: a stopwatch (which may not count sleep) and the wall clock. Tests replace
// [bootClock].
import 'dart:ffi';
import 'dart:io';

/// Time since the device started, asleep or not, or null when it cannot be read on this device. Tests replace it.
Duration? Function() bootClock = readBootClock;

/// The boot clock read through dart:ffi ([bootClock]), or null when it cannot be read here. Set up once, at first use.
Duration? readBootClock() {
  final read = _reader;
  if (read == null) return null;
  try {
    return read();
  } catch (_) {
    return null;
  }
}

final Duration? Function()? _reader = _open();

/// The reading function for this platform, checked with one reading, or null when there is none.
Duration? Function()? _open() {
  try {
    final read = Platform.isLinux || Platform.isAndroid ? _openLinux()
        : Platform.isIOS || Platform.isMacOS ? _openDarwin() : null;
    final first = read?.call();
    return first != null && !first.isNegative ? read : null;
  } catch (_) {
    return null; // a library or symbol missing: the stopwatch and the wall clock, as before
  }
}

typedef _MallocC = Pointer<Void> Function(IntPtr);
typedef _MallocD = Pointer<Void> Function(int);

const _clockBoottime = 7; // CLOCK_BOOTTIME in <linux/time.h>, the same on every Linux and Android

/// libc, with clock_gettime and malloc: the process itself, else libc by name.
DynamicLibrary _libc() {
  for (final open in [DynamicLibrary.process, () => DynamicLibrary.open(Platform.isAndroid ? 'libc.so' : 'libc.so.6')]) {
    try {
      final lib = open();
      if (lib.providesSymbol('clock_gettime') && lib.providesSymbol('malloc')) return lib;
    } catch (_) {}
  }
  throw StateError('no libc');
}

Duration? Function()? _openLinux() {
  final lib = _libc();
  // one struct timespec for the life of the process (two C longs: 16 bytes at most), never freed
  final ts = lib.lookupFunction<_MallocC, _MallocD>('malloc')(16);
  if (ts == nullptr) return null;
  if (sizeOf<IntPtr>() == 8) {
    // 64-bit: time_t and long are 64 bits
    final get = lib.lookupFunction<Int32 Function(Int32, Pointer<Int64>), int Function(int, Pointer<Int64>)>(
        'clock_gettime', isLeaf: true);
    final p = ts.cast<Int64>();
    return () => get(_clockBoottime, p) == 0 ? Duration(microseconds: p[0] * 1000000 + p[1] ~/ 1000) : null;
  }
  // 32-bit (older Android phones): time_t and long are 32 bits in the plain clock_gettime
  final get = lib.lookupFunction<Int32 Function(Int32, Pointer<Int32>), int Function(int, Pointer<Int32>)>(
      'clock_gettime', isLeaf: true);
  final p = ts.cast<Int32>();
  return () => get(_clockBoottime, p) == 0 ? Duration(microseconds: p[0] * 1000000 + p[1] ~/ 1000) : null;
}

Duration? Function()? _openDarwin() {
  final lib = DynamicLibrary.process();
  final ticks = lib.lookupFunction<Uint64 Function(), int Function()>('mach_continuous_time', isLeaf: true);
  final timebase = lib.lookupFunction<Int32 Function(Pointer<Uint32>), int Function(Pointer<Uint32>)>(
      'mach_timebase_info');
  final info = lib.lookupFunction<_MallocC, _MallocD>('malloc')(8).cast<Uint32>(); // {numer, denom}, read once
  if (info == nullptr) return null;
  final int numer, denom;
  try {
    if (timebase(info) != 0) return null;
    numer = info[0];
    denom = info[1];
  } finally {
    lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free')(info.cast());
  }
  if (numer == 0 || denom == 0) return null;
  return () {
    final t = ticks();
    if (t < 0) return null; // never: 2^63 ticks is centuries
    // ticks * numer / denom without overflowing: numer is at most a few hundred
    final ns = (t ~/ denom) * numer + (t % denom) * numer ~/ denom;
    return Duration(microseconds: ns ~/ 1000);
  };
}
