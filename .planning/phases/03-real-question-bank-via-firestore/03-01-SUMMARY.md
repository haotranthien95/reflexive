---
phase: 03-real-question-bank-via-firestore
plan: 01
subsystem: question-bank
tags: [firestore, firebase, question-bank, setup-screen, practice-loop, seam, tracer]
status: complete

requires:
  - "Phase 2's QuestionSource seam, PracticeState/PracticeScreen constructor injection, and the SETUP-07 Start gate"
  - "A Firebase project (`reflex-english`) with Firestore in Native mode and no Auth product — created by the user (D-44)"
  - "`flutterfire configure` output committed to main as 38a802c (lib/firebase_options.dart, google-services.json, GoogleService-Info.plist, firebase.json, Gradle plugin wiring)"
provides:
  - "A live, seeded Firestore `questions` collection with deployed rules and a built composite index"
  - "`FirestoreQuestionSource` — the production QuestionSource: subjects read + filtered per-session query"
  - "`QuestionBankUnavailableException` — the read-failed-vs-genuinely-empty signal"
  - "`normalizeSubjects` — the pure, host-testable BANK-02 topic-derivation rule"
  - "`kQuestionsCollection` / `kCreatedAtField` — the single source of truth Phase 4's importer must write against"
  - "The async `QuestionSource` seam (`subjects()` + `questionsFor()`)"
  - "`tool/seed_questions.mjs` — the disposable dev seed (--dry-run / seed / --verify / --force)"
affects:
  - "Plan 02 — builds the loading / empty / could-not-load / zero-result states on top of the seam and the exception this plan introduced"
  - "Plan 03 — retires PlaceholderQuestionSource, kQuestions and kSubjects, and writes down the D-39 permission change in PROJECT.md / .claude/CLAUDE.md"
  - "Phase 4's importer (IMPORT-01..03) — must write `created_at` as a native Firestore Timestamp and supersedes tool/"

tech-stack:
  added:
    - "firebase_core ^4.13.0 — Firebase app bootstrap"
    - "cloud_firestore ^6.8.0 — the question bank; contributes INTERNET to the merged release manifest"
    - "firebase (Web SDK) ^12.17.1 — tool/ only, never in the app binary"
  patterns:
    - "The fourth injectable seam of the established shape: abstract contract free of package types -> named production impl -> `late final X _x = widget.x ?? RealX()`"
    - "Cache-versus-server: a zero-document snapshot with `metadata.isFromCache` true is unreachable, not empty"
    - "Pure normalization extracted out of an untestable adapter, so the rule can be asserted on the host without faking Firestore"

key-files:
  created:
    - "lib/services/firestore_question_source.dart"
    - "firestore.rules"
    - "firestore.indexes.json"
    - "tool/seed_questions.mjs"
    - "tool/package.json"
    - "tool/README.md"
  modified:
    - "firebase.json"
    - ".gitignore"
    - "analysis_options.yaml"
    - "pubspec.yaml"
    - "lib/main.dart"
    - "lib/data/questions.dart"
    - "lib/screens/setup_screen.dart"
    - "lib/screens/practice_screen.dart"
    - "lib/state/practice_state.dart"
    - "android/app/src/main/AndroidManifest.xml"
    - "test/screens/setup_screen_test.dart"
    - "test/screens/practice_screen_test.dart"
    - "test/state/practice_state_test.dart"
    - "test/state/practice_session_test.dart"

decisions:
  - "Task 1 resolved as `option-a`: `created_at` is a native Firestore Timestamp; the Firestore auto-generated document ID IS the schema's `id` and is NOT duplicated in the document. Collection name: `questions`."
  - "The cache-versus-server rule is applied once, in a shared `_read` helper both reads go through, rather than written twice — two copies is how the two reads end up disagreeing about what 'empty' means."
  - "The BANK-02 topic-derivation rule was extracted to a free `normalizeSubjects` function so it is host-testable without `fake_cloud_firestore`, leaving the adapter itself genuinely logic-free as D-47 claims."
  - "`build/**` is excluded from analysis: adding cloud_firestore makes SwiftPM check the Firebase Apple SDKs' full Dart sources into build/macos/SourcePackages, which the analyzer walks."

metrics:
  duration: "~75 min"
  completed: 2026-08-09
  tasks: 2
  commits: 2

actuals:
  tokens: 21000
  tasks: 2
  commits: 2
---

# Phase 3 Plan 01: Real Question Bank via Firestore — Tracer Summary

Setup's topic checkboxes and the practice loop's prompts now come from a live, seeded Firestore
`questions` collection through an async `QuestionSource` seam, with a server-side
`subject in […]` + `level ==` + `orderBy created_at` query behind a deployed composite index —
and no Firebase import anywhere in `lib/state/` or on the practice screen.

## Task 1 — the question-document contract (resolved by the user, no code)

**Selected option id: `option-a`. Collection name: `questions`. Firebase project: `reflex-english`.**

`created_at` is a **native Firestore `Timestamp`**. The Firestore auto-generated document ID **is**
BANK-01's `id` and is deliberately **not** duplicated as an in-document field. Seeded documents carry
exactly `{content, subject, level, created_at}` and nothing else.

Both sides agree on that representation, which was the acceptance criterion:

- `tool/seed_questions.mjs` writes `Timestamp.fromMillis(...)`, strictly increasing at 1 s steps.
- `FirestoreQuestionSource.questionsFor` reads it back via `orderBy(kCreatedAtField)` where
  `kCreatedAtField == 'created_at'`.
- `node tool/seed_questions.mjs --verify` asserts both facts against the live project: *every
  `created_at` is a native Firestore Timestamp* and *the D-43 query returns strictly ascending
  `created_at`*. Both PASS.

## Task 2 — rules, index, seed (commit `b9a0aeb`)

**`firestore.rules`** — deny-by-default, with `allow read, write: if true` under `match
/questions/{questionId}` and nothing at the database root. The comment block above it names the
concrete exposure (anyone with the project ID can read the whole bank and overwrite or delete any
question in it), names Firebase Auth as the only thing that would change it, and states that
recordings, history and session configuration are never written here.

**`firestore.indexes.json`** — composite index on `questions`: `level` asc, `subject` asc,
`created_at` asc, plus the empty `fieldOverrides` array.

**No console divergence.** The authored definition was accepted as-is. `firebase firestore:indexes`
reports it back as `level`, `subject`, `created_at`, `__name__` (all ascending) — `__name__` is
Firestore's implicit tiebreaker, not a change to what was authored. The console's one-click link that
appeared while the index was still building decodes to the same field order, so the plan's "console is
authoritative" fallback was never needed.

**`firebase.json`** — a `firestore` key with `rules` and `indexes` was added as a sibling of
flutterfire's `flutter` block. The `flutter` block is byte-identical to what the CLI wrote.

**`tool/`** — a Node ES-module seed using the **Firebase Web SDK** (v12.17.1), not `firebase-admin`:
the admin SDK bypasses security rules and needs a service-account key, which D-46 rejected, so seeding
through the Web SDK actually exercises the open rules this phase commits to. Credentials are read out
of `lib/firebase_options.dart` so the script cannot seed a project the app does not read.

Deployed with `firebase deploy --only firestore:rules,firestore:indexes` (exit 0), then
`npm install --prefix tool`, `--dry-run`, the real run, and `--verify`.

### Seeded document counts

29 documents. Cells below count **all** documents including the two deliberately malformed ones
(`Daily life` × B1 and `Travel` × A1 each carry one extra).

| Subject                                         | A1 | B1 | C1 | Total |
|-------------------------------------------------|----|----|----|-------|
| Daily life                                      | 3  | 4  | 2  | 9     |
| Food & health                                   | 0  | 3  | 2  | 5     |
| Technology, media and everyday digital habits   | 0  | 2  | 0  | 2     |
| Travel                                          | 3  | 3  | 0  | 6     |
| Work & study                                    | 2  | 3  | 2  | 7     |
| **documents**                                   |    |    |    | **29**|

Valid-only, i.e. the D-45 matrix as specified: `Daily life` 3/3/2, `Work & study` 2/3/2, `Travel`
2/3/**0**, `Food & health` **0**/3/2, the long subject 0/2/0.

- Two genuinely empty combinations: `Travel` × C1 and `Food & health` × A1 (D-41 is now reachable).
- Longest subject name: `Technology, media and everyday digital habits` — 45 chars.
- Longest prompt: 324 chars.
- Two malformed documents: one with no `content` field at all, one whose `content` is whitespace only.

`node tool/seed_questions.mjs --verify` exits 0 with all nine acceptance checks PASS, including a
replay of the real D-43 query.

**Index build latency (expected, not a failure).** The first two `--verify` runs failed with
"The query requires an index. That index is currently building" — exactly the asynchronous case the
plan anticipated. It passed roughly 7 minutes after deploy. The script prints that guidance itself
rather than leaving the next person to decode a Firestore error code.

## Task 3 — the tracer: Firebase boots, Setup reads the bank, the loop drills it (commit `03fbaff`)

**Gradle dialect: `flutterfire configure` emitted the Kotlin-DSL `id("…")` form in BOTH files.** No
conversion was needed. `android/settings.gradle.kts` already carried
`id("com.google.gms.google-services") version("4.4.4") apply false` inside its existing `plugins { }`
block, and `android/app/build.gradle.kts` already carried `id("com.google.gms.google-services")` with
no version, both fenced by `// START/END: FlutterFire Configuration` markers. **Neither Gradle file was
touched by this plan.** This is the fact the next Firebase-touching phase will want: on this
Flutter (3.44.6) / AGP (9.0.1) / FlutterFire CLI combination the Groovy `apply plugin:` fallback did
not occur.

`firebase_core` was **not** in `pubspec.yaml` despite `flutterfire configure` having run — both
packages were added here with `flutter pub add firebase_core cloud_firestore`, letting pub resolve the
version-locked pair.

Everything else landed as planned: `Firebase.initializeApp` before the first frame (after
`ensureInitialized()`, without displacing `configureFonts()`); the async two-member seam; the
`FirestoreQuestionSource` adapter with the cache-versus-server rule; Setup's `questionSource` override
replacing `subjects`, with `_loadSubjects()` started via `unawaited` alongside the untouched orphan
sweep; `_startSession` made async with the config snapshotted synchronously first;
`PracticeState`/`PracticeScreen` taking a resolved `List<String>`; and the AndroidManifest and
`configureFonts()` doc comments rewritten to drop the now-false no-network claim.

`_pickQuestion()` **lost a hop rather than gaining an `await`** — it is still a pure synchronous
function of `questionNumber`, and `questionAt` is byte-identical (D-42).

## Verification

| Gate | Result |
|------|--------|
| `flutter analyze` | No issues found |
| `flutter test` | 181/181 pass (was 170 before this plan) |
| `flutter build apk --debug` | Built `build/app/outputs/flutter-apk/app-debug.apk` |
| `firebase deploy --only firestore:rules,firestore:indexes` | exit 0 |
| `node tool/seed_questions.mjs --verify` | exit 0, 9/9 checks PASS |
| `flutter test test/widgets/phase_control_test.dart` | 13/13 pass — no PracticePhase added |
| No Firebase in the loop | `grep -rE 'cloud_firestore\|firebase_core\|FirebaseFirestore' lib/state/ lib/screens/practice_screen.dart` → no matches |
| No `QuestionSource` field in `PracticeState` | `grep -E 'final QuestionSource' lib/state/practice_state.dart` → no matches |
| Gradle plugin, non-comment lines | 1 in `settings.gradle.kts`, 1 in `app/build.gradle.kts` |
| `grep -c 'isFromCache'` in the adapter | 2 |
| `grep -c 'no network permission'` in AndroidManifest | 0 |
| `grep -c 'DefaultFirebaseOptions.currentPlatform' lib/main.dart` | 1 |

### Two acceptance criteria whose literal counts were unsatisfiable as written

Both are recorded rather than quietly rounded:

1. `grep -c 'Future<List<String>> questionsFor' lib/data/questions.dart` was specified as `1`; the
   actual value is `2`, and likewise for `subjects`. This is a direct consequence of the same task's
   own instruction to "update `PlaceholderQuestionSource` to satisfy both" — the abstract declaration
   and the override each match. Both members exist with the required signature; the criterion's stated
   count is internally inconsistent with the action text, not with the code.
2. `grep -c 'allowRuntimeFetching = false' lib/main.dart` was specified as `1`; the actual value is
   `2`, and **it was already 2 at HEAD before this plan** (`git show HEAD:lib/main.dart` confirms) —
   the second match is prose inside the pre-existing doc comment. Unchanged by this plan.

### Outstanding UAT (not run)

The tracer's `<human-check>` — launch on a networked device, confirm the Topics card shows the seeded
subjects including the 45-character one, tick `Travel` at B1, and confirm the first prompt is a seeded
Travel B1 question rather than a Phase 2 placeholder — **has not been run**. No device or emulator was
attached to this session, and it cannot be discharged from the host. It is recorded in `.planning/WINDOWS.md`
as an `unrun-verify`. Everything mechanically checkable about that path (the query shape, the ordering,
the index, the seeded content) is proven by `--verify` against the live project.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] `flutter analyze` reported 110 issues from a third-party package**

- **Found during:** Task 3, first `flutter analyze` run after `flutter pub add cloud_firestore`.
- **Issue:** Adding `cloud_firestore` makes `flutter pub get` resolve the Firebase Apple SDKs through
  SwiftPM, which checks the package's **full Dart sources** out into
  `build/macos/SourcePackages/cloud_firestore-6.8.0/`. The analyzer walks `build/`, so `flutter analyze`
  reported ~106 lints and 4 errors belonging to `cloud_firestore`'s own example app and tests. The
  phase's "analyze reports no issues" gate was impossible to satisfy honestly, and this project's own
  findings were drowned. Deleting the directory is not a fix — it reappears on the next `pub get`.
- **Fix:** Added an `analyzer: exclude: - build/**` block to `analysis_options.yaml`, with a comment
  explaining why it became load-bearing in this phase. `linter:` and its `rules:` block are unchanged.
- **Files modified:** `analysis_options.yaml` (not in the plan's `files_modified`).
- **Commit:** `03fbaff`

**2. [Rule 2 — Missing critical functionality] Unhandled async errors on both new read paths**

- **Found during:** Task 3, while wiring `_loadSubjects()` and the async `_startSession()`.
- **Issue:** The plan scopes the loading / empty / could-not-load / zero-result branches to plan 02 and
  says this task "wires the success branch only". Taken literally that leaves a throwing
  `QuestionSource` producing an **unhandled async error** out of an `unawaited(...)` call, and leaves
  `PracticeScreen` reachable with an empty bank — where `questionAt` divides by `length` and the loop
  crashes on its first prompt.
- **Fix:** Both paths now contain and `debugPrint` the failure (never surfacing exception text), and
  `_startSession` refuses to navigate on a zero-result query. Each is commented in-place as a **KNOWN
  GAP closed by plan 02**, naming what plan 02 adds. This is containment, explicitly not the handling.
- **Files modified:** `lib/screens/setup_screen.dart`
- **Commit:** `03fbaff`

**3. [Rule 3 — Blocking] Regenerated plugin registrants**

- **Found during:** Task 3, after `flutter pub add`.
- **Issue:** `macos/Flutter/GeneratedPluginRegistrant.swift`,
  `windows/flutter/generated_plugin_registrant.cc` and `windows/flutter/generated_plugins.cmake` are
  tracked generated files that the tool rewrote to register the new plugins. Leaving them uncommitted
  would leave the tree dirty and the registration inconsistent with `pubspec.lock`.
- **Fix:** Committed alongside the dependency change. Not in the plan's `files_modified` because the
  plan did not anticipate the tool touching non-Android platform folders.
- **Commit:** `03fbaff`

### Deliberate design additions (not deviations from intent)

- **`normalizeSubjects` extracted as a free function.** The plan's test acceptance asks for a Setup
  test proving the subject list renders "in case-insensitive sorted order with duplicates collapsed",
  but that normalization belongs to `FirestoreQuestionSource`, which cannot be constructed on the host
  (D-47 rejected `fake_cloud_firestore`). Asserting it through a fake source would have tested the fake.
  The rule is now a pure function covered by five direct unit tests, and `SetupScreen` is tested for
  what it actually guarantees: it renders its source's list verbatim.
- **The seed script refuses to run against a non-empty collection** unless `--force` is passed.
  Documents use auto-generated IDs, so a second run would silently add a duplicate bank rather than
  replace it.
- **`--verify` replays the real D-43 query**, not just a collection read. A plain read needs no index
  and would have passed while the composite index was still building — which is exactly what happened.

## Known Stubs

Each is authorised by the plan (this is the tracer; plans 02 and 03 expand it), and each is recorded
in `.planning/WINDOWS.md`.

| Stub | File | Line | Reason |
|------|------|------|--------|
| A failed subjects read leaves `_subjects` empty, so `_NoTopics` ("No topics yet") doubles as the could-not-load state — the exact lie D-37 forbids | `lib/screens/setup_screen.dart` | ~112 | Plan 02 adds the distinct `setup-topics-error` state with its own Retry (D-37) |
| The frames before the subjects read lands also render `_NoTopics` — there is no loading state | `lib/screens/setup_screen.dart` | ~99 | Plan 02 adds `setup-topics-loading` (D-37) |
| A failed Start query makes the tap do nothing — no inline failure message | `lib/screens/setup_screen.dart` | ~168 | Plan 02 adds the Start-failure surface (D-38) |
| A zero-result query makes the tap do nothing — no message naming level and topics | `lib/screens/setup_screen.dart` | ~178 | Plan 02 adds the zero-result message (D-41) |
| No busy state on START SESSION while the query runs | `lib/screens/setup_screen.dart` | ~157 | Plan 02 adds it (D-33) |
| Malformed documents are skipped silently rather than skipped **and logged** | `lib/services/firestore_question_source.dart` | ~140 | Plan 02 owns skip-and-log |
| No guard on the Firestore `whereIn` limit — a topic selection wider than the limit fails as a raw `FirebaseException` | `lib/services/firestore_question_source.dart` | ~127 | Plan 02 makes it fail loudly rather than truncate (flagged assumption 2) |
| `PlaceholderQuestionSource`, `kQuestions` and `kSubjects` still exist | `lib/data/questions.dart` | 17, 52, 105 | Plan 03 retires them; they keep the pre-existing suite compiling meanwhile |

None of these prevent the plan's goal: the Setup → filtered query → loop path carries real Firestore
data end to end.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: network-egress | `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml` | First network surface in the app. `INTERNET` now reaches the merged release manifest transitively via `cloud_firestore`. The BANK-01 prohibition (no recording, history row or session config leaves the device) is upheld — nothing in this plan writes user practice data to Firestore, and no analytics, crash-reporting or ads SDK was added. **The D-39 merged-release-manifest inspection is still owed** and is a required UAT item: confirm `INTERNET` is the ONLY permission the Firebase dependencies added. |
| threat_flag: unauthenticated-write | `firestore.rules` | The `questions` collection accepts unauthenticated read AND write from anyone holding the project ID. This is D-46's deliberate posture, documented in the rules file itself. `google-services.json` and `firebase_options.dart` are committed to the repo, so the project ID is not secret — that is inherent to a client-side Firebase app with no auth, not new here. |
| threat_flag: credential-in-repo | `lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` | Firebase API keys are committed (committed to main as `38a802c`, before this plan). These are client identifiers rather than secrets by Firebase's design — access is governed entirely by `firestore.rules`, which is why the openness of those rules is the thing that matters. |

## Self-Check: PASSED

Created files verified present:
`lib/services/firestore_question_source.dart`, `firestore.rules`, `firestore.indexes.json`,
`tool/seed_questions.mjs`, `tool/package.json`, `tool/README.md` — all FOUND.

Commits verified in `git log`:
`b9a0aeb` (Task 2) — FOUND. `03fbaff` (Task 3) — FOUND.

No files were deleted by either commit (`git diff --diff-filter=D` empty for both). Working tree clean.
