---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 03
current_phase_name: real-question-bank-via-firestore
status: executing
stopped_at: Phase 3 UI-SPEC approved
last_updated: "2026-08-09T07:39:38.653Z"
last_activity: 2026-08-09
last_activity_desc: Phase 03 execution started
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 14
  completed_plans: 11
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-09)

**Core value:** The user can drill spoken English under real time pressure (timed prompt → forced recording → auto-advance) and can always go back and listen to exactly what they said on any past question.
**Current focus:** Phase 03 — real-question-bank-via-firestore

## Current Position

Phase: 03 (real-question-bank-via-firestore) — EXECUTING
Plan: 1 of 3
Status: Executing Phase 03
Last activity: 2026-08-09 — Phase 03 execution started

Progress: [████████████████████] 11/11 plans (100%) — Phases 1-2 of 4 complete

## Performance Metrics

**Velocity:**

- Total plans completed: 11
- Average duration: - min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 6 | - | - |
| 02 | 5 | - | - |

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
- [Phase 2]: The release build carries `RECORD_AUDIO` as its only permission. Phase 3 adds Firestore and will be the first change to require `INTERNET` in the release manifest — a deliberate, documented departure from the current no-network posture.
- [Roadmap]: Topics derived from Firestore `subject` values are deferred to Phase 3 — Phases 1-2 build against placeholder topic data so crash-safety and timer precision aren't coupled to Firebase wiring.

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 3]: Adding Firestore introduces the app's first network dependency and the first `INTERNET` permission in the release build. The loop must stay usable offline — decide where the question fetch happens (setup only, never mid-loop) before planning.
- [Phase 3]: Firestore rules will be open (no auth) by design. This is an accepted single-user tradeoff, but it must be written down in the phase that sets the rules, not left implicit.

_Resolved in Phase 2:_ the iOS `AudioInterruptionMode` `-10868` risk was settled by a real-device answered-call test (D-31), and the `arming` window question was resolved by the countdown absorbing it.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 | Shuffle/randomize question order within a topic (LOOP-V2-01) | Deferred to v2 | Requirements definition |
| v2 | Re-record a single past question from history (HIST-V2-01) | Deferred to v2 | Requirements definition |
| v2 | Playback speed control on saved recordings (HIST-V2-02) | Deferred to v2 | Requirements definition |

## Session Continuity

Last session: 2026-08-09T06:44:10.645Z
Stopped at: Phase 3 UI-SPEC approved
Resume file: .planning/phases/03-real-question-bank-via-firestore/03-UI-SPEC.md
