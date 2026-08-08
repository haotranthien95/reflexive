import 'package:flutter/material.dart';

import 'screens/practice_screen.dart';

void main() {
  runApp(const EnglishReflexApp());
}

class EnglishReflexApp extends StatelessWidget {
  const EnglishReflexApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Theming (warm palette, rounded shapes, friendly display font) lands in
    // Plan 2 — this plan only needs the app to build and run.
    return const MaterialApp(
      title: 'EnglishReflex',
      home: PracticeScreen(),
    );
  }
}
