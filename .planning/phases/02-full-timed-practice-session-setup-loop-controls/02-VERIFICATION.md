---
phase: 02-full-timed-practice-session-setup-loop-controls
verified: 2026-08-09T04:26:36Z
status: passed
score: 16/16 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: null
deferred:

  - truth: "Questions are filtered by the selected topics and CEFR level (PlaceholderQuestionSource returns the whole bank unfiltered)"
    addressed_in: "Phase 3"
    evidence: "Phase 3 Success Criterion 2: 'Starting a session fetches only the questions matching the selected topics and CEFR level from Firestore.' The seam (QuestionSource) already exists and is the documented Phase 3 swap point."
human_verification:

  - test: |
      D-31 real-device interruption check (harvested from 02-05-PLAN <human-check>).
      On a REAL device (not an emulator), with a real SIM:

      1. Start a session with answer length 60 s and begin recording an answer.
      2. Call the device from another phone and ANSWER the call. Speak ~10 s, hang up.
      3. Return to the app.
      4. Tap RESUME and confirm the session continues from where it stopped.
      5. Repeat with backgrounding instead of a call: press Home mid-recording, wait 10 s, reopen.
      6. Start a session and leave the phone untouched longer than the OS screen timeout.
    expected: |
      Steps 3/5: the session is parked paused, the banner reads "Paused — your answer was
      saved when the app was interrupted.", recording has NOT resumed by itself, and the
      partial answer is already in Exercise History.
      Step 4: the session continues from where it stopped, no answer replayed from the start.
      Step 6: the screen stays on for the whole session and turns off normally afterwards.
    why_human: |
      Research assumption A1 — that an iOS backgrounding may suspend the isolate before the
      commit lands — is unfalsifiable on the host. The `record` package has a documented iOS
      AudioInterruptionMode rough edge (-10868). Host tests prove the handler, its ordering
      and the commit; they cannot prove the OS delivers the signal with enough runway.
      Step 5 exists specifically to settle A1. Step 6 also settles the wakelock (D-30),
      whose host test proves only that the seam is called.

  - test: "Run a full configured session on a real device with the real microphone: set d to 120 s and to 10 s, and let each auto-stop fire."
    expected: "Recording auto-stops at the configured d, the on-screen readout hits 0:00 at the same moment, and the answer is playable from History."
    why_human: "The `d` deadline is host-tested against a fake recorder backend. Real capture, real m4a finalization and real playback at the new 10–120 s range have never run on hardware. Phase 1 already carries device-UAT-pending on LOOP-03/LOOP-06 for the same reason; Phase 2 widens the range."

  - test: "Visually review Setup, both countdown surfaces, the recording surface, the paused surface, the stop dialog and the completion state against 02-UI-SPEC.md on a real device."
    expected: "Colour roles, the Baloo 2 headings, the 96px ring vs the 128px glyph distinction (D-22), touch-target floors and the cartoon-like feel match the UI-SPEC."
    why_human: "Visual appearance, perceived distinctness of the two countdowns, and 'playful/colourful' quality are not assertable by widget tests."

  - test: "Review the 8 judgment-tier prohibitions listed in the Prohibitions section of this report and confirm the LLM-judge verdicts."
    expected: "Each MUST-NOT is confirmed as not having happened."
    why_human: "unverified-prohibition — human review recommended. These prohibitions carry no `verification: test` marker and no wired negative-test enforcement, so the verdicts below are NON-AUTHORITATIVE LLM judgements backed by codebase evidence, never a green automated pass."
---

# Phase 02: Full Timed Practice Session (Setup, Loop & Controls) — Verification Report

**Phase Goal:** User can configure a complete practice session (level, question count, timings, replay toggle) and run it through the full timed reflex-drill loop across multiple questions, with pause/resume and stop-with-confirmation available at all times.
**Verified:** 2026-08-09T04:26:36Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **SC1** — user configures level, count (1-100), `t`, `d`, `r`; Start disabled unless valid | VERIFIED | `setup_screen.dart:199-251` — three `_SettingSlider`s with min/max/divisions `1/100/99`, `3/30/27`, `10/120/110`; `_LevelChips` over `kLevels` A1–C2; `_ReplayToggle`. `:554` `onPressed: canStart ? onStart : null` (genuinely null, not a swallowed tap). Tests: `setup_screen_test.dart:188,247,297,313,334,351,387,421` |
| 2 | **SC2** — 3 s countdown → per-question live `t` countdown → recording → 3 s countdown into the next question | VERIFIED | `practice_state.dart:561 _enterGetReady` → `:584 _enterReading` → `:623 _startNewQuestion` → `:723 stopRecording` tail at `:858-859` re-enters get-ready. Tracer test `practice_session_test.dart:425` walks Setup→3→2→1→`t`→record; LOOP-07 tests `:642,676,776` assert the exact phase sequence |
| 3 | **SC3** — session auto-completes once `question_count` answers are given | VERIFIED | `practice_state.dart:849` `if (answeredCount >= config.questionCount) _enterComplete()`. Tests `:703` (3-question session lands in `complete` with 3 rows) and `:728` (bank+1 length) |
| 4 | **SC4** — app bar Pause/Resume + Stop present throughout; pause freezes; Stop confirms | VERIFIED | `practice_screen.dart:306-350` — `actions` is non-null in every phase but `complete`; Pause `onPressed: _state.canPause ? … : null`, Stop `onPressed` unconditional. Freeze tests `practice_session_test.dart:950,977,1005,1047`; dialog tests `practice_screen_test.dart:167-291` |
| 5 | Setup is the app home; Start carries one immutable `SessionConfig` (D-28/D-18) | VERIFIED | `main.dart:132 home: const SetupScreen()`; `setup_screen.dart:129-149` builds `SessionConfig` and pushes `PracticeScreen(config:)`. `session_config.dart` is `@immutable` with no `toMap`/`fromMap`. Test `setup_screen_test.dart:421,466` |
| 6 | **LOOP-02 / D-20** — the `t` countdown runs fully to zero before the recorder is armed; no STOP and no listening mascot while the mic is cold | VERIFIED | `arming` is a distinct phase (`practice_state.dart:630`); `recording` published only at `:660` after `recordingService.start()` returns. Test `:497-514` asserts `calls` is empty at t-1 and `['start']` only after the final second |
| 7 | **SETUP-05 / D-21** — auto-stop at the session `d`, and the readout is the same object as the deadline | VERIFIED | `practice_state.dart:649 maxDuration: Duration(seconds: config.answerSeconds)`; `recording_service.dart:261-273` — one `PausableCountdown` feeds both `onTick` and `onElapsed`. Test `:516` asserts `lastMaxDuration == kDefaultAnswerSeconds`, not the Phase 1 fixed 60 s |
| 8 | **SETUP-06** — with `r` ON the inter-question countdown starts only after replay resolves; with `r` OFF the player is never touched | VERIFIED | `practice_state.dart:825-844` guarded by `config.autoReplay`; get-ready is entered after the awaited `play`. Tests `:642` (ordering assertion `replaying` index < last `getReady` index) and `:676` (`calls` never contains `play`) |
| 9 | **D-23** — a session longer than the bank cycles it in sequential order rather than capping | VERIFIED | `questions.dart:96 questionAt(bank, i) => bank[i % bank.length]`. Test `:728` asserts the wrap at the exact boundary (`answers.last == kQuestions.first`) |
| 10 | The reported count never overstates what was committed | VERIFIED | `practice_state.dart:794` `answeredCount += 1` sits AFTER `appendAnswer` returns; `questionNumber` is a separate field (`:119` vs `:126`). Test `:776` (`k` vs count divergence) and `:796` (save failure at k leaves k-1) |
| 11 | **CTRL-04** — pause freezes all four clock kinds; resume continues in place, never restarts | VERIFIED | One `pause()`/`resume()` pair, `practice_state.dart:278-387`, switching over the four pausable phases; `PausableCountdown.resume()` never restarts the current second (`pausable_countdown.dart:75-78`). Four tests: `:950` (3·2·1), `:977` (`t`), `:1005` (`d` deadline), `:1047` (replay bound) |
| 12 | The paused state is published only on a CONFIRMED recorder pause; an unconfirmed pause shows the error banner, never a paused banner | VERIFIED | `recording_service.dart:307-314` — asks `_backend.isPaused()` and does not infer success from the absence of a throw; `practice_state.dart:308-313` routes `false` to `_fail()`. Test `:1088`; on-screen test `:1234` also asserts the pulse ring is off while paused |
| 13 | **CTRL-02/CTRL-03/D-29** — exactly ONE dialog and ONE early-exit path; system Back is routed into it; interception released at completion | VERIFIED | `grep showDialog lib/` returns exactly one hit (`practice_screen.dart:228`); `completeEarly` has exactly one call site (`:245`); `_requestStop()` is the sole handler for both the Stop action (`:348`) and `PopScope.onPopInvokedWithResult` (`:281`), guarded by `_confirmingStop`. `canPop: isComplete` (`:274`). Tests `practice_screen_test.dart:167,190,207,235,267,294,328` |
| 14 | **D-31** — an interruption finalizes and commits the in-flight answer FIRST, then parks paused; the app never auto-resumes | VERIFIED (host) | `practice_state.dart:411-454` — one handler, `_interruptionPending` set before any await, `stopRecording()` reused verbatim; commit at `:762` happens before the `:802` park. Both producers wired at `practice_screen.dart:113-127`. Tests `:1395` (backgrounding), `:1440` (answered call), `:1458` (both collapse onto one handler), `:1491`, `:1519`. **Device-level residual risk carried to human verification** |
| 15 | **D-30** — wakelock held for the session, released on end / dispose / background; failure is silent | VERIFIED | `practice_screen.dart:101,113,120,142-146,162-165` — one `_setWake` pair with try/catch + `debugPrint`, `_wakeReleased` latch prevents late re-acquire. Tests `practice_screen_test.dart:351,368,377,392` |
| 16 | **PERSIST-01 across N** — a force-stop at question k leaves exactly k committed answers under exactly one session row | VERIFIED | `database_helper.dart:159-177` — `appendAnswer` is its own transaction per answer, lazy session creation (D-26). Test `practice_session_test.dart:1613` runs against REAL SQLite (`sqfliteFfiInit`), closes the handle and reopens to simulate a process kill |

**Score:** 16/16 truths verified (0 present, behavior-unverified)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Questions filtered by selected topics and CEFR level — `PlaceholderQuestionSource.questionsFor()` returns the whole bank unfiltered | Phase 3 | Phase 3 SC2: "Starting a session fetches only the questions matching the selected topics and CEFR level from Firestore." The `QuestionSource` seam (`questions.dart:67`) exists precisely so Phase 3 changes the data source without editing `practice_state.dart`. SETUP-02's requirement text is "user can SELECT a CEFR level", which is satisfied |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/models/session_config.dart` | Immutable SessionConfig | VERIFIED | 49 lines, `@immutable`, six required fields, deliberately no serialization |
| `lib/utils/pausable_countdown.dart` | The one timing primitive | VERIFIED | 99 lines, `start/pause/resume/cancel`, terminal `_finished`, cancel-before-callback |
| `lib/screens/setup_screen.dart` | Full config form + gated Start | VERIFIED | 568 lines, all six settings, `ChoiceChip`, pinned footer, imported by `main.dart` |
| `lib/data/questions.dart` | ~20 prompts, `kSubjects`, `questionAt`, `QuestionSource` | VERIFIED | 96 lines, 20 prompts, 5 subjects, cycling accessor |
| `lib/state/practice_state.dart` | The full session loop | VERIFIED | 861 lines, 10 phases, pause/resume, interruption handler, completion |
| `lib/widgets/phase_control.dart` | Total phase→control map | VERIFIED | 305 lines, all 10 phases keyed, totality asserted in test |
| `lib/widgets/countdown_ring.dart` | 96px determinate ring | VERIFIED | 93 lines, `_diameter = 96`, determinate arc, used by `practice_screen.dart:392` |
| `lib/db/database_helper.dart` | `appendAnswer` + `findSession` | VERIFIED | 260 lines, per-answer transaction, lazy session row |
| `lib/services/recording_service.dart` | Confirmed pause/resume + `onPausedChanged` | VERIFIED | 368 lines, `isPaused()`-backed confirmation, pausable deadline |
| `lib/services/audio_player_service.dart` | Pausable playback + `replayCompletionTimeoutFor` | VERIFIED | 220 lines, `PausableCountdown` bound rather than `Future.timeout` |
| `lib/services/screen_wake_controller.dart` | Injectable wake seam | VERIFIED | 51 lines, `abstract class ScreenWakeController` + production impl |
| `pubspec.yaml` | `wakelock_plus: ^1.7.0` | VERIFIED | line 43, exact pin required by the D-31 background-release path |
| `test/state/practice_session_test.dart` | End-to-end loop tests | VERIFIED | 1670 lines (min 60) |
| `test/utils/pausable_countdown_test.dart` | Tick/pause/resume/cancel | VERIFIED | 163 lines (min 40) |
| `test/widgets/countdown_ring_test.dart` | Ring rendering | VERIFIED | 84 lines (min 30) |
| `test/screens/setup_screen_test.dart` | Defaults, ranges, gate | VERIFIED | 529 lines (min 80) |
| `test/services/screen_wake_controller_test.dart` | Channel-free seam tests | VERIFIED | 73 lines (min 25) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `setup_screen.dart` | `practice_screen.dart` | `PracticeScreen(config:)` | WIRED | `:142` inside `Navigator.push` |
| `practice_state.dart` | `pausable_countdown.dart` | one instance per transition, cancelled in dispose | WIRED | `:567`, `:591`; `dispose()` at `:251` |
| `practice_state.dart` | `database_helper.dart` | `appendAnswer` after finalize | WIRED | `:762`, strictly after `recordingService.stop()` at `:730` |
| `practice_state.dart` | `recording_service.dart` | `maxDuration: config.answerSeconds` | WIRED | `:649` |
| `main.dart` | `setup_screen.dart` | `home: const SetupScreen()` | WIRED | `:132` |
| `practice_state.dart` | `audio_player_service.dart` | replay awaited only when `config.autoReplay` | WIRED | `:825` |
| `practice_state.dart` | `questions.dart` | `questionAt(...)` cycles the bank | WIRED | `:536` |
| `practice_screen.dart` | `countdown_ring.dart` | reading phase renders the ring in the anchor slot | WIRED | `:392` |
| `practice_state.dart` | `recording_service.dart` | pause believed only on `isPaused()` | WIRED | `recording_service.dart:310` |
| `practice_state.dart` | `audio_player_service.dart` | pause freezes player + completion bound | WIRED | `:318`, `audio_player_service.dart:172` |
| `practice_screen.dart` | `practice_state.dart` | app-bar Pause/Resume calls the one pair | WIRED | `:311-327`, `Icons.pause_rounded` |
| `practice_screen.dart` | `practice_state.dart` | both producers call one `handleInterruption()` | WIRED | `:115` (onHide) and `:127` (onPausedChanged) |
| `practice_screen.dart` | `screen_wake_controller.dart` | enable/disable wrapped in try-catch | WIRED | `:59-60`, `:133-140` |
| `practice_screen.dart` | `setup_screen.dart` | the confirmed End-session path is the one early pop | WIRED | `:242` `Navigator.of(context).pop()` — reached only from `_requestStop` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `setup_screen.dart` | `_selectedTopics`, `_level`, `_questionCount`, `_thinkingSeconds`, `_answerSeconds`, `_autoReplay` | local `State` fields driven by real widget callbacks; flow into `SessionConfig` at `:129` | Yes | FLOWING |
| `practice_screen.dart` | `_state.countdownSeconds`, `recordingSecondsRemaining`, `currentQuestion`, `answeredCount` | `PracticeState` via `ListenableBuilder`; each written by a live `PausableCountdown` tick or a returned DB commit | Yes | FLOWING |
| `phase_control.dart` | `recordingSecondsRemaining` | passed from `_state` at `practice_screen.dart:436`, not a literal | Yes | FLOWING |
| `countdown_ring.dart` | `remainingSeconds`/`totalSeconds` | `_state.countdownSeconds` / `config.thinkingSeconds` at `:393-394` | Yes | FLOWING |
| `_CompletionHeadline` | `answeredCount` | `_state.answeredCount`, incremented only post-commit | Yes | FLOWING |
| `_StopConfirmationDialog` | `answeredCount` | read from `_state` at `:227` before the dialog opens | Yes | FLOWING |

No hollow props found: no `=\{(\[\]|\{\}|null|''|"")\}` call-site literals feeding a rendering path.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Whole suite runs green | `flutter test` | `00:25 +171: All tests passed!` | PASS |
| Static analysis clean | `flutter analyze` | `No issues found! (ran in 4.0s)` | PASS |
| Exactly one confirmation dialog exists | `grep -rn "showDialog" lib/` | 1 hit (`practice_screen.dart:228`) | PASS |
| Exactly one early-exit path | `grep -rn "completeEarly" lib/` | 1 definition + 1 call site | PASS |
| Phase→control map is total | `grep kPhaseControlKeys.length test/widgets/phase_control_test.dart` | asserted equal to `PracticePhase.values.length` | PASS |
| Release build has no network permission | manifest scan | `main` = `RECORD_AUDIO` only; `INTERNET` confined to debug/profile | PASS |
| No debt markers in phase files | `grep -rnE "TBD\|FIXME\|XXX" lib/ test/` | no matches | PASS |
| Working tree clean, all waves merged | `git status --short` / `git log` | clean; `fbe4207` tracking commit after wave 4 | PASS |

### Probe Execution

Not applicable — no `scripts/*/tests/probe-*.sh` exist in this repo and no plan declares a probe. Step 7c: SKIPPED (no probes declared or discoverable).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SETUP-02 | 02-03 | Select a CEFR level (A1–C2) | SATISFIED | `kLevels` + `_LevelChips`, B1 default; `setup_screen_test.dart:387,403` |
| SETUP-03 | 02-03 | Number of questions 1–100 | SATISFIED | slider `min:1 max:100 divisions:99`; test `:297,351` |
| SETUP-04 | 02-01, 02-03 | Pre-record countdown `t` | SATISFIED | slider `3–30` default 5; consumed at `practice_state.dart:588`; test `:313` |
| SETUP-05 | 02-01, 02-03 | Max recording duration `d` | SATISFIED | slider `10–120` default 60; `maxDuration` at `:649`; test `:334` + `practice_session_test.dart:516` |
| SETUP-06 | 02-02, 02-03 | Auto-replay toggle `r` | SATISFIED | `_ReplayToggle` default ON; gate at `:825`; tests `:642,676` |
| SETUP-07 | 02-01, 02-03 | Start blocked without a topic | SATISFIED | `onPressed: canStart ? onStart : null`; tests `:247` + `practice_session_test.dart:448-465` |
| LOOP-01 | 02-01 | 3-second countdown before the first question | SATISFIED | `_enterGetReady` / `kGetReadySeconds = 3`; test `:476-485` |
| LOOP-02 | 02-01 | Live `t` countdown before recording | SATISFIED | `_enterReading` + `arming` gap; test `:497-514` |
| LOOP-07 | 02-02 | 3-second countdown between questions, after playback | SATISFIED | `stopRecording` tail `:858`; tests `:642,676,776` |
| LOOP-08 | 02-02 | Session completes at `question_count` | SATISFIED | `:849`; tests `:703,728,757` |
| CTRL-01 | 02-04 | Pause/Resume in the app bar at all times | SATISFIED | `practice_screen.dart:309-329` present in every non-complete phase; `canPause` totality test `:1196` |
| CTRL-02 | 02-05 | Stop in the app bar at all times | SATISFIED | `practice_screen.dart:341-349` — unconditional `onPressed`, present in every non-complete phase |
| CTRL-03 | 02-05 | Stop shows a confirmation before ending early | SATISFIED | one `showDialog` at `:228`; tests `practice_screen_test.dart:167,190,207,235,267` |
| CTRL-04 | 02-04 | Pause freezes countdown/recording state | SATISFIED | one `pause()` over four clock kinds; tests `:950,977,1005,1047` |

**Orphaned requirements:** none. The union of the five plans' `requirements:` fields is exactly the 14 IDs the ROADMAP assigns to Phase 2.

### Prohibitions (judgment-tier — NON-AUTHORITATIVE)

None of these carry `verification: test` and none has wired negative-test enforcement, so each verdict below is an LLM judgement backed by codebase evidence. **unverified-prohibition — human review recommended.**

| # | Prohibition | Judge verdict | Evidence |
|---|-------------|---------------|----------|
| 1 | MUST NOT score/rank/grade the user's answer | Holds | Completion renders only "Nice work!" + a bare count (`practice_screen.dart:591-618`). No scoring symbol anywhere in `lib/` |
| 2 | MUST NOT leave the microphone live after dispose or session end | Holds | `practice_screen.dart:171-176` stops before disposing the recorder; `completeEarly` at `practice_state.dart:494` stops too; `RecordingService.dispose` is terminal (`:360`) |
| 3 | MUST NOT report a count higher than what was committed | Holds | `answeredCount` incremented only post-`appendAnswer` (`:794`); test `:796` |
| 4 | MUST NOT persist/cache/log/transmit the session config (D-18) | Holds | No `shared_preferences` dependency; `SessionConfig` has no `toMap`/`fromMap`; all Setup fields are plain `State` fields; test `setup_screen_test.dart:466` |
| 5 | MUST NOT show a paused banner while the microphone is still capturing | Holds | `pause()` publishes `paused` only after `isPaused()` confirms; failure → `_fail()`. Test `:1088` |
| 6 | MUST NOT discard a captured answer on pause | Holds | `pause()` touches no stored row and no file; only `completeEarly` discards, and only the not-yet-finalized in-flight recording |
| 7 | MUST NOT auto-resume recording after an interruption / background / pause | Holds | Recorder started only from `_startNewQuestion`; `_resumeStartsNextQuestion` re-enters the get-ready countdown, not `recording` (`:358-363`). `const RecordConfig()` — no auto-resuming interruption mode set |
| 8 | MUST NOT introduce a network permission or network-capable dependency | Holds | `android/app/src/main/AndroidManifest.xml` carries `RECORD_AUDIO` only; `INTERNET` appears solely in the debug/profile manifests (Flutter tooling default). No HTTP/socket package in `pubspec.yaml`; `wakelock_plus` declares no permission |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No `TBD`/`FIXME`/`XXX` debt markers, no `TODO`/`HACK`, no "not yet implemented"/"coming soon" strings anywhere in `lib/` or `test/` |

`_NoTopics` (`setup_screen.dart:488`) and `PlaceholderQuestionSource` (`questions.dart:78`) are the two constructs that could read as stubs. Both are **not** stubs: `_NoTopics` is deliberately-locked copy for a branch that goes live in Phase 3 and is covered by a held-out test (`setup_screen_test.dart:269`) that injects an empty subject list; `PlaceholderQuestionSource` is the documented Phase 3 swap seam, and its non-filtering is the deferred item recorded above.

### Deviations Assessed

All five executor-reported departures were checked against the code rather than the SUMMARY narrative.

1. **02-04 — paused control slot renders the frozen readout beneath the RESUME pill.** CONFIRMED and CORRECT. `phase_control.dart:241-267` renders `Column(key: practice-control-paused)` = RESUME pill + conditional readout. The UI-SPEC layout table (line 349) lists only the pill for that slot, but the Pause section (line 421-422) requires "the frozen numeral/readout stays on screen at its frozen value". Without this the `d` readout would vanish on pause, because while `displayPhase == recording` the focus slot holds the question card, not the readout. The resolution honours the spec's stated intent, keeps the totality assertion intact (one key), and is behaviourally tested — `practice_session_test.dart:1288` asserts `'0:07 left'` is on screen while paused. **Not a gap.**
2. **02-05 — one `_requestStop()` instead of a bool-returning `_confirmStop()`.** CONFIRMED and CORRECT. `grep showDialog lib/` = exactly 1 hit; `completeEarly` = exactly 1 call site; `_requestStop` is invoked from exactly two producers (the Stop action and `PopScope`), re-entrancy-guarded by `_confirmingStop`. CTRL-02 and CTRL-03 are satisfied, and the executor's argument holds: a bool-returning confirm would have duplicated the zero-answer-vs-completion branch at both producers, which is exactly the drift D-29 forbids. **Not a gap.**
3. **02-05 — self-pause vs OS-pause fix.** CONFIRMED and CORRECT. `_expectingSelfPause` is set BEFORE `recordingService.pause()` (`practice_state.dart:307`), consumed exactly once in `_handleInterruption` (`:434-437`), released on a failed pause (`:311`) and on every `resume()` (`:348`) so it cannot swallow a later genuine interruption. The regression test (`:1547`) wires the producer exactly as `PracticeScreen` does, asserts `PausedReason.user` AND that nothing was committed, then drives a real interruption afterwards and asserts it is still labelled `interrupted`. That second half is what makes the guard trustworthy rather than merely present. **Not a gap.**
4. **Acceptance greps that could not hold literally.** Judged satisfied on substance. The shared `_SettingSlider` yields one `semanticFormatterCallback` occurrence but all three sliders pass a distinct formatter, and `setup_screen_test.dart:370` asserts all three announcements individually (`'10 questions'`, `'5 seconds thinking time'`, `'60 seconds answer length'`). Grep counts inflated by doc-comment mentions are a measurement artefact, not a requirement gap. **Not a gap.**
5. **02-01/02-02 test-harness deviation (in-memory `DatabaseHelper` double in widget tests).** No durability coverage lost. Real sqflite-ffi coverage exists in two places: `test/db/database_helper_test.dart` (359 lines, `sqfliteFfiInit()` at `:16`) and the plain `test()` at `practice_session_test.dart:1613`, which drives three answers through the real helper, disposes, **closes the handle and reopens a fresh one against the same on-disk file** — a genuine process-kill simulation asserting 1 session row, 3 answer rows and their order. The rationale is sound: `flutter_test`'s fake clock never yields to the real event loop that completes ffi futures. **Not a gap.**

### Gaps Summary

No gaps. Every observable truth is backed by code that exists, is substantive, is wired, and — for every behaviour-dependent truth (state transitions, the pause/cancel/cleanup invariants, and the interruption ordering invariant) — by a passing behavioural test rather than symbol presence alone. `flutter analyze` is clean and the full suite is 171/171.

The phase does not reach `passed` because four human-verification items remain, three of which can only be settled on hardware:

- The **D-31 real-device interruption check** was explicitly not discharged by the 02-05 executor and is the phase's one acknowledged open risk. Host tests prove the handler, its write ordering and the commit; research assumption A1 (an iOS backgrounding may suspend the isolate before the commit lands) is unfalsifiable on the host. This is correctly classified as a human item, not an automated gap.
- Real-microphone capture at the newly widened `d` range (10–120 s) has never run on hardware. Phase 1 already carries device-UAT-pending on LOOP-03/LOOP-06 for the same reason.
- Visual conformance to `02-UI-SPEC.md` is not assertable by widget tests.
- The eight judgment-tier prohibitions carry non-authoritative LLM verdicts (all "holds", each with codebase evidence) and are flagged for human sign-off rather than absorbed into a green pass.

**Non-blocking bookkeeping note:** `.planning/REQUIREMENTS.md` still lists all 14 Phase 2 requirements as `Pending` in the Traceability table while Phase 1's read `Complete`. The implementation satisfies all 14 (see Requirements Coverage above); only the status column is stale. This is a documentation update for the ship step, not a code gap.

---

_Verified: 2026-08-09T04:26:36Z_
_Verifier: Claude (gsd-verifier)_
