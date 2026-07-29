---
status: current
last-verified: 2026-07-29
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is released at `v1.1.0`. The next release is `2.0.0`, the first
published to the PowerShell Gallery. Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-07-29**: Hardened the `SessionStart` hook probe. It resolved an
  attacker-controlled payload path through `Join-Path` and `Test-Path`, so a
  path this host cannot resolve writes to standard error and corrupts the JSON
  contract the caller parses. Now uses `[System.IO.Path]::Combine` and
  `[System.IO.File]::Exists`, which carry no provider semantics.
- **2026-07-29**: Fixed CI failing on Windows PowerShell 5.1 and Linux while
  Windows PowerShell 7 passed. A Windows GUI test was tagged `Unit` and guarded
  by `#requires`, which fails discovery instead of skipping; the hook tests
  treated a deliberate stderr write and non-zero exit as a crash; and
  Windows PowerShell 5.1 decoded BOM-less UTF-8 Markdown as ANSI.
- **2026-07-29**: Fixed all three CI test jobs failing. Four repository tests
  assumed the gitignored `.memory-bank/promptHistory.md` exists, so the suite
  had only ever run in a developer worktree. Reproducing against a clean clone
  also exposed that `Setup-CopilotSettings.Tests.ps1` still derived the target
  folder name from the clone directory, which the module migration fixed to
  `CopilotAtelier`.
- **2026-07-29**: Fixed the first GitHub Actions run failing in 0s with an
  invalid workflow file. A step's `shell` key rejects every context, so
  `shell: ${{ matrix.shell }}` broke compilation of the whole file; the shell
  moved to `jobs.<job_id>.defaults.run`, which does accept `matrix`. Added
  `tests/Workflows.Tests.ps1` as the regression guard.
- **2026-07-29**: Fixed the build breaking on Sampler 0.120.0. Its new
  `WorkspaceDependencies` task declares `BuiltModuleSubdirectory` with a
  non-empty `'module'` default; InvokeBuild treats an empty string as an unset
  property, so that default leaked into the shared build scope and overrode
  `build.yaml`. Aligned `build.yaml` on `module` and made the test suite match
  the subdirectory instead of hard-coding it.
- **2026-07-29**: Migrated the repository to a Sampler-built PowerShell module
  distributed through the PowerShell Gallery. Module sources under `source/`,
  three exported commands over six private helpers, a custom build task that
  copies the six customization directories into the built module, GitVersion
  versioning, GitHub Actions CI across Windows PowerShell 5.1 and PowerShell 7
  on Windows and Linux, and a QA plus unit test suite. `Setup-CopilotSettings.ps1`
  survives as a clone entry point shim. 339 passing tests, 70.77 percent module
  coverage. Recorded as Decision 18.
- **2026-07-29**: Fixed both hooks failing to start on Windows. VS Code spawns
  hook commands without a shell, so `%USERPROFILE%` and `$HOME` were never
  expanded and `-File` never resolved. Commands now use `-Command` with
  `Join-Path` plus explicit `exit $LASTEXITCODE`. The old regression passed
  because it ran the shipped string through `cmd.exe /c`; it now spawns without
  a shell against a staged fake home.
- **2026-07-28**: Closed the gap against the VS Code 1.130 Customization
  surface. Added a fifth Customization type (`Hooks/`) with deterministic
  never-push enforcement and a Memory Bank probe, a root `plugin.json`, model
  priority arrays with a GA fallback across all 11 Custom agents, subagent
  eligibility controls, `compatibility` on 25 environment-bound Skills,
  `context: fork` on the two Skills that ingest untrusted external content, and
  native Waza/analyzer routing in `agent-evals`. Fixed two over-cap Skill
  descriptions. Two new suites bring the repository to 250 passing tests.
- **2026-07-27**: Extended `windows-gui-screenshot-capture` with a source-ownership
  branch for existing executables, event-driven window/control readiness,
  cross-process control handling, state restoration, stronger image-content
  validation, an external-Win32 reference, and real-failure regression evals.
- **2026-07-25**: Completed independent label and security review, final static
  checks, 44-test Pester validation, and deployment. The audited 25-case router
  reports 0 critical-file misses, 0 unexpected history loads, 0 fallback
  failures, all 15 Decision records in Full mode, and 52.93 percent average
  version-controlled context reduction after compacting the routed indexes. All
  142 deployed files match source by
  path and SHA-256; the deployed initializer and health checker pass initialized
  and clean-checkout scenarios. Changes remain uncommitted and unpushed.
- **2026-07-24**: Implemented evaluated Memory Bank routing with `index.md` as
  the sole unconditional read, 25 independently audited task cases, zero
  critical-file misses, a 50 percent context-reduction floor, and a tested
  Full-read fallback. Extracted 15 Decision records, added freshness and source
  metadata, demoted prompt history from routine reads, added optional Memory
  Bank topics and a deterministic health check, and retained least-privilege
  Custom agent tool lists by making native-memory guidance explicitly
  conditional.
- **2026-07-24**: Audited the Memory Bank against current Cline, VS Code 1.130,
  Claude Code, Agent Skills, Anthropic context-engineering guidance, OpenAI,
  Google ADK, AutoGen, LangGraph, MADR, and recent memory benchmarks. Confirmed
  that the file schema remains viable but the unconditional eight-file read
  costs approximately 10.7k tokens per turn. Found two local documentation
  conflicts and an eight-agent native-memory tool gap. Recorded an
  evaluation-first, shadow-routing migration rule; no runtime change was made.
- **2026-07-23**: Added the deployed `memory-bank` Skill and centralized the
  Definition of Done in Post-flight. Pre-flight now safely creates only missing
  canonical base files before durable writes. All 11 Custom agents use shared
  lifecycle Instructions while preserving exact tools, handoffs, domain
  workflows, quality gates, and role-specific persistence schemas. Removed ten
  duplicate lifecycle blocks and three per-tool narration templates. Added a
  deterministic PowerShell initializer with LF/no-BOM, byte-preservation,
  idempotency, and partial-base `-WhatIf` tests; deployed hashes and a sandbox
  initialization pass. Harmonized all role initialization triggers with the
  shared durable-write/read-only boundary, restored the Software Engineer's
  on-demand role files, respected repository policy for local ephemera, and
  hash-locked full role schemas.
- **2026-07-22**: Reduced the Software Engineer Custom agent from 413 to 156
  lines while preserving all 45 tools, both handoffs, focused/final validation,
  test-first behavior changes, bug-fix regression guards, self-review,
  risk-triggered independent review, and agentic-security checks. Pre-flight
  now reuses supplied Instruction and Skill bodies. Setup removes legacy
  duplicate location aliases without touching unrelated paths. Complete Pester,
  AST, analyzer, Markdown, independent-review, deployment, and live-profile
  checks passed.
- **2026-07-21**: Established the Glossary with 20 Canonical terms and verified
  that its forbidden phrases do not conflict with existing artifacts.
- **2026-07-21**: Made the Setup script cross-platform, added a sandboxed Linux
  regression, and guarded against null copy destinations that could flatten
  Customization directories into the current working directory.
- **2026-07-21**: Proved and completed guarded cleanup of artifacts from the
  failed Linux setup run.
- **2026-07-17**: Added the `windows-gui-screenshot-capture` Skill with
  rendering-engine-specific capture recipes and deterministic verification.
- **2026-07-16**: Added `automatedlab-proxmox`, hardened WinRM and long-running
  job guidance, and completed the detached cross-platform Pester/build contract.
- **2026-07-16**: Exempted Non-impacting turns from Post-flight documentation
  while retaining the full closure path for Substantive turns.
- **2026-07-11**: Restored file and directory creation tools across all Custom
  agents and added role-appropriate task and rename capabilities.
- **2026-07-09**: Added `test-driven-development`,
  `debugging-and-error-recovery`, and `code-review-and-quality`, plus the shared
  Definition of Done.
- **2026-07-02**: Added agentic-security and evaluation Skills, introduced the
  portable `AGENTS.md`, and aligned Custom agents on Claude Opus 4.8.

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

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.
