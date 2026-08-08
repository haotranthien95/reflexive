---
phase: 01-record-save-replay-a-single-answer-crash-safe
plan: 05
subsystem: ui
tags: [google_fonts, baloo2, flutter, assets, typography, offline, privacy]

# Dependency graph
requires:
  - phase: 01-record-save-replay-a-single-answer-crash-safe (plan 02)
    provides: The EnglishReflexApp theme with the four UI-SPEC text roles calling GoogleFonts.baloo2()
provides:
  - Baloo 2 SemiBold bundled as a hash-verified Flutter asset with its OFL licence
  - configureFonts() — runtime font fetching disabled before the first frame, OFL registered with LicenseRegistry
  - test/theme/typography_test.dart — proves the font loads from the bundle rather than silently falling back
  - Zero outbound network requests from the app, making the AndroidManifest "no network permission" comment provably true
affects: [phase-02-setup-screen, phase-03-firestore-question-bank, any-future-ui-phase]

# Actuals (#2632) — same estimateTokens scale (chars/4 over the realized diff).
# Excludes the 418064-byte binary font, which is fetched rather than authored.
actuals:
  tokens: 4545
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Bundled-asset Google Fonts: assets/ declaration + allowRuntimeFetching=false, no fonts: section"
    - "Order-dependent test files carry the reason for the order in-file, next to each test"

key-files:
  created:
    - assets/fonts/Baloo2-SemiBold.ttf
    - assets/fonts/OFL.txt
    - test/theme/typography_test.dart
  modified:
    - lib/main.dart
    - pubspec.yaml
    - .claude/CLAUDE.md

key-decisions:
  - "Bundled the font rather than adding INTERNET to the release manifest — keeps the app's fully-on-device posture and removes its only outbound request"
  - "Kept google_fonts ^8.2.1 rather than dropping it — D-15 and the UI-SPEC lock Baloo 2 via that package; it now loads from the bundle instead of the CDN"
  - "Declared the font under assets: with no fonts: section — google_fonts matches bundled faces by filename through the asset manifest, so a fonts: entry would register a redundant second family"
  - "Asserted the theme by invoking EnglishReflexApp.build() directly rather than pumping the app, because PracticeScreen.initState reaches for sqflite/path_provider channels that do not exist under flutter test"

patterns-established:
  - "Third-party binary assets are pinned by sha256 and byte length, verified before commit, and acquired only from the single permitted URL"
  - "A guard test is proven non-vacuous by deliberately breaking the thing it guards and observing it fail, before it is trusted"

requirements-completed: [UI-01, UI-02]

coverage:
  - id: D1
    description: "Baloo 2 SemiBold is bundled in the app package and is the only load path, so the locked D-15 typography ships in a release build with no network access"
    requirement: "UI-01"
    verification:
      - kind: unit
        ref: "test/theme/typography_test.dart#the Baloo2-SemiBold asset is bundled in the asset manifest"
        status: pass
      - kind: unit
        ref: "test/theme/typography_test.dart#Baloo 2 SemiBold loads from the bundled asset, not the network"
        status: pass
      - kind: other
        ref: "shasum -a 256 assets/fonts/Baloo2-SemiBold.ttf == ebc0059bc16fccdd40426abe2dea840739eb972b5feccedcd652a094cf0b2a8d; wc -c == 418064"
        status: pass
    human_judgment: false
  - id: D2
    description: "The app makes zero outbound HTTP requests for fonts, and the release Android manifest still declares only RECORD_AUDIO"
    requirement: "UI-02"
    verification:
      - kind: unit
        ref: "test/theme/typography_test.dart#configureFonts disables runtime font fetching"
        status: pass
      - kind: other
        ref: "git diff --quiet -- android/app/src/main/AndroidManifest.xml (exit 0)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The four UI-SPEC text roles keep their locked sizes, weights, line-heights and family assignment (Display/Heading on Baloo 2; Label/Body on the default Material font)"
    requirement: "UI-01"
    verification:
      - kind: unit
        ref: "test/theme/typography_test.dart#the UI-SPEC typography contract still holds"
        status: pass
    human_judgment: false
  - id: D4
    description: "On a physical device in airplane mode, a RELEASE build renders the question prompt and screen titles in the rounded Baloo 2 face, the palette and mascot read as warm and friendly rather than corporate grey, and the longest question reflows without clipping at maximum OS text scale"
    verification: []
    human_judgment: true
    rationale: "Typeface identity, palette warmth and mascot tone are visual judgments. Only a release build in airplane mode distinguishes a bundled load from a cached fetch — a debug build grants INTERNET and would load the font either way, which is exactly how Gap 2 escaped notice originally."

# Metrics
duration: 18min
completed: 2026-08-08
status: complete
---

# Phase 01 Plan 05: Bundle Baloo 2 Offline Summary

**Baloo 2 SemiBold now ships inside the app package as a sha256-pinned asset with runtime fetching disabled, closing verification Gap 2 — the locked D-15 typography previously did not exist in release builds and silently fell back to Roboto.**

## Performance

- **Duration:** ~18 min
- **Tasks:** 2
- **Files modified:** 6 (3 created, 3 modified)

## Accomplishments

- **Closed verification Gap 2.** `google_fonts` fetched Baloo 2 over HTTPS at runtime, nothing was bundled, and the `INTERNET` permission existed only in the debug and profile manifests — which are stripped from release. Release builds therefore could not fetch the font and silently fell back to the default Material font, invisibly to any developer testing locally. The font is now bundled and the fetch path is switched off.
- **Removed the app's only outbound network request.** `GoogleFonts.config.allowRuntimeFetching = false` runs before the first frame. The `AndroidManifest.xml` comment claiming no network permission is requested is now provably true rather than merely written down, and no install/launch signal leaks to a third-party CDN (threat T-05-01, severity high, mitigated).
- **Verified the font binary against a pin, not a vibe.** The file was fetched only from the exact `fonts.gstatic.com/s/a/<sha256>.ttf` URL that `google_fonts` 8.2.1 itself resolves for `FontWeight.w600`, then checked against both the sha256 (`ebc0059b…`) and the byte length (`418064`) carried in the installed package descriptor. Both matched exactly (threat T-05-02, mitigated).
- **Added the check the phase never had, and proved it can actually fail.** Four guards now cover the typography contract. Critically, the load test was validated by deliberately deleting the font and rebuilding the test asset bundle — see "Issues Encountered", because the first attempt at this validation was itself misleading.
- **Registered the OFL licence** with `LicenseRegistry`, so the bundled family is disclosed on the app's licences page.

## Task Commits

1. **Task 1: Bundle Baloo 2 SemiBold and switch runtime fetching off** — `9b013a6` (feat)
2. **Task 2: Prove the font loads rather than silently falling back** — `7232f7e` (test)

## Files Created/Modified

- `assets/fonts/Baloo2-SemiBold.ttf` — the 600-weight static instance, 418064 bytes, hash-verified
- `assets/fonts/OFL.txt` — SIL Open Font License text for the family
- `test/theme/typography_test.dart` — four guards over the typography contract
- `lib/main.dart` — `configureFonts()`; called from `main()` after `WidgetsFlutterBinding.ensureInitialized()`
- `pubspec.yaml` — real `assets:` block listing `assets/fonts/`, replacing the commented-out template
- `.claude/CLAUDE.md` — `google_fonts` row records the bundled/offline configuration

## Decisions Made

- **Bundled the font instead of granting `INTERNET` in release.** `01-VERIFICATION.md` named both remediations. Bundling is the one `01-02-SUMMARY.md` itself proposed, it preserves the app's stated fully-on-device posture, and it eliminates the offline-first-run fallback rather than accepting it.
- **Kept `google_fonts` rather than removing it** (diverging from the code review's preferred fix). D-15 and the UI-SPEC Design System table lock Baloo 2 *via that package*; it is retained and simply stops reaching the network.
- **No `fonts:` section in `pubspec.yaml`.** `google_fonts` resolves a bundled face by scanning the asset manifest for a filename ending in `Baloo2-SemiBold`, so the `assets:` declaration is sufficient; a `fonts:` entry would register a second, redundant family.
- **Asserted the theme via `EnglishReflexApp.build()` rather than pumping the widget.** The plan permitted either pumping the app or reconstructing the same `ThemeData`. Both were poor fits: pumping builds `PracticeScreen`, whose `initState` calls `sqflite` and `path_provider` platform channels that do not exist under `flutter test` (its unawaited `startNewQuestion()` would surface as an async test failure), while reconstructing the `ThemeData` would assert against a copy rather than the real theme. Invoking `build()` with a captured `BuildContext` asserts the actual theme from `lib/main.dart` without building the home screen. This still resolves the font family, so the "must run last" ordering rationale is unchanged.

## Deviations from Plan

None — plan executed exactly as written. No deviation rules fired; no files outside this plan's `files_modified` list were touched, and the parallel agent's files (`lib/state/`, `lib/screens/`, `lib/services/`, `lib/widgets/`) were not modified.

## Issues Encountered

**The test asset bundle is stale-cached, which nearly produced a false "verified" result.** After writing the four tests, all passed — but a passing guard proves nothing until it is shown it can fail. Deleting `assets/fonts/Baloo2-SemiBold.ttf` and re-running produced *all four tests still passing*, because `flutter test` reuses a prebuilt bundle at `build/unit_test_assets/` and does not invalidate it when a source asset appears or disappears. Only after `rm -rf build/unit_test_assets` did the intended failure appear:

```
Exception: GoogleFonts.config.allowRuntimeFetching is false but font
Baloo2-SemiBold was not found in the application assets.
```

Both font guards failed as designed; tests 3 and 4 correctly kept passing, since the theme's declared family string is set by `google_fonts` regardless of whether the bytes actually loaded — which is precisely why guards 1 and 2 exist. The font was then restored and re-verified bit-for-bit (sha256 and byte length re-checked, `git status` clean), and the full suite re-run green.

**Handoff note:** if `test/theme/typography_test.dart` ever fails immediately after adding, moving or renaming a file under `assets/`, run `rm -rf build/unit_test_assets` before investigating — the failure is likely a stale bundle rather than a real regression. This is Flutter tooling behaviour, not a defect in this code, and it is the same class of invisible-staleness problem that let Gap 2 survive review in the first place.

## Verification Results

- `shasum -a 256 assets/fonts/Baloo2-SemiBold.ttf` → `ebc0059bc16fccdd40426abe2dea840739eb972b5feccedcd652a094cf0b2a8d` ✅
- `wc -c < assets/fonts/Baloo2-SemiBold.ttf` → `418064` ✅
- `flutter analyze` → **No issues found!** ✅
- `flutter test` → **All tests passed** (36 tests, including 4 new) ✅
- `git diff --quiet -- android/app/src/main/AndroidManifest.xml` → exit 0, manifest byte-for-byte unchanged ✅
- Negative control: with the font removed and the bundle rebuilt, both font guards fail ✅

## Known Stubs

None. No placeholder values, no skipped tests, no unrun `<verify>` blocks.

## User Setup Required

None — no external service configuration required. The font is bundled; nothing needs provisioning.

## Next Phase Readiness

- The typography contract is now mechanically enforced. Future UI phases can rely on `displayLarge`/`headlineSmall` genuinely rendering in Baloo 2.
- One `backstop` item remains for device UAT (coverage `D4`): confirm in a **RELEASE build in airplane mode** that the face, palette and mascot read correctly, and that the longest question reflows at maximum OS text scale. A debug build cannot distinguish a bundled load from a cached fetch.
- **Note for Phase 3 (Firestore):** that phase will add the `INTERNET` permission for the question bank. When it does, the font must stay bundled — restoring network access must not become an excuse to reintroduce the runtime font fetch, which is what this plan's guards are there to prevent.

---
*Phase: 01-record-save-replay-a-single-answer-crash-safe*
*Completed: 2026-08-08*
