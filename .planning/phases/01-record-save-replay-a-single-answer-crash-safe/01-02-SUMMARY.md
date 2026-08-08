---
phase: 01-record-save-replay-a-single-answer-crash-safe
plan: 02
subsystem: ui
tags: [flutter, dart, google_fonts, baloo2, material3, theming, accessibility, animation]

requires:
  - phase: 01-01
    provides: "PracticeScreen, HistoryScreen, SessionDetailScreen and PracticeState.phase — the working screens this plan restyles"
provides:
  - "MaterialApp.theme carrying the UI-SPEC colour tokens (ivory/peach/coral/warm-red/brown) as the single source of colour for every screen"
  - "Typography roles wired to the UI-SPEC table: Baloo 2 for Display/Heading, default Material font for Label/Body"
  - "Mascot widget — 120px mic-with-face with idle/listening/error variants and an accent pulse ring gated on isRecording"
  - "96px circular Stop target and 64px-minimum history/detail rows"
  - "Text-scale-safe practice screen: scrolls rather than clipping when the OS text size grows"
affects: [01-03, 02-timed-multi-question-loop]

actuals:
  tokens: 7500
  tasks: 2
  commits: 3

tech-stack:
  added:
    - "google_fonts ^8.2.1"
  patterns:
    - "All colour lives in ThemeData; screens read Theme.of(context).colorScheme / textTheme and never hardcode a hex value"
    - "Centre-but-scroll layout (LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight)) so large OS text scales reflow instead of overflowing"
    - "Fixed-size touch targets wrap their label in FittedBox so the target size survives max text scale"
    - "Self-contained presentational widgets (Mascot) carry their own UI-SPEC token literals so they render identically outside the app theme"

key-files:
  created:
    - lib/widgets/mascot.dart
    - test/widgets/mascot_test.dart
  modified:
    - lib/main.dart
    - lib/screens/practice_screen.dart
    - lib/screens/history_screen.dart
    - lib/screens/session_detail_screen.dart
    - pubspec.yaml
    - pubspec.lock
    - .claude/CLAUDE.md

key-decisions:
  - "onPrimary is #3D2B1F (warm brown), not white — brown-on-coral is 4.7:1 versus white-on-coral at 2.8:1, so the STOP label passes WCAG AA and stays inside the warm palette"
  - "The practice screen centres its content but scrolls when it no longer fits, which is what makes the largest-OS-text-scale backstop survivable"
  - "Mascot is drawn from Flutter primitives (Container/Icon/AnimationController) — no image asset, no network fetch, and it renders correctly in a bare MaterialApp under test"
  - "History rows keep an accent chevron (navigation) while detail rows keep the accent play icon (playback), so accent always names the action the row actually performs"
  - "google_fonts fetches Baloo 2 at runtime and caches it; not bundling the .ttf keeps the repo lean but adds the app's first network egress — flagged rather than silently changed"

patterns-established:
  - "Theme-first styling: a screen that needs a colour or a text size reads it from Theme.of(context), never from a literal"
  - "Any fixed-height UI element must be proven safe at the largest OS text scale (scroll, FittedBox, or minHeight — never a hard max)"

requirements-completed: [UI-01, UI-02]

coverage:
  - id: D1
    description: "All three screens render with the UI-SPEC colour tokens: #FFF8F0 background, #FFDDB3 surfaces, #FF6B35 accent, #E5484D error, #3D2B1F text-on-color"
    requirement: "UI-02"
    verification:
      - kind: other
        ref: "grep -n '0xFFFFF8F0|0xFFFF6B35|0xFFE5484D' lib/main.dart — all five tokens defined and bound to scaffoldBackgroundColor/colorScheme"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: confirm ivory background, peach cards/rows, coral Stop button and play icons"
        status: unknown
    human_judgment: true
    rationale: "Whether the rendered palette actually reads as warm/friendly rather than corporate-grey is a visual judgment; only the token values are machine-checkable."
  - id: D2
    description: "Question prompt renders in Baloo 2 at 32/600/1.3 and screen titles at 24/600/1.2, with Label/Body left on the default Material font"
    requirement: "UI-01"
    verification:
      - kind: other
        ref: "grep -n 'GoogleFonts.baloo2' lib/main.dart — displayLarge and headlineSmall only; labelLarge/bodyLarge are plain TextStyle"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: confirm Baloo 2 glyphs on the question text and screen titles only"
        status: unknown
    human_judgment: true
    rationale: "google_fonts resolves the font family at runtime; only a real render proves Baloo 2 actually loaded rather than silently falling back."
  - id: D3
    description: "No screen pins textScaleFactor/textScaler — text inherits the OS accessibility text-size setting"
    requirement: "UI-01"
    verification:
      - kind: other
        ref: "grep -rn 'textScaleFactor|textScaler' lib/ — single hit, and it is the comment forbidding the override"
        status: pass
    human_judgment: false
  - id: D4
    description: "The longest hardcoded question wraps across multiple lines with no clipping or overflow, including at the largest OS text-scale setting"
    requirement: "UI-01"
    verification:
      - kind: manual_procedural
        ref: "Set OS text size to maximum, reopen the Practice screen, confirm the prompt reflows and the screen scrolls without a RenderFlex overflow stripe"
        status: unknown
    human_judgment: true
    rationale: "UI-SPEC marks this a backstop; the mitigation (scrollable centred column) is in code but only a real device at max text scale proves no clipping."
  - id: D5
    description: "The accent pulse ring is present only while recording is active and disappears the moment recording stops"
    requirement: "UI-02"
    verification:
      - kind: unit
        ref: "test/widgets/mascot_test.dart#the ring follows isRecording as it toggles"
        status: pass
      - kind: unit
        ref: "test/widgets/mascot_test.dart#idle mascot builds and shows no pulse ring"
        status: pass
      - kind: unit
        ref: "test/widgets/mascot_test.dart#recording mascot builds and shows the pulse ring"
        status: pass
    human_judgment: false
  - id: D6
    description: "A 120px mic-with-face mascot appears on the Practice screen with distinct idle vs. listening faces, and a non-mocking concerned face reserved for the error state"
    requirement: "UI-02"
    verification:
      - kind: unit
        ref: "test/widgets/mascot_test.dart#error variant builds and shows no pulse ring"
        status: pass
      - kind: manual_procedural
        ref: "flutter run on device: watch the mascot idle, while recording, and (after Plan 3) in the error state"
        status: unknown
    human_judgment: true
    rationale: "The tone prohibition — the face must never read as mocking, disappointed, or shaming — is inherently a human call, not an assertion."
  - id: D7
    description: "The Stop button is a 96px-diameter circular target and history/detail rows have a 64px minimum height"
    requirement: "UI-01"
    verification:
      - kind: other
        ref: "grep -n 'width: 96' lib/screens/practice_screen.dart; grep -n 'minHeight: 64' lib/screens/history_screen.dart lib/screens/session_detail_screen.dart"
        status: pass
      - kind: other
        ref: "flutter analyze — zero issues, so the constrained layouts compile as written"
        status: pass
    human_judgment: false
  - id: D8
    description: "CLAUDE.md's Supporting Libraries table documents google_fonts per D-15 and the UI-SPEC package note"
    verification:
      - kind: other
        ref: "grep -n 'google_fonts' .claude/CLAUDE.md — one Supporting Libraries row"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-08-08
status: complete
---

# Phase 1 Plan 02: Warm Visual System Summary

**The three Plan 1 screens restyled onto the locked UI-SPEC design contract: a Material 3 theme carrying the ivory/peach/coral palette, Baloo 2 on the Display and Heading roles only, a 120px mic-with-face mascot whose coral ring pulses only while the mic is live, and text that reflows instead of clipping at the largest OS text size.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-08T04:37:59Z
- **Completed:** 2026-08-08T04:45:57Z
- **Tasks:** 2
- **Files modified:** 8 (2 created, 6 modified)

## Accomplishments

- Built `MaterialApp.theme` as the single source of colour and type for the app: every screen now reads `Theme.of(context).colorScheme` / `textTheme` instead of carrying ad-hoc `TextStyle`s and default Material greys.
- Mapped the UI-SPEC typography table exactly — Baloo 2 at 32/600/1.3 (question prompt) and 24/600/1.2 (screen titles), default Material font at 18/600/1.2 (labels) and 16/400/1.5 (body) — so the friendly display font never leaks into body copy.
- Added the recurring mascot (D-13): a 120px peach mic-with-face drawn from Flutter primitives, with idle, listening, and concerned-not-sad error variants, and an accent pulse ring gated strictly on `isRecording`.
- Applied the large-touch-target exceptions: a 96px circular STOP button and 64px-minimum history/detail rows, with accent colour used only on affordances (never as a decorative fill).
- Made the Practice screen survive the largest OS accessibility text size — it centres normally and scrolls once the content outgrows the viewport, rather than throwing a RenderFlex overflow.

## Task Commits

1. **Task 1: Theme (colours + typography) applied to all three screens** - `5ad1e33` (feat)
2. **Task 2: Mascot widget with recording-state pulse ring** - `2c69aec` (feat)

**Plan metadata:** see the `docs(01-02)` commit that follows this file.

## Files Created/Modified

- `lib/main.dart` - The whole design system: five UI-SPEC colour tokens, the derived `ColorScheme`, the AppBar theme, and the four typography roles
- `lib/widgets/mascot.dart` - `Mascot` widget; face variants, `AnimationController`-driven pulse ring, eager controller construction, disposal
- `lib/screens/practice_screen.dart` - Mascot + peach rounded question card + 96px circular STOP; scroll-safe centred layout
- `lib/screens/history_screen.dart` - Baloo 2 title, peach rounded rows at 64px minimum, accent chevron affordance, themed empty state
- `lib/screens/session_detail_screen.dart` - Baloo 2 title, peach rounded rows, accent play icon
- `test/widgets/mascot_test.dart` - Four widget tests covering ring presence/absence and both face variants
- `pubspec.yaml` / `pubspec.lock` - `google_fonts: ^8.2.1`
- `.claude/CLAUDE.md` - Supporting Libraries row for `google_fonts` with the UI-SPEC rationale

## Decisions Made

- **Brown, not white, on the coral Stop button.** White on `#FF6B35` is 2.8:1 — below WCAG AA even for large text. `#3D2B1F` on coral is 4.7:1 and is already the UI-SPEC text-on-color token, so `onPrimary` was set to it.
- **Centre-but-scroll instead of a plain centred Column.** UI-01's backstop demands the longest question reflow without clipping at max text scale; a fixed centred Column would overflow. `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight)` keeps the normal centred look and degrades to scrolling.
- **The mascot owns its token literals.** It is a self-contained presentational widget with no theme dependency, so it renders identically inside a bare `MaterialApp` in tests and cannot be broken by a future theme edit. Screens, by contrast, always go through `Theme.of(context)`.
- **History rows keep the chevron.** UI-SPEC asks for an accent play affordance on history rows, but tapping a history row *navigates* to the session; showing a play icon there would promise playback the row does not perform. Accent now marks the chevron (still a tappable affordance) and the play icon stays on the detail rows that actually play audio. This carries forward and closes the reconciliation Plan 1 flagged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The mascot crashed when disposed without ever recording**
- **Found during:** Task 2
- **Issue:** The plan's `AnimationController` was written as a lazy `late final` field initialiser. When `isRecording` was never true the controller was never touched during the widget's life, so `dispose()` *constructed* it — creating a `Ticker` against a deactivating element. Flutter threw "Looking up a deactivated widget's ancestor is unsafe" every time an idle mascot left the tree, which on the Practice screen means every navigation away from the screen.
- **Fix:** The controller is constructed eagerly in `initState()` and only `repeat()` is conditional.
- **Files modified:** `lib/widgets/mascot.dart`
- **Verification:** `test/widgets/mascot_test.dart#idle mascot builds and shows no pulse ring` reproduced the crash before the fix and passes after; all four mascot tests pass.
- **Committed in:** `2c69aec`

**2. [Rule 2 - Missing Critical] Stop button label would have failed contrast**
- **Found during:** Task 1
- **Issue:** The plan set `colorScheme.primary` to coral but left `onPrimary` to `ColorScheme.fromSeed`, which pairs a saturated primary with white. White on `#FF6B35` is 2.8:1 — unreadable-by-standard for an app whose named requirement is large, easily readable text (UI-01).
- **Fix:** `onPrimary: Color(0xFF3D2B1F)` — 4.7:1, and identical to the `labelLarge` colour the plan already specified for the STOP label, so icon and label match.
- **Files modified:** `lib/main.dart`
- **Verification:** Contrast computed from the WCAG relative-luminance formula for both candidate pairs; `flutter analyze` clean.
- **Committed in:** `5ad1e33`

**3. [Rule 2 - Missing Critical] Max text scale would have overflowed the Practice screen**
- **Found during:** Task 1
- **Issue:** The plan forbids pinning `textScaler` (correct) but the existing layout was a fixed centred `Column` inside `Padding`. At the largest OS text size the 32px prompt plus the 96px button exceeds the viewport, producing a clipped RenderFlex overflow — a direct violation of the plan's own backstop must-have ("wraps ... with no clipping/overflow ... at the largest OS text-scale setting").
- **Fix:** Wrapped the body in `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight: viewport - padding)` so it stays centred until it cannot be, then scrolls. The STOP label is wrapped in `FittedBox` so the fixed 96px target never overflows either.
- **Files modified:** `lib/screens/practice_screen.dart`
- **Verification:** `flutter analyze` clean, 21/21 tests pass; on-device confirmation at max text scale remains coverage item D4.
- **Committed in:** `5ad1e33`

### Planned-scope adjustments (not defects)

- **History-row affordance:** accent chevron rather than the play icon UI-SPEC names, because history rows navigate rather than play (see Decisions).
- **Explicit `appBarTheme`:** added so the app bar's peach background, brown foreground and accent action icon are deterministic rather than inherited from M3's surface-tint defaults.
- **Colour tokens as `static const` on `EnglishReflexApp`:** the acceptance criteria name the literals `Color(0xFFFFF8F0)` / `Color(0xFFFF6B35)` / `Color(0xFFE5484D)`; they are defined as named constants in `lib/main.dart` and bound to `scaffoldBackgroundColor` / `colorScheme.primary` / `colorScheme.error` rather than repeated inline.

---

**Total deviations:** 3 auto-fixed (1 bug, 2 missing-critical) + 3 documented scope adjustments
**Impact on plan:** Deviation 1 fixes a crash the plan's literal wording would have shipped. Deviations 2 and 3 are what make UI-01 ("large, easily readable text") actually true rather than nominally configured. No scope creep — no logic, persistence, recording or navigation behaviour was touched.

## Issues Encountered

- **`google_fonts` fetches Baloo 2 at runtime.** The package downloads the font from `fonts.gstatic.com` on first use and caches it on device; offline first-runs fall back to the default Material font. Bundling the `.ttf` as an asset would remove the fetch but adds binary assets to the repo — deliberately not done here (see Threat Flags).

## Known Stubs

None. `Mascot.isError` is wired to `PracticePhase.error`, which no code sets yet — Plan 3 of this phase owns the error path and its copy. That is planned sequencing, not a placeholder: the parameter has a real, tested rendering today.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: network-egress | `pubspec.yaml`, `lib/main.dart` | The plan's `<threat_model>` states "No new data/storage/network boundary". That is now inaccurate: `google_fonts` performs a runtime HTTPS request to `fonts.gstatic.com` to fetch Baloo 2 on first launch, which is this app's first outbound network call (Plan 1 shipped with zero). No user data is transmitted — the request is a static font download — but the app now depends on a third-party CDN at first run and the Android/iOS network posture changes. Remediation options for a future phase: bundle the Baloo 2 `.ttf` as a Flutter asset and set `GoogleFonts.config.allowRuntimeFetching = false`. |

`T-02-01` (supply chain) was honoured: the official `google_fonts` package (publisher `material.io`, the canonical pub.dev package) was added via `flutter pub add`, resolved to `^8.2.1`, with a caret range rather than `any`. No lookalike package was installed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready:**
- Plan 3 can add its error banner straight onto `Theme.of(context).colorScheme.error` and `Mascot(isError: true)` — both already exist and render.
- Phase 2's Setup screen inherits the full theme with no styling work; new screens only need to read `textTheme` roles.

**Outstanding — device UAT:**
- Coverage items D1, D2, D4 and D6: on-device confirmation of the rendered palette, that Baloo 2 actually loads (rather than silently falling back), that the longest question reflows without clipping at the largest OS text size, and that the mascot's faces read as friendly rather than evaluative.

## Self-Check: PASSED

Both created files (`lib/widgets/mascot.dart`, `test/widgets/mascot_test.dart`) and all six
modified files exist on disk. Both task commits (`5ad1e33`, `2c69aec`) are present in `git log`.
`flutter analyze` reports "No issues found!" and `flutter test` reports 21/21 passing
(17 inherited from Plan 1 plus 4 new mascot tests).

---
*Phase: 01-record-save-replay-a-single-answer-crash-safe*
*Completed: 2026-08-08*
