import 'dart:async';
import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/screens/import_sheet.dart';
import 'package:englishreflex/screens/setup_screen.dart';
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
class FakeQuestionBankWriter implements QuestionBankWriter {
  FakeQuestionBankWriter({
    List<Object>? keyOutcomes,
    this.holdExistingKeys = false,
    this.holdWrite = false,
  }) : keyOutcomes = keyOutcomes ?? <Object>[<String>{}];

  final List<Object> keyOutcomes;
  final bool holdExistingKeys;
  final bool holdWrite;

  /// D-54 reads the bank ONCE per import. This is what makes that a real
  /// assertion rather than an intention.
  int existingKeysCallCount = 0;
  int writeCallCount = 0;

  /// Every row handed to [write], in the order it arrived — the assertion that
  /// pins D-63's file-order contract.
  final List<ImportRow> written = <ImportRow>[];

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
    // One completed "commit", reported only once it is done — the real writer's
    // contract, modelled rather than approximated.
    onProgress?.call(rows.length, rows.length);
    return rows.length;
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
