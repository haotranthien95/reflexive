# `seed/` — the starter question bank

`seed-questions.json` is the content the app's question bank ships with: **600 questions —
ten topics x six CEFR levels x ten questions in every one of the sixty cells.** It is
authored here, in the repo, in the app's own import format, and it is loaded into Firestore
**through the app's own Import JSON action, on a device** (D-57).

## What this directory is NOT

- **Not a Flutter asset.** `seed-questions.json` is deliberately absent from `pubspec.yaml`'s
  `assets:` list and is never bundled into the app binary. Nothing under `lib/` reads it.
  Bundling it would reintroduce a second in-app question bank, which is exactly what
  deleting `PlaceholderQuestionSource` in Phase 3 was meant to prevent (D-36) — with two
  banks the user cannot tell which one they are drilling against.
- **Not a first-run mechanism.** Seeding makes the bank non-empty for every install; it does
  not make a brand-new install work offline. The bank lives in Firestore, so a device that
  has never been online still needs one successful Setup visit before it can drill (D-56).
- **Not a second write path.** There is exactly one way questions get into the bank: the
  in-app importer. That is why the one-off Node seed script that used to live under `tool/`
  was deleted in this phase rather than kept as a convenience — it did not normalize, did
  not dedupe and did not reject a bad level, so keeping it would have meant two writers into
  one collection obeying two different sets of rules.

## Why it stays in the repo after the import

The Phase 3 dev seed was **wiped** before this file was imported, and that delete is one-way
(D-58). This file is the only way back to a known-good bank. Keeping it also means the
content is reviewable in a diff: a question that presumes something about the learner, or
one that drifts off its CEFR level, is caught in review rather than discovered mid-drill.

## The format

Exactly the app's import format and nothing more — one object with one key, `data`, whose
value is a list of rows carrying exactly `content`, `subject` and `level`:

```json
{
  "data": [
    { "content": "What time do you get up in the morning?", "subject": "Daily Life", "level": "A1" }
  ]
}
```

No `id` and no `created_at`: the app generates both at import time. `id` is the Firestore
auto-generated document key and is never duplicated inside the document; `created_at` is a
native `Timestamp` that increases strictly in file order, so **bank order reproduces the
order of the rows in this file** (D-63).

## The ten topics

`Daily Life`, `Travel`, `Food & Dining`, `Work & Career`, `Health & Fitness`, `Education`,
`Technology`, `Family & Relationships`, `Sports`, `Entertainment & Hobbies`.

These strings must stay **character for character identical** to the "Seed Topics" list in
`docs/QUESTION_GENERATION_PROMPT.md`. A topic is nothing more than a distinct `subject`
value in the bank, so `Travel` and `travel` would be two checkboxes for one topic. (The
importer trims surrounding whitespace on write, so a stray space cannot fork a topic — but
it does not case-fold, and it should not: a topic name is a query key.)

## Content rules every row obeys

- **Answerable out loud** in a few sentences. No written-essay prompts, no yes/no trivia, no
  question with one correct factual answer.
- **Level-appropriate.** A1/A2 are simple, everyday and short-answer; B1/B2 ask for
  opinions, experience and comparison; C1/C2 are abstract, hypothetical or debate-shaped.
- **Unique.** No two rows share the same `content` + `subject` + `level`, and near-duplicate
  phrasings within a topic are avoided so a session does not feel repetitive.
- **Answerable by anyone.** No question requires the learner to disclose a health condition,
  their income, their religion, their immigration status or their sexual orientation, and
  none presumes a particular family shape, income level, physical ability or nationality.
  Where a topic edges toward the personal the question is framed so it can be answered about
  people in general — what makes a workplace good rather than what the learner earns, how
  people stay active rather than the learner's own medical history.
- **Plain ASCII apostrophes and no embedded newlines, tabs or carriage returns**, so the file
  is trivially valid JSON and any row renders as a single line in the importer's skip list.

## Regenerating a topic

Run the prompt in `docs/QUESTION_GENERATION_PROMPT.md` once per topic-by-level cell
(`[TOPIC]` = one of the ten strings above, `[LEVEL]` = one CEFR level, `[NUMBER]` = 10), then
merge the resulting `data` arrays into one file. Re-check the content rules above by hand —
the prompt states them, but nothing enforces them.

Two mechanical checks before committing a regenerated file:

```bash
# 600 rows, 10 topics, 10 rows in each of the 60 cells, all triples distinct
node -e "const d=require('./seed/seed-questions.json').data;const L=['A1','A2','B1','B2','C1','C2'];const T=[...new Set(d.map(r=>r.subject))];const c={};for(const r of d)c[r.subject+'/'+r.level]=(c[r.subject+'/'+r.level]||0)+1;const bad=T.flatMap(t=>L.filter(l=>c[t+'/'+l]!==10));const u=new Set(d.map(r=>JSON.stringify([r.content,r.subject,r.level])));if(d.length!==600||T.length!==10||bad.length||u.size!==600){console.error({rows:d.length,topics:T.length,badCells:bad,unique:u.size});process.exit(1)}console.log('ok')"

# every subject string also appears in the generation prompt
node -e "const d=require('./seed/seed-questions.json').data;const p=require('fs').readFileSync('docs/QUESTION_GENERATION_PROMPT.md','utf8');const m=[...new Set(d.map(r=>r.subject))].filter(s=>!p.includes(s));if(m.length){console.error(m);process.exit(1)}console.log('ok')"
```

## Loading it

The file is **side-loaded onto the device and imported through the app** — there is no
script and no console step:

1. Copy `seed/seed-questions.json` onto the device (any location the OS file picker can
   reach: Downloads, Files, Drive).
2. Open the app, and on the Setup screen tap the **Import questions** action in the app bar.
3. Tap **Choose a JSON file** and pick the copied file.
4. Wait for the write to finish. The sheet cannot be dismissed while it is writing — 600
   rows exceed one Firestore write batch (500), so the import commits in two chunks and the
   progress bar advances once per completed chunk.
5. Read the result: how many were added, how many were already in the bank, how many rows
   were skipped and why. Then tap **Done** — Setup re-reads its topics on dismissal, so the
   ten topics appear without leaving the screen.

Importing the same file twice is harmless: the importer skips any row whose content, subject
and level already exist in the bank, and counts them as duplicates rather than errors.

The full on-device procedure, including wiping the previous dev seed first and reading the
result back, is plan `04-05` of phase 04.
