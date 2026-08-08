---
status: testing
phase: 01-record-save-replay-a-single-answer-crash-safe
source: [01-VERIFICATION.md]
started: 2026-08-08T00:00:00Z
updated: 2026-08-08T00:00:00Z
---

## Current Test

number: 1
name: SC-4 / D-07 force-kill on a clean install
expected: |
  Round A: every finished answer still listed and still plays.
  Round B: the in-flight recording leaves no session row and no history entry,
  its partial .m4a is swept from disk on next launch, and Round A's answers are untouched.
awaiting: user response

## Tests

### 1. SC-4 / D-07 force-kill, on a CLEAN INSTALL of a build with the current bundle id (`com.haotran.englishreflex`)

**Delete the app from the device first.** The bundle identifier changed in commit `a07ae59`, so the app now uses a different on-device container and any force-kill result from before that commit is void.

Round A: finish 2+ answers, force-kill from the OS task switcher (not a hot restart), relaunch, open Exercise History.
Round B: force-kill *while* a recording is actively in progress, relaunch, open Exercise History.

expected: Round A — every finished answer still listed and still plays. Round B — the in-flight recording leaves no session row and no history entry, its partial `.m4a` is swept from disk on next launch, and Round A's answers are untouched.
why_human: Requires a real OS process kill; declared `verification: backstop` by plans 01-03 and 01-06.
result: [pending]

### 2. SC-2 auto-replay

Finish a recording by tapping STOP, then do not touch the screen.

expected: The answer plays back audibly with no tap, "Playing your answer…" shows during playback, then a NEW question appears with recording re-armed.
why_human: Audible playback needs speakers. The previous hang risk is closed and the wait is now bounded at 65s — a freeze at "Playing your answer…" lasting longer than ~65s would be a genuine NEW defect worth reporting.
result: [pending]

### 3. SC-3 / HIST-03 tap-to-replay

Record 2-3 answers, open Exercise History, tap a session, tap a question row. Then tap a second row while the first is still playing.

expected: Rows listed newest-first immediately; tapping plays that specific recording audibly; the second tap stops the first before starting the second.
why_human: Playback goes through the `audioplayers` platform channel. Optional extra: delete the underlying `.m4a` via a file manager and tap the row again — it should say "That recording is no longer available on this device." rather than doing nothing.
result: [pending]

### 4. SC-5 / UI-02 visual style

View the Practice and History screens in a **RELEASE build in airplane mode**, then raise the OS text size to maximum and re-check the longest question.

expected: Warm coral/peach/ivory palette, friendly mascot, and the rounded Baloo 2 face on the question and screen titles — visibly not the default Material font, even offline in release. Text reflows and scrolls at max text scale without clipping.
why_human: "Friendly, not corporate-grey" is a visual judgment. This is also the on-device confirmation of the Gap 2 font fix; the airplane-mode condition is what proves the bundled asset, not a CDN, is the load path.
result: [pending]

### 5. SC-1 / LOOP-03 leading-audio loss

On a clean first launch, answer the mic permission dialog. Then speak the instant the question appears, tap STOP after ~2s, and listen to the replay.

expected: The replay contains your very first words with no clipped opening syllable. No blank or frozen screen while the permission dialog is pending — only the question and the "Getting ready…" label.
why_human: Real microphone capture cannot run on the test host, and the honest `arming` window means leading-audio cost should be measured rather than assumed to be zero.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
