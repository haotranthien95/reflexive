import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../services/audio_player_service.dart';
import '../services/recording_service.dart';
import '../state/practice_state.dart';
import 'history_screen.dart';

/// The single practice screen: a question appears and recording starts the
/// instant the screen opens (D-01). No Start button, no elapsed timer, no
/// countdown (D-04) — just a big Stop button while recording.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  late final PracticeState _state;

  @override
  void initState() {
    super.initState();
    _state = PracticeState(
      recordingService: RecordingService(),
      audioPlayerService: AudioPlayerService(),
      databaseHelper: DatabaseHelper(),
    );
    // Reflex framing: recording begins immediately, with no user action.
    _state.startNewQuestion();
  }

  @override
  void dispose() {
    _state.recordingService.dispose();
    _state.audioPlayerService.dispose();
    _state.dispose();
    super.dispose();
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(databaseHelper: _state.databaseHelper),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EnglishReflex'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Exercise History',
            onPressed: _openHistory,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _state.currentQuestion,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 48),
                if (_state.phase == PracticePhase.recording)
                  FilledButton.icon(
                    onPressed: _state.stopRecording,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('STOP'),
                  ),
                if (_state.phase == PracticePhase.replaying)
                  const Text('Playing your answer…'),
              ],
            ),
          );
        },
      ),
    );
  }
}
