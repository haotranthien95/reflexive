import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/screens/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A helper whose read always fails — stands in for an unreadable database.
///
/// The whole point of these tests: this must NOT look like "you have no
/// recordings". A read failure and an absence of data are different facts and
/// the user is entitled to be told which one happened.
class ThrowingDatabaseHelper extends DatabaseHelper {
  int callCount = 0;

  @override
  Future<List<Session>> listSessions() async {
    callCount++;
    throw StateError('database unreadable');
  }
}

/// A helper returning a caller-supplied list, optionally failing the first
/// call so the retry path can be driven end to end.
class FakeHistoryDatabaseHelper extends DatabaseHelper {
  FakeHistoryDatabaseHelper(this.sessions, {this.failFirstCall = false});

  final List<Session> sessions;
  final bool failFirstCall;
  int callCount = 0;

  @override
  Future<List<Session>> listSessions() async {
    callCount++;
    if (failFirstCall && callCount == 1) {
      throw StateError('transient read failure');
    }
    return sessions;
  }
}

Session _session(int id) => Session(
      id: id,
      createdAt: DateTime(2026, 8, 8, 14, id),
    );

Widget _wrap(DatabaseHelper helper) =>
    MaterialApp(home: HistoryScreen(databaseHelper: helper));

void main() {
  group('HistoryScreen read failure', () {
    testWidgets('renders the error state and never the empty state',
        (tester) async {
      await tester.pumpWidget(_wrap(ThrowingDatabaseHelper()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-error')), findsOneWidget);
      expect(find.byKey(const Key('history-empty')), findsNothing);
      // The literal Copywriting Contract empty-state strings must be absent:
      // telling a user their practice is gone when it is merely unreadable is
      // the exact failure this screen must never present.
      expect(find.text('No recordings yet'), findsNothing);
      expect(
        find.text("Finish your first answer and it'll show up here."),
        findsNothing,
      );
      expect(find.text(kHistoryErrorMessage), findsOneWidget);
    });

    testWidgets('offers a retry that re-issues the query', (tester) async {
      final helper = FakeHistoryDatabaseHelper(
        [_session(2), _session(1)],
        failFirstCall: true,
      );

      await tester.pumpWidget(_wrap(helper));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-error')), findsOneWidget);
      expect(helper.callCount, 1);

      await tester.tap(find.byKey(const Key('history-error-retry')));
      await tester.pumpAndSettle();

      expect(helper.callCount, 2);
      expect(find.byKey(const Key('history-error')), findsNothing);
      expect(find.byType(InkWell), findsNWidgets(2));
    });

    testWidgets('the retry control clears the touch-target floor',
        (tester) async {
      await tester.pumpWidget(_wrap(ThrowingDatabaseHelper()));
      await tester.pumpAndSettle();

      final Size size =
          tester.getSize(find.byKey(const Key('history-error-retry')));
      expect(size.width, greaterThanOrEqualTo(64));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('HistoryScreen empty state', () {
    testWidgets('zero sessions renders the empty state, not the error state',
        (tester) async {
      await tester.pumpWidget(_wrap(FakeHistoryDatabaseHelper(const [])));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.byKey(const Key('history-error')), findsNothing);
      expect(find.text('No recordings yet'), findsOneWidget);
      expect(
        find.text("Finish your first answer and it'll show up here."),
        findsOneWidget,
      );
    });
  });

  group('HistoryScreen populated state', () {
    testWidgets('renders one tappable row per session', (tester) async {
      await tester.pumpWidget(
        _wrap(FakeHistoryDatabaseHelper([_session(2), _session(1)])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNWidgets(2));
      expect(find.byKey(const Key('history-empty')), findsNothing);
      expect(find.byKey(const Key('history-error')), findsNothing);
    });

    testWidgets('one session renders exactly one row', (tester) async {
      await tester.pumpWidget(_wrap(FakeHistoryDatabaseHelper([_session(1)])));
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
    });
  });
}
