import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/question_answer.dart';
import '../models/session.dart';
import '../services/audio_player_service.dart';
import '../utils/audio_paths.dart';
import '../utils/date_format.dart';
import 'history_screen.dart' show kHistoryErrorMessage;

/// Shown when the recording a row points at is no longer on disk.
///
/// A tap that finds nothing to play must say so. Silence is indistinguishable
/// from a broken app, and this phase promises the user their answers are
/// retrievable — when one is not, that has to be stated.
const String kRecordingMissingMessage =
    'That recording is no longer available on this device.';

/// Shown when the file exists but the player refused it.
const String kRecordingPlaybackFailedMessage =
    "Couldn't play that recording — try again.";

/// One session's answered questions, each replayable on tap (HIST-02/HIST-03).
///
/// In Phase 1 this always renders exactly one row; Phase 2 reuses the same row
/// component for many rows without restructuring.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.databaseHelper,
    this.audioPlayerService,
  });

  final Session session;
  final DatabaseHelper databaseHelper;

  /// Injection seam, mirroring `PracticeState`'s constructor injection.
  ///
  /// Production leaves this null and the screen builds its own service. A
  /// widget test MUST supply one (wrapping a fake [AudioPlaybackBackend]),
  /// because the real backend's first call reaches a platform channel that has
  /// no implementation under `flutter test` and never replies — a tap test
  /// would hang rather than fail.
  final AudioPlayerService? audioPlayerService;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late final AudioPlayerService _audioPlayerService;
  late Future<List<QuestionAnswer>> _answersFuture;

  @override
  void initState() {
    super.initState();
    // Constructing the service touches no platform channel — its backend is
    // resolved lazily on first play/stop/dispose.
    _audioPlayerService = widget.audioPlayerService ?? AudioPlayerService();
    _load();
  }

  /// The one place the query is issued — used by [initState] and by retry.
  ///
  /// [Session.id] is nullable and `Session.fromMap` will happily produce a
  /// null, so force-unwrapping it here would turn a data problem into a
  /// red-screen crash inside `initState` (T-06-03). A session with no id has no
  /// rows to fetch, which is exactly an empty list.
  void _load() {
    final int? id = widget.session.id;
    _answersFuture = id == null
        ? Future.value(const <QuestionAnswer>[])
        : widget.databaseHelper.listAnswersForSession(id);
  }

  @override
  void dispose() {
    unawaited(_audioPlayerService.dispose());
    super.dispose();
  }

  /// Replays one answer. A tap can never be a silent no-op.
  Future<void> _play(QuestionAnswer answer) async {
    // Stop whatever is already playing FIRST, so a second tap replaces the
    // previous recording instead of overlapping it. A failure to stop is not
    // a reason to refuse the new playback.
    try {
      await _audioPlayerService.stop();
    } catch (_) {
      // Nothing was playing, or the player rejected the stop; either way the
      // play below is still the right next step.
    }

    // The DB stores a relative path; resolve it against the CURRENT documents
    // directory so the recording still plays after an app update.
    final String absolutePath = await toAbsolutePath(answer.audioPath);

    if (!await File(absolutePath).exists()) {
      _showMessage(kRecordingMissingMessage);
      return;
    }

    try {
      await _audioPlayerService.play(absolutePath);
    } catch (_) {
      // Deliberately does not surface the exception text (T-06-04).
      _showMessage(kRecordingPlaybackFailedMessage);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Session — ${formatSessionTimestamp(widget.session.createdAt)}',
          style: theme.textTheme.headlineSmall,
        ),
      ),
      body: FutureBuilder<List<QuestionAnswer>>(
        future: _answersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          // MUST come before the `snapshot.data` read: on error `data` is null,
          // so falling through would render an unreadable session as a session
          // that simply has no questions (T-06-01).
          if (snapshot.hasError) {
            return _SessionDetailError(onRetry: () => setState(_load));
          }
          final answers = snapshot.data ?? const <QuestionAnswer>[];
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: answers.length,
            itemBuilder: (context, index) {
              final answer = answers[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Material(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      // `unawaited` rather than a dropped future: every failure
                      // inside `_play` is already handled there, and this makes
                      // the fire-and-forget deliberate rather than accidental.
                      onTap: () => unawaited(_play(answer)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                answer.questionText,
                                // Detail rows sit at list scale, not the live
                                // Practice-screen prompt scale.
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.play_circle_fill,
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The detail screen's read-failure state — the same shape and the same copy as
/// `_HistoryError`, so the app has exactly one failure voice for "your saved
/// recordings could not be read", just as `kRecordingErrorMessage` gives the
/// practice loop one voice for "recording failed".
///
/// Never renders `snapshot.error` (T-06-04).
class _SessionDetailError extends StatelessWidget {
  const _SessionDetailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: const Key('session-detail-error'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              kHistoryErrorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            TextButton(
              key: const Key('session-detail-error-retry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                // Touch-target floor, not part of the 4px content scale.
                minimumSize: const Size(64, 48),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
