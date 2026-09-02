---
status: current
last-verified: 2026-08-27
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is published to the PowerShell Gallery and released at `v4.0.0`
(2026-08-26), whose changelog section landed on `main` in #22. Incremental work
is tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-09-02**: Added a session clock so Post-flight closes with a measured
  timestamp and the chat's elapsed duration. A model has no clock, so both
  numbers come from hooks: `Add-SessionContext.ps1` writes the session start to
  `<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.json`, and a new
  `Stop` hook, `Write-SessionClose.ps1`, reads it at the end of every turn and
  appends one `systemMessage` under the checklist. `UserPromptSubmit` was ruled
  out — common output format only, no `additionalContext` — and `PreToolUse` was
  rejected as a token cost on every call. Decision record 0024.

- **2026-09-01**: Fixed three defects in `long-running-job-monitor` after a
  45-minute live Hyper-V proof ran with the Skill never loaded: no cadence
  tick, thirty silent minutes, two mid-job turns with no status line. The
  `USE FOR:` list carried "live test" but not *proof*, that workspace's
  canonical word for a live integration run, so the selector never matched — it
  now names `live proof`, `proof harness`, `proof run`, `hour-long run`. The
  structural half: arming the tick lived only in a later section, so step 2 now
  requires it in the same turn as the launch, and the checklist item is
  unconditional. E10 measures the trigger on vocabulary alone.

- **2026-09-01**: Fixed an unbounded handoff loop in the `cycle: full` chain.
  A raw transcript showed fifteen complete `software-engineer` ↔
  `security-reviewer` round trips in one autopilot session (30 MB against a
  ~600 KB norm), because both legs carried `send: true` and the only bound was
  prose. The reviewer's *Fix Issues Found* leg is now `send: false`, so the
  cycle still reaches the reviewer unattended but cannot re-enter
  implementation without a click; the "after two rounds" wording is gone from
  both agent bodies, the agents README, and the unreleased changelog entry.
  `tests/DevelopmentCycle.Tests.ps1` now walks the whole handoff graph and
  fails on any ring of `send: true` edges, and self-checks the detector against
  a synthetic ring. The audit found no other closeable ring: `software-architect`
  → `software-engineer` → `security-reviewer` is the only other `send: true`
  path and the architect has no inbound edge.

- **2026-09-01**: Diagnosed the red `main` build (CI run 33430725722) — the
  second recurrence of one failure mode. `elster-form-capture` took
  `activeContext.md` to 220 lines against a 200-line budget; five days earlier
  `dc6206e` had taken `systemPatterns.md` to 122 against 110 (CI run
  33080179473). Both failed on the Windows leg alone. The lesson both times was
  that curating back to the edge only defers the breach, because the Post-flight
  append every Substantive turn owes re-breaks it on the next commit.

- **2026-08-31**: Fixed a contradiction between an agent and its Skill that
  reached a signed submission. `tax-researcher` demanded the RDG/StBerG
  disclaimer "at the end of every substantive output"; `german-tax-research`
  forbade it in anything addressed to the Finanzamt. The unqualified
  instruction won, and the notice ended up below the signature block of two
  `Einspruchsbegründungen` — caught only after the taxpayer had signed them.
  The lesson generalises beyond this pair: **an unqualified instruction in an
  agent body overrides a qualified rule buried in a Skill**, so the narrower
  rule has to live where the broad one is stated. Both files now carry a marker
  sweep, and the Skill requires it twice — against the Markdown and against the
  rendered PDF's text layer, because a template can reintroduce what the source
  no longer shows.
- **2026-08-31**: Gave `german-tax-research` a *disclosure economy*. A letter to
  a tax office had been naming its own missing receipts, explaining positions it
  did not claim, and conceding reductions nobody had asked for. One test now
  decides every sentence — does it support an amount that is actually declared?
  `§ 150 Abs. 2 AO` demands complete and truthful bases of taxation, not a
  self-assessment of evidentiary strength; `§§ 90, 97 AO` bite on request.
- **2026-08-31**: Added the `elster-form-capture` Skill from three capture runs
  across two assessment years in a live tax repository. Its load-bearing fact:
  the official ERiC field numbers behind `name="fields[…]"` are stable across
  years, the `Teilseite` and `Zeile` numbers are not — the `Anlage V` was
  renumbered for 2023 and again for 2024 without one `data-eru-name` changing.
  Transmission stays with the taxpayer (`§ 150 Abs. 2 S. 1 AO`), so the Skill
  fills fields and never presses *Versenden*. Driving the form mechanically
  audits the capture guide faster than following it does.

- **2026-08-31**: Wrote `docs/summit-2027-session-proposals.md` for a call that
  closed the same day — a 90-minute Customization anatomy session, a 45-minute
  AI-assisted process field report, and a 25-minute alternate. Round one is
  blind, so the abstracts name neither speaker nor project.

- **2026-08-28**: Added the opt-in `cycle: full` development cycle — architect,
  engineer, security reviewer, technical writer, with the reviewer as the gate
  and a gated fail path back into implementation. The correction that shaped it:
  removing the auto-handover earlier the same day treated *automatic* as the
  problem, but the problem was *unrequested* — consent at the entry point covers
  the whole chain, so a requested cycle may progress on its own. Close-out
  defers to the final stage or four agents each write a changelog entry and a
  commit for one change. Rules live in the agent bodies because a Skill is
  advisory and cannot bind them; one new handoff edge, `security-reviewer` to
  `technical-writer`, closed the graph. The architect carries a trigger phrase
  book and a refusal list — "end-to-end" means end-to-end tests, so it does not
  start one. `cycle: off` ends a running chain at the current stage, which then
  closes out instead of stranding the commit; both switches are documented in
  the root README and the agents README with the single-agent default first.
  The Contoso overlay names its two reversed inherited defaults in the preamble,
  because a precedence clause 180 lines later resolves the self-contradiction
  only for a reader who gets there.

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

- Restore a Windows PowerShell 5.1 CI leg now that `Repair_ManifestEncoding`
  fixes the manifest instead of working around it. The leg was dropped
  2026-07-29 for the defect this fix closes; re-adding it guards the fix and
  needs the `ci.yml` `shell: pwsh` steps distinguished from `powershell.exe`.
- Run the seven shipped trigger-query sets, then cover the 38 Skills still on
  the `SkillTriggerCoverage` uncovered baseline. The sets are authored but
  unmeasured, so the gate currently proves only that the queries exist. Execute
  mode needs ShellPilot plus a paid backend, neither present on this machine.
- Split the nine Skills still on the `SkillFrontmatter` over-budget baseline
  into bodies under 500 lines plus one-level references, one per change,
  removing each from the baseline as it lands. `german-legal-research` at 780
  body lines is the next worst.
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
