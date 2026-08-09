# Phase 3: Real Question Bank via Firestore - Context

**Gathered:** 2026-08-09
**Status:** Ready for planning
**Mode:** Default interactive discuss — four gray areas presented, all four selected and discussed

<domain>
## Phase Boundary

Phase 2 built the whole timed drill against `PlaceholderQuestionSource` and a hardcoded `kSubjects` list, deliberately routing every prompt lookup through the `QuestionSource` seam so this phase could swap the data source without touching loop logic. Phase 3 performs that swap: **Setup's topic checkboxes are populated from the distinct `subject` values actually present in Firestore (SETUP-01/BANK-02), and starting a session issues a real Firestore query for only the questions matching the selected topics and CEFR level (BANK-03), against the fixed `{id, content, subject, level, created_at}` schema (BANK-01).**

This is also the phase that first connects the app to a network. Everything about that — the `INTERNET` permission, offline behaviour, failure surfaces, and the open-rules posture — is in scope precisely because it is a first.

**In scope:** SETUP-01, BANK-01, BANK-02, BANK-03. Plus the Firebase project wiring (`firebase_options.dart` via `flutterfire configure`), `firestore.rules`, and a throwaway dev seed script that exists only so this phase is demoable.

**Explicitly NOT in scope:**
- **In-app JSON import** — IMPORT-01..04, Phase 4. The dev seed script (D-40) is a developer tool run from the maintainer's machine, not a shipped feature, and it is superseded when Phase 4's real importer lands.
- **The ~10 seeded starter topics** — IMPORT-05, Phase 4. Phase 3 seeds only enough content to prove the query paths, including at least one deliberately empty topic×level combination.
- **The 3-screen audit** — UI-03, Phase 4.
- **Shuffled question order** — LOOP-V2-01, v2. D-23's sequential order stands; D-39 only defines what "sequential" means against Firestore.
- **Firebase Auth, Firebase Storage, cloud sync of history/recordings** — permanently out of scope per PROJECT.md. Recordings and session history stay device-local and untouched by this phase.

Everything Phase 1 and Phase 2 locked is inherited unchanged: the crash-safe write ordering, the frozen `sessions`/`question_answers` schema, the pause/interruption contract (D-24/D-25/D-31), and the rule that the practice loop never waits on anything it wasn't handed at construction.

</domain>

<decisions>
## Implementation Decisions

### Fetch timing & query shape

- **D-32:** A session takes **two Firestore reads**, both on the Setup screen: (1) a read of the `questions` collection to derive the distinct `subject` values for the topic checkboxes (BANK-02), and (2) on START SESSION, a **real filtered query** — `where subject in <selected topics>` + `where level == <chosen level>` + `orderBy created_at` — that returns only this session's questions (BANK-03).
  *Known and accepted redundancy:* deriving distinct subjects requires reading every document, because the client SDK has no field projection, so read (1) already contains read (2)'s data. Filtering that in memory was the alternative and was rejected — the user chose a genuine filtered query so BANK-03 is satisfied literally and the query that runs is the query that is tested, rather than one code path deriving topics and a second, untested one deriving questions. *Alternatives rejected: one bulk fetch at Setup with client-side Dart filtering (cheaper, but makes BANK-03 an in-memory `where` clause); a `.snapshots()` listener (a bank that can change underneath an in-flight session).*
  — **Reversibility:** reversible — collapsing back to one fetch means deleting the second query and filtering the already-held list; no data or contract changes.

- **D-33:** **The Start-tap query blocks on the Setup screen.** START SESSION enters a busy state while the query runs, and `PracticeScreen` is pushed only once the resolved question list is in hand. A failure therefore leaves the user on Setup, with every setting intact and nothing to unwind. This preserves `PracticeScreen`'s Phase 2 constructor contract — it is handed everything it needs and never discovers a dependency mid-session. *Alternatives rejected: pushing first and loading under the LOOP-01 get-ready countdown (a slow query forces either stretching the fixed 3 s countdown or erroring on a screen the user just entered); prefetching on every topic/level change (many queries and a Start-during-flight race).*
  — **Reversibility:** reversible.

- **D-34:** **`QuestionSource.questionsFor(config)` becomes `Future<List<String>>` and is called only from Setup.** `PracticeState` drops its hardcoded `final QuestionSource questionSource = const PlaceholderQuestionSource()` field and instead receives the already-resolved `List<String>` through its constructor. `_pickQuestion()` stays a **pure synchronous function of `questionNumber`** — which is what keeps D-23's cycling intact and keeps `reading` and `arming` showing the same prompt for the same question. The loop remains provably network-free: after Start, there is no code path from the practice screen to Firestore. *Alternatives rejected: carrying the prompts inside `SessionConfig` (that class is documented as "what Setup decided", and its no-serialization rule exists to keep it a settings object); keeping `QuestionSource` synchronous and injecting a pre-loaded instance (an object whose correctness depends on having been awaited first, which silently returns an empty bank if it wasn't).*
  — **Reversibility:** costly — the async signature and the constructor change touch `PracticeState`, `PracticeScreen`, `SetupScreen` and every test that constructs them.

- **D-35:** **Setup re-reads the subjects every time it appears** — on `initState` and again on return from Practice or History. Always current, no staleness rule to explain, and it means Phase 4's importer needs no extra wiring: finishing an import and landing back on Setup shows the new topics automatically. One read per Setup visit is trivially cheap at this scale, and the SDK cache absorbs repeats. *Alternatives rejected: caching for the process lifetime (a Phase 4 import would need an app restart to become visible — a papercut we would be knowingly building in); a manual refresh affordance (a new control on a deliberately spare screen that the user has to know to use).*
  — **Reversibility:** reversible.

### Offline & failure behavior

- **D-36:** **Offline support is the Firestore SDK's own on-device cache and nothing else.** No mirror table, no bundled fallback bank. After one successful online Setup visit, both the subjects read and the Start query are served from cache with the network off, which is what keeps the drill usable on a plane or a dead connection. **This narrows a standing requirement and PROJECT.md must say so plainly:** "the practice loop runs fully offline" becomes **"the practice loop runs offline after one successful online Setup visit"** — a genuinely first-run-offline device has an empty cache and cannot start a session. *Alternatives rejected: keeping the ~20 placeholder prompts as a last-resort fallback (keeps alive a second question source Phase 2 built to be deleted, and the user cannot tell which bank they are drilling against); mirroring the bank into the sqflite DB (a schema version bump on the deliberately frozen tables, plus a sync/staleness rule, against the "leanest code" constraint); requiring network outright (contradicts the standing offline requirement).*
  — **Reversibility:** reversible — adding a fallback or a mirror later is additive.

- **D-37:** **The Topics card has three distinct states: loading, loaded-but-empty, and could-not-load.** The existing `setup-topics-empty` copy ("No topics yet — Import some questions and your topics will show up here") means *the bank is genuinely empty*, and is never shown for a read failure; the failure state gets its own message and a **Retry** button. Start is disabled in both non-loaded states. This applies Phase 1 Plan 6's established rule — *a read failure is never presented as missing data* — to the question bank. *Alternatives rejected: one shared state with a Retry button (tells a user with a full bank and flaky network that their questions are gone — the exact failure Phase 1 Plan 6 was written to prevent); a snackbar over a permanently spinning card (unrecoverable once dismissed, and unreadable to a widget test).*
  — **Reversibility:** reversible.

- **D-38:** **A failed Start query keeps the user on Setup** with a short inline failure message beside the Start button and every chosen topic, level and slider value preserved; tapping Start again retries. Follows Phase 1's error-copy convention — one fixed user-facing failure string, with exception detail going to `debugPrint`/`FlutterError.reportError` and never to the screen. *Alternatives rejected: a blocking Retry/Cancel dialog (a modal for something the user can simply re-tap, on a screen whose only dialog today is the Stop confirmation); falling back to filtering the Setup read in memory (silently reintroduces the client-side path D-32 chose against, giving two ways to feed a session and testing only one).*
  — **Reversibility:** reversible.

- **D-39 (permission posture):** **The `RECORD_AUDIO`-only stance is formally retired, in writing.** `cloud_firestore` adds `INTERNET` to the merged release manifest; PROJECT.md and `.claude/CLAUDE.md` must be updated to state that the release build now carries `RECORD_AUDIO` + `INTERNET` and why. `GoogleFonts.config.allowRuntimeFetching = false` **stays** — that guard is about the font never fetching, not about the permission, and `test/theme/typography_test.dart` still depends on it. **Re-running Phase 2's merged-release-manifest inspection is a required UAT item**, to confirm `INTERNET` is the *only* thing the Firebase dependencies added — no analytics, no ads, no surprise transitive permission. *Alternative rejected: an automated manifest guard test (it cannot run in plain `flutter test` — it needs a release build artifact first).*
  — **Reversibility:** one-way — undoing it means removing Firestore, which is the whole phase; the *documentation* of it is what must not be skipped, since STATE.md flags the undocumented version as a blocker.

### Matching semantics & empty results

- **D-40:** **Level matching is exact** — `where level == <chosen level>`. A B1 session contains only B1 questions. No CEFR ordering is encoded anywhere in app code, and the level chip means "this is the difficulty I am drilling". *Alternatives rejected: level-and-below (bakes an A1<A2<…<C2 ordering into the app, and makes a C2 session mostly easy questions unless the bank is balanced); exact-with-silent-widening on empty (the session quietly is not the difficulty that was chosen, with no way to tell, and two query paths to test).*
  — **Reversibility:** reversible.

- **D-41:** **A zero-result topic×level combination is explained at Start, not pre-blocked at Setup.** Start stays enabled; tapping it runs the query, gets nothing back, and shows an actionable inline message naming *both* dimensions — e.g. "No C2 questions in Travel or Food & health. Try a different level or add topics." This reuses D-38's Start-failure surface, adds no new Setup UI, and costs one read to discover. *Alternatives rejected: per-topic counts on the Topics card with impossible topics greyed out (real new UI on a deliberately spare screen, counts to keep in sync with the level chip, and it leans on client-side derivation for the question the Start query is supposed to answer); a live "N questions available" line above Start (same objection, smaller).*
  — **Reversibility:** reversible.

- **D-42:** **D-23's cycling is unchanged under real data.** A 20-question session against a 4-question result set runs all 20, repeating the 4 in order. The configured `question_count` is never silently contradicted, and `questionAt(bank, i) => bank[i % bank.length]` plus every test built on it survives untouched. *Alternatives rejected: warning before starting (needs the pool size known before Start, i.e. either a count derived from the Setup read or a confirm dialog after the query — both re-open D-41); capping the session at the pool size (silently contradicts the number the user chose, exactly what D-23 rejected, and changes LOOP-08's meaning).*
  — **Reversibility:** reversible.

- **D-43:** **"Sequential bank order" (D-23) means `orderBy created_at` ascending** — oldest question first. A Firestore query has no inherent order unless one is requested, so this must be explicit. It is deterministic and repeatable across runs, gives `created_at` a job beyond metadata, and makes newly imported questions land at the *end* — so a Phase 4 import visibly extends the bank rather than reshuffling it. With multiple topics selected, questions interleave by import time. **This requires a composite index**; the researcher must confirm the exact index shape for `subject in […]` + `level ==` + `orderBy created_at`, and the plan should capture creating it (the Firestore console offers a one-click create link on the first failing query). *Alternatives rejected: no `orderBy`, taking Firestore's implicit document-ID order (with auto-generated IDs that is an arbitrary-but-stable order — a de-facto shuffle, quietly doing the thing LOOP-V2-01 deferred to v2); `orderBy subject, created_at` (topic-blocks a multi-topic session, which is worse for reflex drilling, and needs a wider index).*
  — **Reversibility:** reversible in code; the index itself is infrastructure that must exist before the query works.

### Firebase setup, seeding & rules

- **D-44:** **There is no Firebase project yet — creating it is a documented prerequisite step of this phase, performed by the user.** The plan must spell out: create the project in the Firebase console with **Firestore in Native mode and no Auth product**, then run `flutterfire configure` to generate `lib/firebase_options.dart` and the per-platform config (`android/app/google-services.json`, iOS `GoogleService-Info.plist`). These are the user's credentials on the user's machine — the plan treats them as a prerequisite it cannot perform, tells the user exactly what to run, and does not proceed as if they exist. `Firebase.initializeApp()` must be added to `main()` before `runApp`, alongside the existing `configureFonts()` call.
  — **Reversibility:** one-way — the project ID and generated config become the app's identity; changing them later means re-running `flutterfire configure` and re-seeding the bank.

- **D-45:** **First questions get in via a throwaway dev seed script, not shipped in the app.** A small `tool/seed_questions.dart` (or equivalent) run once from the maintainer's machine, pushing a modest starter set that deliberately covers **multiple subjects across multiple levels, including at least one topic×level combination that is empty**, so D-41's zero-result path is demonstrable rather than theoretical. It is not part of the app binary and is deleted or superseded when Phase 4's real importer lands. *Alternatives rejected: hand-typing documents in the Firestore console (tedious to get subject×level coverage, easy to typo a field name, painful to redo); pulling Phase 4's IMPORT-05 seed content forward (real scope movement, and it couples this phase to seed-content decisions it does not need to make).*
  — **Reversibility:** reversible — it is disposable by design.

- **D-46 (resolves the STATE.md open-rules blocker):** **`firestore.rules` lives in the repo and allows unauthenticated read *and write* on the `questions` collection only, denying everything else.** Write is open now because the seed script needs it and Phase 4's in-app importer will need it from the client. The rules file must carry a comment stating plainly that this is a knowingly open single-user bank, **what the exposure actually is** (anyone with the project ID can read or overwrite the question bank), and what would change it (adding Firebase Auth, which PROJECT.md puts out of scope for v1). The honesty is the mitigation, not a fix. *Alternatives rejected: read-only client rules with the seed script writing via the Admin SDK and a service-account key (narrower now, but Phase 4's importer reopens it one phase later — churn for one phase of safety); leaving the console's default 30-day test-mode rules (they expire and the app breaks silently a month later, and it leaves exactly the implicit-not-documented state STATE.md asked us to resolve).*
  — **Reversibility:** reversible — rules are edited and redeployed independently of the app.

- **D-47:** **Host-testability stops at the seam, exactly as it does for the microphone.** `FirestoreQuestionSource` stays a deliberately thin adapter — build query, map documents to prompts, return — with no logic worth unit-testing. Every Setup and loop test injects a **fake async `QuestionSource`** that can return topics, return questions, return empty, or throw, so all four states designed above (loaded, empty, could-not-load, zero-result) are covered on the host with no device and no new dependency. The real query is proven by on-device UAT, exactly as the recording path is. *Alternatives rejected: adding `fake_cloud_firestore` as a dev dependency (it would exercise the real `where`/`orderBy` clauses in `flutter test`, but its query semantics are an approximation — index requirements in particular are not modelled — so a passing test would not prove the real query runs, at the cost of one more dependency); the Firestore emulator (an external process to install and orchestrate, well beyond this project's tooling footprint).*
  — **Reversibility:** reversible.

### Claude's Discretion

- Exact copy for the could-not-load state (D-37), the Start-failure message (D-38) and the zero-result message (D-41), within the established warm/playful voice and Phase 1's single-fixed-failure-string convention.
- The Firestore collection name (`questions` is the obvious choice, matching PROJECT.md's wording), the document → prompt mapping, and how a malformed document (missing `content`, unknown `level`) is handled — skip-and-log is the expected default, but the specific handling is an implementation call.
- Whether the busy state on START SESSION (D-33) is a spinner in the button, a disabled button with a label change, or an overlay.
- Whether `FirestoreQuestionSource` also exposes the subjects read or whether that is a separate small method/class alongside it — the constraint is only that the loop keeps receiving a resolved `List<String>` and never learns where it came from.
- The precise shape of the seed script (Dart via `tool/`, or a Node script) and its content, subject to D-45's coverage requirement.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope & requirements
- `.planning/PROJECT.md` — core value, constraints, Key Decisions table. **Two entries need updating in this phase:** the "practice loop must run fully offline" active requirement is narrowed by D-36, and the `PlaceholderQuestionSource` Key Decisions row moves from "Pending" to done.
- `.planning/REQUIREMENTS.md` — this phase covers SETUP-01, BANK-01, BANK-02, BANK-03. IMPORT-01..05 and UI-03 are Phase 4 and must not be pulled forward.
- `.planning/ROADMAP.md` — Phase 3 goal, its two success criteria, dependency on Phase 2.
- `.planning/STATE.md` — carries the two Phase 3 blockers this discussion resolves: the network/offline question (D-33 + D-36 — the fetch happens at Setup only, never mid-loop) and the open-rules-must-be-written-down question (D-46).

### Prior-phase artifacts that constrain this phase
- `.planning/phases/02-full-timed-practice-session-setup-loop-controls/02-CONTEXT.md` — D-16..D-31. Especially **D-19** (the topic checkbox UI and the SETUP-07 Start gate that this phase feeds real data into, without changing the widget or the validation), **D-23** (sequential order and cycling, which D-42/D-43 preserve and define), and **D-18** (settings are not persisted — do not let a question-bank cache become a settings cache by accident).
- `.planning/phases/01-record-save-replay-a-single-answer-crash-safe/01-CONTEXT.md` — D-01..D-15, especially the crash-safe write ordering and the error-copy convention D-38 follows.
- `.planning/phases/01-record-save-replay-a-single-answer-crash-safe/01-UI-SPEC.md` — the locked palette, type scale, spacing scale and copywriting contract. The new loading/error/empty states on Setup must extend this system, not invent a second one.

### Stack guidance
- `.claude/CLAUDE.md` — the recommended stack and the "What NOT to Use" table. Note that its `cloud_firestore` / `firebase_core` rows describe "fetch questions once at setup time, derive distinct subjects client-side"; **D-32 keeps the client-side subject derivation but deliberately adds a second, genuinely filtered query on Start** — the planner should record that refinement rather than treat it as a contradiction. The `firebase_auth` / `firebase_storage` "do not use" rows remain binding.

### Code that changes
- `lib/data/questions.dart` — holds `QuestionSource`, `PlaceholderQuestionSource`, `kQuestions`, `kSubjects`, `questionAt`. The seam's signature changes here (D-34).
- `lib/state/practice_state.dart:99` — the hardcoded `const PlaceholderQuestionSource()` field, and `:536` `_pickQuestion()`.
- `lib/screens/setup_screen.dart` — `_subjects`, `_TopicsCard`, the `setup-topics-empty` branch, `_startSession()`.
- `lib/main.dart` — `Firebase.initializeApp()` goes here, next to `configureFonts()`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- **`lib/data/questions.dart`** — `QuestionSource` is the seam Phase 2 built explicitly for this swap, and its doc comment says so. `questionAt(bank, index)` (cycling, D-23) is reused verbatim by D-42. `PlaceholderQuestionSource` and `kSubjects` are what get replaced; `kQuestions` may survive only if something still needs it after D-36 ruled out a fallback bank — otherwise it goes too.
- **`lib/screens/setup_screen.dart`** — already has everything the topic UI needs: `_TopicsCard`, `_selectedTopics`, `_toggleTopic`, the `canStart = _selectedTopics.isNotEmpty` gate (SETUP-07), and an **already-built empty state** keyed `setup-topics-empty` whose doc comment says it is "unreachable in Phase 2 … and goes live when Phase 3 sources it from Firestore". D-37 makes it live and adds a sibling error state. The `subjects` constructor override already exists as a test seam.
- **`lib/models/session_config.dart`** — `topics` and `level` were deliberately added in Phase 2 "even though Phase 2 draws every prompt from a hardcoded placeholder bank … so the fields [the Firestore query] will read must already be travelling with the session". They are exactly the two fields D-32's query needs. Its no-serialization rule stands (D-34 keeps prompts out of it).
- **`lib/main.dart`** — `configureFonts()` already establishes the "initialize before `runApp`" pattern that `Firebase.initializeApp()` joins.

### Established patterns
- **Platform dependencies live behind injectable constructor seams** (`RecorderBackend`, `AudioPlaybackBackend`, `documentsDirProvider`, `DatabaseHelper`, `ScreenWakeController`), constructed lazily so a test with a fake never touches a platform channel. D-47 extends this to `QuestionSource` rather than inventing a new testing approach.
- **A read failure is never presented as missing data** — established for History in Phase 1 Plan 6, applied to the bank by D-37.
- **One fixed user-facing failure string**; exception detail goes only to `debugPrint`/`FlutterError.reportError`. D-38 follows this.
- **Theming:** every colour and text style comes from `Theme.of(context)`; `lib/main.dart` is the single source of the palette and type scale. New loading/error states must not hardcode a hex value, and `textScaler` is never pinned.
- **`kPhaseControlKeys` in `lib/widgets/phase_control.dart` is a deliberately total map** enforced by `test/widgets/phase_control_test.dart` — if this phase adds any `PracticePhase`, it needs an entry. (It probably should not: D-33 keeps loading on Setup, outside the phase machine.)
- **Tests mirror `lib/` path-for-path** under `test/`.

### Integration points
- **`PracticeState`'s constructor** — gains the resolved `List<String>`, loses the `questionSource` field (D-34). This ripples to `PracticeScreen` and to every test constructing either.
- **`SetupScreen._startSession()`** — becomes async: run the query, handle the three outcomes (questions / empty / error), and only then `Navigator.push`.
- **`SetupScreen.initState`** — already runs `_sweepOrphanRecordings()`; the subjects read joins it, and D-35 additionally re-runs it whenever Setup reappears. **The orphan sweep's ordering contract must not be disturbed** — `pruneOrphanRecordings` must still complete before any recording file name is chosen.
- **`pubspec.yaml`** — adds `firebase_core ^4.13.0` and `cloud_firestore ^6.8.0`; let `flutter pub add` / `flutterfire configure` resolve the matching pair rather than hand-pinning both.
- **`android/app/src/main/AndroidManifest.xml`** — its comment currently states "no network permission are requested". That comment becomes false with this phase and must be rewritten, not left to rot (D-39).
- **Android build files** — the Google Services Gradle plugin wiring that `flutterfire configure` expects; the researcher should confirm the current required steps for the installed Flutter/Gradle versions.

</code_context>

<specifics>
## Specific Ideas

- **The loop must stay provably network-free.** After Start, there should be no code path from the practice screen to Firestore at all — not a lazy one, not a retry, not a cache refresh. D-33 and D-34 exist to make that a structural property rather than a discipline.
- **Distinguish "no questions" from "couldn't ask".** The user was explicit twice — once for the topic list (D-37) and once for the empty result (D-41). Both messages should name what is actually true, and the zero-result one should name *both* dimensions (level and topics) because either could be the thing to change.
- **A failure never costs the user their setup.** Topics, level and all three sliders survive every error path (D-38); nothing about a failed network call should send them back to defaults.
- **The seed data has a job beyond "some questions exist"** — it must include an empty topic×level combination, or D-41's path ships unexercised.
- **Write the tradeoff down where it bites.** The open rules (D-46) and the retired permission stance (D-39) are both things a future reader would otherwise find as an unexplained surprise.

</specifics>

<deferred>
## Deferred Ideas

- **Per-topic or total question counts shown on Setup** (D-41 alternatives) — genuinely useful once the bank is large, and the Setup read already holds the data. Revisit if real use shows users hitting zero-result dead ends often.
- **Warning before a session that will repeat questions** (D-42 alternative) — the cheapest version rides on the count above, so it naturally follows if that is ever built.
- **`fake_cloud_firestore` for host-level query tests** (D-47 alternative) — revisit if the query grows past a single `where`/`orderBy` shape, or if a wrong-field-name bug actually escapes to a device.
- **An automated merged-manifest permission guard** (D-39 alternative) — needs a release build artifact, so it belongs with a CI/release-pipeline phase if one ever exists.
- **Level-and-below matching** (D-40 alternative) — revisit only if real use shows the bank is too thin at any single level to sustain a session.
- **In-app JSON import, the ~10 seeded topics, and the 3-screen audit** — Phase 4 (IMPORT-01..05, UI-03), already scheduled.
- **Shuffled question order** — LOOP-V2-01, v2.

</deferred>

---

*Phase: 3-Real Question Bank via Firestore*
*Context gathered: 2026-08-09*
