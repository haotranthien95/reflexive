# Phase 2: Full Timed Practice Session (Setup, Loop & Controls) - Pattern Map

**Mapped:** 2026-08-08
**Files analyzed:** 17 (7 new lib, 5 modified lib, plus mirrored tests)
**Analogs found:** 16 / 17

This is a **Flutter/Dart** project. Source in `lib/`, tests mirror it path-for-path under `test/`.
Every excerpt below is real code already in the repo — copy the shape, not just the idea.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|-------------------|------|-----------|----------------|-------|
| `lib/models/session_config.dart` (NEW) | model (immutable value object) | transform | `lib/models/session.dart`, `lib/models/question_answer.dart` | role-match |
| `lib/screens/setup_screen.dart` (NEW) | screen (form) | local state → push nav | `lib/screens/history_screen.dart` (chrome/theming), `lib/screens/practice_screen.dart` (nav + scroll/textScale) | role-match |
| `lib/utils/pausable_countdown.dart` (NEW) | utility (pure Dart, timer) | event-driven | `lib/services/recording_service.dart` `_autoStopTimer` block (the only existing `Timer` discipline) | partial |
| `lib/services/screen_wake_controller.dart` (NEW) | service (platform seam) | request-response | `lib/services/audio_player_service.dart` (abstract backend + lazy prod impl) | **exact** |
| `lib/data/questions.dart` (MODIFY) | data/config | static | itself (extend `kQuestions` to ~20, add `kSubjects` behind a seam) | exact |
| `lib/services/recording_service.dart` (MODIFY) | service | streaming/event | itself | exact |
| `lib/services/audio_player_service.dart` (MODIFY) | service | streaming | itself | exact |
| `lib/db/database_helper.dart` (MODIFY: `insertAnswer`) | db | CRUD | its own `insertAnsweredSession` | exact |
| `lib/state/practice_state.dart` (MODIFY: loop, phases, pause) | state (ChangeNotifier) | event-driven | itself | exact |
| `lib/widgets/phase_control.dart` (MODIFY: new phases + `remainingSeconds`) | widget | static | itself | exact |
| `lib/widgets/countdown_ring.dart` (NEW) | widget (presentational) | static | `lib/widgets/mascot.dart` | role-match |
| `lib/screens/practice_screen.dart` (MODIFY: config arg, PopScope, app bar, lifecycle) | screen | event-driven | itself | exact |
| `lib/main.dart` (MODIFY: `home: SetupScreen()`) | config | — | itself | exact |
| `test/models/session_config_test.dart` (NEW) | test | — | `test/models/session_test.dart` | exact |
| `test/utils/pausable_countdown_test.dart` (NEW) | test (timer) | — | `test/services/recording_service_test.dart` | exact |
| `test/screens/setup_screen_test.dart` (NEW) | test (widget) | — | `test/screens/history_screen_test.dart` | exact |
| `test/state/practice_session_test.dart` (NEW — **must be a new file**, see Pitfall 3) | test (timer + ffi) | — | `test/state/practice_state_test.dart` + `test/db/database_helper_test.dart` | exact |
| `test/widgets/phase_control_test.dart` (MODIFY) | test | — | itself | exact |
| `test/services/screen_wake_controller_test.dart` (NEW) | test | — | `test/services/audio_player_service_test.dart` | exact |

---

## Pattern Assignments

### `lib/services/screen_wake_controller.dart` (NEW — service seam, D-30)

**Analog:** `lib/services/audio_player_service.dart:12-58` — copy this shape exactly (abstract seam →
private production impl → lazily-resolved injected backend, so a host test never builds a channel).

```dart
/// Playback, reduced to the four operations [AudioPlayerService] needs.
///
/// Mirrors `RecorderBackend`: the seam a test injects so the REAL
/// [AudioPlayerService] ... runs without any platform channel.
abstract class AudioPlaybackBackend {
  Future<void> play(String absoluteFilePath);
  Stream<void> get onComplete;
  Future<void> stop();
  Future<void> dispose();
}

class _AudioPlayersBackend implements AudioPlaybackBackend {
  late final AudioPlayer _player = AudioPlayer();
  @override
  Future<void> play(String absoluteFilePath) =>
      _player.play(DeviceFileSource(absoluteFilePath));
  ...
}

class AudioPlayerService {
  AudioPlayerService({AudioPlaybackBackend? backend}) : _injectedBackend = backend;
  final AudioPlaybackBackend? _injectedBackend;
  late final AudioPlaybackBackend _backend =
      _injectedBackend ?? _AudioPlayersBackend();
```

Additional obligations for this file: both call sites wrap in `try/catch` + `debugPrint` only
(UI-SPEC forbids a new user-facing failure string).

---

### `lib/utils/pausable_countdown.dart` (NEW — utility)

**Analog:** the deadline block in `lib/services/recording_service.dart:184-212` — this is the
repo's only existing `Timer` discipline, and the new class replaces it.

```dart
    _recording = true;
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(kMaxRecordingDuration, () {
      _autoStopTimer = null;
      if (!_recording) return;
      if (onAutoStop != null) { onAutoStop(); } else { unawaited(stop()); }
    });
```
```dart
  Future<String?> stop() async {
    if (_startInFlight != null) { _stopRequestedDuringStart = true; return null; }
    if (!_recording) return null;      // "first stop signal wins"
    _recording = false;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    return _backend.stop();
  }
```

Conventions to copy: (1) always `?.cancel()` then null the field before re-arming — a pending
timer fails the test binding at teardown; (2) a terminal flag makes the object un-re-armable;
(3) the *why* (Timer vs Stopwatch testability) goes in the doc comment, Phase 1 style. The
canonical class body is drafted in `02-RESEARCH.md` § Q2.

---

### `lib/models/session_config.dart` (NEW — immutable value object)

**Analog:** `lib/models/session.dart` (20 lines) — plain class, named required fields, `fromMap`
factory where a DB row exists. `SessionConfig` is **not** persisted (D-18), so it needs no
`fromMap`/`toMap`: just `final` fields (`topics`, `level`, `questionCount`, `thinkingSeconds`,
`answerSeconds`, `autoReplay`) + a `const` constructor + `@immutable`. Keep `level` and `topics`
from day one so Phase 3's Firestore query has fields to read.

---

### `lib/screens/setup_screen.dart` (NEW — form screen, becomes `home:`)

**Analog:** `lib/screens/practice_screen.dart` (StatefulWidget + Scaffold + AppBar action + push
nav + textScale-safe scroll) and `lib/screens/history_screen.dart` (theme discipline).

**App-bar action + push navigation** (`practice_screen.dart:73-92`) — move verbatim to Setup (D-28/D-29):
```dart
  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(databaseHelper: _state.databaseHelper),
      ),
    );
  }
  ...
      appBar: AppBar(
        title: const Text('EnglishReflex'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Exercise History',
            onPressed: _openHistory,
          ),
        ],
      ),
```

**Text-scale containment** (`practice_screen.dart:110-124`) — the body scrolls, the footer is pinned outside it:
```dart
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, // lg — screen edge padding
                          vertical: 32, // xl
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 64,
                          ),
```

**Theming** (`history_screen.dart:53-61`): `final theme = Theme.of(context);` then
`theme.textTheme.headlineSmall` / `theme.colorScheme.surface`. **Never a hex literal in a screen** —
the only literal-colour file is `lib/widgets/mascot.dart` (documented exception, lines 27-39).

**Keyed sub-widgets + touch floor** (`history_screen.dart:145-188`): private `_Xxx` StatelessWidgets
with `key: const Key('history-error')` and `minimumSize: const Size(64, 48)` with the comment
`// Touch-target floor, not part of the 4px content scale.`

---

### `lib/db/database_helper.dart` — add `insertAnswer` (D-26)

**Analog:** its own `insertAnsweredSession` (`database_helper.dart:140-166`). Leave that method
byte-for-byte alone; add the sibling with the same doc-comment obligations (crash-safety note,
"MUST only be called AFTER the audio file is finalized", one transaction per call).

```dart
  /// Crash-safety-critical write path (D-08 / PERSIST-01).
  ///
  /// Writes one `sessions` row and its one `question_answers` row inside a
  /// SINGLE transaction ...
  /// MUST only ever be called AFTER the audio file is confirmed finalized on
  /// disk — never before, and never as two independent writes.
  Future<int> insertAnsweredSession({
    required String questionText,
    required String audioRelativePath,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.transaction<int>((txn) async {
      final sessionId = await txn.insert(kSessionsTable, {'created_at': now});
      await txn.insert(kQuestionAnswersTable, {
        'session_id': sessionId,
        'question_text': questionText,
        'audio_path': audioRelativePath,
        'created_at': now,
      });
      return sessionId;
    });
  }
```
No schema change, no `version:` bump (still `version: 1` at line 99). Values always go through
typed `insert()`/`whereArgs` — never string-concatenated (file header contract).

---

### `lib/state/practice_state.dart` — extend (loop, pause, new phases)

**Analog:** itself. Three constructs must survive verbatim.

**1. Injected services + post-dispose notify guard** (lines 38-88):
```dart
class PracticeState extends ChangeNotifier {
  PracticeState({
    required this.recordingService,
    required this.audioPlayerService,
    required this.databaseHelper,
  });
  ...
  /// [notifyListeners] that is safe after [dispose].
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
```
`SessionConfig` joins this constructor as a required field. `dispose()` must additionally cancel
every `PausableCountdown` and the `onPausedChanged` subscription.

**2. The write-ordering contract in `stopRecording()` (lines 212-293) — split only its tail.**
Keep the guard comments and the deliberate placement of `_disposed`:
```dart
    // NOTE: deliberately NO `if (_disposed) return;` here. Once stop() has
    // returned, the recorder has already finalized the user's answer on disk,
    // and the save below IS the crash-safety contract ...
    // The disposal check belongs AFTER the commit — see below.
```
```dart
    } catch (error, stack) {
      debugPrint('EnglishReflex: saving the answer failed: $error');
      FlutterError.reportError(FlutterErrorDetails(
        exception: error, stack: stack, library: 'englishreflex',
        context: ErrorDescription('saving a finished answer'),
      ));
      _fail();
      return;
    }
    // Safe here and only here: the answer is committed ...
    if (_disposed) return;
```
Only the code after that commit changes (interruption park → optional replay → `getReady`/complete).

**3. Re-entrancy collapse** (lines 111-118) — the shape any new async entry point (`resume()`,
`handleInterruption()`) should reuse:
```dart
  Future<void> startNewQuestion() {
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    final started = _startNewQuestion().whenComplete(() => _startInFlight = null);
    _startInFlight = started;
    return started;
  }
```
Also: one fixed failure string only (`kRecordingErrorMessage`, line 28); exception detail never
reaches the screen.

---

### `lib/widgets/phase_control.dart` — new phases + `remainingSeconds`

**Analog:** itself. The totality map is the guardrail:
```dart
const Map<PracticePhase, Key> kPhaseControlKeys = <PracticePhase, Key>{
  PracticePhase.idle: Key('practice-control-idle'),
  PracticePhase.arming: Key('practice-control-arming'),
  ...
};
```
Add `getReady`/`reading`/`paused`/`complete` entries (UI-SPEC names the keys). Caption phases copy:
```dart
      case PracticePhase.arming:
        return Text(
          'Getting ready…',
          key: kPhaseControlKeys[PracticePhase.arming],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        );
```
The `recording` case keeps its 96px `FittedBox(fit: BoxFit.scaleDown)` circle (lines 90-119) and gains
the `"{M}:{SS} left"` readout **inside the same keyed widget** (wrap in a `Column` under the existing
`key:`) so `findsOneWidget` still holds. The class doc comment must gain the new justification for
timer-driven `getReady`/`reading` (the existing "every await is guarded" argument does not transfer —
see UI-SPEC).

---

### `lib/widgets/countdown_ring.dart` (NEW — presentational widget)

**Analog:** `lib/widgets/mascot.dart` — the repo's only other bespoke, non-interactive visual
widget that occupies a fixed anchor box. Copy its shape: a `StatelessWidget` sized by an outer
`SizedBox` to the same 144px anchor box the mascot occupies, so swapping mascot ↔ ring causes
zero layout shift between `getReady`, `reading` and `recording`.

Two divergences from the analog, both deliberate:
1. **Colours come from `Theme.of(context)`, not literals.** `mascot.dart` is the codebase's ONE
   documented literal-colour exception (its lines 27-39 explain why); that exemption does **not**
   extend to the ring. Coral arc via `colorScheme.primary`, peach track via `colorScheme.surface`.
2. **The indicator must be DETERMINATE** (`value:` computed from the elapsed fraction, never
   null). An indeterminate `CircularProgressIndicator` animates forever and would make any widget
   test that settles hang — the same hazard `02-RESEARCH.md` § Q8 flags for countdown phases.

Created by `02-02-PLAN.md` Task 2; tested by `test/widgets/countdown_ring_test.dart`, whose
analog is `test/widgets/mascot_test.dart`.

---

### `lib/screens/practice_screen.dart` — config arg, PopScope, session app bar, lifecycle

**Analog:** itself. Keep the `ListenableBuilder` + banner-above-content structure (lines 94-155) and
this dispose contract verbatim, extending it with `_lifecycle.dispose()` and the paused-subscription
cancel **before** the existing chain:
```dart
  @override
  void dispose() {
    // Stop any in-flight recording BEFORE tearing the recorder down: leaving
    // the screen must never leave the microphone live. ...
    unawaited(
      _state.recordingService
          .stop()
          .catchError((Object _) => null)
          .whenComplete(_state.recordingService.dispose),
    );
    unawaited(_state.audioPlayerService.dispose());
    _state.dispose();
    super.dispose();
  }
```
The `_bootstrap()` orphan-sweep block (lines 38-54) moves to app/Setup start-up — its caller
contract comment moves with it. `PopScope`/`AppLifecycleListener` snippets: `02-RESEARCH.md` § Q6/Q5.

---

### Tests

**Timer tests → `testWidgets`, in NEW files.** Analog `test/services/recording_service_test.dart:60-68`
(quote this rationale in the new files):
```dart
  // Every test runs inside `testWidgets` because flutter_test's
  // AutomatedTestWidgetsFlutterBinding already runs the body on a fake clock:
  // a real `Timer` created here is a fake timer and `tester.pump(duration)`
  // advances it. No `fake_async` dependency is needed.
  //
  // That binding also FAILS any test that ends with a pending timer, so each
  // test below either pumps past the deadline or disposes the service.
```
Do **not** convert `test/state/practice_state_test.dart` to `testWidgets` (its
`FlutterError.reportError` save-failure test would break — Pitfall 3). New loop tests go in
`test/state/practice_session_test.dart`. No `pumpAndSettle` around countdown phases (Pitfall 4).

**Fake backend style** — `test/services/recording_service_test.dart:15-55`: a `calls` list, gate
`Completer`s, no platform channel. Extend `FakeRecorderBackend` with `pause/resume/isPaused` and a
`StreamController<bool>`-backed `onPausedChanged`.

**Real-SQLite host tests** — `test/db/database_helper_test.dart:12-31`:
```dart
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_db_test');
    documentsDirProvider = () async => tempDir;
    helper = DatabaseHelper();
  });
  tearDown(() async {
    await helper.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });
```

**Widget-test host** — `test/widgets/phase_control_test.dart:7-23` `_host()` helper + the two
totality assertions (`kPhaseControlKeys.length == PracticePhase.values.length`, and every phase
renders exactly one keyed control). Extend, never weaken.

---

## Shared Patterns

### Doc comments carry the contract
**Source:** every file in `lib/`. Each non-obvious guard has a comment saying *what breaks without it*
(e.g. `recording_service.dart:218-223`, `practice_state.dart:229-235`, `database_helper.dart:62-92`).
**Apply to:** all new files. New invariants this phase (silent-no-op pause, four-clock freeze,
new-test-file rule) belong in code comments, not only in planning docs.

### Theme-only styling
**Source:** `lib/main.dart:79-131` (single palette + 4-size/2-weight text theme).
**Apply to:** `setup_screen.dart`, new `PhaseControl` branches. Read via `Theme.of(context)`; derive
the 128px glyph as `textTheme.displayLarge!.copyWith(fontSize: kCountdownGlyphSize, ...)`; never pin
`textScaler`. Only `mascot.dart` may hold literal colours (documented exception).

### One failure string
**Source:** `practice_state.dart:28` `kRecordingErrorMessage` + `history_screen.dart:19`
`kHistoryErrorMessage`. **Apply to:** everything new — Phase 2 adds **no** new user-facing failure
string. Exception detail goes to `debugPrint`/`FlutterError.reportError` only.

### Lazy platform seam
**Source:** `recording_service.dart:81-86`, `audio_player_service.dart:52-58`.
**Apply to:** `ScreenWakeController` and every extension of the two existing backends. Seams stay free
of package types (map `RecordState` → `bool` inside the production backend).

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `lib/utils/pausable_countdown.dart` | utility | event-driven | No standalone pausable-timer utility exists; `lib/utils/*` are pure string/path helpers. Nearest discipline is `RecordingService`'s `_autoStopTimer` (quoted above); the full class shape is drafted in `02-RESEARCH.md` § Q2. |

Also no analog for the *widgets* `Slider`/`ChoiceChip`/`CheckboxListTile`/`SwitchListTile`/
`AlertDialog`/`PopScope` — none appear anywhere in `lib/` today. Use stock Material per the UI-SPEC
control table, styled only through `Theme.of(context)`.

## Metadata

**Analog search scope:** all of `lib/` (15 files) and `test/` (12 files) — the entire codebase.
**Files scanned:** 27
**Pattern extraction date:** 2026-08-08
