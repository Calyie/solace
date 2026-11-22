// The quiet timer and the sleep wind-down, counted from the clock rather than from ticks, so they stay right when a
// frame is missed or the phone sleeps for a while: the time left, pause and resume, which bells are due, and how loud
// the wind-down's sound should be. Pure Dart: the tests drive it with a clock of their own.
import 'bell.dart';

/// What the person chose for one sit.
class SitPlan {
  const SitPlan({required this.length, this.interval, this.startBell = true, this.endBell = true});
  final Duration length;
  final Duration? interval; // null: no interval bell
  final bool startBell, endBell;

  /// When the interval bells ring: every [interval] from the start, never at the very end (the ending bell is there).
  List<Duration> get intervalTimes {
    final every = interval;
    if (every == null || every <= Duration.zero) return const [];
    return [for (var t = every; t < length; t += every) t];
  }
}

enum SitState { ready, running, paused, finished, ended }

class SitTimer {
  SitTimer(this.plan, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final SitPlan plan;
  final DateTime Function() _clock;

  SitState _state = SitState.ready;
  DateTime? _since; // when the current stretch of sitting began (only while running)
  Duration _banked = Duration.zero; // the time sat before the last pause
  int _rung = 0; // interval bells rung so far

  SitState get state => _state;
  bool get running => _state == SitState.running;
  bool get over => _state == SitState.finished || _state == SitState.ended;

  Duration get _raw => _banked + (_state == SitState.running ? _clock().difference(_since!) : Duration.zero);

  /// The time sat so far, never more than the length.
  Duration get elapsed {
    final e = _raw;
    return e > plan.length ? plan.length : (e < Duration.zero ? Duration.zero : e);
  }

  Duration get left => plan.length - elapsed;

  /// From 0 at the start to 1 at the end.
  double get progress => plan.length <= Duration.zero ? 1 : elapsed.inMicroseconds / plan.length.inMicroseconds;

  /// Begins the sit; the starting bell rings, if it was chosen.
  List<BellKind> start() {
    if (_state != SitState.ready) return const [];
    _state = SitState.running;
    _since = _clock();
    return [if (plan.startBell) BellKind.start];
  }

  void pause() {
    if (_state != SitState.running) return;
    _banked = _raw;
    _since = null;
    _state = SitState.paused;
  }

  void resume() {
    if (_state != SitState.paused) return;
    _since = _clock();
    _state = SitState.running;
  }

  /// Ends early, by choice: no ending bell.
  void end() {
    if (over) return;
    _banked = elapsed;
    _since = null;
    _state = SitState.ended;
  }

  /// The bells due now; call it often. After a long gap (the phone asleep) at most one interval bell rings, never a
  /// burst of them, and once the time is up only the ending bell.
  List<BellKind> poll() {
    if (_state != SitState.running) return const [];
    final e = _raw;
    final times = plan.intervalTimes;
    if (e >= plan.length) {
      _banked = plan.length;
      _since = null;
      _state = SitState.finished;
      _rung = times.length;
      return [if (plan.endBell) BellKind.end];
    }
    var due = _rung;
    while (due < times.length && times[due] <= e) {
      due++;
    }
    if (due == _rung) return const [];
    _rung = due;
    return const [BellKind.interval];
  }
}

/// The sleep wind-down: the sound plays steadily, then fades to silence over the last third (at least five minutes),
/// and stops. Nothing rings at the end.
class WindDown {
  const WindDown(this.length);
  final Duration length;

  Duration get fade {
    final third = length ~/ 3;
    const least = Duration(minutes: 5);
    return third >= least ? third : (length < least ? length : least);
  }

  /// The volume (on the slider's scale, 0 to 1) at [elapsed], from [base] down to silence at the end. A straight line
  /// on the slider's scale, which the player turns into an even fade to the ear.
  double volumeAt(Duration elapsed, double base) {
    if (elapsed >= length) return 0;
    final fadeFrom = length - fade;
    if (elapsed <= fadeFrom) return base;
    return base * (1 - (elapsed - fadeFrom).inMilliseconds / fade.inMilliseconds);
  }
}
