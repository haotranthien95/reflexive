// The starter bank, checked against the importer that will actually read it.
//
// **Why this test exists rather than a shell one-liner.** Every other check on
// `seed/seed-questions.json` — row counts, cell coverage, distinct triples — can
// be written in a few lines of `node`, and the plan's acceptance criteria are.
// But those checks re-state the importer's rules in a second language, and a
// second statement of a rule is free to drift from the one the app actually
// runs. This test states nothing: it calls `parseImportFile` and
// `dedupeAgainstBank` themselves, so "the seed is importable" is measured by the
// code that will import it (D-53, D-54, D-62).
//
// It is also a standing guard. A regenerated topic that quietly introduces a
// lower-case level, a padded subject or a repeated question fails here, in
// `flutter test`, rather than on a device halfway through a 600-row write.
library;

import 'dart:convert';
import 'dart:io';

import 'package:englishreflex/services/firestore_question_source.dart';
import 'package:englishreflex/services/question_importer.dart';
import 'package:englishreflex/services/question_bank_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ten topics, in the order `seed/README.md` and
/// `docs/QUESTION_GENERATION_PROMPT.md` both list them.
///
/// Written out here rather than derived from the file, so a topic renamed in the
/// seed is a failing test rather than a silently updated expectation.
const List<String> _kSeedSubjects = <String>[
  'Daily Life',
  'Travel',
  'Food & Dining',
  'Work & Career',
  'Health & Fitness',
  'Education',
  'Technology',
  'Family & Relationships',
  'Sports',
  'Entertainment & Hobbies',
];

const int _kQuestionsPerCell = 10;

void main() {
  late String seedJson;

  setUpAll(() {
    // `flutter test` runs with the package root as its working directory. The
    // seed is NOT a Flutter asset (it is never bundled — see seed/README.md), so
    // it is read as an ordinary repo file rather than through rootBundle.
    final file = File('seed/seed-questions.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'seed/seed-questions.json is missing — the starter bank (IMPORT-05) '
          'is the only way back from the one-way D-58 wipe.',
    );
    seedJson = file.readAsStringSync();
  });

  group('seed/seed-questions.json, read by the shipped importer', () {
    test('parses with no file-level problem and skips no row', () {
      final parse = parseImportFile(seedJson);

      expect(
        parse.skips,
        isEmpty,
        reason: 'Every row of the shipped seed must be importable. A skip here '
            'is a row the user would be told about on the import sheet.',
      );
      expect(parse.rows, hasLength(parse.totalRows));
      expect(
        parse.totalRows,
        _kSeedSubjects.length * kLevels.length * _kQuestionsPerCell,
      );
    });

    test('normalization is a no-op — the file is already in canonical form', () {
      // parseImportFile trims content and subject and upper-cases level (D-53).
      // The seed should need none of that: what is in the repo is what lands in
      // Firestore, so a diff of the file is a diff of the bank.
      final decoded = jsonDecode(seedJson) as Map<String, dynamic>;
      final raw = (decoded['data'] as List<dynamic>).cast<Map<String, dynamic>>();
      final parsed = parseImportFile(seedJson).rows;

      expect(parsed, hasLength(raw.length));
      for (var i = 0; i < raw.length; i++) {
        expect(parsed[i].content, raw[i]['content'],
            reason: 'row ${i + 1}: content was altered by normalization');
        expect(parsed[i].subject, raw[i]['subject'],
            reason: 'row ${i + 1}: subject was altered by normalization');
        expect(parsed[i].level, raw[i]['level'],
            reason: 'row ${i + 1}: level was altered by normalization');
      }
    });

    test('against an empty bank every row survives the dedupe pass', () {
      final plan = dedupeAgainstBank(parseImportFile(seedJson), const <String>{});

      expect(
        plan.duplicateCount,
        0,
        reason: 'Two seed rows share a content/subject/level triple, so the '
            'second would be silently dropped as a duplicate (D-54).',
      );
      expect(plan.rowsToWrite, hasLength(plan.totalRows));
      expect(plan.skips, isEmpty);
    });

    test('re-importing the seed adds nothing the second time', () {
      final first = dedupeAgainstBank(
        parseImportFile(seedJson),
        const <String>{},
      );
      final bankAfterFirstImport = first.rowsToWrite
          .map((r) => importDedupeKey(r.content, r.subject, r.level))
          .toSet();

      final second = dedupeAgainstBank(
        parseImportFile(seedJson),
        bankAfterFirstImport,
      );

      expect(second.rowsToWrite, isEmpty);
      expect(second.duplicateCount, first.totalRows);
    });

    test('ten topics at all six levels, ten questions in every cell', () {
      final rows = parseImportFile(seedJson).rows;

      expect(
        rows.map((r) => r.subject).toSet(),
        _kSeedSubjects.toSet(),
        reason: 'A subject string that drifts from the generation prompt forks '
            'the topic list into two checkboxes for one topic (D-53).',
      );

      for (final subject in _kSeedSubjects) {
        for (final level in kLevels) {
          expect(
            rows.where((r) => r.subject == subject && r.level == level).length,
            _kQuestionsPerCell,
            reason: '$subject x $level does not hold $_kQuestionsPerCell '
                'questions — a topic-by-level combination the user can pick '
                'would come up short on a fresh bank.',
          );
        }
      }
    });

    test('is larger than one write batch, so the chunked commit path runs', () {
      // D-57: seeding the bank and proving the importer are the same act. The
      // multi-chunk commit is the half of the writer no host test can reach, so
      // the seed has to be the thing that crosses the cap on a real device.
      expect(
        parseImportFile(seedJson).totalRows,
        greaterThan(kMaxWritesPerBatch),
      );
    });

    test('no row content carries a newline, tab or carriage return', () {
      // The skip list renders echoed question text on one line (sanitizedEcho),
      // but the seed should not rely on that boundary to look right in a diff or
      // in the Firestore console.
      for (final row in parseImportFile(seedJson).rows) {
        expect(
          RegExp(r'[\n\r\t]').hasMatch(row.content),
          isFalse,
          reason: 'content contains a control character: ${row.content}',
        );
      }
    });
  });
}
