---
status: current
last-verified: 2026-11-12
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.1.0`, published 2026-11-11
at 19:56 UTC to GitHub and the PowerShell Gallery from `a3167d8` (#54), the
commit CI had published as `6.1.0-preview0026`. The changelog rollover #55
(`f358226`) followed at 23:43 UTC; its CI run (43122012334, GitVersion
`6.1.1-preview.1`) published nothing (Deploy skipped, confirmed 2026-11-12). Incremental work is
tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-11-12**: Brief 04, the adapter smoke check (`software-engineer`), on `ai/adapter-runtime-smoke`: cases C1 to C3 ran offline on
  the composed `software-engineer` variant in Copilot CLI 1.0.96 and the source profile in runtime 1.0.108-0; C2 passed on both, C3 on
  the variant, C1 failed on both on an ignored-field warning. Receipts bound to each file's SHA-256 let `Get-CopilotAtelierClientAdapter`
  report `RuntimeVerified` for those cases only; the fallback test went red first, then green. Full gate 5,819 passed, 0 failed.
- **2026-11-12**: Brief 05, the hook input probe (`software-engineer`), merged as #56 (`548a162`): the push guard fires in a VS Code
  agent-host chat on runtime 1.0.108-0 (live inert probe denied); the 14 `HookSdkRuntime` failures were the fixtures, which now pass
  the agent host's `enableConfigDiscovery`, `enableFileHooks`, and `enableSkills` (44 of 44); a new block pins the hook input for
  `skill`, `view` (`Read`), `edit` (`Edit`), and `create` (`Write`) in that runtime and Copilot CLI 1.0.96, red first (14 failed),
  then 18 of 18. The owner declined a Skill-use and a changed-file collector.
- **2026-11-11**: Brief 10, GitHub issue #49 (`software-engineer`), merged as #54 (`a3167d8`) and released as `v6.1.0`: the owner-ruled `Update-CopilotAtelier
  -AllowPrerelease` installs previews, and without it the command names a newer preview. Versions keep and compare their prerelease labels
  through `Get-CopilotAtelierModuleVersion` and `Compare-CopilotAtelierVersion`, also in Windows PowerShell 5.1 (no `SemanticVersion`); the
  Deployment record, `IsCurrent`, and `VersionDrift` follow; Install and Test warn about a git working tree as Canonical target. Red first;
  an independent review's Blocker (PowerShellGet 3 reports the label separately) and Major (an update that did not land) fixed test-first.
  The release run pushed the rollover branch but could not open its pull request; #55 merged it with the final newline restored.
- **2026-11-10**: Brief 03, the travel work (`software-engineer`), merged as #53 (`dc714ba`, `6.1.0-preview0025`): the Markdown
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
- Decide adapter case C1: drop `target` from the Copilot CLI variant, or let C1 tolerate fields a client documents as ignored; then
  rerun `tests/ClientAdapterRuntime.Tests.ps1` and replace the receipts in `Get-CopilotAtelierClientContract`.
- Probe VS Code Local's hook input for the Skill and file tools (tool names, payload, `matcher`) before
  any collector is reconsidered; brief 05 verified only the SDK host and Copilot CLI, offline.
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
