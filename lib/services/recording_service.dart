import 'dart:async';

import 'package:record/record.dart';

/// Hard cap on a single recording (D-09). Configurable `d` arrives in Phase 2.
const Duration kMaxRecordingDuration = Duration(seconds: 60);

/// Thrown by [RecordingService.start] when the OS has not granted microphone
/// access, instead of letting the plugin fail somewhere deeper.
///
/// This is a *signal*, not a crash: `PracticeState` catches it and moves the
/// loop into its error phase so the screen can show the pre-approved
/// user-facing copy. The exception's own text is developer-facing only and is
/// never rendered to the user (T-03-02).
class RecordingPermissionDeniedException implements Exception {
  const RecordingPermissionDeniedException();

  @override
  String toString() => 'RecordingPermissionDeniedException';
}

/// The microphone, reduced to the four operations [RecordingService] needs.
///
/// This is the seam the tests substitute: with a fake backend injected, the
/// REAL [RecordingService] — its deadline, its guards, its arming-window
/// handling — runs without any platform channel.
abstract class RecorderBackend {
  Future<bool> hasPermission();

  Future<void> start(String absoluteFilePath);

  /// Finalizes the current recording and returns its absolute path.
  Future<String?> stop();

  Future<void> dispose();
}

/// The production backend: `package:record`'s [AudioRecorder], using the
/// package defaults (AAC-LC / m4a, no custom codec, bitrate or sample rate —
/// D-11).
class _RecordPackageBackend implements RecorderBackend {
  late final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String absoluteFilePath) =>
      _recorder.start(const RecordConfig(), path: absoluteFilePath);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// Owns the microphone's lifecycle for one recording at a time.
///
/// Its contract, in three sentences:
///
///  * **A stop signal is never silently lost.** A stop arriving while the
///    recorder is still arming is remembered in [_stopRequestedDuringStart],
///    and the `start()` that finishes arming finalizes and *discards* that
///    recording instead of arming a deadline.
///  * **A start is never silently ignored.** Starting while a recording is
///    already active or arming throws a [StateError], so a caller can never
///    believe it armed a path the recorder was never given — and can never
///    commit a `question_answers` row naming a file that does not exist.
///  * **The microphone is live only while [_recording] is true.** That flag is
///    set only after a completed start and cleared by the stop that finalizes
///    it, which is what makes the 60 s deadline (D-09) impossible to disarm
///    permanently and impossible to outlive.
///
/// The backend is resolved lazily so a test that injects a fake never
/// constructs a platform channel.
class RecordingService {
  RecordingService({RecorderBackend? backend}) : _injectedBackend = backend;

  final RecorderBackend? _injectedBackend;
  late final RecorderBackend _backend =
      _injectedBackend ?? _RecordPackageBackend();

  Timer? _autoStopTimer;

  /// True only between a COMPLETED start and the stop that finalizes it.
  bool _recording = false;

  /// Non-null only while the arming window — permission check AND backend start
  /// together — is open.
  Future<void>? _startInFlight;

  /// Set when a stop signal arrives during that arming window.
  bool _stopRequestedDuringStart = false;

  Future<bool> hasPermission() => _backend.hasPermission();

  /// The whole arming window as ONE future.
  ///
  /// Holding both awaits together is what lets [_startInFlight] span the
  /// permission check as well as the backend start. Splitting them — awaiting
  /// the permission check first and only then assigning
  /// `_startInFlight = _backend.start(...)` — would leave the permission half
  /// uncovered, and a stop landing there would be dropped.
  Future<void> _arm(String absoluteFilePath) async {
    if (!await hasPermission()) {
      throw const RecordingPermissionDeniedException();
    }
    await _backend.start(absoluteFilePath);
  }

  /// Starts recording to [absoluteFilePath].
  ///
  /// Throws [RecordingPermissionDeniedException] when microphone access is not
  /// granted — checked *before* any file is touched, so a denied attempt leaves
  /// nothing behind on disk and nothing in the database.
  ///
  /// Throws [StateError] when a recording is already active or arming. This is
  /// deliberately not a silent return: a silent return would let `PracticeState`
  /// publish [PracticePhase.recording] against a path the recorder was never
  /// given and then commit a row naming a file that does not exist — the exact
  /// durable-stale-path failure this phase's crash-safety contract excludes.
  ///
  /// [onAutoStop] is invoked when the 60 s deadline elapses while still
  /// recording. The callback owns the stop (it calls [stop] itself) so the
  /// finalized path is delivered to exactly one consumer. If no callback is
  /// supplied the deadline stops the recorder directly as a safety net.
  Future<void> start(
    String absoluteFilePath, {
    void Function()? onAutoStop,
  }) async {
    if (_recording || _startInFlight != null) {
      throw StateError(
        'RecordingService.start() called while a recording is already active '
        'or arming',
      );
    }
    _stopRequestedDuringStart = false;
    // Assigned SYNCHRONOUSLY, with no await between the reset above and this
    // line. Dart is single-threaded, so no stop signal can slip into the gap —
    // the arming window has no uncovered moment at all.
    final Future<void> arming = _startInFlight = _arm(absoluteFilePath);
    try {
      await arming;
    } finally {
      _startInFlight = null;
    }

    // Honour a stop that landed mid-arming BEFORE arming anything else.
    if (_stopRequestedDuringStart) {
      _stopRequestedDuringStart = false;
      try {
        await _backend.stop();
      } catch (_) {
        // Nothing to recover: the recording is being discarded either way.
      }
      // `_recording` stays false and no deadline is set, so the microphone is
      // never live while the screen shows an error banner. The discard is
      // unconditional and therefore correct for a stop from EITHER half of the
      // window: during `_backend.start()` it finalizes a recorder that did
      // start, and during `hasPermission()` it finalizes one that started
      // immediately afterwards.
      return;
    }

    _recording = true;
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(kMaxRecordingDuration, () {
      _autoStopTimer = null;
      if (!_recording) return;
      if (onAutoStop != null) {
        onAutoStop();
      } else {
        unawaited(stop());
      }
    });
  }

  /// Stops the current recording and returns the finalized absolute file path.
  ///
  /// Returns `null` when the recorder is still arming (the signal is recorded,
  /// not lost — see [start]), or when nothing is recording, which is the
  /// "first stop signal wins" guard for the manual-tap vs auto-stop race.
  Future<String?> stop() async {
    if (_startInFlight != null) {
      _stopRequestedDuringStart = true;
      return null;
    }
    if (!_recording) return null;
    _recording = false;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    return _backend.stop();
  }

  Future<void> dispose() async {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _recording = false;
    _stopRequestedDuringStart = false;
    await _backend.dispose();
  }
}
