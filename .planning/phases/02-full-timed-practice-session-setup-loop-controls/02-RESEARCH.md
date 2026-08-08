# Phase 2: Full Timed Practice Session (Setup, Loop & Controls) - Research

**Researched:** 2026-08-08
**Domain:** Flutter timed-state-machine UI + `record` pause/resume + app-lifecycle/audio-interruption handling + host-deterministic timer testing
**Confidence:** HIGH (every load-bearing API claim was read from the exact package version this project resolves to, in `~/.pub-cache`, or from the Flutter 3.44.6 SDK source on this machine)

**Verification method note.** Nothing in the Standard Stack / API sections below comes from
training memory or a web search. Every API signature, default value, enum member and native
behaviour was read this session from the resolved artefacts on disk:
`pubspec.lock` → `~/.pub-cache/hosted/pub.dev/<pkg>-<version>/…` and `/Applications/flutter/packages/…`.
Line numbers and verbatim quotes are given so the planner and plan-checker can re-open the same file.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Setup screen — inputs, defaults & validation

- **D-16:** The three numeric settings each render as a **large numeric readout above a slider** — no keyboard, one widget per setting, full range reachable by drag, and big enough to satisfy UI-01/D-14. Ranges and defaults: `question_count` 1–100 (default **10**), `t` 3–30 s (default **5**), `d` 10–120 s (default **60** — matches Phase 1's `kMaxRecordingDuration`, D-09). *Alternatives rejected: preset chips + custom text field; −/+ steppers (too many taps to cross a 1–100 range).*
- **D-17:** CEFR level is a **single-select row of six rounded chips (A1 A2 B1 B2 C1 C2)** that wraps to two lines. Default **B1**. *Alternatives rejected: dropdown, segmented control — both fight the playful/large-target direction (D-14).*
- **D-18:** Setup settings are **not remembered between sessions** — every visit starts from the fixed defaults in D-16/D-17. Rationale: keeps Phase 2 free of any new persistence surface and any schema-version bump, honouring the "leanest code" constraint. *Alternative rejected for now: a one-row settings table (schema 1→2). If re-entering five fields every session becomes annoying in real use, this is the cheapest thing to add later — it is additive and does not disturb the frozen `sessions`/`question_answers` schema.*
- **D-19:** Setup shows a **real, working topic-checkbox section backed by a hardcoded placeholder subject list** (~5 subjects derived from the expanded placeholder question bank). SETUP-07 is genuinely enforced in Phase 2 — **Start is disabled until at least one topic is checked** — and Phase 3 replaces only the data source, not the widget or the validation. *Alternatives rejected: hiding topics until Phase 3 (would leave SETUP-07 unimplemented and untestable); showing always-checked/disabled topics (makes the Start gate a no-op).*

#### Timed loop mechanics

- **D-20 (resolves the STATE.md arming-window blocker):** The per-question `t` countdown runs **to zero, and only then does the recorder arm**. The existing Phase 1 `PracticePhase.arming` state and its "Getting ready…" copy cover that window, and the `d` deadline starts only once the microphone is genuinely live. Rationale: preserves Phase 1's honesty contract (never show a STOP button / listening mascot while the mic is cold), keeps countdown audio out of the answer file, and reuses already-tested code. *Alternatives rejected: pre-arming during the final ~1 s of the countdown (eliminates the gap but puts silent pre-roll in every file); arming at countdown start (records the entire countdown).*
- **D-21:** A **remaining-seconds readout of `d` is shown while recording**, beneath the STOP button, so the user can pace an answer. This deliberately supersedes Phase 1's D-04 ("no elapsed timer during recording"), which explicitly scoped timer/countdown UI to Phase 2. The STOP button stays the visually dominant element — the timer is secondary, not a second focal point.
- **D-22:** The two 3-second countdowns (LOOP-01 at session start, LOOP-07 between questions) render as a **full-screen "3 · 2 · 1" with the mascot and the question hidden** — visually distinct from the `t` countdown, which always shows the question text. The two countdowns must never be confusable: one means "get ready to read", the other means "read this now, you speak at 0". LOOP-07's 3-second countdown starts *after* auto-replay finishes when `r` is on.
- **D-23:** The placeholder question list is **expanded to ~20 prompts**, and if `question_count` still exceeds the number of available questions the loop **cycles through the bank again** rather than capping the session. This keeps LOOP-08 literally true for any configured count and makes long sessions testable before Firestore exists. Question order is **sequential bank order, not shuffled** — LOOP-V2-01 is deferred to v2. *Alternative rejected: capping the session at the available count (would silently contradict the configured `question_count` and make Phase 2's loop untestable at realistic lengths against a small placeholder bank).*

#### Pause, Stop & session lifecycle

- **D-24:** Pause is a **true pause**, available at every moment of a session including mid-recording (CTRL-01/CTRL-04). It uses `record`'s `pause()`/`resume()` for the microphone and freezes the `d` deadline and any running countdown; Resume continues from exactly where it stopped rather than restarting the current step. This requires extending `RecordingService` with pause/resume and converting the fixed `Timer` deadline into a pausable one. *Alternatives rejected: disabling Pause while recording (violates CTRL-01's "at all times"); pause-stops-and-saves (loses the half-finished answer's continuity).*
- **D-25:** The Stop confirmation dialog (CTRL-03) **auto-pauses the session while it is open** and resumes on cancel. Without this, the `d` deadline fires and the answer auto-saves behind the modal while the user is still deciding.
- **D-26:** The `sessions` row is created **lazily, on the first captured answer** — not at Start. This preserves Phase 1's D-08 guarantee ("nothing captured ⇒ no trace") and keeps History free of empty session rows, so no History-side filtering is needed. Each subsequent answer is inserted in its **own** transaction against that session id, keeping PERSIST-01's per-question durability. A session abandoned before any answer writes nothing at all. *Alternative rejected: creating the row up front and filtering empty sessions out of the History query (two places to keep in sync, and a crash between Start and the first answer would leave a permanent orphan row).*
- **D-27:** When a session ends — completed via LOOP-08 *or* stopped early via CTRL-03 — the app shows a short **completion screen**: "Nice work! N answers recorded", with *Back to setup* and *View this session*. This is a state of the practice screen, not a fourth route, so UI-03 (exactly 3 core screens) still holds. A session stopped before its first answer returns straight to Setup, since there is nothing to view (see D-26).

#### Navigation & interruptions

- **D-28:** **Setup becomes the app's home screen.** Start pushes the Practice screen; History is reached from a single app-bar icon on Setup, exactly as it is reached from Practice today. Push-based navigation only — no tab bar, no drawer (UI-03). Phase 1's `PracticeScreen` therefore stops being `home:` and starts taking a session configuration as a constructor argument.
- **D-29:** **The user cannot navigate away from an active session.** The session app bar carries only Pause/Resume and Stop (CTRL-01/02) — no History icon. System Back / the back gesture is intercepted with `PopScope` and routed into the same Stop confirmation dialog (D-25), so there is exactly one way to end a session early and it always confirms.
- **D-30:** **Add `wakelock_plus` and hold a wakelock for the duration of an active session**, releasing it when the session ends or the screen is disposed. The default OS screen timeout is frequently shorter than one `t`+`d` cycle, so without this the screen locks while the user is mid-answer — a real break in the core loop, not a nicety. This is a deliberate, justified exception to the minimize-packages constraint: one small, actively maintained package, used at exactly one call site. *Alternative rejected: deferring it (ships a loop that visibly breaks in normal use).*
- **D-31 (resolves the STATE.md iOS-interruption blocker):** An interruption — incoming phone call, or the app being backgrounded — is **treated as an auto-pause**. If a recording was live, it is finalized and saved first (Phase 1's write ordering is unchanged: finalize file → one transaction → only then anything else), and the session parks in the paused state. Resuming is always an explicit user tap; the app never silently resumes recording after an interruption. A **real-device call-interruption test is a required UAT item for this phase** — the `record` package's `AudioInterruptionMode` behaviour on iOS has a documented `-10868` rough edge that cannot be proven by host tests. *Alternatives rejected: discarding the in-flight recording (throws away a real answer the user already gave); recording through the interruption (not reliably possible on iOS).*

### Claude's Discretion

- Exact copy for the completion screen, the Stop confirmation dialog and the countdown screens (within the established warm/playful voice), exact slider tick behaviour and label formatting, the specific ~20 placeholder prompts and the ~5 placeholder subject names, and how the pausable deadline is implemented internally (stopwatch + rescheduled `Timer` vs. periodic tick) are all left to implementation.
- Whether the timed loop lives in an extended `PracticeState` or a new session-scoped `ChangeNotifier` alongside it is an implementation call — the constraint is that the Phase 1 record→save→replay sequence and its guard/ordering comments survive intact, and that services stay injectable through the same constructor seams.

### Deferred Ideas (OUT OF SCOPE)

- **Persisting last-used Setup settings** (D-18) — cheapest future addition if re-entering five fields per session becomes annoying; additive table, no disturbance to the frozen schema.
- **Pre-arming the recorder during the last second of the `t` countdown** (D-20 alternative) — revisit only if real-device use shows the post-countdown arming gap is perceptible.
- **Shuffled question order** (LOOP-V2-01) — v2, per REQUIREMENTS.md.
- **Real topics and the Firestore-backed bank** (SETUP-01, BANK-01..03) — Phase 3; Phase 2 deliberately builds the seam for it.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SETUP-02 | Select a CEFR level (A1–C2) | Pure local widget state; `ChoiceChip` in a `Wrap` per UI-SPEC. No API risk. The level is **carried into the session config but not yet used to filter** — the bank is placeholder until Phase 3 (D-19). Recommend `SessionConfig.level` exists from day one so Phase 3's Firestore query has a field to read. |
| SETUP-03 | `question_count` 1–100 | `Slider(min: 1, max: 100, divisions: 99)`. Feeds LOOP-08's terminating condition and the "Question {k} of {N}" title. |
| SETUP-04 | Pre-record countdown `t` | `Slider(min: 3, max: 30, divisions: 27)`. Consumed by `PausableCountdown` (§ Q2) in the `reading` phase. |
| SETUP-05 | Max recording duration `d` | `Slider(min: 10, max: 120, divisions: 110)`. **`d` must replace the `const kMaxRecordingDuration` deadline** in `RecordingService` (`lib/services/recording_service.dart:186`) *and* the derived `kReplayCompletionTimeout` (`lib/services/audio_player_service.dart:9-10`). See § Q3. |
| SETUP-06 | Auto-replay toggle `r` | `SwitchListTile`. Phase 1 hard-coded "always replay" at `lib/state/practice_state.dart:279-288`; Phase 2 makes that whole block conditional on `r`. |
| SETUP-07 | Start blocked with 0 topics | `FilledButton(onPressed: selected.isEmpty ? null : _start)`. Genuinely enforced (D-19). |
| LOOP-01 | 3-s countdown at session start | `PausableCountdown(3)` in a new `getReady` phase. § Q2. |
| LOOP-02 | Live `t`-second countdown per question | `PausableCountdown(t)` in a new `reading` phase, then D-20's existing `arming` window. § Q2. |
| LOOP-07 | 3-s countdown between questions | Same `getReady` phase, entered **after** replay completes when `r` is on. § Q2/Q3. |
| LOOP-08 | Session completes after `question_count` answers | Counter incremented only on a **committed** answer (so it equals the row count — matches D-27's "N answers recorded"). § Q7. |
| CTRL-01 | Pause/Resume in app bar at all times | `record` `pause()`/`resume()` verified present (§ Q1) + `PausableCountdown.pause()` + `AudioPlayer.pause()` (§ Q3). Disabled-not-hidden in `arming`/`saving`/`error`/`idle` per UI-SPEC. |
| CTRL-02 | Stop in app bar at all times | Plain `IconButton`. No API risk. |
| CTRL-03 | Stop shows a confirmation dialog | `showDialog` + `AlertDialog`, `barrierDismissible: true`, `null` treated as cancel. Reached from **both** the app-bar Stop and `PopScope` (§ Q6). |
| CTRL-04 | Pause freezes countdown/recording state | The hard one. § Q1 (recorder), § Q2 (countdowns), § Q3 (replay). **Critical finding:** `record`'s `pause()` silently no-ops in the wrong state on both platforms — see Pitfall 1. |
</phase_requirements>

---

## Summary

This phase adds no genuinely novel technology. Every capability it needs is already present in the
exact package versions this project resolves to, and the two that looked risky at discuss time —
`record` pause/resume and iOS interruption handling — turned out to be *fully supported and already
correctly configured by the code Phase 1 wrote*. `_RecordPackageBackend.start()` passes
`const RecordConfig()` (`lib/services/recording_service.dart:49`), and `RecordConfig`'s default for
`audioInterruption` is `AudioInterruptionMode.pause`, documented verbatim as
*"Pauses automatically, resumes manually the recording."* D-31's native half therefore needs **zero
configuration change**. What is missing is the *Dart-side awareness* of that native pause: it is only
observable through `AudioRecorder.onStateChanged()`, which the app does not subscribe to.

The real risks in this phase are three, and none of them are package-selection risks:

1. **Silent no-op pauses.** Both `record`'s `pause()` and its `resume()` are implemented as guarded
   early-returns on iOS (`guard m_state == .record else { return }`) and Android
   (`if (isRecording())`). A pause that lands in the wrong state **does not throw** — it returns
   normally having done nothing. The app therefore cannot infer "the microphone is paused" from "the
   call did not throw," which is precisely the honesty failure the UI-SPEC flags at E10/error.
2. **Timer testability.** Phase 1's whole quality story rests on "a test with a fake never touches a
   platform channel," and `flutter_test`'s binding gives that for free for `Timer`s — but **not** for
   `Stopwatch`, and **not** in a plain `test()`. The one existing test file for the loop
   (`test/state/practice_state_test.dart`) deliberately avoids the widget binding, so Phase 2's
   timer-driven tests cannot simply be appended to it.
3. **Where the paused-time bookkeeping lives.** Four separate clocks (two 3-s countdowns, `t`, `d`)
   plus a replay completion timeout must all freeze together. Implementing them four different ways
   is how this phase gets a "paused for 90 s, then the answer auto-saved behind the dialog" bug.

**Primary recommendation:** Build exactly one ~60-line `PausableCountdown` in
`lib/utils/pausable_countdown.dart` (a `Timer.periodic(1s)` that decrements an integer), use it for
all four countdowns *and* the replay timeout, extend the two existing backend seams with
`pause()`/`resume()` plus a recorder state stream, add `wakelock_plus ^1.7.0` behind a third seam of
the same shape, and put every timer-driven test in **new** `testWidgets` files. Add no other package.

---

## Architectural Responsibility Map

This is a single-process on-device Flutter app; the "tiers" are the app's own layers plus the OS.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Session configuration (SETUP-02..07) | Widget/local state (`SetupScreen`) | — | Not persisted (D-18); it exists only long enough to be handed to the practice screen as a constructor argument. No service, no DB. |
| Session config transport | Immutable value object (`SessionConfig`) | — | D-28 makes `PracticeScreen` take a config argument. A plain `@immutable class` with 5 fields keeps the widget constructor honest and gives Phase 3 a place to hang `topics`/`level`. |
| Loop sequencing (which phase, which question, when) | `ChangeNotifier` (`PracticeState` extended, or a session-scoped sibling) | — | Established Phase 1 pattern; no state-management package (CLAUDE.md "What NOT to Use"). |
| Countdown timing (LOOP-01/02/07, `d` readout) | `lib/utils/` pure-Dart utility | `ChangeNotifier` (owns instances) | Must be host-testable with no platform channel; a plain Dart class driven by `Timer` is exactly that. |
| Microphone lifecycle + pause/resume | `RecordingService` | `RecorderBackend` seam → `package:record` | Extending the existing seam is strictly cheaper than a new service and keeps the arming-window guarantees (`lib/services/recording_service.dart:58-80`) in one place. |
| Playback + pause/resume | `AudioPlayerService` | `AudioPlaybackBackend` seam → `package:audioplayers` | Same reasoning. |
| Durable per-answer write | `DatabaseHelper` → SQLite | — | Frozen schema (D-05); one **new** method, no migration. § Q7. |
| Screen-wake during a session | New `ScreenWakeController` seam → `wakelock_plus` | OS window flag / idle timer | Platform channel ⇒ must sit behind a seam or `flutter test` throws `MissingPluginException`. § Q4. |
| App background/foreground detection | `AppLifecycleListener` (Flutter SDK) | Practice screen `State` | Framework-level; owned by the `StatefulWidget` that also owns the wakelock and the recorder. |
| Audio interruption (call, focus loss) | OS → `record` native → `RecordState` stream | `RecorderBackend` seam | The OS owns the decision; the app only *observes* it. Do not try to detect calls yourself. § Q5. |
| Back-gesture interception | `PopScope` (Flutter SDK) | Practice screen build | § Q6. |

---

## Answers to the Phase's Eight Technical Questions

### Q1 — `record` ^7.1.1 pause / resume / isPaused

**Resolved version: `record 7.1.1`, `record_platform_interface 2.1.0`, `record_android 2.1.2`, `record_ios 2.1.1`** [VERIFIED: `pubspec.lock`, cross-checked against `~/.pub-cache/hosted/pub.dev/`]. `7.1.1` is also the latest published version (pub.dev API: `latest: 7.1.1, published: 2026-06-29`) [VERIFIED: pub.dev registry API].

**The API exists and is public.** From `~/.pub-cache/hosted/pub.dev/record-7.1.1/lib/src/record.dart:93-141`, verbatim:

```dart
  /// Pauses recording session.
  Future<void> pause() {
    return _safeCall(() {
      return _platform.pause(_recorderId);
    });
  }

  /// Resumes recording session after [pause].
  Future<void> resume() {
    return _safeCall(() {
      return _platform.resume(_recorderId);
    });
  }
```
```dart
  /// Listen to recorder states [RecordState].
  ///
  /// Provides pause, resume and stop states.
  ///
  /// Also, you can retrieve async errors from it by adding [Function? onError] callback to the subscription.
  Stream<RecordState> onStateChanged() =>
      _recordStateStream ?? _initStateStream();
```
```dart
  /// Checks if there's valid recording session.
  /// So if session is paused, this method will still return [true].
  Future<bool> isRecording() {
    return _safeCall(() => _platform.isRecording(_recorderId));
  }

  /// Checks if recording session is paused.
  Future<bool> isPaused() {
    return _safeCall(() => _platform.isPaused(_recorderId));
  }
```

The state enum is `enum RecordState { pause, record, stop }`
[VERIFIED: `record_platform_interface-2.1.0/lib/src/types/record_state.dart:2`, verbatim].

The package's own platform-parity matrix marks `pause/resume` supported on **Android, iOS, web,
Windows, macOS and linux** [VERIFIED: `record-7.1.1/README.md:21`].

**What it does to the output file: one continuous file, with the paused span excised.**

- **iOS** (`record_ios-2.1.1/ios/record_ios/Sources/record_ios/delegate/RecorderFileDelegate.swift:51-61`, verbatim):
  ```swift
  func pause() {
    guard let recorder = m_audioRecorder, recorder.isRecording else { return }
    recorder.pause()
    m_onPause()
  }

  func resume() throws {
    guard let recorder = m_audioRecorder else { return }
    recorder.record()
    m_onRecord()
  }
  ```
  `AVAudioRecorder.pause()` / `.record()` keeps the same destination URL and appends. No second file,
  no re-open, and `stop()` still returns the one path the service handed in.
- **Android**: the project's `const RecordConfig()` resolves to `AndroidRecordConfig(useLegacy: false)`
  [VERIFIED: `record_platform_interface-2.1.0/lib/src/types/android_record_config.dart:53-60` — `this.useLegacy = false`],
  so the **advanced** `AudioRecorder` path is used, not the legacy `MediaRecorder`. Its pause blocks
  the capture loop on a semaphore while leaving the encoder/muxer and output file open
  [VERIFIED: `record_android-2.1.2/…/recorder/AudioRecorder.kt:71-83` and `…/recorder/RecordThread.kt:45-56, 157-162`].

**Platform caveat you can safely ignore, and why.** The *legacy* Android path wraps
`MediaRecorder.pause()` in `if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)` and **silently does
nothing below API 24** [VERIFIED: `record_android-2.1.2/…/recorder/MediaRecorder.kt:85-95`]. This
project never takes that path (`useLegacy` stays `false`), and Flutter 3.44.6's default
`minSdkVersion` is 24 regardless [VERIFIED: `/Applications/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:26` — `val minSdkVersion: Int = 24`; `android/app/build.gradle.kts` uses `minSdk = flutter.minSdkVersion`]. **Do not set `useLegacy: true`.**

**Platform caveat you must NOT ignore — pause/resume fail silently in the wrong state.**
iOS guards on state and returns:
```swift
  func pause() {
    guard m_state == .record else { return }
    m_delegate?.pause()
  }

  func resume() throws {
    guard m_state == .pause else { return }
    try m_delegate?.resume()
  }
```
[VERIFIED: `record_ios-2.1.1/…/Recorder.swift:82-90`, verbatim]. Android is equivalent —
`fun pauseRecording() { if (isRecording()) { pauseState() } }`
[VERIFIED: `record_android-2.1.2/…/recorder/RecordThread.kt:45-49`].
**Consequence:** `await recorder.pause()` completing without throwing does **not** prove the
microphone stopped. See Pitfall 1 for the required mitigation.

**Interaction with a max-duration deadline.** `record` has **no built-in maximum duration** — the
60-second cap is entirely `RecordingService`'s own `Timer(kMaxRecordingDuration, …)`
(`lib/services/recording_service.dart:186`). Because pause excises the paused span from the audio,
the deadline **must** be paused in lock-step, or a 60-second `d` interrupted by a 30-second pause
would auto-stop after 30 seconds of actual speech. This is exactly what D-24 requires and is the
single most important behavioural coupling in the phase.

---

### Q2 — A pausable, host-testable countdown/deadline

**Recommendation: one class, `lib/utils/pausable_countdown.dart`, built on `Timer.periodic(const Duration(seconds: 1))` that decrements an integer. Use it for all four countdowns and for the replay timeout. Add no package.**

**Why `Timer` and not `Stopwatch` — this is a testability decision, not a taste one.**
`flutter_test`'s `AutomatedTestWidgetsFlutterBinding` runs the test body on a fake clock, so a real
`Timer` created inside `testWidgets` is a fake timer and `tester.pump(duration)` advances it. The
project already relies on this and documents it verbatim
(`test/services/recording_service_test.dart:60-68`):

> `// Every test runs inside `testWidgets` because flutter_test's`
> `// AutomatedTestWidgetsFlutterBinding already runs the body on a fake clock:`
> `// a real `Timer` created here is a fake timer and `tester.pump(duration)``
> `// advances it. No `fake_async` dependency is needed.`

`Stopwatch` gets no such treatment. `package:fake_async` 1.3.3 contains no reference to `Stopwatch`
at all [VERIFIED: `grep -rn "Stopwatch" ~/.pub-cache/hosted/pub.dev/fake_async-1.3.3/lib/` returns
nothing], and the only `Stopwatch` in `flutter_test`'s binding is `_TestSamplingClock`, an internal
gesture-sampling clock [VERIFIED: `/Applications/flutter/packages/flutter_test/lib/src/binding.dart:3233-3243`].
**A `Stopwatch` constructed in `lib/` runs on real wall time under `flutter test` and cannot be
advanced by `tester.pump()`.** A stopwatch-based deadline is therefore untestable on the host without
introducing a `clock`/time-provider seam — which is more code than the whole countdown class.

**Why `fakeAsync`/`FakeAsync` is the wrong answer here.** `fake_async 1.3.3` **is** present in
`pubspec.lock`, but as `dependency: transitive` (via `flutter_test`) [VERIFIED: `pubspec.lock`].
The project runs `flutter analyze` as its `build_command`, `analysis_options.yaml` includes
`package:flutter_lints/flutter.yaml`, and `flutter_lints 6.0.0` pulls in `lints 6.0.0` whose
`core.yaml:19` enables `depend_on_referenced_packages` [VERIFIED: `~/.pub-cache/hosted/pub.dev/lints-6.0.0/lib/core.yaml:19`].
Importing `package:fake_async` directly would fail the build gate unless `fake_async: ^1.3.3` is added
to `dev_dependencies`. `testWidgets` gives the identical fake clock for free and matches the file the
plan will be extending.

**Why periodic-decrement and not stopwatch + rescheduled `Timer`** (D-24/Claude's Discretion
explicitly leaves this open):

1. **The displayed number is the state.** The UI-SPEC needs an integer on screen for all four
   countdowns (128 px 3·2·1 glyph ×2, the ring's `Heading 24` numeral, and `"{M}:{SS} left"`). With
   decrement there is no derived value and no rounding-boundary flicker where the ring shows "5" for
   1.02 s and "4" for 0.98 s.
2. **Pause is `_timer?.cancel()`; resume is `_timer = Timer.periodic(...)`.** No elapsed-time
   arithmetic, therefore no partial-second loss or gain accumulating across many pause cycles — the
   exact class of bug that makes a 10-question session's `d` drift.
3. **One mechanism, one pause path, one test file.** A stopwatch deadline would still need a separate
   periodic tick for the readout, i.e. two clocks to freeze in step. Four countdowns × two clocks is
   how CTRL-04 regresses.
4. **Reversible.** If second-granularity ever proves insufficient, the class can gain an internal
   monotonic correction without changing a single call site.

**Accepted cost:** the deadline is quantised to whole seconds and inherits per-tick event-loop
latency. For a 10–120 s answer cap on a drill app this is immaterial, and it is *less* error-prone
than the alternative.

**Shape (the planner may rename; the obligations are the ticks, the pause and the terminal callback):**

```dart
// lib/utils/pausable_countdown.dart
import 'dart:async';

/// A whole-second countdown that can be frozen and resumed in place (D-24).
///
/// Deliberately built on `Timer.periodic`, NOT `Stopwatch`: flutter_test's
/// AutomatedTestWidgetsFlutterBinding runs `testWidgets` bodies on a fake clock
/// that advances real `Timer`s under `tester.pump(duration)` but does NOT fake
/// `Stopwatch`. A stopwatch-based deadline would be untestable on the host —
/// which would break the "a test with a fake never touches a platform channel,
/// and never waits on real time" invariant Phase 1 established.
class PausableCountdown {
  PausableCountdown({
    required int seconds,
    required this.onTick,
    required this.onElapsed,
  })  : assert(seconds > 0),
        _remaining = seconds;

  /// Called after every whole second, with the NEW remaining value (…, 2, 1, 0).
  final void Function(int remainingSeconds) onTick;

  /// Called exactly once, immediately after the tick that reaches zero.
  final void Function() onElapsed;

  int _remaining;
  Timer? _timer;
  bool _finished = false;

  int get remainingSeconds => _remaining;
  bool get isRunning => _timer != null;
  bool get isFinished => _finished;

  void start() => _arm();

  /// Freezes at the current whole second. Idempotent.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// Continues from exactly where [pause] stopped. Idempotent, and a no-op once
  /// the countdown has elapsed — so a resume racing the final tick can never
  /// re-arm a finished countdown.
  void resume() {
    if (_finished || _timer != null) return;
    _arm();
  }

  /// Terminal. A cancelled countdown never fires again, so a disposed screen
  /// can never be left with a pending timer (which the test binding fails on).
  void cancel() {
    _finished = true;
    pause();
  }

  void _arm() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remaining -= 1;
      onTick(_remaining);
      if (_remaining <= 0) {
        cancel();
        onElapsed();
      }
    });
  }
}
```

**Where each countdown comes from:**

| Phase | Source of `seconds` | On elapse |
|-------|---------------------|-----------|
| `getReady` (LOOP-01, session start) | literal `3` | → `reading` |
| `reading` (LOOP-02) | `config.thinkingSeconds` (`t`) | → `arming` (D-20: the recorder arms only now) |
| `recording` (D-21 readout **and** the `d` deadline) | `config.answerSeconds` (`d`) | → `stopRecording()` (replaces `Timer(kMaxRecordingDuration, …)`) |
| `replaying` completion timeout | `config.answerSeconds + 5` | → give up waiting, fall through (§ Q3) |
| `getReady` (LOOP-07, between questions) | literal `3` | → next question's `reading` |

Note this collapses the recording deadline and the D-21 readout into **one** object — the number
shown is the deadline, so they cannot disagree.

---

### Q3 — `audioplayers` pause/resume and reworking `kReplayCompletionTimeout`

**Resolved version: `audioplayers 6.8.1`** (also latest: pub.dev API `latest: 6.8.1, published: 2026-06-27`) [VERIFIED: `pubspec.lock` + pub.dev registry API].

**Pause/resume is supported and resumes in place.** From
`~/.pub-cache/hosted/pub.dev/audioplayers-6.8.1/lib/src/audioplayer.dart:235-278`, verbatim:

```dart
  /// Pauses the audio that is currently playing.
  ///
  /// If you call [resume] later, the audio will resume from the point that it
  /// has been paused.
  Future<void> pause() async {
    desiredState = PlayerState.paused;
    await creatingCompleter.future;
    if (desiredState == PlayerState.paused) {
      await _platform.pause(playerId);
      state = PlayerState.paused;
      await _positionUpdater?.stopAndUpdate();
    }
  }
```
```dart
  /// Resumes the audio that has been paused or stopped.
  Future<void> resume() async {
    desiredState = PlayerState.playing;
    await _resume();
  }
```

Note the documented behaviour of `resume()`: *"Resumes the audio that has been paused **or stopped**."*
`stop()`'s own doc says *"The position is going to be reset and you will no longer be able to resume
from the last point"* (line 253-254). So a `resume()` issued after playback has already completed
restarts the file from zero. **Guard the resume on "the completion event has not fired yet"** or a
pause landing in the same frame as the end of a replay will replay the whole answer again.

**Reworking the timeout (the UI-SPEC flags this explicitly, `## Interaction Contract`).**
Today, `lib/services/audio_player_service.dart:9-10`:

```dart
const Duration kReplayCompletionTimeout =
    Duration(seconds: 60 + 5); // kMaxRecordingDuration + 5s
```

and it is applied at line 94 as `await completed.timeout(kReplayCompletionTimeout, onTimeout: () {});`.

Two independent defects for Phase 2:
- **(a) it does not follow `d`.** With `d = 120` a legitimate 118-second replay would be cut off at
  65 s and the loop would advance while the user is still listening. Fix: the const becomes a
  parameter derived from the session's `d`.
- **(b) `Future.timeout` cannot be paused.** `Future<T>.timeout` schedules against real elapsed time
  and offers no freeze. A user who pauses during `replaying` for 90 s with `d = 60` returns to find
  the loop has already moved on — the exact failure the UI-SPEC names ("otherwise a long pause during
  replay trips the timeout and the loop advances behind the user's back").

**Recommended fix — replace `Future.timeout` with the same `PausableCountdown`, so the codebase has
exactly one timing mechanism:**

```dart
// lib/services/audio_player_service.dart  (shape, not final code)
abstract class AudioPlaybackBackend {
  Future<void> play(String absoluteFilePath);
  Stream<void> get onComplete;
  Future<void> pause();     // NEW — AudioPlayer.pause()
  Future<void> resume();    // NEW — AudioPlayer.resume()
  Future<void> stop();
  Future<void> dispose();
}

/// Replaces the old fixed `kReplayCompletionTimeout`: five seconds of slack over
/// the session's configured `d`, which is the longest answer this session can
/// produce. Kept as a named helper so the "+5s slack" rationale stays in one place.
Duration replayCompletionTimeoutFor(Duration answerLimit) =>
    answerLimit + const Duration(seconds: 5);

Future<void> play(
  String absoluteFilePath, {
  bool awaitCompletion = false,
  Duration? completionTimeout,   // NEW — caller passes replayCompletionTimeoutFor(d)
}) async { … }
```

The wait itself becomes a `Completer` resolved by *either* the (still subscribed-before-play)
completion event *or* a `PausableCountdown`'s `onElapsed`. `AudioPlayerService.pause()` then pauses
both the player and that countdown; `resume()` resumes both. **Both of Phase 1's documented
protections must survive verbatim** (`lib/services/audio_player_service.dart:70-77`): the completion
subscription is still captured *before* `play()` (because `onComplete` is a non-replaying broadcast
stream), and the wait is still bounded.

---

### Q4 — `wakelock_plus` (D-30)

**Recommended: `wakelock_plus: ^1.7.0`.**

- Latest published version **1.7.0**, published **2026-07-21** [VERIFIED: pub.dev registry API].
- Constraints: `sdk: '>=3.11.0 <4.0.0'`, `flutter: '>=3.41.0'` [VERIFIED: pub.dev registry API, 1.7.0 pubspec]. This project is Dart **3.12.2** / Flutter **3.44.6** [VERIFIED: `flutter --version` on this machine] — compatible. The 1.7.0 changelog entry is literally *"Flutter 3.44 upgrade"* [VERIFIED: `fluttercommunity/wakelock_plus` CHANGELOG, raw GitHub].
- **Do not pin `^1.6.x`.** 1.7.0 ships PR #134, *"fix(android): defer wakelock toggle when no activity is attached"* [CITED: CHANGELOG]. The Android implementation throws `NoActivityException("wakelock requires a foreground activity")` when `activity == null` [VERIFIED: `wakelock_plus-1.6.1/android/…/Wakelock.kt:17-19, 36, 40`] — which is exactly the situation D-31 creates when the session releases the wakelock on backgrounding.

**Exact API** [VERIFIED: `~/.pub-cache/hosted/pub.dev/wakelock_plus-1.6.1/lib/wakelock_plus.dart`; the 1.7.0 changelog lists only Android/Gradle/SPM changes, no Dart API change — treat the signatures as stable but re-confirm at implementation time]:

```dart
class WakelockPlus {
  static Future<void> enable() => toggle(enable: true);
  static Future<void> disable() => toggle(enable: false);
  static Future<void> toggle({required bool enable}) { … }
  static Future<bool> get enabled => wakelockPlusPlatformInstance.enabled;
}
```

**Manifest / Info.plist: nothing to add — and 02-CONTEXT.md's stated reason is wrong.**
02-CONTEXT.md `## Existing Code Insights` says *"`wakelock_plus` (D-30) needs no new Android permission
(`WAKE_LOCK` is added by the plugin's own manifest)."* The **conclusion is right, the mechanism is
not**, and the difference matters for the release-build audit:

- The plugin's own manifest declares **no permissions at all** — it is a bare
  `<manifest package="dev.fluttercommunity.plus.wakelock"></manifest>`
  [VERIFIED: `wakelock_plus-1.6.1/android/src/main/AndroidManifest.xml`, full file].
- Android is implemented as a **window flag**, which requires no permission of any kind
  [VERIFIED: `wakelock_plus-1.6.1/android/src/main/kotlin/dev/fluttercommunity/plus/wakelock/Wakelock.kt:20-27`, verbatim]:
  ```kotlin
    if (message.enable!!) {
      if (!enabled) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    } else if (enabled) {
      activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
  ```
- iOS is `UIApplication.sharedApplication.isIdleTimerDisabled` — no `Info.plist` key, no entitlement
  [VERIFIED: `wakelock_plus-1.6.1/ios/wakelock_plus/Sources/wakelock_plus/WakelockPlusPlugin.m:30, 38`].

**Net effect on the release build's deliberate no-INTERNET stance: zero.** No `<uses-permission>` is
merged in by this plugin — not even `WAKE_LOCK`, and certainly not `INTERNET`. The Phase 1 release
posture (`android/app/src/main/AndroidManifest.xml` carries only `RECORD_AUDIO`) is untouched.
Recommend the plan add a manifest-diff assertion to verification so this stays true.

**Under `flutter test`: it does NOT work unmediated.** `WakelockPlus.toggle` reaches a pigeon-generated
method channel; with no handler registered in the test binding the call raises `MissingPluginException`.
The package does expose `@visibleForTesting var wakelockPlusPlatformInstance` for overriding, but
that is a **global static**, which is a different shape from every other platform dependency in this
codebase. **Recommend a third seam of the established shape:**

```dart
// lib/services/screen_wake_controller.dart
/// The screen-wake capability, reduced to what an active session needs (D-30).
///
/// Mirrors `RecorderBackend` / `AudioPlaybackBackend`: the seam a test injects
/// so no platform channel is constructed on the host. Resolved lazily for the
/// same reason.
abstract class ScreenWakeController {
  Future<void> enable();
  Future<void> disable();
}

class WakelockPlusScreenWakeController implements ScreenWakeController {
  @override
  Future<void> enable() => WakelockPlus.enable();
  @override
  Future<void> disable() => WakelockPlus.disable();
}
```

Both call sites must swallow failures to `debugPrint` only — the UI-SPEC Copywriting Contract states
*"a wakelock failure is silent (debug log only)"* and Phase 2 introduces **no new user-facing failure
string**.

---

### Q5 — App lifecycle + audio interruption (D-31)

**Two independent signals. Do not conflate them.**

#### (a) Audio interruption — already configured correctly, but currently invisible to Dart

`RecordConfig`'s default is `this.audioInterruption = AudioInterruptionMode.pause`
[VERIFIED: `record_platform_interface-2.1.0/lib/src/types/record_config.dart:89`], and the enum's own
doc is verbatim [VERIFIED: `…/types/audio_interruption_mode.dart`, full file]:

```dart
/// Recorder behaviour when audio is interrupted by another source.
enum AudioInterruptionMode {
  /// Recording state stays the same on interruption.
  none,

  /// Pauses automatically, resumes manually the recording.
  pause,

  /// Pauses and resumes automatically the recording.
  pauseResume,
}
```

`AudioInterruptionMode.pause` — *"Pauses automatically, resumes manually"* — **is D-31's policy,
word for word**, and `lib/services/recording_service.dart:49` already passes `const RecordConfig()`.
**No configuration change is required.** Do not switch to `pauseResume` (it would silently resume
recording after a call, which D-31 explicitly forbids).

Native wiring, for the plan's confidence:
- iOS registers an `AVAudioSession.interruptionNotification` observer and, on `.began`, calls
  `pause()` whenever the mode is not `.none`
  [VERIFIED: `record_ios-2.1.1/…/extension/RecorderSessionExtension.swift:104-115`].
- Android hooks audio-focus loss:
  `onFocusLoss = { recorderThread?.pauseRecording() }`
  [VERIFIED: `record_android-2.1.2/…/recorder/AudioRecorder.kt:36-42`, verbatim].

**The actual gap:** that native pause is *invisible to Dart* unless the app subscribes to
`AudioRecorder.onStateChanged()`. Without it, `PracticeState` keeps showing the listening mascot,
the pulse ring and a live `d` countdown while the microphone is frozen — the single worst honesty
failure available in this phase. **The `RecorderBackend` seam must gain a state stream.**

Keep the seam free of `package:record` types (it currently uses only Dart core types). Map at the
production backend:

```dart
abstract class RecorderBackend {
  Future<bool> hasPermission();
  Future<void> start(String absoluteFilePath);
  Future<String?> stop();
  Future<void> pause();                    // NEW
  Future<void> resume();                   // NEW
  Future<bool> isPaused();                 // NEW — the honesty check, see Pitfall 1
  /// Emits `true` when the recorder is paused, `false` when it is recording.
  /// Fires for pauses the app did NOT initiate (an incoming call, audio-focus
  /// loss), which is the only way Dart learns about them (D-31).
  Stream<bool> get onPausedChanged;        // NEW
  Future<void> dispose();
}

// production backend:
@override
Stream<bool> get onPausedChanged => _recorder
    .onStateChanged()
    .where((s) => s != RecordState.stop)
    .map((s) => s == RecordState.pause);
```

#### (b) Backgrounding — `AppLifecycleListener` is the current best practice

`AppLifecycleListener` exists on Flutter 3.44.6
[VERIFIED: `/Applications/flutter/packages/flutter/lib/src/widgets/app_lifecycle_listener.dart:64` —
`class AppLifecycleListener with WidgetsBindingObserver, Diagnosticable`], with constructor callbacks
`onResume, onInactive, onHide, onShow, onPause, onRestart, onDetach, onStateChange`
[VERIFIED: same file, lines 68-76].

**Prefer it over `WidgetsBindingObserver.didChangeAppLifecycleState`.** Both work; `AppLifecycleListener`
*is* a `WidgetsBindingObserver` internally and additionally decodes the raw state stream into discrete
transitions (`hidden` reached from `inactive` fires `onHide`; reached from `paused` fires `onRestart`),
which is precisely the distinction this phase needs and which hand-rolled `didChangeAppLifecycleState`
switch statements habitually get wrong.

**Which callback for "the app was backgrounded": `onHide`.** Do **not** trigger on `onInactive` —
`inactive` fires for a pulled-down notification shade, Control Centre, the app switcher, and (on iOS)
an incoming-call *banner*. A call that is never answered would auto-pause a session that was never
actually interrupted. The `IosRecordConfig` doc makes the distinction explicit
[VERIFIED: `record_platform_interface-2.1.0/lib/src/types/ios_record_config.dart:8-14`]:
*"the recording session is not interrupted by an incoming call ringing. The interruption only begins
once the user actually answers the call."*
The **answered** call arrives on path (a); the **backgrounded app** arrives on path (b). Clean split.

#### Concrete, testable recommendation for "finalize and save the in-flight answer, then park paused"

Phase 1's `stopRecording()` (`lib/state/practice_state.dart:212-293`) already *is* the
finalize → one transaction → commit sequence, and its guard/ordering comments are the crash-safety
contract. **Do not fork it.** Split only its tail:

```
stopRecording()  ── unchanged through the `insertAnswer…` commit and the `_disposed` check ──►
                    then, instead of unconditionally replaying + re-arming:
                      if (_interruptionPending) { phase = paused; pausedReason = interrupted; return; }
                      if (config.autoReplay)    { …replay… }
                      _advanceToNextQuestion();   // LOOP-07 / LOOP-08
```

The interruption handler then becomes:

```
onInterruption(source: audioFocus | appHidden):
  1. _interruptionPending = true;             // set BEFORE any await
  2. if (phase == recording) await stopRecording();   // finalize → commit → park paused
     else { pause every running countdown; phase = paused; }
  3. pausedReason = PausedReason.interrupted; // drives the UI-SPEC's second banner variant
  4. releaseWakelock();                        // wrapped in try/catch, debugPrint only
```

Both entry points converge on one method, so there is one code path to test and one to reason about.

**Two real-device caveats the plan must record and the UAT must cover.**
1. On **iOS**, once the process is backgrounded the Dart isolate is suspended, so the `await` chain
   inside `stopRecording()` may not complete before suspension — the commit can land on the *next*
   foreground rather than before backgrounding. On **Android** the isolate keeps running and the
   commit lands immediately. [ASSUMED — this is platform behaviour, not something readable from the
   package source; it must be proven by the D-31 real-device UAT.]
2. The `-10868` rough edge named in STATE.md is addressed in the versions this project resolves to:
   `record` 7.0.0 lists *"iOS: fix: Respect `shouldResume` system flag on audio interruption and don't
   stop on resume failure"* and 6.2.0 lists *"fix(Android/iOS): `AudioInterruptionMode` not pausing or
   resuming"* [VERIFIED: `record-7.1.1/CHANGELOG.md`]. **This does not discharge the UAT obligation** —
   D-31 requires an actual answered phone call mid-recording on a real device.

---

### Q6 — `PopScope` (D-29)

**Current correct API on Flutter 3.44.6: `canPop` + `onPopInvokedWithResult`.**
`onPopInvoked` is deprecated and passing both is asserted against
[VERIFIED: `/Applications/flutter/packages/flutter/lib/src/widgets/pop_scope.dart:83-100`, verbatim]:

```dart
class PopScope<T> extends StatefulWidget {
  const PopScope({
    super.key,
    required this.child,
    this.canPop = true,
    this.onPopInvokedWithResult,
    @Deprecated(
      'Use onPopInvokedWithResult instead. '
      'This feature was deprecated after v3.22.0-12.0.pre.',
    )
    this.onPopInvoked,
  }) : assert(
         onPopInvokedWithResult == null || onPopInvoked == null,
         'onPopInvoked is deprecated, use onPopInvokedWithResult',
       );
```

The semantics, verbatim from the class doc (lines 47-58):

> `/// If [canPop] is false, then a system back gesture will not pop the route off`
> `/// of the enclosing [Navigator]. [onPopInvokedWithResult] will still be called, and`
> `/// `didPop` will be `false`. On iOS when using [CupertinoRouteTransitionMixin]`
> `/// with [canPop] set to false, no gesture will be detected at all, so`
> `/// [onPopInvokedWithResult] will not be called. Programmatically attempting pop`
> `/// navigation will also result in a call to [onPopInvokedWithResult], with `didPop``
> `/// indicating success or failure.`
> `///`
> `/// If [canPop] is true, then a system back gesture will cause the enclosing`
> `/// [Navigator] to receive a pop as usual.`

**The pattern for "intercept back, confirm, pop only on confirm":**

```dart
PopScope<void>(
  // Released in the `complete` phase per the UI-SPEC, where the back arrow
  // reappears and pops to Setup.
  canPop: _isSessionOver,
  onPopInvokedWithResult: (bool didPop, void result) async {
    if (didPop) return;               // already popped — nothing to intercept
    final bool end = await _confirmStop();   // the SAME dialog the app-bar Stop opens
    if (!end || !mounted) return;
    Navigator.of(context).pop();      // the one and only early-exit path (D-29)
  },
  child: Scaffold(…),
)
```

Three things the plan must get right:
- **Guard on `didPop`.** When `canPop` is true the callback still fires with `didPop == true`; acting
  on it would open the dialog on a pop that has already happened.
- **`mounted` after the `await`.** `showDialog` is asynchronous; the widget can be gone by the time it
  resolves. (`use_build_context_synchronously` is in `flutter_lints`, so `flutter analyze` will catch
  a missed check — treat that as the guard rail, not the design.)
- **One dialog, two callers.** The app-bar Stop and `PopScope` must both call the same
  `_confirmStop()` so D-25's auto-pause-while-open and the barrier-tap-means-cancel rule can never
  diverge. The iOS `CupertinoRouteTransitionMixin` caveat above is irrelevant here because the app
  uses `MaterialPageRoute` (`lib/screens/practice_screen.dart:75`).

---

### Q7 — Schema extension for multi-answer sessions (D-26)

**The tables do not change. This is one new method, no migration, no version bump.**

The existing write path already does exactly the "create a session and its first answer in one
transaction" half of D-26, **and it already returns the new session id**
(`lib/db/database_helper.dart:150-166`). The minimal, lowest-risk change is therefore: **leave
`insertAnsweredSession` byte-for-byte alone** — it is the crash-safety-critical method guarded by the
existing test suite — and add a single sibling:

```dart
  /// Appends one answer to an EXISTING session (D-26).
  ///
  /// The lazy-creation counterpart to [insertAnsweredSession]: the first answer
  /// of a session goes through that method (which creates the `sessions` row and
  /// returns its id); every later answer of the same session comes here. A
  /// session abandoned before its first answer therefore writes nothing at all,
  /// preserving D-08's "nothing captured ⇒ no trace".
  ///
  /// Its own transaction per call, so PERSIST-01 holds per QUESTION, not per
  /// session: a force-kill at question 7 of 10 leaves exactly 6 committed
  /// answers.
  ///
  /// MUST only ever be called AFTER the audio file is confirmed finalized on
  /// disk — identical caller contract to [insertAnsweredSession].
  ///
  /// [sessionId] must name a row that exists: `PRAGMA foreign_keys = ON` is
  /// applied on every open (see [_onConfigure]), so an insert against a missing
  /// session fails loudly instead of writing an orphan.
  Future<void> insertAnswer({
    required int sessionId,
    required String questionText,
    required String audioRelativePath,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction<void>((txn) async {
      await txn.insert(kQuestionAnswersTable, {
        'session_id': sessionId,
        'question_text': questionText,
        'audio_path': audioRelativePath,
        'created_at': now,
      });
    });
  }
```

Notes for the planner:
- **`version: 1` stays `version: 1`** (`lib/db/database_helper.dart:99`). Nothing in the DDL changes,
  so `onUpgrade` is not needed and devices carrying a Phase 1 database keep working untouched.
- The class doc already anticipates this: *"Schema (locked in Phase 1 per D-05, extended by Phase 2
  with more rows — never a migration)"* [VERIFIED: `lib/db/database_helper.dart:10-11`, verbatim].
- The FK is genuinely enforced — `PRAGMA foreign_keys = ON` runs in `_onConfigure` on **every** open
  [VERIFIED: `lib/db/database_helper.dart:120-122`], so `insertAnswer` against a nonexistent
  `sessionId` throws rather than orphaning a row. That is a second line of defence behind the
  in-memory `int? _sessionId`.
- The explicit `db.transaction` around a lone `INSERT` is redundant with SQLite's implicit
  per-statement transaction. It is recommended anyway, purely so the two write methods look identical
  and a future reviewer does not read the asymmetry as significance.
- **Caller shape in the loop:**
  `_sessionId = _sessionId == null ? await db.insertAnsweredSession(…) : (await db.insertAnswer(sessionId: _sessionId!, …), _sessionId!).$2;`
  — or, more readably, an `if/else`. `_sessionId` is in-memory only; a force-kill loses it and the
  relaunched app starts a fresh session, which is exactly D-26/D-08's stated behaviour.
- `listSessions()` / `listAnswersForSession()` / `listReferencedAudioPaths()` need **no change** —
  `listAnswersForSession` already orders `id ASC`, i.e. insertion order (HIST-02)
  [VERIFIED: `lib/db/database_helper.dart:177-186`].
- **The answered-count for LOOP-08 and D-27 must be incremented only after the commit returns**, so
  it can never exceed the row count the completion screen promises.

---

### Q8 — Widget-testing timed UI deterministically

**The mechanism is already in the repo and needs no new dependency:** `testWidgets` +
`await tester.pump(duration)` on the binding's fake clock (see the verbatim comment quoted in § Q2 at
`test/services/recording_service_test.dart:60-68`, proven by that file's ten timer tests). The same
file also documents the second half of the contract:

> `// That binding also FAILS any test that ends with a pending timer, so each`
> `// test below either pumps past the deadline or disposes the service.`

Four rules the plan must write into its test tasks:

1. **Every timer-driven test is a `testWidgets`, never a plain `test()`.** A plain `test()` has no
   fake clock; `Timer.periodic(1s)` would need real wall-clock waits.
2. **Never call `pumpAndSettle()` on a screen with a running countdown.** A `Timer.periodic` that
   triggers rebuilds keeps scheduling frames, so `pumpAndSettle` runs to its timeout and fails. Use
   explicit `await tester.pump(const Duration(seconds: 1))`, N times, and assert the on-screen numeral
   after each. (The UI-SPEC's countdown ring is a *determinate* `CircularProgressIndicator(value: …)`,
   which is fine; an **indeterminate** one — `value: null` — animates forever and would break
   `pumpAndSettle` on its own.)
3. **Leave no pending timer.** Either run each countdown to zero or `cancel()` it in a `tearDown` /
   the state's `dispose()`. The `cancel()` in the sketched `PausableCountdown` exists for this.
4. **⚠ Put Phase 2's loop tests in a NEW file — do not append them to `test/state/practice_state_test.dart`.**
   That file deliberately uses plain `test()`, and says why verbatim
   [VERIFIED: `test/state/practice_state_test.dart:265-268`]:

   > `// Deliberately a plain `test()`, not a `testWidgets()`: initialising the`
   > `// widget binding in this file would make FlutterError.onError fail the`
   > `// save-failure test below (IN-04).`

   The save-failure path calls `FlutterError.reportError` (`lib/state/practice_state.dart:263-270`),
   which the widget binding turns into a test failure. Converting that file to `testWidgets` would
   break an existing regression guard. **Recommended new files:**
   `test/utils/pausable_countdown_test.dart`, `test/state/practice_session_test.dart` (timed loop,
   pause/resume, LOOP-08 completion) and `test/screens/setup_screen_test.dart` — mirroring `lib/`
   path-for-path as the repo already does.

**Driving lifecycle transitions in tests.** `WidgetsBinding.handleAppLifecycleStateChanged` is public
[VERIFIED: `/Applications/flutter/packages/flutter/lib/src/widgets/binding.dart:1330`], so
`tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive)` works. **But
`AppLifecycleListener` asserts on illegal transitions** — the switch at
`app_lifecycle_listener.dart:213-268` carries `'Invalid state transition from $previousState to $state'`
for every case [VERIFIED, verbatim]. Legal chains, read directly from those asserts:

| To state | Legal previous states |
|----------|----------------------|
| `resumed` | `null`, `inactive`, `detached` |
| `inactive` | `null`, `hidden`, `resumed` |
| `hidden` | `null`, `paused`, `inactive` |
| `paused` | `null`, `hidden` |
| `detached` | `null`, `paused` |

So a backgrounding test must drive `resumed → inactive → hidden` (which fires `onHide`) and a return
must drive `hidden → inactive → resumed`. Jumping straight from `resumed` to `paused` trips the
assert, and `flutter test` runs in debug where asserts are live.

**Recommended test list for the phase's timed behaviour** (each is deterministic and sub-second):

| Behaviour | Shape |
|-----------|-------|
| LOOP-01 3·2·1 then question | pump 1s ×3, assert numeral 3→2→1 then the `reading` phase key |
| LOOP-02 `t` runs fully to zero *before* arming (D-20) | assert `recorderService.calls` is still empty at `t-1` s, non-empty after `t` |
| `d` auto-stop fires at `d`, not before | the existing `recording_service_test.dart` pattern, parameterised on `d` |
| CTRL-04 pause freezes a countdown | pump 2s, pause, pump 60s, assert the numeral is unchanged; resume, pump, assert it moves again |
| CTRL-04 pause freezes the `d` deadline | pause at `d-2` s, pump `d`×2, assert no stop was issued; resume, pump 2s, assert exactly one stop |
| LOOP-08 completes at `question_count` | run N cycles with a fake recorder, assert `complete` phase and N rows |
| PERSIST-01 across N answers | force-stop at question k, assert exactly k rows in one session |
| **Auto-stop vs. Pause in the same frame** | the UI-SPEC's ⚠ unresolved race — assert auto-stop wins and the pause applies at the next pausable phase |
| D-31 backgrounding | drive `resumed→inactive→hidden`, assert the in-flight answer committed and the phase is `paused` with the interrupted banner |

---

## Standard Stack

### Core (already in `pubspec.yaml` — no version change required)

| Library | Version (resolved) | Purpose in Phase 2 | Why Standard |
|---------|--------------------|--------------------|--------------|
| `record` | **7.1.1** (latest) | Microphone + **`pause()`/`resume()`/`isPaused()`/`onStateChanged()`** for D-24 and D-31 | Already the project's recorder; the pause API and the interruption mode this phase needs are present and correctly defaulted. [VERIFIED: pub cache source + pub.dev registry] |
| `audioplayers` | **6.8.1** (latest) | Replay + **`pause()`/`resume()`** for pausing during `replaying` | Already the project's player; pause/resume documented to resume in place. [VERIFIED: pub cache source + pub.dev registry] |
| `sqflite` | 2.4.3 | One new `insertAnswer` method, unchanged schema | Frozen by D-05. [VERIFIED: `pubspec.lock`] |
| `path_provider` / `path` | 2.1.6 / 1.9.0 | Unchanged | — |
| `google_fonts` | 8.2.1 | Unchanged (the 128 px countdown glyph derives from the existing `displayLarge`) | — |
| Flutter SDK | **3.44.6 / Dart 3.12.2** | `PausableCountdown` (`dart:async` `Timer`), `AppLifecycleListener`, `PopScope`, `ChangeNotifier`/`ListenableBuilder`, Material `Slider`/`ChoiceChip`/`SwitchListTile`/`CheckboxListTile`/`AlertDialog` | Every Phase 2 widget and timing primitive is in the SDK. [VERIFIED: `flutter --version` on this machine] |

### Supporting — the phase's only new package

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `wakelock_plus` | **^1.7.0** | Hold the screen awake for the duration of an active session (D-30) | Exactly two call sites (session start / session end + dispose), behind a `ScreenWakeController` seam. Pin `^1.7.0`, not `^1.6.x` — see § Q4. |

**Installation:**
```bash
flutter pub add wakelock_plus
```

**Explicitly NOT added, with reasons:**

| Tempting package | Why not |
|------------------|---------|
| `fake_async` (as a dev_dependency) | `testWidgets` already provides the identical fake clock, and the repo already relies on it. Adding it would be one more dependency for zero capability. Only add it if a plain-`test()` timer test proves unavoidable — and it does not, because those tests belong in new `testWidgets` files anyway (§ Q8). |
| `pausable_timer` / `timer_count_down` / any countdown package | The whole class is ~60 lines of `Timer` bookkeeping with no edge cases the project does not already own. Adding a package here would be a "hand-rolling" inversion — see § Don't Hand-Roll for where the line actually falls. |
| `provider` / `riverpod` / `flutter_bloc` | CLAUDE.md "What NOT to Use". One `ChangeNotifier` + `ListenableBuilder` still covers Setup → Practice → History. |
| `permission_handler` | `record.hasPermission()` already covers it; Phase 1 deliberately avoided it. |
| `shared_preferences` | Would only be needed to persist Setup settings, which D-18 explicitly defers. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Timer.periodic` decrement | `Stopwatch` + rescheduled `Timer` | Wall-clock-exact deadline, but **not advanced by `tester.pump()`** (§ Q2) and needs a second clock for the UI. Only worth it if sub-second deadline accuracy ever becomes a requirement, and then behind the same class. |
| `Timer.periodic` decrement | `Ticker` / `AnimationController` (60 fps) | Would give a smoothly sweeping countdown ring instead of a 1-second step. Costs a `TickerProvider`, a `vsync`, and per-frame rebuilds; and `pumpAndSettle` still cannot be used. If the stepping ring looks bad on device, a `TweenAnimationBuilder` between whole-second values is the cheap upgrade — presentation only, no change to the timing source of truth. |
| `AppLifecycleListener` | `WidgetsBindingObserver.didChangeAppLifecycleState` | Works, but you re-implement the transition decoding that `AppLifecycleListener` already does and that this phase depends on (`onHide` vs `onInactive`). |
| Extending `PracticeState` | A new session-scoped `ChangeNotifier` beside it | CONTEXT.md's Claude's Discretion allows either. **Recommend extending**, so the Phase 1 stop→save→replay sequence and its guard comments stay literally where the tests point at them; the loop-sequencing additions are new methods, not edits to `stopRecording()`'s body above the commit. |
| `PhaseControl` gets new `PracticePhase` values | Orthogonal `bool isPaused` flag | UI-SPEC accepts both. **Recommend new phase values** (`getReady`, `reading`, `paused`, `complete`) — the `kPhaseControlKeys` totality test then mechanically forces a control for each, which is the guard rail the project deliberately built. The `isPaused` variant needs a hand-written short-circuit *before* the switch plus a hand-extended test, i.e. the guard becomes manual. |

---

## Package Legitimacy Audit

The `package-legitimacy` seam supports `npm|pypi|crates` only and rejects `--ecosystem pub`
[VERIFIED: `gsd-tools query package-legitimacy check --ecosystem pub wakelock_plus` →
`Error: Usage: gsd-tools package-legitimacy check --ecosystem <npm|pypi|crates> <pkg1> ...`].
Equivalent evidence was gathered from the pub.dev registry API instead.

| Package | Registry | Age / Version | Downloads | Source Repo | Publisher | Verdict | Disposition |
|---------|----------|---------------|-----------|-------------|-----------|---------|-------------|
| `wakelock_plus` | pub.dev | 1.7.0, published 2026-07-21 | **2,059,089 / 30 days**; 637 likes; **160/160 pub points** | `github.com/fluttercommunity/wakelock_plus` | **verified publisher `fluttercommunity.dev`** | OK | Approved — add as `^1.7.0` |
| `record` | pub.dev | 7.1.1, published 2026-06-29 | already a direct dependency since Phase 1 | `github.com/llfbandit/record` | — | OK | Already installed, no change |
| `audioplayers` | pub.dev | 6.8.1, published 2026-06-27 | already a direct dependency since Phase 1 | — | — | OK | Already installed, no change |

[VERIFIED: `https://pub.dev/api/packages/wakelock_plus`, `/score`, `/publisher`; and
`https://pub.dev/api/packages/{record,audioplayers}`]

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none. `wakelock_plus` is a Flutter Community package with a
verified publisher, a perfect pana score and >2M monthly downloads — no `checkpoint:human-verify` is
warranted. It also introduces **no new Android permission and no new iOS entitlement** (§ Q4), so it
cannot broaden the app's attack surface or disturb the deliberate no-INTERNET release posture.

---

## Architecture Patterns

### System Architecture Diagram

```
 ┌────────────────── SetupScreen  (NEW — becomes `home:`, D-28) ───────────────────┐
 │  topics[] ✓   level   question_count   t   d   r                                │
 │  local widget state only, nothing persisted (D-18)                              │
 │  Start enabled ⇔ topics.isNotEmpty (SETUP-07)                                   │
 └───────────────┬────────────────────────────────────────┬────────────────────────┘
                 │ Navigator.push(SessionConfig)          │ app-bar history icon
                 ▼                                        ▼
 ┌──────────── PracticeScreen(config) ────────────┐   HistoryScreen (unchanged)
 │  AppBar: "Question k of N"  [Pause][Stop]      │
 │  PopScope(canPop: sessionOver) ─► confirmStop  │
 │  AppLifecycleListener(onHide: ─► interruption) │
 │  ScreenWakeController.enable() on entry        │
 │                    │                           │
 │                    ▼                           │
 │  ┌──────── PracticeState (ChangeNotifier) ────────────────────────────────┐    │
 │  │                                                                        │    │
 │  │  getReady(3) ─► reading(t) ─► arming ─► recording(d) ─► saving          │    │
 │  │      ▲                                                    │             │    │
 │  │      │  k < N                                             ▼             │    │
 │  │      └──────────────── [r] replaying ◄──── COMMIT ────────┘             │    │
 │  │                            │                                            │    │
 │  │                     k == N ▼                                            │    │
 │  │                        complete                                         │    │
 │  │                                                                        │    │
 │  │  paused  ◄── pause()/Stop-dialog/interruption ── ANY of the above ──►   │    │
 │  │            (freezes the one active PausableCountdown + the recorder)    │    │
 │  └───┬──────────────┬───────────────────┬──────────────────┬──────────────┘    │
 └──────┼──────────────┼───────────────────┼──────────────────┼───────────────────┘
        │              │                   │                  │
        ▼              ▼                   ▼                  ▼
  PausableCountdown  RecordingService  AudioPlayerService  DatabaseHelper
  (Timer.periodic)         │                  │                  │
                    RecorderBackend    AudioPlaybackBackend    sqflite
                           │                  │                  │
                    package:record     package:audioplayers   englishreflex.db
                           │                                     │
                  ┌────────┴────────┐                   sessions ─1:N─ question_answers
                  │ onStateChanged  │                   (created lazily      (own txn
                  │  RecordState    │                    on 1st answer,       per answer,
                  │  .pause  ◄──────┼── OS audio         D-26)                PERSIST-01)
                  └─────────────────┘   interruption
                                        (call / focus loss)
```

Trace of the primary use case: Start → `getReady(3)` → `reading(t)` shows the question → at zero the
recorder arms (`arming`, D-20) → `recording(d)` with the STOP circle and the `d` readout → STOP or
the `d` deadline → `saving` finalizes the file and commits one transaction → if `r`, `replaying` →
`getReady(3)` for question k+1, or `complete` when k == N.

### Recommended Project Structure

```
lib/
├── data/
│   └── questions.dart        # ~20 prompts + ~5 subjects + a QuestionSource seam (D-19/D-23)
├── models/
│   ├── session.dart          # unchanged
│   ├── question_answer.dart  # unchanged
│   └── session_config.dart   # NEW — immutable: topics, level, count, t, d, r
├── screens/
│   ├── setup_screen.dart     # NEW — becomes `home:` (D-28)
│   ├── practice_screen.dart  # takes SessionConfig; PopScope; lifecycle; wakelock
│   ├── history_screen.dart   # unchanged
│   └── session_detail_screen.dart  # unchanged
├── services/
│   ├── recording_service.dart        # + pause/resume/isPaused/onPausedChanged, configurable d
│   ├── audio_player_service.dart     # + pause/resume, d-derived pausable timeout
│   └── screen_wake_controller.dart   # NEW seam over wakelock_plus (D-30)
├── state/
│   └── practice_state.dart   # + loop sequencing, paused state, session-id bookkeeping
├── utils/
│   ├── audio_paths.dart      # unchanged
│   ├── date_format.dart      # unchanged
│   └── pausable_countdown.dart  # NEW — the one timing primitive
└── widgets/
    ├── mascot.dart           # unchanged
    ├── phase_control.dart    # + getReady / reading / paused / complete keys
    ├── countdown_ring.dart   # NEW — 96px determinate ring (UI-SPEC)
    └── countdown_numeral.dart# NEW — 128px glyph in a fixed 160px box (UI-SPEC)
```

### Pattern 1: Extend the seam, don't add a service

**What:** `RecordingService` and `AudioPlayerService` each gain `pause()`/`resume()` that delegate to
new methods on their existing `RecorderBackend` / `AudioPlaybackBackend` abstract classes.
**When to use:** every time Phase 2 needs a new platform capability.
**Why:** the seams are what make `flutter test` free of platform channels
(`lib/services/recording_service.dart:80-86`: *"The backend is resolved lazily so a test that injects
a fake never constructs a platform channel."*). Introducing a capability *outside* a seam — e.g.
calling `WakelockPlus.enable()` directly from a `State` — silently breaks that invariant and the
failure shows up as a `MissingPluginException` in an unrelated widget test.

### Pattern 2: One countdown object alive at a time

**What:** `PracticeState` holds `PausableCountdown? _countdown` — exactly one, replaced on every phase
transition, `cancel()`ed in `dispose()`.
**When to use:** always.
**Why:** `pause()` and `resume()` then have nothing to choose between, and the test binding's
"no pending timers at test end" rule has one thing to satisfy. Two concurrent countdowns is how the
"pause froze the display but not the deadline" bug gets in.

### Pattern 3: New `PracticePhase` values, so the totality test does the enforcing

Add `getReady`, `reading`, `paused`, `complete` to `PracticePhase`
(`lib/state/practice_state.dart:19`). `test/widgets/phase_control_test.dart:26-39` asserts
`kPhaseControlKeys.length == PracticePhase.values.length`, so the build fails until each has a keyed
control — the guard the project deliberately built (`lib/widgets/phase_control.dart:5-13`).

**The `PhaseControl` doc comment must be extended, not just the map.** Its current justification for
label-only controls is *"every `await` in `stopRecording()` is guarded, so these phases are strictly
transient"* — that argument **does not transfer** to `getReady` and `reading`, which are timer-driven,
not await-driven. Their justification (per UI-SPEC) is: they are bounded by a timer that always fires,
**and** the app bar carries Pause and Stop in both, so neither is ever a dead end even if a timer were
lost. Write that into the comment; a reader who finds the old rationale applied to a timer-driven
phase will draw the wrong conclusion.

### Pattern 4: Interruption and backgrounding converge on one handler

Two producers (`RecorderBackend.onPausedChanged` emitting an un-requested `true`; and
`AppLifecycleListener.onHide`) call one `_onInterrupted()`. One method to test, one to reason about,
one place where `pausedReason` is set for the UI-SPEC's second banner variant.

### Anti-Patterns to Avoid

- **Treating a non-throwing `pause()` as proof the mic stopped.** Both platforms no-op silently in the
  wrong state (§ Q1). See Pitfall 1.
- **`Stopwatch`-based deadlines.** Not advanced by `tester.pump()` (§ Q2).
- **`pumpAndSettle()` on a countdown screen.** Runs to timeout and fails (§ Q8).
- **Adding timer tests to `test/state/practice_state_test.dart`.** Converting it to `testWidgets`
  breaks the IN-04 save-failure regression guard it documents at lines 265-268 (§ Q8).
- **Moving the `_disposed` check between `recordingService.stop()` and the DB commit.**
  `lib/state/practice_state.dart:229-235` documents at length why it must stay after the commit
  (WR-01). Multiplying the write path across N answers multiplies the exposure — do not touch that
  ordering.
- **Creating the `sessions` row at Start.** D-26 rejects it; an app killed between Start and the first
  answer would leave a permanent orphan row that History would have to filter.
- **`AudioInterruptionMode.pauseResume`.** Would silently resume recording after a call, which D-31
  explicitly forbids ("the app never silently resumes recording after an interruption").
- **`AndroidRecordConfig(useLegacy: true)`.** Routes pause through `MediaRecorder`, which silently
  no-ops below API 24 (§ Q1).
- **Triggering the interruption handler on `onInactive`.** Pauses the session for a notification-shade
  pull or an unanswered call banner (§ Q5).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pausing a live recording | Stop + start a second file, then concatenate on resume | `record`'s `pause()`/`resume()` | The native implementations keep one file open and excise the paused span (§ Q1). Concatenating two AAC/m4a files needs a container-aware muxer — there is no correct byte-level concat. |
| Detecting an incoming call | Telephony/call-state plugins, platform channels | `RecordConfig.audioInterruption` (already defaulted to `.pause`) + `onStateChanged()` | The OS already owns and publishes this. A call-state plugin would need `READ_PHONE_STATE` on Android — a new dangerous permission for information the audio session already gives you free. |
| Resuming playback mid-file | Track a position and `seek()` after re-`play()` | `AudioPlayer.pause()` / `resume()` | Documented to resume from the pause point (§ Q3). A seek-based reimplementation adds a round trip and a race with `onSeekComplete`. |
| Keeping the screen awake | Periodic synthetic input, `SystemChannels` pokes, a foreground service | `wakelock_plus` | Android needs a window flag on the *activity's* window and iOS needs `isIdleTimerDisabled`; both are per-platform and neither is reachable from Dart without a plugin (§ Q4). |
| Intercepting the system back gesture | `WillPopScope` (removed), raw `Navigator` observers | `PopScope` + `onPopInvokedWithResult` | Predictive back on Android 14+ requires route-level participation, which `PopScope` provides via `ModalRoute.registerPopEntry` (§ Q6). |
| Decoding app lifecycle transitions | A hand-written `didChangeAppLifecycleState` switch | `AppLifecycleListener` | It already distinguishes `hidden`-from-`inactive` (`onHide`) from `hidden`-from-`paused` (`onRestart`), which is the distinction D-31 hinges on (§ Q5). |
| **Where the line falls the other way** | — | **Hand-roll `PausableCountdown`** | This is *timing policy*, not a solved hard problem: ~60 lines of `Timer` bookkeeping with no platform surface, no edge cases the project does not already own, and full control over the pause semantics CTRL-04 requires. Pulling a countdown package in would import someone else's pause semantics and a dependency the project cannot fake. |

**Key insight:** in this phase, everything that touches *the OS or the audio hardware* must be
delegated (the OS is the only component that knows when a call arrives or when a codec can be
suspended), and everything that is *the app's own timing policy* should be owned outright, because
D-24's "resume continues from exactly where it stopped" is a product decision no library encodes.

---

## Runtime State Inventory

Phase 2 is not a rename, but D-26 changes how existing on-device state is written and D-28 changes the
app's entry point, so the inventory is worth stating explicitly.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `englishreflex.db` at `getApplicationDocumentsDirectory()/englishreflex.db`, `version: 1` [VERIFIED: `lib/db/database_helper.dart:35, 94-103`]. Phase-1 devices hold N single-answer sessions. | **None.** No DDL change, no version bump, no `onUpgrade`. Existing rows read identically; `listAnswersForSession` already supports N rows (§ Q7). |
| Stored data | Audio files under `recordings/` relative to the documents dir, referenced by relative path [VERIFIED: `lib/utils/audio_paths.dart` usage at `lib/state/practice_state.dart:151, 283`]. | **None** to the format. **One relocation:** the launch-time `pruneOrphanRecordings` sweep currently lives in `PracticeScreen._bootstrap()` (`lib/screens/practice_screen.dart:43-54`); D-28 makes Setup the entry point, so the sweep must move to app/Setup start-up and **still complete before any file name is chosen** — its documented caller contract. |
| Live service config | None — the app has no backend until Phase 3 (Firestore). | None. |
| OS-registered state | Android: `RECORD_AUDIO` only, in `android/app/src/main/AndroidManifest.xml` [VERIFIED: full file read]. iOS: `NSMicrophoneUsageDescription`. `wakelock_plus` merges **no** `<uses-permission>` (§ Q4). | **None.** Recommend a verification step that diffs the merged manifest to prove no permission was added. |
| Secrets / env vars | None — no keys, no `.env`, no network. | None. |
| Build artifacts | `assets/fonts/Baloo2-SemiBold.ttf` + `OFL.txt`, matched by filename scan [VERIFIED: `pubspec.yaml:67-77` comment + `lib/main.dart:26-32`]. | **None.** Phase 2 adds no font and no asset; the 128 px glyph derives from the existing `displayLarge`. |
| App entry point | `home: const PracticeScreen()` [VERIFIED: `lib/main.dart:130`]. | **Change to `SetupScreen` (D-28).** `configureFonts()` and the whole `ThemeData` block stay untouched — the UI-SPEC introduces zero new base tokens. |

**Nothing found in category:** live service config, secrets/env vars — verified by inspection of the
repo (no network code, no config files, `pubspec.yaml` has no Firebase dependency yet).

---

## Common Pitfalls

### Pitfall 1: A `pause()` that silently does nothing, behind a UI that says "Paused"

**What goes wrong:** `await recorderBackend.pause()` returns normally, the app publishes the
`paused` phase and the banner *"Paused — nothing is being recorded."*, and the microphone is still
live capturing whatever the user says next into the answer file.
**Why it happens:** both native implementations are guarded early-returns, not throws —
iOS `guard m_state == .record else { return }` [VERIFIED: `record_ios-2.1.1/…/Recorder.swift:82-85`]
and Android `if (isRecording())` [VERIFIED: `record_android-2.1.2/…/RecordThread.kt:45-49`]. A pause
racing the `d` auto-stop, or landing during the arming window, hits exactly that guard.
**How to avoid:** treat the *state*, not the call, as the source of truth. Either
(a) `await backend.pause(); if (!await backend.isPaused()) { /* do not publish paused */ }`, or
(b) publish `paused` only when `onPausedChanged` emits `true`. Option (b) is preferable because it
also covers OS-initiated pauses (D-31) with the same code path. Additionally, keep the UI-SPEC's rule
that **Pause is disabled during `arming`** — that removes the worst window by construction.
**Warning signs:** the mascot's pulse ring still animating under the paused banner; an answer file
noticeably longer than the elapsed `d` countdown; the `d` readout frozen while the file grows.
**This is the UI-SPEC's `E10 / error` 🧪 backstop, and it now has a concrete mechanism behind it.**

### Pitfall 2: The `d` deadline keeps running while paused, so the answer auto-saves behind the dialog

**What goes wrong:** the user taps Stop, reads the confirmation dialog for 20 s, and taps *Keep going* —
only to find the answer was auto-saved and the loop has advanced to the next question.
**Why it happens:** `Timer(kMaxRecordingDuration, …)` (`lib/services/recording_service.dart:186`) has
no pause; neither does `Future.timeout` in `AudioPlayerService`. Because `record`'s pause excises the
paused span from the file, a running deadline is also *wrong* — it would cut the answer short by the
paused duration.
**How to avoid:** D-25 mandates auto-pausing while the dialog is open, and § Q2/§ Q3 make both the
deadline and the replay timeout `PausableCountdown` instances. One `pause()` on `PracticeState` must
freeze the recorder, the active countdown **and** any replay timeout together.
**Warning signs:** a `saving` or `replaying` phase appearing while a modal is up; answer durations
shorter than the user's speech after a pause.

### Pitfall 3: Phase 2's timer tests silently disable Phase 1's save-failure guard

**What goes wrong:** a plan adds loop tests to `test/state/practice_state_test.dart`, converts the
file to `testWidgets` to get the fake clock, and the "save failure shows the same copy and does NOT
auto-restart recording" test starts failing — or worse, is quietly weakened to make it pass.
**Why it happens:** `lib/state/practice_state.dart:263-270` calls `FlutterError.reportError`, and the
widget binding turns reported errors into test failures. The file documents this at lines 265-268.
**How to avoid:** new files. `test/utils/pausable_countdown_test.dart` and
`test/state/practice_session_test.dart` (§ Q8).
**Warning signs:** a diff that changes `test()` → `testWidgets()` in `practice_state_test.dart`; a
newly added `FlutterError.onError = null` in a setUp.

### Pitfall 4: `pumpAndSettle()` hangs the countdown tests

**What goes wrong:** `await tester.pumpAndSettle()` after entering a countdown phase runs to the
default 10-minute timeout and fails with "pumpAndSettle timed out".
**Why it happens:** a `Timer.periodic` that triggers `setState`/`notifyListeners` keeps scheduling
frames, so the tree never settles.
**How to avoid:** explicit `await tester.pump(const Duration(seconds: 1))`. Also keep the countdown
ring a **determinate** `CircularProgressIndicator(value: …)`; an indeterminate one animates forever on
its own.
**Warning signs:** any `pumpAndSettle` in a test that touches `getReady`, `reading` or `recording`.

### Pitfall 5: A pending timer fails an otherwise-passing test

**What goes wrong:** a test asserts correctly and then fails at teardown with "A Timer is still
pending even after the widget tree was disposed."
**Why it happens:** `AutomatedTestWidgetsFlutterBinding` fails any test ending with a live timer —
documented in the repo at `test/services/recording_service_test.dart:66-68`.
**How to avoid:** `PausableCountdown.cancel()` in `PracticeState.dispose()` and in test `tearDown`s;
or pump each countdown to zero.

### Pitfall 6: The interruption never reaches Dart

**What goes wrong:** an answered phone call pauses the mic natively, but the app keeps showing
`recording` with a running `d` countdown, then "saves" a truncated answer with no explanation.
**Why it happens:** the native pause is only observable through `onStateChanged()`, and the current
`RecorderBackend` has no such method (`lib/services/recording_service.dart:27-36` — four methods only).
**How to avoid:** add `onPausedChanged` to the seam and subscribe for the lifetime of a session
(§ Q5). Cancel the subscription in `dispose()`.
**Warning signs:** a `d` countdown that reaches zero and commits a much shorter file than `d`.

### Pitfall 7: Releasing the wakelock while backgrounded throws

**What goes wrong:** the D-31 handler calls `disable()` on `onHide`, and on Android
`Wakelock.toggle` raises `NoActivityException("wakelock requires a foreground activity")`
[VERIFIED: `wakelock_plus-1.6.1/…/Wakelock.kt:17-19, 36`].
**How to avoid:** pin `^1.7.0` (its PR #134 defers the toggle when no activity is attached) **and**
wrap both calls in a `try/catch` that only `debugPrint`s — the UI-SPEC forbids a new user-facing
failure string for this.

### Pitfall 8: The `k` counter and the committed row count drift apart

**What goes wrong:** the completion screen says "8 answers recorded" and the session detail shows 7.
**Why it happens:** incrementing the answered counter on entering `saving` rather than after the
transaction commits. A save failure (`lib/state/practice_state.dart:254-273`) leaves the counter ahead.
**How to avoid:** increment **only** after `insertAnsweredSession`/`insertAnswer` returns. Note the
UI-SPEC's `k` (app-bar "Question k of N") is a *different* counter — it increments at the start of the
inter-question `getReady` — so keep them as two named fields, not one reused int.

### Pitfall 9: `resume()` on a finished replay restarts the whole answer

**What goes wrong:** the user pauses in the same frame the replay ends, then resumes, and hears the
answer from the beginning.
**Why it happens:** `AudioPlayer.resume()` is documented as *"Resumes the audio that has been paused
**or stopped**"* [VERIFIED: `audioplayers-6.8.1/lib/src/audioplayer.dart:265`].
**How to avoid:** guard the service's `resume()` on "the completion event has not yet fired".

---

## Code Examples

### Extending `RecorderBackend` and the production backend (§ Q1, § Q5)

```dart
// lib/services/recording_service.dart — production backend, extended
// Source: verified against ~/.pub-cache/hosted/pub.dev/record-7.1.1/lib/src/record.dart:93-141
class _RecordPackageBackend implements RecorderBackend {
  late final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String absoluteFilePath) =>
      // `const RecordConfig()` already carries
      // `audioInterruption: AudioInterruptionMode.pause` — "Pauses automatically,
      // resumes manually the recording" — which is D-31's policy verbatim.
      // Do NOT switch to `pauseResume`: that resumes recording after a call
      // without the user asking, which D-31 forbids.
      _recorder.start(const RecordConfig(), path: absoluteFilePath);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<bool> isPaused() => _recorder.isPaused();

  /// The ONLY way Dart learns about a pause it did not request — an answered
  /// call on iOS, audio-focus loss on Android. `RecordState.stop` is filtered
  /// out because stopping is already reported through `stop()`'s return value.
  @override
  Stream<bool> get onPausedChanged => _recorder
      .onStateChanged()
      .where((RecordState s) => s != RecordState.stop)
      .map((RecordState s) => s == RecordState.pause);

  @override
  Future<void> dispose() => _recorder.dispose();
}
```

### The honesty check after a requested pause (Pitfall 1)

```dart
/// Pauses the microphone and reports whether it ACTUALLY paused.
///
/// `record`'s pause is a guarded early-return on both platforms
/// (iOS `guard m_state == .record else { return }`, Android `if (isRecording())`),
/// so a call that lands in the wrong state returns normally having done nothing.
/// The caller must therefore never infer "the mic is paused" from "the call did
/// not throw" — publishing the paused banner on that inference is the phase's
/// worst available honesty failure (D-24).
Future<bool> pause() async {
  if (!_recording) return false;
  await _backend.pause();
  final bool paused = await _backend.isPaused();
  if (paused) _pausedCountdown?.pause();   // the `d` deadline freezes WITH the mic
  return paused;
}
```

### `PopScope` routing Back into the one confirmation dialog (§ Q6, D-29)

```dart
// Source: /Applications/flutter/packages/flutter/lib/src/widgets/pop_scope.dart:83-100
@override
Widget build(BuildContext context) {
  return PopScope<void>(
    // Interception is RELEASED in the completion state, where the back arrow
    // reappears and pops to Setup (UI-SPEC Interaction Contract).
    canPop: _state.phase == PracticePhase.complete,
    onPopInvokedWithResult: (bool didPop, void result) async {
      if (didPop) return;                 // the pop already happened
      final bool end = await _confirmStop();   // the SAME dialog the app-bar Stop opens
      if (!end || !mounted) return;
      Navigator.of(context).pop();
    },
    child: Scaffold(/* … */),
  );
}
```

### Lifecycle wiring for D-31 (§ Q5)

```dart
// Source: /Applications/flutter/packages/flutter/lib/src/widgets/app_lifecycle_listener.dart:64-76
late final AppLifecycleListener _lifecycle;

@override
void initState() {
  super.initState();
  _lifecycle = AppLifecycleListener(
    // Deliberately onHide (inactive -> hidden), NOT onInactive: `inactive` also
    // fires for the notification shade, Control Centre, the app switcher and an
    // UNANSWERED incoming-call banner. An answered call arrives on the audio
    // path instead (RecorderBackend.onPausedChanged), so the two signals stay
    // cleanly separated.
    onHide: () => unawaited(_state.handleInterruption()),
  );
  _pausedSub = _state.recordingService.onPausedChanged
      .where((bool paused) => paused)
      .listen((_) => unawaited(_state.handleInterruption()));
}

@override
void dispose() {
  _lifecycle.dispose();
  unawaited(_pausedSub.cancel());
  // ... Phase 1's existing stop -> dispose chain, unchanged ...
  super.dispose();
}
```

### Driving a backgrounding test (§ Q8)

```dart
testWidgets('backgrounding mid-recording commits the answer and parks paused',
    (tester) async {
  // ... pump the practice screen into `recording` ...

  // AppLifecycleListener asserts on illegal transitions
  // ('Invalid state transition from $previousState to $state'), so the chain
  // must be walked, not jumped. resumed -> inactive -> hidden fires onHide.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  await tester.pump();

  expect((await databaseHelper.listSessions()), hasLength(1));
  expect(state.phase, PracticePhase.paused);
  expect(find.text('Paused — your answer was saved when the app was interrupted.'),
      findsOneWidget);
});
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact on this phase |
|--------------|------------------|--------------|----------------------|
| `WillPopScope` | `PopScope` + `canPop`/`onPopInvokedWithResult` | `WillPopScope` deprecated in 3.12, `onPopInvoked` deprecated after **v3.22.0-12.0.pre** [VERIFIED: the `@Deprecated` annotation text in `pop_scope.dart:92-94`] | D-29 must use `onPopInvokedWithResult`. Any snippet using `WillPopScope` or `onPopInvoked` is stale. |
| `WidgetsBindingObserver.didChangeAppLifecycleState` | `AppLifecycleListener` | Flutter 3.13 | D-31's background detection. Both still work; the listener decodes the transitions this phase depends on. |
| `AppLifecycleState` = 4 states | 5 states, with `hidden` between `inactive` and `paused` | Flutter 3.13 | Tests must walk `resumed → inactive → hidden → paused`; the old 3-state mental model trips the assert. |
| `record` ≤6.x on older Flutter | **`record` 7.0.0 raised the floor to Flutter 3.44 / Dart 3.12** [VERIFIED: `record-7.1.1/CHANGELOG.md`, 7.0.0 entry] | 2026 | This project sits exactly on that floor (Flutter 3.44.6 / Dart 3.12.2). Do not downgrade Flutter. |
| `record` background recording service (Android) | **Removed in 7.0.0** (breaking) | 7.0.0 | Irrelevant here — recording is foreground-only by design — but it means any pre-7.x Android background-recording guidance is dead. |
| `record` iOS interruption bugs (`-10868` family) | 6.2.0 *"fix(Android/iOS): `AudioInterruptionMode` not pausing or resuming"*; 7.0.0 *"iOS: fix: Respect `shouldResume` system flag on audio interruption and don't stop on resume failure"* | 6.2.0 / 7.0.0 | STATE.md's blocker is addressed in the resolved version — **but the D-31 real-device UAT obligation stands.** |
| `wakelock` (original) | `wakelock_plus` (Flutter Community) | original discontinued | D-30 must use `wakelock_plus`; the original `wakelock` package is abandoned. |

**Deprecated/outdated — do not use:**
- `WillPopScope`, `PopScope.onPopInvoked`.
- `AndroidRecordConfig(useLegacy: true)` for this app (silent no-op pause below API 24).
- `AudioInterruptionMode.pauseResume` for this app (contradicts D-31).
- The `wakelock` package (superseded by `wakelock_plus`).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | On iOS, backgrounding suspends the Dart isolate quickly enough that `stopRecording()`'s await chain may not complete before suspension, so the D-31 commit can land on the next foreground rather than before backgrounding. | § Q5 | Moderate. If the isolate is killed outright rather than suspended, an in-flight answer could be lost on iOS backgrounding — a genuine PERSIST-01 gap. **Must be proven by the D-31 real-device UAT**, and the UAT script should include "background the app mid-recording, then relaunch and check history", not only the phone-call case. |
| A2 | `wakelock_plus` 1.7.0's Dart API (`enable`/`disable`/`toggle`/`enabled`) is identical to 1.6.1's, which is the version whose source was read on this machine. | § Q4, Standard Stack | Low. The 1.7.0 changelog lists only Android/Gradle/SPM changes. Re-confirm at implementation time by opening `~/.pub-cache/hosted/pub.dev/wakelock_plus-1.7.0/lib/wakelock_plus.dart` after `flutter pub get`. |
| A3 | `WakelockPlus.toggle` raises `MissingPluginException` (rather than silently succeeding) under `flutter test` with no mock handler, which is why the `ScreenWakeController` seam is required. | § Q4 | Low. Standard Flutter method-channel behaviour, but if it silently no-ops the seam is merely unnecessary, not wrong. |
| A4 | A whole-second-granularity `d` deadline is acceptable for a 10–120 s answer cap. | § Q2 | Very low. The user-visible readout is whole seconds either way; the failure mode is a sub-second-late auto-stop. |
| A5 | The `d` slider at 1-second divisions (110 steps) is draggable with acceptable precision on a real phone. | UI-SPEC D-16 | Low, and already anticipated — the UI-SPEC sanctions a 5-second-division fallback. Confirm during UAT and, if taken, verify the `{n} sec` format and the 60 default still hold. |
| A6 | The UI-SPEC's ⚠ unresolved N=0 Stop-dialog body ("Nothing has been recorded yet.") and the auto-stop-vs-Pause race resolution ("auto-stop wins; the pause applies at the next pausable phase") are the intended behaviours. | Open Questions | Low individually, but both are **explicitly flagged unresolved by the UI checker** and must be confirmed rather than assumed by the planner. |

---

## Open Questions (RESOLVED)

> All four were resolved during Phase 2 planning (2026-08-08). Each recommendation below was
> adopted; the `RESOLVED:` line on each question names the plan that owns the implementation.
> Nothing in this section is still open.

1. **The N = 0 Stop-confirmation dialog body (UI-SPEC E11, ⚠ unresolved).**
   - **RESOLVED: adopted as recommended — owned by `02-05-PLAN.md`** (Task 1 action + acceptance
     criterion for the exact string; recorded as flagged assumption #2 in that plan and authored as
     the `E11/empty` and `E11/zero-one-many` truths). Still carried to UAT for user confirmation,
     as a copy decision rather than an architectural one.
   - What we know: the Copywriting Contract locks bodies for N ≥ 2 and N = 1; Stop is enabled in every
     phase, including before the first answer commits; on confirm with 0 answers the app pops straight
     to Setup and nothing was written (D-26).
   - What's unclear: the exact body string for N = 0.
   - Recommendation: adopt the UI-SPEC's own proposal — *"Nothing has been recorded yet."* — keeping
     the title and both actions unchanged. This is a copy decision, not an architectural one; flag it
     for user confirmation but do not block planning on it.

2. **The `d` auto-stop landing in the same frame as a Pause tap (UI-SPEC carried-forward race, ⚠ unresolved).**
   - **RESOLVED: adopted as recommended — owned by `02-04-PLAN.md`** (Task 2 implements the deferred
     `_pendingPauseRequest`; Task 3 makes it an explicit test case; recorded as flagged assumption #2
     and as a `must_haves` truth in that plan).
   - What we know: Phase 1 already established "first signal wins, second is a no-op" for the
     manual-Stop vs auto-stop race, and proved it (`test/services/recording_service_test.dart:90-105`).
   - What's unclear: whether the losing Pause request should be dropped or deferred.
   - Recommendation: **auto-stop wins; the pause request is deferred and applied at the next pausable
     phase** (the UI-SPEC's stated assumption). This is strictly kinder than dropping it — a user who
     tapped Pause gets a paused session either way. Write it as an explicit test case, not as an
     inherited convention.

3. **Whether the interruption handler should skip the auto-replay entirely.**
   - **RESOLVED: skip, as recommended — owned by `02-05-PLAN.md`** (Task 2 suppresses the replay on
     the interruption path; `02-02-PLAN.md` flagged assumption #2 requires the replay gate to be
     written so 02-05 can suppress it without restructuring the post-commit tail).
   - What we know: D-31 says "finalized and saved first … and the session parks in the paused state."
     UI-SPEC's paused banner variant says *"your answer was saved when the app was interrupted."*
   - What's unclear: with `r = true`, should the replay be skipped outright, or queued for after Resume?
   - Recommendation: **skip it.** Replaying an answer into a screen the user is not looking at, or
     starting playback the instant they return, both contradict "resuming is always an explicit user
     tap." Low risk, easy to revisit.

4. **`PracticeState` extension vs. a session-scoped sibling `ChangeNotifier`** (explicitly listed under
   CONTEXT.md's Claude's Discretion).
   - **RESOLVED: extend, as recommended — owned by every plan in the phase.** No sibling notifier is
     created anywhere in `02-01` … `02-05`; the loop, the pause pair and the interruption handler are
     all methods on `PracticeState`, and the `stopRecording()` guard/ordering comments stay where the
     existing tests point.
   - Recommendation: **extend**, so the guard/ordering comments in `stopRecording()` stay where the
     existing tests point. Splitting the class would move the crash-safety contract, which is the one
     thing the phase must not regress.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | everything | ✓ | 3.44.6 stable (framework `ee80f08bbf`, 2026-07-08) | — |
| Dart SDK | everything | ✓ | 3.12.2 (2026-06-09) | — |
| `record` (resolved) | D-24, D-31 | ✓ | 7.1.1 + `record_android` 2.1.2 / `record_ios` 2.1.1 / `record_platform_interface` 2.1.0 | — |
| `audioplayers` (resolved) | pause during `replaying` | ✓ | 6.8.1 | — |
| `sqflite` / `sqflite_common_ffi` | D-26 write path + its host tests | ✓ | 2.4.3 / 2.3.0 (dev) | — |
| `wakelock_plus` | D-30 | ✗ (not yet in `pubspec.yaml`) | 1.7.0 available on pub.dev; 1.6.1 already in the local pub cache | None needed — a single `flutter pub add wakelock_plus` |
| `fake_async` | *not required* | present transitively (1.3.3) | — | `testWidgets` fake clock (preferred; § Q2) |
| pub.dev network access | `flutter pub add` | ✓ (verified by live registry queries this session) | — | — |
| Android SDK / iOS toolchain | on-device UAT for D-31 | not probed | — | The D-31 call-interruption UAT **cannot** be substituted by a host test; it is a required manual item. |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — `wakelock_plus` is a one-command install.

---

## Project Constraints (from CLAUDE.md)

Directives extracted from `./.claude/CLAUDE.md`; the planner must verify compliance.

| Directive | Phase 2 compliance |
|-----------|--------------------|
| Stack table: `record`, `audioplayers`, `sqflite`, `path_provider`, `path`, `google_fonts`, `cupertino_icons` | Unchanged. No version bump needed. |
| **"What NOT to Use": no `provider`/`riverpod`/`flutter_bloc`/`GetX`** | Honoured — `ChangeNotifier` + `ListenableBuilder` + `setState`. |
| **"What NOT to Use": no `drift`/`floor`/`ObjectBox`/`Isar`/`Hive`** | Honoured — one new hand-written SQL method (§ Q7). |
| **"What NOT to Use": no `firebase_auth` / `firebase_storage`** | Honoured — no Firebase at all in Phase 2. |
| **"What NOT to Use": no second icon package** | Honoured — Material icons (`pause_rounded`, `play_arrow_rounded`, `stop_rounded`) per UI-SPEC. |
| Supporting-libraries table lists `dart:convert`, `dart:io`, `ChangeNotifier`/`ValueNotifier`, `path`, `google_fonts`, `cupertino_icons` | `wakelock_plus` is **not** listed. **The planner must add it to that table** with the D-30 rationale, as 02-CONTEXT.md's `<canonical_refs>` instructs — and should correct the permission mechanism per § Q4 (window flag / idle timer, **not** a `WAKE_LOCK` permission). |
| Dev tools: `sqflite_common_ffi` is test-only, never shipped | Unchanged. |
| Minimize packages / "nhanh nhất, ít code nhất" | One package added, with a written justification and exactly one seam + two call sites. `PausableCountdown` is hand-rolled rather than imported for the same reason. |
| GSD workflow enforcement (no direct edits outside a GSD command) | Applies to execution, not to this document. |
| Docs must be thorough enough to hand off/resume | This phase's new invariants (silent-no-op pause, the four-clock freeze, the new-test-file rule) belong in code comments in the Phase 1 style, not only in planning docs. |

---

## Sources

### Primary (HIGH confidence) — read from disk this session

- `~/.pub-cache/hosted/pub.dev/record-7.1.1/lib/src/record.dart` — `pause`, `resume`, `isPaused`, `isRecording`, `onStateChanged`, `dispose`, `_initStateStream`
- `~/.pub-cache/hosted/pub.dev/record-7.1.1/lib/src/part/record_state.dart` — `_StateMixin`
- `~/.pub-cache/hosted/pub.dev/record-7.1.1/CHANGELOG.md` — 6.2.0 / 7.0.0 / 7.1.0 / 7.1.1 entries
- `~/.pub-cache/hosted/pub.dev/record-7.1.1/README.md` — platform feature-parity matrix
- `~/.pub-cache/hosted/pub.dev/record_platform_interface-2.1.0/lib/src/types/{record_config,audio_interruption_mode,android_record_config,ios_record_config,record_state}.dart`
- `~/.pub-cache/hosted/pub.dev/record_ios-2.1.1/ios/record_ios/Sources/record_ios/{Recorder.swift,delegate/RecorderFileDelegate.swift,extension/RecorderSessionExtension.swift}`
- `~/.pub-cache/hosted/pub.dev/record_android-2.1.2/android/src/main/kotlin/com/llfbandit/record/{RecorderWrapper.kt,record/recorder/{AudioRecorder,MediaRecorder,RecordThread}.kt}`
- `~/.pub-cache/hosted/pub.dev/audioplayers-6.8.1/lib/src/audioplayer.dart` — `pause`/`resume`/`stop`/`seek` and their docs
- `~/.pub-cache/hosted/pub.dev/wakelock_plus-1.6.1/{pubspec.yaml,CHANGELOG.md,lib/wakelock_plus.dart,android/src/main/AndroidManifest.xml,android/src/main/kotlin/.../Wakelock.kt,ios/.../WakelockPlusPlugin.m}`
- `~/.pub-cache/hosted/pub.dev/lints-6.0.0/lib/core.yaml` — `depend_on_referenced_packages`
- `/Applications/flutter/packages/flutter/lib/src/widgets/pop_scope.dart` — `PopScope`, deprecation text, doc semantics
- `/Applications/flutter/packages/flutter/lib/src/widgets/app_lifecycle_listener.dart` — callbacks and transition asserts
- `/Applications/flutter/packages/flutter/lib/src/widgets/binding.dart:1330` — `handleAppLifecycleStateChanged`
- `/Applications/flutter/packages/flutter_test/lib/src/binding.dart:3233-3243` — `_TestSamplingClock`
- `/Applications/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:26` — default `minSdkVersion = 24`
- Project source read in full: `lib/{main,data/questions,db/database_helper,services/recording_service,services/audio_player_service,state/practice_state,screens/practice_screen,widgets/phase_control}.dart`, `test/{services/recording_service_test,state/practice_state_test,widgets/phase_control_test}.dart`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `android/app/{build.gradle.kts,src/main/AndroidManifest.xml}`, `.planning/{REQUIREMENTS,STATE,config.json}`, `.planning/phases/01-*/01-CONTEXT.md`, `.planning/phases/02-*/{02-CONTEXT,02-UI-SPEC}.md`

### Secondary (MEDIUM confidence)

- pub.dev registry API — `https://pub.dev/api/packages/{wakelock_plus,record,audioplayers}` (latest versions + publish dates), `/score` (pana points, likes, 30-day downloads), `/publisher` (verified publisher)
- `https://raw.githubusercontent.com/fluttercommunity/wakelock_plus/main/wakelock_plus/CHANGELOG.md` — the 1.7.0 entry
- `flutter --version` / `dart --version` on this machine

### Tertiary (LOW confidence)

- None. No claim in this document rests on a web search or on training memory. The only LOW-confidence
  material is collected in the **Assumptions Log** and tagged `[ASSUMED]`.

---

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — every version read from `pubspec.lock` and cross-checked against both the
  on-disk pub cache and the live pub.dev registry; the one new package has a verified publisher and a
  perfect pana score.
- `record` / `audioplayers` pause semantics: **HIGH** — Dart API, native Swift and native Kotlin all
  read directly for the exact resolved versions, including the silent-no-op guards.
- Timer testability: **HIGH** — verified against the Flutter SDK on this machine and against the
  project's own existing, passing test file and its explanatory comments.
- Lifecycle / `PopScope`: **HIGH** — read from the Flutter 3.44.6 SDK source, including the deprecation
  annotation and the transition asserts.
- iOS behaviour under backgrounding (A1) and the `-10868` field behaviour: **LOW/MEDIUM** — the
  package-level fixes are verified from the changelog, but real-device behaviour is not provable on the
  host. This is precisely why D-31 mandates a real-device UAT.
- Pitfalls: **HIGH** for 1, 2, 3, 4, 5, 6, 7, 9 (each traced to a specific line of source);
  **MEDIUM** for 8 (a reasoning-level counter-drift risk, not an API fact).

**Sections deliberately omitted:**
- *Validation Architecture* — `.planning/config.json` sets `workflow.nyquist_validation: false`.
- *Security Domain* — `.planning/config.json` sets `workflow.security_enforcement: false`. (No new
  permission, no network, no user input crossing a trust boundary is introduced this phase; the only
  data written is app-authored strings and app-generated file paths through sqflite's parameterised
  helpers, unchanged from Phase 1.)

**Research date:** 2026-08-08
**Valid until:** 2026-09-07 (30 days). The stack is stable, but `record`, `audioplayers` and
`wakelock_plus` were all published within the last 6 weeks — re-run `flutter pub outdated` before
implementation if more than a month elapses.
