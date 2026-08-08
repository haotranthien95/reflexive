import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/question_answer.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/screens/setup_screen.dart';
import 'package:englishreflex/services/audio_player_service.dart';
import 'package:englishreflex/services/recording_service.dart';
import 'package:englishreflex/state/practice_state.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:englishreflex/widgets/phase_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recorder that touches no platform channel, so the REAL loop — its
/// countdowns, its phase transitions, its write ordering — runs on the host.
class FakeRecordingService extends RecordingService {
  FakeRecordingService(this.calls);

  final List<String> calls;
  String? lastRequestedPath;
  Duration? lastMaxDuration;

  @override
  Future<void> start(
    String absoluteFilePath, {
    void Function()? onAutoStop,
    Duration? maxDuration,
    void Function(int remainingSeconds)? onTick,
  }) async {
    lastRequestedPath = absoluteFilePath;
    lastMaxDuration = maxDuration;
    calls.add('start');
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
    return lastRequestedPath;
  }

  @override
  Future<void> dispose() async {}
}

class FakeAudioPlayerService extends AudioPlayerService {
  FakeAudioPlayerService(this.calls);

  final List<String> calls;

  @override
  Future<void> play(String absoluteFilePath,
      {bool awaitCompletion = false}) async {
    calls.add('play');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// An in-memory stand-in for [DatabaseHelper] that models exactly the identity
/// rule this plan is proving: a session row is created lazily by the FIRST
/// answer, and every later answer of the same session appends to it (D-26).
///
/// It exists because real SQLite CANNOT be driven from inside a `testWidgets`
/// body: `sqflite_common_ffi`'s futures are completed by the real event loop,
/// and the fake clock this file needs for its countdowns never yields to it —
/// not even via `tester.runAsync`, which hangs outright while a `Timer.periodic`
/// countdown is live. A real-database assertion here would deadlock the run.
///
/// That split is deliberate, not a gap in coverage. This file owns the LOOP —
/// phase order, the D-20 cold-microphone window, the D-21 deadline, and the fact
/// that exactly ONE answer is written for a one-question session. The real
/// engine, its transaction boundaries and its crash-safety guarantees are owned
/// by `test/db/database_helper_test.dart`, which is a plain `test()` file with
/// no fake clock in its way and asserts against real sqflite-ffi.
class InMemoryDatabaseHelper extends DatabaseHelper {
  final List<Session> sessions = <Session>[];
  final List<QuestionAnswer> answers = <QuestionAnswer>[];

  @override
  Future<int> insertAnsweredSession({
    required String questionText,
    required String audioRelativePath,
  }) async {
    final id = sessions.length + 1;
    sessions.add(Session(id: id, createdAt: DateTime.now()));
    answers.add(
      QuestionAnswer(
        id: answers.length + 1,
        sessionId: id,
        questionText: questionText,
        audioPath: audioRelativePath,
        createdAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<List<Session>> listSessions() async => List<Session>.of(sessions);

  @override
  Future<List<QuestionAnswer>> listAnswersForSession(int sessionId) async =>
      answers.where((answer) => answer.sessionId == sessionId).toList();

  @override
  Future<Set<String>> listReferencedAudioPaths() async =>
      answers.map((answer) => answer.audioPath).toSet();

  @override
  Future<void> close() async {}
}

void main() {
  // Every test runs inside `testWidgets` because flutter_test's
  // AutomatedTestWidgetsFlutterBinding already runs the body on a fake clock:
  // a real `Timer` created here is a fake timer and `tester.pump(duration)`
  // advances it. No `fake_async` dependency is needed.
  //
  // That binding also FAILS any test that ends with a pending timer, so each
  // test below either pumps past the deadline or disposes the service.
  //
  // This is a NEW file rather than an addition to
  // `test/state/practice_state_test.dart` on purpose. That file is deliberately
  // a plain `test()` file — initialising the widget binding in it would make
  // `FlutterError.onError` fail its save-failure regression test (see its own
  // comment at the `a disposal racing the stop still saves the finished answer`
  // case). The fake clock this file needs and the un-initialised binding that
  // file needs cannot coexist, so they live apart.
  //
  // The corollary, and the one rule this file imposes on `lib/`: NOTHING on the
  // loop's hot path may await a future only the real event loop can complete.
  // The fake clock advances timers and drains microtasks; it never pumps the
  // real event loop, so such an await parks the phase machine forever. That is
  // why `ensureRecordingsDir` checks existence synchronously and why the
  // database here is [InMemoryDatabaseHelper] rather than sqflite-ffi.

  late Directory tempDir;
  late InMemoryDatabaseHelper databaseHelper;
  late List<String> calls;
  late FakeRecordingService recordingService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_session');
    // Pre-created so the loop's sync `ensureRecordingsDir()` is a single stat.
    Directory('${tempDir.path}/$kRecordingsDirName').createSync(recursive: true);
    documentsDirProvider = () async => tempDir;
    databaseHelper = InMemoryDatabaseHelper();
    calls = <String>[];
    recordingService = FakeRecordingService(calls);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Drives the loop's non-timer async work to completion.
  ///
  /// A ZERO-duration `pump()` is the tool, repeated. Each one drains the fake
  /// zone's microtask queue, which is where every `await` continuation inside
  /// `PracticeState` is parked; the arm → record → stop → save path is a chain
  /// of several such awaits, so one pump is not enough. The duration stays zero
  /// so no countdown under test advances behind an assertion.
  ///
  /// Deliberately NOT `tester.runAsync`: this loop always has a live
  /// `Timer.periodic`, and the binding's fake-async/real-async reconciliation
  /// never returns while one is pending — the whole run hangs with no output.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(Duration.zero);
    }
  }

  testWidgets('Setup → configured session → one committed answer → completion',
      (tester) async {
    // A phone-shaped portrait surface. The default test window is 800x600
    // landscape, on which the practice screen's centred STOP circle lands
    // exactly on the bottom edge and `tap()` misses it — a layout artefact of
    // the test surface, not of the screen. Every layout this app ships is
    // portrait.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: SetupScreen(
          databaseHelper: databaseHelper,
          recordingService: recordingService,
          audioPlayerService: FakeAudioPlayerService(calls),
        ),
      ),
    );
    await settle(tester);

    // SETUP-07: Start is genuinely inert until a topic is checked (D-19).
    final startButton = find.byKey(const Key('setup-start'));
    expect(
      tester.widget<FilledButton>(startButton).onPressed,
      isNull,
      reason: 'START SESSION must be disabled with zero topics checked',
    );
    expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);

    await tester.tap(find.byKey(const Key('setup-topic-Daily life')));
    await tester.pump();

    expect(
      tester.widget<FilledButton>(startButton).onPressed,
      isNotNull,
      reason: 'checking one topic must enable START SESSION',
    );
    expect(find.byKey(const Key('setup-start-blocked')), findsNothing);

    await tester.tap(startButton);
    await tester.pump();
    // Half a second: long enough for the push transition to finish, short
    // enough that the get-ready countdown has not ticked yet. Deliberately NOT
    // `pumpAndSettle()` — a `Timer.periodic` keeps scheduling frames, so a
    // countdown phase never settles and that call would run to its timeout.
    await tester.pump(const Duration(milliseconds: 500));

    // LOOP-01: the session opens on the 3·2·1, question card hidden (D-22).
    expect(find.byKey(const Key('practice-countdown-glyph')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Get ready…'), findsOneWidget);
    expect(find.text(kQuestionsFirstPrompt), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);

    // The tick that reaches 0 hands straight over to the `t` countdown, so the
    // numeral 0 is never rendered.
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(kPhaseControlKeys[PracticePhase.reading]!),
      findsOneWidget,
    );
    expect(find.byKey(const Key('practice-countdown-glyph')), findsNothing);
    expect(find.text(kQuestionsFirstPrompt), findsOneWidget);

    // LOOP-02 / D-20: the microphone stays cold for the WHOLE `t` countdown.
    // `t` is the Setup default of 5 s, so this lands at t-1.
    await tester.pump(const Duration(seconds: 4));
    expect(
      calls,
      isEmpty,
      reason: 'the recorder was armed before the t countdown reached 0',
    );
    expect(
      find.byKey(kPhaseControlKeys[PracticePhase.reading]!),
      findsOneWidget,
    );

    // The final second: `reading` hands over to `arming`, which arms the
    // recorder exactly once.
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(calls, ['start']);
    expect(
      recordingService.lastMaxDuration,
      const Duration(seconds: kDefaultAnswerSeconds),
      reason: 'the deadline must be the session `d`, not the Phase 1 fixed 60 s',
    );

    // D-21: the readout is derived from the same `d` the deadline uses.
    expect(
      find.byKey(kPhaseControlKeys[PracticePhase.recording]!),
      findsOneWidget,
    );
    expect(find.text('1:00 left'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(kPhaseControlKeys[PracticePhase.recording]!),
        matching: find.byType(FilledButton),
      ),
    );
    await settle(tester);

    // D-26/D-27: exactly one session row holding exactly one answer, and the
    // completion state on screen.
    final sessions = await databaseHelper.listSessions();
    expect(sessions, hasLength(1));
    final savedAnswers =
        await databaseHelper.listAnswersForSession(sessions.single.id!);
    expect(savedAnswers, hasLength(1));
    expect(savedAnswers.single.questionText, kQuestionsFirstPrompt);
    expect(savedAnswers.single.audioPath, startsWith('$kRecordingsDirName/'));

    expect(find.byKey(const Key('practice-complete')), findsOneWidget);
    expect(find.text('Nice work!'), findsOneWidget);
    expect(find.text('1 answer recorded.'), findsOneWidget);
    expect(find.text('Session complete'), findsOneWidget);
    expect(calls, ['start', 'stop']);
  });
}

/// The first prompt of the placeholder bank — the one a sequential draw at
/// question 1 must produce (D-23).
const String kQuestionsFirstPrompt = 'What did you do this morning?';
