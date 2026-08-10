/// Test-only import files, owned by `test/` and shipped nowhere.
///
/// **These are fixtures, not seed content.** Nothing in `lib/` may import this
/// file — the app has exactly one question source and it is Firestore, and the
/// only JSON the app ever reads is a file the user picks at runtime. The
/// `kFixture` prefix is what makes a reader of any test body able to tell at a
/// glance that the data is scaffolding rather than something the app ships.
///
/// **Ordering is load-bearing wherever an assertion depends on it.** D-63 turns
/// file order into bank order, so a test that asserts which rows the writer
/// received, and in what sequence, is asserting against the literal order of the
/// `data` array in the string below. Reordering an array here silently moves
/// those expectations.
///
/// **The two deliberately malformed rows are a migration, not an invention.**
/// D-58 wipes the Phase 3 dev seed, which carried two documents that existed
/// only to be broken — one with no `content` field at all, one whose `content`
/// was whitespace only. The edge-path coverage they provided lives here now,
/// which is exactly what D-58 promises when the seed is deleted.
library;

/// Three valid rows, no duplicates, nothing to skip — the happy path.
///
/// Deliberately mixes a padded `content`, a padded `subject` and a lower-case
/// `level` into row 2, so the end-to-end test's assertion on what reached the
/// writer also proves D-53's normalization ran on the way through rather than
/// being a separate unit-test-only concern.
const String kFixtureThreeRowImport = '''
{"data": [
  {"content": "What did you do this morning?", "subject": "Daily life", "level": "A2"},
  {"content": "  Describe a journey that did not go as planned.  ", "subject": "  Travel  ", "level": "b1"},
  {"content": "Is it better to plan everything or to improvise?", "subject": "Opinions", "level": "C1"}
]}
''';

/// The normalized rows [kFixtureThreeRowImport] must produce, in file order.
///
/// Spelled out as three flat lists rather than built from the JSON above,
/// because a fixture that derives its own expectation cannot catch a
/// normalization bug — both sides would move together.
const List<List<String>> kFixtureThreeRowExpected = <List<String>>[
  <String>['What did you do this morning?', 'Daily life', 'A2'],
  <String>['Describe a journey that did not go as planned.', 'Travel', 'B1'],
  <String>['Is it better to plan everything or to improvise?', 'Opinions', 'C1'],
];

/// Exactly one valid row — the IMPORT-03 lower boundary: one document written,
/// and the singular branch of every count string.
const String kFixtureSingleRowImport = '''
{"data": [
  {"content": "What is the first thing you do after waking up?", "subject": "Daily life", "level": "A1"}
]}
''';

/// The two malformed documents retired from the Phase 3 dev seed (D-58), now
/// carried as import rows: row 1 has no `content` key at all, row 2's `content`
/// is whitespace only. Both must be skipped with `blankContent`, at 1-based
/// positions 1 and 2. Row 3 is valid, so the file also proves that bad rows do
/// not take out the good ones (D-52).
const String kFixtureRetiredMalformedRows = '''
{"data": [
  {"subject": "Daily life", "level": "B1"},
  {"subject": "Travel", "level": "A1", "content": "   \\n\\t  "},
  {"content": "A perfectly good question.", "subject": "Travel", "level": "A1"}
]}
''';

// ── File-shape fixtures (D-62) ───────────────────────────────────────────────
// Each of the four below is a DIFFERENT way of not being a question file, and
// all four must land on the one file-shape signal. The empty one is separate on
// purpose: a file being empty and a file being wrong are two different facts.

/// Not JSON at all — the shape of a text file picked by mistake.
const String kFixtureNotJson = 'this is not JSON, it is a sentence';

/// Valid JSON whose top-level value is a LIST, not an object — the shape of a
/// file someone wrote as a bare array of questions.
const String kFixtureTopLevelList =
    '[{"content": "A question.", "subject": "Travel", "level": "A1"}]';

/// A valid JSON object with no `data` key — the shape of a file that used a
/// different name for the array.
const String kFixtureNoDataKey =
    '{"questions": [{"content": "A question.", "subject": "Travel", "level": "A1"}]}';

/// `data` present but not a list.
const String kFixtureDataNotAList = '{"data": "a string, not a list"}';

/// `data` present, well formed and EMPTY — the file-empty signal, not the
/// file-shape one.
const String kFixtureEmptyData = '{"data": []}';

// ── Normalization fixtures (D-53) ────────────────────────────────────────────

/// Two rows whose `content` and `subject` differ ONLY by surrounding
/// whitespace. Normalizing on write is what stops them becoming two questions
/// and two topic checkboxes.
const String kFixturePaddedTwins = '''
{"data": [
  {"content": "Where would you go?", "subject": "Travel", "level": "B1"},
  {"content": "  Where would you go?  ", "subject": " Travel\\t", "level": "B1"}
]}
''';

/// Levels in every casing an AI-generated file realistically emits. All three
/// are unambiguous and are accepted after upper-casing.
const String kFixtureMixedCaseLevels = '''
{"data": [
  {"content": "Question one.", "subject": "Travel", "level": "b1"},
  {"content": "Question two.", "subject": "Travel", "level": "c2"},
  {"content": "Question three.", "subject": "Travel", "level": " a2 "}
]}
''';

// ── Rejection fixtures (D-55) ────────────────────────────────────────────────

/// Row 1 is a bare string rather than an object; row 2 is a number. Neither is
/// shaped like a question. Row 3 is valid, so the 1-based numbering of the two
/// skips is genuinely being counted rather than guessed.
const String kFixtureRowsNotObjects = '''
{"data": [
  "just a string",
  42,
  {"content": "A perfectly good question.", "subject": "Travel", "level": "A1"}
]}
''';

/// Row 1's `content` is a number rather than text — a shape `sanitizedText`
/// rejects and one an AI emitting a bare year could produce.
const String kFixtureNonStringContent = '''
{"data": [
  {"content": 1999, "subject": "Travel", "level": "A1"}
]}
''';

/// Row 1 has no `subject`; row 2's is whitespace only. Both are unusable as a
/// topic, and a question with no topic is unpickable on Setup.
const String kFixtureBlankSubjects = '''
{"data": [
  {"content": "A question.", "level": "A1"},
  {"content": "Another question.", "subject": "   ", "level": "A1"}
]}
''';

/// `B7` is not a CEFR level. The raw text is quoted back to the user, so the
/// skip has to carry it.
const String kFixtureBadLevel = '''
{"data": [
  {"content": "Describe a time you had to change plans.", "subject": "Travel", "level": "B7"}
]}
''';

/// Row 1 is wrong in TWO ways — blank content AND a bad level. The check order
/// is content, then subject, then level, so the reported reason is
/// deterministic rather than whichever check happened to run first.
const String kFixtureBlankContentAndBadLevel = '''
{"data": [
  {"content": "  ", "subject": "Travel", "level": "Z9"}
]}
''';

// ── Dedupe fixtures (D-54) ───────────────────────────────────────────────────

/// The same question three times, spelled two ways: rows 1 and 3 are identical
/// and row 2 differs only by padding, so after normalization all three are one
/// question. The FIRST is kept and the two later ones are counted as
/// duplicates — never skipped, never an error.
const String kFixtureRepeatedWithinFile = '''
{"data": [
  {"content": "What did you do this morning?", "subject": "Daily life", "level": "A2"},
  {"content": " What did you do this morning? ", "subject": "Daily life", "level": "A2"},
  {"content": "What did you do this morning?", "subject": "Daily life", "level": "A2"}
]}
''';

/// Four valid rows in a deliberate order, used to prove the surviving rows keep
/// FILE order after the middle one is deduped away. **Ordering is load-bearing
/// here** — D-63 turns it into bank order.
const String kFixtureFourOrderedRows = '''
{"data": [
  {"content": "First.", "subject": "Travel", "level": "A1"},
  {"content": "Second.", "subject": "Travel", "level": "A1"},
  {"content": "Third.", "subject": "Travel", "level": "A1"},
  {"content": "Fourth.", "subject": "Travel", "level": "A1"}
]}
''';

// ── Whole-report fixtures (IMPORT-04) ────────────────────────────────────────
// The rows above each exercise ONE rule. The ones below exercise the report:
// every row of the file has to be accounted for in one of the three categories,
// and the three have to be tellable apart on screen.

/// All three outcomes in ONE file, so a single import produces a summary card
/// with all three lines and a skip list with all three reasons.
///
/// Row 1 and row 4 are new; row 2 is [kFixtureMixedOutcomeBankKey], already in
/// the bank; rows 3, 5 and 6 are skipped for three DIFFERENT reasons at three
/// non-adjacent positions — which is what makes the 1-based numbering in the
/// skip list genuinely counted rather than an index that happens to line up.
///
/// Expected report: 2 added, 1 duplicate, 3 skipped at rows 3, 5 and 6.
const String kFixtureMixedOutcome = '''
{"data": [
  {"content": "First new question.", "subject": "Travel", "level": "A1"},
  {"content": "Already there.", "subject": "Travel", "level": "B1"},
  {"content": "Describe a time you had to change plans.", "subject": "Travel", "level": "B7"},
  {"content": "Second new question.", "subject": "Opinions", "level": "C1"},
  {"subject": "Daily life", "level": "A2"},
  "just a string"
]}
''';

/// The three normalized field values of [kFixtureMixedOutcome]'s row 2.
///
/// Spelled out here rather than in the test body so the fixture and the bank
/// state it is deduped against cannot drift apart: a test builds the bank's key
/// set from these through `importDedupeKey`, which is the same function the
/// import itself uses.
const List<String> kFixtureMixedOutcomeBankKey = <String>[
  'Already there.',
  'Travel',
  'B1',
];

/// A `level` value 240 characters long — twenty times the 12-character echo cap.
///
/// **The layout-integrity case, not a validation case.** The row is skipped for
/// its level either way; what this fixture exercises is the render site, which
/// must truncate the quoted value before it reaches a widget. The repeating
/// 12-character block is deliberate: the first block is exactly the cap, so an
/// assertion can name the expected prefix without counting characters.
final String kFixturePathologicalLevel = '''
{"data": [
  {"content": "A perfectly good question.", "subject": "Travel", "level": "${'ABCDEFGHIJKL' * 20}"}
]}
''';

/// Question text carrying a newline, a carriage return and a tab.
///
/// The row is skipped for its level, so its content is echoed back in the skip
/// row's sub-line — which is the surface that must collapse all three to single
/// spaces. A raw newline reaching that widget would break the one-line row the
/// whole skip list is laid out around.
const String kFixtureNewlinesInQuestion = '''
{"data": [
  {"content": "Line one.\\nLine two.\\r\\nLine three.\\tTabbed.", "subject": "Travel", "level": "B7"}
]}
''';

/// The text [kFixtureNewlinesInQuestion]'s one skip row must render.
///
/// Written out rather than derived, for the same reason
/// [kFixtureThreeRowExpected] is: an expectation that computes itself from the
/// input moves whenever the input does and catches nothing.
const String kFixtureNewlinesCollapsed =
    'Line one. Line two. Line three. Tabbed.';

/// [rowCount] valid, mutually distinct rows — the only way to cross a batch
/// boundary on the host.
///
/// **A builder, not a constant, and deliberately so.** The case it exists for is
/// "more rows than fit in one `writeBatch`", which is 501 of them; pasting 501
/// literal rows into this file would bury every other fixture in it and would
/// hard-code a cap that lives in `question_bank_writer.dart`. The caller passes
/// the count so the test reads `kMaxWritesPerBatch + 1` and the relationship
/// between the fixture and the cap is stated where it matters.
///
/// Each row's content carries its own index, so no two rows can dedupe against
/// each other and the count that reaches the writer is the count the file had.
String kFixtureRowsBeyondBatchCap(int rowCount) {
  final rows = <String>[
    for (var i = 1; i <= rowCount; i++)
      '  {"content": "Generated question $i.", "subject": "Travel", '
          '"level": "A1"}',
  ];
  return '{"data": [\n${rows.join(',\n')}\n]}';
}
