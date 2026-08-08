---
phase: 01-record-save-replay-a-single-answer-crash-safe
plan: 01
subsystem: database
tags: [flutter, dart, sqflite, record, audioplayers, path_provider, sqflite_common_ffi, changenotifier]

requires: []
provides:
  - "Runnable Flutter app (englishreflex) scaffolded with android/ios mic permissions declared"
  - "sessions + question_answers SQLite schema, locked for Phase 2 to extend without migration"
  - "DatabaseHelper.insertAnsweredSession — session + answer written in ONE transaction, after file finalization"
  - "RecordingService — 60s one-shot auto-stop deadline with first-stop-wins guard"
  - "AudioPlayerService — local-file playback, optional await-to-completion for auto-replay"
  - "PracticeState (ChangeNotifier) — the record -> save -> replay -> reset loop"
  - "PracticeScreen, HistoryScreen, SessionDetailScreen with tap-to-replay"
  - "documentsDirProvider seam making all app-local path resolution testable"
affects: [02-timed-multi-question-loop, 03-firestore-question-bank, 04-json-import]

actuals:
  tokens: 69000
  tasks: 3
  commits: 3

tech-stack:
  added:
    - "record ^7.1.1"
    - "audioplayers ^6.8.1"
    - "sqflite ^2.4.3"
    - "path_provider ^2.1.6"
    - "path ^1.9.0"
    - "sqflite_common_ffi ^2.3.0 (dev)"
  patterns:
    - "Manual constructor injection of services into a single ChangeNotifier (no DI package)"
    - "Crash-safety write ordering: finalize audio file -> single DB transaction -> replay"
    - "Relative audio paths in the DB, resolved to absolute only at play time"
    - "Overridable provider globals (documentsDirProvider, sqflite databaseFactory) as the test seam for platform-only APIs"
    - "Lazily-constructed plugin objects (late final) so test subclasses never touch a platform channel"

key-files:
  created:
    - lib/db/database_helper.dart
    - lib/state/practice_state.dart
    - lib/services/recording_service.dart
    - lib/services/audio_player_service.dart
    - lib/utils/audio_paths.dart
    - lib/utils/date_format.dart
    - lib/models/session.dart
    - lib/models/question_answer.dart
    - lib/data/questions.dart
    - lib/screens/practice_screen.dart
    - lib/screens/history_screen.dart
    - lib/screens/session_detail_screen.dart
    - test/db/database_helper_test.dart
    - test/state/practice_state_test.dart
    - test/models/session_test.dart
    - test/models/question_answer_test.dart
  modified:
    - lib/main.dart
    - pubspec.yaml
    - android/app/src/main/AndroidManifest.xml
    - ios/Runner/Info.plist
    - .claude/CLAUDE.md

key-decisions:
  - "The 60s deadline invokes the onAutoStop callback rather than stopping the recorder itself, so exactly one consumer receives the finalized path and the auto-stop path saves like a manual stop"
  - "AudioPlayerService.play gained an awaitCompletion flag; the practice loop waits for the replay to finish before re-arming the mic, so the next recording never captures the replay"
  - "A single overridable documentsDirProvider in lib/utils/audio_paths.dart is the seam for both audio files and the DB file, mirroring sqflite's databaseFactory override so flutter test can run the real write path"
  - "Plugin objects (AudioRecorder, AudioPlayer) are constructed lazily so test fakes subclassing the services never initialise a platform channel"
  - "Hand-written formatSessionTimestamp instead of adding intl — one format, no localisation in this milestone"

patterns-established:
  - "Crash-safety ordering: audio file finalized -> insertAnsweredSession in one db.transaction() -> replay. Phase 2 reuses this verbatim for multi-answer sessions."
  - "Typed sqflite insert()/query() with whereArgs everywhere; no string-interpolated SQL."
  - "Screens own their own AudioPlayerService and dispose it; state lives in one ChangeNotifier per screen-flow."

requirements-completed: [LOOP-03, LOOP-04, LOOP-05, LOOP-06, PERSIST-01, PERSIST-02, HIST-01, HIST-02, HIST-03, HIST-04]

coverage:
  - id: D1
    description: "Recording begins automatically the instant PracticeScreen opens, with no button tap (LOOP-03, D-01)"
    requirement: "LOOP-03"
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#startNewQuestion begins recording immediately, with no user action"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: open app, confirm question shown and recording active with no tap"
        status: unknown
    human_judgment: true
    rationale: "Real microphone capture and the mic-permission dialog cannot be exercised on the test host; must be seen on a device."
  - id: D2
    description: "Recording auto-stops at 60 seconds when the user does not tap Stop (LOOP-04, D-09)"
    requirement: "LOOP-04"
    verification:
      - kind: manual_procedural
        ref: "flutter run on device: start a recording and wait 60s without tapping Stop"
        status: unknown
    human_judgment: true
    rationale: "A real 60s wall-clock deadline against a live recorder needs a device; the Timer construct is present but its firing is not asserted."
  - id: D3
    description: "A large, always-visible Stop button ends the recording early and finalizes it (LOOP-05)"
    requirement: "LOOP-05"
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#stopRecording saves BEFORE replaying, then resets and re-arms"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: tap STOP mid-recording"
        status: unknown
    human_judgment: true
    rationale: "Button size/visibility is a visual judgment; final styling lands in Plan 2."
  - id: D4
    description: "The just-recorded answer auto-replays the instant recording stops, then the screen resets to a fresh question and records again (LOOP-06, D-03/D-10)"
    requirement: "LOOP-06"
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#stopRecording saves BEFORE replaying, then resets and re-arms"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: confirm audible playback then a new question with recording re-armed"
        status: unknown
    human_judgment: true
    rationale: "Audible playback and the absence of mic feedback during replay can only be judged on a device."
  - id: D5
    description: "Session + its one answer row are written in a SINGLE transaction only after the audio file is finalized (PERSIST-01, D-08)"
    requirement: "PERSIST-01"
    verification:
      - kind: unit
        ref: "test/db/database_helper_test.dart#insertAnsweredSession writes exactly one session and one linked answer"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#stopRecording saves BEFORE replaying, then resets and re-arms"
        status: pass
      - kind: unit
        ref: "test/state/practice_state_test.dart#a losing stop signal writes nothing — first stop wins"
        status: pass
    human_judgment: false
  - id: D6
    description: "A force-kill mid-session leaves every already-answered question intact in history, and an in-flight recording leaves no trace (PERSIST-02, D-07)"
    requirement: "PERSIST-02"
    verification:
      - kind: manual_procedural
        ref: "Record an answer, force-kill the app process, relaunch, open History"
        status: unknown
    human_judgment: true
    rationale: "D-07 explicitly requires a real force-kill-and-relaunch test; this is the phase's defining risk and cannot be inferred from unit tests."
  - id: D7
    description: "History lists every session most-recent-first, or the 'No recordings yet' empty state (HIST-01)"
    requirement: "HIST-01"
    verification:
      - kind: unit
        ref: "test/db/database_helper_test.dart#listSessions orders sessions most-recent-first"
        status: pass
      - kind: unit
        ref: "test/db/database_helper_test.dart#listSessions returns nothing when no answer has been recorded"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: History with zero sessions, then with two"
        status: unknown
    human_judgment: true
    rationale: "Empty-state copy rendering and row layout are visual; the underlying queries are unit-proven."
  - id: D8
    description: "Session detail shows only that session's answers, in insertion order, titled 'Session — {date, time}' (HIST-02)"
    requirement: "HIST-02"
    verification:
      - kind: unit
        ref: "test/db/database_helper_test.dart#listAnswersForSession is scoped strictly to the requested session"
        status: pass
      - kind: unit
        ref: "test/db/database_helper_test.dart#listAnswersForSession returns an empty list for an unknown session id"
        status: pass
    human_judgment: false
  - id: D9
    description: "Tapping a question row in session detail plays that row's own recording (HIST-03)"
    requirement: "HIST-03"
    verification:
      - kind: manual_procedural
        ref: "flutter run on device: open a session, tap the question row"
        status: unknown
    human_judgment: true
    rationale: "Requires real recorded audio on a device; playback is not observable on the test host."
  - id: D10
    description: "History entries and their recordings survive app restarts — audio paths are stored relative and re-resolved at play time (HIST-04)"
    requirement: "HIST-04"
    verification:
      - kind: unit
        ref: "test/state/practice_state_test.dart#stopRecording saves BEFORE replaying, then resets and re-arms"
        status: pass
      - kind: unit
        ref: "test/models/question_answer_test.dart#audioPath stays relative — never an absolute device path"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: record, fully quit, relaunch, open History and replay"
        status: unknown
    human_judgment: true
    rationale: "Durability across a real process restart needs a device run."
  - id: D11
    description: "Both platforms declare the microphone permission package:record requires"
    verification:
      - kind: other
        ref: "grep -c android.permission.RECORD_AUDIO android/app/src/main/AndroidManifest.xml (=1); grep -c NSMicrophoneUsageDescription ios/Runner/Info.plist (=1)"
        status: pass
    human_judgment: false

duration: 811min
completed: 2026-08-08
status: complete
---

# Phase 1 Plan 01: Walking Skeleton — Record, Save & Replay Summary

**A runnable Flutter app whose Practice screen auto-records on open, writes the session + answer in one SQLite transaction only after the audio file is finalized, auto-replays it, resets to a fresh question, and surfaces every past recording in a History list with tap-to-replay.**

## Performance

- **Duration:** 811 min wall clock (includes a long idle gap; the three task commits landed within 4 minutes of each other)
- **Started:** 2026-08-07T14:59:42Z
- **Completed:** 2026-08-08T04:31:02Z
- **Tasks:** 3
- **Files modified:** 146 (78 hand-authored/edited + Flutter scaffold + pubspec.lock)

## Accomplishments

- Scaffolded the `englishreflex` Flutter project and locked the `sessions` + `question_answers` schema Phase 2 will extend without a migration (D-05).
- Wired the full reflex loop end-to-end: question appears → recording auto-starts → manual Stop or the 60 s deadline finalizes the file → session + answer committed in one transaction → auto-replay → fresh question, recording re-armed.
- Built History (sessions most-recent-first, with the exact empty-state copy) and Session detail (`Session — Aug 7, 2:45 PM`) with per-answer tap-to-replay.
- Proved the crash-safety-critical ordering with automated tests that run the *real* `DatabaseHelper` against an FFI SQLite engine — the DB row is committed before playback begins, and a losing stop signal writes nothing at all.
- Declared `RECORD_AUDIO` (Android) and `NSMicrophoneUsageDescription` (iOS); recordings stay in app-private storage with no external-storage or network permission requested.

## Task Commits

1. **Task 1 (tracer): Scaffold + record → save → replay → reset loop** - `2be3882` (feat)
2. **Task 2: History list + session detail with tap-to-replay** - `f415e6f` (feat)
3. **Task 3: State-machine/DB tests + mic-permission manifests** - `5641491` (test)

## Files Created/Modified

- `lib/db/database_helper.dart` - Schema creation plus `insertAnsweredSession` (one transaction), `listSessions` (id DESC), `listAnswersForSession` (session-scoped, id ASC)
- `lib/state/practice_state.dart` - `PracticePhase` enum and the whole loop; services injected via constructor
- `lib/services/recording_service.dart` - `package:record` wrapper, 60 s one-shot deadline, first-stop-wins guard
- `lib/services/audio_player_service.dart` - `package:audioplayers` wrapper with optional await-to-completion playback
- `lib/utils/audio_paths.dart` - `documentsDirProvider` seam, `ensureRecordingsDir`, `toAbsolutePath`, `recordingRelativePath`
- `lib/utils/date_format.dart` - `formatSessionTimestamp` producing `Aug 7, 2:45 PM`
- `lib/models/session.dart`, `lib/models/question_answer.dart` - Row models with `fromMap`/`toMap`
- `lib/data/questions.dart` - Five hardcoded rotating prompts (D-02)
- `lib/screens/practice_screen.dart` - Auto-starts recording in `initState`, STOP button only while recording, "Playing your answer…" during replay, History nav
- `lib/screens/history_screen.dart`, `lib/screens/session_detail_screen.dart` - History list, empty state, per-answer replay
- `test/db/database_helper_test.dart`, `test/state/practice_state_test.dart` - Crash-safety and ordering proofs against the FFI SQLite engine
- `test/models/*_test.dart` - Model round-trip tests
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` - Microphone permissions
- `.claude/CLAUDE.md` - Added `path` and `sqflite_common_ffi` to the stack tables as instructed by the plan

## Decisions Made

- **Auto-stop delegates the stop.** The 60 s `Timer` invokes `onAutoStop` (which calls `stop()` itself) rather than stopping the recorder directly, so the finalized path reaches exactly one consumer and the auto-stop path saves identically to a manual stop.
- **Replay is awaited to completion before re-arming.** Otherwise the next recording would start while the answer was still audible and the microphone would capture the replay.
- **One documents-directory seam.** `documentsDirProvider` in `lib/utils/audio_paths.dart` backs both the DB file path and the recordings directory, so a single override lets `flutter test` exercise the real write path (`path_provider` has no test-host implementation).
- **No `intl`.** A 12-line `formatSessionTimestamp` covers the single required format.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 60 s auto-stop would have saved nothing**
- **Found during:** Task 1
- **Issue:** The plan specified the timer call `stop()` internally *and then* invoke `onAutoStop`. Because `stop()` is guarded against a second call, `PracticeState.stopRecording()` (the callback) would have received `null` and skipped the DB write — every unattended recording would have been silently discarded.
- **Fix:** The deadline now invokes `onAutoStop` and lets that callback own the stop; an internal `stop()` remains only as a fallback when no callback was supplied.
- **Files modified:** `lib/services/recording_service.dart`
- **Verification:** `test/state/practice_state_test.dart` asserts the stop → save → play → start ordering the callback drives.
- **Committed in:** `2be3882`

**2. [Rule 1 - Bug] Auto-replay would have been recorded by the next take**
- **Found during:** Task 1
- **Issue:** `AudioPlayer.play()` resolves when playback *starts*. Following the plan literally (`await play(...)` then `startNewQuestion()`) would have re-armed the microphone while the answer was still playing, and contradicted the must-have "after auto-replay finishes, the screen resets".
- **Fix:** Added `awaitCompletion` to `AudioPlayerService.play`; the practice loop awaits `onPlayerComplete` before resetting. History tap-to-replay keeps the fire-and-forget default.
- **Files modified:** `lib/services/audio_player_service.dart`, `lib/state/practice_state.dart`
- **Verification:** `flutter analyze` clean; ordering asserted in `practice_state_test.dart`. Audible confirmation is a device UAT item (D4).
- **Committed in:** `2be3882`

**3. [Rule 3 - Blocking] `path_provider` is unavailable under `flutter test`**
- **Found during:** Task 1
- **Issue:** Task 3's plan text assumed `DatabaseHelper` needed "zero changes" to run under the FFI engine, but both `DatabaseHelper` and the recordings directory call `getApplicationDocumentsDirectory()`, which throws on the test host — the crash-safety tests could not have run.
- **Fix:** Introduced one overridable `documentsDirProvider` global in `lib/utils/audio_paths.dart` (deliberately mirroring sqflite's own `databaseFactory` override), used by both the DB path and the recordings directory.
- **Files modified:** `lib/utils/audio_paths.dart`, `lib/db/database_helper.dart`
- **Verification:** 11 DB/state tests run against the real write path and pass.
- **Committed in:** `2be3882`

**4. [Rule 3 - Blocking] Task 1 referenced a screen Task 2 was to create**
- **Found during:** Task 1
- **Issue:** Task 1 wires the History `IconButton` to `HistoryScreen`, which the plan assigns to Task 2 — the project would not have compiled at the Task 1 commit.
- **Fix:** Created a minimal `HistoryScreen` with its final constructor signature in Task 1; Task 2 replaced the body. No stub remains.
- **Files modified:** `lib/screens/history_screen.dart`
- **Verification:** `flutter analyze` reported zero issues at both commits.
- **Committed in:** `2be3882`, superseded by `f415e6f`

**5. [Rule 3 - Blocking] Plugin `dispose()` signatures are async**
- **Found during:** Task 1
- **Issue:** The plan specified `void dispose()` on both services, but `AudioRecorder.dispose()` and `AudioPlayer.dispose()` both return `Future<void>`.
- **Fix:** Both service `dispose()` methods return `Future<void>`.
- **Files modified:** `lib/services/recording_service.dart`, `lib/services/audio_player_service.dart`
- **Verification:** `flutter analyze` clean.
- **Committed in:** `2be3882`

**6. [Rule 2 - Missing Critical] A null finalized path would have frozen the screen**
- **Found during:** Task 1
- **Issue:** `stopRecording()` sets `phase = saving` before awaiting `stop()`. The plan said to treat a `null` return as a bare no-op, which would have left the UI stuck on "saving" with no control visible.
- **Fix:** A `null` path resets `phase` to `idle` and notifies listeners, writing nothing to the DB.
- **Files modified:** `lib/state/practice_state.dart`
- **Verification:** `practice_state_test.dart#a losing stop signal writes nothing — first stop wins`.
- **Committed in:** `2be3882`

### Planned-scope adjustments (not defects)

- **New file `lib/utils/date_format.dart`** (not in the plan's file list): the `Session — {date, time}` format is needed by both History rows and the detail title. A shared util avoids screens importing screens and avoids adding `intl`.
- **Lazy plugin construction:** `AudioRecorder`/`AudioPlayer` are `late final` so the Task 3 fakes (which subclass the real services) never construct a platform channel.
- **History row affordance:** UI-SPEC calls for an accent play icon on history rows, but tapping a session row *navigates* rather than plays. Used `chevron_right` there and kept the play icon on the detail rows that actually play. Plan 2 owns final styling and can reconcile.
- **Desktop/web scaffold retained:** `flutter create .` generated `linux/`, `macos/`, `web/`, `windows/`. These were committed as generated rather than pruned, since removing platforms is a structural decision outside this plan's scope.

---

**Total deviations:** 6 auto-fixed (2 bugs, 3 blocking, 1 missing-critical) + 4 documented scope adjustments
**Impact on plan:** Deviations 1, 2 and 6 fix behaviour the plan's literal text would have shipped broken (silent data loss on auto-stop, mic capturing the replay, a frozen screen). Deviation 3 is what makes the crash-safety tests possible at all. No scope creep.

## Issues Encountered

- `flutter analyze` flagged `unnecessary_import` on `package:sqflite/sqflite.dart` in both new test files (`sqflite_common_ffi` re-exports `databaseFactory`). Removed both imports; analyze is clean.

## Known Stubs

None. Theming (warm palette, Baloo 2, mascot) is deliberately deferred to Plan 2 of this phase, and the timed multi-question loop to Phase 2 — both are planned scope, not placeholders.

## Threat Flags

None — no new security-relevant surface beyond the plan's `<threat_model>`. The app makes zero network calls in this phase, requests only `RECORD_AUDIO`/microphone, writes exclusively to app-private storage, and uses typed sqflite `insert()`/`query()` with `whereArgs` throughout.

## User Setup Required

None - no external service configuration required. Running on a device requires only accepting the microphone permission prompt at first launch.

## Next Phase Readiness

**Ready:**
- Schema, service boundaries and the crash-safety write ordering are locked; Plan 2 (theming) and Phase 2 (multi-question loop) both build on them without restructuring.
- `PracticeState` is the single extension point for Phase 2's countdowns and question counter; `SessionDetailScreen` already renders a list and needs no change to show many answers per session.

**Outstanding — device UAT required before this phase can be called verified:**
- PERSIST-02 force-kill-and-relaunch test (D-07) — the phase's defining risk, explicitly not inferable from unit tests.
- Real microphone capture, the 60 s auto-stop firing, audible auto-replay with no mic feedback, and History/detail replay on a real device (coverage items D1–D4, D7, D9, D10).

## Self-Check: PASSED

All 16 claimed created files and 5 modified files exist on disk. All four claimed commits
(`2be3882`, `f415e6f`, `5641491`, `530f5c0`) are present in `git log`. `flutter analyze`
reports zero issues and `flutter test` reports 17/17 passing.

---
*Phase: 01-record-save-replay-a-single-answer-crash-safe*
*Completed: 2026-08-08*
