---
status: current
last-verified: 2026-10-16
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.0.0`, published 2026-09-30
from `a592832`. CI on `main` has since published the prereleases
`6.0.1-preview0001` (`fea564f`) and `6.1.0-preview0001` (`7a48abe`) to
`6.1.0-preview0014` (`3481536`, 2026-10-16) to GitHub Releases and the
PowerShell Gallery (verified 2026-10-16). Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-10-16**: The pinned hook line under the PowerShell hosts (`software-engineer`, `review: on`),
  the first follow-up after R-04 that the owner chose (option A of a design note), built on
  `ai/hook-line-under-hosts` after #42 merged: `HookContract` also runs the line under Windows
  PowerShell 5.1 and the PowerShell that runs the verifier, built from the README's table of hosts,
  and needs 0, 2, 2 under all three; each wrapper is shown closed to the run identity first, and a
  quoted program path now fails (1, 1, 1 under both wrappers; the old check passed it). Three reviews
  (Approve with changes, Approve with changes, Approve; 16 findings, mostly wording that claimed more
  than was run), 95 mutation checks none of which survived, gates of 5,328, 5,341 and 5,341 passed.
  No host ran the line (decision 0025, revision 2026-10-16). Not pushed.
- **2026-10-15**: R-04 (`software-engineer`, `review: on`), the first P5 follow-up, built on
  `ai/r04-run-identity-token` after #41 merged (`0145cbf`, `6.1.0-preview0013`): the required
  check `IdentityPrivilege` reads the access token of the verifier process and refuses one that
  is not a standard account's (elevated, split administrator token, above Medium integrity, the
  Administrators group in any state, or a privilege outside five; a thread that impersonates
  is unmeasured), and gates the hook probe, git and the appender. One review said Approve with
  changes (no Blocker or Major, 10 Minors, 2 Nits); the fixes are test first with 109 mutation
  checks, none survived. Full gate on `840a438`: 5,276 passed, 0 failed, 147 skipped, 90.84 %.
  A delta check said Approve with changes (2 Minors, 4 Nits, none fixed in code). The Pass is
  tested through a seam (decision 0025, revision 2026-10-15). Merged as #42 on 2026-10-16
  (squash `3481536`, `6.1.0-preview0014`; CI 5,232, 4,298 and 4,296 passed, none failed).
- **2026-10-12 to 2026-10-15**: P5 (`software-engineer`, `review: on`) rebuilt the containment
  verifier `Test-RunContainment.ps1` and the ledger appender `Invoke-LedgerAppender.ps1` after
  a first review that said Block (13 findings). Nine independent reviews in all; each fix round
  but the last found something new in the code the previous one added, the two Majors
  (S-21, S-25) in `Get-HookInterpreter`, whose hook-line check became a plain shape held to
  the PowerShell parser by a seeded test; the last, part F, said Approve. The claims shrank
  where a reviewer showed them too large (decision 0025). Final gate on `d8eddb4`: 5,063
  passed, 0 failed, 146 skipped, 90.84 %. Written down as not done: the pinned line run under
  the PowerShell hosts, S-33, a two-account test (R-04 and the hook line followed, above). Merged as #40 on
  2026-10-15 (squash `0531814`, `6.1.0-preview0012`; `main` CI 5,020, 4,145 and 4,143 passed,
  none failed); `systemPatterns.md` has the patterns CI found.
- **2026-10-13 to 2026-10-14**: P2 (`software-engineer`, `review: on`) built the Remote grant
  on `ai/hook-ask-remote-approval`: a Grant marker the user types in their own prompt, such
  as `[[allow-remote: git push, gh pr create]]`, makes the new `UserPromptSubmit` hook
  `Add-RemoteGrant.ps1` record a short-lived, session-bound grant that
  `Block-RemoteMutation.ps1` consumes, the same in the Agent Host, VS Code Local, and Copilot
  CLI. A hook `ask` was disproved live (the Agent Host approves it under auto-approve),
  `COPILOT_ATELIER_ALLOW_REMOTE` is removed, and the guard reads PowerShell as a syntax tree,
  so a string that only mentions a blocked command passes. Seven independent review passes
  (three rejections, an approval with changes, three more the owner asked for, and a bounded
  delta check) left no Blocker or Major, each finding a test that failed first; live
  acceptance passed on 2026-10-13. Merged as #38 (squash `1c1327e`, 2026-10-14 09:29 UTC;
  `6.1.0-preview0011`) after one CI fix: a Windows runner stall made the guard name its time
  limit, so the two new suites run it with the longest limit it accepts. Decision 0016 holds
  the evidence; `activeContext.md` the state.
- **2026-10-12**: Merged #32 to #36 into `main` one at a time (`6.1.0-preview0005` to `0009`):
  #34 corrects the `automatedlab-deployment` Skill (P7), #35 hands a command the user runs
  over in its own fenced code block (P3), #36 adds the task ledger and `/migrate-handoff-sequence`
  to `subagent-dispatch` (P8; no external eval ran). The review of the hand-merged hook scripts
  approved with changes (M-01 to M-06; M-04, a `.familiarity` name collision, stays open).

## Stable capabilities

- Deterministic lifecycle hooks that block remote mutation (a Grant marker in the
  user's own prompt authorizes one) and prove Memory Bank presence without relying
  on model compliance.
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
