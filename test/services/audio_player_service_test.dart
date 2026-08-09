import 'dart:async';

import 'package:englishreflex/services/audio_player_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [AudioPlaybackBackend] that touches no platform channel, with a
/// broadcast completion stream that mirrors `audioplayers`' non-replaying
/// `onPlayerComplete`.
class FakeAudioPlaybackBackend implements AudioPlaybackBackend {
  final StreamController<void> controller = StreamController<void>.broadcast();
  final List<String> calls = <String>[];

  /// Emits completion from INSIDE `play()`, before its own future resolves —
  /// the shape that a subscribe-after-play implementation drops forever.
  bool emitCompletionDuringPlay = false;

  @override
  Future<void> play(String absoluteFilePath) async {
    calls.add('play');
    if (emitCompletionDuringPlay) controller.add(null);
  }

  @override
  Stream<void> get onComplete => controller.stream;

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await controller.close();
  }
}

const String _path = '/fake/recordings/a.m4a';

void main() {
  test('a completion emitted during play() still resolves the wait', () async {
    // Regression guard for the subscribe-BEFORE-play ordering: onPlayerComplete
    // is a non-replaying broadcast stream, so an event emitted between the play
    // await resolving and a later subscription is gone forever.
    final backend = FakeAudioPlaybackBackend()..emitCompletionDuringPlay = true;
    final service = AudioPlayerService(backend: backend);

    await service.play(_path, awaitCompletion: true);

    expect(backend.calls, contains('play'));
    await service.dispose();
  });

  testWidgets('a backend that never emits completion still resolves within '
      'kReplayCompletionTimeout', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final backend = FakeAudioPlaybackBackend();
    final service = AudioPlayerService(backend: backend);

    var done = false;
    unawaited(service.play(_path, awaitCompletion: true).then((_) {
      done = true;
    }));

    await tester.pump(kReplayCompletionTimeout - const Duration(seconds: 1));
    expect(done, isFalse, reason: 'the wait resolved before the ceiling');

    await tester.pump(const Duration(seconds: 2));
    expect(done, isTrue,
        reason: 'a missed completion event must not hang the practice loop');

    await service.dispose();
  });

  testWidgets('pausing an awaited replay freezes its completion bound, and '
      'resuming lets the real completion event resolve it', (tester) async {
    // UI-SPEC: the replay bound must EXCLUDE paused time. A bound that kept
    // running through a pause would trip while the user was away and advance
    // the loop behind their back.
    await tester.pumpWidget(const SizedBox());
    final backend = FakeAudioPlaybackBackend();
    final service = AudioPlayerService(backend: backend);
    const Duration bound = Duration(seconds: 15);

    var done = false;
    unawaited(service
        .play(_path, awaitCompletion: true, completionTimeout: bound)
        .then((_) {
      done = true;
    }));
    await tester.pump();

    await tester.pump(const Duration(seconds: 5));
    await service.pause();
    expect(backend.calls, contains('pause'));

    // Ten times the whole bound, spent paused.
    await tester.pump(bound * 10);
    expect(done, isFalse, reason: 'the completion bound ran through a pause');

    await service.resume();
    expect(backend.calls, contains('resume'));

    // The real completion event, arriving after the resume.
    backend.controller.add(null);
    await tester.pump();
    expect(done, isTrue);

    await service.dispose();
  });

  testWidgets('resume() after the completion event has already fired is a '
      'no-op and never restarts playback', (tester) async {
    // `AudioPlayer.resume()` is documented to resume audio that has been paused
    // OR STOPPED — so a pause landing in the same frame as the end of a replay
    // would replay the whole answer from the beginning.
    await tester.pumpWidget(const SizedBox());
    final backend = FakeAudioPlaybackBackend()..emitCompletionDuringPlay = true;
    final service = AudioPlayerService(backend: backend);

    await service.play(_path, awaitCompletion: true);

    await service.resume();

    expect(backend.calls, isNot(contains('resume')));
    expect(backend.calls.where((c) => c == 'play'), hasLength(1));

    await service.dispose();
  });

  test('replayCompletionTimeoutFor derives the bound from the session d', () {
    // One place owns the "+5 s of slack" rationale.
    expect(
      replayCompletionTimeoutFor(const Duration(seconds: 120)),
      const Duration(seconds: 125),
    );
    expect(
      replayCompletionTimeoutFor(const Duration(seconds: 60)),
      kReplayCompletionTimeout,
      reason: 'the Phase 1 constant must be exactly the d=60 s case',
    );
  });

  test('awaitCompletion:false returns without waiting for completion',
      () async {
    // The fire-and-forget path History's tap-to-replay uses.
    final backend = FakeAudioPlaybackBackend();
    final service = AudioPlayerService(backend: backend);

    await service.play(_path);

    expect(backend.calls.where((c) => c == 'play'), hasLength(1));
    await service.dispose();
  });
}
