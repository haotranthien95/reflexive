# Stack Research

**Domain:** Flutter mobile app — spoken-English reflex practice (local-first audio recording/playback + thin Firestore question bank)
**Researched:** 2026-08-07
**Confidence:** MEDIUM (package identities and architectural guidance are well-established / cross-source consistent; exact version numbers were fetched live from pub.dev on the research date and will drift — pin ranges, don't hard-pin patch versions)

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
| `cupertino_icons` (default Flutter template) | ^1.0.8 | Default icon set | Keep the stock default; do not add a second icon package (e.g. `flutter_icons`) for a small colorful/cartoon UI — Material icons + a couple of custom PNG/SVG mascot assets are enough. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| FlutterFire CLI (`flutterfire configure`) | One-time generation of `firebase_options.dart` and per-platform Firebase config | Run once during project setup, not a runtime dependency. Requires a Firebase project created in the console first (Firestore in Native mode, no Auth product needed). |
| Firestore Console — Security Rules | Restrict the `questions` collection to read/write without requiring Firebase Auth (since the app has no login) | Because there's no auth, rules must intentionally allow unauthenticated read (and write, for JSON import) on `questions` — document this as an accepted tradeoff of the "no backend beyond Firestore, no auth" constraint, not an oversight. |

## Installation

```bash
# Core
flutter pub add record audioplayers cloud_firestore firebase_core sqflite path_provider file_picker

# Firebase project wiring (one-time, not a pubspec dependency)
dart pub global activate flutterfire_cli
flutterfire configure
```

No dev-dependency additions are required beyond the default Flutter template (`flutter_lints`, `flutter_test`) — this stack deliberately has no code-generation step (no `build_runner`, no `.g.dart` files to maintain).

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

**If the question bank grows into the thousands and setup-screen topic loading becomes slow:**
- Add a small denormalized `subjects` array field or a lightweight `topics` collection maintained by the JSON-import step (write distinct subjects as a side-effect of import).
- Because this isn't needed at current expected scale (a hobby practice app, low hundreds of questions), don't build it pre-emptively.

**If recordings need to survive an app reinstall or be shared between the user's devices later:**
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

---
*Stack research for: Flutter spoken-English reflex-practice app (EnglishReflex)*
*Researched: 2026-08-07*
