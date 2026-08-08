import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/questions.dart';
import '../db/database_helper.dart';
import '../services/audio_player_service.dart';
import '../services/recording_service.dart';
import '../utils/audio_paths.dart';

/// Where the practice loop currently is.
enum PracticePhase { idle, recording, saving, replaying, error }

/// The whole Phase 1 practice loop in one [ChangeNotifier]:
///
///   pick question → record → (manual Stop or 60 s auto-stop) → finalize file
///   → save session+answer in ONE transaction → auto-replay → reset & repeat.
///
/// Services are injected through the constructor (manual constructor
/// injection, no DI package) — this is the seam the tests substitute fakes on.
class PracticeState extends ChangeNotifier {
  PracticeState({
    required this.recordingService,
    required this.audioPlayerService,
    required this.databaseHelper,
  });

  final RecordingService recordingService;
  final AudioPlayerService audioPlayerService;
  final DatabaseHelper databaseHelper;

  final Random _random = Random();

  /// The prompt currently shown to the user.
  String currentQuestion = kQuestions.first;

  PracticePhase phase = PracticePhase.idle;

  String? errorMessage;

  int? _lastQuestionIndex;

  /// DB-relative path of the recording currently being captured.
  String? _currentRelativePath;

  /// Picks the next prompt, avoiding an immediate repeat where possible.
  String _pickQuestion() {
    if (kQuestions.length == 1) {
      _lastQuestionIndex = 0;
      return kQuestions.first;
    }
    int index;
    do {
      index = _random.nextInt(kQuestions.length);
    } while (index == _lastQuestionIndex);
    _lastQuestionIndex = index;
    return kQuestions[index];
  }

  /// Shows a fresh question and immediately starts recording — no Start button
  /// and no confirmation (D-01).
  Future<void> startNewQuestion() async {
    currentQuestion = _pickQuestion();
    errorMessage = null;
    phase = PracticePhase.recording;
    notifyListeners();

    final dir = await ensureRecordingsDir();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
    _currentRelativePath = recordingRelativePath(fileName);
    final absolutePath = p.join(dir.path, fileName);

    await recordingService.start(
      absolutePath,
      onAutoStop: () => unawaited(stopRecording()),
    );
  }

  /// Ends the current recording — invoked by the Stop button and by the 60 s
  /// auto-stop deadline. Only the first signal to arrive does any work.
  ///
  /// Ordering here is the crash-safety contract (D-08/D-10): the DB write only
  /// happens after `stop()` has returned a finalized path, and the replay only
  /// happens after that write has committed.
  Future<void> stopRecording() async {
    if (phase != PracticePhase.recording) return;
    phase = PracticePhase.saving;
    notifyListeners();

    final finalizedPath = await recordingService.stop();
    if (finalizedPath == null) {
      // A stop was already in flight (first-stop-wins) or the recorder had
      // nothing to finalize. Nothing was captured, so nothing is saved.
      phase = PracticePhase.idle;
      notifyListeners();
      return;
    }

    final relativePath =
        _currentRelativePath ?? recordingRelativePath(p.basename(finalizedPath));
    _currentRelativePath = null;

    await databaseHelper.insertAnsweredSession(
      questionText: currentQuestion,
      audioRelativePath: relativePath,
    );

    phase = PracticePhase.replaying;
    notifyListeners();

    final absolutePath = await toAbsolutePath(relativePath);
    await audioPlayerService.play(absolutePath, awaitCompletion: true);

    // Reset to a fresh question and re-arm recording (D-03).
    await startNewQuestion();
  }
}
