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

  /// The path the backend most recently finished starting — i.e. what it is
  /// actually recording.
  String? lastStartedPath;

  int get stopCount => calls.where((c) => c == 'stop').length;
  bool get backendWasStarted => calls.any((c) => c.startsWith('start:'));

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
