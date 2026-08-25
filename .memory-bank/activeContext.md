---
status: current
last-verified: 2026-08-25
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Two change sets are in flight: the compaction checkpoint, committed on
`ai/precompact-checkpoint`, and the authoring schema refresh, still uncommitted
in the working tree. The release provenance fix already shipped in `f7f302d`.

## Implemented — authoring schema refresh

- `Instructions/copilot-authoring.instructions.md` re-verified against the
  current VS Code and agentskills.io documentation. Prompt `agent` is optional
  and accepts `plan` or a Custom agent name; Instructions also activate by
  semantic match on `description`; Agents gained `target`, `mcp-servers`, and
  `handoffs.model`; the hook stdout contract is documented alongside the exit
  codes; keys the repository requires but the platform does not are labelled.
- Two portability traps are now named: a Claude-format `matcher` is parsed and
  ignored, and tool input keys are camelCase here where Claude uses snake_case.
- Not changed, and reported instead: `plugin.json` is the legacy Copilot format
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

## Implemented - release provenance (shipped in `f7f302d`)

- `CHANGELOG.md` gained `[3.0.0] - 2026-08-01` and `[3.1.0] - 2026-08-07`,
  reconstructed from the two unmerged rollover commits rather than from the
  commit log, so each entry sits under the release it shipped in. 13 entries to
  `3.0.0`, 5 to `3.1.0`. Compare links filled in.
- `plugin.json` moved to `3.1.0`.
- `tests/PluginManifest.Tests.ps1` gained the release provenance gate: every
  non-preview tag reachable from `HEAD` needs a matching release section, with a
  tag at `HEAD` exempt so a tag push cannot deadlock on its own gate. The same
  file pins `plugin.json.version` to `major.minor.patch`, never a pre-release.

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
- Release provenance root cause is a merge gap, not a pipeline gap.
  `Create_ChangeLog_GitHub_PR` ran and produced
  `origin/updateChangelogAfterv3.0.0` (`e594924`) and
  `origin/updateChangelogAfterv3.1.0` (`13a16d3`). Nobody merged the pull
  requests, the task swallows failures in a `catch` that only logs, and no test
  compared tags against sections. Merging those branches today would misfile the
  July entries.
- That gate was shown to reject before it was accepted: 8 passed and 3 failed,
  naming `v3.0.0` and `v3.1.0`; after the fix 12 of 12 pass. Full suite at that
  point: 807 passed, 0 failed, 61 skipped, coverage 78.44 % against 65 %.
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
- `Skills/german-employment-law/` is gone; the working tree is clean of it.

## Next step

Get a decision on running the paid sweeps. With a go-ahead: install ShellPilot,
answer the 75 route-selection prompts against one pinned model in fresh
contexts, grade them, then sweep the seven trigger-query sets and author
`german-tax-research`'s set in the same pass. Without one, the remaining
unblocked work is splitting the nine over-budget Skill bodies, starting with
`german-legal-research` at 780 lines.
