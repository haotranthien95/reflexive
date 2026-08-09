---
status: testing
phase: 03-real-question-bank-via-firestore
source: [03-VERIFICATION.md]
started: 2026-08-09T11:22:17Z
updated: 2026-08-09T11:22:17Z
---

## Current Test

number: 1
name: Networked-device tracer — the app actually runs against the live Firestore bank
expected: |
  On a networked Android device, launch the app. The Setup screen's topic
  checkboxes are populated with the seeded subjects read from Firestore — at
  minimum: Daily life, Work & study, Travel, Food & health, and the long
  "Technology, media and everyday digital habits". They are NOT placeholder
  topics (the placeholder bank no longer exists in the binary).

  Select "Travel", choose level B1, and tap START SESSION. The practice loop
  opens and shows a prompt that came back from that Firestore query — a real
  seeded Travel/B1 question, not a hardcoded string.
awaiting: user response

## Tests

### 1. Networked-device tracer — the app actually runs against the live Firestore bank
expected: Setup renders the seeded subjects from Firestore (Daily life, Work & study, Travel, Food & health, and the 45-char "Technology, media and everyday digital habits"); selecting Travel + B1 and tapping START SESSION opens the loop on a real seeded Travel/B1 prompt. Closes ROADMAP success criteria SC1 and SC2. Ledger entry #1.
result: [pending]

### 2. Malformed-document skip-and-log
expected: Two documents were seeded deliberately malformed — `Daily life`×B1 with no `content` field, and `Travel`×A1 with whitespace-only `content`. Confirm neither produces a blank checkbox row on Setup nor a blank prompt mid-session, and that each skip appears in the debug console naming its document ID. Covers UI-SPEC backstops E1/partial and E3/partial. Ledger entry #12.
result: [pending]

### 3. E1/long-text — long subject name at maximum text scale
expected: At the largest OS text-scale setting, the seeded 45-character subject "Technology, media and everyday digital habits" WRAPS and grows its 64px topic row rather than clipping, and the topics card scrolls rather than pushing START SESSION off screen. Ledger entry #14.
result: [pending]

### 4. E2/long-text — Start footer at maximum text scale, plus the zero-result path
expected: At the largest OS text-scale setting the non-scrolling Start footer shows no RenderFlex overflow for its longest content — the three-or-more-topics zero-result message, and the failure row with its icon — and grows by shrinking the scroll area above rather than clipping, with the button still fully visible at its full 64px height. Then run the zero-result path end to end (e.g. Travel × C1, a deliberately empty combination): the message names both the level and the topics, no session starts, and no topic/level/slider value is lost. Ledger entry #15.
result: [pending]

### 5. E3/long-text — long prompt in the question card
expected: At maximum text scale, the seeded 324-character prompt renders un-clipped in the peach question card in the reading, recording and paused states. Supersedes Phase 2's backstop, which was written against curated placeholder constants that were all short. Ledger entry #16.
result: [pending]

### 6. D-36 offline claim — three parts
expected: |
  (a) An online-first Setup visit plus a completed session warms the SDK cache.
  (b) Airplane mode + force-stop + relaunch still shows topics and still runs a
      full session from cache.
  (c) Cleared app data while STILL OFFLINE lands on the could-not-load state
      WITH its retry button — NOT the empty state.

  Part (c) is the phase's sharpest correctness detail: a cache-served
  zero-document read must never read as "your questions are gone".
  PROJECT.md's narrowed offline requirement now claims exactly this.
  Ledger entry #17.
result: [pending]

### 7. Start-query latency — measurement, not pass/fail
expected: Measure how long the Start query takes on a real device. If it routinely exceeds ~1 s, the sanctioned response is to DISABLE the Setup form controls during the busy frame — never an overlay. The current design (tap-time config snapshot wins, controls stay interactive) is pinned by a passing host test; this item only asks whether real latency justifies revisiting it. Record the number. Ledger entry #13.
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
