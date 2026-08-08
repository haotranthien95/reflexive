import 'dart:async';

/// A whole-second countdown that can be frozen and resumed in place (D-24).
///
/// This is the phase's ONE timing primitive: the 3·2·1 get-ready countdown, the
/// per-question `t` countdown and the `d` recording deadline are all instances
/// of this class. Collapsing them onto one mechanism is what makes a single
/// pause path able to freeze every clock in step — four countdowns with four
/// bespoke timers is how CTRL-04 regresses.
///
/// **Why `Timer.periodic` and not `Stopwatch` — a testability decision, not a
/// taste one.** `flutter_test`'s `AutomatedTestWidgetsFlutterBinding` runs a
/// `testWidgets` body on a fake clock, so a real `Timer` created here is a fake
/// timer that `tester.pump(duration)` advances. It does NOT fake `Stopwatch`: a
/// `Stopwatch` constructed in `lib/` runs on real wall time under `flutter test`
/// and cannot be advanced by `tester.pump()`, so a stopwatch-based deadline
/// would not be host-testable without inventing a whole time-provider seam —
/// more code than this class. The repo already relies on and documents that
/// binding behaviour verbatim at
/// `test/services/recording_service_test.dart:60-68`.
///
/// **Why the displayed number IS the state.** Every countdown in the UI-SPEC
/// renders an integer, so decrementing an `int` avoids the rounding-boundary
/// flicker a derived elapsed-fraction readout produces, and pausing costs no
/// elapsed-time arithmetic — therefore no partial-second drift accumulates
/// across many pause cycles.
///
/// **Why [cancel] exists.** The same binding FAILS any test that ends with a
/// pending timer. A countdown owned by a screen that is being torn down must be
/// cancelled in `dispose()`, following the `?.cancel()`-then-null-the-field
/// discipline `RecordingService` already uses for its deadline.
class PausableCountdown {
  PausableCountdown({
    required int seconds,
    required this.onTick,
    required this.onElapsed,
  })  : assert(seconds > 0, 'a zero-length countdown would never tick'),
        _remaining = seconds;

  /// Called after every whole second with the NEW remaining value (…, 2, 1, 0).
  final void Function(int remainingSeconds) onTick;

  /// Called exactly once, immediately after the tick that reaches zero.
  final void Function() onElapsed;

  int _remaining;
  Timer? _timer;
  bool _finished = false;

  /// Seconds still to run. Frozen while paused.
  int get remainingSeconds => _remaining;

  /// True only while a timer is actually ticking.
  bool get isRunning => _timer != null;

  /// True once the countdown reached zero or was [cancel]led. Terminal.
  bool get isFinished => _finished;

  /// Arms the countdown. A second [start] on a running countdown is a no-op, so
  /// a double-arm can never leave two timers racing on one object.
  void start() {
    if (_finished || _timer != null) return;
    _arm();
  }

  /// Freezes at the current whole second. Idempotent.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// Continues from exactly where [pause] stopped — it never restarts the
  /// current second. Idempotent, and a no-op once the countdown has elapsed, so
  /// a resume racing the final tick can never re-arm a finished countdown.
  void resume() {
    if (_finished || _timer != null) return;
    _arm();
  }

  /// Terminal. A cancelled countdown never ticks and never fires [onElapsed]
  /// again, and cannot be re-armed by [start] or [resume].
  void cancel() {
    _finished = true;
    pause();
  }

  void _arm() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remaining -= 1;
      onTick(_remaining);
      if (_remaining <= 0) {
        // Cancel BEFORE the callback: onElapsed routinely arms the next
        // countdown, and a still-live timer here would tick underneath it.
        cancel();
        onElapsed();
      }
    });
  }
}
