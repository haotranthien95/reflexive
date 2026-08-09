import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/models/session_config.dart';
import 'package:englishreflex/screens/practice_screen.dart';
import 'package:englishreflex/screens/setup_screen.dart';
import 'package:englishreflex/services/audio_player_service.dart';
import 'package:englishreflex/services/recording_service.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
          subjects: subjects,
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
            child: SetupScreen(databaseHelper: _EmptyDatabaseHelper()),
          ),
        ),
      );
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
