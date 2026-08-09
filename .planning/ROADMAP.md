# Roadmap: EnglishReflex

## Overview

EnglishReflex ships as four vertical slices, each a fully demoable capability. Phase 1 proves the highest-risk requirement first — recording, replaying, and crash-safely persisting a single answer — before any looping or configuration complexity exists. Phase 2 wraps that proven primitive into the full timed reflex-drill mechanic (countdown → record → auto-stop → replay → next-question) across a configurable, multi-question session with pause/resume/stop controls, using placeholder topic data so the loop can be built and tested independently of Firebase. Phase 3 swaps that placeholder data for the real Firestore-backed question bank. Phase 4 adds the bulk JSON import path, seeds the bank with starter content, and confirms the app's navigation footprint stays to exactly three screens. By the end of Phase 4, every v1 requirement is delivered and the app is usable end-to-end for real practice.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Record, Save & Replay a Single Answer (Crash-Safe)** - Prove the core record → save-immediately → replay → history loop survives an app kill before any looping or setup complexity is added (completed 2026-08-08)
- [x] **Phase 2: Full Timed Practice Session (Setup, Loop & Controls)** - Wrap the proven recording primitive into a configurable, multi-question timed drill with pause/resume/stop-with-confirm (completed 2026-08-09)
- [ ] **Phase 3: Real Question Bank via Firestore** - Replace placeholder topic/question data with the live Firestore-backed question bank
- [ ] **Phase 4: Bulk Import, Seed Content & Screen Polish** - Add JSON bulk import, seed ~10 starter topics, and confirm the app stays to exactly 3 screens

## Phase Details

### Phase 1: Record, Save & Replay a Single Answer (Crash-Safe)

**Goal**: User can answer a practice question by recording their voice, have it saved to local storage the instant it's captured, replay it, and find it in an Exercise History list — and none of that is lost if the app is force-killed mid-use.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: LOOP-03, LOOP-04, LOOP-05, LOOP-06, PERSIST-01, PERSIST-02, HIST-01, HIST-02, HIST-03, HIST-04, UI-01, UI-02
**Success Criteria** (what must be TRUE):

  1. Recording an answer starts automatically and a large, always-visible stop button can end it early; if not stopped manually it auto-stops after the configured max duration.
  2. If auto-replay is enabled, the just-recorded answer plays back automatically the moment recording stops.
  3. Every recorded answer appears immediately in an Exercise History list; tapping an entry plays its recording.
  4. Force-killing the app mid-use and relaunching still shows every already-recorded answer in history — nothing captured before the crash is lost.
  5. The recording and history screens use large, easily readable text and a simple, colorful, friendly visual style (not corporate/minimal-grey).

**Plans**: 6/6 plans executed
Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Walking Skeleton: scaffold, persistence, and the record→save→replay→history loop
- [x] 01-04-PLAN.md — Gap closure: every practice phase has a way forward (arming state, guarded failure paths, first RecordingService tests)
- [x] 01-05-PLAN.md — Gap closure: Baloo 2 actually ships in a release build (bundled asset, runtime fetching off)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Visual & typography system (warm palette, Baloo 2, mascot)
- [x] 01-06-PLAN.md — Gap closure: history never presents a read failure as missing data, plus requirement-tracking reconciliation

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-03-PLAN.md — Crash-safety hardening (error handling, FK enforcement, D-07 force-kill test)

**UI hint**: yes

### Phase 2: Full Timed Practice Session (Setup, Loop & Controls)

**Goal**: User can configure a complete practice session (level, question count, timings, replay toggle) and run it through the full timed reflex-drill loop across multiple questions, with pause/resume and stop-with-confirmation available at all times.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: SETUP-02, SETUP-03, SETUP-04, SETUP-05, SETUP-06, SETUP-07, LOOP-01, LOOP-02, LOOP-07, LOOP-08, CTRL-01, CTRL-02, CTRL-03, CTRL-04
**Success Criteria** (what must be TRUE):

  1. User can configure a session — CEFR level, question count (1-100), pre-record countdown `t`, max recording duration `d`, and auto-replay toggle `r` — and Start is disabled unless setup is valid.
  2. Starting a session shows a 3-second countdown, then each question displays with a live `t`-second countdown before recording begins, followed by a 3-second countdown into the next question after each answer.
  3. The session automatically completes once the configured `question_count` has been answered.
  4. An app bar with Pause/Resume and Stop is visible throughout the session; pausing freezes the current countdown/recording state, and tapping Stop requires confirmation before the session ends early.

**Plans**: 5/5 plans executed
Plans:
**Wave 1**

- [x] 02-01-PLAN.md — Tracer: a configured session runs one question end to end (Setup → 3·2·1 → `t` → record at `d` → one durable answer → completion), plus the promoted N-answer write path

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — The full N-question loop: replay gate, inter-question countdown, automatic completion, bank cycling, and both countdown surfaces
- [x] 02-03-PLAN.md — Setup screen complete: CEFR chips, the three numeric readout+slider settings, and the auto-replay toggle

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-04-PLAN.md — Pause/Resume: one confirmed freeze across the recorder, every countdown and the replay timeout

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-05-PLAN.md — Stop with confirmation, back-gesture interception, session wakelock, and interruption handling

**UI hint**: yes

### Phase 3: Real Question Bank via Firestore

**Goal**: Session setup and the practice loop run on the real Firestore-backed question bank instead of placeholder data — topics are derived from actual `subject` values, and only matching questions are fetched per session.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: BANK-01, BANK-02, BANK-03, SETUP-01
**Success Criteria** (what must be TRUE):

  1. The topic checkboxes in Setup are populated from the distinct `subject` values actually present in the Firestore question bank (schema `{id, content, subject, level, created_at}`).
  2. Starting a session fetches only the questions matching the selected topics and CEFR level from Firestore.

**Plans**: 2/3 plans executed
Plans:
**Wave 1**

- [x] 03-01-PLAN.md — Tracer: a real seeded Firestore bank, real topics on Setup, and a real filtered query feeding the loop

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — Every read outcome told honestly: the four topics-card states, the three Start-button states, and adapter hardening

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 03-03-PLAN.md — Retire the placeholder bank, write down the network/offline and open-rules tradeoffs, and discharge the on-device checks

**UI hint**: yes

### Phase 4: Bulk Import, Seed Content & Screen Polish

**Goal**: The question bank can be grown via bulk JSON import from within the app, ships with seed content so it's never empty on first run, and the app's navigation is confirmed to be exactly the 3 core screens with nothing extraneous.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: IMPORT-01, IMPORT-02, IMPORT-03, IMPORT-04, IMPORT-05, UI-03
**Success Criteria** (what must be TRUE):

  1. User can pick a local JSON file matching the `{"data": [{"content": "...", "subject": "...", "level": "..."}, ...]}` format and import it into the Firestore bank, with `id` and `created_at` auto-generated per question.
  2. Import reports success/failure per row rather than failing silently or partially.
  3. On first run, the question bank already contains ~10 general-purpose seeded topics so Setup is never empty.
  4. The app has exactly 3 core screens (Setup, Practice Session, History) with no extraneous navigation.

**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Record, Save & Replay a Single Answer (Crash-Safe) | 6/6 | Complete    | 2026-08-08 |
| 2. Full Timed Practice Session (Setup, Loop & Controls) | 5/5 | Complete    | 2026-08-09 |
| 3. Real Question Bank via Firestore | 2/3 | In Progress|  |
| 4. Bulk Import, Seed Content & Screen Polish | 0/TBD | Not started | - |
