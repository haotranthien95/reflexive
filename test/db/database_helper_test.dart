import 'dart:io';

import 'package:englishreflex/db/database_helper.dart';
import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late DatabaseHelper helper;

  setUpAll(() {
    // Redirect DatabaseHelper's internal openDatabase() at the FFI SQLite
    // engine so these tests exercise the real schema and real transactions
    // with no device/emulator and no changes to DatabaseHelper itself.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_db_test');
    documentsDirProvider = () async => tempDir;
    helper = DatabaseHelper();
  });

  tearDown(() async {
    await helper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('insertAnsweredSession', () {
    test('writes exactly one session and one linked answer', () async {
      final sessionId = await helper.insertAnsweredSession(
        questionText: 'What did you do this morning?',
        audioRelativePath: 'recordings/1.m4a',
      );

      expect(sessionId, greaterThan(0));

      final db = await helper.database;
      final sessions = await db.query(DatabaseHelper.kSessionsTable);
      final answers = await db.query(DatabaseHelper.kQuestionAnswersTable);

      expect(sessions, hasLength(1));
      expect(answers, hasLength(1));
      expect(answers.single['session_id'], sessionId);
      expect(answers.single['question_text'], 'What did you do this morning?');
      expect(answers.single['audio_path'], 'recordings/1.m4a');
    });

    test('two back-to-back recordings produce two distinct sessions, '
        'each with exactly one answer', () async {
      final first = await helper.insertAnsweredSession(
        questionText: 'Question one',
        audioRelativePath: 'recordings/1.m4a',
      );
      final second = await helper.insertAnsweredSession(
        questionText: 'Question two',
        audioRelativePath: 'recordings/2.m4a',
      );

      expect(first, isNot(second));

      final db = await helper.database;
      expect(await db.query(DatabaseHelper.kSessionsTable), hasLength(2));

      // No session may ever exist with zero answers (HIST-02 empty case).
      for (final id in [first, second]) {
        expect(await helper.listAnswersForSession(id), hasLength(1));
      }
    });
  });

  group('listSessions', () {
    test('returns nothing when no answer has been recorded', () async {
      expect(await helper.listSessions(), isEmpty);
    });

    test('orders sessions most-recent-first', () async {
      final first = await helper.insertAnsweredSession(
        questionText: 'Oldest',
        audioRelativePath: 'recordings/1.m4a',
      );
      final second = await helper.insertAnsweredSession(
        questionText: 'Newest',
        audioRelativePath: 'recordings/2.m4a',
      );

      final sessions = await helper.listSessions();

      expect(sessions.map((s) => s.id).toList(), [second, first]);
    });
  });

  group('foreign key enforcement', () {
    test('rejects an answer row pointing at a session that does not exist',
        () async {
      // Proves PRAGMA foreign_keys = ON is actually applied by
      // DatabaseHelper.onConfigure — a REFERENCES clause alone is inert in
      // SQLite, so without the pragma this insert would silently succeed and
      // create an orphaned row (T-03-01).
      final db = await helper.database;

      expect(
        () => db.insert(DatabaseHelper.kQuestionAnswersTable, {
          'session_id': 999,
          'question_text': 'Orphan',
          'audio_path': 'recordings/orphan.m4a',
          'created_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(await helper.listSessions(), isEmpty);
    });

    test('the pragma is on for the helper\'s own connection', () async {
      final db = await helper.database;
      final result = await db.rawQuery('PRAGMA foreign_keys');
      expect(result.single.values.single, 1);
    });

    test('a legitimate insert still succeeds with enforcement on', () async {
      final sessionId = await helper.insertAnsweredSession(
        questionText: 'Still works',
        audioRelativePath: 'recordings/1.m4a',
      );

      expect(await helper.listAnswersForSession(sessionId), hasLength(1));
    });
  });

  group('listReferencedAudioPaths', () {
    test('returns nothing when no answer has been recorded', () async {
      expect(await helper.listReferencedAudioPaths(), isEmpty);
    });

    test('returns the DB-relative path of every saved answer', () async {
      await helper.insertAnsweredSession(
        questionText: 'One',
        audioRelativePath: 'recordings/1.m4a',
      );
      await helper.insertAnsweredSession(
        questionText: 'Two',
        audioRelativePath: 'recordings/2.m4a',
      );

      expect(
        await helper.listReferencedAudioPaths(),
        {'recordings/1.m4a', 'recordings/2.m4a'},
      );
    });
  });

  group('database (lazy open)', () {
    test('two overlapping first accesses open exactly one connection',
        () async {
      // The launch-time orphan sweep and an immediate History tap can both
      // reach the getter before either has finished opening. Count the
      // documents-dir resolutions: `_open()` performs exactly one, so two
      // resolutions means the database was opened twice and one handle leaked
      // for the process lifetime.
      var docsDirResolutions = 0;
      documentsDirProvider = () async {
        docsDirResolutions++;
        return tempDir;
      };

      // Deliberately NOT awaited in sequence — both requests are in flight.
      final futureA = helper.database;
      final futureB = helper.database;
      final a = await futureA;
      final b = await futureB;

      expect(identical(a, b), isTrue,
          reason: 'both accesses must resolve to the same Database instance');
      expect(docsDirResolutions, 1,
          reason: 'the open path must run exactly once');
    });

    test('close() leaves the helper able to open again', () async {
      final first = await helper.database;
      expect(first.isOpen, isTrue);

      await helper.close();

      final second = await helper.database;
      expect(second.isOpen, isTrue);

      // And the reopened connection is a working database, not a stale handle.
      expect(await helper.listSessions(), isEmpty);
    });

    test('a FAILED open is not cached — the next caller re-attempts', () async {
      // REGRESSION GUARD (CR-02). `_dbFuture ??= _open()` memoized the REJECTED
      // future permanently, so every later call replayed the cached error
      // without re-attempting anything. Two consequences, both of which defeat
      // work done in this same phase: the "Try again" buttons 01-06 added
      // become a permanent no-op for the likeliest cause of the error they
      // retry, and a transient launch-time failure makes every subsequent
      // insertAnsweredSession fail for the process lifetime — while the user is
      // told to check a microphone permission.
      var attempts = 0;
      documentsDirProvider = () async {
        attempts++;
        if (attempts == 1) {
          throw StateError('transient: cannot resolve docs dir');
        }
        return tempDir;
      };
      final retryingHelper = DatabaseHelper();
      addTearDown(retryingHelper.close);

      await expectLater(
        retryingHelper.listSessions(),
        throwsA(isA<StateError>()),
      );

      // The retry affordance's whole contract: the next call really tries again.
      expect(await retryingHelper.listSessions(), isEmpty);
      expect(attempts, 2,
          reason: 'the second read never re-attempted the open');
    });

    test('close() before the database was ever opened is a no-op', () async {
      await helper.close();
      expect(await helper.listSessions(), isEmpty);
    });
  });

  group('listAnswersForSession', () {
    test('is scoped strictly to the requested session', () async {
      final first = await helper.insertAnsweredSession(
        questionText: 'Belongs to session one',
        audioRelativePath: 'recordings/1.m4a',
      );
      final second = await helper.insertAnsweredSession(
        questionText: 'Belongs to session two',
        audioRelativePath: 'recordings/2.m4a',
      );

      final firstAnswers = await helper.listAnswersForSession(first);
      final secondAnswers = await helper.listAnswersForSession(second);

      expect(firstAnswers, hasLength(1));
      expect(firstAnswers.single.questionText, 'Belongs to session one');
      expect(firstAnswers.single.sessionId, first);

      expect(secondAnswers, hasLength(1));
      expect(secondAnswers.single.questionText, 'Belongs to session two');
      expect(secondAnswers.single.sessionId, second);
    });

    test('returns an empty list for an unknown session id', () async {
      expect(await helper.listAnswersForSession(999), isEmpty);
    });
  });
}
