import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_question_source.dart';
import 'question_importer.dart';

/// Firestore's documented cap on how many operations one `WriteBatch` may
/// carry: **500**.
///
/// **Unlike [kMaxTopicsPerQuery], the installed SDK does not check this at
/// all.** Verified against `cloud_firestore` 6.8.0's own
/// `lib/src/write_batch.dart` in this repo's pub cache: `set`, `update` and
/// `delete` assert only that the document belongs to the same Firestore
/// instance, and `commit()` forwards straight to the platform delegate. There is
/// no client-side operation count, not even a debug-mode `assert`. An over-cap
/// commit therefore goes to the server and comes back as an opaque failure with
/// nothing in the log naming the real cause — so this constant and the chunking
/// in [FirestoreQuestionBankWriter.write] are the ONLY guard that exists, in
/// both build modes.
///
/// The number itself is the documented **server** limit and has not been
/// observed failing at 501 in this project — nothing here probes the edge. The
/// ~600-row seed import in plan 04-05 is what exercises the multi-chunk path
/// against the real backend for the first time.
///
/// Pinned by `test/services/question_importer_test.dart` so a change forces a
/// deliberate decision rather than a silent drift between this constant and the
/// server.
const int kMaxWritesPerBatch = 500;

/// Thrown when SOME chunks committed and a later one did not.
///
/// **This is the one place a partial write survives D-52's
/// validate-everything-first design.** Every accept/reject judgement is made
/// before the first document goes out, so nothing is left to decide during the
/// write — but a ~600-row import needs more than one `writeBatch` commit
/// ([kMaxWritesPerBatch]), and chunk 2 can fail after chunk 1 has landed.
///
/// **It is reported rather than prevented, on purpose.** IMPORT-04 forbids a
/// SILENT or unreported partial failure, not the physical possibility of one.
/// The payload is what lets the sheet state the exact count that landed and then
/// name the recovery in the same breath — and the recovery is genuinely safe
/// because D-54 dedupes against the bank, so re-importing the same file skips
/// whatever already made it.
///
/// **Numeric payload only** — no exception text, no Firestore error code, no
/// document ID, no collection name. Everything else goes to `debugPrint`.
class ImportPartialWriteException implements Exception {
  const ImportPartialWriteException({required this.done, required this.total});

  /// Rows the server has ACKNOWLEDGED. Never an optimistic count.
  final int done;

  /// Rows the import set out to write.
  final int total;

  @override
  String toString() => 'ImportPartialWriteException($done/$total)';
}

/// The write side of the question bank (IMPORT-01), behind the established
/// seam shape.
///
/// **No Firestore type crosses this seam.** No `WriteBatch`, no `Timestamp`, no
/// `QuerySnapshot`, no `FirebaseException` — only plain Dart in
/// ([ImportRow]) and out (`Set<String>`, `int`), plus
/// [QuestionBankUnavailableException] and [ImportPartialWriteException] as the
/// two signals. That containment is what lets the import sheet be driven end to
/// end by a plain fake on the host.
abstract class QuestionBankWriter {
  /// Every question already in the bank, as [importDedupeKey] values (D-54).
  ///
  /// Throws [QuestionBankUnavailableException] when the bank could not be read.
  Future<Set<String>> existingKeys();

  /// Writes [rows] and returns how many were durably committed.
  ///
  /// [onProgress] is called with the cumulative committed count and the total,
  /// **only after a commit future has completed** — never optimistically per
  /// row.
  Future<int> write(
    List<ImportRow> rows, {
    void Function(int committed, int total)? onProgress,
  });
}

/// The production implementation: the real Firestore `questions` collection.
///
/// **Deliberately a thin adapter** (D-47), exactly like
/// [FirestoreQuestionSource]: read the bank, chunk the rows, commit. The one
/// piece of judgement in the feature lives in `question_importer.dart`, on the
/// host-testable side of the seam. `fake_cloud_firestore` was rejected for this
/// file for the same reason it was rejected for the read adapter — it does not
/// model the real backend's limits, so a passing test would not prove the real
/// commit runs. The multi-chunk path is proven by the seed import in plan 04-05.
class FirestoreQuestionBankWriter implements QuestionBankWriter {
  FirestoreQuestionBankWriter({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// The dedupe read, and the gate the whole import passes through (D-60).
  ///
  /// **The read is forced to the SERVER.** Confirmed against the installed
  /// `cloud_firestore` 6.8.0: `Query.get` takes an optional [GetOptions] whose
  /// `source` selects the read source, [Source] is exported from the package's
  /// public library, and the documented behaviour of [Source.server] is that it
  /// avoids the cache and generates an error when the server cannot be reached.
  ///
  /// That error is exactly the gate this phase wants. Firestore applies writes
  /// to the local cache immediately but the commit Future completes only on
  /// server acknowledgement, so an import attempted offline would otherwise spin
  /// forever with the questions queued on the device. Failing HERE ends the
  /// import before a single document is written, which is what lets the sheet
  /// say "nothing was imported" and mean it.
  ///
  /// **The server source is independently correct anyway:** a cache-served
  /// dedupe read would miss questions written from another device and would let
  /// duplicates straight through.
  ///
  /// Rethrown as [QuestionBankUnavailableException] — the READ-side signal
  /// imported from `firestore_question_source.dart` rather than a second
  /// "could not reach the bank" type. Two types for one fact is how two call
  /// sites end up catching different halves of it.
  ///
  /// A document missing any of the three fields is SKIPPED and logged with its
  /// ID, exactly as [FirestoreQuestionSource.subjects] skips a malformed
  /// document: one bad row must not take out the whole import. The consequence
  /// is only that such a row is not deduped against, which at worst lets one
  /// copy of an already-broken question through.
  @override
  Future<Set<String>> existingKeys() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection(kQuestionsCollection)
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (error, stack) {
      debugPrint('Import dedupe read failed: $error');
      debugPrintStack(stackTrace: stack);
      throw const QuestionBankUnavailableException();
    }

    final keys = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final content = sanitizedText(data[_contentField]);
      final subject = sanitizedText(data[_subjectField]);
      final level = sanitizedText(data[_levelField])?.toUpperCase();
      if (content == null || subject == null || level == null) {
        debugPrint(
          'Skipping question ${doc.id} in the dedupe read: one of '
          '`$_contentField`, `$_subjectField`, `$_levelField` is missing, not '
          'a string, or blank — it cannot form a dedupe key.',
        );
        continue;
      }
      keys.add(importDedupeKey(content, subject, level));
    }
    return keys;
  }

  /// Commits [rows] in chunks of at most [kMaxWritesPerBatch], in file order.
  ///
  /// Each document body is EXACTLY four fields — `content`, `subject`, `level`
  /// and [kCreatedAtField] — written to a NEW auto-ID document reference. There
  /// is no `id` field inside the document: the id IS the auto-generated
  /// document key (BANK-01), and duplicating it in the body is how the two
  /// silently diverge.
  ///
  /// **`created_at` is D-63.** A native Firestore `Timestamp` built from epoch
  /// millis `base + index * step`, where the step is one second and the base is
  /// now minus the whole span, so the values strictly increase in FILE order and
  /// even the newest written row is still in the past. File order therefore
  /// becomes bank order under D-43's ascending `orderBy`, and an import visibly
  /// extends the end of the bank. This is the same scheme
  /// `tool/seed_questions.mjs` already used, which is why the composite index
  /// and `FirestoreQuestionSource` need no change.
  ///
  /// The index runs over the WHOLE row list, not per chunk, so the sequence does
  /// not restart at a chunk boundary.
  ///
  /// *`FieldValue.serverTimestamp()` on every row was considered and rejected:*
  /// it is immune to a wrong phone clock and is the obvious "correct" choice in
  /// isolation, but every document in one commit resolves to the same instant,
  /// so a 600-row import would be one giant tie — precisely the de-facto shuffle
  /// D-43 exists to prevent. **Accepted risk:** a badly wrong device clock can
  /// place an import BEFORE existing questions in bank order. Single-user app,
  /// non-destructive, visible only as ordering.
  ///
  /// **Progress is only ever reported for a completed commit.** Nothing here
  /// counts a row the server has not acknowledged (IMPORT-01, and the D-37
  /// precedent).
  ///
  /// On a commit failure: if NO earlier chunk committed, nothing landed and this
  /// throws [QuestionBankUnavailableException]. If an earlier chunk DID commit,
  /// it throws [ImportPartialWriteException] carrying the exact counts.
  @override
  Future<int> write(
    List<ImportRow> rows, {
    void Function(int committed, int total)? onProgress,
  }) async {
    final total = rows.length;
    if (total == 0) return 0;

    const stepMs = 1000;
    final baseMs = DateTime.now().millisecondsSinceEpoch - total * stepMs;
    final collection = _firestore.collection(kQuestionsCollection);

    var committed = 0;
    for (var start = 0; start < total; start += kMaxWritesPerBatch) {
      final end =
          start + kMaxWritesPerBatch < total ? start + kMaxWritesPerBatch : total;
      final batch = _firestore.batch();
      for (var i = start; i < end; i++) {
        final row = rows[i];
        batch.set(collection.doc(), <String, Object?>{
          _contentField: row.content,
          _subjectField: row.subject,
          _levelField: row.level,
          kCreatedAtField: Timestamp.fromMillisecondsSinceEpoch(
            baseMs + i * stepMs,
          ),
        });
      }

      try {
        // Awaited before the next chunk starts, deliberately: the counts this
        // method reports have to be counts the server has confirmed.
        await batch.commit();
      } catch (error, stack) {
        debugPrint('Import batch commit failed after $committed of $total '
            'rows: $error');
        debugPrintStack(stackTrace: stack);
        if (committed == 0) throw const QuestionBankUnavailableException();
        throw ImportPartialWriteException(done: committed, total: total);
      }

      committed = end;
      onProgress?.call(committed, total);
    }
    return committed;
  }

  static const String _subjectField = 'subject';
  static const String _levelField = 'level';
  static const String _contentField = 'content';
}
