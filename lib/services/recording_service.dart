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

/// Thin wrapper around `package:record`'s [AudioRecorder].
///
/// Responsibilities beyond the raw plugin:
///  * enforce the 60 s one-shot deadline (D-09);
///  * guarantee "first stop signal wins" — a manual Stop tap and the auto-stop
///    timer firing at effectively the same moment must produce exactly one
///    finalized file and one save.
///
/// The recorder is created lazily so that test fakes subclassing this service
/// never touch a platform channel.
class RecordingService {
  late final AudioRecorder _recorder = AudioRecorder();

  Timer? _autoStopTimer;
  bool _stopping = false;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording to [absoluteFilePath] using the package defaults
  /// (AAC-LC / m4a, no custom codec or bitrate tuning — D-11).
  ///
  /// Throws [RecordingPermissionDeniedException] when microphone access is not
  /// granted — checked *before* any file is touched, so a denied attempt leaves
  /// nothing behind on disk and nothing in the database.
  ///
  /// [onAutoStop] is invoked when the 60 s deadline elapses while still
  /// recording. The callback owns the stop (it calls [stop] itself) so the
  /// finalized path is delivered to exactly one consumer. If no callback is
  /// supplied the deadline stops the recorder directly as a safety net.
  Future<void> start(
    String absoluteFilePath, {
    void Function()? onAutoStop,
  }) async {
    if (!await hasPermission()) {
      throw const RecordingPermissionDeniedException();
    }
    _stopping = false;
    await _recorder.start(const RecordConfig(), path: absoluteFilePath);
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(kMaxRecordingDuration, () {
      _autoStopTimer = null;
      if (_stopping) return;
      if (onAutoStop != null) {
        onAutoStop();
      } else {
        unawaited(stop());
      }
    });
  }

  /// Stops the current recording and returns the finalized absolute file path.
  ///
  /// Returns `null` when a stop is already in flight or nothing is recording —
  /// this is the "first stop signal wins" guard for the manual-tap vs
  /// auto-stop race. The second signal is a silent no-op.
  Future<String?> stop() async {
    if (_stopping) return null;
    _stopping = true;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    return _recorder.stop();
  }

  Future<void> dispose() async {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    await _recorder.dispose();
  }
}
