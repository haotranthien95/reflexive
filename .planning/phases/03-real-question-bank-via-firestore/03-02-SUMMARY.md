---
phase: 03-real-question-bank-via-firestore
plan: 02
subsystem: question-bank
tags: [firestore, setup-screen, error-states, empty-vs-unreachable, ui-states, d-37, d-38, d-41]
status: complete

requires:
  - "Plan 03-01's `QuestionSource` async seam, `FirestoreQuestionSource`, `QuestionBankUnavailableException` and `normalizeSubjects`"
  - "The live, seeded `questions` collection on Firebase project `reflex-english` — in particular its two deliberately malformed documents and its two empty topic×level combinations"
provides:
  - "The topics card's four mutually exclusive states: loading, populated, empty, could-not-load"
  - "The Start button's three states (ready / blocked / busy) and the footer's four helper states (none / blocked / zero-result / failure)"
  - "`kTopicsErrorMessage` and `kQuestionLoadErrorMessage` — the two bank-failure strings, one per retry affordance"
  - "`noQuestionsMessage(level, topics)` — the pure, three-branch D-41 zero-result copy"
  - "`sanitizedText(Object?)` — the one shared usable-field rule, host-testable"
  - "`kMaxTopicsPerQuery` — Firestore's confirmed `whereIn` cap, guarded loudly rather than trimmed"
  - "`FakeQuestionSource` — the single scripted test double driving every read outcome on the host"
affects:
  - "Plan 03 — retires `PlaceholderQuestionSource`/`kQuestions`/`kSubjects` and runs the on-device UAT this plan defers to it"
  - "Phase 4's importer (IMPORT-01) — is the named trigger that would make `kMaxTopicsPerQuery` batching required rather than speculative"

tech-stack:
  added: []
  patterns:
    - "Nullable-data + two flags instead of `FutureBuilder`: a bare `FutureBuilder` flips to loading and error on every new future, which cannot express a silent background refresh"
    - "`null` data means never-loaded and an empty list means server-confirmed-empty — the two are never spelled the same way"
    - "One nullable message field + one treatment flag, rendered by an else-if chain, so mutually exclusive helper states are exclusive by construction rather than by discipline"
    - "Two separate `styleFrom` calls for two button treatments, rather than one call with ternary arguments"
    - "A scripted test double whose per-call outcomes are `a List is returned, anything else is thrown`, plus a Completer gate so in-flight frames are observable under the fake clock"

key-files:
  created:
    - "test/services/firestore_question_source_test.dart"
  modified:
    - "lib/screens/setup_screen.dart"
    - "lib/services/firestore_question_source.dart"
    - "test/screens/setup_screen_test.dart"

decisions:
  - "Firestore's `whereIn` limit is 30, confirmed against the INSTALLED cloud_firestore 6.8.0's own assert in lib/src/query.dart, not against prose docs."
  - "That plugin assert is stripped from release builds, which is the reason the explicit pre-query guard earns its keep rather than being redundant."
  - "`sanitizedText` is the shared usability JUDGEMENT; the value each read carries forward differs — prompts trimmed, subjects raw — because a subject is a server-side query key and trimming it would produce a checkbox matching nothing."
  - "The topics card does not use `FutureBuilder` despite following history_screen's branch order: a FutureBuilder cannot express D-35's silent background refresh."
  - "A catch-all sits beside the `on QuestionBankUnavailableException` clause: a read that threw is a read that was not served, whatever threw it."
  - "The last-Start-outcome is one nullable message plus one treatment flag, not two independent message fields, so B3 and B4 cannot coexist."

metrics:
  duration: "~55 min"
  completed: 2026-08-09
  tasks: 3
  commits: 3

actuals:
  tokens: 22000
  tasks: 3
  commits: 3
---

# Phase 3 Plan 02: The Four Honest Read Outcomes — Summary

Setup now tells the truth about the question bank in every direction: the topics card
distinguishes *loading*, *populated*, *genuinely empty* and *couldn't reach* as four mutually
exclusive states; START SESSION shows work in flight without losing its coral fill; a zero-result
query names both the level and the topics; and a failed one names the connection while preserving
every setting. The adapter skips malformed documents with a console note instead of rendering blank
rows, and refuses a topic selection wider than Firestore's `whereIn` cap rather than trimming it to
fit.

## The confirmed `whereIn` limit, and where it was confirmed

**30**, for `in` and `array-contains-any`.

**Source: the installed package's own enforcement**, `cloud_firestore 6.8.0`,
`~/.pub-cache/hosted/pub.dev/cloud_firestore-6.8.0/lib/src/query.dart:726-731`:

```dart
// This assert checks whether "in" or "array-contains-any" have 30 or less filters
assert(
  (operator != 'in' && operator != 'array-contains-any') ||
      (value as Iterable).length <= 30,
  "'$operator' filters support a maximum of 30 elements in the value [Iterable].",
);
```

Two things worth recording about that source:

1. **It is stronger than documentation, not weaker.** The plan asked for the limit "for the installed
   `cloud_firestore` version", and this is the installed version enforcing it in its own code — not a
   doc page that may describe a different release. The immediately preceding assert in the same block
   pins the *other* operators at 10, which is exactly the pre-2023 number an assumption would likely
   have carried forward; the confirmation was therefore not academic.
2. **The assert is debug-only and this is why the guard exists.** Dart strips `assert` from release
   builds, so in a release APK an over-limit `whereIn` would be sent to the server and come back as
   an opaque `INVALID_ARGUMENT` `FirebaseException` — which `_read` would dutifully convert into
   `QuestionBankUnavailableException` with nothing in the log naming the real cause. The explicit
   pre-query guard makes the edge behave identically in both build modes *and* emit a `debugPrint`
   that names the actual problem. This is written into `kMaxTopicsPerQuery`'s doc comment.

**Context7 was not reachable from this agent and no substitute was invented.** The MCP tools were not
present in this agent's tool set (the known upstream bug that strips MCP tools from agents with a
restricted tool list), and `ctx7` is not installed on this machine; the executor contract forbids
`npx --yes` to fetch it. Rather than fall back to training-data recall — the exact thing the plan
warned against by saying "confirm rather than assume" — the number was read out of the dependency
that is actually resolved in `pubspec.lock`. `test/services/firestore_question_source_test.dart`
pins `kMaxTopicsPerQuery == 30` so a future SDK bump that moves the limit forces a deliberate
decision instead of a silent drift.

## Task 1 — the topics card tells the truth (commit `c6e32aa`)

`List<String> _subjects` became `List<String>? _subjects`, and that one type change is D-37 in a
field: `null` is *never successfully loaded* and an empty list is *the server confirming the bank is
empty*, and they are no longer spelled the same way. Two flags, `_topicsLoading` (initialised `true`,
so the very first frame is the spinner rather than a flash of an empty card) and `_topicsError`, join
it — all three driven from the single `_loadSubjects()` query site that `initState`, the retry button
and the reappearance refresh all come through.

**The branch order is `history_screen.dart`'s, but the mechanism deliberately is not.** A bare
`FutureBuilder` flips to loading and to error on *every* new future, which cannot express D-35's
silent background refresh — so the card branches on plain state fields instead, in the same
load-bearing order (loading → error → data), with the comment explaining why any other order coerces
a failed read into an empty bank.

`_loadSubjects` takes a `background` flag. A background read touches neither flag and, on failure,
keeps the last-known topics and says nothing beyond a `debugPrint`. It is driven off the
`Navigator.push` awaits already in the file — `_openHistory` and `_startSession` each gained one —
rather than a route observer, so Phase 4's importer will need no extra wiring. When the card is
already in could-not-load there is nothing worth keeping, so that refresh is a foreground read
instead.

**Selection reconciliation** (`_selectedTopics.retainAll(subjects)`) runs after every successful read
and is commented as the thing standing between the user and a silent zero-result naming a topic that
is no longer on screen to uncheck.

Two new private widgets: `_TopicsLoading` (coral indicator, 16px, `Loading your topics…`) and
`_TopicsError` (`_HistoryError`'s exact geometry — 48px red `error_outline_rounded`, 16px, centred
message, 16px, a `TextButton` at `minimumSize: Size(64, 48)` — with the one sanctioned deviation that
the message and the button label are brown rather than error red, because warm red measures 3.03:1 on
peach and clears the 3:1 non-text threshold for the icon while failing the 4.5:1 text threshold).
`_NoTopics` was **not** rewritten; only its doc comment, which named plan 02 as its fixer.

The blocked helper's trigger narrowed to `topicsLoaded && subjects.isNotEmpty &&
selectedTopics.isEmpty`, with the comment recording that this is the Phase 2 latent bug going live
rather than a new behaviour.

## Task 2 — the Start footer tells the truth (commit `a29c298`)

`_startSession` now builds the `SessionConfig` first and synchronously (the race resolution, and now
an explicit test case), sets `_starting`, clears any prior helper, awaits, and branches three ways:
push on success, zero-result helper on a server-confirmed empty list, failure helper on a throw.
`_starting` is cleared on every path including before the push, so popping back off a session finds a
normal footer. No navigation and no reset happens on either failure.

The busy button is the same `FilledButton` with a second `styleFrom` call — two calls rather than one
with ternary arguments, because busy is a different treatment and not a tweak. It overrides
`disabledBackgroundColor` to `primary` and `disabledForegroundColor` to `onPrimary`, because
`FilledButton` paints the disabled fill whenever `onPressed` is null and a busy button falling back
to the peach blocked treatment would render *in flight* identically to *blocked*. Its child is a 24px
`CircularProgressIndicator` in brown `onPrimary`, keyed `setup-start-busy`, inside
`Semantics(label: 'Starting session')`. `onPressed` stays null, so a double-Start is structurally
impossible.

The helper slot is an **else-if chain** returning `Widget?`, so `setup-start-blocked`,
`setup-start-no-questions` and `setup-start-error` are mutually exclusive by construction rather than
by three conditions someone has to keep disjoint. The 8px gap belongs to the helper, so the resting
ready state is one button and nothing else.

### Final wording — both failure constants

| Constant | Value |
|----------|-------|
| `kTopicsErrorMessage` | `Couldn't reach your question bank — check your connection and try again.` |
| `kQuestionLoadErrorMessage` | `Couldn't reach your question bank — check your connection and tap START SESSION again.` |

Identical first clause, deliberately divergent second: the topics card has a **"Try again" button**
directly beneath its message and the footer has **no button at all**, so re-tapping START SESSION is
the retry and the copy has to say so. A shared string would have had to name neither.

### Final wording — all three zero-result branches

`noQuestionsMessage(String level, List<String> topics)` is a top-level pure function with exactly
three branches:

| Topics | Output |
|--------|--------|
| 1 | `No {level} questions in {topic} yet. Try another level, or pick more topics.` |
| 2 | `No {level} questions in {topicA} or {topicB} yet. Try another level, or pick more topics.` |
| 3+ | `No {level} questions in any of your {n} topics yet. Try another level, or pick different topics.` |

Worked, and asserted verbatim in three unit tests:

- `No C2 questions in Travel yet. Try another level, or pick more topics.`
- `No C2 questions in Travel or Food & health yet. Try another level, or pick more topics.`
- `No C2 questions in any of your 4 topics yet. Try another level, or pick different topics.`

The two-topic join is **`or`**, not `and`, because the query is a disjunction. The 3+ branch names the
count rather than enumerating because the footer does not scroll and an unbounded string would push
the 64px button off-screen; it still names the topic dimension, so D-41's both-dimensions requirement
holds. Zero topics is unreachable behind SETUP-07 and falls into the count branch rather than earning
a fourth string for a state the button makes impossible — recorded in the function's doc comment.

Both helpers clear on any topic toggle, any level change, any slider move, and on the next tap.

## Task 3 — the adapter survives real data (commit `d95f4a7`)

`sanitizedText(Object? raw)` is the one shared rule: the trimmed value when `raw` is a `String` with
non-whitespace content, `null` otherwise.

**One deliberate refinement of the plan's wording, and it matters.** The plan says to "use it from
both reads", which taken as *use its return value verbatim* would have broken a decision plan 01 made
on purpose. `normalizeSubjects` keeps `'Travel'` and `' Travel'` as **distinct** topics precisely
because the server-side `subject in [...]` compares exact strings, and 03-01 has a test pinning that.
So `subjects()` uses `sanitizedText` as the **yes/no usability judgement** and carries the **raw**
value forward; `questionsFor` uses the **trimmed** value, because a prompt is display text where
stray whitespace is noise, not a query key. Both reads therefore share one definition of "usable" —
which was the point of extracting it — while differing on what they do with the answer. This is
written into `sanitizedText`'s doc comment so the asymmetry reads as a decision rather than an
oversight.

Each skip emits one `debugPrint` naming the document ID and the reason. Neither read throws on a
malformed document: one bad row must not take out the whole bank. Nothing about a skip reaches the
screen.

The `whereIn` guard compares `config.topics.length` against `kMaxTopicsPerQuery` before the query
runs, emits one `debugPrint` naming the real cause, and throws `QuestionBankUnavailableException`. It
does **not** call `take`/`sublist` and does not return a partial bank. The rejected multi-batch merge
and its reversal trigger (IMPORT-01 growing the bank past 30 distinct subjects) are recorded in the
constant's doc comment, together with the accepted imprecision that the throw currently lands on copy
naming the connection.

The containment rule is intact: no `QuerySnapshot`, `DocumentSnapshot` or `FirebaseException` appears
anywhere under `lib/screens/` or `lib/state/`.

## Tests

`test/screens/setup_screen_test.dart` now carries **exactly one** class implementing the seam.
`FakeQuestionSource` replaces both Phase 3 doubles and scripts per-call outcomes under a single rule:
*a `List<String>` is returned — an empty one being a server-confirmed empty read — and anything else
is thrown*, with the last entry repeating once the script runs out.

Its one addition beyond the plan's sketch is `holdSubjects` / `holdQuestions`, which park a call on a
`Completer` the test releases by hand. Without it "the spinner is on screen while the read is in
flight" is a race with the harness rather than an assertion; a `Completer` stays inside the microtask
queue the fake clock does drain, so it does not reintroduce the `Future.delayed` hang the file's own
header comment warns about. It is what makes the busy-button and retry-returns-to-loading tests real.

New coverage, all of it asserting the wrong state's key **and** its literal copy are absent:

- Loading is the first frame; Start shut; no helper. Releasing the gate lands on the rows.
- A read that threw renders `setup-topics-error` while `setup-topics-empty`, `No topics yet` and the
  empty state's body are all absent — and the reverse for a server-confirmed empty read.
- Topics-state totality (`exactly one of four`) asserted in five scenarios.
- Retry increments the fake's call count and returns the card to loading before resolving.
- A background refresh shows no spinner; when it throws, the rows are still on screen and
  `setup-topics-error` is absent.
- A re-read omitting a previously checked topic drops it from the **selection**, not just the screen
  (proved through the Start gate, not through the checkbox).
- The busy button: no label, `onPressed` null, resolved fill equals theme `primary` and not `surface`,
  height still 64.
- A failed Start preserves the level chip, both checked topics and all three slider readouts, pushes
  no route, and leaks no exception text.
- The tap-time snapshot wins: Start tapped at B2, level changed to C2 mid-flight, and both the config
  the fake was called with and the one `PracticeScreen` received are B2.
- Helper-slot totality (`at most one of three`) asserted across nothing-selected, zero-result and
  failure, including that a second attempt **replaces** rather than accumulates.
- All three `noQuestionsMessage` branches as exact strings.

`test/services/firestore_question_source_test.dart` covers `sanitizedText` for an ordinary string
(trimmed), whitespace-only, `null`, and four non-`String` values, plus a whitespace-padded string that
is still usable — and pins `kMaxTopicsPerQuery`.

## Verification

| Gate | Result |
|------|--------|
| `flutter analyze` | No issues found |
| `flutter test` | 205/205 pass (181 at the plan's base commit, 188 after Task 1, 199 after Task 2) |
| `flutter build apk --debug` | Built successfully — see the build note below |
| `grep -rn "KNOWN GAP" lib/ test/` | no matches — all seven plan-01 gaps closed and their comments removed |
| topics keys present in `setup_screen.dart` | `setup-topics-loading`, `setup-topics-error`, `setup-topics-error-retry`, `setup-topics-empty`, `setup-topics-card` |
| footer keys present | `setup-start`, `setup-start-blocked`, `setup-start-busy`, `setup-start-no-questions`, `setup-start-error` |
| `grep -c 'kTopicsErrorMessage'` | 2 |
| `grep -c 'kQuestionLoadErrorMessage'` | 3 |
| `grep -c 'String noQuestionsMessage'` | 1 |
| `grep -c 'Starting session'` | 1 |
| `grep -c 'disabledBackgroundColor'` | 3 (blocked value, busy override, and the busy branch's own peach sibling) |
| `grep -c 'QuestionBankUnavailableException'` in `setup_screen.dart` | 1 (a real `on` clause, not a comment) |
| hex colour literal in `setup_screen.dart` | 0 |
| `implements QuestionSource` in `setup_screen_test.dart` | 1 |
| `grep -v '^\s*//' … \| grep -c 'String? sanitizedText'` | 1 |
| `grep -v '^\s*//' … \| grep -c 'kMaxTopicsPerQuery'` | 3 |
| `grep -v '^\s*//' … \| grep -c 'debugPrint'` | 6 |
| `grep -E 'topics\.(take\|sublist)'` | 0 — the guard throws, never trims |
| `grep -rE 'QuerySnapshot\|DocumentSnapshot\|FirebaseException' lib/screens/ lib/state/` | 0 in every file |
| `git diff --name-only -- pubspec.yaml pubspec.lock` | empty — no dependency added |

## Deviations from Plan

### Auto-fixed issues

**None.** No bug, missing critical functionality or blocker was discovered during execution; the
three `flutter analyze` errors hit mid-task were type errors in code written seconds earlier, fixed
before any commit, and are not deviations.

### Deliberate refinements (recorded because they are judgement calls, not drift)

**1. `sanitizedText` decides usability for both reads, but only `questionsFor` uses its return
value.**
See Task 3 above. Applying the trimmed value to subjects would have silently reversed plan 01's
deliberate exact-string rule and broken its held-out test. The plan's own instruction to use one
shared rule is honoured; what differs is what each caller does with the verdict.

**2. `_loadSubjects` and `_startSession` each carry a catch-all beside the `on
QuestionBankUnavailableException` clause.**
The plan names only the seam's own exception. A source that throws anything else — which the test
suite deliberately does, to prove the injected source is the one consulted — would otherwise escape
as an unhandled async error. A read that threw is a read that was not served, whatever threw it, so
both land on the same honest state. Structured as one `failure` local with a single handling site
rather than two duplicated catch bodies.

**3. The last-Start-outcome is two coupled fields, not one.**
The plan's artifact list says "the last-Start-outcome field", singular. It is implemented as
`String? _startMessage` plus `bool _startMessageIsFailure`, assigned together in exactly two places,
because the zero-result text is computed from the tap-time snapshot while the failure text is a
constant. A private wrapper class would have been a symbol the plan did not sanction; the mutual
exclusion that matters is enforced where it is observable, in the render's else-if chain, and is
asserted by the helper-totality test.

**4. `FakeQuestionSource` gained a Completer gate.**
Not in the plan's sketch. Without it the plan's own required behaviours — "the card returns to
loading *before resolving*" and "an in-flight query renders the busy button" — are unobservable,
because a synchronous fake has already resolved by the next `pump`. The gate stays inside the
microtask queue, so it does not reintroduce the `Future.delayed` hang the file's header warns about.

**5. `_openHistory` became `async` and the app-bar callback became
`() => unawaited(_openHistory())`.**
Required by the plan's instruction to drive the D-35 refresh off the existing `Navigator.push`
awaits; noted because it changes a call site the plan's `<files>` did not call out.

## Known Stubs

**None.** Every state this plan is responsible for is wired to real data through the seam, and every
branch is reachable and asserted. The two remaining `lib/data/questions.dart` stubs
(`PlaceholderQuestionSource`, `kQuestions`, `kSubjects`) are plan 03's, unchanged and untouched here.

## Outstanding UAT (not run — no device or emulator attached to this session)

Recorded here rather than appended to `.planning/WINDOWS.md`: this plan ran as a parallel worktree
agent alongside a sibling, and appending to a shared cross-phase ledger from two worktrees in the
same wave is a merge conflict waiting to happen. **The orchestrator should fold the two items below
into `WINDOWS.md` as `unrun-verify` entries for phase 03 when it merges this wave.**

1. **Task 3's `<human-check>`, which the plan itself defers to plan 03's on-device UAT.** On a
   networked device, confirm the two deliberately malformed seeded documents (`Daily life`×B1 with no
   `content` field, `Travel`×A1 with whitespace-only `content`) produce neither a blank checkbox row
   nor a blank question card, and that both skips appear in the debug console naming their document
   IDs. Everything host-checkable about that path — the rule itself — is proven by
   `test/services/firestore_question_source_test.dart`; what is not host-checkable is the adapter
   calling it, which is exactly where D-47 puts the boundary.
2. **The Start-query latency question the plan's `<output>` asks about is unanswered.** The flagged
   assumption is that the config snapshotted at tap time wins and the controls stay interactive
   during the busy frame. That assumption is now an explicit, passing test rather than an inherited
   convention, but **whether real on-device query latency justifies revisiting it was not measured**,
   because no device was attached. The sanctioned upgrade if the query routinely exceeds about a
   second remains: disable the form controls during the busy frame, never add an overlay.

## Known limitation, accepted deliberately

The over-limit `whereIn` branch is **not** covered by a `flutter test` assertion — it lives inside
`questionsFor`, which needs a Firestore handle no host test may construct (D-47). It is pinned by the
plan's grep criteria, by `kMaxTopicsPerQuery`'s unit test, and by the fact that it is unreachable at
the current bank size (5 subjects against a limit of 30). This is the same host-testability boundary
the microphone sits behind, not a gap in this plan's coverage.

## Threat Flags

**None new.** No network endpoint, auth path, file access pattern or schema change at a trust
boundary was introduced. This plan adds no dependency, no Firestore field, no permission and no
design token; it changes only how already-fetched data is rendered and how already-thrown failures
are explained. The phase's standing flags (`network-egress`, `unauthenticated-write`,
`credential-in-repo`) were raised in 03-01 and are unchanged.

One thing worth naming as a positive: this plan tightens the existing containment posture rather
than loosening it. Two new user-facing failure strings were added, and both were written to the
established rule that no exception text, Firestore error code, collection name, document ID or
project ID may reach the screen — asserted negatively by
`expect(find.textContaining('QuestionBankUnavailable'), findsNothing)` on both surfaces.

## Self-Check: PASSED

Created file verified present: `test/services/firestore_question_source_test.dart` — FOUND.
Modified files verified present: `lib/screens/setup_screen.dart`,
`lib/services/firestore_question_source.dart`, `test/screens/setup_screen_test.dart` — all FOUND.

Commits verified in `git log`: `c6e32aa` (Task 1) — FOUND. `a29c298` (Task 2) — FOUND. `d95f4a7`
(Task 3) — FOUND.

No files were deleted by any of the three commits (`git diff --diff-filter=D` empty for each).
Working tree clean before this summary was written. No shared orchestrator artifact (`STATE.md`,
`ROADMAP.md`, `WINDOWS.md`) was modified.
