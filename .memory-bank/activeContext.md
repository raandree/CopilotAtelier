---
status: current
last-verified: 2026-08-25
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

PR 47 shipped in `345a25e`, carrying two fixes: the Windows PowerShell 5.1
`Install-Module` regression that affected every release since `2.0.0`, and the
CI failure its own pipeline then hit. The usage-stats Skill and `/usage` Prompt
land with this merge. Three other change sets are in flight: the compaction
checkpoint, committed on `ai/precompact-checkpoint`; the authoring schema
refresh, shipped in `39dd690` with a follow-on `description` fix on
`ai/authoring-instruction-description`; and the `skill-creator` split stacked on
that branch. The release provenance fix shipped in `f7f302d`.

## Implemented — usage stats

- `Skills/copilot-usage-stats/SKILL.md` and the `/usage` Prompt on `Ctrl+K U`
  answer "how much has this project consumed" from `session_usage`.
- A hook was ruled out on evidence: no hook event carries usage, the transcript
  records `assistant.turn_end` as `{"turnId":"0"}`, and the local
  `session-store.db` has no `events` table and no token column.
- `input_tokens` already contains `cache_read_tokens`; the difference is the
  fresh share. `sessions.repository` is unnormalized, so scope with `ILIKE`
  over both `repository` and `cwd` or most of a project's history is dropped.
- Copilot bills usage, not requests, since 2026-06-01, so tokens convert to AI
  credits at 1 credit = $0.01. The `cost` column is a legacy request multiplier,
  not money. Billing cached input at the input rate inflates by ~10x.

## Implemented — PR 47, manifest encoding

- Root cause reproduced directly: `Test-ModuleManifest` against the built
  `4.0.0` manifest under real `powershell.exe` failed with "not a valid Windows
  PowerShell restricted language file" at an em dash that had been mis-decoded
  into mojibake. `Install-Module` discards that detail and reports only "not a
  properly-formed module", which is why issue #20 could not be actioned from
  the error text alone.
- `Create_Changelog_Release_Output` saves the manifest without a byte-order
  mark; Windows PowerShell 5.1 decodes a BOM-less file with the ANSI code page,
  so every non-ASCII character in the embedded release notes corrupts on read.
- The same defect was diagnosed on 2026-07-29 and closed by deleting the CI leg
  that caught it, on the premise that nobody runs the module on that host.
  Issue #20 falsified the premise. Fixed at the source this time:
  `.build/Repair_ManifestEncoding.build.ps1` re-saves the manifest as UTF-8 with
  a BOM, with a regression assertion in `tests/QA/module.tests.ps1`.

## Implemented — PR 47, the CI failure it exposed

- The PR build failed in `Package Module` while GitVersion had actually
  **succeeded**: exit code 0 and valid JSON. Two independent defects stacked.
- `GitVersion.yml` left `feature` and `hotfix` unanchored, so
  `ai/fix-manifest-bom-ps51` matched both — `ai/` and `fix-`. GitVersion takes
  the first match and warns about the rest on stdout.
- `ci.yml` read that same stdout and required it to start with `{`, so the
  warning turned a good run into `did not return JSON`. It now locates the JSON
  block, echoes any preamble as diagnostics instead of discarding it, and fails
  with the parser message when the block will not parse.
- Both regexes are anchored, and a new `-ForEach` gate asserts every
  representative branch name matches exactly one configuration. Shown to reject
  first: `'ai/fix-manifest-bom-ps51' matched: feature, hotfix, but got 2`, 821
  passed and 1 failed; after the fix 822 of 822 pass.
- The parsing change was exercised against the captured CI output before it
  shipped: the run CI rejected now yields `4.0.0-PR0021.43`, clean output still
  parses, and output with no JSON is still rejected.

## Implemented — skill-creator split

- Body 492 → 344 lines behind `references/authoring-patterns.md` and
  `references/scripts-and-evaluation.md`, both one level deep.
- The cut line is "only add context the model does not already have": what
  upstream already teaches moved out, what only this repository knows stayed.
- Settled whether an `instruction-creator` Skill is owed. It is not: creation is
  owned by `copilot-authoring` and verification by `agent-evals`.

## Implemented — authoring schema refresh (shipped in `39dd690`)

- `Instructions/copilot-authoring.instructions.md` re-verified against current
  VS Code and agentskills.io documentation: Prompt `agent` is optional,
  Instructions also activate by semantic match on `description`, Agents gained
  `target`, `mcp-servers`, and `handoffs.model`, and the hook stdout contract
  now joins the exit codes. House rules are labelled as such.
- Two portability traps: a Claude-format `matcher` is parsed then ignored, and
  tool input keys are camelCase here where Claude uses snake_case.
- The Instruction declares its own `description`; `applyTo` matches only files
  that already exist, so the "Instruction, Skill, or Hook?" question asked
  before anything is created could never reach it.
- Open and reported, not changed: `plugin.json` is the legacy Copilot format
  and its description claims hooks are outside the plugin format, which Agent
  Plugins 1.0 no longer makes true.

## Implemented — compaction checkpoint

- `Hooks/scripts/Write-CompactionCheckpoint.ps1` runs on `PreCompact` and writes
  `.memory-bank/session/compaction-<UTC>Z.md` with the trigger, transcript path,
  branch, commit, changed paths, and a resume protocol.
- `Instructions/preflight.instructions.md` gained a *Compaction recovery*
  section: distrust the summary, read the newest checkpoint, re-apply routes,
  re-read the driving Customizations from disk, verify the working tree.
- Decision 0021 records the split and what it cannot do; `.gitignore`,
  `.memory-bank/session/README.md`, and `Hooks/README.md` carry the artifact.

## Focused evidence

- `PreCompact` supports the common output format only. There is no
  `additionalContext` field, so no hook can inject text into the
  post-compaction context; the recovery half must be an Instruction, which is
  re-sent with every request. This is the constraint that shaped the design, not
  a simplification.
- `tests/Hooks.Tests.ps1` went red first for the right reason — missing script,
  missing event — then 48 of 48 pass. Coverage includes a payload that smuggles
  a newline and a forged list item into a file an agent reads back.
- The hook writes nothing when the workspace has no Memory Bank or the payload
  names no workspace. Guessing from the spawn directory would drop a checkpoint
  into an unrelated repository, which the unreadable-payload test would have
  done against this repo.
- Writing a literal level-two release header inside changelog prose breaks
  `Get-ChangelogData`; it parsed the example as a real section.
- `Instructions/copilot-authoring.instructions.md` carries unrelated in-progress
  frontmatter-schema work. It is deliberately excluded from the checkpoint
  commit and left in the working tree.

## Blocked, not deferred

The ShellPilot module and `Invoke-ShpBatch` are absent on this machine, so
`-Mode Execute` is unavailable for both eval harnesses. That blocks the two
measurement items outright rather than by choice of priority:

- The 75 prepared route-selection prompts cannot be answered, so no
  pass@k or pass^k result exists yet.
- The seven authored trigger-query sets cannot be swept, so `german-tax-research`
  and the other 37 baselined Skills stay unmeasured for discovery.

Both need ShellPilot plus a paid model backend, and a sweep costs money, so the
run needs an explicit go-ahead rather than an assumption.

## Open findings

- No trigger-query set was authored for `german-tax-research`. Adding one would
  flip its coverage test from skipped to enforced while the sweep that gives it
  meaning cannot run, growing the "authored but never measured" debt the seven
  existing sets already represent. Author it with the sweep, not before.

## Carried forward from the route-selection eval

- `Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
  modes, and `MemoryBankRouteSelection.Tests.ps1` covers prompt isolation, label
  leakage, fallback, strict shape, reliability aggregation, and failure
  accounting.
- The first stage infers routes and fallback only. The deterministic resolver
  still receives human labels for `durableWrite`, role files, and relevant
  Decision records.
- Total context-window cost, latency, and answer quality under routed versus
  full loading remain unmeasured.
- Safety is gameable on its own: a reply naming every route never misses. No
  precision floor is set, because no measured baseline exists to derive one
  from, so `Passed = True` at low precision is not yet a failing build.

## Carried forward from earlier focuses

- `WindowsAccessControl` slots 1 and 2 use the older ink-variant reading of
  dark/light, so two sets in one shared library disagree on "dark mode". That
  repository is not in this workspace.
- The `brand-logo-system` integration step was measured on one project only.
- The `skill-creator` description edit remains unproven: train reached 100 %
  while validation fell, which is the overfitting signal.

## Next step

Get a decision on running the paid sweeps. With a go-ahead: install ShellPilot,
answer the 75 route-selection prompts against one pinned model in fresh
contexts, grade them, then sweep the seven trigger-query sets and author
`german-tax-research`'s set in the same pass. Without one, the remaining
unblocked work is splitting the nine over-budget Skill bodies, starting with
`german-legal-research` at 780 lines.
