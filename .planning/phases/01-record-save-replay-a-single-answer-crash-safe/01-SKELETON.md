# Walking Skeleton — EnglishReflex

**Phase:** 1
**Generated:** 2026-08-07

## Capability Proven End-to-End

A user opens the app, speaks an answer to an auto-shown question while it auto-records, the recording is saved to on-device SQLite + filesystem the instant it finalizes, it auto-plays back, and it appears in an Exercise History list they can reopen and replay later — surviving a force-kill of the app process at any point after that save.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | Flutter (single codebase, mobile-first: Android + iOS) | User-specified (PROJECT.md); no web/desktop target needed for v1. |
| State management | Flutter SDK `ChangeNotifier` + `ListenableBuilder`, no package | CLAUDE.md explicitly excludes `provider`/`riverpod`/`bloc`/`GetX` for a single screen-flow app; `PracticeState` is the one shared engine object (D-05/PATTERNS.md). |
| Local persistence | `sqflite` (raw SQL, 2 tables: `sessions`, `question_answers`), no ORM/codegen | CLAUDE.md "What NOT to Use" rules out `drift`/`Hive`/`Isar`; schema locked by D-05 (session-first, one-way door — Phase 2 extends without migration). |
| Audio capture/playback | `record` (capture) + `audioplayers` (local-file playback) | Pre-vetted in STACK.md/RESEARCH.md; no `just_audio`/background-audio packages (out of scope). |
| File storage | `path_provider`'s app-private documents directory; DB stores **relative** paths, resolved to absolute at read time | Avoids the iOS sandbox-UUID-drift anti-pattern (ARCHITECTURE.md Anti-Pattern 3); keeps recordings device-local (no `firebase_storage`). |
| Typography/theme | Warm coral/orange/yellow Material 3 theme; `google_fonts` (`Baloo 2`) for Display/Heading roles only | Locked by D-12–D-15; `google_fonts` is a new, explicitly user-directed addition to the stack (flagged in UI-SPEC for a CLAUDE.md update). |
| Deployment target | Local dev run via `flutter run` on an Android emulator/device (and iOS simulator where available) — no CI/store deployment in Phase 1 | No backend beyond a future Firestore question bank (Phase 3); Phase 1 has zero network dependency, so "deployment" means "runs locally end-to-end." |
| Directory layout | Feature-flat: `lib/models/`, `lib/services/`, `lib/state/`, `lib/screens/`, `lib/widgets/`, `lib/utils/`, `lib/data/` | Matches ARCHITECTURE.md's recommended structure for a 3-4 screen app — no `domain/`/`repository interfaces`/DI container (contradicts the "least code" constraint at this scale). |

## Stack Touched in Phase 1

- [x] Project scaffold (`flutter create`, `pubspec.yaml` dependencies, lint via `flutter analyze`, test runner via `flutter test`)
- [x] Routing — `PracticeScreen` (home) <-> `HistoryScreen` <-> `SessionDetailScreen`, via `Navigator.push`
- [x] Database — real read AND write: `DatabaseHelper.insertAnsweredSession(...)` (write, transactional), `DatabaseHelper.listSessions()` / `listAnswersForSession(...)` (read)
- [x] UI — interactive elements wired to real services: Stop button ends `RecordingService`, History rows/question rows trigger `AudioPlayerService.play(...)`
- [x] "Deployment" — documented local full-stack run command: `flutter run` (Android emulator or iOS simulator), no backend/network dependency to stand up

## Out of Scope (Deferred to Later Slices)

- Session Setup screen, configurable `t`/`d`/`r`/`question_count`/topics/level — Phase 2 (`SETUP-*`)
- Multi-question timed loop, 3s countdowns, pause/resume/stop-with-confirm app bar — Phase 2 (`LOOP-01/02/07/08`, `CTRL-*`)
- Firestore-backed question bank, real `subject`/`level` topics — Phase 3 (`BANK-*`, `SETUP-01`)
- JSON bulk import, seeded starter content, "exactly 3 screens" navigation audit — Phase 4 (`IMPORT-*`, `UI-03`)
- Countdown-drift-safe wall-clock timer UI (no elapsed-timer/countdown display exists in Phase 1 at all, per D-04) — Phase 2
- `AudioInterruptionMode` real-interruption (phone call) recovery UX — Phase 2 per RESEARCH.md pitfalls mapping
- Orphan-file startup sweep — not required in Phase 1 because D-08's write ordering (file finalized fully before any DB row) guarantees zero orphans can be created in the first place; revisit only if a future phase's write path changes that guarantee

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- Phase 2: Full timed practice session — Setup screen + multi-question state machine (`SessionController`) reusing `RecordingService`/`AudioPlayerService`/`DatabaseHelper` unchanged, adding `t`/`d` configurability and Pause/Resume/Stop.
- Phase 3: Real question bank via Firestore — `FirestoreService` supplies `List<String>` (or a `Question` model) in place of `lib/data/questions.dart`'s hardcoded list; no change to the recording/persistence/history layers.
- Phase 4: Bulk JSON import + seed content + navigation audit — additive `FirestoreService.importJson(...)` and a seed script; confirms the app still has exactly 3 core screens.
