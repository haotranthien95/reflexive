// EnglishReflex — one-off Firestore question-bank seed (D-45).
//
// WHAT THIS IS
//   A developer tool, run once from the maintainer's machine, that puts enough
//   real questions into the `questions` collection for Phase 3 to be demoable
//   and for its edge paths to be *exercised* rather than merely designed.
//
// IT IS DISPOSABLE BY DESIGN
//   Nothing under `tool/` is imported by `lib/` and nothing under `tool/` enters
//   the app binary. Phase 4's in-app JSON importer (IMPORT-01) supersedes it;
//   delete this directory when that lands. See tool/README.md.
//
// WHY THE WEB SDK AND NOT firebase-admin
//   The Admin SDK bypasses security rules and needs a service-account key —
//   which D-46 explicitly rejected. The Web SDK goes through the same open
//   `questions` rules the app itself relies on, so seeding actually *proves*
//   those rules work rather than routing around them.
//
// THE DOCUMENT CONTRACT (Task 1, option-a — one-way door, do not drift)
//   Every document carries EXACTLY four fields: `content`, `subject`, `level`,
//   `created_at`. The schema's `id` (BANK-01) is the Firestore auto-generated
//   document key — it is deliberately NOT duplicated as an in-document field,
//   because a duplicated key can drift out of sync with the real one.
//   `created_at` is a NATIVE Firestore Timestamp (not an ISO string, not epoch
//   millis) and is strictly increasing across the written set, so D-43's
//   `orderBy('created_at')` produces an order that is observable and checkable.
//   Phase 4's importer MUST write this same representation.
//
// MODES
//   --dry-run   Print the document matrix and totals. Writes nothing.
//   (default)   Seed the collection. Refuses if it is already non-empty unless
//               --force is passed, so a second run cannot silently double the
//               bank (auto-IDs never collide, so re-running would not overwrite).
//   --verify    Read the collection back, print the per-subject and
//               per-subject-per-level matrix, replay the real D-43 query, and
//               exit non-zero if any acceptance count is wrong.
//
// USAGE
//   npm install --prefix tool
//   node tool/seed_questions.mjs --dry-run
//   node tool/seed_questions.mjs
//   node tool/seed_questions.mjs --verify
//
//   Credentials are read from lib/firebase_options.dart by default, or passed
//   as --project-id=<id> --api-key=<key>.

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { initializeApp } from 'firebase/app';
import {
  Timestamp,
  addDoc,
  collection,
  getDocs,
  getFirestore,
  limit,
  orderBy,
  query,
  terminate,
  where,
} from 'firebase/firestore';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, '..');

/// The one place the collection is named on this side of the wire. Its Dart
/// counterpart is `kQuestionsCollection` in
/// lib/services/firestore_question_source.dart — the two must agree.
const COLLECTION = 'questions';

/// The exact CEFR strings `kLevels` uses in lib/screens/setup_screen.dart. The
/// app matches level with `==` and no widening (D-40), so a typo here is a
/// silently empty session, not an error.
const LEVELS = ['A1', 'B1', 'C1'];

// ── The seed matrix (D-45) ───────────────────────────────────────────────────
//
// This is a requirement, not an example. Two combinations are deliberately
// EMPTY (`Travel` × C1 and `Food & health` × A1) because D-41's zero-result
// message ships unexercised without them. One subject name is deliberately
// long and one prompt is deliberately long, because the UI-SPEC's E1/E3
// long-text backstops otherwise have nothing to fail against. Two documents
// are deliberately malformed so plan 02's skip-and-log path has something to
// skip.

const LONG_SUBJECT = 'Technology, media and everyday digital habits';

/// >200 characters on purpose — the UI-SPEC E3 long-prompt backstop.
const LONG_PROMPT =
  'Think about the very first thing you reach for when you wake up and the last '
  + 'thing you look at before you fall asleep. Describe how the screens in your '
  + 'life shape an ordinary day for you, what you would genuinely miss if they '
  + 'all disappeared tomorrow morning, and the one habit you would change if you '
  + 'could change only one.';

/// Valid documents, grouped subject → level → prompts. Prompts are real practice
/// questions in the voice of the Phase 2 bank in lib/data/questions.dart: short,
/// answerable aloud, and pitched at their CEFR level.
const MATRIX = {
  'Daily life': {
    A1: [
      'What do you eat for breakfast?',
      'Who do you live with?',
      'What time do you wake up on a normal day?',
    ],
    B1: [
      'Describe a small habit you would like to change, and why.',
      'Tell me about a typical Sunday in your life.',
      'What is the most useful thing in your home, and how often do you use it?',
    ],
    C1: [
      'To what extent do the routines you keep shape the person you become?',
      'Describe a domestic ritual you follow without questioning, and unpack why it persists.',
    ],
  },
  'Work & study': {
    A1: [
      'What is your job, or what do you study?',
      'Do you work better in the morning or in the afternoon?',
    ],
    B1: [
      'Describe a task at work or school that you find difficult.',
      'Tell me about a colleague or classmate you learn a lot from.',
      'What one change would make your working day better?',
    ],
    C1: [
      'Argue for or against the claim that expertise is mostly a matter of deliberate practice.',
      'How should an organisation balance individual autonomy against collective consistency?',
    ],
  },
  Travel: {
    A1: [
      'Where do you want to go on your next holiday?',
      'How do you travel to another city — by bus, by train or by plane?',
    ],
    B1: [
      'Describe a place you have visited that surprised you.',
      'Tell me about something that went wrong on a trip.',
      'What do you always pack, and what do you always forget?',
    ],
    // C1 is deliberately absent — this is the zero-result combination D-41 needs.
  },
  'Food & health': {
    // A1 is deliberately absent — the second zero-result combination.
    B1: [
      'Describe a dish from your country to someone who has never tried it.',
      'Tell me about a change you made to eat or sleep better.',
      'How do you stay active during a busy week?',
    ],
    C1: [
      'How far should a government go in shaping what its citizens eat?',
      'Discuss the tension between convenience food and long-term public health.',
    ],
  },
  [LONG_SUBJECT]: {
    B1: [
      LONG_PROMPT,
      'Describe an app you use every single day and explain why you keep it.',
    ],
  },
};

/// Deliberately broken documents, so the malformed-document skip path (plan 02)
/// has real data to skip instead of a hypothetical.
const MALFORMED = [
  {
    label: 'missing `content` field entirely',
    // No `content` key at all.
    fields: { subject: 'Daily life', level: 'B1' },
  },
  {
    label: '`content` is whitespace only',
    fields: { subject: 'Travel', level: 'A1', content: '   \n\t  ' },
  },
];

// ── Plumbing ─────────────────────────────────────────────────────────────────

function argFlag(name) {
  return process.argv.includes(`--${name}`);
}

function argValue(name) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}

/// Reads `projectId` / `apiKey` out of the generated lib/firebase_options.dart
/// rather than asking for them again: that file is the app's identity, so a
/// mismatch between it and this script would seed a bank the app never reads.
function readFirebaseConfig() {
  const projectIdArg = argValue('project-id');
  const apiKeyArg = argValue('api-key');
  if (projectIdArg && apiKeyArg) {
    return { projectId: projectIdArg, apiKey: apiKeyArg };
  }

  const path = resolve(REPO_ROOT, 'lib/firebase_options.dart');
  let source;
  try {
    source = readFileSync(path, 'utf8');
  } catch {
    throw new Error(
      `Could not read ${path}. Run \`flutterfire configure\` at the repo root, `
      + 'or pass --project-id=<id> --api-key=<key>.',
    );
  }

  const android = source.match(
    /static const FirebaseOptions android = FirebaseOptions\(([\s\S]*?)\);/,
  );
  if (!android) {
    throw new Error(
      'lib/firebase_options.dart has no `android` FirebaseOptions block — '
      + 're-run `flutterfire configure`, or pass --project-id / --api-key.',
    );
  }
  const field = (name) => {
    const m = android[1].match(new RegExp(`${name}:\\s*'([^']+)'`));
    if (!m) throw new Error(`lib/firebase_options.dart is missing \`${name}\`.`);
    return m[1];
  };
  return {
    projectId: field('projectId'),
    apiKey: field('apiKey'),
    appId: field('appId'),
    messagingSenderId: field('messagingSenderId'),
  };
}

/// Flattens [MATRIX] + [MALFORMED] into the exact write order, assigning each
/// document a strictly increasing `created_at`.
///
/// The step is one second so the ordering is obvious to a human reading the
/// Firestore console, and the base is `now` minus the whole span so the newest
/// seeded question is still in the past — a Phase 4 import lands *after* the
/// seed, which is exactly what D-43 promises ("newly imported questions land at
/// the end").
function buildDocuments() {
  const rows = [];
  for (const [subject, byLevel] of Object.entries(MATRIX)) {
    for (const level of LEVELS) {
      for (const content of byLevel[level] ?? []) {
        rows.push({ subject, level, content, malformed: null });
      }
    }
  }
  for (const bad of MALFORMED) {
    rows.push({ ...bad.fields, malformed: bad.label });
  }

  const stepMs = 1000;
  const baseMs = Date.now() - rows.length * stepMs;
  return rows.map((row, i) => {
    const { malformed, ...fields } = row;
    return {
      malformed,
      // Exactly {content?, subject, level, created_at} — nothing else, no `id`.
      data: { ...fields, created_at: Timestamp.fromMillis(baseMs + i * stepMs) },
    };
  });
}

function tally(docs) {
  const subjects = [...new Set(docs.map((d) => d.subject ?? '(missing)'))].sort(
    (a, b) => a.toLowerCase().localeCompare(b.toLowerCase()),
  );
  const cells = new Map();
  for (const d of docs) {
    const key = `${d.subject ?? '(missing)'} ${d.level ?? '(missing)'}`;
    cells.set(key, (cells.get(key) ?? 0) + 1);
  }
  return { subjects, count: (s, l) => cells.get(`${s} ${l}`) ?? 0 };
}

function printMatrix(docs) {
  const { subjects, count } = tally(docs);
  const width = Math.max(...subjects.map((s) => s.length), 'SUBJECT'.length);
  console.log(
    `  ${'SUBJECT'.padEnd(width)}  ${LEVELS.map((l) => l.padStart(4)).join('')}  TOTAL`,
  );
  for (const s of subjects) {
    const counts = LEVELS.map((l) => String(count(s, l)).padStart(4)).join('');
    const total = LEVELS.reduce((n, l) => n + count(s, l), 0);
    console.log(`  ${s.padEnd(width)}  ${counts}  ${String(total).padStart(5)}`);
  }
  console.log(`  ${'-'.repeat(width + 2 + LEVELS.length * 4 + 7)}`);
  console.log(`  ${'documents'.padEnd(width)}  ${' '.repeat(LEVELS.length * 4)}  ${String(docs.length).padStart(5)}`);
  return { subjects, count };
}

// ── Modes ────────────────────────────────────────────────────────────────────

function dryRun() {
  const docs = buildDocuments();
  console.log(`DRY RUN — nothing will be written to \`${COLLECTION}\`.\n`);
  printMatrix(docs.map((d) => d.data));
  const bad = docs.filter((d) => d.malformed);
  console.log(`\n  malformed documents included on purpose: ${bad.length}`);
  for (const d of bad) {
    console.log(`    - ${d.data.subject} / ${d.data.level}: ${d.malformed}`);
  }
  const longest = [...new Set(docs.map((d) => d.data.subject))].sort(
    (a, b) => b.length - a.length,
  )[0];
  console.log(`\n  longest subject name: "${longest}" (${longest.length} chars)`);
  const longestPrompt = docs
    .map((d) => d.data.content ?? '')
    .sort((a, b) => b.length - a.length)[0];
  console.log(`  longest prompt: ${longestPrompt.length} chars`);
  console.log(
    `  created_at: native Firestore Timestamp, strictly increasing, 1s apart\n`,
  );
  console.log('Re-run without --dry-run to write these documents.');
}

async function seed(db, force) {
  const existing = await getDocs(collection(db, COLLECTION));
  if (!existing.empty && !force) {
    console.error(
      `REFUSING TO SEED: \`${COLLECTION}\` already holds ${existing.size} `
      + 'document(s).\n'
      + 'Documents are written with auto-generated IDs, so a second run would '
      + 'ADD a duplicate bank rather than replace it.\n'
      + 'Delete the collection in the Firebase console first, or pass --force '
      + 'if duplicates are genuinely what you want.',
    );
    return 1;
  }

  const docs = buildDocuments();
  // Written one at a time, in order, rather than in a batch: the whole point of
  // `created_at` here is a *checkable* sequence, and a serial write makes the
  // order that lands the order printed above.
  for (const d of docs) {
    await addDoc(collection(db, COLLECTION), d.data);
  }
  console.log(`Wrote ${docs.length} documents to \`${COLLECTION}\`.\n`);
  printMatrix(docs.map((d) => d.data));
  console.log('\nRun with --verify to read it back.');
  return 0;
}

async function verify(db) {
  const snap = await getDocs(collection(db, COLLECTION));
  const docs = snap.docs.map((d) => d.data());
  console.log(`Read back ${docs.length} documents from \`${COLLECTION}\`.\n`);
  const { subjects, count } = printMatrix(docs);

  const malformed = docs.filter(
    (d) => typeof d.content !== 'string' || d.content.trim().length === 0,
  );
  console.log(`\n  malformed documents present (expected, D-45): ${malformed.length}`);
  const longest = [...subjects].sort((a, b) => b.length - a.length)[0] ?? '';
  console.log(`  longest subject name: "${longest}" (${longest.length} chars)`);

  // Replay the REAL D-43 query shape the app will issue. This is the only way
  // to prove the composite index in firestore.indexes.json is actually built —
  // a plain collection read needs no index and would pass regardless.
  let ordered = [];
  try {
    const q = query(
      collection(db, COLLECTION),
      where('subject', 'in', ['Travel', 'Daily life']),
      where('level', '==', 'B1'),
      orderBy('created_at'),
      limit(50),
    );
    ordered = (await getDocs(q)).docs.map((d) => d.data());
    console.log(
      `\n  D-43 query replay (subject in [Travel, Daily life] + level == B1 + `
      + `orderBy created_at): ${ordered.length} docs`,
    );
  } catch (e) {
    console.error(
      `\nFAIL: the real D-43 query threw: ${e.message}\n`
      + 'If this says the query requires an index, the composite index is still '
      + 'BUILDING. Wait for the Firebase console to report it as Enabled and '
      + 're-run — index builds are asynchronous.',
    );
    return 1;
  }

  const failures = [];
  const check = (ok, label) => {
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}`);
    if (!ok) failures.push(label);
  };

  console.log('\nAcceptance checks:');
  check(subjects.length >= 5, `at least 5 distinct subjects (got ${subjects.length})`);
  check(count('Travel', 'B1') > 0, `Travel x B1 is non-zero (got ${count('Travel', 'B1')})`);
  check(count('Travel', 'C1') === 0, `Travel x C1 is ZERO (got ${count('Travel', 'C1')})`);
  check(
    count('Food & health', 'A1') === 0,
    `Food & health x A1 is ZERO (got ${count('Food & health', 'A1')})`,
  );
  check(longest.length > 30, `a subject name longer than 30 chars (got ${longest.length})`);
  check(malformed.length >= 2, `at least 2 malformed documents (got ${malformed.length})`);
  check(ordered.length > 0, 'the real D-43 query returns documents');

  const times = ordered.map((d) => d.created_at?.toMillis?.());
  check(
    times.every((t) => typeof t === 'number'),
    'every created_at is a native Firestore Timestamp',
  );
  check(
    times.every((t, i) => i === 0 || t > times[i - 1]),
    'the D-43 query returns strictly ascending created_at',
  );

  if (failures.length > 0) {
    console.error(`\n${failures.length} check(s) FAILED.`);
    return 1;
  }
  console.log('\nAll checks passed.');
  return 0;
}

// ── Entry point ──────────────────────────────────────────────────────────────

async function main() {
  if (argFlag('dry-run')) {
    dryRun();
    return 0;
  }

  const config = readFirebaseConfig();
  console.log(`Firebase project: ${config.projectId}\n`);
  const db = getFirestore(initializeApp(config));
  try {
    return argFlag('verify') ? await verify(db) : await seed(db, argFlag('force'));
  } finally {
    // Firestore keeps a live connection open; without this Node never exits.
    await terminate(db).catch(() => {});
  }
}

main().then(
  (code) => process.exit(code ?? 0),
  (err) => {
    console.error(err?.message ?? err);
    process.exit(1);
  },
);
