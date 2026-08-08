import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/question_answer.dart';
import '../models/session.dart';
import '../services/audio_player_service.dart';
import '../utils/audio_paths.dart';
import '../utils/date_format.dart';

/// One session's answered questions, each replayable on tap (HIST-02/HIST-03).
///
/// In Phase 1 this always renders exactly one row; Phase 2 reuses the same row
/// component for many rows without restructuring.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.databaseHelper,
  });

  final Session session;
  final DatabaseHelper databaseHelper;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final AudioPlayerService _audioPlayerService = AudioPlayerService();
  late Future<List<QuestionAnswer>> _answersFuture;

  @override
  void initState() {
    super.initState();
    _answersFuture =
        widget.databaseHelper.listAnswersForSession(widget.session.id!);
  }

  @override
  void dispose() {
    _audioPlayerService.dispose();
    super.dispose();
  }

  Future<void> _play(QuestionAnswer answer) async {
    // The DB stores a relative path; resolve it against the CURRENT documents
    // directory so the recording still plays after an app update.
    final absolutePath = await toAbsolutePath(answer.audioPath);
    await _audioPlayerService.play(absolutePath);
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
                      onTap: () => _play(answer),
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
