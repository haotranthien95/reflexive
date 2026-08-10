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
