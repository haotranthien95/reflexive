import 'dart:io';

import 'package:englishreflex/models/session_config.dart';
import 'package:englishreflex/screens/practice_screen.dart';
import 'package:englishreflex/services/recording_service.dart';
import 'package:englishreflex/services/screen_wake_controller.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The loop doubles live in the session test, which owns them and documents WHY
// each one has the shape it has (why the database must be in-memory under a
// fake clock, why the recorder backend rather than the service is faked). They
// are imported with an explicit `show` rather than copied: a second copy of
// `InMemoryDatabaseHelper` would be a second model of the D-26 lazy-session
// rule, free to drift from the one the loop is actually tested against.
import '../fixtures/questions.dart';
import '../state/practice_session_test.dart'
    show FakeAudioPlayerService, FakeRecorderBackend, InMemoryDatabaseHelper;
import '../services/screen_wake_controller_test.dart'
    show FakeScreenWakeController;

/// A route to pop BACK to.
///
/// Every case here is about leaving a session, so the session must sit on a
/// pushed route with something underneath it — popping the only route of a
/// Navigator is not the thing the user does, and would not prove the D-26 "pops
/// straight back to Setup" behaviour at all.
class _SetupStub extends StatelessWidget {
  const _SetupStub({required this.session});

  final Widget session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => session),
            ),
            child: const Text('OPEN SESSION'),
          ),
        ),
      ),
    );
  }
}

void main() {
  late Directory tempDir;
  late InMemoryDatabaseHelper databaseHelper;
  late List<String> calls;
  late FakeRecorderBackend backend;
  late RecordingService recordingService;
  late FakeScreenWakeController wake;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_practice');
    Directory('${tempDir.path}/$kRecordingsDirName').createSync(recursive: true);
    documentsDirProvider = () async => tempDir;
    databaseHelper = InMemoryDatabaseHelper();
    calls = <String>[];
    backend = FakeRecorderBackend();
    recordingService = RecordingService(backend: backend);
    wake = FakeScreenWakeController();
  });

  tearDown(() async {
    // Deliberately NOT `await recordingService.dispose()`. That closes the
    // backend's broadcast `onPausedChanged` controller, whose done event is
    // delivered in the zone the screen's subscription was registered in — the
    // test body's FAKE-async zone, which nobody is pumping any more by the time
    // `tearDown` runs. The await then never returns and the whole suite stalls
    // silently. This joins the file-level list of things that cannot be awaited
    // across the fake clock.
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const SessionConfig config = SessionConfig(
    topics: <String>['Daily life'],
    level: 'B1',
    questionCount: 3,
    thinkingSeconds: 3,
    answerSeconds: 5,
    autoReplay: false,
  );

  /// Drives the loop's non-timer async work to completion. A ZERO-duration
  /// pump drains the fake zone's microtask queue, which is where every `await`
  /// inside `PracticeState` and `_requestStop` is parked; the duration stays
  /// zero so no countdown under test advances behind an assertion.
  ///
  /// Never `pumpAndSettle`: a live `Timer.periodic` keeps scheduling frames, so
  /// a settle-until-idle pump would run to its timeout.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(Duration.zero);
    }
  }

  /// Opens the session on a pushed route, phone-shaped and portrait — the
  /// default 800×600 landscape test window puts the centred STOP circle exactly
  /// on the bottom edge, where `tap()` misses it.
  Future<void> openSession(
    WidgetTester tester, {
    SessionConfig sessionConfig = config,
    ScreenWakeController? wakeController,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: _SetupStub(
          session: PracticeScreen(
            questions: kFixtureQuestions,
            config: sessionConfig,
            recordingService: recordingService,
            audioPlayerService: FakeAudioPlayerService(calls),
            databaseHelper: databaseHelper,
            screenWakeController: wakeController ?? wake,
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN SESSION'));
    await tester.pump();
    // Long enough for the push transition, short enough that the get-ready
    // countdown has not ticked.
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Runs ONE whole question to a committed answer: the 3·2·1, the `t`
  /// countdown, the arming handover, then the `d` deadline's auto-stop.
  Future<void> answerOneQuestion(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3)); // the 3·2·1
    await tester.pump(Duration(seconds: config.thinkingSeconds));
    await settle(tester);
    await tester.pump(Duration(seconds: config.answerSeconds));
    await settle(tester);
  }

  /// Taps the app-bar Stop and lets the dialog build.
  Future<void> tapStop(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('practice-stop-action')));
    await settle(tester);
    // The dialog's own transition. Safe to advance real time here: the session
    // is already frozen behind it (D-25), so no clock moves.
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Tears the screen down so no countdown outlives the test — the binding
  /// fails any test that ends with a pending timer.
  Future<void> closeSession(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('the one confirmation dialog (CTRL-03 / E11)', () {
    testWidgets('N = 0 — the planner-resolved body, and confirming pops '
        'straight to Setup having written nothing', (tester) async {
      await openSession(tester);
      await tapStop(tester);

      expect(find.text('End this session?'), findsOneWidget);
      // The branch the Copywriting Contract left unspecified (E11/empty).
      expect(find.text('Nothing has been recorded yet.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice-stop-confirm')));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('OPEN SESSION'), findsOneWidget,
          reason: 'D-26: with nothing written there is nothing to view');
      expect(find.text('Nice work!'), findsNothing,
          reason: 'a zero-answer stop must NOT show a completion screen');
      expect(await databaseHelper.listSessions(), isEmpty,
          reason: 'a session abandoned before its first answer writes NOTHING');

      await closeSession(tester);
    });

    testWidgets('N = 1 — the singular body, verbatim from the Copywriting '
        'Contract', (tester) async {
      await openSession(tester);
      await answerOneQuestion(tester);
      await tapStop(tester);

      expect(
        find.text(
            "Your 1 answer is already saved — you just won't finish the rest."),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('practice-stop-cancel')));
      await settle(tester);
      await closeSession(tester);
    });

    testWidgets('N >= 2 — the plural body, and confirming shows the completion '
        'state naming both answers', (tester) async {
      await openSession(tester);
      await answerOneQuestion(tester);
      await answerOneQuestion(tester);
      await tapStop(tester);

      expect(
        find.text("Your 2 answers are already saved — "
            "you just won't finish the rest."),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('practice-stop-confirm')));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      // D-27: a session stopped early reaches exactly the state a finished one
      // does — only the number differs, and nothing frames it as a failure.
      expect(find.text('Nice work!'), findsOneWidget);
      expect(find.text('2 answers recorded.'), findsOneWidget);
      expect(find.text('Session complete'), findsOneWidget);
      expect(find.text('OPEN SESSION'), findsNothing,
          reason: 'with answers to view the session must NOT pop to Setup');

      await closeSession(tester);
    });

    testWidgets('the session FREEZES behind the dialog, and the safe action '
        'resumes it from exactly where it stopped (D-25)', (tester) async {
      await openSession(tester);
      // Two seconds into the 3·2·1, so the frozen numeral below is a value the
      // countdown genuinely stopped on rather than its initial one.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('1'), findsOneWidget);

      await tapStop(tester);
      expect(find.byType(AlertDialog), findsOneWidget);

      // Sixty times what is left of the countdown, all of it behind the dialog.
      await tester.pump(const Duration(seconds: 60));
      expect(find.text('1'), findsOneWidget,
          reason: 'a clock ran while the user was deciding');
      expect(find.text(kFixtureFirstPrompt), findsNothing,
          reason: 'the frozen countdown advanced into the question');

      await tester.tap(find.byKey(const Key('practice-stop-cancel')));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsNothing);

      // …and it continues rather than restarting.
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text(kFixtureFirstPrompt), findsOneWidget,
          reason: 'the countdown did not continue after the dialog closed');

      await closeSession(tester);
    });

    testWidgets('a barrier tap is treated identically to the safe action',
        (tester) async {
      await openSession(tester);
      await tester.pump(const Duration(seconds: 2));
      await tapStop(tester);

      // The barrier: anywhere outside the dialog. It returns `null`, and there
      // is exactly ONE destructive path — it always requires the explicit tap.
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('OPEN SESSION'), findsNothing,
          reason: 'a barrier tap ENDED the session');
      expect(find.byKey(const Key('practice-paused-banner')), findsNothing,
          reason: 'a dismissed dialog must leave the session running');

      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text(kFixtureFirstPrompt), findsOneWidget);

      await closeSession(tester);
    });
  });

  group('back is the SAME path, not a second one (D-29)', () {
    testWidgets('a system back gesture during a session opens the one dialog '
        'rather than popping', (tester) async {
      await openSession(tester);
      await tester.pump(const Duration(seconds: 1));

      // The real system back signal, not `Navigator.pop`: this is what
      // `PopScope` intercepts, so it is the only thing that proves the
      // interception rather than assuming it.
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('End this session?'), findsOneWidget,
          reason: 'back must converge on the Stop dialog, not a second path');
      expect(find.text('OPEN SESSION'), findsNothing,
          reason: 'back popped the session without confirming');

      // A back gesture while the dialog is open closes ONLY the dialog…
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('OPEN SESSION'), findsNothing);

      // …and the re-entrancy guard released, so Stop still works afterwards and
      // still opens exactly ONE dialog.
      await tapStop(tester);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice-stop-cancel')));
      await settle(tester);
      await closeSession(tester);
    });

    testWidgets('interception is RELEASED in the completion state, where back '
        'pops to Setup', (tester) async {
      await openSession(tester);
      for (var i = 0; i < config.questionCount; i++) {
        await answerOneQuestion(tester);
      }
      expect(find.text('Session complete'), findsOneWidget);

      // The back arrow reappears in this state, so the tester's own page-back
      // helper — which taps that arrow — is what the user has here.
      await tester.pageBack();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('OPEN SESSION'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'a finished session must not ask for confirmation');

      await closeSession(tester);
    });
  });

  group('the wakelock is held for the session and released with it (D-30)', () {
    testWidgets('enabled on entry, released when the session completes',
        (tester) async {
      await openSession(tester);
      expect(wake.calls, <String>['enable']);

      for (var i = 0; i < config.questionCount; i++) {
        await answerOneQuestion(tester);
      }
      expect(find.text('Session complete'), findsOneWidget);
      expect(wake.calls, <String>['enable', 'disable'],
          reason: 'the hold must end with the session, not with the route');

      await closeSession(tester);
      expect(wake.calls.where((c) => c == 'disable'), hasLength(1),
          reason: 'an already-released hold must not be released twice');
    });

    testWidgets('released when the screen is disposed', (tester) async {
      await openSession(tester);
      expect(wake.calls, <String>['enable']);

      await closeSession(tester);

      expect(wake.calls, contains('disable'));
    });

    testWidgets('released when the app is backgrounded', (tester) async {
      await openSession(tester);
      await tester.pump(const Duration(seconds: 1));

      // The legal chain: AppLifecycleListener asserts on illegal transitions,
      // and `flutter test` runs with asserts live.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle(tester);

      expect(wake.calls, contains('disable'));

      await closeSession(tester);
    });

    testWidgets('an enable() that throws is silent — no banner, no user-facing '
        'text, and the session runs regardless', (tester) async {
      final throwing = FakeScreenWakeController()..throwOnEnable = true;
      await openSession(tester, wakeController: throwing);

      expect(throwing.calls, contains('enable'));
      expect(find.byKey(const Key('practice-error-banner')), findsNothing);
      expect(find.textContaining('wakelock'), findsNothing);
      expect(find.textContaining('screen'), findsNothing);

      // The loop is entirely unaffected.
      await answerOneQuestion(tester);
      expect(await databaseHelper.listSessions(), hasLength(1));

      await closeSession(tester);
    });
  });
}
