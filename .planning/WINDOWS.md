---
schema_version: 1
open_count: 15
waived_count: 0
fixed_count: 2
total_count: 17
last_updated: 2026-08-09T11:01:07.934Z
---

# Broken Windows Ledger

> Cross-phase defect register. `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 3 | unrun-verify | lib/screens/setup_screen.dart |  | Tracer human-check not run: no device attached. Confirm on a networked device that Setup shows the seeded subjects and a Travel/B1 session drills a seeded prompt. | open |  | 2026-08-09T09:23:37.905Z |  |
| 2 | 3 | unrun-verify | android/app/src/main/AndroidManifest.xml |  | D-39 merged-release-manifest inspection still owed: confirm INTERNET is the ONLY permission the Firebase dependencies added. | fixed | Discharged by plan 03-03: release APK built and the merged manifest + merger blame report read. Firebase contributed INTERNET **and** ACCESS_NETWORK_STATE (not INTERNET alone, as this entry assumed); no analytics/ads/location/account permission. | 2026-08-09T09:23:38.373Z | 2026-08-09T11:01:07.934Z |
| 3 | 3 | stub | lib/screens/setup_screen.dart | 112 | A failed subjects read leaves _subjects empty, so _NoTopics doubles as the could-not-load state (D-37 lie). Plan 02 adds setup-topics-error. | open |  | 2026-08-09T09:24:09.075Z |  |
| 4 | 3 | stub | lib/screens/setup_screen.dart | 99 | No loading state: frames before the subjects read lands render _NoTopics. Plan 02 adds setup-topics-loading. | open |  | 2026-08-09T09:24:09.541Z |  |
| 5 | 3 | stub | lib/screens/setup_screen.dart | 168 | A failed Start query makes the tap do nothing; no inline failure message. Plan 02 adds the D-38 surface. | open |  | 2026-08-09T09:24:10.069Z |  |
| 6 | 3 | stub | lib/screens/setup_screen.dart | 178 | A zero-result query makes the tap do nothing; no message naming level and topics. Plan 02 adds the D-41 message. | open |  | 2026-08-09T09:24:10.546Z |  |
| 7 | 3 | stub | lib/screens/setup_screen.dart | 157 | No busy state on START SESSION while the query runs (D-33). Plan 02 adds it. | open |  | 2026-08-09T09:24:11.057Z |  |
| 8 | 3 | stub | lib/services/firestore_question_source.dart | 140 | Malformed documents are skipped silently rather than skipped and logged. Plan 02 owns skip-and-log. | open |  | 2026-08-09T09:24:20.931Z |  |
| 9 | 3 | stub | lib/services/firestore_question_source.dart | 127 | No guard on the Firestore whereIn limit; a wide topic selection fails as a raw FirebaseException. Plan 02 makes it fail loudly. | open |  | 2026-08-09T09:24:21.607Z |  |
| 10 | 3 | stub | lib/data/questions.dart | 105 | PlaceholderQuestionSource, kQuestions and kSubjects still exist; plan 03 retires them. | fixed | Retired by plan 03-03 commit 3113406. lib/ now holds no practice prompt and no topic name; fixtures moved to test/fixtures/questions.dart. | 2026-08-09T09:24:22.236Z | 2026-08-09T11:01:07.934Z |
| 11 | 3 | deviation | analysis_options.yaml |  | build/** excluded from analysis because cloud_firestore's SwiftPM checkout puts its full Dart sources under build/macos/SourcePackages. | open |  | 2026-08-09T09:24:22.768Z |  |
| 12 | 3 | unrun-verify | lib/services/firestore_question_source.dart | 140 | Malformed-document skip-and-log is unverified on-device. The skip lives inside the deliberately non-host-testable Firestore adapter (D-47), so it can only be checked against the two deliberately malformed seeded documents (`Daily life`×B1 with no `content` field, `Travel`×A1 with whitespace-only `content`): confirm neither produces a blank checkbox row on Setup nor a blank prompt mid-session, and that each skip appears in the debug console naming its document ID. Covers UI-SPEC backstops E1/partial and E3/partial and plan 03-02's deferred human-check — one entry, not three. | open |  | 2026-08-09T11:01:07.934Z |  |
| 13 | 3 | unrun-verify | lib/screens/setup_screen.dart | 157 | Start-query on-device latency is UNMEASURED — no device was attached for plan 03-02 or 03-03. Threshold: if the Start query routinely exceeds ~1 s on a real device, the sanctioned response is to DISABLE the Setup form controls during the busy frame — never an overlay. The current design (tap-time config snapshot wins, controls stay interactive) is an explicit passing host test, but whether real latency justifies revisiting it is unknown. | open |  | 2026-08-09T11:01:07.934Z |  |
| 14 | 3 | unrun-verify | lib/screens/setup_screen.dart |  | UI-SPEC backstop E1/long-text unverified: at the largest OS text-scale setting, confirm the seeded 45-char subject `Technology, media and everyday digital habits` WRAPS and grows its 64px topic row rather than clipping, and that the topics card scrolls rather than pushing START SESSION off screen. | open |  | 2026-08-09T11:01:07.934Z |  |
| 15 | 3 | unrun-verify | lib/screens/setup_screen.dart |  | UI-SPEC backstop E2/long-text unverified: at the largest OS text-scale setting, confirm the non-scrolling Start footer shows no RenderFlex overflow for its longest content — the three-or-more-topics zero-result message, and the failure row with its icon — and grows by shrinking the scroll area above rather than clipping, with the button still fully visible at its full 64px height. Includes the zero-result path end to end: the message names both level and topic, no session starts, and no topic/level/slider value is lost. | open |  | 2026-08-09T11:01:07.934Z |  |
| 16 | 3 | unrun-verify | lib/screens/practice_screen.dart |  | UI-SPEC backstop E3/long-text unverified: at maximum text scale, confirm the seeded 324-character prompt renders un-clipped in the peach question card in the reading, recording and paused states. Supersedes Phase 2's backstop, which was written against curated placeholder constants that were all short. | open |  | 2026-08-09T11:01:07.934Z |  |
| 17 | 3 | unrun-verify | lib/services/firestore_question_source.dart |  | D-36 offline claim unverified on-device, in three parts: (a) online-first Setup visit + a completed session warms the SDK cache; (b) airplane mode + force-stop + relaunch still shows topics and still runs a full session from cache; (c) cleared app data while still offline lands on the could-not-load state WITH its retry button, NOT the empty state. Part (c) is the phase's sharpest correctness detail — a cache-served zero-document read must never read as "your questions are gone". PROJECT.md's narrowed offline requirement now claims exactly this. | open |  | 2026-08-09T11:01:07.934Z |  |

````json
[
  {
    "id": 1,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": null,
    "description": "Tracer human-check not run: no device attached. Confirm on a networked device that Setup shows the seeded subjects and a Travel/B1 session drills a seeded prompt.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:23:37.905Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "android/app/src/main/AndroidManifest.xml",
    "line": null,
    "description": "D-39 merged-release-manifest inspection still owed: confirm INTERNET is the ONLY permission the Firebase dependencies added.",
    "status": "fixed",
    "reason": "Discharged by plan 03-03: release APK built and the merged manifest + merger blame report read. Firebase contributed INTERNET and ACCESS_NETWORK_STATE (not INTERNET alone, as this entry assumed); no analytics/ads/location/account permission.",
    "recorded_at": "2026-08-09T09:23:38.373Z",
    "resolved_at": "2026-08-09T11:01:07.934Z"
  },
  {
    "id": 3,
    "kind": "stub",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": 112,
    "description": "A failed subjects read leaves _subjects empty, so _NoTopics doubles as the could-not-load state (D-37 lie). Plan 02 adds setup-topics-error.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:09.075Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "stub",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": 99,
    "description": "No loading state: frames before the subjects read lands render _NoTopics. Plan 02 adds setup-topics-loading.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:09.541Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "stub",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": 168,
    "description": "A failed Start query makes the tap do nothing; no inline failure message. Plan 02 adds the D-38 surface.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:10.069Z",
    "resolved_at": null
  },
  {
    "id": 6,
    "kind": "stub",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": 178,
    "description": "A zero-result query makes the tap do nothing; no message naming level and topics. Plan 02 adds the D-41 message.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:10.546Z",
    "resolved_at": null
  },
  {
    "id": 7,
    "kind": "stub",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": 157,
    "description": "No busy state on START SESSION while the query runs (D-33). Plan 02 adds it.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:11.057Z",
    "resolved_at": null
  },
  {
    "id": 8,
    "kind": "stub",
    "phase": "3",
    "file": "lib/services/firestore_question_source.dart",
    "line": 140,
    "description": "Malformed documents are skipped silently rather than skipped and logged. Plan 02 owns skip-and-log.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:20.931Z",
    "resolved_at": null
  },
  {
    "id": 9,
    "kind": "stub",
    "phase": "3",
    "file": "lib/services/firestore_question_source.dart",
    "line": 127,
    "description": "No guard on the Firestore whereIn limit; a wide topic selection fails as a raw FirebaseException. Plan 02 makes it fail loudly.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:21.607Z",
    "resolved_at": null
  },
  {
    "id": 10,
    "kind": "stub",
    "phase": "3",
    "file": "lib/data/questions.dart",
    "line": 105,
    "description": "PlaceholderQuestionSource, kQuestions and kSubjects still exist; plan 03 retires them.",
    "status": "fixed",
    "reason": "Retired by plan 03-03 commit 3113406. lib/ now holds no practice prompt and no topic name; fixtures moved to test/fixtures/questions.dart.",
    "recorded_at": "2026-08-09T09:24:22.236Z",
    "resolved_at": "2026-08-09T11:01:07.934Z"
  },
  {
    "id": 11,
    "kind": "deviation",
    "phase": "3",
    "file": "analysis_options.yaml",
    "line": null,
    "description": "build/** excluded from analysis because cloud_firestore's SwiftPM checkout puts its full Dart sources under build/macos/SourcePackages.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:22.768Z",
    "resolved_at": null
  },
  {
    "id": 12,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "lib/services/firestore_question_source.dart",
    "line": 140,
    "description": "Malformed-document skip-and-log is unverified on-device. The skip lives inside the deliberately non-host-testable Firestore adapter (D-47), so it can only be checked against the two deliberately malformed seeded documents (Daily life x B1 with no `content` field, Travel x A1 with whitespace-only `content`): confirm neither produces a blank checkbox row on Setup nor a blank prompt mid-session, and that each skip appears in the debug console naming its document ID. Covers UI-SPEC backstops E1/partial and E3/partial and plan 03-02's deferred human-check — one entry, not three.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T11:01:07.934Z",
    "resolved_at": null
  },
  {
    "id": 13,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": 157,
    "description": "Start-query on-device latency is UNMEASURED — no device was attached for plan 03-02 or 03-03. Threshold: if the Start query routinely exceeds ~1 s on a real device, the sanctioned response is to DISABLE the Setup form controls during the busy frame — never an overlay. The current design (tap-time config snapshot wins, controls stay interactive) is an explicit passing host test, but whether real latency justifies revisiting it is unknown.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T11:01:07.934Z",
    "resolved_at": null
  },
  {
    "id": 14,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": null,
    "description": "UI-SPEC backstop E1/long-text unverified: at the largest OS text-scale setting, confirm the seeded 45-char subject 'Technology, media and everyday digital habits' WRAPS and grows its 64px topic row rather than clipping, and that the topics card scrolls rather than pushing START SESSION off screen.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T11:01:07.934Z",
    "resolved_at": null
  },
  {
    "id": 15,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "lib/screens/setup_screen.dart",
    "line": null,
    "description": "UI-SPEC backstop E2/long-text unverified: at the largest OS text-scale setting, confirm the non-scrolling Start footer shows no RenderFlex overflow for its longest content — the three-or-more-topics zero-result message, and the failure row with its icon — and grows by shrinking the scroll area above rather than clipping, with the button still fully visible at its full 64px height. Includes the zero-result path end to end: the message names both level and topic, no session starts, and no topic/level/slider value is lost.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T11:01:07.934Z",
    "resolved_at": null
  },
  {
    "id": 16,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "lib/screens/practice_screen.dart",
    "line": null,
    "description": "UI-SPEC backstop E3/long-text unverified: at maximum text scale, confirm the seeded 324-character prompt renders un-clipped in the peach question card in the reading, recording and paused states. Supersedes Phase 2's backstop, which was written against curated placeholder constants that were all short.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T11:01:07.934Z",
    "resolved_at": null
  },
  {
    "id": 17,
    "kind": "unrun-verify",
    "phase": "3",
    "file": "lib/services/firestore_question_source.dart",
    "line": null,
    "description": "D-36 offline claim unverified on-device, in three parts: (a) online-first Setup visit + a completed session warms the SDK cache; (b) airplane mode + force-stop + relaunch still shows topics and still runs a full session from cache; (c) cleared app data while still offline lands on the could-not-load state WITH its retry button, NOT the empty state. Part (c) is the phase's sharpest correctness detail — a cache-served zero-document read must never read as 'your questions are gone'. PROJECT.md's narrowed offline requirement now claims exactly this.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T11:01:07.934Z",
    "resolved_at": null
  }
]
````
