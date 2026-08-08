# Phase 2: Full Timed Practice Session (Setup, Loop & Controls) - Context

**Gathered:** 2026-08-08
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — grey areas proposed in batch, all four areas accepted as recommended

<domain>
## Phase Boundary

Phase 1 proved a *single* recording can be captured, saved crash-safely and replayed. Phase 2 wraps that proven core in the real product: a **Setup screen** where the user configures a session (CEFR level, `question_count`, pre-record countdown `t`, max recording duration `d`, auto-replay `r`, plus topic selection gating Start), and a **multi-question timed loop** that runs the configuration end to end — 3-second session-start countdown → per-question `t` countdown → record (auto-stop at `d` or manual STOP) → optional replay → 3-second inter-question countdown → next question — completing automatically after `question_count` answers. Throughout the session an app bar carries Pause/Resume and Stop-with-confirmation.

**In scope:** SETUP-02..07, LOOP-01, LOOP-02, LOOP-07, LOOP-08, CTRL-01..04.

**Explicitly NOT in scope:**
- **Firestore** — the question bank and real topic list stay placeholder data; SETUP-01/BANK-* are Phase 3. Phase 2 must isolate the question source behind a seam Phase 3 can swap without touching loop logic.
- **JSON import / seed content / final screen audit** — Phase 4 (IMPORT-*, UI-03).
- **Shuffled question order** — LOOP-V2-01 is deferred to v2; Phase 2 draws questions in sequential bank order.
- **Re-recording from history, playback speed** — HIST-V2-01/02, deferred to v2.

Phase 1's crash-safety contract is inherited unchanged: an answer is written only after its audio file is finalized, in one transaction, before replay. Phase 2 extends that to N answers per session without a schema migration (D-05).

</domain>

<decisions>
## Implementation Decisions

### Setup screen — inputs, defaults & validation

- **D-16:** The three numeric settings each render as a **large numeric readout above a slider** — no keyboard, one widget per setting, full range reachable by drag, and big enough to satisfy UI-01/D-14. Ranges and defaults: `question_count` 1–100 (default **10**), `t` 3–30 s (default **5**), `d` 10–120 s (default **60** — matches Phase 1's `kMaxRecordingDuration`, D-09). *Alternatives rejected: preset chips + custom text field; −/+ steppers (too many taps to cross a 1–100 range).*
- **D-17:** CEFR level is a **single-select row of six rounded chips (A1 A2 B1 B2 C1 C2)** that wraps to two lines. Default **B1**. *Alternatives rejected: dropdown, segmented control — both fight the playful/large-target direction (D-14).*
- **D-18:** Setup settings are **not remembered between sessions** — every visit starts from the fixed defaults in D-16/D-17. Rationale: keeps Phase 2 free of any new persistence surface and any schema-version bump, honouring the "leanest code" constraint. *Alternative rejected for now: a one-row settings table (schema 1→2). If re-entering five fields every session becomes annoying in real use, this is the cheapest thing to add later — it is additive and does not disturb the frozen `sessions`/`question_answers` schema.*
- **D-19:** Setup shows a **real, working topic-checkbox section backed by a hardcoded placeholder subject list** (~5 subjects derived from the expanded placeholder question bank). SETUP-07 is genuinely enforced in Phase 2 — **Start is disabled until at least one topic is checked** — and Phase 3 replaces only the data source, not the widget or the validation. *Alternatives rejected: hiding topics until Phase 3 (would leave SETUP-07 unimplemented and untestable); showing always-checked/disabled topics (makes the Start gate a no-op).*

### Timed loop mechanics

- **D-20 (resolves the STATE.md arming-window blocker):** The per-question `t` countdown runs **to zero, and only then does the recorder arm**. The existing Phase 1 `PracticePhase.arming` state and its "Getting ready…" copy cover that window, and the `d` deadline starts only once the microphone is genuinely live. Rationale: preserves Phase 1's honesty contract (never show a STOP button / listening mascot while the mic is cold), keeps countdown audio out of the answer file, and reuses already-tested code. *Alternatives rejected: pre-arming during the final ~1 s of the countdown (eliminates the gap but puts silent pre-roll in every file); arming at countdown start (records the entire countdown).*
- **D-21:** A **remaining-seconds readout of `d` is shown while recording**, beneath the STOP button, so the user can pace an answer. This deliberately supersedes Phase 1's D-04 ("no elapsed timer during recording"), which explicitly scoped timer/countdown UI to Phase 2. The STOP button stays the visually dominant element — the timer is secondary, not a second focal point.
- **D-22:** The two 3-second countdowns (LOOP-01 at session start, LOOP-07 between questions) render as a **full-screen "3 · 2 · 1" with the mascot and the question hidden** — visually distinct from the `t` countdown, which always shows the question text. The two countdowns must never be confusable: one means "get ready to read", the other means "read this now, you speak at 0". LOOP-07's 3-second countdown starts *after* auto-replay finishes when `r` is on.
- **D-23:** The placeholder question list is **expanded to ~20 prompts**, and if `question_count` still exceeds the number of available questions the loop **cycles through the bank again** rather than capping the session. This keeps LOOP-08 literally true for any configured count and makes long sessions testable before Firestore exists. Question order is **sequential bank order, not shuffled** — LOOP-V2-01 is deferred to v2. *Alternative rejected: capping the session at the available count (would silently contradict the configured `question_count` and make Phase 2's loop untestable at realistic lengths against a small placeholder bank).*

### Pause, Stop & session lifecycle

- **D-24:** Pause is a **true pause**, available at every moment of a session including mid-recording (CTRL-01/CTRL-04). It uses `record`'s `pause()`/`resume()` for the microphone and freezes the `d` deadline and any running countdown; Resume continues from exactly where it stopped rather than restarting the current step. This requires extending `RecordingService` with pause/resume and converting the fixed `Timer` deadline into a pausable one. *Alternatives rejected: disabling Pause while recording (violates CTRL-01's "at all times"); pause-stops-and-saves (loses the half-finished answer's continuity).*
- **D-25:** The Stop confirmation dialog (CTRL-03) **auto-pauses the session while it is open** and resumes on cancel. Without this, the `d` deadline fires and the answer auto-saves behind the modal while the user is still deciding.
- **D-26:** The `sessions` row is created **lazily, on the first captured answer** — not at Start. This preserves Phase 1's D-08 guarantee ("nothing captured ⇒ no trace") and keeps History free of empty session rows, so no History-side filtering is needed. Each subsequent answer is inserted in its **own** transaction against that session id, keeping PERSIST-01's per-question durability. A session abandoned before any answer writes nothing at all. *Alternative rejected: creating the row up front and filtering empty sessions out of the History query (two places to keep in sync, and a crash between Start and the first answer would leave a permanent orphan row).*
- **D-27:** When a session ends — completed via LOOP-08 *or* stopped early via CTRL-03 — the app shows a short **completion screen**: "Nice work! N answers recorded", with *Back to setup* and *View this session*. This is a state of the practice screen, not a fourth route, so UI-03 (exactly 3 core screens) still holds. A session stopped before its first answer returns straight to Setup, since there is nothing to view (see D-26).

### Navigation & interruptions

- **D-28:** **Setup becomes the app's home screen.** Start pushes the Practice screen; History is reached from a single app-bar icon on Setup, exactly as it is reached from Practice today. Push-based navigation only — no tab bar, no drawer (UI-03). Phase 1's `PracticeScreen` therefore stops being `home:` and starts taking a session configuration as a constructor argument.
- **D-29:** **The user cannot navigate away from an active session.** The session app bar carries only Pause/Resume and Stop (CTRL-01/02) — no History icon. System Back / the back gesture is intercepted with `PopScope` and routed into the same Stop confirmation dialog (D-25), so there is exactly one way to end a session early and it always confirms.
- **D-30:** **Add `wakelock_plus` and hold a wakelock for the duration of an active session**, releasing it when the session ends or the screen is disposed. The default OS screen timeout is frequently shorter than one `t`+`d` cycle, so without this the screen locks while the user is mid-answer — a real break in the core loop, not a nicety. This is a deliberate, justified exception to the minimize-packages constraint: one small, actively maintained package, used at exactly one call site. *Alternative rejected: deferring it (ships a loop that visibly breaks in normal use).*
- **D-31 (resolves the STATE.md iOS-interruption blocker):** An interruption — incoming phone call, or the app being backgrounded — is **treated as an auto-pause**. If a recording was live, it is finalized and saved first (Phase 1's write ordering is unchanged: finalize file → one transaction → only then anything else), and the session parks in the paused state. Resuming is always an explicit user tap; the app never silently resumes recording after an interruption. A **real-device call-interruption test is a required UAT item for this phase** — the `record` package's `AudioInterruptionMode` behaviour on iOS has a documented `-10868` rough edge that cannot be proven by host tests. *Alternatives rejected: discarding the in-flight recording (throws away a real answer the user already gave); recording through the interruption (not reliably possible on iOS).*

### Claude's Discretion

- Exact copy for the completion screen, the Stop confirmation dialog and the countdown screens (within the established warm/playful voice), exact slider tick behaviour and label formatting, the specific ~20 placeholder prompts and the ~5 placeholder subject names, and how the pausable deadline is implemented internally (stopwatch + rescheduled `Timer` vs. periodic tick) are all left to implementation.
- Whether the timed loop lives in an extended `PracticeState` or a new session-scoped `ChangeNotifier` alongside it is an implementation call — the constraint is that the Phase 1 record→save→replay sequence and its guard/ordering comments survive intact, and that services stay injectable through the same constructor seams.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope & requirements
- `.planning/PROJECT.md` — core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — this phase covers SETUP-02..07, LOOP-01, LOOP-02, LOOP-07, LOOP-08, CTRL-01..04
- `.planning/ROADMAP.md` — Phase 2 goal, success criteria, dependency on Phase 1
- `.planning/STATE.md` — the two Phase 2 blockers listed there are resolved by D-20 (arming window) and D-31 (iOS interruption); the UAT obligation in D-31 remains

### Phase 1 artifacts that constrain this phase
- `.planning/phases/01-record-save-replay-a-single-answer-crash-safe/01-CONTEXT.md` — D-01..D-15, especially D-04 (superseded here by D-21), D-05/D-06 (schema and history structure — frozen), D-08 (no trace unless captured), D-09/D-10 (hardcoded `d`/`r`, now configurable)
- `.planning/phases/01-record-save-replay-a-single-answer-crash-safe/01-UI-SPEC.md` — the locked colour palette, type scale, spacing scale and copywriting contract. Phase 2's new screens must extend this system, not invent a second one.

### Stack guidance
- `.claude/CLAUDE.md` — recommended stack and the "What NOT to Use" table. Note `wakelock_plus` (D-30) is **not** currently listed there; the planner should record it as a deliberate addition with the D-30 rationale.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- **`lib/state/practice_state.dart`** — `PracticeState` (`ChangeNotifier`) already owns the whole record → stop → finalize → save-in-one-transaction → replay → re-arm sequence, with `PracticePhase { idle, arming, recording, saving, replaying, error }`. Its guard comments encode the crash-safety contract; the `_disposed` checks sit deliberately *after* the DB commit and must stay there.
- **`lib/services/recording_service.dart`** — owns the microphone lifecycle behind a `RecorderBackend` seam, with a re-entrancy guard, a "stop during arming is never lost" mechanism, and the `kMaxRecordingDuration` deadline. **Phase 2 must make that deadline configurable (`d`) and pausable (D-24)** — it is currently a fixed `Timer(kMaxRecordingDuration, …)`.
- **`lib/services/audio_player_service.dart`** — replay behind an `AudioPlaybackBackend` seam, with `play(path, awaitCompletion: true)` and a completion timeout derived from `kMaxRecordingDuration` (**that derivation must follow `d` once `d` is configurable**).
- **`lib/db/database_helper.dart`** — `insertAnsweredSession({questionText, audioRelativePath})` creates a session **and** its single answer in one transaction. Phase 2 needs a second write path: create-session-once, then insert-answer-into-existing-session (D-26), each answer in its own transaction. `listSessions()` / `listAnswersForSession()` / `listReferencedAudioPaths()` already support multi-answer sessions with no change.
- **`lib/widgets/phase_control.dart`** — `kPhaseControlKeys` is a deliberately **total** map from `PracticePhase` to a widget key, enforced by `test/widgets/phase_control_test.dart`. Any new phase added in Phase 2 (e.g. a countdown or paused phase) **must** get an entry or that test fails by design.
- **`lib/widgets/mascot.dart`**, **`lib/utils/audio_paths.dart`** (relative-path storage + `pruneOrphanRecordings`), **`lib/utils/date_format.dart`**, **`lib/screens/history_screen.dart`**, **`lib/screens/session_detail_screen.dart`** — all reusable unchanged.

### Established patterns
- **State:** one `ChangeNotifier` + `ListenableBuilder`; no state-management package (per `.claude/CLAUDE.md`).
- **Testability:** every platform dependency sits behind an injectable backend interface (`RecorderBackend`, `AudioPlaybackBackend`, `documentsDirProvider`), constructed lazily so a test with a fake never touches a platform channel. `sqflite_common_ffi` runs `DatabaseHelper` against real SQLite in `flutter test`. Phase 2 logic must stay host-testable the same way — timers included.
- **Theming:** every colour and text style comes from `Theme.of(context)`; `lib/main.dart` is the single source of the palette and type scale. Screens never hardcode a hex value, and `textScaler` is never pinned (UI-01).
- **Error copy:** a single fixed user-facing failure string (`kRecordingErrorMessage`); exception detail goes only to `debugPrint`/`FlutterError.reportError`, never to the screen.
- **Tests mirror `lib/` path-for-path** under `test/`.

### Integration points
- **`lib/main.dart`** — `home: const PracticeScreen()` becomes the new Setup screen (D-28); `configureFonts()` and the theme stay untouched.
- **`lib/screens/practice_screen.dart`** — currently self-bootstraps (`initState` → orphan sweep → `startNewQuestion()`) and owns the History app-bar action. Phase 2 changes it to accept a session configuration, replaces the History action with Pause/Stop (D-29), and moves the orphan sweep to app/Setup start-up so it still runs exactly once before any file name is chosen.
- **`lib/data/questions.dart`** — `kQuestions` is the placeholder bank; Phase 2 expands it to ~20 and adds the placeholder subject list (D-19/D-23) **behind a seam Phase 3 can swap for Firestore**.
- **`android/app/src/main/AndroidManifest.xml` / iOS `Info.plist`** — already carry the microphone permission; `wakelock_plus` (D-30) needs no new Android permission (`WAKE_LOCK` is added by the plugin's own manifest).

</code_context>

<specifics>
## Specific Ideas

- The two countdown *kinds* must be unmistakable at a glance: the `t` countdown always shows the question (read it, you speak at 0); the 3-second countdowns hide it (get ready). Same numerals, deliberately different frames.
- STOP stays the single dominant target while recording — the new `d` readout (D-21) is secondary and must not compete with it.
- The reflex framing survives the added configuration: once Start is tapped, the user should never need to touch the screen again for a whole session unless they want to stop early.
- Crash-safety is still the thing that must not regress. A multi-question session is N independent durable writes, not one write at the end — a force-kill at question 7 of 10 must leave 6 answers in history.

</specifics>

<deferred>
## Deferred Ideas

- **Persisting last-used Setup settings** (D-18) — cheapest future addition if re-entering five fields per session becomes annoying; additive table, no disturbance to the frozen schema.
- **Pre-arming the recorder during the last second of the `t` countdown** (D-20 alternative) — revisit only if real-device use shows the post-countdown arming gap is perceptible.
- **Shuffled question order** (LOOP-V2-01) — v2, per REQUIREMENTS.md.
- **Real topics and the Firestore-backed bank** (SETUP-01, BANK-01..03) — Phase 3; Phase 2 deliberately builds the seam for it.

</deferred>

---

*Phase: 2-Full Timed Practice Session (Setup, Loop & Controls)*
*Context gathered: 2026-08-08*
