import 'dart:async';

import 'package:englishreflex/services/recording_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [RecorderBackend] that touches no platform channel, so the REAL
/// [RecordingService] — its 60 s deadline, its first-stop-wins guard and its
/// arming-window handling — can be exercised directly.
///
/// Both arming awaits are independently gateable: [permissionGate] holds the
/// permission check open (the half of the window where the backend has not been
/// touched at all) and [startGate] holds the backend start open (the half where
/// it has).
class FakeRecorderBackend implements RecorderBackend {
  final List<String> calls = <String>[];

  bool permissionGranted = true;
  Completer<void>? permissionGate;
  Completer<void>? startGate;

  /// Makes [pause] behave EXACTLY like both native implementations do in the
  /// wrong state: it returns normally, having done nothing at all. Nothing
  /// throws, and [isPaused] keeps reporting false.
  ///
  /// This switch is the only thing that can prove the honesty rule. A fake whose
  /// pause always works cannot distinguish "the microphone stopped" from "the
  /// call did not throw" — and that distinction is the whole of CTRL-04's
  /// safety argument.
  bool pauseSilentlyNoOps = false;

  bool paused = false;

  final StreamController<bool> pausedChanges =
      StreamController<bool>.broadcast();

  /// The path the backend most recently finished starting — i.e. what it is
  /// actually recording.
  String? lastStartedPath;

  int get stopCount => calls.where((c) => c == 'stop').length;
  bool get backendWasStarted => calls.any((c) => c.startsWith('start:'));

  @override
  Future<void> pause() async {
    calls.add('pause');
    if (pauseSilentlyNoOps) return;
    paused = true;
    pausedChanges.add(true);
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    paused = false;
    pausedChanges.add(false);
  }

  @override
  Future<bool> isPaused() async => paused;

  @override
  Stream<bool> get onPausedChanged => pausedChanges.stream;

  @override
  Future<bool> hasPermission() async {
    calls.add('hasPermission');
    final gate = permissionGate;
    if (gate != null) await gate.future;
    return permissionGranted;
  }

  @override
  Future<void> start(String absoluteFilePath) async {
    calls.add('start:$absoluteFilePath');
    final gate = startGate;
    if (gate != null) await gate.future;
    lastStartedPath = absoluteFilePath;
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
    return lastStartedPath;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await pausedChanges.close();
  }
}

const String _pathA = '/fake/recordings/a.m4a';
const String _pathB = '/fake/recordings/b.m4a';

void main() {
  // Every test runs inside `testWidgets` because flutter_test's
  // AutomatedTestWidgetsFlutterBinding already runs the body on a fake clock:
  // a real `Timer` created here is a fake timer and `tester.pump(duration)`
  // advances it. No `fake_async` dependency is needed.
  //
  // That binding also FAILS any test that ends with a pending timer, so each
  // test below either pumps past the deadline or disposes the service.

  testWidgets('the auto-stop deadline fires exactly once, at '
      'kMaxRecordingDuration and not before', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);
    var fired = 0;

    await service.start(_pathA, onAutoStop: () => fired++);

    await tester.pump(kMaxRecordingDuration - const Duration(seconds: 1));
    expect(fired, 0, reason: 'the deadline fired early');

    await tester.pump(const Duration(seconds: 2));
    expect(fired, 1);

    await tester.pump(kMaxRecordingDuration);
    expect(fired, 1, reason: 'the deadline is one-shot');

    await service.dispose();
  });

  testWidgets('two concurrent stops yield exactly one finalized path and one '
      'backend stop', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);

    await service.start(_pathA);

    // The manual tap and the deadline landing in the same frame.
    final results = await Future.wait<String?>([service.stop(), service.stop()]);

    expect(results.where((r) => r != null), hasLength(1));
    expect(backend.stopCount, 1);

    await service.dispose();
  });

  testWidgets('a stop during the BACKEND-START window is honoured: the '
      'recording is finalized and discarded, never armed', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final gate = Completer<void>();
    backend.startGate = gate;
    final service = RecordingService(backend: backend);
    var fired = 0;

    final arming = service.start(_pathA, onAutoStop: () => fired++);
    await tester.pump();
    expect(backend.backendWasStarted, isTrue,
        reason: 'this case must land after the backend has been touched');

    expect(await service.stop(), isNull);

    gate.complete();
    await arming;

    // Finalized-and-discarded: the recorder was stopped exactly once...
    expect(backend.stopCount, 1);
    // ...and the service is not recording, so a further stop reaches nothing.
    expect(await service.stop(), isNull);
    expect(backend.stopCount, 1);

    // ...and no deadline was armed, so the microphone cannot run on behind an
    // error banner.
    await tester.pump(kMaxRecordingDuration + const Duration(seconds: 1));
    expect(fired, 0);

    await service.dispose();
  });

  testWidgets('a stop during the PERMISSION window is honoured too — the half '
      'of the arming window where the backend has not been touched at all',
      (tester) async {
    // REGRESSION GUARD. `_startInFlight` only covers this window because
    // `start()` assigns it the WHOLE `_arm(...)` future — the one that holds
    // the permission check and the backend start together. A refactor that
    // assigns `_startInFlight = _backend.start(...)` after already awaiting
    // `hasPermission()` would leave this window uncovered: the stop would be
    // silently dropped and the recorder would arm a 60 s deadline behind an
    // error banner. That is exactly what this test exists to catch.
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final gate = Completer<void>();
    backend.permissionGate = gate;
    final service = RecordingService(backend: backend);
    var fired = 0;

    final arming = service.start(_pathA, onAutoStop: () => fired++);
    await tester.pump();
    expect(backend.backendWasStarted, isFalse,
        reason: 'the stop must land before the backend is touched');

    expect(await service.stop(), isNull);

    gate.complete();
    await arming;

    expect(backend.stopCount, 1);
    expect(await service.stop(), isNull);
    expect(backend.stopCount, 1);

    await tester.pump(kMaxRecordingDuration + const Duration(seconds: 1));
    expect(fired, 0);

    await service.dispose();
  });

  testWidgets('after an arming-window stop the next start arms normally',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final gate = Completer<void>();
    backend.startGate = gate;
    final service = RecordingService(backend: backend);

    final arming = service.start(_pathA);
    await tester.pump();
    expect(await service.stop(), isNull);
    gate.complete();
    await arming;

    backend.startGate = null;
    await service.start(_pathB);

    expect(backend.lastStartedPath, _pathB);

    await service.dispose();
  });

  testWidgets('start() throws rather than silently no-opping while a recording '
      'is live, so no caller can believe it armed a path the recorder never got',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);

    await service.start(_pathA);

    await expectLater(
      service.start(_pathB),
      throwsA(isA<StateError>()),
    );
    expect(backend.lastStartedPath, _pathA,
        reason: 'the live recording must be untouched');

    await service.dispose();
  });

  testWidgets('a denied permission throws and leaves no timer armed',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend()..permissionGranted = false;
    final service = RecordingService(backend: backend);
    var fired = 0;

    await expectLater(
      service.start(_pathA, onAutoStop: () => fired++),
      throwsA(isA<RecordingPermissionDeniedException>()),
    );

    // Nothing was touched on disk or in the backend.
    expect(backend.backendWasStarted, isFalse);

    await tester.pump(kMaxRecordingDuration + const Duration(seconds: 1));
    expect(fired, 0);

    await service.dispose();
  });

  testWidgets('a dispose landing IN the arming window still finalizes and '
      'discards — the microphone is never left live behind a torn-down screen',
      (tester) async {
    // REGRESSION GUARD (CR-01). `PracticeScreen.dispose()` emits literally
    // `stop().catchError(...).whenComplete(recordingService.dispose)`, so on a
    // cold-launch teardown the dispose lands ONE MICROTASK after a stop that
    // was recorded as pending — while `start()` is still arming.
    //
    // A `dispose()` that cleared `_stopRequestedDuringStart` destroyed that
    // recorded signal: the resolving `start()` then skipped the
    // finalize-and-discard, armed a live recorder and a 60 s deadline AFTER
    // teardown, and fired `onAutoStop` on a disposed state. That is the exact
    // T-04-01 ghost capture the 01-04 plan declares structurally impossible.
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final gate = Completer<void>();
    backend.startGate = gate;
    final service = RecordingService(backend: backend);
    var fired = 0;

    final arming = service.start(_pathA, onAutoStop: () => fired++);
    await tester.pump();

    // The literal PracticeScreen.dispose() sequence.
    unawaited(
      service
          .stop()
          .catchError((Object _) => null)
          .whenComplete(service.dispose),
    );
    await tester.pump();

    gate.complete();
    await arming;

    // The recording that finished arming was finalized, not armed.
    expect(backend.stopCount, 1,
        reason: 'a disposed service must never leave the recorder running');

    // And no deadline outlived the teardown.
    await tester.pump(kMaxRecordingDuration + const Duration(seconds: 1));
    expect(fired, 0,
        reason: 'a 60 s deadline was armed after dispose() returned');
  });

  testWidgets('start() after dispose() throws instead of driving a disposed '
      'backend', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);

    await service.dispose();

    await expectLater(
      service.start(_pathA),
      throwsA(isA<StateError>()),
    );
    expect(backend.backendWasStarted, isFalse);
  });

  testWidgets('a CONFIRMED pause returns true and freezes the d deadline',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);
    var fired = 0;

    await service.start(
      _pathA,
      onAutoStop: () => fired++,
      maxDuration: const Duration(seconds: 10),
    );

    await tester.pump(const Duration(seconds: 8));
    expect(await service.pause(), isTrue);

    // Two whole minutes of paused time on a deadline with 2 s left on it.
    await tester.pump(const Duration(seconds: 120));
    expect(fired, 0, reason: 'the d deadline kept running through a pause');

    await service.dispose();
  });

  testWidgets('a pause that silently no-ops returns FALSE and leaves the '
      'deadline running — a non-throwing call is never proof', (tester) async {
    // THE honesty rule of this phase. `record`'s pause is a guarded early
    // return on BOTH platforms (iOS guards on the recorder being in the record
    // state, Android on isRecording()), so a call landing in the wrong state
    // returns normally having done nothing. A service that inferred "the mic is
    // paused" from "the call did not throw" would publish a banner reading
    // "nothing is being recorded" over a live microphone.
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend()..pauseSilentlyNoOps = true;
    final service = RecordingService(backend: backend);
    var fired = 0;

    await service.start(
      _pathA,
      onAutoStop: () => fired++,
      maxDuration: const Duration(seconds: 10),
    );

    await tester.pump(const Duration(seconds: 8));
    expect(
      await service.pause(),
      isFalse,
      reason: 'pause() believed a call that did nothing',
    );
    expect(backend.calls, contains('pause'),
        reason: 'the backend must actually have been asked');

    // The deadline was NOT frozen, because the microphone was not paused.
    await tester.pump(const Duration(seconds: 2));
    expect(fired, 1, reason: 'an unconfirmed pause must not disarm the deadline');

    await service.dispose();
  });

  testWidgets('resuming continues the deadline from where the pause stopped, '
      'and fires exactly one auto-stop', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);
    var fired = 0;

    await service.start(
      _pathA,
      onAutoStop: () => fired++,
      maxDuration: const Duration(seconds: 10),
    );

    await tester.pump(const Duration(seconds: 8));
    expect(await service.pause(), isTrue);
    await tester.pump(const Duration(seconds: 60));
    expect(fired, 0);

    expect(await service.resume(), isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(fired, 0, reason: 'resume restarted the deadline instead of '
        'continuing it — 2 s were left, not 1');

    await tester.pump(const Duration(seconds: 1));
    expect(fired, 1);

    await tester.pump(const Duration(seconds: 30));
    expect(fired, 1, reason: 'the deadline is still one-shot after a pause');

    await service.dispose();
  });

  testWidgets('onPausedChanged surfaces an OS-initiated pause the app never '
      'requested', (tester) async {
    // The ONLY way Dart learns about an interruption it did not cause (an
    // answered call on iOS, audio-focus loss on Android). Plan 02-05 subscribes
    // to exactly this.
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);
    final seen = <bool>[];
    final sub = service.onPausedChanged.listen(seen.add);

    await service.start(_pathA, maxDuration: const Duration(seconds: 10));

    // The OS pauses the recorder behind the app's back.
    backend.paused = true;
    backend.pausedChanges.add(true);
    await tester.pump();

    expect(seen, contains(true));
    expect(
      backend.calls,
      isNot(contains('pause')),
      reason: 'the app never asked — that is the whole point of this stream',
    );

    // `unawaited`, deliberately: AWAITING a broadcast subscription's cancel()
    // inside a `testWidgets` body hangs the whole run. The future it returns is
    // not completed by anything the fake clock drives, so the body parks
    // forever and the case dies on the 10-minute suite timeout with no useful
    // output. The cancel itself still takes effect — only the acknowledgement
    // is unobservable here — and `service.dispose()` below closes the
    // controller regardless.
    unawaited(sub.cancel());
    await service.dispose();
  });

  testWidgets('dispose cancels a pending deadline', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeRecorderBackend();
    final service = RecordingService(backend: backend);
    var fired = 0;

    await service.start(_pathA, onAutoStop: () => fired++);
    await service.dispose();

    await tester.pump(kMaxRecordingDuration + const Duration(seconds: 1));
    expect(fired, 0);
    expect(backend.calls, contains('dispose'));
  });
}
