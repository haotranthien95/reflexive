# Phase 4: Bulk Import, Seed Content & Screen Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-09
**Phase:** 4-Bulk Import, Seed Content & Screen Polish
**Areas discussed:** Import surface & the 3-screen rule, Row validation & partial-write semantics, Seed content: mechanism & shape, Import failure/offline/the 30-topic cap

**Area selection:** All four presented gray areas were selected.

---

## Import surface & the 3-screen rule

### Q1 — Where does the import UI live, given UI-03 says exactly 3 core screens?

| Option | Description | Selected |
|--------|-------------|----------|
| Modal sheet off Setup's AppBar | Second IconButton beside History opens a scrollable bottom sheet. Adds no route, so the screen count is unchanged by construction. | ✓ |
| Full-screen route pushed from Setup | Most room for a long result list, matches how History is reached — but makes the route count 5 in the phase whose requirement is "exactly 3 screens". | |
| Inline expandable card on Setup | Truest to a 3-screen app, but puts a rarely-used maintenance action permanently on the pre-drill screen. | |

**User's choice:** Modal sheet off Setup's AppBar → D-48

### Q2 — `session_detail_screen.dart` is already a 4th pushed route. How does UI-03 get satisfied?

| Option | Description | Selected |
|--------|-------------|----------|
| Define "core screen" + written audit | A core screen is a top-level destination; session detail is History's drill-down and the sheet is a modal. Discharge UI-03 with a written route inventory. | ✓ |
| Merge session detail into History | Literally 3 routes, nothing to define — but rewrites a working, tested Phase 1 screen for a requirement about navigation clutter, not route count. | |
| Amend UI-03 to 3 core + 1 detail | Edits the requirement to fit the code, and leaves no rule for what the next screen justifies itself against. | |

**User's choice:** Define "core screen" + written audit → D-49

### Q3 — What happens the instant the user taps the import icon?

| Option | Description | Selected |
|--------|-------------|----------|
| Sheet first, then picker | Idle state naming the expected JSON shape + "Choose JSON file"; then the OS picker; progress and result in the same sheet. | ✓ |
| Straight to the OS file picker | Fewest taps, but a cancelled pick makes the icon appear to do nothing and the format has nowhere to be stated. | |
| Sheet with a bank summary first | Gives the result a before/after, at the cost of another full-collection read. | |

**User's choice:** Sheet first, then picker → D-50

### Q4 — After the import finishes, what does the sheet do?

| Option | Description | Selected |
|--------|-------------|----------|
| Stays on the result until dismissed | One "Done" button; dismissal triggers the subjects re-read. One exit path, one refresh call site. | ✓ |
| Auto-close on a clean import, stay open on failures | Fewer taps in the happy path, but two exit paths and two refresh call sites. | |
| Stays open with "Import another file" | Suits the one-file-per-topic workflow, but per-file results either accumulate as state or silently overwrite. | |

**User's choice:** Stays on the result until dismissed → D-51

**Notes:** Claude flagged during the question that Setup's existing D-35 refresh runs off `Navigator.push` awaits and therefore does **not** fire for a dismissed bottom sheet — the re-read is new wiring, contrary to what `_refreshSubjectsOnReappear()`'s doc comment currently predicts about Phase 4.

---

## Row validation & partial-write semantics

### Q1 — With 100 rows and 3 malformed, what actually gets written?

| Option | Description | Selected |
|--------|-------------|----------|
| Validate everything first, then write the good rows | Parse and validate in memory before touching Firestore; write the valid rows; report skipped rows by name. | ✓ |
| All-or-nothing — one bad row rejects the file | Strictest reading of "never partially"; makes re-import safe by construction, but one stray level string costs a 200-row batch. | |
| Write row by row, report as it goes | Simplest control flow, surfaces write failures per row — but an interruption leaves a genuinely partial import with no summary. | |

**User's choice:** Validate everything first → D-52

### Q2 — What makes a row valid?

| Option | Description | Selected |
|--------|-------------|----------|
| Normalize, then validate | Trim content/subject, trim + upper-case level; invalid only if content/subject blank after trim or level not one of the six. Normalized values are written. | ✓ |
| Validate strictly, write verbatim | Nothing silently altered, but "b1" costs a batch and a trailing space silently forks a topic. | |
| Normalize text, strict on level | Cleans the field that can fork a topic, keeps the closed enum exact. | |

**User's choice:** Normalize, then validate → D-53

**Notes:** The question carried the reason this matters — the reader deliberately does *not* trim `subject`, because trimming at read time would label a checkbox `Travel` that the server-side `whereIn` matches against nothing. Trimming at write time has no such problem.

### Q3 — What happens when an imported question already exists?

| Option | Description | Selected |
|--------|-------------|----------|
| Skip duplicates against both file and bank | One collection read before writing; skip rows matching content+subject+level already present. Reported as its own category, not an error. | ✓ |
| Dedupe within the file only | No extra read, but re-importing a file still doubles those questions with no way to see or undo it. | |
| Append blindly, no dedupe | Leanest code and matches what the generation-prompt doc currently promises; puts the whole burden on the user's memory. | |

**User's choice:** Skip duplicates against both file and bank → D-54

**Notes:** This makes `docs/QUESTION_GENERATION_PROMPT.md`'s "the app's import just appends to the bank" false; rewriting it is now phase work.

### Q4 — What does the result look like on screen?

| Option | Description | Selected |
|--------|-------------|----------|
| Headline counts + a per-row skip list | Counts, then a scrollable list naming each skipped row by 1-based file position and reason, text truncated to one line. | ✓ |
| Counts plus grouped reasons | Compact and stays short for large files, but tells the user a shape of problem, not a location. | |
| Counts only | Leanest; closest of the three to the silent partial failure IMPORT-04 forbids. | |

**User's choice:** Headline counts + a per-row skip list → D-55

---

## Seed content: mechanism & shape

### Q1 — What does "ships with ~10 seeded topics" mean with the bank in a shared Firestore project?

| Option | Description | Selected |
|--------|-------------|----------|
| One-time maintainer seed into Firestore | Every install downloads a full bank; no new app code. Honest cost: a fresh install still needs one online Setup visit. | ✓ |
| Bundled seed JSON, auto-imported on first run | Genuinely makes a fresh offline install usable — but reintroduces a second in-app bank (what D-36 deleted the placeholder to prevent) plus first-run-flag and read-failed-vs-empty rules. | |
| Bundled seed JSON, user imports it manually | One path, always restorable — but the first run IS empty until they tap it. | |

**User's choice:** One-time maintainer seed into Firestore → D-56 (resolves STATE.md's first Phase 4 concern)

### Q2 — How does the seed physically get into Firestore?

| Option | Description | Selected |
|--------|-------------|----------|
| Author it as JSON, import it through the app | Seeding the bank and proving the importer become the same act; `tool/` is deleted as its README instructs. | ✓ |
| Extend the Node seed script, then delete it | Reuses working credential/dry-run/verify machinery, but the importer ships never having written its own bank. | |
| Keep the script as a permanent maintainer tool | Convenient for desktop bulk loads; contradicts the README's exit condition and leaves two write paths with different validation rules. | |

**User's choice:** Author it as JSON, import it through the app → D-57

### Q3 — What happens to the Phase 3 dev seed already in the collection?

| Option | Description | Selected |
|--------|-------------|----------|
| Wipe the collection, import the clean ~10-topic seed | The shipped bank contains only real questions; edge-path coverage moves into test fixtures. | ✓ |
| Keep it and add the ~10 topics on top | Nothing lost and D-41 stays demonstrable live, but the bank permanently carries two documents that exist only to be broken. | |
| Keep the good documents, delete the two malformed ones | Preserves real content, but leaves a mixed topic list and requires console hand-editing. | |

**User's choice:** Wipe the collection → D-58 (one-way; the repo JSON is the only way back)

### Q4 — How deep is the seed?

| Option | Description | Selected |
|--------|-------------|----------|
| All 10 topics × all 6 levels, ~10 each (~600) | Every chip combination returns questions; a single-topic 20-question session cycles only twice. | ✓ |
| All 10 topics × all 6 levels, ~5 each (~300) | Same coverage at half the size, but a 20-question session cycles the same 5 prompts four times. | |
| 10 topics × 3 core levels (A2/B1/B2), ~10 each (~300) | Deep where a learner drills and keeps D-41 live, but three of six level chips return nothing on a fresh install. | |

**User's choice:** ~600 across all 60 combinations → D-59

**Notes:** Two costs stated and accepted — ~600 documents read on every Setup appearance (no field projection), and D-41's zero-result path becoming unreachable in live data. The 10 topic names are fixed by `docs/QUESTION_GENERATION_PROMPT.md`, which already lists them as shipped.

---

## Import failure, offline & the 30-topic cap

### Q1 — Firestore writes ack only from the server, so an offline import spins forever. How is that handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Gate on a server-only read before writing | Force the dedupe read to come from the server; if it fails, the import never starts. Server-only is also the correct dedupe source. | ✓ |
| Bounded wait, then report what was queued | Literally true and retry-safe, but adds a third conditional outcome on a surface whose other messages are definitive. | |
| Report success as soon as writes are applied locally | Fastest, never blocks — but reports "600 imported" for a write that has not reached the bank. | |

**User's choice:** Gate on a server-only read → D-60

### Q2 — The importer can push the bank past 30 distinct subjects, where Start throws onto a connection-flavoured message. What closes that?

| Option | Description | Selected |
|--------|-------------|----------|
| Give the cap its own message on Setup | One new fixed string naming the real cause and fix; the `kMaxTopicsPerQuery` comment's "unreachable branch" claim gets corrected. | ✓ |
| Also warn at import time | Catches it at the moment of cause, at the cost of a distinct-subject count and a fourth report category for something that is not an import failure. | |
| Build the batched multi-query merge now | Removes the limit entirely; contradicts the leanest-code constraint the comment itself cites, and D-43 ordering across batches is real work. | |

**User's choice:** Give the cap its own message on Setup → D-61

### Q3 — What about a bad FILE (not valid JSON, no `data` key, empty list)?

| Option | Description | Selected |
|--------|-------------|----------|
| One file-level failure state, distinct from row results | Short message naming the expected shape + "Choose a different file"; no row list, no counts. Empty `data` gets its own line. | ✓ |
| Fold it into the row report as "0 imported" | One surface, fewer states — but says the same thing for an unreadable file as for 400 duplicates. | |
| Reject at the picker with a snackbar | Fastest to dismiss; snackbars vanish and are unrecoverable, the objection that already ruled one out in D-37. | |

**User's choice:** One file-level failure state → D-62

### Q4 — How is `created_at` stamped across an import?

| Option | Description | Selected |
|--------|-------------|----------|
| Strictly increasing client Timestamps, in file order | File order becomes bank order; matches what the seed script already writes, so the index and reader are unchanged. | ✓ |
| `FieldValue.serverTimestamp()` on every row | Immune to a wrong phone clock, but every document in one commit shares an instant — a 600-row import is one giant tie. | |
| Client Timestamps, clamped after the bank's newest | Guarantees an import lands at the end regardless of clock skew, at no extra query cost; rejected as the more subtle option. | |

**User's choice:** Strictly increasing client Timestamps → D-63 (one-way in data; accepted risk: a badly wrong device clock could order an import before existing questions)

### Wrap-up

Claude offered further questions on the `writeBatch` 500-operation cap and on mid-write sheet dismissal; the user chose to move on. Both are recorded in CONTEXT.md as open implementation questions for research and planning rather than dropped.

---

## Claude's Discretion

- Exact copy for every new user-facing string (format hint, file-level failures, per-row skip reasons, duplicate label, offline string, >30-topics string).
- Import AppBar icon; sheet presentation (drag handle vs fixed height).
- Determinate progress vs plain spinner during the write.
- How the seed JSON is split across files, and whether it stays in the repo after import.
- Where the parse/validate/dedupe logic lives — constrained only to being a pure, host-testable function with the Firestore write behind a thin adapter.

## Deferred Ideas

- Bundled seed JSON auto-imported on first run (D-56 alternative) — revisit if offline-first-run hardens into a requirement.
- Import-time warning when a file pushes the bank past 30 distinct subjects (D-61 alternative).
- Batched multi-query merge for >30 selected topics (D-61 alternative) — still deferred, still documented in `kMaxTopicsPerQuery`.
- Bank summary on the import sheet (D-50 alternative) and per-topic counts on Setup (carried from Phase 3's D-41 alternatives) — same data, natural pair.
- "Import another file" without reopening the sheet (D-51 alternative).
- Editing or deleting questions from inside the app — never requested; the bank is append-only from the client.
- Firebase Auth and non-open `questions` rules — D-46's documented exit condition, out of scope for v1.
- Shuffled order (LOOP-V2-01), re-record from history (HIST-V2-01), playback speed (HIST-V2-02) — v2.
