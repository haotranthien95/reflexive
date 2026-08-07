# Feature Research

**Domain:** Spoken-language reflex/speaking-drill apps (interview-prep timer + shadowing-adjacent, single-user, non-gamified)
**Researched:** 2026-08-07
**Confidence:** MEDIUM (project scope and mechanics are well-specified in PROJECT.md; competitive feature patterns are LOW-confidence web-search-derived and used only to sanity-check, not to drive new scope)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist in *any* record-and-review speaking-practice tool. Missing these makes the app feel broken, not just "lean."

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Configurable practice session (topic, count, timing) before starting | Every reviewed app (Big Interview, ELSA, mock-interview tools) lets the user scope a session before diving in — an un-configurable fixed drill feels rigid | LOW | Already in PROJECT.md active requirements (topics, level, count, `t`, `d`, `r`) |
| Visible countdown before recording starts | "Think time" before forced speech is the entire premise of reflex/interview drilling (mirrors Big Interview's per-question prep beat) — without it, recording feels like it ambushes the user | LOW | Already speced: 3s countdown |
| Auto-stop recording at a max duration | Prevents runaway recordings and forces the "reflex" constraint; every timed-interview tool caps answer length | LOW | Already speced (`d`s max) |
| Manual stop control | Users finish early often; forcing them to wait for auto-stop every time is a top complaint pattern in timer-based recording tools | LOW | Already speced (large stop button) |
| Playback of what you just said (immediate replay) | This is the single most requested feature across all reviewed apps ("record → review" is the core loop of Big Interview, shadowing apps, and voice-coaching apps alike) — a recording tool with no way to hear yourself has no value proposition | LOW–MED | Already speced as `r` toggle; recommend defaulting `r` to true since replay-less recording tools score worst in user feedback across the category |
| Pause / resume mid-session | Real-world interruptions (calls, distractions) are common during any recording session; abrupt session death on backgrounding is a frequently cited frustration in recording-app reviews | MEDIUM | Already speced; must persist state so resume doesn't lose recorded answers |
| Confirm-before-stop / exit | Losing an in-progress session to a mis-tap is a classic complaint in timed-practice tools; a lightweight confirm dialog is industry-standard, not overbuilt | LOW | Already speced |
| Session history list | Every reviewed tool (Big Interview's saved answers, ELSA's session history, shadowing apps' recording library) treats "what did I do before" as core, not optional — practice without a record of practice is disposable | LOW–MED | Already speced |
| Per-question recording playback inside history | Big Interview specifically calls out "record & review" per answer as its headline feature; users expect to jump to a specific past answer, not just see aggregate stats | LOW–MED | Already speced |
| Incremental/crash-safe persistence during a session | Not common as a marketed feature in competitor apps, but it's the direct consequence of table-stakes #5-7 above — if playback and resume are expected, silent data loss on crash breaks both | MEDIUM | Already speced as a reliability requirement; this is *this project's* version of "don't lose the user's data," equivalent to competitors' cloud-autosave but done locally |
| Bulk / seeded content so the app isn't empty on first run | Apps with an empty question bank at first launch have a well-documented "cold start" abandonment problem; ~10 seed topics addresses this | LOW | Already speced |

**Read on PROJECT.md:** all table-stakes items above are already covered by the Active requirements — this project's scope is correctly calibrated to table stakes for this specific sub-category (reflex-drill, not full platform). No additions needed to the Active requirements list.

### Differentiators (Competitive Advantage — Note, Don't Build Now)

These aren't required for this app to feel complete, but they're where competitor apps in this space compete, and worth flagging as intentional backlog/v2 candidates so they aren't accidentally treated as "missing basics" later.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Pronunciation/fluency scoring (pace, filler-word count, confidence score) | This is the #1 differentiator across ELSA, Speeko, and Yoodli — it's literally what they charge subscriptions for | HIGH | Explicitly out of scope per PROJECT.md. Correct call: it requires ML/speech APIs, ongoing accuracy tuning, and shifts the product from "drill tool" to "coach," which is a different value proposition and a much bigger app |
| Playback speed control / loop-a-segment on recordings | Shadowing apps treat 0.5x–2x speed and segment looping as core; useful for a learner re-listening to catch their own mistakes | MEDIUM | Worth a v1.x backlog note — cheap to add once basic playback exists (most Flutter audio players expose a speed parameter), but not needed for MVP validation |
| Streaks / progress stats (sessions this week, avg answer length trend) | Common retention hook in gamified apps (Duolingo-style), and even non-gamified tools like Speeko show a "report card" trend over time | MEDIUM | Explicitly the kind of feature the user is avoiding ("not Duolingo-style"); flag as v2 only if user later wants motivation/retention features |
| Re-recording a specific past question (retry without starting a whole new session) | Big Interview and shadowing apps both let users redo a single answer, useful for isolated practice of a weak topic | LOW–MED | Natural v1.x add — reuses existing record/playback code, doesn't need new architecture, but adds a session-model wrinkle (does a retry create a new history entry or overwrite?) so it's better decided post-MVP with real usage data |
| Random/shuffle question selection within a topic | Competitor tools like Yoodli lean on "randomized prompts" specifically to prevent rehearsed, memorized answers — which reinforces genuine reflex speaking | LOW | Cheap differentiator; consider even for v1 since it's nearly free (query order) and directly reinforces the "reflex" core value — recommend as a fast-follow, not a hard requirement |
| Export/share a recording or session summary | Not core to a personal drill tool, but common once users want to send a sample to a tutor or friend for feedback | MEDIUM | Explicitly conflicts with "local-only, no social features" positioning — defer indefinitely unless requested |
| Adaptive difficulty (level auto-adjusts based on performance) | Speeko's headline mechanic; requires performance measurement first (which requires scoring, which is out of scope) | HIGH | Blocked on scoring feature being out of scope — don't consider until/unless scoring is revisited |

### Anti-Features (Commonly Over-Built in This App Category — Deliberately Skip)

Patterns this category of app (speaking practice / interview prep / shadowing tools) commonly drifts into that would violate this project's "leanest possible" philosophy. These reinforce the Out-of-Scope list already in PROJECT.md and add a few category-specific traps to watch for during implementation.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| AI/ML pronunciation or fluency scoring | "Competitors all have it, feels incomplete without a score" | Requires a speech-analysis backend or on-device ML model, ongoing tuning, and turns a 2-week drill tool into an open-ended ML product; also directly contradicts PROJECT.md's stated non-goal | Recording + playback lets the user self-assess by listening back — sufficient for the stated core value |
| User accounts / login (even "just in case") | "Every app has auth, seems standard" | Adds a whole auth/session-management subsystem, password/security surface, and a backend dependency for a single-device, single-user tool | Device-local data is sufficient; if multi-device is ever needed later, that's a distinct future milestone, not a v1 default |
| Cloud sync / backup of recordings | "What if they lose their phone?" | Pulls in Firebase Storage costs, upload reliability handling, and conflict resolution — none of which is requested; the recording data is exactly the kind of large-binary data that's expensive to sync | Local storage only, as already decided; user can manually back up their device if desired |
| Push notifications / streak reminders | Standard retention pattern in language apps; "keeps users engaged" | Adds notification permission flows, scheduling logic, and a nagging quality that contradicts "not Duolingo-style" positioning | None needed — this is a self-directed practice tool the user opens when they choose to |
| Rich analytics dashboard (charts, trend graphs, per-topic breakdowns) | "Users like seeing progress over time" | Requires aggregation logic, chart libraries, and a whole screen of derived-data UI for a single user who can already scroll their own history | The flat history list already answers "what did I practice and how did it go" — defer charts until/unless requested |
| Admin/CMS screen for managing the question bank inside the app | "Easier than editing Firestore/JSON by hand" | Duplicates Firestore console functionality inside the app; adds CRUD screens, validation, and edit-state management for a maintenance task that happens rarely and is already solved by direct Firestore edits + JSON import | JSON import (already speced) + direct Firestore console access covers all bank-management needs for a solo user |
| Multiple concurrent recording formats / cloud transcoding | "Better audio quality/compatibility" | Solves a problem that doesn't exist yet for a single local device/user; adds real complexity (codec choice, transcoding pipeline) for a feature no one asked for | Pick one audio format the chosen recording package outputs by default and ship it |
| Social features (sharing, leaderboards, comparing with friends) | "Increases engagement in most apps" | Requires backend infrastructure (user identity, feeds, moderation) entirely orthogonal to a solo drill tool; explicitly ruled out in PROJECT.md | None — not aligned with stated single-user goal |
| Speculative "future-proof" abstraction layers (e.g., a generic plugin system for question types, or a multi-language i18n scaffold before it's needed) | "Makes it easier to extend later" | Directly contradicts the user's stated "leanest possible... avoid speculative abstractions" instruction; premature abstraction is the single most common way small Flutter apps balloon in code volume | Build the concrete English-only, fixed-question-shape version now; refactor only when/if multi-language is actually requested |

## Feature Dependencies

```
Session Setup (topics/level/count/timers)
    └──requires──> Question Bank in Firestore (with distinct `subject` values)
                       └──enhanced-by──> JSON Import (bulk-add questions)

Practice Loop (countdown → record → auto-stop → replay → next)
    └──requires──> Session Setup (needs t, d, r, question_count as inputs)
    └──requires──> Local Audio Recording capability
    └──requires──> Incremental local persistence (write-as-you-go)

Pause/Resume/Stop-with-confirm
    └──requires──> Practice Loop (attaches to the same session state machine)

Exercise History (list + per-question playback)
    └──requires──> Incremental local persistence (history is built from what's saved during the loop)
    └──requires──> Local Audio Recording (playback needs the saved audio files)

Re-record a single past question [DIFFERENTIATOR, deferred]
    └──requires──> Exercise History (needs a specific past question to target)
    └──requires──> Practice Loop's record/auto-stop mechanics (reuses them)

Pronunciation/fluency scoring [ANTI-FEATURE / OUT OF SCOPE]
    └──would require──> Speech-analysis backend or on-device ML (not in current stack)
    └──conflicts with──> "leanest possible" philosophy and explicit Out-of-Scope decision

Streaks/analytics dashboard [ANTI-FEATURE / OUT OF SCOPE]
    └──conflicts with──> "not Duolingo-style" positioning stated in research question
```

### Dependency Notes

- **Practice Loop requires Session Setup:** the loop's countdown length, max recording duration, question count, and replay behavior are all configured upstream in setup — the loop cannot run without these parameters, so setup must ship (at least a minimal/default version) before or alongside the loop.
- **Practice Loop requires incremental local persistence:** because history and crash-recovery both depend on data being written question-by-question (not buffered to session end), the persistence layer is a hard prerequisite for the loop being "safe," not a nice-to-have added after.
- **Exercise History requires the same persistence layer as the Practice Loop:** these two features should share one local data model — history is literally "read what the loop already wrote," so building them as separate data paths would be the kind of duplicated-effort abstraction this project is trying to avoid.
- **JSON Import enhances but does not block Session Setup:** the app can launch with only the ~10 seeded topics; import is an enhancement path for growing the question bank, not a blocking dependency for the core loop to work.
- **Re-record (differentiator) requires History to exist first:** there's no "past question" to re-record until history is in place, so this is correctly sequenced as a v1.x addition, not parallel v1 work.
- **Scoring/streaks/analytics conflict with the stated MVP philosophy:** these aren't just "later" features — building them would require infrastructure (ML inference, aggregation logic) that has no other use in this app, so they should be treated as explicitly rejected rather than merely deferred, unless the user's goals change.

## MVP Definition

### Launch With (v1)

Minimum viable product — matches PROJECT.md's Active requirements exactly; no additions recommended by this research.

- [ ] Session setup screen (topics, level, count, countdown `t`, max duration `d`, replay toggle `r`) — without this, the practice loop has no parameters to run on
- [ ] Practice loop (countdown → record → auto-stop → optional replay → next) — this is the entire core value proposition
- [ ] Pause/Resume/Stop with confirm — table stakes for any timed recording tool; prevents accidental data loss
- [ ] Incremental local persistence (write-as-you-go) — required for both crash-safety and history to work correctly
- [ ] Exercise history with per-question playback — the "always go back and listen" half of the stated Core Value
- [ ] Question bank in Firestore + JSON import — required to have content to practice with, and to grow the bank without an in-app admin screen

### Add After Validation (v1.x)

Features to add once the core loop is proven to work well in daily use.

- [ ] Shuffle/random question order within a topic — trigger: user reports sessions feel repetitive or memorized after using seeded content for a while
- [ ] Re-record a single past question from history — trigger: user wants to retry a specific weak answer without starting a whole new session
- [ ] Playback speed control on recordings — trigger: user wants to self-review more critically, common ask once they've accumulated real history to listen back to

### Future Consideration (v2+)

Features to defer indefinitely unless the project's goals explicitly change.

- [ ] Any form of pronunciation/fluency AI scoring — defer because it's a different product category (coaching tool, not drill tool) and was explicitly ruled out
- [ ] Streaks, reminders, gamification — defer because it contradicts the stated "not gamified" positioning
- [ ] Cloud sync, accounts, social features, admin dashboard — defer indefinitely per PROJECT.md's explicit Out of Scope list; only revisit if the single-user, local-only premise itself changes

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Session setup (topics/level/count/timers) | HIGH | LOW | P1 |
| Practice loop (countdown/record/auto-stop/replay) | HIGH | MEDIUM | P1 |
| Pause/Resume/Stop with confirm | HIGH | LOW–MEDIUM | P1 |
| Incremental local persistence | HIGH | MEDIUM | P1 |
| Exercise history + per-question playback | HIGH | MEDIUM | P1 |
| Firestore question bank + JSON import | HIGH | LOW–MEDIUM | P1 |
| Shuffle/random question order | MEDIUM | LOW | P2 |
| Re-record a single past question | MEDIUM | MEDIUM | P2 |
| Playback speed control | LOW–MEDIUM | LOW–MEDIUM | P3 |
| Pronunciation/fluency scoring | MEDIUM (would be HIGH if in scope) | HIGH | Rejected |
| Streaks/analytics dashboard | LOW (contradicts stated positioning) | MEDIUM–HIGH | Rejected |
| Accounts/cloud sync/social/admin dashboard | LOW (explicitly not wanted) | HIGH | Rejected |

**Priority key:**
- P1: Must have for launch (= PROJECT.md's current Active requirements)
- P2: Should have, add when possible post-validation
- P3: Nice to have, future consideration
- Rejected: Deliberately out of scope per this project's philosophy — not a priority tier, a decision

## Competitor Feature Analysis

| Feature | ELSA Speak / Speeko (AI coaching apps) | Big Interview / Yoodli (interview prep) | Shadowing apps (NDTD, ShadowEcho) | Our Approach |
|---------|----------------------------------------|-------------------------------------------|--------------------------------------|--------------|
| Session configuration | Fixed lesson paths, less user-configurable | Question bank browsing, some customization | Content selection (video/audio source) | Fully user-configurable setup screen (topics, level, count, timings) — more flexible than most competitors since this is a drill tool, not a curriculum |
| Recording mechanic | Prompt → record → AI analysis | Prompt → prep time → record → review | Play source → record alongside → compare | Countdown → forced record → auto-stop — closest to Big Interview's model, without the AI analysis step |
| Feedback after recording | AI-generated score/report (core paid feature) | AI or self/coach review | Waveform/audio comparison, sometimes AI pronunciation feedback | None — self-review via playback only (explicit non-goal for scoring) |
| History/review | Session history tied to progress dashboard | Saved recorded answers, replayable | Recording library per source file | Flat session history list with per-question playback — simpler than competitors' dashboards, matches "leanest possible" |
| Content management | Managed by vendor (curated lesson content) | Managed by vendor (curated question bank) | User supplies source video/audio | Firestore-hosted bank + JSON import — solo-maintainable, no admin UI needed |
| Monetization/retention hooks | Subscription + streaks + adaptive difficulty | Subscription + training curriculum | Freemium + content library | None — single-user personal tool, no retention mechanics needed |

## Sources

- [ELSA Speak - App Store](https://apps.apple.com/us/app/elsa-speak-english-learning/id1083804886)
- [Best Speech Coaching Apps for English Fluency in 2025 - Hyperbound](https://www.hyperbound.ai/blog/best-speech-coaching-apps)
- [Best App for Public Speaking in 2026 - Wellspoken](https://www.wellspoken.me/blog/best-app-for-public-speaking)
- [9 Best Apps to Improve Communication Skills (2026) - Articulated](https://articulated.app/blog/best-speech-coaching-apps-2026)
- [7 Best AI Speech Coaching Apps in 2026 - Speakio](https://www.speakio.ai/blog/7-best-ai-speech-coaching-apps-in-2026)
- [Big Interview - UCI Career Center](https://career.uci.edu/resource/big-interview)
- [Google Interview Warmup Is Gone: 8 Best Alternatives (2026) - Skillora](https://skillora.ai/blog/interview-warmup-alternatives)
- [Best AI Mock Interview Tools for Jobseekers in 2026 - Articuler](https://www.articuler.ai/resources/compare/best-ai-mock-interview-tools/)
- [12 Best AI Mock Interview Tools in 2026 - FavTutor](https://favtutor.com/best-ai-mock-interview-tools-2026/)
- [NDTD Language Shadower - App Store](https://apps.apple.com/us/app/ndtd-language-shadower/id6744872799)
- [Shadowing Language Practice - App Store](https://apps.apple.com/vn/app/shadowing-language-practice/id6767460015)
- [ShadowEcho — YouTube Shadowing Practice - Chrome Web Store](https://chromewebstore.google.com/detail/shadowing-practice-loop-%E2%80%93/fcjnmenfbppibcdhoobcpjnfpklimlpc)
- [Speak Pro: Shadowing Lessons](https://speakpro.app/)
- [Scope Creep in Software Development - Medium](https://medium.com/coffee-software/scope-creep-in-software-development-16fc735a7998)
- [How to avoid scope creep and other software design lessons - freeCodeCamp](https://www.freecodecamp.org/news/scope-creep-and-other-software-design-lessons-learned-the-hard-way-edacf021965b/)
- Confidence note: all web sources above are general search-derived (LOW confidence per this project's source hierarchy); used only to cross-check that PROJECT.md's existing scope is well-calibrated, not to introduce new requirements. Highest-confidence input to this document is PROJECT.md itself (explicit user requirements and stated Out of Scope list).

---
*Feature research for: Spoken-English reflex speaking-drill app (Flutter, single-user, local-first)*
*Researched: 2026-08-07*
