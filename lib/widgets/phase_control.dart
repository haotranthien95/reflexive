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
  PracticePhase.arming: Key('practice-control-arming'),
  PracticePhase.recording: Key('practice-control-recording'),
  PracticePhase.saving: Key('practice-control-saving'),
  PracticePhase.replaying: Key('practice-control-replaying'),
  PracticePhase.error: Key('practice-control-error'),
};

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
class PhaseControl extends StatelessWidget {
  const PhaseControl({
    super.key,
    required this.phase,
    required this.onStop,
    required this.onStart,
  });

  final PracticePhase phase;

  /// Ends the current recording (the big STOP target).
  final VoidCallback onStop;

  /// Re-arms the loop after it has come to rest without a recording.
  final VoidCallback onStart;

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
        return SizedBox(
          key: kPhaseControlKeys[PracticePhase.recording],
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

      case PracticePhase.error:
        return SizedBox.shrink(key: kPhaseControlKeys[PracticePhase.error]);
    }
  }
}
