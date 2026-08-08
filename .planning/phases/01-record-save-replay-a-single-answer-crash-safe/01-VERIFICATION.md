---
phase: 01-record-save-replay-a-single-answer-crash-safe
verified: 2026-08-08T00:00:00Z
status: gaps_found
score: 0/5 must-haves verified
behavior_unverified: 3
overrides_applied: 0
gaps:
  - truth: "SC-1 — Recording an answer starts automatically and a large, always-visible stop button can end it early; if not stopped manually it auto-stops after the configured max duration."
    status: partial
    reason: "Tapping the visible STOP button before RecordingService.start() has finished arming drives PracticeState into PracticePhase.idle, which renders no control of any kind — an unrecoverable dead end. In that same interleaving the recorder then starts for real and can never be stopped, because the 60s auto-stop callback early-returns on `phase != recording`. The answer is captured but never saved."
    artifacts:
      - path: "lib/state/practice_state.dart"
        issue: "stopRecording() line 130 sets `phase = PracticePhase.idle` on a null finalized path; PracticeScreen has no widget for the idle phase (no Stop, no Retry, no Start), so the loop is stuck. startNewQuestion() lines 81-82 also set phase=recording and notifyListeners() BEFORE awaiting ensureRecordingsDir()/recordingService.start(), so the STOP button is on screen during the arming window."
      - path: "lib/screens/practice_screen.dart"
        issue: "Lines 126-133 render a control only for PracticePhase.recording and PracticePhase.replaying. Phases idle and saving render no affordance at all."
      - path: "lib/services/recording_service.dart"
        issue: "The 60s Timer and the `_stopping` first-stop-wins guard have zero test coverage — test/state/practice_state_test.dart's FakeRecordingService overrides start() and stop() wholesale, so neither the Timer nor the guard is ever constructed in any test. There is no test/services/ directory."
    missing:
      - "Only set phase=recording (and therefore show the STOP button) after recordingService.start() has resolved, or render an explicit arming state with no STOP affordance."
      - "Give PracticePhase.idle a recoverable affordance (a Start/Try-again control) instead of a controlless screen."
      - "Have the auto-stop callback stop the recorder even when PracticeState is no longer in the recording phase, so a recorder that was armed after a losing stop cannot run unbounded."
      - "Add test/services/recording_service_test.dart covering the 60s Timer firing and the concurrent manual-stop vs auto-stop race against the real _stopping guard (use fakeAsync/FakeTimer with a mock AudioRecorder seam)."
  - truth: "SC-5 / Plan 01-02 — Question prompt text renders in Baloo 2 at 32px SemiBold(600); screen titles render in Baloo 2 at 24px SemiBold(600) (D-15, UI-SPEC locked typography contract)"
    status: failed
    reason: "google_fonts 8.2.1 fetches Baloo 2 over HTTPS at runtime (GoogleFonts.config.allowRuntimeFetching defaults to true; verified in the package source). No .ttf is bundled and pubspec.yaml has no active `fonts:` or `assets:` section. android/app/src/main/AndroidManifest.xml declares only RECORD_AUDIO — the INTERNET permission exists ONLY in the debug and profile manifests. A release Android build therefore cannot fetch the font and silently falls back to the default Material font, so the locked Baloo 2 typography does not ship."
    artifacts:
      - path: "android/app/src/main/AndroidManifest.xml"
        issue: "No <uses-permission android:name=\"android.permission.INTERNET\" /> — present only in src/debug and src/profile, which are stripped from release builds."
      - path: "pubspec.yaml"
        issue: "google_fonts: ^8.2.1 declared, but no `fonts:` section and no bundled Baloo 2 .ttf asset; runtime fetch is the only load path."
      - path: "lib/main.dart"
        issue: "Lines 66-78 call GoogleFonts.baloo2() for displayLarge and headlineSmall with no allowRuntimeFetching=false and no bundled-asset fallback."
    missing:
      - "Bundle Baloo 2 .ttf as a Flutter asset and set GoogleFonts.config.allowRuntimeFetching = false (the remediation the 01-02-SUMMARY itself names), OR add the INTERNET permission to the main manifest and accept the CDN dependency plus the offline-first-run fallback."
      - "A test or on-device check that proves Baloo 2 actually loaded rather than silently falling back."
  - truth: "Plan 01-01 — After auto-replay finishes, the screen resets to a freshly-picked hardcoded question and immediately starts recording again (D-03); the loop always reaches a recoverable state"
    status: partial
    reason: "stopRecording() has no error handling around recordingService.stop() (line 126), toAbsolutePath() (line 155) or audioPlayerService.play() (line 156). A throw from any of these leaves PracticeState permanently in `saving` or `replaying` — both of which PracticeScreen renders with no control and no error banner. Separately, AudioPlayer.onPlayerComplete derives from a non-replaying broadcast StreamController (verified in audioplayers 6.8.1 audioplayer.dart:97), so `await _player.onPlayerComplete.first` subscribed after `await play()` can miss the completion event and never resolve — freezing the loop at \"Playing your answer…\" forever."
    artifacts:
      - path: "lib/state/practice_state.dart"
        issue: "Lines 121-160: only the insertAnsweredSession call is wrapped in try/catch. The stop, path-resolution and playback calls are unguarded."
      - path: "lib/services/audio_player_service.dart"
        issue: "Lines 22-25: awaitCompletion awaits onPlayerComplete.first with no timeout and no PlayerState fallback; a missed or never-emitted completion event hangs the practice loop permanently."
    missing:
      - "Wrap the whole post-stop sequence in try/catch and route failures to _fail() so the error banner + Retry are always reachable."
      - "Bound the awaitCompletion wait (timeout, or subscribe to onPlayerComplete before calling play()) so a missed completion event cannot hang the loop."
  - truth: "History reflects the true persisted state — a read failure is never presented as absence of data (supports SC-3/SC-4)"
    status: partial
    reason: "HistoryScreen ignores snapshot.hasError and coerces a failed read to an empty list, rendering the 'No recordings yet' empty state. For a phase whose entire point is 'nothing captured is ever lost', a transient DB read error is displayed to the user as total data loss."
    artifacts:
      - path: "lib/screens/history_screen.dart"
        issue: "Line 48: `final sessions = snapshot.data ?? const <Session>[];` — snapshot.hasError is never checked, so an exception renders as the empty state."
      - path: "lib/screens/session_detail_screen.dart"
        issue: "Line 69: same pattern — a failed listAnswersForSession renders an empty session instead of an error."
    missing:
      - "Check snapshot.hasError and render a distinct error state with a retry affordance, separate from the empty state."
behavior_unverified_items:
  - truth: "SC-2 — If auto-replay is enabled, the just-recorded answer plays back automatically the moment recording stops."
    test: "flutter run on a physical device. Let a recording finish (tap STOP or wait out the 60s cap). Listen."
    expected: "The answer you just spoke plays back audibly with no tap, 'Playing your answer…' is shown during playback, and when playback ends a NEW question appears with recording already re-armed."
    why_human: "Audible playback and the save-then-play ordering at real latency cannot be observed from code. The only automated coverage is test/state/practice_state_test.dart with a FakeAudioPlayerService that records a 'play' call and returns immediately — it never plays audio and never exercises the onPlayerComplete await that gates the reset."
  - truth: "SC-3 — Every recorded answer appears immediately in an Exercise History list; tapping an entry plays its recording."
    test: "Record 2-3 answers. Open Exercise History via the app bar icon. Confirm the count and most-recent-first order. Tap a session, then tap the question row in the detail screen."
    expected: "Every answer is listed immediately, newest at the top; tapping a detail row plays that specific recording audibly."
    why_human: "The DB half is proven by real-SQLite tests (test/db/database_helper_test.dart runs against sqflite_common_ffi and covers ordering, session scoping and the empty state). The 'plays its recording' half calls into the audioplayers platform channel and requires a device with speakers."
  - truth: "SC-4 — Force-killing the app mid-use and relaunching still shows every already-recorded answer in history — nothing captured before the crash is lost."
    test: "D-07, the phase's defining risk. Record and finish at least 2 answers. Force-kill the app from the OS task switcher (not a hot restart). Relaunch. Open Exercise History. Then repeat, but force-kill WHILE a recording is actively in progress."
    expected: "After the kill, every previously finished answer is still listed and still plays. The recording that was in flight at kill time leaves no trace — no session row, no history entry, and its partial .m4a is swept from disk on the next launch (D-08)."
    why_human: "Plan 01-03 declares this truth `verification: backstop` — explicitly not inferable from unit tests. It requires an actual OS-level process kill on a device, which this environment cannot perform. Code-level evidence is strong (single-transaction insertAnsweredSession, PRAGMA foreign_keys=ON, pruneOrphanRecordings awaited before arming, all covered by real-SQLite tests) but the user locked this as a mandatory on-device proof."
  - truth: "SC-5 — The recording and history screens use large, easily readable text and a simple, colorful, friendly visual style (not corporate/minimal-grey)."
    test: "flutter run on a device. Look at the Practice screen and the History screen. Then raise the OS text-size setting to its maximum and re-check the longest question ('What is one thing you want to learn this year?')."
    expected: "Warm ivory background, peach cards/rows, coral STOP button and play icons, a friendly mic-with-face mascot whose ring pulses only while recording. Text reflows and scrolls rather than clipping at max text scale. The mascot never reads as sad or judgmental."
    why_human: "Palette hexes, type scale and touch-target sizes are all confirmed in code, but 'friendly, not corporate-grey' and 'readable at arm's length' are visual judgments. Note: verify separately in a RELEASE build whether the Baloo 2 font actually loads — see the SC-5 gap above; in debug it will load because the debug manifest grants INTERNET."
  - truth: "Recording actually captures the user's voice from the moment the question appears (SC-1, LOOP-03, D-01)"
    test: "flutter run on a device. On first launch, respond to the mic permission dialog. Then start speaking the instant the question appears and immediately tap STOP. Replay the result."
    expected: "The playback contains the very first words you spoke. No blank/frozen screen while the permission dialog is pending."
    why_human: "Real microphone capture cannot be exercised on the test host. Additionally, PracticeState sets phase=recording and repaints BEFORE awaiting ensureRecordingsDir() and recordingService.start(), so the UI claims to be recording before the recorder is armed — measure how much leading audio is actually lost on a real device."
---

# Phase 1: Record, Save & Replay a Single Answer (Crash-Safe) — Verification Report

**Phase Goal:** User can answer a practice question by recording their voice, have it saved to local storage the instant it's captured, replay it, and find it in an Exercise History list — and none of that is lost if the app is force-killed mid-use.
**Verified:** 2026-08-08
**Status:** gaps_found
**Re-verification:** No — initial verification

## Mode Note

ROADMAP.md marks this phase `Mode: mvp`, but the phase goal is not in the User Story format (`As a ..., I want to ..., so that ...`) that MVP-mode verification requires. Rather than refuse verification outright, this report applies the standard goal-backward methodology against the five ROADMAP Success Criteria (which are well-formed and testable) and omits the User Flow Coverage table. If MVP-mode verification output is wanted for this phase, run `/gsd mvp-phase 1` to set a User Story goal first.

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP Success Criterion) | Status | Evidence |
|---|---|---|---|
| 1 | Recording starts automatically; a large, always-visible stop button ends it early; auto-stops after max duration | FAILED | Auto-start is wired (`_bootstrap()` → `startNewQuestion()` in `practice_screen.dart:32,50`) and the 96px circular STOP button exists (`practice_screen.dart:241-276`). But the button is NOT always visible — it renders only for `PracticePhase.recording`, and tapping it during the arming window drives the loop into `PracticePhase.idle`, which renders **no control at all**. The 60s `Timer` exists (`recording_service.dart:61`) but no test constructs it. See gap 1. |
| 2 | Auto-replay plays the just-recorded answer the moment recording stops | PRESENT_BEHAVIOR_UNVERIFIED | Ordering is correct and tested: `stopRecording()` saves, then sets `phase=replaying`, then calls `audioPlayerService.play(..., awaitCompletion: true)` (`practice_state.dart:140-156`); `practice_state_test.dart#stopRecording saves BEFORE replaying` asserts the save landed before the first play. Audible playback needs a device. Unguarded hang risk on the completion await — see gap 3. |
| 3 | Every recorded answer appears immediately in History; tapping an entry plays its recording | PRESENT_BEHAVIOR_UNVERIFIED | The list half is genuinely verified against a real SQLite engine: `listSessions()` orders `id DESC`, `listAnswersForSession()` scopes with `where: 'session_id = ?'` + `orderBy: 'id ASC'`, both covered by passing tests in `test/db/database_helper_test.dart`. The tap-to-play half (`session_detail_screen.dart:84` → `_play` → `AudioPlayerService.play`) is wired but needs a device. |
| 4 | Force-killing mid-use and relaunching still shows every already-recorded answer | PRESENT_BEHAVIOR_UNVERIFIED | Strong code evidence: `insertAnsweredSession` writes session + answer in one `db.transaction()` only after `recordingService.stop()` returns a finalized path; `PRAGMA foreign_keys = ON` in `_onConfigure`; `pruneOrphanRecordings` awaited before arming. All covered by passing real-SQLite tests. But Plan 01-03 marks the force-kill test `verification: backstop` and D-07 requires a real process kill — impossible in this environment. |
| 5 | Screens use large readable text and a simple, colorful, friendly visual style | FAILED | Palette, type scale and touch targets are exactly per UI-SPEC in `main.dart:18-94`. However the locked Baloo 2 typography (D-15) does not ship in a release build: google_fonts fetches at runtime, no font is bundled, and the main Android manifest has no INTERNET permission. See gap 2. |

**Score:** 0/5 truths verified (3 present, behavior-unverified; 2 failed)

The 0/5 headline is not a claim that three of the criteria are broken. Criteria 2, 3 and 4 have strong code-level and real-SQLite test evidence and are pending on-device UAT only — this environment has no device, so their runtime behavior cannot be certified. Criteria 1 and 5 have observable code-level defects independent of any device.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `pubspec.yaml` | record/audioplayers/sqflite/path_provider/path + sqflite_common_ffi dev dep | VERIFIED | All present at the CLAUDE.md-specified versions; `google_fonts: ^8.2.1` added per D-15 |
| `lib/main.dart` | App entrypoint + UI-SPEC theme | VERIFIED | Every UI-SPEC hex present as a named constant; textTheme maps all 4 roles |
| `lib/db/database_helper.dart` | Schema + insertAnsweredSession + listSessions + listAnswersForSession | VERIFIED | Plus `listReferencedAudioPaths()` and `_onConfigure` FK pragma; 14 passing tests against sqflite_common_ffi |
| `lib/models/session.dart` | Session model | VERIFIED | fromMap/toMap; tested |
| `lib/models/question_answer.dart` | QuestionAnswer model | VERIFIED | fromMap/toMap; tested |
| `lib/services/recording_service.dart` | start/stop, 60s auto-stop, first-stop-wins | ⚠️ WIRED, UNTESTED | All three behaviors present in code. Zero test coverage — no `test/services/` directory exists |
| `lib/services/audio_player_service.dart` | play/stop wrapper | ⚠️ WIRED, UNTESTED | Present; `awaitCompletion` path has an unbounded await (gap 3). Zero direct tests |
| `lib/utils/audio_paths.dart` | ensureRecordingsDir + toAbsolutePath + prune | VERIFIED | 3 passing prune tests in `test/utils/audio_paths_test.dart` |
| `lib/data/questions.dart` | ~5 hardcoded questions | VERIFIED | 5 questions, plain ASCII, D-02 satisfied |
| `lib/state/practice_state.dart` | Full record/save/replay/reset loop | ⚠️ PARTIAL | Loop is complete and correctly ordered, but `idle`/`saving`/`replaying` are unrecoverable on the failure paths (gaps 1, 3) |
| `lib/screens/practice_screen.dart` | Auto-start, Stop button, replay indicator, History nav | ⚠️ PARTIAL | All present; renders no affordance for `idle` and `saving` phases |
| `lib/screens/history_screen.dart` | Session list, empty state, tap-to-open | ⚠️ PARTIAL | Correct list/empty/order behavior; swallows read errors into the empty state (gap 4) |
| `lib/screens/session_detail_screen.dart` | Answers list, tap-to-replay | ⚠️ PARTIAL | Correct; same error-swallowing pattern |
| `lib/widgets/mascot.dart` | 120px mascot, idle/listening/error, accent pulse ring | VERIFIED | 4 passing widget tests including the dispose-without-recording crash regression |
| `android/.../AndroidManifest.xml` | RECORD_AUDIO | ⚠️ PARTIAL | RECORD_AUDIO present. INTERNET missing from the main manifest, which breaks Baloo 2 in release (gap 2) |
| `ios/Runner/Info.plist` | NSMicrophoneUsageDescription | VERIFIED | Key present |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| `practice_state.dart` | `recording_service.dart` | `recordingService.start()` (:90), `recordingService.stop()` (:126) | WIRED |
| `practice_state.dart` | `database_helper.dart` | `databaseHelper.insertAnsweredSession(...)` (:140), after a non-null finalized path | WIRED |
| `practice_state.dart` | `audio_player_service.dart` | `audioPlayerService.play(absolutePath, awaitCompletion: true)` (:156), after the DB commit | WIRED |
| `history_screen.dart` | `database_helper.dart` | `widget.databaseHelper.listSessions()` (:28) via FutureBuilder | WIRED |
| `session_detail_screen.dart` | `database_helper.dart` | `listAnswersForSession(session.id!)` (:36) via FutureBuilder | WIRED |
| `practice_screen.dart` | `mascot.dart` | `Mascot(isRecording: ..., isError: ...)` (:118) | WIRED |
| `main.dart` theme | all 3 screens | Theme text roles consumed | WIRED (pattern variance) — screens use `final theme = Theme.of(context)` then `theme.textTheme.X`, not the literal `Theme.of(context).textTheme`. Functionally identical; 18 call sites confirmed |
| `recording_service.dart` | `practice_state.dart` | `RecordingPermissionDeniedException` caught → `PracticePhase.error` | WIRED (:94-100) |
| `practice_state.dart` | `practice_screen.dart` | `phase == PracticePhase.error` → error banner + Retry | WIRED (:88, 95-99) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `history_screen.dart` | `_sessionsFuture` | `DatabaseHelper.listSessions()` → `db.query(sessions, orderBy: 'id DESC')` | Yes — real SQLite query, no static return | FLOWING |
| `session_detail_screen.dart` | `_answersFuture` | `listAnswersForSession(id)` → parameterised `db.query` | Yes | FLOWING |
| `practice_screen.dart` | `_state.currentQuestion` | `_pickQuestion()` over `kQuestions` (5 real strings) | Yes | FLOWING |
| `practice_screen.dart` | `_state.phase` | Mutated by the real record/save/replay loop | Yes | FLOWING |
| `session_detail_screen.dart` | `answer.audioPath` | DB column → `toAbsolutePath()` → `DeviceFileSource` | Yes — relative path stored, resolved at play time | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full test suite | `flutter test` | `00:03 +32: All tests passed!` (exit 0) | PASS |
| RecordingService has a test file | `ls test/services/` | Directory does not exist | FAIL — no coverage for the 60s timer or the first-stop-wins guard |
| google_fonts fetches at runtime | `grep allowRuntimeFetching` in package source | `if (GoogleFonts.config.allowRuntimeFetching)` gates an HTTP fetch; default true | CONFIRMED (gap 2) |
| Release build has INTERNET permission | `grep -rn INTERNET android/` | Only `src/debug` and `src/profile` | FAIL (gap 2) |
| Baloo 2 bundled as an asset | `grep '^  fonts:' pubspec.yaml` | No active `fonts:` or `assets:` section; no .ttf anywhere in the repo | FAIL (gap 2) |
| onPlayerComplete replays missed events | inspect `audioplayers-6.8.1/lib/src/audioplayer.dart:97` | `StreamController<AudioEvent>.broadcast()` — no replay buffer | CONFIRMED hang risk (gap 3) |
| Real mic capture / audible playback / force-kill | — | No device or emulator available | SKIP → human verification |

### Probe Execution

Not applicable — this phase declares no probes and the project has no `scripts/*/tests/probe-*.sh` convention.

### Requirements Coverage

All 12 requirement IDs mapped to Phase 1 in REQUIREMENTS.md are claimed by a plan. No orphaned requirements.

| Requirement | Source Plan | Status | Evidence |
|---|---|---|---|
| LOOP-03 (recording starts automatically) | 01-01 | NEEDS HUMAN | `_bootstrap()` → `startNewQuestion()` wired; real mic capture is device-only. UI enters the recording state before the recorder is armed |
| LOOP-04 (auto-stop after `d`) | 01-01 | NEEDS HUMAN | `Timer(kMaxRecordingDuration = 60s)` wired to `onAutoStop`; no test constructs the timer |
| LOOP-05 (large always-visible stop button) | 01-01 | BLOCKED | 96px button exists, but it is absent in `idle`/`saving`/`error`, and tapping it during arming produces an unrecoverable `idle` |
| LOOP-06 (auto-replay on stop) | 01-01 | NEEDS HUMAN | `play(..., awaitCompletion: true)` wired after the DB commit; audibility is device-only |
| PERSIST-01 (write immediately after capture) | 01-01, 01-03 | SATISFIED | Single-transaction write invoked only after a non-null finalized path; covered by passing real-SQLite tests |
| PERSIST-02 (survives kill mid-session) | 01-01, 01-03 | NEEDS HUMAN | Transaction + FK pragma + orphan sweep all verified in code and tests; D-07 force-kill is a locked on-device proof |
| HIST-01 (every session in the list) | 01-01 | SATISFIED | `listSessions()` `id DESC` + empty state; tested |
| HIST-02 (session detail shows its questions) | 01-01 | SATISFIED | `where: 'session_id = ?'`, `orderBy: 'id ASC'`; tested including cross-session scoping |
| HIST-03 (tap a question to play it) | 01-01 | NEEDS HUMAN | `onTap: () => _play(answer)` wired; audibility is device-only |
| HIST-04 (persist across restarts) | 01-03 | NEEDS HUMAN | Reads are pure (`db.query` only, no writes); relaunch behavior is device-only |
| UI-01 (large readable fonts) | 01-02 | SATISFIED (with caveat) | 32/24/18/16 scale, no textScaler pin, scrollable question column, 96px and 64px touch targets. Font-family caveat in gap 2 |
| UI-02 (colorful/friendly, not corporate-grey) | 01-02 | BLOCKED | Palette and mascot verified in code, but the locked Baloo 2 face does not ship in release builds |

**Bookkeeping note:** REQUIREMENTS.md lines 66-67 still show UI-01 and UI-02 unchecked, and the traceability table (lines 136-137) still marks them `Pending`, even though Plan 01-02 claimed and implemented them. LOOP-03..HIST-04 were updated to `Complete`. This is a tracking inconsistency to resolve alongside the gaps.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| — | — | `TBD` / `FIXME` / `XXX` debt markers | — | None found in `lib/` or `test/` — clean |
| — | — | `TODO` / `HACK` / `PLACEHOLDER` | — | None found — clean |
| `lib/services/recording_service.dart` | 78 | `return null` | Info | Intentional first-stop-wins sentinel, documented. Not a stub — but its `null` is what the caller mishandles (gap 1) |
| `lib/screens/history_screen.dart` | 48 | `snapshot.data ?? const []` | Warning | Error coerced to the empty state (gap 4) |
| `lib/screens/session_detail_screen.dart` | 36 | `widget.session.id!` force-unwrap | Info | Reachable only via a DB-loaded Session, which always has an id |
| `lib/utils/audio_paths.dart` | 22 | Mutable public global `documentsDirProvider` | Info | Test seam living in production code; production code never reassigns it |
| `lib/state/practice_state.dart` | 86 | Millisecond-resolution file names | Info | Two recordings inside the same millisecond would collide; not reachable given a >0s recording |

No blocker-severity anti-patterns and no unreferenced debt markers. The gaps in this report come from control-flow analysis, not from marker scanning.

### Human Verification Required

Five items, listed in full in the `behavior_unverified_items` frontmatter above. In priority order:

**1. D-07 force-kill test (SC-4) — the phase's defining risk.**
Record and finish at least 2 answers, force-kill the app from the OS task switcher, relaunch, open Exercise History. Then repeat with a kill *during* an active recording. Expect: every finished answer intact and playable; the in-flight recording leaves no session row, no history entry, and its partial file swept from disk. Plan 01-03 explicitly declares this `verification: backstop` — the user locked it as non-inferable from unit tests.

**2. Audible auto-replay and loop reset (SC-2).**
Finish a recording and listen. Expect audible playback, then a new question with recording re-armed. Watch specifically for the loop freezing at "Playing your answer…" — that is the gap-3 hang.

**3. Tap-to-replay from history (SC-3 / HIST-03).**
Tap a question row in session detail; expect that specific recording to play.

**4. Visual style and text scale (SC-5).**
Confirm the warm palette and mascot read as friendly. Raise the OS text size to maximum and confirm the longest question reflows without clipping. **Check in a release build whether Baloo 2 actually loads** — debug builds will load it because the debug manifest grants INTERNET, so a debug check will not surface gap 2.

**5. Leading-audio loss on auto-start (SC-1 / LOOP-03).**
Speak the instant the question appears, tap STOP immediately, replay. Expect your first words to be present. Also confirm no blank/frozen screen while the first-launch mic permission dialog is pending.

### Gaps Summary

The phase built the right architecture and the persistence layer is genuinely solid — the single-transaction write after file finalization, the foreign-key pragma, the relative-path storage, and the orphan sweep are all real, correctly ordered, and covered by tests that run against an actual SQLite engine rather than a mock. 32/32 tests pass and `flutter analyze` is clean. The record → save → replay → history happy path is fully wired end to end.

What is missing is robustness on the failure edges of that loop, and one shipping defect.

**The practice loop has three unrecoverable dead ends.** `PracticePhase.idle` and `PracticePhase.saving` render no control whatsoever in `PracticeScreen`, yet both are reachable: `idle` whenever `recordingService.stop()` returns null (which happens if the user taps the already-visible STOP button before `start()` finishes arming), and `saving` whenever `stop()` throws, since `stopRecording()` wraps only the database call in a try/catch. `replaying` is a third, reached if the unbounded `onPlayerComplete.first` await never resolves — and that stream is a non-replaying broadcast controller, so a missed completion event is permanent. In each case the user is left on a screen with a question and no way forward. The arming-window case is the worst: the recorder then starts for real and can never be stopped, because the 60s auto-stop callback early-returns on `phase != recording`, so a full answer is captured and silently discarded.

**The locked Baloo 2 typography does not ship.** google_fonts fetches over the network at runtime, nothing is bundled, and the INTERNET permission exists only in the debug and profile manifests. Release builds will silently fall back to Roboto. The 01-02 SUMMARY flagged the runtime fetch honestly as a threat flag and even named the remediation; what it did not catch is that the release manifest makes the fetch impossible rather than merely optional.

**The two riskiest units have no tests.** `RecordingService` — which owns the 60s deadline and the first-stop-wins guard, i.e. exactly the two behaviors the phase goal names — has zero test coverage. The `FakeRecordingService` in `practice_state_test.dart` overrides both `start()` and `stop()` completely, so no test ever constructs the `Timer` or exercises the `_stopping` flag. The test named "a losing stop signal writes nothing — first stop wins" proves only that `PracticeState` handles a null return; it cannot reproduce the race it is named for.

Nothing here is deferred to a later phase. Phase 2 adds the Setup screen and multi-question loop with pause/resume, but none of its success criteria cover the failure-path recovery, the font packaging, or the recorder test coverage identified above.

---

_Verified: 2026-08-08_
_Verifier: Claude (gsd-verifier)_
