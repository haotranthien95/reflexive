import 'package:audioplayers/audioplayers.dart';

/// Thin wrapper around `package:audioplayers`' [AudioPlayer] for replaying a
/// single local recording. Foreground only — no background/lock-screen audio.
///
/// The player is created lazily so that test fakes subclassing this service
/// never touch a platform channel.
class AudioPlayerService {
  late final AudioPlayer _player = AudioPlayer();

  /// Plays the file at [absoluteFilePath].
  ///
  /// When [awaitCompletion] is true the returned future does not resolve until
  /// playback finishes. The practice loop uses this so the next recording only
  /// starts *after* the auto-replay has finished (D-03/D-10) — otherwise the
  /// microphone would capture the replay itself. Tap-to-replay in History uses
  /// the default fire-and-forget behaviour.
  Future<void> play(
    String absoluteFilePath, {
    bool awaitCompletion = false,
  }) async {
    await _player.play(DeviceFileSource(absoluteFilePath));
    if (awaitCompletion) {
      await _player.onPlayerComplete.first;
    }
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}
