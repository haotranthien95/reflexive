---
phase: 01-record-save-replay-a-single-answer-crash-safe
plan: 03
subsystem: reliability
tags: [flutter, dart, sqflite, foreign-keys, error-handling, permissions, crash-safety]

requires:
  - phase: 01-01
    provides: "RecordingService, PracticeState, DatabaseHelper and the crash-safe write ordering this plan hardens"
  - phase: 01-02
    provides: "colorScheme.error (#E5484D) and Mascot(isError:) — the theme tokens the error banner renders on"
provides:
  - "RecordingPermissionDeniedException — a typed, catchable signal from RecordingService.start() when the mic is denied"
  - "PracticePhase.error wired from both recorder failure and save failure, always carrying the verbatim UI-SPEC copy"
  - "PracticeState.retry() and a Retry affordance on the error banner"
  - "PRAGMA foreign_keys = ON via DatabaseHelper.onConfigure — the REFERENCES clause from Plan 1 is now actually enforced"
  - "pruneOrphanRecordings() — a launch-time sweep of audio files no DB row references, run strictly before the first recording is armed"
  - "DatabaseHelper.listReferencedAudioPaths()"
affects: [02-timed-multi-question-loop]

actuals:
  tokens: 11000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "One fixed user-facing failure string (kRecordingErrorMessage) shared by every failure path; exception objects are caught and discarded, never rendered"
    - "Connection-level SQLite settings applied in onConfigure so already-created databases pick them up with no migration and no version bump"
    - "Destructive cleanup is awaited to completion before the resource it sweeps can be re-created (prune -> then arm the recorder)"

key-files:
  created:
    - test/utils/audio_paths_test.dart
  modified:
    - lib/services/recording_service.dart
    - lib/state/practice_state.dart
    - lib/screens/practice_screen.dart
    - lib/db/database_helper.dart
    - lib/utils/audio_paths.dart
    - test/state/practice_state_test.dart
    - test/db/database_helper_test.dart

key-decisions:
  - "One error message constant, not one per failure kind — the user's next action is identical (check the mic, tap Retry) and a per-cause message is exactly how exception detail leaks into the UI"
  - "Enabling foreign keys needs no migration: the pragma is per-connection state and Plan 1's CREATE TABLE already carries the REFERENCES clause, and SQLite does not re-validate existing rows when the pragma is switched on — so a Plan 1 database can never fail to open because of this change"
  - "A save failure does NOT auto-restart recording; only the user's Retry tap does, so a persistently failing disk cannot spin the loop"
  - "The orphan sweep runs from the screen's bootstrap and is awaited before startNewQuestion() picks a file name — a file being written right now is by definition unreferenced, so the ordering is what makes the sweep safe"

patterns-established:
  - "User-facing error copy is a named constant in the state layer, asserted verbatim in tests; widgets receive the string and have no access to the exception"
  - "Every launch-time cleanup must state, in its doc comment, the ordering contract that keeps it from deleting live data"

requirements-completed: [PERSIST-01, PERSIST-02, HIST-04]

coverage:
  - id: D1
    description: "A denied microphone permission puts PracticeState in PracticePhase.error with the exact UI-SPEC copy, and PracticeScreen shows it in a banner instead of crashing"
    requirement: "PERSIST-01"
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#error handling a denied microphone permission shows the exact UI-SPEC copy and writes nothing"
        status: pass
      - kind: manual_procedural
        ref: "Revoke the microphone in OS Settings, launch the app, open the Practice screen"
        status: unknown
    human_judgment: true
    rationale: "A real OS permission-denial dialog cannot be triggered from a sandboxed test host; only a device proves the banner renders and the app does not crash."
  - id: D2
    description: "The error banner never surfaces a raw exception message, stack trace, or file path — only the fixed UI-SPEC copy string (T-03-02)"
    requirement: "PERSIST-01"
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#error handling a save failure shows the same copy and does NOT auto-restart recording — the injected exception text contains a device file path and never reaches errorMessage"
        status: pass
      - kind: other
        ref: "_ErrorBanner takes only a String message supplied by PracticeState; both catch blocks bind `catch (_)` and discard the exception object"
        status: pass
    human_judgment: false
  - id: D3
    description: "A visible Retry affordance on the error banner calls startNewQuestion() again, returning the app to a normal recording attempt"
    requirement: "PERSIST-01"
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#error handling retry() re-attempts recording once permission is granted"
        status: pass
      - kind: manual_procedural
        ref: "Grant the microphone from OS Settings, return to the app, tap Retry on the banner"
        status: unknown
    human_judgment: true
    rationale: "The button's visibility, size and legibility on a real screen is a visual judgment; the state transition it drives is unit-proven."
  - id: D4
    description: "The database rejects a question_answers row referencing a non-existent session id (PRAGMA foreign_keys = ON via onConfigure)"
    requirement: "PERSIST-02"
    verification:
      - kind: unit
        ref: "test/db/database_helper_test.dart#foreign key enforcement rejects an answer row pointing at a session that does not exist"
        status: pass
      - kind: unit
        ref: "test/db/database_helper_test.dart#foreign key enforcement the pragma is on for the helper's own connection"
        status: pass
      - kind: unit
        ref: "test/db/database_helper_test.dart#foreign key enforcement a legitimate insert still succeeds with enforcement on"
        status: pass
    human_judgment: false
  - id: D5
    description: "All SQL access in database_helper.dart uses typed insert()/query() with whereArgs — zero string-interpolated SQL over any value (T-01-02 final audit)"
    verification:
      - kind: other
        ref: "grep -rn 'rawQuery|rawInsert|rawUpdate|rawDelete' lib/ -> no matches; the only execute() calls are the fixed PRAGMA and two CREATE TABLE statements interpolating this class's own static const table-name identifiers"
        status: pass
    human_judgment: false
  - id: D6
    description: "A force-kill while a recording is in progress leaves zero trace on relaunch — no session row, no question_answers row, no orphaned audio file (D-08)"
    requirement: "PERSIST-02"
    verification:
      - kind: unit
        ref: "test/utils/audio_paths_test.dart#pruneOrphanRecordings deletes a file left behind by a kill mid-recording"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#a losing stop signal writes nothing — first stop wins (no row is written without a finalized path)"
        status: pass
      - kind: manual_procedural
        ref: "D-07 case 1: start a recording, force-kill the process (swipe from recents or adb shell am force-stop) BEFORE tapping Stop, relaunch, open History"
        status: unknown
    human_judgment: true
    rationale: "D-07 explicitly requires a real force-kill on a real process; the phase's defining risk cannot be inferred from unit tests."
  - id: D7
    description: "Force-killing AFTER at least one question has been fully answered leaves that answer intact in History with a working recording (D-07 case 2)"
    requirement: "PERSIST-02"
    verification:
      - kind: unit
        ref: "test/utils/audio_paths_test.dart#pruneOrphanRecordings never touches a file a saved answer still points at (the launch sweep cannot eat a saved recording)"
        status: pass
      - kind: manual_procedural
        ref: "D-07 case 2: fully answer a question (let it save and auto-replay), force-kill the process, relaunch, open History and replay the answer"
        status: unknown
    human_judgment: true
    rationale: "Backstop per the plan's must_haves; durability across a real process kill needs a device."
  - id: D8
    description: "Relaunching repeatedly without recording shows the identical History list each time — reads are pure and the launch sweep is idempotent (HIST-04)"
    requirement: "HIST-04"
    verification:
      - kind: unit
        ref: "test/db/database_helper_test.dart#listReferencedAudioPaths returns the DB-relative path of every saved answer (the sweep's keep-set is exactly what the DB references)"
        status: pass
      - kind: unit
        ref: "test/utils/audio_paths_test.dart#pruneOrphanRecordings is a harmless no-op when there is nothing to sweep"
        status: pass
      - kind: manual_procedural
        ref: "Relaunch the app three times without recording; History must show the same rows, all still replayable"
        status: unknown
    human_judgment: true
    rationale: "listSessions/listAnswersForSession are pure SELECTs, but the new launch-time sweep is the one write that now runs on every launch — a device run confirms it never removes a referenced recording."

duration: 8min
completed: 2026-08-08
status: complete
---

# Phase 1 Plan 03: Error Handling & Crash-Safety Hardening Summary

**A denied microphone or a failed save now lands on a stable, retryable error banner carrying the exact UI-SPEC copy and nothing about the app's internals, while the database enforces the referential integrity it only declared before and a launch-time sweep removes the partial audio file a force-kill mid-recording leaves behind.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-08-08T04:50Z (approx.)
- **Completed:** 2026-08-08T04:58Z
- **Tasks:** 2
- **Files modified:** 8 (1 created, 7 modified)

## Accomplishments

- Replaced Plan 1's "just don't crash" permission behaviour with a real gate: `RecordingService.start()` checks `hasPermission()` **before** touching a file and throws a typed `RecordingPermissionDeniedException`, so a denied attempt leaves nothing on disk and nothing in the database.
- Wired both failure paths — recorder failure and save failure — into `PracticePhase.error` carrying one shared, verbatim UI-SPEC string, with the exception object caught and discarded so no file path or class name can reach the screen.
- Added the error banner: docked above the question card (which stays visible, per UI-SPEC), warm red on icon/text/Retry only rather than a red fill, wrapping copy and a 48px-minimum Retry target.
- Turned on `PRAGMA foreign_keys` via `onConfigure`, making Plan 1's inert `REFERENCES` clause a real constraint — and did it without a migration, so devices already carrying a version-1 database pick enforcement up on their next launch.
- Closed the last literal gap in D-08's "leaves no trace": a force-kill mid-recording used to leave a partial `.m4a` on disk forever. It is now swept at launch, strictly before the next recording is armed.
- Re-audited every statement in `database_helper.dart` for parameterization (T-01-02): no value is ever concatenated into SQL.

## Task Commits

1. **Task 1: Mic-permission-denied and save-failure handling with a real error banner** - `b8e4716` (feat)
2. **Task 2: Foreign-key enforcement, SQL-parameterization audit, orphan-file sweep** - `d35c03e` (feat)

## Files Created/Modified

- `lib/services/recording_service.dart` - `RecordingPermissionDeniedException`; `start()` now gates on `hasPermission()` before any file is created
- `lib/state/practice_state.dart` - `kRecordingErrorMessage` (the one user-facing failure string), try/catch around the recorder start and around `insertAnsweredSession`, `retry()`, and the private `_fail()` transition
- `lib/screens/practice_screen.dart` - `_ErrorBanner` widget; body restructured so the banner docks above the still-visible question card; `_bootstrap()` sweeps orphans then arms the first recording
- `lib/db/database_helper.dart` - `onConfigure` running `PRAGMA foreign_keys = ON`; `listReferencedAudioPaths()`; a precise class-level note on what the remaining `execute()` calls are
- `lib/utils/audio_paths.dart` - `pruneOrphanRecordings()` with its caller ordering contract
- `test/state/practice_state_test.dart` - `FailingDatabaseHelper` plus three error-handling tests (denied permission, retry, save failure)
- `test/db/database_helper_test.dart` - Five tests: FK rejection, pragma state, legitimate insert still works, and the referenced-path query
- `test/utils/audio_paths_test.dart` - Three sweep tests: deletes an orphan, keeps a referenced file, no-ops when empty

## Decisions Made

- **One error message, not one per cause.** The UI-SPEC contract names a single string and the user's next action is identical either way. Branching the copy by failure kind is precisely the pressure that leaks `SqliteException: disk I/O error` onto a user's screen, so both catch blocks call the same `_fail()`.
- **Foreign keys need no migration.** `PRAGMA foreign_keys` is per-connection state, not schema, and Plan 1's `CREATE TABLE` already declared `REFERENCES sessions(id)`. SQLite also does not re-validate existing rows when the pragma is enabled, so a database created by Plan 1 cannot fail to open because of this — it simply starts enforcing on the next write. No version bump, no `onUpgrade`.
- **A save failure never auto-restarts recording.** `stopRecording()` returns after `_fail()` instead of falling through to `startNewQuestion()`. If the disk is genuinely full, an auto-restart would loop record → fail → record forever; the user's Retry tap is the only way forward (T-03-03).
- **The sweep's safety is its ordering, not a lock.** A file currently being recorded is by definition unreferenced by the database, so a concurrent sweep would delete it. `_bootstrap()` therefore awaits the sweep to completion before `startNewQuestion()` picks a filename, and that contract is written into the function's doc comment so a future caller cannot violate it silently.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] A force-kill mid-recording left a permanent orphaned audio file**

- **Found during:** Task 2
- **Issue:** The plan's must-have requires that a force-kill mid-recording leave "no session row, no question_answers row, **no orphaned audio file**", and Task 2's D-07 human-check says to confirm "no orphaned file". Neither Plan 1 nor Plan 3's task actions delete anything from disk. `package:record` streams into its output file while recording, so every kill mid-recording (and every denied-then-abandoned attempt) left a partial `.m4a` that nothing referenced and nothing would ever remove — invisible in History, but a permanent unbounded disk leak, and the human-check as written would have failed on inspection.
- **Fix:** Added `DatabaseHelper.listReferencedAudioPaths()` and `pruneOrphanRecordings()`, swept once from `PracticeScreen._bootstrap()` and awaited to completion before the first recording is armed.
- **Files modified:** `lib/db/database_helper.dart`, `lib/utils/audio_paths.dart`, `lib/screens/practice_screen.dart`, `test/utils/audio_paths_test.dart`
- **Verification:** Three new tests, including one asserting the sweep never deletes a file a saved answer points at (the failure mode that would have made this fix worse than the bug).
- **Committed in:** `d35c03e`

**2. [Rule 2 - Missing Critical] A denied permission would still have created the recordings directory and reserved a path**

- **Found during:** Task 1
- **Issue:** The plan places the permission check inside `RecordingService.start()`, but `PracticeState.startNewQuestion()` calls `ensureRecordingsDir()` and assigns `_currentRelativePath` *before* that call. On denial the state would have kept a stale `_currentRelativePath`, which a later `stopRecording()` could have used as the fallback path for a save.
- **Fix:** The catch block clears `_currentRelativePath` before failing, and the entire path-resolution block sits inside the `try` so a filesystem error is handled identically to a permission error.
- **Files modified:** `lib/state/practice_state.dart`
- **Verification:** `test/state/practice_state_test.dart#a denied microphone permission ... writes nothing` asserts the session table stays empty.
- **Committed in:** `b8e4716`

### Planned-scope adjustments (not defects)

- **A third test the plan did not name:** the plan specifies tests for permission-denial and retry. A save-failure test (`FailingDatabaseHelper`) was added because the plan also *implements* save-failure handling, and the "does not auto-restart recording" behaviour is the part most likely to regress silently. It doubles as the proof that an exception's text — deliberately seeded with a device file path — never reaches `errorMessage`.
- **Foreign-key test written against `DatabaseHelper`'s own connection** rather than the plan's "apply the pragma the same way `onConfigure` applies it" in the test. Re-applying the pragma in the test would have proven only that SQLite works; querying `helper.database` proves that *this class* configures it.
- **`test/utils/audio_paths_test.dart` is a new file** not in the plan's `files_modified` list — a consequence of deviation 1. The sweep lives in `lib/utils/`, so its tests belong beside the other utils rather than in the DB test file.

---

**Total deviations:** 2 auto-fixed (both missing-critical) + 3 documented scope adjustments
**Impact on plan:** Deviation 1 is what makes the plan's own force-kill must-have literally true rather than true-only-in-the-database. Deviation 2 closes a stale-path window the plan's ordering left open. No architectural change, no new dependency, no behaviour removed.

## Issues Encountered

None blocking. Worth flagging for Phase 2: the orphan sweep is safe today because there is exactly one `PracticeScreen`, created once at app start, and it awaits the sweep before arming the microphone. Phase 2 introduces a Setup screen ahead of the practice loop — whoever moves or re-runs the bootstrap must preserve that ordering, or the sweep will delete the recording currently being written.

## Known Stubs

None.

## Deferred / Outstanding Verification

The two human-checks in this plan could not be run here — they require a real device and a real process kill, and are the phase's defining risk (D-07):

- **D-07 case 1:** start a recording, force-kill before Stop, relaunch → History must show no new session and the recordings directory must contain no leftover file.
- **D-07 case 2:** fully answer one question, force-kill, relaunch → that answer must still be in History and still replayable.
- **Mic-permission denial on device:** revoke the microphone, open the Practice screen → the banner must appear with the question card still visible, and Retry must work after granting.

These are recorded as `status: unknown` coverage items D1, D3, D6, D7 and D8 above, and remain outstanding for phase verification.

## Threat Flags

None. This plan adds no network surface, no new permission, no new dependency, and no new file-system location — it removes files from a directory the app already owns and tightens an existing database constraint. The threat register's three `mitigate` dispositions are implemented: T-03-01 (foreign keys enforced), T-03-02 (fixed copy only, exception objects discarded), and T-03-03 remains `accept` and is now provably true — retry is user-initiated only, and the save-failure path deliberately does not restart the loop.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready:**
- The error path is a real, tested state Phase 2 can extend: a new failure (e.g. a Firestore fetch failure) sets `PracticePhase.error` with its own copy and inherits the banner and Retry for free.
- Foreign-key enforcement is on before Phase 2 starts writing multiple `question_answers` rows per session, so a mis-scoped multi-row insert fails loudly at the DB layer instead of creating orphans.

**Outstanding:**
- The D-07 force-kill test (both cases) and the on-device permission-denial check — see Deferred / Outstanding Verification. Phase 1 should not be called verified until these are run.

## Self-Check: PASSED

All 8 claimed files (1 created, 7 modified) exist on disk. Both task commits (`b8e4716`, `d35c03e`)
are present in `git log`. `flutter analyze` reports "No issues found!" and `flutter test` reports
32/32 passing (24 inherited from Plans 1-2 plus 8 new).

---
*Phase: 01-record-save-replay-a-single-answer-crash-safe*
*Completed: 2026-08-08*
