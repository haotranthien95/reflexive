import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/questions.dart';
import '../db/database_helper.dart';
import '../models/session_config.dart';
import '../services/audio_player_service.dart';
import '../services/recording_service.dart';
import '../utils/audio_paths.dart';
import '../utils/pausable_countdown.dart';

/// Where the practice loop currently is.
///
/// [arming] sits deliberately between [reading] and [recording]: it is the
/// window in which `RecordingService.start()` is still in flight. The screen
/// must not claim to be recording — no listening mascot, no STOP button — until
/// the microphone is actually live.
///
/// [getReady] and [reading] are the two Phase 2 countdown phases and are
/// deliberately distinct values rather than one phase plus a flag: they render
/// opposite slots (D-22 — `getReady` hides the question, `reading` makes it
/// dominant), and separate values are what let `kPhaseControlKeys`' totality
/// test prove each one has a control.
///
/// [reading] running fully to zero BEFORE [arming] begins is D-20: the
/// countdown never lands inside the answer file, and the microphone is never
/// claimed to be live while it is still cold.
enum PracticePhase {
  idle,
  getReady,
  reading,
  arming,
  recording,
  saving,
  replaying,
  complete,
  error,
}

/// The session-start countdown, LOOP-01. A literal, not a setting: D-16 makes
/// `t` configurable and deliberately leaves this one fixed.
const int kGetReadySeconds = 3;

/// The single user-facing failure message for this phase, verbatim from the
/// UI-SPEC Copywriting Contract.
///
/// Every failure path — microphone permission denied, recorder failure, or a
/// save failure — shows exactly this string. Raw exception text, stack traces
/// and file paths are deliberately never surfaced (T-03-02): the user gets the
/// likely cause and the next action, nothing about the app's internals.
const String kRecordingErrorMessage =
    'Recording failed — check your microphone permission and try again.';

/// The whole practice loop in one [ChangeNotifier]:
///
///   3·2·1 get-ready → show question + `t` countdown → arm recorder → record →
///   (manual Stop or the `d` auto-stop) → finalize file → save the answer in ONE
///   transaction → completion state.
///
/// Services are injected through the constructor (manual constructor
/// injection, no DI package) — this is the seam the tests substitute fakes on.
/// [config] joins them as a required value: the loop's timings, question count
/// and replay behaviour are the session's, never module-level constants.
class PracticeState extends ChangeNotifier {
  PracticeState({
    required this.recordingService,
    required this.audioPlayerService,
    required this.databaseHelper,
    required this.config,
  });

  final RecordingService recordingService;
  final AudioPlayerService audioPlayerService;
  final DatabaseHelper databaseHelper;

  /// This session's configuration, fixed for its whole lifetime (D-18).
  final SessionConfig config;

  /// The Phase 3 swap point. The loop asks this for prompts and never reads
  /// [kQuestions] itself.
  final QuestionSource questionSource = const PlaceholderQuestionSource();

  /// Used ONLY for the recording file-name entropy suffix. The question picker
  /// used to draw from this too; D-23 replaced that with sequential bank order.
  final Random _random = Random();

  /// The prompt currently shown to the user.
  String currentQuestion = kQuestions.first;

  /// 1-based position in the session — the `k` of "Question k of N".
  int questionNumber = 1;

  /// Answers actually committed to the database so far. Incremented only AFTER
  /// the transaction returns, so it can never exceed the committed row count.
  int answeredCount = 0;

  /// Whatever countdown is currently on screen: the 3·2·1 in [getReady], `t` in
  /// [reading]. Zero when no countdown is running.
  int countdownSeconds = 0;

  /// Seconds left on the `d` deadline while recording (D-21), null otherwise.
  int? recordingSecondsRemaining;

  /// The lazily-created `sessions` row this session's answers belong to — null
  /// until the first answer commits (D-26), which is what keeps a session
  /// abandoned before any answer from writing anything at all.
  int? sessionId;

  /// When the first answer of this session was committed.
  DateTime? sessionStartedAt;

  /// Exactly ONE countdown object is alive at a time. Every phase transition
  /// replaces it and `dispose()` cancels it, so a torn-down screen can never
  /// leave a pending timer behind (which the test binding fails on).
  PausableCountdown? _countdown;

  /// Starts at [PracticePhase.arming], not [PracticePhase.idle]: `idle` renders
  /// a recovery control that would otherwise flash before anything has gone
  /// wrong. In a real session this value is never rendered — `PracticeScreen`
  /// calls [startSession] synchronously in `initState`, so the first frame is
  /// already [PracticePhase.getReady]. `idle` keeps its control for any path
  /// that reaches it without being the construction state.
  PracticePhase phase = PracticePhase.arming;

  String? errorMessage;

  /// DB-relative path of the recording currently being captured.
  String? _currentRelativePath;

  /// Non-null while a `startNewQuestion()` is in flight — the state half of the
  /// re-entrancy guard (the service half lives in [RecordingService.start]).
  Future<void>? _startInFlight;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    // Terminal, and unconditional: a countdown that outlives this object would
    // tick against a torn-down screen and fail the test binding at teardown.
    _countdown?.cancel();
    _countdown = null;
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

  /// The prompt for the CURRENT [questionNumber], in sequential bank order,
  /// cycling when the session is longer than the bank (D-23).
  ///
  /// Deliberately a pure function of [questionNumber]: [reading] and [arming]
  /// both call it for the same question, and a picker with hidden state (as
  /// Phase 1's random one had) would hand them two different prompts — the
  /// question card would change between "read this" and "speak now".
  String _pickQuestion() =>
      questionAt(questionSource.questionsFor(config), questionNumber - 1);

  /// Starts the session with the 3·2·1 get-ready countdown (LOOP-01).
  ///
  /// The question card stays hidden throughout it (D-22) and the recorder is not
  /// touched — nothing about the microphone happens until [reading] has also run
  /// to zero.
  Future<void> startSession() async {
    _enterGetReady();
  }

  /// Replaces the single live countdown and arms the new one.
  void _arm(PausableCountdown countdown) {
    _countdown?.cancel();
    _countdown = countdown;
    countdown.start();
  }

  void _enterGetReady() {
    phase = PracticePhase.getReady;
    countdownSeconds = kGetReadySeconds;
    recordingSecondsRemaining = null;
    _notify();
    _arm(
      PausableCountdown(
        seconds: kGetReadySeconds,
        onTick: (remaining) {
          countdownSeconds = remaining;
          _notify();
        },
        onElapsed: _enterReading,
      ),
    );
  }

  /// The per-question `t` countdown (LOOP-02). It runs FULLY to zero before the
  /// recorder is armed (D-20) — `onElapsed` is the only path to
  /// [startNewQuestion] in a normal session.
  void _enterReading() {
    currentQuestion = _pickQuestion();
    errorMessage = null;
    phase = PracticePhase.reading;
    countdownSeconds = config.thinkingSeconds;
    _notify();
    _arm(
      PausableCountdown(
        seconds: config.thinkingSeconds,
        onTick: (remaining) {
          countdownSeconds = remaining;
          _notify();
        },
        onElapsed: () => unawaited(startNewQuestion()),
      ),
    );
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
        // The session's `d` (SETUP-05/D-21), not the Phase 1 fixed 60 s.
        maxDuration: Duration(seconds: config.answerSeconds),
        onTick: (remaining) {
          recordingSecondsRemaining = remaining;
          _notify();
        },
      );
      if (_disposed) return;

      // Only now is the microphone genuinely live.
      _currentRelativePath = recordingRelativePath(fileName);
      recordingSecondsRemaining = config.answerSeconds;
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
  ///
  /// Disposal is handled on the same principle. The `_disposed` checks sit only
  /// AFTER the `insertAnsweredSession` commit, never between the recorder
  /// finalizing the file and that commit: once the audio exists on disk the
  /// save is unconditional, and only the notification, the replay and the
  /// re-arm depend on the screen still being alive.
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

    // NOTE: deliberately NO `if (_disposed) return;` here. Once stop() has
    // returned, the recorder has already finalized the user's answer on disk,
    // and the save below IS the crash-safety contract: an answer that was fully
    // spoken must never be silently discarded just because the screen is being
    // torn down. Returning here left the .m4a on disk with no row referencing
    // it, so the next launch's pruneOrphanRecordings() deleted it. The
    // disposal check belongs AFTER the commit — see below.
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
    // Safe here and only here: the answer is committed, so everything that
    // remains — the replay and the re-arm — is UI-facing work that a torn-down
    // screen has no use for.
    if (_disposed) return;

    // Both counters move only AFTER the commit returned, so neither can ever
    // claim more answers than the database actually holds.
    answeredCount += 1;
    sessionStartedAt ??= DateTime.now();
    recordingSecondsRemaining = null;

    // Plan 02-01 deliberately ends the session on the first committed answer:
    // this is the tracer's far end, not the finished loop. Plan 02-02 restores
    // the optional replay (`config.autoReplay`) and the inter-question advance
    // here, and only then does `questionCount` start deciding when to complete.
    phase = PracticePhase.complete;
    _notify();
  }
}
