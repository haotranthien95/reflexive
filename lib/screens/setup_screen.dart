import 'dart:async';

import 'package:flutter/material.dart';

import '../data/questions.dart';
import '../db/database_helper.dart';
import '../models/session_config.dart';
import '../services/audio_player_service.dart';
import '../services/firestore_question_source.dart';
import '../services/json_file_picker.dart';
import '../services/question_bank_writer.dart';
import '../services/recording_service.dart';
import '../utils/audio_paths.dart';
import 'history_screen.dart';
import 'import_sheet.dart';
import 'practice_screen.dart';

/// The D-16/D-17 session defaults. Every visit to Setup starts here, because
/// settings are deliberately not remembered between sessions (D-18).
const String kDefaultLevel = 'B1';
const int kDefaultQuestionCount = 10;
const int kDefaultThinkingSeconds = 5;
const int kDefaultAnswerSeconds = 60;
const bool kDefaultAutoReplay = true;

// The six CEFR levels now live in `lib/services/firestore_question_source.dart`
// beside the other facts a screen and a service must agree on (D-53). The name
// is unchanged and resolves through the services import above; see that file for
// why the constant moved rather than being imported from here.

/// The single user-facing message for a topics read that could not be SERVED,
/// as opposed to a bank that is genuinely empty (D-37).
///
/// Written to the same rules as `kHistoryErrorMessage` and
/// `kRecordingErrorMessage`: name the likely cause and the next action, blame
/// nothing on the user, and leak no exception text, Firestore error code,
/// collection name, document ID or project ID to the screen.
///
/// **"Couldn't reach" is the load-bearing verb.** It names the network as the
/// suspect, so this string can never be misread as "your bank is empty" — the
/// exact confusion D-37 exists to prevent, and the reason this constant and
/// `_NoTopics`' copy must stay two different sentences.
///
/// A sibling constant, `kQuestionLoadErrorMessage`, covers the OTHER bank
/// failure — a failed Start query. They share a first clause and deliberately
/// diverge in the second, because the two failures have two different retry
/// affordances: this one has a "Try again" button directly beneath it, and that
/// one has no button at all, so its copy has to name START SESSION as the retry.
/// One fixed string per failure is Phase 1's convention; two failures earn two
/// strings, not one vague one.
const String kTopicsErrorMessage =
    "Couldn't reach your question bank — check your connection and try again.";

/// The single user-facing message for a Start query that could not be SERVED
/// (D-38).
///
/// **Why this is a sibling of [kTopicsErrorMessage] and not the same string.**
/// The first clause is identical on purpose — one failure, one voice — but the
/// second clause names the retry affordance, and the two failures have two
/// different ones. The topics card has a "Try again" button sitting directly
/// under its message; this one has no button at all, because re-tapping START
/// SESSION *is* the retry (D-38 rejected a Retry/Cancel dialog for something the
/// user can simply tap again). A shared string would have to name neither, and a
/// failure message that does not name its own next action is half a message.
///
/// Same containment rule: no exception text, no Firestore error code, no
/// collection name, no document ID, no project ID.
const String kQuestionLoadErrorMessage =
    "Couldn't reach your question bank — check your connection and tap "
    'START SESSION again.';

/// The single user-facing message for a Start attempt refused because more than
/// [kMaxTopicsPerQuery] topics are checked (D-61).
///
/// **Why this is a sibling of [kTopicsErrorMessage] and [kQuestionLoadErrorMessage]
/// and not the same string.** Those two name the CONNECTION, because that is
/// what failed. This one names a limit the user can satisfy right now by
/// unchecking a topic that is visible on the same screen — the server was never
/// asked, so there is nothing about the network to report and nothing to retry.
/// Reusing [kQuestionLoadErrorMessage] here is what the app did before this
/// phase, and it told a user with 40 topics ticked to check a connection that
/// was working perfectly.
///
/// Same containment rule as its siblings: no exception text, no error code, no
/// collection name, no document ID, no project ID. The number is written as a
/// literal rather than interpolated from [kMaxTopicsPerQuery] because the copy
/// is a fixed, reviewed sentence, not a template — a `const` interpolation would
/// let an SDK bump silently rewrite user-facing text.
const String kTooManyTopicsMessage =
    'You can drill at most 30 topics at once — uncheck a few.';

/// Which of the three things the Start footer's one message can be saying.
///
/// **A total map, replacing the is-this-a-failure bool this phase retired.**
/// That bool answered a two-way question ("icon or no icon"), and the
/// over-limit case is a third answer: no icon, but not a zero-result either.
/// Adding a second bool beside it would have made two flags that can both be
/// true, which is precisely how two helper lines end up on screen at once. An
/// enum can only ever hold one value, so the footer's four keys stay mutually
/// exclusive by construction, and `_helper`'s `switch` over it is exhaustive —
/// a fifth kind added later fails to compile until it has been given a branch,
/// rather than silently falling through to the last `else`.
///
/// Carried alongside `_startMessage` and assigned together with it, in
/// `_startSession` and `_clearStartMessage` and nowhere else.
enum StartMessageKind {
  /// The server answered, and answered with nothing (D-41). No icon.
  noQuestions,

  /// The bank could not be read (D-38). Red icon — retrying is the fix.
  bankUnavailable,

  /// More than [kMaxTopicsPerQuery] topics were checked, so no query was ever
  /// issued (D-61). No icon — it is a setting to change, not a fault.
  tooManyTopics,
}

/// The zero-result explanation for a topics-by-level combination the bank has
/// nothing for (D-41).
///
/// Names **both** dimensions, because either could be the one to change, and
/// offers both actions in every branch for the same reason. "yet" is deliberate
/// and warm: the bank is growable by Phase 4's importer, so this is a temporary
/// state rather than a verdict.
///
/// **Three branches, and the third one is a length bound, not a shortcut.** The
/// footer is the one region of Setup that does not scroll, so an unbounded topic
/// list would grow the helper until it pushed the 64px button off-screen.
/// Beyond two topics the message names the COUNT and still names the topic
/// dimension ("any of your 4 topics"), which satisfies D-41 without an
/// unbounded string.
///
/// The two-topic join word is **`or`**, never `and`: the query is a disjunction
/// (`subject in [...]`), and "and" would imply a question has to match both.
///
/// A pure function, so all three branches are unit-testable on the host with no
/// widget. Zero topics is unreachable — SETUP-07 gates Start on at least one —
/// and falls into the count branch rather than earning a fourth string for a
/// state the button makes impossible.
String noQuestionsMessage(String level, List<String> topics) {
  if (topics.length == 1) {
    return 'No $level questions in ${topics.single} yet. '
        'Try another level, or pick more topics.';
  }
  if (topics.length == 2) {
    return 'No $level questions in ${topics.first} or ${topics.last} yet. '
        'Try another level, or pick more topics.';
  }
  return 'No $level questions in any of your ${topics.length} topics yet. '
      'Try another level, or pick different topics.';
}

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
    this.questionSource,
    this.jsonFilePicker,
    this.questionBankWriter,
  });

  final DatabaseHelper? databaseHelper;
  final RecordingService? recordingService;
  final AudioPlayerService? audioPlayerService;

  /// The question bank, injectable (D-47).
  ///
  /// Replaces the Phase 2 `subjects` list override, which could only stand in
  /// for the topic checkboxes. A whole [QuestionSource] stands in for the bank:
  /// a test can now script the subjects read AND the Start query — including
  /// empty results and failures — which is what lets every read state be covered
  /// on the host with no device and no new dependency.
  ///
  /// Null in production, where [FirestoreQuestionSource] is constructed lazily.
  final QuestionSource? questionSource;

  /// The import's two platform seams (IMPORT-01), injectable for the same
  /// reason [questionSource] is (D-47).
  ///
  /// They are held here and passed STRAIGHT THROUGH to [ImportSheet] rather
  /// than resolved on this screen: Setup never constructs either real
  /// implementation, so opening the sheet in a widget test touches no file
  /// picker channel and no Firestore handle. Null in production, where
  /// [FilePickerJsonFilePicker] and [FirestoreQuestionBankWriter] are built
  /// lazily inside the sheet.
  final JsonFilePicker? jsonFilePicker;
  final QuestionBankWriter? questionBankWriter;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final DatabaseHelper _databaseHelper =
      widget.databaseHelper ?? DatabaseHelper();

  /// Resolved lazily, so a test that injects a fake never constructs a Firestore
  /// handle — the same rule `PracticeScreen` applies to its wakelock.
  late final QuestionSource _questionSource =
      widget.questionSource ?? FirestoreQuestionSource();

  final Set<String> _selectedTopics = <String>{};

  String _level = kDefaultLevel;
  int _questionCount = kDefaultQuestionCount;
  int _thinkingSeconds = kDefaultThinkingSeconds;
  int _answerSeconds = kDefaultAnswerSeconds;
  bool _autoReplay = kDefaultAutoReplay;

  /// The topic checkboxes, read from the bank (SETUP-01/BANK-02).
  ///
  /// **`null` means "never successfully loaded", which is NOT the same as
  /// empty.** That distinction is the whole of D-37 in one field: an empty list
  /// is the server confirming the bank has nothing in it, and `null` is the
  /// frames before an answer arrived or after one failed to. Collapsing the two
  /// into a single empty list is what made plan 01's card tell an offline user
  /// with a full bank that their topics were gone.
  List<String>? _subjects;

  /// True while a FOREGROUND read is in flight — the initial read and every
  /// retry, never a D-35 background refresh.
  ///
  /// Starts `true` because [initState] issues that first read: the very first
  /// frame therefore renders the loading state rather than flashing an empty
  /// card at the user for one frame.
  bool _topicsLoading = true;

  /// True when the last FOREGROUND read failed. Never set by a background
  /// refresh (D-35), which must not replace good data with an error.
  bool _topicsError = false;

  /// True while the Start query is in flight (D-33) — the busy button.
  bool _starting = false;

  /// What the last Start attempt has to say for itself, or null when it has
  /// nothing to say (it succeeded, or none has happened since the user last
  /// changed something).
  ///
  /// **One message, so the three outcome helpers are mutually exclusive by
  /// construction rather than by discipline.** The companion [StartMessageKind]
  /// only chooses the treatment and the key — a red icon means *something went
  /// wrong, retrying is the fix*; no icon means *change a setting*, which the
  /// zero-result and the over-limit cases both are, for two different settings.
  /// That split is the footer's honesty signal.
  ///
  /// The two fields are null together and non-null together, and they are only
  /// ever assigned together — in [_startSession] and in [_clearStartMessage] and
  /// nowhere else. Null means the last attempt has nothing to say: it succeeded,
  /// or the user has changed something since.
  String? _startMessage;
  StartMessageKind? _startMessageKind;

  @override
  void initState() {
    super.initState();
    unawaited(_sweepOrphanRecordings());
    // Started alongside the sweep and NOT chained to it: neither awaits the
    // other, so the sweep's ordering contract (it must finish before any
    // recording file name is chosen) is untouched by how long the bank read
    // takes, and a slow network cannot delay the cleanup.
    unawaited(_loadSubjects());
  }

  /// The ONE place the subjects read is issued — [initState], the "Try again"
  /// button and the D-35 reappearance refresh all come through here, so the
  /// three can never drift into disagreeing about what a read does.
  ///
  /// [background] is the D-35 stale-while-revalidate flag and it changes exactly
  /// two things: a background read touches neither state flag (no spinner, no
  /// flip to could-not-load), and on failure it keeps the last-known topics on
  /// screen and says nothing. Loading and could-not-load are both *"there is
  /// nothing on screen"* states; reaching one of them because a silent refresh
  /// failed would replace usable data with a spinner and flicker the checkboxes
  /// on every return from History. A genuinely unreachable bank still gets an
  /// honest surface one tap away — the Start query's own failure helper.
  Future<void> _loadSubjects({bool background = false}) async {
    if (!background && !_topicsLoading) {
      setState(() {
        _topicsLoading = true;
        _topicsError = false;
      });
    }

    List<String>? subjects;
    Object? failure;
    try {
      subjects = await _questionSource.subjects();
    } on QuestionBankUnavailableException catch (error) {
      // The seam's own signal, and the only exception the production source is
      // documented to throw: the bank could not be READ. That includes the
      // zero-documents-from-cache case, which `FirestoreQuestionSource` has
      // already turned into this throw — which is why this screen needs no
      // Firestore type and no cache awareness of its own.
      failure = error;
    } catch (error, stack) {
      // Anything else is a source misbehaving, and it lands on the same honest
      // state: a read that threw is a read that was not served, whatever threw.
      failure = error;
      debugPrintStack(stackTrace: stack);
    }

    // `setState` after an `await` needs this guard: the read outlives the screen
    // whenever the user leaves Setup before it lands, and calling `setState` on
    // a disposed `State` throws.
    if (!mounted) return;

    if (failure != null) {
      // Exception detail goes to the console and NOWHERE else — no exception
      // text, no Firestore error code, no collection name, no document ID and
      // no project ID may reach the screen.
      debugPrint('Subjects read failed: $failure');
      if (background) return;
      setState(() {
        _topicsLoading = false;
        _topicsError = true;
      });
      return;
    }

    setState(() {
      _subjects = subjects;
      _topicsLoading = false;
      _topicsError = false;
      // MANDATORY after every successful read. Without it a topic that vanished
      // from the bank survives in the selection, travels into
      // `SessionConfig.topics`, and becomes a `subject in [...]` filter on a
      // value that does not exist — a silent zero-result the user cannot
      // explain, because the topic it blames is not on screen to be unchecked.
      _selectedTopics.retainAll(subjects!);
    });
  }

  /// The D-35 re-read, run whenever Setup becomes visible again.
  ///
  /// Driven from the `Navigator.push` awaits already in this file rather than
  /// from a route observer: History and Start are the only two ways off this
  /// screen, so one `await` per push covers every return path with no new
  /// machinery.
  ///
  /// **Phase 4's importer needed its own call site after all (D-51).** The
  /// prediction that used to sit here — that the importer would land the user
  /// back on Setup and need no extra wiring — holds for a pushed route and is
  /// FALSE for a modal bottom sheet, which pops no route. D-48 chose a sheet
  /// precisely so UI-03's screen count stayed three, and the cost of that choice
  /// is this: without the explicit `await` in [_openImportSheet], an import's new
  /// topics would not appear until the user left Setup and came back.
  ///
  /// Background — silent — UNLESS the card is currently showing could-not-load,
  /// where there is no good data to preserve and a spinner is an improvement on
  /// a stale error.
  Future<void> _refreshSubjectsOnReappear() =>
      _loadSubjects(background: !_topicsError);

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

  /// Awaited, unlike the plan-01 version, purely so the pop back into Setup can
  /// trigger the D-35 refresh. The push itself is unchanged.
  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(databaseHelper: _databaseHelper),
      ),
    );
    if (!mounted) return;
    await _refreshSubjectsOnReappear();
  }

  /// Opens the importer (D-48). Shaped exactly like [_openHistory], with
  /// `showModalBottomSheet` where the push would be.
  ///
  /// **The re-read hangs off the sheet's own `await`, never off the Done
  /// button's handler.** That one line covers every way the sheet can close —
  /// Done, drag-down, barrier tap and system back — so there is exactly one
  /// refresh call site and no exit path that silently skips it (D-51). Wiring it
  /// to the button would have left three exits unrefreshed.
  ///
  /// [_clearStartMessage] runs too: a "No B1 questions in Travel yet." line is
  /// very likely to have just been made false by the import that closed, and
  /// leaving it on screen would be the app contradicting itself.
  Future<void> _openImportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      // The result state's skip list is unbounded (plan 02), so the sheet sizes
      // to its content and scrolls rather than being height-locked.
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      // Ivory: a modal sheet is CHROME, and peach marks content — the two cards
      // inside it are the content.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)), // lg
      ),
      // Capped so the scrim and the drag handle stay visible and the sheet never
      // reads as a full screen — which would undo the point of D-48.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (_) => ImportSheet(
        picker: widget.jsonFilePicker,
        writer: widget.questionBankWriter,
      ),
    );
    if (!mounted) return;
    setState(_clearStartMessage);
    await _refreshSubjectsOnReappear();
  }

  void _toggleTopic(String subject, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selectedTopics.add(subject);
      } else {
        _selectedTopics.remove(subject);
      }
      _clearStartMessage();
    });
  }

  /// Drops whichever Start helper was showing.
  ///
  /// All three of them describe ONE specific attempt, so all three must go the
  /// moment that attempt stops describing the screen. "No C2 questions in Travel
  /// yet." sitting under a configuration the user has since changed to B1 is not
  /// a stale message, it is a false one — and an "at most 30 topics" line under
  /// a four-topic selection is the same lie about a different setting, made
  /// worse by the fact that unchecking a topic is precisely the action its copy
  /// asks for.
  ///
  /// Called from inside an existing `setState` in every place a setting changes
  /// — every topic, the level and all three sliders — again at the top of
  /// [_startSession], and once more when the import sheet closes.
  void _clearStartMessage() {
    _startMessage = null;
    _startMessageKind = null;
  }

  /// Runs the real filtered query, then pushes the session (D-33).
  ///
  /// The query blocks HERE rather than under the get-ready countdown on the
  /// practice screen: a failure therefore leaves the user on Setup with every
  /// setting intact and nothing to unwind, and `PracticeScreen` keeps its
  /// contract of being handed everything it needs.
  Future<void> _startSession() async {
    // Snapshotted FIRST and synchronously: the values at tap time are the ones
    // that count. Anything the user changes while the query is in flight belongs
    // to the next session, not this one.
    final config = SessionConfig(
      // Filtered through the rendered subject list rather than read straight
      // out of the set, so the topics arrive in the order they appear on screen
      // — which is also the order the zero-result message names them in.
      // `_subjects` cannot be null here (Start is only enabled once the read has
      // landed), but the fallback keeps that an invariant rather than a `!`.
      topics: List<String>.unmodifiable(
        (_subjects ?? const <String>[]).where(_selectedTopics.contains),
      ),
      level: _level,
      questionCount: _questionCount,
      thinkingSeconds: _thinkingSeconds,
      answerSeconds: _answerSeconds,
      autoReplay: _autoReplay,
    );

    setState(() {
      _starting = true;
      // A new attempt supersedes the last one's explanation before it has an
      // answer of its own.
      _clearStartMessage();
    });

    List<String>? questions;
    Object? failure;
    String? failureMessage;
    StartMessageKind? failureKind;
    try {
      questions = await _questionSource.questionsFor(config);
    } on TooManyTopicsException catch (error) {
      // FIRST, and deliberately above the bank-unreachable arm (D-61): the
      // selection is wider than Firestore's `whereIn` cap, so the guard threw
      // before a query was ever issued. Nothing about the network failed, and
      // the fix is on this screen — uncheck a topic.
      failure = error;
      failureMessage = kTooManyTopicsMessage;
      failureKind = StartMessageKind.tooManyTopics;
    } on QuestionBankUnavailableException catch (error) {
      // The bank could not be READ — including the offline zero-documents-from-
      // cache case, which the adapter has already turned into this throw. That
      // is a failure, never a zero-result: "try another level" is only true
      // advice when the server actually answered.
      failure = error;
      failureMessage = kQuestionLoadErrorMessage;
      failureKind = StartMessageKind.bankUnavailable;
    } catch (error, stack) {
      // Anything else is a source misbehaving, and it lands on the read-failure
      // surface: a query that threw is a query that was not served, whatever
      // threw. It is never the over-limit string, which claims a specific cause.
      failure = error;
      failureMessage = kQuestionLoadErrorMessage;
      failureKind = StartMessageKind.bankUnavailable;
      debugPrintStack(stackTrace: stack);
    }

    if (!mounted) return;

    if (failure != null) {
      // Exception detail goes to the console and NOWHERE else, for the
      // over-limit signal exactly as for the unreachable one.
      debugPrint('Start query failed: $failure');
      setState(() {
        _starting = false;
        _startMessage = failureMessage;
        _startMessageKind = failureKind;
      });
      return;
    }

    // A zero-result combination is real, expected and server-confirmed (D-41) —
    // `Travel` at C1 is empty in the seeded bank by design. It is explained here
    // rather than navigated into: `questionAt` divides by `length`, so an empty
    // bank would crash the loop on its first prompt, and more importantly the
    // user is owed the reason.
    final resolved = questions!;
    if (resolved.isEmpty) {
      setState(() {
        _starting = false;
        // Built from the SNAPSHOT, not from the live controls: the message must
        // name the level and topics the query actually ran with.
        _startMessage = noQuestionsMessage(config.level, config.topics);
        _startMessageKind = StartMessageKind.noQuestions;
      });
      return;
    }

    // Cleared BEFORE the push, so popping back off the session finds a normal
    // footer rather than a button still spinning for a query that finished long
    // ago.
    setState(() => _starting = false);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeScreen(
          config: config,
          questions: resolved,
          databaseHelper: _databaseHelper,
          recordingService: widget.recordingService,
          audioPlayerService: widget.audioPlayerService,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshSubjectsOnReappear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The topics read has landed AND succeeded. Every gate below hangs off this
    // rather than off "the list is non-empty", because a loading card and a
    // failed card both have an empty list and neither is a bank the user can
    // pick from.
    final bool topicsLoaded =
        !_topicsLoading && !_topicsError && _subjects != null;
    final List<String> subjects = _subjects ?? const <String>[];
    final bool canStart = topicsLoaded && _selectedTopics.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'EnglishReflex',
          style: theme.textTheme.headlineSmall,
          // The title now competes with TWO actions instead of one, so it
          // ellipsises rather than overflowing at the largest OS text scale —
          // the same treatment the practice AppBar already carries.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // A fixed two-entry literal, never data-driven: neither action is
        // conditional on the bank, the network or the import state, so this list
        // can never render empty. Import is PREPENDED — `actions:` renders
        // left→right ending at the right edge, so putting it first leaves the
        // History icon exactly where the user's thumb already expects it. Adding
        // an action must not move an existing one.
        actions: [
          IconButton(
            key: const Key('setup-import'),
            icon: const Icon(Icons.upload_file),
            // Icon-only, so the tooltip IS the accessible name — exactly as the
            // History action's is. Never disabled: every failure the import can
            // hit lives inside the sheet, where it has room to be explained, and
            // a disabled icon with no explanation is what this app's conventions
            // forbid. No local colour override — `appBarTheme.actionsIconTheme`
            // already paints AppBar actions coral.
            tooltip: 'Import questions',
            onPressed: () => unawaited(_openImportSheet()),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Exercise History',
            onPressed: () => unawaited(_openHistory()),
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
                      subjects: subjects,
                      loading: _topicsLoading,
                      failed: _topicsError,
                      selected: _selectedTopics,
                      onChanged: _toggleTopic,
                      onRetry: () => unawaited(_loadSubjects()),
                    ),
                    const SizedBox(height: 32), // xl — between Setup sections
                    // The chip row sits directly on the ivory background, NOT
                    // inside a peach card: unselected chips are peach, and
                    // peach on peach would make them vanish.
                    _LevelChips(
                      selected: _level,
                      onSelected: (level) => setState(() {
                        _level = level;
                        _clearStartMessage();
                      }),
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
                      onChanged: (value) => setState(() {
                        _questionCount = value.round();
                        _clearStartMessage();
                      }),
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
                      onChanged: (value) => setState(() {
                        _thinkingSeconds = value.round();
                        _clearStartMessage();
                      }),
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
                      onChanged: (value) => setState(() {
                        _answerSeconds = value.round();
                        _clearStartMessage();
                      }),
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
            // `unawaited` rather than passing `_startSession` directly: the
            // footer's callback is a `VoidCallback`, and making the fire-and-
            // forget explicit is what keeps `unawaited_futures` honest here.
            _StartFooter(
              canStart: canStart,
              // The Phase 2 latent copy bug going live, not a new behaviour.
              // The helper used to render for any `!canStart`, which back then
              // could only mean "no topic checked" because the subject list was
              // a non-empty constant. Sourced from Firestore, `!canStart` also
              // covers loading, an empty bank and could-not-load — and "pick at
              // least one topic" is wrong for all three, because there is
              // nothing to pick. The topics card directly above says what is
              // actually happening, and in the failure case owns the only Retry.
              showBlockedHelper: topicsLoaded &&
                  subjects.isNotEmpty &&
                  _selectedTopics.isEmpty,
              starting: _starting,
              message: _startMessage,
              messageKind: _startMessageKind,
              onStart: () => unawaited(_startSession()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The peach topic card — the one peach surface on Setup, because peach marks
/// question-bank DATA (it is Firestore-backed from Phase 3), never form chrome.
///
/// The card is the same peach `Material` at radius 24 with 24px padding in
/// every one of its four states; only its body changes. It is deliberately NOT
/// height-locked: the four states have genuinely different natural heights, and
/// reserving the tallest would leave dead peach space in the common populated
/// case. Everything below it is inside the Setup scroll view and the Start
/// footer is pinned outside, so nothing the user needs can be pushed off-screen
/// when the height changes.
class _TopicsCard extends StatelessWidget {
  const _TopicsCard({
    required this.subjects,
    required this.loading,
    required this.failed,
    required this.selected,
    required this.onChanged,
    required this.onRetry,
  });

  final List<String> subjects;
  final bool loading;
  final bool failed;
  final Set<String> selected;
  final void Function(String subject, bool? checked) onChanged;
  final VoidCallback onRetry;

  /// Exactly one of loading, could-not-load, empty or the checkbox rows.
  ///
  /// **The branch ORDER is load-bearing**, and it is the same order
  /// `history_screen.dart` uses for the same reason: loading first, then the
  /// failure, and only then read the data. Falling through in any other order
  /// coerces a read that never landed into an empty list and renders it as "the
  /// bank is empty" — the precise failure Phase 1 Plan 6 was written to prevent
  /// and that D-37 restates for the question bank. A user with a full bank and
  /// a flat connection must never be told their topics are gone.
  Widget _body(ThemeData theme) {
    if (loading) return const _TopicsLoading();
    if (failed) return _TopicsError(onRetry: onRetry);
    if (subjects.isEmpty) return const _NoTopics();
    return Column(
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
    );
  }

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
        child: _body(theme),
      ),
    );
  }
}

/// Shown while a FOREGROUND subjects read is in flight — the first read of a
/// Setup lifetime and every read a "Try again" tap starts (D-37).
///
/// The caption is not decoration. A bare spinner in a card is indistinguishable
/// from a stalled failure for a sighted user and is silent to a screen reader;
/// the caption resolves both, and its ellipsis marks the state as transient per
/// the established voice rule.
///
/// The spinner is coral — the one accent addition this phase makes — because
/// accent marks something tappable or actively happening, and a spinner is the
/// purest case of "actively happening". It can never collide with the Start
/// button's own spinner: Start is disabled for the whole of this state.
class _TopicsLoading extends StatelessWidget {
  const _TopicsLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('setup-topics-loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: theme.colorScheme.primary),
        const SizedBox(height: 16), // md
        Text(
          'Loading your topics…',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

/// Shown when the subjects read FAILED — a different widget, a different key
/// and different copy from [_NoTopics], which is the entire point of D-37.
///
/// **Constructed with `_HistoryError`'s geometry** (48px icon → 16px → centred
/// message → 16px → a `TextButton` at `minimumSize: Size(64, 48)`), so the app
/// has one recognisable failure shape wherever a read can fail.
///
/// Exactly one deviation from it: the message and the button label use
/// `bodyLarge`/`labelLarge` in the default brown WITHOUT `_HistoryError`'s
/// error-colour `copyWith`. Warm red measures 3.03:1 on peach — it clears
/// WCAG's 3:1 non-text threshold, which is why the icon stays red and carries
/// the "something went wrong" signal, but it fails the 4.5:1 threshold for
/// 16px body text. Brown on peach measures 10.4:1. Keeping the geometry and
/// changing only the colour means the shape is recognisable AND legible.
///
/// Never renders the exception: internal detail stays out of the UI, matching
/// the contract `kRecordingErrorMessage` and `kHistoryErrorMessage` already set.
class _TopicsError extends StatelessWidget {
  const _TopicsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('setup-topics-error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 48, // 2xl
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16), // md
        Text(
          kTopicsErrorMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16), // md
        TextButton(
          key: const Key('setup-topics-error-retry'),
          onPressed: onRetry,
          style: TextButton.styleFrom(
            // Touch-target floor, not part of the 4px content scale.
            minimumSize: const Size(64, 48),
            foregroundColor: theme.colorScheme.onSurface,
          ),
          child: Text('Try again', style: theme.textTheme.labelLarge),
        ),
      ],
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

/// Reachable from Phase 3 onward: the subject list is now read from Firestore,
/// so a genuinely empty bank renders this. The copy was locked in Phase 2 so the
/// swap had a state to land on rather than inventing one under deadline.
///
/// **It means exactly what it says, and nothing else.** [_TopicsLoading] owns
/// the frames before an answer arrives and [_TopicsError] owns a read that was
/// not served — including the offline case where Firestore resolves a *
/// successful*, zero-document snapshot out of an empty cache, which
/// `FirestoreQuestionSource` turns into a throw before it can ever reach this
/// widget. So this state is only ever the server confirming the bank is empty,
/// which is what makes "Import some questions" true advice rather than a lie
/// about a network problem.
///
/// The widget itself is deliberately unchanged from Phase 2 — its key and both
/// its strings are covered by a held-out widget test, and making a branch
/// reachable is not a reason to rewrite the branch.
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
  const _StartFooter({
    required this.canStart,
    required this.showBlockedHelper,
    required this.starting,
    required this.message,
    required this.messageKind,
    required this.onStart,
  });

  final bool canStart;

  /// Narrower than `!canStart` on purpose — see the call site. "Pick at least
  /// one topic to start." is only true when there is something to pick.
  final bool showBlockedHelper;

  /// The Start query is in flight (D-33).
  final bool starting;

  /// The last Start attempt's explanation, or null when there is none.
  final String? message;

  /// Which of the three things [message] is saying, and therefore which
  /// treatment and which key it gets. Null exactly when [message] is null.
  final StartMessageKind? messageKind;

  final VoidCallback onStart;

  /// At most ONE helper line. The blocked helper wins outright, and the other
  /// three are chosen by an EXHAUSTIVE `switch` over [StartMessageKind] rather
  /// than by an else-if chain of conditions kept disjoint by hand — so the four
  /// keys are mutually exclusive by construction, and a fifth helper added later
  /// cannot compile until it has been given its own branch.
  ///
  /// Nothing at all while the topics are loading, empty or unreachable: the card
  /// directly above already says what is happening and, in the failure case,
  /// owns the only Retry affordance. A second simultaneous message would make
  /// Setup the one screen in the app with two competing error surfaces.
  ///
  /// The red-icon-versus-brown-words split is the footer's honesty signal: an
  /// icon means something went wrong and retrying is the fix, no icon means
  /// change a setting. The words stay brown in all of them because warm red
  /// measures 3.03:1 on the ivory footer — icon-safe, text-unsafe.
  Widget? _helper(ThemeData theme) {
    if (showBlockedHelper) {
      return Text(
        'Pick at least one topic to start.',
        key: const Key('setup-start-blocked'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge,
      );
    }
    final String? text = message;
    final StartMessageKind? kind = messageKind;
    if (text == null || kind == null) return null;

    return switch (kind) {
      StartMessageKind.noQuestions => Text(
          text,
          key: const Key('setup-start-no-questions'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      // The one helper in this slot that carries an icon, because it is the one
      // that means *something went wrong*.
      StartMessageKind.bankUnavailable => Row(
          key: const Key('setup-start-error'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 24, // lg
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8), // sm
            // Expanded so the message wraps inside the footer rather than
            // overflowing it — the footer is the one region that does not
            // scroll.
            Expanded(
              child: Text(text, style: theme.textTheme.bodyLarge),
            ),
          ],
        ),
      // **NO icon, deliberately, and that absence is load-bearing** (D-61).
      // This is not a fault; it is a limit the user can satisfy by unchecking a
      // topic that is visible on the same screen. The red error icon would file
      // it under "something went wrong, retry" — the exact misreading this
      // string exists to end. Nothing else about it differs from the
      // zero-result helper: brown Body, centred, full footer width to wrap into
      // precisely because no icon is stealing 32px of it.
      StartMessageKind.tooManyTopics => Text(
          text,
          key: const Key('setup-start-too-many-topics'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helper = _helper(theme);

    // Two separate `styleFrom` calls rather than one with ternary arguments,
    // because the busy state is a different button treatment, not a tweak.
    // `FilledButton` paints `disabledBackgroundColor` whenever `onPressed` is
    // null, so without the override a busy button would fall back to the peach
    // blocked treatment — an action IN FLIGHT rendered identically to an action
    // BLOCKED, which is the opposite message.
    final ButtonStyle style = starting
        ? FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            disabledBackgroundColor: theme.colorScheme.primary, // stays coral
            disabledForegroundColor: theme.colorScheme.onPrimary,
          )
        : FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            disabledBackgroundColor: theme.colorScheme.surface, // peach
            disabledForegroundColor: theme.colorScheme.onSurface,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 24, // lg
        vertical: 16, // md
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The 8px gap belongs to the helper, not to the footer: the resting
          // ready state is one button and nothing else.
          if (helper != null) ...[
            helper,
            const SizedBox(height: 8), // sm
          ],
          SizedBox(
            width: double.infinity,
            // Touch-target floor from the UI-SPEC exceptions, and identical in
            // all three button states: the 24px spinner sits inside it with room
            // to spare, so there is no layout shift on tap or on completion.
            height: 64,
            child: FilledButton(
              key: const Key('setup-start'),
              // Null — not a swallowed tap — so the gate is enforced by the
              // widget itself and SETUP-07 cannot be defeated by a stray
              // handler (D-19). The same holds for the busy frame, which is what
              // makes a double-Start structurally impossible rather than merely
              // ignored.
              onPressed: (canStart && !starting) ? onStart : null,
              style: style,
              child: starting
                  // The busy state carries no text at all, so it carries a
                  // semantic label instead — otherwise the one moment the screen
                  // is doing something would be silent to a screen reader. The
                  // spinner is brown `onPrimary`, not coral: coral inside a
                  // coral-filled button would be invisible.
                  ? Semantics(
                      label: 'Starting session',
                      child: SizedBox(
                        width: 24, // lg
                        height: 24,
                        child: CircularProgressIndicator(
                          key: const Key('setup-start-busy'),
                          strokeWidth: 3,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    )
                  : Text('START SESSION', style: theme.textTheme.labelLarge),
            ),
          ),
        ],
      ),
    );
  }
}
