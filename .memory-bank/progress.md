---
status: current
last-verified: 2026-07-30
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is released at `v1.1.0`. The next release is `2.0.0`, the first
published to the PowerShell Gallery. Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-08-11**: Corrected `windows-gui-screenshot-capture`, prompted by a live
  "screenshot the Edge window" request the Skill answered wrongly twice. Its
  "GPU-composited content returns solid black" verdict had generalised a
  measurement of a hosted WebView2 control to all of Chromium; measured on
  Windows `10.0.26200` with Edge `151.0.4129.72`, `PW_RENDERFULLCONTENT`
  painted a full 2560x1540 frame on the first attempt. Step 2 now separates a
  hosted control from an application's own top-level frame and prescribes
  attempt, validate, escalate. The Skill also had no branch for a window the
  user already had open, where nothing may be launched or closed;
  `scripts/WindowCapture.ps1` implements it as the inverse-lifecycle sibling of
  `DialogCapture.ps1`, with 13 new tests.

- **2026-08-10**: `long-running-job-monitor` gained an unprompted chat
  heartbeat. Measured that an async command's completion notification spawns an
  agent turn with no user input, disproving the Skill's own claim that the agent
  cannot self-schedule. `Start-JobHeartbeat.ps1` arms one tick and emits a
  measured summary, backed by a metadata-only state file that stores no probe
  scriptblock because it is re-read and acted on at every wake. Live smoke tests
  proved the wake chain, the `1x, 1x, 2x, 3x, 6x` ladder, the sliding reset,
  concurrent jobs waking independently, and state-only reconstruction from a
  separate process; they also exposed a missing cancel, so `-Stop` now kills a
  pending tick after matching the recorded process start time. A guarded `Stop`
  hook was confirmed to force a turn, so chain enforcement is viable and the
  batch pre-arm fallback is unnecessary. 18 tests; the scripts had none before.

- **2026-08-07**: `pandoc-docx-export` now carries the grey shading Word drops
  silently. Pandoc maps block quotes to `BlockText` and inline code to
  `VerbatimChar` correctly, but neither style has a fill in the stock reference
  document, so the preview's distinction is lost without warning. Recipe 3
  gained both `w:shd` patches and an output-side count of the two styles;
  gotcha #6 records that `w:pPr` and `w:rPr` are ordered sequences, that `[xml]`
  parsing cannot catch an order violation, and that only a headless LibreOffice
  conversion to PDF proves the file opens.

- **2026-08-06**: `subagent-dispatch` gained the mirror image of its
  no-pre-judging rule: never hand a re-performer the answer. A dispatch asking
  for an independent recomputation must not carry the expected values, and a
  "sealed" section at the end of the same brief is not a barrier — the brief
  arrives as one text, so the values go in a separate file the reviewer opens
  deliberately. Every other leak is named by path, the reviewer discloses what
  it read, and afterwards agreement under exposure counts weaker than
  disagreement.

- **2026-08-04**: Added `Skills/gilb-requirements-engineering`, the first
  Customization covering Tom and Kai Gilb's method: Planguage `Scale` and
  `Meter` quantification, Impact Estimation Tables, Evo step planning, and
  Specification Quality Control, in a 322-line body plus four references.
  `grill-me` elicits; this Skill quantifies, and both cross-reference the other.

- **2026-08-01**: Bounded the append that keeps breaking CI. The Post-flight
  Instruction mandates a `progress.md` append every substantive turn and set no
  limit, so the file grew until the health check errored — twice. Step 2 now
  requires curating the oldest entries in the same edit when the file is at or
  near its budget, `Skills/memory-bank/SKILL.md` runs the health check after any
  Memory Bank edit rather than only after initialization, and
  `sampler-build-debug` gained a "Reproduce a CI-Only Failure" section: derive
  the built commit from the GitVersion `+n` suffix, test a clean clone, and
  never hard-code a version sentinel that can equal Sampler's `0.0.1` fallback.

- **2026-08-01**: Recorded the shipped `2.0.0` release in `CHANGELOG.md`. With
  the token in place the release reached GitHub and was rejected with `422 body
  is too long`: Sampler sends the `[Unreleased]` section as the release body and
  it had reached 143697 of the 125000 characters GitHub allows, because
  `Create_ChangeLog_GitHub_PR` needs the same missing secret and never rolled
  `2.0.0` into a version section. `tests/QA/module.tests.ps1` now fails at
  100000 characters.

- **2026-08-01**: Fixed the publish failure in run 30689416495. The Gallery
  rejected `3.0.0-preview0001` with HTTP 409 because the release that shipped it
  was never tagged: `ContinuousDelivery` anchors the pre-release number on the
  last tag, `Publish_Release_To_GitHub` writes that tag, and it skips itself
  when `GitHubToken` is empty while the Gallery publish still runs. The deploy
  job now verifies both secrets before publishing. `GitHubToken` still has to be
  added to the repository.

- **2026-08-01**: Fixed the CI test failure in run 30568587317. The Memory Bank
  health check errored because this file had reached 220 lines against its
  200-line budget, the same append-until-red failure that broke CI on
  2026-07-29 at 205 lines. The budget stays; `Test-MemoryBankHealth.ps1` now
  raises a `LineBudgetNearLimit` warning at 90 percent of any line budget, and
  `MemoryBankHealth.Tests.ps1` prints those warnings so a passing run still
  names the file about to breach. Retention applied here restored 62 lines of
  headroom.

- **2026-08-01**: Audited the new `german-tax-research` Skill against the
  consolidated statutory text in force on that date. Corrected the `§ 237 AO`
  AdV interest rate (0.15 % → 0.5 % per month, because `§ 238 Abs. 1a AO` is
  limited to `§ 233a` cases), the `Art. 97 § 36 Abs. 3 Nr. 5/7 EGAO` overrides of
  the 14-month `§ 152` and 15-month `§ 233a` counts for VZ 2020 to 2024, the
  `§ 238 Abs. 1c AO` evaluation interval, and the VZ 2025 childcare rule. The
  remainder verified clean, including every cited BFH docket.

- **2026-07-30**: Added the Skill `evidence-package-assembly`; strengthened
  `skill-creator`, `agent-evals`, and `debugging-and-error-recovery` and added
  `subagent-dispatch` (Skill count 40 → 41); dropped the Windows PowerShell 5.1
  CI leg, whose ANSI decode of the BOM-less built manifest breaks the manifest
  parse before any test runs. Detail in `CHANGELOG.md`.

- **2026-07-29**: Migrated the repository to a Sampler-built PowerShell module
  distributed through the PowerShell Gallery (Decision 18), with CI stabilized
  across nine failures the same day. CI rules live in `techContext.md`.

## Stable capabilities

- Deterministic lifecycle hooks that block remote mutation and prove Memory Bank
  presence without relying on model compliance.
- Screenshot documentation for modifiable Windows applications, existing or
  third-party executables without source access, and windows the user already
  has open.
- One-command, idempotent Setup script with Windows, macOS, and Linux path
  handling.
- One Canonical target exposed through `~/.copilot` Discovery links, with
  opt-in Claude Code and Agent Skills links.
- Agent plugin packaging for installation from a Git URL.
- Role-specific Custom agents with Agent-to-agent handoffs, model priority
  arrays, and explicit subagent eligibility.
- File-scoped Instructions and on-demand Skills with declared environment
  requirements.
- Prompt templates for repeatable development, research, legal, and operations
  workflows.
- Detached Pester and build execution with persistent completion evidence.
- Test-first behavior changes, regression guards, risk-scaled review, and
  agentic-security checks.
- Routed Memory Bank loading with deterministic non-inferiority, health,
  provenance, compactness, and rollback checks.

## Open work

- Split the ten Skills on the `SkillFrontmatter` over-budget baseline into
  bodies under 500 lines plus one-level references, removing each from the
  baseline as it lands.
- Continue splitting oversized auto-applied Instructions into concise enforced
  rules plus on-demand Skill references where that can be done without losing
  behavior.
- Keep Custom agent bodies within explicit prompt budgets and add deterministic
  regression checks for other frequently used agents.
- Extend the routing eval set when real retrieval failures are observed.
- Add Markdown linting to continuous integration when the required runtime is
  available.
- Review model identifiers when Copilot model availability changes; the last
  entry of every agent `model` array must stay GA.
- Evaluate the remaining VS Code surfaces that no Customization covers yet:
  the agent host and its harness selection, `chat.assistedPermissions.enabled`,
  and organization-level instructions and agents.
- Address the deferred Minor review findings in `Set-CustomizationLink`: the
  `Read-Host` prompt hangs an unattended run, a child present in both source and
  target is discarded rather than compared, and `Copy-Item -Recurse` may follow
  a child reparse point.
- Curate `techContext.md`, reported at 194 of 200 budgeted lines, and
  `systemPatterns.md`, above the 90 % warning line at 106 of 110. The former's
  per-test-file inventory duplicates `tests/` and conflicts with the file's own
  "do not duplicate changing inventories" rule.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
