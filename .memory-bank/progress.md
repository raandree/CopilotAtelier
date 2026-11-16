---
status: current
last-verified: 2026-11-14
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.1.0`, published 2026-11-11
at 19:56 UTC to GitHub and the PowerShell Gallery from `a3167d8` (#54), the
commit CI had published as `6.1.0-preview0026`. The changelog rollover #55
(`f358226`) followed at 23:43 UTC; its CI run (43122012334, GitVersion
`6.1.1-preview.1`) published nothing (Deploy skipped, confirmed 2026-11-12). The newest
pre-release is `6.2.0-preview0002`, which CI published from #58 (`aea224e`, run 43431374837) on 2026-11-13
at 13:59 UTC. Incremental work is tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-11-14**: Brief 15, a CI retry for the Gallery bootstrap (`software-engineer`, a controller run), on `ai/ci-gallery-bootstrap-retry`,
  stacked on brief 14, not pushed. The `Package Module` job resolves its dependencies in a step of its own: up to three attempts, 15 and 45 s
  apart, each in a new pwsh, each retry without what a failed attempt saved, 15 minutes at most; `pack`, the tests and the release run once.
  Red first; every mutant caught. Approve with eight Nits, then Approve with two, all fixed; gate 6,073 passed, 0 failed, 91.61 %.
- **2026-11-14**: Brief 14, a run id for `-Revalidate` (`software-engineer`, a controller run), on `ai/revalidate-run-id`, stacked on brief 12,
  not pushed. Design (a) under the owner's delegation: the profile names its run in `runId` (`schemaVersion` 2, new for every run), and
  `LedgerRun` requires every validated ledger record to carry it, so another run's sealed ledger no longer revalidates. Red first; N02 caught in
  six forms. Approve with changes, then Approve with two Nits; gate 6,064 passed, 0 failed, 91.61 %. Verifier `9e150ba8…5c65`; appender unchanged.
- **2026-11-14**: Brief 12, the module folders in `WritableRoots` (`software-engineer`, a controller run), on `ai/writable-roots-module-folders`,
  stacked on brief 17, not pushed. Q1 to Q4 under the owner's delegation: the check also measures every place PowerShell loads modules from,
  Windows PowerShell 5.1's included, inside a declared root or not; a place this identity can replace counts as writable; every path and reason
  is relayed. Red first; 64 mutants, X09 equivalent. Request changes twice (R12-01 to R12-09), then Approve; gate 5,989 passed, 0 failed, 91.61 %.
- **2026-11-14**: Brief 17, C2 that fails closed (`software-engineer`, a controller run), on `ai/c2-fail-closed`, stacked on brief 16, not
  pushed. Option 1 under the owner's delegation: C2 fails while any delegation tool is offered to the VS Code client; one helper decides C1
  and C2 for each run and, on every CI leg, for each receipt's recorded `Observation`; `RuntimeVerified` needs every case to pass, read
  exactly. Red first; every reviewer mutant caught. Approve with changes, Approve, a Nit round; gate 5,893 passed, 0 failed, 91.61 %.
- **2026-11-14**: Brief 16, the Reddit quarantine (`software-engineer`, a controller run), on `ai/reddit-quarantine`, stacked on brief 13,
  not pushed. Option 1 under the owner's delegation: `quarantined-reader` is user-invocable and hidden from the subagent list, the agent only
  runs `reddit-read` and declines to run the reader, and the user reads its summary in a chat of its own; `reddit-read` refuses without
  `headless: false`. Red first; seven SHA-256 pins; every reviewer mutant caught. Request changes, then Approve; gate 5,878 passed, 0 failed.
- **2026-11-13**: Re-review of the review fixes nobody had reviewed (`software-engineer`, the owner's ruling): brief 13 Approve; #54
  Approve with four Nits (handoff backlog); #57 Approve with changes, so brief 17 (C2 fails closed); #53 Request changes, two Majors in
  the Reddit quarantine, so brief 16. #58 and #56 left out as low risk; no GitHub review existed on #53 to #58.
- **2026-11-13**: Brief 13, S-19 (`software-engineer`), pushed on `ai/s19-replayed-acknowledgement`: the ledger client counts the sink's
  records before it sends and believes only a later sequence (`sequence > n`, the owner's ruling), so a replayed identical record is refused,
  and a sink it cannot count stops the send. Red first (the replay exited 0 on `aea224e`); 14 mutants caught. Review: Approve with changes,
  then Approve on re-review; R13-01 to R13-09 fixed. New appender digest `f55e163b…0572`.
- **2026-11-13**: Brief 11, S-20 (`software-engineer`), merged as #58 (`aea224e`, 13:10 UTC): the appender's two lines about a dropped
  connection and the hook check's four exception texts, two closure details and interpreter path are relayed as printable ASCII,
  closing S-20, V-05 and W-03 (red first, 8 and then 2 tests; 12 mutants caught). The S-04/S-05 functions and the `-Validate`
  stored-line case run on every system. Review: Approve with changes; R11-02 to R11-06 fixed, R11-01 (26+ verifier texts) a follow-up.
- **2026-11-12**: Brief 04, the adapter smoke check (`software-engineer`), merged as #57 (`0859e9e`): cases C1 to C3 ran offline; the
  composed `software-engineer` variant passed all three on Copilot CLI 1.0.96 once it stopped emitting `target`, and the source profile
  failed C1 and C2 on runtime 1.0.108-0, whose agent host ignores `agents:`. Receipts bound to each file's SHA-256 raise the state only for
  passed runtime cases; fallback test red first. An independent review's 2 Major (unbounded delegation, untested binding) fixed test-first.

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
  non-inferiority, health, provenance, route-coverage, compactness, and rollback checks.

## Open work

- Desktop `CopilotAtelier New\LEDGER.md` keeps the queue's history (01-08 and P2-P20) with
  Decision 0028 gates, dependencies, and duplicate/superseded references; the open prompts
  are in Desktop `CopilotAtelier-handoffs` (start with `00-README.md`).
- Close #49 when you like; its reply is posted, and CI run 43122012334 (the #55 merge) published nothing.
- Probe VS Code Local's hook input for the Skill and file tools (tool names, payload, `matcher`) before
  any collector is reconsidered; brief 05 verified only the SDK host and Copilot CLI, offline.
- Push `ai/travel-photo-diary-skill` from the other machine (`C:\Git\CopilotAtelier`, worktree
  `C:\Git\CopilotAtelier-travel-photo-diary`); it is not on GitHub (checked 2026-11-10). Until it
  is, the boundary between it and the `travel-handbook` Skill stays provisional.
- Sign in to Reddit once in the CareerAuthBrowser profile and run `reddit-read` live: the task is
  tested against a fake browser only, so its refusal of redirects is unverified against live Reddit.
- Delete any `extracted\all-cookies.json` that a `dump-cookies` run before brief 03 left in
  `%LOCALAPPDATA%\CareerAuthBrowser`: it holds cookie values in plaintext.
- `auth-state/` of `authenticated-web-extraction` keeps other sites' session cookies in plaintext for any agent with a shell, and
  `quarantined-reader` can read it; encrypting it (option 2 of brief 16) and brief 16's two other follow-ups are in the handoff `backlog.md`.
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
- Run the thirteen other trigger-query sets (the two travel sets of 2026-11-10 included), then cover the 36 Skills still on
  the `SkillTriggerCoverage` uncovered baseline; only `subagent-dispatch`'s set
  has run (2026-10-21). ShellPilot reads a folded `>-` description as `>-`,
  which likely explains why no Skill loaded in the wiki case; give it one-line
  copies. Native discovery is still unmeasured.
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
