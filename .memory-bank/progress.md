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
  matrix. Run 30526269252 failed in `Invoke_Pester_Tests_v5` before any test
  ran: `Create_Changelog_Release_Output` writes the built manifest as UTF-8
  without a byte order mark, Windows PowerShell 5.1 decodes a BOM-less file with
  the ANSI code page, and the UTF-8 bytes of `→` become a sequence ending in a
  right single quotation mark that the tokenizer reads as a string delimiter,
  which terminates the release notes and breaks the manifest parse. Verified
  that the same manifest imports cleanly on PowerShell 7 and fails only under a
  code page 1252 decode. A `Set_Built_Manifest_Encoding` build task that forced
  the byte order mark was written and then discarded: the module is not used on
  Windows PowerShell 5.1, so removing the leg is the cheaper contract. All three
  legs now run PowerShell 7 and the matrix `shell` key is gone.
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
  day. A step `shell` key accepts no context, so the matrix shell moved to
  `jobs.<job_id>.defaults.run`; Sampler 0.120.0 leaked a non-empty
  `BuiltModuleSubdirectory` default into the shared build scope; four tests
  assumed the gitignored `promptHistory.md`; macOS reads settings from
  `~/Library/Application Support` rather than `XDG_CONFIG_HOME`; this file had
  reached 205 lines against its budget; `#requires` failed Pester discovery
  instead of skipping one file; the `SessionStart` hook resolved an untrusted
  path through the PowerShell provider and corrupted its own JSON contract;
  hook commands were spawned without a shell, so `%USERPROFILE%` never
  expanded; and the GitVersion step piped a log-carrying stream into
  `ConvertFrom-Json`, which hid every real failure message. The durable rules
  live in `techContext.md`; `tests/Workflows.Tests.ps1` guards the workflow
  contract.
- **2026-07-28**: Closed the gap against the VS Code 1.130 Customization
  surface. Added `Hooks/` with deterministic never-push enforcement and a
  Memory Bank probe, a root `plugin.json`, model priority arrays with a GA
  fallback across all Custom agents, subagent eligibility controls,
  `compatibility` on environment-bound Skills, `context: fork` on the two
  Skills that ingest untrusted external content, and native Waza and analyzer
  routing in `agent-evals`.

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
