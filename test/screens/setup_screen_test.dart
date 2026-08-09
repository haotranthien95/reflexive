import 'dart:async';
import 'dart:io';

import 'package:englishreflex/data/questions.dart';
import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/models/session_config.dart';
import 'package:englishreflex/screens/practice_screen.dart';
import 'package:englishreflex/screens/setup_screen.dart';
import 'package:englishreflex/services/audio_player_service.dart';
import 'package:englishreflex/services/firestore_question_source.dart';
import 'package:englishreflex/services/recording_service.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The topics these tests drive, standing in for whatever is in the real bank.
///
/// Mirrors the old `kSubjects` constant so the topic keys every pre-existing
/// test taps (`setup-topic-Travel`, `setup-topic-Daily life`) keep resolving.
/// Already in the case-insensitive sorted order [normalizeSubjects] produces,
/// because `SetupScreen` renders its source's list verbatim and does not sort.
const List<String> _kTestSubjects = <String>[
  'Daily life',
  'Food & health',
  'Opinions',
  'Travel',
  'Work & study',
];

/// The one scripted [QuestionSource] behind every read state D-47 puts behind
/// the seam — loaded, empty, could-not-load and zero-result, for both reads.
///
/// **One class, not four.** Each read takes a list of per-call outcomes and the
/// rule for reading them is a single sentence: *a `List<String>` is returned, an
/// empty one being a server-confirmed empty read; anything else is thrown.* The
/// last entry repeats once the script runs out, so a test that only cares about
/// the first outcome writes one entry.
///
/// **Every method completes synchronously by default** (`async` with no real
/// `await`). That is deliberate and load-bearing for the same reason
/// `_EmptyDatabaseHelper` exists: `testWidgets` runs on a fake clock that drains
/// microtasks but never yields to the real event loop, so a `Future.delayed`
/// here would never resolve and every test in this file would hang on a topics
/// card that never fills.
///
/// **[holdSubjects] / [holdQuestions] are the one exception, and they are how
/// an in-flight frame becomes observable.** A held call parks on a [Completer]
/// the test releases by hand, which stays inside the microtask queue the fake
/// clock does drain — so "the spinner is on screen while the read is in flight"
/// is a real assertion rather than a race with the harness.
class FakeQuestionSource implements QuestionSource {
  FakeQuestionSource({
    List<Object>? subjectOutcomes,
    List<Object>? questionOutcomes,
    this.holdSubjects = false,
    this.holdQuestions = false,
  })  : subjectOutcomes = subjectOutcomes ?? <Object>[_kTestSubjects],
        questionOutcomes =
            questionOutcomes ?? <Object>[const <String>['A fake prompt.']];

  final List<Object> subjectOutcomes;
  final List<Object> questionOutcomes;
  final bool holdSubjects;
  final bool holdQuestions;

  /// Proves a re-read happened, and how many times.
  int subjectsCallCount = 0;
  int questionsCallCount = 0;

  /// Every config the Start query was actually issued with, in order — this is
  /// what pins the tap-time snapshot against a mid-flight settings change.
  final List<SessionConfig> configs = <SessionConfig>[];

  Completer<void>? _subjectsGate;
  Completer<void>? _questionsGate;

  /// Lets a parked call proceed. A no-op when nothing is parked, so a test can
  /// release unconditionally without racing the screen's own call ordering.
  void releaseSubjects() {
    final gate = _subjectsGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void releaseQuestions() {
    final gate = _questionsGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  static List<String> _resolve(List<Object> script, int callIndex) {
    final outcome =
        script[callIndex < script.length ? callIndex : script.length - 1];
    if (outcome is List<String>) return outcome;
    throw outcome;
  }

  @override
  Future<List<String>> subjects() async {
    final callIndex = subjectsCallCount++;
    if (holdSubjects) {
      await (_subjectsGate = Completer<void>()).future;
    }
    return _resolve(subjectOutcomes, callIndex);
  }

  @override
  Future<List<String>> questionsFor(SessionConfig config) async {
    final callIndex = questionsCallCount++;
    configs.add(config);
    if (holdQuestions) {
      await (_questionsGate = Completer<void>()).future;
    }
    return _resolve(questionOutcomes, callIndex);
  }
}

/// The scripted "this read could not be served" outcome.
///
/// The production source's own signal, so scripting it is scripting exactly
/// what `FirestoreQuestionSource` throws for a `FirebaseException` AND for the
/// offline zero-documents-from-cache case.
const Object _kUnreachable = QuestionBankUnavailableException();

/// A database double with no engine behind it.
///
/// Deliberately NOT sqflite-ffi. `flutter_test`'s binding runs a `testWidgets`
/// body on a fake clock that drains microtasks but never yields to the real
/// event loop, so an ffi future would never complete inside these tests — the
/// finding plan 02-01 paid for and recorded in its summary. Setup only ever
/// asks the database one question (which audio files are still referenced, for
/// the orphan sweep), and none of the behaviour under test here depends on the
/// answer. Real SQLite is proven by `test/db/database_helper_test.dart`.
class _EmptyDatabaseHelper extends DatabaseHelper {
  @override
  Future<Set<String>> listReferencedAudioPaths() async => <String>{};

  @override
  Future<List<Session>> listSessions() async => <Session>[];
}

/// A recorder backend that touches no platform channel. Only needed because the
/// config assertion navigates into `PracticeScreen`, which builds a real
/// recorder when none is injected.
class _SilentRecorderBackend implements RecorderBackend {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String absoluteFilePath) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<bool> isPaused() async => false;

  @override
  Stream<bool> get onPausedChanged => const Stream<bool>.empty();

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> dispose() async {}
}

class _SilentPlaybackBackend implements AudioPlaybackBackend {
  @override
  Stream<void> get onComplete => const Stream<void>.empty();

  @override
  Future<void> play(String absoluteFilePath) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// The app's theme, rebuilt locally.
///
/// `EnglishReflexApp` composes its `ThemeData` inline inside `build`, so there
/// is no seam to import it through, and reaching for one would mean editing
/// `lib/main.dart` — owned by another plan this wave. The four type roles and
/// the four palette values are mirrored verbatim; Baloo 2 is replaced by the
/// default family so the test never depends on a font asset. What matters to
/// every assertion below is that theme-derived styles RESOLVE, not which
/// glyphs they draw.
ThemeData _testTheme() {
  const Color accent = Color(0xFFFF6B35);
  const Color surface = Color(0xFFFFDDB3);
  const Color background = Color(0xFFFFF8F0);
  const Color textOnColor = Color(0xFF3D2B1F);
  const Color errorRed = Color(0xFFE5484D);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      onPrimary: textOnColor,
      surface: surface,
      onSurface: textOnColor,
      error: errorRed,
    ),
    scaffoldBackgroundColor: background,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: textOnColor,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: textOnColor,
      ),
      labelLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: textOnColor,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: textOnColor,
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_setup');
    Directory('${tempDir.path}/$kRecordingsDirName').createSync(recursive: true);
    documentsDirProvider = () async => tempDir;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget host({QuestionSource? source}) => MaterialApp(
        theme: _testTheme(),
        home: SetupScreen(
          databaseHelper: _EmptyDatabaseHelper(),
          recordingService:
              RecordingService(backend: _SilentRecorderBackend()),
          audioPlayerService:
              AudioPlayerService(backend: _SilentPlaybackBackend()),
          // A whole source, not a subject list: the subject list moved behind
          // the `QuestionSource` seam when Phase 3 sourced it from Firestore,
          // and a scriptable source is what lets one harness drive all four read
          // outcomes. Passing one is also what proves production's
          // `FirestoreQuestionSource` is never constructed under `flutter test`.
          questionSource: source ?? FakeQuestionSource(),
        ),
      );

  /// A tall PORTRAIT surface so every control is laid out and hit-testable
  /// without scrolling first. The 800x600 landscape default is not a shape this
  /// app ever ships in, and the height is what keeps the slider drags below
  /// from needing an `ensureVisible` dance. The text-scale case deliberately
  /// uses a REALISTIC surface instead — overflow is the whole point there.
  Future<void> pumpSetup(
    WidgetTester tester, {
    QuestionSource? source,
    Size size = const Size(400, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(source: source));
    // TWO frames, not one. The subject list stopped being a compile-time
    // constant available on the first frame when Phase 3 sourced it from
    // Firestore: frame one lands before `_loadSubjects()`'s future has been
    // drained, so the topics card is still empty. The second frame is where the
    // topics appear.
    //
    // Fixed HERE, in the shared harness, rather than test by test — otherwise
    // every Setup test in this file would carry the same extra `pump()` and the
    // next one written would forget it.
    await tester.pump();
    await tester.pump();
  }

  bool startEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('setup-start')))
          .onPressed !=
      null;

  group('SetupScreen defaults', () {
    testWidgets('the first frame is exactly the D-16/D-17 defaults',
        (tester) async {
      await pumpSetup(tester);

      // Level: B1 and nothing else.
      for (final level in kLevels) {
        final chip =
            tester.widget<ChoiceChip>(find.byKey(Key('setup-level-$level')));
        expect(chip.selected, level == 'B1',
            reason: '$level selection state on the first frame');
      }

      // The three numeric readouts, in Copywriting Contract format.
      expect(find.text('10'), findsOneWidget);
      expect(find.text('5 sec'), findsOneWidget);
      expect(find.text('60 sec'), findsOneWidget);

      // Auto-replay ON (SETUP-06 / D-10).
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('setup-replay')))
            .value,
        isTrue,
      );

      // No topic checked — so Start is gated shut on arrival.
      for (final tile in tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile))) {
        expect(tile.value, isFalse);
      }
      expect(startEnabled(tester), isFalse);
    });

    testWidgets('every user-facing string matches the Copywriting Contract',
        (tester) async {
      await pumpSetup(tester);

      expect(find.text('Topics'), findsOneWidget);
      expect(find.text('Level'), findsOneWidget);
      expect(find.text("CEFR level of the questions you'll get."),
          findsOneWidget);
      expect(find.text('Questions'), findsOneWidget);
      expect(find.text('Thinking time'), findsOneWidget);
      expect(
        find.text(
            'How long you get to read the question before recording starts.'),
        findsOneWidget,
      );
      expect(find.text('Answer length'), findsOneWidget);
      expect(find.text('Recording stops automatically after this long.'),
          findsOneWidget);
      expect(find.text('Play back my answers'), findsOneWidget);
      expect(find.text('Hear each answer right after you record it.'),
          findsOneWidget);
      expect(find.text('Pick at least one topic to start.'), findsOneWidget);
      expect(find.text('START SESSION'), findsOneWidget);
    });
  });

  group('SetupScreen Start gate (SETUP-07)', () {
    testWidgets('the gate and its explanation always arrive together',
        (tester) async {
      await pumpSetup(tester);

      expect(startEnabled(tester), isFalse);
      expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();

      expect(startEnabled(tester), isTrue);
      expect(find.byKey(const Key('setup-start-blocked')), findsNothing);

      // Unchecking the LAST topic must restore both halves, not just the
      // button — a disabled Start with no reason beside it is the failure.
      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();

      expect(startEnabled(tester), isFalse);
      expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);
    });

    testWidgets('an empty subject list shows the locked empty state and '
        'keeps Start shut', (tester) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(subjectOutcomes: <Object>[<String>[]]),
      );

      expect(find.byKey(const Key('setup-topics-empty')), findsOneWidget);
      expect(find.text('No topics yet'), findsOneWidget);
      expect(find.text('Import some questions and your topics will show up '
          'here.'), findsOneWidget);
      expect(startEnabled(tester), isFalse);
    });
  });

  group('SetupScreen reads its topics from the injected bank (BANK-02)', () {
    testWidgets('an injected source is the ONLY source consulted — the '
        'production Firestore one is never constructed', (tester) async {
      // A source scripted to throw a plain `StateError`, which is NOT the seam's
      // own signal. If `SetupScreen` ever built its own `FirestoreQuestionSource`
      // instead of using the injected one, this test would fail on a missing
      // Firebase app — and either way it fails, which is the point: no
      // `flutter test` run may reach a Firestore handle.
      final source = FakeQuestionSource(
        subjectOutcomes: <Object>[
          StateError('the injected source must be the one that is used'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: SetupScreen(
            databaseHelper: _EmptyDatabaseHelper(),
            questionSource: source,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The injected source was asked, its throw was contained and logged, and
      // the screen is still standing — nothing reached the platform.
      expect(source.subjectsCallCount, 1);
      expect(find.byKey(const Key('setup-start')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Anything that threw is could-not-load, whatever it threw.
      expect(find.byKey(const Key('setup-topics-error')), findsOneWidget);
    });

    testWidgets('the checkboxes are exactly the bank\'s subjects, in the '
        'order the bank gave them', (tester) async {
      // `SetupScreen` renders its source's list verbatim: ordering, de-duping
      // and blank-dropping belong to the source (see `normalizeSubjects`), so
      // the screen has one job and it is this one.
      await pumpSetup(
        tester,
        source: FakeQuestionSource(
          subjectOutcomes: <Object>[
            normalizeSubjects(<Object?>[
              'Travel',
              'daily life',
              'Travel', // an exact duplicate: one checkbox
              '   ', // blank: no checkbox
              null, // not a String: no checkbox
              'Work & study',
            ]),
          ],
        ),
      );

      // Case-insensitive sort puts 'daily life' first, before 'Travel'.
      final topicTitles = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(topicTitles, <String>['daily life', 'Travel', 'Work & study']);
    });

    testWidgets('a single-subject bank renders one checkbox and ticking it '
        'opens Start', (tester) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(
          subjectOutcomes: <Object>[<String>['Travel']],
        ),
      );

      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(startEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();

      expect(startEnabled(tester), isTrue);
    });
  });

  group('START SESSION carries the query\'s prompts into the loop (BANK-03)',
      () {
    /// A host with the bank's *questions* scripted as well as its subjects.
    Future<void> pumpWithBank(
      WidgetTester tester,
      List<String> questions,
    ) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(questionOutcomes: <Object>[questions]),
      );
    }

    testWidgets('the loop is handed exactly what the query returned, in the '
        'order it returned them', (tester) async {
      const bank = <String>['First seeded prompt.', 'Second seeded prompt.'];
      await pumpWithBank(tester, bank);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // D-34: a resolved value crosses into the session, never a source.
      expect(
        tester.widget<PracticeScreen>(find.byType(PracticeScreen)).questions,
        bank,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a zero-result topic-by-level combination does NOT open a '
        'session (D-41)', (tester) async {
      // `Travel` at C1 is deliberately empty in the seeded bank. Navigating with
      // an empty bank would crash the loop on its first prompt, because
      // `questionAt` divides by `length`. Plan 02 adds the message that explains
      // it; this plan's job is that the tap cannot take the user anywhere.
      await pumpWithBank(tester, const <String>[]);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PracticeScreen), findsNothing);
      expect(tester.takeException(), isNull);
      // Nothing the user chose was lost on the way (D-38's standing rule).
      expect(startEnabled(tester), isTrue);
    });
  });

  group('SetupScreen topics card — the four read states (D-37)', () {
    /// How many of the four mutually exclusive bodies are on screen.
    ///
    /// The card is a deliberately TOTAL map, the same discipline
    /// `kPhaseControlKeys` enforces on the practice screen: a topics state with
    /// none of these present is a card that says nothing, and two at once is a
    /// card that contradicts itself.
    int statesPresent(WidgetTester tester) => <bool>[
          find.byKey(const Key('setup-topics-loading')).evaluate().isNotEmpty,
          find.byKey(const Key('setup-topics-empty')).evaluate().isNotEmpty,
          find.byKey(const Key('setup-topics-error')).evaluate().isNotEmpty,
          find.byType(CheckboxListTile).evaluate().isNotEmpty,
        ].where((present) => present).length;

    testWidgets('the first frame is loading, with Start shut and no helper',
        (tester) async {
      final source = FakeQuestionSource(holdSubjects: true);
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(source: source));

      expect(find.byKey(const Key('setup-topics-loading')), findsOneWidget);
      expect(find.text('Loading your topics…'), findsOneWidget);
      expect(statesPresent(tester), 1);
      expect(startEnabled(tester), isFalse);
      // Nothing to pick yet, so nothing tells the user to pick.
      expect(find.byKey(const Key('setup-start-blocked')), findsNothing);

      source.releaseSubjects();
      await tester.pump();

      expect(find.byKey(const Key('setup-topics-loading')), findsNothing);
      expect(find.byType(CheckboxListTile),
          findsNWidgets(_kTestSubjects.length));
      expect(statesPresent(tester), 1);
    });

    testWidgets('a read that threw is could-not-load, and says NOTHING the '
        'empty state says', (tester) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(subjectOutcomes: <Object>[_kUnreachable]),
      );

      expect(find.byKey(const Key('setup-topics-error')), findsOneWidget);
      expect(find.text(kTopicsErrorMessage), findsOneWidget);
      expect(find.byKey(const Key('setup-topics-error-retry')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // The negative half IS the requirement. Telling a user with a full bank
      // and a flat connection that their topics are gone is the exact failure
      // D-37 exists to prevent, so the empty state's key and its heading must
      // both be absent — not merely "a different widget somewhere".
      expect(find.byKey(const Key('setup-topics-empty')), findsNothing);
      expect(find.text('No topics yet'), findsNothing);
      expect(
        find.text('Import some questions and your topics will show up here.'),
        findsNothing,
      );
      expect(statesPresent(tester), 1);

      // No exception detail leaked to the screen.
      expect(find.textContaining('QuestionBankUnavailable'), findsNothing);
      expect(startEnabled(tester), isFalse);
      expect(find.byKey(const Key('setup-start-blocked')), findsNothing);
    });

    testWidgets('a server-confirmed empty bank is the empty state, and says '
        'NOTHING the failure state says', (tester) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(subjectOutcomes: <Object>[<String>[]]),
      );

      expect(find.byKey(const Key('setup-topics-empty')), findsOneWidget);
      expect(find.text('No topics yet'), findsOneWidget);

      expect(find.byKey(const Key('setup-topics-error')), findsNothing);
      expect(find.text(kTopicsErrorMessage), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(statesPresent(tester), 1);

      expect(startEnabled(tester), isFalse);
      // Zero subjects: the pick-a-topic helper would be pointing at an empty
      // card. This is the latent Phase 2 copy bug, fixed.
      expect(find.byKey(const Key('setup-start-blocked')), findsNothing);
    });

    testWidgets('with subjects on screen and none checked, the pick-a-topic '
        'helper IS present', (tester) async {
      await pumpSetup(tester);

      expect(find.byType(CheckboxListTile),
          findsNWidgets(_kTestSubjects.length));
      expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);
      expect(statesPresent(tester), 1);
    });

    testWidgets('Try again re-issues the read and returns the card to loading '
        'before it resolves', (tester) async {
      final source = FakeQuestionSource(
        subjectOutcomes: <Object>[_kUnreachable, _kTestSubjects],
        holdSubjects: true,
      );
      await pumpSetup(tester, source: source);
      source.releaseSubjects();
      await tester.pump();

      expect(find.byKey(const Key('setup-topics-error')), findsOneWidget);
      expect(source.subjectsCallCount, 1);

      await tester.tap(find.byKey(const Key('setup-topics-error-retry')));
      await tester.pump();

      expect(source.subjectsCallCount, 2);
      // Loading replaces the failure immediately — and loading has no Retry
      // button, so a second tap is structurally impossible rather than merely
      // ignored.
      expect(find.byKey(const Key('setup-topics-loading')), findsOneWidget);
      expect(find.byKey(const Key('setup-topics-error')), findsNothing);
      expect(statesPresent(tester), 1);

      source.releaseSubjects();
      await tester.pump();

      expect(find.byType(CheckboxListTile),
          findsNWidgets(_kTestSubjects.length));
      expect(statesPresent(tester), 1);
    });

    testWidgets('a background refresh shows no spinner, and a failed one keeps '
        'the last-known topics on screen (D-35)', (tester) async {
      final source = FakeQuestionSource(
        subjectOutcomes: <Object>[_kTestSubjects, _kUnreachable],
        holdSubjects: true,
      );
      await pumpSetup(tester, source: source);
      source.releaseSubjects();
      await tester.pump();
      expect(find.byType(CheckboxListTile),
          findsNWidgets(_kTestSubjects.length));

      // Leave Setup and come back — D-35's re-read, driven by the History push.
      await tester.tap(find.byTooltip('Exercise History'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(source.subjectsCallCount, 2);
      // In flight, and SILENT: replacing usable data with a spinner would
      // flicker the checkboxes on every return from History.
      expect(find.byKey(const Key('setup-topics-loading')), findsNothing);
      expect(find.byType(CheckboxListTile),
          findsNWidgets(_kTestSubjects.length));

      source.releaseSubjects();
      await tester.pump();

      // It failed, and that changed nothing the user can see.
      expect(find.byKey(const Key('setup-topics-error')), findsNothing);
      expect(find.byType(CheckboxListTile),
          findsNWidgets(_kTestSubjects.length));
      expect(statesPresent(tester), 1);
    });

    testWidgets('a re-read that no longer lists a checked topic drops it from '
        'the SELECTION, not just the screen', (tester) async {
      final source = FakeQuestionSource(
        subjectOutcomes: <Object>[
          <String>['Daily life', 'Travel'],
          <String>['Daily life'], // Travel left the bank between visits
        ],
      );
      await pumpSetup(tester, source: source);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();
      expect(startEnabled(tester), isTrue);

      await tester.tap(find.byTooltip('Exercise History'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(source.subjectsCallCount, 2);
      expect(find.byKey(const Key('setup-topic-Travel')), findsNothing);
      // The reconciliation is the point: without it `Travel` survives in the
      // selection, travels into `SessionConfig.topics`, and filters on a value
      // that does not exist — a silent zero-result naming a topic the user
      // cannot see to uncheck.
      expect(startEnabled(tester), isFalse);
      expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);
    });
  });

  group('The Start footer — busy, zero-result, could-not-reach', () {
    /// How many of the three helper lines are on screen.
    ///
    /// The slot is zero-or-one, never many: B3 and B4 cannot coexist because a
    /// query either throws or returns and each tap replaces the last outcome,
    /// and B2 cannot coexist with either because reaching a query at all
    /// requires a checked topic.
    int helpersPresent(WidgetTester tester) => <bool>[
          find.byKey(const Key('setup-start-blocked')).evaluate().isNotEmpty,
          find
              .byKey(const Key('setup-start-no-questions'))
              .evaluate()
              .isNotEmpty,
          find.byKey(const Key('setup-start-error')).evaluate().isNotEmpty,
        ].where((present) => present).length;

    /// The fill the button ACTUALLY paints, not the one it was handed.
    ///
    /// Resolving matters here: `FilledButton` paints `disabledBackgroundColor`
    /// whenever `onPressed` is null, which is true of both the blocked and the
    /// busy state — so only the resolved value can tell them apart.
    Color? resolvedFill(WidgetTester tester, {bool disabled = true}) => tester
        .widget<FilledButton>(find.byKey(const Key('setup-start')))
        .style
        ?.backgroundColor
        ?.resolve(disabled ? <WidgetState>{WidgetState.disabled} : <WidgetState>{});

    testWidgets('an in-flight query renders the busy button — no label, no '
        'tap, and still coral', (tester) async {
      final source = FakeQuestionSource(holdQuestions: true);
      await pumpSetup(tester, source: source);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();

      expect(find.byKey(const Key('setup-start-busy')), findsOneWidget);
      expect(find.text('START SESSION'), findsNothing);
      // Null, not a swallowed tap: a double-Start is structurally impossible.
      expect(startEnabled(tester), isFalse);
      // An action IN FLIGHT must not look identical to an action BLOCKED.
      expect(resolvedFill(tester), _testTheme().colorScheme.primary);
      expect(resolvedFill(tester), isNot(_testTheme().colorScheme.surface));
      // The button never changes size between states.
      expect(
        tester
            .widget<SizedBox>(
              find
                  .ancestor(
                    of: find.byKey(const Key('setup-start')),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .height,
        64,
      );
      expect(helpersPresent(tester), 0);

      source.releaseQuestions();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PracticeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a blocked button keeps the peach fill, so busy and blocked '
        'are never the same picture', (tester) async {
      await pumpSetup(tester);

      expect(startEnabled(tester), isFalse);
      expect(resolvedFill(tester), _testTheme().colorScheme.surface);
      expect(find.text('START SESSION'), findsOneWidget);
      expect(find.byKey(const Key('setup-start-busy')), findsNothing);
    });

    testWidgets('a zero-result query explains itself and costs the user '
        'nothing (D-41 + D-38)', (tester) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(questionOutcomes: <Object>[<String>[]]),
      );

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.tap(find.byKey(const Key('setup-level-C1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('setup-start-no-questions')), findsOneWidget);
      expect(find.text(noQuestionsMessage('C1', <String>['Travel'])),
          findsOneWidget);
      expect(helpersPresent(tester), 1);
      // Not a failure: no icon, and the failure key is absent.
      expect(find.byKey(const Key('setup-start-error')), findsNothing);
      expect(find.byType(PracticeScreen), findsNothing);
      // Nothing was reset, and the button is usable again.
      expect(startEnabled(tester), isTrue);
      expect(find.byKey(const Key('setup-start-busy')), findsNothing);
    });

    testWidgets('a failed query names the connection and preserves every '
        'setting (D-38)', (tester) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(questionOutcomes: <Object>[_kUnreachable]),
      );

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.tap(find.byKey(const Key('setup-topic-Work & study')));
      await tester.tap(find.byKey(const Key('setup-level-A2')));
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('setup-count-slider')),
        const Offset(-1000, 0),
      );
      await tester.drag(
        find.byKey(const Key('setup-thinking-slider')),
        const Offset(1000, 0),
      );
      await tester.drag(
        find.byKey(const Key('setup-answer-slider')),
        const Offset(-1000, 0),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('setup-start-error')), findsOneWidget);
      expect(find.text(kQuestionLoadErrorMessage), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(helpersPresent(tester), 1);
      expect(find.byKey(const Key('setup-start-no-questions')), findsNothing);

      // No route was pushed.
      expect(find.byType(PracticeScreen), findsNothing);

      // A failure never costs the user their setup.
      for (final level in kLevels) {
        expect(
          tester.widget<ChoiceChip>(find.byKey(Key('setup-level-$level')))
              .selected,
          level == 'A2',
          reason: '$level after a failed Start query',
        );
      }
      for (final subject in <String>['Travel', 'Work & study']) {
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(Key('setup-topic-$subject')))
              .value,
          isTrue,
        );
      }
      expect(
        tester.widget<Text>(find.byKey(const Key('setup-count-readout'))).data,
        '1',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('setup-thinking-readout')))
            .data,
        '30 sec',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('setup-answer-readout'))).data,
        '10 sec',
      );

      // And no exception text reached the screen.
      expect(find.textContaining('QuestionBankUnavailable'), findsNothing);
    });

    testWidgets('changing a topic, the level or a slider clears the last '
        "attempt's helper", (tester) async {
      Future<void> failStart(WidgetTester tester, FakeQuestionSource s) async {
        await tester.tap(find.byKey(const Key('setup-start')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      final source =
          FakeQuestionSource(questionOutcomes: <Object>[_kUnreachable]);
      await pumpSetup(tester, source: source);
      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();

      // The level.
      await failStart(tester, source);
      expect(find.byKey(const Key('setup-start-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('setup-level-C2')));
      await tester.pump();
      expect(helpersPresent(tester), 0);

      // A slider.
      await failStart(tester, source);
      expect(find.byKey(const Key('setup-start-error')), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('setup-count-slider')),
        const Offset(-1000, 0),
      );
      await tester.pump();
      expect(helpersPresent(tester), 0);

      // A topic — and unchecking the last one hands the slot back to the
      // blocked helper rather than leaving two messages behind.
      await failStart(tester, source);
      expect(find.byKey(const Key('setup-start-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();
      expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);
      expect(helpersPresent(tester), 1);
    });

    testWidgets('the tap-time SessionConfig wins over a level changed '
        'mid-flight', (tester) async {
      final source = FakeQuestionSource(holdQuestions: true);
      await pumpSetup(tester, source: source);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.tap(find.byKey(const Key('setup-level-B2')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();
      expect(find.byKey(const Key('setup-start-busy')), findsOneWidget);

      // The controls stay interactive during the busy frame — deliberately, no
      // invisible disabling and no overlay.
      await tester.tap(find.byKey(const Key('setup-level-C2')));
      await tester.pump();

      source.releaseQuestions();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The query ran with the level the user had chosen when they tapped. The
      // mid-flight change belongs to the NEXT Start.
      expect(source.configs.single.level, 'B2');
      expect(
        tester.widget<PracticeScreen>(find.byType(PracticeScreen)).config.level,
        'B2',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('at most one helper line, in each of the three states that '
        'produce one', (tester) async {
      final source = FakeQuestionSource(
        questionOutcomes: <Object>[<String>[], _kUnreachable],
      );
      await pumpSetup(tester, source: source);

      // Nothing selected.
      expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);
      expect(helpersPresent(tester), 1);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();
      expect(helpersPresent(tester), 0);

      // After a zero result.
      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('setup-start-no-questions')), findsOneWidget);
      expect(helpersPresent(tester), 1);

      // After a failure — the previous outcome is REPLACED, never accumulated.
      await tester.tap(find.byKey(const Key('setup-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('setup-start-error')), findsOneWidget);
      expect(helpersPresent(tester), 1);
    });

    testWidgets('the resting ready state is one button and nothing else',
        (tester) async {
      await pumpSetup(tester);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.pump();

      expect(startEnabled(tester), isTrue);
      expect(
        resolvedFill(tester, disabled: false),
        _testTheme().colorScheme.primary,
      );
      expect(find.text('START SESSION'), findsOneWidget);
      expect(helpersPresent(tester), 0);
    });
  });

  group('noQuestionsMessage (D-41 copy)', () {
    test('one topic names that topic and the level', () {
      expect(
        noQuestionsMessage('C2', <String>['Travel']),
        'No C2 questions in Travel yet. '
        'Try another level, or pick more topics.',
      );
    });

    test('two topics are joined with OR, because the query is a disjunction',
        () {
      expect(
        noQuestionsMessage('C2', <String>['Travel', 'Food & health']),
        'No C2 questions in Travel or Food & health yet. '
        'Try another level, or pick more topics.',
      );
    });

    test('three or more names the COUNT, so the non-scrolling footer stays '
        'length-bounded', () {
      expect(
        noQuestionsMessage('C2', <String>[
          'Travel',
          'Food & health',
          'Daily life',
          'Work & study',
        ]),
        'No C2 questions in any of your 4 topics yet. '
        'Try another level, or pick different topics.',
      );
    });
  });

  group('normalizeSubjects (BANK-02 rules)', () {
    test('collapses exact duplicates to one topic', () {
      expect(
        normalizeSubjects(<Object?>['Travel', 'Travel', 'Travel']),
        <String>['Travel'],
      );
    });

    test('keeps values differing only by case or surrounding whitespace as '
        'DISTINCT topics', () {
      // Deliberate: the server-side `whereIn` compares exact strings, so folding
      // these together here would hand the user a checkbox that matches nothing.
      expect(
        normalizeSubjects(<Object?>['Travel', 'travel', ' Travel']),
        <String>[' Travel', 'Travel', 'travel'],
      );
    });

    test('drops blank, whitespace-only, missing and non-String values', () {
      expect(
        normalizeSubjects(<Object?>['', '   ', null, 42, <String>[], 'Travel']),
        <String>['Travel'],
      );
    });

    test('sorts case-insensitively, and the same input always sorts the same '
        'way', () {
      const input = <Object?>['zebra', 'Apple', 'banana', 'Cherry'];
      const expected = <String>['Apple', 'banana', 'Cherry', 'zebra'];
      expect(normalizeSubjects(input), expected);
      // Re-read stability: a second call never reshuffles the checkboxes.
      expect(normalizeSubjects(input.reversed), expected);
    });

    test('an empty bank yields no topics at all', () {
      expect(normalizeSubjects(const <Object?>[]), isEmpty);
    });
  });

  group('SetupScreen slider ranges', () {
    /// Saturates a slider by dragging far past its end, so the assertion is
    /// about the RANGE the widget can represent rather than about the drag
    /// distance. An out-of-range value has no way to appear.
    Future<void> saturate(
      WidgetTester tester,
      String keyPrefix, {
      required bool toMax,
    }) async {
      await tester.drag(
        find.byKey(Key('$keyPrefix-slider')),
        Offset(toMax ? 1000 : -1000, 0),
      );
      await tester.pump();
    }

    testWidgets('questions reaches exactly 1 and exactly 100', (tester) async {
      await pumpSetup(tester);

      await saturate(tester, 'setup-count', toMax: false);
      expect(
        tester.widget<Text>(find.byKey(const Key('setup-count-readout'))).data,
        '1',
      );

      await saturate(tester, 'setup-count', toMax: true);
      expect(
        tester.widget<Text>(find.byKey(const Key('setup-count-readout'))).data,
        '100',
      );
    });

    testWidgets('thinking time reaches exactly 3 sec and exactly 30 sec',
        (tester) async {
      await pumpSetup(tester);

      await saturate(tester, 'setup-thinking', toMax: false);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('setup-thinking-readout')))
            .data,
        '3 sec',
      );

      await saturate(tester, 'setup-thinking', toMax: true);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('setup-thinking-readout')))
            .data,
        '30 sec',
      );
    });

    testWidgets('answer length reaches exactly 10 sec and exactly 120 sec',
        (tester) async {
      await pumpSetup(tester);

      await saturate(tester, 'setup-answer', toMax: false);
      expect(
        tester.widget<Text>(find.byKey(const Key('setup-answer-readout'))).data,
        '10 sec',
      );

      await saturate(tester, 'setup-answer', toMax: true);
      expect(
        tester.widget<Text>(find.byKey(const Key('setup-answer-readout'))).data,
        '120 sec',
      );
    });

    testWidgets('divisions land on whole numbers, never a fraction',
        (tester) async {
      await pumpSetup(tester);

      // A partial drag: whatever it lands on must still be a bare integer with
      // no decimal point, because divisions make every reachable value exact.
      await tester.drag(
        find.byKey(const Key('setup-count-slider')),
        const Offset(37, 0),
      );
      await tester.pump();

      final readout = tester
          .widget<Text>(find.byKey(const Key('setup-count-readout')))
          .data!;
      expect(readout, isNot(contains('.')));
      expect(int.parse(readout), inInclusiveRange(1, 100));
    });

    testWidgets('each slider announces its unit to a screen reader',
        (tester) async {
      await pumpSetup(tester);

      String announce(String keyPrefix) {
        final slider =
            tester.widget<Slider>(find.byKey(Key('$keyPrefix-slider')));
        return slider.semanticFormatterCallback!(slider.value);
      }

      expect(announce('setup-count'), '10 questions');
      expect(announce('setup-thinking'), '5 seconds thinking time');
      expect(announce('setup-answer'), '60 seconds answer length');
    });
  });

  group('SetupScreen level chips (SETUP-02)', () {
    testWidgets('selecting a level deselects the previous one', (tester) async {
      await pumpSetup(tester);

      await tester.tap(find.byKey(const Key('setup-level-C1')));
      await tester.pump();

      final selected = <String>[
        for (final level in kLevels)
          if (tester
              .widget<ChoiceChip>(find.byKey(Key('setup-level-$level')))
              .selected)
            level,
      ];
      expect(selected, <String>['C1']);
    });

    testWidgets('tapping the selected chip is a no-op, never a deselect',
        (tester) async {
      await pumpSetup(tester);

      await tester.tap(find.byKey(const Key('setup-level-B1')));
      await tester.pump();

      // Single-select is an INVARIANT here: there is no "no level chosen"
      // state to fall into, so this tap must change nothing.
      expect(
        tester.widget<ChoiceChip>(find.byKey(const Key('setup-level-B1')))
            .selected,
        isTrue,
      );
    });
  });

  group('SetupScreen -> SessionConfig', () {
    testWidgets('START SESSION carries the live value of all six fields',
        (tester) async {
      await pumpSetup(tester);

      await tester.tap(find.byKey(const Key('setup-topic-Travel')));
      await tester.tap(find.byKey(const Key('setup-level-A2')));
      await tester.tap(find.byKey(const Key('setup-replay')));
      await tester.pump();

      await tester.drag(
        find.byKey(const Key('setup-count-slider')),
        const Offset(-1000, 0),
      );
      await tester.drag(
        find.byKey(const Key('setup-thinking-slider')),
        const Offset(1000, 0),
      );
      await tester.drag(
        find.byKey(const Key('setup-answer-slider')),
        const Offset(-1000, 0),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('setup-start')));
      // Two pumps, not `pumpAndSettle`: the route transition needs a frame, and
      // the session on the other side of it owns a live countdown that would
      // never let `pumpAndSettle` return.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final SessionConfig config =
          tester.widget<PracticeScreen>(find.byType(PracticeScreen)).config;

      expect(config.topics, <String>['Travel']);
      expect(config.level, 'A2');
      expect(config.questionCount, 1);
      expect(config.thinkingSeconds, 30);
      expect(config.answerSeconds, 10);
      expect(config.autoReplay, isFalse);

      // Tear the session down inside the test rather than leaving its
      // countdown alive past the end of it.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a fresh Setup forgets everything the last one chose (D-18)',
        (tester) async {
      await pumpSetup(tester);

      await tester.tap(find.byKey(const Key('setup-level-C2')));
      await tester.tap(find.byKey(const Key('setup-replay')));
      await tester.pump();

      // Rebuild from scratch — exactly what returning to Setup after a session
      // does. Nothing is read back from anywhere, because nothing was written.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpSetup(tester);

      expect(
        tester.widget<ChoiceChip>(find.byKey(const Key('setup-level-B1')))
            .selected,
        isTrue,
      );
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('setup-replay')))
            .value,
        isTrue,
      );
      expect(find.text('10'), findsOneWidget);
    });
  });

  group('SetupScreen at a large OS text scale (UI-01)', () {
    testWidgets('scrolls instead of overflowing, footer intact',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: SetupScreen(
              databaseHelper: _EmptyDatabaseHelper(),
              questionSource: FakeQuestionSource(),
            ),
          ),
        ),
      );
      // Two frames — see `pumpSetup` for why the subjects need the second one.
      await tester.pump();
      await tester.pump();

      // A RenderFlex overflow THROWS in a test — so this is the assertion.
      expect(tester.takeException(), isNull);

      // The footer is pinned outside the scroll view, so the CTA and its
      // blocked-reason line are both on screen before any scrolling.
      expect(find.byKey(const Key('setup-start')), findsOneWidget);
      expect(find.byKey(const Key('setup-start-blocked')), findsOneWidget);

      // And the body genuinely scrolls rather than clipping the tail off.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('setup-start')), findsOneWidget);
    });
  });
}
