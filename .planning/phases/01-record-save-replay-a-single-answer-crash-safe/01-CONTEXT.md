# Phase 1: Record, Save & Replay a Single Answer (Crash-Safe) - Context

**Gathered:** 2026-08-07
**Status:** Ready for planning

<domain>
## Phase Boundary

A single screen that proves the core record → save-immediately → replay → history loop survives an app kill, before any timed multi-question loop, Setup screen, or Firestore question bank exist (those are Phases 2-4). Recording starts automatically, is backed by a hardcoded rotating question list, auto-stops at a hardcoded max duration (or is stopped manually), optionally auto-replays, and is persisted to local storage question-by-question so a force-kill mid-use loses nothing already captured. Every recording appears in an Exercise History list built on the session/question-answer schema that Phase 2 will extend to multi-question sessions.

</domain>

<decisions>
## Implementation Decisions

### Trigger & prompt shape
- **D-01:** Recording starts automatically the instant the screen opens — no Start button. Matches the "reflex" core value even without Phase 2's pre-record countdown `t`.
- **D-02:** Question text comes from a small hardcoded rotating list (~5 questions), picked each time the screen opens — exercises variability without needing the real Firestore bank (deferred to Phase 3).
- **D-03:** After recording stops (and auto-replay finishes, if enabled), the screen resets to a fresh question and is immediately ready to record again — supports repeated manual testing of the record/save/replay loop.
- **D-04:** While actively recording, the screen shows only a large Stop button — no elapsed timer, no countdown display. Matches the "leanest code" priority; timer/countdown UI is Phase 2 scope (`t`/`d` display).

### History data model
- **D-05:** Build the full `sessions` + `question_answers` schema now, not a flat answers table. Each Phase 1 recording is a session containing exactly one `question_answers` row. Phase 2 only needs to add more rows per session — no schema migration later. — **Reversibility:** one-way — switching from a flat table to session-based schema after Phase 2 code depends on it would require a data migration; deciding it now avoids that.
- **D-06:** The History screen shows a list of sessions (session-first), and tapping one opens session detail showing its question(s). For Phase 1 that detail view happens to show exactly one question, but the screen structure is final — Phase 2 doesn't need to restructure this UI, only populate it with more rows.
- **D-07:** Verification of PERSIST-02 (crash safety) must include an explicit manual test: start a recording, force-kill the app process, relaunch, and confirm the prior save appears in history. This is the phase's core risk and must be proven on a real run, not inferred from unit tests alone.
- **D-08:** If the app is killed while actively recording (before Stop fires and the file is finalized), that recording leaves no trace on relaunch — no placeholder/failed row. A DB row + audio file is only written once recording has fully stopped and the file is finalized. Matches PERSIST-02's literal wording ("already answered questions").

### Recording defaults
- **D-09:** Hardcoded max recording duration (`d`) for this phase: 60 seconds. Configurable `d` arrives with Phase 2's Setup screen.
- **D-10:** Hardcoded auto-replay default (`r`) for this phase: always on. Every recording auto-plays back immediately after stopping, exercising LOOP-06 on every use. (Manual replay-from-history for HIST-03 is tested separately via the History screen.)
- **D-11:** Use the `record` package's default audio codec/bitrate/sample rate (typically AAC/M4A) — no custom quality tuning in this phase.

### Visual style specifics
- **D-12:** Color palette: warm & playful direction — coral/orange/yellow-forward.
- **D-13:** Include a simple recurring mascot/character (not just colorful UI elements) — e.g. a mic-with-face icon shown during recording/result states.
- **D-14:** Visual reference: Duolingo-style — playful, rounded, bold saturated colors, big friendly buttons/touch targets.
- **D-15:** Typography: use a friendly Google Font (e.g. Fredoka, Baloo 2) for headings/question text rather than the default Material font, reinforcing the cartoon-like feel. Add the `google_fonts` package for this (not yet in the stack's package list — flag for research/planner to confirm addition).

### Claude's Discretion
- Exact rotating question text/wording, exact hex values within the warm & playful palette, and the specific mascot design/asset (icon vs. simple illustration) are left to implementation — user gave direction (Duolingo-style, warm palette, mic-with-face-style mascot), not exact specs.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope & requirements
- `.planning/PROJECT.md` — core value, constraints, key decisions (topics deferred to Phase 3, local-only storage, lean-code philosophy)
- `.planning/REQUIREMENTS.md` — full v1 requirement list; this phase covers LOOP-03, LOOP-04, LOOP-05, LOOP-06, PERSIST-01, PERSIST-02, HIST-01, HIST-02, HIST-03, HIST-04, UI-01, UI-02
- `.planning/ROADMAP.md` — Phase 1 goal, success criteria, and dependency on nothing (first phase)

### Stack guidance
- `.claude/CLAUDE.md` — recommended stack (`record`, `audioplayers`, `sqflite`, `path_provider`), "What NOT to Use" table, and rationale for each choice. Note: `google_fonts` (D-15) is not currently listed here — researcher/planner should confirm it fits the "minimize packages" constraint before adding.

No other external specs/ADRs exist yet — this is the project's first phase.

</canonical_refs>

<code_context>
## Existing Code Insights

No Flutter project has been scaffolded yet (`.planning`/`.claude` exist, `lib/`/`pubspec.yaml` do not). This phase's plan must include initial Flutter project setup as a prerequisite step, not just feature code.

### Reusable Assets
- None yet — greenfield.

### Established Patterns
- None yet — greenfield. This phase establishes the first patterns (schema shape, ChangeNotifier-based recording-state management per CLAUDE.md's stack guidance) that later phases will follow.

### Integration Points
- N/A for this phase — no prior code to integrate with.

</code_context>

<specifics>
## Specific Ideas

- "Reflex" framing: recording should start the instant the question appears — no button, no delay — even in this reduced Phase 1 flow without the full pre-record countdown.
- Visual direction: Duolingo-style — playful, rounded, bold warm colors (coral/orange/yellow), big touch targets, a simple mascot/character (mic-with-face style), friendly rounded Google Font for headings.
- Crash-safety is the phase's defining risk: must be proven via an actual force-kill-and-relaunch test, not just code review or unit tests.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope. (Setup screen, timed loop across multiple questions, pause/resume/stop controls, Firestore question bank, and JSON import all remain correctly scoped to Phases 2-4 per ROADMAP.md.)

</deferred>

---

*Phase: 1-Record, Save & Replay a Single Answer (Crash-Safe)*
*Context gathered: 2026-08-07*
