import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../utils/audio_paths.dart';

/// Local SQLite access for practice sessions and their answered questions.
///
/// Schema (locked in Phase 1 per D-05, extended by Phase 2 with more rows —
/// never a migration):
///
/// ```sql
/// CREATE TABLE sessions (
///   id INTEGER PRIMARY KEY AUTOINCREMENT,
///   created_at TEXT NOT NULL
/// );
/// CREATE TABLE question_answers (
///   id INTEGER PRIMARY KEY AUTOINCREMENT,
///   session_id INTEGER NOT NULL REFERENCES sessions(id),
///   question_text TEXT NOT NULL,
///   audio_path TEXT NOT NULL,
///   created_at TEXT NOT NULL
/// );
/// ```
///
/// All statements go through sqflite's typed `insert()`/`query()` helpers with
/// `whereArgs` — never string-interpolated SQL (T-01-02).
class DatabaseHelper {
  static const String kDatabaseFileName = 'englishreflex.db';
  static const String kSessionsTable = 'sessions';
  static const String kQuestionAnswersTable = 'question_answers';

  Database? _db;

  /// Opens (and on first run creates) the database lazily.
  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final docsDir = await appDocumentsDir();
    final path = p.join(docsDir.path, kDatabaseFileName);
    final db = await openDatabase(path, version: 1, onCreate: _onCreate);
    _db = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE $kSessionsTable (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE $kQuestionAnswersTable (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES $kSessionsTable(id),
  question_text TEXT NOT NULL,
  audio_path TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
  }

  /// Crash-safety-critical write path (D-08 / PERSIST-01).
  ///
  /// Writes one `sessions` row and its one `question_answers` row inside a
  /// SINGLE transaction, so a kill mid-write can never leave a session without
  /// its answer (or an answer without its session).
  ///
  /// MUST only ever be called AFTER the audio file is confirmed finalized on
  /// disk — never before, and never as two independent writes.
  ///
  /// Returns the new session's id.
  Future<int> insertAnsweredSession({
    required String questionText,
    required String audioRelativePath,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.transaction<int>((txn) async {
      final sessionId = await txn.insert(kSessionsTable, {'created_at': now});
      await txn.insert(kQuestionAnswersTable, {
        'session_id': sessionId,
        'question_text': questionText,
        'audio_path': audioRelativePath,
        'created_at': now,
      });
      return sessionId;
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
