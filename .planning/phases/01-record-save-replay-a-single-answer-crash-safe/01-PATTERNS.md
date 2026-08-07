# Phase 1: Record, Save & Replay a Single Answer (Crash-Safe) - Pattern Map

**Mapped:** 2026-08-07
**Files analyzed:** 10 (estimated, from CONTEXT.md + stack docs)
**Analogs found:** 0 / 10 — **greenfield project, confirmed**

## Greenfield Confirmation

This repository has no Flutter project scaffolded yet:

```
$ find . -maxdepth 2
./.claude
./.planning
./docs
./prompt.md
```

No `lib/`, no `pubspec.yaml`, no `test/`. There is zero existing Dart/Flutter source code to analogize from. CONTEXT.md's `<code_context>` section independently confirms this ("None yet — greenfield"). This PATTERNS.md therefore does **not** contain per-file analog assignments — instead it specifies the **first patterns** this phase must establish, derived from `.claude/CLAUDE.md`'s stack guidance and the locked decisions in `01-CONTEXT.md`. All later phases (2-4) should treat Phase 1's implementation as the canonical analog for controllers/services/state-management/schema going forward.

## File Classification (files this phase will create — no analogs, first of their kind)

| New File | Role | Data Flow | Analog | Notes |
|----------|------|-----------|--------|-------|
| `lib/main.dart` | config/entry | request-response (app bootstrap) | none | Standard Flutter `runApp` entry; also wires `MaterialApp` theme (warm palette, Google Font per D-12/D-14/D-15) |
| `lib/db/database_helper.dart` (or `lib/data/db.dart`) | service (DB access) | CRUD | none | Opens/creates sqflite DB, exposes `sessions` + `question_answers` CRUD per D-05 |
| `lib/models/session.dart` | model | transform | none | Plain Dart class mapping `sessions` table row |
| `lib/models/question_answer.dart` | model | transform | none | Plain Dart class mapping `question_answers` table row |
| `lib/services/recording_service.dart` | service | streaming/file-I/O | none | Wraps `record` package: start/stop/auto-stop-at-60s, returns file path |
| `lib/services/audio_player_service.dart` | service | streaming/file-I/O | none | Wraps `audioplayers` package: play a local file path (replay) |
| `lib/state/practice_state.dart` (ChangeNotifier) | provider/store | event-driven | none | Holds current question, recording phase (idle/recording/finalizing/replaying), notifies UI on phase change — per CLAUDE.md's explicit guidance to use `ChangeNotifier`/`ValueNotifier`, not a state-mgmt package |
| `lib/screens/practice_screen.dart` | component (screen) | event-driven | none | Auto-starts recording on screen open (D-01), shows Stop button only while recording (D-04), triggers save + auto-replay on stop (D-10), resets to fresh question after (D-03) |
| `lib/screens/history_screen.dart` | component (screen) | CRUD (read) | none | Lists sessions (session-first per D-06), queries `database_helper` |
| `lib/screens/session_detail_screen.dart` | component (screen) | CRUD (read) | none | Shows question_answers for a tapped session; manual replay (HIST-03) |
| `lib/data/questions.dart` | config/data | transform | none | Hardcoded rotating ~5-question list (D-02), picks one per screen open |
| `test/db/database_helper_test.dart` | test | CRUD | none | First test file — establishes test structure/conventions |

## First-Pattern Guidance (to replace "analogs" for this greenfield phase)

### Schema shape (source: CONTEXT.md D-05, D-08)
Establish exactly two tables now, matching the session-first model:
```sql
CREATE TABLE sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL
);

CREATE TABLE question_answers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  question_text TEXT NOT NULL,
  audio_path TEXT NOT NULL,
  created_at TEXT NOT NULL
);
```
Critical rule (D-08): a `sessions` row + its `question_answers` row must be written to the DB **only after** the audio file is fully finalized (recording stopped, file flushed/closed). Never write a placeholder row before recording completes — a kill mid-recording must leave zero trace. This ordering (finalize file -> write DB row, ideally in one transaction or immediately sequential) is the core crash-safety pattern (PERSIST-02) that Phase 2 will reuse verbatim when writing multiple `question_answers` rows per session.

### State management (source: CLAUDE.md "Supporting Libraries", CONTEXT.md code_context)
Use a single `ChangeNotifier` (e.g. `PracticeState`) exposing phase enum (`idle`, `recording`, `saving`, `replaying`) and current question. `PracticeScreen` wraps relevant widgets in `ListenableBuilder` (or `AnimatedBuilder`) listening to this notifier. Do not introduce `provider`/`riverpod`/`bloc` — explicitly excluded in CLAUDE.md's "What NOT to Use" table. This will be the canonical state-management pattern for Phase 2's more complex multi-question loop.

### Recording flow (source: CONTEXT.md D-01, D-04, D-08, D-09, D-11)
- On `PracticeScreen.initState`/screen open: immediately call `recordingService.start()` — no button, no confirmation.
- Use `record` package defaults (no custom codec/bitrate config) — D-11.
- Enforce a 60s hard cap (D-09) — either via package's built-in max-duration option if available, or a `Timer` that calls `stop()` at 60s.
- Only after `stop()` resolves with a finalized file path: write DB rows (session + question_answer), then trigger auto-replay (D-10) via `audioPlayerService.play(path)`.
- After replay completes: reset state to a freshly-picked question and re-arm auto-start recording (D-03).

### Error handling (no existing pattern — establish now)
Since this is the first phase, define a minimal convention: wrap file I/O and DB writes in try/catch; on failure, surface a simple SnackBar/dialog and return to idle state rather than crashing. Keep this lightweight per the "leanest code" constraint — no custom exception hierarchy needed yet.

### Visual/theme conventions (source: CONTEXT.md D-12 through D-15)
- `MaterialApp.theme`: warm palette (coral/orange/yellow-forward), rounded shapes (large `borderRadius` on buttons/cards).
- Headings/question text use `google_fonts` (e.g. `GoogleFonts.fredoka()` or `GoogleFonts.baloo2()`) — flagged in CONTEXT.md as a new package not yet in CLAUDE.md's stack list; planner should confirm addition is acceptable (single small package, no codegen, aligns with "minimize packages" only loosely — but explicitly user-directed per D-15).
- Include a simple mascot element (mic-with-face icon or small illustration) shown during recording/result states — exact asset left to implementation per Claude's Discretion note.

## Shared Patterns (apply across all files in this phase)

### Crash-safety ordering
**Source:** derived from PERSIST-02 requirement + D-08 (no prior code exists)
**Apply to:** `recording_service.dart`, `database_helper.dart`, `practice_state.dart`
Rule: finalize audio file fully before any DB write; DB write for a session+answer pair should be atomic/sequential immediately after finalization, with no intermediate "pending" row.

### ChangeNotifier-based UI state
**Source:** CLAUDE.md Supporting Libraries table (no code yet, guidance only)
**Apply to:** `practice_state.dart`, `practice_screen.dart`
Rule: single `ChangeNotifier` per screen-flow that needs cross-widget state; `ListenableBuilder` in the widget tree; no external state package.

### Local-only persistence, no cloud writes for recordings
**Source:** CLAUDE.md "What NOT to Use" (`firebase_storage` explicitly excluded)
**Apply to:** `recording_service.dart`, `database_helper.dart`
Rule: audio files stay under `path_provider`'s app documents directory; only the file path (not the audio itself) is referenced from sqflite rows. Firestore is not touched in this phase (question bank is hardcoded per D-02).

## No Analog Found

All files in this phase have no analog — this is expected and correct for a greenfield first phase.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| all files listed above | various | various | No prior Dart/Flutter source exists in this repository; Phase 1 establishes the first patterns |

## Metadata

**Analog search scope:** entire repository root (`.`, maxdepth 2) — confirmed no `lib/`, `pubspec.yaml`, or `test/` directories exist
**Files scanned:** 0 Dart/Flutter source files (none exist)
**Pattern extraction date:** 2026-08-07
</content>
