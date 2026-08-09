/// Test-only stand-ins for the question bank, owned by `test/` and shipped
/// nowhere.
///
/// **Why this file exists.** Phase 2 shipped a placeholder bank in
/// `lib/data/questions.dart` (`kQuestions`, `kSubjects`,
/// `PlaceholderQuestionSource`) so the timed loop could be built and tested
/// before Firestore existed. Phase 3 gave the app a real bank, and D-36
/// explicitly rejected keeping the placeholder as an offline fallback: two banks
/// means the user cannot tell which one they are drilling against, and a source
/// built to be deleted that survives the phase becomes permanent by accident.
/// So the constants were deleted from `lib/` — and the tests that legitimately
/// need *some* fixed prompts to assert against got their own copy, here.
///
/// **The prompts are carried over verbatim from the retired constant.** That is
/// deliberate: the loop tests assert on exact strings and exact ordering, so
/// rewording them would have turned a file-move into a behavioural change and
/// hidden any real regression inside the churn.
///
/// **These are fixtures, not a bank.** Nothing in `lib/` may import this file —
/// the app has exactly one question source and it is Firestore. The `kFixture`
/// prefix is what makes a reader of any test body able to tell at a glance that
/// the data is scaffolding rather than something the app ships.
library;

/// The prompts the loop tests draw from.
///
/// **Ordering is load-bearing.** `questionAt` draws sequentially and question 1
/// of a session is always [kFixtureQuestions] `.first`, so the original Phase 1
/// five stay at the head of the list — reordering them would silently move every
/// cycling assertion's expectations (D-23/D-42). New prompts are appended.
///
/// The entries are deliberately NOT tagged with a subject or a level: this
/// fixture models a resolved question list — what `QuestionSource.questionsFor`
/// hands back *after* the server-side `subject in […]` + `level ==` filter has
/// already run — not the bank the filter runs against.
const List<String> kFixtureQuestions = <String>[
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

/// The prompt a sequential draw at question 1 must produce (D-23).
///
/// Spelled out as its own constant rather than written as
/// `kFixtureQuestions.first` at each call site, because several assertions read
/// `expect(find.text(...), findsNothing)` — and a `findsNothing` against an
/// expression is much easier to misread than one against a named prompt.
const String kFixtureFirstPrompt = 'What did you do this morning?';

/// The topics the Setup tests drive, standing in for whatever is in the real
/// bank.
///
/// Carries the same five names the retired `kSubjects` constant held, so the
/// topic keys every pre-existing test taps (`setup-topic-Travel`,
/// `setup-topic-Daily life`) keep resolving.
///
/// **Already in the case-insensitive sorted order `normalizeSubjects` produces**
/// — which is a different order from the retired constant's. That is not a
/// transcription slip: `SetupScreen` renders its source's list verbatim and does
/// not sort, so a fixture in any other order would be modelling a source that
/// the production `FirestoreQuestionSource` cannot produce.
const List<String> kFixtureSubjects = <String>[
  'Daily life',
  'Food & health',
  'Opinions',
  'Travel',
  'Work & study',
];
