# Phase 4: Bulk Import, Seed Content & Screen Polish - Context

**Gathered:** 2026-08-09
**Status:** Ready for planning
**Mode:** Default interactive discuss — four gray areas presented, all four selected and discussed

<domain>
## Phase Boundary

Phases 1–3 built the drill and connected it to a real Firestore question bank that only a
maintainer can fill. Phase 4 closes the last three gaps in v1: **the bank becomes
user-growable from inside the app** (pick a JSON file → validate → write to Firestore,
reporting per-row outcomes: IMPORT-01..04), **it ships non-empty** with ~10 general-purpose
topics seeded (IMPORT-05), and **the app's navigation footprint is confirmed and written
down as exactly 3 core screens** (UI-03). After this phase every v1 requirement is
delivered.

**In scope:** IMPORT-01, IMPORT-02, IMPORT-03, IMPORT-04, IMPORT-05, UI-03. Plus the
documentation consequences those create — updating
`docs/QUESTION_GENERATION_PROMPT.md` (which currently makes a claim D-54 falsifies),
deleting `tool/` per its own README, and closing the two Phase 4 concerns STATE.md carries.

**Explicitly NOT in scope:**
- **Editing or deleting questions from inside the app** — the bank is append-only from the
  client; removing a question is a Firebase-console act. No requirement asks for it.
- **A question-bank browser / count display on Setup** — deferred from Phase 3 (D-41
  alternatives) and still deferred.
- **Batched multi-query merge for >30 selected topics** — D-61 gives the cap an honest
  message instead; the batching itself stays deferred exactly as
  `firestore_question_source.dart` documents.
- **Firebase Auth, tightening the open `questions` rules** — D-46's exposure is accepted and
  unchanged. The importer is the first client-side writer through those rules and must not
  widen the surface: no new collection, no rule change.
- **Cloud sync of history/recordings, pronunciation scoring, shuffled order** — permanently
  out of scope / v2.

Everything Phases 1–3 locked is inherited unchanged: the crash-safe write ordering, the
frozen sqflite schema, the document contract (`content`/`subject`/`level`/`created_at`
only, `created_at` a native Firestore `Timestamp`, `id` = the auto-generated document key
and never duplicated in-document), and the rule that the practice loop never reaches the
network.

</domain>

<decisions>
## Implementation Decisions

### Import surface & the 3-screen rule

- **D-48:** **The importer is a modal bottom sheet opened from a second `IconButton` in
  `SetupScreen`'s AppBar**, beside the existing History action. It is not a route. This is
  what makes UI-03 true by construction rather than by argument — the screen count is
  unchanged because nothing was pushed. A sheet also scrolls, so a long per-row skip list
  (D-55) still fits. *Alternatives rejected: a full-screen pushed route (most room, matches
  how History is reached — but it makes the route count five in the very phase whose
  requirement is "exactly 3 screens with no extraneous navigation"); an inline expandable
  card on Setup (truest to a 3-screen app, but it puts a rarely-used maintenance action
  permanently on the screen the user passes through before every single drill, on a screen
  deliberately kept spare).*
  — **Reversibility:** reversible.

- **D-49:** **"Core screen" is defined, and UI-03 is discharged by a written route
  inventory.** A core screen is a top-level destination the user navigates *to*;
  `SessionDetailScreen` is History's drill-down and the import sheet is a modal, so neither
  is one. The phase must produce an explicit inventory naming every route in the app and its
  classification, so a future fourth destination is a visible change rather than a silent
  one. **This is a real finding, not a formality:** `lib/screens/` already contains four
  screens and UI-03 says three, so the requirement cannot be checked off without saying what
  it counts. *Alternatives rejected: merging session detail into an expandable History list
  (literally 3 routes with nothing to define — but it rewrites a working, tested Phase 1
  screen and its test file for a requirement that is about navigation clutter, not route
  count); amending UI-03 to "3 core + 1 detail" (edits the requirement to fit the code, and
  leaves no rule for what the next screen would have to justify itself against).*
  — **Reversibility:** reversible.

- **D-50:** **Tapping the import icon opens the sheet first, then the OS picker.** The sheet
  opens on an idle state carrying one line that names the expected
  `{"data": [{content, subject, level}]}` shape and a large "Choose JSON file" button; the
  picker follows, then progress and the result render in the same sheet. The extra tap buys
  the required format an on-screen home, so a user who picks the wrong file learns what was
  expected without leaving the app. *Alternatives rejected: icon → OS picker directly
  (fewest taps, but a cancelled pick makes the icon appear to do nothing, and the format has
  nowhere to be stated); opening with a "your bank: N questions across M topics" summary
  (a nice before/after, but it costs another full-collection read on a screen that already
  reads the whole bank on every appearance).*
  — **Reversibility:** reversible.

- **D-51:** **The result stays on screen until dismissed, behind a single "Done" button, and
  dismissal triggers an explicit subjects re-read.** **The re-read is mandatory and is not
  covered by existing code:** D-35's refresh runs off the `Navigator.push` awaits in
  `_openHistory()` and `_startSession()`, and a bottom sheet pops no route, so without a new
  call site an import's new topics would not appear until the user left Setup and came back.
  One exit path, one refresh call site. *Alternatives rejected: auto-closing on a clean
  import and holding open on failures (fewer taps in the happy path, but two exit paths and
  two refresh call sites on a screen whose convention is a single exit — the same objection
  D-29 raised against a bool-returning `_confirmStop()`); an "Import another file" loop
  inside the sheet (useful for the one-file-per-topic/level workflow, but per-file results
  then either accumulate as state or silently overwrite each other).*
  — **Reversibility:** reversible.

### Row validation & partial-write semantics

- **D-52:** **The entire file is parsed and validated in memory BEFORE anything is written**,
  then only the valid rows are written. IMPORT-04's "never silently or partially" is
  satisfied by the write phase having nothing left to decide: every accept/reject judgement
  is already made when the first document goes out. A user with 97 good rows and 3 bad ones
  keeps the 97. *Alternatives rejected: all-or-nothing, where one bad row rejects the file
  (the strictest reading, and re-import is safe by construction since there is never a
  half-written file — but an AI-generated 200-row file with one stray level string costs the
  whole batch); write-row-by-row-and-report-as-you-go (simplest control flow and it surfaces
  write failures per row too, but an interruption mid-file leaves a genuinely partial import
  with no summary, which is the state IMPORT-04's wording exists to prevent).*
  — **Reversibility:** reversible.

- **D-53:** **Normalize, then validate.** `content` and `subject` are trimmed; `level` is
  trimmed and upper-cased. A row is invalid only if `content` or `subject` is blank after
  trimming, or `level` is not one of `A1`/`A2`/`B1`/`B2`/`C1`/`C2`. **The normalized values
  are what get written.** This is the decision that keeps `Travel`, ` Travel` and `travel `
  from ever becoming three checkboxes for one topic — the exact split `normalizeSubjects`
  deliberately refuses to paper over at read time, because trimming a subject on READ would
  label a checkbox `Travel` that the server-side `subject in [...]` matches against nothing.
  Trimming on WRITE has no such problem: it stops the two values from coexisting at all.
  *Alternatives rejected: validate strictly and write verbatim (nothing the user wrote is
  ever silently altered and the skip report teaches the format — but an AI emitting `"b1"`
  costs a whole batch, and one trailing space that slips through silently forks a topic);
  normalize text but require the level string to be exactly right (a defensible split, and
  the closest runner-up — rejected because a wrong-cased level is unambiguous and there is
  no correctness reason to reject what can be read).*
  — **Reversibility:** reversible for future imports; **already-written values are not
  retroactively normalized**, so a bank imported under a different rule would need a data
  fix, not a code change.

- **D-54:** **Duplicates are skipped, against both the file and the existing bank.** The
  importer reads the collection once before writing and skips any row whose
  `content` + `subject` + `level` already exists in the bank or earlier in the same file.
  Duplicates are reported as their own category ("12 already in your bank"), never as an
  error. The cost is one full-collection read — which is exactly the read `SetupScreen`
  already performs on every appearance, so it is a known-cheap operation at this scale. The
  benefit is that re-importing a file is harmless, and the documented workflow (one
  generated file per topic × level, merged or imported one at a time) makes an accidental
  re-import realistic. *Alternatives rejected: dedupe within the file only (no extra read at
  all, but re-importing the same file still doubles those questions, and the user discovers
  it only by drilling the same prompt twice as often, with no in-app way to tell which copy
  to remove); append blindly (leanest code, and it matches what
  `docs/QUESTION_GENERATION_PROMPT.md` currently promises — but it puts the whole burden on
  the user's memory with no way to see or undo the damage).*
  — **Reversibility:** reversible.
  — **Consequence:** `docs/QUESTION_GENERATION_PROMPT.md` says "the app's import just
  appends to the bank." That sentence becomes false and must be rewritten in this phase.

- **D-55:** **The result is headline counts plus a per-row skip list keyed by file
  position.** "85 imported · 12 already in your bank · 3 skipped", then a scrollable list
  naming each skipped row by its **1-based position in the file** and why —
  `Row 14: level "B7" is not one of A1–C2` — with the question text truncated to one line.
  The position is what makes the row findable in the source file; a reason alone tells the
  user a shape of problem, not a location. This is literally what IMPORT-04 asks for.
  *Alternatives rejected: counts plus grouped reasons ("2 invalid level, 1 blank content") —
  compact and it stays short for a 500-row file, but the user has to hunt their own JSON;
  counts only (closest of the three to the silent partial failure IMPORT-04 forbids).*
  — **Reversibility:** reversible.

### Seed content

- **D-56:** **IMPORT-05 is satisfied by a one-time maintainer seed into the real Firestore
  project — there is no app-side first-run mechanism.** Every install then downloads a bank
  that is already full. **The honest cost must be written into PROJECT.md rather than left
  as a surprise, and it resolves STATE.md's first Phase 4 concern:** a brand-new install
  still needs one online Setup visit before it can drill. **IMPORT-05 makes the bank
  non-empty; it does not make the app offline-capable on first run**, and the D-36 narrowing
  ("the practice loop runs offline *after one successful online Setup visit*") stands
  unchanged. *Alternatives rejected: a bundled seed JSON auto-imported on first run (it
  genuinely makes a fresh offline install usable — but it reintroduces a second in-app
  question bank, which is the exact thing D-36 deleted `PlaceholderQuestionSource` to
  prevent, and it needs a first-run flag plus a rule for what happens when the bank read
  FAILS rather than returns empty — the distinction Phase 3 spent a whole plan getting
  right); a bundled seed the user imports manually (one path, one importer, no first-run
  detection, and the starter set is always restorable — but the first run IS empty until
  they tap it, which is what IMPORT-05 says it should not be).*
  — **Reversibility:** reversible — a bundled seed is additive if the offline-first-run
  requirement ever hardens.

- **D-57:** **The seed is authored in the repo as import-format JSON and loaded through the
  app's own importer, on a device.** Seeding the bank and proving the importer works become
  the same act — the strongest UAT this phase can have — and it discharges `tool/README.md`'s
  own stated exit condition, so **`tool/` is deleted in this phase**. *Alternatives rejected:
  extending `tool/seed_questions.mjs`'s matrix and running it once from the maintainer's
  machine (it already handles credentials, `--dry-run`, refuse-if-non-empty and a `--verify`
  pass that replays the real D-43 query — but the importer would then ship without ever
  having written the bank it is responsible for); keeping the script permanently as a
  desktop bulk-load tool (convenient, but it directly contradicts its README's exit
  condition and leaves two write paths into `questions` with different rules — the script
  does not normalize, dedupe, or reject a bad level).*
  — **Reversibility:** reversible in principle; deleting `tool/` is recoverable from git.

- **D-58:** **The Phase 3 dev seed is wiped before the real seed is imported.** The current
  collection holds five throwaway subjects (including `Technology, media and everyday
  digital habits`, long on purpose), levels A1/B1/C1 only, two deliberately empty
  topic × level combinations, one 200+ character prompt, and **two deliberately malformed
  documents** (one with no `content`, one whose `content` is whitespace). None of that
  belongs in the bank a real user drills against. The edge-path coverage those documents
  provided moves into the importer's and the adapter's test fixtures, where it belongs.
  *Alternatives rejected: keeping it and importing on top (nothing is lost and D-41's
  zero-result path plus the malformed-document skip stay demonstrable against live data —
  but the shipped bank then permanently contains two documents that exist only to be
  broken); hand-pruning the two bad documents in the console (preserves real content and
  cleans the junk, but leaves a topic list mixing throwaway and intended names, and console
  hand-editing is exactly the untracked-change path `firestore.rules` was moved into the
  repo to avoid).*
  — **Reversibility:** **one-way** — the deleted documents are gone; the seed JSON in the
  repo is the only way back, which is another reason D-57 keeps it in the repo.

- **D-59:** **The seed is all 10 named topics × all 6 CEFR levels × ~10 questions each
  (~600 documents).** The topic names are already fixed by
  `docs/QUESTION_GENERATION_PROMPT.md`, which lists them as "already shipped in the app":
  `Daily Life`, `Travel`, `Food & Dining`, `Work & Career`, `Health & Fitness`, `Education`,
  `Technology`, `Family & Relationships`, `Sports`, `Entertainment & Hobbies`. Full coverage
  means every chip combination the user can pick returns questions, and a single-topic
  20-question session cycles only twice rather than four times. **Two accepted costs, stated
  rather than discovered:** (1) the subjects read has no field projection, so every Setup
  appearance reads ~600 documents — comfortably inside Firestore's free tier for one user,
  but it is now the dominant read cost in the app; (2) **D-41's zero-result path is no
  longer reachable in live data** and remains covered only by the fake-source unit tests.
  *Alternatives rejected: ~5 questions per combination (~300) (same coverage at half the
  read cost and half the content to generate — but a 20-question single-topic session then
  cycles the same 5 prompts four times, blunting the reflex drill and making the app good
  only after the user does work); 10 topics × 3 core levels A2/B1/B2 (~300) (deep where a
  self-studying learner actually drills, and it keeps D-41 live — but three of six level
  chips return nothing on a fresh install, which reads as a broken app).*
  — **Reversibility:** reversible — the bank grows or shrinks independently of the code.

### Import failure, offline & the 30-topic cap

- **D-60:** **A server-only read gates the import; an offline import never starts.** This is
  the phase's sharpest correctness detail, and it is the write-side mirror of Phase 3's
  cache-versus-server rule. Firestore applies writes to the local cache immediately but the
  returned Future completes only on **server acknowledgement**, so an import attempted
  offline would spin forever while the questions sat queued on the device. D-54's dedupe
  pass already has to read the bank — force that read to come from the **server**, not the
  cache, and a failure ends the import before a single document is written, with one fixed
  user-facing string. **The server-only source is independently correct anyway:** a
  cache-served dedupe read would miss questions added from another device and would let
  duplicates through. *Alternatives rejected: a bounded wait on the acks, then reporting
  that the questions are saved on this device and will upload later (literally true, and a
  retry is harmless because the local cache makes the dedupe pass find them — but it adds a
  third, conditional outcome the user must understand, on a surface whose other messages are
  all definitive); reporting success as soon as writes are applied locally (fastest and
  never blocks, but it reports "600 imported" for a write that has not reached the bank —
  the exact class of statement Phase 1 Plan 6 and D-37 exist to prevent).*
  — **Reversibility:** reversible.

- **D-61:** **The >30-selected-topics throw gets its own user-facing string on Setup.**
  Today that throw lands on the generic Start-failure message, which names the user's
  connection — imprecise, and `firestore_question_source.dart` says so in its own comment,
  accepting the imprecision **only because the branch is unreachable at the seeded bank
  size**. This phase's importer is what the comment names as the thing that can make it
  reachable, so the acceptance expires here. The new string names the real cause and the
  real fix ("you can drill at most 30 topics at once — uncheck a few"). One new fixed
  string, no new query machinery, and **the `kMaxTopicsPerQuery` doc comment must be updated
  to stop claiming the branch is unreachable.** *Alternatives rejected: also warning at
  import time when a file pushes the bank past 30 distinct subjects (catches it at the
  moment of cause rather than three screens later — but it costs a distinct-subject count in
  the importer and a fourth report category for something that is not an import failure:
  the import succeeded, the bank just got wide); building the batched multi-query merge now
  (removes the limit entirely, but it contradicts the leanest-code constraint the comment
  itself cites, and preserving D-43's `created_at` order across merged batches is real work
  that nothing here forces).*
  — **Reversibility:** reversible.

- **D-62:** **A bad FILE is its own state, distinct from row results.** Not-valid-JSON, no
  `data` key, `data` not a list — the sheet shows a short message naming what the file must
  look like plus the expected shape, and offers "Choose a different file". **No row list and
  no counts, because nothing was examined.** A file that parses but whose `data` array is
  empty gets its own line ("that file has no questions in it"), since that is the file being
  *empty* rather than *wrong* — the same empty-versus-unreadable split the whole project
  runs on. *Alternatives rejected: folding it into the row report as "0 imported" (one
  result surface, fewer states to build and test — but "0 imported" then says the same thing
  for an unreadable file as for a file of 400 duplicates, collapsing two facts this project
  keeps apart); rejecting at the picker with a snackbar (fastest to dismiss, but snackbars
  vanish and are unrecoverable once gone — the objection that already ruled a snackbar out
  for the Topics card failure in D-37).*
  — **Reversibility:** reversible.

- **D-63:** **`created_at` is a strictly increasing client `Timestamp` per row, ascending in
  file order.** D-43 defines bank order as `orderBy('created_at')` ascending, so a batch
  sharing one timestamp would be hundreds of ties — arbitrary order inside the batch, which
  is precisely the de-facto shuffle D-43 was written to prevent. Per-row increasing
  timestamps make **file order become bank order**, and an import visibly extends the end of
  the bank. This is also exactly what `tool/seed_questions.mjs` already writes, so the
  representation the reader and the composite index were built on is unchanged.
  *Alternatives rejected: `FieldValue.serverTimestamp()` on every row (the server's clock,
  immune to a wrong phone clock, and the obvious "correct" choice in isolation — but every
  document in one commit resolves to the same instant, so a 600-row import is one giant tie);
  client timestamps clamped to start after the bank's newest `created_at` (guarantees an
  import lands at the end regardless of clock skew, and the dedupe read already has the data
  so it costs no extra query — rejected as the more subtle option, since it turns
  `created_at` into an ordering key more than a creation time).*
  — **Reversibility:** **one-way in data** — changing the representation later is a data
  migration, not a refactor: the composite index in `firestore.indexes.json` is built on
  this field's type and `FirestoreQuestionSource` reads it back in this form.
  — **Accepted risk:** a badly wrong device clock could place an import *before* existing
  questions in bank order. Single-user app, non-destructive, visible only as ordering.

### Claude's Discretion

- **Exact copy** for every new string, within the established warm/playful voice and the
  one-fixed-string-per-failure convention: the sheet's idle-state format hint, the file-level
  failure messages (D-62), each per-row skip reason (D-55), the duplicate category label,
  the offline/could-not-reach-the-bank string (D-60) and the >30-topics string (D-61).
- **The AppBar icon** for import, and whether the sheet is a `showModalBottomSheet` with a
  drag handle or a fixed-height sheet.
- **Progress presentation** during the write — determinate ("writing 240 of 600") versus a
  plain spinner.
- **How the seed JSON is split** across files (one file per topic, one per topic × level, or
  one large file), and whether the seed JSON stays in the repo after import — D-58's
  one-way delete argues for keeping it.
- **Where the importer's parse/validate/dedupe logic lives** — the constraint is only that
  it be a pure, host-testable function of "decoded JSON + existing bank" → "rows to write +
  skip report", with the Firestore write behind the same kind of thin adapter every other
  platform dependency uses.

### Open implementation questions for research and planning

These were surfaced during discussion and deliberately left to the researcher/planner
rather than decided here. They are not gray areas the user needs to answer — they are
facts to establish.

1. **Firestore's `writeBatch` caps at 500 operations**, so a ~600-row seed needs at least
   two commits. The planner must decide and document what happens when batch 1 commits and
   batch 2 fails — this is the one place a partial write can still occur despite D-52, and
   the answer must be consistent with IMPORT-04's "never silently or partially". (The
   researcher should confirm the exact cap and the recommended chunking pattern against the
   installed `cloud_firestore 6.8.0`.)
2. **Whether the sheet can be dismissed mid-write**, and what the user is told if they do.
3. **How the server-only read is expressed** in the installed SDK
   (`GetOptions(source: Source.server)` or equivalent) and exactly which failure modes it
   raises when offline — D-60's whole design hangs on this.
4. **Whether `file_picker ^11.0.3` needs any Android/iOS configuration** beyond the pubspec
   entry on the current target SDKs, and whether it returns a path or bytes on each
   platform.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope & requirements
- `.planning/PROJECT.md` — core value, constraints, Key Decisions table. **Three things need
  updating in this phase:** the three Active requirements (JSON import, ~10 seeded topics,
  the reusable generation prompt) move to Validated; a Key Decisions row records D-56's
  honest statement that IMPORT-05 makes the bank non-empty but does not make a first run
  offline-capable; and the "No pronunciation scoring in v1" row is still marked "— Pending"
  and should be resolved at milestone close.
- `.planning/REQUIREMENTS.md` — this phase covers IMPORT-01..05 and UI-03. Its Traceability
  table and the `Complete (device UAT pending)` qualifiers need updating. Note UI-03's
  wording is what D-49 defines a rule for.
- `.planning/ROADMAP.md` — Phase 4 goal and its four success criteria.
- `.planning/STATE.md` — carries **two Phase 4 concerns this discussion resolves**: the
  seed-versus-offline-first-run question (answered by D-56, and the answer is "no, and here
  is where that is written down"), and the note that the in-app importer is the first
  client-side writer through the open rules (D-46 unchanged; the importer adds no collection
  and no rule change).

### Prior-phase artifacts that constrain this phase
- `.planning/phases/03-real-question-bank-via-firestore/03-CONTEXT.md` — D-32..D-47. Most
  binding here: **D-43** (`orderBy created_at`, which D-63 must not break), **D-35**
  (Setup re-reads subjects on reappear — D-51 adds the sheet-dismiss call site the existing
  hook does not cover), **D-37** (read failure ≠ missing data, which D-60 and D-62 extend to
  the write path), **D-46** (the open rules the importer writes through), and **D-47**
  (host-testability stops at the seam).
- `.planning/phases/01-record-save-replay-a-single-answer-crash-safe/01-UI-SPEC.md` — the
  locked palette, type scale, spacing scale and copywriting contract. The import sheet and
  every new string extend this system; they do not invent a second one.
- `.planning/phases/02-full-timed-practice-session-setup-loop-controls/02-CONTEXT.md` —
  D-16..D-31, especially **D-29**'s single-exit rule, which D-51 applies to the sheet.

### Stack guidance
- `.claude/CLAUDE.md` — the recommended stack, the Conventions section (the house rules this
  phase must follow), and the "What NOT to Use" table. `file_picker ^11.0.3` is already the
  chosen picker and is listed there but **not yet in `pubspec.yaml`** — this phase adds it.

### Docs this phase must change
- `docs/QUESTION_GENERATION_PROMPT.md` — **already exists and already names the 10 seed
  topics as "already shipped in the app", which is not yet true.** D-59 makes it true. But
  the file also states "the app's import just appends to the bank", which **D-54 falsifies**
  — it must be rewritten to describe normalization (D-53) and duplicate-skipping (D-54).
  This file is PROJECT.md's third Active deliverable ("a reusable prompt given to the user,
  not run by the app"), so getting it right is requirement work, not housekeeping.
- `tool/README.md` and `tool/` — the README's own exit condition ("delete this directory
  when Phase 4's in-app JSON importer lands") fires in this phase (D-57).
- `android/app/src/main/AndroidManifest.xml` — check whether `file_picker` adds any
  permission to the merged release manifest. Phase 3's verified set is `RECORD_AUDIO` +
  `INTERNET` + `ACCESS_NETWORK_STATE`; if that changes, the CLAUDE.md and PROJECT.md rows
  that state it must change with it.

### Infrastructure (repo is the source of truth, never the console)
- `firestore.rules` — the open read/write rules the importer writes through. **Unchanged by
  this phase.**
- `firestore.indexes.json` — the composite index (`level`, `subject`, `created_at`) D-63
  depends on. Deployed with
  `firebase deploy --only firestore:rules,firestore:indexes`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- **`lib/services/firestore_question_source.dart`** — the importer's most important
  neighbour. `kQuestionsCollection` is **the one place the collection is named** and its doc
  comment explicitly tells this phase's importer to read it rather than repeat the string.
  `kCreatedAtField` and its native-`Timestamp` contract are what D-63 must honour.
  `sanitizedText()` is the existing pure trim-and-reject rule — D-53's validation should
  reuse or mirror it rather than write a second one. `normalizeSubjects()` documents exactly
  why exact-string subjects matter, which is D-53's whole rationale.
  `kMaxTopicsPerQuery` (line 84) carries a doc comment that **names this phase** as the
  thing that could make its branch reachable, and states that the imprecise error copy is
  accepted "only because the branch is unreachable at the current bank size" — D-61 closes
  that.
- **`lib/screens/setup_screen.dart`** — the AppBar `actions:` list (line 473) currently
  holds exactly one `IconButton` (History); D-48 adds the second.
  `_refreshSubjectsOnReappear()` (line 300) is the D-35 refresh and **its doc comment
  already anticipates this phase** ("Phase 4's importer lands the user back here too, and
  will need no extra wiring") — that is true for a pushed route and **not** true for a
  bottom sheet, which is exactly the gap D-51 closes. `_loadSubjects(background:)` is the
  method to call. `_clearStartMessage()` shows the established pattern for dropping a
  message that has stopped describing the screen.
- **`tool/seed_questions.mjs`** — being deleted, but read it first: its seed matrix,
  its strictly-increasing-`Timestamp` write (the D-63 precedent), its `--verify` mode that
  replays the real D-43 query, and its `--force` refuse-if-non-empty guard are all prior art
  for what the importer and the seed content have to get right.
- **`docs/QUESTION_GENERATION_PROMPT.md`** — the topic list D-59 must match exactly, string
  for string, or the doc's central promise breaks.

### Established patterns
- **Platform dependencies live behind injectable constructor seams, resolved lazily**
  (`RecorderBackend`, `AudioPlaybackBackend`, `documentsDirProvider`, `DatabaseHelper`,
  `ScreenWakeController`, `QuestionSource`). The file picker and the Firestore write are two
  more of these. A test injecting a fake must never construct the real one.
- **No vendor type crosses a seam** — no `QuerySnapshot`, `DocumentSnapshot`,
  `FirebaseException` or `FilePickerResult` under `lib/screens/`.
- **A failure is never presented as missing data**, and **one fixed user-facing string per
  failure** with detail to `debugPrint`/`FlutterError.reportError` only. D-60 and D-62 are
  this rule applied to the write path.
- **Edge cases fail loudly rather than silently degrading** — the `whereIn` guard throws
  rather than trimming the selection. D-52/D-55 are the import-side expression of the same
  rule: nothing is dropped without being named.
- **Every colour and text style comes from `Theme.of(context)`**; `textScaler` is never
  pinned. The sheet's per-row list must reflow at max OS text scale.
- **Tests mirror `lib/` path for path** under `test/`; fixtures live in `test/fixtures/`,
  never in `lib/`. **D-58's deleted malformed documents should reappear here as fixtures.**
- **Doc comments record the decision and the rejected alternative**, tagged with the
  decision ID.

### Integration points
- **`SetupScreen`'s AppBar** — one new action (D-48).
- **`SetupScreen`'s sheet-dismiss path** — a new `_refreshSubjectsOnReappear()` call site
  that no existing code covers (D-51).
- **`SetupScreen`'s Start failure surface** — one new fixed string for the >30-topics case
  (D-61), alongside `kQuestionLoadErrorMessage` and `noQuestionsMessage()`.
- **`pubspec.yaml`** — adds `file_picker ^11.0.3`. `dart:convert` and `dart:io` are SDK
  libraries; add no JSON package.
- **The `questions` collection itself** — wiped and re-seeded (D-58), which means the
  composite index must still be deployed and built before the first Start query afterwards.
- **`tool/` deletion** — removes `tool/package.json`, `tool/node_modules`,
  `tool/package-lock.json`, `tool/seed_questions.mjs`, `tool/README.md`.

</code_context>

<specifics>
## Specific Ideas

- **UI-03 must be *shown*, not argued.** The route inventory (D-49) is the deliverable that
  makes "exactly 3 screens" checkable by a future reader who counts four files in
  `lib/screens/` and wants to know whether that is a bug.
- **Seeding and proving the importer are the same act** (D-57). If the seed goes in any
  other way, the importer ships never having written the bank it owns.
- **The write path inherits the read path's honesty rules.** "I could not reach the bank",
  "that file is not readable", "that file has no questions", "these rows were skipped" and
  "these were already there" are five different facts and get five different surfaces —
  the same discipline D-37 established for the Topics card.
- **A duplicate is not an error.** It gets its own count and its own neutral wording; a user
  re-importing a file should feel reassured, not warned.
- **The `created_at` contract is load-bearing and easy to break casually** (D-63). It is the
  one thing in this phase that is a data migration rather than a refactor if it goes wrong.
- **Write the consequences down where they bite.** D-56's "still needs one online visit"
  belongs in PROJECT.md, D-54's dedupe belongs in the generation-prompt doc, and D-61's
  reachability belongs in the `kMaxTopicsPerQuery` comment that currently claims otherwise.

</specifics>

<deferred>
## Deferred Ideas

- **A bundled seed JSON auto-imported on first run** (D-56 alternative) — the only design
  that makes a never-online install usable. Revisit if the offline-first-run promise ever
  hardens into a requirement; it is purely additive.
- **Warning at import time when a file pushes the bank past 30 distinct subjects** (D-61
  alternative) — catches the cap at the moment of cause. Revisit if the Setup-side message
  proves to arrive too late to be useful.
- **The batched multi-query merge for >30 selected topics** (D-61 alternative) — still
  deferred, still documented in `kMaxTopicsPerQuery`. Revisit when a real bank exceeds 30
  distinct subjects.
- **A bank summary on the import sheet** (D-50 alternative) and **per-topic question counts
  on Setup** (carried over from Phase 3's D-41 alternatives) — both need the same data and
  would naturally be built together.
- **"Import another file" without reopening the sheet** (D-51 alternative) — revisit if the
  one-file-per-topic × level workflow proves tedious in practice.
- **Editing or deleting questions from inside the app** — never requested; the bank is
  append-only from the client and pruning is a Firebase-console act.
- **Firebase Auth and non-open `questions` rules** — D-46's documented exit condition, out
  of scope for v1.
- **Shuffled question order (LOOP-V2-01), re-record from history (HIST-V2-01), playback
  speed (HIST-V2-02)** — v2.

</deferred>

---

*Phase: 4-Bulk Import, Seed Content & Screen Polish*
*Context gathered: 2026-08-09*
