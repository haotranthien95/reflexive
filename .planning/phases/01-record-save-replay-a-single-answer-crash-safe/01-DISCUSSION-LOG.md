# Phase 1: Record, Save & Replay a Single Answer (Crash-Safe) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-07
**Phase:** 1-Record, Save & Replay a Single Answer (Crash-Safe)
**Areas discussed:** Trigger & prompt shape, History data model, Recording defaults, Visual style specifics

---

## Trigger & prompt shape

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-start on open | Screen opens, question appears, recording begins immediately, no button | ✓ |
| Tap to start | Question appears, user taps a big Start button to begin | |

**User's choice:** Auto-start on open

| Option | Description | Selected |
|--------|-------------|----------|
| One fixed question | Always the same hardcoded text | |
| Small rotating list | ~5 hardcoded questions, one picked each time the screen opens | ✓ |
| No question text | Just "Tap to record your answer", no question | |

**User's choice:** Small rotating list

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for another take | Screen resets to a fresh question, ready to record again | ✓ |
| Stay on result | Shows replay/re-record controls, waits for manual continue | |
| Jump to History | Navigates immediately to the History list | |

**User's choice:** Ready for another take

| Option | Description | Selected |
|--------|-------------|----------|
| Just a big Stop button | Minimal, no extra chrome | ✓ |
| Stop button + elapsed timer | Shows seconds counted so far | |
| Stop button + countdown to auto-stop | Shows seconds remaining until auto-stop | |

**User's choice:** Just a big Stop button
**Notes:** None.

---

## History data model

| Option | Description | Selected |
|--------|-------------|----------|
| One-question sessions | sessions + question_answers tables now, schema ready for Phase 2 | ✓ |
| Flat answers list | Single answers table now, restructure later | |

**User's choice:** One-question sessions

| Option | Description | Selected |
|--------|-------------|----------|
| List of sessions | Session-first list, tap opens session detail | ✓ |
| List of answers directly | Flat list, skip session-detail step | |

**User's choice:** List of sessions

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, manual crash test | Explicit verification: start recording, force-kill, relaunch, confirm | ✓ |
| Automated approximation only | Rely on unit/integration tests only | |

**User's choice:** Yes, manual crash test

| Option | Description | Selected |
|--------|-------------|----------|
| No trace — only completed answers | Row+file written only once recording fully stopped | ✓ |
| Show as interrupted/failed | Write a placeholder row, mark failed if never confirmed | |

**User's choice:** No trace — only completed answers
**Notes:** None.

---

## Recording defaults

| Option | Description | Selected |
|--------|-------------|----------|
| 60 seconds | Generous default max recording duration | ✓ |
| 30 seconds | Shorter default | |

**User's choice:** 60 seconds

| Option | Description | Selected |
|--------|-------------|----------|
| Always on | Every recording auto-replays after stopping | ✓ |
| Always off | Recordings never auto-play | |
| Simple in-screen toggle | Lightweight toggle switch, not full Setup UI | |

**User's choice:** Always on

| Option | Description | Selected |
|--------|-------------|----------|
| Package defaults | Use record package's default codec/bitrate | ✓ |
| I want to specify | User has a specific quality/format concern | |

**User's choice:** Package defaults
**Notes:** None.

---

## Visual style specifics

| Option | Description | Selected |
|--------|-------------|----------|
| Warm & playful | Coral/orange/yellow-forward palette | ✓ |
| Cool & fresh | Teal/blue/mint-forward palette | |
| Vibrant multi-color | Duolingo-style multiple bold accents | |

**User's choice:** Warm & playful

| Option | Description | Selected |
|--------|-------------|----------|
| No mascot | Colors/icons/shapes carry personality | |
| Simple mascot | Small recurring character, e.g. mic-with-face icon | ✓ |

**User's choice:** Simple mascot

| Option | Description | Selected |
|--------|-------------|----------|
| Duolingo-style | Playful, rounded, bold saturated colors | ✓ |
| Headspace-style | Softer pastel, calm, rounded | |
| No specific reference | Trust design judgment | |

**User's choice:** Duolingo-style

| Option | Description | Selected |
|--------|-------------|----------|
| Friendly Google Font | Rounded playful font (e.g. Fredoka, Baloo 2) | ✓ |
| Default Material font, bigger | Keep default family, just size up | |

**User's choice:** Friendly Google Font
**Notes:** Requires adding the `google_fonts` package, which is not yet listed in CLAUDE.md's stack — flagged in CONTEXT.md for researcher/planner confirmation.

---

## Claude's Discretion

- Exact rotating question wording, exact hex values within the warm & playful palette, and the specific mascot design/asset are left to implementation.

## Deferred Ideas

None — discussion stayed within Phase 1 scope.
