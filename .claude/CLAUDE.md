<!-- GSD:project-start source:PROJECT.md -->

## Project

**EnglishReflex**

A simple, colorful Flutter mobile app for practicing spontaneous spoken English ("phản xạ" — reflex speaking practice). The user configures a practice session (topics, CEFR level, question count, timings), then goes through a timed loop: a question appears, a countdown runs, the app records the user's spoken answer, auto-stops after a max duration (or the user stops manually), optionally replays the recording, then moves to the next question. Every session and its recordings are saved locally and can be replayed later. The question bank lives in Firebase and can be extended by importing a JSON file. Built for a single user studying independently, prioritizing speed of use over feature breadth.

**Core Value:** The user can drill spoken English under real time pressure (timed prompt → forced recording → auto-advance) and can always go back and listen to exactly what they said on any past question.

### Constraints

- **Platform**: Flutter (single codebase, mobile-first) — user-specified
- **Backend**: Firebase (Firestore) for the question bank only — user-specified; nothing else needs a backend
- **Local storage**: session history + audio files must persist on-device across app restarts, written incrementally during the session — user-specified reliability requirement
- **Simplicity**: minimize code volume and screen count; avoid speculative abstractions — user-specified priority ("nhanh nhất, ít code nhất")
- **Docs**: despite the lean code, documentation must be thorough enough to hand off/resume later — user-specified

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `record` | ^7.1.1 | Microphone → audio file recording (start/stop, max-duration handling) | The de-facto standard Flutter recording plugin. Cross-platform (Android/iOS at minimum, which is all this app needs), actively maintained (published ~39 days before this research), has a built-in `hasPermission()`/simple start/stop API — no need for a separate permission_handler dependency for the basic record flow. |
| `audioplayers` | ^6.8.1 | Playback of a single locally recorded file (replay a question's answer) | Simplest API of the two mainstream options for "play this one local file, maybe stop it." `DeviceFileSource(path)` plays a local file directly. Skip `just_audio` (see Alternatives) — its extra feature surface (playlists, gapless looping, background-audio session handling) is pure overhead here since there's no background playback or streaming requirement. |
| `cloud_firestore` | ^6.8.0 | Read-only-ish access to the question bank (`questions` collection) + bulk write on JSON import | This is the project's explicit, non-negotiable backend choice (per PROJECT.md). Official Firebase Flutter plugin, actively maintained (published 3 days before this research). No Firebase Auth needed — Firestore can be used with open/dev-mode security rules for a single-user local app (document this tradeoff explicitly in the phase that sets up Firestore rules). |
| `firebase_core` | ^4.13.0 | Mandatory Firebase app bootstrap (`Firebase.initializeApp()`) | Required transitive dependency of any Firebase plugin; not optional. Paired with `firebase_options.dart` generated once via the `flutterfire configure` CLI (a dev tool, not a runtime package). |
| `sqflite` | ^2.4.3 | Embedded local DB for session history: sessions + per-question recordings, written incrementally, queryable for the history screen | Raw SQLite, zero code generation, zero build_runner step — the leanest embedded-DB option that still gives real ACID transactions (each `INSERT` after a question is captured is durably committed, which is exactly the "crash-safe, question-by-question" requirement). Two small tables (`sessions`, `question_answers`) is well within "just write SQL," no ORM warranted. |
| `path_provider` | ^2.1.6 | Resolve on-device directories for the SQLite file and recorded audio files (`getApplicationDocumentsDirectory()`) | Official Flutter-team plugin, required by both `sqflite` (DB file path) and `record` (output file path) workflows. Trivial, near-zero-API surface. |
| `file_picker` | ^11.0.3 | Let the user pick a JSON file from device storage for bulk question import | Standard, most-used Flutter file picker. Supports `FileType.custom, allowedExtensions: ['json']` to restrict the OS picker to JSON files directly, avoiding any custom validation UI. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `dart:convert` (SDK, no package) | bundled | Parse imported JSON (`jsonDecode`) and encode/decode any structured local blobs | Always — this is a Dart SDK library, not a pub package. Do not add a third-party JSON package for this; the app's JSON shape is trivial (`{"data": [...]}`). |
| `dart:io` (SDK, no package) | bundled | Read the picked JSON file (`File(path).readAsString()`), write/delete audio files | Always — SDK library. No package needed for basic file I/O. |
| Flutter `ChangeNotifier` / `ValueNotifier` + `ListenableBuilder` (Flutter SDK, no package) | bundled | Share practice-loop engine state (countdown phase, pause/resume/stop, current question index) between the app bar actions and the practice screen body | Use this instead of any state-management package. It is built into `package:flutter/foundation.dart` and `package:flutter/widgets.dart` — zero added dependency, and this app has exactly one screen-flow (setup → practice loop → history) that needs cross-widget state sharing. |
| `path` | ^1.9.0 | Join filesystem path segments (`join(dir.path, 'file.m4a')`) for the SQLite DB file and recorded audio files | Tiny Dart-team-maintained path-joining utility, required by sqflite's documented usage pattern; added in Phase 1. |
| `google_fonts` | ^8.2.1 | Load the Baloo 2 Google Font for headings/question text only, reinforcing the cartoon-like feel (D-15) | Display/Heading text roles only — a single font-family package addition, not a UI framework; consistent with the project's minimize-packages constraint since it replaces zero existing code and adds one dependency for one visual requirement. Body/Label roles stay on the default Material font. Added in Phase 1 Plan 2. **Offline by construction (Phase 1 Plan 5):** the Baloo 2 SemiBold instance is bundled at `assets/fonts/Baloo2-SemiBold.ttf` and `GoogleFonts.config.allowRuntimeFetching` is set to `false` in `configureFonts()` before the first frame, so font loading never touches the network and the release build stays free of any network permission — without this the release APK silently fell back to the default Material font, since the `INTERNET` permission exists only in the debug/profile manifests. |
| `cupertino_icons` (default Flutter template) | ^1.0.8 | Default icon set | Keep the stock default; do not add a second icon package (e.g. `flutter_icons`) for a small colorful/cartoon UI — Material icons + a couple of custom PNG/SVG mascot assets are enough. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `sqflite_common_ffi` (dev_dependency, ^2.3.0) | Run `DatabaseHelper` against a real SQLite engine inside `flutter test` (no device/emulator) via `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` | Test-only; never shipped in the app binary. Added in Phase 1. |
| FlutterFire CLI (`flutterfire configure`) | One-time generation of `firebase_options.dart` and per-platform Firebase config | Run once during project setup, not a runtime dependency. Requires a Firebase project created in the console first (Firestore in Native mode, no Auth product needed). |
| Firestore Console — Security Rules | Restrict the `questions` collection to read/write without requiring Firebase Auth (since the app has no login) | Because there's no auth, rules must intentionally allow unauthenticated read (and write, for JSON import) on `questions` — document this as an accepted tradeoff of the "no backend beyond Firestore, no auth" constraint, not an oversight. |

## Installation

# Core

# Firebase project wiring (one-time, not a pubspec dependency)

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| `audioplayers` for playback | `just_audio` | If the app later needs background/lock-screen playback, playlists, gapless looping, or streaming from a URL. Not needed here — playback is always "replay the one file I just recorded," foreground only. |
| `sqflite` (raw SQL) | `drift` (SQL ORM, formerly Moor) | If the schema grows past a handful of tables/queries and type-safety/reactive streams become worth the `build_runner` codegen tax. Drift is the safer long-term choice for a bigger app, but for 2 tables and a handful of hand-written queries it's net-more code and tooling for this MVP. |
| `sqflite` | `Hive` / `Isar` | Never, for a new project right now — both were abandoned by their original maintainer; Isar in particular is explicitly flagged by the community as stalled, with only unofficial forks continuing it. Don't build crash-safety-critical persistence on an unmaintained engine. |
| Flutter `ChangeNotifier`/`ValueNotifier` (no package) | `provider` | If a second, unrelated feature area emerges later that also needs to read the same shared state from a distant part of the widget tree (e.g. a future settings screen affecting the practice loop). `provider` is a thin, well-regarded wrapper around `InheritedNotifier` and is the natural next step — but adding it now for a single screen-flow is premature. |
| Flutter `ChangeNotifier`/`ValueNotifier` | `riverpod` / `bloc` / `GetX` | Only if the app grows multiple independent feature modules, needs dependency injection across many screens, or needs testable business-logic separation at scale. All are excellent tools — none are proportionate to a 3-screen (setup, practice, history) app with one shared engine object. |
| `file_picker` | `image_picker`, custom platform channels | Never for this use case — `file_picker` is the only package of the group built for arbitrary-file (JSON) selection with extension filtering. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| `Isar` / `Hive` | Both abandoned by their original author; community forks are a maintenance liability, not a feature, for a project meant to be simple to hand off/resume later | `sqflite` |
| `drift` / `floor` / `ObjectBox` for this schema | Adds a codegen step (`build_runner`, or in ObjectBox's case a native binding generator) for a persistence need that's really "2 tables, 4 queries" — directly contradicts the "leanest possible code, minimal package count" constraint | `sqflite` with hand-written SQL |
| `provider` / `riverpod` / `flutter_bloc` / `GetX` | Solves a state-sharing problem this app doesn't have yet (one screen-flow, one shared engine object); each pulls in an app-wide architecture pattern and extra boilerplate for zero benefit at this scale | `setState` + Flutter's built-in `ChangeNotifier`/`ValueNotifier`/`ListenableBuilder` |
| `firebase_auth` | Explicitly out of scope per PROJECT.md ("no auth"); adding it means sign-in screens, token/session handling, and Firestore rules complexity for a single local user | Open (documented) Firestore rules scoped to the `questions` collection only |
| `firebase_storage` | Explicitly out of scope — recordings must stay device-local per the user's constraint; cloud storage would also add cost/quota management for no requested benefit | Local files via `path_provider` + `dart:io`, referenced by path from `sqflite` |
| `just_audio_background` / any background-audio package | No requirement for lock-screen controls or background playback in this drill-tool use case | Foreground-only `audioplayers` |
| A second Firestore "topics" collection | The schema is explicitly `{id, content, subject, level, created_at}` only; topics are just the distinct `subject` values already present in `questions` | Fetch `questions` once at setup time, derive distinct subjects client-side (small dataset, no need for Firestore's limited/expensive distinct-query workarounds) |

## Stack Patterns by Variant

- Add a small denormalized `subjects` array field or a lightweight `topics` collection maintained by the JSON-import step (write distinct subjects as a side-effect of import).
- Because this isn't needed at current expected scale (a hobby practice app, low hundreds of questions), don't build it pre-emptively.
- That would reintroduce cloud storage (`firebase_storage` or similar) — explicitly deferred; revisit only if the "local-only" constraint changes in a future milestone.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `cloud_firestore ^6.8.0` | `firebase_core ^4.13.0` | Firebase Flutter plugins are released together and version-locked by the FlutterFire team; always let `flutter pub add` / `flutterfire configure` resolve the matching pair rather than hand-pinning both independently. |
| `record ^7.1.1` | Flutter 3.x, current Dart SDK | No known conflicts with the rest of this stack; requires `RECORD_AUDIO` permission (Android manifest) and `NSMicrophoneUsageDescription` (iOS Info.plist) to be added manually regardless of package version. |
| `sqflite ^2.4.3` | `path_provider ^2.1.6` | Standard pairing — `path_provider` resolves the writable app-documents directory, `sqflite` opens the DB file there. No version coupling beyond normal semver. |
| `file_picker ^11.0.3` | Android/iOS | On newer Android targets, picking files from certain scoped-storage locations may prompt runtime permission dialogs handled internally by the plugin; no extra `permission_handler` dependency required for the basic "pick a JSON file" flow. |

## Sources

- pub.dev package pages (direct fetch, official registry) — `record`, `audioplayers`, `just_audio`, `cloud_firestore`, `firebase_core`, `sqflite`, `path_provider`, `file_picker`, `drift` — used for current stable version numbers and last-publish recency. Confidence: MEDIUM (official first-party registry, but tooled as a live web fetch rather than a pinned/cached doc — re-verify exact patch versions at implementation time).
- Context7 `/websites/flutter_dev` (official Flutter docs, "Add multiplayer support using Firestore" cookbook) — verified `cloud_firestore` + `firebase_core` usage pattern (collection/document references, `.get()`/`.snapshots()`, `withConverter`). Confidence: MEDIUM.
- Web search synthesis (Brave-backed) on Isar/Hive maintenance status, Drift vs sqflite vs Hive positioning, and setState-vs-Provider guidance for small apps, cross-checked across multiple independent 2025/2026 articles (Greenrobot Flutter databases overview, Luci Studio "Flutter Local Database Landscape 2026," multiple Medium/dev.to state-management comparisons). Confidence: LOW-to-MEDIUM individually, but treated as reliable where multiple independent sources agreed (Isar/Hive abandonment, Drift's codegen requirement, "don't over-engineer state management for small apps").

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
