---
phase: 01-record-save-replay-a-single-answer-crash-safe
verified: 2026-08-08T09:33:20Z
status: human_needed
score: 6/11 must-haves verified
behavior_unverified: 5
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 0/5
  gaps_closed:
    - "SC-1 / Gap 1 — the practice loop's unrecoverable dead ends (idle/saving rendered no control; STOP during the arming window stranded the loop while the recorder armed for real; RecordingService had zero test coverage)"
    - "SC-5 / Gap 2 — the locked Baloo 2 typography did not ship in release builds (runtime CDN fetch, nothing bundled, no INTERNET permission in the release manifest)"
    - "Gap 3 — unguarded awaits in stopRecording() stranded the loop in saving/replaying, and awaitCompletion awaited a non-replaying broadcast stream unbounded"
    - "Gap 4 — history_screen.dart and session_detail_screen.dart coerced a failed read into the empty state"
    - "Documentation gap raised by the previous pass of THIS report — REQUIREMENTS.md contradicted itself about 10 of 12 Phase 1 requirements. Closed by commit eb68811."
  gaps_remaining: []
  regressions: []
gaps: []
deferred: []
behavior_unverified_items:
  - truth: "SC-2 — If auto-replay is enabled, the just-recorded answer plays back automatically the moment recording stops."
    test: "On a physical device: flutter run. Wait for the first question to appear. Speak an answer, then tap the coral STOP button. Do not touch the screen again."
    expected: "Without any tap: the answer you just spoke plays back audibly, 'Playing your answer…' is displayed under the mascot during playback, and when playback ends a NEW question appears with recording already re-armed (mascot listening, STOP button visible)."
    why_human: "Audible playback at real latency cannot be observed from code. The save-then-replay ordering, the subscribe-before-play race and the 65s ceiling are now genuinely proven by test/services/audio_player_service_test.dart against the real AudioPlayerService — but every one of those tests uses a fake backend that emits a synthetic completion event and plays no audio."
  - truth: "SC-3 — Every recorded answer appears immediately in an Exercise History list; tapping an entry plays its recording."
    test: "On a physical device: record and finish 2-3 answers. Tap the history icon in the app bar. Note the row count and the order. Tap the top session, then tap the question row inside the detail screen."
    expected: "Every finished answer is listed immediately with no refresh, newest at the top. Tapping a detail row plays that specific recording audibly. Tapping a second row while the first is playing stops the first rather than overlapping the two."
    why_human: "The list half is proven against a real SQLite engine and by widget tests that now also distinguish the error state from the empty state. The 'plays its recording' half calls into the audioplayers platform channel and requires a device with speakers."
  - truth: "SC-4 — Force-killing the app mid-use and relaunching still shows every already-recorded answer in history — nothing captured before the crash is lost."
    test: "D-07, the phase's defining risk. MUST be run on a clean install of a build carrying the current bundle identifier (see why_human). Round A: record and finish at least 2 answers, force-kill the app from the OS task switcher (not a hot restart, not a debugger stop), relaunch, open Exercise History. Round B: start a new recording, and while it is actively recording, force-kill from the task switcher. Relaunch and open Exercise History."
    expected: "Round A: every previously finished answer is still listed and still plays. Round B: the recording that was in flight at kill time leaves no trace — no new session row, no history entry — and its partial .m4a is swept from disk on the next launch (D-08). The answers from Round A are still intact after Round B."
    why_human: "Plans 01-03 and 01-06 both declare this `verification: backstop` — explicitly not inferable from unit tests. It requires an actual OS-level process kill. CRITICAL CAVEAT (WR-11): commit a07ae59 changed PRODUCT_BUNDLE_IDENTIFIER to com.haotran.englishreflex, so the app now installs into a DIFFERENT container. Any prior SC-4 result is void, and any pre-existing on-device data is not comparable. Delete the old app from the device first, then install fresh."
  - truth: "SC-5 — The recording and history screens use large, easily readable text and a simple, colorful, friendly visual style (not corporate/minimal-grey)."
    test: "On a physical device, ideally a RELEASE build (flutter run --release), with the device in airplane mode to prove no network is involved. Look at the Practice screen and the History screen. Then raise the OS text-size / font-scale setting to its maximum and return to the Practice screen, cycling questions until the longest one appears ('What is one thing you want to learn this year?')."
    expected: "Warm ivory background, peach question card and history rows, coral STOP button and play icons, and a friendly mic-with-face mascot whose ring pulses only while recording. The question text and screen titles render in a rounded, friendly face (Baloo 2) — visibly NOT the default Material font — even in release and even offline. At maximum text scale the longest question reflows and the column scrolls rather than clipping or overflowing. The mascot never reads as sad or judgmental."
    why_human: "The FONT half is no longer a gap — the .ttf is bundled and both guards were confirmed non-vacuous by deleting the font and watching them go red (see Behavioural Spot-Checks). What remains is the visual judgment: 'friendly, not corporate-grey' and 'readable at arm's length' cannot be asserted from hex values and type-scale numbers."
  - truth: "Recording actually captures the user's voice from the moment the question appears (SC-1, LOOP-03, D-01)"
    test: "On a physical device, first launch after a clean install so the microphone permission dialog appears. Respond to the dialog. Then, on the next question, begin speaking the instant the question text appears and tap STOP after roughly two seconds. Listen to the auto-replay."
    expected: "The playback contains the very first words you spoke, with no perceptible clipped syllable at the start. While the permission dialog is pending, the screen shows the question and the 'Getting ready…' label — never a blank, white or frozen screen."
    why_human: "Real microphone capture cannot be exercised on the test host. The screen now correctly waits for RecordingService.start() to resolve before claiming to record, so the UI no longer lies — but that also means an arming window measurably exists. Measure how much leading audio it actually costs on a real device."
human_verification:
  - test: "SC-4 / D-07 force-kill, on a CLEAN INSTALL of a build with the current bundle id (com.haotran.englishreflex). Round A: finish 2+ answers, force-kill from the OS task switcher, relaunch, open Exercise History. Round B: force-kill WHILE a recording is actively in progress, relaunch, open Exercise History."
    expected: "Round A: every finished answer still listed and still plays. Round B: the in-flight recording leaves no session row and no history entry, its partial .m4a is swept from disk on next launch, and Round A's answers are untouched."
    why_human: "Requires a real OS process kill; declared `verification: backstop` by plans 01-03 and 01-06. Prior results are void because the bundle identifier changed (WR-11) — the app now uses a different on-device container."
  - test: "SC-2 auto-replay. Finish a recording by tapping STOP and then do not touch the screen."
    expected: "The answer plays back audibly with no tap, 'Playing your answer…' shows during playback, then a NEW question appears with recording re-armed."
    why_human: "Audible playback needs speakers. Note: the previous hang risk is closed and the wait is bounded at 65s, so a freeze at 'Playing your answer…' lasting longer than ~65s would be a genuine NEW defect worth reporting."
  - test: "SC-3 / HIST-03 tap-to-replay. Record 2-3 answers, open Exercise History, tap a session, tap a question row. Then tap a second row while the first is still playing."
    expected: "Rows listed newest-first immediately; tapping plays that specific recording audibly; the second tap stops the first before starting the second."
    why_human: "Playback goes through the audioplayers platform channel. Optional extra: delete the underlying .m4a via a file manager and tap the row again — it should say 'That recording is no longer available on this device.' rather than doing nothing."
  - test: "SC-5 / UI-02 visual style. View the Practice and History screens in a RELEASE build in airplane mode, then raise the OS text size to maximum and re-check the longest question."
    expected: "Warm coral/peach/ivory palette, friendly mascot, and the rounded Baloo 2 face on the question and screen titles — visibly not the default Material font, even offline in release. Text reflows and scrolls at max text scale without clipping."
    why_human: "'Friendly, not corporate-grey' is a visual judgment. This is also the on-device confirmation of the Gap 2 font fix; the airplane-mode condition is what proves the bundled asset, not a CDN, is the load path."
  - test: "SC-1 / LOOP-03 leading-audio loss. On a clean first launch, answer the mic permission dialog. Then speak the instant the question appears, tap STOP after ~2s, and listen to the replay."
    expected: "The replay contains your very first words with no clipped opening syllable. No blank or frozen screen while the permission dialog is pending — only the question and the 'Getting ready…' label."
    why_human: "Real microphone capture cannot run on the test host, and the honest `arming` window means leading-audio cost should be measured rather than assumed to be zero."
---

# Phase 1: Record, Save & Replay a Single Answer (Crash-Safe) — Verification Report

**Phase Goal:** User can answer a practice question by recording their voice, have it saved to local storage the instant it's captured, replay it, and find it in an Exercise History list — and none of that is lost if the app is force-killed mid-use.
**Verified:** 2026-08-08T09:33:20Z
**Status:** human_needed
**Re-verification:** Yes — after the 01-04 / 01-05 / 01-06 gap-closure cycle, the 01-REVIEW blocker fixes, and the documentation fix in `eb68811`

## Mode Note

ROADMAP.md marks this phase `Mode: mvp`, but the phase goal is not in the User Story format (`As a ..., I want to ..., so that ...`) that MVP-mode verification requires. As in the previous report, this verification applies standard goal-backward methodology against the five ROADMAP Success Criteria and omits the User Flow Coverage table.

## Headline

**Every gap is now closed, and nothing remains that can be settled without a device.**

All four gaps from the original verification were checked at the mechanism level in real source — not against the SUMMARY narrative — and two were checked by falsification rather than by reading. The two review BLOCKERs and the data-loss WARNING were genuinely fixed, each with a regression test that reproduces the reviewer's own probe. The one gap the previous pass of this report raised — a self-contradicting `.planning/REQUIREMENTS.md` — is closed by commit `eb68811`, which I verified independently rather than accepting on report.

**The status is `human_needed`, not `gaps_found`.** I re-walked every open code-review warning against the blocker bar (does it make a truth FAILED, an artifact MISSING/STUB, a key link NOT_WIRED, or constitute a blocker anti-pattern?) and none clears it — the reasoning for each is recorded in "Why no open warning is a blocker" below, including the one genuine close call (WR-03). What is left is five on-device UAT items that no amount of code reading can settle. The right next action is `/gsd-verify-work 01` on a phone, not `/gsd-plan-phase 01 --gaps`.

## Verification of the documentation fix (`eb68811`)

Confirmed independently, not taken on report:

| Check | Command | Result |
|---|---|---|
| No Phase 1 requirement left unchecked | `grep -cE '^\- \[ \] \*\*(LOOP-0[3-6]\|PERSIST-0[12]\|HIST-0[1-4]\|UI-0[12])\*\*'` | `0` |
| All 12 are now `[x]` | `grep -E '^\- \[[ x]\] \*\*(...)\*\*'` | 12 rows, all `- [x]` |
| Traceability rows untouched | `grep -E '^\| (LOOP-0[3-6]\|...) '` | Unchanged — 5 `Complete`, 7 `Complete (device UAT pending)` |
| Scope of the commit | `git show --stat eb68811` | `.planning/REQUIREMENTS.md` only, 10 insertions / 10 deletions |
| No source file changed | `git diff --stat 8e94401 eb68811 -- lib/ test/ pubspec.yaml android/ ios/ assets/` | Empty |
| Working tree clean of source edits | `git status --porcelain lib/ test/ ...` | Empty (my Gap 2 falsification was fully restored) |

The checkbox list and the traceability table now agree for all twelve Phase 1 requirements, and the file's footer note (line 148) already documents the two-tier meaning: `Complete` means proven by automated tests, `Complete (device UAT pending)` means implemented with an outstanding on-device check. That is a coherent, defensible statement of Phase 1's state.

**On the test baseline.** `flutter analyze` clean and `flutter test` 82/82 were established at `8e94401`. Because `git diff 8e94401 eb68811` over `lib/`, `test/`, `pubspec.yaml`, `android/`, `ios/` and `assets/` is provably empty and the working tree carries no source edits, the compiled and tested artifact at `eb68811` is byte-identical to the one those results came from. Re-running would produce no new evidence, so the baseline carries forward on that identity rather than on assumption.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | **SC-1** — Recording starts automatically; a large stop button can end it early; auto-stops after the configured max duration | ✓ VERIFIED | The state machine is proven behaviourally, not by presence. `practice_state.dart:130-153` publishes `arming` first and only sets `recording` **after** `recordingService.start()` resolves; `practice_state_test.dart#the phase stays arming until the recorder has actually started` asserts that transition. `recording_service_test.dart` drives the **real** `RecordingService` against an injected `RecorderBackend` and proves the 60s `Timer` fires at `kMaxRecordingDuration`, not before, and exactly once. The 96px circular STOP renders for `recording` (`phase_control.dart:90-119`) and is the only control in that phase. `_onAutoStop()` (`practice_state.dart:170-180`) stops the recorder even when the loop has left `recording`. Real mic capture is tracked separately as truth 11. |
| 2 | **SC-2** — Auto-replay plays the just-recorded answer the moment recording stops | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Ordering, the subscribe-before-play race and the bounded wait are all genuinely tested against the real `AudioPlayerService` (`audio_player_service_test.dart`, 3 tests). Audible playback needs a device. |
| 3 | **SC-3** — Every recorded answer appears immediately in History; tapping an entry plays its recording | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | List half proven against real SQLite plus 8 new widget tests. Tap-to-play half reaches the audioplayers platform channel. |
| 4 | **SC-4** — Force-killing mid-use and relaunching still shows every already-recorded answer | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Code evidence is stronger than at first verification: single-transaction write, `PRAGMA foreign_keys = ON`, orphan sweep, AND the WR-01 fix guaranteeing a finalized answer commits even mid-teardown. Still `verification: backstop` — requires a real process kill, now against a changed bundle identifier. |
| 5 | **SC-5** — Screens use large readable text and a simple, colorful, friendly visual style | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | The shipping defect is gone (truth 7). Type scale, palette and touch targets asserted in `typography_test.dart`. What remains is the visual judgment, which no test can make. |
| 6 | **Gap 1 closed** — the practice loop has no unrecoverable dead end, and `RecordingService` has real tests | ✓ VERIFIED | `kPhaseControlKeys` is total over `PracticePhase.values`, and `PhaseControl.build`'s `switch` has no `default:` arm while returning a non-nullable `Widget` — so a new phase is a **compile** error before the exhaustive test even runs. STOP is no longer rendered during arming, and `stopRecording()` early-returns unless `phase == recording`, so the original race has no entry point. `test/services/recording_service_test.dart` (10 tests) constructs the **real** service, the **real** `Timer` and the **real** guards — it does not repeat the `FakeRecordingService` pattern that made the old coverage vacuous. |
| 7 | **Gap 2 closed** — the locked Baloo 2 typography ships in a release build | ✓ VERIFIED | `assets/fonts/Baloo2-SemiBold.ttf` is a real 418,064-byte TrueType file. `pubspec.yaml:76-77` has an active `assets:` block. `main.dart:26-32` sets `allowRuntimeFetching = false` before `runApp()`. The main Android manifest is unchanged and still declares only `RECORD_AUDIO`. **Falsified, not assumed:** with `build/unit_test_assets` cleared and the .ttf renamed away, both guards go red. |
| 8 | **Gap 3 closed** — no unguarded failure path can freeze the loop | ✓ VERIFIED | Every await in `stopRecording()` is inside a guarded path: `recordingService.stop()` (`:218-227`), `insertAnsweredSession()` (`:249-273`), and `toAbsolutePath()` + `play()` together (`:282-288`). `AudioPlayerService.play()` captures `onComplete.first` **before** `_backend.play()` and bounds it with `kReplayCompletionTimeout` (`:91-94`). Both properties covered by tests that genuinely fail without them. |
| 9 | **Gap 4 closed** — history never presents a read failure as absence of data | ✓ VERIFIED | `snapshot.hasError` checked **before** the `snapshot.data` read in both `history_screen.dart:72` and `session_detail_screen.dart:141`. Error and empty are separate widgets with separate keys and separate copy. Retry calls `setState(_load)` where `_load()` genuinely reassigns the future. The retry is no longer a lie: `database_helper.dart:83-92` drops the memo on a failed open (`identical` guard preserves the double-open fix), with a regression test. |
| 10 | **Plan 01-06** — REQUIREMENTS.md reflects the true post-gap-closure state of every Phase 1 requirement | ✓ VERIFIED | Closed by `eb68811`. All 12 checkboxes `[x]`; traceability rows unchanged and consistent; the two-tier `Complete` / `Complete (device UAT pending)` meaning documented in the file footer. Verified by grep, by diff scope, and by confirming no source file moved. |
| 11 | Recording actually captures the user's voice from the moment the question appears (SC-1, LOOP-03, D-01) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Wired and correctly ordered; real microphone capture is device-only, and the honest `arming` window means leading-audio cost should now be measured rather than assumed to be zero. |

**Score:** 6/11 truths verified — 0 failed, 5 device-only.

Read the denominator carefully: **every truth that can be settled without a device is verified (6 of 6).** The 5 not counted are not defects and not doubts about the code — they are `verification: backstop` items that the plans deliberately declared non-inferable from unit tests, and they abstain rather than passing silently. A 6/11 here means "code complete, phone pending", not "5 things broken". The score cannot reach 11/11 from this environment by design.

### Deferred Items

None. No gap remains to defer. Several open code-review warnings become *reachable* in Phase 2 (see Anti-Patterns), but Phase 2's success criteria do not undertake to fix them, so they are advisory carry-forward rather than deferred gaps.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/widgets/phase_control.dart` | Total phase→control mapping | ✓ VERIFIED | 143 lines; `kPhaseControlKeys` covers all 6 phases; exhaustive `switch`; used at `practice_screen.dart:139` |
| `lib/state/practice_state.dart` | `arming` phase, `_onAutoStop`, re-entrancy guard, fully guarded `stopRecording()` | ✓ VERIFIED | 294 lines; all six mechanisms present and individually tested |
| `lib/services/recording_service.dart` | `RecorderBackend` seam, `_recording` lifecycle flag, `_arm()` spanning both awaits, `_disposed` terminal flag | ✓ VERIFIED | 231 lines; CR-01 fix present (`dispose()` no longer clears `_stopRequestedDuringStart`; `start()` throws after dispose; `_stopRequestedDuringStart \|\| _disposed` discard) |
| `lib/services/audio_player_service.dart` | `AudioPlaybackBackend` seam, `kReplayCompletionTimeout`, subscribe-first bounded wait | ✓ VERIFIED | 100 lines; both protections present |
| `test/services/recording_service_test.dart` | Real-service coverage of the deadline and the guards | ✓ VERIFIED | 312 lines, 10 `testWidgets` on the fake-clock binding; includes the WR-09 dispose-during-arming regression |
| `test/services/audio_player_service_test.dart` | Proof a missed completion cannot hang the loop | ✓ VERIFIED | 3 tests; the timeout test uses the fake clock and would hang the suite without the ceiling |
| `test/widgets/phase_control_test.dart` | Exhaustive `PracticePhase.values` test | ✓ VERIFIED | 5 tests including totality and "no phase renders a START control" |
| `assets/fonts/Baloo2-SemiBold.ttf` | Bundled 600-weight face | ✓ VERIFIED | 418,064 bytes, valid TrueType |
| `assets/fonts/OFL.txt` | SIL OFL text, registered with LicenseRegistry | ✓ VERIFIED | 4,384 bytes; loaded in `configureFonts()` via `rootBundle.loadString` |
| `pubspec.yaml` | Active `assets:` section, no new runtime dependency | ✓ VERIFIED | `assets: - assets/fonts/`; dependency list unchanged from before the closure cycle |
| `lib/main.dart` | `configureFonts()` called before `runApp()` | ✓ VERIFIED | `ensureInitialized()` → `configureFonts()` → `runApp()` at `:34-39` |
| `test/theme/typography_test.dart` | Proof the asset is bundled and fetching is off | ✓ VERIFIED (fragility noted) | 4 tests, all non-vacuous today — confirmed by deletion. WR-07's ordering fragility is real but unexercised |
| `lib/screens/history_screen.dart` | `hasError` branch, distinct retryable error state | ✓ VERIFIED | 221 lines; `_HistoryError` keyed separately from `_EmptyHistory` |
| `lib/screens/session_detail_screen.dart` | Same error branch, null-safe id, missing-file feedback, stop-before-play | ✓ VERIFIED (partial on one sub-clause) | All four present. WR-03 remains open: `toAbsolutePath()` and `File.exists()` at `:100-102` sit outside the `try` |
| `lib/db/database_helper.dart` | Memoized `Future<Database>` that does not cache a failure | ✓ VERIFIED | `:83-92`; `identical(_dbFuture, attempt)` means a racing `close()` keeps its own fresh memo |
| `test/screens/history_screen_test.dart` | Empty vs error distinguishable, retry re-issues | ✓ VERIFIED | 6 tests |
| `test/screens/session_detail_screen_test.dart` | Detail error state, null-id path, tap-to-replay | ✓ VERIFIED | 9 tests, driving real `dart:io` inside `tester.runAsync()` |
| `android/app/src/main/AndroidManifest.xml` | RECORD_AUDIO only, unchanged by 01-05 | ✓ VERIFIED | Only `RECORD_AUDIO`; `INTERNET` still confined to `src/debug` and `src/profile` — now correct, since nothing fetches |
| `.planning/REQUIREMENTS.md` | Corrected checkboxes AND traceability for all 12 | ✓ VERIFIED | Closed by `eb68811`; both surfaces now agree |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `recording_service.dart` | `practice_state.dart` | auto-stop deadline invokes `_onAutoStop()` | WIRED | `onAutoStop: () => unawaited(_onAutoStop())` at `practice_state.dart:146`; callback fires from `Timer` at `recording_service.dart:186-194`; 2 matches for `_onAutoStop` |
| `practice_state.dart` | `phase_control.dart` | `PhaseControl(phase: _state.phase, ...)` | WIRED | 1 match at `practice_screen.dart:139`, inside the `ListenableBuilder` so it repaints on every phase change |
| `audio_player_service.dart` | `practice_state.dart` | `play(awaitCompletion: true)` bounded by `kReplayCompletionTimeout` | WIRED | 3 matches of `kReplayCompletionTimeout`; consumed at `practice_state.dart:284` |
| `pubspec.yaml` | `lib/main.dart` | bundled asset satisfies `GoogleFonts.baloo2(w600)` locally | WIRED | `assets/fonts` in pubspec; `allowRuntimeFetching = false` in `configureFonts()` |
| `lib/main.dart` | `test/theme/typography_test.dart` | test calls `configureFonts()` then awaits `pendingFonts()` | WIRED | 3 matches of `configureFonts` in each file |
| `database_helper.dart` | `history_screen.dart` | a throwing `listSessions()` reaches `snapshot.hasError` | WIRED | 1 match, at `:72`, before the `data` read |
| `database_helper.dart` | `session_detail_screen.dart` | a throwing `listAnswersForSession()` reaches `snapshot.hasError` | WIRED | 1 match, at `:141`, before the `data` read |
| `practice_state.dart` | `database_helper.dart` | `insertAnsweredSession(...)` after a non-null finalized path | WIRED | `:250`, inside try/catch, after the null check at `:236` |
| `practice_screen.dart` | `recording_service.dart` | `dispose()` stops before tearing down | WIRED | `:62-67`; the exact sequence is replayed verbatim by the CR-01 regression test |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `history_screen.dart` | `_sessionsFuture` | `listSessions()` → `db.query(sessions, orderBy: 'id DESC')` | Yes — real SQLite query; error path no longer collapses to `[]` | FLOWING |
| `session_detail_screen.dart` | `_answersFuture` | `listAnswersForSession(id)` → parameterised `db.query`; null id → explicit `Future.value([])` | Yes — the empty literal is a deliberate null-id branch, not an error swallow | FLOWING |
| `practice_screen.dart` | `_state.phase` | Mutated by the real record/save/replay loop; consumed by `PhaseControl` and `Mascot` | Yes | FLOWING |
| `practice_screen.dart` | `_state.currentQuestion` | `_pickQuestion()` over `kQuestions` | Yes | FLOWING |
| `phase_control.dart` | `phase` prop | Passed from `_state.phase` at the call site — not hardcoded | Yes | FLOWING |
| `session_detail_screen.dart` | `answer.audioPath` | DB column → `toAbsolutePath()` → existence check → `DeviceFileSource` | Yes | FLOWING |
| `main.dart` textTheme | `displayLarge` / `headlineSmall` | `GoogleFonts.baloo2()` resolving the bundled .ttf | Yes — proven by deleting the asset and watching the load test throw | FLOWING |

### Behavioural Spot-Checks

| Behaviour | Command | Result | Status |
|---|---|---|---|
| Static analysis | `flutter analyze` | `No issues found! (ran in 2.8s)` | ✓ PASS |
| Full suite, stale asset bundle cleared | `rm -rf build/unit_test_assets && flutter test` | `00:07 +82: All tests passed!` | ✓ PASS |
| **Font guard falsification** | `mv Baloo2-SemiBold.ttf …disabled && rm -rf build/unit_test_assets && flutter test test/theme/typography_test.dart` | `+2 -2` — BOTH `Baloo 2 SemiBold loads from the bundled asset` and `the Baloo2-SemiBold asset is bundled in the asset manifest` FAILED (`Expected: non-empty / Actual: WhereIterable<String>:[]`). File restored, suite re-run green. | ✓ PASS — the Gap 2 guards are genuinely non-vacuous |
| Font asset is a real font | `file assets/fonts/Baloo2-SemiBold.ttf` | `TrueType Font data, 15 tables` (418,064 bytes) | ✓ PASS |
| `RecordingService` tests use the real service | read `test/services/recording_service_test.dart` | `RecordingService(backend: FakeRecorderBackend())` — the **service** is real, only the platform backend is faked. The real `Timer`, `_recording` flag, `_startInFlight`/`_stopRequestedDuringStart` handshake and `_disposed` flag all execute. | ✓ PASS — does not repeat the old `FakeRecordingService` pattern |
| Release manifest still has no INTERNET | `grep -rn INTERNET android/` | only `src/debug` and `src/profile` | ✓ PASS (now correct by design) |
| CR-01 regression test exists and passes | `a dispose landing IN the arming window still finalizes and discards` | present, passing | ✓ PASS |
| CR-02 regression test exists and passes | `a FAILED open is not cached — the next caller re-attempts` | present, passing | ✓ PASS |
| WR-01 regression test exists and passes | `a disposal racing the stop still saves the finished answer` | present, passing | ✓ PASS |
| REQUIREMENTS.md has no unchecked Phase 1 requirement | `grep -cE '^\- \[ \] \*\*(LOOP-0[3-6]\|PERSIST-0[12]\|HIST-0[1-4]\|UI-0[12])\*\*'` | `0` | ✓ PASS |
| `eb68811` touched no source | `git diff --stat 8e94401 eb68811 -- lib/ test/ pubspec.yaml android/ ios/ assets/` | empty | ✓ PASS |
| `PracticePhase.idle` reachability | `grep -rn "phase = PracticePhase" lib/` | 5 assignments: `arming` ×2, `recording`, `error`, `saving`, `replaying`. **Zero** assign `idle`. | ⚠️ CONFIRMED dead (WR-05) |
| Debt markers in changed files | `grep -rn -E "TBD\|FIXME\|XXX" lib/ test/` | zero matches | ✓ PASS |
| Real mic / audible playback / force-kill / visual judgment | — | no device or emulator available | ? SKIP → human verification |

### Probe Execution

Not applicable — this phase declares no probes and the project has no `scripts/*/tests/probe-*.sh` convention.

### Requirements Coverage

All 12 requirement IDs mapped to Phase 1 in REQUIREMENTS.md are claimed by a plan. No orphaned requirements. Checkbox list and traceability table now agree for all twelve.

| Requirement | Source Plan | Status | Evidence |
|---|---|---|---|
| LOOP-03 (recording starts automatically) | 01-01, 01-04 | NEEDS HUMAN | `_bootstrap()` → `startNewQuestion()`; arming→recording transition tested. Real mic capture is device-only. |
| LOOP-04 (auto-stop after `d`) | 01-01, 01-04 | ✓ SATISFIED | The 60s `Timer` is now exercised by the real service: fires at `kMaxRecordingDuration`, not before, exactly once, and is cancelled by `dispose()`. The single biggest change from the first verification. |
| LOOP-05 (large always-visible stop button) | 01-01, 01-04 | ✓ SATISFIED | 96px circular STOP; the arming dead end is gone; every phase renders exactly one control and the mapping is compile-enforced. Previously BLOCKED. |
| LOOP-06 (auto-replay on stop) | 01-01, 01-04 | NEEDS HUMAN | Subscribe-before-play + 65s ceiling tested; audibility is device-only. |
| PERSIST-01 (write immediately after capture) | 01-01, 01-03, 01-04, 01-06 | ✓ SATISFIED | Single-transaction write after a non-null finalized path, now unconditional across teardown (WR-01 fix). |
| PERSIST-02 (survives kill mid-session) | 01-01, 01-03, 01-06 | NEEDS HUMAN | Transaction + FK pragma + orphan sweep + WR-01 fix. D-07 force-kill is a locked on-device proof, and must be re-run after the bundle-identifier change. |
| HIST-01 (every session in the list) | 01-01, 01-06 | ✓ SATISFIED | `id DESC`; empty and error states now distinct and both tested. |
| HIST-02 (session detail shows its questions) | 01-01, 01-06 | ✓ SATISFIED | Scoped `where session_id = ?`, `id ASC`; cross-session scoping tested at both the DB and widget layers. |
| HIST-03 (tap a question to play it) | 01-01, 01-06 | NEEDS HUMAN | Missing-file and player-failure feedback now surfaced (2 tests) and stop-before-play added. Audibility is device-only. Partial residue: WR-03's two unguarded awaits. |
| HIST-04 (persist across restarts) | 01-03, 01-06 | NEEDS HUMAN | Reads are pure; relaunch behavior is device-only. |
| UI-01 (large readable fonts) | 01-02, 01-05 | ✓ SATISFIED | 32/24/18/16, no `textScaler` pin, scrollable question column, 96px/64px touch targets — and the face they render in now actually ships. |
| UI-02 (colorful/friendly, not corporate-grey) | 01-02, 01-05 | NEEDS HUMAN | Palette, mascot and Baloo 2 all verified in code and in the bundle. "Friendly, not corporate-grey" is a visual judgment. Previously BLOCKED. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| — | — | `TBD` / `FIXME` / `XXX` / `TODO` / `HACK` / `PLACEHOLDER` | — | **None found** anywhere in `lib/` or `test/` — clean |
| `lib/state/practice_state.dart` | 19, 60 | `PracticePhase.idle` has zero assignments — dead enum member | ⚠️ Warning | WR-05, discussed below |
| `lib/widgets/phase_control.dart` | 51-52, 67-80 | `onStart` callback and the `idle` "Try again" control are unreachable in production | ⚠️ Warning | Dead code; two tests assert behaviour of an unreachable state |
| `test/state/practice_state_test.dart` | 241-250 | "two recordings started in the same millisecond do not collide" is separated by a real-clock `stopRecording()` | ⚠️ Warning | WR-06 — deleting the `_${_random.nextInt(1 << 20)}` entropy suffix would leave this test green. The suffix IS present in `practice_state.dart:140-141`, so the property holds; only its guard is toothless |
| `lib/screens/session_detail_screen.dart` | 100-102 | `toAbsolutePath()` and `File(...).exists()` sit outside the `try` | ⚠️ Warning | WR-03, still open — a `MissingPluginException` or I/O error escapes `_play` into an `unawaited` with no handler, so a tap can still be a silent no-op on those narrower inputs |
| `lib/services/audio_player_service.dart` | 91-94 | `Stream.first` subscription is not cancelled on the timeout path | ⚠️ Warning | WR-02, still open — one permanently-attached listener per timed-out replay. Harmless on the happy path (`first` self-cancels); accumulates only when the ceiling is actually hit |
| `lib/state/practice_state.dart` | 154 | Blanket `catch (_)` swallows the deliberately-introduced `StateError` | ⚠️ Warning | WR-04, still open. **Unreachable in Phase 1** (verified: the only routes to a second `start()` are `onStart` from the unreachable `idle`, and `retry()` which requires `phase == error`, which cannot coexist with a live recorder except via this same `StateError`). Becomes reachable when Phase 2 adds pause/resume |
| `lib/screens/session_detail_screen.dart` | 63, 82 | Disposes an injected `AudioPlayerService` it does not own | ⚠️ Warning | WR-08, still open. Harmless today (production passes nothing); bites the first Phase 2 caller that shares a player |
| `ios/Runner.xcodeproj/project.pbxproj` | 386, 566, 589 | `PRODUCT_BUNDLE_IDENTIFIER = com.haotran.englishreflex` changed by unrelated commit `a07ae59` | ⚠️ Warning | WR-11, still open. Confirmed present. The app installs into a different container, voiding any prior on-device SC-4 result — folded into UAT item 1 |
| `test/theme/typography_test.dart` | 52-58 | Primary guard's non-vacuity depends on declaration order and a clean `build/unit_test_assets` | ⚠️ Warning | WR-07, still open. **Empirically non-vacuous today** (falsified above), but nothing enforces it stays that way |
| `lib/services/recording_service.dart` | 205, 207 | `return null` | ℹ️ Info | Documented first-stop-wins / arming sentinels. The caller now routes both to `error`, not to a controlless phase |
| `lib/widgets/phase_control.dart` | 69, 85, 95, 124, 133, 139 | `kPhaseControlKeys[...]` looked up nullably at the use site | ℹ️ Info | IN-01. Totality test catches a removed entry, but the invariant isn't expressed where relied on |
| `lib/services/audio_player_service.dart` | 9-10 | `Duration(seconds: 60 + 5)` hand-copies `kMaxRecordingDuration`'s 60 | ℹ️ Info | IN-02. No drift test exists; Phase 2 makes `d` configurable |

No unreferenced debt markers, and no blocker-severity anti-pattern.

### Why no open warning is a blocker

The status hinges on this, so each open warning is tested against the bar explicitly rather than waved through:

- **WR-03 — the genuine close call.** The 01-06 must-have reads *"Tapping a history detail row whose audio file no longer exists tells the user the recording is unavailable instead of doing nothing, and any playback error is surfaced rather than swallowed."* Clause 1 is satisfied and tested — `File(absolutePath).exists()` returning false routes to `kRecordingMissingMessage`. Clause 2's operative noun is *playback* error, and the `play()` call **is** guarded. What is unguarded is path resolution (`toAbsolutePath` → `path_provider`) and the `File.exists()` I/O call itself — pre-playback, not playback. Reachability: `path_provider` failing means a broken plugin registration that would break the entire app rather than one tap; `File.exists()` throwing instead of returning false requires an OS-level I/O fault. Neither defeats HIST-03's user-facing promise on any ordinary path. **Judgment: PARTIAL on one sub-clause, WARNING not BLOCKER.** I am recording the reasoning so it can be overruled on sight rather than buried.
- **WR-02** — a resource leak confined to the timeout path. The must-have it relates to ("bounds the wait so a missed event cannot hang the loop") is satisfied; the leak does not affect correctness.
- **WR-04** — traced to unreachable in Phase 1. Unreachable code cannot be a Phase 1 defect.
- **WR-05** — dead code, not wrong code. The gap's intent is satisfied more strongly than requested (see below).
- **WR-06** — a weak *guard*, not a wrong *behaviour*: the entropy suffix it fails to protect is present in the source and I confirmed it directly.
- **WR-07** — empirically falsified as non-vacuous today; the warning is about future fragility.
- **WR-08** — no production path passes an injected player, so nothing in Phase 1 hits it.
- **WR-11** — not a code defect at all. It is a build-config change that invalidates prior *evidence*, which is why it is escalated into UAT item 1 rather than treated as a gap.

None makes a truth FAILED, an artifact MISSING or STUB, or a key link NOT_WIRED. Nothing here is a thing to *plan*; the remaining warnings are things to *triage*, and the remaining unknowns are things to *test on a phone*.

### On WR-05 and Gap 1b — an explicit judgment (unchanged)

Gap 1b asked for *"a recoverable affordance (a Start/Try-again control) on `PracticePhase.idle` instead of a controlless screen."*

`PhaseControl` maps `idle` to a 64px "Try again" `FilledButton`. It also — separately, in `practice_state.dart` — made `idle` unreachable: the constructor initialises to `arming`, and every path that previously landed on `idle` now calls `_fail()` → `error`.

**Judgment: the gap's INTENT is fully satisfied; its LITERAL wording is satisfied by unreachable code.** The intent behind 1b was never "make the `idle` enum value nice"; it was *"the loop must never come to rest on a screen with no way forward."* That property is now true twice over, and both proofs are stronger than the one the gap asked for:

1. The phase→control map is **total and compile-enforced** — the `switch` has no `default:` arm and returns a non-nullable `Widget`, so a future phase without a control fails to compile, before the exhaustive test even runs.
2. The specific route that used to reach `idle` (a null finalized path) now reaches `error`, which carries the `_ErrorBanner` with a working `Retry` wired to `PracticeState.retry()` — a *better* recovery affordance than the one requested, because it also tells the user what happened.

So Gap 1 stays closed. What remains is a smaller, different problem the gap did not ask about: `PracticePhase.idle`, `PhaseControl.onStart`, `PracticeScreen`'s `onStart:` argument, and two of the five `phase_control_test` cases are all dead in production. Concretely this costs: the exhaustive totality test reports coverage over a state space one member larger than the reachable one (mildly overstating what it proves), and the project's explicit minimal-code constraint is violated by four dead artifacts. It is a WARNING for the user's judgment — delete `idle` and its four dependants, or keep it with an `@visibleForTesting` note declaring it a reserved future state — not a blocker.

### Human Verification Required

Five items, each with a full procedure in the `human_verification` frontmatter block so `/gsd-verify-work 01` can drive them directly. In priority order:

**1. D-07 force-kill test (SC-4) — the phase's defining risk, and the most urgent.**
Delete the app from the device first, then install fresh: commit `a07ae59` changed the iOS bundle identifier to `com.haotran.englishreflex`, so the app now uses a different container and any previous result or pre-existing on-device data is not comparable. *Round A:* record and finish at least 2 answers, force-kill from the OS task switcher (not a hot restart, not a debugger stop), relaunch, open Exercise History — every finished answer must still be listed and still play. *Round B:* force-kill *during* an active recording — that recording must leave no session row and no history entry, its partial `.m4a` must be swept on next launch (D-08), and Round A's answers must be untouched.

**2. Audible auto-replay and loop reset (SC-2).**
Finish a recording by tapping STOP, then do not touch the screen. Expect audible playback with no tap, "Playing your answer…" during playback, then a NEW question with recording re-armed. The previous hang risk is closed and the wait is bounded at 65s, so a freeze at "Playing your answer…" lasting longer than ~65s would now be a genuine **new** defect worth reporting.

**3. Tap-to-replay from history (SC-3 / HIST-03).**
Record 2-3 answers, open Exercise History, confirm newest-first ordering, tap a session, tap a question row — that specific recording should play audibly. Tap a second row while the first plays; the first should stop rather than overlap. Optional extra: delete the underlying `.m4a` via a file manager and tap the row again — expect "That recording is no longer available on this device." rather than silence.

**4. Visual style and text scale (SC-5 / UI-02).**
Run a RELEASE build (`flutter run --release`) with the device in airplane mode. Confirm the warm coral/peach/ivory palette and friendly mascot, and that the question and screen titles render in the rounded Baloo 2 face — visibly not the default Material font, offline. The airplane-mode condition is what proves the bundled asset rather than a CDN is the load path, and this is the on-device confirmation of the Gap 2 fix. Then raise OS text size to maximum and confirm the longest question reflows and scrolls without clipping.

**5. Leading-audio loss on auto-start (SC-1 / LOOP-03).**
On a clean first launch, answer the mic permission dialog. Then speak the instant the question appears, tap STOP after ~2s, and listen to the replay. Expect your very first words present with no clipped opening syllable, and no blank or frozen screen while the permission dialog is pending — only the question and the "Getting ready…" label. The screen now honestly shows that label during arming instead of falsely claiming to record, so this measures a window that genuinely exists rather than one that was previously hidden.

### Summary

The gap-closure cycle did its job, and the documentation fix completes it.

Every one of the four original gaps was verified at the mechanism level in real source, and where the mechanism's own proof was suspect I falsified it rather than reading it. Deleting `Baloo2-SemiBold.ttf` with the stale `build/unit_test_assets` cleared turns both font guards red — Gap 2 cannot survive a second time the way it survived the first. `test/services/recording_service_test.dart` constructs the **real** `RecordingService`, so the real 60s `Timer` and the real first-stop-wins guard now execute across ten tests, closing the exact "the tests can't reproduce the race they're named for" complaint that made Gap 1 a gap. The two review BLOCKERs and the data-loss WARNING each shipped with a regression test replaying the reviewer's probe verbatim; the CR-02 fix in particular is subtle and correct, using `identical(_dbFuture, attempt)` so a racing `close()` keeps its own fresh memo while a failed open still drops its own. Commit `eb68811` closes the last gap by ticking the ten Phase 1 checkboxes — verified by grep, by diff scope, and by confirming no source file moved.

**No gap remains, and no open warning clears the blocker bar** — each was tested against it individually above, including WR-03, the one genuine close call, whose reasoning is recorded so it can be overruled on sight. Eight code-review warnings stay open and are worth triaging, not planning. Three of them are specifically Phase 2 hazards: **WR-04**'s swallowed `StateError` and **WR-08**'s borrowed-player disposal become reachable exactly when Phase 2 adds pause/resume phases and makes the practice screen pushable behind a Setup screen, and **WR-05**'s dead `idle` phase should be resolved one way or the other before that state machine grows. Triage them before Phase 2 planning rather than after.

What is left is five on-device UAT items that no amount of code reading can settle — audible playback, tap-to-play, the D-07 force-kill, the visual judgment, and real microphone capture. The plans deliberately declared these `verification: backstop` so they abstain rather than passing silently, and this report honours that: they are not verified from code. The correct next action is `/gsd-verify-work 01` with a phone in hand.

---

_Verified: 2026-08-08T09:33:20Z_
_Verifier: Claude (gsd-verifier)_
_Method: re-verification against the four original gaps plus the documentation gap raised by this report's previous pass, all checked at the mechanism level in source; Gap 2 confirmed by falsification (asset deletion), Gap 1 confirmed by auditing the new test seams for tests that cannot fail, `eb68811` confirmed by grep + diff scope + source-identity check_
_Baseline: `flutter analyze` clean; `flutter test` 82/82 passing with `build/unit_test_assets` cleared, carried forward to `eb68811` on proven source byte-identity_
