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
| `cloud_firestore` | ^6.8.0 (**installed: 6.8.0**) | Read-only-ish access to the question bank (`questions` collection) + bulk write on JSON import | This is the project's explicit, non-negotiable backend choice (per PROJECT.md). Official Firebase Flutter plugin. No Firebase Auth needed — the open rules tradeoff is now documented in `firestore.rules` and in PROJECT.md's Key Decisions, with its concrete exposure and its exit condition. **Installed in Phase 3;** the collection is `questions` and its name lives in exactly one place, `kQuestionsCollection`. **D-32's refinement of this file's older "derive distinct subjects client-side" wording:** the client-side derivation is KEPT for the topic checkbox list (`normalizeSubjects` over one collection read), but the per-session fetch is a genuinely filtered **server-side** query — `subject in […]` + `level ==` + `orderBy created_at`, behind the composite index in `firestore.indexes.json` — so the query that runs is the query that is tested, rather than one path deriving topics and a second, untested one deriving questions. **`whereIn` carries at most 30 values** (confirmed against this installed version's own assert in `lib/src/query.dart`; other operators cap at 10). That assert is stripped from release builds, which is exactly why `kMaxTopicsPerQuery` guards the edge explicitly before the query rather than trusting the SDK. |
| `firebase_core` | ^4.13.0 (**installed: 4.13.0**) | Mandatory Firebase app bootstrap (`Firebase.initializeApp()`) | Required transitive dependency of any Firebase plugin; not optional. Paired with `firebase_options.dart` generated once via the `flutterfire configure` CLI (a dev tool, not a runtime package). Installed in Phase 3; `Firebase.initializeApp()` runs in `main()` before the first frame, alongside `configureFonts()`. **These two packages are what put `INTERNET` and `ACCESS_NETWORK_STATE` into the merged release manifest** — see the `wakelock_plus` row for the verified complete permission set. |
| `sqflite` | ^2.4.3 | Embedded local DB for session history: sessions + per-question recordings, written incrementally, queryable for the history screen | Raw SQLite, zero code generation, zero build_runner step — the leanest embedded-DB option that still gives real ACID transactions (each `INSERT` after a question is captured is durably committed, which is exactly the "crash-safe, question-by-question" requirement). Two small tables (`sessions`, `question_answers`) is well within "just write SQL," no ORM warranted. |
| `path_provider` | ^2.1.6 | Resolve on-device directories for the SQLite file and recorded audio files (`getApplicationDocumentsDirectory()`) | Official Flutter-team plugin, required by both `sqflite` (DB file path) and `record` (output file path) workflows. Trivial, near-zero-API surface. |
| `file_picker` | ^11.0.3 | Let the user pick a JSON file from device storage for bulk question import | Standard, most-used Flutter file picker. Supports `FileType.custom, allowedExtensions: ['json']` to restrict the OS picker to JSON files directly, avoiding any custom validation UI. Reached only through the `JsonFilePicker` seam (`lib/services/json_file_picker.dart`), never directly. **It costs no permission** — re-verified against the merged release manifest on 2026-08-10 (see the `wakelock_plus` row for the full set). **It does contribute one non-permission manifest element:** a `<queries>` entry for `android.intent.action.GET_CONTENT` with mime type `*/*`, from the plugin's own library manifest — an Android 11+ package-visibility declaration, not an access grant, and it is why the merged manifest's `<queries>` block has two `<intent>` children where the source manifest has one. **It DOES need one piece of Android build configuration beyond the pubspec entry, and without it the release build does not compile:** see the `file_picker` block in `android/build.gradle.kts`. Under this app's AGP 9.0.1 the plugin skips applying the Kotlin Gradle Plugin and expects AGP's Built-in Kotlin, which `android.builtInKotlin=false` disables, so its Kotlin-only Android implementation is never compiled and `GeneratedPluginRegistrant.java` fails on a missing `FilePickerPlugin` symbol. **iOS needs nothing:** the `FileType.custom` path uses `UIDocumentPickerViewController`, which requires no `Info.plist` usage-description key — the plugin's `UIImagePickerController` code is on its gallery/media paths, which this app never calls. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `dart:convert` (SDK, no package) | bundled | Parse imported JSON (`jsonDecode`) and encode/decode any structured local blobs | Always — this is a Dart SDK library, not a pub package. Do not add a third-party JSON package for this; the app's JSON shape is trivial (`{"data": [...]}`). |
| `dart:io` (SDK, no package) | bundled | Read the picked JSON file (`File(path).readAsString()`), write/delete audio files | Always — SDK library. No package needed for basic file I/O. |
| Flutter `ChangeNotifier` / `ValueNotifier` + `ListenableBuilder` (Flutter SDK, no package) | bundled | Share practice-loop engine state (countdown phase, pause/resume/stop, current question index) between the app bar actions and the practice screen body | Use this instead of any state-management package. It is built into `package:flutter/foundation.dart` and `package:flutter/widgets.dart` — zero added dependency, and this app has exactly one screen-flow (setup → practice loop → history) that needs cross-widget state sharing. |
| `path` | ^1.9.0 | Join filesystem path segments (`join(dir.path, 'file.m4a')`) for the SQLite DB file and recorded audio files | Tiny Dart-team-maintained path-joining utility, required by sqflite's documented usage pattern; added in Phase 1. |
| `google_fonts` | ^8.2.1 | Load the Baloo 2 Google Font for headings/question text only, reinforcing the cartoon-like feel (D-15) | Display/Heading text roles only — a single font-family package addition, not a UI framework; consistent with the project's minimize-packages constraint since it replaces zero existing code and adds one dependency for one visual requirement. Body/Label roles stay on the default Material font. Added in Phase 1 Plan 2. **Offline by construction (Phase 1 Plan 5):** the Baloo 2 SemiBold instance is bundled at `assets/fonts/Baloo2-SemiBold.ttf` and `GoogleFonts.config.allowRuntimeFetching` is set to `false` in `configureFonts()` before the first frame, so font loading never touches the network — without this the release APK silently fell back to the default Material font, since back then the `INTERNET` permission existed only in the debug/profile manifests. **Phase 3 makes the bundled asset and the runtime-fetch guard matter MORE, not less** (D-39): the release build now genuinely carries `INTERNET`, so a runtime font fetch would no longer fail loudly at the permission boundary — it would *succeed*, silently reintroducing a network round-trip on the app's first frame and a silent fallback whenever the CDN is slow. The guard is what `test/theme/typography_test.dart` asserts on, and it stays. |
| `wakelock_plus` | ^1.7.0 | Hold the screen awake for the duration of an active practice session (D-30) | Session lifetime only — `enable()` on session entry, `disable()` on session end, on screen dispose and on backgrounding. **Why it earns an exception to the minimize-packages constraint:** the default OS screen timeout (commonly 30 s) is frequently shorter than one thinking-time-plus-answer-length cycle, so without it the screen locks mid-answer while the user is still speaking — the drill breaks at exactly the moment it matters. It costs exactly one seam (`lib/services/screen_wake_controller.dart`, two methods) and two call sites; removing it is deleting the seam's production implementation and one dependency line. **Pin `^1.7.0`, never `^1.6.x`:** 1.7.0 ships the fix that defers the Android wakelock toggle when no activity is attached — 1.6.x throws `NoActivityException` in that state, which is exactly the situation the D-31 interruption path creates when it releases the wakelock on backgrounding. **Permission mechanism (corrects an earlier note that credited the plugin's own manifest):** the plugin declares **no permission of any kind** — its Android library manifest is a bare `<manifest package="dev.fluttercommunity.plus.wakelock"></manifest>`, Android is implemented as the `FLAG_KEEP_SCREEN_ON` window flag and iOS as `isIdleTimerDisabled`, neither of which needs a permission or an entitlement. Verified in Phase 2 Plan 5, again in Phase 3 Plan 3, and **re-verified on 2026-08-10 in Phase 4 Plan 5 after `file_picker` was added** — every time against the **merged release manifest** (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), never merely against the source manifest. **The Phase 2 claim that `RECORD_AUDIO` is the release build's only permission is retired — it was true then and is false now.** The Phase 3 merged release manifest declares `RECORD_AUDIO` (from this app's own manifest) plus `INTERNET` and `ACCESS_NETWORK_STATE` (both contributed by `firebase-firestore:26.5.0`). **Phase 4's re-verification found that set UNCHANGED — the file picker contributed no permission at all**, which is a finding in its own right and is why it is written down rather than left silent. Grepping the merged manifest for `<uses-permission` (the form that also catches an app-namespaced entry, per the source manifest's own instruction) returns exactly four lines, and this is the complete set the release build ships with: `android.permission.RECORD_AUDIO`, `android.permission.INTERNET`, `android.permission.ACCESS_NETWORK_STATE`, and `com.englishreflex.englishreflex.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` — the last being the app-scoped `signature`-protection-level receiver permission from `androidx.core:core` that the Flutter embedding pulls in. No analytics, advertising-ID, location, account or storage permission. The wakelock row's own point is untouched: `wakelock_plus` still declares **no permission of any kind**, and neither `FLAG_KEEP_SCREEN_ON` nor `isIdleTimerDisabled` needs one. Under `flutter test` the package reaches a pigeon-generated method channel and raises `MissingPluginException` unmediated; it is therefore always called through the `ScreenWakeController` seam, never directly. |
| `cupertino_icons` (default Flutter template) | ^1.0.8 | Default icon set | Keep the stock default; do not add a second icon package (e.g. `flutter_icons`) for a small colorful/cartoon UI — Material icons + a couple of custom PNG/SVG mascot assets are enough. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `sqflite_common_ffi` (dev_dependency, ^2.3.0) | Run `DatabaseHelper` against a real SQLite engine inside `flutter test` (no device/emulator) via `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` | Test-only; never shipped in the app binary. Added in Phase 1. |
| FlutterFire CLI (`flutterfire configure`) | One-time generation of `firebase_options.dart` and per-platform Firebase config | Run once during project setup, not a runtime dependency. Requires a Firebase project created in the console first (Firestore in Native mode, no Auth product needed). |
| Firestore Security Rules — **the repo is the source of truth**, not the console | Restrict the `questions` collection to read/write without requiring Firebase Auth (since the app has no login) | **Edit `firestore.rules` in the repo and deploy with `firebase deploy --only firestore:rules,firestore:indexes`; do NOT edit rules in the Firebase console** — a console edit is invisible to code review and is silently overwritten by the next deploy. `firestore.indexes.json` holds the composite index the session query needs, and is deployed the same way. Because there's no auth, the rules intentionally allow unauthenticated read *and* write on `questions`; the file's own header comment states the exposure and the exit condition in full, and PROJECT.md's Key Decisions carries the same statement. This is an accepted tradeoff of the "no backend beyond Firestore, no auth" constraint, not an oversight. |

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

Established across Phases 1–3 and reinforced by each. These are the house rules a new
change is expected to follow.

- **Platform and network dependencies live behind injectable constructor seams, resolved
  lazily.** `RecorderBackend`, `AudioPlaybackBackend`, `documentsDirProvider`,
  `DatabaseHelper`, `ScreenWakeController` and `QuestionSource` all have the same shape: an
  abstract contract free of package types, a named production implementation, and
  `late final X _x = widget.x ?? RealX()` so a test that injects a fake never constructs the
  real one and never touches a platform channel. Host-testability stops **at** the seam —
  the thin adapter behind it is proven by on-device UAT, not by a mock of the vendor SDK.
- **No vendor type crosses a seam.** No `QuerySnapshot`, `DocumentSnapshot` or
  `FirebaseException` appears anywhere under `lib/screens/` or `lib/state/` — only
  `List<String>` out and the seam's own exception type in.
- **A read failure is never presented as missing data.** "You have nothing" and "I could
  not ask" are different facts and get different states. In practice this means a nullable
  data field (`null` = never loaded) next to an empty collection (= the server confirming
  emptiness), never one value spelled both ways — and a zero-result read served *from cache*
  is unreachable, not empty.
- **One fixed user-facing string per failure.** Exception text, error codes, collection
  names, document IDs and project IDs never reach the screen; detail goes to `debugPrint` /
  `FlutterError.reportError` only. Where two failures have different retry affordances they
  get two strings, because the copy has to name the affordance that is actually there.
- **A failure never costs the user their setup.** Every topic, level and slider value
  survives every error path.
- **Every colour and text style comes from `Theme.of(context)`.** `lib/main.dart` is the
  single source of the palette and type scale; no hex literal in a screen, and `textScaler`
  is never pinned.
- **Tests mirror `lib/` path for path** under `test/`, and shared test doubles are imported
  across test files rather than copied — a second copy of a double is a second model of the
  rule it stands for, free to drift from the one the code is actually tested against. Test
  fixture data lives in `test/fixtures/`, never in `lib/`.
- **Edge cases fail loudly rather than silently degrading.** A selection wider than
  Firestore's `whereIn` cap throws instead of being trimmed to fit; a malformed document is
  skipped *and logged* with its ID instead of rendering blank.
- **Doc comments record the decision and the rejected alternative,** tagged with the
  decision ID (D-nn). A comment that says what the code does is redundant; one that says
  what was considered and discarded is why the next change does not silently undo it.
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
