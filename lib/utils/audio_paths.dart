import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Single seam for resolving the app's private documents directory.
///
/// Everything that touches app-local storage (recorded audio files AND the
/// SQLite database file) goes through this one function so that:
///
///  * production code always lands inside `path_provider`'s app-private
///    documents container (never external/shared storage) — T-01-01;
///  * `flutter test` can substitute a temp directory, because `path_provider`
///    has no plugin implementation on the test host. This mirrors sqflite's
///    own `databaseFactory` override pattern.
///
/// Tests override this by assigning [documentsDirProvider].
typedef DocumentsDirProvider = Future<Directory> Function();

/// Overridable provider for the app documents directory. Defaults to
/// `path_provider`'s `getApplicationDocumentsDirectory()`.
DocumentsDirProvider documentsDirProvider = getApplicationDocumentsDirectory;

/// Resolves the app documents directory (test-overridable).
Future<Directory> appDocumentsDir() => documentsDirProvider();

/// Name of the sub-directory (relative to the documents dir) holding recordings.
const String kRecordingsDirName = 'recordings';

/// Resolves `<appDocumentsDir>/recordings`, creating it if it does not exist.
Future<Directory> ensureRecordingsDir() async {
  final docsDir = await appDocumentsDir();
  final dir = Directory(p.join(docsDir.path, kRecordingsDirName));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Turns a DB-stored *relative* path (e.g. `recordings/1234.m4a`) into an
/// absolute path valid for the current app install.
///
/// Absolute paths are never stored in the DB: on iOS the sandbox container
/// path changes across app updates, so a persisted absolute path goes stale.
Future<String> toAbsolutePath(String relativePath) async {
  final docsDir = await appDocumentsDir();
  return p.join(docsDir.path, relativePath);
}

/// Builds the DB-stored relative path for a recording file name.
String recordingRelativePath(String fileName) =>
    p.join(kRecordingsDirName, fileName);

/// Deletes every file in the recordings directory that no database row points
/// at, and returns how many were removed.
///
/// This is the disk half of D-08's "an interrupted recording leaves no trace".
/// `package:record` streams into its output file while recording, so a process
/// force-killed mid-recording leaves a partial, never-committed `.m4a` behind:
/// invisible in History (nothing references it) but permanently occupying
/// space. Sweeping it on the next launch makes "zero trace" literally true.
///
/// CALLER CONTRACT: must be awaited to completion BEFORE the next recording is
/// armed. A file being written right now is by definition unreferenced, so
/// running this concurrently with an active recording would delete it.
///
/// Best-effort by design: a file that cannot be deleted is a harmless leftover,
/// never a reason to block the practice loop.
Future<int> pruneOrphanRecordings(Set<String> referencedRelativePaths) async {
  final dir = await ensureRecordingsDir();
  var deleted = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    if (referencedRelativePaths
        .contains(recordingRelativePath(p.basename(entity.path)))) {
      continue;
    }
    try {
      await entity.delete();
      deleted++;
    } catch (_) {
      // Leave it; it is unreachable from the UI either way.
    }
  }
  return deleted;
}
