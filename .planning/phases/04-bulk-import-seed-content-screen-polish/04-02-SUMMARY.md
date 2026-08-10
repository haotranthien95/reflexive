---
phase: 04-bulk-import-seed-content-screen-polish
plan: 02
subsystem: import
tags: [bottom-sheet, error-states, untrusted-input, PopScope, flutter, widget-tests]

requires:
  - phase: 04-bulk-import-seed-content-screen-polish
    plan: 01
    provides: "ImportSheet S1–S4 and its string block, ImportSkip/ImportSkipReason/ImportParse/ImportPlan, ImportFileUnreadableException, ImportFileShapeException, ImportFileEmptyException, ImportPartialWriteException, kMaxWritesPerBatch, FakeJsonFilePicker and FakeQuestionBankWriter"
  - phase: 03-real-question-bank-via-firestore
    provides: "QuestionBankUnavailableException, kTopicsErrorMessage's copy rules, _TopicsError's failure geometry"
  - phase: 01-record-save-replay-a-single-answer-crash-safe
    provides: "the locked palette, type scale and spacing scale every new surface reads through Theme.of(context)"
provides:
  - "The complete eight-state ImportSheet: S5 file problem (two sub-keys), S6 file empty, S7 bank unreachable, S8 partial write"
  - "The full string inventory: kImportSkipListLabel, kImportUnreadableFileMessage, kImportBadShapeMessage, kImportEmptyFileMessage, kImportEmptyFileBody, kImportUnreachableMessage"
  - "importDuplicatesLine, importSkippedLine, importPartialMessage, importSkipReason — all pure, all host-testable"
  - "sanitizedEcho + kMaxEchoedLevelChars + kMaxEchoedQuestionChars: the untrusted-input boundary for everything the picked file renders back"
  - "The per-row skip list, keyed by 1-based file position"
  - "_ShapeExampleCard and _PrimaryButton: one shape string and one primary-button geometry, several render sites"
  - "The verified dismissal-route matrix for Flutter 3.44.6, and the scroll-physics drag guard that covers what PopScope cannot"
  - "expectOnlyState and kSheetStateKeys — the eight-state exclusivity assertion every state test runs through"
  - "FakeQuestionBankWriter with chunked commits, per-chunk progress and a derived failure, making the 501-row path host-reachable"
  - "test/fixtures/import_files.dart: kFixtureMixedOutcome, kFixturePathologicalLevel, kFixtureNewlinesInQuestion, kFixtureRowsBeyondBatchCap"
affects: [04-04 docs and tool deletion, 04-05 seed import, manifest audit and the drag-handle follow-up]

actuals:
  tokens: 26000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A total map over a closed enum for user-facing copy, so adding a case is a compile error rather than a blank row"
    - "One named render-preparation function as the single untrusted-input boundary, with the bound named at the call site"
    - "A scripted fake that derives its failure from the production implementation's own rule rather than scripting the exception"
    - "A test-side list of state keys written out independently of the enum, so the two can disagree and be caught"

key-files:
  created: []
  modified:
    - lib/screens/import_sheet.dart
    - test/screens/import_sheet_test.dart
    - test/fixtures/import_files.dart

key-decisions:
  - "Verified all three dismissal routes against the pinned Flutter 3.44.6 source: system back and barrier tap both go through Navigator.maybePop and ARE blocked by PopScope; drag-to-dismiss calls Navigator.pop directly and is NOT. The sanctioned fallback (enableDrag: false) lives in setup_screen.dart, which this plan may not touch, so the sheet ships a scroll-physics gesture-arena guard instead and the residual 48px drag-handle gap is recorded as a follow-up"
  - "kMaxEchoedQuestionChars was added alongside kMaxEchoedLevelChars rather than passing a magic number, because sanitizedEcho takes its bound as an argument and the question sub-line needs one too"
  - "The error icon is inlined at three render sites rather than extracted into a shared failure header, matching the project's existing _TopicsError/_HistoryError duplication and keeping the icon count checkable by grep"
  - "importSkipReason's badLevel branch renders empty quotes when the level was absent or not text, rather than earning a fifth string for an edge that is already accurate"
  - "REQUIREMENTS.md was NOT touched: IMPORT-01/02/04's on-device proof is still plan 04-05's, and it is a shared artifact another wave agent may also write"

patterns-established:
  - "expectOnlyState: a totality assertion applied on every frame every state test looks at, rather than in one dedicated mutual-exclusion test"
  - "A fake that models the production chunking rule, so a path that only exists above a threshold is reachable without a device"
  - "Two sibling failure strings with an explicit doc-comment answer to 'why is this not the same string as its neighbour'"

requirements-completed: []

coverage:
  - id: D1
    description: "Every row of the file is accounted for — added plus already-in-your-bank plus skipped equals the number of entries in the data list (IMPORT-04)"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a mixed import reports all three lines and names each skipped row"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every skipped row is named by its 1-based FILE position together with its reason, and a row with nothing to echo omits its sub-line"
    requirement: IMPORT-02
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a mixed import reports all three lines and names each skipped row"
        status: pass
    human_judgment: false
  - id: D3
    description: "A duplicate is counted in its own neutral category, never listed per row, and never carries an error icon or error wording"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a mixed import reports all three lines and names each skipped row"
        status: pass
    human_judgment: false
  - id: D4
    description: "A file that could not be opened and a file that opened but is not shaped like a question file get two different messages, and only the second shows the expected shape"
    requirement: IMPORT-02
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a file that could not be OPENED shows no format example"
        status: pass
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a file that is not a question file DOES show the example"
        status: pass
    human_judgment: false
  - id: D5
    description: "A file that parses but whose data list is empty gets the empty-state treatment — heading plus body, no icon, no red"
    requirement: IMPORT-02
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#an empty data list is an empty STATE, not a failure"
        status: pass
    human_judgment: false
  - id: D6
    description: "A failure before the first commit says in so many words that nothing was imported, and a write that fails before its first chunk lands there rather than on the partial state"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a failed bank read says that nothing was imported"
        status: pass
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a write that fails before its FIRST chunk is not a partial"
        status: pass
    human_judgment: false
  - id: D7
    description: "A commit that fails after an earlier chunk committed renders the partial-write state with the exact number of rows that landed, never a success-shaped summary"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a chunk failing after an earlier one reports exact counts"
        status: pass
    human_judgment: false
  - id: D8
    description: "Retrying after a bank-unreachable failure resumes from the bank read; the user is never asked to find their file a second time"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#retry resumes from the bank read and never re-opens the picker"
        status: pass
    human_judgment: false
  - id: D9
    description: "No text taken from the imported file reaches a widget without being newline-stripped and length-capped: question text is one ellipsised line, an echoed level is truncated to 12 characters"
    requirement: IMPORT-02
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a pathological level value is capped before it is quoted back"
        status: pass
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#newlines in question text cannot break a skip row"
        status: pass
    human_judgment: false
  - id: D10
    description: "The eight states are mutually exclusive by a single state key — no frame can show two of them"
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#expectOnlyState, called by every state test in the file"
        status: pass
    human_judgment: false
  - id: D11
    description: "While the write is in flight the sheet cannot be dismissed by the Done button, a barrier tap or the system back gesture"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a barrier tap is refused mid-write and honoured afterwards"
        status: pass
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#the route refuses to pop mid-write and agrees afterwards"
        status: pass
    human_judgment: false
  - id: D12
    description: "While the write is in flight the sheet cannot be dismissed by a DRAG"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#the sheet body claims vertical drags only while writing"
        status: partial
    human_judgment: true
    rationale: "The test proves the guard is armed on the sheet body, and the Flutter 3.44.6 source proves why it is needed (BottomSheet's onClosing calls Navigator.pop directly, never consulting PopScope). It does NOT prove the arena outcome for a real drag, and it cannot cover the 48px drag handle, which BottomSheet renders outside the sheet builder's subtree. Closing that needs enableDrag: false at the showModalBottomSheet call in setup_screen.dart. On-device UAT in plan 04-05."
  - id: D13
    description: "A file larger than one writeBatch commits in chunks and the progress bar advances only on completed commits"
    requirement: IMPORT-01
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a file larger than one batch commits in chunks"
        status: pass
    human_judgment: true
    rationale: "The fake models the real writer's chunking rule exactly, so the SHEET's behaviour above the cap is proven. That the real Firestore writeBatch honours the same cap against the live backend is still the ~600-row seed import in plan 04-05."
  - id: D14
    description: "A failure never costs the user their setup — topics, level and sliders survive every terminal failure"
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a failure never costs the user their setup (four parameterised cases)"
        status: pass
    human_judgment: false
  - id: D15
    description: "No reason string in the row-level report calls a row invalid, an error or a failure; each describes the row rather than its author"
    requirement: IMPORT-04
    verification:
      - kind: unit
        ref: "test/screens/import_sheet_test.dart#a mixed import reports all three lines and names each skipped row"
        status: pass
    human_judgment: true
    rationale: "The test pins the four strings verbatim, which prevents drift. Whether the copy READS as non-blaming is a judgement the test cannot make; the four strings are the ones the approved UI-SPEC specifies, and the doc comment on importSkipReason records the rule so a future edit has to break it deliberately."

duration: 45min
completed: 2026-08-10
status: complete
---

# Phase 4 Plan 02: Four facts, four surfaces Summary

**The import sheet grew from one happy path to eight mutually exclusive states: a result that accounts for every row of the file in three zero-suppressed lines plus a positioned, reasoned, length-capped skip list, and four terminal failures that each name their own cause, their own consequence and their own next action — with the mid-write dismissal blocked on every route the pinned Flutter version lets a widget block.**

## Performance

- **Duration:** ~45 min
- **Completed:** 2026-08-10
- **Tasks:** 3
- **Files modified:** 3 (0 created, 3 modified)
- **Suite:** 235 → 256 tests, all green

## Accomplishments

- **IMPORT-04's "never silently or partially" is now true on screen, not just in the types.** Every one of a file's rows lands in exactly one of three visible categories, the three add up, and the three are told apart by shape rather than by wording alone: a peach summary card for counts, an ivory list for the rows that need an edit, and a red-iconed brown-worded surface for the things that actually went wrong.
- **Five different facts got five different surfaces.** "I could not open that file", "that file is not a question file", "that file has no questions", "I could not reach your bank and wrote nothing" and "I wrote 500 of your 501" are now five separately keyed states with five messages. Plan 01 threw all five signals and rendered none of them.
- **The one genuinely partial outcome is a first-class state.** A chunk failing after an earlier one committed renders exact counts and a recovery that is safe *because* the dedupe pass skips whatever already arrived — not a degraded success card.
- **The untrusted-input boundary is one function with a named bound at each call site.** `sanitizedEcho` collapses newlines, carriage returns and tabs, collapses whitespace runs, trims and truncates; a 240-character `level` renders as 12 characters and an ellipsis, and a question with embedded newlines renders as one line.
- **The dismissal question the UI-SPEC flagged as version-dependent is answered with evidence.** Read out of Flutter 3.44.6's own source rather than guessed: two of the three routes are blocked by `PopScope`, the third is not, and the gap is now both narrowed and named.
- **The 501-row path is reachable on the host.** `FakeQuestionBankWriter` chunks by `kMaxWritesPerBatch` and reports per completed chunk, so the multi-chunk progress path and the partial-write outcome are both driven by tests instead of waiting for a device.

## Task Commits

1. **Task 1: Every row the file contained is accounted for on screen** — `66c359a` (feat)
2. **Task 2: Four terminal failures, four surfaces, and a write that cannot be walked out of** — `9c46a2c` (feat)
3. **Task 3: Widget coverage for all eight states** — `aad5eb3` (test)

## Files Created/Modified

- `lib/screens/import_sheet.dart` — the eight-state enum and dispatch chain; `kImportSkipListLabel`, `kImportUnreadableFileMessage`, `kImportBadShapeMessage`, `kImportEmptyFileMessage`, `kImportEmptyFileBody`, `kImportUnreachableMessage`; `importDuplicatesLine`, `importSkippedLine`, `importPartialMessage`, `importSkipReason`, `sanitizedEcho`, `kMaxEchoedLevelChars`, `kMaxEchoedQuestionChars`; the full result card and skip list; `_ImportFileProblem`, `_ImportEmptyFile`, `_ImportUnreachable`, `_ImportPartial`; `_ShapeExampleCard` and `_PrimaryButton`; `_dragGuardPhysics`. The flow split into `_chooseFileAndImport` and `_importParsedFile` so the retry has somewhere to resume.
- `test/screens/import_sheet_test.dart` — `kSheetStateKeys` and `expectOnlyState`; the `runImport` helper; eighteen new `testWidgets` across seven groups; `FakeQuestionBankWriter` rebuilt to chunk, to record per-chunk progress and to derive its failure from the production rule.
- `test/fixtures/import_files.dart` — `kFixtureMixedOutcome` + `kFixtureMixedOutcomeBankKey`, `kFixturePathologicalLevel`, `kFixtureNewlinesInQuestion` + `kFixtureNewlinesCollapsed`, `kFixtureRowsBeyondBatchCap(int)`.

## Decisions Made

- **The dismissal matrix, verified rather than assumed.** Against `/Applications/flutter/packages/flutter/lib/src/material/bottom_sheet.dart` and `.../widgets/modal_barrier.dart` at Flutter 3.44.6: a barrier tap runs `ModalBarrier`'s dismiss handler → `Navigator.maybePop` → `ModalRoute.popDisposition` → the registered `PopScope`, and the system back gesture takes the same path. **Both are blocked.** Drag-to-dismiss does not: `_ModalBottomSheetState` builds its `BottomSheet` with `onClosing: () { if (route.isCurrent) Navigator.pop(context); }`, an unconditional pop. **What shipped is the gesture-arena guard, not the UI-SPEC's sanctioned `enableDrag: false` fallback** — see the deviation below for why, and what is left open.
- **`kMaxEchoedQuestionChars` was added to the symbol set.** `sanitizedEcho` takes its bound as an argument, and the question sub-line needs one; passing `200` inline would have been the one un-named number in a file where every bound is a documented constant. It is a defensive bound rather than a display rule — the display rule is `maxLines: 1`.
- **Three inlined error icons, not one shared failure header.** An extracted `_FailureHeader` was written first and then unwound: the project's existing precedent is `_TopicsError` carrying `_HistoryError`'s geometry as a documented copy rather than a shared widget, and the plan's own acceptance gate counts three `Icon(` call sites precisely so "the empty-file state has no icon" is checkable by counting. One shared site would have made the count 1 and the property unstateable in the same terms.
- **`importSkipReason`'s bad-level branch renders empty quotes for a missing level.** A row with `level` absent or non-textual has nothing quotable; `level "" isn't one of A1–C2` is accurate about a field that was empty, and inventing a fifth string for it would break the four-branch total map the doc comment promises.
- **`ImportSheet` now imports `firestore_question_source.dart`.** For `QuestionBankUnavailableException` only — the same import `setup_screen.dart` already makes, for the same reason. The phase verification (`no package:cloud_firestore or package:file_picker under lib/screens/`) still passes: no vendor type crosses the seam.
- **REQUIREMENTS.md was not touched.** IMPORT-01/02/04 still owe their on-device proof to plan 04-05, and it is a shared artifact another wave agent may be writing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] The sanctioned mid-write drag fallback needs a file this plan may not touch**

- **Found during:** Task 2, the plan's own `<verify all three routes>` backstop
- **Issue:** Drag-to-dismiss bypasses `PopScope` on the pinned Flutter version (see Decisions). The plan's sanctioned fallback is to present the sheet as non-dismissible and non-draggable for the write phase — but `enableDrag` and `isDismissible` are arguments to `showModalBottomSheet`, whose call site is in `lib/screens/setup_screen.dart`. That file is owned by the concurrently-running plan 04-03 and is explicitly out of bounds for this agent. `ModalBottomSheetRoute.enableDrag` is also `final`, so even from inside the sheet it could not be toggled mid-write without re-showing the sheet.
- **Fix:** The sheet body wears `AlwaysScrollableScrollPhysics` while the write is in flight. A `Scrollable` whose physics accept a user offset registers a vertical-drag recognizer, and the innermost recognizer wins the arena — so a drag on the body scrolls or clamps instead of dismissing, where the default physics decline the drag when the content fits and hand it straight to the sheet's dismiss recognizer. Documented in full on `_dragGuardPhysics`, including what it cannot reach.
- **Files modified:** `lib/screens/import_sheet.dart`
- **Verification:** `test/screens/import_sheet_test.dart#the sheet body claims vertical drags only while writing` asserts the physics are armed while writing and released afterwards.
- **Committed in:** `9c46a2c`
- **Residual, and deliberately not papered over:** the 48px drag handle is rendered by `BottomSheet` in a `Stack` **outside** the sheet builder's subtree, so a drag starting on the handle still dismisses mid-write. See "Follow-ups this plan could not close".

**2. [Rule 2 - Missing Critical] `kMaxEchoedQuestionChars` added beyond the plan's symbol table**

- **Found during:** Task 1
- **Issue:** The plan names `kMaxEchoedLevelChars` and specifies `sanitizedEcho(String raw, int maxChars)`, but the skip row's question sub-line also has to pass through `sanitizedEcho` (it is the surface the newline-strip rule exists for) and there was no named bound for it.
- **Fix:** A second documented constant beside the first, framed as a defensive bound rather than a display rule.
- **Files modified:** `lib/screens/import_sheet.dart`
- **Verification:** `flutter analyze` clean; the newline and cap tests pass.
- **Committed in:** `66c359a`

**3. [Rule 1 - Bug] The first mid-write back-gesture assertion was vacuous**

- **Found during:** Task 3
- **Issue:** The test asserted `await navigator.maybePop()` returns `false` while writing. It returns **`true`**: `Navigator.maybePop` returns true for `RoutePopDisposition.doNotPop` as well as for an actual pop, because its boolean means "handled", not "popped". The assertion failed, and had it been written the other way round it would have passed for both outcomes and proved nothing.
- **Fix:** Assert the sheet is still on its writing state after `maybePop`, and gone after it once the write completes. The reason the boolean is not the assertion is recorded in the test.
- **Files modified:** `test/screens/import_sheet_test.dart`
- **Verification:** the test now fails if the guard is removed.
- **Committed in:** `aad5eb3`

---

**Total deviations:** 3 auto-fixed (2 missing critical, 1 bug)
**Impact on plan:** No scope creep. One acceptance-criterion-shaped constraint (three inlined error icons rather than a shared header) was honoured over a DRY instinct, and is recorded above as a decision. Every artifact, symbol, key and acceptance criterion in the plan was delivered.

## Issues Encountered

- **`grep`-shaped acceptance criteria and refactoring pull in opposite directions, and the criterion should win when it encodes a property.** The "exactly 3 `Icon(` call sites" gate is not really about counting icons — it is about there being no fourth icon anywhere in the file for the empty-file branch to reach for. A shared header widget makes that property *stronger* and the stated check meaningless. Unwinding the extraction kept the check honest and matched the codebase's existing failure-widget style, but it is worth noting that the two goals genuinely conflicted here rather than pretending one was obviously right.
- **Reading the framework beat reasoning about it.** The UI-SPEC flagged `PopScope`'s coverage of drag and barrier as "version-dependent, verify on device". Two greps through the installed Flutter source answered it exactly, in opposite directions for the two gestures — which is not the answer either "it all works" or "none of it works" would have predicted, and it is the difference between shipping a guard and shipping a comment.

## Known Stubs

None. All eight states are built, all four terminal failures render, and the skip list echoes real file content through the real caps.

One bounded gap, which is a cross-file ownership constraint rather than a stub: mid-write **drag** dismissal is narrowed to the 48px drag-handle strip rather than eliminated. See below.

## Follow-ups this plan could not close

- **`enableDrag: false` for the write phase.** The complete fix for mid-write drag dismissal is at the `showModalBottomSheet` call in `lib/screens/setup_screen.dart`, which this plan does not own. Because `ModalBottomSheetRoute.enableDrag` is `final`, the honest options are (a) pass `enableDrag: false` unconditionally and accept that the sheet is never drag-dismissible in any state, or (b) leave the current guard and accept the handle-strip gap. (a) is a real UX cost in the seven dismissible states; (b) is a real correctness gap in the one state that matters. **This needs a decision, not just an edit** — recommend raising it in plan 04-04 with the on-device drag behaviour from 04-05's UAT in hand.
- **Backgrounding the app mid-write** remains the UI-SPEC's one unresolved interaction race, unchanged and untestable on the host. Plan 04-05 UAT.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: untrusted-input-render | `lib/screens/import_sheet.dart` | Plan 01's flag is now **discharged in code**: `sanitizedEcho` is the single boundary, both echoed values (`offendingLevel`, `questionText`) pass through it with named bounds, and both caps are pinned by tests. Recorded here rather than dropped because the property is a render-site invariant — a future state that echoes a third file-authored value must route it through the same function, and nothing but review enforces that. |
| threat_flag: gesture-bypass | `lib/screens/import_sheet.dart` | Mid-write drag dismissal via the 48px drag handle is not blocked (see Follow-ups). Its worst case is not data loss — the commit continues and re-importing is safe by construction — but the user loses the outcome report, which is the fact IMPORT-04 requires be shown. |

## User Setup Required

None. No new dependency, no rules change, no index change, no credential.

## Next Phase Readiness

**Ready for plan 04-04 (docs and tool deletion).** The string inventory is complete and final, so any documentation of the import flow can quote the shipped copy rather than the spec's. The one open decision it should pick up is the `enableDrag` tradeoff above.

**Ready for plan 04-05 (seed import and manifest audit).** Three things it must settle that nothing here can: whether `file_picker` widens the merged release manifest; whether the plugin returns bytes or a path on Android and iOS; and the on-device drag/barrier/back behaviour of the sheet mid-write, including the handle strip. The multi-chunk write path is now exercised on the host by the fake, so the ~600-row seed is confirming the *backend* half of a path whose *sheet* half is already pinned.

**One thing any later plan touching the sheet should know:** the eight states are enforced by `expectOnlyState` over `kSheetStateKeys` in the test file, which is a deliberate second copy of the key list. Adding a ninth state means adding it there too, and the tests will say so.

## Self-Check: PASSED

All 3 claimed modified files exist on disk and all 3 claimed commits resolve in `git log`
(`66c359a`, `9c46a2c`, `aad5eb3`). `flutter analyze --no-fatal-infos` exits 0 and the full
`flutter test` suite is green at **256 tests** (235 before this plan's 21 new ones).
Plan verification re-run: `grep -c "0xFF" lib/screens/import_sheet.dart` returns 0, and
`grep -rE 'package:cloud_firestore|package:file_picker' lib/screens/` matches nothing.

---
*Phase: 04-bulk-import-seed-content-screen-polish*
*Completed: 2026-08-10*
