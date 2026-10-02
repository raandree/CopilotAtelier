---
status: current
last-verified: 2026-10-01
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v6.0.0`, published 2026-09-30
from `a592832` (release API, verified 2026-10-01). Incremental work is tracked
under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-10-02**: Closed review finding F-03 on `ai/contributor-calibration`: a
  question that authorizes an irreversible, destructive, or security-relevant
  action offers no `not sure, you pick` option. Red then green. Side by side
  with the previous wording it changed no measured behavior (decision cases 10
  of 10 each; a push probe kept the option off the push in 2 of 2 each; 0.63
  USD). Added `docs/SECURITY-REVIEW.md` with all 32 findings. Full Windows
  `build,test` 2,319 passed, 1 failed (the v6.0.0 gate) at 90.74%.

- **2026-10-02**: Merged into local `main` by fast-forward: the v6.0.0 rollover
  (`4ee08c2`), its dropped final newline (`12428d6`), and the SessionStart fix
  replayed on top (`b9cee3b`, `139c06c`, `09e2798`), with its changelog entry
  moved back under `[Unreleased]`. Full gate on `main`: 2,288 passed, 0
  failed, 121 skipped, 90.74%. Worktree and fix branch removed. Not pushed,
  not deployed.

- **2026-10-01**: Fixed the missing SessionStart context on
  `ai/sdk-session-context` (`7bc21c6`, docs `3c4dc35` and later). The Copilot
  SDK host reads only a top-level `additionalContext`; the hook wrote only
  `hookSpecificOutput`, which VS Code's built-in Copilot extension reads for
  Local chats. It now writes both. Test red then green; full gate 2,287 passed,
  1 failed (the v6.0.0 gate). A probe chat received the fixed context once and
  no nested or plain-text marker. Not deployed, not pushed.

- **2026-10-01**: Closed the independent review of contributor calibration:
  4 Major (delegation bounds, provenance, two redaction gaps), then a passing
  fix round; every Minor and Nit fixed test-first or ruled on, F-03 parked
  (private self-check red 15, then 46 of 46). The private eval gained a pinned
  `gpt-5.5` judge (38 of 40 against human labels): full run 100% against 52.1%
  without, shipped wording 39 of 39 on the 8 cases it could affect. German
  replies are a drifting `claude-opus-5` quirk. About 7.36 USD in model calls.
  Full Windows `build,test` 2,317 passed, 2 failed at 90.74%: the v6.0.0 gate
  and a race in `LongRunningJobMonitor.Tests.ps1:229`, green in isolation.

- **2026-10-01**: First live denial since the launcher fix: a harmless push
  probe in an SDK chat was blocked. The guard matched and exited 2, the host
  logged `Hook command failed with code 1` with the reason on stderr, and the
  model saw only `(hook errored)`, so prompt 06 still applies.

- **2026-10-01**: Audited the six hook follow-up prompts on the Desktop: none
  was run, and the fix reached `main` by fast-forward without a pull request or
  the prompt-02 review. CI run 36601011621 passed ubuntu, macos, and windows,
  so prompt 03 was retired. Eight SDK sessions since the redeploy logged 1,113
  `preToolUse` runs and no failed hook, yet none received the `SessionStart`
  context: the GitHub hooks reference consumes only a top-level
  `additionalContext`, and `Add-SessionContext.ps1` nests it under
  `hookSpecificOutput`, the VS Code Local shape. Prompt 01 now targets that.

- **2026-09-30**: Added answer rules to contributor calibration: at `new` and
  `familiar` an abstract finding gets one concrete example, and a calculated
  result names its sources and method. Red 2 then green. The private eval,
  rerun with a frozen grader, scores 52.1% to 87.5% over 16 paired cases; read
  by hand, the rules appear in 8 of 8 and 7 of 8 replies, against 2 of 3 and at
  most 1 of 3 before. The exact `not sure, you pick` fell to 12 of 16 in two
  cases, delegation always offered. About 2.63 USD. Full Windows `build,test`
  2,311 passed, 1 failed (the v6.0.0 gate) at 90.74%. Not pushed.

- **2026-09-30**: Built a private behavior eval for contributor calibration from
  17 approved real-chat cases, kept outside the repository. `claude-opus-5`, K=3,
  paired cases: content 83.3% to 90.0%, decision contract 0% to 100%, all 55.6%
  to 93.3%; wrong-language replies 12 to 5. About 3.20 USD in model calls.

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
- `LongRunningJobMonitor.Tests.ps1:229` reads the heartbeat state file as soon
  as it exists, but `Set-Content` creates it before writing; it failed once in a
  full build on 2026-10-01 and passed twice alone. Poll for the field instead.
- `Get-SessionElapsed.ps1` without `-Path` reads the newest clock of the
  workspace, so a subagent or parallel chat there shadows the parent's clock
  (2026-10-01: a 06:29 start). Inject the reader with this session's `-Path`.
- Confirm live in a fresh agent-host chat that `software-engineer` calls
  `web_fetch` for `#web/fetch`; drop the paired runtime names once
  github/copilot-cli#4594 ships fixed, per decision 0026's removal condition.
- Push local `main` (5 commits ahead on 2026-10-02): it carries the v6.0.0
  rollover, so `updateChangelogAfterv6.0.0` needs no pull request, and the
  SessionStart fix. Then rebase `ai/contributor-calibration` onto it.
- Hook follow-ups, with prompts on the development machine's Desktop (amended
  2026-10-01; 03 retired): deploy the SessionStart fix, merged into local
  `main` on 2026-10-02 (01); review the shipped fix independently (02);
  run the `-Repair` deploy on the hand-patched machine from `main` (04); check
  whether VS Code turns a block (exit 2) into a warning, and whether
  `COPILOT_ATELIER_ALLOW_REMOTE` set in an agent terminal reaches the hook
  (05); and surface the block reason the SDK host drops (06).
- Copilot SDK chats load every Instruction twice, once as `C:\Users\…` and once
  as `c:\Users\…` (seen in two chats on 2026-10-01). Find which two sources
  disagree on drive-letter case; no `chat.instructionsFilesLocations` is set.
- Decide on GitVersion's `major-version-bump-message`: it matches "major"
  anywhere, so review prose in #25 moved `main` to 6.0.0.
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
  fixes the manifest. Re-adding it guards the fix and needs the `ci.yml`
  `shell: pwsh` steps distinguished from `powershell.exe`.
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
