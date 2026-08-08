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

  @override
  Future<void> start(String absoluteFilePath, {void Function()? onAutoStop}) async {
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
}
