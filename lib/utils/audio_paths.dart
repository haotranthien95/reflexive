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
