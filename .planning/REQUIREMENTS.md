# Requirements: EnglishReflex

**Defined:** 2026-08-07
**Core Value:** The user can drill spoken English under real time pressure (timed prompt → forced recording → auto-advance) and can always go back and listen to exactly what they said on any past question.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Setup

- [ ] **SETUP-01**: User can select one or more topics via checkboxes, fetched from the Firestore question bank (topics = distinct `subject` values present)
- [ ] **SETUP-02**: User can select a CEFR level (A1, A2, B1, B2, C1, C2)
- [ ] **SETUP-03**: User can pick the number of questions for the session, from 1 to 100 (`question_count`)
- [ ] **SETUP-04**: User can set the pre-record countdown duration in seconds (`t`)
- [ ] **SETUP-05**: User can set the max recording duration in seconds before auto-stop (`d`)
- [ ] **SETUP-06**: User can toggle whether each recording auto-plays back after capture (`r`)
- [ ] **SETUP-07**: Starting a session requires at least one topic selected; the Start action is blocked/disabled otherwise

### Practice Loop

- [ ] **LOOP-01**: Starting a session shows a 3-second countdown before the first question appears
- [ ] **LOOP-02**: Each question displays with a live `t`-second countdown before recording begins
- [ ] **LOOP-03**: Recording starts automatically the instant the pre-record countdown reaches 0
- [ ] **LOOP-04**: Recording stops automatically after `d` seconds
- [ ] **LOOP-05**: User can manually stop the current recording early via a large, always-visible stop button
- [ ] **LOOP-06**: If `r` is true, the just-recorded answer plays back automatically once recording stops
- [ ] **LOOP-07**: After each question (and its playback, if enabled), a 3-second countdown transitions to the next question
- [ ] **LOOP-08**: The session completes automatically once `question_count` questions have been answered

### Session Controls

- [ ] **CTRL-01**: The app bar shows a Pause/Resume control at all times during an active session
- [ ] **CTRL-02**: The app bar shows a Stop control at all times during an active session
- [ ] **CTRL-03**: Tapping Stop shows a confirmation dialog before the session actually ends early
- [ ] **CTRL-04**: Pausing freezes the current countdown/recording state until the user resumes

### History

- [ ] **HIST-01**: Every session (completed or stopped early) appears in an Exercise History list
- [ ] **HIST-02**: Opening a session in history shows the list of its questions alongside their recordings
- [ ] **HIST-03**: Tapping a question in a session's detail view plays that question's recording
- [ ] **HIST-04**: History entries and their recordings persist across app restarts

### Local Persistence

- [ ] **PERSIST-01**: Each answered question (audio file + metadata) is written to local storage immediately after capture, not buffered until session end
- [ ] **PERSIST-02**: If the app is killed or crashes mid-session, all questions already answered before the crash are still visible in history on relaunch

### Question Bank

- [ ] **BANK-01**: Question bank is stored in Firestore using the schema `{id, content, subject, level, created_at}`
- [ ] **BANK-02**: App derives the selectable topic list from the distinct `subject` values present in the question bank (no separate topics collection)
- [ ] **BANK-03**: App fetches only the questions matching the selected topics and level for a given session

### JSON Import

- [ ] **IMPORT-01**: User can pick a local JSON file to bulk-import questions into the Firestore bank
- [ ] **IMPORT-02**: Import accepts exactly the format `{"data": [{"content": "...", "subject": "...", "level": "..."}, ...]}`
- [ ] **IMPORT-03**: Each imported question gets `id` and `created_at` auto-generated at import time
- [ ] **IMPORT-04**: Import reports success/failure per row rather than failing silently or partially
- [ ] **IMPORT-05**: The app ships with ~10 general-purpose topics seeded in the question bank so the first run isn't empty

### Visual Design

- [ ] **UI-01**: Interface uses large, easily readable font sizes throughout (read-at-arm's-length, then speak)
- [ ] **UI-02**: Visual style is simple, colorful, and friendly/cartoon-like — not corporate/minimal-grey
- [ ] **UI-03**: The app has exactly 3 core screens (Setup, Practice Session, History) with no extraneous navigation

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Practice Loop Enhancements

- **LOOP-V2-01**: Shuffle/randomize question order within a selected topic (reinforces the "reflex" mechanic by preventing memorized answer order)

### History Enhancements

- **HIST-V2-01**: Re-record a single past question directly from history
- **HIST-V2-02**: Playback speed control on saved recordings

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Pronunciation/fluency AI scoring or feedback | Different product category (coaching tool vs. drill tool); not requested |
| User accounts / authentication | Single local user, no login needed for v1 |
| Cloud sync/backup of history or recordings | Explicitly local-only per user request |
| Streaks, gamification, analytics dashboard | Contradicts the "simple, fast" positioning; not a Duolingo-style platform |
| Social features (sharing, leaderboards) | Not part of the stated goal |
| Admin web dashboard for question-bank management | JSON import inside the app is the only bank-management path for v1 |
| Multi-language support (non-English target) | Target language is English only for v1 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SETUP-01 | Phase 3 | Pending |
| SETUP-02 | Phase 2 | Pending |
| SETUP-03 | Phase 2 | Pending |
| SETUP-04 | Phase 2 | Pending |
| SETUP-05 | Phase 2 | Pending |
| SETUP-06 | Phase 2 | Pending |
| SETUP-07 | Phase 2 | Pending |
| LOOP-01 | Phase 2 | Pending |
| LOOP-02 | Phase 2 | Pending |
| LOOP-03 | Phase 1 | Pending |
| LOOP-04 | Phase 1 | Pending |
| LOOP-05 | Phase 1 | Pending |
| LOOP-06 | Phase 1 | Pending |
| LOOP-07 | Phase 2 | Pending |
| LOOP-08 | Phase 2 | Pending |
| CTRL-01 | Phase 2 | Pending |
| CTRL-02 | Phase 2 | Pending |
| CTRL-03 | Phase 2 | Pending |
| CTRL-04 | Phase 2 | Pending |
| HIST-01 | Phase 1 | Pending |
| HIST-02 | Phase 1 | Pending |
| HIST-03 | Phase 1 | Pending |
| HIST-04 | Phase 1 | Pending |
| PERSIST-01 | Phase 1 | Pending |
| PERSIST-02 | Phase 1 | Pending |
| BANK-01 | Phase 3 | Pending |
| BANK-02 | Phase 3 | Pending |
| BANK-03 | Phase 3 | Pending |
| IMPORT-01 | Phase 4 | Pending |
| IMPORT-02 | Phase 4 | Pending |
| IMPORT-03 | Phase 4 | Pending |
| IMPORT-04 | Phase 4 | Pending |
| IMPORT-05 | Phase 4 | Pending |
| UI-01 | Phase 1 | Pending |
| UI-02 | Phase 1 | Pending |
| UI-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 36 total
- Mapped to phases: 36 (populated by roadmapper)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-07*
*Last updated: 2026-08-07 after roadmap creation (36/36 requirements mapped to 4 phases)*
