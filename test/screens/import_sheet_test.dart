import 'dart:async';
import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/screens/import_sheet.dart';
import 'package:englishreflex/screens/setup_screen.dart';
import 'package:englishreflex/services/firestore_question_source.dart';
import 'package:englishreflex/services/json_file_picker.dart';
import 'package:englishreflex/services/question_bank_writer.dart';
import 'package:englishreflex/services/question_importer.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/import_files.dart';
// The scripted question source is imported, not copied. A second copy of a
// double is a second model of the rule it stands for, free to drift from the one
// the code is actually tested against.
import 'setup_screen_test.dart' show FakeQuestionSource;

/// Drives the WHOLE import path on the host, with both platform seams faked:
/// the Setup AppBar action, the sheet, the pure importer, the dedupe read, the
/// chunked write and the dismissal refresh.
///
/// **What is deliberately NOT covered here, and why.** The two adapters —
/// `FilePickerJsonFilePicker` and `FirestoreQuestionBankWriter` — are not
/// host-testable and are not meant to be (D-47): one reaches a file-picker
/// platform channel and the other resolves `FirebaseFirestore.instance`, neither
/// of which a `flutter test` process can construct. `fake_cloud_firestore` was
/// rejected for the same reason the read adapter rejected it — it does not model
/// the real backend's limits, so a passing test would not prove the real commit
/// runs. Both are proven by the on-device seed import in plan 04-05.
///
/// What this file DOES prove is everything between the two seams, which is where
/// all of the judgement lives.

/// The scripted file picker.
///
/// Built to [FakeQuestionSource]'s shape exactly: a list of per-call outcomes
/// where a `String` (or `null`, meaning the user cancelled) is returned and
/// anything else is thrown, with the last entry repeating once the script runs
/// out.
///
/// **Completes synchronously by default.** `testWidgets` runs on a fake clock
/// that drains microtasks but never yields to the real event loop, so a
/// `Future.delayed` here would never resolve and every test in this file would
/// hang on a sheet that never leaves its idle state.
class FakeJsonFilePicker implements JsonFilePicker {
  FakeJsonFilePicker({List<Object?>? outcomes, this.holdPick = false})
      : outcomes = outcomes ?? <Object?>[kFixtureThreeRowImport];

  final List<Object?> outcomes;
  final bool holdPick;

  /// Proves the picker was reached, and how many times.
  int callCount = 0;

  Completer<void>? _gate;

  void releasePick() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<String?> pickJsonText() async {
    final callIndex = callCount++;
    if (holdPick) {
      await (_gate = Completer<void>()).future;
    }
    final outcome =
        outcomes[callIndex < outcomes.length ? callIndex : outcomes.length - 1];
    if (outcome == null) return null;
    if (outcome is String) return outcome;
    throw outcome;
  }
}

/// The scripted bank writer.
///
/// Same shape and the same synchronous-by-default rule as [FakeJsonFilePicker].
/// The two [Completer] gates are how the in-flight "Comparing with your bank…"
/// and "Saving…" frames become assertable rather than a race with the harness.
///
/// **The write path is CHUNKED, not approximated.** It walks the rows in
/// [kMaxWritesPerBatch]-sized chunks and reports progress once per completed
/// chunk, exactly as `FirestoreQuestionBankWriter.write` does — which is the
/// only way the multi-chunk progress path and the partial-write outcome are
/// reachable without a device. A fake that reported one commit for any row count
/// would have made the 501-row case indistinguishable from the 3-row case, which
/// is precisely the case worth testing.
class FakeQuestionBankWriter implements QuestionBankWriter {
  FakeQuestionBankWriter({
    List<Object>? keyOutcomes,
    this.holdExistingKeys = false,
    this.holdWrite = false,
    this.failAfterChunks,
  }) : keyOutcomes = keyOutcomes ?? <Object>[<String>{}];

  final List<Object> keyOutcomes;
  final bool holdExistingKeys;
  final bool holdWrite;

  /// How many chunks commit before the write fails, or null for a write that
  /// succeeds.
  ///
  /// **The failure it then throws is derived, not scripted**, by the real
  /// writer's own rule: nothing committed means nothing landed and the bank is
  /// simply unreachable; something committed means a partial write carrying the
  /// exact counts. Scripting the exception instead would let a test assert a
  /// count the production writer would never have produced.
  final int? failAfterChunks;

  /// D-54 reads the bank ONCE per import. This is what makes that a real
  /// assertion rather than an intention.
  int existingKeysCallCount = 0;
  int writeCallCount = 0;

  /// Every row handed to [write], in the order it arrived — the assertion that
  /// pins D-63's file-order contract.
  final List<ImportRow> written = <ImportRow>[];

  /// Every `(committed, total)` pair reported, in order. A progress report that
  /// ran ahead of a commit would show up here as an extra pair.
  final List<List<int>> progressReports = <List<int>>[];

  Completer<void>? _keysGate;
  Completer<void>? _writeGate;

  void releaseExistingKeys() {
    final gate = _keysGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void releaseWrite() {
    final gate = _writeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<Set<String>> existingKeys() async {
    final callIndex = existingKeysCallCount++;
    if (holdExistingKeys) {
      await (_keysGate = Completer<void>()).future;
    }
    final outcome = keyOutcomes[
        callIndex < keyOutcomes.length ? callIndex : keyOutcomes.length - 1];
    if (outcome is Set<String>) return outcome;
    throw outcome;
  }

  @override
  Future<int> write(
    List<ImportRow> rows, {
    void Function(int committed, int total)? onProgress,
  }) async {
    writeCallCount++;
    written.addAll(rows);
    if (holdWrite) {
      await (_writeGate = Completer<void>()).future;
    }

    final total = rows.length;
    var committed = 0;
    var chunks = 0;
    for (var start = 0; start < total; start += kMaxWritesPerBatch) {
      if (chunks == failAfterChunks) {
        if (committed == 0) throw const QuestionBankUnavailableException();
        throw ImportPartialWriteException(done: committed, total: total);
      }
      final end = start + kMaxWritesPerBatch < total
          ? start + kMaxWritesPerBatch
          : total;
      committed = end;
      chunks++;
      // Reported only once the "commit" is done — never optimistically per row.
      progressReports.add(<int>[committed, total]);
      onProgress?.call(committed, total);
    }
    return committed;
  }
}

/// A database double with no engine behind it.
///
/// A local copy rather than an import: the sibling Setup test's equivalent is
/// private to that file, and making it public would mean editing a file this
/// plan does not own. Setup only ever asks the database which audio files are
/// still referenced, for the orphan sweep, and nothing under test here depends
/// on the answer.
class _EmptyDatabaseHelper extends DatabaseHelper {
  @override
  Future<Set<String>> listReferencedAudioPaths() async => <String>{};

  @override
  Future<List<Session>> listSessions() async => <Session>[];
}

/// The app's theme, rebuilt locally for the same reason the sibling Setup test
/// rebuilds it: `EnglishReflexApp` composes its `ThemeData` inline inside
/// `build`, so there is no seam to import it through. Baloo 2 is replaced by the
/// default family so the test never depends on a font asset — what matters here
/// is that theme-derived styles RESOLVE, not which glyphs they draw.
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

List<List<String>> _asRows(List<ImportRow> rows) => rows
    .map((row) => <String>[row.content, row.subject, row.level])
    .toList(growable: false);

/// The sheet's eight state keys, as a closed list.
///
/// Written out here rather than derived from the private `_ImportPhase` enum
/// precisely so it is a SECOND statement of the same fact: if a state is added
/// to the sheet without a key, or a key is renamed, this list stops matching and
/// [expectOnlyState] starts failing. A list computed from the code under test
/// would agree with it no matter what it said.
const List<String> kSheetStateKeys = <String>[
  'import-idle',
  'import-checking',
  'import-writing',
  'import-result',
  'import-file-problem',
  'import-empty-file',
  'import-unreachable',
  'import-partial',
];

/// Asserts the sheet is showing [expected] and, just as importantly, NONE of the
/// other seven.
///
/// The sheet's whole honesty contract rests on the eight states being mutually
/// exclusive: a populated result that could also render a busy affordance, or an
/// error icon beside its summary, would be the app telling the user two
/// different things at once. Every state test in this file goes through here, so
/// "no test can find two of the eight keys in the same pumped frame" is enforced
/// on every frame any test looks at rather than in one dedicated test.
void expectOnlyState(String expected) {
  assert(kSheetStateKeys.contains(expected), 'unknown state key: $expected');
  for (final key in kSheetStateKeys) {
    expect(
      find.byKey(Key(key)),
      key == expected ? findsOneWidget : findsNothing,
      reason: key == expected
          ? 'expected the sheet to be showing $key'
          : '$key must not be on screen at the same time as $expected',
    );
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_import');
    Directory('${tempDir.path}/$kRecordingsDirName').createSync(recursive: true);
    documentsDirProvider = () async => tempDir;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpSetup(
    WidgetTester tester, {
    required FakeQuestionSource source,
    required FakeJsonFilePicker picker,
    required FakeQuestionBankWriter writer,
  }) async {
    // A tall PORTRAIT surface, so the sheet's whole body — including its 64px
    // button — is laid out and hit-testable without an `ensureVisible` dance.
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: _testTheme(),
      home: SetupScreen(
        databaseHelper: _EmptyDatabaseHelper(),
        questionSource: source,
        jsonFilePicker: picker,
        questionBankWriter: writer,
      ),
    ));
    // TWO frames: the first lands before `_loadSubjects()`'s future has drained.
    await tester.pump();
    await tester.pump();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('setup-import')));
    await tester.pumpAndSettle();
  }

  group('the import path, end to end', () {
    testWidgets(
        'AppBar action → pick a file → the count that landed → new topics',
        (tester) async {
      final source = FakeQuestionSource();
      final picker = FakeJsonFilePicker();
      final writer = FakeQuestionBankWriter();
      await pumpSetup(
          tester, source: source, picker: picker, writer: writer);

      final subjectsBefore = source.subjectsCallCount;

      // 1. The AppBar action opens the sheet on its IDLE state — the sheet
      //    first, then the picker (D-50). Nothing has been read yet.
      await openSheet(tester);
      expect(find.byKey(const Key('import-idle')), findsOneWidget);
      expect(find.text(kImportIdleMessage), findsOneWidget);
      expect(picker.callCount, 0,
          reason: 'the picker must not open until the user asks for it');

      // 2. The one action on the idle state runs the whole import.
      await tester.tap(find.byKey(const Key('import-choose-file')));
      await tester.pumpAndSettle();

      expect(picker.callCount, 1);
      expect(writer.existingKeysCallCount, 1,
          reason: 'the dedupe read is issued exactly once per import (D-54)');
      expect(writer.writeCallCount, 1);

      // 3. The writer received the NORMALIZED rows, in FILE order (D-53/D-63).
      expect(_asRows(writer.written), kFixtureThreeRowExpected);

      // 4. The result names the count the server acknowledged.
      expect(find.byKey(const Key('import-result')), findsOneWidget);
      expect(find.text('3 questions added'), findsOneWidget);

      // 5. Done closes the sheet, and the dismissal — not the button — is what
      //    re-reads the topics (D-51).
      await tester.tap(find.byKey(const Key('import-done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-result')), findsNothing);
      expect(find.byKey(const Key('import-idle')), findsNothing);
      expect(source.subjectsCallCount, subjectsBefore + 1);
    });

    testWidgets('a one-row file writes one document and says so',
        (tester) async {
      final picker =
          FakeJsonFilePicker(outcomes: <Object?>[kFixtureSingleRowImport]);
      final writer = FakeQuestionBankWriter();
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: picker,
        writer: writer,
      );

      await openSheet(tester);
      await tester.tap(find.byKey(const Key('import-choose-file')));
      await tester.pumpAndSettle();

      expect(writer.written, hasLength(1));
      expect(find.text('1 question added'), findsOneWidget);
    });

    testWidgets('a cancelled pick is not a failure and gets no copy',
        (tester) async {
      final picker = FakeJsonFilePicker(outcomes: <Object?>[null]);
      final writer = FakeQuestionBankWriter();
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: picker,
        writer: writer,
      );

      await openSheet(tester);
      await tester.tap(find.byKey(const Key('import-choose-file')));
      await tester.pumpAndSettle();

      expect(picker.callCount, 1);
      // Straight back to the idle body, with the format hint exactly where it
      // was, and nothing read or written.
      expect(find.byKey(const Key('import-idle')), findsOneWidget);
      expect(find.text(kImportIdleMessage), findsOneWidget);
      expect(writer.existingKeysCallCount, 0);
      expect(writer.writeCallCount, 0);
    });
  });

  group('the in-flight states', () {
    testWidgets('the bank read renders its own caption, not the file one',
        (tester) async {
      final writer = FakeQuestionBankWriter(holdExistingKeys: true);
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: FakeJsonFilePicker(),
        writer: writer,
      );

      await openSheet(tester);
      await tester.tap(find.byKey(const Key('import-choose-file')));
      // `pump`, never `pumpAndSettle`: the checking state carries an
      // indeterminate spinner, which schedules a frame forever.
      await tester.pump();

      expect(find.byKey(const Key('import-checking')), findsOneWidget);
      expect(find.text(kImportCheckingBankMessage), findsOneWidget);
      expect(find.text(kImportCheckingFileMessage), findsNothing);

      writer.releaseExistingKeys();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-result')), findsOneWidget);
    });

    testWidgets('the write state is captioned, shows a bar and holds the sheet',
        (tester) async {
      final writer = FakeQuestionBankWriter(holdWrite: true);
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: FakeJsonFilePicker(),
        writer: writer,
      );

      await openSheet(tester);
      await tester.tap(find.byKey(const Key('import-choose-file')));
      await tester.pump();

      expect(find.byKey(const Key('import-writing')), findsOneWidget);
      expect(find.text(importSavingMessage(3)), findsOneWidget);
      expect(find.text(kImportKeepOpenMessage), findsOneWidget);
      // The bar starts empty: no row is reported before a commit completes.
      expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const Key('import-writing-progress')))
            .value,
        0.0,
      );
      // The one state the sheet refuses to leave — a user who closes mid-write
      // never learns which rows landed (IMPORT-04).
      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse,
      );

      writer.releaseWrite();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-result')), findsOneWidget);
      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isTrue,
      );
    });
  });

  /// Opens the sheet and runs the import to whatever terminal state it reaches.
  ///
  /// Every state group below starts the same way, so the differences between
  /// them are the fakes and the assertions rather than the choreography.
  Future<void> runImport(
    WidgetTester tester, {
    required FakeJsonFilePicker picker,
    required FakeQuestionBankWriter writer,
    FakeQuestionSource? source,
  }) async {
    await pumpSetup(
      tester,
      source: source ?? FakeQuestionSource(),
      picker: picker,
      writer: writer,
    );
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('import-choose-file')));
    await tester.pumpAndSettle();
  }

  group('the idle state', () {
    testWidgets('opens on the format hint and exactly one action',
        (tester) async {
      final picker = FakeJsonFilePicker();
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: picker,
        writer: FakeQuestionBankWriter(),
      );
      await openSheet(tester);

      expectOnlyState('import-idle');
      expect(find.text(kImportIdleMessage), findsOneWidget);
      expect(find.text(kImportShapeExample), findsOneWidget);
      expect(find.byKey(const Key('import-choose-file')), findsOneWidget);
      // Nothing has been read: the sheet comes BEFORE the picker (D-50).
      expect(picker.callCount, 0);
      // The idle state is not a failure state and carries no fault marking.
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });
  });

  group('the result state', () {
    testWidgets('a clean import shows one summary line and no skip section',
        (tester) async {
      await runImport(
        tester,
        picker: FakeJsonFilePicker(),
        writer: FakeQuestionBankWriter(),
      );

      expectOnlyState('import-result');
      expect(find.text('3 questions added'), findsOneWidget);
      // Both zero-suppressed lines are absent, and so is the whole skip section.
      expect(find.textContaining('already in your bank'), findsNothing);
      expect(find.textContaining('was skipped'), findsNothing);
      expect(find.textContaining('rows were skipped'), findsNothing);
      expect(find.text(kImportSkipListLabel), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets(
        'a mixed import reports all three lines and names each skipped row',
        (tester) async {
      final bankKey = importDedupeKey(
        kFixtureMixedOutcomeBankKey[0],
        kFixtureMixedOutcomeBankKey[1],
        kFixtureMixedOutcomeBankKey[2],
      );
      await runImport(
        tester,
        picker: FakeJsonFilePicker(outcomes: <Object?>[kFixtureMixedOutcome]),
        writer: FakeQuestionBankWriter(keyOutcomes: <Object>[
          <String>{bankKey},
        ]),
      );

      expectOnlyState('import-result');

      // Every one of the file's six rows is accounted for: 2 + 1 + 3 (IMPORT-04).
      final added = find.text(importAddedLine(2));
      final duplicates = find.text(importDuplicatesLine(1));
      final skipped = find.text(importSkippedLine(3));
      expect(added, findsOneWidget);
      expect(duplicates, findsOneWidget);
      expect(skipped, findsOneWidget);

      // FIXED order — added, then already-in-bank, then skipped — so the same
      // fact is always in the same place across imports.
      expect(tester.getTopLeft(added).dy,
          lessThan(tester.getTopLeft(duplicates).dy));
      expect(tester.getTopLeft(duplicates).dy,
          lessThan(tester.getTopLeft(skipped).dy));

      // One keyed row per skip, at its 1-based position in the FILE — not its
      // position in the skip list, which would be 1, 2, 3.
      expect(find.text(kImportSkipListLabel), findsOneWidget);
      expect(find.byKey(const Key('import-skip-row-3')), findsOneWidget);
      expect(find.byKey(const Key('import-skip-row-5')), findsOneWidget);
      expect(find.byKey(const Key('import-skip-row-6')), findsOneWidget);
      for (final absent in <int>[1, 2, 4]) {
        expect(find.byKey(Key('import-skip-row-$absent')), findsNothing);
      }

      expect(find.text('Row 3 · level "B7" isn\'t one of A1–C2'), findsOneWidget);
      expect(find.text('Row 5 · no question text'), findsOneWidget);
      expect(find.text('Row 6 · not shaped like a question'), findsOneWidget);

      // A row WITH usable text echoes it; the two without omit the sub-line
      // entirely rather than rendering an empty one.
      expect(
        find.text('Describe a time you had to change plans.'),
        findsOneWidget,
      );
      for (final row in <int>[5, 6]) {
        expect(
          find.descendant(
            of: find.byKey(Key('import-skip-row-$row')),
            matching: find.byType(Text),
          ),
          findsOneWidget,
          reason: 'row $row has nothing to echo, so it is a one-line block',
        );
      }

      // A duplicate is a neutral COUNT and is never enumerated: listing 400 of
      // them would bury the three rows that actually need an edit.
      expect(find.textContaining('Already there.'), findsNothing);
      // And it is never marked as a fault.
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('a pathological level value is capped before it is quoted back',
        (tester) async {
      await runImport(
        tester,
        picker:
            FakeJsonFilePicker(outcomes: <Object?>[kFixturePathologicalLevel]),
        writer: FakeQuestionBankWriter(),
      );

      expectOnlyState('import-result');
      // Twelve characters and an ellipsis — the whole reason line stays the
      // length of its template plus the cap, whatever the file contained.
      expect(
        find.text('Row 1 · level "ABCDEFGHIJKL…" isn\'t one of A1–C2'),
        findsOneWidget,
      );
      expect(find.textContaining('ABCDEFGHIJKLABCDEFGHIJKL'), findsNothing);
    });

    testWidgets('newlines in question text cannot break a skip row',
        (tester) async {
      await runImport(
        tester,
        picker:
            FakeJsonFilePicker(outcomes: <Object?>[kFixtureNewlinesInQuestion]),
        writer: FakeQuestionBankWriter(),
      );

      expectOnlyState('import-result');
      final echo = find.text(kFixtureNewlinesCollapsed);
      expect(echo, findsOneWidget);
      // Not merely "it fits": the raw control characters are gone, and the
      // widget is pinned to one ellipsised line.
      final text = tester.widget<Text>(echo);
      expect(text.data, isNot(contains('\n')));
      expect(text.data, isNot(contains('\r')));
      expect(text.data, isNot(contains('\t')));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('the file cannot be used', () {
    testWidgets('a file that could not be OPENED shows no format example',
        (tester) async {
      final writer = FakeQuestionBankWriter();
      await runImport(
        tester,
        picker: FakeJsonFilePicker(
          outcomes: <Object?>[const ImportFileUnreadableException()],
        ),
        writer: writer,
      );

      expectOnlyState('import-file-problem');
      expect(
        find.byKey(const Key('import-file-problem-unreadable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-file-problem-shape')), findsNothing);
      expect(find.text(kImportUnreadableFileMessage), findsOneWidget);
      // Telling the user "it needs to look like this" about a file the app
      // never read would be a false explanation.
      expect(find.text(kImportShapeExample), findsNothing);
      expect(
        find.byKey(const Key('import-choose-different-file')),
        findsOneWidget,
      );
      expect(writer.existingKeysCallCount, 0);
      expect(writer.writeCallCount, 0);
    });

    testWidgets('a file that is not a question file DOES show the example',
        (tester) async {
      final writer = FakeQuestionBankWriter();
      await runImport(
        tester,
        picker: FakeJsonFilePicker(outcomes: <Object?>[kFixtureNoDataKey]),
        writer: writer,
      );

      expectOnlyState('import-file-problem');
      expect(
        find.byKey(const Key('import-file-problem-shape')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('import-file-problem-unreadable')),
        findsNothing,
      );
      expect(find.text(kImportBadShapeMessage), findsOneWidget);
      expect(find.text(kImportShapeExample), findsOneWidget);
      // The file was rejected before a single row was examined (D-62), so
      // nothing was read from the bank and nothing was written.
      expect(writer.existingKeysCallCount, 0);
      expect(writer.writeCallCount, 0);
    });

    testWidgets('choosing a different file restarts the import in the sheet',
        (tester) async {
      final picker = FakeJsonFilePicker(
        outcomes: <Object?>[kFixtureNotJson, kFixtureSingleRowImport],
      );
      await runImport(
        tester,
        picker: picker,
        writer: FakeQuestionBankWriter(),
      );
      expectOnlyState('import-file-problem');

      await tester.tap(find.byKey(const Key('import-choose-different-file')));
      await tester.pumpAndSettle();

      expectOnlyState('import-result');
      expect(find.text('1 question added'), findsOneWidget);
      expect(picker.callCount, 2);
    });
  });

  group('the file is empty', () {
    testWidgets('an empty data list is an empty STATE, not a failure',
        (tester) async {
      final writer = FakeQuestionBankWriter();
      await runImport(
        tester,
        picker: FakeJsonFilePicker(outcomes: <Object?>[kFixtureEmptyData]),
        writer: writer,
      );

      expectOnlyState('import-empty-file');
      expect(find.text(kImportEmptyFileMessage), findsOneWidget);
      expect(find.text(kImportEmptyFileBody), findsOneWidget);
      // Empty is not wrong: no icon and no red anywhere in this state.
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(
        find.byKey(const Key('import-choose-different-file')),
        findsOneWidget,
      );
      expect(writer.existingKeysCallCount, 0);
      expect(writer.writeCallCount, 0);
    });
  });

  group('the bank could not be reached', () {
    testWidgets('a failed bank read says that nothing was imported',
        (tester) async {
      final writer = FakeQuestionBankWriter(
        keyOutcomes: <Object>[const QuestionBankUnavailableException()],
      );
      await runImport(
        tester,
        picker: FakeJsonFilePicker(),
        writer: writer,
      );

      expectOnlyState('import-unreachable');
      expect(find.text(kImportUnreachableMessage), findsOneWidget);
      expect(find.byKey(const Key('import-retry')), findsOneWidget);
      // The claim in the copy has to be true: the read gates the write, so not
      // one document went out.
      expect(writer.writeCallCount, 0);
    });

    testWidgets('retry resumes from the bank read and never re-opens the picker',
        (tester) async {
      final picker = FakeJsonFilePicker();
      final writer = FakeQuestionBankWriter(keyOutcomes: <Object>[
        const QuestionBankUnavailableException(),
        <String>{},
      ]);
      await runImport(tester, picker: picker, writer: writer);
      expectOnlyState('import-unreachable');
      expect(picker.callCount, 1);

      await tester.tap(find.byKey(const Key('import-retry')));
      await tester.pumpAndSettle();

      expectOnlyState('import-result');
      expect(find.text('3 questions added'), findsOneWidget);
      // The file was already read and parsed; only the network failed. Making a
      // briefly-offline user hunt for their file again would charge them for it.
      expect(picker.callCount, 1);
      expect(writer.existingKeysCallCount, 2);
    });

    testWidgets('a write that fails before its FIRST chunk is not a partial',
        (tester) async {
      await runImport(
        tester,
        picker: FakeJsonFilePicker(),
        writer: FakeQuestionBankWriter(failAfterChunks: 0),
      );

      // Nothing committed means nothing landed, which is the unreachable fact
      // and not the partial one.
      expectOnlyState('import-unreachable');
      expect(find.text(kImportUnreachableMessage), findsOneWidget);
    });
  });

  group('a partial write', () {
    testWidgets('a chunk failing after an earlier one reports exact counts',
        (tester) async {
      final rowCount = kMaxWritesPerBatch + 1;
      await runImport(
        tester,
        picker: FakeJsonFilePicker(
          outcomes: <Object?>[kFixtureRowsBeyondBatchCap(rowCount)],
        ),
        writer: FakeQuestionBankWriter(failAfterChunks: 1),
      );

      expectOnlyState('import-partial');
      expect(
        find.text(importPartialMessage(kMaxWritesPerBatch, rowCount)),
        findsOneWidget,
      );
      // The success-shaped summary card is NOT reused for a partial write.
      expect(find.text(importAddedLine(kMaxWritesPerBatch)), findsNothing);
      expect(
        find.byKey(const Key('import-choose-different-file')),
        findsOneWidget,
      );

      // Done is still the single exit, even though this state has two buttons.
      await tester.tap(find.byKey(const Key('import-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-partial')), findsNothing);
    });
  });

  group('the write is chunked', () {
    testWidgets('a file larger than one batch commits in chunks',
        (tester) async {
      final rowCount = kMaxWritesPerBatch + 1;
      final writer = FakeQuestionBankWriter();
      await runImport(
        tester,
        picker: FakeJsonFilePicker(
          outcomes: <Object?>[kFixtureRowsBeyondBatchCap(rowCount)],
        ),
        writer: writer,
      );

      expectOnlyState('import-result');
      expect(find.text(importAddedLine(rowCount)), findsOneWidget);
      // Two commits, each reported only once it completed — never a per-row
      // optimistic advance.
      expect(writer.progressReports, <List<int>>[
        <int>[kMaxWritesPerBatch, rowCount],
        <int>[rowCount, rowCount],
      ]);
    });
  });

  group('dismissal while a write is in flight', () {
    testWidgets('a barrier tap is refused mid-write and honoured afterwards',
        (tester) async {
      final writer = FakeQuestionBankWriter(holdWrite: true);
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: FakeJsonFilePicker(),
        writer: writer,
      );
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('import-choose-file')));
      await tester.pump();
      expectOnlyState('import-writing');

      // Well above the sheet, which sits at the bottom of a 2000px surface.
      await tester.tapAt(const Offset(200, 10));
      await tester.pump();
      await tester.pump();
      expectOnlyState('import-writing');

      writer.releaseWrite();
      await tester.pumpAndSettle();
      expectOnlyState('import-result');

      await tester.tapAt(const Offset(200, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-result')), findsNothing);
    });

    testWidgets('the route refuses to pop mid-write and agrees afterwards',
        (tester) async {
      final writer = FakeQuestionBankWriter(holdWrite: true);
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: FakeJsonFilePicker(),
        writer: writer,
      );
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('import-choose-file')));
      await tester.pump();

      // `Navigator.maybePop` is the single mechanism BOTH the system back
      // gesture and the barrier tap route through on the pinned Flutter
      // version, so exercising it here IS exercising the back gesture.
      //
      // The assertion is on the sheet still being there, NOT on maybePop's
      // return value: it returns true for a refused pop as well as an accepted
      // one, because true means "handled" rather than "popped". Asserting the
      // boolean would have looked stricter and proved nothing.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expectOnlyState('import-writing');

      writer.releaseWrite();
      await tester.pumpAndSettle();
      expectOnlyState('import-result');

      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-result')), findsNothing);
    });

    testWidgets('the sheet body claims vertical drags only while writing',
        (tester) async {
      final writer = FakeQuestionBankWriter(holdWrite: true);
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: FakeJsonFilePicker(),
        writer: writer,
      );
      await openSheet(tester);

      ScrollPhysics? sheetPhysics() => tester
          .widget<SingleChildScrollView>(find.descendant(
            of: find.byType(ImportSheet),
            matching: find.byType(SingleChildScrollView),
          ))
          .physics;

      // Idle: the sheet's own drag-to-dismiss is welcome.
      expect(sheetPhysics(), isNull);

      await tester.tap(find.byKey(const Key('import-choose-file')));
      await tester.pump();
      expectOnlyState('import-writing');
      // Writing: the body always accepts the drag, so it wins the gesture arena
      // against the sheet's dismiss recognizer, which pops the route directly
      // and never consults PopScope on this Flutter version.
      expect(sheetPhysics(), isA<AlwaysScrollableScrollPhysics>());

      writer.releaseWrite();
      await tester.pumpAndSettle();
      expect(sheetPhysics(), isNull);
    });
  });

  group('a failure never costs the user their setup', () {
    // Every terminal failure, driven through the same before/after comparison.
    // A failure that silently reset a topic, a level or a slider would be the
    // app charging the user for its own bad day.
    final scenarios = <String, FakeQuestionBankWriter Function()>{
      'import-file-problem': FakeQuestionBankWriter.new,
      'import-empty-file': FakeQuestionBankWriter.new,
      'import-unreachable': () => FakeQuestionBankWriter(
            keyOutcomes: <Object>[const QuestionBankUnavailableException()],
          ),
      'import-partial': () => FakeQuestionBankWriter(failAfterChunks: 1),
    };
    final files = <String, String>{
      'import-file-problem': kFixtureNotJson,
      'import-empty-file': kFixtureEmptyData,
      'import-unreachable': kFixtureThreeRowImport,
      'import-partial': kFixtureRowsBeyondBatchCap(kMaxWritesPerBatch + 1),
    };

    for (final state in scenarios.keys) {
      testWidgets('$state leaves every Setup value where it was',
          (tester) async {
        await pumpSetup(
          tester,
          source: FakeQuestionSource(),
          picker: FakeJsonFilePicker(outcomes: <Object?>[files[state]]),
          writer: scenarios[state]!(),
        );

        // A configuration the user would be annoyed to lose.
        await tester.tap(find.byKey(const Key('setup-topic-Travel')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('setup-level-C1')));
        await tester.pump();
        final countBefore =
            tester.widget<Slider>(find.byKey(const Key('setup-count-slider')));
        final levelBefore =
            tester.widget<ChoiceChip>(find.byKey(const Key('setup-level-C1')));
        expect(levelBefore.selected, isTrue);

        await openSheet(tester);
        await tester.tap(find.byKey(const Key('import-choose-file')));
        await tester.pumpAndSettle();
        expectOnlyState(state);

        // Out through the barrier — the exit route a user takes when a failure
        // has told them there is nothing more to do here.
        await tester.tapAt(const Offset(200, 10));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<CheckboxListTile>(
                  find.byKey(const Key('setup-topic-Travel')))
              .value,
          isTrue,
        );
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('setup-level-C1')))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<Slider>(find.byKey(const Key('setup-count-slider')))
              .value,
          countBefore.value,
        );
      });
    }
  });

  group('the Setup AppBar', () {
    testWidgets('carries exactly two always-enabled actions, import first',
        (tester) async {
      await pumpSetup(
        tester,
        source: FakeQuestionSource(),
        picker: FakeJsonFilePicker(),
        writer: FakeQuestionBankWriter(),
      );

      final actions = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      );
      expect(actions, findsNWidgets(2));

      final buttons = tester.widgetList<IconButton>(actions).toList();
      // Import is PREPENDED, so the History action does not move (D-48).
      expect((buttons.first.icon as Icon).icon, Icons.upload_file);
      expect(buttons.first.tooltip, 'Import questions');
      expect((buttons.last.icon as Icon).icon, Icons.history);
      // Neither is ever disabled, and neither is conditional on data.
      for (final button in buttons) {
        expect(button.onPressed, isNotNull);
      }
    });
  });
}
