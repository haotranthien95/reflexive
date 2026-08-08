import 'dart:async';

import 'package:flutter/material.dart';

import '../data/questions.dart';
import '../db/database_helper.dart';
import '../models/session_config.dart';
import '../services/audio_player_service.dart';
import '../services/recording_service.dart';
import '../utils/audio_paths.dart';
import 'history_screen.dart';
import 'practice_screen.dart';

/// The D-16/D-17 session defaults. Every visit to Setup starts here, because
/// settings are deliberately not remembered between sessions (D-18).
const String kDefaultLevel = 'B1';
const int kDefaultQuestionCount = 10;
const int kDefaultThinkingSeconds = 5;
const int kDefaultAnswerSeconds = 60;
const bool kDefaultAutoReplay = true;

/// The app's home screen (D-28): configure a session, then start it.
///
/// Plan 02-01 builds only the topic section and the gated START SESSION action —
/// the level chips, the three sliders and the replay toggle land in plan 02-02
/// and feed the same [SessionConfig]. Until then Start supplies the defaults
/// above, so the config travelling into a session is already the real shape.
///
/// **Local state only** (D-18): nothing here is written to the database, so this
/// screen adds no persistence surface and no schema version bump.
///
/// The services are optional constructor parameters for the same reason
/// `HistoryScreen` takes its [DatabaseHelper]: it is the seam a widget test
/// injects an ffi-backed helper and channel-free fakes on, so the real
/// Setup → session → committed answer path can be driven on the host. In
/// production every one of them is null and the real implementations are built
/// lazily.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    this.databaseHelper,
    this.recordingService,
    this.audioPlayerService,
    this.subjects,
  });

  final DatabaseHelper? databaseHelper;
  final RecordingService? recordingService;
  final AudioPlayerService? audioPlayerService;

  /// Overrides [kSubjects]. Exists for the held-out empty-topic-list test: the
  /// empty branch is unreachable in production this phase (the list is a
  /// non-empty constant) and goes live when Phase 3 sources it from Firestore.
  final List<String>? subjects;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final DatabaseHelper _databaseHelper =
      widget.databaseHelper ?? DatabaseHelper();

  final Set<String> _selectedTopics = <String>{};

  List<String> get _subjects => widget.subjects ?? kSubjects;

  @override
  void initState() {
    super.initState();
    unawaited(_sweepOrphanRecordings());
  }

  /// Sweeps recording files no database row points at.
  ///
  /// Moved here from `PracticeScreen` when Setup became the home screen (D-28),
  /// and its caller contract moved with it: [pruneOrphanRecordings] must
  /// complete BEFORE the next recording's file name is chosen, because a file
  /// being written right now is by definition unreferenced and would be deleted.
  /// Setup is now the earliest point at which that is true — the user cannot
  /// reach a microphone without passing through this screen first.
  Future<void> _sweepOrphanRecordings() async {
    try {
      await pruneOrphanRecordings(
        await _databaseHelper.listReferencedAudioPaths(),
      );
    } catch (_) {
      // Cleanup is best-effort; never let it stand between the user and the
      // microphone.
    }
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(databaseHelper: _databaseHelper),
      ),
    );
  }

  void _toggleTopic(String subject, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selectedTopics.add(subject);
      } else {
        _selectedTopics.remove(subject);
      }
    });
  }

  void _startSession() {
    final config = SessionConfig(
      topics: List<String>.unmodifiable(
        _subjects.where(_selectedTopics.contains),
      ),
      level: kDefaultLevel,
      questionCount: kDefaultQuestionCount,
      thinkingSeconds: kDefaultThinkingSeconds,
      answerSeconds: kDefaultAnswerSeconds,
      autoReplay: kDefaultAutoReplay,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeScreen(
          config: config,
          databaseHelper: _databaseHelper,
          recordingService: widget.recordingService,
          audioPlayerService: widget.audioPlayerService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool canStart = _selectedTopics.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('EnglishReflex', style: theme.textTheme.headlineSmall),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Exercise History',
            onPressed: _openHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // Scrolls rather than clips once the OS text-scale setting grows
              // the content past the viewport (UI-01). The Start footer is
              // pinned OUTSIDE this, so the CTA never scrolls away.
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24, // lg — screen edge padding
                  vertical: 32, // xl
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Topics', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8), // sm
                    _TopicsCard(
                      subjects: _subjects,
                      selected: _selectedTopics,
                      onChanged: _toggleTopic,
                    ),
                  ],
                ),
              ),
            ),
            _StartFooter(canStart: canStart, onStart: _startSession),
          ],
        ),
      ),
    );
  }
}

/// The peach topic card — the one peach surface on Setup, because peach marks
/// question-bank DATA (it becomes Firestore-backed in Phase 3), never form
/// chrome.
class _TopicsCard extends StatelessWidget {
  const _TopicsCard({
    required this.subjects,
    required this.selected,
    required this.onChanged,
  });

  final List<String> subjects;
  final Set<String> selected;
  final void Function(String subject, bool? checked) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A `Material` rather than a decorated `Container`: a `ListTile` paints its
    // background and ink splashes onto the nearest `Material` ancestor, so a
    // coloured box between the two hides the row's own tap feedback — Flutter
    // asserts on exactly that. Same pattern the history rows already use.
    return Material(
      key: const Key('setup-topics-card'),
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(24), // lg
        child: subjects.isEmpty
            ? const _NoTopics()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final subject in subjects)
                    ConstrainedBox(
                      // Touch-target floor, not part of the 4px content scale.
                      // A ConstrainedBox (not a fixed height) so a long subject
                      // name at max text scale GROWS the row instead of
                      // clipping.
                      constraints: const BoxConstraints(minHeight: 64),
                      child: CheckboxListTile(
                        key: Key('setup-topic-$subject'),
                        value: selected.contains(subject),
                        onChanged: (checked) => onChanged(subject, checked),
                        activeColor: theme.colorScheme.primary,
                        checkColor: theme.colorScheme.onPrimary,
                        // The card already supplies the 24px horizontal padding.
                        contentPadding: EdgeInsets.zero,
                        title: Text(subject, style: theme.textTheme.labelLarge),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Unreachable in Phase 2 — [kSubjects] is a non-empty constant (D-19). The copy
/// is locked now so Phase 3's Firestore swap has a state to land on rather than
/// inventing one under deadline.
class _NoTopics extends StatelessWidget {
  const _NoTopics();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('setup-topics-empty'),
      children: [
        Text(
          'No topics yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8), // sm
        Text(
          'Import some questions and your topics will show up here.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

/// The pinned footer. Deliberately outside the scroll view: START SESSION is the
/// screen's only action and must never be scrolled off.
class _StartFooter extends StatelessWidget {
  const _StartFooter({required this.canStart, required this.onStart});

  final bool canStart;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 24, // lg
        vertical: 16, // md
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shown ONLY while Start is disabled: the disabled button and the
          // reason it is disabled always arrive together, which is why the
          // disabled state keeps a full-opacity label rather than greying out.
          if (!canStart) ...[
            Text(
              'Pick at least one topic to start.',
              key: const Key('setup-start-blocked'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8), // sm
          ],
          SizedBox(
            width: double.infinity,
            height: 64, // Touch-target floor from the UI-SPEC exceptions.
            child: FilledButton(
              key: const Key('setup-start'),
              // Null — not a swallowed tap — so the gate is enforced by the
              // widget itself and SETUP-07 cannot be defeated by a stray
              // handler (D-19).
              onPressed: canStart ? onStart : null,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                disabledBackgroundColor: theme.colorScheme.surface,
                disabledForegroundColor: theme.colorScheme.onSurface,
              ),
              child: Text('START SESSION', style: theme.textTheme.labelLarge),
            ),
          ),
        ],
      ),
    );
  }
}
