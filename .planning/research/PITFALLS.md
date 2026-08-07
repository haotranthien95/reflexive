# Pitfalls Research

**Domain:** Flutter mobile app — timed audio-recording practice loop with local-first persistence and a small Firestore-backed content bank
**Researched:** 2026-08-07
**Confidence:** MEDIUM (mix of MEDIUM-confidence library docs via Context7 and LOW-confidence general web search; no HIGH-confidence curated sources were available this run — treat specifics as directional and verify against current `record`/`cloud_firestore` docs at implementation time)

## Critical Pitfalls

### Pitfall 1: Countdown timer drifts and desyncs from the actual recording duration

**What goes wrong:**
A `Timer.periodic(Duration(seconds: 1), ...)` that decrements a counter each tick looks correct in a simulator but drifts under real load — widget rebuilds, GC pauses, other timers, or a busy frame can delay a tick by tens to hundreds of milliseconds. Over a 3–10s countdown this is usually invisible, but the drift compounds across a session of 20+ questions, and worse, if the *recording start/stop* is driven by counting ticks rather than by elapsed wall-clock time, the actual audio file duration silently diverges from the configured `d` (max recording duration) — the countdown UI can reach "0" a beat before or after the recorder actually stops.

**Why it happens:**
Developers reach for the pattern "decrement `remaining` by 1 each periodic callback" because it's the most obvious mental model. It works in a stopwatch app where sub-second accuracy doesn't matter, but this app's entire value proposition (`t` seconds to think, hard-stop at `d` seconds) is precise, time-boxed behavior — the countdown *is* the mechanic, not decoration.

**How to avoid:**
Never trust tick count as the source of truth. Capture a `DateTime` (or `Stopwatch`) at the moment the phase starts, and on every tick compute `remaining = target - Stopwatch.elapsed` (or `endTime.difference(DateTime.now())`), then display/round that value — this self-corrects for drift instead of accumulating it. Drive the auto-stop-recording transition off the same `Stopwatch`/deadline, not off "tick counter hit zero", so the UI countdown and the actual recording cutoff are reading the same clock. Keep the periodic tick's callback body trivial (just a `setState` with the recomputed value) — do nothing else in it.

**Warning signs:**
- Countdown UI and actual audio file length disagree by more than ~200ms in manual testing.
- Long test sessions (20+ questions) show later questions' recordings running noticeably longer/shorter than earlier ones.
- Any `await` (file I/O, Firestore call) placed inside the timer callback or inside `build()` during a session.

**Phase to address:**
The phase implementing the practice loop / countdown mechanic (core timed loop). This is foundational — retrofitting a wall-clock-based timer after the UI is built around tick-counting is a rewrite, not a patch.

---

### Pitfall 2: Recording silently fails to resume (or never started) after an interruption

**What goes wrong:**
An incoming call, Siri, another app briefly grabbing the mic, or the user switching apps mid-recording can interrupt audio capture. On iOS specifically there's a documented failure mode where the microphone does not reactivate after a call-interruption ends (`AVFAudio` error `-10868`) unless the audio session is explicitly reconfigured. If the app doesn't listen for interruption events at all, the recorder can be left in a "recording" state in the UI while zero audio is actually being captured — the user finishes speaking, taps stop, and gets a silent or corrupt file with no error surfaced.

**Why it happens:**
Interruption handling is invisible in the happy-path (simulator, no incoming calls) so it's easy to ship without it. The `record` package's Android side auto-pauses on audio-focus loss by default, but iOS interruption handling and resume behavior is less automatic and has known rough edges.

**How to avoid:**
Use the `record` package's `AudioInterruptionMode` explicitly (`pause` or `pauseResume` — not the default `none`) rather than leaving it implicit, and pick `pause` (manual resume) over `pauseResume` for this app: on a hard interruption (incoming call) you likely want the countdown loop to pause and show the user an explicit "resume" affordance rather than silently auto-resuming into a recording the user didn't expect. Listen for the recorder's state stream and treat any unexpected `pause`/`stop` event during an active recording phase as a signal to pause the whole session timer, not just the audio — don't let the countdown keep running while the recorder is silently paused. On iOS, treat a resume failure (no audio frames after resume) as detectable-and-recoverable: verify amplitude/stream activity resumes, and if not, prompt the user to retry that question rather than saving a silent file.

**Warning signs:**
- Testing a session while receiving a real phone call (not just simulator) produces a 0-byte or silent recording.
- No manual test of "background the app mid-recording, come back" exists before ship.
- Recorder's `onStateChanged` / interruption stream is never subscribed to.

**Phase to address:**
The phase implementing audio recording/playback (core capture mechanic). Should be validated with a manual on-device test (real interruption, not simulator) before that phase is marked done.

---

### Pitfall 3: Crash or force-kill mid-write corrupts session history or leaves orphaned audio files

**What goes wrong:**
The project's own reliability requirement is "write each question+recording to local DB/storage immediately after it's captured." If that write is not atomic, a crash or OS kill at the wrong instant (writing session metadata, or the audio file itself) can leave a truncated/corrupt JSON or DB row, or an audio file that exists on disk but was never registered in the session's metadata (orphaned file — wastes storage and can confuse the history UI, e.g. showing a question as "answered" with no playable file, or vice versa).

**Why it happens:**
Naive `file.writeAsBytes(...)` or a single non-transactional DB `insert` followed by a separate file write are two operations that are *not* atomic together — a crash between them (or during either one) leaves inconsistent state. This is easy to miss because crashes during a specific few-hundred-millisecond write window are rare in dev testing but will happen in the wild given enough sessions.

**How to avoid:**
Use the temp-file-then-rename pattern for the audio file itself: record to a temp path, and only `rename()` it into its final location after the recording is confirmed stopped/flushed (POSIX rename is atomic on the same filesystem, so a crash mid-write leaves either nothing or a fully-written file, never a partial one). Only after the file rename succeeds, write/commit the corresponding metadata row (question index, file path, timestamp) — order matters: file first, then metadata pointing at it, so metadata is never orphaned pointing at a nonexistent file, and any file that exists without matching metadata is trivially identifiable as orphaned garbage. On app startup, run a lightweight sweep: any audio file on disk not referenced by any session's metadata is a leftover from an interrupted write and safe to delete; any temp files from an interrupted write should also be cleaned up. Prefer a real embedded DB (sqlite via `sqflite` or `drift`, or even `Hive`/`Isar`) over hand-rolled JSON-file writes for the metadata layer — these give you transactional single-row writes so a crash can't corrupt the *other* already-saved questions in the same session.

**Warning signs:**
- Metadata and audio files are written as two independent, uncoordinated steps with no defined ordering.
- No startup-time reconciliation/cleanup logic exists for orphaned files or temp files.
- Session history storage uses a single monolithic file (e.g. one big JSON array for all sessions) that gets fully rewritten on every question — this both defeats "incremental" writes and makes corruption of one question corrupt the entire history.

**Phase to address:**
The phase implementing local persistence / session history storage. This is the phase most likely to need deeper design attention given it's explicitly called out as a reliability requirement in PROJECT.md — flag it for extra scrutiny/testing (simulate kill mid-session) before considering it done.

---

### Pitfall 4: App backgrounded or killed mid-recording loses more than expected

**What goes wrong:**
`WidgetsBindingObserver.didChangeAppLifecycleState` is the standard hook for reacting to backgrounding, but it has real limitations that matter for a recording app: (1) it also fires for *unrelated* transitions like a permission dialog or biometric prompt appearing (`inactive`/`resumed` churn that isn't real backgrounding), so naively pausing the session on every `inactive` event causes false pauses; (2) work started in `paused`/`detached` has only a few hundred milliseconds before the OS can suspend the process, so "gracefully stop and save the recording" logic triggered from that callback may not finish; (3) a hard kill (task-switcher swipe, OS OOM kill, user force-quits) delivers **no lifecycle callback at all** — there is no cleanup opportunity, period.

**Why it happens:**
Lifecycle handling is often bolted on late, after the core loop is built assuming the app is always in the foreground. Developers test by pressing home and returning quickly, which never exercises the "OS reclaimed the process" or "hard kill" paths that will happen in real usage.

**How to avoid:**
Don't rely on lifecycle callbacks to *save* data — rely on Pitfall 3's incremental, immediately-committed writes so that by the time any lifecycle event fires, the last fully-answered question is already durably saved; the lifecycle callback's job is only to gracefully pause the *currently in-flight* question (stop the countdown/recorder, mark that one question as incomplete/needs-retry) rather than to perform first-time persistence. Distinguish real backgrounding from transient `inactive` churn by only acting on `paused` (not `inactive`) for anything destructive, and debounce/guard against rapid state flapping. On resume (`resumed` after having been `paused`), explicitly check whether a recording was left active and recover into a known-safe state (e.g. show "recording was interrupted, retry this question") rather than assuming state is exactly as it was left. Accept that a hard-kill will lose at most the *current* in-progress question's audio (not the whole session) — this is the achievable guarantee, not "lose nothing ever."

**Warning signs:**
- Session-pause logic is written inside `inactive` rather than `paused`.
- No test exists for "swipe-kill the app mid-recording, relaunch, check history."
- The observer is registered but never removed in `dispose()` (memory leak / duplicate callbacks after widget rebuilds).

**Phase to address:**
The phase implementing the practice loop's Pause/Resume/Stop app-bar controls and session lifecycle — should be explicitly tested against "backgrounded" and "force-killed" scenarios, not just "paused via the in-app Pause button."

---

### Pitfall 5: Firestore reads/costs blow up from avoidable listener and query patterns

**What goes wrong:**
Even though this project's question bank is small and read-mostly, two common mistakes cause disproportionate Firestore reads: (1) using a live `snapshots()` listener for a bank that only needs to be fetched once per session-setup screen — the listener stays subscribed for the widget's whole lifetime and re-reads on every reconnect; (2) not enabling/relying on the SDK's default offline persistence and instead fetching from source on every screen visit, ignoring the cache. There's also a specific billing footgun: a snapshot listener disconnected for more than 30 minutes (app backgrounded, phone loses signal) is billed as a brand-new full query on reconnect rather than an incremental diff — for a "select topics" screen a user might open, walk away, and return to, this can matter over many sessions even at small scale.

**Why it happens:**
`snapshots()` (live listener) is the first thing shown in most Firestore tutorials, so it gets reached for even when a one-time `get()` is the correct tool. For a picker screen (select topics/CEFR level before starting a session), the data doesn't need to be live — it only needs to be fresh enough at session-setup time.

**How to avoid:**
Use a one-shot `get()` for the question bank fetch on the session-setup screen (topics list, and the questions themselves once topics/level are chosen) rather than a `snapshots()` listener — this content changes only via the user's own JSON import action, not from another writer, so there's no need for live updates. Rely on cloud_firestore's default mobile offline persistence (enabled by default on iOS/Android) rather than re-fetching aggressively; explicitly set `Settings(persistenceEnabled: true)` for clarity even though it's the default. Keep queries narrow — filter by `subject` and `level` server-side (`where` clauses) rather than fetching the whole collection and filtering client-side, since the collection will grow via bulk JSON imports over time. Given the bank is genuinely small (tens to low-hundreds of questions), this is a low-risk area at current scale — the guidance matters more as the bank grows via repeated JSON imports.

**Warning signs:**
- `.snapshots()` used anywhere that isn't actually displaying live, continuously-updating data.
- Full collection fetched client-side then filtered in Dart instead of using Firestore `where`.
- No explicit `Settings(persistenceEnabled: true)` and no thought given to what happens when the setup screen is opened with no network.

**Phase to address:**
The phase implementing the question bank fetch / session setup screen (topics + level selection) and the JSON import feature. Low urgency given expected scale — flag as "verify pattern once, don't over-invest."

---

### Pitfall 6: Bulk JSON import partially succeeds and leaves the bank in an inconsistent state

**What goes wrong:**
The JSON import feature (`{"data": [{content, subject, level}, ...]}`) writes many documents to Firestore from a single user action. A naive loop of individual `add()` calls with no error handling means a network blip partway through leaves some questions imported and others silently dropped, with the user having no idea which ones succeeded — and no easy way to know without re-diffing the whole file against the bank.

**Why it happens:**
Import UIs are often built for the happy path (small test file, good network) and error handling is deferred; since this is a single-user local tool, "just re-run it" seems fine until duplicate entries pile up from partial-retry imports (no dedup on retry = duplicate questions in the bank).

**How to avoid:**
Batch the writes using Firestore's `WriteBatch` (up to 500 operations per batch) so each batch either fully commits or fully fails — this bounds the "partial success" blast radius to one batch instead of one document at a time, and lets the import report success/failure per batch rather than silently degrading. Validate the JSON shape (`content`/`subject`/`level` present and non-empty) client-side before writing anything, and show the user a clear count ("47 imported, 3 skipped: missing content") rather than a silent all-or-nothing result. Since re-import is a realistic user action (pasting fresh LLM-generated batches), keep imports idempotent-enough in intent even though full dedup isn't required for v1 — at minimum, warn the user the action is additive and will create duplicates if the same file is imported twice.

**Warning signs:**
- Import loop uses per-document `add()` with no batching and no aggregated error reporting.
- No client-side schema validation before writing to Firestore (malformed rows silently become malformed documents).
- No user-visible confirmation of how many questions were actually imported vs. skipped.

**Phase to address:**
The phase implementing the JSON bulk import feature.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|------------------|
| Store session history as one big JSON file instead of an embedded DB (sqlite/Hive/Isar) | Zero new dependency, simplest possible code | Defeats incremental-write reliability requirement; one corrupt write can damage the entire history, not just one session | Never — this project's own reliability requirement (write-as-you-go) effectively requires per-record durability, which a monolithic file can't give cheaply |
| Skip `AudioInterruptionMode` configuration (use package default) | Less code to write initially | Silent recording failures on real interruptions (calls), hard to debug later since it only reproduces with real phone events | Only acceptable for a throwaway prototype, never for the shipped v1 |
| Decrement a tick counter for the countdown instead of computing from a captured start time | Simpler mental model, works fine in quick manual tests | Countdown/recording-cutoff drift compounds across a session; becomes visibly wrong at scale (many questions) | Never — the fix costs almost nothing extra, there's no scenario where the naive version is worth keeping |
| Use `snapshots()` listeners for the (rarely-changing) question bank instead of one-shot `get()` | Marginally simpler code, "just works" | Unneeded background listeners, extra reads on long-idle reconnects, no real benefit since only the user's own import changes the data | Acceptable if the app later adds a "live sync while importing on another device" feature — not applicable to this single-user local app |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|-------------------|
| `record` package (audio capture) | Leaving `AudioInterruptionMode` at its default and never subscribing to the recorder's state stream, so interruptions go unnoticed | Explicitly set `AudioInterruptionMode.pause`, subscribe to state changes, and treat an unexpected pause/stop during an active recording phase as a session-level event, not just an audio-layer detail |
| `record` package — iOS background | Recording silently stops when the app backgrounds because `UIBackgroundModes` isn't configured | If any background recording continuation is desired, add `audio`/`fetch` to `Info.plist` `UIBackgroundModes`; otherwise explicitly pause the session (don't let the recorder run in an undefined state) when backgrounded |
| `permission_handler` | Requesting mic permission once at app launch, then never handling the "permanently denied" state gracefully later | Request permission contextually right before the first recording, and when status is `permanentlyDenied`, show a clear prompt routing to `openAppSettings()` rather than silently failing to record |
| `cloud_firestore` (question bank) | Using `.snapshots()` for a picker screen that doesn't need live updates | Use one-shot `get()` for setup-screen reads; reserve listeners for cases with genuine concurrent-writer live-update needs (none exist in this app's v1 scope) |
| `cloud_firestore` transactions/batches | Assuming a transaction or batch write will work offline (e.g. during JSON import with flaky connectivity) | Transactions require being online (reads fail immediately if offline); design the import flow to detect and surface connectivity failures rather than assuming eventual consistency will save it |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Heavy work (file I/O, JSON parsing, DB writes) executed synchronously inside the countdown `Timer.periodic` callback or inside `build()` | Visible stutter/jank right as a question transitions (countdown hits zero, recording starts/stops) — exactly the moments where a snappy feel matters most | Keep the timer callback to a `setState` with a precomputed value only; do all persistence work in an async task kicked off outside the paint-critical path (e.g. right after `stop()` returns, not inside the tick) | Becomes visible immediately on real devices once history writes are added — easy to miss in dev if writes are still stubbed out |
| Rebuilding the entire practice-loop screen (including the countdown ring/number) on every 1-second tick when the countdown is nested deep in a large widget tree | Frame time creeps up over a session, especially on lower-end Android devices, as more widgets participate in each tick's rebuild | Isolate the countdown display in its own small widget (or `ValueListenableBuilder`/`AnimatedBuilder`) so each tick only rebuilds the number/ring, not the whole screen | Noticeable on mid/low-tier Android hardware even at small scale (single user, but device variety matters) |
| Fetching the full question bank client-side and filtering by topic/level in Dart | Slightly slower setup-screen load as the bank grows via repeated JSON imports; wasted reads | Filter server-side with Firestore `where('subject', isEqualTo: ...)` / `where('level', isEqualTo: ...)` | Only matters once the bank grows past a few hundred questions via repeated imports — low urgency at v1 scale but cheap to do right from the start |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Firestore question-bank collection left with open/default rules while relying only on "no auth UI" for protection | Anyone with the Firebase config (extractable from the compiled app) could read/write/spam the collection since there's no user auth gating access | Even with no end-user login, set Firestore security rules that at minimum restrict writes (e.g. require a build-time App Check token, or accept that v1 is single-user and the risk is low but document it as a known gap rather than an oversight) |
| Audio recordings (potentially sensitive spoken content) stored in a world-readable app directory or with no OS-level file protection | On a lost/shared device, another app or user could access recorded speech | Store audio files under the app's private documents directory (default for `path_provider`'s `getApplicationDocumentsDirectory()`), not external/shared storage — this is likely already the natural choice given "local-only" is a stated constraint, but worth confirming explicitly |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-------------------|
| Countdown-to-record transition has no distinct audio/haptic/visual cue at the exact moment recording starts | User doesn't realize recording began until partway through their first word, cutting off the start of their answer — undermines the "reflex practice" value | Give a clear, near-instant signal (short haptic + visual state change) exactly when recording starts, decoupled from any animation easing that might visually lag the real start moment |
| Auto-stop at max duration `d` has no warning before cutoff | User is speaking naturally and gets abruptly cut off mid-sentence with no anticipation, feels jarring/punitive rather than like a fair drill constraint | Show a subtle visual warning (e.g. color change, small ticking indicator) in the last 1–2 seconds before auto-stop, consistent with the "timed pressure" mechanic being the *point*, not an ambush |
| Stop-recording confirmation dialog (for the session-level Stop button) reuses the same style/weight as trivial confirmations | Users might not register that Stop actually discards/ends the session, or conversely get confirmation-fatigue and blow past it | Keep the Stop confirmation distinct and clear about consequence ("End session? Your answered questions are saved, remaining questions won't be asked") since history is saved incrementally — the copy should reflect that reality accurately, not vaguely warn about "losing progress" when progress is in fact saved |

## "Looks Done But Isn't" Checklist

- [ ] **Countdown timer:** Often "looks done" after testing in a simulator with no other load — verify by running a full 20+ question session on a real mid-tier Android device and comparing displayed countdown transitions against actual recorded-file durations.
- [ ] **Recording interruption handling:** Often missing real-device interruption testing — verify by placing/receiving an actual phone call mid-recording (not just backgrounding the app) and confirming the app recovers gracefully rather than saving silence.
- [ ] **Incremental crash-safe writes:** Often "looks done" because it works when the app exits normally — verify by force-killing the app (swipe from recents, or `adb shell am kill`) mid-recording and mid-metadata-write, then relaunching and confirming history is intact up to the last fully-completed question with no orphaned files.
- [ ] **JSON import:** Often tested only with a small, perfectly-formed file — verify with a malformed file (missing fields, wrong types, empty `data` array) and confirm the app reports a clear per-row outcome rather than crashing or silently importing nothing.
- [ ] **Firestore offline behavior:** Often untested without network — verify the session-setup screen (topic/level picker) behaves sanely in airplane mode using the cached bank, rather than hanging or showing an empty list with no explanation.
- [ ] **App-bar Pause/Resume during recording:** Often only tested as a UI toggle — verify that Pause actually pauses the underlying recorder (not just the visible timer), and Resume genuinely continues capturing audio rather than restarting a fresh empty recording.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|------------------|
| Countdown/recording drift discovered late (post-implementation) | MEDIUM | Refactor the tick handler to compute remaining time from a captured deadline instead of decrementing; audit any place that used tick-count as a proxy for elapsed time (e.g. "record for N ticks") and replace with deadline-based stop logic |
| Orphaned audio files / corrupted metadata discovered in production-like testing | LOW–MEDIUM | Add a startup reconciliation pass: list all audio files, cross-reference against session metadata, delete unreferenced files and flag sessions with metadata pointing at missing files as "recording unavailable" rather than crashing the history view |
| Interruption handling missing after initial ship | MEDIUM | Add `AudioInterruptionMode` + state-stream subscription as a follow-up patch; since recordings are already saved incrementally per Pitfall 3, this is additive and doesn't require a data-model change |
| Firestore listener/read costs discovered to be higher than expected | LOW | Swap `snapshots()` calls to one-shot `get()` on the affected screens; low-risk change since the question bank isn't meant to be live-updating in this app |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| Countdown timer drift / desync from recording | Core practice-loop / countdown phase | Real-device multi-question session; compare displayed countdown transitions to actual audio file durations |
| Recording fails to resume after interruption | Audio recording/playback phase | Manual real-device test: receive an actual call mid-recording, confirm graceful pause/resume or clear retry prompt |
| Crash-safety of incremental writes / orphaned files | Local persistence / session history phase | Force-kill app mid-session (real device or `adb`), relaunch, verify history integrity and no orphaned files |
| App lifecycle mishandling (background/kill mid-recording) | Practice-loop session controls (Pause/Resume/Stop, app-bar) phase | Background and force-kill tests during an active recording, not just via the in-app Pause button |
| Firestore read/cost footguns | Session setup / topic picker + JSON import phase | Code review for `snapshots()` vs `get()` usage; airplane-mode test of setup screen |
| Partial/inconsistent bulk JSON import | JSON import feature phase | Import a deliberately malformed file and a file that exceeds batch limits; confirm clear per-row reporting, no silent partial success |

## Sources

- [Permission Handling in Flutter](https://atuoha.hashnode.dev/permission-handling-in-flutter) — web search, LOW confidence
- [How to Handle Permissions in Flutter: A Comprehensive Guide (freeCodeCamp)](https://www.freecodecamp.org/news/how-to-handle-permissions-in-flutter-for-beginners/) — web search, LOW confidence
- [record / audio_session interruption issue #162](https://github.com/ryanheise/audio_session/issues/162) — web search, LOW confidence
- [audio_session | Flutter package](https://pub.dev/packages/audio_session) — web search, LOW confidence
- [Understanding Flutter's Timer class and Timer.periodic (LogRocket)](https://blog.logrocket.com/understanding-flutter-timer-class-timer-periodic/) — web search, LOW confidence
- [Flutter Case Study: A More Accurate Timer](https://medium.com/geekculture/flutter-case-study-timer-precision-a1154b431e8) — web search, LOW confidence
- [Flutter performance profiling (docs.flutter.dev)](https://docs.flutter.dev/perf/ui-performance) — web search, LOW confidence
- [Read and write files (docs.flutter.dev cookbook)](https://docs.flutter.dev/cookbook/persistence/reading-writing-files) — web search, LOW confidence
- [Stop Silent Data Loss: checksum + atomic writes + temp file patterns](https://tech-champion.com/data-science/stop-silent-data-loss-checksum-atomic-writes-temp-file-patterns/) — web search, LOW confidence
- [Firestore pricing (Google Cloud)](https://cloud.google.com/firestore/pricing) — web search, LOW confidence
- [Access data offline | Firestore](https://firebase.google.com/docs/firestore/manage-data/enable-offline) — web search, LOW confidence
- [How to drastically reduce the number of reads when no documents are changed in Firestore (Medium)](https://medium.com/firebase-tips-tricks/how-to-drastically-reduce-the-number-of-reads-when-no-documents-are-changed-in-firestore-8760e2f25e9e) — web search, LOW confidence
- [flutter/flutter issue #96779 — WidgetBindingObserver lifecycle timing on iOS](https://github.com/flutter/flutter/issues/96779) — web search, LOW confidence
- [Mastering Flutter App Lifecycle with WidgetsBindingObserver (Medium)](https://medium.com/@krishna.ram30/mastering-flutter-app-lifecycle-with-widgetsbindingobserver-1350319cc3fa) — web search, LOW confidence
- `record` package README and source (`AudioInterruptionMode`, background recording docs) — Context7 `/llfbandit/record`, MEDIUM confidence
- FlutterFire `cloud_firestore` Settings/SnapshotMetadata/transaction source — Context7 `/firebase/flutterfire`, MEDIUM confidence

---
*Pitfalls research for: Flutter spoken-English reflex-practice app (audio recording, countdown timers, incremental crash-safe local writes, Firestore-backed question bank)*
*Researched: 2026-08-07*
