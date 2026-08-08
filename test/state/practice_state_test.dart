import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/services/audio_player_service.dart';
import 'package:englishreflex/services/recording_service.dart';
import 'package:englishreflex/state/practice_state.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Records start/stop calls without touching any platform channel. The real
/// [RecordingService] creates its `AudioRecorder` lazily, so overriding both
/// methods here means no plugin is ever constructed.
class FakeRecordingService extends RecordingService {
  FakeRecordingService(this.calls);

  final List<String> calls;
  String? lastRequestedPath;

  /// Set to true to simulate a second stop signal losing the race.
  bool stopReturnsNull = false;

  /// Set to true to simulate the OS refusing microphone access.
  bool throwPermissionDenied = false;

  @override
  Future<void> start(String absoluteFilePath, {void Function()? onAutoStop}) async {
    if (throwPermissionDenied) {
      calls.add('start-denied');
      throw const RecordingPermissionDeniedException();
    }
    lastRequestedPath = absoluteFilePath;
    calls.add('start');
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
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

  @override
  Future<void> play(String absoluteFilePath, {bool awaitCompletion = false}) async {
    calls.add('play');
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

  test('startNewQuestion begins recording immediately, with no user action',
      () async {
    await state.startNewQuestion();

    expect(state.phase, PracticePhase.recording);
    expect(calls, ['start']);
    expect(recordingService.lastRequestedPath, isNotNull);
    expect(recordingService.lastRequestedPath, endsWith('.m4a'));
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

  test('a losing stop signal writes nothing — first stop wins', () async {
    await state.startNewQuestion();
    recordingService.stopReturnsNull = true;

    await state.stopRecording();

    expect(calls, ['start', 'stop']);
    expect(await databaseHelper.listSessions(), isEmpty);
    expect(state.phase, PracticePhase.idle);
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
  });
}
