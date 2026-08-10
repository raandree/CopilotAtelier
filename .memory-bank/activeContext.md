---
status: current
last-verified: 2026-08-10
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

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

Carry the shading Word silently drops through `pandoc-docx-export`, and repair
the changelog entry that recorded it.

## Implemented

- `Skills/pandoc-docx-export/SKILL.md` — Recipe 3 gained **Grey Shading for
  Block Quotes and Inline Code**: the `BlockText` paragraph and `VerbatimChar`
  character styles, both `w:shd` patches with print-legible fills, the optional
  left bar, and a verification snippet that counts both styles in the produced
  `word/document.xml`. Gotcha #6 records the enforced OOXML child order for
  `w:pPr` and `w:rPr`. Six triggers added to the description; the workflow step
  for the reference document updated to match.
- `CHANGELOG.md` — the new entry had replaced the `subagent-dispatch` bullet of
  2026-08-06 and absorbed its 1922-character body as its own second paragraph.
  Split back into two bullets; the restored entry is byte-identical to `HEAD`.

## Focused evidence

- Pandoc maps both constructs correctly; the loss is in the stock reference
  document, where neither style carries a fill. Nothing warns, so verification
  counts `w:val="BlockText"` and `w:val="VerbatimChar"` in the output — a style
  that fails to apply falls back to body text and looks like ordinary output.
- `w:pPr` and `w:rPr` are ordered sequences. Parsing the patched `styles.xml`
  with `[xml]` catches malformed XML but not an order violation, because
  wrongly ordered children are still well-formed. Only a headless LibreOffice
  conversion to PDF proves the file opens.
- The description now measures 1013 of 1024 characters. One more trigger
  keyword breaks the cap, and an over-cap Skill is dropped silently.
- `tests/SkillFrontmatter.Tests.ps1`: 188 passed, 0 failed, 10 skipped (the
  documented over-budget baseline, which already lists this Skill at 795 body
  lines). `markdownlint-cli2` over both changed files: 0 issues.

## Superseded focus

Close the containment gap in `subagent-dispatch`: a delegated recomputation
that can see the answer it was dispatched to reproduce. Landed as **Never hand
a re-performer the answer** — expected values go in a separate file, every
other leak is named by path, the reviewer discloses what it read, and
afterwards agreement under exposure counts weaker than disagreement.

## Superseded focus

Add an evidentiary-integrity audit for long-running case files, invoked
deliberately and run in a fresh session.

## Implemented

- `Prompts/audit-case-file.prompt.md` — read-only audit of a case file and its
  unsent drafts. Rules: project memory is a finding aid, not evidence; run in a
  fresh session because a drafting agent confirms its own conclusions; author
  and addressee are part of every claim. Six hunted error classes, five
  verification results, deadline-ordered scope, explicit "not found" finding.
  Orchestrates `citation-integrity`, `devils-advocate-review`, and the severity
  labels of `code-review-and-quality`.
- Stale Memory Bank path removed from three Prompts — `export-emails`,
  `sync-project-emails`, `deadline-action-handoff`. Thirteen occurrences, two of
  them inside hard ABORT gates that threw on every repository following
  Decision 0001. References to the Skill named `memory-bank` and the deliberate
  legacy variant in `ubiquitous-language.instructions.md` were left untouched.

## Focused evidence

- Trigger: one drafting session on a live case file checked three assertions
  against the primary corpus for the first time. One was refuted by a message
  the author had sent himself, one had been framed backwards by the assistant,
  one was attackable in wording. All three had survived because nobody had
  opened the source file since the claim was written down.
- Built as a Prompt, not a Skill: deliberately invoked, fixed procedure, single
  artefact — the analogue of `peer-review.prompt.md`. A Skill would overlap
  `citation-integrity` and degrade auto-selection for both.
- Folder roles are derived from the routing table at run time, so the Prompt
  carries no project-specific paths, route names, or facts.

## Open finding

`Prompts/export-emails.prompt.md` in this repository is a generation behind the
copy deployed under `~/.copilot/prompts/` — 106 lines against 126. The deployed
version parameterises the export script with `-PersonNames` and `-FolderSlug`,
derives patterns from email addresses as well as names, and carries a rule
forbidding hardcoded names in the prompt, in commits, and in scratch files. None
of that exists here. A build and install would therefore regress a working
Prompt. Back-porting is a content decision and was left to the owner.
- The first description measured 1237 characters against the 1024 cap the
  Copilot CLI silently enforces by dropping the Skill. Trimming the prose
  summary rather than the `USE FOR:` keywords brought it to 930, because only
  the keywords drive auto-selection.
- No `systemPatterns.md` entry was added. The Skill-versus-Custom-agent
  placement rule already lives in `Skills/skill-creator/SKILL.md` and
  `Instructions/copilot-authoring.instructions.md`, and the file sits at 96 of
  110 budgeted lines.
- `markdownlint-cli2` over the six new and edited files: 0 issues. Frontmatter
  parses through `ConvertFrom-Yaml`, the folder name matches `name`, the body is
  322 lines against the 500 budget, and all ten relative links resolve.

## Next step

The Skill has no evals. Write three real requirement fragments carrying
unquantified quality words, confirm the Skill triggers by name on the PRE-FLIGHT
line, and check that the output actually carries `Scale`, `Meter`, and a sourced
benchmark.

Still outstanding from the previous focus: add the `GitHubToken` repository
secret, without which the deploy job fails at its guard, and the macOS test leg
remains unproven until it runs green.
