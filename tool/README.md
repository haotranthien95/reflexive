# `tool/` — the one-off Firestore question-bank seed

**This directory is disposable by design.** It exists so Phase 3 is demoable at all: without it the
`questions` collection is empty, the Setup screen has no topics to draw, and every edge path the phase
designs (D-41's zero-result message, the long-subject and long-prompt backstops, the malformed-document
skip) ships untested against real data.

Nothing here is imported by `lib/`. Nothing here enters the app binary. It runs once, from the
maintainer's machine.

**Delete this directory when Phase 4's in-app JSON importer (IMPORT-01) lands.** That importer is the
real, shipped way questions get into the bank; keeping a second write path around after it exists would
mean two ways to fill the bank and only one of them tested.

## What it writes

Documents in the `questions` collection carrying **exactly** four fields — `content`, `subject`,
`level`, `created_at` — and nothing else. The schema's `id` (BANK-01) is the Firestore auto-generated
document key; it is deliberately not duplicated inside the document, because a duplicated key can drift
out of sync with the real one.

`created_at` is a **native Firestore `Timestamp`**, strictly increasing across the written set. This is
a one-way door (Task 1, `option-a`): D-43 defines "sequential bank order" as `orderBy('created_at')`,
the composite index in `firestore.indexes.json` is built on this field, `FirestoreQuestionSource` reads
it back in this representation, and **Phase 4's importer must write the same one**. Changing it later is
a data migration, not a refactor.

The seed matrix is a requirement, not an example (D-45). It deliberately includes:

- five subjects, one of them long on purpose (`Technology, media and everyday digital habits`);
- two genuinely **empty** subject-by-level combinations — `Travel` x `C1` and `Food & health` x `A1` —
  so D-41's zero-result path is reachable;
- one prompt over 200 characters, so the UI-SPEC's long-text backstop has something to fail against;
- two deliberately malformed documents (one with no `content` field, one whose `content` is only
  whitespace), so the skip-and-log path has something to skip.

## Why the Firebase **Web** SDK and not `firebase-admin`

The Admin SDK bypasses security rules and needs a service-account key, which D-46 explicitly rejected.
The Web SDK writes through the same knowingly-open `questions` rules the app itself depends on — so
seeding actually exercises those rules rather than routing around them.

## Running it

```bash
# One-time
npm install --prefix tool

# See exactly what would be written; writes nothing
node tool/seed_questions.mjs --dry-run

# Write it
node tool/seed_questions.mjs

# Read it back and check the acceptance counts, including a replay of the real
# D-43 query (which is the only way to prove the composite index is built)
node tool/seed_questions.mjs --verify
```

Credentials are read from `lib/firebase_options.dart` — the app's own identity, so the script cannot
seed a project the app does not read. Override with `--project-id=<id> --api-key=<key>` if needed.

The default run **refuses** if `questions` is already non-empty: documents are written with
auto-generated IDs, so a second run would add a duplicate bank rather than replace it. Delete the
collection in the Firebase console first, or pass `--force` if duplicates are genuinely what you want.

## Rules and index

`firestore.rules` and `firestore.indexes.json` live at the repo root and are deployed separately from
the app:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

Index builds are **asynchronous**. If `--verify` reports that the query requires an index, wait for the
Firebase console to show it as Enabled and re-run — that is a build still in flight, not a failure.
