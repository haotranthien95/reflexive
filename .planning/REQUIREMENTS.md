# Requirements: EnglishReflex

**Defined:** 2026-08-07
**Core Value:** The user can drill spoken English under real time pressure (timed prompt → forced recording → auto-advance) and can always go back and listen to exactly what they said on any past question.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Setup

- [x] **SETUP-01**: User can select one or more topics via checkboxes, fetched from the Firestore question bank (topics = distinct `subject` values present)
- [x] **SETUP-02**: User can select a CEFR level (A1, A2, B1, B2, C1, C2)
- [x] **SETUP-03**: User can pick the number of questions for the session, from 1 to 100 (`question_count`)
- [x] **SETUP-04**: User can set the pre-record countdown duration in seconds (`t`)
- [x] **SETUP-05**: User can set the max recording duration in seconds before auto-stop (`d`)
- [x] **SETUP-06**: User can toggle whether each recording auto-plays back after capture (`r`)
- [x] **SETUP-07**: Starting a session requires at least one topic selected; the Start action is blocked/disabled otherwise

### Practice Loop

- [x] **LOOP-01**: Starting a session shows a 3-second countdown before the first question appears
- [x] **LOOP-02**: Each question displays with a live `t`-second countdown before recording begins
- [x] **LOOP-03**: Recording starts automatically the instant the pre-record countdown reaches 0
- [x] **LOOP-04**: Recording stops automatically after `d` seconds
- [x] **LOOP-05**: User can manually stop the current recording early via a large, always-visible stop button
- [x] **LOOP-06**: If `r` is true, the just-recorded answer plays back automatically once recording stops
- [x] **LOOP-07**: After each question (and its playback, if enabled), a 3-second countdown transitions to the next question
- [x] **LOOP-08**: The session completes automatically once `question_count` questions have been answered

### Session Controls

- [x] **CTRL-01**: The app bar shows a Pause/Resume control at all times during an active session
- [x] **CTRL-02**: The app bar shows a Stop control at all times during an active session
- [x] **CTRL-03**: Tapping Stop shows a confirmation dialog before the session actually ends early
- [x] **CTRL-04**: Pausing freezes the current countdown/recording state until the user resumes

### History

- [x] **HIST-01**: Every session (completed or stopped early) appears in an Exercise History list
- [x] **HIST-02**: Opening a session in history shows the list of its questions alongside their recordings
- [x] **HIST-03**: Tapping a question in a session's detail view plays that question's recording
- [x] **HIST-04**: History entries and their recordings persist across app restarts

### Local Persistence

- [x] **PERSIST-01**: Each answered question (audio file + metadata) is written to local storage immediately after capture, not buffered until session end
- [x] **PERSIST-02**: If the app is killed or crashes mid-session, all questions already answered before the crash are still visible in history on relaunch

### Question Bank

- [x] **BANK-01**: Question bank is stored in Firestore using the schema `{id, content, subject, level, created_at}`
- [x] **BANK-02**: App derives the selectable topic list from the distinct `subject` values present in the question bank (no separate topics collection)
- [x] **BANK-03**: App fetches only the questions matching the selected topics and level for a given session

### JSON Import

- [x] **IMPORT-01**: User can pick a local JSON file to bulk-import questions into the Firestore bank
- [x] **IMPORT-02**: Import accepts exactly the format `{"data": [{"content": "...", "subject": "...", "level": "..."}, ...]}`
- [x] **IMPORT-03**: Each imported question gets `id` and `created_at` auto-generated at import time
- [x] **IMPORT-04**: Import reports success/failure per row rather than failing silently or partially
- [ ] **IMPORT-05**: The app ships with ~10 general-purpose topics seeded in the question bank so the first run isn't empty

### Visual Design

- [x] **UI-01**: Interface uses large, easily readable font sizes throughout (read-at-arm's-length, then speak)
- [x] **UI-02**: Visual style is simple, colorful, and friendly/cartoon-like — not corporate/minimal-grey
- [x] **UI-03**: The app has exactly 3 core screens (Setup, Practice Session, History) with no extraneous navigation

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
| SETUP-01 | Phase 3 | Complete (device UAT pending) |
| SETUP-02 | Phase 2 | Complete |
| SETUP-03 | Phase 2 | Complete |
| SETUP-04 | Phase 2 | Complete |
| SETUP-05 | Phase 2 | Complete |
| SETUP-06 | Phase 2 | Complete |
| SETUP-07 | Phase 2 | Complete |
| LOOP-01 | Phase 2 | Complete |
| LOOP-02 | Phase 2 | Complete |
| LOOP-03 | Phase 1 | Complete (device UAT discharged in Phase 2) |
| LOOP-04 | Phase 1 | Complete |
| LOOP-05 | Phase 1 | Complete |
| LOOP-06 | Phase 1 | Complete (device UAT discharged in Phase 2) |
| LOOP-07 | Phase 2 | Complete |
| LOOP-08 | Phase 2 | Complete |
| CTRL-01 | Phase 2 | Complete |
| CTRL-02 | Phase 2 | Complete |
| CTRL-03 | Phase 2 | Complete |
| CTRL-04 | Phase 2 | Complete |
| HIST-01 | Phase 1 | Complete |
| HIST-02 | Phase 1 | Complete |
| HIST-03 | Phase 1 | Complete (device UAT pending) |
| HIST-04 | Phase 1 | Complete (device UAT pending) |
| PERSIST-01 | Phase 1 | Complete |
| PERSIST-02 | Phase 1 | Complete (device UAT pending) |
| BANK-01 | Phase 3 | Complete |
| BANK-02 | Phase 3 | Complete |
| BANK-03 | Phase 3 | Complete (device UAT pending) |
| IMPORT-01 | Phase 4 | Complete (device UAT pending) |
| IMPORT-02 | Phase 4 | Complete |
| IMPORT-03 | Phase 4 | Complete (device UAT pending) |
| IMPORT-04 | Phase 4 | Complete (device UAT pending) |
| IMPORT-05 | Phase 4 | Seed authored; loaded on-device in plan 04-05 |
| UI-01 | Phase 1 | Complete (device UAT pending) |
| UI-02 | Phase 1 | Complete (device UAT pending) |
| UI-03 | Phase 4 | Complete |

**Coverage:**

- v1 requirements: 36 total
- Mapped to phases: 36 (populated by roadmapper)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-07*
*Last updated: 2026-08-10 — Phase 4 statuses recorded (IMPORT-01..05, UI-03).*

*`Complete` means proven by automated tests. `Complete (device UAT pending)` means the implementation is done but the remaining evidence is an on-device check that has not been performed yet.*

*SETUP-01 and BANK-03 carry that qualifier because the Firestore adapter is deliberately not host-testable (D-47) — the topic checkboxes rendering real seeded subjects, and the filtered session query returning them, are proven on a device rather than in `flutter test`.*

*IMPORT-01, IMPORT-03 and IMPORT-04 carry it for the same D-47 reason on the write side: the picker adapter and the Firestore writer sit past the seam, so the real file pick, the four-field document body with its strictly increasing `created_at`, and the multi-chunk commit above the 500-op batch cap are all proven by plan 04-05's on-device seed import. Everything on the host side of the seam — the whole-file validation, the per-row skip report keyed by file position, the duplicate pass and all eight sheet states, including the partial-write outcome — is under direct test. IMPORT-02 is unqualified: it is entirely the pure `parseImportFile` contract.*

*IMPORT-05 is deliberately still open. `seed/seed-questions.json` exists in the repo, holds 600 rows across ten topics at all six CEFR levels, and is validated against the shipped importer's own code by `test/services/seed_import_file_test.dart` — but the requirement is that the **bank** is not empty, and the bank is in Firestore. It closes when plan 04-05 loads the file on a device.*

*BANK-01 and BANK-02 remain unqualified, on new evidence. The mechanism that used to justify BANK-01 — the `--verify` mode of the one-off Node seed script under `tool/` — was **retired with that directory in this phase** (D-57: two write paths into one collection with different rules is what the deletion removes). Its evidence is replaced, not merely dropped: the document contract is now asserted by the app's own import path, which writes exactly `content`/`subject`/`level`/`created_at` with the auto-generated key as the schema's `id`, and is read back on-device by the plan 04-05 seed import. BANK-02's topic-derivation rule was never the script's to prove — `normalizeSubjects` is a pure function under direct unit test and still is.*
