# Prompt: Generate Question Bank Data (for any AI)

Copy the block below, fill in the `[...]` placeholders, and paste it into ChatGPT, Claude, Gemini, or any other AI. The output is a JSON file ready to import directly via the **Import questions** action in the app's Setup app bar.

## The Prompt

```
You are generating practice-question data for an English speaking-practice app.

TASK
Generate [NUMBER] English speaking-practice questions for the topic "[TOPIC]" at
CEFR level [LEVEL].

RULES
- Each question must be something a learner can answer OUT LOUD in a short spoken
  answer (a few sentences) — not a written-essay prompt, not a yes/no trivia fact.
- Questions must match the stated CEFR level's vocabulary and grammar complexity:
  - A1/A2: very simple, everyday, present-tense, short-answer questions
  - B1/B2: opinions, experiences, comparisons, some past/future tense
  - C1/C2: abstract, nuanced, hypothetical, or debate-style questions
- Every question must be unique (no near-duplicates within this batch).
- The "subject" field must be EXACTLY: "[TOPIC]" (same spelling/casing every time).
- The "level" field must be EXACTLY one of: "A1", "A2", "B1", "B2", "C1", "C2".
- Do not include ids, dates, explanations, or answers — only the question text.

OUTPUT FORMAT — return ONLY valid JSON, no markdown fences, no commentary, matching
this exact shape:

{
  "data": [
    { "content": "What's your name?", "subject": "[TOPIC]", "level": "[LEVEL]" },
    { "content": "...", "subject": "[TOPIC]", "level": "[LEVEL]" }
  ]
}

Generate exactly [NUMBER] items now.
```

**Fill in before sending:**
- `[NUMBER]` — how many questions you want (e.g. `20`)
- `[TOPIC]` — one topic, exact spelling (see the seed list below, or your own)
- `[LEVEL]` — one CEFR level: `A1`, `A2`, `B1`, `B2`, `C1`, or `C2`

Run it once per topic/level combination you want to fill (e.g. "Travel" + "B1", then "Travel" + "B2", etc.), then merge the `"data"` arrays together before importing, or import each file one at a time. Either way the import is safe to repeat: the app checks the whole file before it writes anything, tidies each value, skips any row it cannot use and tells you which one, and skips any question your bank already has instead of adding a second copy. What that means in practice is spelled out below.

## What the app actually does with your file

Read this before you go hunting for a bug in a file that the app handled exactly as designed.

**Nothing is written until the whole file has been checked.** The app reads and validates every row first, then writes only the rows that survived. A file with 97 good rows and 3 unusable ones imports the 97 — one bad row never costs you the batch.

**Values are tidied on the way in, and the tidied value is what gets stored.** `content` and `subject` have surrounding whitespace trimmed; `level` is trimmed *and* upper-cased. So `" Travel"` is stored as `Travel`, and `"b1"` is stored as `B1`.

**A row the app cannot use is skipped and named by its position.** A row is skipped when `content` is missing, is not text, or is blank once trimmed; when `subject` is missing, is not text, or is blank once trimmed; when `level` is not one of the six CEFR values after trimming and upper-casing; or when the entry is not an object at all. Each skipped row appears in the result under **What we skipped**, identified by its **1-based position in the `data` list** and its reason — for example `Row 14 · level "B7" isn't one of A1–C2`. The position is what makes the row findable in your editor.

**A question already in your bank is skipped as a duplicate, not added again.** Before writing, the app reads your bank and compares each row's `content` + `subject` + `level` against it, and against the rows earlier in the same file. Anything that matches is counted separately — *"12 were already in your bank"* — and is never reported as an error. **Re-importing the same file is therefore harmless**: the second import adds nothing.

**A whole-file problem is reported on its own, with no row list.** If the file is not valid JSON, has no `data` key, or has a `data` value that is not a list, no row was examined and no counts are shown — just what the file needs to look like. A file that parses but whose `data` list is empty gets its own message, because a file being *empty* is a different fact from a file being *wrong*.

### What this means for the prompt you write

- **A lower-case level is accepted, not rejected.** An AI that emits `"b1"` costs you nothing; the app stores `B1`. You still want the prompt's exact-value rule, because `"Beginner"` or `"A1-A2"` *is* a skipped row.
- **Stray whitespace around a topic name cannot fork your topic list.** ` Travel` and `Travel` both land as `Travel`, so you will not end up with two checkboxes for one topic. Casing is a different matter — `travel` and `Travel` are two topics, because a topic name is a lookup key and the app deliberately does not case-fold it. Copy the strings below exactly.
- **You do not have to track what you have already imported.** Merge freely, re-run a topic, import an overlapping file — duplicates are counted and dropped.
- **Every row gets its own timestamp, in file order.** Questions appear in the bank in the order they appear in your file, and a new import lands at the end.

## Seed Topics (already shipped in the app)

The app ships with these 10 general-purpose topics, at **all six CEFR levels with ten questions in each of the sixty combinations** — so no topic-and-level pair you can tick comes back empty on a fresh install. That starter content is authored in the repo at `seed/seed-questions.json` and loaded through this same import action; see `seed/README.md` for how it is regenerated and why it stays in the repo.

Reuse these exact strings for `[TOPIC]` so new questions land under the same filters as the shipped ones:

1. `Daily Life`
2. `Travel`
3. `Food & Dining`
4. `Work & Career`
5. `Health & Fitness`
6. `Education`
7. `Technology`
8. `Family & Relationships`
9. `Sports`
10. `Entertainment & Hobbies`

You are not limited to these — any `subject` string you use becomes a selectable topic in the app's setup screen automatically, since topics are just the distinct `subject` values found in the question bank.

## Required Import Format

Whatever AI you use, the final JSON file you import must always match this shape exactly — this is enforced by the app's import validation:

```json
{
  "data": [
    { "content": "What's your name?", "subject": "Daily Life", "level": "A1" },
    { "content": "Describe your morning routine.", "subject": "Daily Life", "level": "A2" }
  ]
}
```

- `content` — the question text, required, non-empty once trimmed
- `subject` — the topic, required, non-empty once trimmed
- `level` — one of `A1`, `A2`, `B1`, `B2`, `C1`, `C2`, required (lower case is accepted and corrected)
- `id` and `created_at` are **not** included in the import file — the app generates them automatically when it writes each question to Firestore.

Save the AI's output as a `.json` file, put it somewhere the device's file picker can reach, then open Setup, tap **Import questions**, tap **Choose a JSON file** and pick it. The sheet reports how many were added, how many were already in your bank and which rows were skipped; tap **Done** and the new topics appear on Setup straight away.
