import 'dart:async';
import 'dart:io';

import 'package:englishreflex/data/questions.dart';
import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/question_answer.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/models/session_config.dart';
import 'package:englishreflex/screens/setup_screen.dart';
import 'package:englishreflex/services/audio_player_service.dart';
import 'package:englishreflex/services/recording_service.dart';
import 'package:englishreflex/state/practice_state.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:englishreflex/widgets/phase_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

/// Records every `play` call, and — when handed a [databaseHelper] — snapshots
/// how many session rows already existed at the moment playback started.
///
/// That snapshot is the whole of the commit-happens-before-replay guard
/// (D-08/D-10). It lived in `test/state/practice_state_test.dart` through Phase
/// 1; plan 02-01 removed the replay from `stopRecording()`'s tail, which left it
/// measuring a replay that no longer ran, and pointed it here. This plan
/// restores the replay under `config.autoReplay`, so the guard is genuine again
/// and lives where the replay now happens.
class FakeAudioPlayerService extends AudioPlayerService {
  FakeAudioPlayerService(this.calls, {this.databaseHelper});

  final List<String> calls;
  final DatabaseHelper? databaseHelper;

  /// Sessions already committed when `play` was FIRST invoked. 1 is the only
  /// correct value — the answer being replayed must already be on disk.
  int? sessionsAtFirstPlay;

  /// Simulates the player failing on an already-saved answer.
  bool throwOnPlay = false;

  /// The bound the loop asked for, so a test can prove it is derived from the
  /// session's `d` rather than the fixed Phase 1 ceiling.
  Duration? lastCompletionTimeout;

  @override
  Future<void> play(String absoluteFilePath,
      {bool awaitCompletion = false, Duration? completionTimeout}) async {
    calls.add('play');
    lastCompletionTimeout = completionTimeout;
    final DatabaseHelper? helper = databaseHelper;
    if (helper != null) {
      sessionsAtFirstPlay ??= (await helper.listSessions()).length;
    }
    // Thrown AFTER the snapshot so a throwing player still proves the ordering.
    if (throwOnPlay) throw StateError('playback failed');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// An [InMemoryDatabaseHelper] whose Nth `appendAnswer` throws, standing in for
/// a full disk at the exact moment of a save.
class FailingAtDatabaseHelper extends InMemoryDatabaseHelper {
  FailingAtDatabaseHelper({required this.failOnCall});

  /// 1-based index of the `appendAnswer` call that fails.
  final int failOnCall;

  int appendCalls = 0;

  @override
  Future<int> appendAnswer({
    int? sessionId,
    required String questionText,
    required String audioRelativePath,
  }) async {
    appendCalls += 1;
    if (appendCalls == failOnCall) {
      throw StateError('the database is full');
    }
    return super.appendAnswer(
      sessionId: sessionId,
      questionText: questionText,
      audioRelativePath: audioRelativePath,
    );
  }
}

/// Deduplicated record of every phase the loop passed through, plus what the
/// two counters read AT THE MOMENT each phase was entered.
///
/// Capturing all three together is what makes the counter-drift assertions
/// possible: `questionNumber` and `answeredCount` disagree for the whole of
/// every question, and the only way to prove each moves at the right instant is
/// to read them at a phase boundary rather than at the end.
class PhaseLog {
  PhaseLog(this._state) {
    _state.addListener(_onChange);
  }

  final PracticeState _state;

  final List<PracticePhase> phases = <PracticePhase>[];
  final List<int> questionNumbers = <int>[];
  final List<int> answeredCounts = <int>[];

  void _onChange() {
    if (phases.isNotEmpty && phases.last == _state.phase) return;
    phases.add(_state.phase);
    questionNumbers.add(_state.questionNumber);
    answeredCounts.add(_state.answeredCount);
  }

  /// The counters as they read when [phase] was entered for the
  /// [occurrence]-th time (1-based).
  int questionNumberAt(PracticePhase phase, int occurrence) =>
      questionNumbers[_indexOf(phase, occurrence)];

  int answeredCountAt(PracticePhase phase, int occurrence) =>
      answeredCounts[_indexOf(phase, occurrence)];

  int countOf(PracticePhase phase) => phases.where((p) => p == phase).length;

  int _indexOf(PracticePhase phase, int occurrence) {
    var seen = 0;
    for (var i = 0; i < phases.length; i++) {
      if (phases[i] != phase) continue;
      seen += 1;
      if (seen == occurrence) return i;
    }
    throw StateError('$phase was entered fewer than $occurrence times: $phases');
  }
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

  /// Overrides [DatabaseHelper.appendAnswer] — the single transaction-owning
  /// writer the loop actually calls (D-26) — so this double models the same
  /// lazy-session-creation rule the real one enforces.
  @override
  Future<int> appendAnswer({
    int? sessionId,
    required String questionText,
    required String audioRelativePath,
  }) async {
    final int id;
    if (sessionId == null) {
      id = sessions.length + 1;
      sessions.add(Session(id: id, createdAt: DateTime.now()));
    } else {
      id = sessionId;
    }
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

  testWidgets(
      'Setup → configured session → one committed answer → the next question',
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
    // enough that the get-ready countdown has not ticked yet. Every pump in
    // this file carries an EXPLICIT duration, and none waits for the tree to go
    // idle — a `Timer.periodic` keeps scheduling frames, so a countdown phase
    // never reaches idle and a settle-until-idle pump would run to its timeout.
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

    // D-26: exactly one session row holding exactly one answer.
    final sessions = await databaseHelper.listSessions();
    expect(sessions, hasLength(1));
    final savedAnswers =
        await databaseHelper.listAnswersForSession(sessions.single.id!);
    expect(savedAnswers, hasLength(1));
    expect(savedAnswers.single.questionText, kQuestionsFirstPrompt);
    expect(savedAnswers.single.audioPath, startsWith('$kRecordingsDirName/'));

    // RETARGETED BY PLAN 02-02. Plan 02-01's tracer ended the session on the
    // first committed answer because there was no loop yet; this plan closes the
    // loop, so the SAME tap now replays (Setup's `r` defaults ON) and counts
    // into question 2 of the default 10. Asserting completion here would be
    // asserting the tracer's stub, not the product.
    expect(calls, ['start', 'stop', 'play']);
    expect(find.byKey(const Key('practice-complete')), findsNothing);
    expect(find.text('Session complete'), findsNothing);

    // LOOP-07 on screen: `k` names the question the countdown counts INTO, and
    // the question card is hidden again behind the 3·2·1 (D-22).
    expect(find.text('Question 2 of $kDefaultQuestionCount'), findsOneWidget);
    expect(
      find.byKey(kPhaseControlKeys[PracticePhase.getReady]!),
      findsOneWidget,
    );
    expect(find.byKey(const Key('practice-countdown-glyph')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(kQuestionsFirstPrompt), findsNothing);

    // Tear the screen down: the inter-question countdown is LIVE, and the test
    // binding fails any test that ends with a pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  // ───────────────────────────────────────────────────────────────────────────
  // The loop itself, driven directly against `PracticeState`.
  //
  // Still `testWidgets`, and for the same single reason the tracer above is:
  // the fake clock. `PracticeState` is nothing but countdowns, and only this
  // binding's clock can advance them. There is no widget tree in these cases —
  // `tester.pump(duration)` drives the timers, not a build.
  // ───────────────────────────────────────────────────────────────────────────

  SessionConfig configFor({
    int questionCount = 1,
    int thinkingSeconds = 3,
    int answerSeconds = 10,
    bool autoReplay = false,
  }) {
    return SessionConfig(
      topics: const <String>['Daily life'],
      level: 'B1',
      questionCount: questionCount,
      // The D-16 floor. Deliberately the shortest legal `t`: these cases are
      // about the loop's ORDER, and every extra second is only pumping.
      thinkingSeconds: thinkingSeconds,
      answerSeconds: answerSeconds,
      autoReplay: autoReplay,
    );
  }

  PracticeState newState({
    required SessionConfig config,
    DatabaseHelper? helper,
    FakeAudioPlayerService? player,
  }) {
    return PracticeState(
      recordingService: recordingService,
      audioPlayerService: player ?? FakeAudioPlayerService(calls),
      databaseHelper: helper ?? databaseHelper,
      config: config,
    );
  }

  /// Runs ONE whole question: the 3·2·1 already armed, the `t` countdown, the
  /// arming handover, and a manual stop through to the commit (and the replay,
  /// when the session asked for one).
  ///
  /// It assumes the loop is sitting on an armed get-ready countdown — which is
  /// exactly the state both `startSession()` and the previous question's commit
  /// leave it in. That single precondition is the loop's shape.
  Future<void> answerOneQuestion(
    WidgetTester tester,
    PracticeState state,
  ) async {
    await tester.pump(const Duration(seconds: kGetReadySeconds));
    await tester.pump(Duration(seconds: state.config.thinkingSeconds));
    await settle(tester);
    unawaited(state.stopRecording());
    await settle(tester);
  }

  /// The deduplicated phase order of ONE question that ends the session.
  List<PracticePhase> cycleEndingIn(PracticePhase last, {required bool replay}) {
    return <PracticePhase>[
      PracticePhase.getReady,
      PracticePhase.reading,
      PracticePhase.arming,
      PracticePhase.recording,
      PracticePhase.saving,
      if (replay) PracticePhase.replaying,
      last,
    ];
  }

  testWidgets('1 — with r ON a committed answer replays, then counts into the '
      'next question', (tester) async {
    final state = newState(config: configFor(questionCount: 2, autoReplay: true));
    final log = PhaseLog(state);

    await state.startSession();
    await answerOneQuestion(tester, state);
    await answerOneQuestion(tester, state);

    expect(
      log.phases,
      <PracticePhase>[
        ...cycleEndingIn(PracticePhase.getReady, replay: true),
        // The second question reuses the get-ready the first one entered, so
        // its own cycle starts at `reading`.
        PracticePhase.reading,
        PracticePhase.arming,
        PracticePhase.recording,
        PracticePhase.saving,
        PracticePhase.replaying,
        PracticePhase.complete,
      ],
    );
    // LOOP-07/adjacency: get-ready is entered only once the replay has resolved,
    // so the two are never concurrent.
    expect(
      log.phases.indexOf(PracticePhase.replaying) <
          log.phases.lastIndexOf(PracticePhase.getReady),
      isTrue,
    );

    state.dispose();
  });

  testWidgets('2 — with r OFF the player is never touched and get-ready follows '
      'the commit directly', (tester) async {
    final state = newState(config: configFor(questionCount: 2));
    final log = PhaseLog(state);

    await state.startSession();
    await answerOneQuestion(tester, state);
    await answerOneQuestion(tester, state);

    // SETUP-06: not "called and ignored" — not called at all.
    expect(calls, isNot(contains('play')));
    expect(log.countOf(PracticePhase.replaying), 0);
    expect(
      log.phases,
      <PracticePhase>[
        ...cycleEndingIn(PracticePhase.getReady, replay: false),
        PracticePhase.reading,
        PracticePhase.arming,
        PracticePhase.recording,
        PracticePhase.saving,
        PracticePhase.complete,
      ],
    );

    state.dispose();
  });

  testWidgets('3 — a three-question session runs three cycles and lands in '
      'complete with three rows under one session', (tester) async {
    final state = newState(config: configFor(questionCount: 3));

    await state.startSession();
    for (var i = 0; i < 3; i++) {
      await answerOneQuestion(tester, state);
    }

    expect(state.phase, PracticePhase.complete);
    expect(state.answeredCount, 3);

    final sessions = await databaseHelper.listSessions();
    expect(sessions, hasLength(1), reason: 'one session row, not one per answer');
    final answers =
        await databaseHelper.listAnswersForSession(sessions.single.id!);
    expect(answers, hasLength(3));
    expect(
      answers.map((a) => a.questionText).toList(),
      kQuestions.take(3).toList(),
    );

    state.dispose();
  });

  testWidgets('4 — a session longer than the bank cycles it in sequential order '
      'and still completes at questionCount', (tester) async {
    // One past the bank, so the wrap is observed at its exact boundary (D-23).
    final int count = kQuestions.length + 1;
    final state = newState(config: configFor(questionCount: count));

    await state.startSession();
    for (var i = 0; i < count; i++) {
      await answerOneQuestion(tester, state);
    }

    expect(state.phase, PracticePhase.complete);
    expect(state.answeredCount, count);

    final sessions = await databaseHelper.listSessions();
    final answers =
        await databaseHelper.listAnswersForSession(sessions.single.id!);
    expect(answers, hasLength(count));
    expect(answers.first.questionText, kQuestions.first);
    expect(answers[kQuestions.length - 1].questionText, kQuestions.last);
    expect(
      answers.last.questionText,
      kQuestions.first,
      reason: 'the bank must wrap to its head, not cap the session',
    );

    state.dispose();
  });

  testWidgets('5 — no inter-question countdown runs after the FINAL answer',
      (tester) async {
    final state = newState(config: configFor(questionCount: 2));
    final log = PhaseLog(state);

    await state.startSession();
    await answerOneQuestion(tester, state);
    await answerOneQuestion(tester, state);

    // Two questions, two get-readys: the session's own, and the one between
    // them. A third would mean the loop counted into a question that will never
    // be asked.
    expect(log.countOf(PracticePhase.getReady), 2);
    expect(log.phases.last, PracticePhase.complete);
    expect(state.questionNumber, 2);

    state.dispose();
  });

  testWidgets('6 — k moves at the START of the inter-question countdown, the '
      'committed count only after the commit', (tester) async {
    final state = newState(config: configFor(questionCount: 2));
    final log = PhaseLog(state);

    await state.startSession();
    await answerOneQuestion(tester, state);

    // The app-bar title names the question the user is ABOUT to face.
    expect(log.questionNumberAt(PracticePhase.getReady, 2), 2);
    // …and by then exactly one answer is on disk. The two numbers disagree, on
    // purpose: 2 asked, 1 answered.
    expect(log.answeredCountAt(PracticePhase.getReady, 2), 1);
    // The counter had NOT moved while the save was still in flight.
    expect(log.answeredCountAt(PracticePhase.saving, 1), 0);
    expect(log.questionNumberAt(PracticePhase.recording, 1), 1);

    state.dispose();
  });

  testWidgets('7 — a save failure at question k leaves k-1 answers and does not '
      'advance the loop', (tester) async {
    final helper = FailingAtDatabaseHelper(failOnCall: 2);
    final state = newState(config: configFor(questionCount: 3), helper: helper);

    await state.startSession();
    await answerOneQuestion(tester, state);
    await answerOneQuestion(tester, state);

    expect(state.answeredCount, 1, reason: 'the failed save must not be counted');
    expect(state.phase, PracticePhase.error);
    expect(
      state.questionNumber,
      2,
      reason: 'the loop must not count into question 3 after a failed save',
    );
    expect(await helper.listSessions(), hasLength(1));
    expect(
      await helper.listAnswersForSession(1),
      hasLength(1),
      reason: 'the rolled-back transaction wrote nothing partial',
    );
    // The cause is reported to developer sinks only; the screen shows the one
    // fixed string. Claiming it here keeps the binding from failing the test.
    expect(tester.takeException(), isA<StateError>());

    state.dispose();
  });

  testWidgets('8 — a replay failure never blocks the loop: the answer is '
      'already saved', (tester) async {
    // Relocated from `test/state/practice_state_test.dart`, where plan 02-01
    // left it with no replay to exercise.
    final player = FakeAudioPlayerService(calls)..throwOnPlay = true;
    final state = newState(
      config: configFor(questionCount: 2, autoReplay: true),
      player: player,
    );

    await state.startSession();
    await answerOneQuestion(tester, state);

    expect(calls, contains('play'));
    expect(state.answeredCount, 1);
    expect(await databaseHelper.listAnswersForSession(1), hasLength(1));
    expect(
      state.phase,
      PracticePhase.getReady,
      reason: 'a cosmetic playback failure must not strand the session',
    );
    expect(state.questionNumber, 2);

    state.dispose();
  });

  testWidgets('9 — the answer is already committed at the moment playback '
      'starts', (tester) async {
    // The second relocated Phase 1 guard: commit-happens-before-replay
    // (D-08/D-10), re-provable now that a replay exists again.
    final player =
        FakeAudioPlayerService(calls, databaseHelper: databaseHelper);
    final state = newState(
      config: configFor(questionCount: 1, autoReplay: true),
      player: player,
    );

    await state.startSession();
    await answerOneQuestion(tester, state);

    expect(
      player.sessionsAtFirstPlay,
      1,
      reason: 'the session row must exist before its answer is replayed',
    );
    expect(state.phase, PracticePhase.complete);

    state.dispose();
  });

  testWidgets('a realistic session length and a session longer than the bank '
      'both complete', (tester) async {
    // The two lengths a user actually configures against the 20-prompt
    // placeholder bank: one comfortably inside it, one that has to wrap.
    for (final int count in <int>[10, 25]) {
      final helper = InMemoryDatabaseHelper();
      final state = newState(
        config: configFor(questionCount: count),
        helper: helper,
      );

      await state.startSession();
      for (var i = 0; i < count; i++) {
        await answerOneQuestion(tester, state);
      }

      expect(state.phase, PracticePhase.complete, reason: 'count=$count');
      expect(state.answeredCount, count, reason: 'count=$count');

      final sessions = await helper.listSessions();
      expect(sessions, hasLength(1), reason: 'count=$count');
      final answers =
          await helper.listAnswersForSession(sessions.single.id!);
      expect(answers, hasLength(count), reason: 'count=$count');
      expect(
        answers.map((a) => a.questionText).toList(),
        List<String>.generate(count, (i) => questionAt(kQuestions, i)),
        reason: 'sequential bank order, wrapping rather than capping (D-23)',
      );

      state.dispose();
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PERSIST-01 across N, against REAL SQLite.
  //
  // A plain `test()`, deliberately: `sqflite_common_ffi`'s futures are completed
  // by the real event loop, which the fake clock inside a `testWidgets` body
  // never yields to (see the note on [InMemoryDatabaseHelper]). Dropping the
  // fake clock costs this case the countdowns — so it drives the loop through
  // `startNewQuestion()`/`stopRecording()` directly, which is the same pair the
  // countdowns call and the only pair that touches the database.
  // ───────────────────────────────────────────────────────────────────────────
  group('durability across N answers', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('a session abandoned at question 4 of 10 leaves exactly 3 committed '
        'answers under exactly one session row', () async {
      final helper = DatabaseHelper();
      final state = PracticeState(
        recordingService: recordingService,
        audioPlayerService: FakeAudioPlayerService(calls),
        databaseHelper: helper,
        config: const SessionConfig(
          topics: <String>['Daily life'],
          level: 'B1',
          questionCount: 10,
          thinkingSeconds: 3,
          answerSeconds: 10,
          autoReplay: false,
        ),
      );

      for (var i = 0; i < 3; i++) {
        await state.startNewQuestion();
        await state.stopRecording();
      }

      // Question 4 is armed and then abandoned — the force-stop shape. Nothing
      // was finalized, so nothing may be committed for it.
      await state.startNewQuestion();
      state.dispose();

      // The simulated process kill: close the handle and come back through a
      // brand-new one against the same on-disk file.
      await helper.close();
      final reopened = DatabaseHelper();
      addTearDown(reopened.close);

      final sessions = await reopened.listSessions();
      expect(
        sessions,
        hasLength(1),
        reason: 'nine questions must not become nine session rows',
      );
      final answers = await reopened.listAnswersForSession(sessions.single.id!);
      // Asserted on the ROW COUNT and the row ORDER, not on the loop's own
      // counters: this case has to stay red if a future change ever brings back
      // a one-answer-per-session assumption.
      expect(answers, hasLength(3));
      expect(
        answers.map((a) => a.questionText).toList(),
        kQuestions.take(3).toList(),
      );
      for (final answer in answers) {
        expect(answer.audioPath, startsWith('$kRecordingsDirName/'));
      }
    });
  });
}

/// The first prompt of the placeholder bank — the one a sequential draw at
/// question 1 must produce (D-23).
const String kQuestionsFirstPrompt = 'What did you do this morning?';
