---
phase: 02-full-timed-practice-session-setup-loop-controls
plan: 01
subsystem: practice-loop
tags: [setup-screen, timed-loop, countdown, persistence, tracer]
status: complete

requires:
  - Phase 1 PracticeState / RecordingService / DatabaseHelper / PhaseControl
provides:
  - SessionConfig (immutable session transport)
  - PausableCountdown (the phase's one timing primitive)
  - SetupScreen (new app home, D-28)
  - PracticePhase.getReady / .reading / .complete + keyed controls
  - DatabaseHelper.appendAnswer (single transaction-owning writer, D-26)
  - DatabaseHelper.findSession
affects:
  - lib/main.dart (home is now SetupScreen)
  - lib/utils/audio_paths.dart (ensureRecordingsDir is now sync-checked)
  - test/state/practice_state_test.dart (5 tests retargeted)

tech-stack:
  added: []
  patterns:
    - "One PausableCountdown alive at a time, replaced on every phase transition, cancelled in dispose()"
    - "Lazy session creation: the sessions row is written by the FIRST answer, one transaction per answer"
    - "Nothing on the loop's hot path awaits a future only the real event loop can complete"

key-files:
  created:
    - lib/models/session_config.dart
    - lib/utils/pausable_countdown.dart
    - lib/screens/setup_screen.dart
    - test/state/practice_session_test.dart
    - test/utils/pausable_countdown_test.dart
    - test/models/session_config_test.dart
  modified:
    - lib/state/practice_state.dart
    - lib/db/database_helper.dart
    - lib/services/recording_service.dart
    - lib/widgets/phase_control.dart
    - lib/screens/practice_screen.dart
    - lib/data/questions.dart
    - lib/utils/audio_paths.dart
    - lib/main.dart
    - test/state/practice_state_test.dart
    - test/widgets/phase_control_test.dart
    - test/db/database_helper_test.dart

decisions:
  - "appendAnswer owns the only transaction; insertAnsweredSession is a one-line delegation to its sessionId==null branch"
  - "ensureRecordingsDir checks existence synchronously so arming is never gated on filesystem I/O"
  - "The tracer widget test drives an in-memory DatabaseHelper double; real sqflite is proven by test/db/database_helper_test.dart"
  - "The tracer test pins a 400x900 portrait surface rather than the 800x600 landscape default"

metrics:
  duration: ~75m
  completed: 2026-08-08
  tasks: 3
  commits: 3

actuals:
  tokens: 26000
  tasks: 3
  commits: 3
---

# Phase 2 Plan 01: End-to-End Configured Session Summary

A configured practice session now runs from the Setup screen through a 3·2·1
get-ready countdown, a per-question `t` countdown, arming, recording against a
session-supplied `d` deadline, one durably committed answer and a completion
state — with `appendAnswer` as the single transaction-owning writer behind it.

## What Was Built

**Task 1 — the tracer (`0575498`).** One entry point wired through every layer:
`SessionConfig` carries topics/level/counts/timings out of `SetupScreen`;
`PausableCountdown` became the one timing primitive behind the get-ready
countdown, the `t` countdown and the `d` recording deadline; `PracticePhase`
gained `getReady`, `reading` and `complete`, each with a keyed control;
`RecordingService.start` gained `maxDuration` and `onTick` so the deadline and
the on-screen readout are the same object (D-21); `SetupScreen` became the app
home (D-28) with a topic-gated `START SESSION` (SETUP-07) and now owns the
orphan-recording sweep.

**Task 2 — the identity promotion (`978db16`).** `DatabaseHelper.appendAnswer`
is the ONE crash-safety-critical writer: it creates the `sessions` row lazily on
the first answer and appends thereafter, each call in its own transaction, so
durability holds per question rather than per session. `insertAnsweredSession`
survives only as a one-line delegation. Five new DB tests cover lazy creation,
appending, the N-answer round-trip, a simulated process kill after answer k, and
the orphan-`sessionId` foreign-key failure. Schema and `version: 1` untouched.

**Task 3 — the guard rails (`22dfd7b`).** Seven `testWidgets` cases pin
`PausableCountdown`'s tick/elapse-once, pause-freeze, resume-in-place,
idempotent `pause`/`resume`/`start`, no-re-arm-after-elapsing and terminal
`cancel` semantics. `SessionConfig` gains a compile-time field contract.
`phase_control_test.dart` gains the `d` readout, the null-readout case, the two
new captions, both completion buttons and the null-callback guard — with both
totality assertions untouched.

## Verification

- `flutter analyze` — no issues.
- `flutter test` — 102 tests, all passing (83 after Task 1, 88 after Task 2).
- Every Task 1, 2 and 3 acceptance-criteria grep checked; see Deviations for the
  single one that could not hold as literally written.

## Deviations from Plan

### 1. [Rule 3 — Blocking] The tracer test cannot use real SQLite

**Found during:** Task 1 (the inherited failure this retry was spawned to fix).

**Issue:** the plan specifies the tracer test drive real `sqflite_common_ffi` and
assert on `listSessions()`. It cannot. `flutter_test`'s
`AutomatedTestWidgetsFlutterBinding` runs a `testWidgets` body on a fake clock
that advances timers and drains microtasks but never yields to the real event
loop. Every sqflite-ffi future is completed by the real event loop, so the loop
parked forever on its first `await` — the `reading → arming` handover never
armed the recorder. Confirmed directly: a bare `await helper.listSessions()` as
the first line of a `testWidgets` body hangs the run with no output and no
timeout. `tester.runAsync` — the documented escape hatch, and the first remedy
tried — hangs just as hard, because this loop always has a live `Timer.periodic`
and the binding's fake-async/real-async reconciliation never returns with one
pending.

**Fix, in three parts:**

1. `ensureRecordingsDir()` now checks existence and creates synchronously
   (`existsSync`/`createSync`). This is the remedy the plan itself flagged as
   "worth checking on its own merits": arming the microphone should not be gated
   behind filesystem I/O. Two syscalls per question, and the arming handover is
   now bounded only by the recorder.
2. The tracer test injects an `InMemoryDatabaseHelper` that models the same
   lazy-session-creation rule (`appendAnswer` override). The split is
   deliberate: this file owns the LOOP (phase order, the D-20 cold-microphone
   window, the D-21 deadline, exactly one answer for a one-question session);
   the real engine, its transactions and its crash-safety guarantees are owned
   by `test/db/database_helper_test.dart`, a plain `test()` file with no fake
   clock in its way — which Task 2 extended with five more real-sqflite cases
   including the kill-after-k invariant.
3. The test pins a 400x900 portrait surface. On the 800x600 landscape default
   the centred STOP circle lands exactly on the bottom edge and `tap()` misses
   it — a test-surface artefact; every layout this app ships is portrait.

**Net effect on coverage:** none of the plan's truths lost a test. The
"exactly one `question_answers` row against exactly one `sessions` row" truth is
asserted in both places — against the double in the loop test and against real
SQLite in the DB test.

**Files:** `lib/utils/audio_paths.dart`, `test/state/practice_session_test.dart`.
**Commit:** `0575498`.

### 2. [Documentation] One acceptance grep cannot hold as written

Task 2's criterion `grep -c 'testWidgets' test/state/practice_state_test.dart`
equals 0 conflicts with the plan's own instruction to keep that file's rationale
comment, which contains the word `testWidgets`. Zero `testWidgets` **cases**
exist in the file (the intent); one mention survives, inside the comment the
plan mandates. No code change made.

## Inherited Work

This plan was executed as a retry over a previous executor's uncommitted
snapshot (9 modified + 4 new files, 81 passing / 1 failing). The snapshot was
restored, reproduced exactly, verified against each task's requirements, and
then repaired as described above. `lib/utils/audio_paths.dart` was added to the
plan's file list as part of deviation 1; everything else stayed within scope.

## Known Stubs

None. `PlaceholderQuestionSource` reads the five Phase 1 prompts and is the
declared Phase 3 Firestore swap point, not a stub — the seam is exercised by the
tracer. Plan 02-02 restores the optional replay and the inter-question advance,
which this plan deliberately stops short of (the tracer ends the session on the
first committed answer, and `practice_state.dart` says so at the call site).

## Self-Check: PASSED

- All six created files present on disk.
- All three commits present in `git log`.
- `test/state/practice_session_test.dart` is 318 lines (min 60);
  `test/utils/pausable_countdown_test.dart` is 163 lines (min 40).
