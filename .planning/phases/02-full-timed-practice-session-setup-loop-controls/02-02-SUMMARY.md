---
phase: 02-full-timed-practice-session-setup-loop-controls
plan: 02
subsystem: practice-loop
tags: [loop, countdown, replay-gate, completion, persistence, cycling]
status: complete

requires:
  - 02-01 (SessionConfig, PausableCountdown, appendAnswer, PracticePhase.getReady/.reading/.complete)
provides:
  - The closed multi-question loop: commit → optional replay → 3·2·1 → next question
  - LOOP-08 completion driven by the COMMITTED answer count
  - CountdownRing (the 96px determinate `t` ring)
  - kQuestions expanded to 20 prompts with sequential wrap (D-23)
  - PhaseControl.isFirstQuestion (the two get-ready captions)
affects:
  - test/state/practice_state_test.dart (two 02-01-parked cases un-parked)
  - test/state/practice_session_test.dart (tracer tail retargeted)

tech-stack:
  added: []
  patterns:
    - "One private `_enterGetReady()` owns the phase ORDER; both session start and the post-commit tail call it"
    - "`questionNumber` (asked) and `answeredCount` (committed) are two fields that must never be merged or derived from each other"
    - "A determinate CircularProgressIndicator only — a null `value` animates forever and hangs any settling test"
    - "Real-SQLite cases live in plain `test()` bodies; fake-clock cases live in `testWidgets`; the two never mix in one case"

key-files:
  created:
    - lib/widgets/countdown_ring.dart
    - test/widgets/countdown_ring_test.dart
  modified:
    - lib/state/practice_state.dart
    - lib/data/questions.dart
    - lib/widgets/phase_control.dart
    - lib/screens/practice_screen.dart
    - test/state/practice_session_test.dart
    - test/state/practice_state_test.dart
    - test/widgets/phase_control_test.dart

decisions:
  - "LOOP-08 fires on `answeredCount >= questionCount`, never on `questionNumber` — a save failure at the last question leaves the session one short rather than faking a completion"
  - "With `r` off the audio player is not touched at all, so 'off' is observable rather than merely inaudible"
  - "The 02-01 tracer test was retargeted rather than pinned to a 1-question config: with the loop closed, its stop lands on question 2 of the default 10"
  - "The durability case is a plain `test()` driving startNewQuestion/stopRecording — the only pair that touches the database — because sqflite-ffi futures cannot resolve under the fake clock"

metrics:
  duration: ~35m
  completed: 2026-08-09
  tasks: 3
  commits: 3

actuals:
  tokens: 29000
  tasks: 3
  commits: 3
---

# Phase 2 Plan 02: The Loop Closes Summary

A configured session of any length now runs unattended end to end: every
committed answer optionally replays, counts 3·2·1 into the next question, and
the session terminates on the number of answers actually written to disk — with
the `t` countdown finally rendering as its own 96px ring opposite the 3·2·1's
128px numeral.

## What Was Built

**Task 1 — the loop closes (`0201539`).** `stopRecording()`'s tail replaced
02-01's unconditional jump to `complete` with the real sequence: increment the
committed count, replay only when `config.autoReplay` (SETUP-06 finally
replacing Phase 1's hardcoded always-on D-10), end the session when
`answeredCount >= config.questionCount` (LOOP-08), otherwise increment `k` and
re-enter the same `_enterGetReady()` the session opened with (LOOP-07). Nothing
between the `stopRecording()` entry guard and the post-commit `if (_disposed)
return;` moved — the crash-safety contract is byte-for-byte what 02-01 left.
`kQuestions` grew from 5 to 20 prompts with the original five kept at the head,
so no existing expectation moved.

**Task 2 — the second countdown surface (`d905b35`).** `CountdownRing` renders a
determinate 96px ring inside the *mascot's own* 144px box, which is what makes
the `reading`-phase swap cost zero layout shift. `PhaseControl` gained
`isFirstQuestion`, so one keyed control carries both get-ready captions.
`PracticeScreen` wires the anchor slot and passes `questionNumber == 1`.

**Task 3 — the durability proof (`566742a`).** A real-SQLite case runs three
answers, abandons question 4, closes the handle and comes back through a new
one — finding exactly 3 answers under exactly 1 session row, in bank order.
Plus 10- and 25-question runs proving the wrap, and the ring's containment at
text scale 2.0.

## Verification

- `flutter analyze` — no issues.
- `flutter test` — 118 tests, all passing (111 after Task 1 and Task 2).
- Every acceptance grep for all three tasks checked; two needed a doc-comment
  reword, see Deviations.

## Deviations from Plan

### 1. [Rule 3 — Blocking] Two `practice_state_test.dart` cases had to be un-parked

**Found during:** Task 1.

`test/state/practice_state_test.dart` is not in this plan's `files_modified`,
but two of its cases went red the moment the replay came back — by design. Plan
02-01 removed the replay from the tail and left both cases asserting `calls ==
['start', 'stop']` with comments saying, in as many words, that plan 02-02 would
restore the real guard. Its config sets `autoReplay: true`, so both now see the
third `play` call.

- `stopRecording saves BEFORE anything else…` now asserts `['start', 'stop',
  'play']` **and** restores the `sessionsAtFirstPlay == 1` ordering assertion
  that 02-01 had to drop.
- `the answer is committed and the loop moves on even with a failing player` now
  genuinely arms a throwing player and proves the answer survives it, rather
  than proving the player was never reached.

This is the coverage handover 02-01 explicitly scheduled, not scope creep.

### 2. [Documentation] The tracer test's tail was retargeted

`test/state/practice_session_test.dart`'s end-to-end case asserted the
completion state after ONE answer. That was the tracer's stub: it held only
because 02-01's tail ended every session on the first commit. With the loop
closed and Setup's defaults (10 questions, `r` on), the same tap now replays and
counts into question 2 — so the case asserts *that*, plus the one committed row,
plus the hidden question card behind the 3·2·1. It also now tears the screen
down at the end, because the inter-question countdown it leaves running is a
pending timer the binding fails on.

### 3. [Documentation] Two acceptance greps counted doc-comment mentions

`grep -c 'Get ready…' lib/widgets/phase_control.dart` and `grep -c 'Nice work!'
lib/screens/practice_screen.dart` are specified as `equals 1`, but both strings
also appeared inside a nearby doc comment (the `Nice work!` one since Phase 1).
Both comments were reworded to point at the code rather than restate the copy —
the criteria now hold literally, and the copy exists in exactly one place per
file, which is what they were protecting.

## Known Stubs

None. The session-level Pause/Stop app-bar actions the UI-SPEC Layout Contract
shows are NOT missing work from this plan — CTRL-01/02/03 belong to a later plan
in this phase, and the `paused` phase does not exist yet. This plan's `complete`
state is reachable only by LOOP-08; the early-stop path into the same state
arrives with CTRL-03.

## Deferred / Flagged

- **`flagged_assumptions` 1 (LOOP-08 edge category unresolved)** stands as the
  planner left it: the only boundary implemented is `answeredCount ==
  questionCount`, authored as a truth and covered by tests 3, 4 and 9. The
  `questionCount` RANGE boundary is plan 02-03's (SETUP-03/04). Review at UAT.
- **`flagged_assumptions` 2 (skip the replay after an interruption)** — the
  replay gate is a single `if (config.autoReplay)` block at the tail, so plan
  02-05 can suppress it with one added condition and no restructuring, exactly
  as the plan required.
- **Backstop-verified truths** (E8/overflow, E8/long-text, E14/populated,
  E14/zero-one-many) remain backstops: the ring's 2.0-text-scale containment is
  now covered by a real test, but the question card's longest-prompt rendering
  and the 10-row session-detail list are still visual/UAT items.

## Self-Check: PASSED

- `lib/widgets/countdown_ring.dart` — present (93 lines).
- `test/widgets/countdown_ring_test.dart` — present (84 lines, min 30).
- Commits `0201539`, `d905b35`, `566742a` — all present in `git log`.
- `lib/screens/setup_screen.dart` — untouched (owned by concurrent plan 02-03).
