# EnglishReflex

## What This Is

A simple, colorful Flutter mobile app for practicing spontaneous spoken English ("phản xạ" — reflex speaking practice). The user configures a practice session (topics, CEFR level, question count, timings), then goes through a timed loop: a question appears, a countdown runs, the app records the user's spoken answer, auto-stops after a max duration (or the user stops manually), optionally replays the recording, then moves to the next question. Every session and its recordings are saved locally and can be replayed later. The question bank lives in Firebase and can be extended by importing a JSON file. Built for a single user studying independently, prioritizing speed of use over feature breadth.

## Core Value

The user can drill spoken English under real time pressure (timed prompt → forced recording → auto-advance) and can always go back and listen to exactly what they said on any past question.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Session setup: pick topics (fetched from Firebase, multi-select), CEFR level (A1–C2), question count (1–100), pre-record countdown `t`, max recording duration `d`, and whether to auto-replay `r`
- [ ] Practice loop: 3s countdown to start → per question: show question + `t`s countdown → auto-start recording → auto-stop at `d`s (or manual stop via a large stop button) → replay if `r` is true → 3s countdown to next question → repeat until `question_count` reached
- [ ] Persistent app bar during a session with Pause/Resume and Stop; Stop requires confirmation
- [ ] Exercise history: every session is saved and listed; opening one shows its questions with their recordings, tap a question to play its recording
- [ ] History and audio recordings are stored locally on-device (not in the cloud)
- [ ] Progress is saved incrementally as the session runs (question-by-question), not only at session end — an app kill/crash mid-session must not lose already-answered questions
- [ ] Question bank stored in Firebase with schema `{id, content, subject, level, created_at}`
- [ ] JSON import feature to bulk-add questions to the bank, format: `{"data": [{"content": "...", "subject": "...", "level": "..."}, ...]}` (id/created_at auto-generated on import)
- [ ] ~10 general-purpose starter topics seeded in the question bank (e.g. Daily Life, Travel, Sports, Food, Work, Health, Education, Technology, Family, Entertainment)
- [ ] Deliverable: a reusable prompt (given to the user, not run by the app) that instructs any AI to generate question data in the exact required JSON import format

### Out of Scope

- User accounts / authentication — single local user, no login needed for v1
- Pronunciation scoring / AI feedback on the recording — this app is a recording+replay drill tool, not a grader
- Cloud sync/backup of history or recordings — explicitly local-only per user request
- Social features (sharing, leaderboards) — not part of the stated goal
- Admin web dashboard for managing the question bank — JSON import inside the app is the only bank-management path for v1
- Multi-language support (target language is English only) — out of scope, revisit only if requested later

## Context

- **Format of "phản xạ" practice**: this mirrors spoken-English interview/exam drills — a prompt appears, you have a few seconds to think, then you must speak before a timer cuts you off. The countdown-then-record-then-autostop loop is the entire value proposition; it must feel snappy and never block on network calls mid-loop.
- **Question fetching model**: topics selectable in setup are whatever subjects exist in the Firebase question bank — the app should treat "topics" as the distinct set of `subject` values already present (no separate topics collection needed), keeping the schema minimal and matching the user's stated `{id, content, subject, level, created_at}` shape exactly.
- **Data generation workflow**: the user's process is: (1) app ships with ~10 seed topics worth of questions, (2) user can paste a generated prompt into any LLM to produce more question JSON in bulk, (3) user imports that JSON via the app's import feature. The prompt must hard-enforce the `{"data": [{content, subject, level}]}` shape so imports never need reshaping.
- **Reliability requirement**: because recording sessions can be interrupted (call, app switch, crash), local persistence must be write-as-you-go (e.g. write each question+recording to local DB/storage immediately after it's captured), not buffered until session end.
- **Visual direction**: user asked for "simple, big fonts, nice font, a little colorful, cartoon-like" — lean toward large touch targets, big readable type (this is used while reading a prompt at arm's length and then speaking), and a playful but clean palette. Not corporate/minimal-grey.
- **Code philosophy**: user explicitly asked for the leanest possible implementation — favor Flutter's built-in widgets and a small number of well-chosen packages (audio recording/playback, Firebase, local embedded DB) over custom abstractions.

## Constraints

- **Platform**: Flutter (single codebase, mobile-first) — user-specified
- **Backend**: Firebase (Firestore) for the question bank only — user-specified; nothing else needs a backend
- **Local storage**: session history + audio files must persist on-device across app restarts, written incrementally during the session — user-specified reliability requirement
- **Simplicity**: minimize code volume and screen count; avoid speculative abstractions — user-specified priority ("nhanh nhất, ít code nhất")
- **Docs**: despite the lean code, documentation must be thorough enough to hand off/resume later — user-specified

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Topics are derived from distinct `subject` values in the questions collection, no separate topics collection | Matches the user's exact schema request, avoids a second Firebase collection to keep in sync | — Pending |
| Question bank lives only in Firebase; history/recordings live only on-device | Matches user's explicit local-vs-cloud split | — Pending |
| No pronunciation scoring/AI grading in v1 | Not requested; keeps scope to the reflex-drill mechanic only | — Pending |
| Vertical MVP phase structure (working app fast, sliced by user-facing capability) | User wants speed and minimal overhead over exhaustive layering | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-07 after initialization*
