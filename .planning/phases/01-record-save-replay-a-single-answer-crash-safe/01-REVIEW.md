---
phase: 01-record-save-replay-a-single-answer-crash-safe
reviewed: 2026-08-08T00:00:00Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - lib/main.dart
  - lib/data/questions.dart
  - lib/db/database_helper.dart
  - lib/models/question_answer.dart
  - lib/models/session.dart
  - lib/screens/history_screen.dart
  - lib/screens/practice_screen.dart
  - lib/screens/session_detail_screen.dart
  - lib/services/audio_player_service.dart
  - lib/services/recording_service.dart
  - lib/state/practice_state.dart
  - lib/utils/audio_paths.dart
  - lib/utils/date_format.dart
  - lib/widgets/mascot.dart
  - test/db/database_helper_test.dart
  - test/models/question_answer_test.dart
  - test/models/session_test.dart
  - test/state/practice_state_test.dart
  - test/utils/audio_paths_test.dart
  - test/widgets/mascot_test.dart
  - pubspec.yaml
  - android/app/src/main/AndroidManifest.xml
  - ios/Runner/Info.plist
findings:
  critical: 6
  warning: 12
  info: 6
  total: 24
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-08-08
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

The write-ordering claim at the centre of this phase — *finalize file → single transaction → replay* — is
correctly implemented **inside** `PracticeState.stopRecording()`, and the DB layer (parameterised queries,
`PRAGMA foreign_keys = ON`, one transaction for both rows) is sound. The orphan sweep is genuinely awaited
before the first `startNewQuestion()` in `_bootstrap()`.

Everything *around* that happy path is where this falls apart. The state machine publishes
`PracticePhase.recording` — mascot showing "Listening", STOP button live — **before** the microphone is
actually armed, opening a multi-hundred-millisecond (multi-*second* on first launch, behind the OS
permission dialog) window in which the UI lies about the mic being live and a STOP tap interleaves with the
in-flight `start()`. That interleaving permanently disarms the 60 s auto-stop, so the recorder runs
unbounded and the answer is never saved. Separately, three of the five terminal states the loop can reach
(`idle` after a null stop, `saving` after a thrown `stop()`, `replaying` after a hung `onPlayerComplete`)
render **no button, no banner, and nothing that re-arms the loop** — the app is dead until force-restart,
and the existing test suite asserts the `idle` dead-end as *correct behaviour*.

The single most safety-critical class in the phase, `RecordingService`, has **zero tests**. The
`FakeRecordingService` in `practice_state_test.dart` overrides `stop()` with an implementation that has no
`_stopping` flag at all, so the "first stop wins" guard the phase is built around is never once exercised.
`flutter test` passing 32/32 is not evidence here.

Finally, `google_fonts` was added to the stack (it is not in the approved CLAUDE.md stack table) and fetches
Baloo 2 over the network at runtime. No font asset is bundled, and the release Android manifest has no
`INTERNET` permission — so the locked-in typography works in debug and silently does not exist in release.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: BLOCKER — Recording UI goes live before the microphone does; first seconds of every answer are lost

**File:** `lib/state/practice_state.dart:79-93`
**Issue:** `startNewQuestion()` sets `phase = PracticePhase.recording` and calls `notifyListeners()` at
lines 81-82, *then* awaits `ensureRecordingsDir()` (filesystem I/O), `recordingService.start()` → which
itself awaits `hasPermission()` (platform channel) and `_recorder.start()` (AVAudioSession /
MediaRecorder setup). Only after all of that is the mic actually capturing.

During that entire window the screen renders `Mascot(isRecording: true)` with `Semantics(label:
'Listening')`, the accent pulse ring, and a live `_StopButton` (`practice_screen.dart:118-127`). The app is
telling the user "speak now" while nothing is being captured. On a cold first launch this window includes
the modal OS microphone-permission dialog — potentially many seconds of "Listening" with a dead mic. This
is silent data loss on the primary user action, and it is invisible to the tests because
`FakeRecordingService.start()` returns immediately.

It also creates the concurrency window that CR-02 and WR-03 exploit.

**Fix:** Do not publish the recording phase until the recorder confirms it started.

```dart
Future<void> startNewQuestion() async {
  currentQuestion = _pickQuestion();
  errorMessage = null;
  phase = PracticePhase.arming;   // new phase: mascot idle, no STOP button
  notifyListeners();

  try {
    final dir = await ensureRecordingsDir();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
    final absolutePath = p.join(dir.path, fileName);

    await recordingService.start(
      absolutePath,
      onAutoStop: () => unawaited(stopRecording()),
    );

    // Only now is the mic live.
    _currentRelativePath = recordingRelativePath(fileName);
    phase = PracticePhase.recording;
    notifyListeners();
  } catch (_) {
    _currentRelativePath = null;
    _fail();
  }
}
```

Render nothing tappable and no "Listening" affordance while `phase == PracticePhase.arming`.

---

### CR-02: BLOCKER — A STOP tap during the arming window permanently disarms the 60 s auto-stop; the recorder never stops and the answer is never saved

**File:** `lib/services/recording_service.dart:51-83`, `lib/state/practice_state.dart:121-133`
**Issue:** `RecordingService.start()` clears `_stopping = false` at line 58, awaits `_recorder.start()` at
line 59, and only *then* arms `_autoStopTimer` at lines 60-69. `stop()` sets `_stopping = true`
unconditionally at line 79.

Trace a STOP tap landing inside the CR-01 window (which is user-reachable because the STOP button is
already rendered):

1. `startNewQuestion()` → `phase = recording`, awaits `recordingService.start()`; `_stopping = false`;
   `await _recorder.start(...)` is in flight; **no timer exists yet**.
2. User taps STOP → `PracticeState.stopRecording()` passes the `phase == recording` guard → `phase =
   saving` → `await recordingService.stop()` → `_stopping = true`; `_autoStopTimer?.cancel()` is a no-op
   (still null); `_recorder.stop()` is called on a recorder that has not finished starting.
3. `_recorder.start()` resolves — the mic **is now live** — and the continuation at line 61 arms
   `_autoStopTimer` for 60 s.
4. 60 s later the timer body runs, reads `if (_stopping) return;` (line 63) — `_stopping` is still `true`
   from step 2 and is only ever reset by the *next* `start()` — and returns without stopping anything.

Net result: the microphone records indefinitely into a file nobody will ever reference, the answer is
never saved, and the app has parked in `idle` or `error`. On the next launch `pruneOrphanRecordings()`
deletes the file. The user recorded, saw the app stop responding, and lost the answer.

The `_stopping` flag is also never reset on the failure path — if `start()` throws at the permission check
(line 55-57), `_stopping` retains its previous value entirely.

**Fix:** Make the guard a per-recording token rather than a sticky boolean, arm the deadline before any
awaits can interleave, and reject `stop()` when nothing is armed.

```dart
class RecordingService {
  late final AudioRecorder _recorder = AudioRecorder();
  Timer? _autoStopTimer;
  bool _recording = false;   // replaces _stopping; true only between start and stop
  Future<void>? _startInFlight;

  Future<void> start(String absoluteFilePath, {void Function()? onAutoStop}) async {
    if (_recording || _startInFlight != null) return; // re-entrancy guard (WR-03)
    if (!await hasPermission()) throw const RecordingPermissionDeniedException();
    final started = _recorder.start(const RecordConfig(), path: absoluteFilePath);
    _startInFlight = started;
    try {
      await started;
    } finally {
      _startInFlight = null;
    }
    _recording = true;
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(kMaxRecordingDuration, () {
      _autoStopTimer = null;
      if (!_recording) return;
      (onAutoStop ?? () => unawaited(stop()))();
    });
  }

  Future<String?> stop() async {
    if (!_recording) return null;   // nothing armed, or a second signal — no-op
    _recording = false;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    return _recorder.stop();
  }
}
```

---

### CR-03: BLOCKER — `stopRecording()` has no error handling; a thrown `stop()`, path resolution or playback freezes the app with no error banner

**File:** `lib/state/practice_state.dart:121-160`
**Issue:** Only the DB insert (lines 139-150) is wrapped in `try`. Three other awaits can throw and none
are guarded:

- `await recordingService.stop()` (line 126) — `AudioRecorder.stop()` throws on a recorder in a bad state
  (exactly the state CR-02 produces). Phase is left at `PracticePhase.saving`, which
  `practice_screen.dart:126-133` renders as: no STOP button, no "Playing your answer…", no error banner
  (`hasError` is false because phase is `saving`, not `error`). Permanently frozen screen.
- `await toAbsolutePath(relativePath)` (line 155) and `await audioPlayerService.play(...)` (line 156) —
  `audioplayers` throws if the file is missing or the platform player errors. Phase is left at
  `replaying` → the screen shows "Playing your answer…" forever and `startNewQuestion()` at line 159 is
  never reached, so the loop is dead.

The escaping exception has nowhere to go: the STOP button binds `onPressed: _state.stopRecording`
(`practice_screen.dart:127`), which discards the returned `Future`, and the auto-stop path uses
`unawaited(stopRecording())` (line 92). Both produce an unhandled async error the user never sees.

**Fix:** Wrap the whole body and always land on a recoverable phase.

```dart
Future<void> stopRecording() async {
  if (phase != PracticePhase.recording) return;
  phase = PracticePhase.saving;
  notifyListeners();

  String? finalizedPath;
  try {
    finalizedPath = await recordingService.stop();
  } catch (_) {
    _currentRelativePath = null;
    _fail();               // recoverable: the banner's Retry re-arms
    return;
  }
  if (finalizedPath == null) { _fail(); return; }   // see CR-04

  final relativePath =
      _currentRelativePath ?? recordingRelativePath(p.basename(finalizedPath));
  _currentRelativePath = null;

  try {
    await databaseHelper.insertAnsweredSession(
      questionText: currentQuestion,
      audioRelativePath: relativePath,
    );
  } catch (_) {
    _fail();
    return;
  }

  phase = PracticePhase.replaying;
  notifyListeners();

  try {
    await audioPlayerService.play(await toAbsolutePath(relativePath),
        awaitCompletion: true);
  } catch (_) {
    // The answer IS saved; a replay failure must never block the loop.
  }

  await startNewQuestion();
}
```

---

### CR-04: BLOCKER — `PracticePhase.idle` after a null stop is an unrecoverable dead end (and a test asserts it as correct)

**File:** `lib/state/practice_state.dart:127-133`, `lib/screens/practice_screen.dart:126-133`,
`test/state/practice_state_test.dart:152-161`
**Issue:** When `recordingService.stop()` returns `null`, the loop sets `phase = PracticePhase.idle` and
returns. `PracticeScreen.build` renders a STOP button only for `recording` and a "Playing…" label only for
`replaying`; `idle` renders the mascot and question card with **no interactive element at all**. Nothing in
the codebase ever calls `startNewQuestion()` again from `idle` — the only other entry points are
`_bootstrap()` (initState, already run) and `retry()` (only reachable from the error banner, which `idle`
does not show). The user is stuck staring at a question with no way to answer it, short of killing the app.

The code comment at lines 128-129 justifies this as the benign "first-stop-wins" case, but
`PracticeState.stopRecording()`'s own `phase != recording` guard at line 122 already makes a second stop
signal impossible to reach `recordingService.stop()`. The *only* ways to actually observe `null` here are
recorder-level failures (CR-02's interleaving, or the plugin having nothing to finalize) — i.e. every
reachable path to this branch is an error, not a benign race.

`test/state/practice_state_test.dart:160` locks this in with `expect(state.phase,
PracticePhase.idle)`, so the dead end is currently protected by the suite.

**Fix:** Treat a null finalized path as a failure, not a benign outcome, so the error banner (and therefore
Retry) is reachable:

```dart
if (finalizedPath == null) {
  _currentRelativePath = null;
  _fail();   // banner + Retry; the loop is recoverable
  return;
}
```

Then update the test to assert `PracticePhase.error` and that no session was written. Consider deleting
`PracticePhase.idle` entirely — with this change nothing ever enters it after construction.

---

### CR-05: BLOCKER — `awaitCompletion` can hang forever on a short recording, freezing the loop at "Playing your answer…"

**File:** `lib/services/audio_player_service.dart:18-26`, consumed at `lib/state/practice_state.dart:156`
**Issue:** `play()` awaits `_player.play(...)` — which resolves once the *native* player has been told to
start — and only afterwards subscribes with `await _player.onPlayerComplete.first`.
`onPlayerComplete` is a broadcast stream: any completion event emitted between the `play()` await
resolving and the `.first` subscription attaching is dropped, and `.first` then waits on an event that will
never come again. A sub-second recording (tap STOP immediately, or the truncated file CR-02 can produce) is
exactly the case where playback finishes inside that gap.

There is no timeout and no fallback. `stopRecording()`'s await at line 156 never resolves, so
`startNewQuestion()` at line 159 never runs and the screen shows "Playing your answer…" indefinitely.
`FakeAudioPlayerService.play()` overrides the method wholesale and never touches `onPlayerComplete`, so no
test covers this.

**Fix:** Subscribe before starting playback, and bound the wait.

```dart
Future<void> play(String absoluteFilePath, {bool awaitCompletion = false}) async {
  if (!awaitCompletion) {
    await _player.play(DeviceFileSource(absoluteFilePath));
    return;
  }
  final completed = _player.onPlayerComplete.first;   // subscribe FIRST
  await _player.play(DeviceFileSource(absoluteFilePath));
  await completed.timeout(
    kMaxRecordingDuration + const Duration(seconds: 5),
    onTimeout: () {},   // never let replay block the practice loop
  );
}
```

---

### CR-06: BLOCKER — `google_fonts` fetches Baloo 2 over the network at runtime; the release Android build has no INTERNET permission, so the locked typography silently does not ship

**File:** `lib/main.dart:2,66,73`; `pubspec.yaml:42,67-96`;
`android/app/src/main/AndroidManifest.xml:1-5`
**Issue:** `GoogleFonts.baloo2(...)` is used for `displayLarge` (the question prompt — the one element
UI-01 says must be readable at arm's length) and `headlineSmall`. No font file is bundled: the `fonts:`
section of `pubspec.yaml` is entirely commented out (lines 78-96) and there is no `assets/` or `fonts/`
directory in the repo. `GoogleFonts.config.allowRuntimeFetching` is never set, so it defaults to `true` and
the package performs an HTTP GET to `fonts.gstatic.com` on first use, caching to disk.

Consequences:

1. **Release Android silently loses the typography.** `INTERNET` is declared only in
   `android/app/src/debug/AndroidManifest.xml` and `.../profile/AndroidManifest.xml`. The main (release)
   manifest has none. The fetch fails, `google_fonts` swallows it and falls back to the default Material
   font. Baloo 2 renders during development and does not exist in the shipped app — a defect no developer
   will notice locally.
2. **The manifest's own security claim is now false.** `AndroidManifest.xml:2-4` states "no
   `WRITE_EXTERNAL_STORAGE` and no network permission are requested" — true of the manifest, but the app
   *does* attempt an outbound request to a Google CDN on every cold start until cached, which on iOS (no
   permission gate) succeeds and leaks an install signal. That is undisclosed for an app documented as
   fully local.
3. **`google_fonts` is not in the approved stack.** CLAUDE.md's technology table does not list it, and
   "What NOT to Use" is built around minimising package count and network surface.

**Fix (preferred — keeps the typography and removes the network dependency):** vendor the two Baloo 2
weights as assets and drop the package.

```yaml
# pubspec.yaml
flutter:
  uses-material-design: true
  fonts:
    - family: Baloo2
      fonts:
        - asset: fonts/Baloo2-SemiBold.ttf
          weight: 600
```

```dart
// lib/main.dart — replace GoogleFonts.baloo2(...) with:
displayLarge: const TextStyle(
  fontFamily: 'Baloo2',
  fontSize: 32, fontWeight: FontWeight.w600, height: 1.3, color: textOnColor,
),
```

and remove `google_fonts: ^8.2.1` from `pubspec.yaml`. If the package is kept for any reason, it is
mandatory to set `GoogleFonts.config.allowRuntimeFetching = false` in `main()` *and* bundle the assets —
otherwise the runtime fetch remains.

---

## Warnings

### WR-01: WARNING — `_bootstrap()` is fire-and-forget with no disposal guard; `notifyListeners()` can run on a disposed `PracticeState`

**File:** `lib/screens/practice_screen.dart:32,40-51,53-59`
**Issue:** `initState()` calls `_bootstrap()` without awaiting or storing the future. If the element is
disposed while the sweep or `startNewQuestion()` is still in flight (hot restart, or any future navigation
that pops this route), `dispose()` runs `_state.recordingService.dispose()` → `_state.dispose()`, and the
pending continuation then calls `notifyListeners()` on a disposed `ChangeNotifier` (debug assertion
failure) and `recordingService.start()` on a disposed `AudioRecorder`.

**Fix:** Track a disposed flag on `PracticeState` and bail out of both async methods after every await:

```dart
// PracticeState
bool _disposed = false;
@override
void dispose() { _disposed = true; super.dispose(); }
void _notify() { if (!_disposed) notifyListeners(); }
```
Replace every `notifyListeners()` with `_notify()`, and add `if (_disposed) return;` immediately after
each `await` in `startNewQuestion()` / `stopRecording()`.

---

### WR-02: WARNING — Three `Future`s are discarded in `PracticeScreen.dispose()`, and an in-flight recording is never stopped

**File:** `lib/screens/practice_screen.dart:53-59`
**Issue:** `recordingService.dispose()`, `audioPlayerService.dispose()` and `_state.dispose()` are called
synchronously; the first two return `Future`s that are dropped, so any error they raise is unhandled.
Nothing calls `recordingService.stop()` first, so the platform recorder is disposed mid-capture and any
playback in progress keeps its native resources until the plugin's own teardown lands.

**Fix:**

```dart
@override
void dispose() {
  unawaited(_state.recordingService.stop().catchError((_) => null)
      .whenComplete(_state.recordingService.dispose));
  unawaited(_state.audioPlayerService.dispose());
  _state.dispose();
  super.dispose();
}
```

---

### WR-03: WARNING — No re-entrancy guard on `startNewQuestion()`; concurrent calls can persist a DB row pointing at a file the recorder never wrote

**File:** `lib/state/practice_state.dart:78-101,106`
**Issue:** `retry()` is bound directly to `_ErrorBanner.onRetry` (a plain `VoidCallback`, return value
discarded) and `startNewQuestion()` has no in-flight guard. Two overlapping invocations each compute their
own `fileName` and each assign `_currentRelativePath` — whichever assignment lands *last* wins, while
whichever `_recorder.start()` lands last determines the file actually being written. Those two orderings
are independent (they are separated by the `ensureRecordingsDir()` and `hasPermission()` awaits), so
`_currentRelativePath` can end up naming file A while the recorder writes file B.

`stopRecording()` then commits `_currentRelativePath` (file A) to the database at line 140. The result is a
durable `question_answers` row whose `audio_path` points at a file that was never created; file B is
orphaned and deleted on the next launch. History shows the answer, tapping it plays nothing (WR-06 means
there is no feedback either). This is precisely the "saved with a stale audio path" failure the phase's
crash-safety contract is meant to exclude.

**Fix:** Guard re-entry at the state level *and* the service level (see CR-02's `_startInFlight`):

```dart
Future<void>? _startInFlight;

Future<void> startNewQuestion() {
  final inFlight = _startInFlight;
  if (inFlight != null) return inFlight;
  final future = _startNewQuestion().whenComplete(() => _startInFlight = null);
  _startInFlight = future;
  return future;
}
```

---

### WR-04: WARNING — `DatabaseHelper.database` lazy-init is not concurrency-safe; two overlapping first calls open the database twice

**File:** `lib/db/database_helper.dart:42-55,154-157`
**Issue:** The getter checks `_db == null`, then awaits `appDocumentsDir()` and `openDatabase()` before
assigning `_db`. Two callers entering before the first assignment both run `openDatabase()`. This is
reachable: `_bootstrap()` calls `listReferencedAudioPaths()` at screen construction, and the user can tap
the History action (`practice_screen.dart:77-81` → `HistoryScreen.initState` → `listSessions()`) before it
resolves.

`_db` is then overwritten, so `close()` at line 155 closes only the survivor and the other handle leaks for
the process lifetime. (sqflite on-device reference-counts by path, which softens this to a leaked ref-count
and a `close()` that does not actually close; `sqflite_common_ffi`, used by the tests, opens a genuinely
separate connection — so the test environment and production behave differently here.)

**Fix:** Memoize the `Future`, not the resolved value:

```dart
Future<Database>? _dbFuture;

Future<Database> get database => _dbFuture ??= _open();

Future<Database> _open() async {
  final docsDir = await appDocumentsDir();
  return openDatabase(p.join(docsDir.path, kDatabaseFileName),
      version: 1, onConfigure: _onConfigure, onCreate: _onCreate);
}

Future<void> close() async {
  final f = _dbFuture;
  _dbFuture = null;
  if (f != null) await (await f).close();
}
```

---

### WR-05: WARNING — A failed database read is rendered as "No recordings yet", i.e. as apparent data loss

**File:** `lib/screens/history_screen.dart:42-51`, `lib/screens/session_detail_screen.dart:63-70`
**Issue:** Both `FutureBuilder`s check only `connectionState` and then do `snapshot.data ?? const []`.
`snapshot.hasError` is never inspected. If `listSessions()` throws (corrupt DB, locked file, the WR-04
double-open), `connectionState` is `done`, `data` is null, and the user is shown the empty-state copy "No
recordings yet / Finish your first answer and it'll show up here." For an app whose entire value
proposition is "you can always go back and listen to what you said", telling the user their history is
empty when it is actually unreadable is the worst possible failure presentation.

**Fix:**

```dart
if (snapshot.hasError) {
  return _HistoryError(onRetry: () => setState(() {
    _sessionsFuture = widget.databaseHelper.listSessions();
  }));
}
final sessions = snapshot.data ?? const <Session>[];
```

---

### WR-06: WARNING — Tapping a history row whose audio file is missing does nothing, with no feedback

**File:** `lib/screens/session_detail_screen.dart:45-50,84`
**Issue:** `_play()` resolves the path and calls `_audioPlayerService.play()` with no existence check and
no `try`/`catch`; the `onTap` discards the returned `Future`. If the file is gone — deleted by
`pruneOrphanRecordings` after a save-failure orphan (WR-07), lost to a stale path (WR-03), or removed by
iOS storage pressure — the tap produces silence and an unhandled async error. The user cannot distinguish
"the recording is broken" from "I mis-tapped".

**Fix:**

```dart
Future<void> _play(QuestionAnswer answer) async {
  final absolutePath = await toAbsolutePath(answer.audioPath);
  if (!await File(absolutePath).exists()) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This recording is no longer available.')),
    );
    return;
  }
  try {
    await _audioPlayerService.play(absolutePath);
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't play this recording.")),
    );
  }
}
```

---

### WR-07: WARNING — A save failure blames the microphone and silently abandons a successfully recorded answer

**File:** `lib/state/practice_state.dart:23-24,144-150`
**Issue:** The save-failure catch calls `_fail()`, which sets the single fixed string "Recording failed —
check your microphone permission and try again." At this point the recording *succeeded* and was finalized
on disk; what failed was the disk/database write. The user is directed to fix a permission that is not the
problem, and is never told that the answer they just gave is gone. The finalized file is left on disk
unreferenced and is deleted by the next launch's sweep.

Suppressing exception detail from the UI (T-03-02) is correct; collapsing two categorically different
failures into one misleading instruction is not.

**Fix:** Keep exception detail out of the UI but distinguish the *category*, and log the cause for
diagnosis:

```dart
const String kRecordingErrorMessage =
    'Recording failed — check your microphone permission and try again.';
const String kSaveErrorMessage =
    "We couldn't save that answer. Please try again.";

} catch (error, stack) {
  debugPrint('insertAnsweredSession failed: $error');   // developer-facing only
  FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
  _fail(kSaveErrorMessage);
  return;
}
```

---

### WR-08: WARNING — No lifecycle handling; backgrounding or a phone call mid-recording is unhandled

**File:** `lib/screens/practice_screen.dart:21-59`, `lib/services/recording_service.dart:61`
**Issue:** Nothing implements `WidgetsBindingObserver`. If the app is backgrounded or interrupted (incoming
call, another app grabbing the audio session) while `phase == recording`:
- iOS/Android suspend or terminate the capture, but `PracticeState` still believes it is recording;
- the `_autoStopTimer` is throttled/suspended in the background, so the 60 s deadline does not fire on
  time — on resume the app may still be in `recording` with a dead recorder and a timer that will now
  no-op via CR-02's `_stopping` path, or it saves a truncated answer as if it were complete;
- if the OS kills the process, the partial file is swept next launch (this part is the intended D-08
  behaviour and is fine).

For a phase whose defining requirement is surviving a force-kill, an interruption that is *not* a kill is
the more common case and is entirely unhandled.

**Fix:** Add an observer to `_PracticeScreenState` that finalizes on `AppLifecycleState.paused`:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused &&
      _state.phase == PracticePhase.recording) {
    unawaited(_state.stopRecording());   // finalize + commit while we still can
  }
}
```

---

### WR-09: WARNING — `RecordingService` has zero test coverage, and the fake used elsewhere cannot reproduce the race it is meant to prove

**File:** `test/` (no `test/services/` directory), `test/state/practice_state_test.dart:14-45`
**Issue:** The class that owns the 60 s deadline, the first-stop-wins guard and the pre-flight permission
check — the three pieces of logic this phase's reliability rests on — has no test file at all.
`FakeRecordingService.stop()` (lines 36-41) is a full override that returns `lastRequestedPath`
unconditionally; it has no `_stopping` flag and no timer, so the "first stop wins" behaviour asserted by
`practice_state_test.dart:152-161` is testing a hand-written stub, not the production guard.
`stopReturnsNull` is a manually toggled boolean, not a reproduction of the race.

This is why CR-02 and CR-04 are invisible to a green suite.

**Fix:** Add `test/services/recording_service_test.dart` exercising the real class against a fake
`AudioRecorder` seam (extract an injectable recorder factory), covering at minimum: (a) concurrent
`stop()` calls yield exactly one non-null path; (b) `stop()` before `start()` completes does not leave the
recorder armed with a dead timer; (c) the auto-stop timer fires exactly once at
`kMaxRecordingDuration` under `fakeAsync`; (d) a thrown permission check leaves no timer armed.

---

### WR-10: WARNING — `pruneOrphanRecordings`'s caller contract is enforced only by a comment, and is untested

**File:** `lib/utils/audio_paths.dart:63-65`, `lib/screens/practice_screen.dart:40-51`
**Issue:** "CALLER CONTRACT: must be awaited to completion BEFORE the next recording is armed" is prose.
`_bootstrap()` currently honours it, but nothing in the code prevents a second call site from violating it,
and there is no test asserting the ordering — `audio_paths_test.dart` only tests the function in isolation
and there is no `PracticeScreen` widget test at all. Violating it deletes the file currently being written.

**Fix:** Make the contract mechanical rather than documentary — pass the in-progress relative path so it is
always excluded, and never rely on ordering alone:

```dart
Future<int> pruneOrphanRecordings(
  Set<String> referencedRelativePaths, {
  String? inProgressRelativePath,
}) async {
  final protected = {
    ...referencedRelativePaths,
    if (inProgressRelativePath != null) inProgressRelativePath,
  };
  ...
}
```
and add a widget test asserting `_bootstrap` completes the sweep before `startNewQuestion` is called.

---

### WR-11: WARNING — `widget.session.id!` force-unwrap in `SessionDetailScreen`

**File:** `lib/screens/session_detail_screen.dart:35-36`
**Issue:** `Session.id` is declared `int?` (`session.dart:8`) and `Session.fromMap` will happily produce a
null id. A null here throws inside `initState`, which surfaces as a red-screen crash rather than a handled
error. It happens to be safe today only because the sole construction path is `listSessions()`.

**Fix:** Either narrow the model (`final int id;` for a persisted session, with a separate unsaved
constructor) or handle it:

```dart
final id = widget.session.id;
_answersFuture = id == null
    ? Future.value(const <QuestionAnswer>[])
    : widget.databaseHelper.listAnswersForSession(id);
```

---

### WR-12: WARNING — `Session.toMap()` and `QuestionAnswer.toMap()` are production-dead code that duplicates the schema mapping

**File:** `lib/models/session.dart:16-19`, `lib/models/question_answer.dart:30-36`
**Issue:** Neither method is called anywhere in `lib/` — `insertAnsweredSession`
(`database_helper.dart:109-115`) builds its column maps inline. The only callers are
`test/models/*_test.dart`, which round-trip `toMap()` against `fromMap()`, i.e. they verify the dead code
against itself. This is an active drift hazard: rename a column in `DatabaseHelper` and both model
`toMap()`s silently disagree with the schema while the model tests still pass.

**Fix:** Delete both `toMap()` methods and the tests that exercise them, or make `insertAnsweredSession`
the single writer by consuming them:

```dart
await txn.insert(kQuestionAnswersTable,
    QuestionAnswer(sessionId: sessionId, questionText: questionText,
                   audioPath: audioRelativePath, createdAt: now).toMap());
```
The second option is preferable — it makes the column names live in exactly one place.

---

## Info

### IN-01: Timestamps are stored as local time with no timezone offset

**File:** `lib/db/database_helper.dart:107`, `lib/utils/date_format.dart:22`
**Issue:** `DateTime.now().toIso8601String()` yields e.g. `2026-08-08T14:30:00.000` with no offset suffix.
`DateTime.parse` reads it back as local, and `formatSessionTimestamp` then calls `.toLocal()` (a no-op).
History timestamps become wrong after a timezone change or DST transition, and the values are not
comparable across devices.
**Fix:** Store UTC (`DateTime.now().toUtc().toIso8601String()`, which appends `Z`); `.toLocal()` in the
formatter then does real work.

### IN-02: Recording file names can collide at millisecond resolution

**File:** `lib/state/practice_state.dart:86`
**Issue:** `'${DateTime.now().millisecondsSinceEpoch}.m4a'` is unique only if no two recordings start in
the same millisecond. Human pacing makes this unlikely, but a collision silently overwrites a previously
saved answer whose DB row still points at that path.
**Fix:** Append entropy: `'${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(1 << 20)}.m4a'`.

### IN-03: `documentsDirProvider` is a mutable public global in production code

**File:** `lib/utils/audio_paths.dart:22`
**Issue:** The storage-root resolver for both the audio files and the SQLite database is a reassignable
top-level variable shipped in the release binary. It is a reasonable test seam, but it means any code in
the app can silently relocate all persistence.
**Fix:** Gate it — `@visibleForTesting` on a setter, or wrap the override in `assert(() { ... }())` so it
cannot be reassigned in release mode.

### IN-04: `toAbsolutePath` would escape the app sandbox if a stored path were ever absolute

**File:** `lib/utils/audio_paths.dart:45-48`
**Issue:** `p.join(docsDir.path, relativePath)` returns `relativePath` verbatim when it is absolute, and
does not normalise `..` segments. All current writers produce `recordings/<name>`, so this is not
exploitable today — but it is the kind of assumption that breaks when Phase 3's JSON import starts putting
externally-sourced strings near this code.
**Fix:** Assert and normalise:

```dart
Future<String> toAbsolutePath(String relativePath) async {
  final docsDir = await appDocumentsDir();
  final resolved = p.normalize(p.join(docsDir.path, relativePath));
  if (!p.isWithin(docsDir.path, resolved)) {
    throw ArgumentError('audio path escapes the app container');
  }
  return resolved;
}
```

### IN-05: `_pickQuestion` is fragile against an empty or future-dynamic question list

**File:** `lib/state/practice_state.dart:47,59-70`
**Issue:** `currentQuestion = kQuestions.first` (field initializer) and `_random.nextInt(kQuestions.length)`
both throw on an empty list, and the `do/while` loop has no iteration bound. Safe today because
`kQuestions` is a `const` list of 5, but Phase 3 replaces this with a Firestore-fed list that can legitimately
be empty.
**Fix:** Guard now, before the list becomes dynamic:
`if (kQuestions.isEmpty) return 'No questions available';`

### IN-06: `AudioPlayerService.stop()` is never called

**File:** `lib/services/audio_player_service.dart:28`
**Issue:** No call site in `lib/` or `test/`. Notably, `SessionDetailScreen` starts a new `play()` on every
row tap without stopping the previous one, so rapid taps overlap playback — the unused `stop()` is exactly
what that path needs.
**Fix:** Either call it (`await _audioPlayerService.stop();` at the top of `_play`) or delete it.

---

_Reviewed: 2026-08-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
