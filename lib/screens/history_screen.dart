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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Exercise History',
          style: theme.textTheme.headlineSmall,
        ),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ConstrainedBox(
                  // Touch-target floor, not part of the 4px content scale.
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Material(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionDetailScreen(
                            session: session,
                            databaseHelper: widget.databaseHelper,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatSessionTimestamp(session.createdAt),
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Accent marks the tappable affordance. Tapping a
                            // session opens its detail rather than playing, so
                            // this stays a chevron; the play icon lives on the
                            // detail rows that actually play audio.
                            Icon(
                              Icons.chevron_right,
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No recordings yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              "Finish your first answer and it'll show up here.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
