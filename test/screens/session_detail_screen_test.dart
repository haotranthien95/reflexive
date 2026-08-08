import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/question_answer.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/screens/history_screen.dart'
    show kHistoryErrorMessage;
import 'package:englishreflex/screens/session_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A helper whose answer read always fails.
class ThrowingDatabaseHelper extends DatabaseHelper {
  int callCount = 0;

  @override
  Future<List<QuestionAnswer>> listAnswersForSession(int sessionId) async {
    callCount++;
    throw StateError('database unreadable');
  }
}

/// A helper returning a caller-supplied answer list, optionally failing the
/// first call so the retry path can be driven end to end.
class FakeDetailDatabaseHelper extends DatabaseHelper {
  FakeDetailDatabaseHelper(this.answers, {this.failFirstCall = false});

  final List<QuestionAnswer> answers;
  final bool failFirstCall;
  final List<int> requestedSessionIds = <int>[];

  @override
  Future<List<QuestionAnswer>> listAnswersForSession(int sessionId) async {
    requestedSessionIds.add(sessionId);
    if (failFirstCall && requestedSessionIds.length == 1) {
      throw StateError('transient read failure');
    }
    return answers;
  }
}

QuestionAnswer _answer(int id, String questionText) => QuestionAnswer(
      id: id,
      sessionId: 7,
      questionText: questionText,
      audioPath: 'recordings/$id.m4a',
      createdAt: DateTime(2026, 8, 8, 14, id),
    );

Widget _wrap(Session session, DatabaseHelper helper) => MaterialApp(
      home: SessionDetailScreen(session: session, databaseHelper: helper),
    );

final Session _session = Session(id: 7, createdAt: DateTime(2026, 8, 8, 14, 5));

void main() {
  group('SessionDetailScreen read failure', () {
    testWidgets('renders the error state, not an empty answer list',
        (tester) async {
      await tester.pumpWidget(_wrap(_session, ThrowingDatabaseHelper()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-detail-error')), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
      // Shares the History failure voice verbatim.
      expect(find.text(kHistoryErrorMessage), findsOneWidget);
    });

    testWidgets('offers a retry that re-issues the query', (tester) async {
      final helper = FakeDetailDatabaseHelper(
        [_answer(1, 'What did you do this morning?')],
        failFirstCall: true,
      );

      await tester.pumpWidget(_wrap(_session, helper));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-detail-error')), findsOneWidget);
      expect(helper.requestedSessionIds, [7]);

      await tester.tap(find.byKey(const Key('session-detail-error-retry')));
      await tester.pumpAndSettle();

      expect(helper.requestedSessionIds, [7, 7]);
      expect(find.byKey(const Key('session-detail-error')), findsNothing);
      expect(find.text('What did you do this morning?'), findsOneWidget);
    });

    testWidgets('the retry control clears the touch-target floor',
        (tester) async {
      await tester.pumpWidget(_wrap(_session, ThrowingDatabaseHelper()));
      await tester.pumpAndSettle();

      final Size size =
          tester.getSize(find.byKey(const Key('session-detail-error-retry')));
      expect(size.width, greaterThanOrEqualTo(64));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('SessionDetailScreen null session id', () {
    testWidgets('renders an empty list instead of throwing in initState',
        (tester) async {
      // Session.id is nullable and Session.fromMap will happily produce a null,
      // so a force-unwrap here turns a data problem into a red-screen crash.
      final helper = FakeDetailDatabaseHelper(const []);
      final session = Session(createdAt: DateTime(2026, 8, 8, 14, 5));

      await tester.pumpWidget(_wrap(session, helper));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(InkWell), findsNothing);
      expect(find.byKey(const Key('session-detail-error')), findsNothing);
      expect(helper.requestedSessionIds, isEmpty);
    });
  });

  group('SessionDetailScreen populated state', () {
    testWidgets('renders exactly one row carrying the question text',
        (tester) async {
      // Phase 1 sessions hold exactly one answer (D-05); Phase 2 reuses this
      // same row component for many rows with no restructuring.
      await tester.pumpWidget(
        _wrap(
          _session,
          FakeDetailDatabaseHelper([_answer(1, 'Describe your morning.')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
      expect(find.text('Describe your morning.'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    });

    testWidgets('scopes the query to this session only', (tester) async {
      final helper = FakeDetailDatabaseHelper([_answer(1, 'Scoped')]);

      await tester.pumpWidget(_wrap(_session, helper));
      await tester.pumpAndSettle();

      expect(helper.requestedSessionIds, [7]);
    });
  });
}
