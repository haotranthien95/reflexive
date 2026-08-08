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

/// The seam Phase 3 swaps for Firestore.
///
/// Phase 2 deliberately routes every prompt lookup through this interface even
/// though there is exactly one implementation, because the alternative — the
/// loop reading [kQuestions] directly — is what would force Phase 3 to edit
/// `practice_state.dart` to change a data source. The loop must never know
/// where a question came from.
abstract class QuestionSource {
  /// The prompts available for [config]'s topics and level, in bank order.
  List<String> questionsFor(SessionConfig config);
}

/// The Phase 2 implementation: the whole hardcoded bank, unfiltered.
///
/// Filtering by `config.topics`/`config.level` is deliberately absent rather
/// than faked — the placeholder prompts carry no subject or level, so any
/// filter here would be a fiction that Phase 3 would have to unpick. The
/// filtering arrives with the real data, in the Firestore query.
class PlaceholderQuestionSource implements QuestionSource {
  const PlaceholderQuestionSource();

  @override
  List<String> questionsFor(SessionConfig config) => kQuestions;
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
