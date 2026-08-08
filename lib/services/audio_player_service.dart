import 'package:audioplayers/audioplayers.dart';

/// Ceiling on how long the practice loop will wait for a replay to finish.
///
/// `kMaxRecordingDuration` (60 s, D-09) plus five seconds of slack: the longest
/// recording this phase can produce, so a legitimate replay always fits well
/// inside it and only a missed or never-emitted completion event ever hits the
/// ceiling.
const Duration kReplayCompletionTimeout =
    Duration(seconds: 60 + 5); // kMaxRecordingDuration + 5s

/// Playback, reduced to the four operations [AudioPlayerService] needs.
///
/// Mirrors `RecorderBackend`: the seam a test injects so the REAL
/// [AudioPlayerService] — its subscribe-before-play ordering and its timeout —
/// runs without any platform channel.
abstract class AudioPlaybackBackend {
  Future<void> play(String absoluteFilePath);

  /// Fires once each time playback runs to its end. Non-replaying, like
  /// `audioplayers`' own `onPlayerComplete`.
  Stream<void> get onComplete;

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
  ///  2. The wait is bounded by [kReplayCompletionTimeout]. Even if the event
  ///     never arrives at all, a stuck player costs the loop the timeout rather
  ///     than freezing it permanently at "Playing your answer…".
  Future<void> play(
    String absoluteFilePath, {
    bool awaitCompletion = false,
  }) async {
    if (!awaitCompletion) {
      await _backend.play(absoluteFilePath);
      return;
    }

    // Subscribe first — see (1) above. `first` completes with a StateError if
    // the stream closes without ever emitting (a player disposed mid-replay),
    // which would otherwise surface as an unhandled async error long after the
    // timeout has already let the loop move on.
    final Future<void> completed =
        _backend.onComplete.first.catchError((Object _) {});
    await _backend.play(absoluteFilePath);
    await completed.timeout(kReplayCompletionTimeout, onTimeout: () {});
  }

  Future<void> stop() => _backend.stop();

  Future<void> dispose() => _backend.dispose();
}
