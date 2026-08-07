# Prompt: Generate Question Bank Data (for any AI)

Copy the block below, fill in the `[...]` placeholders, and paste it into ChatGPT, Claude, Gemini, or any other AI. The output is a JSON file ready to import directly via the app's **Import JSON** feature.

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

Run it once per topic/level combination you want to fill (e.g. "Travel" + "B1", then "Travel" + "B2", etc.), then merge the `"data"` arrays together before importing, or import each file one at a time — the app's import just appends to the bank.

## Seed Topics (already shipped in the app)

The app ships with these ~10 general-purpose topics. Reuse these exact strings for `[TOPIC]` so new questions land under the same filters as the built-in ones:

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

- `content` — the question text, required, non-empty string
- `subject` — the topic, required, non-empty string
- `level` — one of `A1`, `A2`, `B1`, `B2`, `C1`, `C2`, required
- `id` and `created_at` are **not** included in the import file — the app generates them automatically when it writes each question to Firestore.

Save the AI's output as a `.json` file, then use **Import JSON** in the app to load it into the question bank.
