# Phase 3: Real Question Bank via Firestore - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-09
**Phase:** 3-Real Question Bank via Firestore
**Areas discussed:** Fetch timing & query shape, Offline & failure behavior, Matching & empty results, Getting real data in there

---

## Fetch timing & query shape

### Q1 — How many Firestore reads should a session take, and where do they happen?

| Option | Description | Selected |
|--------|-------------|----------|
| One fetch at Setup, filter in Dart | Read the whole collection once, derive subjects, filter in memory on Start. One network call per Setup visit, zero during the loop. Matches CLAUDE.md's guidance. Whole bank in memory. | |
| Two reads: subjects at Setup, filtered query on Start | Setup read derives subjects; Start issues a real `where subject in […]` + `where level ==` query. Literally satisfies BANK-03. Costs a call on the Start path, a composite index, and the `in` disjunction cap. | ✓ |
| Live snapshot listener | `.snapshots()` so topics self-update. Stream lifecycle to manage; bank can change under an in-flight session. | |

**User's choice:** Two reads
**Notes:** Flagged to the user that deriving distinct subjects requires reading every doc (no client-side field projection), so the Setup read already contains the Start query's data — accepted as a deliberate trade for a genuinely filtered query rather than an in-memory `where`.

### Q2 — Where should the Start-tap query wait live?

| Option | Description | Selected |
|--------|-------------|----------|
| Block on Setup, then push | Busy state on Setup; PracticeScreen pushed only once questions are in hand. Failure leaves the user on Setup with a retry. | ✓ |
| Push first, load inside the 3·2·1 countdown | Hidden under LOOP-01's get-ready countdown if fast. Adds a loading state and a failure path to the loop; a slow query breaks the countdown's fixed 3 s meaning. | |
| Prefetch on topic/level change | Start becomes instant. Many queries per visit, plus a Start-during-flight race. | |

**User's choice:** Block on Setup, then push
**Notes:** Preserves PracticeScreen's Phase 2 "handed everything it needs" constructor contract.

### Q3 — How should the resolved list reach the practice loop?

| Option | Description | Selected |
|--------|-------------|----------|
| QuestionSource goes async; loop takes a resolved list | `questionsFor` returns a Future, called only from Setup; PracticeState receives `List<String>` via constructor. `_pickQuestion()` stays pure and synchronous. | ✓ |
| Add the questions to SessionConfig | One immutable value carries everything. But SessionConfig is documented as "what Setup decided", and its no-serialization rule keeps it a settings object. | |
| Keep QuestionSource sync, inject a pre-loaded instance | Loop code literally unchanged. But an un-awaited instance silently returns an empty bank. | |

**User's choice:** Async QuestionSource, loop takes a resolved list
**Notes:** Keeps D-23's cycling and the reading/arming same-prompt guarantee intact; makes the loop's network-free property structural.

### Q4 — When should Setup re-read the bank to refresh its topic checkboxes?

| Option | Description | Selected |
|--------|-------------|----------|
| Every time Setup appears | initState plus every return from Practice/History. Always current; Phase 4's importer needs no extra wiring. | ✓ |
| Once per app launch, cached in memory | Fewest reads. After a Phase 4 import the user must restart the app to see new topics. | |
| Once per launch plus manual refresh | Cache plus a refresh affordance. A new control on a deliberately spare screen. | |

**User's choice:** Every time Setup appears

---

## Offline & failure behavior

### Q1 — What happens when the device has no network?

| Option | Description | Selected |
|--------|-------------|----------|
| Firestore's own on-device cache | SDK persists read documents and serves queries offline. No extra storage code, no second source of truth. First-run-offline cannot practise; "fully offline" becomes "offline after first successful visit". | ✓ |
| Firestore cache + placeholder bank fallback | First-run-offline users can still drill. Keeps alive a second question source Phase 2 built to be deleted; user can't tell which bank they're on. | |
| Mirror the bank into sqflite | Bank becomes ours, queryable, independent of cache lifetime. Schema version bump on the frozen tables, sync/staleness rule, real code volume. | |
| Require network; block Start offline | Simplest and most honest. Contradicts the standing offline requirement. | |

**User's choice:** Firestore's on-device cache
**Notes:** PROJECT.md's "practice loop runs fully offline" active requirement must be restated as "offline after one successful online Setup visit".

### Q2 — When the subjects read fails outright, what does the Topics card show?

| Option | Description | Selected |
|--------|-------------|----------|
| Distinct error state with Retry, never the empty state | Three states: loading / loaded-but-empty / could-not-load. Start disabled in the latter two. Applies Phase 1 Plan 6's rule to the bank. | ✓ |
| Reuse the empty state, add Retry | One state, less UI. Tells a user with a full bank and flaky network that their questions are gone. | |
| Snackbar, card keeps spinning | Transient error surface. A dismissed snackbar leaves a permanently spinning screen; unreadable to a widget test. | |

**User's choice:** Distinct error state with Retry

### Q3 — What happens when the Start-tap query fails?

| Option | Description | Selected |
|--------|-------------|----------|
| Stay on Setup, inline error near Start, settings intact | Push doesn't happen; re-tapping retries. Follows Phase 1's single fixed failure string. | ✓ |
| Blocking dialog with Retry/Cancel | More prominent. A modal for something the user can just re-tap. | |
| Fall back to filtering the Setup read in memory | Never blocks the user. Silently reintroduces the client-side path just chosen against; two paths, one tested. | |

**User's choice:** Stay on Setup, inline error, settings intact

### Q4 — How formally should the RECORD_AUDIO-only stance be retired?

| Option | Description | Selected |
|--------|-------------|----------|
| Retire in writing + re-verify the merged manifest | Update PROJECT.md and CLAUDE.md; keep `allowRuntimeFetching = false`; re-run Phase 2's merged-release-manifest check as UAT to confirm INTERNET is the only addition. | ✓ |
| Same plus an automated manifest guard | A test asserting the permission set is exactly {RECORD_AUDIO, INTERNET}. Can't run in plain `flutter test` — needs a release build first. | |
| Just note it in the phase docs | Cheapest. Drops a check that has already caught a real problem once in this project. | |

**User's choice:** Retire in writing + re-verify the merged manifest

---

## Matching & empty results

### Q1 — What does "matching the level" mean?

| Option | Description | Selected |
|--------|-------------|----------|
| Exact match only | `where level == 'B1'`. Simplest query, no ordering baked into app code, level chip means real difficulty. Puts weight on the empty-result path. | ✓ |
| Level and below | Mirrors how CEFR actually works, widens the pool. Encodes an A1<…<C2 ordering; a C2 session becomes mostly easy questions. | |
| Exact with automatic widening on empty | Never dead-ends. Session quietly isn't the chosen difficulty; two query paths to test. | |

**User's choice:** Exact match only

### Q2 — What happens when a topic+level combination has zero questions?

| Option | Description | Selected |
|--------|-------------|----------|
| Let them tap Start, then say exactly why | Actionable inline message naming both dimensions. Reuses the Start-failure surface; no new Setup UI. Costs one read to discover. | ✓ |
| Per-topic counts on Setup, pre-block Start | Dead end becomes visually impossible. Real new UI on a spare screen; counts to keep in sync with the level chip. | |
| Live "N questions available" line above Start | Middle ground, much less UI. A number the user has to notice; derived from the Setup read, not the query that runs. | |

**User's choice:** Explain at Start

### Q3 — Pool smaller than question_count?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep cycling, unchanged | Configured count never silently contradicted; `questionAt` and its tests survive untouched. Same prompts repeat with no warning. | ✓ |
| Cycle but warn on Setup | User can widen topics or lower the count first. Needs the pool size known before Start. | |
| Cap the session at pool size | No repeats ever. Silently contradicts the chosen number — what D-23 rejected — and changes LOOP-08's meaning. | |

**User's choice:** Keep cycling, D-23 unchanged

### Q4 — What defines "sequential bank order" for a Firestore query?

| Option | Description | Selected |
|--------|-------------|----------|
| `orderBy created_at` ascending | Deterministic and repeatable; gives `created_at` a job; new imports append to the end; multi-topic sessions interleave by import time. Needs a composite index. | ✓ |
| No orderBy (document-ID order) | Zero index work. With auto-generated IDs it's a de-facto shuffle — quietly doing what LOOP-V2-01 deferred to v2. | |
| `orderBy subject, created_at` | Groups a multi-topic session by topic. Topic-blocked sessions are worse for reflex drilling; wider index. | |

**User's choice:** `orderBy created_at` ascending
**Notes:** Exact composite index shape flagged for the researcher to confirm.

---

## Getting real data in there

### Q1 — Current state of the Firebase side?

| Option | Description | Selected |
|--------|-------------|----------|
| No project yet — create it, guide me | Phase includes a documented setup step: console project (Firestore Native mode, no Auth), then `flutterfire configure`. Treated as a user-performed prerequisite. | ✓ |
| Project exists, not wired into this repo | Only `flutterfire configure` needed. | |
| Already configured outside this checkout | Config files exist but gitignored/elsewhere. | |

**User's choice:** No project yet

### Q2 — How do the first questions get in, given seeding is Phase 4?

| Option | Description | Selected |
|--------|-------------|----------|
| Throwaway dev seed script, not shipped | Small `tool/seed_questions.dart` run once from the maintainer's machine, covering multiple subjects × levels including one deliberately empty combination. Deleted/superseded by Phase 4's importer. | ✓ |
| Hand-type documents in the Firestore console | Zero code. Tedious coverage, easy to typo a field name, painful to redo. | |
| Pull Phase 4's seeding forward | Bank properly populated from the start. Real scope movement into Phase 3. | |

**User's choice:** Throwaway dev seed script

### Q3 — Firestore rules posture?

| Option | Description | Selected |
|--------|-------------|----------|
| Open read + write on `questions` only, documented as a tradeoff | `firestore.rules` in the repo, everything else denied, with a comment naming the actual exposure and what would change it. Honesty is the mitigation, not a fix. | ✓ |
| Open read, writes only from your machine | Admin SDK + service-account key for seeding. Narrower now, but Phase 4's in-app importer reopens it one phase later. | |
| Leave console's default 30-day test-mode rules | Fastest. They expire and the app breaks silently a month later; leaves the implicit state STATE.md asked us to resolve. | |

**User's choice:** Open read + write on `questions` only, documented

### Q4 — How far does host-testability stretch?

| Option | Description | Selected |
|--------|-------------|----------|
| Seam only — fake QuestionSource in tests, real one on device | `FirestoreQuestionSource` stays a thin adapter; tests inject a fake that returns topics/questions/empty/throws, covering all four designed states. Zero new dependencies. | ✓ |
| Add `fake_cloud_firestore` dev dependency | Runs the real `where`/`orderBy` in `flutter test`. Query semantics are an approximation (indexes not modelled), so passing doesn't prove the real query runs. | |
| Firestore emulator for integration tests | Highest fidelity. An external process to install and orchestrate, beyond this project's tooling footprint. | |

**User's choice:** Seam only

---

## Claude's Discretion

- Exact copy for the could-not-load, Start-failure and zero-result messages.
- Firestore collection name, the document → prompt mapping, and malformed-document handling (skip-and-log expected).
- The visual form of the Start busy state (in-button spinner vs. disabled-with-label-change vs. overlay).
- Whether the subjects read lives on `FirestoreQuestionSource` or a sibling method/class.
- The seed script's language and content, subject to the empty-combination coverage requirement.

## Deferred Ideas

- Per-topic / total question counts on Setup (from the zero-result discussion).
- A "questions will repeat" warning before starting (rides on the count above).
- `fake_cloud_firestore` for host-level query tests.
- An automated merged-manifest permission guard (needs a release build artifact / CI).
- Level-and-below matching, if any single level proves too thin to sustain a session.
- In-app JSON import, the ~10 seeded topics, the 3-screen audit — Phase 4, already scheduled.
- Shuffled question order — LOOP-V2-01, v2.

**No scope creep was raised during this discussion** — every area stayed inside the SETUP-01 / BANK-01..03 boundary. The one adjacent item that came up (seeding, IMPORT-05) was explicitly kept in Phase 4 by choosing a throwaway dev script over pulling the requirement forward.
