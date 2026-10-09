---
status: current
last-verified: 2026-10-09
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

- **2026-10-09**: Session lessons full gate: detached `build.ps1 -Tasks build,test`
  passed 2,593 tests, 0 failed, 129 skipped, 90.74% coverage (65% threshold),
  21 build tasks and 0 errors in 22m38s. The existing simulated-backend warning
  remains. All five items are local only; no paid eval or remote mutation.

- **2026-10-09**: Session lessons item 5: add Reading hook evidence for VS Code
  Local, the SDK agent host, and Copilot CLI, scoped to the supplied Windows
  versions/dates. Main's README names logs, transcript limits, compaction
  differences, and read-only sharing flags without adding calibration state.

- **2026-10-09**: Session lessons item 4: the read-only bounded async waiter,
  its full help, and matching Skill/Instruction wiring. Presence went red then
  green in both editions; 11 behavior checks and three wiring checks went red,
  then the combined monitor and guidance suite passed all 70 in each edition.
  Native async monitoring returned `DETACHED-RESULT 0 after 19.1 s` and 29.6 s.
  Timeout is 124, not the 1 an outer EncodedCommand had collapsed it to; the
  test runner now passes LASTEXITCODE through. No foreground polling or paid eval.

- **2026-10-09**: Session lessons item 3: record both hosts' tool-result delivery
  of hook context and its data-only trust boundary in `agent-security-review`.
  Version/date-scoped supplied observations remain explicit; lookalike-block
  escaping is untested. Three checks went red, then green, in both editions; lint is clean.

- **2026-10-09**: Session lessons item 2: name truthiness and the missing-field
  pitfall in both Pester guides. Pester 5.7.1 also coerces `'False'` in
  `Should -Be $true`, so a real boolean needs `Should -BeOfType ([bool])` too;
  the actual comparer uses `Expected -eq Actual`. Six guidance checks went red
  in each edition, then all 27 passed; the three characterizations retain the evidence.

- **2026-10-09**: Session lessons item 1 on `ai/session-lessons` from
  `origin/main` (`9b6a341`): all ten detached Pester guards reject a result
  other than `Passed` and name every failure count; E2 includes load failures.
  Pester 5.7.1 probe matched Prox1: Parse and Discovery `Failed/0/1`, BeforeAll
  `Failed/1/0`, Truthy and Skipped `Passed/0/0` (Result/FailedCount/containers);
  no-tests returned nothing and printed its diagnostic. FailedCount rejection
  in that order: false, false, true, false, false, false; Result rejection:
  true, true, true, false, false, true. The supplied probe is outside the tree.
  Guidance regression: 12 of 18 red, then 18 green, in both PowerShell
  7.6.6 and Windows PowerShell 5.1. No paid eval or remote mutation.

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
- `Get-SessionElapsed.ps1` without `-Path` reads the newest clock of the
  workspace, so a subagent or parallel chat there shadows the parent's clock
  (2026-10-01: a 06:29 start). Inject the reader with this session's `-Path`.
- Confirm live in a fresh agent-host chat that `software-engineer` calls
  `web_fetch` for `#web/fetch`; drop the paired runtime names once
  github/copilot-cli#4594 ships fixed, per decision 0026's removal condition.
- Delete the merged remote branch `copilot/dgthths` on GitHub or from your own
  terminal; the guard blocks an agent's remote mutation.
- Merge `ai/hook-deny-reason` (prompt 06; A2 and B2 passed on 2026-10-04),
  and run prompt 04 on the hand-patched machine; `main` is pushed.
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
