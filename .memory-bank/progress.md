---
status: current
last-verified: 2026-10-04
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

- **2026-10-04**: Fixed prompt 06 on `ai/hook-deny-reason`: Copilot SDK chats
  show the guard's block reason. A model-free probe of the bundled runtime found
  that on exit 2 it drops a PascalCase event's JSON deny that also carries
  `hookSpecificOutput`; the guard now prints the top-level pair alone. The new
  `tests/HookSdkRuntime.Tests.ps1` runs the shipped launcher and guard in that
  runtime (red, then green). Full gate 2,542 passed, 0 failed; deployed, and
  A2 and B2 then passed in new chats (sessions `d2788da5`, `874b1f34`).

- **2026-10-04**: Fixed the clock restart on resume that the live checks found:
  `Add-SessionContext.ps1` keeps a readable clock of the same session when
  `sessionStart` arrives with `source: resume` (red, then 18 of 18). Corrected
  the `[Unreleased]` changelog entry and the hooks README, which claimed the
  SDK host reads the guard's reason on exit 2. Not deployed yet.

- **2026-10-04**: Fixed an intermittent Windows CI failure, also seen on `main`
  (runs 104, 106): a cold runner's first Windows PowerShell run of the real
  guard overran its 5-second limit and blocked a benign command. The launcher
  integration block now warms it up once, unasserted.

- **2026-10-02**: Live checks after the deploy (VS Code 1.140.0, SDK
  1.0.15-preview.4), verified against the session logs on 2026-10-04. A1 and
  B1 to B3 passed: SessionStart context once per chat in both hosts, measured
  clocks, and Local blocks the probe with the full reason, also with the
  override set in the agent's terminal. A2 failed: the SDK denied the probe,
  but the model read only `hook exited with code 2` (fixed 2026-10-04).

- **2026-10-02**: Pushed `main` and merged pull request #27 (contributor
  calibration Phase 1, with review finding F-03 closed and
  `docs/SECURITY-REVIEW.md`) as `7a48abe`; CI run 37058264901 passed and
  published `6.1.0-preview0001`. Closed #19, the API key question. Only `main`
  and the merged `copilot/dgthths` remain on GitHub.

- **2026-10-02**: Worked through hook follow-up prompts 02, 05, and 06 on local
  `main` (`d8cc6f5` to `fea564f`); only their live checks remain.
  - The post-release review failed the v6.0.0 launcher fix: in VS Code Local
    chats on Windows the push guard only warned, because VS Code's outer
    `powershell.exe -Command` reports exit 2 as 1 (Blocker, reproduced).
  - Nine re-reviews followed; every Blocker and Major was fixed test-first
    (SEC-13 to SEC-33, assessment log). The guard now decides within about
    5 s (1 MB parse, 20,000-field walk, 4 MB block caps) and joins split
    command fields in document order and per object, and on its raw path also
    across the payload. The last re-review approved.
  - The override cannot reach a hook from an agent terminal, so an authorized
    push runs in the user's own terminal; never persist it. The SDK host gets
    its own `powershell` launcher and the reason on stdout.
  - Hook suites: 559 passed, 0 failed; full gate of the merge (`634546e`)
    2,536 passed, 0 failed. Deployed: hooks match the source, the deployment
    is healthy, and a push exits 2 with its reason in both host spawns.

- **2026-10-02**: The version now rises only from Conventional Commit markers
  (`31042ea`, `bd60b7a`), approved by an independent review; `main` was then
  merged into `ai/contributor-calibration` (`e0955fb`).

- **2026-10-02**: Fixed the `LongRunningJobMonitor.Tests.ps1` flake (`bff3ac4`):
  the heartbeat state is renamed over atomically, also on Windows PowerShell
  5.1; torn reads fell from 2 to 94 per run to none in 18.

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
