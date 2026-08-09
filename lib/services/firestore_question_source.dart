import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/questions.dart';
import '../models/session_config.dart';

/// The ONE place the Firestore collection is named.
///
/// Phase 4's in-app JSON importer (IMPORT-01) writes into the same collection
/// and must read this constant rather than repeat the string: a second literal
/// is how an importer ends up filling a collection the app never reads.
const String kQuestionsCollection = 'questions';

/// The Firestore field the bank is ordered by (D-43), stored as a NATIVE
/// Firestore `Timestamp` (Task 1, `option-a`).
///
/// Not an ISO-8601 string and not epoch millis: with a native timestamp
/// `orderBy` sorts chronologically forever with no format discipline required of
/// any future writer, and Phase 4's importer can use the server clock rather
/// than the phone's. The composite index in `firestore.indexes.json` is built on
/// this field's type, so changing the representation is a data migration, not a
/// refactor.
const String kCreatedAtField = 'created_at';

/// Thrown when the question bank could not be READ, as opposed to being empty.
///
/// That distinction is this phase's sharpest correctness detail and the reason
/// this type exists at all: "you have no questions" and "I could not ask" are
/// different facts, and the user is entitled to be told which one happened
/// (D-37, the same rule Phase 1 Plan 6 established for History).
///
/// This is a *signal*, not a crash: `SetupScreen` catches it and shows the
/// pre-approved user-facing copy. Its own text is developer-facing only and is
/// never rendered to the user — structurally identical to
/// `RecordingPermissionDeniedException`.
class QuestionBankUnavailableException implements Exception {
  const QuestionBankUnavailableException();

  @override
  String toString() => 'QuestionBankUnavailableException';
}

/// Turns the raw `subject` values of every document in the bank into the topic
/// checkbox list (BANK-02).
///
/// A free function, and the ONE piece of this adapter with logic worth testing
/// on the host: the Firestore call around it is untestable without a device
/// (D-47), but these three rules are pure and each one rejects an alternative
/// that would misbehave in a way nobody would notice until a real bank was in
/// front of them.
///
///  * **Blank and non-`String` values are dropped**, so a malformed document
///    contributes no checkbox rather than an unlabelled one.
///  * **De-duplication is by EXACT string equality**, so `'Travel'` and
///    `'travel '` stay two distinct topics. Case-folding or trimming here would
///    merge them for the checkbox list while the server-side `whereIn` query
///    still treats them as different values — the user would tick one topic and
///    get questions from neither.
///  * **Sorting is case-insensitive lexicographic**, so the same bank always
///    renders the same order and a re-read never reshuffles the checkboxes under
///    the user's finger. Firestore guarantees no order for an unordered read, so
///    without this the order is arbitrary.
List<String> normalizeSubjects(Iterable<Object?> rawValues) {
  final unique = <String>{};
  for (final value in rawValues) {
    if (value is! String) continue;
    if (value.trim().isEmpty) continue;
    unique.add(value);
  }
  return unique.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// The production [QuestionSource]: the real Firestore `questions` collection.
///
/// The fourth seam of the shape `lib/services/screen_wake_controller.dart`
/// establishes — abstract contract free of package types, named production
/// implementation, injected instance resolved lazily by the screen so a test
/// with a fake never constructs a Firestore handle.
///
/// **Deliberately a thin adapter** (D-47): build the query, map documents to
/// prompts, return. There is no logic here worth unit-testing on the host, and
/// host-testability therefore stops at the seam exactly as it does for the
/// microphone — the real query is proven by on-device UAT. `fake_cloud_firestore`
/// was rejected as a dev dependency because it does not model index
/// requirements, so a passing test would not prove the real query runs.
///
/// **No Firestore type crosses this seam.** No `QuerySnapshot`, no
/// `DocumentSnapshot`, no `FirebaseException` — only `List<String>` out and
/// [QuestionBankUnavailableException]. That is the same containment rule
/// `recording_service.dart` documents for its own seam, and it is what lets
/// every Setup and loop test drive all four read states with a plain fake.
class FirestoreQuestionSource implements QuestionSource {
  FirestoreQuestionSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// The distinct `subject` values actually present in the bank (BANK-02).
  ///
  /// Reads every document, because the client SDK has no field projection — a
  /// known and accepted redundancy (D-32), trivially cheap at this scale.
  ///
  /// The read is this method's own; the three rules that turn raw values into
  /// checkboxes live in [normalizeSubjects], where they can be tested.
  @override
  Future<List<String>> subjects() async {
    final snapshot = await _read(_firestore.collection(kQuestionsCollection));
    return normalizeSubjects(
      snapshot.docs.map((doc) => doc.data()[_subjectField]),
    );
  }

  /// This session's prompts: a GENUINE server-side filtered query (BANK-03).
  ///
  /// `subject in <selected topics>` AND `level == <chosen level>` AND
  /// `orderBy created_at` ascending. Filtering the already-read subjects list in
  /// memory was the cheaper alternative and was rejected (D-32): it would make
  /// BANK-03 an in-memory `where` clause, and would leave the app with one code
  /// path deriving topics and a second, untested one deriving questions.
  ///
  /// Level matching is EXACT, with no widening and no CEFR ordering encoded
  /// anywhere (D-40): a B1 session contains only B1 questions. A combination
  /// with no questions comes back empty and is explained at Start (D-41), not
  /// quietly widened into a session that is not the difficulty the user chose.
  ///
  /// This query is what `firestore.indexes.json`'s composite index
  /// (`level`, `subject`, `created_at`, all ascending) exists for.
  @override
  Future<List<String>> questionsFor(SessionConfig config) async {
    final snapshot = await _read(
      _firestore
          .collection(kQuestionsCollection)
          .where(_subjectField, whereIn: config.topics)
          .where(_levelField, isEqualTo: config.level)
          .orderBy(kCreatedAtField),
    );

    final prompts = <String>[];
    for (final doc in snapshot.docs) {
      final content = doc.data()[_contentField];
      if (content is! String) continue;
      if (content.trim().isEmpty) continue;
      prompts.add(content);
    }
    return prompts;
  }

  /// Runs [query] and applies the cache-versus-server rule to the result.
  ///
  /// **This is the sharpest correctness detail in the phase.** Firestore's
  /// default read source is server-then-cache, so with the network down a read
  /// resolves *successfully* from an empty cache with zero documents. Taken at
  /// face value that renders "your bank is empty" to a user whose bank is full
  /// and whose signal is merely down — precisely the failure D-37 exists to
  /// prevent.
  ///
  /// So: a zero-document snapshot whose `metadata.isFromCache` is true is an
  /// unreachable bank and throws. A zero-document snapshot with it false is the
  /// server genuinely confirming emptiness and is returned as-is. A non-empty
  /// cached snapshot is fine, and is what makes the drill usable offline after
  /// one successful online Setup visit (D-36).
  ///
  /// **Both reads go through here**, deliberately: writing the rule twice is how
  /// the two reads end up disagreeing about what "empty" means.
  ///
  /// Every `FirebaseException` is logged to the debug console and rethrown as
  /// [QuestionBankUnavailableException], so no Firestore error code, collection
  /// name, document ID or project ID can reach the screen.
  Future<QuerySnapshot<Map<String, dynamic>>> _read(
    Query<Map<String, dynamic>> query,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await query.get();
    } on FirebaseException catch (error, stack) {
      debugPrint('Question bank read failed: $error');
      debugPrintStack(stackTrace: stack);
      throw const QuestionBankUnavailableException();
    }

    if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) {
      debugPrint(
        'Question bank read returned 0 documents FROM CACHE — treating as '
        'unreachable, not empty.',
      );
      throw const QuestionBankUnavailableException();
    }
    return snapshot;
  }

  static const String _subjectField = 'subject';
  static const String _levelField = 'level';
  static const String _contentField = 'content';
}
