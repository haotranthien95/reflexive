---
phase: 03-real-question-bank-via-firestore
plan: 03
subsystem: question-bank
tags: [firestore, docs, permissions, offline, cleanup, backstops, windows-ledger]
status: complete

requires:
  - "Plan 03-01's `QuestionSource` async seam, `FirestoreQuestionSource` and the live seeded `questions` collection"
  - "Plan 03-02's four honest read outcomes, `FakeQuestionSource` and `kMaxTopicsPerQuery`"
provides:
  - "`test/fixtures/questions.dart` — the test-only prompt/topic fixtures that replaced the shipped placeholder bank"
  - "A `lib/` with exactly one question source and no practice prompt or topic name in it"
  - "The verified merged-release-manifest permission set, with every entry attributed to its contributing dependency"
  - "PROJECT.md's narrowed offline requirement and three new Key Decisions rows (permissions, open rules, questions-resolved-on-Setup)"
  - "`.claude/CLAUDE.md`'s populated Conventions section — the nine house rules Phases 1-3 established"
  - "Six `unrun-verify` ledger entries carrying every on-device check this phase still owes"
affects:
  - "Phase 4's importer (IMPORT-01..05) — inherits the settled document contract, the repo-is-source-of-truth rules posture, and `kMaxTopicsPerQuery` as the named trigger for batching"
  - "Any future dependency change — the manifest-audit method is now recorded with the grep that would have caught what Phase 2's missed"

tech-stack:
  added: []
  patterns:
    - "Test fixture data lives in `test/fixtures/`, never in `lib/` — a shipped constant that only tests use is a second source of truth waiting to be mistaken for the real one"
    - "Permission claims are written from the MERGED release manifest plus the merger's blame report, never from the source manifest and never from inference"
    - "Grep merged manifests for `<uses-permission`, not for `android.permission.*` — the latter structurally cannot match an app-namespaced permission"

key-files:
  created:
    - "test/fixtures/questions.dart"
  modified:
    - "lib/data/questions.dart"
    - "test/state/practice_session_test.dart"
    - "test/state/practice_state_test.dart"
    - "test/screens/practice_screen_test.dart"
    - "test/screens/setup_screen_test.dart"
    - ".planning/PROJECT.md"
    - ".claude/CLAUDE.md"
    - ".planning/REQUIREMENTS.md"
    - ".planning/WINDOWS.md"
    - "android/app/src/main/AndroidManifest.xml"

decisions:
  - "The merged release manifest carries FOUR permission entries, not the three the plan predicted. The fourth is an app-scoped `signature`-level receiver permission from `androidx.core:core:1.13.1`, which the Flutter embedding pulls in — NOT Firebase. Reported rather than accepted silently."
  - "Firebase contributed TWO permissions, not one: `INTERNET` and `ACCESS_NETWORK_STATE`, both from `firebase-firestore:26.5.0`. The source manifest's comment claimed INTERNET alone and was corrected."
  - "Fixture constants were renamed (`kFixtureQuestions` / `kFixtureFirstPrompt` / `kFixtureSubjects`) rather than carried over under their old names, so no test body can read as if it were drilling the shipped bank."
  - "`_kTestSubjects` moved out of `setup_screen_test.dart` into the shared fixture, so all four test files draw stand-in bank data from one place."
  - "Context7 was unreachable again; the offline-cache semantics were read out of the INSTALLED `cloud_firestore 6.8.0` / `cloud_firestore_platform_interface 8.0.6` sources rather than written from recall."

metrics:
  duration: "~50 min"
  completed: 2026-08-09
  tasks: 3
  commits: 3

actuals:
  tokens: 13000
  tasks: 3
  commits: 3
---

# Phase 3 Plan 03: Closing the Phase Honestly — Summary

The app now ships exactly one question bank and the docs say which one it is: the placeholder
prompts and topic names are deleted from `lib/`, the offline promise is narrowed in writing to
what the Firestore cache actually delivers, the open-rules tradeoff is recorded with its
exposure and its exit condition, and the release build's permission set is written from the
merged manifest — where it turned out to differ from what the plan predicted, in two ways.

## The merged-release-manifest permission audit (D-39, required)

`flutter build apk --release` exited 0 (296.4 s, 51.1 MB APK). The merged manifest was found at:

```
build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml
```

**The complete permission set, verbatim — four entries, not three:**

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.INTERNET" />
<permission
    android:name="com.englishreflex.englishreflex.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
    android:protectionLevel="signature" />
<uses-permission android:name="com.englishreflex.englishreflex.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" />
```

Every entry is attributed from the merger's own blame report
(`build/app/intermediates/manifest_merge_blame_file/release/processReleaseMainManifest/manifest-merger-blame-release-report.txt`),
not guessed:

| Permission | Contributed by |
|---|---|
| `android.permission.RECORD_AUDIO` | this app's own `android/app/src/main/AndroidManifest.xml:19` (Phase 1, `package:record`) |
| `android.permission.ACCESS_NETWORK_STATE` | `com.google.firebase:firebase-firestore:26.5.0`, its manifest line 10 |
| `android.permission.INTERNET` | `com.google.firebase:firebase-firestore:26.5.0`, its manifest line 11 |
| `com.englishreflex.englishreflex.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `androidx.core:core:1.13.1`, its manifest lines 22–26 |

**PASS on the class D-39 actually asked to watch for.** No analytics permission, no
advertising-ID permission (no `com.google.android.gms.permission.AD_ID`), no location
permission, no account permission. `WRITE_EXTERNAL_STORAGE` appears exactly once in the merged
file and it is **inside the app's own explanatory comment** — it is not requested.

### Two findings the plan did not predict, reported rather than accepted

**1. Firebase contributed TWO permissions, not one.** The plan (and plan 01's source-manifest
comment, and WINDOWS.md entry #2) all expected `INTERNET` alone from Firebase, with
`ACCESS_NETWORK_STATE` framed as a "may also contain" possibility. The blame report shows both
come from the same `firebase-firestore:26.5.0` manifest, two lines apart. This is the expected,
benign grant the plan describes — it lets the SDK observe connectivity and decide when to fall
back to its cache, and it grants no data access — so it is **not** a phase failure. But the
source manifest's comment asserted the narrower claim as fact, so it was corrected (see
Deviations).

**2. A fourth entry exists, and it is not Firebase's.**
`com.englishreflex.englishreflex.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` is declared and used
by `androidx.core:core:1.13.1`. I confirmed its origin rather than assuming: `androidx.core:core`
at exactly version `1.13.1` is a direct `compile` dependency of
`io.flutter:flutter_embedding_release`, per that artifact's own POM in the Gradle cache. So it
arrives with the **Flutter Android embedding**, not with Firebase, and it would have been in the
Phase 2 release manifest too.

Why nobody saw it before: it is scoped to the app's own package namespace, so a grep for
`android.permission.*` — which is exactly what Phase 2's inspection and this plan's own
`<automated>` verify line use — **structurally cannot match it**. It is `protectionLevel="signature"`,
meaning only an app signed with the same key could ever hold it; androidx.core declares it so
`ContextCompat.registerReceiver(..., RECEIVER_NOT_EXPORTED)` has a permission to name on API 33+.
It grants no data, device or network access. Not a regression, and not in D-39's failure class —
but it was invisible to the method Phase 2 recorded, so the method is now recorded with the
correct grep (`<uses-permission`) in both `AndroidManifest.xml` and `.claude/CLAUDE.md`.

## Task 1 — the placeholder bank is gone (commit `3113406`)

`kQuestions` (20 prompts), `kSubjects` (5 topic names) and `PlaceholderQuestionSource` are
deleted from `lib/data/questions.dart`. D-36 rejected keeping any of them as an offline
fallback, and the file's new header records that reasoning rather than leaving a reader to
wonder where the prompts went.

The prompts moved verbatim into **`test/fixtures/questions.dart`** — content unchanged on
purpose, because the loop tests assert exact strings and exact ordering, so rewording would have
turned a file-move into a behavioural change and hidden any real regression inside the churn.
What did change is the **names**: `kFixtureQuestions`, `kFixtureFirstPrompt`, `kFixtureSubjects`.
A test body reading `answers.first.questionText == kQuestions.first` is ambiguous about whether
it is drilling the shipped bank; the `kFixture` prefix removes that ambiguity at every call site.

Two consolidations beyond a straight move, both recorded in the fixture's doc comment:

- `kQuestionsFirstPrompt`, which lived at the foot of `practice_session_test.dart` and was
  imported cross-file by `practice_screen_test.dart`, moved into the fixture.
- `_kTestSubjects`, a private mirror of the retired `kSubjects` living in
  `setup_screen_test.dart`, moved into the fixture as `kFixtureSubjects` — so all **four** test
  files now draw stand-in bank data from one place instead of two.

The one remaining `PlaceholderQuestionSource` construction (the Setup → session end-to-end test)
now injects the suite's single `FakeQuestionSource`, imported from `setup_screen_test.dart`.
A local second implementation would have been a second model of how a read succeeds, fails or
comes back empty — the duplication this project's conventions reject, and the reason
`practice_screen_test.dart` already imports its doubles cross-file.

`questionAt` is **byte-identical** (D-42), verified by exact-string grep. No behaviour changed.

## Task 2 — the docs describe the app that now exists (commit `02bb7c9`)

**`.planning/PROJECT.md`.** The offline requirement previously promised a fully offline loop
with *no network permission in the release build*. That is now false, and the replacement says
what is true: the loop runs offline **after one successful online Setup visit**, served by the
Firestore SDK's on-device cache — and a device that has never been online has an empty cache and
**cannot start a session**, landing on the could-not-load state rather than the empty one. The
surviving half of the old promise is kept explicitly, because it is the half that matters
mid-drill: no outbound request happens on any path *inside* the loop, since both reads are on
Setup. SETUP-01 moved to Validated, a Validated entry for the Firestore bank and its schema was
added, and the Key Decisions table gained the three required rows (permission posture, open
rules with exposure + exit condition, questions-resolved-on-Setup) while three rows flipped off
`— Pending`.

**`.claude/CLAUDE.md`.** The `wakelock_plus` row's claim that `RECORD_AUDIO` is the release
build's only permission is explicitly **retired** — stated as "it was true then and is false
now" rather than quietly overwritten, so the Phase 2 record still reads as having been correct
when written. Its actual point is preserved: `wakelock_plus` still declares no permission of any
kind. The `google_fonts` row's justification was inverted rather than deleted: the bundled asset
and `allowRuntimeFetching = false` now matter **more**, because with `INTERNET` genuinely
present a runtime font fetch would no longer fail at the permission boundary — it would succeed
silently, reintroducing a first-frame network round-trip. The `cloud_firestore` /
`firebase_core` rows carry the resolved versions from `pubspec.lock` (**6.8.0** and **4.13.0**),
the `questions` collection, D-32's refinement, and the 30-value `whereIn` cap with the note that
the SDK's own assert is stripped from release builds. The Firestore rules row now says the repo
is the source of truth and the console must not be edited. The **Conventions** section replaced
its "not yet established" placeholder with the nine rules Phases 1–3 established.

**`.planning/REQUIREMENTS.md`.** SETUP-01 and BANK-01..03 off `Pending`. BANK-01 and BANK-02 are
unqualified `Complete` — the schema is asserted against the live project by
`tool/seed_questions.mjs --verify` and the topic-derivation rule is a pure function under direct
unit test. SETUP-01 and BANK-03 are `Complete (device UAT pending)`, because the adapter is
deliberately not host-testable (D-47). Every `IMPORT-*` row and `UI-03` still read `Pending`.

### The offline claim, and where it was confirmed

**Context7 was not reachable from this agent, and no substitute was invented.** The
`mcp__context7__*` tools were absent from this agent's tool set (the known upstream bug), and
`ctx7` is not installed on this machine; the executor contract forbids `npx --yes` to fetch it.
The claim was therefore read out of the **installed** package sources rather than from recall:

- `cloud_firestore_platform_interface-8.0.6/lib/src/pigeon/messages.pigeon.dart:129-146` — the
  `Source` enum. The default, `serverAndCache`, "[causes] Firestore to try to retrieve an
  up-to-date (server-retrieved) snapshot, but fall back to returning cached data if the server
  can't be reached." And decisively for the cold-cache case: with no data in the cache,
  "`Query.get` will return an **empty** `QuerySnapshotPlatform` with no documents" — an empty
  result, *not* an error.
- `cloud_firestore_platform_interface-8.0.6/lib/src/settings.dart` and
  `method_channel_firestore.dart:349` (`if (settings.persistenceEnabled == false) return null;`)
  — `persistenceEnabled` is nullable and only an explicit `false` disables disk persistence, so
  the app inherits the native SDK's on-by-default persistence without configuring anything.

That is exactly why plan 01's cache-versus-server rule is load-bearing and why the narrowed
wording is honest: on a never-online device the read comes back as zero documents with
`metadata.isFromCache == true`, which `FirestoreQuestionSource._read` converts into
`QuestionBankUnavailableException` — the could-not-load state — instead of letting it render as
"your questions are gone".

## Task 3 — the checks a host test cannot make

The automated half ran and is recorded above. **The on-device half did not run: no Android
device or emulator was attached to this session.** `flutter devices` offered an iOS 16.7 handset,
macOS and Chrome — none of which can discharge an Android release-build check, and none of which
this agent can observe a screen on, set an OS text-scale on, or toggle airplane mode on.

Rather than assert outcomes I did not observe, every one of these is recorded as an open
`unrun-verify` in `.planning/WINDOWS.md` (commit `dbcea3c`), which is where the phase's owed
evidence now lives:

| UI-SPEC backstop | Status | Ledger |
|---|---|---|
| E1/partial — malformed doc produces no blank checkbox row | **NOT RUN** — needs the two malformed seeded documents on a device | #12 |
| E1/long-text — 45-char subject wraps and grows its 64px row at max text scale | **NOT RUN** | #14 |
| E2/long-text — Start footer shows no RenderFlex overflow at max text scale | **NOT RUN** | #15 |
| E3/partial — malformed doc produces no blank prompt mid-countdown | **NOT RUN** — same device check as E1/partial | #12 |
| E3/long-text — 324-char prompt renders un-clipped in reading/recording/paused | **NOT RUN** | #16 |
| D-36 offline sequence (three parts) | **NOT RUN** | #17 |
| Zero-result path — message names level and topic, no setting lost | **NOT RUN** on device (host-tested by plan 02) | #15 |

E1/partial and E3/partial are deliberately **one** ledger entry, not two, because they are the
same run against the same two seeded documents — the plan's own instruction was to make the
ledger entry and the backstop agree rather than double-count.

What *is* proven without a device, and is worth separating from what is not: the malformed-document
rule itself (`sanitizedText`) is under direct unit test; the zero-result copy's three branches are
asserted verbatim; the four topics-card states and the footer's mutual exclusion are asserted by
widget tests; and the seeded content the backstops target (the 45-char subject, the 324-char
prompt, the two malformed documents, the two empty topic×level cells) is confirmed present in the
live project by `tool/seed_questions.mjs --verify`. What is unproven is specifically **rendering
and adapter behaviour on real hardware**, which is exactly where D-47 draws the host-testability
line for this phase and where Phase 1 drew it for the microphone.

## Verification

| Gate | Result |
|------|--------|
| `flutter analyze` | No issues found |
| `flutter test` | **205/205 pass** — identical to the plan's base commit; no test added, removed or skipped |
| `flutter build apk --release` | exit 0, `build/app/outputs/flutter-apk/app-release.apk` (51.1 MB) |
| Merged release manifest found | yes, `processReleaseMainManifest/AndroidManifest.xml` |
| D-39 failure classes (analytics / ad-ID / location / account) | **none present** |
| Practice prompts or topic names in `lib/` | **none** — grep for the retired prompt/topic strings returns nothing |
| `kQuestions` / `kSubjects` / `PlaceholderQuestionSource` in `lib/` code | **none** — only in the doc comment recording the deletion (see below) |
| `grep -c 'String questionAt(List<String> bank, int index) => bank\[index % bank.length\];'` | 1 — byte-identical (D-42) |
| `class … implements QuestionSource` in `lib/` | 1 — `FirestoreQuestionSource` is the only shipped implementation |
| Test files importing `fixtures/questions.dart` | 4 (criterion asked for ≥ 3) |
| `const List<String>` in the fixture | 2 |
| `.planning/PROJECT.md` still claiming no network permission | 0 |
| `Conventions not yet established` in `.claude/CLAUDE.md` | 0 |
| `IMPORT-*` and `UI-03` traceability rows | all still `Pending` |
| WINDOWS.md frontmatter vs table vs JSON | agree: 17 total, 15 open, 2 fixed; IDs contiguous; JSON parses |
| `STATE.md` / `ROADMAP.md` modified | **neither** — correct for worktree mode |

### One acceptance criterion whose literal form was unsatisfiable, recorded rather than rounded

Task 1 specified `! grep -rEq 'kQuestions|kSubjects|PlaceholderQuestionSource' lib/`. That
expression cannot pass in this repo for a reason unrelated to the placeholder bank: plan 01's
`kQuestionsCollection` constant in `lib/services/firestore_question_source.dart` contains
`kQuestions` as a substring. Adding word boundaries (`\bkQuestions\b`) resolves that collision.

With boundaries applied, two matches remain, both on **doc-comment lines** in
`lib/data/questions.dart` that name the three symbols in order to explain that they were deleted
and why. A comment-stripped grep returns nothing. I kept that comment deliberately: a future
reader who greps for `kQuestions` should land on the explanation rather than on silence, and the
criterion's real intent — the must-have's own wording, *"no Dart constant in `lib/` holds
practice prompts or topic names any more"* — is verified directly and passes.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 — Bug] `android/app/src/main/AndroidManifest.xml`'s comment stated a permission
claim the merged manifest disproves**

- **Found during:** Task 3's manifest audit, cross-read against Task 2's doc work.
- **Issue:** The comment written in plan 01 said the merged release manifest "also carries
  INTERNET, contributed TRANSITIVELY by cloud_firestore", and instructed the next reader to
  "confirm INTERNET is the only thing Firebase brought". The blame report shows
  `firebase-firestore:26.5.0` contributes **`INTERNET` and `ACCESS_NETWORK_STATE`**. Left alone,
  the file that documents the permission posture would have contradicted the audit performed in
  the same phase, and would have actively misdirected the next dependency change.
- **Fix:** Corrected to name both permissions and why each exists, recorded the complete verified
  four-entry set with attributions, and added the concrete instruction to grep merged manifests
  for `<uses-permission` rather than `android.permission.*` — the filter that hid the
  androidx.core entry from Phase 2's inspection.
- **Files modified:** `android/app/src/main/AndroidManifest.xml` (not in the plan's
  `files_modified`; the plan did not anticipate the audit falsifying a source comment).
- **Commit:** `02bb7c9`

### Orchestrator-authorised scope addition

**2. `.planning/WINDOWS.md` — appended six entries and resolved two.**

Not in this plan's `files_modified`. Added on **explicit orchestrator instruction**, which routed
plan 03-02's two deferred items here because this is the phase's closing plan and the last wave,
so there is no concurrent writer to conflict with. Plan 03-02's executor had deliberately refused
to write this shared cross-phase ledger from a parallel worktree, which was the right call.

Recorded so the deviation is traceable and not mistaken for scope creep. The six appended entries
are the two handoff items (#12 malformed-document skip-and-log, #13 the unmeasured Start-query
latency with its ~1 s threshold and its sanctioned response — *disable the form controls during
the busy frame, never an overlay*) plus this plan's own four backstops (#14–#17). The two resolved
entries are #2 and #10, both discharged by this plan's own work.

`gsd-tools` in this installation has no `windows` verb, so the file was edited directly in its
existing format — table, mirrored JSON block and frontmatter counts all updated together and
verified consistent.

### Deliberate refinements (judgement calls, not drift)

**3. Fixture constants were renamed rather than carried over under their old names.** The plan
said the prompts "may be carried over verbatim; what must change is where they live." The
*content* is verbatim; the *identifiers* gained a `kFixture` prefix. Keeping `kQuestions` as a
test-file name would have preserved, in every assertion, the exact ambiguity this task exists to
remove — whether the thing being drilled is the shipped bank.

**4. `_kTestSubjects` moved into the fixture, making it four importers rather than three.** The
plan's criterion asked for ≥ 3 test files importing the fixture and its action text said "update
the four test files". Moving `setup_screen_test.dart`'s private topic mirror into the shared
fixture satisfies both and removes the last place where stand-in bank data was duplicated.

**5. A third Key Decisions row was flipped off `— Pending` beyond the two the plan named.**
"Question bank lives only in Firebase; history/recordings live only on-device" is precisely the
decision this phase made real in both directions. Leaving it `Pending` in the same edit that
added a row asserting recordings are never transmitted would have been internally inconsistent.

**6. WINDOWS.md entries #3–#9 were left `open` rather than resolved — flagged for the
orchestrator.** These are plan 03-02's stub entries, and they appear **verifiably closed**:
`setup-topics-loading`/`setup-topics-error` (#3, #4), `setup-start-error` (#5),
`setup-start-no-questions` (#6) and `setup-start-busy` (#7) are all present in
`lib/screens/setup_screen.dart`; the adapter carries six `debugPrint` skip-and-log sites (#8) and
five `kMaxTopicsPerQuery` references (#9); and plan 02's summary records
`grep -rn "KNOWN GAP" lib/ test/` returning no matches. I did not mark them fixed: they are
another plan's ledger entries and its executor deliberately did not touch this file, so resolving
them was outside what the orchestrator authorised. **Recommend the orchestrator resolve #3–#9 on
merge** — otherwise `/gsd-ship` stays blocked on seven entries describing conditions that no
longer exist in the code.

## Known Stubs

**None introduced.** This plan deleted a stub (the placeholder bank) and added no new one. Every
outstanding item is an *unrun verification*, not unwired code, and each is in the ledger.

## Threat Flags

**None new.** No network endpoint, auth path, file access pattern or schema change at a trust
boundary was introduced — this plan deletes code and writes documentation. The phase's standing
flags (`network-egress`, `unauthenticated-write`, `credential-in-repo`) were raised in 03-01 and
are unchanged.

Two things worth naming as positive outcomes rather than flags: the `network-egress` flag's owed
evidence — D-39's merged-release-manifest inspection — **is now discharged**, with the result that
the network surface is confirmed to be exactly two transitive Firebase permissions and nothing
else; and the `unauthenticated-write` posture is now documented in PROJECT.md's Key Decisions with
its concrete exposure and its exit condition, not only in a rules-file comment that a reader would
have to know to open.

## Self-Check: PASSED

Created file verified present: `test/fixtures/questions.dart` — FOUND.
Release artifact verified present: `build/app/outputs/flutter-apk/app-release.apk` (51,079,966 bytes) — FOUND.
Merged release manifest and merger blame report verified present — both FOUND.

Commits verified in `git log`: `3113406` (Task 1) — FOUND. `02bb7c9` (Task 2) — FOUND.
`dbcea3c` (Task 3 ledger) — FOUND.

`git diff --diff-filter=D` is empty for all three commits — no file was deleted by any of them
(the placeholder bank was removed *within* `lib/data/questions.dart`, which survives).
`git diff --name-only <base>..HEAD` confirms **neither `STATE.md` nor `ROADMAP.md` was modified**,
as required for worktree mode.
