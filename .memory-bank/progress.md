---
status: current
last-verified: 2026-10-10
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

- **2026-10-10**: Ran Desktop prompt 05b (`software-architect`, owner at the
  keyboard): Decision 0028 **Amendment 6, rulings A25 to A32, signed off**. The
  Sonnet writer and the hybrid labels are ratified, with a held-out check of 12
  new replies (bar 11 of 12) in the next run; disclosure to Anthropic, OpenAI,
  Google, and xAI is accepted subject to a read-only `security-review` (approve
  with changes, no Blocker; provider terms UNVERIFIED, TBD-11); the Git `expert`
  ceiling becomes a judged "terse" plus a 3,000-character runaway guard; DSC and
  the Plan-mode cue and the guard stand; one fresh run, no spending limit for
  that run only, and a miss closes criterion 21 as not met. Criterion 21 stays
  not met. No model call, no spend. Record: Decision 0028, *Rulings,
  2026-10-10*; review: `docs/SECURITY-REVIEW.md`.
- **2026-10-10**: Desktop prompt 06 finished (`software-engineer`): Amendment 5's
  grader built, calibrated (judge 2b, 39 of 40, kappa 0.89 after two rubric
  revisions), frozen, and run once with `claude-sonnet-5.5`. **Criterion 21 not
  met**: persistence 77.8 % and 72.2 %, guard fails its reading condition, offer
  and safety at Goal; at most 13.6 USD, no rerun. Two owner deviations (Sonnet
  writer, seven-AI hybrid labels) await the architect. Record: Confirmation of
  Decision 0028, *Amendment 5 built, calibrated, and run*.
- **2026-10-09**: Desktop prompt 06, stage 1 (`software-engineer`): built, tested,
  and documented in the private eval kit what Amendment 5 rules, with no model
  call and no spend. Eval version 3 (judge `gpt-5.5` version 2, quote check,
  A24 vote rule, rubric per level row), guard gate (margin 2), freeze and
  verifier, four offline self-checks (66, 9, 15, 12 checks), and the 40-item
  calibration list with the owner's blind sheet.

- **2026-10-09**: Ran Desktop prompt 05 (`software-architect`, owner at the
  keyboard): Decision 0028 Amendment 5, rulings A20 to A24, signed off. A pinned
  judge replaces the persistence regex checks (calibrated on 40 owner labels,
  bar 36 of 40 and kappa 0.80); the guard gates on non-inferiority (margin 2 in
  51) plus a read; the decisive run is fresh; no spending ceiling set by the
  owner. A read-only security review (approve with changes) found the runner
  lacks a quote check and the labelling sheet needs a local-only rule; both are
  in the record and prompt 06's build order. No model call, no eval spend.
- **2026-10-09**: Ran Desktop prompt 04 (`software-engineer`, owner away): an
  independent read-only review of the private eval kit's privacy boundary,
  four rounds, findings P-01..P-03, V-01..V-04, S-01..S-04. Every Major fixed
  and verified by the reviewer; the last Minor fixed by the author's tests. The
  kit now refuses a working-tree location, an unsafe case id or destination,
  and a repeated JSON key. Criterion 28 holds as scoped; protected runs
  unchanged (347 files, 831,036 bytes). Record in `docs/SECURITY-REVIEW.md`.

- **2026-10-09**: Created the Desktop ledger for 01-08, then consolidated nine
  P1-P9 prompts from `Desktop\p`, preserving names and bytes (SHA-256 9/9).
  README/ledger carry the order and gates; P4 is an older reference, P9 duplicates
  03. All 43 metadata links resolve; imported tasks were not executed.
- **2026-10-08**: Ran Decision 0028's A13 eval (`software-engineer`, Prox1, the
  owner's review and spend approval in chat). TBD-8 closed; 6 persistence cases
  per Position, 3 real-derived carrying only an HMAC digest. Frozen graders:
  persistence 15 of 18 at session start (Fail), 17 of 18 after a compaction,
  guard 50 of 51 (Fail), offer and safety at Goal; 10.19 USD. Criterion 28 met,
  criterion 21 returned to `software-architect`; on reading, every miss but one
  is a grader false negative.

- **2026-10-08**: Proved Decision 0028's backstop live and answered TBD-7
  (`software-engineer`; the owner at the keyboard on Prox1, the branch head
  redeployed): in VS Code Local on Copilot Chat 0.69.0 the first tool call
  after `/compact` re-sent the levels with the backstop suffix and no
  PreCompact ran; Copilot CLI re-sent them through PreCompact on the deployed
  head. `turns` advances in every host, so the grace fallback is not built;
  criteria 22 and 30 met. Ruling A19 (Amendment 4) keeps the Meter's retry and
  makes a run with a failed measured launch evidence only; built test-first.
  Full gate: 3,293 tests, 0 failed. Prox1 runs `main` again, scratch removed.

- **2026-10-08**: Set Decision 0028's latency levels by the re-baseline rule
  (`software-engineer`, from the owner's third RAANDREE3 invocation and its
  CSV): `SessionStart.AddedLatency` Budget 2.0, `PostToolUse.CallLatency` 0.75;
  transfer check passed for both tags (TBD-6 closed); stop lines clear;
  criteria 20, 26, and 29 met. The RAANDREE3 `FailFast` traced to the .NET
  10.0.6 runtime of its PowerShell 7.6.1, not to this repository's code.

- **2026-10-07**: Amendment 3 (A14-A18) signed off; A17/A18 built test-first.
  The reader-shaped Prox1 Meter lost no replicate, spread at most 1.16.

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

- Desktop `CopilotAtelier New\LEDGER.md` owns the local queue: 01-08 and P1-P9.
  It keeps Decision 0028 gates, dependencies, and duplicate/superseded references.
- Merge `ai/session-lessons` (six local commits, not pushed) into `main`: the
  five lessons of the 2026-10-08 live check (Pester `Result` check, `-BeTrue`
  truthiness, hook context in the tool result, `Wait-DetachedResult.ps1`, hook
  evidence locations) are done there, with the Instruction wording reviewed by
  the owner on 2026-10-09. Expect small conflicts in `CHANGELOG.md`, the Memory
  Bank, and the hooks README.
- One-process `windows` launcher (ruling A11): separate work against Decision
  0016, kept here because Decision records here are accepted or superseded.
  Adopt only if `tests/HookLauncher.Tests.ps1` passes unchanged (`cmd.exe`,
  `sh`, an outer PowerShell, `HOME` unset), a deny still exits `2` and blocks
  in both hosts, a Meter run on Prox1 and RAANDREE3 shows the saving, and
  Decision 0028's levels are re-baselined in the same change.
- `Get-SessionElapsed.ps1` without `-Path` reads the newest clock of the
  workspace, so a parallel chat may shadow the parent's clock (06:29 on
  2026-10-01; 10:25 and 13:24 on 2026-10-04; 11:05 on 2026-10-08). Desktop
  prompt 08 and `CopilotAtelier New\LEDGER.md` track the `-Path` fix.
- Confirm live in a fresh agent-host chat that `software-engineer` calls
  `web_fetch` for `#web/fetch`; drop the paired runtime names once
  github/copilot-cli#4594 ships fixed, per decision 0026's removal condition.
- Delete the merged remote branch `copilot/dgthths` on GitHub or from your own
  terminal; the guard blocks an agent's remote mutation.
- Run prompt 04 on the hand-patched machine; `main` is pushed.
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
