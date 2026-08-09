import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../utils/pausable_countdown.dart';

/// DEFAULT ceiling on how long the practice loop will wait for a replay to
/// finish, and no longer the app's real one.
///
/// Kept as the fallback for a caller that supplies no bound of its own — which
/// is what keeps every Phase 1 caller and every Phase 1 timeout test correct
/// unchanged. A configured session derives its own bound from `d`; see
/// [replayCompletionTimeoutFor].
const Duration kReplayCompletionTimeout =
    Duration(seconds: 60 + 5); // 60 s (Phase 1's fixed d) + 5s

/// The replay bound for a session whose answers are capped at [answerLimit].
///
/// The single home of the "+5 s of slack" rationale: an answer can be at most
/// `d` long, so a legitimate replay always fits well inside `d + 5 s` and only a
/// missed or never-emitted completion event ever reaches the bound. Deriving it
/// from the SESSION's `d` rather than a fixed 65 s is what stops a 120-second
/// answer (SETUP-05's ceiling) from tripping the bound halfway through its own
/// replay.
Duration replayCompletionTimeoutFor(Duration answerLimit) =>
    answerLimit + const Duration(seconds: 5);

/// Playback, reduced to the operations [AudioPlayerService] needs.
///
/// Mirrors `RecorderBackend`: the seam a test injects so the REAL
/// [AudioPlayerService] — its subscribe-before-play ordering and its bounded
/// wait — runs without any platform channel.
abstract class AudioPlaybackBackend {
  Future<void> play(String absoluteFilePath);

  /// Fires once each time playback runs to its end. Non-replaying, like
  /// `audioplayers`' own `onPlayerComplete`.
  Stream<void> get onComplete;

  Future<void> pause();

  /// Continues playback from where [pause] stopped.
  ///
  /// Note for callers: the underlying player resumes audio that was paused **or
  /// stopped**, so resuming something that already finished restarts it from
  /// the beginning. [AudioPlayerService.resume] is what guards against that.
  Future<void> resume();

  Future<void> stop();

  Future<void> dispose();
}

/// The production backend: `package:audioplayers`' [AudioPlayer].
class _AudioPlayersBackend implements AudioPlaybackBackend {
  late final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(String absoluteFilePath) =>
      _player.play(DeviceFileSource(absoluteFilePath));

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Replays a single local recording. Foreground only — no background or
/// lock-screen audio.
///
/// The backend is resolved lazily so a test that injects a fake never
/// constructs a platform channel.
class AudioPlayerService {
  AudioPlayerService({AudioPlaybackBackend? backend})
      : _injectedBackend = backend;

  final AudioPlaybackBackend? _injectedBackend;
  late final AudioPlaybackBackend _backend =
      _injectedBackend ?? _AudioPlayersBackend();

  /// The outstanding awaited-completion wait, resolved by whichever of the
  /// completion event or the bound lands first. Null when nothing is awaited.
  Completer<void>? _wait;

  /// The freezable bound on that wait. See [play] for why this is a countdown
  /// and not a `Future.timeout`.
  PausableCountdown? _bound;

  StreamSubscription<void>? _completionSubscription;

  /// True once the current playback has ended. [resume] refuses to act on it,
  /// because resuming a finished player restarts the answer from the beginning.
  bool _completionFired = false;

  /// Plays the file at [absoluteFilePath].
  ///
  /// When [awaitCompletion] is true the returned future does not resolve until
  /// playback finishes. The practice loop uses this so the next recording only
  /// starts *after* the auto-replay has finished (D-03/D-10) — otherwise the
  /// microphone would capture the replay itself. Tap-to-replay in History uses
  /// the default fire-and-forget behaviour.
  ///
  /// Two independent protections guard that wait, and BOTH are kept
  /// deliberately:
  ///
  ///  1. The completion subscription is captured BEFORE playback starts.
  ///     `onComplete` is a non-replaying broadcast stream, so an event emitted
  ///     between the play await resolving and a later subscription is dropped
  ///     forever.
  ///  2. The wait is BOUNDED. Even if the event never arrives at all, a stuck
  ///     player costs the loop [completionTimeout] rather than freezing it
  ///     permanently at "Playing your answer…".
  ///
  /// [completionTimeout] defaults to [kReplayCompletionTimeout] so every Phase 1
  /// caller is unchanged; the practice loop passes
  /// `replayCompletionTimeoutFor(d)`.
  ///
  /// The bound is a [PausableCountdown] rather than `Future.timeout`, because a
  /// `timeout` cannot be frozen: a pause during a replay would let the bound run
  /// on and trip while the user was away, advancing the loop behind their back.
  /// The bound must EXCLUDE paused time (UI-SPEC), which is only possible if it
  /// is the same freezable primitive every other clock in this phase uses.
  Future<void> play(
    String absoluteFilePath, {
    bool awaitCompletion = false,
    Duration? completionTimeout,
  }) async {
    // A new playback supersedes any wait still outstanding; resolving rather
    // than dropping it is what keeps a stranded caller impossible.
    _finishWait();
    _completionFired = false;
    if (!awaitCompletion) {
      await _backend.play(absoluteFilePath);
      return;
    }

    final completer = Completer<void>();
    _wait = completer;

    // Subscribe first — see (1) above. `onDone` and `onError` resolve the wait
    // too: a player disposed mid-replay closes the stream without ever emitting,
    // which would otherwise leave the loop parked until the bound elapsed.
    _completionSubscription = _backend.onComplete.listen(
      (_) => _finishWait(),
      onError: (Object _) => _finishWait(),
      onDone: _finishWait,
    );
    _bound = PausableCountdown(
      seconds: (completionTimeout ?? kReplayCompletionTimeout).inSeconds,
      onTick: (_) {},
      onElapsed: _finishWait,
    )..start();

    await _backend.play(absoluteFilePath);
    await completer.future;
  }

  /// Freezes playback AND its completion bound together.
  ///
  /// Both or neither: pausing the audio while the bound kept running is exactly
  /// how a long pause makes the loop skip past a replay the user never heard.
  Future<void> pause() async {
    _bound?.pause();
    await _backend.pause();
  }

  /// Continues playback and its completion bound from where [pause] stopped.
  ///
  /// A NO-OP once the completion event has already fired. The underlying player
  /// resumes audio that was paused *or stopped*, so a resume landing after the
  /// end of a replay — the same-frame race between a Pause tap and the last of
  /// the audio — would replay the whole answer from the beginning.
  Future<void> resume() async {
    if (_completionFired) return;
    await _backend.resume();
    _bound?.resume();
  }

  /// Both RESOLVE any outstanding wait rather than merely tearing it down: a
  /// replay that is stopped or a player that is disposed has ended, and a caller
  /// awaiting its completion must be released, not stranded at
  /// "Playing your answer…" forever.
  Future<void> stop() {
    _finishWait();
    return _backend.stop();
  }

  Future<void> dispose() {
    _finishWait();
    return _backend.dispose();
  }

  /// Resolves the current wait: the completion event arrived, or the bound
  /// elapsed. Idempotent — whichever lands first wins and the other is inert.
  void _finishWait() {
    _completionFired = true;
    final completer = _wait;
    _endWait();
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// Tears down the bound and the subscription without resolving anything.
  void _endWait() {
    _bound?.cancel();
    _bound = null;
    unawaited(_completionSubscription?.cancel());
    _completionSubscription = null;
    _wait = null;
  }
}
