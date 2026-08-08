import 'package:flutter/foundation.dart';

/// Everything the Setup screen decided about ONE practice session, carried into
/// the practice screen as a single immutable value (D-16/D-17/D-18).
///
/// **Deliberately not persisted, and deliberately without `fromMap`/`toMap`.**
/// D-18 fixes every setting back to its default on each visit to Setup, which is
/// what keeps Phase 2 free of a new persistence surface and free of a schema
/// version bump on the frozen `sessions`/`question_answers` tables. Adding a
/// serialization pair here would be the first half of that bump arriving by
/// accident — if last-used settings are ever wanted, they belong in their own
/// table with their own migration, not in this class.
///
/// [topics] and [level] exist from day one even though Phase 2 draws every
/// prompt from a hardcoded placeholder bank: Phase 3's Firestore query filters
/// the `questions` collection on `subject` and `level`, so the fields it will
/// read must already be travelling with the session by then. Building the seam
/// without them would mean re-threading this value through every call site.
@immutable
class SessionConfig {
  const SessionConfig({
    required this.topics,
    required this.level,
    required this.questionCount,
    required this.thinkingSeconds,
    required this.answerSeconds,
    required this.autoReplay,
  });

  /// The checked subjects. At least one, enforced by the Start gate (SETUP-07).
  final List<String> topics;

  /// CEFR level, one of A1…C2 (SETUP-03).
  final String level;

  /// How many questions the session runs (SETUP-04, 1–100).
  final int questionCount;

  /// `t` — seconds the question is readable before the recorder arms
  /// (SETUP-04/LOOP-02, 3–30).
  final int thinkingSeconds;

  /// `d` — the recording cap in seconds (SETUP-05, 10–120). Supersedes Phase 1's
  /// fixed `kMaxRecordingDuration` as the app's real answer cap.
  final int answerSeconds;

  /// `r` — replay each answer immediately after recording it (SETUP-06).
  final bool autoReplay;
}
