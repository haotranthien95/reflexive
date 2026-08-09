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

/// A scriptable [QuestionSource] — the seam D-47 puts every read state behind.
///
/// **Both methods complete synchronously** (`async` with no real `await`). That
/// is deliberate and load-bearing for the same reason `_EmptyDatabaseHelper`
/// exists: `testWidgets` runs on a fake clock that drains microtasks but never
/// yields to the real event loop, so a `Future.delayed` here would never resolve
/// and every test in this file would hang on a topics card that never fills.
class _FakeQuestionSource implements QuestionSource {
  _FakeQuestionSource({
    this.bankSubjects = _kTestSubjects,
    this.bankQuestions = const <String>['A fake prompt.'],
  });

  final List<String> bankSubjects;
  final List<String> bankQuestions;

  /// Proves a re-read happened, and how many times.
  int subjectsCallCount = 0;

  @override
  Future<List<String>> subjects() async {
    subjectsCallCount++;
    return bankSubjects;
  }

  @override
  Future<List<String>> questionsFor(SessionConfig config) async =>
      bankQuestions;
}

/// A source that fails the test if it is ever asked anything.
///
/// Stands in for the production [FirestoreQuestionSource] in the one test that
/// is about the seam itself rather than about the screen.
class _ExplodingQuestionSource implements QuestionSource {
  @override
  Future<List<String>> subjects() async =>
      throw StateError('the injected source must be the one that is used');

  @override
  Future<List<String>> questionsFor(SessionConfig config) async =>
      throw StateError('the injected source must be the one that is used');
}

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

  Widget host({List<String>? subjects}) => MaterialApp(
        theme: _testTheme(),
        home: SetupScreen(
          databaseHelper: _EmptyDatabaseHelper(),
          recordingService:
              RecordingService(backend: _SilentRecorderBackend()),
          audioPlayerService:
              AudioPlayerService(backend: _SilentPlaybackBackend()),
          // Injecting a whole source, not a subject list: the subject list moved
          // behind the `QuestionSource` seam when Phase 3 sourced it from
          // Firestore. Passing one here is also what proves production's
          // `FirestoreQuestionSource` is never constructed under `flutter test`
          // — see the `_ExplodingQuestionSource` test below.
          questionSource: _FakeQuestionSource(
            bankSubjects: subjects ?? _kTestSubjects,
          ),
        ),
      );

  /// A tall PORTRAIT surface so every control is laid out and hit-testable
  /// without scrolling first. The 800x600 landscape default is not a shape this
  /// app ever ships in, and the height is what keeps the slider drags below
  /// from needing an `ensureVisible` dance. The text-scale case deliberately
  /// uses a REALISTIC surface instead — overflow is the whole point there.
  Future<void> pumpSetup(
    WidgetTester tester, {
    List<String>? subjects,
    Size size = const Size(400, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(subjects: subjects));
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
      await pumpSetup(tester, subjects: const <String>[]);

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
      // If `SetupScreen` ever built its own `FirestoreQuestionSource`, this test
      // would fail on a missing Firebase app rather than on this source's throw
      // — and either way it would fail, which is the point: no `flutter test`
      // run may reach a Firestore handle.
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: SetupScreen(
            databaseHelper: _EmptyDatabaseHelper(),
            questionSource: _ExplodingQuestionSource(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The injected source threw, that throw was contained and logged, and the
      // screen is still standing — nothing reached the platform.
      expect(find.byKey(const Key('setup-start')), findsOneWidget);
      expect(find.byKey(const Key('setup-topics-empty')), findsOneWidget);
    });

    testWidgets('the checkboxes are exactly the bank\'s subjects, in the '
        'order the bank gave them', (tester) async {
      // `SetupScreen` renders its source's list verbatim: ordering, de-duping
      // and blank-dropping belong to the source (see `normalizeSubjects`), so
      // the screen has one job and it is this one.
      await pumpSetup(
        tester,
        subjects: normalizeSubjects(<Object?>[
          'Travel',
          'daily life',
          'Travel', // an exact duplicate: one checkbox
          '   ', // blank: no checkbox
          null, // not a String: no checkbox
          'Work & study',
        ]),
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
      await pumpSetup(tester, subjects: const <String>['Travel']);

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
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: SetupScreen(
            databaseHelper: _EmptyDatabaseHelper(),
            recordingService:
                RecordingService(backend: _SilentRecorderBackend()),
            audioPlayerService:
                AudioPlayerService(backend: _SilentPlaybackBackend()),
            questionSource: _FakeQuestionSource(bankQuestions: questions),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
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
              questionSource: _FakeQuestionSource(),
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
