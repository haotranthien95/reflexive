import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/session.dart';
import '../utils/date_format.dart';
import 'session_detail_screen.dart';

/// Exercise History — every saved session, most recent first (HIST-01).
///
/// Session-first by design (D-06): Phase 1 sessions happen to hold exactly one
/// answer, but the list → detail structure is final and Phase 2 only adds more
/// rows to the detail screen.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.databaseHelper});

  final DatabaseHelper databaseHelper;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Session>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = widget.databaseHelper.listSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise History')),
      body: FutureBuilder<List<Session>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data ?? const <Session>[];
          if (sessions.isEmpty) {
            return const _EmptyHistory();
          }
          return ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: ListTile(
                  title: Text(formatSessionTimestamp(session.createdAt)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SessionDetailScreen(
                        session: session,
                        databaseHelper: widget.databaseHelper,
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No recordings yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              "Finish your first answer and it'll show up here.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
