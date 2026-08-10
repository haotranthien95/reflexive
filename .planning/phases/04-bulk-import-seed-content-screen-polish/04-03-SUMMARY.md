---
phase: 04-bulk-import-seed-content-screen-polish
plan: 03
subsystem: setup-screen
tags: [navigation, ui-03, error-copy, firestore, whereIn, enum-totality, flutter]

requires:
  - phase: 04-bulk-import-seed-content-screen-polish
    plan: 01
    provides: "the setup-import AppBar action, _openImportSheet's dismissal await, the two pass-through seams, ImportSheet, and kLevels relocated into firestore_question_source.dart"
  - phase: 03-real-question-bank-via-firestore
    provides: "kMaxTopicsPerQuery and its guard, QuestionBankUnavailableException, kQuestionLoadErrorMessage, the Start-footer helper slot and _clearStartMessage"
provides:
  - "TooManyTopicsException — the over-limit signal, distinct from the bank-unreachable one"
  - "kTooManyTopicsMessage — the fourth Start-footer string"
  - "StartMessageKind — the total enum that replaced the is-this-a-failure bool"
  - "the setup-start-too-many-topics helper key"
  - "docs/NAVIGATION.md — the repo-side navigation contract that discharges UI-03 (D-49)"
  - "_kStartHelperKeys + a top-level helpersPresent() in test/screens/setup_screen_test.dart, iterated rather than enumerated"
affects: [04-04 tool deletion and docs, 04-05 seed import and on-device UAT]

actuals:
  tokens: 38750
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A total enum replacing a boolean treatment flag, consumed by an exhaustive switch — a fifth case fails to compile rather than falling through the last else"
    - "Two failures with two causes get two exception types, so the catch site can tell them apart without inspecting a message"
    - "A written classification rule in the repo, so a requirement about counts can be checked rather than argued"

key-files:
  created:
    - docs/NAVIGATION.md
  modified:
    - lib/services/firestore_question_source.dart
    - lib/screens/setup_screen.dart
    - test/screens/setup_screen_test.dart
    - test/services/firestore_question_source_test.dart

key-decisions:
  - "_helper dispatches on an EXHAUSTIVE switch over StartMessageKind rather than growing the else-if chain the plan described — same branch order, same four keys, but a fifth helper now fails to compile until it has a branch instead of silently inheriting the last else"
  - "docs/NAVIGATION.md records SessionDetailScreen's SECOND entry point (Practice's completion state, D-27), which neither the plan nor the UI-SPEC inventory mentions; the classification is unchanged because both entry points are content, not chrome"
  - "The 30 in kTooManyTopicsMessage is a literal, not an interpolation of kMaxTopicsPerQuery — the copy is a reviewed sentence, and an SDK bump must not silently rewrite user-facing text"
  - "REQUIREMENTS.md was deliberately NOT edited: it is outside this plan's declared files_modified and is a shared artifact another wave-2 agent could also write"
  - "FakeJsonFilePicker and FakeQuestionBankWriter are imported from import_sheet_test.dart rather than copied, completing a two-way test-library import that Dart permits and the conventions require"

patterns-established:
  - "The footer's helper-key list lives in one const at file level and every exclusivity assertion iterates it, so the invariant cannot be outgrown silently"
  - "A doc that discharges a countable requirement states the rule, the inventory, the result and the maintenance pairing — in that order — so the next reader re-counts rather than re-argues"

requirements-completed: []

coverage:
  - id: D1
    description: "A Start attempt refused for exceeding the whereIn cap renders its own helper key, its own fixed string, and no error icon"
    requirement: UI-03
    verification:
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#an over-limit refusal names the limit and the fix, and is a DIFFERENT helper from a bank failure"
        status: pass
    human_judgment: false
  - id: D2
    description: "The over-limit signal and the bank-unreachable signal are distinct types, and a catch site routes them to two different messages"
    verification:
      - kind: unit
        ref: "test/services/firestore_question_source_test.dart#TooManyTopicsException (D-61)"
        status: pass
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#the SAME screen renders a different key when the bank is unreachable instead"
        status: pass
    human_judgment: false
  - id: D3
    description: "At most one of the four Start-footer helper keys is present in any frame, asserted by iterating the key list rather than by naming keys"
    verification:
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#at most one of the FOUR helper keys, in every state that produces one"
        status: pass
    human_judgment: false
  - id: D4
    description: "The over-limit helper clears on any topic toggle, any level change and any slider change, exactly as the other Start helpers do"
    verification:
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#the over-limit helper clears on a topic toggle, a level change and a slider change"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every topic, the level and all three slider values survive the over-limit path unchanged"
    verification:
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#the over-limit path costs the user nothing"
        status: pass
    human_judgment: false
  - id: D6
    description: "docs/NAVIGATION.md names every navigable surface with its classification, and exactly three are core screens"
    requirement: UI-03
    verification:
      - kind: command
        ref: "grep -c 'Core screen' docs/NAVIGATION.md → 3; every screen class present; ls lib/screens/*.dart | wc -l → 5, all classified"
        status: pass
    human_judgment: false
  - id: D7
    description: "The import surface added no page route — grep MaterialPageRoute over lib/screens/ lists only the four pre-existing push sites"
    requirement: UI-03
    verification:
      - kind: command
        ref: "grep -rn 'MaterialPageRoute' lib/screens/ → history_screen:95, setup_screen:401, setup_screen:581, practice_screen:203"
        status: pass
    human_judgment: false
  - id: D8
    description: "Both sheet-dismiss routes re-read Setup's topics, including one the sheet's own buttons never see"
    verification:
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#closing the sheet through Done re-reads the topics"
        status: pass
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#closing the sheet WITHOUT touching Done re-reads the topics too"
        status: pass
    human_judgment: true
    rationale: "The Done path and a direct route pop are host-drivable. Drag-down and barrier tap are gesture routes a widget test only simulates artificially; the UI-SPEC flags PopScope's coverage of them as Flutter-version-dependent and requires on-device verification, which is plan 04-05's."
  - id: D9
    description: "A deliberately long imported subject name grows its 64px topic row at the largest text scale rather than clipping"
    verification:
      - kind: unit
        ref: "test/screens/setup_screen_test.dart#grows its topic row at the largest text scale instead of clipping"
        status: pass
    human_judgment: false
  - id: D10
    description: "The over-limit guard's real throw site is reached by a >30-topic selection against the live bank"
    verification: []
    human_judgment: true
    rationale: "Reaching the guard means calling FirestoreQuestionSource.questionsFor, which resolves FirebaseFirestore.instance and is not host-testable (D-47). The tests prove the signal, the routing and the copy; only a device with a bank ≥31 subjects wide proves the guard fires there. Plan 04-05's ten-subject seed does not reach it, so this stays an on-device check whenever the bank crosses 30."

duration: 18min
completed: 2026-08-10
status: complete
---

# Phase 4 Plan 03: UI-03 made countable, and the 30-topic cap made honest Summary

**`docs/NAVIGATION.md` turns UI-03 from an argument about five files under `lib/screens/`
into a rule anyone can re-count, and the over-30-topics refusal stops blaming the user's
connection: it throws its own type, lands on its own fixed sentence under its own key, and
carries no error icon — because it is a setting to change, not a fault to retry.**

## Performance

- **Duration:** ~18 min
- **Tasks:** 3
- **Files modified:** 5 (1 created, 4 modified)
- **Test suite:** 235 → 247 tests, all green; `flutter analyze --no-fatal-infos` clean

## Accomplishments

- **The over-limit refusal is now a first-class outcome, end to end.** A distinct signal
  (`TooManyTopicsException`), a distinct catch arm placed above the bank-unreachable one, a
  distinct fixed string (`kTooManyTopicsMessage`), a distinct key
  (`setup-start-too-many-topics`), and no icon. Before this plan, a user with 40 topics
  ticked was told to check a connection that was working perfectly.
- **The footer's exclusivity invariant got stronger, not just wider.** The
  `_startMessageIsFailure` bool is gone — not supplemented — replaced by a three-value
  `StartMessageKind` consumed by an exhaustive `switch`. Two independently-settable
  booleans are how two helper lines end up on screen at once; an enum can only hold one
  value, and the compiler now refuses a fifth kind that has no branch.
- **`kMaxTopicsPerQuery`'s doc comment stopped claiming something that is no longer true.**
  The deferred batched multi-query merge and its reversal trigger are untouched; what was
  deleted is the closing paragraph that accepted connection-blaming copy *on the grounds
  that the branch was unreachable at the bank size of the time*. This phase's importer is
  exactly what makes it reachable, so the acceptance expired here (D-61).
- **UI-03 can be checked by counting.** `docs/NAVIGATION.md` states the three-clause
  definition of a core screen, inventories all five files under `lib/screens/` plus both
  modal surfaces, lands on "3 core screens, 1 detail view, 2 modals, 0 extraneous
  navigation", and names the rule a future surface has to satisfy — including why the
  importer was built as a bottom sheet in the first place.
- **The Setup-side import wiring is pinned by host tests it did not have.** The two AppBar
  actions and their order, both sheet-dismiss refresh routes (including one the sheet's own
  buttons never see), and the stale-helper clear on dismissal.

## Task Commits

1. **Task 1: The over-limit refusal gets its own type and its own sentence** — `0968fb5` (feat)
2. **Task 2: Write down what counts as a screen, so UI-03 can be counted** — `d995ddc` (docs)
3. **Task 3: Test the Setup surface this phase changed** — `9ba77f0` (test)

## Files Created/Modified

- `docs/NAVIGATION.md` *(new)* — the problem statement, the three-clause AND definition of a
  core screen, the complete surface inventory table, the result line, the rule for future
  surfaces, and the maintenance pairing with `REQUIREMENTS.md`'s UI-03 row.
- `lib/services/firestore_question_source.dart` — `TooManyTopicsException` beside its
  sibling; the `questionsFor` guard throws it; `kMaxTopicsPerQuery`'s closing paragraph
  rewritten and tagged D-61.
- `lib/screens/setup_screen.dart` — `kTooManyTopicsMessage`, `enum StartMessageKind`, the
  `_startMessageKind` field replacing the bool, the new catch arm in `_startSession`, and
  `_StartFooter._helper`'s exhaustive four-way dispatch.
- `test/screens/setup_screen_test.dart` — `_kStartHelperKeys`, a top-level
  `helpersPresent()`, injectable import seams in the harness, and 9 new tests across three
  new groups.
- `test/services/firestore_question_source_test.dart` — a `TooManyTopicsException` group
  (self-naming, type distinctness, catch-arm ordering) and an extended `kMaxTopicsPerQuery`
  pin comment.

## Decisions Made

- **`_helper` dispatches on an exhaustive `switch`, not on a longer else-if chain.** The
  plan asked for "the fourth branch in the else-if chain", justified by wanting the keys
  "mutually exclusive by construction rather than by conditions kept disjoint by hand". A
  `switch` over a total enum delivers that justification more completely than the chain
  does: with a chain, a fifth `StartMessageKind` silently renders whatever the final `else`
  produces; with the switch, it does not compile. Same branch order, same four keys, same
  treatments — a stronger guarantee behind them.
- **`docs/NAVIGATION.md` names `SessionDetailScreen`'s second entry point.** See Deviations.
- **The `30` in the copy is a literal.** Interpolating `kMaxTopicsPerQuery` into the
  `const` string would be tidier and would let an SDK bump rewrite a reviewed user-facing
  sentence with nobody reading the result. The doc comment says so, so the next person does
  not "fix" it.
- **`REQUIREMENTS.md` was not touched, and UI-03 is not ticked here.** It is outside this
  plan's declared `files_modified`, and plan 04-02 is running concurrently in its own
  worktree — 04-01 skipped it for the same reason. Everything UI-03 needs now exists in the
  repo and the audit trail is in this summary's `coverage` block; the tick belongs to
  whoever writes the shared file after the wave merges.
- **Test doubles crossed in both directions rather than being copied.**
  `import_sheet_test.dart` already imports `FakeQuestionSource` out of
  `setup_screen_test.dart`; this plan imports `FakeJsonFilePicker` and
  `FakeQuestionBankWriter` back the other way. Dart permits the cycle, and one double per
  seam is what the conventions ask for. The alternative — hoisting both into
  `test/fixtures/` — would have meant editing a file plan 04-02 owns this wave.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] `SessionDetailScreen` has TWO entry points, and the planned inventory named one**

- **Found during:** Task 2, while confirming how the detail view is reached before
  classifying it.
- **Issue:** The plan and the UI-SPEC both describe `SessionDetailScreen` as reached by
  "tapping a row inside History". It is also pushed from `PracticeScreen._openThisSession`,
  the "view this session" button in the completion state (D-27). A navigation contract whose
  entire purpose is that a reader can count surfaces against a rule cannot be missing an
  entry point — that is the one class of error this document exists to prevent, committed by
  the document itself.
- **Fix:** The inventory row names both entry points, and a note under the table explains
  why the second one does not promote the surface: it is reached from content (a button in
  a completion state), not from app-bar chrome, and it is unreachable without first
  finishing a session. It fails clauses 1 and 3 by both routes, so the **Detail view**
  classification and the result line are unchanged.
- **Files modified:** `docs/NAVIGATION.md`
- **Verification:** `grep -c 'Core screen'` still returns exactly 3; the result line still
  reads 3 core screens, 1 detail view, 2 modals.
- **Committed in:** `d995ddc`

### Planned-but-unneeded work

**Task 1's FALLOUT clause found no fallout.** The plan anticipated that retiring
`_startMessageIsFailure` would invalidate existing assertions in
`test/screens/setup_screen_test.dart` and made Task 1 own the repair. It did not: every
existing footer test reaches the treatment through the rendered key
(`setup-start-error` vs `setup-start-no-questions`), never through the widget field, so the
full 235-test suite was green on the first run after the refactor. That is a fact about the
existing tests being written at the right level, and it is recorded here rather than
silently skipped.

---

**Total deviations:** 1 auto-fixed (1 missing critical), plus one anticipated repair that
turned out to be unnecessary.
**Impact on plan:** No scope creep. Every artifact, symbol, key and acceptance criterion in
the plan was delivered as written; the one deviation makes a delivered artifact more
accurate, not larger.

## Issues Encountered

- **A doc comment can fail a grep criterion.** `grep -c "_startMessageIsFailure"` was
  required to return 0, and the first version of the `StartMessageKind` doc comment named
  the retired bool in prose to explain what it replaced. The criterion is right and the
  comment was reworded — but it is worth recording that "the identifier is gone" and "the
  string is gone" are different claims, and the acceptance criteria in this plan were
  written for the second one.

## Known Stubs

None. Every behaviour this plan describes is implemented and driven by a host test. The one
thing that is deliberately unproven on the host is the guard's real throw site inside
`FirestoreQuestionSource.questionsFor` — see `coverage` entry D10 — which is a D-47
seam boundary, not a stub.

## Threat Flags

None. This plan adds no network call, no write path, no new input surface and no rendering
of user- or file-supplied content: `kTooManyTopicsMessage` is a fixed literal, and
`docs/NAVIGATION.md` is documentation. The one thing it removes from the screen is
information — the connection-blaming copy that used to appear for a non-network cause.

## User Setup Required

None. No new dependency, no Firestore rule or index change, no credential, no environment
variable.

## Next Phase Readiness

- **UI-03 is discharged in the repo and ready to be ticked.** `docs/NAVIGATION.md` exists,
  classifies all five files under `lib/screens/` plus both modal surfaces, and the two
  mechanical checks it rests on both hold: five screen files, and four `MaterialPageRoute`
  sites — all pre-existing, none added by the import surface.
- **Plan 04-04** should know `docs/NAVIGATION.md` now exists and is deliberately standalone:
  it is not linked from `docs/QUESTION_GENERATION_PROMPT.md`, because the two documents are
  unrelated.
- **Plan 04-05** inherits one on-device question that nothing here can answer: whether the
  >30-topics guard fires as expected against the live bank. The ten-subject seed does not
  reach it, so this becomes live only if a later import pushes the bank past 30 distinct
  subjects — at which point the batching reversal trigger in `kMaxTopicsPerQuery`'s comment
  is the thing to re-read.
- **`REQUIREMENTS.md`'s UI-03 row is still `Pending`** and was left that way on purpose;
  see Decisions Made.

## Self-Check: PASSED

`docs/NAVIGATION.md` exists on disk; all four modified files exist; all three claimed
commits (`0968fb5`, `d995ddc`, `9ba77f0`) resolve in `git log`.
`flutter analyze --no-fatal-infos` exits 0 and the full `flutter test` suite is green at
247 tests (235 before this plan's own 12).

---
*Phase: 04-bulk-import-seed-content-screen-polish*
*Completed: 2026-08-10*
