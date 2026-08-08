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

/// The six CEFR levels (SETUP-02 / D-17) — a fixed, closed, single-select set.
/// The row can never be empty and exactly one entry is always selected, so
/// there is no "nothing chosen" state to design for.
const List<String> kLevels = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// The app's home screen (D-28): configure a session, then start it.
///
/// Owns all six configurable values — topics, level, question count, thinking
/// time `t`, answer length `d` and auto-replay `r` — and packs them into one
/// immutable [SessionConfig] when START SESSION fires.
///
/// **Local state only, deliberately forgetful** (D-18): every field below is a
/// plain [State] field. Nothing is written to `SharedPreferences`, to the
/// database, or to a file, so this screen adds no persistence surface and no
/// schema version bump. The alternative — a one-row `settings` table remembering
/// the last-used configuration between sessions — was considered and DEFERRED:
/// it buys a returning user a few taps at the cost of a new schema, a migration
/// path and a "reset to defaults" affordance, none of which a drill tool with
/// five settings has earned yet. Every visit therefore starts from the constants
/// above, which is also why there is no reset button: there is nothing to reset.
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

  String _level = kDefaultLevel;
  int _questionCount = kDefaultQuestionCount;
  int _thinkingSeconds = kDefaultThinkingSeconds;
  int _answerSeconds = kDefaultAnswerSeconds;
  bool _autoReplay = kDefaultAutoReplay;

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
      level: _level,
      questionCount: _questionCount,
      thinkingSeconds: _thinkingSeconds,
      answerSeconds: _answerSeconds,
      autoReplay: _autoReplay,
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
                    const SizedBox(height: 32), // xl — between Setup sections
                    // The chip row sits directly on the ivory background, NOT
                    // inside a peach card: unselected chips are peach, and
                    // peach on peach would make them vanish.
                    _LevelChips(
                      selected: _level,
                      onSelected: (level) => setState(() => _level = level),
                    ),
                    const SizedBox(height: 32), // xl
                    _SettingSlider(
                      keyPrefix: 'setup-count',
                      label: 'Questions',
                      // No helper line — "Questions" over a bare numeral needs
                      // no explanation, and the bare numeral also sidesteps the
                      // singular/plural problem entirely.
                      readout: '$_questionCount',
                      value: _questionCount.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      semanticFormatter: (value) =>
                          '${value.round()} questions',
                      onChanged: (value) =>
                          setState(() => _questionCount = value.round()),
                    ),
                    const SizedBox(height: 32), // xl
                    _SettingSlider(
                      keyPrefix: 'setup-thinking',
                      label: 'Thinking time',
                      helper:
                          'How long you get to read the question before recording starts.',
                      readout: '$_thinkingSeconds sec',
                      value: _thinkingSeconds.toDouble(),
                      min: 3,
                      max: 30,
                      divisions: 27,
                      semanticFormatter: (value) =>
                          '${value.round()} seconds thinking time',
                      onChanged: (value) =>
                          setState(() => _thinkingSeconds = value.round()),
                    ),
                    const SizedBox(height: 32), // xl
                    _SettingSlider(
                      keyPrefix: 'setup-answer',
                      label: 'Answer length',
                      helper: 'Recording stops automatically after this long.',
                      readout: '$_answerSeconds sec',
                      value: _answerSeconds.toDouble(),
                      min: 10,
                      max: 120,
                      divisions: 110,
                      semanticFormatter: (value) =>
                          '${value.round()} seconds answer length',
                      onChanged: (value) =>
                          setState(() => _answerSeconds = value.round()),
                    ),
                    const SizedBox(height: 32), // xl
                    _ReplayToggle(
                      value: _autoReplay,
                      onChanged: (value) =>
                          setState(() => _autoReplay = value),
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

/// The CEFR level row (SETUP-02 / D-17): six single-select chips, B1 first.
///
/// Single-select is an invariant, not a validation rule — tapping the selected
/// chip again is a no-op rather than a deselect, so exactly one level is always
/// in force and the row can never reach an empty state.
class _LevelChips extends StatelessWidget {
  const _LevelChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Level', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8), // sm
        Text(
          "CEFR level of the questions you'll get.",
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8), // sm
        Wrap(
          key: const Key('setup-level-chips'),
          spacing: 8, // sm
          runSpacing: 8, // sm — wrapping to a second line at large text scale
          // is the SPECIFIED behaviour here, not an overflow failure.
          children: [
            for (final level in kLevels)
              ChoiceChip(
                key: Key('setup-level-$level'),
                label: Text(level, style: theme.textTheme.labelLarge),
                selected: selected == level,
                // The fill alone carries selection; a checkmark would shift the
                // chip's width as selection moves and jitter the whole row.
                showCheckmark: false,
                backgroundColor: theme.colorScheme.surface, // peach
                selectedColor: theme.colorScheme.primary, // coral
                side: BorderSide.none,
                onSelected: (isSelected) {
                  if (isSelected) onSelected(level);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// One numeric setting: section label, optional helper, a large centred readout
/// and the slider that drives it.
///
/// The readout is always visible, which is why the slider carries no `label:`
/// value-indicator popup — the popup would duplicate it and only while dragging.
/// `min`/`max`/`divisions` make an out-of-range value unrepresentable, so there
/// is no validation-error treatment anywhere on this screen: the constraint is
/// enforced by the widget rather than announced by a message.
class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.keyPrefix,
    required this.label,
    required this.readout,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.semanticFormatter,
    required this.onChanged,
    this.helper,
  });

  final String keyPrefix;
  final String label;
  final String? helper;
  final String readout;
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// Gives a screen reader "10 questions" rather than a bare "10".
  final String Function(double value) semanticFormatter;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8), // sm
        if (helper != null) ...[
          Text(helper!, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8), // sm
        ],
        Text(
          readout,
          key: Key('$keyPrefix-readout'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displayLarge,
        ),
        const SizedBox(height: 8), // sm
        Slider(
          key: Key('$keyPrefix-slider'),
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: theme.colorScheme.primary, // coral
          thumbColor: theme.colorScheme.primary,
          inactiveColor: theme.colorScheme.surface, // peach
          semanticFormatterCallback: semanticFormatter,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The auto-replay switch (SETUP-06), ON by default so the loop the user
/// already knows from Phase 1 (D-10) is what they get without touching anything.
class _ReplayToggle extends StatelessWidget {
  const _ReplayToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      // Touch-target floor, not part of the 4px content scale. A constraint
      // rather than a fixed height so the title and helper GROW the row at
      // large text scale instead of clipping.
      constraints: const BoxConstraints(minHeight: 64),
      child: SwitchListTile(
        key: const Key('setup-replay'),
        value: value,
        onChanged: onChanged,
        // Coral track with the brown `onPrimary` thumb: a coral thumb on a
        // coral track would be invisible, and brown-on-coral is the same 4.7:1
        // pairing every other coral control on the screen uses.
        activeTrackColor: theme.colorScheme.primary,
        activeThumbColor: theme.colorScheme.onPrimary,
        // The screen padding already supplies the 24px horizontal inset.
        contentPadding: EdgeInsets.zero,
        title: Text('Play back my answers', style: theme.textTheme.labelLarge),
        subtitle: Text(
          'Hear each answer right after you record it.',
          style: theme.textTheme.bodyLarge,
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
