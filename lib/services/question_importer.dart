/// The import's pure parse / normalize / validate / dedupe core.
///
/// **Nothing in this file touches a platform.** No Firestore handle, no `File`,
/// no `BuildContext`, no widget import — that is what makes it the analog of
/// [sanitizedText] and [normalizeSubjects] rather than of
/// `FirestoreQuestionSource`. Host-testability stops at the seam (D-47), so the
/// one piece of judgement in the feature is extracted to this side of it while
/// the two adapters around it (`json_file_picker.dart`,
/// `question_bank_writer.dart`) stay thin and are proven on-device.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'firestore_question_source.dart';

/// Why a single row of the file was not imported (D-55).
///
/// A closed set, so the sheet's reason copy is a total map over it rather than
/// an if-chain with a fallback nobody can name.
///
/// **A duplicate is deliberately NOT in this enum.** A row already in the bank
/// is counted in [ImportPlan.duplicateCount] and never appears in a skip list:
/// it is a neutral fact, not a problem the user has to fix (D-54).
enum ImportSkipReason {
  /// The entry in `data` was not a JSON object at all.
  notAnObject,

  /// `content` was missing, not a string, or blank after trimming.
  blankContent,

  /// `subject` was missing, not a string, or blank after trimming.
  blankSubject,

  /// `level` was not one of the six values in [kLevels] after trimming and
  /// upper-casing.
  badLevel,
}

/// One question the import will write, already NORMALIZED (D-53).
///
/// The values here are the values that land in Firestore — trimmed content and
/// subject, upper-cased level — so nothing downstream has to re-apply the rule
/// or wonder whether it was applied.
@immutable
class ImportRow {
  const ImportRow({
    required this.content,
    required this.subject,
    required this.level,
  });

  final String content;
  final String subject;
  final String level;

  /// Value equality, so a test can compare a whole expected row list in one
  /// `expect` rather than field by field.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportRow &&
          other.content == content &&
          other.subject == subject &&
          other.level == level;

  @override
  int get hashCode => Object.hash(content, subject, level);

  @override
  String toString() =>
      'ImportRow(content: $content, subject: $subject, level: $level)';
}

/// One row the import refused, and everything the sheet needs to explain it.
@immutable
class ImportSkip {
  const ImportSkip({
    required this.rowNumber,
    required this.reason,
    this.offendingLevel,
    this.questionText,
  });

  /// The row's **1-based** position in the file's `data` list (D-55).
  ///
  /// One-based, not zero-based, because this number's whole job is to be
  /// findable in the user's editor — and no text editor numbers its first line
  /// zero. A reason without a location tells the user a *shape* of problem, not
  /// a *place*.
  final int rowNumber;

  final ImportSkipReason reason;

  /// The user's RAW level text, carried only for [ImportSkipReason.badLevel] so
  /// the message can quote it back. Untrusted: the render site caps its length
  /// and strips newlines (UI-SPEC "Untrusted Input").
  final String? offendingLevel;

  /// The row's raw content when there was usable text to echo, else `null`.
  ///
  /// `null` rather than an empty string, so the sheet omits the sub-line
  /// entirely instead of rendering a blank one.
  final String? questionText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportSkip &&
          other.rowNumber == rowNumber &&
          other.reason == reason &&
          other.offendingLevel == offendingLevel &&
          other.questionText == questionText;

  @override
  int get hashCode =>
      Object.hash(rowNumber, reason, offendingLevel, questionText);

  @override
  String toString() => 'ImportSkip(row $rowNumber, $reason)';
}

/// The result of reading the file, BEFORE the bank has been consulted.
@immutable
class ImportParse {
  const ImportParse({
    required this.rows,
    required this.skips,
    required this.totalRows,
  });

  /// Every valid row, in file order. Order is load-bearing — D-63 turns it into
  /// bank order.
  final List<ImportRow> rows;

  final List<ImportSkip> skips;

  /// How many entries the file's `data` list had, valid or not.
  final int totalRows;
}

/// The result of reading the file AND comparing it with the bank — the complete
/// decision set, made before a single document is written (D-52).
@immutable
class ImportPlan {
  const ImportPlan({
    required this.rowsToWrite,
    required this.skips,
    required this.duplicateCount,
    required this.totalRows,
  });

  /// The rows that will actually be written, in FILE ORDER (D-63 depends on it).
  final List<ImportRow> rowsToWrite;

  final List<ImportSkip> skips;

  /// Rows dropped because the same question already exists — in the bank, or
  /// earlier in this same file. Its own category, never an error (D-54).
  final int duplicateCount;

  final int totalRows;
}

/// Thrown when the file is not shaped like a question file at all (D-62).
///
/// Not valid JSON, a top-level value that is not an object, no `data` key, or a
/// `data` value that is not a list. **No row was examined**, which is why this
/// is a different fact from any per-row skip and gets its own state with no
/// counts and no row list.
///
/// A *signal*, not a crash; its text is developer-facing and never rendered.
class ImportFileShapeException implements Exception {
  const ImportFileShapeException();

  @override
  String toString() => 'ImportFileShapeException';
}

/// Thrown when the file parsed correctly but its `data` list is empty (D-62).
///
/// **A separate type from [ImportFileShapeException] on purpose.** The file
/// being *empty* and the file being *wrong* are two different facts, and this
/// project keeps them apart everywhere else too — it is the same
/// empty-versus-unreadable split D-37 established for the bank, applied one
/// level down at the file. Collapsing them would make one message stand for a
/// corrupt download and for a file the user simply has not filled in yet.
class ImportFileEmptyException implements Exception {
  const ImportFileEmptyException();

  @override
  String toString() => 'ImportFileEmptyException';
}

/// The separator inside a dedupe key: the zero code unit.
///
/// A printable separator — a pipe, a slash, a colon — can occur inside a real
/// question, subject or level, and then two different rows can produce the same
/// key. A validated field can never contain U+0000, because it arrived through
/// `jsonDecode` and passed [sanitizedText], so this one cannot collide.
const String _kKeySeparator = '\u0000';

/// The D-54 identity of a question: content + subject + level, NORMALIZED.
///
/// Exported so the bank-side read in `question_bank_writer.dart` and the
/// file-side pass here build the same key from the same rule. Two spellings of
/// the same key rule is how a dedupe pass ends up letting duplicates through.
///
/// The three values must already be normalized ([sanitizedText]-trimmed content
/// and subject, upper-cased level); this function does not normalize, so that
/// there is exactly one place the normalization rule lives.
String importDedupeKey(String content, String subject, String level) =>
    '$content$_kKeySeparator$subject$_kKeySeparator$level';

const String _kContentField = 'content';
const String _kSubjectField = 'subject';
const String _kLevelField = 'level';
const String _kDataField = 'data';

/// Reads and validates the WHOLE file in memory, before anything is written
/// (D-52).
///
/// The write phase is left with nothing to decide: every accept/reject
/// judgement is already made when the first document goes out, which is how
/// IMPORT-04's "never silently or partially" is satisfied. A user with 97 good
/// rows and 3 bad ones keeps the 97.
///
/// **Normalize, then validate (D-53), and the NORMALIZED values are what get
/// written.** `content` and `subject` are trimmed with [sanitizedText] — the
/// existing rule, imported rather than rewritten — and `level` is trimmed and
/// upper-cased. Trimming on WRITE is safe precisely because it stops `Travel`,
/// ` Travel` and `travel ` from ever coexisting in the bank; that is the mirror
/// of why [normalizeSubjects] deliberately does NOT trim on READ, where a
/// trimmed checkbox label would match a stored untrimmed subject in nothing.
///
/// *Validate strictly and write verbatim was the runner-up and was rejected:*
/// nothing the user wrote would ever be silently altered, but an AI-generated
/// file emitting `"b1"` would cost the whole batch, and a single trailing space
/// that slipped through would silently fork a topic into two checkboxes with no
/// in-app way to merge them again.
///
/// **Check order is content, then subject, then level**, so a row with two
/// problems always reports the same one and the skip list is deterministic.
///
/// Throws [ImportFileShapeException] for a file that is not a question file and
/// [ImportFileEmptyException] for one whose `data` list is empty.
ImportParse parseImportFile(String jsonText) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } on FormatException catch (error) {
    debugPrint('Import file rejected: not valid JSON ($error).');
    throw const ImportFileShapeException();
  }

  if (decoded is! Map) {
    debugPrint('Import file rejected: the top-level value is a '
        '${decoded.runtimeType}, not an object.');
    throw const ImportFileShapeException();
  }
  if (!decoded.containsKey(_kDataField)) {
    debugPrint('Import file rejected: no `$_kDataField` key.');
    throw const ImportFileShapeException();
  }
  final Object? data = decoded[_kDataField];
  if (data is! List) {
    debugPrint('Import file rejected: `$_kDataField` is a '
        '${data.runtimeType}, not a list.');
    throw const ImportFileShapeException();
  }
  if (data.isEmpty) {
    debugPrint('Import file has an empty `$_kDataField` list — EMPTY, not '
        'malformed.');
    throw const ImportFileEmptyException();
  }

  final rows = <ImportRow>[];
  final skips = <ImportSkip>[];

  for (var i = 0; i < data.length; i++) {
    final rowNumber = i + 1; // 1-based, D-55.
    final Object? entry = data[i];

    if (entry is! Map) {
      skips.add(ImportSkip(
        rowNumber: rowNumber,
        reason: ImportSkipReason.notAnObject,
      ));
      continue;
    }

    final Object? rawContent = entry[_kContentField];
    final Object? rawSubject = entry[_kSubjectField];
    final Object? rawLevel = entry[_kLevelField];

    // Echoed back to the user only when it is genuinely text; a non-string
    // `content` has nothing quotable in it.
    final String? echoableContent = rawContent is String && rawContent.isNotEmpty
        ? rawContent
        : null;

    final String? content = sanitizedText(rawContent);
    if (content == null) {
      skips.add(ImportSkip(
        rowNumber: rowNumber,
        reason: ImportSkipReason.blankContent,
        questionText: echoableContent,
      ));
      continue;
    }

    final String? subject = sanitizedText(rawSubject);
    if (subject == null) {
      skips.add(ImportSkip(
        rowNumber: rowNumber,
        reason: ImportSkipReason.blankSubject,
        questionText: echoableContent,
      ));
      continue;
    }

    final String? level = sanitizedText(rawLevel)?.toUpperCase();
    if (level == null || !kLevels.contains(level)) {
      skips.add(ImportSkip(
        rowNumber: rowNumber,
        reason: ImportSkipReason.badLevel,
        // The user's RAW text, not the upper-cased one: quoting back something
        // they did not type is a worse hint than quoting what they did.
        offendingLevel: rawLevel is String ? rawLevel : null,
        questionText: echoableContent,
      ));
      continue;
    }

    rows.add(ImportRow(content: content, subject: subject, level: level));
  }

  return ImportParse(rows: rows, skips: skips, totalRows: data.length);
}

/// Drops every row the bank already has, and every repeat inside the file
/// itself (D-54).
///
/// [existingKeys] is the bank's questions as [importDedupeKey] values, read
/// once per import from the SERVER (D-60). A row whose key is in that set, or
/// which an EARLIER row of the same file already produced, is counted in
/// [ImportPlan.duplicateCount] and dropped.
///
/// **Duplicates are their own category and are never listed per row and never
/// treated as an error.** Enumerating 400 duplicate rows would bury the 3 rows
/// that actually need an edit, and a user re-importing a file should feel
/// reassured rather than warned: re-importing is harmless by construction, which
/// is the whole point of doing this pass at all.
///
/// Surviving rows keep FILE ORDER, untouched — D-63 turns that order into bank
/// order.
ImportPlan dedupeAgainstBank(ImportParse parsed, Set<String> existingKeys) {
  final seen = <String>{...existingKeys};
  final rowsToWrite = <ImportRow>[];
  var duplicates = 0;

  for (final row in parsed.rows) {
    final key = importDedupeKey(row.content, row.subject, row.level);
    if (!seen.add(key)) {
      duplicates++;
      continue;
    }
    rowsToWrite.add(row);
  }

  return ImportPlan(
    rowsToWrite: rowsToWrite,
    skips: parsed.skips,
    duplicateCount: duplicates,
    totalRows: parsed.totalRows,
  );
}
