import 'dart:async';

import 'package:record/record.dart';

import '../utils/pausable_countdown.dart';

/// DEFAULT cap on a single recording, and no longer the app's real one.
///
/// Phase 2 makes the cap configurable per session (`d`, SETUP-05/D-21) and
/// passes it as [RecordingService.start]'s `maxDuration`. This constant survives
/// as the fallback for a caller that supplies none — which is what keeps every
/// Phase 1 deadline test meaningful and unchanged. Do NOT reintroduce it as a
/// ceiling over `d`: `d` ranges to 120 s and is the user's choice.
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

  /// Suspends capture. Deliberately returns nothing meaningful: on BOTH
  /// platforms this is a guarded early return that does nothing at all in the
  /// wrong state and still returns normally. Ask [isPaused] afterwards — never
  /// infer success from the absence of a throw.
  Future<void> pause();

  /// Continues capture into the SAME file. The paused span is excised from the
  /// recording rather than encoded as silence.
  Future<void> resume();

  /// The recorder's ACTUAL paused state, read back from the platform. This is
  /// the confirmation [RecordingService.pause] believes instead of the pause
  /// call's own return.
  Future<bool> isPaused();

  /// True/false as the recorder enters and leaves its paused state — including
  /// transitions the app never requested.
  ///
  /// This stream is the ONLY way Dart learns that the OS paused the microphone
  /// on its own: an answered call on iOS, audio-focus loss on Android. Nothing
  /// else in this class reports that, because nothing else is invoked. Plan
  /// 02-05's interruption handling subscribes to exactly this.
  ///
  /// Kept as a `bool` stream rather than the plugin's own state enum so this
  /// seam stays free of package types and every test can drive it with a plain
  /// `StreamController<bool>`.
  Stream<bool> get onPausedChanged;

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
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<bool> isPaused() => _recorder.isPaused();

  /// Maps the plugin's three-valued recorder state onto the seam's `bool`.
  ///
  /// `stop` is filtered out rather than mapped to false: a stopped recorder is
  /// not an un-paused one, and emitting false for it would tell a subscriber the
  /// microphone came back when it actually went away.
  @override
  Stream<bool> get onPausedChanged => _recorder
      .onStateChanged()
      .where((state) => state != RecordState.stop)
      .map((state) => state == RecordState.pause);

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
///  * **A disposed service is terminal.** [dispose] counts as a stop signal for
///    a start that is still arming and makes every later [start] throw, so a
///    torn-down screen can never leave a live recorder or an armed deadline
///    behind it.
///
/// **The deadline and the on-screen remaining-seconds readout are the SAME
/// object** (D-21). `start`'s `onTick` is fed by the very [PausableCountdown]
/// that will fire the auto-stop, so the number the user paces their answer
/// against cannot disagree with the moment the recording actually ends. Deriving
/// the readout from a second clock is exactly how a "3 seconds left" display
/// ends up cutting someone off at 5.
///
/// The backend is resolved lazily so a test that injects a fake never
/// constructs a platform channel.
class RecordingService {
  RecordingService({RecorderBackend? backend}) : _injectedBackend = backend;

  final RecorderBackend? _injectedBackend;
  late final RecorderBackend _backend =
      _injectedBackend ?? _RecordPackageBackend();

  /// The `d` deadline AND the source of the remaining-seconds readout. Exactly
  /// one is alive at a time; it is cancelled and nulled before any re-arm.
  PausableCountdown? _deadline;

  /// True only between a COMPLETED start and the stop that finalizes it.
  bool _recording = false;

  /// Non-null only while the arming window — permission check AND backend start
  /// together — is open.
  Future<void>? _startInFlight;

  /// Set when a stop signal arrives during that arming window.
  bool _stopRequestedDuringStart = false;

  /// Set by [dispose] and never cleared. A disposed service is TERMINAL: it can
  /// never arm again, and a [start] still in flight when it is set treats the
  /// disposal itself as a stop signal.
  bool _disposed = false;

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
  /// [onAutoStop] is invoked when the deadline elapses while still recording.
  /// The callback owns the stop (it calls [stop] itself) so the finalized path
  /// is delivered to exactly one consumer. If no callback is supplied the
  /// deadline stops the recorder directly as a safety net.
  ///
  /// [maxDuration] is the session's configured `d` (SETUP-05). When null the
  /// deadline falls back to [kMaxRecordingDuration], which is what keeps every
  /// Phase 1 caller and every Phase 1 deadline test correct unchanged.
  ///
  /// [onTick] receives the NEW remaining whole second after every tick, from the
  /// same countdown that owns the deadline (D-21).
  Future<void> start(
    String absoluteFilePath, {
    void Function()? onAutoStop,
    Duration? maxDuration,
    void Function(int remainingSeconds)? onTick,
  }) async {
    if (_disposed) {
      throw StateError('RecordingService.start() called after dispose()');
    }
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
    //
    // A [dispose] counts as one of those stop signals in its own right.
    // `PracticeScreen.dispose()` emits `stop().whenComplete(recorder.dispose)`,
    // so on a teardown during the arming window the dispose lands one microtask
    // after the stop — and a service that is being torn down must NEVER resolve
    // into a live recorder with a 60 s deadline attached.
    if (_stopRequestedDuringStart || _disposed) {
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
    _paused = false;
    _deadline?.cancel();
    _deadline = PausableCountdown(
      seconds: (maxDuration ?? kMaxRecordingDuration).inSeconds,
      onTick: (remainingSeconds) => onTick?.call(remainingSeconds),
      onElapsed: () {
        _deadline = null;
        if (!_recording) return;
        if (onAutoStop != null) {
          onAutoStop();
        } else {
          unawaited(stop());
        }
      },
    )..start();
  }

  /// True only while the microphone is CONFIRMED paused — set from
  /// [_backend.isPaused], never from a pause call returning without throwing.
  bool _paused = false;

  /// Whether the microphone is currently paused, as this service last confirmed.
  bool get isPaused => _paused;

  /// Re-published so the loop can learn about a pause it never requested.
  ///
  /// See [RecorderBackend.onPausedChanged] for why this stream exists at all:
  /// an OS-initiated pause (an answered call, audio-focus loss) reaches Dart
  /// through nothing else.
  Stream<bool> get onPausedChanged => _backend.onPausedChanged;

  /// Pauses the microphone, and reports whether it ACTUALLY paused.
  ///
  /// **The return value is the whole point of this method.** `record`'s pause is
  /// a guarded early return on both platforms — iOS guards on the recorder being
  /// in the record state, Android on `isRecording()` — so a call that lands in
  /// the wrong state returns normally having done nothing at all. A caller that
  /// inferred "the microphone is paused" from "the call did not throw" would
  /// publish a banner reading *"Paused — nothing is being recorded"* over a live
  /// microphone. So the backend is asked afterwards, and only its answer is
  /// believed.
  ///
  /// **The deadline freezes in lock-step or not at all.** A pause EXCISES the
  /// paused span from the audio file rather than encoding silence into it, so a
  /// `d` deadline that kept running through a 30-second pause would auto-stop 30
  /// seconds of speech early — cutting the answer short by exactly the time the
  /// user was away. Freezing the deadline only on a CONFIRMED pause is what
  /// keeps the deadline and the microphone describing the same recording.
  Future<bool> pause() async {
    if (!_recording || _paused) return false;
    await _backend.pause();
    if (!await _backend.isPaused()) return false;
    _paused = true;
    _deadline?.pause();
    return true;
  }

  /// Resumes the microphone, and reports whether it ACTUALLY resumed.
  ///
  /// The exact mirror of [pause], and believed on the same terms: `resume` is
  /// the same kind of guarded early return, so the un-freezing of the deadline
  /// waits on the backend confirming the recorder is no longer paused. The
  /// deadline continues from the second it stopped on — [PausableCountdown]
  /// never restarts the current second.
  Future<bool> resume() async {
    if (!_recording || !_paused) return false;
    await _backend.resume();
    if (await _backend.isPaused()) return false;
    _paused = false;
    _deadline?.resume();
    return true;
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
    _paused = false;
    _deadline?.cancel();
    _deadline = null;
    return _backend.stop();
  }

  /// Tears the recorder down. A disposed service is terminal: [start] throws
  /// from then on, and a `start()` that is still arming finalizes and discards
  /// instead of arming.
  ///
  /// Deliberately does NOT clear [_stopRequestedDuringStart]. Clearing it
  /// destroyed a stop that had already been recorded during the arming window,
  /// so the resolving `start()` skipped the finalize-and-discard and armed a
  /// live recorder plus a 60 s deadline *after* teardown — the microphone left
  /// capturing behind a screen that no longer exists (T-04-01). A dispose must
  /// STRENGTHEN a pending stop, never erase it.
  Future<void> dispose() async {
    _disposed = true;
    _deadline?.cancel();
    _deadline = null;
    _recording = false;
    _paused = false;
    await _backend.dispose();
  }
}
