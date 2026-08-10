---
phase: 04-bulk-import-seed-content-screen-polish
plan: 04
subsystem: content-and-docs
tags: [seed-content, cefr, documentation, project-records, tool-deletion, inclusive-content]

requires:
  - phase: 04-bulk-import-seed-content-screen-polish
    plan: 01
    provides: "parseImportFile, dedupeAgainstBank, importDedupeKey, kMaxWritesPerBatch — the rules the seed must satisfy and the code this plan validates it against"
  - phase: 04-bulk-import-seed-content-screen-polish
    plan: 02
    provides: "the eight sheet states and the final string inventory, so the docs quote the shipped copy rather than the spec's"
  - phase: 04-bulk-import-seed-content-screen-polish
    plan: 03
    provides: "docs/NAVIGATION.md, which discharges UI-03 and makes its tick in REQUIREMENTS.md truthful"
  - phase: 03-real-question-bank-via-firestore
    provides: "kLevels, sanitizedText, the D-46 open-rules statement and the tool/ seed script whose exit condition fires here"
provides:
  - "seed/seed-questions.json — the 600-row starter bank (10 topics x 6 CEFR levels x 10 questions)"
  - "seed/README.md — what the directory is, is not, and how the seed is regenerated and loaded"
  - "test/services/seed_import_file_test.dart — the seed validated by CALLING the shipped importer, not by restating its rules"
  - "docs/QUESTION_GENERATION_PROMPT.md corrected: normalization, per-row skipping by file position, duplicate-skipping"
  - "the deletion of tool/ — one write path into the question bank, not two"
  - "PROJECT.md Key Decisions rows for D-56, the D-53/D-54 write contract, and the open-rules statement closing STATE.md's second Phase 4 concern"
  - "REQUIREMENTS.md: IMPORT-01..04 and UI-03 ticked, IMPORT-05 deliberately open"
affects: [04-05 on-device seed import and manifest audit]

actuals:
  tokens: 27000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A shipped data artifact validated by invoking the production code that consumes it, rather than by a second implementation of its rules in another language"
    - "A requirement ticked only to the level its evidence supports, with the remaining evidence named in the traceability row itself"

key-files:
  created:
    - seed/seed-questions.json
    - seed/README.md
    - test/services/seed_import_file_test.dart
  modified:
    - docs/QUESTION_GENERATION_PROMPT.md
    - .planning/PROJECT.md
    - .planning/REQUIREMENTS.md
    - .gitignore
  deleted:
    - tool/seed_questions.mjs
    - tool/README.md
    - tool/package.json
    - tool/package-lock.json

key-decisions:
  - "The seed is validated by a Dart test that CALLS parseImportFile and dedupeAgainstBank, not only by the plan's node one-liners — a node re-statement of the importer's rules is a second model of those rules, free to drift from the one the app runs"
  - "IMPORT-05 is deliberately NOT ticked: the requirement is that the BANK is non-empty, and authoring a file in the repo does not put anything in Firestore. It closes in plan 04-05"
  - "IMPORT-02 is ticked unqualified while IMPORT-01/03/04 carry `Complete (device UAT pending)` — IMPORT-02 is entirely the pure parseImportFile contract, the other three reach past the D-47 seam"
  - "REQUIREMENTS.md's footnote REPLACES the deleted script's --verify evidence for BANK-01 rather than dropping the clause, so a reader is not left wondering where the old evidence went"
  - "The dead tool/node_modules/ .gitignore rule was removed with the directory, though .gitignore is outside the plan's declared files_modified"
  - "Two doc labels were corrected against the shipped widgets: the action is `Import questions`, the button is `Choose a JSON file` — the doc said `Import JSON` and `Choose JSON file`"

patterns-established:
  - "A data file that the app will consume gets a test that runs it through the consumer, so 'it is importable' is measured rather than asserted"
  - "A retired verification mechanism is named in the document that used to cite it, alongside what replaced it"

requirements-completed: [IMPORT-02]

coverage:
  - id: D1
    description: "seed/seed-questions.json parses as the exact import format and every row is a valid import row by the shipped importer's own rules"
    requirement: IMPORT-05
    verification:
      - kind: unit
        ref: "test/services/seed_import_file_test.dart#parses with no file-level problem and skips no row"
        status: pass
      - kind: unit
        ref: "test/services/seed_import_file_test.dart#normalization is a no-op — the file is already in canonical form"
        status: pass
    human_judgment: false
  - id: D2
    description: "All ten topics at all six CEFR levels with ten questions in every one of the sixty combinations, so no topic-by-level pair a user can pick comes back empty on a fresh bank"
    requirement: IMPORT-05
    verification:
      - kind: unit
        ref: "test/services/seed_import_file_test.dart#ten topics at all six levels, ten questions in every cell"
        status: pass
    human_judgment: false
  - id: D3
    description: "The ten seed subject strings match docs/QUESTION_GENERATION_PROMPT.md's list exactly, string for string"
    verification:
      - kind: command
        ref: "node -e '…subjects not found in the prompt…' → [] (empty)"
        status: pass
    human_judgment: false
  - id: D4
    description: "No two seed rows share the same content/subject/level triple, so importing the seed twice adds nothing the second time"
    verification:
      - kind: unit
        ref: "test/services/seed_import_file_test.dart#against an empty bank every row survives the dedupe pass"
        status: pass
      - kind: unit
        ref: "test/services/seed_import_file_test.dart#re-importing the seed adds nothing the second time"
        status: pass
    human_judgment: false
  - id: D5
    description: "The seed file is larger than one Firestore write batch, so importing it exercises the multi-chunk commit path against the real backend"
    verification:
      - kind: unit
        ref: "test/services/seed_import_file_test.dart#is larger than one write batch, so the chunked commit path runs"
        status: pass
    human_judgment: true
    rationale: "The test proves 600 > kMaxWritesPerBatch (500), which is what makes the multi-chunk path REACHABLE. That the real Firestore writeBatch honours the cap and that chunk 2 commits after chunk 1 against the live backend is plan 04-05's on-device import — FirestoreQuestionBankWriter is past the D-47 seam."
  - id: D6
    description: "No seed question requires the learner to disclose sensitive personal information, or presumes a particular family shape, income level, physical ability or nationality"
    requirement: IMPORT-05
    verification: []
    human_judgment: true
    rationale: "A prohibition with `verification: judgment` in the plan's own frontmatter. No test can decide whether a question is answerable by anyone. What is checkable is that the rule was applied deliberately: the personal-facing openings were rewritten during authoring (workplace quality rather than the learner's pay; how people in general stay active rather than the learner's medical history; friendship, neighbours and community rather than a presumed partner, children or living parents; `where you live` rather than a presumed nationality), and seed/README.md states the rule so a regenerated topic is reviewed against it. Family & Relationships and Health & Fitness are the two topics where it bit hardest and both were authored in general terms throughout."
  - id: D7
    description: "docs/QUESTION_GENERATION_PROMPT.md describes what the shipped importer actually does — values are trimmed and the level upper-cased before writing, and a question already in the bank is skipped rather than added again"
    requirement: IMPORT-02
    verification:
      - kind: command
        ref: "grep -c 'just appends to the bank' → 0; grep -i 'duplicate' and grep -i 'trim' both match"
        status: pass
    human_judgment: false
  - id: D8
    description: "tool/ no longer exists, discharging its own README's stated exit condition, and no living document still instructs a reader to run it"
    verification:
      - kind: command
        ref: "test ! -d tool; grep -rln 'tool/seed_questions' --include='*.md' . | grep -v '.planning/phases/' | wc -l → 0"
        status: pass
    human_judgment: false
  - id: D9
    description: "PROJECT.md records that seeding makes the bank non-empty but does not make a first run offline-capable"
    verification:
      - kind: command
        ref: "grep -q 'offline' .planning/PROJECT.md; the D-56 Key Decisions row states a brand-new install still needs one online Setup visit"
        status: pass
    human_judgment: false
  - id: D10
    description: "PROJECT.md records that the importer writes only into the collection the app already reads — no new collection, no rule change, D-46's exposure unchanged"
    verification:
      - kind: command
        ref: "grep -q 'D-46' .planning/PROJECT.md; git status --porcelain firestore.rules empty; git log 95c86a1..HEAD -- firestore.rules → 0 commits"
        status: pass
    human_judgment: false
  - id: D11
    description: "Deleting tool/ broke nothing"
    verification:
      - kind: command
        ref: "flutter analyze --no-fatal-infos exit 0; flutter test → 276 passed"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-08-10
status: complete
---

# Phase 4 Plan 04: The starter bank, and documents that stopped lying Summary

**Six hundred questions — ten topics at all six CEFR levels, ten in every one of the sixty
cells — authored in the repo in the app's own import format and proven importable by running
them through the shipped importer itself; the generation prompt rewritten to describe the
importer that exists rather than the one it was written against; `tool/` deleted so the bank
has one writer instead of two; and the project's own records brought into line with what has
and has not yet been proven on a device.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-08-10
- **Tasks:** 3
- **Files:** 3 created, 4 modified, 4 deleted
- **Suite:** 269 → 276 tests, all green; `flutter analyze --no-fatal-infos` clean

## Accomplishments

- **The bank the app ships against exists, and it is complete rather than representative.**
  Every one of the sixty topic-by-level combinations a user can tick holds exactly ten
  questions, so a fresh install has no empty cell to discover. Ten per cell also means a
  20-question single-topic session cycles twice, not four times — which is the difference
  between a drill and a memory test.
- **"The seed is importable" is measured, not asserted.** The plan's acceptance criteria
  check the file with `node` one-liners that re-state the importer's rules. Those pass — but
  a second statement of a rule is a second model of it, free to drift. So the seed is also
  run through `parseImportFile` and `dedupeAgainstBank` themselves: no skipped row,
  normalization is a **no-op** (what is in the repo is exactly what lands in Firestore), no
  duplicate triple, and a second import of the same file adds nothing.
- **The generation prompt stopped promising something the app does not do.** Its claim that
  the import "just appends to the bank" was the sentence D-54 falsified. It now describes
  whole-file validation before any write, trim-and-upper-case normalization with the
  normalized value stored, per-row skipping named by 1-based file position, and
  duplicate-skipping against both the bank and the file — plus what each of those means for
  the person writing the prompt (a lower-case level is corrected, not rejected; a stray space
  cannot fork a topic; casing still can, because a topic name is a lookup key).
- **The bank has one writer.** `tool/` is gone, discharging its own README's exit condition.
  Keeping it would have left a second path into `questions` that did not normalize, did not
  dedupe and did not reject a bad level — three rules the app now depends on.
- **Three facts that were true but unwritten are now written.** Seeding makes the bank
  non-empty and does *not* make a first run offline-capable. The write contract is
  normalize-then-validate with duplicates as a neutral category. And the importer — the first
  client-side writer through the open rules — widens nothing: same collection, no new
  collection, `firestore.rules` untouched across the whole phase.

## Task Commits

1. **Task 1: Author the first five topics of the starter bank** — `c75d393` (feat)
2. **Task 2: Author the remaining five topics and validate the whole file** — `4ab8ff1` (feat)
3. **Task 3: Make every document describe the importer that actually shipped** — `08dd143` (docs)

## Files Created/Modified

- `seed/seed-questions.json` *(new)* — 600 rows, grouped topic by topic and level by level so
  a human can find a cell. Exactly `content`/`subject`/`level` per row, no `id`, no
  `created_at`. Plain ASCII throughout, nothing over 200 characters, no embedded control
  characters, all 600 content strings distinct.
- `seed/README.md` *(new)* — what the directory is and is **not** (not a Flutter asset, not a
  first-run mechanism, not a second write path), why it survives the one-way D-58 wipe, the
  format and the D-63 ordering contract, the ten strings and why their casing matters, the
  five content rules including the answerable-by-anyone rule, how to regenerate a topic with
  two mechanical checks, and the side-load-and-import procedure.
- `test/services/seed_import_file_test.dart` *(new)* — seven tests that call the importer
  rather than describe it. Its own header records why it exists in preference to a shell
  one-liner.
- `docs/QUESTION_GENERATION_PROMPT.md` — the corrected merge-and-import sentence, a new "What
  the app actually does with your file" section, a "What this means for the prompt you write"
  subsection, the seed-topics note about six levels and `seed/README.md`, and a closing
  paragraph naming the real on-screen labels.
- `.planning/PROJECT.md` — three Active items moved to Validated with earned qualifiers;
  three Key Decisions rows added.
- `.planning/REQUIREMENTS.md` — IMPORT-01..04 and UI-03 ticked, IMPORT-05 left open, six
  traceability rows updated, and the closing footnote rewritten.
- `.gitignore` — the `tool/node_modules/` rule removed with the directory it guarded.
- `tool/seed_questions.mjs`, `tool/README.md`, `tool/package.json`, `tool/package-lock.json`
  — deleted with `git rm -r`.

## Decisions Made

- **IMPORT-05 stays unticked, and that is the point of the row.** The requirement says the
  *bank* is not empty. A 600-row file in the repo is not a row in Firestore. Ticking it here
  would make the phase's most consequential remaining act — plan 04-05's on-device import —
  look like housekeeping. Its traceability row says exactly what is done and what is left
  rather than borrowing the `Complete (device UAT pending)` vocabulary, because "the code is
  finished, a check remains" is not this requirement's situation.
- **IMPORT-02 is the one unqualified tick of the five.** It is entirely the pure
  `parseImportFile` contract — the accepted shape, the rejected shapes, the empty-list split
  — all of which is under direct unit test on the host. IMPORT-01, IMPORT-03 and IMPORT-04
  each reach past the D-47 seam (the real picker, the four-field document body with its
  strictly increasing `created_at`, the multi-chunk commit), so each carries the qualifier.
  Ticking all five the same way would have hidden which one has different evidence.
- **The footnote's retired evidence is named, not deleted.** BANK-01 was unqualified because
  `node tool/seed_questions.mjs --verify` asserted the schema against the live project. That
  script is deleted here. The clause is replaced with what now carries the claim (the app's
  own import path plus the 04-05 read-back) *and* names the retired mechanism, so a future
  reader auditing BANK-01 does not find a confident claim with no visible support.
- **`seed/README.md` describes only the dismissal routes that exist.** The orchestrator's
  post-wave-2 fix made the sheet non-draggable with no handle, so the README's procedure says
  "tap **Done**" and states the write phase cannot be dismissed at all. No swipe is
  described anywhere.
- **The `enableDrag` decision plan 04-02 escalated to this plan was already made.** 04-02's
  "Follow-ups this plan could not close" asked 04-04 to pick up the tradeoff between
  `enableDrag: false` in all eight states and living with the 48px handle gap in the one
  state that matters. Commit `95c86a1` (in this plan's base) chose the former —
  `enableDrag: false, showDragHandle: false` in `setup_screen.dart`. Nothing was left for
  this plan to decide; it is recorded here so the follow-up is visibly closed rather than
  silently dropped.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] The plan's seed checks re-implement the importer's rules instead of calling it**

- **Found during:** Task 2, reading the plan's acceptance criteria against this plan's stated success criterion ("the seed file validates against the importer's OWN rules as shipped, not as the plan described them").
- **Issue:** Every seed check in the plan is a `node` one-liner: it hard-codes the six CEFR strings, its own notion of a blank field, and its own dedupe key. It can therefore pass while the seed is *not* importable — most concretely, a lower-cased `"b1"` passes nothing in the node checks (they test `L.includes(r.level)` and would fail) but the reverse gap is real: a row the node check accepts could still be normalized into something different from what the repo shows, and nothing would notice. The criterion asks for validation by the shipped rules, and a second implementation of those rules is not them.
- **Fix:** `test/services/seed_import_file_test.dart` — seven tests that import `parseImportFile`, `dedupeAgainstBank`, `importDedupeKey`, `kLevels` and `kMaxWritesPerBatch` and run the real seed file through them. The load-bearing one is *"normalization is a no-op"*: it compares each parsed row against the raw JSON field by field, so any value the importer would silently tidy on the way in is a failing test rather than an invisible difference between the repo and the bank.
- **Files modified:** `test/services/seed_import_file_test.dart` (new)
- **Verification:** all 7 pass; suite 269 → 276.
- **Committed in:** `4ab8ff1`

**2. [Rule 1 - Bug] Two on-screen labels in the docs did not match the shipped widgets**

- **Found during:** Task 3, checking the prompt doc's import instructions against `setup_screen.dart` and `import_sheet.dart`.
- **Issue:** `docs/QUESTION_GENERATION_PROMPT.md` told the reader to use the app's "**Import JSON**" feature, twice. The shipped AppBar action's tooltip — which, being icon-only, *is* its accessible name — is `Import questions`. The sheet's button is `Choose a JSON file`, and the first draft of `seed/README.md` wrote it as "Choose JSON file". A user following either document looks for a control that is not there.
- **Fix:** Both documents now quote the shipped strings verbatim.
- **Files modified:** `docs/QUESTION_GENERATION_PROMPT.md`, `seed/README.md`
- **Verification:** the strings are `grep`-matched against `lib/screens/setup_screen.dart:650` and `lib/screens/import_sheet.dart:737`.
- **Committed in:** `08dd143`

**3. [Rule 3 - Blocking] `.gitignore` still guarded a directory that no longer exists**

- **Found during:** Task 3, immediately after `git rm -r tool`.
- **Issue:** `.gitignore` carried `tool/node_modules/` under a three-line comment explaining the one-off seed script's npm tree. `.gitignore` is not in the plan's declared `files_modified`, but the task's whole point is that no living document should describe a `tool/` directory — and a gitignore rule with an explanatory comment is a document.
- **Fix:** The rule and its comment removed in the same commit as the deletion.
- **Files modified:** `.gitignore`
- **Verification:** `git status` clean; nothing untracked appeared.
- **Committed in:** `08dd143`

### Findings about the plan's own acceptance criteria

**The `tool/seed_questions` grep in Task 3 cannot return 0 as written.** The criterion is
`grep -rn 'tool/seed_questions' --include='*.md' . | grep -v '^\./\.planning/phases/' | wc -l`.
On this system `grep -r … .` emits paths **without** a `./` prefix, so the anchored exclusion
never matches and the count came back 49 — all 49 in phase artifacts the criterion means to
exclude. The substantive check, `grep -v '\.planning/phases/'`, returns **0**. Recorded here
rather than silently substituted, because the difference is in the criterion, not the repo.

**Task 3's "replace any instruction that points the reader at a script under `tool/`, if one
exists" found nothing to replace.** The prompt doc never referenced the script; the only
living reference was `REQUIREMENTS.md`'s footnote, which the same task rewrites for its own
stated reason. The conditional was correctly hedged and simply did not fire.

---

**Total deviations:** 3 auto-fixed (1 missing critical, 1 bug, 1 blocking), plus two findings
about the plan's criteria rather than the repo.
**Impact on plan:** No scope creep. Every artifact, count, string and acceptance criterion the
plan specified was delivered; the one addition (the Dart test) exists because the plan's own
success criterion asks for evidence the plan's checks do not provide.

## Issues Encountered

- **A `node` check and a Dart test disagree about what "valid" means, and only one of them is
  the app.** This is the plan's own point about the deleted `tool/` script — two writers with
  two rule sets — reappearing one level up as two *validators*. Writing the Dart test took
  ten minutes and immediately justified itself: the "normalization is a no-op" assertion is
  not expressible in the node checks at all, because they have no access to the trimming rule
  the app applies.
- **Authoring 600 questions that are answerable by anyone is a content problem, not a
  formatting one.** The first drafts of several rows presumed things: "What is your job?"
  (employment), "How has the way people take holidays changed since your parents were young?"
  (living parents), "Describe a piece of technology that older family members find difficult"
  (family), "What exercise do you do?" (physical ability). Each was rewritten to ask about
  people in general or about a preference rather than a circumstance. None of this is
  detectable by any check in the plan, which is why `seed/README.md` states the rule for the
  next person to regenerate a topic.

## Known Stubs

None. The seed is complete at 600 rows, every document this plan touched describes the
shipped behaviour, and `tool/` is gone.

One bounded, deliberate absence: **the seed is in the repo, not in Firestore.** That is
IMPORT-05's remaining half and it is plan 04-05's on-device act, recorded as such in
PROJECT.md's Validated entry and in REQUIREMENTS.md's traceability row rather than glossed.

## Threat Flags

None new. This plan adds no code path: one JSON data file, one test, and documentation. The
two flags plan 01 raised are unchanged and are re-stated here only because this plan is the
one that writes them into the permanent record — `unauthenticated-write` on
`question_bank_writer.dart` is now a PROJECT.md Key Decisions row naming D-46, its three
facts and its exit condition, and `firestore.rules` was confirmed untouched across the whole
phase (`git log 95c86a1..HEAD -- firestore.rules` → 0 commits) rather than merely asserted.

## User Setup Required

None for this plan. No new dependency, no rules change, no index change, no credential.

**For plan 04-05**, which loads this file: `seed/seed-questions.json` must be copied onto the
device somewhere the OS file picker can reach it, and the Phase 3 dev seed must be wiped
first (D-58, one-way — this file is the only way back).

## Next Phase Readiness

**Ready for plan 04-05 (on-device seed import and manifest audit).** The file it imports
exists, is proven importable by the code that will import it, and is 600 rows — 100 above
`kMaxWritesPerBatch`, so the two-chunk commit path runs on the first real import rather than
waiting for a bank that grows into it. `seed/README.md` carries the side-load-and-import
procedure; plan 04-05 owns the wipe, the read-back and the merged-release-manifest check that
`file_picker` may have widened.

**IMPORT-05 is the only v1 requirement this phase leaves open**, and it is open by one act,
not by one piece of work.

**One thing plan 04-05 should know:** `test/services/seed_import_file_test.dart` will fail if
the seed is edited into something the importer would alter or skip. If 04-05 needs to trim
the file for any reason — a partial re-import, a smaller test batch — it should copy it
rather than edit it, or the test's row-count and cell-coverage assertions will need updating
with a reason.

## Self-Check: PASSED

All 3 created files exist on disk (`seed/seed-questions.json`, `seed/README.md`,
`test/services/seed_import_file_test.dart`); all 4 modified files exist; all 4 `tool/` files
are absent and their deletion is in the commit. All 3 claimed commits resolve in `git log`
(`c75d393`, `4ab8ff1`, `08dd143`). `flutter analyze --no-fatal-infos` exits 0 and the full
`flutter test` suite is green at **276 tests** (269 before this plan's 7). The whole-file seed
check, the batch-cap check, the independent `python3` parse and the subject-string
cross-check against the generation prompt all exit 0.

---
*Phase: 04-bulk-import-seed-content-screen-polish*
*Completed: 2026-08-10*
