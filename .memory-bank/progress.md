---
status: current
last-verified: 2026-10-07
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

- **2026-10-07**: Signed off and built Decision 0028 Amendment 3
  (`software-architect` drafted and recorded A14 to A18; the owner accepted
  all six recommended answers; `software-engineer` built A17 and A18
  test-first). The unit is now a reader-shaped frozen reference under one
  composite pin; the Prox1 Meter under it lost no replicate, spread at most
  1.16, both stop lines clear. RAANDREE3 runs next, by the owner.

- **2026-10-07**: Built Decision 0028 Amendment 2 steps 1 and 2 test-first
  (`software-engineer`): the frozen reference script and amended Meter (A9),
  and the backstop re-send in the three calibration hooks (A12), criteria 10,
  14, 26, and 27 tested in both editions; the full gate passed 3,138 tests
  after Decision 0028's `status` was restored. The Prox1 Meter ran and stopped
  on the unit: about 80 ms through the launcher, lost to jitter in one VS Code
  replicate, with both stop lines clear. Four questions returned to
  `software-architect`.

- **2026-10-07**: Signed off Decision 0028 Amendment 2 (`software-architect`
  as a subagent of `software-engineer`; the owner accepted all four
  decisions): rulings A9 to A13 replace the launch unit with a frozen
  reference script, withdraw criterion 20's two verdicts, restate the hook
  cost per machine, add a bounded per-turn backstop re-send for VS Code
  Local, and allow derived and reviewed synthetic persistence cases. An
  independent `security-reviewer` pass found no Blocker; its 12 findings are
  resolved in the text. Nothing is implemented yet.

- **2026-10-07**: VS Code Local runs no PreCompact for a background
  compaction either (Copilot Chat 0.68.0), found when a 70,000-token threshold
  set for the retest made one prompt loop through 2,001 requests and 99
  compactions; the threshold is removed. VS Code's agent host (SDK runtime)
  re-sent the levels after each of three automatic compactions, and the model
  noticed them unprompted. The owner ruled out asking VS Code for a change.
  Three machines' whole histories (2,706 messages) add 2 real level
  statements, both `new`, to the approved Phase 1 cases; the private finder's
  files now state its version. Both gaps returned to `software-architect`
  (questions 4 and 5).

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

- Contributor calibration, Decision 0028: the owner runs the amended Meter
  twice on RAANDREE3; then the re-baseline rule, one `w` per tag across both
  machines (TBD-6 transfer check per tag, both stop lines, the spread); one
  manual compaction in VS Code Local proves the backstop within one turn and
  measures TBD-7, which decides the grace fallback (criteria 22 and 30); A13
  rebuilds the persistence set (TBD-8, owner review of synthetic cases,
  approval and budget before any paid eval).
- One-process `windows` launcher (ruling A11): separate work against Decision
  0016, kept here because Decision records here are accepted or superseded.
  Adopt only if `tests/HookLauncher.Tests.ps1` passes unchanged (`cmd.exe`,
  `sh`, an outer PowerShell, `HOME` unset), a deny still exits `2` and blocks
  in both hosts, a Meter run on Prox1 and RAANDREE3 shows the saving, and
  Decision 0028's levels are re-baselined in the same change.
- `Get-SessionElapsed.ps1` without `-Path` reads the newest clock of the
  workspace, so a subagent or parallel chat there shadows the parent's clock
  (2026-10-01: a 06:29 start; 2026-10-04, in one Copilot SDK chat: a 10:25 and
  a 13:24 start). Inject the reader with this session's `-Path`.
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
  capture the trigger-eval harness's expected simulated backend failure so the
  successful full build emits no warning.
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
