import 'dart:async';

import 'package:flutter/material.dart';

// `QuestionBankUnavailableException` only — the READ-side signal the write seam
// reuses rather than declaring a second "could not reach the bank" type. No
// Firestore type crosses into this file; the import is the same one
// `setup_screen.dart` already makes for the same reason.
import '../services/firestore_question_source.dart';
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

/// The message for a file that was CHOSEN but could not be opened, read or
/// decoded.
///
/// **A sibling of [kImportBadShapeMessage], and deliberately not the same
/// string.** They stand for two different facts and only one of them has any
/// business showing the expected shape: telling the user "it needs to look like
/// this" about a file the app never managed to READ would be a false
/// explanation — the app would be blaming the content of something it never
/// saw. So this one names the only action that can help ("try picking it
/// again") and shows no example at all.
///
/// Same containment rule as every other failure string in this project: no
/// exception text, no error code, no file path, no collection name, no document
/// ID and no project ID reaches the screen. Detail goes to `debugPrint` only.
const String kImportUnreadableFileMessage =
    "Couldn't open that file — try picking it again.";

/// The message for a file that opened fine but is not a question file (D-62).
///
/// **The counterpart of [kImportUnreadableFileMessage].** The app DID read this
/// one, so it can say what was expected — and it does, by rendering the same
/// [kImportShapeExample] block the idle state already shows. The trailing colon
/// is load-bearing: the sentence is incomplete without the example beneath it,
/// which is what stops this string from ever being reused on a surface that has
/// no example to show.
const String kImportBadShapeMessage =
    "That file isn't shaped like a question file — it needs to look like this:";

/// The heading for a file that parsed correctly and contains no questions.
///
/// **This is the app's EMPTY-state treatment, not its failure treatment** —
/// heading plus body, no icon, no red. A file that is empty is not a file that
/// is wrong, and this project keeps the two apart everywhere else too: it is the
/// same empty-versus-unreachable split D-37 established for the bank, applied
/// one level down at the file.
///
/// Its body, [kImportEmptyFileBody], is a separate constant rather than a second
/// sentence in this one, so the two can take the two different type roles the
/// empty-state shape calls for.
const String kImportEmptyFileMessage = 'That file has no questions in it.';

/// The body line beneath [kImportEmptyFileMessage].
///
/// Names exactly what would make the next attempt work, rather than restating
/// the problem. Every empty state in this app answers "so what do I do?" in its
/// second line.
const String kImportEmptyFileBody =
    'Pick a file whose data list has at least one question in it.';

/// The message for a bank that could not be reached at all (D-60).
///
/// **"nothing was imported" is load-bearing and may not be softened.** The
/// server-only dedupe read gates the whole import, so when it fails not one
/// document has been written — and a write that fails before its first chunk
/// commits is the same fact. Without that clause the user cannot tell this state
/// apart from a partial write and has no way to know whether re-importing is
/// safe, which is precisely the ambiguity IMPORT-04 exists to forbid.
///
/// A sibling of `kTopicsErrorMessage` and `kQuestionLoadErrorMessage` and not the
/// same string as either: all three share a first clause because there is one
/// failure and one voice, and all three diverge afterwards because the retry
/// affordance differs. This one has a "Try again" button directly beneath it
/// that resumes from the bank read.
const String kImportUnreachableMessage =
    "Couldn't reach your question bank — nothing was imported. Check your "
    'connection and try again.';

/// Which of the sheet's states is on screen.
///
/// **Eight values, and the sheet renders exactly one of them.** The dispatch
/// chain in `_ImportSheetState._body` is an else-if over this enum, so the eight
/// state keys are mutually exclusive BY CONSTRUCTION rather than by conditions
/// kept disjoint by hand — the same totality discipline `kPhaseControlKeys`
/// enforces on the practice screen. A populated result can therefore never
/// render a busy affordance or an error icon beside its summary.
///
/// **The four terminal failures are four values, not one with a reason field.**
/// They differ in what they show (an icon or not, an example or not), in what
/// they offer (pick again, retry, or both) and in what they mean, so collapsing
/// any two of them into a shared surface would be a regression rather than a
/// simplification.
enum _ImportPhase {
  idle,
  checking,
  writing,
  result,

  /// The file could not be opened, or opened and was not a question file. One
  /// state with two sub-keys, because the two share every pixel except their
  /// message and whether the shape example follows.
  fileProblem,

  /// The file parsed and its `data` list was empty.
  emptyFile,

  /// The bank read failed, or a write failed before any chunk committed.
  /// Nothing was written in either case.
  unreachable,

  /// A chunk failed AFTER an earlier one committed — the one genuinely partial
  /// outcome this phase can produce.
  partial,
}

/// The scroll physics the sheet body wears WHILE A WRITE IS IN FLIGHT, and the
/// only thing standing between a downward drag and a lost outcome report.
///
/// **Why physics and not a `PopScope`.** Drag-to-dismiss on the pinned Flutter
/// version pops the route directly and never consults `PopScope` (see the
/// comment on `canPop` in `_ImportSheetState.build`). The sanctioned fallback in
/// the design contract is `enableDrag: false` on the sheet — but that is a
/// property of the `showModalBottomSheet` CALL, which lives in
/// `setup_screen.dart` and is fixed for the sheet's whole lifetime
/// (`ModalBottomSheetRoute.enableDrag` is `final`), so the sheet cannot reach it
/// and could not toggle it mid-write even if it could.
///
/// What the sheet CAN do is win the gesture arena. A `Scrollable` whose physics
/// return true from `shouldAcceptUserOffset` registers a vertical-drag
/// recognizer, and the innermost recognizer wins — so with these physics a drag
/// on the sheet body scrolls the body (or clamps at its edge) instead of
/// dismissing the sheet. The default physics decline the drag when the content
/// fits, which is exactly when the sheet's own recognizer would otherwise take
/// it and close.
///
/// **The residual gap, stated rather than papered over:** the 48px drag-handle
/// strip is rendered by `BottomSheet` OUTSIDE this builder's subtree, so a drag
/// that starts on the handle itself still dismisses mid-write. Closing that
/// needs `enableDrag: false` at the `showModalBottomSheet` call site. It is
/// recorded as a follow-up rather than fixed here because this plan does not own
/// that file.
///
/// The write is short and the caption already says "Keep this open until it
/// finishes.", so a drag that does nothing is explained BEFORE it is attempted
/// rather than after.
const ScrollPhysics _dragGuardPhysics = AlwaysScrollableScrollPhysics();

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

  /// Which of the file-problem state's two messages is on screen.
  ///
  /// The shape branch shows the expected format; the unreadable branch must not,
  /// because the app never read that file (see [kImportBadShapeMessage]).
  bool _fileProblemIsShape = false;

  /// The counts a partial write landed on, straight from
  /// [ImportPartialWriteException]'s numeric-only payload.
  int _partialDone = 0;
  int _partialTotal = 0;

  /// The already-parsed file, held so "Try again" can resume from the BANK READ
  /// rather than from the picker.
  ///
  /// The file has already been read and validated successfully by the time the
  /// bank can fail; making a briefly-offline user hunt for their file a second
  /// time would be charging them for the network's mistake. Cleared implicitly
  /// by the next pick, which overwrites it.
  ImportParse? _parsed;

  /// Picks a file and runs the whole import through to a terminal state.
  ///
  /// Every judgement is made before the first document goes out (D-52), and the
  /// bank read that gates it is server-only (D-60), so an offline import ends
  /// with nothing written rather than spinning on writes queued in the local
  /// cache.
  ///
  /// The state that owns the button which calls this is replaced the instant the
  /// import moves on, so a second tap is structurally impossible rather than
  /// merely ignored (D-19). While the OS picker is open the body does not change
  /// at all — a cancelled pick must find the surface exactly where it left it —
  /// and [_picking] nulls the button's handler instead.
  Future<void> _chooseFileAndImport() async {
    setState(() => _picking = true);

    final String? jsonText;
    try {
      jsonText = await _picker.pickJsonText();
    } on ImportFileUnreadableException catch (error) {
      // The seam's own signal: a file WAS chosen and could not be read.
      _landOnFileProblem(isShape: false, error: error);
      return;
    } catch (error, stack) {
      // Anything else is the picker seam misbehaving, and it lands on the SAME
      // honest state: a pick that threw is a file that could not be read,
      // whatever threw. Not the shape branch — the app has no evidence about
      // this file's contents, so it must not comment on them.
      _landOnFileProblem(isShape: false, error: error, stack: stack);
      return;
    }

    // `setState` after an `await` needs this guard: the pick outlives the sheet
    // whenever the user dismisses it before the picker answers, and calling
    // `setState` on a disposed `State` throws.
    if (!mounted) return;

    // A cancelled pick is not a failure and gets no copy at all: the body the
    // user was already looking at, with the format hint still on it, is the
    // complete and correct treatment.
    if (jsonText == null) {
      setState(() => _picking = false);
      return;
    }

    setState(() {
      _picking = false;
      _phase = _ImportPhase.checking;
      _comparingWithBank = false;
    });

    final ImportParse parsed;
    try {
      parsed = parseImportFile(jsonText);
    } on ImportFileEmptyException catch (error) {
      // EMPTY, not wrong — its own state, with no icon and no red.
      debugPrint('Import stopped: $error');
      if (!mounted) return;
      setState(() => _phase = _ImportPhase.emptyFile);
      return;
    } on ImportFileShapeException catch (error) {
      _landOnFileProblem(isShape: true, error: error);
      return;
    } catch (error, stack) {
      // The validator misbehaving lands on the same honest state as the file
      // being wrongly shaped: the app read this file and could not make sense
      // of it, whichever half failed.
      _landOnFileProblem(isShape: true, error: error, stack: stack);
      return;
    }

    _parsed = parsed;
    await _importParsedFile();
  }

  /// The half of the import that "Try again" resumes: bank read, dedupe, write.
  ///
  /// Split out from [_chooseFileAndImport] precisely so the retry has somewhere
  /// to restart that is not the picker.
  Future<void> _importParsedFile() async {
    final parsed = _parsed;
    // Unreachable: nothing routes here without a parsed file. Returning rather
    // than asserting keeps a future miswiring on the idle state instead of in a
    // crash.
    if (parsed == null) return;

    setState(() {
      _phase = _ImportPhase.checking;
      _comparingWithBank = true;
    });

    final Set<String> existing;
    try {
      existing = await _writer.existingKeys();
    } on QuestionBankUnavailableException catch (error) {
      _landOnUnreachable(error);
      return;
    } catch (error, stack) {
      _landOnUnreachable(error, stack);
      return;
    }
    if (!mounted) return;

    final plan = dedupeAgainstBank(parsed, existing);
    setState(() {
      _phase = _ImportPhase.writing;
      _rowsToWrite = plan.rowsToWrite.length;
      _rowsCommitted = 0;
    });

    final int added;
    try {
      added = await _writer.write(
        plan.rowsToWrite,
        onProgress: (committed, total) {
          if (!mounted) return;
          setState(() => _rowsCommitted = committed);
        },
      );
    } on ImportPartialWriteException catch (error) {
      // The one genuinely partial outcome, and the only place the sheet reports
      // counts from an exception — numbers only, never its text.
      debugPrint('Import partially written: $error');
      if (!mounted) return;
      setState(() {
        _phase = _ImportPhase.partial;
        _partialDone = error.done;
        _partialTotal = error.total;
      });
      return;
    } on QuestionBankUnavailableException catch (error) {
      // A write that failed before its first chunk committed. Nothing landed,
      // which is exactly what the unreachable copy says.
      _landOnUnreachable(error);
      return;
    } catch (error, stack) {
      _landOnUnreachable(error, stack);
      return;
    }
    if (!mounted) return;

    setState(() {
      _phase = _ImportPhase.result;
      _added = added;
      _duplicates = plan.duplicateCount;
      _skips = plan.skips;
    });
  }

  /// Lands on the file-problem state, on one of its two branches.
  ///
  /// Exception detail goes to the console and NOWHERE else — no exception text,
  /// no Firestore error code, no collection name, no document ID and no file
  /// path may reach the screen.
  void _landOnFileProblem({
    required bool isShape,
    required Object error,
    StackTrace? stack,
  }) {
    debugPrint('Import file rejected: $error');
    if (stack != null) debugPrintStack(stackTrace: stack);
    if (!mounted) return;
    setState(() {
      _picking = false;
      _phase = _ImportPhase.fileProblem;
      _fileProblemIsShape = isShape;
    });
  }

  /// Lands on the bank-unreachable state. Same containment rule as
  /// [_landOnFileProblem].
  void _landOnUnreachable(Object error, [StackTrace? stack]) {
    debugPrint('Import could not reach the bank: $error');
    if (stack != null) debugPrintStack(stackTrace: stack);
    if (!mounted) return;
    setState(() => _phase = _ImportPhase.unreachable);
  }

  /// Exactly one state body, chosen by an else-if chain so the keys are mutually
  /// exclusive BY CONSTRUCTION rather than by conditions kept disjoint by hand —
  /// the same reasoning `_StartFooter._helper` carries on Setup.
  Widget _body() {
    // Every restart-the-flow button in the sheet is the same action and takes
    // the same gate: null while the OS picker is open, so the second tap cannot
    // be fired rather than being swallowed.
    final VoidCallback? onChoose =
        _picking ? null : () => unawaited(_chooseFileAndImport());

    if (_phase == _ImportPhase.idle) {
      return _ImportIdle(onChoose: onChoose);
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
    if (_phase == _ImportPhase.fileProblem) {
      return _ImportFileProblem(isShape: _fileProblemIsShape, onChoose: onChoose);
    }
    if (_phase == _ImportPhase.emptyFile) {
      return _ImportEmptyFile(onChoose: onChoose);
    }
    if (_phase == _ImportPhase.unreachable) {
      return _ImportUnreachable(
        onRetry: () => unawaited(_importParsedFile()),
      );
    }
    if (_phase == _ImportPhase.partial) {
      return _ImportPartial(
        done: _partialDone,
        total: _partialTotal,
        onChoose: onChoose,
        onDone: () => Navigator.of(context).pop(),
      );
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

    final writing = _phase == _ImportPhase.writing;

    return PopScope<void>(
      // The ONE non-dismissible state (UI-SPEC "Dismissal is blocked in exactly
      // one state"): a user who closes mid-write never learns which rows landed.
      // Every other state has written nothing or has already been read, so
      // leaving costs nothing. The same mechanism the practice screen uses to
      // route the back gesture into the Stop dialog (D-29).
      //
      // **Verified against Flutter 3.44.6, the pinned version — and it covers
      // two of the three dismissal routes, not all three.** The system back
      // gesture and a barrier tap both go through `Navigator.maybePop`, which
      // consults this route's `popDisposition` and therefore this `canPop`
      // (`ModalBarrier._handleDismiss` → `Navigator.maybePop`, and
      // `ModalRoute.popDisposition` → its registered `PopEntry`s). Both are
      // blocked. **Drag-to-dismiss is NOT:** `_ModalBottomSheetState` builds its
      // `BottomSheet` with `onClosing: () { if (route.isCurrent)
      // Navigator.pop(context); }`, an unconditional pop that never asks the
      // route's disposition (`material/bottom_sheet.dart`, `_handleDragEnd` →
      // `onClosing`). See [_dragGuardPhysics] for what covers that gap and what
      // it cannot reach.
      canPop: !writing,
      child: SingleChildScrollView(
        // The drag guard. Not cosmetic: see the doc comment on
        // [_dragGuardPhysics].
        physics: writing ? _dragGuardPhysics : null,
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
        const _ShapeExampleCard(),
        const SizedBox(height: 24), // lg
        _PrimaryButton(
          buttonKey: const Key('import-choose-file'),
          label: 'Choose a JSON file',
          onPressed: onChoose,
        ),
      ],
    );
  }
}

/// The expected file format, as one widget with TWO render sites.
///
/// Renders [kImportShapeExample] for the idle state and for the file-problem
/// state's shape branch. One shape string and one card, not a second copy —
/// two copies of a format hint are two hints free to drift apart, and the one
/// the user is looking at would eventually stop being the one the parser
/// enforces.
///
/// Peach marks CONTENT; the sheet's own ivory surface is chrome, which is why
/// the example sits in a card and the sheet does not.
class _ShapeExampleCard extends StatelessWidget {
  const _ShapeExampleCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface, // peach
      borderRadius: BorderRadius.circular(24), // lg
      child: Padding(
        padding: const EdgeInsets.all(24), // lg
        child: Text(kImportShapeExample, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}

/// The sheet's one full-width primary action, in every state that has one.
///
/// A single widget so the 64px floor, the coral fill and the brown label cannot
/// drift between states — and so there is no layout shift when one terminal
/// state replaces another.
///
/// A null [onPressed] keeps the coral fill deliberately: the button is disabled
/// only while the OS picker is open, which is a moment, not a state, and
/// greying it out would read as "this is broken" rather than "wait".
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 64,
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          disabledBackgroundColor: theme.colorScheme.primary,
          disabledForegroundColor: theme.colorScheme.onPrimary,
        ),
        child: Text(label, style: theme.textTheme.labelLarge),
      ),
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
        _PrimaryButton(
          buttonKey: const Key('import-done'),
          label: 'Done',
          onPressed: onDone,
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

/// S5 — that file can't be used. Two facts, one surface, two sub-keys.
///
/// The unreadable branch and the shape branch differ in exactly two things: the
/// message, and whether the expected format follows it. Everything else — the
/// icon, the geometry, the action — is identical, which is why they are one
/// state rather than two, and why the icon below is ONE render site serving both
/// rather than a copy per branch. Showing the format for a file the app never
/// managed to READ would be a false explanation, so the example is bound to the
/// shape branch alone.
///
/// **The failure geometry is `_TopicsError`'s, verbatim** — 48px error-red icon
/// → 16px → the message in BROWN, centred — so the app has one recognisable
/// failure shape wherever a read or a write can fail. Red marks the fault and
/// brown carries the words: warm red on ivory measures 3.72:1, which clears
/// WCAG's 3:1 non-text threshold for the icon and fails the 4.5:1 threshold for
/// 16px body text; brown on ivory measures 12.8:1.
class _ImportFileProblem extends StatelessWidget {
  const _ImportFileProblem({required this.isShape, required this.onChoose});

  final bool isShape;

  /// Null while the OS picker is open (D-19).
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('import-file-problem'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 48, // 2xl
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16), // md
        // The sub-key rides on the message, which is the one thing that differs
        // between the branches, so a test asserts the branch by finding the fact
        // rather than by reading a flag.
        Text(
          isShape ? kImportBadShapeMessage : kImportUnreadableFileMessage,
          key: isShape
              ? const Key('import-file-problem-shape')
              : const Key('import-file-problem-unreadable'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (isShape) ...[
          const SizedBox(height: 16), // md
          const _ShapeExampleCard(),
        ],
        const SizedBox(height: 24), // lg
        _PrimaryButton(
          buttonKey: const Key('import-choose-different-file'),
          label: 'Choose a different file',
          onPressed: onChoose,
        ),
      ],
    );
  }
}

/// S6 — that file has no questions in it.
///
/// **No icon and no red, deliberately.** This is a file that is EMPTY, not
/// wrong, so it gets the app's empty-state treatment — heading, then body, both
/// centred — rather than its failure treatment. Filing it under "something went
/// wrong" would tell the user to retry something that will fail identically
/// every time; what they need is a different file, which is what the copy and
/// the button both say.
class _ImportEmptyFile extends StatelessWidget {
  const _ImportEmptyFile({required this.onChoose});

  /// Null while the OS picker is open (D-19).
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('import-empty-file'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          kImportEmptyFileMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8), // sm
        Text(
          kImportEmptyFileBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24), // lg
        _PrimaryButton(
          buttonKey: const Key('import-choose-different-file'),
          label: 'Choose a different file',
          onPressed: onChoose,
        ),
      ],
    );
  }
}

/// S7 — the bank could not be reached, and nothing was written.
///
/// **"Try again" is a coral primary here where the same label is a brown text
/// button on the Setup topics card.** That is not an inconsistency: on Setup the
/// retry competes with START SESSION on the same screen and must stay secondary;
/// in the sheet it is the ONLY action present, so it takes the primary treatment
/// every other sole action here has. Same label, same job, weighted to its
/// context.
///
/// **The retry does not re-open the picker.** The file has already been read and
/// parsed successfully; only the server read failed, so the retry resumes from
/// the bank read and a briefly-offline user never has to hunt for their file a
/// second time.
class _ImportUnreachable extends StatelessWidget {
  const _ImportUnreachable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('import-unreachable'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `_ImportFileProblem`'s geometry, which is `_TopicsError`'s: red marks
        // the fault, brown carries the words.
        Icon(
          Icons.error_outline_rounded,
          size: 48, // 2xl
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16), // md
        Text(
          kImportUnreachableMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24), // lg
        _PrimaryButton(
          buttonKey: const Key('import-retry'),
          label: 'Try again',
          onPressed: onRetry,
        ),
      ],
    );
  }
}

/// S8 — some of it landed, and here is exactly how much.
///
/// **A first-class terminal state, not a degraded result.** Its own key, its own
/// message, exact counts and a recovery that is genuinely safe — dressing a
/// partial write in the success-shaped summary card is the specific misreport
/// this split exists to prevent.
///
/// **Two buttons is the deliberate exception.** Every other state has exactly
/// one, and the sheet is specified to have a single EXIT — which "Done" still
/// is. "Choose the file again" restarts the flow INSIDE the sheet and exits
/// nothing, exactly as "Choose a different file" already does, so the exit count
/// is still one.
class _ImportPartial extends StatelessWidget {
  const _ImportPartial({
    required this.done,
    required this.total,
    required this.onChoose,
    required this.onDone,
  });

  final int done;
  final int total;

  /// Null while the OS picker is open (D-19).
  final VoidCallback? onChoose;

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('import-partial'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `_ImportFileProblem`'s geometry again. The counts come from the
        // exception's numeric payload, never from its text.
        Icon(
          Icons.error_outline_rounded,
          size: 48, // 2xl
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16), // md
        Text(
          importPartialMessage(done, total),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24), // lg
        _PrimaryButton(
          buttonKey: const Key('import-choose-different-file'),
          label: 'Choose the file again',
          onPressed: onChoose,
        ),
        const SizedBox(height: 8), // sm
        TextButton(
          key: const Key('import-done'),
          onPressed: onDone,
          style: TextButton.styleFrom(
            // Touch-target floor, not part of the 4px content scale.
            minimumSize: const Size(64, 48),
            foregroundColor: theme.colorScheme.onSurface,
          ),
          child: Text('Done', style: theme.textTheme.labelLarge),
        ),
      ],
    );
  }
}
