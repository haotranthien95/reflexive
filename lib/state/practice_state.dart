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

/// The single user-facing failure message for this phase, verbatim from the
/// UI-SPEC Copywriting Contract.
///
/// Every failure path — microphone permission denied, recorder failure, or a
/// save failure — shows exactly this string. Raw exception text, stack traces
/// and file paths are deliberately never surfaced (T-03-02): the user gets the
/// likely cause and the next action, nothing about the app's internals.
const String kRecordingErrorMessage =
    'Recording failed — check your microphone permission and try again.';

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
  ///
  /// If the microphone is unavailable (permission denied, or any other recorder
  /// failure) the loop moves to [PracticePhase.error] instead of crashing, and
  /// writes nothing at all to the database.
  Future<void> startNewQuestion() async {
    currentQuestion = _pickQuestion();
    errorMessage = null;
    phase = PracticePhase.recording;
    notifyListeners();

    try {
      final dir = await ensureRecordingsDir();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRelativePath = recordingRelativePath(fileName);
      final absolutePath = p.join(dir.path, fileName);

      await recordingService.start(
        absolutePath,
        onAutoStop: () => unawaited(stopRecording()),
      );
    } catch (_) {
      // Deliberately swallows the exception object: only the fixed UI-SPEC copy
      // ever reaches the user. Nothing is persisted on this path — there is no
      // finalized audio file, so there must be no session or answer row.
      _currentRelativePath = null;
      _fail();
    }
  }

  /// Re-attempts a recording after a failure — wired to the error banner's
  /// Retry button. Retrying is always user-initiated; the app never loops on a
  /// denied permission by itself (T-03-03).
  Future<void> retry() => startNewQuestion();

  /// Moves the loop into its single user-visible failure state.
  void _fail() {
    phase = PracticePhase.error;
    errorMessage = kRecordingErrorMessage;
    notifyListeners();
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

    try {
      await databaseHelper.insertAnsweredSession(
        questionText: currentQuestion,
        audioRelativePath: relativePath,
      );
    } catch (_) {
      // The transaction rolled back, so nothing partial was written. Surface
      // the same fixed copy and stop here — the loop must NOT auto-restart into
      // another recording after a save failure; the user's Retry tap does that.
      _fail();
      return;
    }

    phase = PracticePhase.replaying;
    notifyListeners();

    final absolutePath = await toAbsolutePath(relativePath);
    await audioPlayerService.play(absolutePath, awaitCompletion: true);

    // Reset to a fresh question and re-arm recording (D-03).
    await startNewQuestion();
  }
}
