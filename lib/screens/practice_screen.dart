import 'dart:async';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/session.dart';
import '../models/session_config.dart';
import '../services/audio_player_service.dart';
import '../services/recording_service.dart';
import '../services/screen_wake_controller.dart';
import '../state/practice_state.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/mascot.dart';
import '../widgets/phase_control.dart';
import 'session_detail_screen.dart';

/// The 3·2·1 get-ready numeral: Display × 4, coral, a single glyph.
///
/// Deliberately ONE named constant used at exactly ONE call site, and derived
/// from `displayLarge` rather than authored as a fifth type-scale step — a
/// second use of this constant is meant to be visible in review.
const double kCountdownGlyphSize = 128;

/// One configured practice session, from the 3·2·1 get-ready countdown through
/// to the completion state.
///
/// Takes its whole configuration as a value (D-28): it stopped being the app's
/// `home:` when Setup took that role, and every timing it uses is the user's,
/// not a constant.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.config,
    this.recordingService,
    this.audioPlayerService,
    this.databaseHelper,
    this.screenWakeController,
  });

  final SessionConfig config;

  /// Optional injected collaborators — the seam a host test uses to run this
  /// screen without a platform channel. Null in production, where the real
  /// implementations are constructed here.
  final RecordingService? recordingService;
  final AudioPlayerService? audioPlayerService;
  final DatabaseHelper? databaseHelper;
  final ScreenWakeController? screenWakeController;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  late final PracticeState _state;

  /// Resolved lazily, so a test that injects a fake never constructs the
  /// platform channel behind the production implementation.
  late final ScreenWakeController _wake =
      widget.screenWakeController ?? const WakelockPlusScreenWakeController();

  /// Decodes the raw lifecycle stream into discrete transitions. Disposed
  /// BEFORE the recorder teardown chain below.
  late final AppLifecycleListener _lifecycle;

  /// The second interruption producer: a pause the app did not ask for.
  late final StreamSubscription<bool> _pausedSub;

  /// True once the wakelock has been released for good (session over or screen
  /// torn down), so a late lifecycle callback cannot re-acquire it.
  bool _wakeReleased = false;

  /// True while the one confirmation dialog is open.
  ///
  /// The re-entrancy guard for [_requestStop]: a second Stop tap, or a back
  /// gesture landing while the dialog is up, must never stack a second dialog
  /// on top of the first (CTRL-02/ordering).
  bool _confirmingStop = false;

  @override
  void initState() {
    super.initState();
    _state = PracticeState(
      recordingService: widget.recordingService ?? RecordingService(),
      audioPlayerService: widget.audioPlayerService ?? AudioPlayerService(),
      databaseHelper: widget.databaseHelper ?? DatabaseHelper(),
      config: widget.config,
    );
    // Synchronous by design: `startSession()` enters `getReady` before the
    // first build, so the construction-time `arming` phase is never rendered.
    //
    // The orphan sweep does NOT run here any more — it moved to `SetupScreen`'s
    // `initState` with its caller contract, which is now satisfied earlier
    // rather than later: it must complete before any recording file name is
    // chosen, and Setup is the first screen the user passes through.
    unawaited(_state.startSession());

    // D-30: the session owns the screen for as long as it runs. The default OS
    // timeout is routinely shorter than one thinking-time-plus-answer cycle, so
    // without this the screen locks mid-answer.
    unawaited(_setWake(true));
    // Releases the hold the moment the session is genuinely over, rather than
    // holding it until the user navigates away from the completion screen.
    _state.addListener(_releaseWakeOnCompletion);

    _lifecycle = AppLifecycleListener(
      // Deliberately the hidden transition (inactive → hidden), NOT inactive:
      // that one also fires for the notification shade, Control Centre, the app
      // switcher and an UNANSWERED incoming-call banner, so triggering on it
      // would pause a session that was never interrupted. An ANSWERED call
      // arrives on the audio path below instead — the two signals stay cleanly
      // separated and converge only at the handler.
      onHide: () {
        unawaited(_setWake(false));
        unawaited(_state.handleInterruption());
      },
      // Re-acquired on return, or one backgrounding would cost the rest of the
      // session its wakelock. Guarded, so it is never re-acquired after the
      // session has ended.
      onShow: () => unawaited(_setWake(true)),
    );

    // The second producer: a pause the app did NOT ask for. Filtered to the
    // true events — the false ones are this app's own resumes coming back.
    _pausedSub = _state.recordingService.onPausedChanged
        .where((bool paused) => paused)
        .listen((_) => unawaited(_state.handleInterruption()));
  }

  /// The one wakelock call site pair, with the silent-failure contract applied
  /// once. A wakelock failure is a nuisance, never a user-facing error — this
  /// phase introduces no new failure string.
  Future<void> _setWake(bool enabled) async {
    if (enabled && _wakeReleased) return;
    try {
      await (enabled ? _wake.enable() : _wake.disable());
    } catch (error) {
      debugPrint('EnglishReflex: the screen wakelock failed: $error');
    }
  }

  void _releaseWakeOnCompletion() {
    if (_wakeReleased || _state.phase != PracticePhase.complete) return;
    _wakeReleased = true;
    unawaited(_setWake(false));
  }

  @override
  void dispose() {
    // Torn down BEFORE the recorder chain below: a lifecycle callback or a
    // recorder state event arriving mid-teardown would drive a handler on a
    // half-disposed screen.
    _lifecycle.dispose();
    // Deliberately NOT awaited. Awaiting a broadcast subscription's cancel()
    // inside a widget test never returns — the future it yields is completed by
    // nothing the fake clock drives.
    unawaited(_pausedSub.cancel());
    _state.removeListener(_releaseWakeOnCompletion);
    _wakeReleased = true;
    unawaited(_setWake(false));

    // Stop any in-flight recording BEFORE tearing the recorder down: leaving
    // the screen must never leave the microphone live. The stop is fire-and-
    // forget (dispose cannot await) but its failure is swallowed explicitly
    // rather than surfacing as an unhandled async error.
    unawaited(
      _state.recordingService
          .stop()
          .catchError((Object _) => null)
          .whenComplete(_state.recordingService.dispose),
    );
    unawaited(_state.audioPlayerService.dispose());
    _state.dispose();
    super.dispose();
  }

  /// Opens the session just finished, from the completion state (D-27).
  ///
  /// Reads the row rather than synthesising a [Session] from local state: the
  /// `created_at` the detail screen shows must be the committed one.
  Future<void> _openThisSession() async {
    final int? id = _state.sessionId;
    if (id == null) return;
    final Session? session = await _state.databaseHelper.findSession(id);
    if (!mounted || session == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(
          session: session,
          databaseHelper: _state.databaseHelper,
        ),
      ),
    );
  }

  /// **The one and only way to end a session early** (CTRL-03 / D-25 / D-29).
  ///
  /// Both producers call exactly this: the app-bar Stop action and the system
  /// back gesture intercepted by [PopScope]. Confirming and acting live in one
  /// method rather than a `_confirmStop()` returning a bool plus two act-blocks,
  /// because two act-blocks is precisely how the back gesture and the Stop
  /// button drift into two different early exits.
  ///
  /// The order is fixed:
  ///   1. pause, so the session is frozen behind the dialog (D-25) — no clock
  ///      may run, and no answer may auto-save, while the user is deciding;
  ///   2. show the dialog;
  ///   3. anything that is not an explicit tap on the destructive action — the
  ///      safe action, a barrier tap, or a back gesture closing the dialog, the
  ///      last two of which arrive here as `null` — resumes and returns. There
  ///      is exactly ONE destructive path and it always requires that tap;
  ///   4. on confirm, with zero committed answers pop straight to Setup (D-26 —
  ///      nothing was ever written, so there is nothing to view), otherwise
  ///      enter the completion state a finished session also reaches (D-27).
  Future<void> _requestStop() async {
    if (_confirmingStop) return;
    _confirmingStop = true;
    try {
      await _state.pause();
      if (!mounted) return;

      final int answeredCount = _state.answeredCount;
      final bool? end = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) =>
            _StopConfirmationDialog(answeredCount: answeredCount),
      );

      if (end != true) {
        await _state.resume();
        return;
      }
      if (!mounted) return;

      if (_state.answeredCount == 0) {
        Navigator.of(context).pop();
        return;
      }
      _state.completeEarly();
    } finally {
      _confirmingStop = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Wraps the whole Scaffold, not just the body: the app-bar title carries
    // "Question k of N" and switches to "Session complete", so the chrome has
    // to rebuild with the loop too.
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final bool hasError = _state.phase == PracticePhase.error;
        final bool isComplete = _state.phase == PracticePhase.complete;
        final bool isPaused = _state.isPaused;
        // What the anchor and focus slots render. While paused this is the
        // FROZEN phase, so the numeral or the question card stays on screen at
        // the value it stopped on (UI-SPEC paused row).
        final PracticePhase displayPhase = _state.displayPhase;

        return PopScope<void>(
          // D-29: while a session is live the system back gesture must not pop
          // the route — it is routed into the SAME confirmation dialog the Stop
          // action opens. Interception is RELEASED in the completion state,
          // where the back arrow reappears and Back pops to Setup as usual.
          canPop: isComplete,
          // The CURRENT API. `onPopInvoked` is deprecated and `PopScope`
          // asserts when both are supplied.
          onPopInvokedWithResult: (bool didPop, void result) {
            // The pop has already happened (canPop was true) — acting on it
            // would open the dialog after the fact.
            if (didPop) return;
            unawaited(_requestStop());
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                isComplete
                    ? 'Session complete'
                    : 'Question ${_state.questionNumber} of '
                          '${widget.config.questionCount}',
                style: theme.textTheme.headlineSmall,
                // A truncated "Question 100 of 100" at max text scale is
                // acceptable; a RenderFlex overflow is not.
                overflow: TextOverflow.ellipsis,
              ),
              // The user cannot navigate away from an active session (D-29), and
              // there is deliberately no History icon here — it lives on Setup.
              // The back arrow REAPPEARS in the completion state, in lock-step
              // with `PopScope.canPop` above: the session is over, so leaving it
              // needs no confirmation and the affordance should say so.
              automaticallyImplyLeading: isComplete,
              // CTRL-01: Pause/Resume is present in EVERY session phase, and
              // merely disabled where there is no clock to freeze — never hidden,
              // so it can never appear to have vanished mid-session. The one
              // exception is `complete`, where the session is genuinely over and
              // the whole action goes away.
              actions: isComplete
                  ? null
                  : <Widget>[
                      IconButton(
                        key: const Key('practice-pause-action'),
                        icon: Icon(
                          isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        tooltip: isPaused ? 'Resume session' : 'Pause session',
                        // Coral when live, warm brown at 38% when inert — a
                        // disabled coral icon would still read as an affordance.
                        style: IconButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          disabledForegroundColor: theme.colorScheme.onSurface
                              .withValues(alpha: 0.38),
                        ),
                        onPressed: _state.canPause
                            ? () => unawaited(
                                isPaused ? _state.resume() : _state.pause(),
                              )
                            : null,
                      ),
                      // CTRL-02: Stop is the SECOND action, and — unlike Pause —
                      // it is ENABLED in every session phase, `arming` and
                      // `saving` included. The two actions never share an
                      // availability rule: Pause needs a clock to freeze, Stop
                      // needs only a session to end.
                      //
                      // Coral, not error red. Ending a session early destroys
                      // nothing — every answer is already durably saved
                      // (PERSIST-01) — so the destructive palette would overstate
                      // it. Error red appears only on the dialog's destructive
                      // label.
                      IconButton(
                        key: const Key('practice-stop-action'),
                        icon: const Icon(Icons.stop_rounded),
                        tooltip: 'Stop session',
                        style: IconButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        onPressed: () => unawaited(_requestStop()),
                      ),
                    ],
            ),
            body: SafeArea(
              // The banner is docked above the question, never instead of it:
              // UI-SPEC requires the question screen stay visible so the user is
              // not left staring at a blank, dead-end screen.
              child: Column(
                children: [
                  if (hasError)
                    _ErrorBanner(
                      message: _state.errorMessage ?? kRecordingErrorMessage,
                      onRetry: _state.retry,
                    ),
                  // Same slot, same construction as the error banner. The two are
                  // mutually exclusive by construction: a pause that could not be
                  // confirmed lands in `error`, never in `paused`.
                  if (isPaused) _PausedBanner(reason: _state.pausedReason),
                  Expanded(
                    // Centred normally, scrollable rather than clipped once the
                    // OS text-scale setting grows the content past the viewport
                    // (UI-01).
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24, // lg — screen edge padding
                            vertical: 32, // xl
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - 64,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // The anchor slot. Every phase but `reading`
                                // shows the mascot; `reading` swaps in the `t`
                                // ring, which occupies the SAME 144px box — the
                                // swap is why neither countdown can be mistaken
                                // for the other, and the matching box is why it
                                // costs no layout shift (D-22).
                                if (displayPhase == PracticePhase.reading)
                                  CountdownRing(
                                    remainingSeconds: _state.countdownSeconds,
                                    totalSeconds: widget.config.thinkingSeconds,
                                  )
                                else
                                  Mascot(
                                    // The pulse ring means "the microphone is
                                    // LIVE", so it is off in every paused state —
                                    // leaving it running while frozen would be the
                                    // single worst honesty failure in this phase.
                                    isRecording:
                                        !isPaused &&
                                        _state.phase == PracticePhase.recording,
                                    isError: hasError,
                                  ),
                                const SizedBox(height: 32), // xl
                                // The focus slot. Its three occupants swap by
                                // phase and the question card is HIDDEN for two
                                // of them (D-22): during the 3·2·1 there is
                                // nothing to read yet, and at the end there is
                                // nothing left to answer.
                                if (displayPhase == PracticePhase.getReady)
                                  _CountdownGlyph(
                                    value: _state.countdownSeconds,
                                  )
                                else if (isComplete)
                                  _CompletionHeadline(
                                    answeredCount: _state.answeredCount,
                                  )
                                else
                                  _QuestionCard(
                                    question: _state.currentQuestion,
                                  ),
                                const SizedBox(height: 48), // 2xl
                                // Every phase renders exactly one control here —
                                // the mapping is total and exhaustively tested,
                                // so no phase can leave this screen controlless.
                                PhaseControl(
                                  phase: _state.phase,
                                  onStop: () =>
                                      unawaited(_state.stopRecording()),
                                  onStart: () =>
                                      unawaited(_state.startNewQuestion()),
                                  onResume: () => unawaited(_state.resume()),
                                  recordingSecondsRemaining:
                                      _state.recordingSecondsRemaining,
                                  // "Get ready…" only for the session's own
                                  // 3·2·1; every later one counts INTO a
                                  // question, so it says "Next question…". `k`
                                  // has already moved by then (LOOP-07).
                                  isFirstQuestion: _state.questionNumber == 1,
                                  // Null until the session has a committed
                                  // `sessions` row (D-26), which renders the
                                  // button DISABLED rather than opening an empty
                                  // detail screen. Task 2 is what starts
                                  // populating `sessionId`.
                                  onViewSession: _state.sessionId == null
                                      ? null
                                      : () => unawaited(_openThisSession()),
                                  onBackToSetup: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The single early-exit confirmation (CTRL-03 / UI-SPEC E11).
///
/// Pops `true` for the one destructive action and `false` for the safe one; a
/// barrier tap or a back gesture closes it with `null`, which
/// [_PracticeScreenState._requestStop] treats identically to the safe one.
///
/// `scrollable: true` is the E11/overflow rule: at the largest OS text-scale
/// setting the body must scroll INSIDE the dialog rather than push the two
/// actions off-screen.
class _StopConfirmationDialog extends StatelessWidget {
  const _StopConfirmationDialog({required this.answeredCount});

  /// COMMITTED answers, never questions attempted — the dialog may only
  /// promise what the database actually holds.
  final int answeredCount;

  /// The three bodies, and nothing else about this dialog, vary with `N`.
  ///
  /// **The `N = 0` string is PLANNER-RESOLVED copy.** The UI-SPEC Copywriting
  /// Contract locks bodies for `N = 1` and `N >= 2` only, yet Stop is enabled
  /// from the first frame of a session — before any answer is committed. The
  /// gap is recorded as ⚠ unresolved at UI-SPEC E11/empty, and this is its
  /// resolution, adopted verbatim from that entry's own proposal. It is written
  /// down here so nobody re-invents user-facing copy; do not reword it without
  /// updating `02-UI-SPEC.md`.
  String get _body {
    if (answeredCount == 0) return 'Nothing has been recorded yet.';
    if (answeredCount == 1) {
      return "Your 1 answer is already saved — you just won't finish the rest.";
    }
    return 'Your $answeredCount answers are already saved — '
        "you just won't finish the rest.";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('practice-stop-dialog'),
      // Ivory, the app's dominant surface — the peach `colorScheme.surface` is
      // the CARD colour, and a peach dialog over a peach question card would
      // read as one continuous plane.
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      scrollable: true,
      title: Text('End this session?', style: theme.textTheme.headlineSmall),
      content: Text(_body, style: theme.textTheme.bodyLarge),
      actions: [
        // The destructive action, deliberately the RECESSIVE one: a text
        // button, in warm red, left of the dominant safe choice.
        TextButton(
          key: const Key('practice-stop-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            // Comfortably above the 44px touch-target floor even as a text
            // button.
            minimumSize: const Size(64, 48),
          ),
          child: Text(
            'End session',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        // The safe path is the visually dominant one, and the one a stray tap
        // is most likely to land on.
        FilledButton(
          key: const Key('practice-stop-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          child: Text('Keep going', style: theme.textTheme.labelLarge),
        ),
      ],
    );
  }
}

/// The 3·2·1 numeral, in a FIXED-height box so the focus slot does not jump as
/// the glyph changes width (3 → 2 → 1).
class _CountdownGlyph extends StatelessWidget {
  const _CountdownGlyph({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      key: const Key('practice-countdown-glyph'),
      height: 160,
      child: Center(
        // Scales down rather than overflowing at the largest OS text-scale
        // setting — the same containment the 96px STOP label uses.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$value',
            style: theme.textTheme.displayLarge!.copyWith(
              fontSize: kCountdownGlyphSize,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The completion state's focus slot (D-27).
///
/// Deliberately never scores, ranks or grades the answers — this app is a drill
/// tool, and the headline below plus a count is the whole of what it may say.
///
/// The count is [answeredCount] — the COMMITTED row count, never the number of
/// questions attempted. A session stopped early reaches this same state; only
/// the number differs, and the copy never frames stopping early as a failure.
class _CompletionHeadline extends StatelessWidget {
  const _CompletionHeadline({required this.answeredCount});

  final int answeredCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('practice-complete'),
      children: [
        Text(
          'Nice work!',
          textAlign: TextAlign.center,
          style: theme.textTheme.displayLarge,
        ),
        const SizedBox(height: 8), // sm
        Text(
          answeredCount == 1
              ? '1 answer recorded.'
              : '$answeredCount answers recorded.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

/// The paused banner (UI-SPEC "paused" state), docked in the same slot and
/// built the same way as [_ErrorBanner].
///
/// **This widget is a claim about the microphone, and it must never overstate
/// one.** It is reachable only from `PracticePhase.paused`, and
/// `PracticeState.pause()` publishes that phase only once the recorder has
/// CONFIRMED it actually stopped. A pause that could not be confirmed lands in
/// the error phase instead — so this copy can never appear over a live
/// microphone.
/// Two variants, selected by [reason]:
///   - user-initiated (D-24): `Paused — nothing is being recorded.`
///   - interrupted (D-31): additionally CLAIMS the answer was saved, which is
///     only ever rendered on the path that finalized and committed it before
///     parking. That claim is why the two variants are one widget with one
///     input rather than two call sites that could each pick the wrong string.
class _PausedBanner extends StatelessWidget {
  const _PausedBanner({required this.reason});

  final PausedReason? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String message = reason == PausedReason.interrupted
        ? 'Paused — your answer was saved when the app was interrupted.'
        : 'Paused — nothing is being recorded.';

    return Container(
      key: const Key('practice-paused-banner'),
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(16), // md
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.pause_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8), // sm
          // Expanded (not a fixed width) so the copy wraps instead of
          // overflowing at the largest OS text-scale setting.
          Expanded(child: Text(message, style: theme.textTheme.labelLarge)),
        ],
      ),
    );
  }
}

/// The failure banner (UI-SPEC "error" state).
///
/// The warm-red error colour is applied to the icon, the message and the Retry
/// label only — never as a full-bleed red fill, which the palette reserves it
/// from. [message] is always the fixed UI-SPEC copy handed down by
/// [PracticeState]; this widget has no access to, and never renders, exception
/// detail (T-03-02).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color error = theme.colorScheme.error;

    return Container(
      key: const Key('practice-error-banner'),
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(16), // md
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: error),
              const SizedBox(width: 8), // sm
              // Expanded (not a fixed width) so the copy wraps instead of
              // overflowing at the largest OS text-scale setting.
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyLarge?.copyWith(color: error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8), // sm
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: error,
                // Keeps the affordance comfortably above the 44px touch-target
                // floor even though it is a text button.
                minimumSize: const Size(64, 48),
              ),
              child: Text(
                'Retry',
                style: theme.textTheme.labelLarge?.copyWith(color: error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prompt, on the peach secondary surface with generously rounded corners.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24), // lg
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        question,
        textAlign: TextAlign.center,
        style: theme.textTheme.displayLarge,
      ),
    );
  }
}
