import 'package:flutter/material.dart';

/// The `t` countdown's anchor-slot surface: a 96px determinate ring with the
/// remaining seconds inside (LOOP-02).
///
/// **Why it must be DETERMINATE.** A `CircularProgressIndicator` with a null
/// `value` animates forever, and a forever-animating widget makes any test that
/// waits for the tree to settle hang outright — which is also why this class
/// computes an elapsed fraction rather than accepting a nullable one. The value
/// is never null, by construction, at any point in the countdown.
///
/// **Why it lives in a 144px box.** That is the exact box [Mascot] occupies, and
/// the `reading` phase swaps this widget in for the mascot in the same slot
/// (D-22). Matching the outer box is what makes that swap cost ZERO layout
/// shift — the ring itself is 96px and simply sits centred inside it.
///
/// The ring is the *only* place the `t` countdown appears: the question card is
/// visible and dominant beside it, which is what makes this unmistakable from
/// the 3·2·1, whose 128px numeral takes the focus slot with no question at all.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  /// Seconds still to run — the number rendered inside the ring.
  final int remainingSeconds;

  /// The countdown's full length, the denominator of the elapsed arc.
  final int totalSeconds;

  /// The mascot's anchor box (`lib/widgets/mascot.dart`). Changing one without
  /// the other reintroduces the layout jump this pairing exists to prevent.
  static const double _anchorBox = 144;

  /// UI-SPEC spacing exception: a visual anchor, not a tap target.
  static const double _diameter = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Defensive rather than decorative: `t` has a floor of 3 s (D-16) so these
    // clamps never fire in a real session, but a zero denominator here would be
    // a NaN arc and a division by zero is not a rendering strategy.
    final int total = totalSeconds < 1 ? 1 : totalSeconds;
    final int remaining = remainingSeconds.clamp(0, total);
    final double elapsedFraction = (total - remaining) / total;

    return SizedBox(
      key: const Key('practice-countdown-ring'),
      width: _anchorBox,
      height: _anchorBox,
      child: Center(
        child: SizedBox(
          width: _diameter,
          height: _diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  // Never null — see the class doc.
                  value: elapsedFraction,
                  strokeWidth: 8,
                  // Coral elapsed arc on the peach track, both from the single
                  // palette. No literal colour appears in this file.
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surface,
                ),
              ),
              Padding(
                // Keeps the numeral clear of the 8px stroke.
                padding: const EdgeInsets.all(16), // md
                child: FittedBox(
                  // The two-digit worst case (`t` = 30) at the largest OS
                  // text-scale setting scales down rather than clipping — the
                  // same containment the 96px STOP label uses.
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$remaining',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
