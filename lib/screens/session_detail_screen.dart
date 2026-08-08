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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Session — ${formatSessionTimestamp(widget.session.createdAt)}',
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
            itemCount: answers.length,
            itemBuilder: (context, index) {
              final answer = answers[index];
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: ListTile(
                  title: Text(answer.questionText),
                  trailing: const Icon(Icons.play_circle_fill),
                  onTap: () => _play(answer),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
