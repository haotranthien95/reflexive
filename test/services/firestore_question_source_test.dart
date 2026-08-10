import 'package:englishreflex/services/firestore_question_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the ONE pure helper `FirestoreQuestionSource` exposes, and nothing
/// else in that file — deliberately.
///
/// The adapter itself is not host-testable and is not meant to be (D-47): the
/// production source resolves `FirebaseFirestore.instance`, which no
/// `flutter test` process can construct, and both `fake_cloud_firestore` and the
/// Firestore emulator were rejected — the fake does not model index
/// requirements, so a passing test would not prove the real query runs, and the
/// emulator is an external process well beyond this project's tooling footprint.
/// The real query is proven by on-device UAT, exactly as the recording path is.
///
/// That is precisely why [sanitizedText] was extracted as a free function: it is
/// the one piece of judgement in the file, both reads depend on agreeing about
/// it, and pulled out here it can be pinned without a Firestore handle.
///
/// The over-limit `whereIn` guard itself is not host-testable for the same
/// reason the adapter is not — reaching it means calling `questionsFor`, which
/// resolves a Firestore handle. What IS pinned here is the part that stopped
/// being an implementation detail in Phase 4: the SIGNAL the guard throws
/// ([TooManyTopicsException]) and its distinctness from
/// [QuestionBankUnavailableException], because that distinctness is the only
/// thing standing between the user and copy that blames their connection for a
/// limit (D-61). Setup's own test drives the resulting helper.
void main() {
  group('sanitizedText — the shared usable-field rule', () {
    test('an ordinary string comes back trimmed', () {
      expect(sanitizedText('What did you do this morning?'),
          'What did you do this morning?');
      expect(sanitizedText('  Describe your day.  '), 'Describe your day.');
      expect(sanitizedText('\n\tTravel\n'), 'Travel');
    });

    test('a whitespace-only string is not usable', () {
      // The exact shape of the second deliberately malformed seed document.
      expect(sanitizedText('   \n\t  '), isNull);
      expect(sanitizedText(''), isNull);
    });

    test('a missing field is not usable', () {
      // `doc.data()[field]` returns null for a field the document never had —
      // the shape of the first deliberately malformed seed document.
      expect(sanitizedText(null), isNull);
    });

    test('a non-String value is not usable, whatever it is', () {
      // Firestore documents are user-authored and Phase 4 will let a JSON
      // import write anything at all into these fields.
      expect(sanitizedText(42), isNull);
      expect(sanitizedText(3.14), isNull);
      expect(sanitizedText(true), isNull);
      expect(sanitizedText(<String, Object?>{'text': 'nested'}), isNull);
      expect(sanitizedText(<String>['a list of prompts']), isNull);
    });

    test('a string that is only meaningful after trimming is still usable', () {
      // The rule is "has non-whitespace content", not "starts with a letter" —
      // a prompt padded by a sloppy import is real data, not a malformed row.
      expect(sanitizedText(' ? '), '?');
    });
  });

  group('kMaxTopicsPerQuery', () {
    test("is Firestore's confirmed whereIn limit for the installed SDK", () {
      // Confirmed against cloud_firestore 6.8.0's own assert in
      // lib/src/query.dart, which reads "'in' filters support a maximum of 30
      // elements in the value [Iterable]". Pinned here so a future SDK bump that
      // changes the limit forces a deliberate decision rather than a silent
      // drift between this constant and the server.
      //
      // **The branch this constant guards now has a user-facing string of its
      // own** (D-61): it throws [TooManyTopicsException], and Setup renders
      // `kTooManyTopicsMessage` for it rather than the connection-blaming
      // Start-failure copy it used to land on. So this number is no longer only
      // a query limit — it is the number printed in a sentence the user reads,
      // and changing it means changing that sentence too.
      expect(kMaxTopicsPerQuery, 30);
    });
  });

  group('TooManyTopicsException (D-61)', () {
    test('names itself, and nothing else', () {
      // Developer-facing only, exactly like its sibling: this text goes to the
      // debug console and never to a widget.
      expect(const TooManyTopicsException().toString(),
          'TooManyTopicsException');
    });

    test('is a DISTINCT type from the bank-unavailable signal', () {
      // The whole point of the split. If a `catch` could not tell these apart,
      // the over-limit refusal would keep landing on copy that blames the user's
      // connection for a limit that has nothing to do with the network.
      const Object overLimit = TooManyTopicsException();
      const Object unavailable = QuestionBankUnavailableException();

      expect(overLimit, isNot(isA<QuestionBankUnavailableException>()));
      expect(unavailable, isNot(isA<TooManyTopicsException>()));
      expect(overLimit, isA<Exception>());

      // And the arm ordering a caller relies on actually works: catching the
      // over-limit type first must NOT swallow the unavailable one.
      String caught;
      try {
        throw unavailable;
      } on TooManyTopicsException {
        caught = 'over-limit';
      } on QuestionBankUnavailableException {
        caught = 'unavailable';
      }
      expect(caught, 'unavailable');

      try {
        throw overLimit;
      } on TooManyTopicsException {
        caught = 'over-limit';
      } on QuestionBankUnavailableException {
        caught = 'unavailable';
      }
      expect(caught, 'over-limit');
    });
  });
}
