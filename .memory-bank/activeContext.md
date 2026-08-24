---
status: current
last-verified: 2026-08-24
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Work the open findings on `main` without committing, at the user's explicit
request. Two landed: the unsupported `german-tax-research` red flag is gone, and
the README *Available Skills* catalogue has both its missing rows and a gate.

## Implemented

- `Skills/german-tax-research/SKILL.md` no longer carries *Editing one row of a
  table without printing its neighbours afterwards*. The flag pointed at nothing
  the Skill or its six references teaches, and it is editing-tool hygiene rather
  than tax material. Removed instead of retro-fitted with invented evidence.
- `README.md` gained the nine missing catalogue rows: `agent-evals`,
  `agent-security-review`, `doc-coauthoring`, `evidence-package-assembly`,
  `gilb-requirements-engineering`, `grill-me`, `mcp-builder`,
  `pswritehtml-reporting`, `skill-creator`.
- `tests/SkillCatalogue.Tests.ps1` is the new gate: every shipped Skill has a
  row, every row names a shipped Skill, every row carries a description, and a
  count assertion guards the parser itself.
- `AGENTS.md` lists the gate in its enforcement table.
- `CHANGELOG.md` records the gate, the catalogue repair, and the dropped flag,
  and the unreleased tax-research entry no longer claims the third red flag.

## Focused evidence

- Drift measured before the fix: 36 catalogue rows against 45 shipped Skills,
  0 orphan rows.
- The gate was shown to reject before it was accepted. With the `agent-evals`
  row removed the run is 133 passed and 1 failed, naming
  `agent-evals has a catalogue row`; restored, 136 of 136 pass.
- `SkillCatalogue`, `SkillTriggerCoverage`, `SkillFrontmatter`, and
  `SkillsRefValidate` together: 488 passed, 0 failed, 60 skipped, exit 0.
- `markdownlint-cli2` reports 0 issues across `README.md`, `AGENTS.md`, and
  `Skills/german-tax-research/SKILL.md`.
- The parser reads the `## Available Skills` section only. A whole-file scan
  reads `**Agents**` and `**Instructions**` from the folder table as Skills, so
  the orphan check would fail on rows never meant to name one.
- `techContext.md` needs no matching edit: it delegates to `Skills/` rather than
  holding a per-Skill inventory.
- Nothing is committed. The working tree holds all five changed files.

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
