import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../services/audio_player_service.dart';
import '../services/recording_service.dart';
import '../state/practice_state.dart';
import '../widgets/mascot.dart';
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
    final theme = Theme.of(context);

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
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _state,
          builder: (context, _) {
            final bool hasError = _state.phase == PracticePhase.error;

            // The banner is docked above the question, never instead of it:
            // UI-SPEC requires the question screen stay visible so the user is
            // not left staring at a blank, dead-end screen.
            return Column(
              children: [
                if (hasError)
                  _ErrorBanner(
                    message: _state.errorMessage ?? kRecordingErrorMessage,
                    onRetry: _state.retry,
                  ),
                Expanded(
                  // Centred normally, scrollable rather than clipped once the
                  // OS text-scale setting grows the content past the viewport
                  // (UI-01).
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, // lg — screen edge padding
                          vertical: 32, // xl
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 64,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Mascot(
                                isRecording:
                                    _state.phase == PracticePhase.recording,
                                isError: hasError,
                              ),
                              const SizedBox(height: 32), // xl
                              _QuestionCard(question: _state.currentQuestion),
                              const SizedBox(height: 48), // 2xl
                              if (_state.phase == PracticePhase.recording)
                                _StopButton(onPressed: _state.stopRecording),
                              if (_state.phase == PracticePhase.replaying)
                                Text(
                                  'Playing your answer…',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The failure banner (UI-SPEC "error" state).
///
/// The warm-red error colour is applied to the icon, the message and the Retry
/// label only — never as a full-bleed red fill, which the palette reserves it
/// from. [message] is always the fixed UI-SPEC copy handed down by
/// [PracticeState]; this widget has no access to, and never renders, exception
/// detail (T-03-02).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color error = theme.colorScheme.error;

    return Container(
      key: const Key('practice-error-banner'),
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(16), // md
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: error),
              const SizedBox(width: 8), // sm
              // Expanded (not a fixed width) so the copy wraps instead of
              // overflowing at the largest OS text-scale setting.
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyLarge?.copyWith(color: error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8), // sm
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: error,
                // Keeps the affordance comfortably above the 44px touch-target
                // floor even though it is a text button.
                minimumSize: const Size(64, 48),
              ),
              child: Text('Retry', style: theme.textTheme.labelLarge?.copyWith(
                color: error,
              )),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prompt, on the peach secondary surface with generously rounded corners.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24), // lg
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        question,
        textAlign: TextAlign.center,
        style: theme.textTheme.displayLarge,
      ),
    );
  }
}

/// The 96px circular Stop target — the single most important tap target on the
/// screen, deliberately far above the 44px minimum (UI-SPEC spacing exception).
class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 96,
      height: 96,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        // Scales the label down rather than overflowing the fixed-size target
        // at the largest OS text-scale setting.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stop_rounded, size: 28),
              Text('STOP', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}
