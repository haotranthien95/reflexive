# Project Research Summary

**Project:** EnglishReflex — Flutter spoken-English reflex-practice app
**Domain:** Small single-user mobile app — timed audio-recording practice loop with local-first persistence and a thin Firestore-backed question bank
**Researched:** 2026-08-07
**Confidence:** MEDIUM

## Executive Summary

This is a lean, single-user Flutter drill tool — not a platform. Its core loop (countdown → record → auto-stop → optional replay → next question) is closer in shape to Big Interview's prep-time-then-record mechanic than to an AI coaching app like ELSA or Speeko. All four research files converge on the same conclusion: the correct architecture is deliberately small — three screens (Setup, Practice Session, History), three thin service classes (Firestore, Audio, Local DB), two SQLite tables, and one Firestore collection — with no repository interfaces, no DI container, and no third-party state-management package. PROJECT.md's existing Active requirements already match the category's table stakes exactly; research found no missing must-have features and confirmed that scoring, streaks, cloud sync, and admin UI are correctly excluded as anti-features for this product's positioning.

The recommended stack (`record`, `audioplayers`, `cloud_firestore`+`firebase_core`, `sqflite`, `path_provider`, `file_picker`) is lean by design: no code generation, no ORM, no auth. The single biggest technical risk sits squarely in the reliability requirement the user themselves called out — "an app kill/crash mid-session must not lose already-answered questions." Pitfalls research is unambiguous that this is achievable cheaply (insert-as-you-go SQLite writes, temp-file-then-rename for audio, relative file paths) but is also the thing most likely to "look done but isn't" if not deliberately tested with real force-kills and real interruptions (phone calls, backgrounding) rather than just happy-path simulator runs.

The second material risk cluster is timing precision: naive tick-counting timers drift from actual recorded-audio duration, which directly undermines the "reflex" mechanic that is this app's entire value proposition. Both of these risks (crash-safety and timer precision) are cheap to get right from the start and expensive to retrofit — they should be built into the foundational phase(s) rather than treated as polish. Firestore is comparatively low-risk: it's read-mostly, has no live-update requirement, and its main pitfalls (listener overuse, unbatched imports) are easy fixes, not architectural risks.

## Key Findings

### Recommended Stack

The stack is a minimal, no-codegen Flutter toolkit: `record` for capture, `audioplayers` for local-file-only playback, `cloud_firestore`+`firebase_core` for the read-mostly question bank (no Firebase Auth), `sqflite` with hand-written SQL for session/answer history, `path_provider` for resolving on-device directories, and `file_picker` for JSON import. Deliberately rejected: `just_audio` (streaming/background features not needed), `drift`/`floor`/`ObjectBox` (codegen tax disproportionate to a 2-table schema), `Hive`/`Isar` (both effectively abandoned upstream), and any state-management package (`provider`/`riverpod`/`bloc`/`GetX` — a single shared engine object across 3 screens doesn't need one).

**Core technologies:**
- `record` (^7.1.1): microphone capture, start/stop with built-in permission handling — the de-facto standard Flutter recording plugin
- `cloud_firestore` + `firebase_core`: question bank read/import, official Firebase plugins, no Auth product needed (open, documented dev-mode rules)
- `sqflite` (^2.4.3): embedded local DB for session/answer history — raw SQL, zero build_runner, real ACID transactions for crash-safe incremental writes
- Flutter `ChangeNotifier`/`ValueNotifier` (SDK, no package): shares practice-loop state between app bar and screen body without adding a state-management dependency
- `path_provider` + `file_picker`: resolve local storage paths / pick a JSON file for bulk question import

### Expected Features

PROJECT.md's Active requirements already match this category's table stakes with no gaps — research recommends no additions to MVP scope, only confirms it's correctly calibrated.

**Must have (table stakes) — already in scope:**
- Configurable session setup (topics, level, count, countdown `t`, max duration `d`, replay `r`)
- Visible countdown before recording, auto-stop at max duration, manual stop control
- Immediate playback of what was just recorded (recommend defaulting `r` to true)
- Pause/resume mid-session, confirm-before-stop/exit
- Session history list with per-question playback
- Incremental, crash-safe local persistence during a session
- Seeded question content (~10 topics) so first run isn't empty

**Should have (v1.x, add after validation):**
- Shuffle/random question order within a topic (cheap, reinforces "reflex" value)
- Re-record a single past question from history
- Playback speed control on recordings

**Defer indefinitely (v2+ / rejected):**
- Pronunciation/fluency AI scoring — different product category, explicitly out of scope
- Streaks/gamification/analytics dashboard — contradicts "not Duolingo-style" positioning
- Accounts, cloud sync, social features, in-app admin/CMS screen — explicitly out of scope per PROJECT.md

### Architecture Approach

Three screens (Setup → Practice Session → History), three thin service classes (`FirestoreService`, `AudioService`, `LocalDbService`) each wrapping exactly one data source with plain async methods — no repository interfaces, no DI container, manual constructor injection only. The practice loop is modeled as an explicit enum-driven state machine (`SessionPhase`) owned by a `SessionController` (`ChangeNotifier`), separated from the screen widget because it's the one piece of logic complex enough to warrant unit-testing without Flutter noise. History and persistence share a single local data model — history is just "read what the loop already wrote."

**Major components:**
1. `SessionController` — countdown/record/auto-stop/replay state machine, owns the `Timer`, writes each answer immediately after capture
2. `LocalDbService` — sqflite wrapper for `sessions`/`answers` tables, insert-as-you-go, no ORM/codegen
3. `AudioService` — thin wrapper over `record` (capture) + `audioplayers` (playback), file paths stored relative to app-documents dir
4. `FirestoreService` — one-shot `get()` reads for topics/questions, `WriteBatch` for JSON import; never touched mid-session

Recommended build order (vertical slices, not layers): (1) recording + incremental save + playback + minimal history on one hardcoded question — proves crash-safety first; (2) full timed state machine over N questions; (3) Firestore wiring for real question data; (4) JSON import + seed data + pause/resume/stop polish.

### Critical Pitfalls

1. **Countdown timer drift** — decrementing a tick counter instead of computing remaining time from a captured deadline causes the countdown UI and actual recording duration to silently diverge, undermining the core "reflex" mechanic. Fix: always compute `remaining = deadline - now()`, drive both UI and auto-stop off the same clock.
2. **Crash/force-kill mid-write corrupts history or orphans audio files** — the project's own reliability requirement demands atomic incremental writes. Fix: temp-file-then-rename for audio (atomic), write file before metadata row, use `sqflite` transactions, run a startup orphan-file sweep.
3. **Recording silently fails to resume after interruption** (phone call, app switch) — especially an iOS-documented failure mode where mic doesn't reactivate post-interruption. Fix: explicit `AudioInterruptionMode.pause`, subscribe to recorder state stream, pause the whole session (not just audio) on unexpected state change.
4. **App backgrounded/killed mid-recording loses more than expected** — lifecycle callbacks are unreliable (no callback at all on hard kill, false triggers on `inactive`). Fix: rely on incremental writes (not lifecycle hooks) as the actual save mechanism; only act destructively on `paused`, not `inactive`; accept that only the current in-flight question can be lost.
5. **Bulk JSON import partially succeeds silently** — unbatched writes leave the bank inconsistent on network blips. Fix: `WriteBatch` (chunked at 500), client-side schema validation before writing, clear per-row success/failure reporting to the user.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Core recording + crash-safe persistence + minimal playback/history (single hardcoded question)
**Rationale:** This proves the hardest, highest-risk requirement (crash-safety, insert-as-you-go writes, atomic file handling) before any UI polish, looping, or Firestore work exists. Retrofitting crash-safety after the fact is a rewrite, not a patch.
**Delivers:** `AudioService`, `LocalDbService` (schema + incremental insert), relative-path file-naming scheme, bare-bones history list/detail screen.
**Addresses:** Incremental persistence, per-question playback (table stakes from FEATURES.md).
**Avoids:** Pitfall 3 (crash/orphaned files), Pitfall 3's related Anti-Pattern 2 (buffer-then-write-at-end) and Anti-Pattern 3 (absolute file paths).

### Phase 2: Full timed practice loop / state machine over N questions
**Rationale:** Builds the deadline-based countdown/auto-stop/replay mechanic and multi-question looping on top of the already-proven persistence primitives from Phase 1, using a small in-memory (still stubbed) question list.
**Delivers:** `SessionController` enum-driven state machine, wall-clock-based countdown, auto-stop, optional auto-replay, looping.
**Uses:** `record` (capture), `audioplayers` (playback), Flutter `ChangeNotifier`/`Timer` (no state-mgmt package).
**Implements:** Pattern 1 (enum-driven state machine) from ARCHITECTURE.md; must avoid Pitfall 1 (timer drift) and Pitfall 2 (interruption handling) from PITFALLS.md.

### Phase 3: Firestore integration for real question data
**Rationale:** Naturally last among core-loop phases since it only supplies input data to a loop that already works end-to-end; keeps Firestore concerns isolated from the crash-sensitive and timing-sensitive work.
**Delivers:** `FirestoreService.fetchTopics()`/`fetchQuestions()`, Setup screen wired to real data, replacing the hardcoded question list.
**Avoids:** Pitfall 5 (listener overuse — use one-shot `get()`, not `snapshots()`; filter server-side with `where`).

### Phase 4: JSON import + seed data + session-control polish (pause/resume/stop-with-confirm)
**Rationale:** Additive features layered onto an already-working record→save→replay→history loop and Firestore read path; nothing else depends on them, so they're safe to sequence last.
**Delivers:** Bulk JSON import (batched, validated, per-row reporting), ~10 seeded topics, app-bar Pause/Resume/Stop-with-confirm controls tested against real backgrounding/force-kill scenarios.
**Avoids:** Pitfall 6 (partial import inconsistency), Pitfall 4 (lifecycle mishandling — test real background/kill, not just in-app Pause button).

### Phase Ordering Rationale

- Crash-safety (the single highest-risk, explicitly-stated reliability requirement) is proven in Phase 1, before any other complexity is layered on — dependencies point this way per ARCHITECTURE.md's Build Order Implications section.
- Timing precision (Pitfall 1) is built correctly from the start in Phase 2 rather than retrofitted, since UI built around tick-counting would require a rewrite to fix later.
- Firestore is isolated to Phase 3 because FEATURES.md's dependency graph shows Session Setup requiring the question bank, but the Practice Loop itself has no Firestore dependency mid-session — so real Firestore data can be added without touching the loop's internals.
- Import/seed/session-controls are grouped last because FEATURES.md explicitly marks JSON import as "enhances but does not block" core setup, and PITFALLS.md flags pause/resume lifecycle testing as needing the already-working incremental-write foundation to test against meaningfully.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1 (crash-safe persistence):** PITFALLS.md flags this as the phase "most likely to need deeper design attention" — verify current `sqflite` transaction semantics and temp-file-rename patterns at implementation time (sources here were LOW/MEDIUM confidence, general web synthesis).
- **Phase 2 (timed loop, interruption handling):** `record` package's `AudioInterruptionMode` behavior on iOS has known rough edges (documented `-10868` error) — verify against current `record` docs/changelog before implementation, not just this research snapshot.

Phases with standard patterns (skip research-phase):
- **Phase 3 (Firestore integration):** Well-documented via official FlutterFire docs (Context7, MEDIUM confidence); straightforward one-shot reads and batched writes, no novel patterns.
- **Phase 4 (JSON import, seed data, session controls):** Standard Flutter patterns (WriteBatch, WidgetsBindingObserver, confirm dialogs) — established idioms, low ambiguity.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Package identities and architectural fit are well-established and cross-source consistent; exact pinned versions were fetched live from pub.dev and will drift — pin ranges, not patch versions. |
| Features | MEDIUM | PROJECT.md itself (highest-confidence input) already fully specifies scope; competitive research is LOW-confidence web search used only to sanity-check, not to add requirements — no gaps found. |
| Architecture | MEDIUM | Flutter/package API facts confirmed via Context7 official docs (MEDIUM); folder-structure and "don't over-engineer" opinions are LOW-confidence web search but directly justified against the user's own explicit "least code" constraint in PROJECT.md. |
| Pitfalls | MEDIUM | Mix of MEDIUM-confidence official docs (record, cloud_firestore via Context7) and LOW-confidence general web search; no HIGH-confidence curated sources found this run — treat specifics as directional, verify against current package docs at implementation time. |

**Overall confidence:** MEDIUM

### Gaps to Address

- **Exact `record`/`audioplayers`/`cloud_firestore` version numbers will drift** between this research date and implementation — re-verify via `flutter pub add` resolution at setup time rather than hard-pinning what's written here.
- **iOS `AudioInterruptionMode` resume behavior** is flagged as having "known rough edges" from a single GitHub issue reference — needs a real-device manual test (actual phone call mid-recording) during Phase 2, not just code review.
- **Firestore security rules without Auth** are an accepted, documented tradeoff (open rules scoped to `questions` collection) rather than a resolved security posture — worth an explicit note/decision record when Phase 3's Firestore setup happens, not a silent gap.
- **Device storage growth from audio files over months of use** — not needed for v1, but flagged in ARCHITECTURE.md as a future product decision (delete-old-sessions affordance); worth a backlog note rather than v1 scope.

## Sources

### Primary (MEDIUM confidence — official docs via Context7)
- `record` package official docs — Context7 `/llfbandit/record`
- `cloud_firestore`/FlutterFire official docs — Context7 `/firebase/flutterfire`
- Flutter "Add multiplayer support using Firestore" cookbook — Context7 `/websites/flutter_dev`

### Secondary (MEDIUM confidence)
- pub.dev package pages (direct fetch) — version/recency for `record`, `audioplayers`, `just_audio`, `cloud_firestore`, `firebase_core`, `sqflite`, `path_provider`, `file_picker`, `drift`

### Tertiary (LOW confidence — general web search, cross-checked against PROJECT.md constraints)
- Isar/Hive maintenance status, Drift vs sqflite vs Hive positioning, setState-vs-Provider guidance for small apps
- Competitor feature analysis (ELSA Speak, Big Interview, Yoodli, shadowing apps) — used only to validate existing scope, not to add requirements
- Flutter Timer precision patterns, WidgetsBindingObserver lifecycle limitations, atomic-write/temp-file patterns, Firestore offline/cost guidance

---
*Research completed: 2026-08-07*
*Ready for roadmap: yes*
