import 'package:englishreflex/utils/pausable_countdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every case here is a `testWidgets`, never a plain `test()`.
///
/// `PausableCountdown` is built on `Timer.periodic`, and only
/// `flutter_test`'s `AutomatedTestWidgetsFlutterBinding` fakes the clock those
/// timers run on: inside a `testWidgets` body a real `Timer` IS a fake timer,
/// and `tester.pump(duration)` advances it. A plain `test()` would have to sleep
/// on real wall time — slow, and flaky at second boundaries.
///
/// That same binding FAILS any test ending with a pending timer, so each case
/// below either runs its countdown to zero or cancels it. That is not test
/// hygiene for its own sake: it is the guard that would catch a `cancel()` which
/// silently stopped cancelling.
///
/// Assertions are on `remainingSeconds`, `isRunning`, `isFinished` and on
/// recorded callback lists — never on wall-clock time.
void main() {
  /// Builds a countdown that records everything it emits.
  ({
    PausableCountdown countdown,
    List<int> ticks,
    List<String> elapsed,
  }) build(int seconds) {
    final ticks = <int>[];
    final elapsed = <String>[];
    final countdown = PausableCountdown(
      seconds: seconds,
      onTick: ticks.add,
      onElapsed: () => elapsed.add('elapsed'),
    );
    return (countdown: countdown, ticks: ticks, elapsed: elapsed);
  }

  testWidgets('ticks down one whole second at a time and elapses exactly once',
      (tester) async {
    final c = build(3);
    c.countdown.start();

    expect(c.countdown.remainingSeconds, 3);
    expect(c.countdown.isRunning, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(c.ticks, [2]);
    await tester.pump(const Duration(seconds: 1));
    expect(c.ticks, [2, 1]);
    await tester.pump(const Duration(seconds: 1));
    expect(c.ticks, [2, 1, 0]);

    expect(c.elapsed, ['elapsed']);
    expect(c.countdown.isFinished, isTrue);
    expect(c.countdown.isRunning, isFalse);

    // A finished countdown emits nothing further, however long the clock runs.
    await tester.pump(const Duration(seconds: 30));
    expect(c.ticks, [2, 1, 0]);
    expect(c.elapsed, ['elapsed']);
  });

  testWidgets('pause freezes the remaining value and resume continues from it',
      (tester) async {
    final c = build(10);
    c.countdown.start();
    await tester.pump(const Duration(seconds: 3));
    expect(c.countdown.remainingSeconds, 7);

    c.countdown.pause();
    expect(c.countdown.isRunning, isFalse);

    // A full minute of frozen time must not move the number by one second.
    await tester.pump(const Duration(seconds: 60));
    expect(c.countdown.remainingSeconds, 7);
    expect(c.ticks, [9, 8, 7]);

    c.countdown.resume();
    expect(c.countdown.isRunning, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(c.countdown.remainingSeconds, 6, reason: 'resume must not restart');

    c.countdown.cancel();
  });

  testWidgets('pause and resume are each idempotent', (tester) async {
    final c = build(10);
    c.countdown.start();
    await tester.pump(const Duration(seconds: 1));

    c.countdown.pause();
    c.countdown.pause();
    await tester.pump(const Duration(seconds: 5));
    expect(c.countdown.remainingSeconds, 9);
    expect(c.ticks, [9]);

    // A second resume must not arm a SECOND timer — two timers on one object
    // would double the tick rate and the number would fall twice as fast.
    c.countdown.resume();
    c.countdown.resume();
    await tester.pump(const Duration(seconds: 1));
    expect(c.ticks, [9, 8]);

    c.countdown.cancel();
  });

  testWidgets('start on an already running countdown does not double-arm it',
      (tester) async {
    final c = build(10);
    c.countdown.start();
    c.countdown.start();

    await tester.pump(const Duration(seconds: 1));
    expect(c.ticks, [9], reason: 'a second start armed a second timer');

    c.countdown.cancel();
  });

  testWidgets('resume after elapsing is a no-op and never re-arms',
      (tester) async {
    final c = build(1);
    c.countdown.start();
    await tester.pump(const Duration(seconds: 1));
    expect(c.elapsed, ['elapsed']);

    c.countdown.resume();
    expect(c.countdown.isRunning, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(c.ticks, [0]);
    expect(c.elapsed, ['elapsed']);
  });

  testWidgets('cancel is terminal — no tick, no elapse, no pending timer',
      (tester) async {
    final c = build(5);
    c.countdown.start();
    await tester.pump(const Duration(seconds: 2));
    expect(c.ticks, [4, 3]);

    c.countdown.cancel();
    expect(c.countdown.isFinished, isTrue);
    expect(c.countdown.isRunning, isFalse);

    // If cancel() had left the timer alive the binding would fail this test at
    // teardown with a pending-timer error, which is the point of pumping past
    // where the countdown would otherwise have reached zero.
    await tester.pump(const Duration(seconds: 10));
    expect(c.ticks, [4, 3]);
    expect(c.elapsed, isEmpty);

    // And it cannot be re-armed.
    c.countdown.start();
    c.countdown.resume();
    expect(c.countdown.isRunning, isFalse);
  });

  testWidgets('a countdown that is never started never ticks', (tester) async {
    final c = build(3);

    await tester.pump(const Duration(seconds: 10));
    expect(c.ticks, isEmpty);
    expect(c.countdown.remainingSeconds, 3);
    expect(c.countdown.isRunning, isFalse);
  });
}
