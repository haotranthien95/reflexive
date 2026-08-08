---
phase: 01-record-save-replay-a-single-answer-crash-safe
reviewed: 2026-08-08T00:00:00Z
depth: deep
scope: gap-closure run only (plans 01-04, 01-05, 01-06) — diff cd5cdae..HEAD
supersedes: the 01-01..01-03 review previously in this file
files_reviewed: 19
files_reviewed_list:
  - lib/services/recording_service.dart
  - lib/services/audio_player_service.dart
  - lib/state/practice_state.dart
  - lib/widgets/phase_control.dart
  - lib/screens/practice_screen.dart
  - lib/screens/history_screen.dart
  - lib/screens/session_detail_screen.dart
  - lib/db/database_helper.dart
  - lib/main.dart
  - pubspec.yaml
  - assets/fonts/OFL.txt
  - ios/Runner/Info.plist
  - ios/Runner.xcodeproj/project.pbxproj
  - test/services/recording_service_test.dart
  - test/services/audio_player_service_test.dart
  - test/state/practice_state_test.dart
  - test/widgets/phase_control_test.dart
  - test/theme/typography_test.dart
  - test/screens/history_screen_test.dart
  - test/screens/session_detail_screen_test.dart
  - test/db/database_helper_test.dart
findings:
  critical: 2
  warning: 11
  info: 6
  total: 19
status: issues_found
baseline:
  flutter_analyze: clean
  flutter_test: 78/78 passing
---

# Phase 1 Gap Closure (plans 01-04 / 01-05 / 01-06): Code Review Report

**Reviewed:** 2026-08-08
**Depth:** deep (cross-file, with executable probes)
**Scope:** `git diff cd5cdae..HEAD -- lib/ test/ pubspec.yaml android/ ios/ assets/`
**Files Reviewed:** 19 (+2 binary/licence assets)
**Status:** issues_found

## Summary

This run is a large net improvement and the four gaps are substantially closed. Verified by
reading, not by trusting the summaries:

- **Gap 1** — `PhaseControl`'s phase→control map is genuinely total, and it is total *twice over*:
  the `switch` in `PhaseControl.build` has no `default:` arm and returns a non-nullable `Widget`,
  so adding a `PracticePhase` is a **compile** error before the exhaustive test even runs. Phase 2
  can add pause/resume phases safely.
- **Gap 2** — the font is genuinely bundled. `google_fonts` 8.2.1's `loadFontIfNecessary` really
  does `throw` when `allowRuntimeFetching == false` and no matching asset is found
  (`google_fonts_base.dart:175-181`), and `googleFontsTextStyle` really does register the load in
  `pendingFontFutures` — so `await GoogleFonts.pendingFonts()` is a real assertion, and the
  ordering in `main()` (`ensureInitialized` → `configureFonts` → `runApp` → first `GoogleFonts.*`
  call in `EnglishReflexApp.build`) is correct.
- **Gap 3** — every `await` in `stopRecording()` is guarded, and `AudioPlayerService` subscribes
  before `play()` *and* bounds the wait. Both protections are real.
- **Gap 4** — `snapshot.hasError` is checked **before** `snapshot.data` in both `history_screen.dart:72`
  and `session_detail_screen.dart:141`, and both retry buttons call `setState(_load)` where `_load()`
  genuinely **reassigns** the future. Not a no-op button.
- **Constraints** — `pubspec.yaml` gained **no new runtime dependency**. The only change is an
  `assets:` block. `flutter analyze` is clean and `flutter test` is 78/78.

Two defects survive that the green suite cannot see, and both were reproduced with executable
probes rather than inferred:

1. **`RecordingService.dispose()` clears the pending-stop flag.** A `dispose()` landing in the
   arming window — the exact interleaving `PracticeScreen.dispose()` produces on a cold launch, and
   the one the 01-04 plan names as the reachable case — makes the resolving `start()` skip the
   finalize-and-discard and instead arm a live recorder plus a 60 s deadline *after* teardown.
   Probe result: `stopCount=0`, auto-stop `fired=1`. This is the T-04-01 ghost capture the plan
   declares "structurally impossible."
2. **`DatabaseHelper` memoizes a *failed* open forever.** This is a **regression**: the old
   `Database? _db` getter retried on the next call; `_dbFuture ??= _open()` never does. Probe
   result: the second read never re-attempts (`attempts=1`) and fails with the cached error. It
   makes the retry button 01-06 added a permanent no-op for the most likely cause of the error
   state it retries, and it turns a transient launch-time failure into every-save-fails-forever
   with the message "check your microphone permission."

Beyond those, the notable pattern is that the new test suite is strong on the paths the plans
anticipated and blind on the two adjacent ones (dispose-during-arming, throwing open) — which is
precisely where both criticals live. Two tests also cannot fail for the reason their names claim.

Judgement on the three pre-declared deviations: **all three are acceptable.** The single
`_showMessage` helper is better than two duplicated `mounted` guards and both message constants are
independently tested; the `audioPlayerService` seam is necessary and correctly defaulted; the
`Duration(seconds: 60 + 5)` workaround is the only const-legal spelling (see IN-02 for the residual
drift risk).

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: BLOCKER — `dispose()` during the arming window discards the pending stop, leaving the microphone live and a 60 s deadline armed after teardown

**File:** `lib/services/recording_service.dart:196-202` (with `:150-164`, `:184-194`); caller
`lib/screens/practice_screen.dart:62-67`

**Issue:** `dispose()` unconditionally clears the very flag the arming-window discard depends on:

```dart
Future<void> dispose() async {
  _autoStopTimer?.cancel();
  _autoStopTimer = null;
  _recording = false;
  _stopRequestedDuringStart = false;   // <-- destroys the pending stop
  await _backend.dispose();
}
```

`PracticeScreen.dispose()` (`practice_screen.dart:62-67`) chains exactly
`stop().catchError(...).whenComplete(recordingService.dispose)`. Trace it with a start still arming:

1. `start()` assigns `_startInFlight = _arm(path)` and awaits. Correct.
2. `stop()` sees `_startInFlight != null`, sets `_stopRequestedDuringStart = true`, returns `null`.
   Correct — the signal is recorded.
3. `.whenComplete` fires `dispose()` in the very next microtask, which sets
   `_stopRequestedDuringStart = false`. The recorded signal is destroyed.
4. `_arm` resolves. `start()` reads `_stopRequestedDuringStart` — now `false` — skips the
   finalize-and-discard block entirely, sets `_recording = true`, and arms
   `Timer(kMaxRecordingDuration, ...)`.

Net result: the backend is never stopped, the microphone stays live for up to 60 s behind a
torn-down screen, and when the deadline lands it calls `onAutoStop` → `PracticeState._onAutoStop()`
on a disposed state. This is the exact T-04-01 "microphone live while the interface says otherwise"
threat, and the exact `up-to-60s ghost capture` the 01-04 plan and SUMMARY both claim is
structurally impossible.

**Reproduced.** Driving the literal `PracticeScreen.dispose()` sequence against the real
`RecordingService` with a gated `FakeRecorderBackend`:

```
PROBE stopCount=0 calls=[hasPermission, start:/fake/a.m4a, dispose]
PROBE autoStop fired=1   (expected 0)
```

`stopCount=0` proves the recording was never finalized; `fired=1` proves a 60 s deadline was armed
after `dispose()` returned.

Reachability in Phase 1 is limited (`PracticeScreen` is `home:` and is only disposed on hot restart
or process teardown), but Phase 2 makes the practice screen pushable behind a Setup screen, at which
point every back-navigation during arming hits this.

**Fix:** `dispose()` must *strengthen* the pending stop, not erase it, and `start()` must refuse to
arm after disposal.

```dart
bool _disposed = false;

Future<void> dispose() async {
  _disposed = true;
  _autoStopTimer?.cancel();
  _autoStopTimer = null;
  _recording = false;
  // Deliberately NOT clearing _stopRequestedDuringStart: a stop recorded during
  // the arming window must still be honoured by the start() that is resolving,
  // or the microphone is left live behind a torn-down screen.
  await _backend.dispose();
}

// in start(), replacing the pending-stop check:
if (_stopRequestedDuringStart || _disposed) {
  _stopRequestedDuringStart = false;
  try { await _backend.stop(); } catch (_) {}
  return;
}
```

Also guard the entry: `if (_disposed) throw StateError('RecordingService used after dispose');`.
Add the probe above as a permanent test (see WR-09).

---

### CR-02: BLOCKER — a failed database open is memoized forever, so the new "Try again" buttons can never recover and every save fails for the process lifetime

**File:** `lib/db/database_helper.dart:60-74` (specifically `:63`)

**Issue:**

```dart
Future<Database>? _dbFuture;
Future<Database> get database => _dbFuture ??= _open();
```

If `_open()` rejects — `appDocumentsDir()` failing, `openDatabase()` hitting a locked or corrupt
file, disk pressure — the **rejected future is cached permanently**. Every subsequent call to
`database` returns the same already-failed future without re-attempting anything. There is no path
back: nothing calls `close()` (which is the only code that clears `_dbFuture`) outside tests.

This is a **regression introduced by this run**. The code it replaced memoized the resolved value
(`Database? _db`), so a failed open left `_db == null` and the *next* call retried. Fixing the
double-open traded a leaked handle for a permanent-failure latch.

Two concrete consequences, both of which defeat work this same run performed:

1. **The gap-4 retry affordance is a lie for its most likely trigger.** `_HistoryError`'s
   "Try again" calls `setState(_load)` → `listSessions()` → `await database` → the cached rejection.
   The button re-renders the same error forever. Gap 4 asked for "a distinct error state *with a
   retry affordance*"; the affordance exists and cannot work.
2. **Silent, permanent data loss for the whole session.** `_bootstrap()` swallows the sweep's
   failure (`practice_screen.dart:48-51`) and proceeds to arm recording. Every
   `insertAnsweredSession()` then hits the cached rejection, lands in `stopRecording()`'s catch
   (`practice_state.dart:242`), and shows `kRecordingErrorMessage` — "Recording failed — check your
   microphone permission and try again." The user is told to fix a microphone permission, records
   answer after answer, and nothing is ever saved. That is the precise failure mode
   PERSIST-01/PERSIST-02 exist to exclude.

**Reproduced.** With `documentsDirProvider` failing only its first call (a transient cause that is
gone by the retry):

```
PROBE docsDirResolutionAttempts=1  secondError=Bad state: transient: cannot resolve docs dir
```

`attempts=1` proves the second read never even re-tried the open.

**Fix:** memoize the future, but drop the memo when it fails.

```dart
Future<Database> get database => _dbFuture ??= _openOrForgetOnFailure();

Future<Database> _openOrForgetOnFailure() async {
  try {
    return await _open();
  } catch (_) {
    // A failed open must NEVER be cached: the retry affordances in
    // HistoryScreen / SessionDetailScreen depend on the next call re-attempting.
    _dbFuture = null;
    rethrow;
  }
}
```

The `??=` still assigns before `_open()`'s first `await` can yield, so the double-open fix this
run made is fully preserved. Add the regression test in WR-10.

---

## Warnings

### WR-01: WARNING — a disposal between the recorder finalizing and the DB write silently discards a completed answer

**File:** `lib/state/practice_state.dart:222`

**Issue:** `stopRecording()` returns early at `if (_disposed) return;` **after**
`recordingService.stop()` has already finalized the file on disk but **before**
`insertAnsweredSession()`. The `.m4a` exists and contains the user's answer; no row references it;
the next launch's `pruneOrphanRecordings()` deletes it. This directly violates the 01-04 plan's own
prohibition: *"An answer the user has already spoken and finished must never be silently
discarded."* The two later `_disposed` checks (`:262`, `:274`) are correctly placed — this one is
on the wrong side of the commit.

**Fix:** once a finalized path exists, the save is unconditional; only the notification and the
replay/re-arm depend on liveness.

```dart
// delete the `if (_disposed) return;` at :222 — the save below is the crash-safety contract
if (finalizedPath == null) { ... }
...
try { await databaseHelper.insertAnsweredSession(...); } catch (...) { ... }
if (_disposed) return;   // safe: the answer is committed
```

---

### WR-02: WARNING — `awaitCompletion` leaks a broadcast stream subscription on every timeout

**File:** `lib/services/audio_player_service.dart:91-94`

**Issue:** `Future.timeout` bounds the *wait*; it does not cancel the underlying operation. The
subscription created by `_backend.onComplete.first` stays attached after the timeout resolves, and
is released only when the stream closes — i.e. when the player is disposed at screen teardown. In
the practice loop, which runs continuously, that is one permanently-attached listener on
`audioplayers`' `onPlayerComplete` per timed-out replay, accumulating for the app's lifetime.

The subscription *is* correctly released on the happy path (`Stream.first` cancels on its first
event) and errors are absorbed by the `.catchError` — so this is the timeout path only, which is
exactly the path the fix was written for.

**Fix:** own the subscription explicitly and cancel it on every exit.

```dart
final completer = Completer<void>();
final StreamSubscription<void> sub = _backend.onComplete.listen(
  (_) { if (!completer.isCompleted) completer.complete(); },
  onError: (Object _) { if (!completer.isCompleted) completer.complete(); },
  onDone: () { if (!completer.isCompleted) completer.complete(); },
);
try {
  await _backend.play(absoluteFilePath);
  await completer.future.timeout(kReplayCompletionTimeout, onTimeout: () {});
} finally {
  await sub.cancel();   // timeout, completion, or throw — all release it
}
```

---

### WR-03: WARNING — `_play`'s "a tap can never be a silent no-op" contract still has two unguarded awaits

**File:** `lib/screens/session_detail_screen.dart:100-105`, invoked via `unawaited` at `:162`

**Issue:** The `try` only wraps `_audioPlayerService.play(...)`. Two earlier awaits are bare:

- `await toAbsolutePath(answer.audioPath)` (`:100`) resolves through `appDocumentsDir()`, a
  `path_provider` platform-channel call that can throw (`MissingPluginException`, platform error).
- `await File(absolutePath).exists()` (`:102`) can throw on an I/O-level failure, not just return
  `false`.

Either throw escapes `_play`, and `onTap: () => unawaited(_play(answer))` attaches no error handler
— so the tap produces silence and an unhandled async error. That is the exact WR-06 failure 01-06
set out to close, on a narrower input.

**Fix:** widen the guard to the whole body.

```dart
Future<void> _play(QuestionAnswer answer) async {
  try { await _audioPlayerService.stop(); } catch (_) {}
  try {
    final String absolutePath = await toAbsolutePath(answer.audioPath);
    if (!await File(absolutePath).exists()) {
      _showMessage(kRecordingMissingMessage);
      return;
    }
    await _audioPlayerService.play(absolutePath);
  } catch (_) {
    _showMessage(kRecordingPlaybackFailedMessage);
  }
}
```

---

### WR-04: WARNING — `_startNewQuestion()`'s blanket `catch (_)` swallows the new `StateError`, which can leave the microphone live behind an error banner

**File:** `lib/state/practice_state.dart:144-160`

**Issue:** 01-04 deliberately made `RecordingService.start()` **throw** a `StateError` while a
recording is active "so a caller can never believe it armed a path the recorder was never given"
(T-04-03). But the only caller catches it with a bare `catch (_)` that does nothing except clear
`_currentRelativePath` and show the error banner. The previous recording is still live with its 60 s
deadline armed; when the deadline lands, `_onAutoStop()` sees `phase != recording`, calls
`recordingService.stop()` and **throws the finalized path away**. The user's answer is captured and
silently discarded, and the mic ran for up to a minute behind an error banner.

Confirmed not reachable through Phase 1's UI today: `onStart` is only wired to the `idle` control
(unreachable — see WR-05) and `onRetry` only renders in `error`, and no path reaches either while
`RecordingService._recording` is true. But the `StateError` was introduced *precisely* so a caller
could react to it, and Phase 2 adds pause/resume plus a countdown to this exact state machine.

**Fix:** distinguish it, rather than treating "a recorder is already running" as "the microphone is
unavailable".

```dart
} on StateError catch (error, stack) {
  // The recorder is still live; finalize it before parking in error, or the mic
  // keeps capturing behind the banner.
  debugPrint('EnglishReflex: start() on a live recorder: $error');
  FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
  try { await recordingService.stop(); } catch (_) {}
  _currentRelativePath = null;
  _fail();
} catch (_) {
  _currentRelativePath = null;
  _fail();
}
```

---

### WR-05: WARNING — `PracticePhase.idle` is now unreachable, so the recovery affordance the verification gap asked for can never render

**File:** `lib/state/practice_state.dart:19,60`; `lib/widgets/phase_control.dart:67-80`;
`lib/screens/practice_screen.dart:143-144`

**Issue:** `grep -rn "PracticePhase.idle" lib/` finds **zero assignments**. The constructor
initialises to `arming` (`:60`), and every failure path that previously set `idle` now calls
`_fail()` → `error`. `PracticePhase.idle` is a dead enum member.

Consequences worth triaging rather than fixing blindly:

- The verification gap's bullet — *"Give `PracticePhase.idle` a recoverable affordance (a
  Start/Try-again control) instead of a controlless screen"* — is satisfied on paper by a control
  the app can never display.
- `PhaseControl.onStart` and `PracticeScreen`'s `onStart: () => unawaited(_state.startNewQuestion())`
  are dead code, and `phase_control_test.dart:55-59,95-98` assert behaviour of an unreachable state.
- The exhaustive totality test now reports full coverage of a state space one member larger than the
  reachable one, which mildly overstates what it proves.

This is not a bug — the loop is genuinely recoverable via `error` — but it should be a conscious
decision, not an accident.

**Fix:** either delete `PracticePhase.idle` (and its key, control, callback and two tests), or add
an assertion documenting that it is a reserved future state and mark the control
`@visibleForTesting`. Deleting is the smaller footprint and matches the project's minimal-code
constraint.

---

### WR-06: WARNING — the "same millisecond" collision test cannot fail for the reason it names

**File:** `test/state/practice_state_test.dart:241-250`

**Issue:**

```dart
await state.startNewQuestion();
final firstPath = recordingService.lastRequestedPath;
await state.stopRecording();          // includes a full sqflite transaction
final secondPath = recordingService.lastRequestedPath;
expect(secondPath, isNot(firstPath));
```

The two starts are separated by a real-clock `stopRecording()` — a recorder stop, an sqflite
transaction and a replay — so their `millisecondsSinceEpoch` prefixes differ in practice every run.
The assertion therefore passes on the timestamp alone: **delete the `_${_random.nextInt(1 << 20)}`
suffix from `practice_state.dart:140-141` and this test still passes.** It is listed in
`01-04-SUMMARY.md` as verification for coverage item D7 and for the `PERSIST-01/adjacency` must-have
truth, neither of which it actually establishes.

**Fix:** assert the property, not the outcome — the name must carry entropy beyond the timestamp.

```dart
final base = p.basenameWithoutExtension(recordingService.lastRequestedPath!);
expect(base, matches(RegExp(r'^\d+_\d+$')),
    reason: 'the file name must carry entropy beyond the millisecond timestamp');
```

---

### WR-07: WARNING — the typography suite's strongest assertion is silently vacuous under any reordering, and a green run is not evidence the asset is bundled

**File:** `test/theme/typography_test.dart:52-58`

**Issue:** The file honestly documents three ways its primary guard degrades into a
guaranteed pass (`:29-49`): any `pump` or intervening `await` between the two statements, any
earlier test resolving the family into the process-global `_loadedFonts`, and the requirement that
the theme-building test run last. All three are enforced only by declaration order and a comment.
`flutter_test` honours declaration order today, but nothing fails if a future edit moves a test —
the guard just starts passing unconditionally, which is the same invisible-degradation class as the
original Gap 2.

Compounding it, the 01-05 executor's own finding stands: `flutter test` reuses
`build/unit_test_assets/` and does **not** invalidate it when an asset is added or removed. A green
`flutter test` on a machine with a stale bundle is not evidence the font ships. The negative control
the executor ran (delete font → `rm -rf build/unit_test_assets` → both guards fail) was correct and
valuable, but it is a one-time manual act, not a standing property of the suite.

**Fix:** remove the ordering dependency so the guard is self-contained. `google_fonts` exposes a
cache reset (`clearCache()` in `google_fonts_base.dart:27`); if it is reachable from the public
surface, call it at the top of the load test. Otherwise merge the two order-dependent tests into a
single test so the order cannot be broken by moving one, and add the
`rm -rf build/unit_test_assets` step to whatever CI command runs `flutter test`.

---

### WR-08: WARNING — `SessionDetailScreen` disposes an `AudioPlayerService` it does not own

**File:** `lib/screens/session_detail_screen.dart:63,82`

**Issue:** `_audioPlayerService = widget.audioPlayerService ?? AudioPlayerService();` then
`dispose()` tears it down unconditionally. When the service is injected, the screen destroys an
object whose lifetime belongs to the caller. Harmless today — production passes nothing, and each
test builds a fresh one — but the seam's whole purpose is to let a caller supply a service, and the
obvious next caller (a Phase 2 screen sharing one player) gets its player killed on the first back
navigation.

**Fix:** only dispose what the screen created.

```dart
late final bool _ownsPlayer;
...
_ownsPlayer = widget.audioPlayerService == null;
_audioPlayerService = widget.audioPlayerService ?? AudioPlayerService();
...
void dispose() {
  if (_ownsPlayer) unawaited(_audioPlayerService.dispose());
  super.dispose();
}
```

---

### WR-09: WARNING — no test disposes during the arming window, which is why CR-01 survives a 78-green suite

**File:** `test/services/recording_service_test.dart:239-251`

**Issue:** The suite covers both halves of the arming window thoroughly (`:107-175`) and covers
`dispose()` (`:239-251`) — but only the easy composition: `dispose()` is always called *after*
`start()` has fully resolved. The one interleaving that matters, `stop()` then `dispose()` while
`start()` is still in flight, is untested, and it is the literal sequence
`PracticeScreen.dispose()` emits. The two arming-window tests both `await arming` before disposing,
which is precisely the ordering that hides CR-01.

**Fix:** add the CR-01 probe verbatim as a permanent test:

```dart
testWidgets('a dispose landing in the arming window still finalizes and '
    'discards — the mic is never left live behind a torn-down screen',
    (tester) async {
  // ... gate startGate, call start(), then:
  unawaited(service.stop().catchError((Object _) => null)
      .whenComplete(service.dispose));
  await tester.pump();
  gate.complete();
  await arming;
  expect(backend.stopCount, 1);
  await tester.pump(kMaxRecordingDuration + const Duration(seconds: 1));
  expect(fired, 0);
});
```

---

### WR-10: WARNING — no test exercises a *failing* database open, which is why CR-02 survives

**File:** `test/db/database_helper_test.dart` (new `database (lazy open)` group);
`test/screens/history_screen_test.dart:12-20`

**Issue:** The new group covers the happy double-open, `close()`-then-reopen, and `close()` before
any open — every case where `_open()` succeeds. No test makes `_open()` throw, so the
permanent-failure latch is invisible.

`history_screen_test.dart` looks like it covers recovery, but `FakeHistoryDatabaseHelper` overrides
`listSessions()` wholesale, so the retry test never reaches the memoized getter at all. It proves
the *widget* re-issues the query (which it does, correctly) — not that the query can ever succeed
again. The two layers' tests together give the impression of end-to-end retry coverage that neither
provides.

**Fix:** add the CR-02 probe:

```dart
test('a failed open is not cached — the next caller retries', () async {
  var attempts = 0;
  documentsDirProvider = () async {
    attempts++;
    if (attempts == 1) throw StateError('transient');
    return tempDir;
  };
  final helper = DatabaseHelper();
  await expectLater(helper.listSessions(), throwsA(isA<StateError>()));
  expect(await helper.listSessions(), isEmpty);   // recovers
  expect(attempts, 2);
});
```

---

### WR-11: WARNING — an unrelated tooling commit changed the iOS bundle identifier inside this phase's diff

**File:** `ios/Runner.xcodeproj/project.pbxproj` (three build configurations), `ios/Runner/Info.plist`

**Issue:** Commit `a07ae59` ("Add loop host contract generator and allowlist ratchet utilities")
sits inside `cd5cdae..HEAD` and changes `PRODUCT_BUNDLE_IDENTIFIER` from
`com.englishreflex.englishreflex` to `com.haotran.englishreflex` in Debug, Release and Profile, plus
`objectVersion` 54 → 60 and a reordering of `NSMicrophoneUsageDescription` in `Info.plist`. No plan
in this run declares `ios/` as a modified file; 01-04, 01-05 and 01-06 all state "no new
Android/iOS permission," and 01-05 explicitly verified the *Android* manifest was byte-for-byte
unchanged — the iOS side was never checked.

Why it matters beyond bookkeeping: a bundle-identifier change makes the build a **different app** on
device. The previous install's app-container — the SQLite file and every recorded `.m4a` — is not
carried over. SC-4 ("force-kill and relaunch still shows every already-recorded answer") and any
prior on-device UAT were performed against a container that a rebuilt app no longer opens.

**Fix:** confirm the rename is intentional (it looks like a legitimate signing-identity fix), record
it in the phase artifacts rather than leaving it inside an unrelated tooling commit, and re-run the
SC-4 force-kill UAT after it. The `Info.plist` key reordering is cosmetic and safe — the key is
present and unchanged.

---

## Info

### IN-01: `kPhaseControlKeys[phase]` is looked up nullably at the use site
**File:** `lib/widgets/phase_control.dart:69,85,95,124,133,139`
**Issue:** Each case does `key: kPhaseControlKeys[PracticePhase.x]` (type `Key?`). A removed map
entry yields a silently *unkeyed* widget rather than an error. The totality test catches it, but the
invariant is not expressed where it is relied on.
**Fix:** use `kPhaseControlKeys[PracticePhase.x]!` so the map's totality is asserted at the use site
too.

### IN-02: `kReplayCompletionTimeout` cannot drift-check against `kMaxRecordingDuration`
**File:** `lib/services/audio_player_service.dart:9-10`
**Issue:** The `Duration(seconds: 60 + 5)` workaround is correct and correctly documented (Dart has
no const `Duration + Duration`), but the `60` is now a hand-copied literal. Changing
`kMaxRecordingDuration` in Phase 2 — which the comment at `recording_service.dart:5` says is coming
("Configurable `d` arrives in Phase 2") — leaves the ceiling silently stale.
**Fix:** a one-line test: `expect(kReplayCompletionTimeout, greaterThan(kMaxRecordingDuration));`

### IN-03: `practice_state_test.dart` never restores the global `documentsDirProvider`
**File:** `test/state/practice_state_test.dart:126` vs `test/screens/session_detail_screen_test.dart:198`
**Issue:** The detail-screen test correctly restores the global in `tearDown`; the state test does
not. Harmless while each file runs in its own isolate, but the two files disagree about the
convention.
**Fix:** mirror the restore in `tearDown`.

### IN-04: `FlutterError.reportError` on the save-failure path is a live landmine for `test/state/`
**File:** `lib/state/practice_state.dart:251-258`
**Issue:** Already documented by the 01-04 executor and worth carrying: adding a single `testWidgets`
case to `practice_state_test.dart` initialises the binding, at which point `FlutterError.onError`
fails the "a save failure shows the same copy" test. The diagnostic itself is the right call
(WR-07's diagnosable half from the prior review).
**Fix:** either keep that file `test()`-only with a comment at the top, or route diagnostics through
an overridable sink.

### IN-05: prior finding IN-01 (local-time timestamps) is untouched and still open
**File:** `lib/db/database_helper.dart:126`
**Issue:** `DateTime.now().toIso8601String()` still writes offset-less local time; `date_format.dart`'s
`.toLocal()` remains a no-op. Correctly out of scope for a gap-closure run — noting it so it is not
lost when the prior review is replaced by this one. Prior IN-03/IN-04/IN-05 and WR-07/WR-08/WR-10
likewise remain open by explicit, documented deferral.

### IN-06: `RecordingService` has no use-after-dispose guard
**File:** `lib/services/recording_service.dart:128-137,184,196`
**Issue:** After `dispose()`, `start()` and `stop()` remain callable and will drive a disposed
backend. The `_disposed` flag proposed in CR-01 closes this at the same time.
**Fix:** covered by CR-01's fix.

---

_Reviewed: 2026-08-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep — findings CR-01 and CR-02 reproduced with executable probes against the real classes_
_Baseline at review time: `flutter analyze` clean, `flutter test` 78/78 passing_
_This review is ADVISORY — it does not block the phase._
