# Navigation contract

## Why this file exists

`REQUIREMENTS.md`'s **UI-03** says the app has *"exactly 3 core screens (Setup, Practice
Session, History) with no extraneous navigation"*. Anyone checking that by looking at the
code finds **five files under `lib/screens/`** — `setup_screen.dart`,
`practice_screen.dart`, `history_screen.dart`, `session_detail_screen.dart` and
`import_sheet.dart` — plus **two modal surfaces** that never appear in that directory
listing at all. Five is not three, and there is no way to tick UI-03 off, or to fail it
honestly, without first writing down *what the requirement counts*. That is this file. It
is the artifact that makes UI-03 checkable rather than arguable (D-49), and the directory
listing above is deliberately the count of files **on disk today**, not a historical one:
a file under `lib/screens/` is not the unit UI-03 counts, which is exactly the confusion
this document exists to remove.

## What counts as a core screen

A **core screen** is a top-level destination that satisfies all three of the following:

1. the user navigates **to** it from the app's own chrome — an app-bar action or a primary
   call to action — **AND**
2. it owns a distinct task the user can stay in indefinitely — **AND**
3. it is reachable without first opening another destination's content.

The three clauses are joined by AND, so failing any one of them is enough to disqualify a
surface. Three familiar shapes each fail at least one:

- **A drill-down of a list item** fails clause 3 (you cannot get to it without first
  opening the list's content) and usually clause 1 as well (you reach it by tapping a row,
  which is content, not chrome).
- **A modal sheet** fails clause 2: it is a transient task with a terminal outcome, and
  the user is expected to finish it and leave, not to live in it.
- **A modal dialog** fails clause 2 for the same reason, and typically clause 1 too.

None of the three is a core screen.

## The complete surface inventory

Every navigable surface in the app, with no exceptions:

| Surface | Reached from | Pushes a route? | Classification |
|---------|--------------|-----------------|----------------|
| `SetupScreen` (`lib/screens/setup_screen.dart`) | `MaterialApp.home` in `lib/main.dart` — the app opens on it | — (root) | **Core screen 1 of 3** |
| `PracticeScreen` (`lib/screens/practice_screen.dart`) | Setup's primary call to action, `START SESSION` | yes (`MaterialPageRoute`) | **Core screen 2 of 3** |
| `HistoryScreen` (`lib/screens/history_screen.dart`) | Setup's app-bar history action | yes (`MaterialPageRoute`) | **Core screen 3 of 3** |
| `SessionDetailScreen` (`lib/screens/session_detail_screen.dart`) | tapping a row **inside** History; and the "view this session" button in Practice's own completion state (D-27) | yes (`MaterialPageRoute`) | **Detail view** — fails clause 3 (unreachable without first opening a History row, or first finishing a session) and clause 1 (reached from content, never from chrome) |
| Import bottom sheet — `ImportSheet` (`lib/screens/import_sheet.dart`) | Setup's app-bar import action | **no** — `showModalBottomSheet` pushes a modal, not a page | **Modal** — fails clause 2: a transient maintenance task with a single terminal outcome |
| Stop-confirmation `AlertDialog` (inside `lib/screens/practice_screen.dart`) | the Practice app-bar Stop action, or the system back gesture routed through `PopScope` (D-29) | no | **Modal** |
| Snackbars and banners | shown in place, on whichever surface raised them | no | **In-place feedback** — not destinations at all |

Two notes on reading the table:

- **`ImportSheet` lives under `lib/screens/` but is not a screen.** It sits there because
  it is a Flutter surface built from `BuildContext` like its neighbours, and moving it
  would have bought nothing but a fifth directory. Its classification is decided by the
  three clauses, not by its path — and it pushes no page route, which is the mechanical
  half of why it fails clause 2 rather than passing clause 1.
- **`SessionDetailScreen` has two entry points, and both are content.** The History row is
  the obvious one; the second is the "view this session" button in Practice's completion
  state, which is reachable only after actually finishing or stopping a session. Neither
  is app-bar chrome, and neither is reachable without first being inside another
  destination — so the second entry point does not promote it. It is still a detail view.

## The result

**Exactly 3 core screens (Setup, Practice, History), 1 detail view, 2 modals, 0
extraneous navigation. UI-03 holds.**

## The rule that keeps it holding

**Any future surface that would push a `MaterialPageRoute` from app-bar chrome or from a
primary call to action becomes a fourth core screen.** Such a surface must either justify
itself against UI-03 — which means amending the requirement, deliberately and in writing —
or be built as a modal or a detail view instead.

**This is exactly why the importer was built as a bottom sheet (D-48).** A full-screen
pushed route for the import flow would have made the app's route count five in the one
phase whose requirement is *exactly three screens with no extraneous navigation*. Choosing
a modal means the screen count is unchanged **by construction** rather than by argument:
there is no reading of the three clauses on which a `showModalBottomSheet` becomes a core
screen, so nobody has to be persuaded.

## Maintenance

When a surface is added or removed, **two places change together**:

1. **this file** — its inventory table, and the result line above it;
2. **`.planning/REQUIREMENTS.md`** — the UI-03 row, if and only if the core-screen count
   itself moved.

A change to one without the other is the failure this document was written to prevent:
the inventory drifting out of date is how the app quietly acquires a fourth core screen
that nobody ever decided to add.
