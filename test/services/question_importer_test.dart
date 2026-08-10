import 'package:englishreflex/screens/import_sheet.dart';
import 'package:englishreflex/services/question_bank_writer.dart';
import 'package:englishreflex/services/question_importer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/import_files.dart';

/// Pins every rule the importer decides — and nothing that needs a device.
///
/// **What is deliberately NOT covered here, and why.** The two adapters around
/// this core are not host-testable and are not meant to be (D-47):
/// `FilePickerJsonFilePicker` reaches a file-picker platform channel and
/// `FirestoreQuestionBankWriter` resolves `FirebaseFirestore.instance`, neither
/// of which a `flutter test` process can construct. `fake_cloud_firestore` was
/// rejected for the same reason the read adapter rejected it — it does not model
/// the real backend's limits, so a passing test would not prove the real commit
/// runs — and the Firestore emulator is an external process well beyond this
/// project's tooling footprint. Both adapters, including the multi-chunk write
/// and the `Source.server` dedupe read, are proven by the on-device seed import
/// in plan 04-05. `test/screens/import_sheet_test.dart` covers everything
/// between the two seams.
///
/// That is precisely why [parseImportFile] and [dedupeAgainstBank] were
/// extracted as free functions: they are the whole of the judgement in this
/// feature, and pulled out here they can be pinned with no Firestore handle and
/// no widget.
void main() {
  group('parseImportFile — the file itself (D-62)', () {
    test('text that is not JSON at all is a FILE problem', () {
      expect(() => parseImportFile(kFixtureNotJson),
          throwsA(isA<ImportFileShapeException>()));
    });

    test('a top-level list rather than an object is a FILE problem', () {
      expect(() => parseImportFile(kFixtureTopLevelList),
          throwsA(isA<ImportFileShapeException>()));
    });

    test('an object with no data key is a FILE problem', () {
      expect(() => parseImportFile(kFixtureNoDataKey),
          throwsA(isA<ImportFileShapeException>()));
    });

    test('an object whose data value is not a list is a FILE problem', () {
      expect(() => parseImportFile(kFixtureDataNotAList),
          throwsA(isA<ImportFileShapeException>()));
    });

    test('an EMPTY data list is a different signal from a wrong file', () {
      // The whole point of the split: "that file has no questions in it" and
      // "that file isn't shaped like a question file" are two different facts,
      // and one message for both would say the same thing about a corrupt
      // download as about a file the user simply has not filled in yet. Asserted
      // as `isNot` too, because the two types passing the same `isA` check is
      // exactly the regression this guards.
      expect(() => parseImportFile(kFixtureEmptyData),
          throwsA(isA<ImportFileEmptyException>()));
      expect(() => parseImportFile(kFixtureEmptyData),
          throwsA(isNot(isA<ImportFileShapeException>())));
    });
  });

  group('parseImportFile — normalization (D-53)', () {
    test('content and subject are stripped, and the STRIPPED values land', () {
      final parsed = parseImportFile(kFixtureThreeRowImport);

      expect(parsed.rows, hasLength(3));
      expect(
        parsed.rows.map((r) => <String>[r.content, r.subject, r.level]).toList(),
        kFixtureThreeRowExpected,
      );
      expect(parsed.skips, isEmpty);
      expect(parsed.totalRows, 3);
    });

    test('a lower-case or mixed-case level is upper-cased and accepted', () {
      final parsed = parseImportFile(kFixtureMixedCaseLevels);

      expect(parsed.skips, isEmpty);
      expect(parsed.rows.map((r) => r.level).toList(), <String>['B1', 'C2', 'A2']);
    });

    test('two spellings that differ only by whitespace produce the SAME row',
        () {
      // This is the whole reason normalization happens on WRITE. Left alone,
      // these two rows would become two questions and — worse — ` Travel` and
      // `Travel` would become two topic checkboxes, which `normalizeSubjects`
      // deliberately refuses to paper over at read time because a trimmed
      // checkbox label would match the stored untrimmed subject in nothing.
      final parsed = parseImportFile(kFixturePaddedTwins);

      expect(parsed.rows, hasLength(2));
      expect(parsed.rows.first, parsed.rows.last);
      expect(parsed.rows.first.subject, 'Travel');
    });
  });

  group('parseImportFile — rejection, by reason and by position (D-55)', () {
    test('an entry that is not an object is skipped, at its 1-based position',
        () {
      final parsed = parseImportFile(kFixtureRowsNotObjects);

      expect(parsed.rows, hasLength(1));
      expect(parsed.skips.map((s) => s.rowNumber).toList(), <int>[1, 2]);
      for (final skip in parsed.skips) {
        expect(skip.reason, ImportSkipReason.notAnObject);
      }
      expect(parsed.totalRows, 3);
    });

    test('the two malformed documents retired from the Phase 3 dev seed', () {
      // D-58 wipes the dev seed; the edge coverage its two deliberately broken
      // documents provided lives in the fixtures now. Row 1 has no `content`
      // key at all, row 2's is whitespace only — and row 3 proves that neither
      // takes out the good row beside them (D-52).
      final parsed = parseImportFile(kFixtureRetiredMalformedRows);

      expect(parsed.skips, hasLength(2));
      expect(parsed.skips[0].rowNumber, 1);
      expect(parsed.skips[0].reason, ImportSkipReason.blankContent);
      expect(parsed.skips[1].rowNumber, 2);
      expect(parsed.skips[1].reason, ImportSkipReason.blankContent);
      expect(parsed.rows.single.content, 'A perfectly good question.');
    });

    test('a non-string content is skipped, not coerced', () {
      final parsed = parseImportFile(kFixtureNonStringContent);

      expect(parsed.rows, isEmpty);
      expect(parsed.skips.single.reason, ImportSkipReason.blankContent);
      expect(parsed.skips.single.rowNumber, 1);
      // Nothing quotable: a number has no question text to echo back, so the
      // sheet omits the sub-line rather than rendering "1999".
      expect(parsed.skips.single.questionText, isNull);
    });

    test('a missing or blank subject is skipped, at its position', () {
      final parsed = parseImportFile(kFixtureBlankSubjects);

      expect(parsed.rows, isEmpty);
      expect(parsed.skips.map((s) => s.rowNumber).toList(), <int>[1, 2]);
      for (final skip in parsed.skips) {
        expect(skip.reason, ImportSkipReason.blankSubject);
      }
    });

    test('a level outside A1–C2 is skipped and its RAW text is carried', () {
      final parsed = parseImportFile(kFixtureBadLevel);

      expect(parsed.rows, isEmpty);
      final skip = parsed.skips.single;
      expect(skip.rowNumber, 1);
      expect(skip.reason, ImportSkipReason.badLevel);
      // The user's own text, so the message can quote it back — that is the
      // fastest way for them to find the row in their editor.
      expect(skip.offendingLevel, 'B7');
      expect(skip.questionText, 'Describe a time you had to change plans.');
    });

    test('a row with two problems reports the CONTENT one, deterministically',
        () {
      // Check order is content, then subject, then level. Without a fixed order
      // the same file could report different reasons on different runs, and a
      // skip list the user cannot reproduce is a skip list they cannot act on.
      final parsed = parseImportFile(kFixtureBlankContentAndBadLevel);

      expect(parsed.skips.single.reason, ImportSkipReason.blankContent);
    });
  });

  group('dedupeAgainstBank (D-54)', () {
    test('a row already in the bank is a duplicate, not a skip', () {
      final parsed = parseImportFile(kFixtureSingleRowImport);
      final existing = <String>{
        importDedupeKey(
          'What is the first thing you do after waking up?',
          'Daily life',
          'A1',
        ),
      };

      final plan = dedupeAgainstBank(parsed, existing);

      expect(plan.rowsToWrite, isEmpty);
      expect(plan.duplicateCount, 1);
      // A duplicate is a neutral fact, never a problem to fix: it must not
      // appear in the list of rows the user is being asked to edit.
      expect(plan.skips, isEmpty);
    });

    test('a row repeated later in the same file keeps the FIRST copy', () {
      final plan = dedupeAgainstBank(
        parseImportFile(kFixtureRepeatedWithinFile),
        <String>{},
      );

      expect(plan.rowsToWrite, hasLength(1));
      expect(plan.duplicateCount, 2);
      expect(plan.skips, isEmpty);
      expect(plan.totalRows, 3);
    });

    test('an empty bank key set keeps every row', () {
      final plan = dedupeAgainstBank(
        parseImportFile(kFixtureThreeRowImport),
        <String>{},
      );

      expect(plan.rowsToWrite, hasLength(3));
      expect(plan.duplicateCount, 0);
    });

    test('the surviving rows are still in FILE order', () {
      // D-63 turns file order into bank order, so a dedupe pass that reorders
      // the survivors would silently reorder the bank.
      final parsed = parseImportFile(kFixtureFourOrderedRows);
      final existing = <String>{
        importDedupeKey('Second.', 'Travel', 'A1'),
      };

      final plan = dedupeAgainstBank(parsed, existing);

      expect(
        plan.rowsToWrite.map((r) => r.content).toList(),
        <String>['First.', 'Third.', 'Fourth.'],
      );
      expect(plan.duplicateCount, 1);
    });

    test('skips survive the dedupe pass untouched', () {
      final parsed = parseImportFile(kFixtureRetiredMalformedRows);

      final plan = dedupeAgainstBank(parsed, <String>{});

      expect(plan.skips, parsed.skips);
      expect(plan.totalRows, 3);
    });
  });

  group('importDedupeKey', () {
    test('two rows differing only in level produce different keys', () {
      expect(
        importDedupeKey('A question.', 'Travel', 'A1'),
        isNot(importDedupeKey('A question.', 'Travel', 'A2')),
      );
    });

    test('the separator cannot be forged out of field content', () {
      // With a printable separator — a pipe, a slash, a colon — these two rows
      // would build the SAME key and one would silently vanish as a "duplicate"
      // of the other. The zero code unit cannot appear in a value that arrived
      // through `jsonDecode` and passed `sanitizedText`, so the split is
      // unambiguous.
      expect(
        importDedupeKey('a', 'b|c', 'A1'),
        isNot(importDedupeKey('a|b', 'c', 'A1')),
      );
      expect(
        importDedupeKey('a', 'b', 'A1'),
        isNot(importDedupeKey('a b', '', 'A1')),
      );
    });
  });

  group('kMaxWritesPerBatch', () {
    test("is Firestore's documented per-batch operation cap", () {
      // Pinned so a change forces a deliberate decision rather than a silent
      // drift between this constant and the server. **Unlike
      // `kMaxTopicsPerQuery`, this one is NOT asserted by the installed SDK at
      // all**: cloud_firestore 6.8.0's `WriteBatch` checks only that each
      // document belongs to the same Firestore instance, not how many
      // operations the batch carries — not even in debug. This constant and the
      // chunking around it are the only client-side guard there is.
      expect(kMaxWritesPerBatch, 500);
    });
  });

  group('the count strings', () {
    test('importAddedLine has a zero, a singular and a plural branch', () {
      // "0 questions added" reads like a bug where "No questions added" reads
      // like an outcome — and a zero result is entirely normal here, because a
      // file whose rows were all already in the bank adds nothing and is a
      // complete success.
      expect(importAddedLine(0), 'No questions added');
      expect(importAddedLine(1), '1 question added');
      expect(importAddedLine(85), '85 questions added');
    });

    test('importSavingMessage has a singular and a plural branch', () {
      expect(importSavingMessage(1), 'Saving 1 question to your bank…');
      expect(importSavingMessage(600), 'Saving 600 questions to your bank…');
    });
  });
}
