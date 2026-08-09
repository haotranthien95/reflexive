import '../models/session_config.dart';

/// Hardcoded rotating practice questions (D-02, expanded to ~20 by D-23).
///
/// The real question bank lives in Firestore and arrives in Phase 3; this list
/// exists only so the record → save → replay loop has varying prompts to
/// exercise. Each prompt is answerable in well under the shortest configurable
/// answer length and kept short enough to render comfortably in the Display
/// text style.
///
/// **Ordering is load-bearing.** [questionAt] draws sequentially and the loop's
/// question 1 is always `kQuestions.first`, so the original Phase 1 five stay at
/// the head of the list — moving them would silently move every existing test's
/// expectations. New prompts are appended, roughly four per entry in
/// [kSubjects], and are deliberately NOT tagged with a subject or a level: the
/// placeholder bank carries no metadata (see [PlaceholderQuestionSource]).
const List<String> kQuestions = [
  // Daily life
  'What did you do this morning?',
  'Describe your favourite place to relax.',
  'What is one thing you want to learn this year?',
  'Tell me about a meal you really enjoyed.',
  'How do you usually get to work or school?',
  'What does a perfect weekend look like for you?',
  'Describe the room you are sitting in right now.',
  'What is the first thing you do after waking up?',
  // Work & study
  'What are you working on at the moment?',
  'Describe a skill you use every day at work or school.',
  'Tell me about a time you had to explain something difficult.',
  'What makes a good teacher or a good manager?',
  // Travel
  'Where would you go if you had a free plane ticket?',
  'Describe a journey that did not go as planned.',
  'What do you always pack when you travel?',
  // Food & health
  'How do you usually stay active during the week?',
  'Describe a dish you would like to learn to cook.',
  'What helps you sleep well at night?',
  // Opinions
  'Do you prefer working alone or in a team, and why?',
  'Is it better to plan everything or to improvise?',
];

/// The placeholder topic list the Setup screen checkboxes are built from
/// (D-19), matching the UI-SPEC Layout Contract verbatim.
///
/// These are NOT a second source of truth about the question bank: Phase 3
/// replaces this constant with the distinct `subject` values read from
/// Firestore, and nothing else about the Setup screen or the SETUP-07 Start
/// gate changes when it does.
const List<String> kSubjects = [
  'Daily life',
  'Work & study',
  'Travel',
  'Food & health',
  'Opinions',
];

/// The seam Phase 2 built for the Firestore swap, now swapped (D-34).
///
/// Phase 2 deliberately routed every prompt lookup through this interface even
/// though there was exactly one implementation, because the alternative — the
/// loop reading [kQuestions] directly — is what would have forced Phase 3 to
/// edit `practice_state.dart` to change a data source. The loop must never know
/// where a question came from, and after this phase it structurally cannot: the
/// loop is handed a resolved `List<String>` and holds no source at all.
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

/// The last remnant of the Phase 2 placeholder bank, kept alive for exactly one
/// plan.
///
/// Nothing in production constructs this any more — `SetupScreen` resolves
/// `FirestoreQuestionSource` when no source is injected. It survives this plan
/// only so the pre-existing test suite keeps compiling while the Firestore path
/// is proven end to end; **plan 03 retires it**, together with [kQuestions] and
/// [kSubjects]. Do not build anything new on it, and in particular do not
/// reintroduce it as an offline fallback bank: D-36 rejected that outright,
/// because a user cannot tell which bank they are drilling against.
///
/// Filtering by `config.topics`/`config.level` is deliberately still absent
/// rather than faked — the placeholder prompts carry no subject or level, so any
/// filter here would be a fiction. The real filtering lives in the Firestore
/// query.
class PlaceholderQuestionSource implements QuestionSource {
  const PlaceholderQuestionSource();

  @override
  Future<List<String>> subjects() async => kSubjects;

  @override
  Future<List<String>> questionsFor(SessionConfig config) async => kQuestions;
}

/// The prompt at [index] in [bank], **cycling** rather than running out (D-23).
///
/// A configured `question_count` of 100 against a 5-prompt placeholder bank must
/// still run 100 questions: capping the session at the bank size would silently
/// contradict the number the user chose on Setup, and would make a realistic
/// session length untestable before Firestore exists. Repeats are expected and
/// deliberately unlabelled in the UI.
///
/// Order is sequential bank order, not shuffled — LOOP-V2-01 defers shuffling
/// to v2, and Phase 1's immediate-repeat-avoiding random picker is deliberately
/// replaced by this.
String questionAt(List<String> bank, int index) => bank[index % bank.length];
