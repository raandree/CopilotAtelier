---
status: current
last-verified: 2026-09-29
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier's latest full GitHub release is `v5.0.0`, published 2026-09-10;
`main` published pre-release `v6.0.0-preview0001` on 2026-09-29 (release API,
verified 2026-09-29). Incremental work is tracked under `[Unreleased]` in
`CHANGELOG.md`.

## Recent milestones

- **2026-09-30**: Shipped contributor calibration Phase 1 on
  `ai/contributor-calibration` (decision 0027): the always-on
  `contributor-calibration` Instruction, `/simpler` and `/deeper`, and
  `not sure, you pick` in `grill-me`, `software-architect`, and
  `gilb-requirements-engineering`. New test red 19 then green 19; full Windows
  `build,test` 2,309 passed, 1 failed at 90.74%. The failure is the v6.0.0
  changelog gate, which fails past the tag until `updateChangelogAfterv6.0.0`
  merges. Behavior unmeasured. Not pushed.

- **2026-09-29**: Restored Custom agent tools in VS Code agent-host sessions on
  `ai/agent-runtime-tool-names` (decision 0026). The runtime drops VS Code tool
  names it cannot resolve, so every agent now pairs them with `web_fetch`,
  `grep`, `glob`, `ask_user`, and `vscodeBrowser/*`; the twelve open agents add
  seven session tools and the four contained ones gain only search and question
  names. The CLI contract emits `web_fetch`, `grep`, and `glob` instead of the
  dead `web` and `search` aliases. New test red 28 then green; offline probe 16
  of 16 agents; full Windows build/test 2,286/0/121 at 90.74%. The security
  review's parser Major was fixed (red 7 then green); its `agents:` and
  cross-session findings are recorded in 0026 for the user. Not pushed.

- **2026-09-29**: Part 2 of the hook fix. The GitHub hooks reference verifies the
  SDK host's contract: PascalCase events get the VS Code `tool_input` payload,
  `timeout` aliases `timeoutSec`, a timeout fails open, and any other non-zero
  `preToolUse` exit denies. `Block-RemoteMutation` therefore allows an unreadable
  payload with exit 0 (red 3, then focused 428/0/56). Redeployed; this session
  and its subagents did not reload hooks, so the fresh-chat check is the user's.
- **2026-09-29**: Fixed the hook launchers on `ai/fix-hook-launcher-home`. The
  Copilot SDK host copies `command` into its `powershell` field on Windows, where
  `HOME` is unset, so every `PreToolUse` call was denied as `hook errored` and
  `SessionStart` never injected context (this machine's 2026-09-24 session log
  records exactly that). Launchers now try `PLUGIN_ROOT`, `HOME`, `USERPROFILE`,
  then the OS profile folder, bypass the execution policy, and report the
  underlying error. New `tests/HookLauncher.Tests.ps1`: red 125 of 284 against
  the old launchers; full Windows build/test 2,155/0/121 at 90.67% coverage.
- **2026-09-29**: Diagnosed CI run `36549550887` (PR #26 rollover: `plugin.json`
  4.0.0 under `[5.0.0]` on all platforms); `main` was already green after #25
  (`314c795`, run `36553689149`). Fixed the cause on `ai/rollover-plugin-manifest`:
  `Update_PluginManifest_Version` runs before `Create_ChangeLog_GitHub_PR`,
  `GitHubFilesToAdd` commits the manifest, and admission never republishes
  changelog- or manifest-only pushes. Red 8 of 29; mutations caught 4 and 1;
  focused 65/0/0; full Windows build/test 1,931/0/65 at 90.67%. Not pushed.

- **2026-09-29**: Rebased `ai/eval-gate-integrity` onto `main` `16a81d3` (#26,
  the automated v5.0.0 changelog rollover). Only `2b45419` conflicted; the
  resolution keeps one `[5.0.0]` heading below the branch's `[Unreleased]`
  fixes and restores the MD047 final newline the rollover stripped. `e8961fa`
  is tree-identical to `ab68c93`; range-diff shows the other four commits
  patch-identical. Focused suites 43/0/0; markdownlint clean. Not pushed.

- **2026-09-25**: Implemented F1-F4, N1-N3, P1/P2 review follow-ups: compatible
  trigger replies, structured severity, bounded reads, stable timeout errors,
  valid sample IDs, missing edge-case coverage, CI deduplication/cancellation,
  non-publishing changelog validation, and unique release headings. Eval red
  12 then 176/0/38; CI red 18 then 43/0/0; duplicate-header mutation rejected.
  Final focused 220/0/38; full Windows build/test 1,917/0/65 at 90.67% coverage.
  Pushed `fc12ef3` and opened PR #25. Push run `36121027315` and PR run
  `36121068837` passed admission, packaging, and every platform. No deployment
  or merge; the docs-only close-out push also verifies PR deduplication live.

- **2026-09-24**: Independent review of `7a186c5..2b45419` approved the eval/CI
  batch with no Blocker, Major, or exploitable vulnerability. Four Minor
  observations concern reply-format compatibility, message-derived severity,
  duplicate CI cost, and future rollover coordination; the sample-query ID gap
  was verified as pre-existing. No implementation changes or remote mutations.
  The prior exact-head run `36043691291` is green; review records stay local.

- **2026-09-24**: Research-backed evaluation gate hardening on
  `ai/eval-gate-integrity`: strict case/ID validation, literal substring
  matching, exact sample counts, bounded regex execution, and trigger failures
  that cannot disappear into correct negatives or smaller denominators.
  Original scripts failed 28 of 45 corrected CLI regressions. Full Windows gate
  1,875/0/67 at 90.67% coverage preceded final self-review follow-ups; rebuilt
  affected gate 634/0/59 passed afterward. Topic pushes run the unchanged
  three-platform CI matrix without enabling deployment. No live
  model quality, trigger discovery, or containment improvement is claimed.
  First-push CI run `36040997940` caught the overdue v5 release rollover after
  the tag-at-HEAD exemption lapsed. Restored its verified history and static
  plugin version; repair gate 40/0/0. No remote merge or weakened gate.

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
  (Session handoff), and a Phase 1 behavior eval on 20 to 50 real chats.
- Confirm live in a fresh agent-host chat that `software-engineer` calls
  `web_fetch` for `#web/fetch`; drop the paired runtime names once
  github/copilot-cli#4594 ships fixed, per decision 0026's removal condition.
- Merge `updateChangelogAfterv6.0.0`, which carries `plugin.json` (checked
  locally 2026-09-30); until then every commit past v6.0.0 fails that gate.
- Hook follow-ups, with prompts on the development machine's Desktop: check
  whether VS Code wraps hook commands in PowerShell `-Command`, which would turn
  a block (exit 2) into a warning; check whether `COPILOT_ATELIER_ALLOW_REMOTE`
  set in an agent terminal reaches the hook, which the host starts with its own
  environment; and surface the block reason the SDK host drops.
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
