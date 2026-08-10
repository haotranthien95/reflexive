import 'dart:async';

import 'package:flutter/material.dart';

import '../services/json_file_picker.dart';
import '../services/question_bank_writer.dart';
import '../services/question_importer.dart';

/// The idle state's one instruction line (D-50).
///
/// The sheet opens BEFORE the picker precisely so this sentence and the shape
/// example below it have somewhere to live: a user who picks the wrong file
/// learns what was expected without leaving the app, and a cancelled pick cannot
/// make the AppBar icon look broken.
const String kImportIdleMessage =
    'Add questions to your bank from a JSON file shaped like this:';

/// The expected file shape, pre-broken into three short lines.
///
/// **Deliberately NOT in a monospace family.** A code font here would be a third
/// font family in a two-family contract, for a three-line hint. It is a shape to
/// recognise, not code to copy, so it renders at Body 16 brown inside a peach
/// card and wraps rather than clipping. Plain `Text` — never `SelectableText`,
/// never an editable field.
///
/// One constant, two render sites: plan 02's file-problem state shows this same
/// block rather than a second copy of the string.
const String kImportShapeExample = '{"data": [\n'
    '  {"content": "…", "subject": "…", "level": "A2"}\n'
    ']}';

/// The busy caption while the file is being read and validated.
///
/// A sibling of [kImportCheckingBankMessage] and not the same string: the two
/// name two genuinely different waits, and a single "Working…" would make a
/// stalled network read indistinguishable from a slow parse. Every busy state in
/// this app is captioned — a bare spinner is indistinguishable from a stall for
/// a sighted user and silent to a screen reader.
const String kImportCheckingFileMessage = 'Checking your file…';

/// The busy caption while the bank is being read for the dedupe pass (D-54).
///
/// Named as a comparison rather than a download, because that is what the user
/// is waiting for: the app is finding out which of their questions are already
/// there. See [kImportCheckingFileMessage] for why the two captions are
/// separate strings.
const String kImportCheckingBankMessage = 'Comparing with your bank…';

/// The line under the write-progress bar.
///
/// It exists to explain a blocked gesture BEFORE it is attempted rather than
/// after: the write is the one state the sheet does not let the user leave,
/// because a user who closes mid-write never learns which rows landed — the
/// unreported partial outcome IMPORT-04 exists to prevent.
const String kImportKeepOpenMessage = 'Keep this open until it finishes.';

/// "Saving {n} questions to your bank…", with a singular branch.
///
/// A pure function, so both branches are unit-testable on the host with no
/// widget — the form [noQuestionsMessage] set in Phase 3. Singular/plural is a
/// branch, never an interpolated `s`, because the app's voice is written English
/// and "1 questions" reads like a bug.
String importSavingMessage(int count) {
  if (count == 1) return 'Saving 1 question to your bank…';
  return 'Saving $count questions to your bank…';
}

/// The result headline: "{n} questions added", with singular AND zero branches.
///
/// **The zero branch is not decoration.** "0 questions added" reads like a bug
/// where "No questions added" reads like an outcome, and a zero result is
/// entirely normal here — a file whose rows were all already in the bank adds
/// nothing and is a complete success (D-54).
///
/// Pure, so all three branches are testable with no widget.
String importAddedLine(int count) {
  if (count == 0) return 'No questions added';
  if (count == 1) return '1 question added';
  return '$count questions added';
}

/// The result's SECOND line: how many rows the bank already had (D-54).
///
/// **Past tense, neutral, and deliberately un-iconed.** A user re-importing a
/// file should feel reassured rather than warned — the app is telling them their
/// bank is already correct. There is no zero branch because the line is
/// zero-suppressed at the render site: "0 were already in your bank" is a fact
/// nobody needs and a line nobody should have to read past.
String importDuplicatesLine(int count) {
  if (count == 1) return '1 was already in your bank';
  return '$count were already in your bank';
}

/// The result's THIRD line: how many rows the file's own contents disqualified.
///
/// Sibling of [importDuplicatesLine] and NOT the same string, because the two
/// count two different facts: a duplicate needs nothing from the user, and a
/// skipped row needs an edit. Also zero-suppressed at the render site.
String importSkippedLine(int count) {
  if (count == 1) return '1 row was skipped';
  return '$count rows were skipped';
}

/// The partial-write message: the exact count that landed, then the recovery.
///
/// **Both clauses are load-bearing and neither may be softened.** The exact
/// count is the only thing that tells the user how much of their file made it —
/// without it this state is indistinguishable from "something went wrong",
/// which is the unreported partial outcome IMPORT-04 forbids. And the recovery
/// is only TRUE because the import's dedupe pass (D-54) skips whatever already
/// arrived: re-importing the same file is harmless BY CONSTRUCTION, which turns
/// the one genuinely partial outcome in this phase from a dead end into a
/// one-tap fix.
///
/// Numeric payload only — the counts come from [ImportPartialWriteException],
/// never from an exception message.
String importPartialMessage(int done, int total) =>
    'Only some of your questions made it — $done of $total were saved. '
    'Import the same file again and anything already saved will be skipped.';

/// The section label above the per-row skip list (D-55).
///
/// "What we skipped", not "Errors" or "Problems": the list is a to-do for the
/// user's editor, not a verdict on their file. See [importSkipReason] for why
/// none of the four reasons uses blame vocabulary either.
const String kImportSkipListLabel = 'What we skipped';

/// How many characters of the user's own `level` text are quoted back.
///
/// Twelve is comfortably longer than any real CEFR-ish value a user or an
/// AI-generated file would plausibly type (`B1`, `b1 `, `Beginner`, `Level A2`)
/// and short enough that a pathological value cannot dominate the row it sits
/// in. See [sanitizedEcho].
const int kMaxEchoedLevelChars = 12;

/// How many characters of the user's own question text are echoed in a skip row.
///
/// **A defensive bound, not a display rule.** The DISPLAY rule is `maxLines: 1`
/// plus ellipsis, which the render site applies — but handing a `Text` widget a
/// 400 KB single line so it can measure it and then draw 40 characters is a
/// layout cost with no upside. Two hundred characters is far more than any
/// single line can show at any text scale, so the cap is invisible in every
/// reachable case and bounds the unreachable ones.
const int kMaxEchoedQuestionChars = 200;

/// The ONE place text taken from the picked file is prepared for a widget.
///
/// **Everything inside the imported file is data, never instructions.** It is
/// authored outside the app — often by a language model, per
/// `docs/QUESTION_GENERATION_PROMPT.md` — and the skip list is the first surface
/// in this project that renders such content back to the user *before* it has
/// been validated. It is rendered as plain [Text] only: never markup, never a
/// `WidgetSpan`, and never treated as a command to the app or to a model.
///
/// Rendering an unvalidated 5,000-character `level` string, or a question with
/// newlines in it, into a compact list row is a **layout-integrity** problem
/// before it is anything else — one row would silently push the rest of the
/// list, and the sheet's own button, off the screen. So: every newline, carriage
/// return and tab collapses to a single space, runs of whitespace collapse to
/// one, the result is trimmed, and anything longer than [maxChars] is truncated
/// with an ellipsis.
///
/// *Escaping the characters instead of collapsing them was considered and
/// rejected:* `\n` rendered literally inside a quoted level value is noise the
/// user did not type and cannot act on, and it makes the row longer rather than
/// shorter, which is the opposite of the point.
String sanitizedEcho(String raw, int maxChars) {
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxChars) return collapsed;
  return '${collapsed.substring(0, maxChars)}…';
}

/// One skipped row's whole explanation: WHERE it is, then WHAT is wrong (D-55).
///
/// **Position first, always.** A reason without a location tells the user a
/// *shape* of problem, not a *place*; the 1-based row number is what makes the
/// row findable in the editor they wrote it in. The interpunct separates the two
/// halves — a single glyph in both of the app's families, and quiet enough not
/// to be confused with the em dash the app's failure strings use for
/// "— what to do".
///
/// **A total map over [ImportSkipReason]**, with no fallback branch, so adding a
/// reason to that enum is a compile error here rather than a row that renders
/// blank.
///
/// **None of the four branches blames the person who wrote the file.** No
/// "invalid", no "error", no "failed" — each one describes the ROW. "no question
/// text" is a fact about a row; "invalid question" is a judgement about an
/// author. The user of this app is also the author of these files, and telling
/// them their own file is invalid is the one thing this copy must never do.
///
/// The accepted set is written as the range **A1–C2** rather than a six-item
/// list because that is exactly what the Setup level chips already show them.
///
/// The quoted level is the user's OWN raw text, passed through [sanitizedEcho]
/// with [kMaxEchoedLevelChars] first — quoting back something they did not type
/// is a worse hint than quoting what they did, and an uncapped echo is the
/// layout hazard that function exists for. A row whose `level` was absent or was
/// not text at all has nothing quotable and renders empty quotes: accurate, and
/// still one of the four strings rather than a fifth one for an edge.
String importSkipReason(ImportSkip skip) {
  final row = 'Row ${skip.rowNumber}';
  switch (skip.reason) {
    case ImportSkipReason.blankContent:
      return '$row · no question text';
    case ImportSkipReason.blankSubject:
      return '$row · no topic';
    case ImportSkipReason.badLevel:
      final value = sanitizedEcho(skip.offendingLevel ?? '', kMaxEchoedLevelChars);
      return '$row · level "$value" isn\'t one of A1–C2';
    case ImportSkipReason.notAnObject:
      return '$row · not shaped like a question';
  }
}

/// Which of the sheet's states is on screen.
///
/// **Only the states this plan builds.** The four terminal failure surfaces
/// (file problem, file empty, bank unreachable, partial write) and the per-row
/// skip list are plan 02's expansion; until then every failure is logged and
/// lands back on [_ImportPhase.idle], which is honest about having done nothing
/// even though it does not yet explain why.
enum _ImportPhase { idle, checking, writing, result }

/// The importer, as a modal bottom sheet (D-48).
///
/// **A sheet and not a route, by construction.** UI-03 says the app has exactly
/// three core screens; a full-screen pushed route would have made the route
/// count five in the very phase whose requirement is "exactly 3 screens with no
/// extraneous navigation". `showModalBottomSheet` pushes a modal, not a page, so
/// the screen count is unchanged as a fact rather than as an argument.
///
/// Both platform dependencies arrive as nullable constructor parameters and are
/// resolved lazily, so a test that injects fakes never constructs a Firestore
/// handle or a file-picker channel. This file imports NEITHER vendor package: it
/// talks only to the two seam contracts and to the importer's plain-Dart types.
class ImportSheet extends StatefulWidget {
  const ImportSheet({super.key, this.picker, this.writer});

  /// The file-picker seam. Null in production, where
  /// [FilePickerJsonFilePicker] is constructed lazily.
  final JsonFilePicker? picker;

  /// The bank-write seam. Null in production, where
  /// [FirestoreQuestionBankWriter] is constructed lazily.
  final QuestionBankWriter? writer;

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  late final JsonFilePicker _picker =
      widget.picker ?? const FilePickerJsonFilePicker();
  late final QuestionBankWriter _writer =
      widget.writer ?? FirestoreQuestionBankWriter();

  _ImportPhase _phase = _ImportPhase.idle;

  /// Swaps the checking caption from the file to the bank. One state, one key,
  /// one caption change — the UI-SPEC's S2 is a single surface.
  bool _comparingWithBank = false;

  /// True from the moment "Choose a JSON file" is tapped until the picker
  /// answers. The sheet stays on its idle body throughout (a cancelled pick must
  /// find the format hint exactly where it left it, D-50 step 3a), but the
  /// button's handler goes null, so a second tap is structurally impossible
  /// rather than merely ignored (D-19).
  bool _picking = false;

  int _rowsToWrite = 0;
  int _rowsCommitted = 0;
  int _added = 0;

  /// The other two facts the result owes the user beside "what landed": how many
  /// rows the bank already had, and which rows need an edit. Both come from the
  /// same already-complete [ImportPlan], which is why the result card can never
  /// render half-populated — it mounts on the transition INTO the result state
  /// with every count already known.
  int _duplicates = 0;
  List<ImportSkip> _skips = const <ImportSkip>[];

  /// The whole import, from the picker to the count that landed.
  ///
  /// Every judgement is made before the first document goes out (D-52), and the
  /// bank read that gates it is server-only (D-60), so an offline import ends
  /// here with nothing written rather than spinning on writes queued in the
  /// local cache.
  Future<void> _chooseFileAndImport() async {
    setState(() => _picking = true);

    final String? jsonText;
    try {
      jsonText = await _picker.pickJsonText();
    } catch (error, stack) {
      _landOnIdle('File pick failed', error, stack);
      return;
    }

    // `setState` after an `await` needs this guard: the pick outlives the sheet
    // whenever the user dismisses it before the picker answers, and calling
    // `setState` on a disposed `State` throws.
    if (!mounted) return;

    // A cancelled pick is not a failure and gets no copy at all: the idle body
    // with the format hint still on it is the complete and correct treatment.
    if (jsonText == null) {
      setState(() => _picking = false);
      return;
    }

    setState(() {
      _picking = false;
      _phase = _ImportPhase.checking;
      _comparingWithBank = false;
    });

    try {
      final parsed = parseImportFile(jsonText);

      setState(() => _comparingWithBank = true);
      final existing = await _writer.existingKeys();
      if (!mounted) return;

      final plan = dedupeAgainstBank(parsed, existing);
      setState(() {
        _phase = _ImportPhase.writing;
        _rowsToWrite = plan.rowsToWrite.length;
        _rowsCommitted = 0;
      });

      final added = await _writer.write(
        plan.rowsToWrite,
        onProgress: (committed, total) {
          if (!mounted) return;
          setState(() => _rowsCommitted = committed);
        },
      );
      if (!mounted) return;

      setState(() {
        _phase = _ImportPhase.result;
        _added = added;
        _duplicates = plan.duplicateCount;
        _skips = plan.skips;
      });
    } catch (error, stack) {
      _landOnIdle('Import failed', error, stack);
    }
  }

  /// The single failure landing for this plan.
  ///
  /// Plan 02 replaces it with the four terminal states that each name their own
  /// cause and their own next action. Until then the rule that matters is still
  /// honoured: exception detail goes to the console and NOWHERE else — no
  /// exception text, no Firestore error code, no collection name, no document ID
  /// and no file path may reach the screen.
  void _landOnIdle(String what, Object error, StackTrace stack) {
    debugPrint('$what: $error');
    debugPrintStack(stackTrace: stack);
    if (!mounted) return;
    setState(() {
      _picking = false;
      _phase = _ImportPhase.idle;
      _comparingWithBank = false;
    });
  }

  /// Exactly one state body, chosen by an else-if chain so the keys are mutually
  /// exclusive BY CONSTRUCTION rather than by conditions kept disjoint by hand —
  /// the same reasoning `_StartFooter._helper` carries on Setup.
  Widget _body() {
    if (_phase == _ImportPhase.idle) {
      return _ImportIdle(
        onChoose: _picking ? null : () => unawaited(_chooseFileAndImport()),
      );
    }
    if (_phase == _ImportPhase.checking) {
      return _ImportChecking(
        message: _comparingWithBank
            ? kImportCheckingBankMessage
            : kImportCheckingFileMessage,
      );
    }
    if (_phase == _ImportPhase.writing) {
      return _ImportWriting(committed: _rowsCommitted, total: _rowsToWrite);
    }
    return _ImportResult(
      added: _added,
      duplicates: _duplicates,
      skips: _skips,
      onDone: () => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope<void>(
      // The ONE non-dismissible state (UI-SPEC "Dismissal is blocked in exactly
      // one state"): a user who closes mid-write never learns which rows landed.
      // Every other state has written nothing or has already been read, so
      // leaving costs nothing. The same mechanism the practice screen uses to
      // route the back gesture into the Stop dialog (D-29).
      canPop: _phase != _ImportPhase.writing,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            24, // lg
            24, // lg
            24, // lg
            16, // md
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Import questions', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24), // lg
              _body(),
            ],
          ),
        ),
      ),
    );
  }
}

/// S1 — the resting state the sheet opens on, before the picker (D-50).
class _ImportIdle extends StatelessWidget {
  const _ImportIdle({required this.onChoose});

  /// Null while the picker is open, so the gate is enforced by the widget
  /// itself rather than by a handler that swallows the second tap (D-19).
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('import-idle'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(kImportIdleMessage, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16), // md
        // Peach marks CONTENT; the sheet's own ivory surface is chrome, which is
        // why the example sits in a card and the sheet does not.
        Material(
          color: theme.colorScheme.surface, // peach
          borderRadius: BorderRadius.circular(24), // lg
          child: Padding(
            padding: const EdgeInsets.all(24), // lg
            child: Text(kImportShapeExample, style: theme.textTheme.bodyLarge),
          ),
        ),
        const SizedBox(height: 24), // lg
        SizedBox(
          // The established primary-button floor, identical in every state so
          // there is no layout shift between them.
          height: 64,
          child: FilledButton(
            key: const Key('import-choose-file'),
            onPressed: onChoose,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              disabledBackgroundColor: theme.colorScheme.primary,
              disabledForegroundColor: theme.colorScheme.onPrimary,
            ),
            child: Text('Choose a JSON file', style: theme.textTheme.labelLarge),
          ),
        ),
      ],
    );
  }
}

/// S2 — reading and validating the file, then reading the bank.
///
/// One widget and one key for both waits, with the caption as the only
/// difference: they are the same surface doing the same thing to the user.
/// No button slot at all — there is nothing to cancel that dismissing the sheet
/// does not already cancel, and nothing has been written.
class _ImportChecking extends StatelessWidget {
  const _ImportChecking({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: message,
      child: Column(
        key: const Key('import-checking'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24, // lg
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary, // coral — actively happening
            ),
          ),
          const SizedBox(height: 16), // md
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// S3 — the write, with an honest determinate bar.
///
/// `value` is committed rows over rows to write and advances ONLY when a batch
/// has actually committed, never optimistically per row. For a typical user file
/// that is one step from 0 to 1; for the 600-row seed it is two. That coarseness
/// is deliberately the truthful granularity — this app does not report a write
/// it has not seen acknowledged (D-60, and the D-37 precedent).
///
/// The caption is not a `liveRegion` and does not change during the write, so a
/// screen-reader user gets one announcement rather than one per batch.
class _ImportWriting extends StatelessWidget {
  const _ImportWriting({required this.committed, required this.total});

  final int committed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('import-writing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          importSavingMessage(total),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16), // md
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            key: const Key('import-writing-progress'),
            // A zero-row write never reaches this widget, but the guard keeps
            // the division an invariant rather than a `!`.
            value: total == 0 ? 0 : committed / total,
            minHeight: 8, // sm
            color: theme.colorScheme.primary, // coral
            backgroundColor: theme.colorScheme.surface, // peach track
          ),
        ),
        const SizedBox(height: 8), // sm
        Text(
          kImportKeepOpenMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

/// S4 — the outcome, held on screen until the user dismisses it (D-51).
///
/// One exit, one refresh call site: the Setup-side re-read is wired to the
/// sheet's own `await`, not to this button, so drag-down, barrier tap and system
/// back are covered by the same line.
///
/// **The only state that grows with data**, and the only one that carries no
/// icon and no error red: a duplicate is a neutral fact and a skipped row is
/// "your file needs an edit", not "something went wrong". A partial write is a
/// different fact and gets its own state rather than this success-shaped card —
/// dressing a partial write in the success surface is the specific misreport
/// that split exists to prevent.
class _ImportResult extends StatelessWidget {
  const _ImportResult({
    required this.added,
    required this.duplicates,
    required this.skips,
    required this.onDone,
  });

  final int added;
  final int duplicates;
  final List<ImportSkip> skips;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('import-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: theme.colorScheme.surface, // peach — content
          borderRadius: BorderRadius.circular(24), // lg
          child: Padding(
            padding: const EdgeInsets.all(24), // lg
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The added line ALWAYS renders; the other two are suppressed at
                // zero. The order is fixed rather than "whatever is non-zero
                // first", so the same fact is always in the same place across
                // imports and the card is read by position, not by scanning.
                Text(
                  importAddedLine(added),
                  style: theme.textTheme.headlineSmall,
                ),
                if (duplicates > 0) ...[
                  const SizedBox(height: 8), // sm
                  Text(
                    importDuplicatesLine(duplicates),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                if (skips.isNotEmpty) ...[
                  const SizedBox(height: 8), // sm
                  Text(
                    importSkippedLine(skips.length),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ],
            ),
          ),
        ),
        // The skip list sits directly on the sheet's IVORY surface with no card
        // of its own — peach never sits on peach. Omitted entirely when nothing
        // was skipped: no label, no empty container, no "0 skipped" line.
        if (skips.isNotEmpty) ...[
          const SizedBox(height: 24), // lg
          Text(kImportSkipListLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 16), // md
          // A plain Column inside the sheet's ONE scroll view, never a nested
          // scrollable: a nested scrollable inside a draggable sheet is the
          // classic gesture conflict. No cap, no show-more and no grouping —
          // rows stay in file order so the list reads in the same order as the
          // user's editor.
          for (var i = 0; i < skips.length; i++) ...[
            if (i > 0) const SizedBox(height: 16), // md
            _SkipRow(skip: skips[i]),
          ],
        ],
        const SizedBox(height: 24), // lg
        SizedBox(
          height: 64,
          child: FilledButton(
            key: const Key('import-done'),
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            child: Text('Done', style: theme.textTheme.labelLarge),
          ),
        ),
      ],
    );
  }
}

/// One row of the skip list: where the problem is, then what it is.
///
/// **Two lines, and the second one is optional.** The reason line is never
/// truncated, because the reason is the actionable half. The question sub-line
/// below it is the user's own text and is the one deliberate truncation in this
/// app — one ellipsised line — because its job is recognition, not reading. A
/// row with no usable content omits the sub-line entirely rather than rendering
/// an empty one.
///
/// **Deliberately NOT floored at 64px.** That floor exists for *tappable* rows
/// (history rows, topic checkboxes, the replay toggle); these are read-only
/// static content with no gesture attached, and pinning them to 64px would make
/// a 40-row list three screens tall for no accessibility gain.
class _SkipRow extends StatelessWidget {
  const _SkipRow({required this.skip});

  final ImportSkip skip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = skip.questionText;
    final echo = raw == null ? null : sanitizedEcho(raw, kMaxEchoedQuestionChars);

    return Column(
      key: Key('import-skip-row-${skip.rowNumber}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(importSkipReason(skip), style: theme.textTheme.bodyLarge),
        if (echo != null && echo.isNotEmpty) ...[
          const SizedBox(height: 8), // sm
          Text(
            echo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}
