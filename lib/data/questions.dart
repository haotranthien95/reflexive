/// The question-source seam and the cycling helper — and, since Phase 3, no
/// question data at all.
///
/// **This file used to hold a second question bank.** Phase 2 shipped
/// `kQuestions` (≈20 hardcoded prompts), `kSubjects` (5 hardcoded topics) and
/// `PlaceholderQuestionSource` so the timed loop could be built and tested
/// before Firestore existed. Phase 3 plan 03 deleted all three, because D-36
/// rejected keeping them as an offline fallback: with two banks a user cannot
/// tell which one they are drilling against, and a source that was built to be
/// deleted becomes permanent by accident if it survives the phase that replaced
/// it. The app now ships exactly one question source and it is Firestore.
///
/// What remains is the seam ([QuestionSource]) and the pure draw rule
/// ([questionAt]). The test fixtures that used to borrow the shipped prompts now
/// live in `test/fixtures/questions.dart`, owned by `test/` and shipped nowhere
/// — `lib/` holds no practice prompt and no topic name.
library;

import '../models/session_config.dart';

/// The seam Phase 2 built for the Firestore swap, now swapped (D-34).
///
/// Phase 2 deliberately routed every prompt lookup through this interface even
/// though there was exactly one implementation, because the alternative — the
/// loop reading a prompt constant directly — is what would have forced Phase 3
/// to edit `practice_state.dart` to change a data source. The loop must never
/// know where a question came from, and after this phase it structurally cannot:
/// the loop is handed a resolved `List<String>` and holds no source at all.
///
/// **Both members are `Future`-returning, and that is the phase's real change.**
/// The synchronous alternative — keeping this interface synchronous and
/// injecting an instance that has already been awaited — was rejected because it
/// produces an object whose correctness depends on someone having awaited it
/// first, and which silently returns an empty bank when they did not.
///
/// Both are called ONLY from `SetupScreen` (D-32/D-33). Nothing on the practice
/// screen or in `lib/state/` touches this interface.
abstract class QuestionSource {
  /// The distinct topic values in the bank, for the Setup checkboxes
  /// (SETUP-01/BANK-02).
  ///
  /// Ordering, de-duplication and blank-dropping are the IMPLEMENTATION's
  /// contract, not the caller's: `SetupScreen` renders what it is given, in the
  /// order it is given. See `FirestoreQuestionSource.subjects` for the rules the
  /// production source applies.
  Future<List<String>> subjects();

  /// The prompts for [config]'s topics and level, in bank order.
  ///
  /// "Bank order" means ascending `created_at` (D-43) — a Firestore query has no
  /// inherent order unless one is requested, so leaving it unspecified would
  /// have been a de-facto shuffle, quietly doing the thing LOOP-V2-01 defers to
  /// v2.
  Future<List<String>> questionsFor(SessionConfig config);
}

/// The prompt at [index] in [bank], **cycling** rather than running out (D-23).
///
/// A configured `question_count` of 100 against a 4-question result set must
/// still run 100 questions: capping the session at the bank size would silently
/// contradict the number the user chose on Setup (D-42). Repeats are expected
/// and deliberately unlabelled in the UI.
///
/// Order is sequential bank order, not shuffled — LOOP-V2-01 defers shuffling
/// to v2, and Phase 1's immediate-repeat-avoiding random picker is deliberately
/// replaced by this.
String questionAt(List<String> bank, int index) => bank[index % bank.length];
