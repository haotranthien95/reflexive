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
