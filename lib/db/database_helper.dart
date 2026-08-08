import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/question_answer.dart';
import '../models/session.dart';
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
/// Every statement carrying a *value* goes through sqflite's typed
/// `insert()`/`query()` helpers with `whereArgs` — no value is ever
/// concatenated into SQL text (T-01-02, re-audited in Plan 3). The only
/// `execute()` calls in this file are the fixed `PRAGMA` and the two
/// `CREATE TABLE` statements, whose sole interpolations are this class's own
/// `static const` table-name identifiers — SQL identifiers cannot be bound as
/// parameters, and no user or file input reaches them.
class DatabaseHelper {
  static const String kDatabaseFileName = 'englishreflex.db';
  static const String kSessionsTable = 'sessions';
  static const String kQuestionAnswersTable = 'question_answers';

  /// The in-flight-or-resolved open, memoized as a FUTURE rather than as the
  /// resolved [Database].
  ///
  /// The previous getter memoized `Database? _db` and awaited two async calls
  /// (`appDocumentsDir()` then `openDatabase()`) *between* its null check and
  /// its assignment. Dart's single-threaded event loop does not make that
  /// window safe: any other caller reaching the getter while the first open is
  /// still in flight sees `_db == null` and starts a second open. Both callers
  /// then hold a connection and only the last assignment is ever closed — the
  /// first handle leaks for the whole process lifetime.
  ///
  /// That window is genuinely reachable in this app: `PracticeScreen`'s
  /// launch-time orphan sweep reads the database, and the user can tap through
  /// to History before the sweep's open has resolved. A leaked/duplicated
  /// connection is one of the concrete ways a later read can fail — which is
  /// exactly what `HistoryScreen`'s error state now reports honestly instead of
  /// rendering as "No recordings yet".
  ///
  /// Memoizing the future closes the window: `??=` assigns before the first
  /// `await` inside [_open] can yield, so every subsequent caller awaits the
  /// same open.
  Future<Database>? _dbFuture;

  /// Opens (and on first run creates) the database lazily, exactly once.
  Future<Database> get database => _dbFuture ??= _open();

  Future<Database> _open() async {
    final docsDir = await appDocumentsDir();
    final path = p.join(docsDir.path, kDatabaseFileName);
    return openDatabase(
      path,
      version: 1,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
  }

  /// Runs on EVERY open, before any migration or query.
  ///
  /// SQLite ignores `REFERENCES` constraints unless foreign-key enforcement is
  /// switched on per connection, so the `question_answers.session_id
  /// REFERENCES sessions(id)` declaration written in Plan 1 was inert. Turning
  /// it on here makes an orphaned answer row impossible at the DB layer — a
  /// second line of defense behind [insertAnsweredSession]'s transaction
  /// (T-03-01 / PERSIST-02 / D-08).
  ///
  /// Deliberately NOT a schema migration and NOT a version bump: the pragma is
  /// connection state, and the `REFERENCES` clause already exists in databases
  /// created by Plan 1. Devices that have already run the app therefore pick
  /// enforcement up on their next launch with no upgrade path, and SQLite does
  /// not re-validate pre-existing rows when the pragma is enabled — so an old
  /// database can never fail to open because of this change.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
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

  /// Every saved session, most recent first (HIST-01).
  Future<List<Session>> listSessions() async {
    final db = await database;
    final rows = await db.query(kSessionsTable, orderBy: 'id DESC');
    return rows.map(Session.fromMap).toList();
  }

  /// The answered questions belonging to [sessionId], in insertion order
  /// (HIST-02). Scoped strictly to that session via a parameterised `where`.
  Future<List<QuestionAnswer>> listAnswersForSession(int sessionId) async {
    final db = await database;
    final rows = await db.query(
      kQuestionAnswersTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(QuestionAnswer.fromMap).toList();
  }

  /// Every audio path the database still points at, as DB-relative paths.
  ///
  /// Used to sweep recording files left behind on disk by a process kill that
  /// happened mid-recording — those were never committed to the database, so
  /// nothing references them (D-08: an interrupted recording leaves no trace).
  Future<Set<String>> listReferencedAudioPaths() async {
    final db = await database;
    final rows = await db.query(
      kQuestionAnswersTable,
      columns: ['audio_path'],
    );
    return rows.map((row) => row['audio_path']! as String).toSet();
  }

  /// Closes the memoized connection, if one was ever opened.
  ///
  /// The memo is cleared BEFORE the close is awaited, so a caller that reaches
  /// [database] during the close gets a fresh open rather than a handle that is
  /// about to become invalid.
  Future<void> close() async {
    final pending = _dbFuture;
    _dbFuture = null;
    if (pending == null) return;
    final db = await pending;
    await db.close();
  }
}
