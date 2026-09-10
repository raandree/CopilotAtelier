---
status: current
last-verified: 2026-09-10
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is published to the PowerShell Gallery and released at `v4.0.0`
(2026-08-26), whose changelog section landed on `main` in #22. Incremental work
is tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-09-10**: Fixed Windows OneDrive false detection from a generic variable
  or pre-created folder, preserving account-specific selection, explicit
  targets, and macOS/Linux defaults. Both regressions red then green; focused
  7/0; full Windows `build,test` 1,779/0/116 at 90.67% coverage. AST/analyzer
  clean; README and changelog updated. Live path resolution now stays local;
  no real-profile deployment, migration, or remote mutation was performed.

- **2026-09-08**: Transferred wiki timeout and partial-publication recovery
  lessons into the two existing Sampler Skills, with one real regression case,
  sanitized fixtures, and grader-only success evidence. Pester 5.7.1 structural
  and Memory Bank gates: 617/0/108; nine Markdown documents render, 30 local
  links resolve, and prompt, CI fences, and evaluated hashes are verified.
  `uv` conformance is unavailable. Five ShellPilot requests
  per prior/changed arm completed with zero Skill loads in either arm; body
  effects and native discovery remain unmeasured. Descriptions unchanged; no
  commit or remote mutation. Raw traces and snapshots remain external scratch.

- **2026-09-07**: Repaired CI run `34147860492`: retain hidden adapter metadata
  in build artifacts and canonicalize plan-review temporary fixtures. Workflow
  regression 4/1 then 5/0; linked-temp regression red then green; Node 165/0.
  Clean-checkout gate 1,777/0/116 at 90.72%; final record/workflow checks 12/0.
  Committed and pushed `0367ce3` on `main` as requested. GitHub Actions run
  `34163989373` passed packaging, all three test jobs, and deployment at 21:54
  UTC. The uploaded ownership manifest and generated-file hash were verified.

- **2026-09-07**: Closed the CONDITIONAL review's Major on `f933946`. The
  heading verifier was wired but unproven by the gate CI runs, because the
  behavioural evidence needs `markdown-it`; `tests/PlanReview.Tests.ps1` now
  asserts the import, the instantiation, and every `server.mjs` read call site,
  proven by a mutation that failed exactly that test and was restored
  byte-identical. The hook is mandatory rather than `null`-defaulted, and an
  over-deep request body is refused as `too-deep` instead of leaving its
  deepest keys unwalked. Windows gate 1,775 passed, zero failed, 116 skipped at
  90.72% coverage; Node 255, Edge 42, focused Pester 44.

- **2026-09-07**: Integrated saved PR-01 through PR-09 corrections with the
  existing plan-review hardening. Parser-verified headings refuse ambiguous
  anchors before comment or verdict writes, including queued mutations; CLI,
  empty-revision actions, and mutation-gate coverage are corrected. Preserved
  per-launch sessions, bounded state, ownership locks, snapshots, and drafts.
  Windows full gate 1,774/0/116 at 90.72% coverage; Node 248/0 on Windows and
  Linux; Edge 42; focused Pester 43. Replaced a scheduling-based lock regression
  with observable readiness and proved discrimination under a slow schedule.
  The original independent review covers `3d115a3`; no re-review is claimed.

- **2026-09-07 09:44 UTC**: Seven-task integration at `3d115a3`: Windows gate
  1,773/0/116, 90.72% coverage; Node 180, Edge 40, focused Pester 42. Earlier
  Linux evidence predates these corrections; no push or paid evaluation.

- **2026-09-07**: Corrected `tools/plan-review` in two uncommitted rounds:
  per-launch cookies and bound-address authorities, strict byte-bounded state
  reads/writes that preserve refused content, ownership-aware locks, source
  rechecks inside and after mutation, immutable asset snapshots, visible stale
  drafts, guarded asynchronous selection, CommonMark fences, and globally
  unique section keys. `CHANGELOG.md` retains the defects and regression details.
  Round 1's Node 178 was a miscount; the suite held 163 before round 2.

- **2026-09-07**: Committed tasks 01-06 on `main` as six feature commits
  (`c0c7166` through `288a4ad`) plus records at `555c260`. Added global
  `node_modules/` exclusion and committed task 07 in `3b04d46` with
  regression guards. Windows full gate: 1,810 passed, 90.72% coverage; Linux
  Unit/QA: 1,707 passed, 90.42%. Node: 133 per OS; browser: 30; zero failures.
  Existing warnings remain; no push, real-profile deployment, or paid evaluation.

- **2026-09-07**: Added optional `tools/plan-review` outside the module payload.
  Revision-bound browser feedback never authorizes implementation; chat sign-off
  remains authoritative. The guide and threat model retain security boundaries.

- **2026-09-07**: Added read-only `Get-CopilotAtelierClientAdapter` (task 06 of
  the sequential series) and corrected it in one round. The VS Code profiles
  stay the only source; only frontmatter is rewritten, through an allow-list
  where an unmapped identifier is an error and a strict YAML subset that rejects
  an unknown or duplicate field instead of dropping it. An `execute/` prefix is
  a namespace, not execution authority: only `execute/runInTerminal` reaches the
  execute alias. A restriction that cannot be expressed removes what it guards,
  so `review: on` and `cycle: full` are declared unsupported inside the composed
  file behind a marker carrying the byte-identical shared body's SHA-256.
  Neither client is runtime verified. The build task owns
  `output/clientAdapters/` through a hashed manifest: every path component is
  guarded, the whole operation is validated before the first delete, and an
  edited generated file, an unowned collision, and a names-only `schema 1`
  manifest are all refused. Red 46/103, then 103/103; round 2 121/121.

- **2026-09-07**: Added the `changed-file-validation` Skill (task 05 of the
  sequential series): opt-in, bounded, manual collection with snapshot-bound
  receipts and plan identity. Owned workers bound PowerShell checks; partial
  Markdown structure checks never replace markdownlint. Red 23 of 72 then
  12 of 85, 85/0/0. Full contracts remain in `CHANGELOG.md` and git.

- **2026-09-07**: Added read-only `Get-CopilotAtelierSkillHealth` (task 04) with
  validated provenance and reconciled grading (red 29 then 81/0); shipped the
  reviewed learning inbox (`09416a4`, 62/0) with guarded, hash-approved,
  append-only promotion. Full contracts remain in `CHANGELOG.md` and git.

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
  Test-first behavior changes, regression guards, risk-scaled review, and
  agentic-security checks. Routed Memory Bank loading with deterministic
  non-inferiority, health, provenance, compactness, and rollback checks.

## Open work

- Split research delegation into a read-only code explorer and a public-source
  researcher instead of granting the full `research-analyst` tool surface, and
  review the twelve-agent browser allow-list role by role, adding explicit
  public, authenticated, credential, upload, and irreversible-action bounds to
  every retained browser workflow.
- Replace the three handwritten agent-frontmatter parsers with one shared YAML
  parser and fixtures that prove malformed nested handoffs and lists fail, and
  capture the trigger-eval harness's expected simulated backend failure so the
  successful full build emits no warning.
- Restore a Windows PowerShell 5.1 CI leg now that `Repair_ManifestEncoding`
  fixes the manifest. Re-adding it guards the fix and needs the `ci.yml`
  `shell: pwsh` steps distinguished from `powershell.exe`.
- Run the eleven shipped trigger-query sets, then cover the 37 Skills still on
  the `SkillTriggerCoverage` uncovered baseline. Every set is authored but
  unmeasured. ShellPilot now reports ready with the existing Copilot backend;
  the wiki case completed ten paired requests, but no Skill loaded. Native
  discovery and a graded post-load comparison are still needed.
- Split the nine Skills on the `SkillFrontmatter` over-budget baseline into
  bodies under 500 lines plus one-level references, one per change, removing
  each from the baseline as it lands; `german-legal-research` at 780 is worst.
- Continue splitting oversized auto-applied Instructions into concise enforced
  rules plus on-demand Skill references. Keep Custom agent bodies within
  explicit prompt budgets and add deterministic regression checks for other
  frequently used agents.
- Extend the routing eval set when real retrieval failures are observed, and add
  Markdown linting to continuous integration when the runtime is available.
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
