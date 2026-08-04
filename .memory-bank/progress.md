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

- **2026-08-04**: Added `Skills/gilb-requirements-engineering`, the first
  Customization covering Tom and Kai Gilb's method: Planguage `Scale` and
  `Meter` quantification, Impact Estimation Tables with credibility ratings,
  Evo step planning, and Specification Quality Control defect density, in a
  322-line body plus four references. Placed as a Skill rather than a Custom
  agent because the knowledge is portable across harnesses and auto-triggers
  from every agent, where a persona has to be selected. `grill-me` elicits;
  this Skill quantifies, and both sides of the overlap audit now cross-
  reference the other.

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

- **2026-07-30**: Added the Skill `evidence-package-assembly`, extracted from a
  live Finanzamt filing. Covers the Markdown-to-PDF pipeline on Windows
  (pandoc plus headless Edge, including the silent-no-output failure that still
  returns exit code 0), the page-numbering criterion for deciding which sheets
  may be omitted from a source document, redaction defaults, and cover-sheet
  structure. Ships two scripts; the Python merge-and-verify script was
  regression-tested against the real 42-page package and reproduced it exactly.

- **2026-07-30**: Dropped the Windows PowerShell 5.1 leg from the CI test
  matrix. `Create_Changelog_Release_Output` writes the built manifest as UTF-8
  without a byte order mark, Windows PowerShell 5.1 decodes a BOM-less file with
  the ANSI code page, and the UTF-8 bytes of `→` end in a right single quotation
  mark that the tokenizer reads as a string delimiter, which breaks the manifest
  parse before any test runs. A build task forcing the byte order mark was
  written and discarded: the module is not used on that runtime, so removing the
  leg is the cheaper contract. All three legs now run PowerShell 7.
- **2026-07-30**: Strengthened the authoring and engineering-discipline Skills.
  `skill-creator` now classifies the baseline failure — discipline, shaping,
  omission, or conditional — before prescribing a guidance form, and scopes the
  anti-rationalization triad to discipline failures only, because prohibitions
  backfire on shaping failures. `agent-evals` gained a wording micro-test loop
  with a mandatory no-guidance control arm and its stop condition (no failure in
  the control means the guidance is not written) plus variance as a metric.
  `debugging-and-error-recovery` gained boundary instrumentation for layered
  systems and a three-failed-fixes stop condition. New `subagent-dispatch` Skill
  documents delegation: model tier per task, a dispatch that carries the task
  not the session history, artifacts as files, no pre-judging a reviewer, a
  compaction-surviving ledger, verification against the diff rather than the
  subagent's claim, and a five-round fix cap. Skill count 40 → 41.
- **2026-07-29**: Migrated the repository to a Sampler-built PowerShell module
  distributed through the PowerShell Gallery. Module sources under `source/`,
  three exported commands over six private helpers, a custom build task that
  copies the six customization directories into the built module, GitVersion
  versioning, GitHub Actions CI, and a QA plus unit test suite.
  `Setup-CopilotSettings.ps1` survives as a clone entry point shim. Recorded as
  Decision 18.
- **2026-07-29**: Stabilized the new GitHub Actions pipeline across a single
  day: a step `shell` key that accepts no context, a Sampler 0.120.0 property
  default leaking into the build scope, four tests assuming the gitignored
  `promptHistory.md`, the macOS configuration root, this file at 205 lines
  against its budget, `#requires` failing Pester discovery, an untrusted hook
  path resolved through the PowerShell provider, hook commands spawned without a
  shell, and a GitVersion log stream piped into `ConvertFrom-Json`. The durable
  rules live in `techContext.md`; `tests/Workflows.Tests.ps1` guards the
  workflow contract.

## Stable capabilities

- Deterministic lifecycle hooks that block remote mutation and prove Memory Bank
  presence without relying on model compliance.
- Screenshot documentation for both modifiable Windows applications and
  existing or third-party executables without source access.
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
- Curate `techContext.md`, which the health check now reports at 194 of 200
  budgeted lines. Its per-test-file inventory duplicates `tests/` and conflicts
  with the file's own "do not duplicate changing inventories" rule.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
