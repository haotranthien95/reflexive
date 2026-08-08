import 'package:englishreflex/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Guards verification Gap 2: the Baloo 2 typography locked by D-15 must
/// actually ship, rather than silently falling back to the default Material
/// font in a release build.
///
/// TEST ORDER IN THIS FILE IS LOAD-BEARING. Do not reorder these tests. The
/// per-test comments explain exactly what each reordering would break — every
/// one of them turns a real assertion into a vacuous one that passes no matter
/// what, which is precisely the silent-fallback failure mode this file exists
/// to catch.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // ---------------------------------------------------------------------
  // MUST BE THE FIRST TEST IN THIS FILE.
  // ---------------------------------------------------------------------
  // This is the strongest claim here — that google_fonts really resolved
  // Baloo 2 SemiBold from the bundled asset — but it is also the most fragile
  // observation. Three properties of google_fonts 8.2.1 make it work, and each
  // is a way it silently breaks if written differently:
  //
  // (1) WHY A CLEAN COMPLETION IS POSITIVE EVIDENCE. `loadFontIfNecessary`
  //     looks for a matching bundled asset first. When none is found and
  //     `allowRuntimeFetching` is false, it THROWS an exception naming the
  //     missing font, and that error is rethrown into the future collected by
  //     `pendingFonts()`. So completing without error can only mean the
  //     bundled face loaded — a silent fallback cannot masquerade as success.
  //     (The package attaches its own `.whenComplete(...).ignore()` listener,
  //     so the failure never surfaces as an unhandled zone error. Awaiting
  //     `pendingFonts()` is what makes it visible; nothing else will.)
  //
  // (2) NO `pump`, AND NO OTHER `await`, BETWEEN THE TWO CALLS BELOW.
  //     `googleFontsTextStyle` adds the load future to `pendingFontFutures`
  //     and REMOVES it again on completion. Any pump — or any intervening
  //     await — lets that future settle first, leaving `pendingFonts()` to
  //     await an empty list: a guaranteed pass regardless of outcome.
  //
  // (3) THIS MUST RUN BEFORE ANYTHING THAT RESOLVES THE FAMILY.
  //     `_loadedFonts` is a process-global set. Once any test in this run has
  //     loaded Baloo2, this call returns early and registers an
  //     already-complete future — again a guaranteed pass. That is why the
  //     test which builds the app theme is LAST.
  //
  // Uses a plain `test()`, not `testWidgets`, because `testWidgets` pumps.
  test('Baloo 2 SemiBold loads from the bundled asset, not the network', () async {
    configureFonts();

    // These two statements must stay adjacent. See (2) above.
    GoogleFonts.baloo2(fontWeight: FontWeight.w600);
    await expectLater(GoogleFonts.pendingFonts(), completes);
  });

  // The PRIMARY non-vacuous mechanical guard for Gap 2. Unlike the load test
  // above, this depends on no global state, no test ordering and no exception
  // plumbing — it fails deterministically if the font file is renamed, moved,
  // or dropped from the `assets:` list in pubspec.yaml, which is the realistic
  // regression. Treat this as the floor beneath the stronger-but-more-fragile
  // load test, not as a secondary nicety.
  //
  // The filename is matched, not just its presence: google_fonts'
  // `findFamilyWithVariantAssetPath` scans the asset manifest for an entry
  // ending in `Baloo2-SemiBold` before the `.ttf`/`.otf` extension.
  test('the Baloo2-SemiBold asset is bundled in the asset manifest', () async {
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);

    expect(
      manifest.listAssets().where((String a) => a.endsWith('Baloo2-SemiBold.ttf')),
      isNotEmpty,
      reason: 'Baloo2-SemiBold.ttf must be bundled; google_fonts matches it by '
          'filename through the asset manifest. If this fails, the release '
          'build silently falls back to the default Material font.',
    );
  });

  test('configureFonts disables runtime font fetching', () {
    configureFonts();

    expect(
      GoogleFonts.config.allowRuntimeFetching,
      isFalse,
      reason: 'Runtime fetching must stay off so the bundled asset is the only '
          'load path, and so the app makes no outbound request.',
    );
  });

  // ---------------------------------------------------------------------
  // MUST BE THE LAST TEST IN THIS FILE.
  // ---------------------------------------------------------------------
  // Building the app theme calls GoogleFonts.baloo2(), which resolves the
  // family and populates the process-global `_loadedFonts`. Running this
  // before the load test would make that test pass vacuously — see (3) above.
  //
  // `EnglishReflexApp.build` is invoked directly rather than pumped, so the
  // real theme from lib/main.dart is asserted (not a duplicate of it) without
  // building PracticeScreen, whose initState reaches for sqflite and
  // path_provider platform channels that do not exist under `flutter test`.
  testWidgets('the UI-SPEC typography contract still holds', (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    );

    final MaterialApp app =
        const EnglishReflexApp().build(capturedContext) as MaterialApp;
    final TextTheme textTheme = app.theme!.textTheme;

    // google_fonts returns a family string of the form `Baloo2_regular`
    // (family, underscore, variant) with the bare family as a fallback, which
    // is why these assert `contains` rather than equality.
    final TextStyle display = textTheme.displayLarge!;
    expect(display.fontSize, 32);
    expect(display.fontWeight, FontWeight.w600);
    expect(display.height, 1.3);
    expect(display.fontFamily, contains('Baloo2'));

    final TextStyle heading = textTheme.headlineSmall!;
    expect(heading.fontSize, 24);
    expect(heading.fontWeight, FontWeight.w600);
    expect(heading.height, 1.2);
    expect(heading.fontFamily, contains('Baloo2'));

    // Label and Body deliberately stay on the default Material font — Baloo 2
    // is reserved for the Display and Heading roles only (D-15, UI-SPEC).
    final TextStyle label = textTheme.labelLarge!;
    expect(label.fontSize, 18);
    expect(label.fontWeight, FontWeight.w600);
    expect(label.height, 1.2);
    expect(label.fontFamily ?? '', isNot(contains('Baloo2')));

    final TextStyle body = textTheme.bodyLarge!;
    expect(body.fontSize, 16);
    expect(body.fontWeight, FontWeight.w400);
    expect(body.height, 1.5);
    expect(body.fontFamily ?? '', isNot(contains('Baloo2')));
  });
}
