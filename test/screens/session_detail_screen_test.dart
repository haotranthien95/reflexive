import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/models/question_answer.dart';
import 'package:englishreflex/models/session.dart';
import 'package:englishreflex/screens/history_screen.dart'
    show kHistoryErrorMessage;
import 'package:englishreflex/screens/session_detail_screen.dart';
import 'package:englishreflex/services/audio_player_service.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

/// Substitutes the platform channel so the REAL [AudioPlayerService] — and the
/// screen's stop-before-play ordering — run under `flutter test`.
class FakePlaybackBackend implements AudioPlaybackBackend {
  FakePlaybackBackend({this.throwOnPlay = false});

  final bool throwOnPlay;
  final List<String> calls = <String>[];

  @override
  Future<void> play(String absoluteFilePath) async {
    calls.add('play:$absoluteFilePath');
    if (throwOnPlay) throw StateError('player refused the file');
  }

  @override
  Stream<void> get onComplete => const Stream<void>.empty();

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

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

Widget _wrap(
  Session session,
  DatabaseHelper helper, {
  AudioPlaybackBackend? backend,
}) =>
    MaterialApp(
      home: SessionDetailScreen(
        session: session,
        databaseHelper: helper,
        audioPlayerService: backend == null
            ? null
            : AudioPlayerService(backend: backend),
      ),
    );

/// Answer rows are counted by their play affordance, not by `InkWell`: the
/// error state's own retry `TextButton` builds an `InkWell` too, so counting
/// those would conflate a row with a button.
final Finder _answerRows = find.byIcon(Icons.play_circle_fill);

final Session _session = Session(id: 7, createdAt: DateTime(2026, 8, 8, 14, 5));

void main() {
  group('SessionDetailScreen read failure', () {
    testWidgets('renders the error state, not an empty answer list',
        (tester) async {
      await tester.pumpWidget(_wrap(_session, ThrowingDatabaseHelper()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-detail-error')), findsOneWidget);
      expect(_answerRows, findsNothing);
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
      expect(_answerRows, findsNothing);
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

      expect(_answerRows, findsOneWidget);
      expect(find.text('Describe your morning.'), findsOneWidget);
    });

    testWidgets('scopes the query to this session only', (tester) async {
      final helper = FakeDetailDatabaseHelper([_answer(1, 'Scoped')]);

      await tester.pumpWidget(_wrap(_session, helper));
      await tester.pumpAndSettle();

      expect(helper.requestedSessionIds, [7]);
    });
  });

  group('SessionDetailScreen tap-to-replay', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('englishreflex_detail');
      documentsDirProvider = () async => tempDir;
    });

    tearDown(() async {
      documentsDirProvider = getApplicationDocumentsDirectory;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Writes a stand-in file at the absolute path the given answer resolves to.
    ///
    /// Must run inside [WidgetTester.runAsync]: `testWidgets` bodies execute in
    /// a fake-async zone that never pumps the real event loop, so an awaited
    /// `dart:io` future would simply never resolve.
    Future<void> createRecordingFile(
      WidgetTester tester,
      QuestionAnswer answer,
    ) async {
      await tester.runAsync(() async {
        final File file = File(await toAbsolutePath(answer.audioPath));
        await file.parent.create(recursive: true);
        await file.writeAsString('not really audio');
      });
    }

    /// Taps the answer row and lets `_play`'s real filesystem check resolve.
    ///
    /// Same reason as above: `_play` calls `File.exists()`, so the tap must be
    /// driven on the real event loop before the resulting SnackBar can be
    /// pumped into the tree.
    Future<void> tapRow(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(_answerRows);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
    }

    testWidgets('a row whose recording is gone says so rather than nothing',
        (tester) async {
      // WR-06: this tap used to be a silent no-op. Silence is indistinguishable
      // from a broken app, and this phase promises the answers are retrievable
      // — so when one is not, that has to be stated.
      final backend = FakePlaybackBackend();

      await tester.pumpWidget(
        _wrap(
          _session,
          FakeDetailDatabaseHelper([_answer(1, 'Answer with no file')]),
          backend: backend,
        ),
      );
      await tester.pumpAndSettle();

      await tapRow(tester);

      expect(find.text(kRecordingMissingMessage), findsOneWidget);
      // Never attempted to play a file that is not there.
      expect(backend.calls.where((c) => c.startsWith('play:')), isEmpty);
    });

    testWidgets('a player failure is surfaced, not swallowed', (tester) async {
      final backend = FakePlaybackBackend(throwOnPlay: true);
      final answer = _answer(1, 'Answer with a file');
      await createRecordingFile(tester, answer);

      await tester.pumpWidget(
        _wrap(
          _session,
          FakeDetailDatabaseHelper([answer]),
          backend: backend,
        ),
      );
      await tester.pumpAndSettle();

      await tapRow(tester);

      expect(find.text(kRecordingPlaybackFailedMessage), findsOneWidget);
    });

    testWidgets('a second tap stops the previous playback before starting',
        (tester) async {
      // IN-06: AudioPlayerService.stop() had no caller, so two rapid taps could
      // overlap two recordings.
      final backend = FakePlaybackBackend();
      final answer = _answer(1, 'Answer with a file');
      await createRecordingFile(tester, answer);

      await tester.pumpWidget(
        _wrap(
          _session,
          FakeDetailDatabaseHelper([answer]),
          backend: backend,
        ),
      );
      await tester.pumpAndSettle();

      await tapRow(tester);
      await tapRow(tester);

      final String? played = await tester.runAsync(
        () async => 'play:${await toAbsolutePath(answer.audioPath)}',
      );
      // Every play is preceded by a stop, so two recordings can never overlap.
      expect(backend.calls, ['stop', played, 'stop', played]);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
