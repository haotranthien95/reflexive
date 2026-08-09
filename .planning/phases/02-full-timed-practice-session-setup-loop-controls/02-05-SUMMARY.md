---
phase: 02-full-timed-practice-session-setup-loop-controls
plan: 05
subsystem: practice-loop
tags: [stop, confirmation-dialog, popscope, wakelock, interruption, ctrl-02, ctrl-03, d-29, d-30, d-31]
status: complete

requires:
  - 02-04 (PracticePhase.paused, pause()/resume(), RecorderBackend.onPausedChanged, the paused banner slot)
  - 02-02 (the closed loop and stopRecording()'s finalize → one transaction → commit ordering)
provides:
  - The app-bar Stop action (CTRL-02) and the ONE confirmation dialog (CTRL-03)
  - _requestStop() — the single early-exit path both the Stop action and the intercepted back gesture call
  - PopScope interception released only in the completion state (D-29)
  - ScreenWakeController — the third platform seam, over wakelock_plus (D-30)
  - PracticeState.handleInterruption() — the ONE interruption handler both producers converge on (D-31)
  - PausedReason + the second paused-banner variant
  - PracticeState.completeEarly() and the one _enterComplete() transition
affects:
  - test/state/practice_session_test.dart (six new D-31 cases; now also imports the wake seam's fake)

tech-stack:
  added:
    - "wakelock_plus ^1.7.0"
  patterns:
    - "Confirm-and-act in ONE method, not a bool-returning confirm plus two act-blocks — two act-blocks is how a back gesture and a button drift into two different early exits"
    - "A platform stream that reports a state cannot report WHO caused it: when the app and the OS both produce the same event, the app must remember which it was and consume exactly one"
    - "A dependency's permission claim is verified against the merged RELEASE manifest and its merger blame report, never against the source manifest or a debug build"
    - "Awaiting a broadcast-backed dispose() in tearDown stalls the run forever — the done event is delivered in the fake-async zone nobody pumps once the body ends"

key-files:
  created:
    - lib/services/screen_wake_controller.dart
    - test/services/screen_wake_controller_test.dart
    - test/screens/practice_screen_test.dart
  modified:
    - lib/screens/practice_screen.dart
    - lib/state/practice_state.dart
    - pubspec.yaml
    - pubspec.lock
    - macos/Flutter/GeneratedPluginRegistrant.swift
    - .claude/CLAUDE.md
    - test/state/practice_session_test.dart

decisions:
  - "The plan asked for a `Future<bool> _confirmStop()` called from two entry points; it was implemented instead as ONE `_requestStop()` that confirms AND acts. A bool-returning confirm still leaves each caller to decide what to do with `true`, which is exactly the duplication the critical requirement forbids. One method means the D-26 zero-answer pop and the D-27 completion transition physically cannot diverge between the button and the gesture"
  - "The system back gesture is driven in tests with `tester.binding.handlePopRoute()` rather than `tester.pageBack()`. Mid-session there IS no back arrow (`automaticallyImplyLeading` is false), so pageBack has nothing to tap; handlePopRoute is the actual system signal PopScope intercepts. pageBack is used for the completion state, where the arrow genuinely reappears"
  - "`resume()` now also cancels a DEFERRED pause request. A Stop dialog opened during `arming`/`saving` defers the D-25 auto-pause; dismissing it with the safe action would otherwise leave the request armed and freeze the session at the next countdown, seconds after the user chose to keep going"
  - "An interruption on the FINAL answer completes the session rather than parking it — parking would leave a RESUME pill with nothing to resume into (LOOP-08)"
  - "Resuming from an interrupted-and-committed park runs the LOOP-07 advance (`k` moves, the 3·2·1 arms) instead of restoring a frozen phase. There is no frozen phase: the answer finished. Restoring `recording` would resume a recorder that was already stopped and finalized"
  - "The wakelock is re-acquired on returning to the foreground. D-30's truths name only release conditions, but without a re-acquire one backgrounding would cost the whole rest of the session its screen hold"

metrics:
  duration: ~95m
  completed: 2026-08-09
  tasks: 3
  commits: 3

actuals:
  tokens: 71000
  tasks: 3
  commits: 3
---

# Phase 2 Plan 05: Stop, Back, Wakelock and Interruption Summary

There is now exactly **one** way to end a session early — one method, one
dialog, reached identically from the app-bar Stop and the system back gesture —
and exactly **one** interruption handler, which finalizes and **commits** the
in-flight answer before the session parks paused.

## What Was Built

**Task 1 — the single early-exit path (`94901c6`).** `_requestStop()` pauses the
session (D-25), shows the one `AlertDialog`, treats a `null` result — barrier
tap, or a back gesture closing the dialog — as identical to the safe action, and
on confirm either pops straight to Setup at `N = 0` (D-26, nothing was written
so there is nothing to view) or enters the completion state at `N >= 1` (D-27).
`PopScope<void>` with `canPop`/`onPopInvokedWithResult` routes the back gesture
into that same method; `canPop` and the app bar's back arrow are both released
in the completion state, in lock-step. `PracticeState.completeEarly()` routes
through the same `_enterComplete()` a naturally finished session takes, so early
stopping is one transition rather than two.

Stop sits second in the app bar, coral rather than error red (ending early
destroys nothing — every answer is already durably saved), and is **enabled in
every session phase including `arming` and `saving`**, where Pause is
deliberately disabled. The two actions never share an availability rule: Pause
needs a clock to freeze, Stop needs only a session to end.

**Task 2 — the wakelock and the one interruption handler (`c520d71`).**
`wakelock_plus ^1.7.0` sits behind `ScreenWakeController`, the third seam of the
established shape. `handleInterruption()` is reached by both producers — the
lifecycle hidden transition and `RecorderBackend.onPausedChanged` — sets its
pending flag **before any await**, and when recording reuses `stopRecording()`
verbatim so the finalize → ONE transaction → commit sequence is shared, not
forked. Its tail then parks paused instead of replaying and advancing; the
auto-replay is skipped entirely, because replaying into a screen the user is not
looking at contradicts "resuming is always an explicit tap". `PausedReason`
selects the second banner variant.

**Task 3 — the proofs (`ba2a246`).** 150 → **171** tests. Every D-31 case
asserts the committed **row**, not the phase: a handler that parked paused
without committing would satisfy a phase-only assertion and still lose the
answer this path exists to save.

## Verification

- `flutter analyze` — **no issues**.
- `flutter test` — **171 tests, all passing** (150 at the plan's start).
- Every acceptance grep for all three tasks checked and passing:
  `onPopInvokedWithResult` ×1 and `onPopInvoked:` ×0, `showDialog` ×1,
  `barrierDismissible: true` ×1, each dialog literal exactly ×1, `Stop session`
  ×1, `wakelock_plus: ^1.7` ×1, `uses-permission` ×1 in the source manifest,
  the hidden-transition callback ×1 and the inactive one ×0,
  `handleInterruption` ×2 in the screen (both producers, one handler),
  `AudioInterruptionMode` ×0 in `recording_service.dart` (the default already IS
  the required policy and is not overridden).
- `git diff lib/state/practice_state.dart` confirms **nothing above the
  post-commit disposal check in `stopRecording()` moved** — the interruption
  branch is a pure addition after the bookkeeping lines.

### The release-manifest claim is verified, not asserted

The critical requirement was to prove against the **actual merged release
manifest**, because this project already learned that `INTERNET` exists only in
the debug/profile manifests and a release-only regression is invisible in a
debug build. A full `flutter build apk --release` was run and the merged output
inspected:

- `build/app/intermediates/packaged_manifests/release/.../AndroidManifest.xml`
  declares exactly two permissions: `RECORD_AUDIO`, and
  `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- The manifest-merger **blame report** attributes the first to the app's own
  `android/app/src/main/AndroidManifest.xml:5` and the second to
  `[androidx.core:core:1.13.1]` — a signature-level self-permission that comes
  in with the Flutter embedding and predates this plan.
- `grep -c wakelock` over that blame report is **0**: the new dependency
  contributes **no manifest node of any kind**. `grep -c INTERNET` over the
  packaged release manifest is **0**.

The plugin is a `FLAG_KEEP_SCREEN_ON` window flag on Android and
`isIdleTimerDisabled` on iOS — neither needs a permission or an entitlement.
The release build's deliberate microphone-only, no-network posture is unchanged.
Research assumption **A2** (the 1.7.0 Dart API matches 1.6.1's) was re-confirmed
by reading the resolved `wakelock_plus-1.7.0/lib/wakelock_plus.dart` in the pub
cache: `enable()` / `disable()` / `toggle({required bool enable})` / `enabled`,
unchanged.

## Deviations from Plan

### 1. [Rule 1 — Bug] The app's OWN pause was being reported as an interruption

`onPausedChanged` cannot distinguish "the OS paused the recorder for an answered
call" from "this app just called `pause()`" — both are a `true` on the same
stream — and stream delivery is asynchronous, so the event routinely arrives
**before** `pause()` has finished publishing `PracticePhase.paused`. The phase
check inside the handler therefore does not close the window. An ordinary Pause
tap was surfacing the D-31 banner, which **claims an answer was saved** that was
never saved. Caught by plan 02-04's existing on-screen paused-banner test, which
went red the moment the subscription was wired.

Fixed with `_expectingSelfPause`: set before the app's own `recordingService.pause()`,
consumed by exactly one event in the handler, released if the pause was not
confirmed. A dedicated regression test asserts both halves — an ordinary Pause
stays `PausedReason.user` and writes nothing, **and** a genuine interruption
arriving afterwards is still recognised (the consumed flag must not swallow it).

### 2. [Rule 2 — Missing] `resume()` did not cancel a deferred pause

`pause()` DEFERS rather than drops a request landing in `arming`/`saving`. A
Stop dialog opened in one of those phases and then dismissed with the safe
action left that request armed, so the session would freeze at the next
countdown seconds after the user explicitly chose to keep going. `resume()` now
clears it — an explicit resume cancelling a queued pause is correct generally,
not just on this path.

### 3. [Rule 2 — Missing] The wakelock is re-acquired on returning to the foreground

The plan's truths name only release conditions. Releasing on backgrounding
without re-acquiring on return would silently cost the rest of the session its
screen hold. `onShow` re-enables, guarded by `_wakeReleased` so it can never be
re-acquired after the session has genuinely ended.

### 4. [Rule 1 — Bug] `dispose()` double-released an already-released wakelock

A session reaching its completion state releases the hold there; `dispose()`
then released it again. Harmless but redundant, and caught by an explicit
assertion. Now guarded.

### 5. [Design] One `_requestStop()` instead of `_confirmStop()` + two act-blocks

Recorded under `decisions` above. Strictly stronger against the critical
requirement: with a bool-returning confirm, each of the two callers still owns
its own "what to do with `true`", which is precisely where the back gesture and
the button would drift apart.

### 6. [Documentation] A fourth thing that cannot be awaited on the fake clock

`await recordingService.dispose()` in a `tearDown` **stalls the run forever**.
The backend's broadcast `onPausedChanged` controller is closed there, and its
done event is delivered in the zone the screen's subscription was registered in
— the test body's fake-async zone, which nobody is pumping once the body has
ended. This cost one ten-minute silent stall before it was isolated with a
temporary probe (since removed). The reason is recorded inline in the new test
file's `tearDown`, joining sqflite-ffi futures, `tester.runAsync` under a live
`Timer.periodic`, and `await sub.cancel()` from plan 02-04.

## Known Stubs

None.

## Deferred / Flagged

- **The D-31 real-device human check is NOT discharged and is carried to UAT.**
  It is the one check only a device can make: a genuinely answered phone call
  mid-recording, on a real SIM. Host tests prove the handler, the ordering and
  the commit; they cannot prove the platform's behaviour around them. Steps are
  in the plan's `<verify><human-check>` and are the D-31 obligation from
  CONTEXT.md.
- **Research assumption A1 stands unresolved** — on iOS the Dart isolate may be
  suspended before the commit lands, so the answer may commit on the *next*
  foreground rather than before backgrounding. On Android it lands immediately,
  which is what the host tests model. If A1 is wrong in the stronger direction
  (the isolate is killed, not suspended) an iOS backgrounding could still lose
  an in-flight answer. Step 5 of the human check exists specifically to settle
  this and must not be skipped.
- **`flagged_assumptions` 1 (CTRL-03 edge category `unclassified`)** stands as
  the planner left it. The three body variants and the barrier-equals-cancel
  rule are now explicit tests rather than assumptions; the category itself is
  still worth a manual look at UAT.
- **`flagged_assumptions` 2 (the N = 0 dialog body)** is RESOLVED in code as the
  UI-SPEC's own proposal, `Nothing has been recorded yet.`, asserted verbatim by
  a test and carrying an inline comment recording that it is planner-resolved
  copy. Confirm at UAT; `02-UI-SPEC.md` E11/empty is still marked ⚠ unresolved
  and should be updated when it is.
- **E11/overflow** is structurally satisfied (`scrollable: true` on the dialog,
  so the body scrolls internally rather than pushing the actions off-screen) but
  remains a visual/UAT item at maximum text scale.

## Self-Check: PASSED

- `lib/services/screen_wake_controller.dart` — present, contains `abstract class ScreenWakeController`.
- `lib/screens/practice_screen.dart` — present, contains `onPopInvokedWithResult` (×1).
- `lib/state/practice_state.dart` — present, contains `handleInterruption`.
- `pubspec.yaml` — present, contains `wakelock_plus: ^1.7.0`.
- `test/services/screen_wake_controller_test.dart` — present, 73 lines.
- `test/screens/practice_screen_test.dart` — present, 11 cases green.
- Commits `94901c6`, `c520d71`, `ba2a246` — all present in `git log`.
- No scratch or probe test files left in the tree; the temporary probes inside
  the N = 0 case were removed before its commit.
