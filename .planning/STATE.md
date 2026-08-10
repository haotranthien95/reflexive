---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 04
current_phase_name: bulk-import-seed-content-screen-polish
status: executing
stopped_at: "Phase 4 plan 04-05 task 4 — on-device UAT deferred by the developer"
last_updated: "2026-08-10T08:15:00.000Z"
last_activity: 2026-08-10
last_activity_desc: "Phase 04 plan 04-05 tasks 1+3 done; task 4 (Android device UAT) temporarily skipped"
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 19
  completed_plans: 18
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-09)

**Core value:** The user can drill spoken English under real time pressure (timed prompt → forced recording → auto-advance) and can always go back and listen to exactly what they said on any past question.
**Current focus:** Phase 04 — bulk-import-seed-content-screen-polish

## Current Position

Phase: 04 (bulk-import-seed-content-screen-polish) — EXECUTING (paused at a human gate)
Plan: 5 of 5 (04-05 in progress — 3 of its 4 tasks done)
Status: Phase 04 blocked on plan 04-05 Task 4, an on-device checkpoint the developer has temporarily skipped
Last activity: 2026-08-10 — 04-05 tasks 1+3 complete; task 4 (Android device UAT) deferred

Progress: [████████████████░░░░] 18/19 plans (95%) — Phases 1-3 complete, Phase 4 at 4/5 plans

### Plan 04-05 — partial progress (do NOT treat as complete; no SUMMARY.md exists)

| Task | What it was | Status |
|------|-------------|--------|
| 1 | Re-verify the release build's permission set after `file_picker` | ✓ committed `3eba6ec` |
| 2 | Confirm the one-way wipe of the live `questions` collection (D-58) | ✓ developer chose option-a (wipe) |
| 3 | Wipe the collection, redeploy rules+indexes, read back zero | ✓ read-back exit 0, `0 documents` |
| 4 | Seed the live bank on a device through the app's own importer | ○ **DEFERRED — needs a phone** |

Task 1 finding: the merged release manifest declares `RECORD_AUDIO`, `INTERNET`,
`ACCESS_NETWORK_STATE` and the app-scoped `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` —
unchanged from Phase 3; the file picker contributed no permission. It DID require an
Android build-config fix (KGP scoped to the `file_picker` subproject in
`android/build.gradle.kts`): the release build had been broken since 04-01 and no host
test could catch it, because `flutter test` never invokes the Android toolchain.

Task 4 fixtures are pre-built and waiting; regenerate them with the same shapes if the
scratchpad is gone. Resume with `/gsd-execute-phase 4`.

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
- **[Phase 4 — LIVE DATA] The `questions` collection in `reflex-english` is currently EMPTY (0 documents).** Plan 04-05 Task 3 wiped the Phase 3 dev seed on 2026-08-10 (D-58, developer-confirmed), and Task 4 — which re-seeds it — is deferred. **The app therefore shows an empty bank on every device right now and cannot start any session.** D-57 forbids re-seeding by any route other than the app's own importer on a device, so the only fix is to finish Task 4. The content is safe: all 600 rows live in `seed/seed-questions.json` in the repo, which is exactly the way back D-57 kept the one-way door open for.
- [Phase 4]: Plan 04-05 Task 4 step 13 expects a "not JSON at all" file to show the *unreadable* message with no shape block, but `parseImportFile` routes every content problem — invalid JSON included — to `ImportFileShapeException`, i.e. the shape branch WITH the block. The unreadable branch is reserved for a genuine read/decode failure in `json_file_picker.dart`, and D-62's doc comment says that split is deliberate. Likely a wording defect in the plan step, not in the code; settle it on-device by importing both a bad-UTF-8 file and a readable-but-not-JSON file and recording which surface each produces.
- [Phase 4]: `ImportSkip.questionText` is documented as null "so the sheet omits the sub-line entirely instead of rendering a blank one", but `echoableContent` tests `isNotEmpty` on the RAW string, so whitespace-only content is echoed. Watch for a blank sub-line on the blank-content skip row during Task 4 step 12.

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

Last session: 2026-08-10
Stopped at: Phase 4 plan 04-05 Task 4 — the on-device import UAT, temporarily skipped by the developer
Resume file: .planning/phases/04-bulk-import-seed-content-screen-polish/04-05-PLAN.md

To resume: `/gsd-execute-phase 4`. Task 4 needs a physical device — build a fresh release
APK first (`3eba6ec` fixed a release build that had been broken since 04-01), push
`seed/seed-questions.json`, and work groups A–H, then hand back so the agent can re-run
Task 3's wipe before the final restoring import (group I, step 23a). The phase cannot be
verified or marked complete until that checkpoint passes — group I included.
