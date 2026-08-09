---
status: complete
phase: 02-full-timed-practice-session-setup-loop-controls
source: [02-VERIFICATION.md]
started: 2026-08-09T04:30:00Z
updated: 2026-08-09T05:16:00Z
---

## Current Test

[testing complete]

## Tests

### 1. D-31 real-device interruption check (answered call, backgrounding, screen timeout)

On a REAL device (not an emulator), with a real SIM:

1. Start a session with answer length 60 s and begin recording an answer.
2. Call the device from another phone and ANSWER the call. Speak ~10 s, hang up.
3. Return to the app.
4. Tap RESUME and confirm the session continues from where it stopped.
5. Repeat with backgrounding instead of a call: press Home mid-recording, wait 10 s, reopen.
6. Start a session and leave the phone untouched longer than the OS screen timeout.

expected: |
  Steps 3/5: the session is parked paused, the banner reads "Paused — your answer was
  saved when the app was interrupted.", recording has NOT resumed by itself, and the
  partial answer is already in Exercise History.
  Step 4: the session continues from where it stopped, no answer replayed from the start.
  Step 6: the screen stays on for the whole session and turns off normally afterwards.
why_human: |
  Research assumption A1 — that an iOS backgrounding may suspend the isolate before the
  commit lands — is unfalsifiable on the host. The `record` package has a documented iOS
  AudioInterruptionMode rough edge (-10868). Host tests prove the handler, its ordering
  and the commit; they cannot prove the OS delivers the signal with enough runway.
  Step 5 exists specifically to settle A1. Step 6 also settles the wakelock (D-30),
  whose host test proves only that the seam is called.
result: pass

### 2. Real-microphone capture across the widened `d` range

Run a full configured session on a real device with the real microphone: set `d` to 120 s
and to 10 s, and let each auto-stop fire.

expected: Recording auto-stops at the configured `d`, the on-screen readout hits 0:00 at the same moment, and the answer is playable from History.
why_human: The `d` deadline is host-tested against a fake recorder backend. Real capture, real m4a finalization and real playback at the new 10–120 s range have never run on hardware. Phase 1 already carries device-UAT-pending on LOOP-03/LOOP-06 for the same reason; Phase 2 widens the range.
result: pass

### 3. UI-SPEC visual conformance on a real device

Visually review Setup, both countdown surfaces, the recording surface, the paused surface,
the stop dialog and the completion state against `02-UI-SPEC.md` on a real device.

expected: Colour roles, the Baloo 2 headings, the 96px ring vs the 128px glyph distinction (D-22), touch-target floors and the cartoon-like feel match the UI-SPEC.
why_human: Visual appearance, perceived distinctness of the two countdowns, and "playful/colourful" quality are not assertable by widget tests.
result: pass

### 4. Confirm the 8 judgment-tier prohibition verdicts

Review the 8 judgment-tier prohibitions listed in the Prohibitions section of
`02-VERIFICATION.md` and confirm the recorded verdicts.

expected: Each MUST-NOT is confirmed as not having happened.
why_human: unverified-prohibition — human review recommended. These prohibitions carry no `verification: test` marker and no wired negative-test enforcement, so the recorded verdicts are NON-AUTHORITATIVE LLM judgements backed by codebase evidence, never a green automated pass.
result: pass

## Summary

total: 4
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
