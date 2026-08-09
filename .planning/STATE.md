---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 4
current_phase_name: Bulk Import, Seed Content & Screen Polish
status: planning
stopped_at: Phase 4 context gathered
last_updated: "2026-08-09T14:12:31.713Z"
last_activity: 2026-08-09
last_activity_desc: Phase 03 UAT passed 7/7, phase complete, transitioned to Phase 4
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 14
  completed_plans: 14
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-09)

**Core value:** The user can drill spoken English under real time pressure (timed prompt → forced recording → auto-advance) and can always go back and listen to exactly what they said on any past question.
**Current focus:** Phase 4 — Bulk Import, Seed Content & Screen Polish

## Current Position

Phase: 4 — Bulk Import, Seed Content & Screen Polish
Plan: Not started
Status: Ready to plan
Last activity: 2026-08-09 — Phase 03 UAT passed 7/7, phase complete, transitioned to Phase 4

Progress: [████████████████████] 14/14 plans (100%) — Phases 1-3 of 4 complete

## Performance Metrics

**Velocity:**

- Total plans completed: 14
- Average duration: - min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 6 | - | - |
| 02 | 5 | - | - |
| 03 | 3 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 1]: Crash-safe write ordering is locked — finalize the audio file, then one SQLite transaction, then replay. Phase 2's multi-question loop must keep this ordering per question.
- [Phase 1]: The `sessions` + `question_answers` schema is frozen for Phase 2 to extend without a migration.
- [Phase 1]: Services reach the platform through injectable backend seams (`RecorderBackend`, `AudioPlaybackBackend`, `documentsDirProvider`) — new loop logic should stay testable on the host the same way.
- [Phase 1]: Baloo 2 is a bundled asset with runtime fetching off; the app makes no outbound request. Phase 3 adds Firestore and will be the first thing to need network.
- [Phase 2]: `PlaceholderQuestionSource` (`lib/data/questions.dart`) is the documented Phase 3 swap seam — replacing it with the Firestore-backed source is the core of Phase 3, and SETUP-01 (topics = distinct `subject` values) rides on it.
- [Phase 2]: An OS interruption parks the session paused and commits the partial answer; it never auto-resumes recording. Phase 3's network fetch must not re-enter the loop in a way that bypasses this.
- [Phase 3]: The placeholder bank is **deleted**, not kept as a fallback (D-36) — `lib/data/questions.dart` holds only the `QuestionSource` seam and `FirestoreQuestionSource`; test data lives in `test/fixtures/questions.dart`. Phase 4's importer must not reintroduce a second in-app bank.
- [Phase 3]: A session's questions are resolved on **Setup** and handed to the loop as a plain `List<String>` (D-33/D-34). `PracticeState` holds no `QuestionSource`. Phase 4's import flow must keep the fetch on Setup — there is no network path out of the practice screen and it should stay that way.
- [Phase 3]: The per-session fetch is a real server-side query — `subject in […]` + `level ==` + `orderBy created_at` — behind the composite index in `firestore.indexes.json` (D-32). `whereIn` caps at 30 values, guarded explicitly by `kMaxTopicsPerQuery`. Phase 4's seeding must keep the index deployed (`firebase deploy --only firestore:rules,firestore:indexes`).
- [Phase 3]: Firestore rules are deployed **from the repo** (`firestore.rules`), never edited in the console — a console edit is invisible to review and is overwritten by the next deploy. Phase 4's in-app importer writes through these same open rules.
- [Phase 3]: A read failure and an empty bank are different states with different copy and different affordances; a cache-served zero-document read is unreachable, not empty. Verified end-to-end in UAT test 6. Phase 4's import result messaging should follow the same rule.

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 4]: A device that has never been online has an empty Firestore cache and **cannot start a session** — this is the accepted, documented narrowing of the offline promise (D-39/D-36). Phase 4 seeds the starter content; if seeding is expected to make a fresh install usable offline, that is a different mechanism (bundled seed JSON) and a new decision, not something the current design delivers.
- [Phase 4]: The open `questions` rules allow unauthenticated **write**. Phase 4's in-app importer is the first client-side writer through them, which is exactly the exposure D-46 accepted — no new decision needed, but the importer should not widen the surface further (no new collections, no rule relaxation).

_Resolved in Phase 2:_ the iOS `AudioInterruptionMode` `-10868` risk was settled by a real-device answered-call test (D-31), and the `arming` window question was resolved by the countdown absorbing it.

_Resolved in Phase 3:_ both Phase 3 concerns are discharged. The network-dependency concern was answered by D-33/D-34 (both reads on Setup, none inside the loop) and verified on-device by UAT test 6; the open-rules concern was written down in full in `firestore.rules`, PROJECT.md Key Decisions (D-46) and CLAUDE.md, rather than left implicit.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 | Shuffle/randomize question order within a topic (LOOP-V2-01) | Deferred to v2 | Requirements definition |
| v2 | Re-record a single past question from history (HIST-V2-01) | Deferred to v2 | Requirements definition |
| v2 | Playback speed control on saved recordings (HIST-V2-02) | Deferred to v2 | Requirements definition |

## Session Continuity

Last session: 2026-08-09T14:12:31.690Z
Stopped at: Phase 4 context gathered
Resume file: .planning/phases/04-bulk-import-seed-content-screen-polish/04-CONTEXT.md
