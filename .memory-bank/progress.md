---
status: current
last-verified: 2026-10-18
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.0.0`, published 2026-09-30
from `a592832`. CI on `main` has since published the prereleases
`6.0.1-preview0001` (`fea564f`) and `6.1.0-preview0001` (`7a48abe`) to
`6.1.0-preview0017` (`a481c9d`, 2026-10-18) to GitHub Releases and the
PowerShell Gallery (verified 2026-10-18). Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-10-18**: The property test of the hook-line shape on a fresh seed (`software-engineer`,
  `review: on`), the next P5 follow-up, built on `ai/property-test-fresh-seed`: on CI the seeded test
  runs once more on a seed it draws and prints with the PowerShell version, and
  `CONTAINMENT_PROPERTY_SEED=N` runs one again (a bad value fails). Generator and comparison moved
  into helpers with the same random stream (same results for 11 seeds); one review (`code-review`
  agent) found them unpinned: 78 tests, 65 mutants caught, gate 5,405 passed. Test-only. Not pushed.
- **2026-10-18**: S-33 (`software-engineer`, `review: on`), the next P5 follow-up: `Get-HookInterpreter`
  refuses a program path with a second colon, after the one of the drive letter, quoted or not (a quoted
  one passed the drive rule and ended at "could not be measured"). Seven rows red first, 15 mutants
  caught, a 200,000-line differential changed only colon paths. One review (built-in `security-review`
  agent): Approve with changes, no vulnerability, 6 findings fixed; gate 5,374 passed. Merged as #45
  (squash `a481c9d`, `6.1.0-preview0017`; Windows CI 5,332 passed); carries the records of #43 and #44.
- **2026-10-17**: The Remote grant tests (`software-engineer`, `review: on`), merged as #44 (squash
  `ab01e51`, `6.1.0-preview0015`): 3 of the 4 red Windows legs in 14 since 13 October were a runner stall
  that made the guard fail closed and a harmless empty grant file that stays on Windows. `Invoke-Guard`
  retries a call once after exit 2 at 5 s or more (at most 5 per run, warned); the concurrent-push test
  asserts what the guard promises. Test-only: 28 tests, 39 mutants caught, one review, gate 5,304 passed.
- **2026-10-16**: The pinned hook line under the PowerShell hosts (`software-engineer`, `review: on`):
  `HookContract` also runs the line under Windows PowerShell 5.1 and the PowerShell that runs the
  verifier, built from the README's table of hosts, and needs 0, 2, 2 under all three; each wrapper is
  shown closed to the run identity first, and a quoted program path now fails. Three reviews (16 findings,
  mostly wording), 95 mutants caught, gate 5,341 passed; no host ran the line (decision 0025, revision
  2026-10-16). Merged as #43 (squash `1de0c04`, `6.1.0-preview0016`; Windows CI 5,325 passed).
- **2026-10-15**: R-04 (`software-engineer`, `review: on`): the required check `IdentityPrivilege` reads
  the verifier's access token and refuses one that is not a standard account's (elevated, split
  administrator token, above Medium integrity, the Administrators group, or a privilege outside five;
  an impersonating thread is unmeasured), and gates the hook probe, git and the appender. One review and a
  delta check (Approve with changes), 109 mutants caught, gate 5,276 passed; the Pass is tested through a
  seam (decision 0025, revision 2026-10-15). Merged as #42 (squash `3481536`, `6.1.0-preview0014`).
- **2026-10-12 to 2026-10-15**: P5 (`software-engineer`, `review: on`) rebuilt the containment verifier
  `Test-RunContainment.ps1` and the ledger appender `Invoke-LedgerAppender.ps1` after a first review
  that said Block (13 findings). Nine independent reviews in all; each fix round but the last found
  something new in the code the previous one added, the two Majors (S-21, S-25) in
  `Get-HookInterpreter`, whose hook-line check became a plain shape held to the PowerShell parser by a
  seeded test; the last said Approve. The claims shrank where a reviewer showed them too large
  (decision 0025). Final gate on `d8eddb4`: 5,063 passed. Not done: a two-account test (R-04, the hook
  line and S-33 followed, above). Merged as #40 on 2026-10-15 (squash `0531814`, `6.1.0-preview0012`);
  `systemPatterns.md` has the patterns CI found.
- **2026-10-13 to 2026-10-14**: P2 (`software-engineer`, `review: on`) built the Remote grant: a Grant
  marker the user types in their own prompt, such as `[[allow-remote: git push, gh pr create]]`, makes
  the new `UserPromptSubmit` hook `Add-RemoteGrant.ps1` record a short-lived, session-bound grant that
  `Block-RemoteMutation.ps1` consumes, the same in the Agent Host, VS Code Local, and Copilot CLI. A hook
  `ask` was disproved live (the Agent Host approves it under auto-approve),
  `COPILOT_ATELIER_ALLOW_REMOTE` is removed, and the guard reads PowerShell as a syntax tree. Seven
  independent review passes left no Blocker or Major; live acceptance passed on 2026-10-13. Merged as
  #38 (squash `1c1327e`, `6.1.0-preview0011`). Decision 0016 holds the evidence.
- **2026-10-12**: Merged #32 to #36 one at a time (`6.1.0-preview0005` to `0009`): P7, P3 (a command the
  user runs comes in its own fenced block) and P8 (the task ledger). The review of the hand-merged hook
  scripts approved with changes (M-01 to M-06; M-04, a `.familiarity` name collision, stays open).

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

- Desktop `CopilotAtelier New\LEDGER.md` owns the local queue: 01-08 and P2-P9.
  It keeps Decision 0028 gates, dependencies, and duplicate/superseded references.
  The owner ruled on 06c, P6, and P8 on 2026-10-20; the P6 rebuild and the P8 checks run next.
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
