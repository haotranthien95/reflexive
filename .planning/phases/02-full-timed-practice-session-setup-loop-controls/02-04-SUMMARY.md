---
phase: 02-full-timed-practice-session-setup-loop-controls
plan: 04
subsystem: practice-loop
tags: [pause, resume, ctrl-01, ctrl-04, honesty-contract, clocks, app-bar]
status: complete

requires:
  - 02-02 (the closed loop: getReady → reading → arming → recording → saving → replaying → next)
  - 02-01 (PausableCountdown, SessionConfig, the RecorderBackend/AudioPlaybackBackend seams)
provides:
  - CONFIRMED pause/resume of the microphone — RecordingService.pause()/resume() return whether the mic ACTUALLY changed state
  - RecorderBackend.onPausedChanged, the OS-initiated-pause stream plan 02-05 binds to
  - PracticePhase.paused plus one PracticeState.pause()/resume() pair that freezes all four clocks
  - replayCompletionTimeoutFor(d) and a freezable, d-derived replay completion bound
  - The session app-bar Pause/Resume action (CTRL-01) and the paused banner
affects:
  - test/screens/setup_screen_test.dart, test/screens/session_detail_screen_test.dart, test/state/practice_state_test.dart (fakes widened for the new seam methods)

tech-stack:
  added: []
  patterns:
    - "A platform call that can no-op silently is never believed on its own — ask the backend to CONFIRM, and publish state only from the confirmation"
    - "Every bound that a user can pause must be a PausableCountdown, never Future.timeout — a timeout cannot be frozen"
    - "`paused` is a PHASE, not an orthogonal bool, so the kPhaseControlKeys totality test covers it like every other phase"
    - "The frozen phase is remembered in one field (`_phaseBeforePause`) and restored verbatim; `displayPhase` is what the anchor/focus slots render, `phase` is what the control slot renders"
    - "A tester.pump() drains the whole microtask queue, so a transient phase must be GATED (a Completer in the fake) to be observable at all"

key-files:
  created: []
  modified:
    - lib/services/recording_service.dart
    - lib/services/audio_player_service.dart
    - lib/state/practice_state.dart
    - lib/widgets/phase_control.dart
    - lib/screens/practice_screen.dart
    - test/services/recording_service_test.dart
    - test/services/audio_player_service_test.dart
    - test/state/practice_session_test.dart
    - test/widgets/phase_control_test.dart
    - test/state/practice_state_test.dart
    - test/screens/setup_screen_test.dart
    - test/screens/session_detail_screen_test.dart

decisions:
  - "An unconfirmed recorder pause routes to the existing _fail() path — the Phase 1 error banner — rather than publishing `paused`. A banner reading 'nothing is being recorded' over a live microphone is the worst outcome available in this phase, so the honest error is strictly better than the convenient lie"
  - "The d-deadline-vs-Pause race resolves as: auto-stop wins, pause request DEFERRED (not dropped) to the next pausable phase. Only the two strictly transient phases (arming, saving) defer; error/idle/complete are resting states where a queued pause would fire against a clock the user never meant to freeze"
  - "The deferred pause is applied at the next COUNTDOWN, not at the replay: the replay begins and ends inside a single await, so a pause applied at its start would have nothing to freeze yet"
  - "AudioPlayerService.resume() is a no-op once the completion event has fired — AudioPlayer.resume() resumes audio that was paused OR STOPPED, so the same-frame race between a Pause tap and the end of a replay would otherwise replay the whole answer"
  - "The paused control carries the frozen `d` readout under its existing key, reconciling the UI-SPEC's control-slot table (RESUME only) with its Pause section ('the frozen numeral/readout stays on screen')"

metrics:
  duration: ~50m
  completed: 2026-08-09
  tasks: 3
  commits: 3

actuals:
  tokens: 53500
  tasks: 3
  commits: 3
---

# Phase 2 Plan 04: Pause Is A True Pause Summary

One `pause()` on `PracticeState` now freezes the microphone, the single live
`PausableCountdown` and any replay-completion wait together — and the paused
state is published only once the recorder has **confirmed** it actually
stopped, because `record`'s pause is a guarded early return that no-ops
silently in the wrong state.

## What Was Built

**Task 1 — both platform seams gain confirmed pause/resume (`053e8ab`).**
`RecorderBackend` grew `pause()`, `resume()`, `isPaused()` and
`onPausedChanged`, all free of `package:record` types so the seam stays
fake-able with a plain `StreamController<bool>`; the production backend maps
the plugin's three-valued state onto that bool, filtering out `stop` (a
stopped recorder is not an un-paused one). `RecordingService.pause()` and
`.resume()` return whether the microphone ACTUALLY changed state: each awaits
the backend call and then awaits `isPaused()`, and freezes the `d` deadline
only on the confirmation. The doc comment carries the mechanism, not just the
rule — including why the deadline must freeze in lock-step (a pause EXCISES
the paused span from the audio file, so a deadline that kept running would cut
the answer short by exactly the paused duration).

`AudioPlaybackBackend` gained `pause()`/`resume()`, and the replay bound moved
off `Future.timeout` — which cannot be frozen — onto a `Completer` resolved by
either the completion subscription or a `PausableCountdown`'s `onElapsed`. The
bound is now derived from the session's `d` via
`replayCompletionTimeoutFor(d)`, with `kReplayCompletionTimeout` surviving as
the default so every Phase 1 caller and test is unchanged. Both of the file's
documented protections survive verbatim: the completion subscription is still
captured BEFORE `play()`, and the wait is still bounded.

**Task 2 — one pause/resume pair, the app-bar action, the paused surface
(`90d4fe5`).** `PracticePhase.paused` is a real phase (so the
`kPhaseControlKeys` totality test covers it), with `_phaseBeforePause` holding
the frozen phase for verbatim restoration and `displayPhase` telling the screen
which phase's anchor and focus slots to keep rendering. `pause()` dispatches on
the live clock — recorder, countdown or player — and routes an unconfirmed
recorder pause to `_fail()`. `PhaseControl` gained the keyed `RESUME` pill;
`PracticeScreen` gained the app-bar `IconButton` (coral when live, warm brown at
38% when inert, hidden only at `complete`) and the paused banner, built in the
same slot and the same way as the Phase 1 error banner. The mascot's pulse ring
is off in every paused state.

**Task 3 — the proofs (`53d7f5d`).** Nine behaviours, all on the fake clock with
explicit one-second pumps. Each clock case asserts the FROZEN VALUE across a
pause many times longer than the clock itself, not merely the phase — a pause
that published `paused` while a clock kept running would satisfy a phase-only
assertion and still be the exact dishonesty this plan exists to prevent.

## Verification

- `flutter analyze` — no issues.
- `flutter test` — **150 tests, all passing** (139 after Task 1, 139 after Task 2).
- Every acceptance grep for all three tasks checked and passing:
  `onPausedChanged` ×4, zero package types inside `abstract class
  RecorderBackend`, `replayCompletionTimeoutFor` ×3, **zero** `.timeout(`,
  `practice-control-paused` ×1, each banner/tooltip literal exactly ×1, zero
  `Color(0x` literals, zero `pumpAndSettle`.

**The honesty rule is proven, not asserted.** Both `FakeRecorderBackend`s carry
a `pauseSilentlyNoOps` switch that makes `pause()` return normally while leaving
`isPaused()` false — reproducing both native guards exactly. Two tests depend on
it: `RecordingService.pause()` returns `false` and leaves the deadline running,
and the loop lands in `error` with the Phase 1 banner and **never** in `paused`.
A fake whose pause always worked could not distinguish "the microphone stopped"
from "the call did not throw", which is the whole of CTRL-04's safety argument.

## Deviations from Plan

### 1. [Rule 3 — Blocking] Six test files needed coordinated fake edits

Widening `RecorderBackend` and `AudioPlaybackBackend` broke every fake
implementing them and both `FakeAudioPlayerService.play` overrides (a Dart
override must accept all of the supertype's named parameters). The plan's
`reversibility rating="costly"` predicted exactly this. Fixed in the Task 1
commit: `test/screens/setup_screen_test.dart`,
`test/screens/session_detail_screen_test.dart`,
`test/state/practice_state_test.dart` and both fakes in
`test/state/practice_session_test.dart`.

### 2. [Rule 1 — Bug] `stop()`/`dispose()` had to RESOLVE the outstanding wait

Replacing `Future.timeout` with a `Completer` introduced a way to strand a
caller: the old `onComplete.first.catchError(...)` resolved when a disposed
player closed the stream, whereas simply tearing down the new subscription
would have left an awaiting `stopRecording()` parked at "Playing your answer…"
forever. `stop()`, `dispose()` and a superseding `play()` now all resolve the
wait rather than dropping it.

### 3. [Documentation] `await sub.cancel()` hangs the fake clock

The `onPausedChanged` test initially hung the entire suite for ten minutes with
no output. Root cause: **awaiting a broadcast subscription's `cancel()` inside a
`testWidgets` body never returns** — the future it yields is not completed by
anything the fake clock drives. The cancel is now `unawaited` with the reason
recorded inline. This joins the file's existing fake-clock constraints
(sqflite-ffi futures, `tester.runAsync` under a live `Timer.periodic`) as a
third thing that cannot be awaited on the fake clock.

### 4. [Documentation] The same-frame race needed a GATED commit to be observable

A `tester.pump()` drains the fake zone's microtask queue, so against the ungated
in-memory helper the entire save completed inside the same pump that fired the
`d` deadline — the loop was back at the next get-ready before the test could
tap, and the `saving` phase the race is about never existed long enough to
target. A new `GatedDatabaseHelper` parks the commit on a `Completer`, which is
what makes the race a real test rather than a lucky one.

### 5. [Rule 2 — Missing] The paused control carries the frozen `d` readout

The UI-SPEC's layout table gives the paused control slot only the `RESUME`
pill, while its Pause section requires "the frozen numeral/readout stays on
screen at its frozen value". Honouring only the table would have dropped the
readout the moment a mid-answer pause landed. The readout now renders beneath
the pill, inside the paused phase's existing key (so the totality assertion
still sees exactly one keyed control), and only when
`recordingSecondsRemaining` is non-null — which is precisely "paused from
`recording`".

## Known Stubs

None.

The `Stop` action the UI-SPEC's app-bar shows beside Pause is NOT missing work
from this plan: CTRL-02/CTRL-03 (Stop plus its confirmation dialog, and the
D-25 auto-pause behind that dialog) belong to a later plan. This plan's app bar
carries the Pause/Resume action alone, which is CTRL-01 in full.

Likewise the SECOND paused-banner variant — "Paused — your answer was saved
when the app was interrupted." (D-31) — is deliberately absent: it belongs to
plan 02-05's interruption handling, which binds to the `onPausedChanged` stream
this plan publishes.

## Deferred / Flagged

- **`flagged_assumptions` 1 (CTRL-04 edge category `unresolved`)** stands as the
  planner left it. The four clocks and both races are now explicit tests rather
  than assumptions; the category itself is still worth a manual look at UAT.
- **`flagged_assumptions` 2 (auto-stop vs Pause)** is RESOLVED in code and
  covered by a test: the auto-stop wins, the answer commits, the pause request
  is deferred to the next pausable phase. One narrowing worth recording: the
  deferred pause applies at the next *countdown*, not at the replay, because a
  replay begins and ends inside a single await and a pause applied at its start
  would have nothing to freeze.
- **`flagged_assumptions` 3 (`RecordConfig` unchanged)** honoured — not a
  character of `RecordConfig` was touched.
- **Backstop truths** E10/overflow, E10/long-text and E10/error: the first two
  are structurally satisfied (the banner text sits in an `Expanded` and wraps,
  the paused control keeps a fixed 64px pill) but are visual/UAT items at max
  text scale. E10/error is now covered by a real test at the state level; the
  on-DEVICE behaviour of a genuinely failing `record.pause()` remains a UAT
  backstop.

## Self-Check: PASSED

- `lib/services/recording_service.dart` — present, contains `onPausedChanged` (×4).
- `lib/services/audio_player_service.dart` — present, contains `replayCompletionTimeoutFor` (×3), zero `.timeout(`.
- `lib/state/practice_state.dart` — present, contains `PracticePhase.paused`.
- `lib/widgets/phase_control.dart` — present, contains `practice-control-paused`.
- Commits `053e8ab`, `90d4fe5`, `53d7f5d` — all present in `git log`.
- `lib/screens/setup_screen.dart` and `lib/main.dart` — untouched.
- No scratch or probe test files left in the tree (`git status` clean after the final commit).
