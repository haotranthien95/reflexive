---
phase: 01-record-save-replay-a-single-answer-crash-safe
plan: 06
subsystem: ui
tags: [flutter, sqflite, futurebuilder, error-handling, snackbar, concurrency, widget-tests]

# Dependency graph
requires:
  - phase: 01-record-save-replay-a-single-answer-crash-safe (plan 01)
    provides: DatabaseHelper, HistoryScreen, SessionDetailScreen, the sessions/question_answers schema
  - phase: 01-record-save-replay-a-single-answer-crash-safe (plan 03)
    provides: PRAGMA foreign_keys enforcement and the T-03-02 "no internal detail on screen" contract
  - phase: 01-record-save-replay-a-single-answer-crash-safe (plan 04)
    provides: AudioPlaybackBackend seam and kRecordingErrorMessage, the single-failure-voice pattern
provides:
  - A keyed, retryable error state on both history screens, proven distinct from the empty state
  - kHistoryErrorMessage — one failure voice shared by HistoryScreen and SessionDetailScreen
  - DatabaseHelper memoizing Future<Database>, so overlapping first accesses open exactly one connection
  - Null-safe session id, missing-file feedback, player-error feedback, and stop-before-play on tap-to-replay
  - AudioPlayerService injection seam on SessionDetailScreen, making tap-to-replay testable
  - REQUIREMENTS.md stating one coherent truth about all twelve Phase 1 requirements
affects: [phase-02-full-practice-loop, phase-03-firestore-question-bank, phase-01-verification]

# Actuals (#2632) — same estimateTokens scale (chars/4 over the realized diff).
actuals:
  tokens: 9239
  tasks: 3
  commits: 5

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FutureBuilder ordering: the snapshot.hasError branch MUST precede the snapshot.data read, because data is null on error and would otherwise render a failure as an absence"
    - "Empty state and error state each carry a distinct widget Key, so tests assert they are mechanically distinguishable rather than eyeballing copy"
    - "Memoize Future<T>, not T, for lazy async singletons — ??= assigns before the first await can yield"
    - "Screens that touch a platform-channel service take it as an optional constructor parameter, mirroring PracticeState's constructor injection"
    - "Widget tests that exercise real dart:io must drive the tap inside tester.runAsync(); the fake-async zone never resolves real I/O futures"

key-files:
  created:
    - test/screens/history_screen_test.dart
    - test/screens/session_detail_screen_test.dart
  modified:
    - lib/db/database_helper.dart
    - lib/screens/history_screen.dart
    - lib/screens/session_detail_screen.dart
    - test/db/database_helper_test.dart
    - .planning/REQUIREMENTS.md

key-decisions:
  - "The two failure SnackBar call sites were factored into one _showMessage helper rather than inlined, so the mounted guard exists once; this trades the plan's `grep -c SnackBar >= 2` proxy for two named constants each proven by a dedicated test"
  - "SessionDetailScreen gained an optional AudioPlayerService parameter — without the seam a tap test hangs on an unanswered platform channel rather than failing"
  - "The double-open test counts documentsDirProvider invocations rather than trusting identical(), because sqflite's own per-path cache makes identical() pass even when the open path runs twice"
  - "kHistoryErrorMessage is shared verbatim by both screens rather than duplicated per-screen, matching how kRecordingErrorMessage gives the practice loop one voice"
  - "Phase 1 traceability uses two distinct statuses so no requirement is marked done on the strength of a device check nobody ran"

patterns-established:
  - "One failure voice per failure class: a single const string shared by every screen that can hit it"
  - "A read failure is never coerced into an empty collection anywhere in the app"

requirements-completed: [HIST-01, HIST-02, HIST-03, HIST-04, PERSIST-01, PERSIST-02, UI-01, UI-02]

coverage:
  - id: D1
    description: "HistoryScreen renders a distinct, retryable error state on a failed read and never the 'No recordings yet' empty copy"
    requirement: "HIST-01"
    verification:
      - kind: unit
        ref: "test/screens/history_screen_test.dart#renders the error state and never the empty state"
        status: pass
      - kind: unit
        ref: "test/screens/history_screen_test.dart#offers a retry that re-issues the query"
        status: pass
      - kind: unit
        ref: "test/screens/history_screen_test.dart#zero sessions renders the empty state, not the error state"
        status: pass
    human_judgment: false
  - id: D2
    description: "SessionDetailScreen renders the same error state, survives a null session id, and scopes its query to one session"
    requirement: "HIST-02"
    verification:
      - kind: unit
        ref: "test/screens/session_detail_screen_test.dart#renders the error state, not an empty answer list"
        status: pass
      - kind: unit
        ref: "test/screens/session_detail_screen_test.dart#renders an empty list instead of throwing in initState"
        status: pass
      - kind: unit
        ref: "test/screens/session_detail_screen_test.dart#scopes the query to this session only"
        status: pass
    human_judgment: false
  - id: D3
    description: "DatabaseHelper opens exactly one connection under overlapping first access, and close() leaves it reopenable"
    requirement: "PERSIST-01"
    verification:
      - kind: unit
        ref: "test/db/database_helper_test.dart#two overlapping first accesses open exactly one connection"
        status: pass
      - kind: unit
        ref: "test/db/database_helper_test.dart#close() leaves the helper able to open again"
        status: pass
    human_judgment: false
  - id: D4
    description: "Tapping a detail row surfaces a missing file and a player error instead of silence, and stops previous playback before starting the next"
    requirement: "HIST-03"
    verification:
      - kind: unit
        ref: "test/screens/session_detail_screen_test.dart#a row whose recording is gone says so rather than nothing"
        status: pass
      - kind: unit
        ref: "test/screens/session_detail_screen_test.dart#a player failure is surfaced, not swallowed"
        status: pass
      - kind: unit
        ref: "test/screens/session_detail_screen_test.dart#a second tap stops the previous playback before starting"
        status: pass
    human_judgment: false
  - id: D5
    description: "SC-3/HIST-03 — on a device, recording 2-3 answers then opening Exercise History lists every answer newest-first, and tapping a question row plays that specific recording audibly"
    requirement: "HIST-03"
    verification: []
    human_judgment: true
    rationale: "Audibility cannot be asserted from a widget test; the fake backend proves the call is made with the right path, not that sound comes out of a speaker."
  - id: D6
    description: "SC-4/D-07 — force-killing the app from the OS task switcher after two finished answers still shows and plays them on relaunch; a kill DURING recording leaves no session row and its partial .m4a is swept"
    requirement: "PERSIST-02"
    verification: []
    human_judgment: true
    rationale: "CONTEXT.md D-07 locks this as a mandatory real-process proof. This environment cannot perform an OS-level process kill, and no unit test can substitute for one."
  - id: D7
    description: "REQUIREMENTS.md reflects the true post-gap-closure state of all twelve Phase 1 requirements"
    verification:
      - kind: other
        ref: "grep -c 'Gaps Found' .planning/REQUIREMENTS.md → 0"
        status: pass
    human_judgment: false

# Metrics
duration: 32min
completed: 2026-08-08
status: complete
---

# Phase 01 Plan 06: A Read Failure Is Reported As A Read Failure Summary

**Both history screens now distinguish "your recordings could not be read" from "you have no recordings", with a retry on each, plus the memoized database open that removes the most plausible cause of that read error.**

## Performance

- **Duration:** ~32 min (worktree `worktree-agent-abe35902831e4987f`, base `28f50c9`)
- **Started:** 2026-08-08
- **Completed:** 2026-08-08
- **Tasks:** 3 (Tasks 1 and 2 each TDD: RED commit then GREEN commit)
- **Files modified:** 7 (2 created, 5 modified)

## Accomplishments

- **Gap 4 closed on BOTH screens, not just the first.** `HistoryScreen` and `SessionDetailScreen` each coerced a failed read into an empty list via `snapshot.data ?? const []`, rendering a transient database error as "No recordings yet" — for a phase whose entire premise is that nothing captured is ever lost, that is the worst possible failure presentation. Each screen now has a `snapshot.hasError` branch placed *before* the `snapshot.data` read, returning a keyed error widget with a retry that re-issues the query.
- **The two states are provably distinct, not just visually different.** `_EmptyHistory` is keyed `history-empty` and the new error widget `history-error`, so the widget tests pump a throwing helper and a zero-row helper against the same screen and assert the error key is present while the empty key — and both literal Copywriting Contract strings — are absent. Eyeballing copy would not have caught a regression here; a key assertion does.
- **The double-open defect is gone, and the test proves the right thing.** `DatabaseHelper` memoized `Database? _db` while awaiting two async calls between the null check and the assignment, so the launch-time orphan sweep and an immediate History tap could both enter and open the database twice, leaking one handle for the process lifetime. It now memoizes `Future<Database>` via `_dbFuture ??= _open()`, and `close()` clears the memo before awaiting.
- **The scenario is real, not theoretical.** `PracticeScreen` passes `_state.databaseHelper` straight into `HistoryScreen`, so the sweep and the History read share one helper instance — exactly the two overlapping first accesses the fix addresses.
- **A tap on a history row can no longer be a silent no-op.** A missing audio file and a player error each produce a `SnackBar`; the previous code awaited `play()` on a nonexistent path and discarded the future. `AudioPlayerService.stop()` — which review finding IN-06 flagged as having no caller anywhere — is now called before every play, so two rapid taps cannot overlap two recordings.
- **`widget.session.id!` is gone.** `Session.id` is nullable and `Session.fromMap` will happily produce a null, so the force-unwrap turned a data problem into a red-screen crash inside `initState`. It now renders an empty answer list.
- **`test/screens/` exists for the first time; test count 78 (up from 68).** `flutter analyze`: no issues. Whole suite green.
- **`REQUIREMENTS.md` now states one coherent, defensible truth about Phase 1** — five requirements `Complete` on test evidence, seven `Complete (device UAT pending)`, none marked done on the strength of a check nobody ran.

## Task Commits

1. **Task 1 (RED): failing tests for the history error state and the double-open** — `79db948` (test)
2. **Task 1 (GREEN): error state + memoized `Future<Database>`** — `de3ee57` (feat)
3. **Task 2 (RED): failing tests for the detail error state and null session id** — `f8788b0` (test)
4. **Task 2 (GREEN): detail error state, null-safe id, honest playback feedback** — `9c6d591` (feat)
5. **Task 3: reconcile REQUIREMENTS.md** — `e06dda4` (docs)

## Files Created/Modified

**Created**

- `test/screens/history_screen_test.dart` — the error/empty distinction, the retry round-trip, the touch-target floor, and the populated-list cases.
- `test/screens/session_detail_screen_test.dart` — the detail error state, the null-id path, the scoped query, and a `tap-to-replay` group that drives real filesystem checks through `tester.runAsync()` with a fake `AudioPlaybackBackend`.

**Modified**

- `lib/db/database_helper.dart` — `Database? _db` → `Future<Database>? _dbFuture` + `_open()`; `close()` clears the memo before awaiting. The field's doc comment records why the *future* is memoized and names the concrete two-caller race.
- `lib/screens/history_screen.dart` — `kHistoryErrorMessage`; `_HistoryError`; `_load()` shared by `initState` and retry; `snapshot.hasError` branch; `history-empty` key on `_EmptyHistory`.
- `lib/screens/session_detail_screen.dart` — `_SessionDetailError`; `kRecordingMissingMessage` / `kRecordingPlaybackFailedMessage`; `_load()` with the null-guarded id; `_play()` rewritten (stop-before-play, existence check, guarded play, `_showMessage`); `onTap` now `unawaited(...)`; optional `audioPlayerService` parameter.
- `test/db/database_helper_test.dart` — a `database (lazy open)` group: the overlapping-access count, reopen-after-close, and close-before-open.
- `.planning/REQUIREMENTS.md` — UI-01/UI-02 ticked; twelve Phase 1 traceability rows reconciled; footer note.

## Decisions Made

- **The error copy names the cause AND explicitly says the recordings are still there.** `kHistoryErrorMessage` is *"Couldn't open your recordings — they're still saved on this device. Try again."* The UI-SPEC Copywriting Contract has no read-failure row, so this was written to its stated rules (name the likely cause and the next action, never blame the user). The middle clause is load-bearing and is the whole reason this plan exists: the failure must not *read* as data loss.
- **One shared message, two screens.** `SessionDetailScreen` imports `kHistoryErrorMessage` rather than declaring its own, so the app has exactly one voice for "your saved recordings could not be read", matching how `kRecordingErrorMessage` serves the practice loop.
- **Neither error widget touches `snapshot.error`.** Preserves Plan 3's T-03-02 contract; the user gets the situation, never the exception text or a file path.
- **The concurrency test counts `documentsDirProvider` invocations, not object identity.** During RED, `identical(a, b)` passed against the *broken* implementation — sqflite keeps its own per-path open cache, so identity proves nothing about whether our open path ran twice. Counting the documents-dir resolutions (exactly one per `_open()`) observes the defect directly: it read 2 before the fix and 1 after.
- **Phase 1 statuses use two values, deliberately.** `Complete` only where behaviour is proven by automated tests (LOOP-04, LOOP-05, HIST-01, HIST-02, PERSIST-01); `Complete (device UAT pending)` wherever the remaining evidence is an on-device check carried as a `backstop` truth. The whole point of the backstop markers is that they abstain rather than silently pass, and commit `1d39a76` on this branch's ancestry already reverted one premature blanket `Complete`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SessionDetailScreen` needed an `AudioPlayerService` injection seam**

- **Found during:** Task 2 (the missing-file test)
- **Issue:** The plan's `<behavior>` requires "tapping a row whose audio file does not exist shows a message rather than doing nothing silently", but the screen constructed `AudioPlayerService()` internally as a `final` field. `_play()`'s first statement awaits `_audioPlayerService.stop()`, which lazily resolves the real `_AudioPlayersBackend` and reaches an `audioplayers` platform channel that has no implementation under `flutter test`. The call never returns, so the test **hung** (twice, to a 300s tool timeout) rather than failing — the worst kind of untestable, because it looks like an environment problem rather than a design one.
- **Fix:** Added an optional `audioPlayerService` parameter to `SessionDetailScreen`, defaulting to `AudioPlayerService()` in `initState`. This is the same manual constructor injection `PracticeState` already uses for all three of its services, so it introduces no new pattern. Tests inject the *real* `AudioPlayerService` wrapping a fake `AudioPlaybackBackend` — the seam Plan 01-04 built for exactly this purpose.
- **Files modified:** `lib/screens/session_detail_screen.dart`, `test/screens/session_detail_screen_test.dart`
- **Verification:** The three `tap-to-replay` tests run and pass in ~1s instead of hanging.
- **Committed in:** `9c6d591` (Task 2 commit)

**2. [Rule 2 - Missing Critical] Added the three tap-to-replay tests the plan's test list omitted**

- **Found during:** Task 2
- **Issue:** The plan's `<behavior>` block names "tapping a row whose audio file does not exist shows a message", but its enumerated test list (a)-(d) covers only the error state, retry, null id and row rendering. The behaviour that closes review findings WR-06 and IN-06 would have shipped with no automated coverage at all.
- **Fix:** Added a `tap-to-replay` group covering the missing-file SnackBar, the player-error SnackBar, and the `['stop', play, 'stop', play]` call ordering that proves two taps cannot overlap.
- **Files modified:** `test/screens/session_detail_screen_test.dart`
- **Verification:** All three pass; the ordering test would fail if the `stop()` call were removed.
- **Committed in:** `9c6d591` (Task 2 commit)

### Acceptance criterion not met as literally written

**`grep -c 'SnackBar' lib/screens/session_detail_screen.dart` returns 1, not `>= 2`.**

The plan describes two inline `SnackBar` sites, each with its own `mounted` guard. Both were factored into a single `_showMessage(String)` helper, so the `mounted` guard exists in exactly one place and cannot drift between the two paths. The criterion's *intent* — two distinct, user-visible failure messages — is met and is verified more strongly than a grep can: `kRecordingMissingMessage` and `kRecordingPlaybackFailedMessage` are named constants, each asserted by its own passing widget test. Flagged here rather than satisfied by inlining, because contorting the code to move a proxy metric would make it worse while proving nothing extra.

All other acceptance criteria pass: `snapshot.hasError` ≥1 in both screens (1 each), `session.id!` = 0, `_audioPlayerService.stop()` = 1, `_dbFuture` = 4, `Gaps Found` = 0, both UI checkboxes ticked.

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing critical) + 1 flagged criterion.
**Impact on plan:** Both auto-fixes were required to verify behaviour the plan itself specified. No scope creep — no new dependency, no new screen, no schema change.

## Issues Encountered

- **A widget test that hangs instead of failing.** Two separate causes, both worth recording because both look identical from the outside (a silent 300s timeout with zero output, since `flutter test` buffers). First: the unstubbed `audioplayers` platform channel never replies (fixed by the injection seam above). Second: `testWidgets` bodies run in a fake-async zone that pumps fake timers but never the real event loop, so an awaited `dart:io` future — `File.exists()` inside `_play`, `Directory.createTemp` in a test body — simply never resolves. Both the file creation and the tap now run inside `tester.runAsync()`, and each helper carries an in-file comment saying why, so the next person does not rediscover this the slow way.
- **`identical()` passed against the broken database implementation.** Documented under Decisions; it would have been an entirely convincing green test that proved nothing. The RED run is what exposed it — the identity assertion passed while the resolution count failed, in the same test.
- **`build/unit_test_assets` was cleared before the full-suite run** per the wave-1 handoff note. No test result changed, but the stale-bundle trap is real and the clear is cheap.
- No blockers, no checkpoints, no architectural (Rule 4) decisions were required.

## Known Stubs

None. No placeholder values, no TODO/FIXME, no skipped tests introduced by this plan.

## Threat Flags

None. This plan adds no network endpoint, no auth path, no new file-access pattern and no schema change. `T-06-05` (resolving a stored relative path outside the app container) remains `accept` as the plan records: every Phase 1 writer produces a `recordings/<name>` relative path, so the escape is unreachable today; it is carried as review finding IN-04 for Phase 3, where externally-sourced strings first enter the app.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Verification Gap 4 is closed on both screens.** The remaining Phase 1 evidence is entirely on-device: SC-3 (audible tap-to-replay), SC-4/D-07 (the force-kill proof), and the visual half of SC-5. These are carried as `human_judgment: true` coverage entries D5 and D6 so they route to a human rather than auto-passing.
- **Phase 2 inherits the pattern, and should not break it.** Phase 2 adds multi-question sessions, which means more `FutureBuilder`s over the same tables. The rule established here — `snapshot.hasError` before `snapshot.data`, distinct keys for empty vs error — must be applied to every new list it introduces. `listAnswersForSession()` already orders by `id ASC`, which is the ordering multi-question detail rendering depends on.
- **Two review findings remain deliberately open**, per the plan's `<review_disposition>`: WR-12 (`toMap()` production-dead) folds naturally into Phase 2's multi-row inserts, and IN-01 (timestamps stored as local time with no offset) needs a plan that can carry a data migration — history ordering uses `sessions.id DESC`, not the timestamp, so there is no functional impact today.
- **`.planning/STATE.md` and `.planning/ROADMAP.md` were deliberately NOT modified** — this plan ran in a worktree and the orchestrator owns those writes after the wave merges.

---
*Phase: 01-record-save-replay-a-single-answer-crash-safe*
*Completed: 2026-08-08*
