---
phase: 01-record-save-replay-a-single-answer-crash-safe
plan: 04
subsystem: ui
tags: [flutter, record, audioplayers, state-machine, changenotifier, flutter_test, fake-clock]

requires:
  - phase: 01-record-save-replay-a-single-answer-crash-safe
    provides: "PracticeState, PracticeScreen, RecordingService, AudioPlayerService, DatabaseHelper, Mascot and the D-01..D-15 decision set (plans 01-01..01-03)"
provides:
  - "PracticePhase.arming — the honest name for the window in which the recorder is still starting"
  - "lib/widgets/phase_control.dart — a total, exhaustively-tested PracticePhase to on-screen-control mapping"
  - "A fully guarded PracticeState.stopRecording(): no await in the stop/save/replay/re-arm sequence can strand the loop"
  - "PracticeState._onAutoStop() — the 60s deadline still finalizes the recorder when the loop has left the recording phase"
  - "PracticeState._startInFlight — a re-entrancy guard so two overlapping startNewQuestion() calls arm exactly one recorder"
  - "RecorderBackend + AudioPlaybackBackend seams — the real services are now unit-testable without a platform channel"
  - "RecordingService._recording / _startInFlight / _stopRequestedDuringStart — a stop signal is never lost and a start is never silently ignored"
  - "kReplayCompletionTimeout — a hard ceiling on the auto-replay wait"
  - "First-ever tests for RecordingService and AudioPlayerService"
affects: [phase-2-timed-multi-question-loop, phase-2-setup-screen, phase-3-firestore-question-bank]

actuals:
  tokens: 16250
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "Backend seam pattern: an abstract Backend class + a private production implementation + an optional constructor parameter resolved through a `late final` field, so injected fakes never construct a platform channel"
    - "Total phase to control mapping proven by an exhaustive test over an enum's `values`"
    - "Timer tests on flutter_test's built-in fake clock (testWidgets + tester.pump) instead of a fake_async dependency"

key-files:
  created:
    - lib/widgets/phase_control.dart
    - test/widgets/phase_control_test.dart
    - test/services/recording_service_test.dart
    - test/services/audio_player_service_test.dart
  modified:
    - lib/state/practice_state.dart
    - lib/screens/practice_screen.dart
    - lib/services/recording_service.dart
    - lib/services/audio_player_service.dart
    - test/state/practice_state_test.dart

key-decisions:
  - "The idle control is labelled 'Try again', never 'START' — the UI-SPEC Copywriting Contract states no Start button exists in this phase (D-01), so the recovery affordance is worded rather than invented"
  - "PracticeState's initial phase is arming, not idle, so no recovery control flashes during the cold-launch orphan sweep"
  - "RecordingService.start() throws a StateError while a recording is active or arming rather than silently no-opping, so a caller can never publish a recording phase against a path the recorder was never given"
  - "_startInFlight is assigned the whole _arm() future (permission check AND backend start) so the arming window has no uncovered moment"
  - "A stop landing mid-arming causes the resolving start() to finalize and DISCARD the recording rather than arm a deadline — the microphone is never live behind an error banner"
  - "AudioPlayerService keeps BOTH the subscribe-before-play ordering and the kReplayCompletionTimeout ceiling; each is independently sufficient and both are kept deliberately"
  - "REQUIREMENTS.md left untouched — LOOP-03..06 stay 'Gaps Found' until the phase verifier re-runs (a prior premature Complete was reverted in cd5cdae's ancestry)"

patterns-established:
  - "Backend seam: abstract RecorderBackend / AudioPlaybackBackend + private production impl + optional constructor injection resolved lazily"
  - "Exhaustive enum-coverage widget test: assert the key map is total over PracticePhase.values, then pump every member and assert findsOneWidget"
  - "Guarded-await discipline in the practice loop: every await in stopRecording() sits in a try/catch whose failure lands in a recoverable phase"
  - "User-facing copy stays the single locked UI-SPEC string; diagnosis goes to debugPrint + FlutterError.reportError only"

requirements-completed: [LOOP-03, LOOP-04, LOOP-05, LOOP-06]

coverage:
  - id: D1
    description: "Every PracticePhase renders exactly one keyed control — no phase leaves the practice screen with nothing on it"
    requirement: LOOP-05
    verification:
      - kind: unit
        ref: "test/widgets/phase_control_test.dart#every PracticePhase renders exactly one keyed control"
        status: pass
      - kind: unit
        ref: "test/widgets/phase_control_test.dart#kPhaseControlKeys is total over PracticePhase.values"
        status: pass
    human_judgment: false
  - id: D2
    description: "The idle control is labelled 'Try again' and no phase renders a START control (UI-SPEC Copywriting Contract, D-01)"
    requirement: LOOP-05
    verification:
      - kind: unit
        ref: "test/widgets/phase_control_test.dart#the idle control is labelled \"Try again\""
        status: pass
      - kind: unit
        ref: "test/widgets/phase_control_test.dart#no phase renders a START control"
        status: pass
    human_judgment: false
  - id: D3
    description: "The screen no longer claims to be recording while the recorder is still arming — PracticePhase.arming holds until start() resolves"
    requirement: LOOP-03
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#the phase stays arming until the recorder has actually started"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#a freshly constructed PracticeState is arming, not idle"
        status: pass
    human_judgment: false
  - id: D4
    description: "No unguarded await in stopRecording(): a null stop, a throwing stop, a failed save and a failed replay all land the loop in a recoverable phase"
    requirement: LOOP-06
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#every injected failure leaves the loop in a recoverable phase"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#a losing stop signal is surfaced as a recoverable failure and writes nothing"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#a recorder that throws on stop lands in error, never in saving"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#a replay failure never blocks the loop — the answer is already saved"
        status: pass
    human_judgment: false
  - id: D5
    description: "The 60s auto-stop deadline fires exactly once at kMaxRecordingDuration, not before, and survives a losing stop"
    requirement: LOOP-04
    verification:
      - kind: unit
        ref: "test/services/recording_service_test.dart#the auto-stop deadline fires exactly once, at kMaxRecordingDuration and not before"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#the auto-stop deadline still stops the recorder when the loop has already left the recording phase"
        status: pass
    human_judgment: false
  - id: D6
    description: "A stop landing in EITHER half of the arming window (permission check or backend start) is honoured: the recording is finalized and discarded, no deadline is armed, and the microphone is never live behind an error banner"
    requirement: LOOP-04
    verification:
      - kind: unit
        ref: "test/services/recording_service_test.dart#a stop during the BACKEND-START window is honoured: the recording is finalized and discarded, never armed"
        status: pass
      - kind: unit
        ref: "test/services/recording_service_test.dart#a stop during the PERMISSION window is honoured too — the half of the arming window where the backend has not been touched at all"
        status: pass
    human_judgment: false
  - id: D7
    description: "No committed question_answers row can name a file the recorder was not told to write — overlapping starts collapse, a start on a live recording throws, and file names carry entropy"
    requirement: LOOP-03
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#two overlapping startNewQuestion calls produce exactly one recorder start, and the saved path is the one the recorder was given"
        status: pass
      - kind: unit
        ref: "test/services/recording_service_test.dart#start() throws rather than silently no-opping while a recording is live, so no caller can believe it armed a path the recorder never got"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#two recordings started in the same millisecond do not collide"
        status: pass
    human_judgment: false
  - id: D8
    description: "The auto-replay wait is bounded by kReplayCompletionTimeout and subscribes before playback starts, so a missed or absent completion event cannot freeze the loop"
    requirement: LOOP-06
    verification:
      - kind: unit
        ref: "test/services/audio_player_service_test.dart#a backend that never emits completion still resolves within kReplayCompletionTimeout"
        status: pass
      - kind: unit
        ref: "test/services/audio_player_service_test.dart#a completion emitted during play() still resolves the wait"
        status: pass
    human_judgment: false
  - id: D9
    description: "SC-2 / SC-1 on-device behaviour: speaking the instant the question appears and tapping STOP immediately yields a replay containing the first words spoken; a 60s recording auto-stops, saves and replays audibly; no blank or frozen screen while the first-launch microphone-permission dialog is pending"
    requirement: LOOP-06
    verification: []
    human_judgment: true
    rationale: "Real microphone capture, audible playback and the true length of the arming window at device latency cannot be observed from the test host. Carried forward as backstop truths from the plan."

duration: 34min
completed: 2026-08-08
status: complete
---

# Phase 01 Plan 04: Every Practice Phase Has A Way Forward Summary

**A `PracticePhase.arming` state that stops the UI lying about the microphone, a total phase→control mapping proven exhaustively over `PracticePhase.values`, a `RecordingService` whose 60s deadline survives a losing stop, a bounded subscribe-first replay wait, and the first-ever tests for both audio services — 32 tests to 56, `flutter analyze` clean.**

## Performance

- **Duration:** ~34 min
- **Started:** 2026-08-08 (worktree `worktree-agent-a66dcb633b5acb225`, base `cd5cdae`)
- **Completed:** 2026-08-08
- **Tasks:** 3 (each TDD: RED commit then GREEN commit)
- **Files modified:** 9 (4 created, 5 modified)

## Accomplishments

- **Gap 1 closed — the loop has no unrecoverable dead ends.** `PhaseControl` renders exactly one keyed control for every member of `PracticePhase`, and an exhaustive widget test fails the moment a future phase is added without one. The three phases that previously rendered nothing (`idle`, `saving`, `replaying`) now render a `Try again` button and two transient status labels; `error` remains served by the existing `_ErrorBanner`.
- **Gap 1 closed — the screen stops lying about the microphone.** A new `PracticePhase.arming` holds while `recordingService.start()` is in flight, so the listening mascot, the pulse ring and the STOP button no longer appear before the recorder is armed. D-01 is untouched: recording still begins with no user action; only the *claim* waits. `arming` is also the constructor's initial phase, so no recovery control flashes during the cold-launch orphan sweep.
- **Gap 3 closed — no unguarded failure path can freeze the loop.** Every await in `stopRecording()` — the recorder stop, the DB transaction, `toAbsolutePath()` and the replay — now sits in a guarded path. A null finalized path routes to `_fail()` (banner + Retry) instead of the old controlless `PracticePhase.idle`, and writes zero rows.
- **The 60s deadline can no longer be permanently disarmed.** `RecordingService`'s sticky `_stopping` flag is replaced by a per-recording `_recording` lifecycle flag, and `PracticeState._onAutoStop()` finalizes the recorder even when the loop has already left the recording phase.
- **The arming window has no uncovered moment.** `_startInFlight` is assigned the whole `_arm()` future — permission check *and* backend start together — so a stop landing in either half is recorded in `_stopRequestedDuringStart`, and the resolving `start()` finalizes and **discards** the recording instead of arming a deadline. The up-to-60s ghost capture behind an error banner is structurally impossible.
- **`RecordingService` and `AudioPlayerService` have tests for the first time.** Two new `RecorderBackend` / `AudioPlaybackBackend` seams let the *real* services run against fakes with no platform channel, on `flutter_test`'s built-in fake clock — no `fake_async` dependency added.
- **The auto-replay wait is bounded and race-free.** `kReplayCompletionTimeout` (60s + 5s) caps the wait, and the completion subscription is captured *before* playback starts because `onPlayerComplete` is a non-replaying broadcast stream.
- **Test count: 32 → 56.** `flutter analyze`: no issues.

## Task Commits

Each task was committed atomically, RED then GREEN (all three tasks are `tdd="true"`):

1. **Task 1: Every practice phase has a way forward**
   - `a4b14cb` (test) — failing tests for the total phase→control mapping, the arming phase, guarded failures, the auto-stop backstop and the re-entrancy guard
   - `1f2fb77` (feat) — `PracticePhase.arming`, `lib/widgets/phase_control.dart`, `_startInFlight`, `_onAutoStop()`, `_disposed`/`_notify()`, entropy-suffixed file names, guarded `stopRecording()`, `PhaseControl` wired into `PracticeScreen`, `_StopButton` removed, recorder stopped in `dispose()`
2. **Task 2: RecordingService gets a testable seam, a per-recording lifecycle guard, and its first tests**
   - `83db396` (test) — failing first tests for the real `RecordingService`
   - `3a5677a` (feat) — `RecorderBackend` + `_RecordPackageBackend`, `_recording` replacing `_stopping`, `_arm()`, `_stopRequestedDuringStart`, `StateError` on a double start
3. **Task 3: The auto-replay wait is bounded and race-free**
   - `541f12e` (test) — failing tests for the bounded, subscribe-first wait
   - `335bbc7` (feat) — `AudioPlaybackBackend` + `_AudioPlayersBackend`, `kReplayCompletionTimeout`, subscribe-before-play + timeout

No REFACTOR commits were needed — each GREEN implementation was written against the acceptance criteria and needed no cleanup pass.

## Files Created/Modified

**Created**
- `lib/widgets/phase_control.dart` — `PhaseControl` + `kPhaseControlKeys`: the total phase→control mapping. Its class doc records why `idle` says "Try again" rather than "START", why `error` is deliberately empty, and — importantly — that `saving`/`replaying` may only be status labels for as long as every await in `stopRecording()` stays guarded.
- `test/widgets/phase_control_test.dart` — totality, exhaustive per-phase render, the "Try again" label, "no phase renders START", and the tap wiring.
- `test/services/recording_service_test.dart` — first coverage of the real `RecordingService`: the deadline (fires once, not early), concurrent stops, both halves of the arming window, the `StateError` on a live double start, denied permission, dispose.
- `test/services/audio_player_service_test.dart` — subscribe-before-play, the never-emitted-completion ceiling, the fire-and-forget path.

**Modified**
- `lib/state/practice_state.dart` — `PracticePhase.arming`; initial phase `arming`; `_disposed`/`_notify()`; `startNewQuestion()` split into a public re-entrancy-guarded wrapper and a private `_startNewQuestion()`; entropy suffix on recording file names; `_onAutoStop()`; a `stopRecording()` in which every await is guarded and a null/throwing stop lands in `error`; save failures logged via `debugPrint` + `FlutterError.reportError` with no change to user-facing copy.
- `lib/screens/practice_screen.dart` — renders `PhaseControl`; `_StopButton` deleted (moved verbatim into `PhaseControl`); `dispose()` now stops the in-flight recording before tearing the recorder down and no longer drops futures.
- `lib/services/recording_service.dart` — `RecorderBackend` seam, `_recording`/`_startInFlight`/`_stopRequestedDuringStart`, `_arm()`, throwing `start()`, rewritten class contract doc.
- `lib/services/audio_player_service.dart` — `AudioPlaybackBackend` seam, `kReplayCompletionTimeout`, subscribe-first bounded wait.
- `test/state/practice_state_test.dart` — the "losing stop leaves the state at `idle`" assertion (which locked the dead end in place) is replaced by an `error` assertion; new fakes gates/flags (`startGate`, `throwOnStop`, `throwOnPlay`, `lastAutoStop`) and eight new tests.

## Decisions Made

- **`idle` is labelled "Try again", not "START".** The UI-SPEC Copywriting Contract states no Start button exists in this phase because recording begins automatically (D-01). The verifier's gap bullet asks for "a Start/Try-again control"; the recovery wording satisfies it without contradicting a locked contract. Recorded in the `PhaseControl` class doc.
- **The constructor's initial phase is `arming`, not `idle`.** `PracticeScreen._bootstrap()` awaits the orphan sweep before the first `startNewQuestion()`; leaving the initial phase at `idle` would flash the recovery button on every cold launch before anything had gone wrong.
- **`RecordingService.start()` throws rather than silently returning.** A silent return would let `PracticeState` publish `PracticePhase.recording` against a path the recorder was never given and commit a row naming a nonexistent file — the durable-stale-path failure this phase's crash-safety contract excludes (T-04-03).
- **`_startInFlight` is assigned the whole `_arm()` future.** Assigning `_backend.start(...)` after already awaiting `hasPermission()` would leave the permission half of the arming window uncovered. `test/services/recording_service_test.dart`'s permission-window test carries an inline comment saying exactly this, so a later refactor cannot silently reopen the gap.
- **Both replay protections are kept.** The subscribe-before-play ordering and the `kReplayCompletionTimeout` ceiling are each independently sufficient; keeping both is documented in the `play()` doc.
- **REQUIREMENTS.md was deliberately NOT updated.** LOOP-03..06 remain `Gaps Found`. A prior commit on this branch's ancestry (`1d39a76`) explicitly reverted a premature `Complete` marking after gaps were found; re-marking them from inside a worktree, before the phase verifier re-runs, would repeat that mistake. The plan's `requirements` frontmatter is carried in this SUMMARY's `requirements-completed` so the orchestrator/verifier can act on it centrally.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Stream.first` could surface an unhandled async error when the player is disposed mid-replay**
- **Found during:** Task 3 (bounded replay wait)
- **Issue:** The plan specifies `final Future<void> completed = _backend.onComplete.first;`. `Stream.first` completes with a `StateError` ("No element") if the stream closes without ever emitting. After the `kReplayCompletionTimeout` has already let the loop move on, that future is still pending; disposing the player then closes the stream and the error has no handler — an unhandled async error that would fail a `flutter_test` run and, in production, hit `FlutterError.onError` for a condition the timeout has already handled correctly.
- **Fix:** `_backend.onComplete.first.catchError((Object _) {})` — the error is absorbed at the subscription, leaving the timeout as the only thing that decides when the wait ends. The ordering the plan makes load-bearing (subscribe strictly before `_backend.play(...)`) is unchanged, and `grep -n 'onComplete.first'` still shows it on a line preceding `_backend.play(`.
- **Files modified:** `lib/services/audio_player_service.dart`
- **Verification:** `flutter test test/services/audio_player_service_test.dart` exits 0, including the never-emits case whose `service.dispose()` closes the controller after the timeout has resolved.
- **Committed in:** `335bbc7` (Task 3 commit)

**2. [Rule 3 - Blocking] `kReplayCompletionTimeout` cannot be `const`-derived from `kMaxRecordingDuration`**
- **Found during:** Task 3
- **Issue:** The plan requires a public **`const`** `Duration`. `Duration + Duration` is not a const expression in Dart, so `kMaxRecordingDuration + const Duration(seconds: 5)` cannot initialise a `const`, and importing `kMaxRecordingDuration` purely for the doc comment would have been an unused import (`flutter analyze` failure).
- **Fix:** Declared `const Duration kReplayCompletionTimeout = Duration(seconds: 60 + 5);` with an inline `// kMaxRecordingDuration + 5s` marker and a doc comment naming the derivation, and dropped the import. The plan's literal `Duration(seconds: 65)` value is preserved exactly.
- **Files modified:** `lib/services/audio_player_service.dart`
- **Verification:** `flutter analyze` reports no issues; `grep -c 'kReplayCompletionTimeout'` returns 3 (≥2 required).
- **Committed in:** `335bbc7` (Task 3 commit)

**3. [Rule 3 - Blocking] `theme` became an unused local in `PracticeScreen.build`**
- **Found during:** Task 1
- **Issue:** After the `replaying`-only `Text` moved into `PhaseControl`, `final theme = Theme.of(context);` in `PracticeScreen.build` had no remaining reader, which `flutter analyze` flags.
- **Fix:** Removed the local. `_ErrorBanner` and `_QuestionCard` resolve their own theme.
- **Files modified:** `lib/screens/practice_screen.dart`
- **Verification:** `flutter analyze` reports no issues.
- **Committed in:** `1f2fb77` (Task 1 commit)

### Test-observability adjustments (not behaviour changes)

- The plan's Task 2 test (c)/(c2) ask to assert "the service is not recording". Rather than widen `RecordingService`'s public API with an `isRecording` getter that production has no use for, the tests assert the observable equivalent: a further `stop()` returns `null` and the backend's stop count stays at 1. No new public symbol was added.
- The plan's Task 2 test (d) is written as two tests (the post-arming-window re-arm, and the live-double-start `StateError`) rather than one, matching the two acceptance-criteria bullets one-to-one.

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking) + 2 test-observability adjustments
**Impact on plan:** No scope creep. Every plan-pinned structural property is intact — `grep -c '_arm('` = 2, `_startInFlight` is assigned from `_arm(` (line 142) and never from `_backend.start(`, `_stopRequestedDuringStart` = 7, `StateError` = 3, `_stopping` = 0, `abstract class RecorderBackend` = 1, `PracticePhase.arming` = 3 in both `practice_state.dart` and `phase_control.dart`, `_onAutoStop` = 2, `PhaseControl(` = 1 in `practice_screen.dart`, `class _StopButton` = 0.

## Issues Encountered

- **`FlutterError.reportError` on the save-failure path prints an exception dump into `flutter test` output.** This is the intended developer-facing diagnostic sink (WR-07's diagnosable half). It does **not** fail the test, because `test/state/practice_state_test.dart` uses plain `test()` and never initialises the widget binding. **Caution for future work:** adding a `testWidgets` case to that file would initialise the binding, at which point `FlutterError.onError` fails the current test and the "a save failure shows the same copy" test would start failing. Keep that file `test()`-only, or wrap the reporting behind an explicit error-handler override.
- No blockers, no checkpoints, no architectural (Rule 4) decisions were required.

## Known Stubs

None. Every affordance introduced is wired to real state; no placeholder copy, empty data source or `TODO` was introduced.

## Threat Flags

None. No new network endpoint, auth path, file-access pattern or schema change was introduced. The two new abstract classes (`RecorderBackend`, `AudioPlaybackBackend`) are in-process seams over existing plugin calls, and the mitigations for T-04-01 through T-04-04 are implemented and unit-proven as planned.

## User Setup Required

None — no external service configuration, no new package, no new Android/iOS permission.

## Next Phase Readiness

**Ready.** Phase 2's timed multi-question loop can switch exhaustively on `PracticePhase` knowing that `kPhaseControlKeys` totality is mechanically enforced — adding a phase without a control fails `test/widgets/phase_control_test.dart` immediately. Both audio services now have injectable backends, so Phase 2 can unit-test timing behaviour without a device.

**Outstanding for the phase verifier / on-device UAT (carried forward as `backstop` truths, not automated gates):**
- **SC-1/LOOP-03** — speak the instant the question appears, tap STOP immediately, confirm the replay contains the very first words spoken, and measure how much leading audio the arming window still costs at real device latency.
- **SC-2/LOOP-06** — finishing a recording plays the answer back *audibly* with no tap, shows "Playing your answer…" during playback, then presents a new question with recording re-armed; and a recording left alone auto-stops at 60s, saves and replays.
- **UI-SPEC/loading** — on first launch, confirm the OS microphone-permission dialog is the only loading affordance and no blank or frozen screen appears while the permission callback is pending.

**Carried into Phase 2 unchanged** (deliberately not closed here, per the plan's review disposition): WR-07 (one error string covers both mic-denied and save-failure — splitting it needs a UI-SPEC amendment), WR-08 (app-lifecycle handling: backgrounding, phone call mid-recording), WR-10 (`pruneOrphanRecordings`'s caller contract is prose, not mechanical), IN-03, IN-04, IN-05.

---
*Phase: 01-record-save-replay-a-single-answer-crash-safe*
*Completed: 2026-08-08*
