import 'package:flutter/material.dart';

import '../state/practice_state.dart';

/// The one control key each [PracticePhase] renders.
///
/// This map is deliberately the single source of truth for "what is on screen
/// right now", so the exhaustive widget test in
/// `test/widgets/phase_control_test.dart` can prove the mapping is TOTAL: it
/// asserts `kPhaseControlKeys.length == PracticePhase.values.length` and that
/// every phase renders exactly one keyed widget. Adding a phase without adding
/// an entry here fails that test immediately — which is the whole point, since
/// a phase with no control is a screen the user cannot leave.
const Map<PracticePhase, Key> kPhaseControlKeys = <PracticePhase, Key>{
  PracticePhase.idle: Key('practice-control-idle'),
  PracticePhase.getReady: Key('practice-control-get-ready'),
  PracticePhase.reading: Key('practice-control-reading'),
  PracticePhase.arming: Key('practice-control-arming'),
  PracticePhase.recording: Key('practice-control-recording'),
  PracticePhase.saving: Key('practice-control-saving'),
  PracticePhase.replaying: Key('practice-control-replaying'),
  PracticePhase.paused: Key('practice-control-paused'),
  PracticePhase.complete: Key('practice-control-complete'),
  PracticePhase.error: Key('practice-control-error'),
};

/// The `d` remaining-seconds readout (D-21), as `"{M}:{SS} left"`.
///
/// Body-styled warm brown, deliberately NOT coral: a second accent-coloured
/// element beside the STOP circle would create a competing focal point while
/// the user is mid-answer.
String formatRemainingSeconds(int seconds) {
  final int safe = seconds < 0 ? 0 : seconds;
  final String secondsPart = (safe % 60).toString().padLeft(2, '0');
  return '${safe ~/ 60}:$secondsPart left';
}

/// Renders exactly one control for whatever [PracticePhase] the loop is in.
///
/// **Why `idle` says "Try again" and not "START".** The UI-SPEC Copywriting
/// Contract states that no Start button exists in this phase, because recording
/// begins automatically the instant the screen opens (D-01). Introducing one
/// would contradict a locked contract. The verification gap asks for "a
/// Start/Try-again control" on `idle`; the recovery wording satisfies it
/// without inventing the affordance the contract excludes.
///
/// **Why `error` is deliberately empty.** `PracticeScreen`'s `_ErrorBanner`
/// already owns the recoverable affordance (its Retry button) in that phase, so
/// this widget contributes only a keyed `SizedBox.shrink` — present so the map
/// stays total, empty so the screen shows one Retry rather than two.
///
/// **Why `saving` and `replaying` are status labels, not affordances.** Both
/// are strictly transient: every `await` in `PracticeState.stopRecording()` is
/// guarded, so those two phases always exit to `recording`, `arming` or
/// `error`. Neither can become a resting state a user has to escape from. That
/// guarantee is what makes a label sufficient. **If a future change reintroduces
/// an unguarded `await` anywhere in that stop → save → replay → re-arm
/// sequence, these two labels become dead ends again and must be upgraded to
/// real affordances.** Do not mistake a labelled transient state for a solved
/// one.
///
/// **Why `getReady` and `reading` are also status labels — a DIFFERENT
/// argument.** The "every `await` is guarded, so the phase is transient" reason
/// above does not transfer to them: they are timer-driven, not await-driven, and
/// no `await` bounds them at all. Their justification is that each is bounded by
/// a `PausableCountdown` that always fires, AND that the session app bar carries
/// Pause and Stop throughout both phases (CTRL-01/CTRL-02), so neither is a dead
/// end even if a timer were somehow lost. **If a future change removes the
/// app-bar controls from those phases, these captions must be upgraded to real
/// affordances.**
///
/// **Why `complete` carries two real buttons.** It is the one genuinely resting
/// phase in the loop — nothing will move the user off it but a tap — so it is
/// the one phase where a label would be an actual dead end (D-27).
class PhaseControl extends StatelessWidget {
  const PhaseControl({
    super.key,
    required this.phase,
    required this.onStop,
    required this.onStart,
    this.onResume,
    this.recordingSecondsRemaining,
    this.isFirstQuestion = true,
    this.onViewSession,
    this.onBackToSetup,
  });

  final PracticePhase phase;

  /// Ends the current recording (the big STOP target).
  final VoidCallback onStop;

  /// Re-arms the loop after it has come to rest without a recording.
  final VoidCallback onStart;

  /// Un-freezes a paused session (the `RESUME` pill). A null callback renders a
  /// DISABLED pill rather than crashing — the same guard rail the completion
  /// callbacks use.
  final VoidCallback? onResume;

  /// Seconds left on the `d` deadline, rendered beneath STOP (D-21). Null
  /// renders no readout rather than a placeholder.
  final int? recordingSecondsRemaining;

  /// Which of the TWO get-ready captions this 3·2·1 carries.
  ///
  /// The same countdown surface opens the session (LOOP-01) and separates every
  /// pair of questions (LOOP-07), and the Copywriting Contract gives each its
  /// own line — see the two literals at the `getReady` case below. The caption
  /// is the only difference between them: one phase, one key, so the totality
  /// assertion still sees exactly one keyed control here.
  final bool isFirstQuestion;

  /// Completion state: opens this session in History. A null callback renders a
  /// DISABLED button rather than crashing — a caller that forgets one must not
  /// be able to break the guard rail this widget exists to be.
  final VoidCallback? onViewSession;

  /// Completion state: pops back to Setup. Null disables, as above.
  final VoidCallback? onBackToSetup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (phase) {
      case PracticePhase.idle:
        return SizedBox(
          key: kPhaseControlKeys[PracticePhase.idle],
          height: 64, // Touch-target floor from the UI-SPEC spacing exceptions.
          child: FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 32), // xl
            ),
            child: Text('Try again', style: theme.textTheme.labelLarge),
          ),
        );

      case PracticePhase.getReady:
        return Text(
          isFirstQuestion ? 'Get ready…' : 'Next question…',
          key: kPhaseControlKeys[PracticePhase.getReady],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        );

      case PracticePhase.reading:
        return Text(
          'Speak when the timer hits 0',
          key: kPhaseControlKeys[PracticePhase.reading],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        );

      case PracticePhase.arming:
        return Text(
          'Getting ready…',
          key: kPhaseControlKeys[PracticePhase.arming],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        );

      case PracticePhase.recording:
        // The 96px circular Stop target — the single most important tap target
        // on the screen, deliberately far above the 44px minimum (UI-SPEC
        // spacing exception for LOOP-05).
        //
        // The circle and the `d` readout live under ONE key (D-21): the
        // totality test asserts each phase renders exactly one keyed widget, so
        // the readout joins the existing key rather than adding a second.
        return Column(
          key: kPhaseControlKeys[PracticePhase.recording],
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: FilledButton(
                onPressed: onStop,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                // Scales the label down rather than overflowing the fixed-size
                // target at the largest OS text-scale setting.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stop_rounded, size: 28),
                      Text('STOP', style: theme.textTheme.labelLarge),
                    ],
                  ),
                ),
              ),
            ),
            if (recordingSecondsRemaining != null) ...[
              const SizedBox(height: 16), // md
              Text(
                formatRemainingSeconds(recordingSecondsRemaining!),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ],
        );

      case PracticePhase.saving:
        return Text(
          'Saving your answer…',
          key: kPhaseControlKeys[PracticePhase.saving],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        );

      case PracticePhase.replaying:
        // Verbatim UI-SPEC in-flow copy.
        return Text(
          'Playing your answer…',
          key: kPhaseControlKeys[PracticePhase.replaying],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        );

      case PracticePhase.paused:
        // The one control that matters while frozen. A caption would be a dead
        // end here: nothing but this tap moves a paused session forward.
        return SizedBox(
          key: kPhaseControlKeys[PracticePhase.paused],
          height: 64, // Touch-target floor from the UI-SPEC spacing exceptions.
          child: FilledButton.icon(
            onPressed: onResume,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 32), // xl
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('RESUME', style: theme.textTheme.labelLarge),
          ),
        );

      case PracticePhase.complete:
        return Column(
          key: kPhaseControlKeys[PracticePhase.complete],
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 64, // Touch-target floor from the UI-SPEC exceptions.
              child: FilledButton(
                onPressed: onViewSession,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                child: Text(
                  'View this session',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            const SizedBox(height: 8), // sm
            TextButton(
              onPressed: onBackToSetup,
              style: TextButton.styleFrom(
                // Touch-target floor, not part of the 4px content scale.
                minimumSize: const Size(64, 48),
              ),
              child: Text('Back to setup', style: theme.textTheme.labelLarge),
            ),
          ],
        );

      case PracticePhase.error:
        return SizedBox.shrink(key: kPhaseControlKeys[PracticePhase.error]);
    }
  }
}
