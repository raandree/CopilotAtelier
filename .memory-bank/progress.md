---
status: current
last-verified: 2026-09-07
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is published to the PowerShell Gallery and released at `v4.0.0`
(2026-08-26), whose changelog section landed on `main` in #22. Incremental work
is tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-09-07**: Committed tasks 01-06 on `main` as six feature commits
  (`c0c7166` through `288a4ad`) plus records at `555c260`. Added global
  `node_modules/` exclusion and committed task 07 in `3b04d46` with
  regression guards. Windows full gate: 1,810 passed, 90.72% coverage; Linux
  Unit/QA: 1,707 passed, 90.42%. Node: 133 per OS; browser: 30; zero failures.
  Existing warnings remain; no push, real-profile deployment, or paid evaluation.

- **2026-09-07**: Added `tools/plan-review` (task 07 of the sequential series):
  an optional, loopback-only local surface that renders a Design Concept and its
  Mermaid diagrams, anchors comments to stable section keys, and records a
  verdict against one revision hash. It is absent from `CustomizationDirectory`,
  unreferenced by `source/`, and keeps Node dependencies optional. Browser
  feedback never authorizes implementation; chat sign-off remains authoritative.
  Host, Origin, session, and CSRF checks protect the bounded local HTTP surface.
  Initial evidence: 124 Node tests, 22 desktop/mobile browser checks, and 30
  repository checks. Later integration evidence is recorded above; the guide
  and threat model retain detailed boundaries and residual risks.

- **2026-09-07**: Added read-only `Get-CopilotAtelierClientAdapter` (task 06 of
  the sequential series) and corrected it in one round. The VS Code profiles
  stay the only source; only frontmatter is rewritten, through an allow-list
  where an unmapped identifier is an error and a strict YAML subset that rejects
  an unknown or duplicate field instead of dropping it. An `execute/` prefix is
  a namespace, not execution authority: only `execute/runInTerminal` reaches the
  execute alias, and every other mapping stays inside its capability class. A
  restriction that cannot be expressed removes what it guards. `review: on` and
  `cycle: full` are declared unsupported inside the composed file behind an
  explicit marker carrying the byte-identical shared body's SHA-256. Neither
  client is runtime verified. The build task owns `output/clientAdapters/`
  through a hashed manifest: every path component is guarded, the whole
  operation is validated before the first delete, and an edited generated file,
  an unowned collision, and a names-only `schema 1` manifest are all refused.
  Red 46/103, then 103/103; round 2 red 15/121, then 121/121.

- **2026-09-07**: Added the `changed-file-validation` Skill (task 05 of the
  sequential series) and corrected it in two rounds: an opt-in, bounded
  validation pass over the files one work batch changed, with five scripts
  covering collect, report, validate, clear, and the child worker. Collection
  stays manual — no hook is wired: `PostToolUse` is the only plausible
  collector, its input contract is unverified here, and the shipped hooks are
  mandatory. Validators read an isolated snapshot, so a receipt binds to the
  bytes actually read and no project text reaches a command line; the receipt's
  plan identity hashes the linter entry point and the shipped checker code, and
  reuse also requires producible results, a typed Boolean change flag, exactly
  the planned checks, and an agreeing exit status. Parse and PSScriptAnalyzer
  run in an owned child worker with a wall clock, inline analyzer settings, and
  a per-session execution lock. `Markdown.NativeStructure` is `coverage=partial`
  and no longer stands in for markdownlint. Red 23 of 72 then 12 of 85, 85/0/0.

- **2026-09-07**: Added read-only `Get-CopilotAtelierSkillHealth` (task 04 of
  the sequential series) with private `Import-CopilotAtelierSkillObservation`
  and `Measure-CopilotAtelierSkillHealth`, then corrected it in two rounds.
  Usage arrives only through explicit `-ObservationPath` imports validated
  against a closed schema; nothing is stored or uploaded, and missing telemetry
  is unknown, never zero use. Evaluation evidence is content-bound: run output
  counts only through a validated provenance sidecar, and a graded summary only
  when it reconciles with the bounded verdicts in `assertion_results`.
  Red 29 then green 81/0; canonical `build, test` 1492/0, exit 0.

- **2026-09-07**: Added the `reviewed-learning-inbox` Skill (task 03 of the
  sequential series): an on-demand, project-scoped review queue that turns an
  explicitly selected local correction into a reviewable suggestion for an
  existing Skill or Instruction, through six scripts covering record, read,
  decide, discard, preview, and apply. The store at
  `.memory-bank/learning-inbox/candidates.json` sits outside the routed base and
  the deployed tree. Promotion is append-only and needs `-Approve` plus the
  SHA-256 of the reviewed preview, and refuses a foreign project, a contradicting
  or out-of-surface destination, and stale candidate, evidence, destination, or
  preview state before the first write. One content rule guards intake and
  promotion alike, so a hand-edited store cannot smuggle a capability key or
  shell substitution into a Customization. Round 1 added parent-chain reparse
  guards, evidence bound to the candidate record, a byte-preserving exclusive
  append, an atomic locked store, and verified-block repeat handling. Red 39
  then 39/0/0; round 2 red 18 of 62 then 62/0/0. `evals/candidate-cases.json` is
  authored and unexecuted.

- **2026-09-06**: Added opt-in installation profiles (task 02 of the sequential
  series). `-InstallationProfile` (`complete` default, `engineering`,
  `research`, `document-processing`) plus `-IncludeSkill`/`-ExcludeSkill` on
  Install, Update, and Setup; new read-only `Get-CopilotAtelierProfile`;
  `Test-CopilotAtelier` reports the deployed profile. Only Skills are
  selectable, three mandatory Skills are protected, whole Skill folders and
  declared dependencies come along, and every rejection happens before the first
  write. The selection is an additive optional `Selection` field in schema 1.
  Correction round 1 closed three defects: validating a narrowing request
  against the payload it narrows, re-reading the inherited selection under the
  deployment lock, and validating the recorded `Selection` shape strictly.
  Focused suites red 34 then green; regressions red 15 then 210/0/6 on
  PowerShell 7 and 5.1; full gate green.
- **2026-09-06**: Added read-only `Get-CopilotAtelierFootprint` (task 01) with
  the shared `Get-CopilotAtelierDirectoryMap` helper, which the installer now
  reuses, and the filesystem-pure `Measure-CopilotAtelierFootprint` engine. Two
  correction rounds followed: wording says potential automatic loading
  contingent on discovery, not "always loaded"; every mapped root is guarded
  through `Assert-CopilotAtelierRegularPath`; and ambiguous frontmatter fails
  closed. Regressions ran red before each round and green after; committed in
  `c0c7166` as part of the six-feature sequence.

- **2026-09-06**: Reproduced CI run `34061934611` at `5acb69d` in a clean clone
  and a Linux container and fixed shared payload-guard use, dangling Unix
  Discovery links, and the literal POSIX filename fixture on `main`. Windows
  1,266 passed at 88.03% coverage; Linux 1,172; 5.1 focused 120; zero failures.

- **2026-09-06**: Implemented M1-M5/L1-L6 deployment-review remediation with
  per-ID red/green evidence in `assessment-log.md`. Repair remains explicit;
  untracked content and abandoned staging are preserved. Full gate 1,234 passed
  at 87.8% coverage. Independent review: Approve, zero Blocker/Major.

- **2026-09-05**: Implemented hash-aware deployment and conservative removal,
  read-only diagnostics, bounded SessionStart context, and configuration gates.
  1,137 passed at 83.63% coverage; the independent security review returned
  CONDITIONAL with no Critical or High and unresolved findings stay in
  `assessment-log.md`.

- **2026-09-04**: Role-record migration and job-monitor work shipped in `e23eb7e`;
  historical validation is retained in the changelog.

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
  agentic-security checks. Routed Memory Bank loading with deterministic
  non-inferiority, health, provenance, compactness, and rollback checks.

## Open work

- Split research delegation into a read-only code explorer and a public-source
  researcher instead of granting the full `research-analyst` tool surface.
- Review the twelve-agent browser allow-list role by role and add explicit
  public, authenticated, credential, upload, and irreversible-action bounds to
  every retained browser workflow.
- Replace the three handwritten agent-frontmatter parsers with one shared YAML
  parser and fixtures that prove malformed nested handoffs and lists fail.
- Capture the trigger-eval harness's expected simulated backend failure so the
  successful full build emits no warning.
- Restore a Windows PowerShell 5.1 CI leg now that `Repair_ManifestEncoding`
  fixes the manifest. Re-adding it guards the fix and needs the `ci.yml`
  `shell: pwsh` steps distinguished from `powershell.exe`.
- Run the eleven shipped trigger-query sets, then cover the 37 Skills still on
  the `SkillTriggerCoverage` uncovered baseline. Every set is authored but
  unmeasured; Execute mode needs ShellPilot plus a paid backend, neither present.
- Split the nine Skills on the `SkillFrontmatter` over-budget baseline into
  bodies under 500 lines plus one-level references, one per change, removing
  each from the baseline as it lands; `german-legal-research` at 780 is worst.
- Continue splitting oversized auto-applied Instructions into concise enforced
  rules plus on-demand Skill references. Keep Custom agent bodies within
  explicit prompt budgets and add deterministic regression checks for other
  frequently used agents.
- Extend the routing eval set when real retrieval failures are observed.
- Add Markdown linting to continuous integration when the required runtime is
  available.
- Review model identifiers when Copilot model availability changes; the last
  entry of every agent `model` array must stay GA.
- Curate `techContext.md` and `systemPatterns.md` when either approaches its
  line budget; `systemPatterns.md` runs close to its 110-line cap, so any new
  Decision record or relationship needs a trim in the same edit.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
