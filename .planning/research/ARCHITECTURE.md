# Architecture Research

**Domain:** Small single-user Flutter mobile app (timed record/replay drill tool, local-first with a read-mostly Firestore question bank)
**Researched:** 2026-08-07
**Confidence:** MEDIUM (Flutter/package API facts from official docs via Context7 = MEDIUM; folder-structure and DB-choice opinions from general web search = LOW, cross-checked against the user's own explicit "least code" constraint in PROJECT.md)

## Standard Architecture

For an app this size (3-4 screens, one user, no auth, no server logic beyond a single Firestore collection), the "standard" enterprise Flutter architecture (domain/data/presentation layers, repository interfaces, DI containers, BLoC) is the wrong reference point. The right reference point is: **three screens, three services, two local tables, one Firestore collection.** Everything below is sized to that.

### System Overview

```
┌───────────────────────────────────────────────────────────────────┐
│                            UI (screens/)                            │
│  ┌────────────┐   ┌────────────────────┐   ┌────────────────────┐ │
│  │   Setup     │   │  Practice Session   │   │  History (list +   │ │
│  │   Screen    │──▶│  Screen + Session   │──▶│  detail) Screens    │ │
│  │             │   │  Controller (state  │   │                    │ │
│  │             │   │  machine)           │   │                    │ │
│  └─────┬──────┘   └─────────┬──────────┘   └─────────┬──────────┘ │
├────────┼────────────────────┼──────────────────────────┼───────────┤
│        │                    │  Services (services/)     │           │
│  ┌─────▼──────┐    ┌────────▼────────┐   ┌─────────────▼───────┐  │
│  │ Firestore   │    │  Audio Service   │   │  Local DB Service    │  │
│  │ Service     │    │  (record +       │   │  (sqflite: sessions  │  │
│  │ (read topics│    │  player wrapper) │   │  + answers tables)   │  │
│  │ /questions, │    │                  │   │                      │  │
│  │ write import)│   │                  │   │                      │  │
│  └─────┬──────┘    └────────┬────────┘   └─────────────┬───────┘  │
├────────┼────────────────────┼──────────────────────────┼───────────┤
│  ┌─────▼──────┐    ┌────────▼────────┐   ┌─────────────▼───────┐  │
│  │  Firestore  │    │  Filesystem      │   │  SQLite file          │  │
│  │  (cloud)    │    │  (app docs dir,  │   │  (app docs dir,       │  │
│  │             │    │  .m4a files)     │   │  app.db)              │  │
│  └────────────┘    └─────────────────┘   └──────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

There is no separate "domain" or "repository interface" layer. Each service class *is* the repository — it wraps exactly one data source and exposes plain async methods. Nothing implements an abstract interface because there is exactly one implementation of each and no test-double swapping is planned for v1.

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|-------------------------|
| `SetupScreen` | Collect topics/level/counts/timings, read distinct topics from Firestore | `StatefulWidget`, calls `FirestoreService.fetchTopics()` in `initState` |
| `SessionScreen` + `SessionController` | Drive the countdown → record → auto-stop → replay → next loop; own the `Timer`; write each answered question to local DB+disk as it happens | `SessionController` as a plain class (or `ChangeNotifier` if you want `AnimatedBuilder`/`ListenableBuilder` rebuilds) holding an enum phase + `Timer`; `SessionScreen` just renders `controller.phase` |
| `HistoryListScreen` / `SessionDetailScreen` | List past sessions, show per-question playback for one session | `FutureBuilder`/`StreamBuilder` reading directly from `LocalDbService`, no caching layer |
| `FirestoreService` | Read questions (topics = distinct `subject` values), write bulk import batch | Thin class wrapping `cloud_firestore` calls, no interface/abstraction |
| `AudioService` | Start/stop recording to a file path; play back a file path | Thin class wrapping `record` (recording) + a playback package (e.g. `audioplayers`) |
| `LocalDbService` | CRUD for `sessions` and `answers` tables; incremental insert-as-you-go | Thin class wrapping `sqflite` with hand-written SQL (2 tables, no ORM/codegen) |
| Models (`Question`, `SessionConfig`, `SessionRow`, `AnswerRow`) | Plain data classes, `fromMap`/`toMap` | Immutable Dart classes, no code generation (freezed/json_serializable are overkill for 4 tiny classes) |

## Recommended Project Structure

```
lib/
├── main.dart                     # runApp, Firebase.initializeApp, MaterialApp
├── models/
│   ├── question.dart              # Question {id, content, subject, level, createdAt}
│   ├── session_config.dart        # topics, level, questionCount, t, d, autoReplay
│   ├── session.dart                # SessionRow {id, createdAt, config fields, status}
│   └── answer.dart                 # AnswerRow {sessionId, order, questionId, content, audioPath, durationMs}
├── services/
│   ├── firestore_service.dart      # fetchTopics(), fetchQuestions(...), importJson(...)
│   ├── local_db_service.dart       # openDb(), insertSession(), insertAnswer(), completeSession(), listSessions(), listAnswers(sessionId)
│   └── audio_service.dart          # startRecording(path), stopRecording(), play(path), stop()
├── screens/
│   ├── setup/
│   │   └── setup_screen.dart
│   ├── session/
│   │   ├── session_screen.dart     # UI only, renders controller state
│   │   └── session_controller.dart # the state machine + Timer + incremental writes
│   └── history/
│       ├── history_list_screen.dart
│       └── session_detail_screen.dart
└── widgets/
    ├── big_stop_button.dart
    ├── countdown_ring.dart
    └── ... (small shared presentational widgets only)
```

### Structure Rationale

- **Flat `services/` folder, not `data/`, `domain/`, `repositories/`:** three services, three files. A layered folder tree for three files adds navigation overhead with zero benefit — there's nothing to swap or hide behind an interface.
- **`screens/<feature>/` (feature-first, not type-first):** matches what the Flutter team itself recommends once an app outgrows a single file, and keeps everything about one screen (its controller, its widgets if truly local) in one place. Do **not** add `views/`, `viewmodels/`, `widgets/` sub-splits inside each feature folder — for 3 screens that's more folders than files.
- **`session_controller.dart` separated from `session_screen.dart`:** this is the one place worth a deliberate split, because the state machine (timer, phase transitions, incremental DB/file writes) is non-trivial logic that benefits from being readable without Flutter widget noise around it, and from being unit-testable without pumping widgets. Every other screen is simple enough to keep controller logic inline in the `State` class.
- **No `main.dart`-level DI container / service locator (get_it, riverpod, provider):** with 3 services and no interface-swapping need, just construct services where they're used (`SetupScreen` constructs `FirestoreService()`, `SessionController` receives `LocalDbService` and `AudioService` instances via constructor). Manual constructor injection is enough. Confidence: LOW/general-knowledge, but directly justified by the user's explicit "least code, fewest abstractions" constraint.

## Architectural Patterns

### Pattern 1: Enum-driven state machine in a plain controller class

**What:** Model the practice loop as an explicit `enum SessionPhase { starting, questionCountdown, recording, playback, betweenQuestions, finished }` plus a `SessionController` that owns a single `Timer` and transitions the enum on tick/user-action, notifying the screen to rebuild.
**When to use:** Any screen with a clear finite set of mutually-exclusive UI states driven by both time and user input (exactly this session screen). This is the correct level of "state management" here — not a full state-management package.
**Trade-offs:** Slightly more boilerplate than raw booleans (`isRecording`, `isCountingDown`, ...), but eliminates impossible-state bugs (e.g. "recording" and "playback" both true) that boolean-soup produces. Far less boilerplate than BLoC/Riverpod, which add event/state classes and a package dependency for a single-screen, single-user state machine that never needs to be observed from outside that screen.

**Example:**
```dart
enum SessionPhase { questionCountdown, recording, playback, betweenQuestions, finished }

class SessionController extends ChangeNotifier {
  SessionController(this.config, this.db, this.audio, this.questions);
  final SessionConfig config;
  final LocalDbService db;
  final AudioService audio;
  final List<Question> questions;

  int currentIndex = 0;
  SessionPhase phase = SessionPhase.questionCountdown;
  int secondsLeft = 0;
  Timer? _timer;
  late final int sessionId; // set in start()

  Future<void> start() async {
    sessionId = await db.insertSession(config); // durable row #1, before any recording
    _beginQuestionCountdown();
  }

  void _beginQuestionCountdown() {
    phase = SessionPhase.questionCountdown;
    secondsLeft = config.t;
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      secondsLeft--;
      if (secondsLeft <= 0) {
        t.cancel();
        _advancePhase();
      }
      notifyListeners();
    });
  }

  Future<void> _advancePhase() async {
    if (phase == SessionPhase.questionCountdown) {
      phase = SessionPhase.recording;
      await audio.startRecording(_pathFor(currentIndex));
      // auto-stop timer runs config.d seconds, same _tick() pattern
    } else if (phase == SessionPhase.recording) {
      final path = await audio.stopRecording();
      await db.insertAnswer(sessionId, currentIndex, questions[currentIndex], path); // written immediately
      // ... proceed to playback or next question
    }
    notifyListeners();
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}
```

### Pattern 2: Thin service classes, no repository interfaces

**What:** Each service (`FirestoreService`, `LocalDbService`, `AudioService`) is a single concrete class with plain async methods, constructed directly where needed. No `abstract class XRepository` + one implementation.
**When to use:** Any project where you are not writing tests that need fake implementations swapped in via DI, and where there is exactly one real backend per concern (true here: one Firestore project, one SQLite file, one filesystem).
**Trade-offs:** If you later need unit tests for `SessionController` logic without touching real SQLite/mic, you can still pass the concrete `LocalDbService`/`AudioService` instances into the controller's constructor (already shown above) — that alone gives you a seam to substitute a fake in tests, without needing an `abstract class` up front. You get testability without paying the interface tax today.

### Pattern 3: Insert-as-you-go local writes, single-row-per-answer

**What:** Every answered question becomes its own `INSERT` into an `answers` SQLite table the moment recording stops for that question (not a batched write at session end, not a JSON blob column that gets rewritten each time). The parent `sessions` row is inserted once at session start (`status='in_progress'`) and updated once at session end (`status='completed'`).
**When to use:** Exactly the crash-safety requirement in PROJECT.md — "an app kill/crash mid-session must not lose already-answered questions."
**Trade-offs:** None really — this is strictly simpler than buffering in memory and flushing at the end, and SQLite's per-statement durability (each committed `INSERT` is fsync'd by default via `sqflite`) means a kill between questions loses nothing already recorded. The only thing lost on a kill is the *currently in-flight* recording (which is expected and acceptable).

## Data Flow

### Practice-Session Write Flow (the crash-safety-critical path)

```
User taps "Start Session" (SetupScreen)
    ↓ (SessionConfig passed via constructor/route args — no global state)
SessionScreen.initState → SessionController.start()
    ↓
LocalDbService.insertSession(config)          ──▶ sessions row written NOW, status='in_progress'
    ↓                                              (durable: survives kill from this point on)
loop for each question i in 0..questionCount-1:
    questionCountdown (Timer, t seconds)
        ↓
    AudioService.startRecording(path_i)         ──▶ file opened on disk at
                                                     <appDocsDir>/recordings/<sessionId>/<i>_<questionId>.m4a
        ↓ (auto-stop at d seconds OR manual stop tap)
    AudioService.stopRecording() → path_i        ──▶ .m4a file finalized on disk NOW
        ↓
    LocalDbService.insertAnswer(sessionId, i, question, path_i, durationMs)
                                                  ──▶ answers row written NOW (this is the
                                                      "write each question+recording immediately"
                                                      requirement — happens inside the loop,
                                                      not after it)
        ↓
    if config.autoReplay: AudioService.play(path_i)   ──▶ read-only, no write
        ↓
    betweenQuestions countdown → next i
    ↓ (after last question)
LocalDbService.completeSession(sessionId)        ──▶ single UPDATE, status='completed'
    ↓
pop back to Setup or History
```

**Crash-safety property:** at any point where the app is killed, SQLite already contains the `sessions` row plus one `answers` row per fully-recorded question, and the filesystem already contains the corresponding `.m4a` files. The only data lost is the partially-recorded current question (acceptable — it was never "answered"). On next launch, `HistoryListScreen` will show that session as `status='in_progress'` with N answered questions; you don't need special crash-recovery code, the normal read path already reflects reality. (Optional nice-to-have, not required for v1: let the user resume or explicitly mark it "incomplete" in the UI.)

### History Read Flow

```
HistoryListScreen.build → FutureBuilder(LocalDbService.listSessions())
    ↓ tap a session
SessionDetailScreen(sessionId) → FutureBuilder(LocalDbService.listAnswers(sessionId))
    ↓ tap a question row
AudioService.play(<appDocsDir>/answer.audioPath)   ──▶ path stored RELATIVE, resolved against
                                                        current getApplicationDocumentsDirectory()
                                                        at read time (see Pitfall below)
```

### Question-Bank Read Flow (Firestore, read-mostly)

```
SetupScreen.initState → FirestoreService.fetchTopics()
    ↓ (one .get() query over the questions collection, distinct on `subject` client-side —
       no separate topics collection, per PROJECT.md decision)
user selects topics/level/count → FirestoreService.fetchQuestions(topics, level, count)
    ↓ (used only to build the in-memory List<Question> passed into SessionController;
       Firestore is never touched again during the timed loop — no network calls mid-session)
```

### Import Flow (the one Firestore write path)

```
Admin pastes JSON file → JSON parsed client-side → validated against {"data":[{content,subject,level}]}
    ↓
FirestoreService.importJson(list) → WriteBatch, up to 500 sets per batch,
    id + created_at (FieldValue.serverTimestamp()) auto-generated per document
```

## Scaling Considerations

This is a single-user, local-first app — "scale" here means growth in the user's own history over months of use, not concurrent users.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Early use (tens of sessions) | Everything above as-is. No indexes needed beyond `answers.session_id`. |
| Months of daily use (hundreds of sessions, thousands of recordings) | Add an index on `answers.session_id` (trivial, one line in schema creation); consider a "delete session" action that also deletes its `recordings/<sessionId>/` folder, since audio files will dominate device storage over raw DB rows — not needed for v1 but worth a `PITFALLS.md`/backlog note. |
| Hypothetical multi-year archive | Still just SQLite + files; no architectural change needed. This app will never need a server-side database for its local data — that's explicitly out of scope per PROJECT.md. |

### Scaling Priorities

1. **First real constraint: device storage from audio files, not the DB.** A 30s `.m4a` recording is small (tens of KB–low hundreds of KB depending on codec/bitrate), but hundreds of sessions × tens of questions adds up. This is a product decision (add a "delete old sessions" affordance later), not an architecture change now.
2. **Second: nothing else meaningfully "breaks."** Firestore reads are a handful of small queries triggered only in `SetupScreen`; SQLite queries are simple indexed lookups. No caching layer, no pagination is needed at this app's scale.

## Anti-Patterns

### Anti-Pattern 1: Full clean-architecture layering (domain/data/presentation + repository interfaces + DI container) for a 3-4 screen app

**What people do:** Copy a "production Flutter architecture" template — abstract repository interfaces with single implementations, use-case classes wrapping single repository calls, a DI container (get_it/riverpod) wiring it all, separate `entity`/`model` classes for the same data.
**Why it's wrong:** For this app, every one of those layers has exactly one implementation and is never swapped, mocked at scale, or reused across features. The layering adds files, indirection, and cognitive load with no corresponding benefit, directly contradicting the user's explicit "least code, fewest abstractions" priority in PROJECT.md.
**Do this instead:** Three thin service classes, plain data classes, manual constructor injection (Pattern 2 above). Add an interface later, if and only if a second implementation is ever actually needed (e.g. a fake for widget tests).

### Anti-Pattern 2: Buffering session progress in memory, writing once at the end

**What people do:** Accumulate `List<AnswerRow>` in memory during the session and write it all to storage (or Firestore) when the user finishes or taps "Stop."
**Why it's wrong:** Directly violates the stated reliability requirement — any crash, OS kill (backgrounded too long, low memory), or accidental force-quit mid-session loses every already-recorded answer.
**Do this instead:** Insert-as-you-go (Pattern 3 above) — one `INSERT` per answered question, executed the moment that question's recording is finalized, inside the loop.

### Anti-Pattern 3: Storing absolute file paths in the DB

**What people do:** Save `path.absolute` (e.g. `/data/user/0/com.app/app_flutter/recordings/...` or the iOS sandbox container path) directly into the `answers.audio_file_path` column.
**Why it's wrong:** On iOS, the app's sandbox container UUID (and thus the absolute path returned by `getApplicationDocumentsDirectory()`) can change across app updates/reinstalls, silently breaking every stored path and making old recordings unplayable even though the files are still on disk.
**Do this instead:** Store a path *relative* to the documents directory (e.g. `recordings/<sessionId>/<order>_<questionId>.m4a`), and join it with `getApplicationDocumentsDirectory()` at read time, every time.

### Anti-Pattern 4: Pulling in a full state-management package (BLoC/Riverpod/Provider) for single-screen, single-user state

**What people do:** Default to whatever state-management package is "standard" for Flutter production apps, even though nothing here needs to be observed across widget subtrees, no state needs to survive screen navigation beyond what a constructor argument already carries, and there's exactly one user.
**Why it's wrong:** Extra package, extra ceremony (providers/notifiers/events), for state that is naturally scoped to one screen's lifetime. `SetupScreen`'s chosen config only needs to reach `SessionScreen` once, via constructor/route arguments — that's not "app state," it's a function argument.
**Do this instead:** `StatefulWidget`/`ChangeNotifier`-per-controller scoped to the screen that needs it (Pattern 1). If a future milestone genuinely needs cross-screen shared state (none of the current 4 screens do), reach for the smallest thing that solves that specific problem then — not preemptively.

### Anti-Pattern 5: Reaching for Drift/codegen ORMs for a 2-table schema

**What people do:** Pick a "recommended" persistence layer for its type-safety/compile-time-checked-queries reputation (Drift is the commonly cited choice over raw `sqflite`) without weighing the cost of introducing `build_runner` code generation for what is here just two tables (`sessions`, `answers`) with simple insert/select/update statements.
**Why it's wrong:** Drift's safety benefits are real, but the setup cost (table classes, generated code, build step in the dev loop) is disproportionate to two hand-writable tables, and directly works against "least code." Plain `sqflite` with a handful of hand-written SQL statements is fewer total lines and no extra build step for this schema.
**Do this instead:** Use `sqflite` directly with hand-written `CREATE TABLE`/`INSERT`/`SELECT` strings inside `LocalDbService`. Revisit Drift only if the schema grows materially past this app's scope.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Firestore (`cloud_firestore`) | `FirestoreService` wraps `.get()` reads and one `WriteBatch` write path (import) | Confidence: MEDIUM (Context7/official docs). `where()`/`Filter` for querying by subject/level; `WriteBatch` caps at 500 writes per batch — chunk imports larger than that. `FieldValue.serverTimestamp()` for `created_at`. No Firestore reads happen during the timed practice loop — all questions for a session are fetched once up front in `SetupScreen`, so no network dependency mid-recording (matches PROJECT.md's "never block on network calls mid-loop"). |
| `record` package (audio recording) | `AudioService.startRecording(path)` / `stopRecording()` | Confidence: MEDIUM (Context7/official docs). `AudioRecorder()` + `hasPermission()` + `start(RecordConfig(), path: fullPath)` + `stop()` returning the path + `dispose()`. Needs `RECORD_AUDIO` (Android) / mic usage description (iOS) permission declared. |
| Audio playback package (e.g. `audioplayers`) | `AudioService.play(path)` / `stop()` | Confidence: LOW (general knowledge, not independently verified this session) — `record` only handles recording, a separate playback package is needed; `audioplayers` is the commonly used lightweight pairing for local-file playback and is a reasonable default for this app's needs (play one local `.m4a` at a time, no streaming/mixing requirements). Worth a quick doc check when this phase is actually built. |
| `sqflite` (local persistence) | `LocalDbService` wraps raw SQL for `sessions`/`answers` tables | Confidence: LOW (general web-search synthesis, not independently pinned to current docs). Two tables, hand-written SQL, no codegen — see Anti-Pattern 5. |
| `path_provider` | Used once, to resolve `getApplicationDocumentsDirectory()` for both the SQLite file and the `recordings/` folder | Standard companion package for local file storage in Flutter. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `SetupScreen` ↔ `SessionScreen` | Constructor/route arguments (`SessionConfig` + `List<Question>`) | One-way handoff at navigation time; no shared/global state object. |
| `SessionScreen` ↔ `SessionController` | `SessionController` is constructed by `SessionScreen`'s `State`, exposed via `ChangeNotifier`/`AnimatedBuilder` (or passed down if you prefer `ValueListenableBuilder` on individual fields) | Screen is pure rendering of controller state; all timer/recording/DB logic lives in the controller, not in widget build methods. |
| `SessionController` ↔ `LocalDbService`/`AudioService` | Direct method calls, `await`ed inline in the phase-transition logic | No event bus, no streams needed — the controller drives a linear sequence. |
| `HistoryListScreen`/`SessionDetailScreen` ↔ `LocalDbService` | Direct `FutureBuilder` over service calls, re-queried each time the screen is opened | No caching/state layer — SQLite reads are fast enough that re-querying on navigation is simpler and sufficiently performant than maintaining a cache. |
| Any screen ↔ `FirestoreService` | Direct method calls, only from `SetupScreen` (reads) and the import screen/dialog (write) | Firestore is never touched from `SessionScreen`/history screens. |

## Build Order Implications (for vertical-slice phasing)

Component dependencies point toward this build order — each phase should be a working end-to-end slice, not a layer:

1. **Recording + incremental-save + playback + minimal history, single hardcoded question.** Build `AudioService`, `LocalDbService` (schema + insert-as-you-go), the file-naming/relative-path scheme, and a bare-bones `HistoryListScreen`/`SessionDetailScreen`, driven by one hardcoded `Question`. This proves the hardest, most crash-sensitive part of the whole app (Patterns 2 & 3, Anti-Patterns 2 & 3) before any UI polish or multi-question looping exists. No Firestore needed yet.
2. **Full timed loop / state machine over N questions.** Layer in `SessionController`'s phase enum, `Timer`-driven countdown/auto-stop/auto-replay, and looping through a small in-memory `List<Question>` (still hardcoded or trivially stubbed) — this is where Pattern 1 gets built, reusing the persistence primitives from step 1 unchanged.
3. **Firestore integration for real question data.** `FirestoreService.fetchTopics()`/`fetchQuestions()`, wire `SetupScreen`'s topic/level/count/timing inputs to real data, replace the hardcoded question list feeding `SessionController`. This is naturally last among the "core loop" phases because it only supplies input data to a loop that already works end-to-end.
4. **JSON import + seed data + session-controls polish (pause/resume/stop confirmation).** These are additive features on top of an already-working record→save→replay→history loop and the already-working Firestore read path; nothing else depends on them.

This order means the single highest-risk requirement in PROJECT.md — "an app kill/crash mid-session must not lose already-answered questions" — gets built and is verifiable in the very first phase, rather than being bolted on after the UI/looping/Firestore work is done.

## Sources

- `record` package official docs, via Context7 (`/websites/pub_dev_packages_record`, source https://pub.dev/packages/record) — MEDIUM confidence
- `cloud_firestore`/FlutterFire official docs, via Context7 (`/firebase/flutterfire`, source https://github.com/firebase/flutterfire) — MEDIUM confidence
- [Flutter Project Structure: Feature-first or Layer-first? (codewithandrea.com)](https://codewithandrea.com/articles/flutter-project-structure/) — LOW confidence (web search + fetch), used for the "avoid over-engineering small apps" framing
- Web search synthesis on sqflite vs Drift vs Hive (multiple blog sources, no single authoritative source pinned) — LOW confidence, cross-checked against the project's own explicit least-code constraint before recommending plain `sqflite`
- Web search synthesis on Flutter `Timer`/`StatefulWidget` countdown patterns — LOW confidence, consistent with well-established Flutter idioms
- `.planning/PROJECT.md` — authoritative source for the app's actual requirements (crash-safety, local-only storage, Firestore-for-question-bank-only, "least code" priority) that drove every recommendation above

---
*Architecture research for: small single-user Flutter spoken-English practice app*
*Researched: 2026-08-07*
