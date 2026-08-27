---
status: current
last-verified: 2026-08-27
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Every hook was dead. The host substitutes `$` tokens in a hook command string
before the child process parses it, so `$b = if ($env:PLUGIN_ROOT) { ... }`
arrived as `= if () { ... }` and PowerShell refused it with `An expression was
expected after '('`. The only symptom was a *Warning from Session Start hook*
balloon, so the never-push block, the Memory Bank probe, and the compaction
checkpoint were all absent while looking installed. Every command in
`com.github.copilot/hooks/hooks.json` is now written without a single `$`, and
resolution probes `PLUGIN_ROOT`, then `~/.copilot/hooks`, then the plugin's
`~/.vscode*/agent-plugins/*/*/CopilotAtelier`. The corrected file was copied
into the canonical target, and both deployed hooks were run end to end.

## Still open from the 1.0 migration

The plugin package moved to Agent Plugins 1.0, and the package is now the
primary layout rather than a second view of the module payload. `plugin.json`
declares the canonical `$schema`, the legacy `agents` and `skills` path fields
are gone, `Skills/` is root `skills/`, and all four Copilot-specific component
types live under `com.github.copilot/{agents,rules,commands,hooks}`. The module
deployment is preserved by translation: the installer maps deployed name to
source path, so `~/.copilot/{agents,instructions,skills,prompts,hooks}` is
unchanged. Decision 0023 records the trade-off it accepts — cross-type relative
links are now correct in the package view and wrong in the deployed view.

Unverified and deliberately so: no documentation states whether
`.instructions.md` and `.prompt.md` register from `com.github.copilot/rules`
and `com.github.copilot/commands`. The bet is one-sided, since the module path
delivers both regardless. Confirming it needs one empirical test — install from
source and check whether the instructions and prompts appear.

## Environment hazard — scripted bulk writes corrupt file content

Two bulk PowerShell read-modify-write passes over this working tree replaced
whole file contents with a monoalphabetic substitution cipher (`instructions`
→ `nnkteuotnonk`, `applyTo` → `aeelyTo`), 129 files each time. Both were caught
and fully restored from git; no corruption reached a commit.

- It is asynchronous. The script's own byte-exact read-back verification passed
  for all 175 files, and `git diff` showed the corruption afterwards, so the
  rewrite lands after the write returns. A verify-after-write loop cannot
  detect it.
- A single-file scripted write was clean, so it correlates with volume.
- Every `replace_string_in_file` edit was clean, across roughly forty files.

Until the cause is found, edit files through the editor tooling, and treat any
scripted bulk rewrite of this tree as unsafe. `git grep -l -e nnkteuotnon -e\naeelyTo` detects it in one pass.

## Released in v4.0.0

The Custom agent slug rename, the `software-architect` agent, the usage-stats
Skill and `/usage` Prompt, the `skill-creator` split, the Instruction
`description` pass, and the compaction checkpoint all shipped in `v4.0.0`.
Their rationale lives in the `[4.0.0]` changelog section and decisions 0021
and 0022; the durable relationships they established are in
`systemPatterns.md`. Nothing from them is still open.

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
