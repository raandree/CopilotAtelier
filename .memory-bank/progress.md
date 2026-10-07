---
status: current
last-verified: 2026-10-06
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

- **2026-10-06**: Recorded the RAANDREE3 latency Meter and criterion 22's
  manual compactions in Decision 0028: criterion 20 is not met, with one cell
  over Budget and within Fail on each machine; TBD-5 is answered no, because
  RAANDREE3's VS Code launch costs 2.4 times Prox1's; Copilot CLI re-sends the
  levels after `/compact`, and VS Code Local cannot. Returned to
  `software-architect` (second round).

- **2026-10-06**: Addressed the open Phase 2 issues (`software-engineer`): an
  independent `security-reviewer` pass of `main...b7e6502` found five Low
  issues and six test gaps, all fixed test-first (red, then green); both
  reported `Calibration.Delivery` cells are measured in the SDK runtime and
  Copilot CLI (8 of 8); the branch is deployed on Prox1 for criterion 22's
  manual compactions; criterion 21's runner, preview, and draft cases are
  ready in the private kit, with no paid run.

- **2026-10-06**: Implemented Decision 0028 test-first on
  `ai/calibration-phase-2` (`dc6c26a` to `b026161`, `software-engineer`),
  after its sign-off the same day, then Amendment 1 (rulings A1 to A8, signed
  off by `software-architect` after a `rubber-duck` review): write selection
  with `-NewContributor`, `.NET`, registration ownership through the recorded
  hash, the read-only `Get-`, the sentence budget, and the amended Meter. The
  Meter's two runs on Prox1 met every Budget except SessionStart with one
  entry in VS Code's spawn: returned to `software-architect`.

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

- Contributor calibration: `software-architect` rules on criterion 20's Prox1
  result (SessionStart with one entry in VS Code's spawn over Budget, within
  Fail). Then the amended Meter on RAANDREE3 (TBD-5), criterion 21's paid eval
  with Phase 2 groups and the private kit grown past 20 real cases
  (`-Since 2026-09-30` on RAANDREE3 and Prox1), and one manual compaction each
  in VS Code Local and Copilot CLI.
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
