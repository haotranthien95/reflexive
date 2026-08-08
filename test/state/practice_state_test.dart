import 'dart:async';
import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/services/audio_player_service.dart';
import 'package:englishreflex/services/recording_service.dart';
import 'package:englishreflex/state/practice_state.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Records start/stop calls without touching any platform channel. The real
/// [RecordingService] creates its backend lazily, so overriding these methods
/// here means no plugin is ever constructed.
class FakeRecordingService extends RecordingService {
  FakeRecordingService(this.calls);

  final List<String> calls;
  String? lastRequestedPath;

  /// The auto-stop callback the state handed over on the last `start()`.
  void Function()? lastAutoStop;

  /// Held open to keep `start()` in flight, so a test can observe the arming
  /// window the way the real recorder's permission + start awaits produce it.
  Completer<void>? startGate;

  /// Set to true to simulate a second stop signal losing the race.
  bool stopReturnsNull = false;

  /// Set to true to simulate the recorder itself blowing up on stop.
  bool throwOnStop = false;

  /// Set to true to simulate the OS refusing microphone access.
  bool throwPermissionDenied = false;

  @override
  Future<void> start(String absoluteFilePath, {void Function()? onAutoStop}) async {
    if (throwPermissionDenied) {
      calls.add('start-denied');
      throw const RecordingPermissionDeniedException();
    }
    lastRequestedPath = absoluteFilePath;
    lastAutoStop = onAutoStop;
    calls.add('start');
    final gate = startGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
    if (throwOnStop) throw StateError('the recorder failed to finalize');
    if (stopReturnsNull) return null;
    return lastRequestedPath ?? '/fake/recordings/fake.m4a';
  }

  @override
  Future<void> dispose() async {}
}

/// Records play calls and snapshots how many sessions were already persisted
/// at the moment playback started — that snapshot is what proves the
/// save-before-replay ordering (D-08/D-10).
class FakeAudioPlayerService extends AudioPlayerService {
  FakeAudioPlayerService(this.calls, this.databaseHelper);

  final List<String> calls;
  final DatabaseHelper databaseHelper;

  int? sessionsAtFirstPlay;

  /// Set to true to simulate the player failing on an already-saved answer.
  bool throwOnPlay = false;

  @override
  Future<void> play(String absoluteFilePath, {bool awaitCompletion = false}) async {
    calls.add('play');
    if (throwOnPlay) throw StateError('playback failed');
    sessionsAtFirstPlay ??= (await databaseHelper.listSessions()).length;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// A [DatabaseHelper] whose crash-safety-critical write always fails, standing
/// in for a full disk / corrupt database at the exact moment of the save.
class FailingDatabaseHelper extends DatabaseHelper {
  @override
  Future<int> insertAnsweredSession({
    required String questionText,
    required String audioRelativePath,
  }) async {
    throw StateError('disk full: /private/var/mobile/.../englishreflex.db');
  }
}

void main() {
  late Directory tempDir;
  late DatabaseHelper databaseHelper;
  late List<String> calls;
  late FakeRecordingService recordingService;
  late FakeAudioPlayerService audioPlayerService;
  late PracticeState state;

  /// Yields to the event loop until [condition] holds (or we give up), so a
  /// test can observe a state that only exists between two real async awaits.
  Future<void> pumpUntil(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_state_test');
    documentsDirProvider = () async => tempDir;

    databaseHelper = DatabaseHelper();
    calls = <String>[];
    recordingService = FakeRecordingService(calls);
    audioPlayerService = FakeAudioPlayerService(calls, databaseHelper);
    state = PracticeState(
      recordingService: recordingService,
      audioPlayerService: audioPlayerService,
      databaseHelper: databaseHelper,
    );
  });

  tearDown(() async {
    state.dispose();
    await databaseHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('a freshly constructed PracticeState is arming, not idle', () {
    // The cold-launch window (orphan sweep, then the first start) must not
    // flash a recovery control before anything has gone wrong.
    expect(state.phase, PracticePhase.arming);
    expect(calls, isEmpty);
  });

  test('startNewQuestion begins recording immediately, with no user action',
      () async {
    await state.startNewQuestion();

    expect(state.phase, PracticePhase.recording);
    expect(calls, ['start']);
    expect(recordingService.lastRequestedPath, isNotNull);
    expect(recordingService.lastRequestedPath, endsWith('.m4a'));
  });

  test('the phase stays arming until the recorder has actually started',
      () async {
    final gate = Completer<void>();
    recordingService.startGate = gate;

    final started = state.startNewQuestion();
    await pumpUntil(() => calls.contains('start'));

    // Both halves matter: `arming` is also the constructor's initial phase, so
    // the phase alone would pass even if nothing had been issued.
    expect(calls, contains('start'));
    expect(state.phase, PracticePhase.arming);

    gate.complete();
    await started;

    expect(state.phase, PracticePhase.recording);
  });

  test('stopRecording saves BEFORE replaying, then resets and re-arms',
      () async {
    await state.startNewQuestion();
    await state.stopRecording();

    // Ordering contract: finalize -> save -> replay -> reset (D-08/D-10/D-03).
    expect(calls, ['start', 'stop', 'play', 'start']);

    // The DB row was already committed when playback started.
    expect(audioPlayerService.sessionsAtFirstPlay, 1);

    final sessions = await databaseHelper.listSessions();
    expect(sessions, hasLength(1));

    final answers = await databaseHelper.listAnswersForSession(sessions.single.id!);
    expect(answers, hasLength(1));
    expect(answers.single.audioPath, startsWith('recordings/'));
    expect(answers.single.audioPath.startsWith('/'), isFalse);

    // Reset loop: the screen is recording a fresh question again (D-03).
    expect(state.phase, PracticePhase.recording);
  });

  test('a losing stop signal is surfaced as a recoverable failure and writes '
      'nothing', () async {
    await state.startNewQuestion();
    recordingService.stopReturnsNull = true;

    await state.stopRecording();

    expect(calls, ['start', 'stop']);
    expect(await databaseHelper.listSessions(), isEmpty);
    // Deliberately NOT `idle`: every reachable route to a null finalized path
    // is a recorder-level failure, and only the error phase carries a Retry.
    expect(state.phase, PracticePhase.error);
  });

  test('stopRecording is a no-op when nothing is recording', () async {
    await state.stopRecording();

    expect(calls, isEmpty);
    expect(await databaseHelper.listSessions(), isEmpty);
  });

  test('two recordings in a row produce two separate sessions', () async {
    await state.startNewQuestion();
    await state.stopRecording();
    await state.stopRecording();

    final sessions = await databaseHelper.listSessions();
    expect(sessions, hasLength(2));
    expect(sessions.first.id, isNot(sessions.last.id));
    for (final session in sessions) {
      expect(await databaseHelper.listAnswersForSession(session.id!),
          hasLength(1));
    }
  });

  test('two recordings started in the same millisecond do not collide',
      () async {
    await state.startNewQuestion();
    final firstPath = recordingService.lastRequestedPath;
    await state.stopRecording();
    final secondPath = recordingService.lastRequestedPath;

    // The millisecond half of the name can repeat; the entropy suffix cannot.
    expect(secondPath, isNot(firstPath));
  });

  test('a disposal racing the stop still saves the finished answer', () async {
    // REGRESSION GUARD (WR-01). The `_disposed` early return used to sit
    // BETWEEN recordingService.stop() and insertAnsweredSession() — i.e. on the
    // wrong side of the commit. By the time that check ran the recorder had
    // ALREADY finalized the .m4a on disk, so a teardown landing in that window
    // left an answer the user had fully spoken with no row referencing it, to
    // be swept off disk by the next launch's pruneOrphanRecordings(). That
    // directly violates the 01-04 prohibition: "An answer the user has already
    // spoken and finished must never be silently discarded."
    //
    // Deliberately a plain `test()`, not a `testWidgets()`: initialising the
    // widget binding in this file would make FlutterError.onError fail the
    // save-failure test below (IN-04).
    //
    // Its own PracticeState so the shared one is still disposable in tearDown.
    final racingState = PracticeState(
      recordingService: recordingService,
      audioPlayerService: audioPlayerService,
      databaseHelper: databaseHelper,
    );

    await racingState.startNewQuestion();

    // stopRecording() runs synchronously up to `await recordingService.stop()`,
    // so this dispose lands in exactly the window the finalized file exists in.
    final Future<void> stopping = racingState.stopRecording();
    racingState.dispose();
    await stopping;

    final sessions = await databaseHelper.listSessions();
    expect(sessions, hasLength(1),
        reason: 'a finalized recording must be persisted even mid-teardown');

    final answers =
        await databaseHelper.listAnswersForSession(sessions.single.id!);
    expect(answers, hasLength(1));
    expect(answers.single.audioPath,
        endsWith(p.basename(recordingService.lastRequestedPath!)));

    // Only the UI-facing work is skipped after disposal: no replay, and no
    // re-arm behind a screen that no longer exists.
    expect(calls, ['start', 'stop']);
  });

  group('error handling', () {
    test('a denied microphone permission shows the exact UI-SPEC copy and '
        'writes nothing', () async {
      recordingService.throwPermissionDenied = true;

      await state.startNewQuestion();

      expect(state.phase, PracticePhase.error);
      // Verbatim UI-SPEC Copywriting Contract string — no paraphrase, and no
      // exception text, class name or file path leaking through.
      expect(
        state.errorMessage,
        'Recording failed — check your microphone permission and try again.',
      );
      expect(state.errorMessage, isNot(contains('Exception')));

      // Prohibition: a denied attempt never writes a placeholder row.
      expect(await databaseHelper.listSessions(), isEmpty);
    });

    test('retry() re-attempts recording once permission is granted', () async {
      recordingService.throwPermissionDenied = true;
      await state.startNewQuestion();
      expect(state.phase, PracticePhase.error);

      // The user opens Settings, grants the microphone, comes back and taps
      // Retry on the banner.
      recordingService.throwPermissionDenied = false;
      await state.retry();

      expect(state.phase, PracticePhase.recording);
      expect(state.errorMessage, isNull);
      expect(calls, ['start-denied', 'start']);
    });

    test('a recorder that throws on stop lands in error, never in saving',
        () async {
      await state.startNewQuestion();
      recordingService.throwOnStop = true;

      await state.stopRecording();

      expect(state.phase, PracticePhase.error);
      expect(await databaseHelper.listSessions(), isEmpty);
    });

    test('a replay failure never blocks the loop — the answer is already saved',
        () async {
      await state.startNewQuestion();
      audioPlayerService.throwOnPlay = true;

      await state.stopRecording();

      expect(
        state.phase,
        anyOf(PracticePhase.recording, PracticePhase.arming),
      );
      expect(await databaseHelper.listSessions(), hasLength(1));
    });

    test('a save failure shows the same copy and does NOT auto-restart '
        'recording', () async {
      final failingHelper = FailingDatabaseHelper();
      final failingState = PracticeState(
        recordingService: recordingService,
        audioPlayerService: audioPlayerService,
        databaseHelper: failingHelper,
      );
      addTearDown(failingState.dispose);

      await failingState.startNewQuestion();
      await failingState.stopRecording();

      expect(failingState.phase, PracticePhase.error);
      expect(
        failingState.errorMessage,
        'Recording failed — check your microphone permission and try again.',
      );
      // No replay, and crucially no second 'start': the loop waits for the
      // user's Retry tap rather than spinning into another recording.
      expect(calls, ['start', 'stop']);
      // The real (non-failing) database is untouched.
      expect(await databaseHelper.listSessions(), isEmpty);
    });

    test('every injected failure leaves the loop in a recoverable phase',
        () async {
      const recoverable = <PracticePhase>{
        PracticePhase.error,
        PracticePhase.recording,
        PracticePhase.arming,
      };

      // 1. The microphone is denied.
      recordingService.throwPermissionDenied = true;
      await state.startNewQuestion();
      expect(recoverable, contains(state.phase));

      // 2. The stop finalizes nothing.
      recordingService.throwPermissionDenied = false;
      await state.retry();
      recordingService.stopReturnsNull = true;
      await state.stopRecording();
      expect(recoverable, contains(state.phase));

      // 3. The recorder throws on stop.
      recordingService.stopReturnsNull = false;
      await state.retry();
      recordingService.throwOnStop = true;
      await state.stopRecording();
      expect(recoverable, contains(state.phase));

      // 4. Playback throws on an already-committed answer.
      recordingService.throwOnStop = false;
      await state.retry();
      audioPlayerService.throwOnPlay = true;
      await state.stopRecording();
      expect(recoverable, contains(state.phase));
    });
  });

  group('re-entrancy and the auto-stop backstop', () {
    test('the auto-stop deadline still stops the recorder when the loop has '
        'already left the recording phase', () async {
      await state.startNewQuestion();
      final autoStop = recordingService.lastAutoStop;
      expect(autoStop, isNotNull);

      // Drive the loop out of `recording` the way a losing stop does.
      recordingService.stopReturnsNull = true;
      await state.stopRecording();
      expect(state.phase, PracticePhase.error);

      calls.clear();
      autoStop!();
      await pumpUntil(() => calls.contains('stop'));

      // An armed recorder must never be left running past the 60 s cap (D-09).
      expect(calls, contains('stop'));
    });

    test('two overlapping startNewQuestion calls produce exactly one recorder '
        'start, and the saved path is the one the recorder was given', () async {
      final first = state.startNewQuestion();
      final second = state.startNewQuestion();
      await Future.wait<void>([first, second]);

      expect(calls.where((c) => c == 'start').length, 1);

      final requestedPath = recordingService.lastRequestedPath!;
      await state.stopRecording();

      final sessions = await databaseHelper.listSessions();
      expect(sessions, hasLength(1));
      final answers =
          await databaseHelper.listAnswersForSession(sessions.single.id!);
      expect(answers.single.audioPath, endsWith(p.basename(requestedPath)));
    });
  });
}
