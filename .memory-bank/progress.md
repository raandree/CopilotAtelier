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
`6.0.1-preview0001` (`fea564f`) and `6.1.0-preview0001` (`7a48abe`) to GitHub
Releases and the PowerShell Gallery (verified 2026-10-04). Incremental work is
tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-10-11**: Fixed the elapsed line that a parallel chat could take over
  (`ai/session-clock-path`, Desktop prompt 08; three commits, deployed from the
  branch the same day). `Add-SessionContext.ps1` hands the agent `& '<reader>' -Path
  '<clock>'` for the clock it wrote or resumed, quoted for PowerShell (a
  typographic single quote ends a PowerShell string too), and the shortened
  closing line keeps `-Path` while it fits. `Get-SessionElapsed.ps1`, given no
  clock, takes the one `COPILOT_AGENT_SESSION_ID` names first. 20 cases, red
  first (the fixture reproduced `5h 39m` for a 22-minute chat) and each caught by
  a mutation; the owner approved the Instruction wording. An independent review
  (the built-in `security-review` agent; the `security-reviewer` Custom agent's
  model is unavailable in the Copilot SDK runtime) found no Blocker or Major and
  three Low to Medium items, fixed test-first in the second commit: the hook's
  output is pure ASCII, since Windows PowerShell 5.1's OEM encoding turns some
  characters into a bare quote after the quoting, and the key pattern is
  case-sensitive. Redeployed the same day and live-checked with headless Copilot
  CLI sessions: Prox1 reproduced and fixed, and the old hook's silent loss of
  the context in a smart-quote folder confirmed. Decision 0024 holds the
  evidence and what stays open.

- **2026-10-09**: Applied the five session lessons on `ai/session-lessons` from
  `origin/main` (`9b6a341`), test-first, one commit each; every change went red,
  then green, in PowerShell 7.6.6 and Windows PowerShell 5.1. (1) All ten
  detached Pester guards reject a result other than `Passed` and name every
  failure count; the Pester 5.7.1 probe matched Prox1, and load failures count.
  (2) Both Pester guides name truthiness and the missing-field pitfall: 5.7.1
  also coerces `'False'` in `Should -Be $true`, so a real boolean needs
  `Should -BeOfType ([bool])` too. (3) `agent-security-review` records that both
  hosts deliver hook context in the tool result and that it is data only;
  lookalike-block escaping is untested. (4) The read-only `Wait-DetachedResult.ps1`
  waits a bounded time on a detached run, and a timeout is 124, not the 1 an
  outer EncodedCommand collapsed it to. (5) The hooks README names where VS Code
  Local, the SDK agent host, and Copilot CLI record hook evidence, scoped to the
  supplied versions. Full detached gate: 2,593 passed, 0 failed, 129 skipped,
  90.74% coverage (65% threshold), 21 build tasks in 22m38s. No paid eval or
  remote mutation; detail stays in git.

- **2026-10-04**: Fixed prompt 06 on `ai/hook-deny-reason`: Copilot SDK chats
  show the guard's block reason. A model-free probe of the bundled runtime found
  that on exit 2 it drops a PascalCase event's JSON deny that also carries
  `hookSpecificOutput`; the guard now prints the top-level pair alone. The new
  `tests/HookSdkRuntime.Tests.ps1` runs the shipped launcher and guard in that
  runtime (red, then green). Full gate 2,542 passed, 0 failed; deployed, and
  A2 and B2 then passed in new chats (sessions `d2788da5`, `874b1f34`).

- **2026-10-04**: Fixed the clock restart on resume that the live checks found:
  `Add-SessionContext.ps1` preserves a readable same-session clock on resume
  (red, then 18 of 18); corrected the changelog and hooks README. Detail stays in git.

- **2026-10-04**: Fixed an intermittent Windows CI failure, also seen on `main`
  (runs 104, 106): warm the real guard once before asserting its 5-second limit.

- **2026-10-02**: Worked through hook follow-up prompts 02, 05, and 06 on local
  `main` (`d8cc6f5` to `fea564f`); only their live checks remain.
  Ten reviews closed the launcher and guard findings; the full merge gate
  (`634546e`) passed 2,536 tests. Detail stays in git and the assessment log.

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

- Contributor calibration: the Phase 2 Design Concept with `software-architect`
  (Session handoff), and growing the private eval past 20 real cases with a
  `-Since 2026-09-30` search on RAANDREE3.
- Push `main` and delete `origin/ai/session-clock-path` from your own terminal;
  the guard blocks an agent's remote mutation. The clock pin was redeployed on
  2026-10-11; still to confirm live in a new VS Code agent-host chat and in VS
  Code Local, which the Copilot CLI runtime stood in for. Decision 0024 lists
  the cases that stay open.
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
