import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/practice_screen.dart';

void main() {
  runApp(const EnglishReflexApp());
}

/// The warm/playful visual system locked in the Phase 1 UI design contract
/// (`01-UI-SPEC.md`, decisions D-12/D-14). Every colour used anywhere in the app
/// comes from this table via `Theme.of(context).colorScheme` — screens never
/// hardcode a hex value.
class EnglishReflexApp extends StatelessWidget {
  const EnglishReflexApp({super.key});

  /// Dominant (60%) — warm ivory screen background.
  static const Color background = Color(0xFFFFF8F0);

  /// Secondary (30%) — soft peach question card / history rows / mascot body.
  static const Color surface = Color(0xFFFFDDB3);

  /// Accent (10%) — vibrant coral-orange. Only ever marks something tappable or
  /// actively happening (Stop button, recording pulse ring, play affordances).
  static const Color accent = Color(0xFFFF6B35);

  /// Destructive/error — warm red, not clinical pure red.
  static const Color errorRed = Color(0xFFE5484D);

  /// Text on the ivory/peach surfaces — warm dark brown, softer than black.
  static const Color textOnColor = Color(0xFF3D2B1F);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      // Brown-on-coral is 4.7:1 (white-on-coral is only 2.8:1), so the STOP
      // button label stays legible and inside the warm palette family.
      onPrimary: textOnColor,
      surface: surface,
      onSurface: textOnColor,
      error: errorRed,
    );

    return MaterialApp(
      title: 'EnglishReflex',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          foregroundColor: textOnColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          // Accent is the app bar's primary-action icon colour (UI-SPEC); the
          // back button keeps the brown foreground.
          actionsIconTheme: IconThemeData(color: accent),
        ),
        textTheme: TextTheme(
          // Display — the question prompt, the one element that must be
          // readable at arm's length (UI-01). Baloo 2, 32/600/1.3.
          displayLarge: GoogleFonts.baloo2(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: textOnColor,
          ),
          // Heading — screen titles. Baloo 2, 24/600/1.2.
          headlineSmall: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: textOnColor,
          ),
          // Label — button text and row affordances. Default Material font;
          // Baloo 2 is deliberately reserved for Display/Heading only.
          labelLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: textOnColor,
          ),
          // Body — history metadata and secondary text. Default font, 16/400/1.5.
          bodyLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: textOnColor,
          ),
        ),
      ),
      // Deliberately no `builder:` MediaQuery override here — every size above
      // must scale with the OS accessibility text-size setting (UI-01). Never
      // pin textScaler/textScaleFactor to a fixed value.
      home: const PracticeScreen(),
    );
  }
}
