---
phase: 03-real-question-bank-via-firestore
verified: 2026-08-09T11:17:21Z
status: human_needed
score: 35/43 must-haves verified
behavior_unverified: 8
overrides_applied: 0
re_verification:
  previous_status: null
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
behavior_unverified_items:
  - truth: "SC1 — The topic checkboxes in Setup are populated from the distinct `subject` values actually present in the Firestore question bank"
    test: "Launch the app on a networked Android device/emulator. Open Setup and let the topics card resolve."
    expected: "The checkbox rows are the five seeded subjects — Daily life, Food & health, Technology, media and everyday digital habits, Travel, Work & study — in case-insensitive sorted order, and NOT the five retired Phase 2 constants. No blank/unlabelled row appears (the two malformed seeded documents must contribute none)."
    why_human: "`FirestoreQuestionSource.subjects()` is deliberately not host-testable (D-47): the production source resolves `FirebaseFirestore.instance`, which no `flutter test` process can construct. Widget tests prove the render path with a fake, `normalizeSubjects` is unit-tested, and the live bank is confirmed by the seed probe — but the adapter glue between them has never executed. WINDOWS.md #1."
  - truth: "SC2 — Starting a session fetches only the questions matching the selected topics and CEFR level from Firestore"
    test: "On the same device, check `Travel`, leave the level at B1, tap START SESSION and let the first prompt appear."
    expected: "The busy spinner replaces the label, then the practice screen opens on a seeded Travel/B1 prompt (never a Phase 2 placeholder prompt). Selecting `Travel` + C1 instead produces the zero-result helper naming both, and opens no session."
    why_human: "Same D-47 boundary. The query shape (`subject in [...]` + `level ==` + `orderBy created_at`) was replayed against the live bank by `tool/seed_questions.mjs --verify` and returned 7 strictly-ascending documents through the deployed composite index, and the widget suite proves the resolved list crosses into `PracticeScreen` — but the Dart adapter itself has never run. WINDOWS.md #1."
  - truth: "E1/partial + E3/partial — a malformed question document is skipped and logged, never producing a blank checkbox row or a blank prompt"
    test: "On a device against the live bank, inspect the topics card and run a `Daily life` B1 session and a `Travel` A1 session while watching the debug console."
    expected: "No blank checkbox row, no blank question card mid-countdown, and one `Skipping question <docId>: …` line per malformed document."
    why_human: "The skip lives inside the non-host-testable adapter (D-47). `sanitizedText` is unit-tested; its application inside `subjects()`/`questionsFor()` is not. WINDOWS.md #12."
  - truth: "E1/long-text — a long, user-authored subject name wraps and grows the 64px topic row rather than clipping at the largest OS text scale"
    test: "Set the OS text size to maximum and open Setup."
    expected: "`Technology, media and everyday digital habits` (45 chars) wraps and grows its row; the topics card scrolls rather than pushing START SESSION off screen."
    why_human: "Visual rendering at a real OS text-scale setting. WINDOWS.md #14."
  - truth: "E2/long-text — the non-scrolling Start footer shows no RenderFlex overflow at the largest OS text scale for its longest content"
    test: "At maximum text scale, produce the three-or-more-topics zero-result message and then the failure row (airplane mode + cleared cache)."
    expected: "The footer grows by shrinking the scroll area above, no overflow banding, and the button stays fully visible at 64px. The zero-result path loses no topic, level or slider value."
    why_human: "Layout overflow at real text scale. WINDOWS.md #15."
  - truth: "E3/long-text — a long, user-authored prompt renders un-clipped in the peach question card at maximum text scale in the reading, recording and paused states"
    test: "At maximum text scale, run a session containing the seeded 324-character prompt and observe all three states."
    expected: "The prompt renders un-clipped in each state."
    why_human: "Visual rendering; supersedes Phase 2's backstop, which was written against short curated constants. WINDOWS.md #16."
  - truth: "D-36 — the loop works offline after one successful online Setup visit, and a never-been-online device lands on could-not-load, not empty"
    test: "(a) Online: load topics and complete a short session. (b) Airplane mode, force-stop, relaunch: topics still appear and a session still runs. (c) Clear app data while still offline, relaunch."
    expected: "(a) and (b) succeed from the SDK cache. (c) shows `setup-topics-error` with its Try again button — NOT `setup-topics-empty`."
    why_human: "Requires airplane mode, a force-stop and an app-data clear on real hardware. Part (c) is the phase's sharpest correctness detail and is exactly what PROJECT.md's narrowed offline requirement now claims. WINDOWS.md #17."
  - truth: "Start-query on-device latency (informational, surfaced not failed)"
    test: "Measure the wall time between tapping START SESSION and the practice screen appearing, on a real device on a typical connection."
    expected: "Under ~1 s. If it routinely exceeds that, the sanctioned follow-up is disabling the Setup form controls during the busy frame — never an overlay."
    why_human: "Never measured; no device was attached for plan 03-02 or 03-03. The current design (tap-time config snapshot wins, controls stay interactive) is an explicit passing host test, but whether real latency justifies revisiting it is unknown. WINDOWS.md #13."
human_verification:
  - test: "Networked-device tracer: open Setup, confirm the seeded Firestore subjects render; check Travel at B1 and tap START SESSION"
    expected: "Five seeded subjects in case-insensitive sorted order; the session opens on a seeded Travel/B1 prompt, not a Phase 2 placeholder"
    why_human: "The Firestore adapter is deliberately not host-testable (D-47). Covers ROADMAP SC1 and SC2. WINDOWS.md #1"
  - test: "Malformed-document skip-and-log against the two deliberately malformed seeded documents"
    expected: "No blank checkbox row, no blank prompt, and one debug-console skip line naming each document ID"
    why_human: "The skip is inside the adapter. Covers UI-SPEC E1/partial and E3/partial. WINDOWS.md #12"
  - test: "E1/long-text at maximum OS text scale"
    expected: "The 45-char seeded subject wraps and grows its 64px row; the card scrolls rather than pushing Start off screen"
    why_human: "Visual rendering at a real text-scale setting. WINDOWS.md #14"
  - test: "E2/long-text at maximum OS text scale, plus the zero-result path end to end"
    expected: "No RenderFlex overflow in the non-scrolling footer; button fully visible at 64px; no setting lost"
    why_human: "Layout overflow on real hardware. WINDOWS.md #15"
  - test: "E3/long-text at maximum OS text scale"
    expected: "The seeded 324-character prompt renders un-clipped in the reading, recording and paused states"
    why_human: "Visual rendering. WINDOWS.md #16"
  - test: "D-36 three-part offline sequence (warm cache, airplane mode, cleared cache while offline)"
    expected: "Parts (a) and (b) run from cache; part (c) lands on could-not-load with its retry button, never on the empty state"
    why_human: "Requires airplane mode, force-stop and app-data clear on real hardware. WINDOWS.md #17"
  - test: "Measure Start-query latency on a real device"
    expected: "Under ~1 s; above that, disable the Setup form controls during the busy frame (never an overlay)"
    why_human: "Never measured; recorded as WINDOWS.md #13"
flagged_prohibitions:
  - statement: "BANK-01 / privacy — MUST NOT transmit any recording, session-history row, or session configuration off the device; no analytics, crash-reporting, ads or telemetry SDK may ride in with the Firebase dependencies; no Firebase Storage or Firestore write of user practice data"
    verification: judgment
    judge_verdict: held
    flagged: true
    evidence: "pubspec.yaml declares only firebase_core + cloud_firestore (no analytics/crashlytics/admob/messaging/performance). `lib/services/firestore_question_source.dart` contains no `.set(`/`.update(`/`.delete(`/`writeBatch` — the only `.add(` calls are Dart Set/List adds. No `firebase_storage` anywhere. The merged manifest carries no AD_ID, location, account or analytics permission."
    note: "unverified-prohibition — human review recommended (LLM-judge verdict, non-authoritative)"
  - statement: "BANK-02 / transparency — MUST NOT present an unserved or failed read as an empty question bank"
    verification: judgment
    judge_verdict: held
    flagged: true
    evidence: "`FirestoreQuestionSource._read` throws `QuestionBankUnavailableException` on a zero-document snapshot with `metadata.isFromCache == true`; `_TopicsCard._body` branches loading -> failed -> empty in that order; widget tests assert the empty state's key AND its literal heading are absent on a failed read, and the reverse."
    note: "unverified-prohibition — human review recommended; the real cache-served path is WINDOWS.md #17"
  - statement: "BANK-03 / values — MUST NOT silently alter what the user asked for (no shortening below question_count, no level widening, no topic-list trimming to fit whereIn, no fallback question source)"
    verification: judgment
    judge_verdict: held
    flagged: true
    evidence: "`questionAt` cycles rather than capping (byte-identical, pinned by test 4 in practice_session_test.dart); `where(_levelField, isEqualTo: config.level)` is exact with no CEFR ordering anywhere; the over-limit guard throws and `! grep -Eq 'topics\\.(take|sublist)'` passes; `grep -rEc 'class .* implements QuestionSource' lib/` totals 1, so no fallback source exists."
    note: "unverified-prohibition — human review recommended (LLM-judge verdict, non-authoritative)"
warnings:
  - id: W1
    severity: warning
    statement: "WINDOWS.md entries #3–#9 are still `open` but are verifiably closed in the code"
    detail: "#3/#4 (`setup-topics-error`, `setup-topics-loading`), #5 (`setup-start-error`), #6 (`setup-start-no-questions`), #7 (`setup-start-busy`) all exist in lib/screens/setup_screen.dart; #8 (skip-and-log) and #9 (`kMaxTopicsPerQuery` guard) exist in lib/services/firestore_question_source.dart. Plan 03-03's SUMMARY recommends the orchestrator resolve them. Left as-is, `/gsd-ship` stays blocked on seven entries describing conditions that no longer exist."
    action: "Orchestrator decision — mark #3–#9 fixed."
  - id: W2
    severity: warning
    statement: "ROADMAP marks Phase 3 `Mode: mvp` but its Goal is outcome-shaped, not User-Story shaped"
    detail: "`As a … I want to … so that ….` does not match. The MVP-mode User Flow Coverage table could therefore not be produced honestly; standard goal-backward verification was applied instead. Plan 03-01 flags the same thing in its own header and explicitly declines to invent a user story."
    action: "Human decision — run `/gsd mvp-phase 3` to set a User Story goal, or accept the outcome-shaped goal for this phase."
  - id: W3
    severity: warning
    statement: "The merged RELEASE manifest artifact is no longer on disk; only the merged DEBUG manifest remains"
    detail: "build/app/intermediates/merged_manifest/ contains `debug/` only. D-39 was re-confirmed independently against the merged DEBUG manifest, which declares exactly the four recorded entries (RECORD_AUDIO, INTERNET, ACCESS_NETWORK_STATE, com.englishreflex.englishreflex.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) and no analytics/AD_ID/location/account permission — matching plan 03-03's recorded release-build result verbatim. The release APK is also gone (only app-debug.apk is present)."
    action: "Informational. Re-run `flutter build apk --release` before shipping if a fresh release-artifact audit is wanted."
  - id: W4
    severity: info
    statement: "`node tool/seed_questions.mjs --verify` requires `npm install --prefix tool` first"
    detail: "tool/node_modules/ is gitignored, so a fresh checkout fails with ERR_MODULE_NOT_FOUND rather than a probe failure. tool/README.md documents the one-time install. After installing, the probe exits 0 with all nine acceptance checks passing."
    action: "None — documented behaviour."
  - id: W5
    severity: info
    statement: "`subjects()` carrying the RAW (untrimmed) subject value forward is pinned by code review plus `normalizeSubjects` unit tests, not by a test of the adapter line itself"
    detail: "`sanitizedText(raw) == null` is used only as a usability verdict and `rawSubjects.add(raw)` carries the raw value; `questionsFor` uses the trimmed return value. Both behaviours are pinned — `normalizeSubjects` has a test asserting values differing only by case or surrounding whitespace stay distinct, and `sanitizedText` has tests asserting trimming — but the adapter's own two call sites sit behind D-47's accepted host-testability boundary."
    action: "None — the accepted D-47 boundary; covered on device by WINDOWS.md #1."
---

# Phase 3: Real Question Bank via Firestore — Verification Report

**Phase Goal:** Session setup and the practice loop run on the real Firestore-backed question bank instead of placeholder data — topics are derived from actual `subject` values, and only matching questions are fetched per session.
**Verified:** 2026-08-09T11:17:21Z
**Status:** human_needed
**Re-verification:** No — initial verification

**Scope note (W2):** ROADMAP declares `Mode: mvp` for this phase, but the Goal is outcome-shaped rather than `As a … I want to … so that ….`. The MVP-mode User Flow Coverage table was therefore not produced (it would have been fabricated against a non-user-story goal). Standard goal-backward verification was applied. Plan 03-01's own header raises the same point and deliberately declines to invent a user story.

## Goal Achievement

### Observable Truths

Must-haves merged from ROADMAP Success Criteria (non-negotiable) + `must_haves.truths` in all three PLAN frontmatters.

#### ROADMAP Success Criteria

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | Topic checkboxes in Setup are populated from the distinct `subject` values actually present in the Firestore bank (schema `{id, content, subject, level, created_at}`) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Wired end to end: `setup_screen.dart:160` `late final QuestionSource _questionSource = widget.questionSource ?? FirestoreQuestionSource()`; `_loadSubjects()` → `subjects()` → `normalizeSubjects`. Live bank confirmed by `tool/seed_questions.mjs --verify` (exit 0): 29 documents, 5 distinct subjects, every `created_at` a native Firestore `Timestamp`. Render path proven by widget tests with a fake. **The adapter glue has never executed** (D-47) — see human verification #1 / WINDOWS.md #1. |
| SC2 | Starting a session fetches only the questions matching the selected topics and CEFR level from Firestore | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `firestore_question_source.dart:231-235` — `.collection(kQuestionsCollection).where('subject', whereIn: config.topics).where('level', isEqualTo: config.level).orderBy('created_at')`. The probe replayed that exact query against the live bank through the deployed composite index and returned 7 strictly-ascending documents. `setup_screen.dart:396` awaits it and pushes only on success. Widget test asserts `PracticeScreen.questions == bank` verbatim. **The Dart adapter has never run on a device.** |

#### Plan 03-01 truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Setup topic checkboxes rendered from Firestore subjects at runtime, not a Dart constant | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Deduped with SC1. The "not a Dart constant" half is fully VERIFIED: `grep -rE '^\s*(const\|final\|var\|class)\s.*\b(kQuestions\|kSubjects\|PlaceholderQuestionSource)\b' lib/` returns nothing. |
| 2 | Tapping START issues a filtered query and the loop shows prompts from it | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Deduped with SC2. |
| 3 | Firebase initialised before the first frame; `allowRuntimeFetching` still false | ✓ VERIFIED | `main.dart:43-56` — `WidgetsFlutterBinding.ensureInitialized()` → `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` → `configureFonts()` → `runApp(...)`, all sequential before the first frame. `grep -c 'DefaultFirebaseOptions.currentPlatform' lib/main.dart` = 1; `allowRuntimeFetching = false` present and asserted by `test/theme/typography_test.dart`. `flutter build apk --debug` artifact present. |
| 4 | Identical `subject` strings collapse to ONE checkbox; case/whitespace-differing values stay distinct | ✓ VERIFIED | `normalizeSubjects` de-dupes into a `Set<String>` by exact equality. Unit tests: "collapses exact duplicates to one topic" and "keeps values differing only by case or surrounding whitespace as distinct". Both pass. |
| 5 | Topic order deterministic and stable across repeated reads (case-insensitive lexicographic) | ✓ VERIFIED | `..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))`. Unit test "sorts case-insensitively, and the same input always sorts the same way". |
| 6 | A one-subject bank renders one checkbox that enables Start; a missing/blank `subject` contributes no checkbox | ✓ VERIFIED | Widget test "a single-subject bank renders one checkbox and ticking it…" + unit test "drops blank, whitespace-only, missing and non-String values". |
| 7 | Questions come back in ascending `created_at`; same selection → same sequence; later writes land last | ✓ VERIFIED | `.orderBy(kCreatedAtField)` in code, plus the live probe's `PASS the D-43 query returns strictly ascending created_at` and `PASS every created_at is a native Firestore Timestamp`. The composite index is deployed and serving (the query would have failed otherwise). |
| 8 | No code path from the practice screen or `lib/state/` to Firestore | ✓ VERIFIED | `grep -rE 'cloud_firestore\|firebase_core\|FirebaseFirestore\|QuerySnapshot\|DocumentSnapshot\|FirebaseException' lib/state/ lib/screens/practice_screen.dart` returns nothing. `grep -Ec 'final QuestionSource' lib/state/practice_state.dart` = 0. |
| 9 | A session longer than the query result still runs the full count, repeating in order (D-42) | ✓ VERIFIED | `questionAt` byte-identical (exact-string grep = 1). `practice_session_test.dart:744` test 4 runs `bank.length + 1` questions and asserts the last answer's text is `kFixtureQuestions.first` — "the bank must wrap to its head, not cap the session". Passing. |
| 10 | E1/populated — unchanged 64px `CheckboxListTile` rows, coral check on brown; only the row count is now data-driven and unbounded | ✓ VERIFIED | `setup_screen.dart:652-669` — `for (final subject in subjects)` inside `ConstrainedBox(minHeight: 64)`, `activeColor: colorScheme.primary`, `checkColor: colorScheme.onPrimary`. No upper bound, no select-all control. |
| 11 | E1/overflow — the topics card grows with its row count inside the scroll view, is height-locked in no state, and the Start footer stays pinned outside | ✓ VERIFIED | `Column > Expanded > SingleChildScrollView` holds the card; `_StartFooter` is a sibling of the `Expanded`, outside the scroll view. No `SizedBox(height:)` around `_TopicsCard`. The existing "SetupScreen at a large OS text scale" test group asserts scrolling with the footer intact. |
| 12 | E3/populated — the practice screen is visually unchanged, `questionAt` cycling is verbatim, and bank order is ascending `created_at` | ✓ VERIFIED | `git diff 86313c1..HEAD -- lib/screens/practice_screen.dart` = +11 lines, all constructor plumbing for `questions`. `questionAt` grep = 1. |
| 13 | E3/loading — the loop is handed a resolved `List<String>` at construction; no new `PracticePhase`, no new `kPhaseControlKeys` entry | ✓ VERIFIED | `lib/widgets/phase_control.dart` is not in the phase diff at all. `practice_state.dart:88` `required this.questions`; `:125` `late String currentQuestion = questionAt(questions, 0)`. |
| 14 | E3/overflow — the question card's wrap/scroll handling in reading/recording/paused is unchanged | ✓ VERIFIED | Same +11-line constructor-only diff; no layout code touched. |

#### Plan 03-02 truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 15 | E1/empty — `setup-topics-empty` only on a server-confirmed zero-document read; cache-served or thrown renders could-not-load | ✓ VERIFIED | `_read` throws on `docs.isEmpty && metadata.isFromCache`; `_loadSubjects` catches into `_topicsError`. Widget tests assert the error state present with the empty state's key AND its literal heading absent, and the reverse. (The real device cache path is WINDOWS.md #17.) |
| 16 | E1/loading — coral `CircularProgressIndicator` + `Loading your topics…` under `setup-topics-loading`, Start disabled, no footer helper | ✓ VERIFIED | `_TopicsLoading` at `setup_screen.dart:706-727`. Test "the first frame is loading, with Start shut and no helper". |
| 17 | E1/error — 48px red `error_outline_rounded`, brown `kTopicsErrorMessage`, brown `Try again`, distinct keys, no exception text | ✓ VERIFIED | `_TopicsError` at `:746-784`. `kTopicsErrorMessage` count = 3 (decl + doc + use). Test "a read that threw is could-not-load, and says NOTHING the empty state says". Exception detail goes to `debugPrint` only. |
| 18 | E1/zero-one-many — zero → empty state + Start disabled + no pick-a-topic helper; one → one enabling row; many → N scrolling rows, no cap, no select-all | ✓ VERIFIED | Tests across the "four read states" and "reads its topics from the injected bank" groups; `statesPresent(tester) == 1` totality assertion. |
| 19 | E2/empty — the pick-a-topic helper's trigger narrowed to loaded AND non-empty AND nothing selected | ✓ VERIFIED | `setup_screen.dart:594-596` `showBlockedHelper: topicsLoaded && subjects.isNotEmpty && _selectedTopics.isEmpty`. Test "with subjects on screen and none checked, the pick-a-topic helper…". |
| 20 | E2/loading — busy button keeps coral via `disabledBackgroundColor`, 24px spinner keyed `setup-start-busy`, `onPressed` null, 64px, semantic `Starting session` | ✓ VERIFIED | `:1082-1143`. `disabledBackgroundColor` count = 3. Test "an in-flight query renders the busy button" asserts no label, `startEnabled == false`, resolved fill `== primary` and `isNot(surface)`, height `== 64`. |
| 21 | E2/error — red 24px icon + brown `kQuestionLoadErrorMessage` in an `Expanded` under `setup-start-error`; every topic, level and slider preserved | ✓ VERIFIED | `_helper` at `:1052-1068`. Test "a failed query names the connection and preserves every setting (D-38)". |
| 22 | E2/partial — only topic selection gates Start | ✓ VERIFIED | `canStart = topicsLoaded && _selectedTopics.isNotEmpty`; level is a single-select invariant and the sliders always hold values. |
| 23 | E2/populated — resting ready state is a coral START SESSION with NO helper; the 8px gap applies only when a helper is present | ✓ VERIFIED | `:1106-1109` `if (helper != null) ...[helper, SizedBox(height: 8)]`. Test "the resting ready state is one button and nothing else" asserts `helpersPresent == 0`. |
| 24 | E2/overflow — `Column(mainAxisSize: min)` below the `Expanded`, message wraps in an `Expanded` beside its icon, button 64px in all three states | ✓ VERIFIED | `:1101-1145`. (Max-text-scale rendering is backstop E2/long-text, WINDOWS.md #15.) |
| 25 | E2/zero-one-many — at most one of the three helper keys; button exactly one of ready/blocked/busy | ✓ VERIFIED | `_helper` is an else-if chain. Test "at most one helper line, in each of the three states that produce one" asserts `helpersPresent == 1` in each. |
| 26 | E3/empty — a server-confirmed zero-result Start shows the helper naming level and topics, and pushes no PracticeScreen | ✓ VERIFIED | `:426-435`. Tests "a zero-result query explains itself and costs the user nothing" and "a zero-result topic-by-level combination does NOT open a session". |
| 27 | E3/error — the loop has no failure path of its own; the push happens only on success | ✓ VERIFIED | `_startSession` returns before `Navigator.push` on both failure branches. `practice_screen.dart` unchanged apart from the constructor. |
| 28 | E3/zero-one-many — zero → helper, no session; one → full count repeating that prompt, unlabelled; many → ascending `created_at` interleaved | ✓ VERIFIED | Zero-result tests above; cycling test 4; `orderBy` + live probe for ordering. |
| 29 | A background refresh is silent: never flips to loading or could-not-load, keeps last-known topics on a failed re-read, exception to `debugPrint` only | ✓ VERIFIED | `_loadSubjects({bool background})` at `:232-287` — `if (background) return;` before the error `setState`. Test "a background refresh shows no spinner, and a failed one keeps the last-known topics on screen (D-35)" drives a real History push/pop and asserts `subjectsCallCount == 2`, no loading key, no error key, rows still present. |
| 30 | After every successful subjects read the selection is reconciled to the intersection | ✓ VERIFIED | `:285` `_selectedTopics.retainAll(subjects!)`. Test "a re-read that no longer lists a checked topic drops it from the SELECTION, not just the screen" asserts `startEnabled == false` afterwards. |
| 31 | The zero-result and failure helpers clear on any topic/level/slider change and on re-tap | ✓ VERIFIED | `_clearStartMessage()` called from every `setState` in the six control handlers and at the top of `_startSession`. Test "changing a topic, the level or a slider clears the last outcome". |
| 32 | A setting changed mid-flight applies to the NEXT Start — the tap-time `SessionConfig` snapshot wins | ✓ VERIFIED | Config built first and synchronously at `:370-384`. Test "the tap-time SessionConfig wins over a level changed mid-flight" asserts `source.configs.single.level == 'B2'` after tapping C2 mid-flight. |

#### Plan 03-03 truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 33 | The app ships exactly one question bank; no Dart constant in `lib/` holds prompts or topic names | ✓ VERIFIED | No declarations of `kQuestions`/`kSubjects`/`PlaceholderQuestionSource` anywhere in `lib/` (only two doc-comment mentions recording the deletion). `grep -rEc 'class .* implements QuestionSource' lib/` totals 1. `test/fixtures/questions.dart` exists with 2 `const List<String>` and is imported by 4 test files. |
| 34 | The docs state the release build now carries microphone AND network access, why, and that recordings/history are still never transmitted | ✓ VERIFIED | `.planning/PROJECT.md` Key Decisions row (line 75) names the complete verified set with attributions; `.claude/CLAUDE.md`'s `wakelock_plus` row explicitly retires the Phase 2 "RECORD_AUDIO only" claim; `google_fonts` row inverted rather than deleted. |
| 35 | PROJECT.md's offline requirement is narrowed to what the Firestore cache actually delivers | ✓ VERIFIED | PROJECT.md line 27: "run offline **after one successful online Setup visit**… a device that has never been online has an empty cache and **cannot start a session** — it lands on the could-not-load state, not on the empty state." `grep 'no network permission in the release build'` = 0. |
| 36 | The Firestore rules tradeoff is discoverable from the project docs, not only the rules file | ✓ VERIFIED | PROJECT.md Key Decisions row 76 carries the same exposure (project ID → full read + overwrite/delete) and the same exit condition (Firebase Auth) as `firestore.rules`' header comment. |
| 37 | E1/partial — malformed `subject` skipped and logged, never a blank checkbox row *(verification: backstop)* | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `sanitizedText` guard + `debugPrint` at `firestore_question_source.dart:182-188`; `sanitizedText` unit-tested. Adapter application not host-testable (D-47). WINDOWS.md #12. |
| 38 | E1/long-text — a long subject wraps and grows the 64px row at max text scale *(backstop)* | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `ConstrainedBox(minHeight: 64)` not a fixed height; seeded 45-char subject confirmed present by the probe. Rendering unverified. WINDOWS.md #14. |
| 39 | E2/long-text — no RenderFlex overflow in the non-scrolling footer at max text scale *(backstop)* | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `Column(mainAxisSize: min)` + `Expanded` wrap in code; overflow unverified on hardware. WINDOWS.md #15. |
| 40 | E3/partial — missing/blank `content` skipped so no blank prompt reaches the card *(backstop)* | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Guard + `debugPrint` at `:240-247`; two malformed documents confirmed present in the live bank by the probe. WINDOWS.md #12. |
| 41 | E3/long-text — a long prompt renders un-clipped at max text scale in reading/recording/paused *(backstop)* | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Seeded 324-char prompt confirmed present. Rendering unverified. WINDOWS.md #16. |
| 42 | D-39 — the merged RELEASE manifest's complete permission set is RECORD_AUDIO + the Firebase network grants and nothing beyond them *(backstop)* | ✓ VERIFIED | **Independently re-confirmed.** `build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml` declares exactly `android.permission.RECORD_AUDIO`, `android.permission.INTERNET`, `android.permission.ACCESS_NETWORK_STATE` and the app-namespaced `com.englishreflex.englishreflex.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` — matching plan 03-03's recorded release-build result verbatim, with attributions in its blame report. **No analytics, AD_ID, location or account permission.** The source manifest still declares `RECORD_AUDIO` only (`git diff` shows no permission line changed this phase — comment-only edit). See W3 on the missing release artifact. |
| 43 | D-36 — offline after one successful online Setup visit; never-been-online lands on could-not-load, not empty *(backstop)* | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | The `isFromCache` rule is in code and the SDK semantics were read out of the installed `cloud_firestore_platform_interface 8.0.6` sources. The three-part device sequence was never run. WINDOWS.md #17. |

**Score:** 35/43 truths verified (8 present, behavior-unverified). 0 FAILED. 0 overrides applied.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/services/firestore_question_source.dart` | Production `QuestionSource` + `QuestionBankUnavailableException` | ✓ VERIFIED | 299 lines. `class FirestoreQuestionSource implements QuestionSource`, `class QuestionBankUnavailableException implements Exception`, `whereIn`/`isEqualTo`/`orderBy` all present in code, shared `_read` applying the cache rule to both reads. Imported and constructed lazily by `setup_screen.dart:161`. |
| `lib/data/questions.dart` | Async seam (`subjects` + `questionsFor`) + `questionAt` | ✓ VERIFIED | 67 lines, no data. `Future<List<String>> subjects` = 1, `Future<List<String>> questionsFor` = 1, `questionAt` byte-identical. |
| `firestore.rules` | Knowingly-open questions rules with the exposure written down (D-46) | ✓ VERIFIED | `match /questions/{questionId} { allow read, write: if true; }` and nothing at the `/{document=**}` root. 29-line header comment naming what is open, why, the exit condition, and what is NOT exposed. |
| `firestore.indexes.json` | Composite index for the D-43 query | ✓ VERIFIED | `questions` / COLLECTION / `level` ASC, `subject` ASC, `created_at` ASC, `fieldOverrides: []`. Proven serving: the probe's query replay succeeded. |
| `firebase.json` | `firestore` block alongside the `flutter` block | ✓ VERIFIED | Both keys present; `flutter` block intact with project `reflex-english`. |
| `tool/seed_questions.mjs` | Disposable seed covering the D-45 matrix | ✓ VERIFIED | Runs; `--verify` exits 0 with 9/9 acceptance checks. `grep -c 'tool/node_modules' .gitignore` = 1; `grep -rn "tool/" lib/ \| wc -l` = 0. `tool/README.md` marks it disposable and names IMPORT-01 as its retirement trigger. |
| `lib/firebase_options.dart` | Generated project identity | ✓ VERIFIED | `DefaultFirebaseOptions` present (7 refs); referenced once from `main.dart`. |
| `lib/screens/setup_screen.dart` | Four topics states, three Start states, four helper states, two failure constants, zero-result function | ✓ VERIFIED | 1151 lines. All 10 required keys present exactly once. `kTopicsErrorMessage` = 3, `kQuestionLoadErrorMessage` = 3, `String noQuestionsMessage` = 1, `Starting session` = 1, `disabledBackgroundColor` = 3. No hex literal. |
| `test/screens/setup_screen_test.dart` | One scripted `FakeQuestionSource` driving all four read outcomes | ✓ VERIFIED | `grep -c 'implements QuestionSource'` = 1. Substantive behavioural assertions confirmed by reading the test bodies, not just their names. |
| `test/services/firestore_question_source_test.dart` | Host tests for the pure helpers | ✓ VERIFIED | 5 `sanitizedText` groups covering string/whitespace/null/non-String/trim-significant, plus a `kMaxTopicsPerQuery` assertion. |
| `test/fixtures/questions.dart` | Test-only prompt fixtures | ✓ VERIFIED | Present, 2 `const List<String>`, imported by 4 test files. |
| `.planning/PROJECT.md` | Narrowed offline requirement + 3 new Key Decisions rows | ✓ VERIFIED | Lines 19, 20, 27, 62, 63, 74, 75, 76, 77 all confirmed. |
| `.claude/CLAUDE.md` | Stack table updated for the first network dependency | ✓ VERIFIED | `cloud_firestore`/`firebase_core` rows carry installed 6.8.0/4.13.0; Conventions section populated; `Conventions not yet established` = 0. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/screens/setup_screen.dart` | `lib/services/firestore_question_source.dart` | `late final QuestionSource _questionSource = widget.questionSource ?? FirestoreQuestionSource()` | ✓ WIRED | `:160-161`, exact pattern. Lazy — a test injecting a fake never constructs a Firestore handle (asserted by the test "an injected source is the ONLY source consulted"). |
| `lib/screens/setup_screen.dart` | `lib/screens/practice_screen.dart` | resolved `List<String>` through the constructor (D-34) | ✓ WIRED | `:444-450` `PracticeScreen(config: config, questions: resolved, …)`. Test asserts `PracticeScreen.questions == bank`. |
| `lib/screens/practice_screen.dart` | `lib/state/practice_state.dart` | `PracticeState({required this.questions})` | ✓ WIRED | `practice_screen.dart:98` `questions: widget.questions`; `practice_state.dart:88` `required this.questions`, `:125` seeds `currentQuestion` from it. |
| `lib/main.dart` | `lib/firebase_options.dart` | `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` before `runApp` | ✓ WIRED | `main.dart:52-56`. |
| `lib/screens/setup_screen.dart` | `QuestionBankUnavailableException` | caught to choose could-not-load over empty | ✓ WIRED | `:244` and `:397`, two distinct catch sites (subjects read and Start query). |
| `test/screens/setup_screen_test.dart` | `lib/data/questions.dart` | `FakeQuestionSource implements QuestionSource` | ✓ WIRED | Exactly one such class in the whole test suite; imported cross-file by `practice_screen_test.dart`. |
| loop test files | `test/fixtures/questions.dart` | fixture import | ✓ WIRED | 4 importers (criterion asked ≥3). |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `_TopicsCard` rows | `_subjects` (`List<String>?`) | `_loadSubjects()` → `FirestoreQuestionSource.subjects()` → `collection('questions').get()` | Yes — 29 live documents / 5 distinct subjects confirmed by probe | ✓ FLOWING (device leg per SC1) |
| `PracticeScreen.questions` | `resolved` | `_questionSource.questionsFor(config)` → real server-side query | Yes — the identical query replayed live returns 7 ordered docs | ✓ FLOWING (device leg per SC2) |
| `PracticeState.currentQuestion` | `questions` | `questionAt(questions, questionNumber - 1)` | Yes — no hardcoded fallback; `lib/` holds no prompt constant | ✓ FLOWING |
| `_StartFooter.message` | `_startMessage` | `noQuestionsMessage(config.level, config.topics)` / `kQuestionLoadErrorMessage` | Yes — built from the tap-time snapshot, not from live controls | ✓ FLOWING |

No HOLLOW_PROP found: no call site passes `questions:` or `subjects:` a hardcoded empty literal in `lib/`.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Static analysis clean | `flutter analyze` | `No issues found! (ran in 5.5s)` | ✓ PASS |
| Full host suite green | `flutter test` (run once) | `00:25 +205: All tests passed!` | ✓ PASS |
| Live bank exists with the D-45 matrix | `node tool/seed_questions.mjs --verify` | exit 0; 29 docs; 5 subjects; Travel×B1=3, Travel×C1=0, Food&health×A1=0; 45-char subject; 2 malformed docs | ✓ PASS |
| The real D-43 query serves through the deployed composite index | (same probe, query-replay stage) | `subject in [Travel, Daily life] + level == B1 + orderBy created_at` → 7 docs | ✓ PASS |
| `created_at` is a native Firestore `Timestamp` and the query returns strictly ascending order | (same probe) | both PASS | ✓ PASS |
| Merged manifest permission set | `grep -o '<uses-permission…' build/.../debug/processDebugMainManifest/AndroidManifest.xml` | RECORD_AUDIO, INTERNET, ACCESS_NETWORK_STATE, app-namespaced receiver perm — nothing else | ✓ PASS |
| No Firestore write path in the app | `grep -nE '\.(set\|update\|delete)\(\|writeBatch\|SetOptions' lib/services/firestore_question_source.dart` | no matches | ✓ PASS |
| Loop reaches no Firebase symbol | `grep -rE 'cloud_firestore\|firebase_core\|FirebaseFirestore' lib/state/ lib/screens/practice_screen.dart` | no matches | ✓ PASS |
| Release-manifest re-derivation | `flutter build apk --release` | ? SKIP — release artifact was cleaned; corroborated via the merged debug manifest (W3) | ? SKIP |
| App running against the live bank | — | ? SKIP — no Android device or emulator attached | ? SKIP |

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| `tool/seed_questions.mjs` (read-only `--verify` mode) | `npm install --prefix tool && node tool/seed_questions.mjs --verify` | exit 0, all 9 acceptance checks PASS | PASS |

No `scripts/*/tests/probe-*.sh` exist in this repo; the phase's declared probe is the seed script's `--verify` mode, which was executed in this verifier's own process (not read from a SUMMARY claim).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BANK-01 | 03-01, 03-03 | Question bank stored in Firestore using `{id, content, subject, level, created_at}` | ✓ SATISFIED | Probe confirms every document carries exactly `content`/`subject`/`level`/`created_at` with `created_at` a native `Timestamp`; the auto-generated document key is the schema's `id` (Task 1 option-a, recorded in `kCreatedAtField`'s doc comment and `tool/README.md`). |
| BANK-02 | 03-01, 03-02, 03-03 | Topic list derived from distinct `subject` values, no separate topics collection | ✓ SATISFIED | `normalizeSubjects` (unit-tested: dedupe, distinctness, sort, blank-drop) fed by a single-collection read. No second collection anywhere. |
| BANK-03 | 03-01, 03-02, 03-03 | App fetches only questions matching the selected topics and level | ? NEEDS HUMAN | Query construction, the deployed index, the ordering and the no-trim/no-widen guards are all verified; the adapter has never run on a device (D-47). Matches REQUIREMENTS.md's own `Complete (device UAT pending)`. |
| SETUP-01 | 03-01, 03-03 | Topics selectable via checkboxes fetched from the Firestore bank | ? NEEDS HUMAN | Same D-47 boundary. Matches REQUIREMENTS.md's `Complete (device UAT pending)`. |

**Orphaned requirements:** none. REQUIREMENTS.md maps exactly BANK-01, BANK-02, BANK-03 and SETUP-01 to Phase 3, and every one is claimed by a plan. Every `IMPORT-*` row and `UI-03` still read `Pending` (Phase 4), as required.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | `TBD` / `FIXME` / `XXX` | — | **None.** `grep -rnE '\b(TBD\|FIXME\|XXX)\b' lib/ test/fixtures/ tool/seed_questions.mjs firestore.*` returns nothing. No unreferenced debt marker exists in any file this phase touched. |
| — | — | `TODO` / `HACK` / `PLACEHOLDER` | — | **None** in `lib/`, `test/fixtures/` or the seed script. |
| — | — | `KNOWN GAP` | — | **None** — `grep -rn "KNOWN GAP" lib/ test/` returns nothing. |
| `.planning/WINDOWS.md` | #3–#9 | Stale `open` ledger entries | ⚠️ Warning | Seven `stub` entries describe conditions that no longer exist in the code (see W1). Not a code defect — a ledger-accuracy problem that blocks `/gsd-ship`. |

**Known deviations — all five re-confirmed against the code, none re-reported as defects:**

1. `analysis_options.yaml` excludes `build/**` — CONFIRMED, and narrowly scoped: `build/` only, no project source excluded, with an in-file comment explaining that `cloud_firestore` checks its Dart sources into `build/macos/SourcePackages/`. Recorded as WINDOWS.md #11.
2. `sanitizedText` used as a usability VERDICT by `subjects()` (which carries the RAW value forward) and for its TRIMMED value by `questionsFor` — CONFIRMED at `firestore_question_source.dart:182-191` and `:240`. **Both behaviours are pinned by tests:** `normalizeSubjects` has "keeps values differing only by case or surrounding whitespace as distinct"; `sanitizedText` has "an ordinary string comes back trimmed" and "a string that is only meaningful after trimming is still usable". See W5 for the one residual: the adapter's own two call sites sit behind D-47's boundary.
3. `.planning/WINDOWS.md` edited by plan 03-03 outside its `files_modified` — CONFIRMED (commit `dbcea3c`: #12–#17 appended, #2 and #10 resolved). Frontmatter counts (17/15/2) agree with the table and the mirrored JSON.
4. `android/app/src/main/AndroidManifest.xml` edited by plan 03-03 outside its `files_modified` — CONFIRMED comment-only: `git diff 86313c1..HEAD` shows **no** `<uses-permission>` or `<permission>` line added, removed or changed; the file still declares `RECORD_AUDIO` alone.
5. Two of plan 03-01's literal grep counts unsatisfiable as written — CONFIRMED. `kQuestionsCollection` contains `kQuestions` as a substring (word-boundary grep resolves it; the two remaining hits are doc-comment lines recording the deletion). `allowRuntimeFetching = false` appears 2× (doc comment + code) and already did before the phase. Neither reflects a behavioural miss; the underlying must-haves are verified directly.

One further deviation worth recording, not a defect: plan 03-01 asked for `isFromCache` twice in the adapter ("applied in both reads"). The final code applies the rule **once**, in a shared `_read` helper that both reads go through — strictly better than duplicating it, and the doc comment says so explicitly ("writing the rule twice is how the two reads end up disagreeing about what 'empty' means").

### Human Verification Required

7 items. Six are on-device checks that are structurally impossible on a host machine (D-47), already recorded as open `unrun-verify` entries in `.planning/WINDOWS.md`. The seventh is an unmeasured latency observation.

#### 1. Networked-device tracer — the phase goal itself (WINDOWS.md #1)

**Test:** Launch the app on a networked Android device or emulator. Let the Topics card resolve. Check `Travel`, leave the level at B1, tap START SESSION.
**Expected:** The checkboxes are the five seeded Firestore subjects in case-insensitive sorted order — including `Technology, media and everyday digital habits` — not the five retired Phase 2 constants. The busy spinner appears, then the practice screen opens on a seeded Travel/B1 prompt. Selecting `Travel` + C1 instead shows the zero-result helper naming both and opens no session.
**Why human:** `FirestoreQuestionSource` resolves `FirebaseFirestore.instance`, which no `flutter test` process can construct (D-47). This is the only evidence that closes ROADMAP SC1 and SC2 and moves SETUP-01/BANK-03 off `Complete (device UAT pending)`.

#### 2. Malformed-document skip-and-log (WINDOWS.md #12 — covers E1/partial and E3/partial)

**Test:** On the device, inspect the topics card and run a `Daily life` B1 session and a `Travel` A1 session with the debug console attached.
**Expected:** No blank checkbox row; no blank question card mid-countdown; one `Skipping question <docId>: …` line per malformed document.
**Why human:** The skip is inside the adapter. `sanitizedText` is unit-tested; its application is not.

#### 3. E1/long-text at maximum OS text scale (WINDOWS.md #14)

**Test:** Set the OS text size to maximum, open Setup.
**Expected:** The 45-character seeded subject wraps and grows its 64px row rather than clipping; the topics card scrolls rather than pushing START SESSION off screen.
**Why human:** Visual rendering at a real accessibility text-scale setting.

#### 4. E2/long-text and the zero-result path end to end (WINDOWS.md #15)

**Test:** At maximum text scale, select three or more topics at a level with no matching questions to produce the longest zero-result message; then trigger the failure row (airplane mode with a cleared cache).
**Expected:** No RenderFlex overflow; the footer grows by shrinking the scroll area above; the button stays fully visible at 64px; every topic, the level and all three slider values are unchanged after both outcomes.
**Why human:** Layout overflow only manifests on a real viewport at a real text scale.

#### 5. E3/long-text at maximum OS text scale (WINDOWS.md #16)

**Test:** Run a session containing the seeded 324-character prompt; observe the reading, recording and paused states.
**Expected:** The prompt renders un-clipped in all three.
**Why human:** Visual rendering. Supersedes Phase 2's backstop, which was written against short curated constants.

#### 6. D-36 offline sequence, three parts (WINDOWS.md #17)

**Test:** (a) Online: load topics, complete a short session. (b) Airplane mode, force-stop, relaunch. (c) Clear app data while still offline, relaunch.
**Expected:** (a) and (b) work from the SDK cache; (c) shows `setup-topics-error` with its Try again button, **never** `setup-topics-empty`.
**Why human:** Needs airplane mode, force-stop and an app-data clear on hardware. Part (c) is exactly what PROJECT.md's narrowed offline requirement now claims in writing.

#### 7. Start-query latency — unmeasured, surfaced not failed (WINDOWS.md #13)

**Test:** Measure the wall time between tapping START SESSION and the practice screen appearing on a real device.
**Expected:** Under ~1 s. If it routinely exceeds that, the sanctioned follow-up is disabling the Setup form controls during the busy frame — **never** an overlay.
**Why human:** No device was attached for plan 03-02 or 03-03. The current design (tap-time snapshot wins, controls stay interactive) is an explicit passing host test; only real latency can decide whether it needs revisiting.

### Flagged Prohibitions (3 — non-authoritative LLM-judge verdicts)

All three of this phase's prohibitions are judgment-tier (the PLAN entries carry `requirement_id`/`category`/`statement`, with no `verification` field and no wired enforcement test). Per the fail-closed default they are recorded as `unverified-prohibition — human review recommended`, never silently green.

| Prohibition | Judge verdict | Evidence |
|-------------|---------------|----------|
| BANK-01 / privacy — nothing user-generated leaves the device; no telemetry SDK rides in with Firebase | held (flagged) | Only `firebase_core` + `cloud_firestore` in pubspec; no analytics/crashlytics/admob/messaging/performance package; no `firebase_storage`; zero Firestore write calls in `lib/`; merged manifest carries no AD_ID, location, account or analytics permission. |
| BANK-02 / transparency — an unserved or failed read is never presented as an empty bank | held (flagged) | The `isFromCache` throw in `_read`, the load-bearing branch order in `_TopicsCard._body`, and negative-assertion widget tests pinning each state against the other's key AND literal copy. Real cache path is item 6 above. |
| BANK-03 / values — no shortening, no level widening, no topic trimming, no fallback source | held (flagged) | `questionAt` cycles rather than caps (test 4); `isEqualTo` exact level; the over-limit branch throws and `topics.take`/`topics.sublist` appear nowhere; exactly one `implements QuestionSource` ships. |

### Gaps Summary

**No gaps.** Zero truths FAILED; zero artifacts MISSING, STUB or ORPHANED; zero key links NOT_WIRED; zero blocker anti-patterns; zero unreferenced debt markers. `flutter analyze` is clean, all 205 host tests pass, and the live Firestore bank verifies with all nine acceptance checks including a replay of the real D-43 query through the deployed composite index.

What is outstanding is **evidence, not implementation.** Eight truths are present and wired but their runtime behaviour has never been exercised, because the Firestore adapter is deliberately non-host-testable (D-47) and no Android device or emulator was attached during any wave. Two of those eight are the ROADMAP's own success criteria — the phase goal says the app *runs on* the real bank, and the app has never been run against it. That is why this phase is `human_needed` rather than `passed`: the code is complete and the plumbing is correct on every check a host can make, but the drill has not been observed working end to end.

Two orchestrator decisions are also outstanding and are recorded as warnings rather than gaps: the seven stale-`open` WINDOWS.md entries (W1) that will block `/gsd-ship` while describing conditions the code no longer has, and the MVP-mode / non-user-story goal mismatch (W2).

---

*Verified: 2026-08-09T11:17:21Z*
*Verifier: Claude (gsd-verifier)*
