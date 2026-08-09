# Phase 4: Bulk Import, Seed Content & Screen Polish — Pattern Map

**Mapped:** 2026-08-09
**Files analyzed:** 14 (6 new Dart, 3 modified Dart, 4 new/modified test, 1 seed data)
**Analogs found:** 13 / 14
**Upstream:** `04-CONTEXT.md` (D-48..D-63) + `04-UI-SPEC.md`. No RESEARCH.md — deliberate.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/services/question_importer.dart` (NEW) — pure parse/normalize/validate/dedupe | utility (pure) | transform | `lib/services/firestore_question_source.dart` free functions (`sanitizedText` L101-105, `normalizeSubjects` L127-136) | **exact** |
| `lib/services/question_bank_writer.dart` (NEW) — the Firestore write seam | service (seam + adapter) | batch write | `lib/services/firestore_question_source.dart` (`FirestoreQuestionSource` L157-299) + `lib/services/screen_wake_controller.dart` (seam shape) | **exact** |
| `lib/services/json_file_picker.dart` (NEW) — the file-picker seam | service (seam + adapter) | file-I/O | `lib/services/screen_wake_controller.dart` (L27-51) | **exact** |
| `lib/screens/import_sheet.dart` (NEW) — the 8-state modal sheet | component (stateful widget) | request-response | `lib/screens/setup_screen.dart` `_TopicsCard`/`_TopicsLoading`/`_TopicsError`/`_NoTopics` (L619-991) + `_StartFooter._helper` (L1034-1069) | **exact** |
| `lib/screens/import_strings.dart` or top of `import_sheet.dart` (NEW) — the string inventory | config (constants + pure fns) | — | `lib/screens/setup_screen.dart` L28-102 (`kTopicsErrorMessage`, `kQuestionLoadErrorMessage`, `noQuestionsMessage`) | **exact** |
| `lib/screens/setup_screen.dart` (MODIFIED) — AppBar action, sheet-dismiss refresh, B5 helper, `kTooManyTopicsMessage` | screen | request-response | itself — `_openHistory()` L324-332, `actions:` L473-479, `_helper` L1034-1069 | **exact (self)** |
| `lib/services/firestore_question_source.dart` (MODIFIED) — `kMaxTopicsPerQuery` doc correction (D-61); likely a new `TooManyTopicsException` | service | — | itself — `QuestionBankUnavailableException` L36-41 | **exact (self)** |
| `lib/data/questions.dart` (MODIFIED, optional) — if the write seam joins `QuestionSource` | model/contract | — | itself L38-55 | **exact (self)** |
| `test/services/question_importer_test.dart` (NEW) | test (pure unit) | transform | `test/services/firestore_question_source_test.dart` (whole file, 70 lines) | **exact** |
| `test/screens/import_sheet_test.dart` (NEW) | test (widget) | request-response | `test/screens/setup_screen_test.dart` `FakeQuestionSource` L23-90+ | **exact** |
| `test/fixtures/import_files.dart` (NEW) — malformed rows retired from the D-58 dev seed | test fixture | — | `test/fixtures/questions.dart` (whole file, 90 lines) | **exact** |
| `test/screens/setup_screen_test.dart` (MODIFIED) — import action, B5 helper, refresh-on-dismiss | test (widget) | — | itself | **exact (self)** |
| `assets/seed/*.json` or `seed/*.json` (NEW) — ~600-row seed, D-59 | data/config | file-I/O | `tool/seed_questions.mjs` `buildDocuments()` L240-264 (matrix + strictly-increasing `Timestamp`) | **partial** (JS prior art, being deleted) |
| `pubspec.yaml` (MODIFIED) — `file_picker: ^11.0.3` | config | — | its own `firebase_core`/`cloud_firestore` block (L46-58) — comment-why-this-dep convention | **exact (self)** |

Docs also changed, no code analog needed: `docs/QUESTION_GENERATION_PROMPT.md`, `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, deletion of `tool/`.

---

## Pattern Assignments

### `lib/services/question_importer.dart` (utility, transform)

**Analog:** `lib/services/firestore_question_source.dart` — its two free functions are the exact precedent for "the one piece of judgement in the file, extracted so it is host-testable while the adapter around it is not" (D-47).

**Reuse, do not re-write** (`firestore_question_source.dart` L101-105) — D-53's normalization is this rule:

```dart
String? sanitizedText(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}
```

`content` and `subject` validation = `sanitizedText(raw) == null` → skip. `level` = `sanitizedText(raw)?.toUpperCase()` then membership in `kLevels` (`setup_screen.dart` L26). Import `kLevels` rather than re-listing A1–C2.

**Doc-comment pattern to copy** (`firestore_question_source.dart` L107-127) — a bulleted list where each bullet names the rejected alternative and the harm it would have caused:

```dart
/// Turns the raw `subject` values of every document in the bank into the topic
/// checkbox list (BANK-02).
///
///  * **Blank and non-`String` values are dropped**, so a malformed document
///    contributes no checkbox rather than an unlabelled one.
///  * **De-duplication is by EXACT string equality**, so `'Travel'` and
///    `'travel '` stay two distinct topics. Case-folding or trimming here would
///    merge them for the checkbox list while the server-side `whereIn` query
///    still treats them as different values — the user would tick one topic and
///    get questions from neither.
```

D-53's own doc comment must say the mirror of that last bullet: trimming on **write** is safe precisely because it stops the two values from coexisting, which is why the read side deliberately does not.

**Signature shape mandated by CONTEXT ("Claude's Discretion", last bullet):** pure function of `(decoded JSON, existing bank) → (rows to write, skip report)`. No `FirebaseFirestore`, no `File`, no `BuildContext` in this file — that is what makes it the analog of `sanitizedText`/`normalizeSubjects` rather than of `FirestoreQuestionSource`.

**Loud-edge pattern** (`firestore_question_source.dart` L218-228) — the precedent for D-52/D-55 "nothing is dropped without being named":

```dart
if (config.topics.length > kMaxTopicsPerQuery) {
  debugPrint(
    'Question bank query refused: ${config.topics.length} topics selected, '
    'but Firestore allows at most $kMaxTopicsPerQuery values in a `whereIn` '
    'clause. Failing loudly rather than dropping topics to fit (BANK-03).',
  );
  throw const QuestionBankUnavailableException();
}
```

---

### `lib/services/question_bank_writer.dart` (service, batch write)

**Analog:** `lib/services/firestore_question_source.dart` for the adapter + exception + containment; `lib/services/screen_wake_controller.dart` for the seam shape.

**Seam shape** (`screen_wake_controller.dart` L27-51) — abstract contract with no package type, one named production impl, `const` constructor:

```dart
abstract class ScreenWakeController {
  Future<void> enable();
  Future<void> disable();
}

class WakelockPlusScreenWakeController implements ScreenWakeController {
  const WakelockPlusScreenWakeController();

  @override
  Future<void> enable() => WakelockPlus.enable();
}
```

**Signal-exception pattern** (`firestore_question_source.dart` L25-41) — copy verbatim for the import's own failures (D-60 unreachable, D-62 file problems, S8 partial write). Note the `toString()` is developer-facing and the doc comment says so:

```dart
/// Thrown when the question bank could not be READ, as opposed to being empty.
/// ...
/// This is a *signal*, not a crash: `SetupScreen` catches it and shows the
/// pre-approved user-facing copy. Its own text is developer-facing only and is
/// never rendered to the user — structurally identical to
/// `RecordingPermissionDeniedException`.
class QuestionBankUnavailableException implements Exception {
  const QuestionBankUnavailableException();

  @override
  String toString() => 'QuestionBankUnavailableException';
}
```

The partial-write case (S8) needs a **payload-carrying** exception (`done`, `total`) so `importPartialMessage(done, total)` can be built — the one place this phase departs from the `const`-no-fields shape. Keep the payload numeric only; no exception text, no document ID.

**Error containment** (`firestore_question_source.dart` L274-294) — the `_read` wrapper is the exact model for a `_commit` wrapper. Copy the "both paths go through here, deliberately" reasoning and the log-then-rethrow:

```dart
try {
  snapshot = await query.get();
} on FirebaseException catch (error, stack) {
  debugPrint('Question bank read failed: $error');
  debugPrintStack(stackTrace: stack);
  throw const QuestionBankUnavailableException();
}
```

**D-60's server-only read** is the write-side mirror of this same method's cache rule (L286-292). The existing code already proves the codebase's stance that a cache-served zero result is unreachable-not-empty; the importer's dedupe read must go one step further and request `Source.server` explicitly. **Open question 3 in CONTEXT is unresolved and must be verified against installed `cloud_firestore 6.8.0` at plan time** — no existing call site in this repo passes `GetOptions`.

**D-63 `created_at` precedent** — `tool/seed_questions.mjs` L254-263, the only existing writer. Copy the strictly-increasing scheme (1 s step, ascending in row order), and reproduce its L334-336 comment about why order is checkable:

```javascript
const stepMs = 1000;
const baseMs = Date.now() - rows.length * stepMs;
// Exactly {content?, subject, level, created_at} — nothing else, no `id`.
data: { ...fields, created_at: Timestamp.fromMillis(baseMs + i * stepMs) },
```

Read `kQuestionsCollection` and `kCreatedAtField` from `firestore_question_source.dart` (L12, L23) — its own doc comment names this phase's importer and instructs it not to repeat the string.

---

### `lib/services/json_file_picker.dart` (service, file-I/O)

**Analog:** `lib/services/screen_wake_controller.dart` — same excerpt as above.

`file_picker` reaches a method channel exactly as `wakelock_plus` does, so an unmediated call raises `MissingPluginException` under `flutter test`. **No `FilePickerResult` may cross the seam** (CONTEXT "Established patterns"); the contract returns `Future<String?>` (JSON text) or a small owned record, and `null` means the user cancelled — which the UI-SPEC says gets no copy at all. The `dart:io` read belongs behind this seam too, so an unreadable-file `IOException` becomes the seam's own exception rather than reaching `import_sheet.dart`.

**Lazy resolution at the call site** (`setup_screen.dart` L120-125 doc + `late final` fields around L154-195, and `firestore_question_source.dart` L158-159):

```dart
FirestoreQuestionSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
```

The screen-level form is `late final X _x = widget.x ?? RealX();` — a test injecting a fake must never construct the real one.

---

### `lib/screens/import_sheet.dart` (component, request-response)

**Analog:** `lib/screens/setup_screen.dart`'s private state widgets (L619-991) for the state-per-widget + `Key` discipline; `lib/screens/practice_screen.dart` for `PopScope` and modal presentation.

**Mutually-exclusive-state-by-else-if-chain** (`setup_screen.dart` L1034-1069) — the exact model for the sheet's eight states and for the new B5 helper. Note the reasoning: *keys mutually exclusive by construction rather than by conditions kept disjoint by hand*:

```dart
Widget? _helper(ThemeData theme) {
  if (showBlockedHelper) {
    return Text(
      'Pick at least one topic to start.',
      key: const Key('setup-start-blocked'),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge,
    );
  }
  if (message == null) return null;
  if (!messageIsFailure) {
    return Text(message!, key: const Key('setup-start-no-questions'), ...);
  }
  return Row(
    key: const Key('setup-start-error'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.error_outline_rounded, size: 24, color: theme.colorScheme.error),
      const SizedBox(width: 8), // sm
      Expanded(child: Text(message!, style: theme.textTheme.bodyLarge)),
    ],
  );
}
```

This is also the red-icon/brown-text pairing the UI-SPEC requires for S5/S7/S8 — reuse `Icons.error_outline_rounded` and `theme.colorScheme.error` **for the icon only**, never for text.

**Spacing-comment convention:** every magic number carries its token name inline (`const SizedBox(height: 8), // sm`, `horizontal: 24, // lg`). Follow it in the sheet.

**`PopScope` for S3-writing** (`practice_screen.dart` L280-289) — the pinned-version-correct API, already used for the Stop dialog:

```dart
return PopScope<void>(
  canPop: isComplete,
  // The CURRENT API. `onPopInvoked` is deprecated and `PopScope`
  onPopInvokedWithResult: ...
```

Use `canPop: !isWriting`. The UI-SPEC's backstop (drag/barrier may bypass `PopScope`) must be verified on-device; the sanctioned fallback is `isDismissible: false, enableDrag: false`.

**Busy state with a caption + semantic label** (`setup_screen.dart` L1125-1142) — every busy state in this app is captioned, never a bare spinner:

```dart
? Semantics(
    label: 'Starting session',
    child: SizedBox(
      width: 24, // lg
      height: 24,
      child: CircularProgressIndicator(
        key: const Key('setup-start-busy'),
        strokeWidth: 3,
        color: theme.colorScheme.onPrimary,
      ),
    ),
  )
```

**Double-action prevention by `onPressed: null`, not a swallowed tap** (`setup_screen.dart` L1116-1123) — the D-19 precedent the UI-SPEC cites for every in-sheet button.

**Async-after-await guard** (`setup_screen.dart` L258-261) — mandatory in every sheet handler:

```dart
// `setState` after an `await` needs this guard: the read outlives the screen
// whenever the user leaves Setup before it lands, and calling `setState` on
// a disposed `State` throws.
if (!mounted) return;
```

---

### `lib/screens/setup_screen.dart` (MODIFIED — screen)

**Analog:** itself. Three concrete edits.

**1. AppBar action** — prepend to the existing list (L473-479). Import first, History second, so History does not move:

```dart
actions: [
  IconButton(
    icon: const Icon(Icons.history),
    tooltip: 'Exercise History',
    onPressed: () => unawaited(_openHistory()),
  ),
],
```

The new one takes `key: const Key('setup-import')`, `Icons.upload_file`, tooltip `'Import questions'`. Also add `overflow: TextOverflow.ellipsis, maxLines: 1` to the title `Text` at L472 (UI-SPEC AppBar title risk).

**2. Sheet-dismiss refresh** — copy `_openHistory()` (L324-332) exactly, substituting `showModalBottomSheet` for the push:

```dart
Future<void> _openHistory() async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HistoryScreen(databaseHelper: _databaseHelper),
    ),
  );
  if (!mounted) return;
  await _refreshSubjectsOnReappear();
}
```

The new `_openImportSheet()` awaits the sheet, guards `mounted`, calls `_refreshSubjectsOnReappear()`, and per the UI-SPEC's interaction-race row also calls `_clearStartMessage()` inside a `setState` (L355-358).

**`_refreshSubjectsOnReappear()`'s doc comment at L289-301 is now WRONG and must be corrected in this phase.** It currently reads *"Phase 4's importer lands the user back here too, and will need no extra wiring to make its new topics appear."* True for a pushed route, false for a modal sheet — D-51 exists because of this.

**3. B5 helper + `kTooManyTopicsMessage`** — a new constant beside `kTopicsErrorMessage` (L28-49) and `kQuestionLoadErrorMessage` (L51-67). Copy their doc-comment structure verbatim: *why this is a sibling and not the same string*, and *what containment rule it obeys*. The B5 branch needs a third flag or a small enum in `_StartFooter` — today `_startMessageIsFailure` is a bool chosen so the two helpers are "mutually exclusive by construction" (L196-207); a third state must preserve that property, not add a second bool that can be true at the same time.

`_startSession()` (L366-455) is where B5 fires: the `kMaxTopicsPerQuery` guard currently throws `QuestionBankUnavailableException`, which is indistinguishable from a network failure at L397. **Introducing a distinct exception type in `firestore_question_source.dart` is what lets the `catch` at L397-406 route it to B5 instead of `kQuestionLoadErrorMessage`.**

---

### `test/services/question_importer_test.dart` (test, pure unit)

**Analog:** `test/services/firestore_question_source_test.dart` (whole file, 70 lines) — the closest match in the repo, and its header is already about this phase.

**Header pattern** — states what is deliberately NOT tested and why (D-47), and names the alternative tools rejected:

```dart
/// Covers the ONE pure helper `FirestoreQuestionSource` exposes, and nothing
/// else in that file — deliberately.
///
/// The adapter itself is not host-testable and is not meant to be (D-47): ...
/// both `fake_cloud_firestore` and the Firestore emulator were rejected — the
/// fake does not model index requirements, so a passing test would not prove
/// the real query runs ...
```

**Case naming and inline rationale** — note the existing test already anticipates this phase (L43-51):

```dart
test('a non-String value is not usable, whatever it is', () {
  // Firestore documents are user-authored and Phase 4 will let a JSON
  // import write anything at all into these fields.
  expect(sanitizedText(42), isNull);
  expect(sanitizedText(<String, Object?>{'text': 'nested'}), isNull);
});
```

**Pin-the-constant pattern** (L60-69) — `expect(kMaxTopicsPerQuery, 30)` with a comment on why drift must force a deliberate decision. Apply the same to Firestore's `writeBatch` 500-op cap once confirmed (CONTEXT open question 1).

---

### `test/fixtures/import_files.dart` (test fixture)

**Analog:** `test/fixtures/questions.dart` (whole file).

Copy its header rules verbatim in spirit: *nothing in `lib/` may import this file*; the `kFixture` prefix marks scaffolding; ordering is load-bearing where assertions depend on it. **D-58's two deliberately malformed documents (one with no `content`, one whose `content` is whitespace) reappear here as fixture rows** — that migration is explicitly named in CONTEXT's "Established patterns".

```dart
/// **These are fixtures, not a bank.** Nothing in `lib/` may import this file —
/// the app has exactly one question source and it is Firestore. The `kFixture`
/// prefix is what makes a reader of any test body able to tell at a glance that
/// the data is scaffolding rather than something the app ships.
```

---

### `test/screens/import_sheet_test.dart` (test, widget)

**Analog:** `test/screens/setup_screen_test.dart` L23-90 — `FakeQuestionSource` is the template for a `FakeJsonFilePicker` and a `FakeQuestionBankWriter`.

**One scripted fake, not four classes:**

```dart
/// **One class, not four.** Each read takes a list of per-call outcomes and the
/// rule for reading them is a single sentence: *a `List<String>` is returned, an
/// empty one being a server-confirmed empty read; anything else is thrown.* The
/// last entry repeats once the script runs out, so a test that only cares about
/// the first outcome writes one entry.

static List<String> _resolve(List<Object> script, int callIndex) {
  final outcome =
      script[callIndex < script.length ? callIndex : script.length - 1];
  if (outcome is List<String>) return outcome;
  throw outcome;
}
```

**Synchronous completion + a Completer gate** (L30-42) — load-bearing under the fake clock, and the only way S2/S3 in-flight frames become assertable:

```dart
/// **Every method completes synchronously by default** (`async` with no real
/// `await`) ... a `Future.delayed` here would never resolve and every test in
/// this file would hang.
///
/// **[holdSubjects] / [holdQuestions] are the one exception** ... A held call
/// parks on a [Completer] the test releases by hand, which stays inside the
/// microtask queue the fake clock does drain.
```

The writer fake needs the same `holdWrite` gate so S3-writing and its blocked `PopScope` are testable, plus a `callCount` (L58-62 precedent) to prove the dedupe read happened exactly once.

---

### `pubspec.yaml` (MODIFIED)

**Analog:** its own Firebase block (L46-58). The convention is a multi-line comment naming *why the dependency is here and what it costs*, including permission consequences:

```yaml
  # The question bank (BANK-01..03). ...
  # These are the reason the release build now requests network access. The
  # `INTERNET` permission is contributed TRANSITIVELY by cloud_firestore, not
  # declared in android/app/src/main/AndroidManifest.xml — see that file's
  # permission comment, and D-39 for why the Phase 1/2 microphone-only posture is
  # formally retired here rather than left to rot.
  firebase_core: ^4.13.0
  cloud_firestore: ^6.8.0
```

`file_picker: ^11.0.3` gets the same treatment, and the merged-release-manifest permission check (CONTEXT's `AndroidManifest.xml` bullet) is what the comment must record.

---

## Shared Patterns

### Injectable constructor seam, resolved lazily
**Source:** `lib/services/screen_wake_controller.dart` L27-51 (canonical shape); `lib/services/firestore_question_source.dart` L157-161 (with a package default).
**Apply to:** `json_file_picker.dart`, `question_bank_writer.dart`, and both new `SetupScreen`/`ImportSheet` constructor parameters.
Doc comment must say why the seam exists (method channel under `flutter test`), and why any package-provided test override was rejected — `screen_wake_controller.dart` L9-20 is the model, including its rejection of `wakelock_plus`'s own `@visibleForTesting` static global as "a different shape from every other platform dependency in this codebase".

### No vendor type crosses a seam
**Source:** `lib/services/firestore_question_source.dart` L152-156.
**Apply to:** every new file under `lib/screens/`.
```dart
/// **No Firestore type crosses this seam.** No `QuerySnapshot`, no
/// `DocumentSnapshot`, no `FirebaseException` — only `List<String>` out and
/// [QuestionBankUnavailableException].
```
Extend the list: no `FilePickerResult`, no `WriteBatch`, no `Timestamp`, no `FileSystemException`.

### Failure detail goes to the console and nowhere else
**Source:** `lib/screens/setup_screen.dart` L263-274.
**Apply to:** every catch in the importer and the sheet.
```dart
// Exception detail goes to the console and NOWHERE else — no exception
// text, no Firestore error code, no collection name, no document ID and
// no project ID may reach the screen.
debugPrint('Subjects read failed: $failure');
```
Paired with the two-arm catch at L242-256: the seam's own signal exception first, then a bare `catch (error, stack)` with `debugPrintStack` for "a source misbehaving", landing on the *same* honest state.

### One fixed user-facing string per failure, siblings never merged
**Source:** `lib/screens/setup_screen.dart` L28-67.
**Apply to:** the whole 24-row string inventory in `04-UI-SPEC.md`.
The rule the existing comment states: two failures with two different retry affordances earn two strings, because *"a failure message that does not name its own next action is half a message."* This is directly why S5 splits `kImportUnreadableFileMessage` from `kImportBadShapeMessage`, and why S7's "Try again" is a `FilledButton` where the topics card's is a `TextButton`.

### Copy as a pure, host-testable function with a length bound
**Source:** `lib/screens/setup_screen.dart` L69-102 (`noQuestionsMessage`).
**Apply to:** `importAddedLine`, `importDuplicatesLine`, `importSkippedLine`, `importSavingMessage`, `importSkipReason`, `importPartialMessage`.
```dart
/// A pure function, so all three branches are unit-testable on the host with no
/// widget. Zero topics is unreachable — SETUP-07 gates Start on at least one —
/// and falls into the count branch rather than earning a fourth string for a
/// state the button makes impossible.
String noQuestionsMessage(String level, List<String> topics) {
  if (topics.length == 1) { ... }
  if (topics.length == 2) { ... }
  return 'No $level questions in any of your ${topics.length} topics yet. ...';
}
```
Note the third branch exists as a **length bound** on an unbounded input — the same reasoning that caps the echoed `level` value at 12 chars in `importSkipReason` (UI-SPEC Untrusted Input).

### Theme-only colour and type
**Source:** `lib/screens/setup_screen.dart` L459, L1040, L1056-1059.
**Apply to:** every widget in `import_sheet.dart`.
`final theme = Theme.of(context);` at the top of `build`, then `theme.textTheme.bodyLarge` / `labelLarge` / `headlineSmall` and `theme.colorScheme.error` / `.primary` / `.onPrimary` / `.surface`. No hex literal, no `textScaler` override. `test/theme/typography_test.dart` is the existing guard.

### Doc comments record the rejected alternative with its D-nn tag
**Source:** `lib/services/firestore_question_source.dart` L71-84; `lib/data/questions.dart` L1-17; `lib/screens/setup_screen.dart` L104-125.
**Apply to:** every new file.
The house form is: *what was considered, why it was discarded, and the reversal trigger.* `kMaxTopicsPerQuery`'s comment (L71-83) is the exemplar — and is also the one comment this phase must **edit**, since D-61 retires its claim that the branch is unreachable.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| the `writeBatch` chunking + partial-commit path inside `question_bank_writer.dart` | service | batch write | **No existing Dart code in this repo writes to Firestore at all.** The only prior art is `tool/seed_questions.mjs` L333-339, which deliberately writes serially with `addDoc` (*"a serial write makes the order that lands the order printed above"*) and is being deleted. The 500-op cap, the chunk-2-fails-after-chunk-1 path (S8) and the server-only `GetOptions` source are all CONTEXT open questions 1 and 3 — the planner must establish them against installed `cloud_firestore 6.8.0` rather than copy a pattern. |
| the `~600-row seed JSON` content | data | — | Content authoring, not a code pattern. Topic strings must match `docs/QUESTION_GENERATION_PROMPT.md` exactly, string for string (D-59). `tool/seed_questions.mjs` L240-292 (`buildDocuments` / `printMatrix`) is the only matrix-shape precedent and should be read before it is deleted. |

---

## Metadata

**Analog search scope:** `lib/**`, `test/**`, `tool/**`, `pubspec.yaml`
**Files scanned:** 42 Dart files (12,224 lines) + `tool/seed_questions.mjs` + `pubspec.yaml`
**Files read in full or in targeted ranges:** `lib/services/firestore_question_source.dart`, `lib/data/questions.dart`, `lib/services/screen_wake_controller.dart`, `test/fixtures/questions.dart`, `test/services/firestore_question_source_test.dart`, `lib/screens/setup_screen.dart` (L1-130, L195-500, L993-1150), `test/screens/setup_screen_test.dart` (L1-90), `tool/seed_questions.mjs` (L250-369)
**Pattern extraction date:** 2026-08-09
