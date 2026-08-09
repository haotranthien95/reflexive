# Phase 3: Real Question Bank via Firestore - Pattern Map

**Mapped:** 2026-08-09
**Files analyzed:** 13 (4 new source, 5 modified source, 2 new test/modified test groups, 2 config/infra)
**Analogs found:** 11 / 13

Derived from `03-CONTEXT.md` (D-32..D-47) and `03-UI-SPEC.md`. No RESEARCH.md exists — every pattern
below is taken from real code already in `lib/` and `test/`, which is the stronger source anyway.

---

## File Classification

| New/Modified File | New? | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|------|-----------|----------------|---------------|
| `lib/data/questions.dart` | modified | model/seam definition | request-response (async) | itself + `lib/services/recording_service.dart:35-72` (`RecorderBackend`) | exact (seam shape) |
| `lib/services/firestore_question_source.dart` (name at planner's discretion) | **new** | service (thin platform adapter) | request-response / CRUD-read | `lib/services/screen_wake_controller.dart:27-51` | exact |
| `lib/screens/setup_screen.dart` | modified | screen (stateful form + async list) | request-response + async list load | `lib/screens/history_screen.dart:37-137` (loading/error/empty triad) | exact |
| `lib/state/practice_state.dart` | modified | state (ChangeNotifier engine) | event-driven | itself (`:82-99`, `:535`) | n/a — surgical edit |
| `lib/screens/practice_screen.dart` | modified | screen | event-driven | itself (`:30-48` constructor contract) | n/a — surgical edit |
| `lib/main.dart` | modified | config/bootstrap | one-shot init | `configureFonts()` at `lib/main.dart:26-39` | exact |
| `lib/firebase_options.dart` | **new (generated)** | config | n/a | none — `flutterfire configure` output, never hand-edited | **no analog** |
| `firestore.rules` | **new** | config (infra) | n/a | none in repo | **no analog** |
| `tool/seed_questions.dart` | **new** | utility (throwaway dev script) | batch write | none in repo (no `tool/` dir yet) | **no analog** |
| `pubspec.yaml` | modified | config | n/a | existing `wakelock_plus` / `google_fonts` entries + their comment convention | exact |
| `android/app/src/main/AndroidManifest.xml` | modified | config | n/a | its own existing permission comment block (lines 2-5) | exact |
| `test/screens/setup_screen_test.dart` | modified | test (widget) | request-response | `test/screens/history_screen_test.dart:7-46` (Throwing/Fake helper pair) | exact |
| `test/data/questions_test.dart` or `test/screens/setup_copy_test.dart` | **new** | test (unit) | pure function | `test/utils/audio_paths_test.dart` style pure-function test | role-match |

---

## Pattern Assignments

### `lib/services/firestore_question_source.dart` (service, thin platform adapter)

**Analog:** `lib/services/screen_wake_controller.dart` — this is the codebase's canonical
"abstract contract + private/named production impl + injected instance resolved lazily" seam, and its
doc comment explicitly calls itself "the third seam of the ESTABLISHED shape". The Firestore source is
the fourth. D-47 says host-testability stops at the seam, exactly as it does here.

**Seam shape to copy** (`screen_wake_controller.dart:27-51`):

```dart
abstract class ScreenWakeController {
  /// Keeps the screen on. Idempotent — ...
  Future<void> enable();
  Future<void> disable();
}

/// The production implementation: `package:wakelock_plus`.
class WakelockPlusScreenWakeController implements ScreenWakeController {
  const WakelockPlusScreenWakeController();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}
```

Applied here: the abstract `QuestionSource` (async, in `lib/data/questions.dart`) is the contract;
`FirestoreQuestionSource` is the production impl in `lib/services/`; the screen holds
`widget.questionSource ?? FirestoreQuestionSource()` behind `late final` so a test never constructs
a Firestore instance (see the lazy-resolution pattern below).

**Typed-exception pattern to copy** (`lib/services/recording_service.dart:23-28`) — the UI-SPEC
requires the cache-vs-server distinction to be surfaced as a *throw*, not an empty list, so the seam
needs its own exception type in exactly this shape:

```dart
/// Thrown by [RecordingService.start] when the OS has not granted microphone
/// access, instead of letting the plugin fail somewhere deeper.
///
/// This is a *signal*, not a crash: ... The exception's own text is
/// developer-facing only and is never rendered to the user (T-03-02).
class RecordingPermissionDeniedException implements Exception {
  const RecordingPermissionDeniedException();

  @override
  String toString() => 'RecordingPermissionDeniedException';
}
```

Copy verbatim in structure for a `QuestionBankUnavailableException` (or equivalent): `implements
Exception`, `const` ctor, a `toString()` that is developer-facing only, and a doc comment that says
the message never reaches the screen.

**Package-type containment rule to copy** (`recording_service.dart:59-66`, the `onPausedChanged` doc):
the seam is "kept as a `bool` stream rather than the plugin's own state enum so this seam stays free
of package types and every test can drive it with a plain `StreamController<bool>`." Same rule here:
no `QuerySnapshot`, no `DocumentSnapshot`, no `FirebaseException` crosses the seam — only
`List<String>` out and the local exception type.

---

### `lib/data/questions.dart` (seam definition — signature change, D-34)

**Analog:** itself. The existing declaration is already the target shape minus `Future`:

```dart
/// The seam Phase 3 swaps for Firestore.
abstract class QuestionSource {
  /// The prompts available for [config]'s topics and level, in bank order.
  List<String> questionsFor(SessionConfig config);
}
```

Becomes `Future<List<String>> questionsFor(SessionConfig config);`, plus whatever subjects-read
method the planner chooses (D-92 discretion). `PlaceholderQuestionSource` and `kSubjects` are deleted;
`kQuestions` goes with them unless a fake still needs it (D-36 ruled out a fallback bank — prefer
deleting, and let `test/` own its own fixture prompts).

**Keep verbatim** (`lib/data/questions.dart:96`) — D-42 depends on this being untouched:

```dart
String questionAt(List<String> bank, int index) => bank[index % bank.length];
```

**Doc-comment convention this file already models:** every constant and every class carries a comment
explaining *why the alternative was rejected*, not what the code does. New code in this phase must
match that density — see lines 85-95 for the tone.

---

### `lib/screens/setup_screen.dart` (screen, async list load + form)

**Analog A — the loading / error / empty triad:** `lib/screens/history_screen.dart:37-137`. This is
the app's existing "a read failure is never presented as missing data" implementation and the topics
card's A1/A3/A4 states are the same three branches on a different surface.

**Single-query-site pattern** (`history_screen.dart:38-50`):

```dart
late Future<List<Session>> _sessionsFuture;

@override
void initState() {
  super.initState();
  _load();
}

/// The one place the query is issued — used by [initState] and by retry, so
/// the two can never drift apart.
void _load() {
  _sessionsFuture = widget.databaseHelper.listSessions();
}
```

**Branch-ordering rule — load-bearing, copy the comment too** (`history_screen.dart:63-78`):

```dart
if (snapshot.connectionState != ConnectionState.done) {
  return const Center(child: CircularProgressIndicator());
}
// MUST come before the `snapshot.data` read: on error `data` is null,
// so falling through would coerce a failed read into an empty list
// and render it as "No recordings yet" (T-06-01).
if (snapshot.hasError) {
  return _HistoryError(onRetry: () => setState(_load));
}
final sessions = snapshot.data ?? const <Session>[];
if (sessions.isEmpty) {
  return const _EmptyHistory();
}
```

> **Deliberate divergence the planner must handle:** the UI-SPEC's background refresh (D-35,
> stale-while-revalidate: keep last-known topics on a failed re-read, no spinner) cannot be expressed
> by a bare `FutureBuilder` swap, which flips to loading/error on every new future. Setup should
> therefore hold explicit `List<String>? _subjects` + `bool _topicsLoading` + `bool _topicsError`
> fields set from an `async` method, rather than copying `FutureBuilder` wholesale. Keep the
> **branch order** and the **`_load()` single-site** discipline; drop the `FutureBuilder`.

**Analog B — the A4 error body:** `_HistoryError` (`history_screen.dart:145-188`). The UI-SPEC says
A4 is "constructed identically to `_HistoryError`" with exactly one deviation (brown text, not red):

```dart
return Center(
  key: const Key('history-error'),
  child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          kHistoryErrorMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.error),   // <-- DROP the copyWith for the new state
        ),
        const SizedBox(height: 16),
        TextButton(
          key: const Key('history-error-retry'),
          onPressed: onRetry,
          style: TextButton.styleFrom(
            // Touch-target floor, not part of the 4px content scale.
            minimumSize: const Size(64, 48),
          ),
          child: const Text('Try again'),
        ),
      ],
    ),
  ),
);
```

For `_TopicsError`: identical geometry, `key: const Key('setup-topics-error')`, retry key
`setup-topics-error-retry`, and `style: theme.textTheme.bodyLarge` **without** the error-colour
`copyWith` (UI-SPEC Color section: red icon, brown words).

**Analog C — the error-message constant convention** (`history_screen.dart:8-21`):

```dart
/// The single user-facing message for a failed read of saved history.
///
/// Written to the same rules as `kRecordingErrorMessage`: name the likely cause
/// and the next action, blame nothing on the user, and leak no exception text,
/// file path or SQL detail (T-06-04).
const String kHistoryErrorMessage =
    "Couldn't open your recordings — they're still saved on this device. "
    'Try again.';
```

`kTopicsErrorMessage` and `kQuestionLoadErrorMessage` are top-level `const String` in
`setup_screen.dart` (same file as their use, same as History), each with a doc comment naming *why
there are two* — the UI-SPEC's two-retry-affordances rationale.

**Analog D — the private state widgets:** `_TopicsCard`, `_NoTopics`, `_StartFooter` already exist in
this file (lines 267-568). All new state widgets are private `StatelessWidget`s in the same file, with
a `const` ctor, a `final theme = Theme.of(context);` first line, a doc comment stating the design
rationale, and a `const Key(...)` at the root. `_NoTopics` (`:488-512`) must **not** be rewritten —
the UI-SPEC says it is unchanged code that merely becomes reachable.

**Analog E — the optional-injected-service constructor seam** (`setup_screen.dart:49-83`):

```dart
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    this.databaseHelper,
    this.recordingService,
    this.audioPlayerService,
    this.subjects,
  });

  final DatabaseHelper? databaseHelper;
  ...
  /// Overrides [kSubjects]. Exists for the held-out empty-topic-list test: ...
  final List<String>? subjects;
}

class _SetupScreenState extends State<SetupScreen> {
  late final DatabaseHelper _databaseHelper =
      widget.databaseHelper ?? DatabaseHelper();
```

The static `subjects` override is **replaced** by `final QuestionSource? questionSource;` +
`late final QuestionSource _questionSource = widget.questionSource ?? FirestoreQuestionSource();`.
The `late final X _x = widget.x ?? RealX()` idiom is the lazy-resolution rule stated in
`practice_screen.dart:59-61` ("Resolved lazily, so a test that injects a fake never constructs the
platform channel") — apply it verbatim so `flutter test` never touches Firebase.

**Analog F — async work started from `initState`** (`setup_screen.dart:85-108`):

```dart
@override
void initState() {
  super.initState();
  unawaited(_sweepOrphanRecordings());
}

Future<void> _sweepOrphanRecordings() async {
  try {
    await pruneOrphanRecordings(
      await _databaseHelper.listReferencedAudioPaths(),
    );
  } catch (_) {
    // Cleanup is best-effort; never let it stand between the user and the
    // microphone.
  }
}
```

`_loadSubjects()` joins this line — `unawaited(_loadSubjects());` on the next line, neither awaiting
the other (UI-SPEC: "the orphan-sweep ordering contract is undisturbed"). Every `setState` after an
await needs a `if (!mounted) return;` guard, which this file does not yet demonstrate because nothing
currently sets state post-await — add it, and say why in a comment.

**Analog G — the Start handler and the footer gate** (`setup_screen.dart:128-155` and `:537-563`):

```dart
void _startSession() {
  final config = SessionConfig(
    topics: List<String>.unmodifiable(_subjects.where(_selectedTopics.contains)),
    level: _level,
    ...
  );
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PracticeScreen(config: config, ...)));
}
```

Becomes `Future<void> _startSession() async` — build the `config` snapshot **first and
synchronously** (this is exactly the "config snapshotted at tap time wins" race resolution the UI-SPEC
asks to be made an explicit test case; the existing code already builds it before any async work, so
the pattern is already right), then `setState(() => _starting = true)`, run the query, and branch.

The disabled-button style block is the exact place C3's busy override goes:

```dart
onPressed: canStart ? onStart : null,
style: FilledButton.styleFrom(
  backgroundColor: theme.colorScheme.primary,
  foregroundColor: theme.colorScheme.onPrimary,
  disabledBackgroundColor: theme.colorScheme.surface,
  disabledForegroundColor: theme.colorScheme.onSurface,
),
```

For C3 the two `disabled*` values flip to `primary`/`onPrimary` for that frame — same call, different
arguments, no new widget.

---

### `lib/state/practice_state.dart` + `lib/screens/practice_screen.dart` (surgical, D-34)

**Analog:** the file's own existing constructor-injection block (`practice_state.dart:82-99`):

```dart
class PracticeState extends ChangeNotifier {
  PracticeState({
    required this.recordingService,
    required this.audioPlayerService,
    required this.databaseHelper,
    required this.config,
  });
  ...
  /// The Phase 3 swap point. The loop asks this for prompts and never reads
  /// [kQuestions] itself.
  final QuestionSource questionSource = const PlaceholderQuestionSource();

  /// The prompt currently shown to the user.
  String currentQuestion = kQuestions.first;
```

Change: `questionSource` field deleted, `required this.questions` (a `List<String>`) added to the
same parameter block, `currentQuestion` initialised from `questions.first` (or `questionAt(questions,
0)`). `_pickQuestion()` (`:535-536`) loses one hop and stays synchronous — **do not make it async**;
its doc comment at `:528-534` explains why (reading and arming must get the same prompt).

`PracticeScreen` mirrors it: add `required final List<String> questions;` to the constructor at
`:30-48` and pass it through at `:80-86`. The constructor doc — "Takes its whole configuration as a
value (D-28)" — extends to cover the resolved bank.

---

### `lib/main.dart` (config/bootstrap)

**Analog:** `configureFonts()` and `main()` in the same file (`:26-39`):

```dart
void configureFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* { ... });
}

void main() {
  // Required before `configureFonts()` so `rootBundle` is usable.
  WidgetsFlutterBinding.ensureInitialized();
  configureFonts();
  runApp(const EnglishReflexApp());
}
```

`main()` becomes `Future<void> main() async` with
`await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);` added **after**
`ensureInitialized()` and **without displacing or reordering** `configureFonts()` (UI-SPEC, explicit).
The `allowRuntimeFetching = false` line and its ~20-line doc comment stay exactly as written — but the
comment now contains a claim that goes false this phase ("the release Android manifest deliberately
requests no network permission"). Rewrite that clause in the same voice; D-39 forbids leaving it to rot.

---

### `pubspec.yaml` and `AndroidManifest.xml` (config)

**Analog:** the existing `assets:` comment block in `pubspec.yaml` and the permission comment at
`android/app/src/main/AndroidManifest.xml:2-5`:

```xml
<!-- Required by package:record to capture spoken practice answers.
     Recordings are written to app-private storage only — no
     WRITE_EXTERNAL_STORAGE and no network permission are requested. -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

The trailing clause is now false. Rewrite in the same shape: state that `INTERNET` is contributed
transitively by `cloud_firestore` for the question-bank reads, that it is *not* declared here, and
that it is the only permission the Firebase dependencies add (verified against the merged release
manifest per D-39). Config files in this repo carry a *why*, not just a value — match that.

Gradle note for the planner: `android/settings.gradle.kts` uses the Kotlin-DSL `plugins { }` block
(`com.android.application` 9.0.1, Kotlin 2.3.20), so `flutterfire configure`'s Google Services plugin
wiring goes in as `id("com.google.gms.google-services") version "<x>" apply false` there plus
`id("com.google.gms.google-services")` in `android/app/build.gradle.kts` — the `.kts` form, not the
Groovy `apply plugin:` form most Firebase docs show.

---

### `test/screens/setup_screen_test.dart` (test, widget)

**Analog:** `test/screens/history_screen_test.dart:7-46` — the Throwing/Fake pair that D-47's four
states need, one class per behaviour:

```dart
/// A helper whose read always fails — stands in for an unreadable database.
///
/// The whole point of these tests: this must NOT look like "you have no
/// recordings". A read failure and an absence of data are different facts and
/// the user is entitled to be told which one happened.
class ThrowingDatabaseHelper extends DatabaseHelper {
  int callCount = 0;

  @override
  Future<List<Session>> listSessions() async {
    callCount++;
    throw StateError('database unreadable');
  }
}

/// A helper returning a caller-supplied list, optionally failing the first
/// call so the retry path can be driven end to end.
class FakeHistoryDatabaseHelper extends DatabaseHelper {
  FakeHistoryDatabaseHelper(this.sessions, {this.failFirstCall = false});
  final List<Session> sessions;
  final bool failFirstCall;
  int callCount = 0;
  ...
}
```

The `callCount` + `failFirstCall` combination is exactly what proves "Try again re-issues the query"
and what the D-35 background-refresh tests need. Build one `FakeQuestionSource` with
per-call scripted outcomes (subjects list / questions list / empty / throw) rather than four classes.

**Assertion style to copy** (`history_screen_test.dart:52-66`) — asserts the *absence* of the wrong
state's literal copy, which is the phase's sharpest correctness detail (empty vs unreachable):

```dart
expect(find.byKey(const Key('history-error')), findsOneWidget);
expect(find.byKey(const Key('history-empty')), findsNothing);
expect(find.text('No recordings yet'), findsNothing);
expect(find.text(kHistoryErrorMessage), findsOneWidget);
```

**Existing harness in `setup_screen_test.dart` to extend, not replace** (`:154-186`):

```dart
Widget host({List<String>? subjects}) => MaterialApp(
      theme: _testTheme(),
      home: SetupScreen(
        databaseHelper: _EmptyDatabaseHelper(),
        recordingService: RecordingService(backend: _SilentRecorderBackend()),
        audioPlayerService: AudioPlayerService(backend: _SilentPlaybackBackend()),
        subjects: subjects,
      ),
    );

Future<void> pumpSetup(WidgetTester tester, {List<String>? subjects,
    Size size = const Size(400, 2000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(subjects: subjects));
  await tester.pump();
}

bool startEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('setup-start'))).onPressed != null;
```

`subjects:` becomes `questionSource:` throughout. **Note the `await tester.pump()` (single frame)** —
every existing test now needs a settle or an extra pump because the topics arrive asynchronously;
`_EmptyDatabaseHelper`'s header comment (`:14-28`) explains why ffi futures never resolve under the
fake clock, so the `FakeQuestionSource` must complete synchronously (`async` with no real await), not
via `Future.delayed`.

---

### `tool/seed_questions.dart` (utility, batch write) — **no analog**

No `tool/` directory exists. Planner should follow D-45 verbatim and write the header comment in this
repo's voice: what it is, that it is disposable, and that Phase 4's importer supersedes it. Content
requirements are non-negotiable per D-45 + UI-SPEC note 6: multiple subjects × multiple levels, at
least one empty topic×level combination, one long subject name, one long prompt, one malformed doc.

---

## Shared Patterns

### The injectable-seam shape (applies to: `firestore_question_source.dart`, `questions.dart`, both screens, all tests)

**Source:** `lib/services/screen_wake_controller.dart:9-26` (the rationale) + `lib/screens/practice_screen.dart:59-61` (the call site)

```dart
/// Resolved lazily, so a test that injects a fake never constructs the
/// platform channel behind the production implementation.
late final ScreenWakeController _wake =
    widget.screenWakeController ?? const WakelockPlusScreenWakeController();
```

Three parts, always: abstract contract free of package types → named production impl → nullable
constructor param resolved with `late final … ?? Real()`. Never a static/global override.

### Error-copy discipline (applies to: `setup_screen.dart`, `firestore_question_source.dart`)

**Source:** `lib/screens/history_screen.dart:8-21` + `lib/services/recording_service.dart:20-22`

One top-level `const String` per user-facing failure, doc-commented with the rule it follows. Exception
detail goes to `debugPrint` / `FlutterError.reportError` only — never `snapshot.error` on screen, never
a Firestore error code, collection name, document ID or project ID (UI-SPEC voice rules).

### Theming (applies to every widget touched)

**Source:** `lib/main.dart:45-126`, used as `final theme = Theme.of(context);` at the top of every
`build` in `setup_screen.dart` and `history_screen.dart`.

Never a hex literal in a screen. Error red is `theme.colorScheme.error`, coral is
`theme.colorScheme.primary`, peach is `theme.colorScheme.surface`, brown is `theme.colorScheme.onSurface`
/ `onPrimary`. Text styles are `theme.textTheme.{bodyLarge,labelLarge,headlineSmall,displayLarge}` —
no fifth size, no ad-hoc `TextStyle`. `textScaler` is never pinned.

### Key + touch-target conventions (applies to all new Setup widgets)

**Source:** `lib/screens/setup_screen.dart:298-303`, `:546-548`; `lib/screens/history_screen.dart:176-180`

- `ConstrainedBox(constraints: const BoxConstraints(minHeight: 64))` for list rows, with the standing
  comment "Touch-target floor, not part of the 4px content scale."
- `TextButton.styleFrom(minimumSize: const Size(64, 48))` for secondary buttons.
- Every state-bearing subtree gets a `const Key('kebab-case-name')` so a widget test can assert
  totality. Keys required this phase: `setup-topics-loading`, `setup-topics-empty` (exists),
  `setup-topics-error`, `setup-topics-error-retry`, `setup-start-blocked` (exists),
  `setup-start-no-questions`, `setup-start-error`, `setup-start-busy`.

### Doc-comment density

**Source:** `lib/data/questions.dart:85-95`, `lib/services/recording_service.dart:114-143`,
`lib/screens/setup_screen.dart:33-48`

Every class, seam and non-obvious constant carries a comment explaining the decision and the rejected
alternative, tagged with its decision ID (D-xx) or requirement ID. This is the project's stated
handoff constraint and is the single most consistent convention in the codebase — new files that skip
it will read as foreign.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `lib/firebase_options.dart` | config | n/a | Generated by `flutterfire configure`; never hand-authored or hand-edited. No pattern applies |
| `firestore.rules` | config (infra) | n/a | First rules file in the repo. D-46 fully specifies the content and the required comment; follow the repo's "config carries a why" convention (see the AndroidManifest comment) as the only transferable pattern |
| `tool/seed_questions.dart` | utility | batch | No `tool/` directory and no script of any kind exists yet. D-45 is the spec |

---

## Metadata

**Analog search scope:** `lib/` (all 20 files enumerated), `test/` (all 19 files enumerated),
`pubspec.yaml`, `android/` build + manifest files
**Files read in full:** `lib/data/questions.dart`, `lib/screens/setup_screen.dart`,
`lib/screens/history_screen.dart`, `lib/services/recording_service.dart`,
`lib/services/screen_wake_controller.dart`, `lib/models/session_config.dart`, `lib/main.dart`
**Files read in part:** `lib/state/practice_state.dart`, `lib/screens/practice_screen.dart`,
`test/screens/setup_screen_test.dart`, `test/screens/history_screen_test.dart`
**Pattern extraction date:** 2026-08-09
