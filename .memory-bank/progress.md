---
status: current
last-verified: 2026-10-13
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.0.0`, published 2026-09-30
from `a592832`. CI on `main` has since published the prereleases
`6.0.1-preview0001` (`fea564f`) and `6.1.0-preview0001` (`7a48abe`) to
`6.1.0-preview0009` (`e393875`, 2026-10-12) to GitHub Releases and the
PowerShell Gallery (verified 2026-10-12). Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-10-13**: P2 (Desktop prompt, `software-engineer`, `review: on`, Prox1) built the
  Remote grant on `ai/hook-ask-remote-approval`. A Grant marker the user types in their
  own prompt, such as `[[allow-remote: git push, gh pr create]]`, makes the new
  `UserPromptSubmit` hook `Add-RemoteGrant.ps1` record a short-lived, session-bound
  grant that `Block-RemoteMutation.ps1` consumes; it works the same in the Agent Host,
  VS Code Local, and Copilot CLI. A hook `ask` was disproved live (the Agent Host
  approves it under `chat.tools.global.autoApprove`); `COPILOT_ATELIER_ALLOW_REMOTE` is
  removed. The guard now reads PowerShell as a syntax tree, so a string that only
  mentions a blocked command passes (evidence item 2). The independent review rejected
  three rounds (provider drives that define and run code, parameter spellings the guard
  did not know, a quadratic analysis that outlasted the hook timeout, `git --% push`, one
  grant use for a loop of pushes) and approved the fourth with changes; each finding is a
  test that failed first. Live acceptance on 2026-10-13 passed in the Agent Host, VS Code
  Local, and Copilot CLI 1.0.96 started as usual and under `--yolo` (no marker: denied;
  marker: pushed once; auto-approval and `--yolo` did not lift the block). Decision 0016
  holds the evidence; `activeContext.md` holds the state.
- **2026-10-12**: Merged #32 to #36 into `main` one at a time (CI runs #130, #139 to
  #142; `6.1.0-preview0005` to `0009` on GitHub Releases and the Gallery; `main` is
  `e393875`). The review of the hand-merged hook scripts approved with changes
  (`ddf5430` fixed M-01 and M-02; #33 tested M-03, M-05, M-06); M-04, a
  `.familiarity` name collision, stays open.
- **2026-10-12**: #34 corrects the `automatedlab-deployment` Skill (`Remove-LabVMSnapshot`
  also removes the newer checkpoints; P7). #35 hands a command the user runs over in
  its own fenced code block (P3; live after a redeploy). #36 adds the task ledger and
  `/migrate-handoff-sequence` to `subagent-dispatch` (P8; no external eval ran).
- **2026-10-12**: Ran Desktop prompt 06c (`review: on`): four review rounds over the eval
  kit's egress code, 2 Blockers and 7 Majors fixed test-first; E-08, E-09, E-15, E-16
  stay open and no further run is authorized (A34). `docs/SECURITY-REVIEW.md` holds it.
- **2026-10-11**: Closed out Decision 0028 (Desktop prompt 07). The close-out matrix
  proves criteria 1 to 20 and 22 to 30; **criterion 21 stays not met**, worded as A39
  fixes it. Full gate on `ef96c2d`: 3,243 passed, 0 failed, 129 skipped, 90.84 %
  coverage; pull request #32.
- **2026-10-09 to 2026-10-11**: Desktop prompts 03 and 08 reached `main` (`6286ad4`):
  detached Pester guards reject a result other than `Passed`, `Wait-DetachedResult.ps1`,
  and the Post-flight elapsed line pinned to its own chat's clock (Decision 0024).
  The criterion 21 chain (prompts 04 to 06b and 05c, Amendments 5 to 7: persistence
  83.3 %, one fresh run) ended record-only. Records: the Decision's Confirmation.
- **2026-10-02 to 2026-10-08**: Hook follow-ups (`d8cc6f5` to `fea564f`: Copilot SDK
  chats show the guard's block reason, a resumed chat keeps its clock, ten reviews
  closed the launcher and guard findings) and Decision 0028 steps 7.1 to 7.5.
  Detail stays in git.

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
