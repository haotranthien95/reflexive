---
phase: 04-bulk-import-seed-content-screen-polish
plan: 01
subsystem: import
tags: [file_picker, cloud_firestore, writeBatch, bottom-sheet, json, dedupe, flutter]

requires:
  - phase: 03-real-question-bank-via-firestore
    provides: "kQuestionsCollection, kCreatedAtField, sanitizedText, normalizeSubjects, QuestionBankUnavailableException, the QuestionSource seam and SetupScreen's D-35 reappearance refresh"
  - phase: 01-record-save-replay-a-single-answer-crash-safe
    provides: "the locked palette, type scale and spacing scale every new surface reads through Theme.of(context)"
provides:
  - "JsonFilePicker seam + FilePickerJsonFilePicker adapter + ImportFileUnreadableException"
  - "question_importer.dart: parseImportFile, dedupeAgainstBank, importDedupeKey, ImportRow/ImportSkip/ImportParse/ImportPlan, ImportSkipReason, ImportFileShapeException, ImportFileEmptyException"
  - "QuestionBankWriter seam + FirestoreQuestionBankWriter (Source.server dedupe read, 500-op chunked commit, D-63 created_at) + kMaxWritesPerBatch + ImportPartialWriteException"
  - "ImportSheet (S1-S4) and its string inventory: kImportIdleMessage, kImportShapeExample, kImportCheckingFileMessage, kImportCheckingBankMessage, kImportKeepOpenMessage, importSavingMessage, importAddedLine"
  - "SetupScreen's second AppBar action, its two new seam parameters, and the sheet-dismiss refresh call site (D-51)"
  - "kLevels relocated into lib/services/firestore_question_source.dart"
  - "test/fixtures/import_files.dart, including the two malformed documents retired from the Phase 3 dev seed (D-58)"
  - "FakeJsonFilePicker and FakeQuestionBankWriter, the scripted doubles later plans extend"
affects: [04-02 import failure states and skip list, 04-03 too-many-topics string, 04-04 tool deletion and docs, 04-05 seed import and manifest audit]

actuals:
  tokens: 27000
  tasks: 2
  commits: 2

tech-stack:
  added: [file_picker ^11.0.3]
  patterns:
    - "Two more seams of the established shape (abstract contract, named production impl, lazily resolved injection)"
    - "A pure validation core extracted to the host-testable side of the seam, with both adapters left thin"
    - "dependency_overrides used to hold two mandated package pins that share no transitive version"

key-files:
  created:
    - lib/services/json_file_picker.dart
    - lib/services/question_importer.dart
    - lib/services/question_bank_writer.dart
    - lib/screens/import_sheet.dart
    - test/fixtures/import_files.dart
    - test/screens/import_sheet_test.dart
    - test/services/question_importer_test.dart
  modified:
    - pubspec.yaml
    - lib/screens/setup_screen.dart
    - lib/services/firestore_question_source.dart

key-decisions:
  - "file_picker ^11.0.3 and wakelock_plus ^1.7.0 share no win32 version; the tie is broken with dependency_overrides on win32 (^5.9.0) and package_info_plus (^9.0.0) rather than by downgrading either mandated pin or adopting file_picker 12.0.0-beta"
  - "kLevels moved from lib/screens/setup_screen.dart into lib/services/firestore_question_source.dart, so the widget-free importer can validate against it without a service importing a screen (D-53)"
  - "PopScope(canPop: !writing) was added inside the sheet in this plan rather than deferred, because the write path is real here and an unreported mid-write dismissal is what IMPORT-04 forbids"
  - "The dedupe key separator is the zero code unit, not a printable character, so no field content can forge a key boundary"
  - "IMPORT-01..03 are deliberately NOT checked off in REQUIREMENTS.md yet — the terminal failure surfaces (plan 02) and the on-device proof (plan 04-05) are still outstanding"

patterns-established:
  - "Seam pair for a two-way platform dependency: one contract for reading the world in (JsonFilePicker), one for writing it out (QuestionBankWriter), neither leaking a vendor type"
  - "Scripted fake with per-call outcomes plus a Completer hold gate, now applied to a picker and a writer as well as a reader"
  - "A file-level failure and a per-row failure are separate types with separate states, mirroring the bank's empty-versus-unreachable split one level down"

requirements-completed: []

coverage:
  - id: D1
    description: "Tapping the Setup AppBar import action opens a modal bottom sheet without pushing a route, and the app's route count is unchanged (D-48)"
    requirement: IMPORT-01
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#carries exactly two always-enabled actions, import first"
        status: pass
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#AppBar action → pick a file → the count that landed → new topics"
        status: pass
    human_judgment: false
  - id: D2
    description: "A well-formed {\"data\": [...]} file writes one Firestore document per valid, non-duplicate row and reports the count that landed"
    requirement: IMPORT-01
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#AppBar action → pick a file → the count that landed → new topics"
        status: pass
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a one-row file writes one document and says so"
        status: pass
    human_judgment: false
  - id: D3
    description: "A decoded value that is not an object, has no `data` key, or whose `data` is not a list is rejected as a FILE problem before any row is examined and before anything is written (D-62)"
    requirement: IMPORT-02
    verification:
      - kind: unit
        ref: "test/services/question_importer_test.dart#parseImportFile — the file itself (D-62)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Normalize-then-validate: content and subject are trimmed, level is upper-cased, and the normalized values are what get written (D-53)"
    requirement: IMPORT-02
    verification:
      - kind: unit
        ref: "test/services/question_importer_test.dart#parseImportFile — normalization (D-53)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every skipped row is named by its reason AND its 1-based position in the file, deterministically (D-55)"
    requirement: IMPORT-02
    verification:
      - kind: unit
        ref: "test/services/question_importer_test.dart#parseImportFile — rejection, by reason and by position (D-55)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Duplicates against the bank and within the file are counted as their own category, never listed per row and never treated as an error; survivors keep file order (D-54)"
    verification:
      - kind: unit
        ref: "test/services/question_importer_test.dart#dedupeAgainstBank (D-54)"
        status: pass
    human_judgment: false
  - id: D7
    description: "Documents carry exactly content/subject/level/created_at with no in-document id, and created_at strictly increases in file order with a fixed 1000 ms step so bank order reproduces file order (D-63, IMPORT-03)"
    requirement: IMPORT-03
    verification: []
    human_judgment: true
    rationale: "The document body and the Timestamp are written by FirestoreQuestionBankWriter, which resolves FirebaseFirestore.instance and is not host-testable (D-47). Only the real backend can show the four fields, the absent id and the ascending order — the ~600-row seed import in plan 04-05 is the proof."
  - id: D8
    description: "The dedupe read is server-only, so an offline import ends before a single document is written rather than spinning on writes queued in the local cache (D-60)"
    verification:
      - kind: unit
        ref: "grep -q \"Source.server\" lib/services/question_bank_writer.dart"
        status: pass
    human_judgment: true
    rationale: "The grep proves the option is passed; only a real device with the network down proves the resulting failure mode. Its user-facing surface is plan 02's S7 and its live proof is plan 04-05."
  - id: D9
    description: "Dismissing the sheet by any route (Done, drag, barrier, system back) re-reads Setup's topics, so imported topics appear without leaving Setup (D-51)"
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#AppBar action → pick a file → the count that landed → new topics"
        status: pass
    human_judgment: true
    rationale: "The test proves the Done route and the single call site. Drag-down and barrier-tap are gesture routes a widget test drives only artificially; the UI-SPEC flags PopScope's coverage of them as Flutter-version-dependent and requires on-device verification of all three."
  - id: D10
    description: "The file-picker adapter handles both the bytes and the path the plugin may return, and turns any I/O or decode failure into ImportFileUnreadableException"
    verification: []
    human_judgment: true
    rationale: "FilePickerJsonFilePicker reaches a platform channel and is not host-testable (D-47). Which of bytes and path each platform populates is unverified in this repo — the adapter logs which branch ran precisely so on-device UAT answers it."

duration: 61min
completed: 2026-08-10
status: complete
---

# Phase 4 Plan 01: End-to-end JSON import Summary

**A Setup AppBar action opens a modal import sheet that validates a whole JSON file in memory, dedupes it against a server-only read of the bank, and commits the survivors in 500-row batches with strictly increasing `created_at` — with both platform dependencies behind injectable seams and the whole path driven by a host test.**

## Performance

- **Duration:** ~61 min
- **Started:** 2026-08-09T23:20Z
- **Completed:** 2026-08-10T00:21Z
- **Tasks:** 2
- **Files modified:** 12 (7 created, 5 modified — including `pubspec.lock` and the generated macOS plugin registrant)

## Accomplishments

- **The spine of the feature works end to end.** Tap the import action → the sheet opens on its idle state with the required format on screen → pick a file → "Checking your file…" → "Comparing with your bank…" → a determinate write bar → "3 questions added" → Done → the new topics are on Setup. Every one of those steps is asserted by `test/screens/import_sheet_test.dart` with both platform seams faked.
- **The architecture is real, not stubbed.** The picker seam, the pure validator, the server-only dedupe read, the chunked `writeBatch` commit and the modal sheet are all production code. Only the four terminal failure surfaces (S5–S8) and the per-row skip list are deliberately absent, as plan 02's expansion.
- **The judgement is on the host-testable side of the seam.** `question_importer.dart` has no Firestore handle, no `File`, no `BuildContext` and no widget import, and 24 unit tests pin D-52, D-53, D-54, D-55, D-62 and the batch cap with no device.
- **`kLevels` moved into the services layer**, which is what makes the widget-free importer possible: without the move, a service would have had to import a screen and close a Setup → sheet → importer → Setup ring.
- **A hard dependency conflict was resolved without moving either mandated pin.** `file_picker ^11.0.3` and `wakelock_plus ^1.7.0` share no `win32` version; the resolution is documented in `pubspec.yaml` with its reversal trigger.

## Task Commits

1. **Task 1 (tracer): End-to-end "import a JSON file into the bank" — one path only** — `e629074` (feat)
2. **Task 2: Pin the import rules that no widget test can reach** — `b76080b` (test)

Tracer feedback gate: after `e629074` the tracer's own `<verify>` was re-run end to end — `flutter analyze --no-fatal-infos` clean and the FULL suite green (211 tests) — before any expansion work started.

## Files Created/Modified

- `lib/services/json_file_picker.dart` — the picker seam: `JsonFilePicker`, `FilePickerJsonFilePicker` (bytes-preferred with a `dart:io` path fallback, both logged), `ImportFileUnreadableException`. No `FilePickerResult` and no `File` leaves the file.
- `lib/services/question_importer.dart` — the pure core: `parseImportFile`, `dedupeAgainstBank`, `importDedupeKey`, `ImportRow`/`ImportSkip`/`ImportParse`/`ImportPlan`, `ImportSkipReason`, and the two file-level signal exceptions. Reuses `sanitizedText` and `kLevels` rather than restating either rule.
- `lib/services/question_bank_writer.dart` — the write seam: `kMaxWritesPerBatch = 500`, `QuestionBankWriter`, `FirestoreQuestionBankWriter` (server-only dedupe read, chunked commit, D-63 timestamps), `ImportPartialWriteException` with a numeric-only payload.
- `lib/screens/import_sheet.dart` — `ImportSheet` (S1 idle, S2 checking, S3 writing, S4 result), the string inventory, and `importSavingMessage`/`importAddedLine` as pure functions.
- `lib/screens/setup_screen.dart` — the prepended `setup-import` action, `maxLines`/ellipsis on the title, two new pass-through seam parameters, `_openImportSheet()`, and the corrected `_refreshSubjectsOnReappear()` doc comment.
- `lib/services/firestore_question_source.dart` — `kLevels` relocated here with the D-53 rationale.
- `pubspec.yaml` — `file_picker ^11.0.3` with its permission-audit note, plus the documented `dependency_overrides` block.
- `test/fixtures/import_files.dart` — 16 fixtures, including the two malformed documents retired from the Phase 3 dev seed.
- `test/screens/import_sheet_test.dart` — `FakeJsonFilePicker`, `FakeQuestionBankWriter` and six end-to-end/in-flight tests.
- `test/services/question_importer_test.dart` — 24 pure unit tests.

## Decisions Made

- **`kLevels` lives in `firestore_question_source.dart`, not in a new file.** That file is already where the project keeps facts a screen and a service must agree on (`kQuestionsCollection`, `kCreatedAtField`, `sanitizedText`), and both call sites already imported it — so the move cost zero new import lines, which is the check that confirmed it was the right destination rather than a third one.
- **The dedupe key separator is the zero code unit.** A pipe or a slash can occur inside a real question or subject, and then `('a', 'b|c')` and `('a|b', 'c')` build the same key and one row silently vanishes as a "duplicate". A value that arrived through `jsonDecode` and passed `sanitizedText` can never contain U+0000. Pinned by a test.
- **`PopScope(canPop: !writing)` shipped in this plan** rather than waiting for plan 02. The write path is real here, so the state a user could dismiss mid-write is real here too, and an unreported partial outcome is exactly what IMPORT-04 forbids.
- **The picker button nulls its handler while the OS picker is open**, keeping the idle body on screen. Moving to the checking state before the pick would have made a cancelled pick flash a caption about a file that was never chosen; leaving the handler live would have made a second tap possible in exactly the frame the UI-SPEC says must be structurally single-shot.
- **REQUIREMENTS.md was not touched.** IMPORT-01's terminal failure surfaces land in plan 02 and its on-device proof in plan 04-05, so checking the three requirements off here would overstate what is done — and REQUIREMENTS.md is a shared artifact other wave agents may also write.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `file_picker ^11.0.3` and `wakelock_plus ^1.7.0` cannot be resolved together**

- **Found during:** Task 1, step 1 (`flutter pub get` after adding the dependency)
- **Issue:** `file_picker 11.0.3` depends on `win32 ^5.9.0` and `wakelock_plus 1.7.0` on `win32 ^6.0.1`, with no overlapping version. Pub refused the entire resolution and suggested downgrading one of the two. Both versions are pinned by CLAUDE.md for stated reasons — `wakelock_plus` must be ≥1.7.0 for the deferred-toggle fix D-31's interruption path depends on, and `file_picker 11.0.3` is the newest stable release (only 12.0.0-beta is on win32 6). Checked against pub: no `wakelock_plus` release exists that wants win32 5 and carries that fix (1.5.2 is the newest on win32 5).
- **Fix:** A documented `dependency_overrides` block pinning `win32: ^5.9.0` and `package_info_plus: ^9.0.0`. The second is required because `wakelock_plus`'s Linux plugin reads an app name from `package_info_plus`, whose whole 10.x line requires win32 6 and does not compile against win32 5; the single API used (`PackageInfo.fromPlatform().appName`) is unchanged in 9.x. `win32` is a Windows-only FFI binding and this app is mobile-only, so nothing that ships links it. The pubspec comment records the exposure, the fact that `flutter test` compiles those Windows Dart sources on the host (which is how the version was chosen — both wrong overrides failed the suite loudly), and the reversal trigger: delete both lines when `file_picker` 12.x leaves beta.
- **Files modified:** `pubspec.yaml`, `pubspec.lock`
- **Verification:** `flutter pub get` resolves; `flutter analyze --no-fatal-infos` clean; the full 235-test suite passes. Both alternative overrides were tried first and each failed the suite at compile time (win32 6 breaks `file_picker`'s Windows source; win32 5 with `package_info_plus` 10 breaks that one).
- **Committed in:** `e629074`

**2. [Rule 2 - Missing Critical] `PopScope` guard on the write state**

- **Found during:** Task 1, step 5 (`import_sheet.dart`)
- **Issue:** The plan's task list enumerates states S1–S4 and does not mention `PopScope`, but this plan builds the REAL write path — so the state the UI-SPEC calls "the only non-dismissible state" is reachable in this plan, not just in plan 02. A user dismissing mid-write would never learn which rows landed, which is the unreported partial outcome IMPORT-04 exists to prevent.
- **Fix:** `PopScope<void>(canPop: _phase != _ImportPhase.writing)` wrapping the sheet body, using the same mechanism `practice_screen.dart` already uses for the Stop dialog (D-29).
- **Files modified:** `lib/screens/import_sheet.dart`
- **Verification:** `test/screens/import_sheet_test.dart` asserts `canPop` is false while the held write is in flight and true once the result renders.
- **Committed in:** `e629074`

**3. [Rule 1 - Bug] `FilePicker.platform.pickFiles` does not exist in file_picker 11**

- **Found during:** Task 1 (first `flutter analyze` after writing the adapter)
- **Issue:** The instance-based `FilePicker.platform` getter is gone in 11.x; `FilePicker` is an `abstract final class` whose entry points are statics.
- **Fix:** Call `FilePicker.pickFiles(...)` directly, with a comment recording the verification against the installed 11.0.3 source so the next reader does not "fix" it back.
- **Files modified:** `lib/services/json_file_picker.dart`
- **Verification:** `flutter analyze --no-fatal-infos` clean.
- **Committed in:** `e629074`

**4. [Rule 1 - Bug] The dedupe separator was written as a literal NUL byte**

- **Found during:** Task 1 (self-review after writing `question_importer.dart`)
- **Issue:** The separator constant was authored with a raw U+0000 character embedded in the source file rather than the ` ` escape. It compiled, but it made the file binary to `grep` and would have been invisible and unmaintainable in any editor.
- **Fix:** Replaced with the escape sequence; asserted no raw NUL survives anywhere in the file.
- **Files modified:** `lib/services/question_importer.dart`
- **Verification:** Full suite green, including the two `importDedupeKey` separator tests added in task 2.
- **Committed in:** `e629074`

---

**Total deviations:** 4 auto-fixed (1 blocking, 1 missing critical, 2 bugs)
**Impact on plan:** No scope creep. The dependency override is the only one with a lasting maintenance cost, and it carries an explicit reversal trigger. Every plan artifact, symbol, key and acceptance criterion was delivered as written.

## Issues Encountered

- **The host test compiler reaches Windows-only package sources.** `flutter test` on macOS compiles the conditionally-exported Windows implementations of `file_picker`, `wakelock_plus` and `package_info_plus`, so a `dependency_overrides` choice that looks harmless for a mobile-only app is not silent — it fails the suite at compile time. That is what turned the win32 tie-break from a guess into a decision with evidence, and it is recorded in the pubspec comment so the next person does not have to rediscover it.
- **`flutter analyze` does not analyze package sources**, so it passed while the suite could not compile. Both gates are needed; neither substitutes for the other.

## Known Stubs

None that block this plan's goal. Two deliberate, plan-scoped absences, both named in the plan as later work:

- **The four terminal failure surfaces (S5 file problem, S6 file empty, S7 bank unreachable, S8 partial write) and the per-row skip list are not built.** Every failure on the import path is currently logged with `debugPrint` and lands back on the idle state. That is honest about having done nothing, but it does not yet explain *why* — which is plan 02's expansion. The signals those states will render (`ImportFileUnreadableException`, `ImportFileShapeException`, `ImportFileEmptyException`, `QuestionBankUnavailableException`, `ImportPartialWriteException`) are all thrown, typed and distinguishable today, so plan 02 adds screens, not plumbing.
- **The result card shows only the added count.** `ImportPlan.duplicateCount` and `ImportPlan.skips` are computed and carried but not rendered; `importDuplicatesLine`, `importSkippedLine`, `kImportSkipListLabel` and `importSkipReason` are plan 02's strings.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: untrusted-input-render | `lib/screens/import_sheet.dart` | This plan renders nothing from the picked file, so the UI-SPEC's length-cap and newline-strip rules are not yet exercised. Plan 02's skip list is the first surface that echoes file content back (`questionText`, `offendingLevel`) and MUST apply them — `ImportSkip` carries both values raw and uncapped by design, because capping belongs at the render site where the bound is known. |
| threat_flag: unauthenticated-write | `lib/services/question_bank_writer.dart` | First client-side WRITE path through the open `questions` rules (D-46). No new collection and no rule change, as CONTEXT requires — but the app can now append to the bank from a device with no auth, which is the exposure D-46 accepted made concrete. Worth re-reading `firestore.rules`' header when plan 04-05 deploys. |

## User Setup Required

None for this plan. The Firestore rules and composite index are unchanged, and no new credential or environment variable is involved. The merged-release-manifest permission audit that `file_picker` makes necessary is plan 04-05's task, as the pubspec comment records.

## Next Phase Readiness

**Ready for plan 02 (failure states and the skip list).** Every signal it needs to render is already thrown and typed, `ImportSkip` already carries the row number and both echoable values, and the sheet's else-if state chain is shaped to take four more branches. The scripted `FakeJsonFilePicker`/`FakeQuestionBankWriter` doubles take failure outcomes today (any non-`String`/non-`Set<String>` script entry is thrown), so plan 02 needs no new test scaffolding.

**Ready for plan 04-05 (seed import).** The multi-chunk write path exists and is unexercised — a ~600-row seed is the first thing that crosses `kMaxWritesPerBatch`, which is exactly the proof the writer's own doc comment says it is waiting for.

**Two things plan 04-05 must verify on-device and nothing here can:** whether `file_picker` widens the merged release manifest beyond `RECORD_AUDIO` + `INTERNET` + `ACCESS_NETWORK_STATE`, and whether the plugin returns bytes or a path on Android and iOS (the adapter handles both and logs which branch ran).

**One thing plan 04-03 should know:** `kLevels` is now imported from `lib/services/firestore_question_source.dart`. Anything that adds a level-aware surface reads it from there.

---
*Phase: 04-bulk-import-seed-content-screen-polish*
*Completed: 2026-08-10*
