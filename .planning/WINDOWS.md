---
schema_version: 1
open_count: 11
waived_count: 0
fixed_count: 0
total_count: 11
last_updated: 2026-08-09T09:24:22.768Z
---

# Broken Windows Ledger

> Cross-phase defect register. `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 3 | unrun-verify | lib/screens/setup_screen.dart |  | Tracer human-check not run: no device attached. Confirm on a networked device that Setup shows the seeded subjects and a Travel/B1 session drills a seeded prompt. | open |  | 2026-08-09T09:23:37.905Z |  |
| 2 | 3 | unrun-verify | android/app/src/main/AndroidManifest.xml |  | D-39 merged-release-manifest inspection still owed: confirm INTERNET is the ONLY permission the Firebase dependencies added. | open |  | 2026-08-09T09:23:38.373Z |  |
| 3 | 3 | stub | lib/screens/setup_screen.dart | 112 | A failed subjects read leaves _subjects empty, so _NoTopics doubles as the could-not-load state (D-37 lie). Plan 02 adds setup-topics-error. | open |  | 2026-08-09T09:24:09.075Z |  |
| 4 | 3 | stub | lib/screens/setup_screen.dart | 99 | No loading state: frames before the subjects read lands render _NoTopics. Plan 02 adds setup-topics-loading. | open |  | 2026-08-09T09:24:09.541Z |  |
| 5 | 3 | stub | lib/screens/setup_screen.dart | 168 | A failed Start query makes the tap do nothing; no inline failure message. Plan 02 adds the D-38 surface. | open |  | 2026-08-09T09:24:10.069Z |  |
| 6 | 3 | stub | lib/screens/setup_screen.dart | 178 | A zero-result query makes the tap do nothing; no message naming level and topics. Plan 02 adds the D-41 message. | open |  | 2026-08-09T09:24:10.546Z |  |
| 7 | 3 | stub | lib/screens/setup_screen.dart | 157 | No busy state on START SESSION while the query runs (D-33). Plan 02 adds it. | open |  | 2026-08-09T09:24:11.057Z |  |
| 8 | 3 | stub | lib/services/firestore_question_source.dart | 140 | Malformed documents are skipped silently rather than skipped and logged. Plan 02 owns skip-and-log. | open |  | 2026-08-09T09:24:20.931Z |  |
| 9 | 3 | stub | lib/services/firestore_question_source.dart | 127 | No guard on the Firestore whereIn limit; a wide topic selection fails as a raw FirebaseException. Plan 02 makes it fail loudly. | open |  | 2026-08-09T09:24:21.607Z |  |
| 10 | 3 | stub | lib/data/questions.dart | 105 | PlaceholderQuestionSource, kQuestions and kSubjects still exist; plan 03 retires them. | open |  | 2026-08-09T09:24:22.236Z |  |
| 11 | 3 | deviation | analysis_options.yaml |  | build/** excluded from analysis because cloud_firestore's SwiftPM checkout puts its full Dart sources under build/macos/SourcePackages. | open |  | 2026-08-09T09:24:22.768Z |  |

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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:23:38.373Z",
    "resolved_at": null
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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-09T09:24:22.236Z",
    "resolved_at": null
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
  }
]
````
