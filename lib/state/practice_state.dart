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
///
/// [arming] sits deliberately between [idle] and [recording]: it is the window
/// in which `RecordingService.start()` is still in flight. The screen must not
/// claim to be recording — no listening mascot, no STOP button — until the
/// microphone is actually live.
enum PracticePhase { idle, arming, recording, saving, replaying, error }

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

  /// Starts at [PracticePhase.arming], not [PracticePhase.idle]: the screen's
  /// bootstrap awaits the orphan sweep before the first `startNewQuestion()`,
  /// and `idle` renders a recovery control that would otherwise flash on every
  /// cold launch before anything has gone wrong. `arming` is the honest
  /// description of that window; `idle` keeps its control for any path that
  /// reaches it without being the launch state.
  PracticePhase phase = PracticePhase.arming;

  String? errorMessage;

  int? _lastQuestionIndex;

  /// DB-relative path of the recording currently being captured.
  String? _currentRelativePath;

  /// Non-null while a `startNewQuestion()` is in flight — the state half of the
  /// re-entrancy guard (the service half lives in [RecordingService.start]).
  Future<void>? _startInFlight;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// [notifyListeners] that is safe after [dispose].
  ///
  /// The loop is a chain of awaits over the recorder, the disk and the player;
  /// any of them can resolve after the screen has been torn down.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

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
  /// Re-entrant calls collapse onto the in-flight one. Without this, a Retry
  /// tap landing on top of the loop's own reset would arm two recorders and
  /// commit a `question_answers` row naming a file the surviving recorder was
  /// never told to write.
  Future<void> startNewQuestion() {
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    final started =
        _startNewQuestion().whenComplete(() => _startInFlight = null);
    _startInFlight = started;
    return started;
  }

  /// If the microphone is unavailable (permission denied, or any other recorder
  /// failure) the loop moves to [PracticePhase.error] instead of crashing, and
  /// writes nothing at all to the database.
  Future<void> _startNewQuestion() async {
    currentQuestion = _pickQuestion();
    errorMessage = null;
    // NOT `recording` yet: the recorder has not been armed, so claiming to be
    // recording here would put a STOP button and a listening mascot on screen
    // while the microphone is still cold. D-01 is untouched — recording still
    // begins with no user action; only the claim waits.
    phase = PracticePhase.arming;
    _notify();

    try {
      final dir = await ensureRecordingsDir();
      if (_disposed) return;

      // The random suffix is load-bearing: two recordings starting inside the
      // same millisecond would otherwise share a file name and one would
      // silently overwrite the other's saved answer.
      final fileName = '${DateTime.now().millisecondsSinceEpoch}'
          '_${_random.nextInt(1 << 20)}.m4a';
      final absolutePath = p.join(dir.path, fileName);

      await recordingService.start(
        absolutePath,
        onAutoStop: () => unawaited(_onAutoStop()),
      );
      if (_disposed) return;

      // Only now is the microphone genuinely live.
      _currentRelativePath = recordingRelativePath(fileName);
      phase = PracticePhase.recording;
      _notify();
    } catch (_) {
      // Deliberately swallows the exception object: only the fixed UI-SPEC copy
      // ever reaches the user. Nothing is persisted on this path — there is no
      // finalized audio file, so there must be no session or answer row.
      _currentRelativePath = null;
      _fail();
    }
  }

  /// The 60 s deadline landing (D-09).
  ///
  /// When the loop is still recording this is an ordinary stop. When it is NOT
  /// — for example a stop signal landed during the arming window and pushed the
  /// loop into [PracticePhase.error] — the recorder that finished arming
  /// afterwards must still be finalized, or it would keep capturing unbounded
  /// past [kMaxRecordingDuration] behind an error banner.
  Future<void> _onAutoStop() async {
    if (phase == PracticePhase.recording) {
      await stopRecording();
      return;
    }
    try {
      await recordingService.stop();
    } catch (_) {
      // Best-effort backstop; there is nothing further to recover here.
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
    _notify();
  }

  /// Ends the current recording — invoked by the Stop button and by the 60 s
  /// auto-stop deadline. Only the first signal to arrive does any work.
  ///
  /// Ordering here is the crash-safety contract (D-08/D-10): the DB write only
  /// happens after `stop()` has returned a finalized path, and the replay only
  /// happens after that write has committed.
  ///
  /// EVERY await below is guarded. That is not defensive decoration: it is what
  /// makes [PracticePhase.saving] and [PracticePhase.replaying] strictly
  /// transient, and therefore what makes it safe for `PhaseControl` to render
  /// them as status labels rather than escape hatches. Reintroducing an
  /// unguarded await here turns both into dead ends.
  Future<void> stopRecording() async {
    if (phase != PracticePhase.recording) return;
    phase = PracticePhase.saving;
    _notify();

    final String? finalizedPath;
    try {
      finalizedPath = await recordingService.stop();
    } catch (_) {
      // A recorder that cannot finalize has produced no usable file. Surface
      // the fixed copy so the banner's Retry is reachable — never leave the
      // loop parked in `saving`.
      _currentRelativePath = null;
      _fail();
      return;
    }
    if (_disposed) return;

    if (finalizedPath == null) {
      // Every reachable route to a null finalized path is a recorder-level
      // failure. Nothing was captured, so nothing is saved — but the user still
      // needs a way forward, which only the error phase provides.
      _currentRelativePath = null;
      _fail();
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
    } catch (error, stack) {
      // The transaction rolled back, so nothing partial was written. Surface
      // the same fixed copy and stop here — the loop must NOT auto-restart into
      // another recording after a save failure; the user's Retry tap does that.
      //
      // The cause goes to developer-facing sinks ONLY. The UI-SPEC Copywriting
      // Contract locks one string for both the mic-denied and save-failure
      // cases, so not a character of this reaches the screen (T-04-04).
      debugPrint('EnglishReflex: saving the answer failed: $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'englishreflex',
          context: ErrorDescription('saving a finished answer'),
        ),
      );
      _fail();
      return;
    }
    if (_disposed) return;

    phase = PracticePhase.replaying;
    _notify();

    try {
      final absolutePath = await toAbsolutePath(relativePath);
      await audioPlayerService.play(absolutePath, awaitCompletion: true);
    } catch (_) {
      // The answer is already committed, so a replay failure must never block
      // the loop — fall straight through to the reset below.
    }
    if (_disposed) return;

    // Reset to a fresh question and re-arm recording (D-03).
    await startNewQuestion();
  }
}
