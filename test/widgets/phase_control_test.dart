import 'package:englishreflex/state/practice_state.dart';
import 'package:englishreflex/widgets/phase_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts a [PhaseControl] in the smallest tree that gives it a [Theme].
Widget _host(
  PracticePhase phase, {
  VoidCallback? onStop,
  VoidCallback? onStart,
  int? recordingSecondsRemaining,
  VoidCallback? onViewSession,
  VoidCallback? onBackToSetup,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: PhaseControl(
          phase: phase,
          onStop: onStop ?? () {},
          onStart: onStart ?? () {},
          recordingSecondsRemaining: recordingSecondsRemaining,
          // Defaulted to no-ops so the totality loop below — which pumps EVERY
          // phase through this helper — never hands the completion control a
          // null it would render as a disabled dead end.
          onViewSession: onViewSession ?? () {},
          onBackToSetup: onBackToSetup ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  test('kPhaseControlKeys is total over PracticePhase.values', () {
    expect(
      kPhaseControlKeys.length,
      PracticePhase.values.length,
      reason: 'every phase must map to exactly one control key',
    );
    for (final phase in PracticePhase.values) {
      expect(
        kPhaseControlKeys.containsKey(phase),
        isTrue,
        reason: '$phase has no entry in kPhaseControlKeys',
      );
    }
  });

  testWidgets('every PracticePhase renders exactly one keyed control',
      (tester) async {
    // This is the test that fails the moment a future phase is added without a
    // control — the mechanical guard against a screen with no way forward.
    for (final phase in PracticePhase.values) {
      await tester.pumpWidget(_host(phase));
      expect(
        find.byKey(kPhaseControlKeys[phase]!),
        findsOneWidget,
        reason: '$phase rendered no keyed control',
      );
    }
  });

  testWidgets('the idle control is labelled "Try again"', (tester) async {
    await tester.pumpWidget(_host(PracticePhase.idle));

    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('no phase renders a START control', (tester) async {
    // The UI-SPEC Copywriting Contract states no Start button exists in this
    // phase (D-01: recording begins automatically), so the recovery affordance
    // is worded "Try again" instead.
    for (final phase in PracticePhase.values) {
      await tester.pumpWidget(_host(phase));
      expect(find.text('START'), findsNothing, reason: '$phase rendered START');
    }
  });

  testWidgets('the recording control invokes onStop and the idle control '
      'invokes onStart', (tester) async {
    var stops = 0;
    var starts = 0;

    await tester.pumpWidget(
      _host(
        PracticePhase.recording,
        onStop: () => stops++,
        onStart: () => starts++,
      ),
    );
    await tester.tap(find.byKey(kPhaseControlKeys[PracticePhase.recording]!));
    await tester.pump();
    expect(stops, 1);
    expect(starts, 0);

    await tester.pumpWidget(
      _host(
        PracticePhase.idle,
        onStop: () => stops++,
        onStart: () => starts++,
      ),
    );
    await tester.tap(find.byKey(kPhaseControlKeys[PracticePhase.idle]!));
    await tester.pump();
    expect(starts, 1);
    expect(stops, 1);
  });
}
