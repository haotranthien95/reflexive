---
phase: 02-full-timed-practice-session-setup-loop-controls
plan: 03
subsystem: setup-screen
tags: [setup-screen, cefr-level, sliders, auto-replay, session-config, accessibility]
status: complete

requires:
  - 02-01 SetupScreen (topics section + gated START SESSION)
  - 02-01 SessionConfig (the immutable session transport)
provides:
  - CEFR level selection (SETUP-02)
  - questionCount / thinkingSeconds / answerSeconds sliders (SETUP-03/04/05)
  - auto-replay toggle (SETUP-06)
  - SessionConfig built from all six live fields (SETUP-07)
  - kLevels (the closed CEFR set)
  - SetupScreen widget-test coverage
affects:
  - lib/screens/setup_screen.dart
  - test/screens/setup_screen_test.dart

tech-stack:
  added: []
  patterns:
    - "One shared _SettingSlider sub-widget renders all three numeric settings; the three semanticFormatterCallbacks are passed in rather than repeated"
    - "Single-select ChoiceChip: onSelected ignores the deselect edge, so exactly one level is always in force"
    - "Test-local ThemeData mirroring lib/main.dart, minus google_fonts, so widget tests never depend on a font asset"

key-files:
  created:
    - test/screens/setup_screen_test.dart
  modified:
    - lib/screens/setup_screen.dart

decisions:
  - "The three numeric settings share one _SettingSlider widget rather than three near-identical inline blocks; semanticFormatterCallback therefore appears once in source and three times at call sites"
  - "The auto-replay switch uses activeTrackColor coral with the brown onPrimary thumb — a coral thumb on a coral track would be invisible"
  - "The test builds its own ThemeData because EnglishReflexApp composes the real one inline in build(), and lib/main.dart is owned by another plan this wave"
  - "Widget tests inject a no-engine DatabaseHelper double, not sqflite-ffi, per plan 02-01's fake-clock finding"
  - "Interaction tests pin a 400x2000 portrait surface so every control is laid out and hit-testable without an ensureVisible dance; the text-scale test deliberately uses a realistic 400x900 instead"

metrics:
  duration: ~35m
  completed: 2026-08-09
  tasks: 2
  commits: 2

actuals:
  tokens: 21000
  tasks: 2
  commits: 2
---

# Phase 2 Plan 03: Complete the Setup Screen Summary

Setup is now a real configuration form: six single-select CEFR chips defaulting
to B1, three large-readout sliders for question count, thinking time `t` and
answer length `d`, and an auto-replay toggle defaulting to ON — all six values
travelling into the session as one immutable `SessionConfig`, and none of them
remembered anywhere between visits.

## What Was Built

**Task 1 — the five remaining controls (`20080db`).**

- **Level (SETUP-02 / D-17):** `_LevelChips` renders `kLevels` as six
  `ChoiceChip`s in a `Wrap(spacing: 8, runSpacing: 8)` — peach fill / brown
  label when unselected, coral fill when selected, `showCheckmark: false`. The
  row sits directly on ivory, *not* in a peach card, because unselected peach
  chips on a peach surface would vanish. Tapping the already-selected chip is a
  no-op rather than a deselect, which makes "exactly one level is always
  selected" an invariant rather than a validation rule.
- **The three numeric settings (SETUP-03/04/05):** one `_SettingSlider`
  sub-widget, instantiated three times — Questions (1–100, divisions 99,
  default 10, bare-numeral readout, no helper), Thinking time (3–30, divisions
  27, default 5) and Answer length (10–120, divisions 110, default 60). Coral
  active track and thumb, peach inactive track, no `label:` value-indicator
  popup (the always-visible Display readout replaces it), and a
  `semanticFormatterCallback` per slider so a screen reader hears
  "10 questions" / "5 seconds thinking time" / "60 seconds answer length".
- **Auto-replay (SETUP-06):** a `SwitchListTile` with a 64px min-height
  constraint, coral active track, the Copywriting Contract title and helper, ON
  by default so the Phase 1 loop the user already knows is what they get.
- **The wiring (SETUP-07):** `_startSession` now reads `_level`,
  `_questionCount`, `_thinkingSeconds`, `_answerSeconds` and `_autoReplay`
  instead of 02-01's placeholder constants. The pinned footer, the blocked
  helper and the topic gate are untouched.
- **The D-18 record:** the class doc now states that every field is plain
  `State`, names the deferred alternative (a one-row `settings` table
  remembering the last configuration) and says why it was declined — a new
  schema, a migration path and a "reset to defaults" affordance is not a price
  five settings have earned. It also explains the absence of a reset button:
  there is nothing to reset to.

**Task 2 — the tests (`bb2df0a`).** 14 `testWidgets` cases in six groups:
first-frame defaults; every user-facing string asserted verbatim against the
Copywriting Contract; the Start gate opening and closing with the last topic
(with the blocked helper in lockstep both ways); each slider saturated to
exactly its requirement range and no further; a partial drag proving divisions
land on whole numbers; the three semantic announcements; the single-select
invariant including the no-op re-tap; the pushed `SessionConfig` carrying all
six live fields; a fresh Setup forgetting the previous one's choices; and the
locked empty-topics state. The text-scale case renders at
`TextScaler.linear(2.0)` on a realistic 400x900 surface and asserts
`tester.takeException()` is null both before and after scrolling, with the
pinned footer still on screen.

## Verification

- `flutter analyze` — no issues.
- `flutter test` — 116 tests, all passing (102 before this plan, +14).
- `flutter test test/screens/setup_screen_test.dart` — 14 cases, exit 0.
- Acceptance greps on `lib/screens/setup_screen.dart`: `ChoiceChip` ≥ 1,
  `divisions: 99` = 1, `divisions: 27` = 1, `divisions: 110` = 1,
  `SwitchListTile` = 1, `Color(0x` = 0. `shared_preferences` in `pubspec.yaml`
  = 0 — no new persistence surface anywhere in the repo (D-18).

## Deviations from Plan

### 1. [Documentation] `semanticFormatterCallback` appears once in source, not three times

Task 1's acceptance criterion expects
`grep -c 'semanticFormatterCallback' lib/screens/setup_screen.dart` = 3. The
three numeric settings share one `_SettingSlider` widget rather than three
near-identical inline blocks, so the parameter is written once and supplied
three times: `grep -c 'semanticFormatter: '` = 3, and the test asserts all three
callbacks produce their distinct unit strings. The intent — every slider
announces meaning rather than a bare number — holds in full. No code change
made; factoring the widget out was the leaner reading of the same spec.

### 2. [Rule 3 — Blocking] Widget tests use a no-engine database double, not sqflite-ffi

Task 2 specifies an ffi-backed `DatabaseHelper` against a temp directory.
Plan 02-01 established (and paid for) the fact that `flutter_test`'s fake clock
never yields to the real event loop, so sqflite-ffi futures do not complete
inside a `testWidgets` body. Setup asks the database exactly one question — the
orphan sweep's `listReferencedAudioPaths()` — and no behaviour under test here
depends on its answer, so the double returns an empty set and the sweep is
inert. `documentsDirProvider` still points at a real temp directory, matching
`test/state/practice_session_test.dart`. Real SQLite remains proven by
`test/db/database_helper_test.dart`. No coverage was lost.

**Files:** `test/screens/setup_screen_test.dart`. **Commit:** `bb2df0a`.

### 3. [Rule 3 — Blocking] The test builds its own ThemeData

Task 2 asks for "the app's real `ThemeData`". `EnglishReflexApp` composes it
inline inside `build()`, so there is no seam to import it through, and adding
one would mean editing `lib/main.dart` — outside this plan's file scope and
owned by a concurrent plan this wave. `_testTheme()` mirrors the four palette
values and the four type roles verbatim, substituting the default font family
for Baloo 2 so the test never depends on a font asset. Every assertion here is
about styles *resolving*, not about which glyphs they draw.

### 4. [Rule 3 — Blocking] `activeColor` is deprecated on `SwitchListTile`

The UI-SPEC control table names `activeColor` for the replay toggle. On Flutter
3.44 that parameter is deprecated in favour of `activeThumbColor` /
`activeTrackColor`, and `flutter analyze` must report zero issues. The toggle
uses `activeTrackColor: colorScheme.primary` (coral, as specified) with
`activeThumbColor: colorScheme.onPrimary` (brown) — a coral thumb on a coral
track would be invisible, and brown-on-coral is the same 4.7:1 pairing every
other coral control on the screen uses.

## Notes for Later Phases

- `SessionConfig.level` is carried but not yet used to filter questions —
  that is BANK-03 in Phase 3. A reviewer expecting the level to change which
  questions appear in Phase 2 is looking at Phase 3's work.
- The plan's flagged assumption about `d` slider granularity stands: 1-second
  divisions (110 steps) satisfy SETUP-05 literally. If on-device drag precision
  proves painful at UAT and the sanctioned 5-second fallback is taken, the
  `{n} sec` readout format and the default of 60 both still hold unchanged.
- SETUP-02's edge category was left `unresolved` by the planner's probe. The
  closed-set / single-select reading is now encoded in two tests (the
  deselect-on-change case and the no-op re-tap case), but the flag itself
  should still be reviewed manually at UAT.

## Known Stubs

None.

## Self-Check: PASSED

- `lib/screens/setup_screen.dart` present on disk (modified).
- `test/screens/setup_screen_test.dart` present on disk, 511 lines (min 80).
- Both commits present in `git log`: `20080db`, `bb2df0a`.
- `flutter analyze` clean, `flutter test` 116/116 green, working tree clean.
