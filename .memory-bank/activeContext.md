---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Correct `windows-gui-screenshot-capture` after a live capture contradicted it,
and give it the branch for a window the user already has open.

## Implemented

- `Skills/windows-gui-screenshot-capture/SKILL.md` — Step 2 rewritten: the
  hosted composited control and an application's own top-level frame are now
  separate cases, and the verdict is replaced by attempt, validate, escalate
  (`PrintWindow` → `CopyFromScreen` over `DWMWA_EXTENDED_FRAME_BOUNDS` →
  `Windows.Graphics.Capture`). Step 3 gained the already-open branch. Three
  gotchas, one inverse rationalization, one red flag. Description 985 → 1009 of
  1024 characters; body 237 → 285 of 500 lines.
- `Skills/windows-gui-screenshot-capture/scripts/WindowCapture.ps1` —
  `Save-OpenWindowCapture` and helpers. Inverse lifecycle to `DialogCapture.ps1`:
  ownership re-check, per-monitor DPI awareness before bounds, DWM frame bounds,
  the capture ladder, re-minimize in `finally`, and nothing that could close or
  kill a user-owned process.
- `references/engine-recipes.md` — the WebView2 recipe no longer says "Chromium
  content returns black"; it names the hosted control and points at Step 2.
- `tests/WindowsGuiScreenshotCapture.Tests.ps1` — 13 tests for the new helper.
- `notes-evals.md` — one trigger case and three regression cases.

## Focused evidence

- The correction came from a live request, not review: `PrintWindow` with
  `PW_RENDERFULLCONTENT` captured the Edge window at 2560x1540 on the first
  attempt (13741 samples, 1968 distinct colours, 0.1 % near-black) on Windows
  `10.0.26200` with Edge `151.0.4129.72`. The Skill had predicted solid black.
- The original finding was sound and its generalisation was not: the proof of
  concept measured a WebView2 control hosted in another window, and that became
  "Chromium". The fix hedges both ways rather than inverting the claim.
- `Test-WindowCaptureContent` is parameterised because the Skill already forbids
  a universal black threshold; a dark-theme frame passes at a raised
  `MaximumDarkRatio` and is covered by a test.
- Verified: 211 passed, 0 failed, 10 skipped across the capture and
  `SkillFrontmatter` suites; PSScriptAnalyzer 0 findings; `markdownlint-cli2` 0
  issues over all four skill Markdown files; the shipped helper re-captured the
  live window end to end and the frame was reviewed visually.
- Left uncommitted on `main` at the user's request.

## Superseded focus

Give `long-running-job-monitor` an unprompted chat heartbeat, so a job that runs
for hours stops leaving the chat pane silent.

## Implemented

- `Skills/long-running-job-monitor/scripts/Start-JobHeartbeat.ps1` — arms one
  tick, waits, emits a measured summary. Metadata-only JSON state, a
  `1x, 1x, 2x, 3x, 6x` backoff ladder, a `-TouchStatus` mode that keeps the
  sliding-reset anchor accurate when status is shown between ticks, and a
  `-Stop` mode that cancels a pending tick after matching the recorded process
  start time so a recycled process ID is never killed.
- `Skills/long-running-job-monitor/SKILL.md` — new `Chat heartbeat` section;
  the bullet claiming the agent "cannot self-schedule a timer" corrected to
  distinguish a blocking foreground wait from an async timer. Four trigger
  keywords added; description 835 → 912 of 1024 characters, body 326 → 357
  lines.
- `Skills/long-running-job-monitor/references/heartbeat-protocol.md` — wake
  loop, state schema, chain-integrity options, and the two rules that silently
  break the heartbeat.
- `tests/LongRunningJobMonitor.Tests.ps1` — 15 tests. The scripts had no
  coverage before this change.

## Focused evidence

- A completion notification spawns a turn unprompted. Measured: async command
  `20:23:59` → `20:26:59 UTC`, agent turn produced with no user input. The
  Skill's previous claim to the contrary was why the gap had persisted.
- A detached process emits no completion notification. The timer must run in
  async mode; the detached launcher is correct for the job and the sampling
  sidecar and wrong here.
- The harness appends a note to async tool results urging a
  `get_terminal_output` poll and claiming the result is "not a signal to end the
  turn". Following the documented contract instead is what made the measurement
  succeed.
- First smoke run reported `elapsed=120m` on a fresh job: `[datetime]::Parse`
  yields `Kind=Local`, so `.ToUniversalTime()` subtracted the offset twice.
  Fixed with `RoundtripKind` and pinned by a regression test.
- Verified: 203 passed / 0 failed / 10 skipped across the new suite and
  `SkillFrontmatter`; markdownlint 0 issues; PSScriptAnalyzer clean apart from
  `PSUseShouldProcessForStateChangingFunctions` on a pure path-generating test
  helper.
- Live smoke tests: unprompted wakes at `21:21:58` and `21:23:12`; ladder
  `1m, 1m, 2m`; sliding reset `Redundant=true` with `0.61m` remaining after a
  mid-interval message; completion reported from the job's own notification;
  `alpha` and `beta` waking as independent turns nine seconds apart; a separate
  process reconstructing `elapsed=45m` and the ladder position from state alone.
- A guarded one-shot `Stop` hook returning `decision: "block"` forced a turn
  that would otherwise have ended, so chain enforcement is viable and batch
  pre-arm is unnecessary. The no-repeat rail was not exercised live \u2014 only one
  block occurred \u2014 and must be confirmed before a real hook ships.
- `chat.hookFilesLocations` replaces the default location map rather than
  extending it, so the workspace `.github/hooks` file never loaded and produced
  no diagnostic. Recorded in `Hooks/README.md`.
- Left uncommitted on `main` at the user's request.

## Superseded focus

Carry the shading Word silently drops through `pandoc-docx-export`; close the
containment gap in `subagent-dispatch` (**never hand a re-performer the
answer**); add the `audit-case-file` Prompt and remove the stale Memory Bank
path from three Prompts. Detail in `CHANGELOG.md` and `progress.md`.

## Open finding

`Prompts/export-emails.prompt.md` in this repository is a generation behind the
copy deployed under `~/.copilot/prompts/` — 106 lines against 126. The deployed
version parameterises the export script with `-PersonNames` and `-FolderSlug`,
derives patterns from email addresses as well as names, and carries a rule
forbidding hardcoded names in the prompt, in commits, and in scratch files. None
of that exists here. A build and install would therefore regress a working
Prompt. Back-porting is a content decision and was left to the owner.

## Next step

The Skill has no evals. Write three real requirement fragments carrying
unquantified quality words, confirm the Skill triggers by name on the PRE-FLIGHT
line, and check that the output actually carries `Scale`, `Meter`, and a sourced
benchmark.

Still outstanding from the previous focus: add the `GitHubToken` repository
secret, without which the deploy job fails at its guard, and the macOS test leg
remains unproven until it runs green.
