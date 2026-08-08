import 'dart:io';

import 'package:englishreflex/utils/audio_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('englishreflex_paths_test');
    documentsDirProvider = () async => tempDir;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeRecording(String fileName) async {
    final dir = await ensureRecordingsDir();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString('fake audio bytes');
    return file;
  }

  group('pruneOrphanRecordings', () {
    test('deletes a file left behind by a kill mid-recording', () async {
      // A force-kill before Stop finalizes leaves a partial file that no
      // database row references (D-08). Nothing in the UI can reach it, so it
      // must not linger on disk either.
      final orphan = await writeRecording('1700000000000.m4a');

      final deleted = await pruneOrphanRecordings(const <String>{});

      expect(deleted, 1);
      expect(await orphan.exists(), isFalse);
    });

    test('never touches a file a saved answer still points at', () async {
      final kept = await writeRecording('kept.m4a');
      final orphan = await writeRecording('orphan.m4a');

      final deleted =
          await pruneOrphanRecordings({recordingRelativePath('kept.m4a')});

      expect(deleted, 1);
      expect(await kept.exists(), isTrue);
      expect(await orphan.exists(), isFalse);
    });

    test('is a harmless no-op when there is nothing to sweep', () async {
      expect(await pruneOrphanRecordings(const <String>{}), 0);
    });
  });
}
