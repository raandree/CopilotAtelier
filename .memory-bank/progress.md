---
status: current
last-verified: 2026-11-10
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.0.0`, published 2026-09-30
from `a592832`. CI on `main` has since published the prereleases
`6.0.1-preview0001` (`fea564f`) and `6.1.0-preview0001` (`7a48abe`) to
`6.1.0-preview0024` (`4c4fbd3`, 2026-11-10) to GitHub Releases and the
PowerShell Gallery (verified 2026-11-10). Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-11-10**: Brief 03, the travel work (`software-engineer`), on `ai/travel-work`: the Markdown
  Instruction counts MD013 in UTF-16 units and keeps emoji out of linked headings (`dc1dad0`); the contained
  `quarantined-reader` agent reads untrusted text with file reading only (`5e9bb9b`);
  `authenticated-web-extraction` reads Reddit signed in through a GET-only allow-list and hands the files to
  that reader (`15fb67e`); new Skills `travel-handbook` (`bfd44f0`, uv-run Python scripts, 215 offline tests)
  and `travel-planning` (`bc27c27`), each kept by the owner's with/without rule (planning 0 vs 2 corrections;
  handbook kept on an approved rerun). An independent security review found 17 issues (3 Major); all were
  fixed test-first inside their commits. No trip is named in any shipped file. Report in the handoff folder.
- **2026-11-10**: The Task ledger stays in its Handoff sequence's folder (`software-engineer`). Briefs added
  to a folder without `LEDGER.md` now get the ledger there first, never a row in another folder's ledger;
  a Brief claims its number with its row; an Error found before a change still counts. The checker reports
  `LedgerOutsideFolder`. 10 new tests (7 red first), 2 mutants caught, 1,157 focused passed. Merged as
  #51 (`4c4fbd3`, `6.1.0-preview0024`).
- **2026-11-09**: The agents' models (`software-engineer`, owner ruling of 2026-11-09): every Custom agent
  declares Claude Opus 5.5 and Sonnet 5.5 (`spec-work-implementer` Sonnet first), Setup writes
  `copilot:claude-opus-5.5`, and a test fails a model outside the list (Decision record 0029 supersedes
  0007); red first (17 of 182). The R-04 closing test passed on a throwaway standard account. On
  `main` (`ea19ba4`, pushed without a pull request; `6.1.0-preview0022`), redeployed 2026-11-10.
- **2026-11-07**: The Skill index (`software-engineer`). The logs of two Copilot CLI chats (DeskPilot,
  ShellPilot) showed `subagent-dispatch` never loaded for "write handoff prompts": runtime 1.0.103 lists
  Skill descriptions only to 30,000 characters, VS Code's 20 synced Skills first and ours by name, so 30
  of 50 Skills reached the model as a bare name (66 logged sessions agree; VS Code chat uses 15,000).
  Added the always-applied `skill-index.instructions.md` (4,932 characters), a pre-flight pointer, and a
  `SkillCatalog` estimate in `Get-CopilotAtelierFootprint`; red first, gate 5,652 passed. On `main` (`661c30a`, `6.1.0-preview0021`).
- **2026-10-21**: The P8 checks (`software-engineer`; spending approved 2026-10-20). A new 20-query set
  measured the `subagent-dispatch` description; the new one names prompts run one per chat, briefs, the
  task ledger, and folder migration (`claude-opus-5.5` train 10 to 12 of 12, validation 7 to 8 of 8;
  `claude-haiku-4.5` train 7 to 10, validation 7 of 8). Five runs per version: E cases 27 against 9 of 35,
  decoys 20 of 20 in both; a fresh-subagent migration passed every E7 line. Merged as #48 (`ae8684d`).
- **2026-10-20**: P6, the routing-coverage ratchet (`software-engineer`), rebuilt by hand on `main` from
  the uncommitted work of 2026-10-12. Every route needs a real case or a baseline entry with a reason, a
  `role` case needs `roleFiles`, and the Full-read fallback keeps role files. Two owner-labelled cases
  cover `general` and `role`; the floor gates on 87.01 % without the `general`-only case (87.47 % over
  all 27). Red first, 13 mutants caught; gate 5,475 passed. Merged as #47 (`247a826`).

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
  are in Desktop `CopilotAtelier-handoffs` (start with `00-start-here.md`).
- Push `ai/travel-photo-diary-skill` from the other machine (`C:\Git\CopilotAtelier`, worktree
  `C:\Git\CopilotAtelier-travel-photo-diary`); it is not on GitHub (checked 2026-11-10). Until it
  is, the boundary between it and the `travel-handbook` Skill stays provisional.
- Sign in to Reddit once in the CareerAuthBrowser profile and run `reddit-read` live: the task is
  tested against a fake browser only, so its refusal of redirects is unverified against live Reddit.
- Delete any `extracted\all-cookies.json` that a `dump-cookies` run before brief 03 left in
  `%LOCALAPPDATA%\CareerAuthBrowser`: it holds cookie values in plaintext.
- `auth-state/` of `authenticated-web-extraction` keeps other sites' session cookies in plaintext for any
  agent with a shell. It predates brief 03; the review's quarantine covers Reddit text only.
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
