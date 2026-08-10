import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// The "let the user hand me a JSON file" capability, reduced to what the
/// importer needs (IMPORT-01).
///
/// **Why this seam exists at all**, rather than calling `FilePicker` directly:
/// the package reaches a platform channel, so an unmediated call raises
/// `MissingPluginException` under `flutter test` — every widget test of the
/// import sheet would fail on a capability none of them are about. This is the
/// fifth seam of the ESTABLISHED shape (`RecorderBackend`,
/// `AudioPlaybackBackend`, `ScreenWakeController`, `QuestionSource`): abstract
/// contract free of package types, one named production implementation, and an
/// injected instance resolved lazily so a test that supplies a fake never
/// constructs a platform channel.
///
/// **No picker type crosses this seam.** No `FilePickerResult`, no
/// `PlatformFile`, no `File`, no `FileSystemException` — only the file's decoded
/// text out, `null` for a cancelled pick, and
/// [ImportFileUnreadableException] in. The `dart:io` read lives BEHIND the seam
/// deliberately: an unreadable file must become this seam's own signal rather
/// than an I/O exception reaching `import_sheet.dart`.
abstract class JsonFilePicker {
  /// Opens the OS document picker and returns the chosen file's decoded text.
  ///
  /// Returns `null` when the user cancelled. **Cancellation is not a failure**
  /// and gets no user-facing copy at all (UI-SPEC step 3a): the sheet simply
  /// stays on its idle state with the format hint still on screen.
  ///
  /// Throws [ImportFileUnreadableException] when a file WAS chosen but could not
  /// be read or decoded. That is a different fact from cancelling and from the
  /// file being wrongly shaped, and it gets its own state in the sheet.
  Future<String?> pickJsonText();
}

/// Thrown when a chosen file could not be opened, read, or decoded as text.
///
/// A *signal*, not a crash: the import sheet catches it and shows the
/// pre-approved user-facing copy. Its own text is developer-facing only and is
/// never rendered to the user — structurally identical to
/// `QuestionBankUnavailableException` and `RecordingPermissionDeniedException`.
///
/// Deliberately distinct from the wrong-shape signal in `question_importer.dart`:
/// a file that never opened and a file that opened but is not a question file
/// are two different facts with two different messages, and telling the user
/// "it needs to look like this" about a file the app never read would be a false
/// explanation.
class ImportFileUnreadableException implements Exception {
  const ImportFileUnreadableException();

  @override
  String toString() => 'ImportFileUnreadableException';
}

/// The production implementation: `package:file_picker`.
///
/// The picker is asked for [FileType.custom] restricted to the single `json`
/// extension, so the OS itself does the filtering and the app needs no "that
/// isn't a JSON file" screen. The picker surface is OS chrome this app does not
/// style and must not try to.
///
/// **Two read paths, on purpose.** Which of `bytes` and `path` the plugin
/// populates is platform-dependent and is NOT verified in this repo, so the
/// adapter handles both: in-memory bytes are preferred (asked for with
/// `withData: true`) and decoded as UTF-8, and a returned path is read with
/// `dart:io` when bytes are absent. Which branch ran is logged, so the
/// on-device UAT in plan 04-05 answers the question rather than leaving it
/// guessed at. Containing that uncertainty in one file is exactly what the seam
/// is for.
class FilePickerJsonFilePicker implements JsonFilePicker {
  const FilePickerJsonFilePicker();

  @override
  Future<String?> pickJsonText() async {
    final FilePickerResult? result;
    try {
      // A STATIC call, not `FilePicker.platform.pickFiles(...)`: in
      // file_picker 11 `FilePicker` is an `abstract final class` whose entry
      // points are statics, and the older instance-based `platform` getter is
      // gone. Verified against the installed 11.0.3 source.
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
        // Ask for the bytes up front so the common path needs no filesystem
        // read at all. Question files are a few hundred KB at most, so holding
        // one in memory is cheaper than a second round trip.
        withData: true,
      );
    } catch (error, stack) {
      // Exception detail goes to the console and NOWHERE else — no exception
      // text and no file path may reach the screen.
      debugPrint('File pick failed: $error');
      debugPrintStack(stackTrace: stack);
      throw const ImportFileUnreadableException();
    }

    // A cancelled pick. `null` all the way out: the sheet must not treat this
    // as a failure.
    if (result == null || result.files.isEmpty) {
      debugPrint('File pick cancelled by the user.');
      return null;
    }

    final picked = result.files.first;
    try {
      final bytes = picked.bytes;
      if (bytes != null) {
        debugPrint('Import file read from in-memory bytes (${bytes.length} B).');
        return utf8.decode(bytes);
      }
      final path = picked.path;
      if (path != null) {
        debugPrint('Import file read from a path — the plugin supplied no '
            'bytes on this platform.');
        return await File(path).readAsString();
      }
    } catch (error, stack) {
      debugPrint('Import file could not be read or decoded: $error');
      debugPrintStack(stackTrace: stack);
      throw const ImportFileUnreadableException();
    }

    // Neither bytes nor a path: the plugin handed back a result it cannot back
    // with content. Loud rather than silently treated as a cancellation — the
    // user DID choose a file and is owed a message.
    debugPrint('Import file has neither bytes nor a path — nothing to read.');
    throw const ImportFileUnreadableException();
  }
}
