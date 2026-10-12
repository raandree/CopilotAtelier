---
status: current
last-verified: 2026-10-11
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.0.0`, published 2026-09-30
from `a592832`. CI on `main` has since published the prereleases
`6.0.1-preview0001` (`fea564f`), `6.1.0-preview0001` (`7a48abe`),
`6.1.0-preview0002` (`25d8233`), and `6.1.0-preview0003` (`9b6a341`) to GitHub
Releases and the PowerShell Gallery (verified 2026-10-05). Incremental work is
tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-10-12**: PR #32 opened; CI's POSIX-only test defect is fixed in `8eaa991`.
  The review of the hand-merged hook scripts: `ddf5430` fixes a key-rule drift and
  a non-ASCII gap; a tests-only follow-up closes three minors, and M-04 stays open.
- **2026-10-12**: Ran Desktop prompt 06c (`review: on`, Prox1): the built-in
  `security-review` agent reviewed the eval kit's egress code in four rounds, and a
  background agent fixed 2 Blockers and 7 Majors test-first in the kit (self-checks
  all green, reproduced). E-08, E-09, E-15, E-16 stay open; no further run is
  authorized (A34), and the next freeze needs the owner's term file and a digest
  recorded outside the kit. `docs/SECURITY-REVIEW.md` holds the entry.
- **2026-10-11**: Closed out Decision 0028 (Desktop prompt 07,
  `software-engineer`, Prox1). The *Close-out, 2026-10-11* matrix proves criteria
  1 to 20 and 22 to 30, and **criterion 21 stays not met**, worded exactly as A39
  fixes it. Criterion 23's gaps were fixed (README, hooks README, CHANGELOG, the
  Glossary check), TBD-2 is carried forward, and `origin/main` (`6286ad4`, pushed
  by the owner during the close-out) was merged into the branch with 9 conflicts
  resolved. Full gate on the merge commit `ef96c2d`: 3,243 passed, 0 failed, 129
  skipped, 90.84 % coverage. The owner opened the pull request.
- **2026-10-11**: Desktop prompts 03 and 08 reached `main` (`6286ad4`, pushed by the
  owner after merging in an integration clone; gate 2,620 passed). Prompt 08 pins
  the Post-flight elapsed line to its own chat: `Add-SessionContext.ps1` hands the
  agent `& '<reader>' -Path '<clock>'`, and `Get-SessionElapsed.ps1` prefers the
  session `COPILOT_AGENT_SESSION_ID` names. An independent review found no Blocker
  or Major; its fixes made the hook's JSON pure ASCII and the key pattern
  case-sensitive. Decision 0024 holds the evidence and what stays open.
- **2026-10-11**: Ran Desktop prompt 05c (`software-architect`): Decision 0028
  **Amendment 7, A33 to A39**, signed off. Record-only: the judged `expert` row
  is a report, not gate evidence; criterion 21 ships as not met and no further
  run is authorized; a further run needs TBD-11 closed and prompt 06c first
  (06c ran on 2026-10-12).
- **2026-10-10**: Ran Desktop prompts 05b and 06b: Amendment 6 (A25 to A32)
  ratified the Sonnet writer and the hybrid labels, and the one fresh run, frozen
  at `9305035`, closed **criterion 21 as not met** (persistence 83.3 %, held-out
  10 of 12 against 11; TBD-11 UNVERIFIED; 5.92 USD).
- **2026-10-09 and 2026-10-10**: Desktop prompts 04, 05, and 06: an independent
  review of the eval kit's privacy boundary (four rounds; criterion 28 as
  scoped), Amendment 5 (A20 to A24), and its judge-2b run (39 of 40; 77.8 % and
  72.2 %, not met). Records: *Amendment 5 built, calibrated, and run*,
  `docs/SECURITY-REVIEW.md`.
- **2026-10-09**: Applied the five session lessons (`ai/session-lessons`, on `main`
  since 2026-10-11; gate 2,593 passed): detached Pester guards reject a result
  other than `Passed`, `Wait-DetachedResult.ps1`, hook context as data, and the
  hook-evidence locations.
- **2026-10-07 and 2026-10-08**: Amendment 3 (A14 to A18) signed off; the Prox1
  Meter lost no replicate (spread at most 1.16); the A13 eval (TBD-8 closed,
  criterion 28 met; 10.19 USD); the VS Code Local backstop live (TBD-7 closed,
  criteria 22 and 30 met); the latency levels (TBD-6 closed, criteria 20, 26, 29).
- **2026-10-02 to 2026-10-04**: Hook follow-ups on local `main` (`d8cc6f5` to
  `fea564f`) and `ai/hook-deny-reason`: Copilot SDK chats show the guard's block
  reason (`tests/HookSdkRuntime.Tests.ps1` runs the shipped launcher and guard in
  the bundled runtime), a resumed chat keeps its clock, and ten reviews closed the
  launcher and guard findings. Detail stays in git and the assessment log.

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
  Short runs have a bounded async result waiter; longer runs keep heartbeat ticks.
  Test-first behavior changes, regression guards, risk-scaled review, and
  agentic-security checks. Routed Memory Bank loading with deterministic
  non-inferiority, health, provenance, compactness, and rollback checks.

## Open work

- Desktop `CopilotAtelier New\LEDGER.md` owns the local queue: 01-08 and P1-P9.
  It keeps Decision 0028 gates, dependencies, and duplicate/superseded references.
- Confirm the clock pin live in a new VS Code agent-host chat and in VS Code Local
  (the Copilot CLI runtime stood in for them when it was redeployed on
  2026-10-11; `main` is pushed and `origin/ai/session-clock-path` is gone).
  Decision 0024 lists the cases that stay open.
- One-process `windows` launcher (ruling A11): separate work against Decision
  0016, kept here because Decision records here are accepted or superseded.
  Adopt only if `tests/HookLauncher.Tests.ps1` passes unchanged (`cmd.exe`,
  `sh`, an outer PowerShell, `HOME` unset), a deny still exits `2` and blocks
  in both hosts, a Meter run on Prox1 and RAANDREE3 shows the saving, and
  Decision 0028's levels are re-baselined in the same change.
- Confirm live in a fresh agent-host chat that `software-engineer` calls
  `web_fetch` for `#web/fetch`; drop the paired runtime names once
  github/copilot-cli#4594 ships fixed, per decision 0026's removal condition.
- Run prompt 04 on the hand-patched machine.
- Copilot SDK chats load every Instruction twice, once as `C:\Users\…` and once
  as `c:\Users\…`. VS Code discovers `~/.copilot/instructions` as a default
  `copilot-personal` source, and the SDK runtime has its own user-instruction
  discovery (`COPILOT_CUSTOM_INSTRUCTIONS_DIRS`). Report it upstream: turning
  off either source affects every chat.
- Unfixed Minor findings from the 2026-10-02 reviews (assessment log):
  - Hooks: SEC-07 (camelCase `toolArgs`), SEC-08 (Bypass without an integrity
    check), SEC-09 and SEC-10 (test gaps), SEC-12 (the override applies to
    the whole environment), SEC-15 (a dead UNC `PLUGIN_ROOT` still outlasts
    the timeout), SEC-34 (a batch beside 25,000 small objects falls onto the
    raw path and is blocked as a push; options in the assessment log).
  - Versioning and heartbeat: F-02 (fail fast on permanent `IOException`s),
    F-06 (sweep stale `.tmp` files), F-09 (Constrained Language Mode).
  - Accepted and documented: SEC-14, SEC-16, SEC-19 (`command` has no exit
    pass-through), SEC-27 (the limit can overrun by about 1.5 s), SEC-28 and
    escaped-key splits (known evasions), SEC-30 and oversized payloads blocked
    as not inspected in time (git-dense over 1 MB; under pwsh, batches over
    about 16,000 command entries, which Windows PowerShell allows), the raw
    path pairing fields across entries (errs toward blocking), and a linear
    standard-input read (about 120 MB to outlast the timeout).
- Split research delegation into a read-only code explorer and a public-source
  researcher instead of granting the full `research-analyst` tool surface, and
  review the twelve-agent browser allow-list role by role, adding explicit
  public, authenticated, credential, upload, and irreversible-action bounds to
  every retained browser workflow.
- Replace the three handwritten agent-frontmatter parsers with one shared YAML
  parser and fixtures that prove malformed nested handoffs and lists fail, and
  capture the trigger-eval harness's expected simulated backend failure and the
  Meter tests' 15 simulated crashed launches (Invoke-Build records
  `Write-Warning` despite `-WarningAction SilentlyContinue`) so the successful
  full build emits no warning.
- Restore a Windows PowerShell 5.1 CI leg now that `Repair_ManifestEncoding`
  fixes the manifest. Re-adding it guards the fix and the heartbeat's
  `MoveFile` path (review F-03), and needs the `ci.yml` `shell: pwsh` steps
  distinguished from `powershell.exe`. The hook tests' process helpers use
  .NET-only `ProcessStartInfo.ArgumentList` and `Kill($true)`; port or skip them.
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
