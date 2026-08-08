import 'package:englishreflex/widgets/mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pulse ring is the one piece of the mascot with a behavioural contract:
/// it must be present ONLY while a recording is actively in progress, because
/// it is the user's sole "the mic is live" signal (D-04 leaves no timer on the
/// screen). Everything else about the mascot is a visual judgment left to UAT.
void main() {
  const pulseRing = Key('mascot-pulse-ring');

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('idle mascot builds and shows no pulse ring', (tester) async {
    await tester.pumpWidget(wrap(const Mascot()));

    expect(find.byType(Mascot), findsOneWidget);
    expect(find.byKey(pulseRing), findsNothing);
  });

  testWidgets('recording mascot builds and shows the pulse ring',
      (tester) async {
    await tester.pumpWidget(wrap(const Mascot(isRecording: true)));
    // Advance the repeating pulse without settling (it never settles).
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(pulseRing), findsOneWidget);
  });

  testWidgets('the ring follows isRecording as it toggles', (tester) async {
    await tester.pumpWidget(wrap(const Mascot()));
    expect(find.byKey(pulseRing), findsNothing);

    await tester.pumpWidget(wrap(const Mascot(isRecording: true)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(pulseRing), findsOneWidget);

    // Stop fires: the ring must disappear immediately, not linger.
    await tester.pumpWidget(wrap(const Mascot()));
    await tester.pump();
    expect(find.byKey(pulseRing), findsNothing);
  });

  testWidgets('error variant builds and shows no pulse ring', (tester) async {
    await tester.pumpWidget(wrap(const Mascot(isError: true)));

    expect(find.byType(Mascot), findsOneWidget);
    expect(find.byKey(pulseRing), findsNothing);
  });
}
