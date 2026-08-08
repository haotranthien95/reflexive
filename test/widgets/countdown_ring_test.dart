import 'package:englishreflex/widgets/countdown_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts a [CountdownRing] in the smallest tree that gives it a [Theme],
/// optionally under an OS text-scale setting.
Widget _host({
  required int remainingSeconds,
  required int totalSeconds,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: CountdownRing(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the remaining seconds inside the ring', (tester) async {
    await tester.pumpWidget(_host(remainingSeconds: 4, totalSeconds: 5));

    expect(find.text('4'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the indicator is DETERMINATE at every point in the countdown',
      (tester) async {
    // A null `value` animates forever, which makes any test that waits for the
    // tree to settle hang. This is the assertion that keeps that from ever
    // silently returning — checked at both ends and in the middle.
    for (final int remaining in <int>[5, 3, 0]) {
      await tester.pumpWidget(
        _host(remainingSeconds: remaining, totalSeconds: 5),
      );

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, isNotNull, reason: 'remaining=$remaining');
      // The arc shows ELAPSED progress, so it grows as the countdown shrinks.
      expect(indicator.value, closeTo((5 - remaining) / 5, 0.0001));
    }
  });

  testWidgets('the ring occupies exactly the mascot anchor box, even at a text '
      'scale of 2.0', (tester) async {
    // Same 144x144 box `Mascot` occupies. The `reading` phase swaps one for the
    // other in the anchor slot, and any size difference here would show up as a
    // layout jump on every question.
    await tester.pumpWidget(_host(remainingSeconds: 4, totalSeconds: 5));
    expect(tester.getSize(find.byType(CountdownRing)), const Size(144, 144));

    await tester.pumpWidget(
      // The two-digit worst case (`t` = 30, SETUP-04's ceiling) at the largest
      // OS text-scale setting — the numeral scales DOWN rather than pushing the
      // box out or clipping.
      _host(remainingSeconds: 30, totalSeconds: 30, textScale: 2.0),
    );
    expect(tester.getSize(find.byType(CountdownRing)), const Size(144, 144));
    expect(find.text('30'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow at 2.0');
  });

  testWidgets('a zero total does not produce a NaN arc', (tester) async {
    // Unreachable in a real session (`t` floors at 3 s, D-16) but a division by
    // zero is not a rendering strategy.
    await tester.pumpWidget(_host(remainingSeconds: 0, totalSeconds: 0));

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNotNull);
    expect(indicator.value!.isNaN, isFalse);
  });
}
