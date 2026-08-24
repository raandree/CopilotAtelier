---
status: current
last-verified: 2026-08-24
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Record the uncommitted `german-tax-research` hardening in the repository's
durable records. The Skill body had already gained two evidence rules and three
red flags; the changelog and the Memory Bank were the parts still missing.

## Implemented

- `Skills/german-tax-research/SKILL.md` carries *Read the operative sentence,
  not the label* and *Aggregate both directions* under the evidence rules, each
  resting on a measured counterexample rather than on a maxim.
- Three red flags extend the stop-and-re-enter list: classifying a document from
  its label, summing a transaction set through a sign filter, and editing one
  table row without printing its neighbours.
- `CHANGELOG.md` records the change under `[Unreleased]` / `Changed`.
- `progress.md` gained the 2026-08-24 milestone, and the three oldest
  2026-08-11 entries were condensed in the same edit so the append did not push
  the file into a curation warning.

## Focused evidence

- The frontmatter `description` is unchanged, so the trigger surface is the one
  already on the documented `SkillTriggerCoverage` uncovered baseline: no eval
  sweep is owed and no query set changes.
- The body is 244 lines against the 500-line progressive-disclosure budget, so
  the two new sections need no reference split.
- Memory Bank health passes with 0 errors and 0 warnings across 7 canonical
  files and 20 Decision records. `progress.md` sits at 179 of 200 lines, one
  line below the `LineBudgetNearLimit` threshold.
- No `README.md` row changes, because the catalogue lists the description and
  the description did not move.

## Open findings

- The third red flag has nothing behind it. Neither the Skill body nor its six
  references tells the reader to print a table's neighbouring rows after an
  edit, so the flag names a discipline the Skill never teaches. Either add the
  rule where the control table is built, or drop the flag.
- `german-tax-research` has still never been measured for discovery. The two new
  sections are body content, so this change neither improves nor worsens that.

## Carried forward from the route-selection eval

- `Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
  modes, and `MemoryBankRouteSelection.Tests.ps1` covers prompt isolation, label
  leakage, fallback, strict shape, reliability aggregation, and failure
  accounting.
- The 75 prompts prepared from 25 real routing cases are unanswered, so no
  route-selection pass@k or pass^k result exists yet.
- The first stage infers routes and fallback only. The deterministic resolver
  still receives human labels for `durableWrite`, role files, and relevant
  Decision records.
- Total context-window cost, latency, and answer quality under routed versus
  full loading remain unmeasured.
- Safety is gameable on its own: a reply naming every route never misses. No
  precision floor is set, because no measured baseline exists to derive one
  from, so `Passed = True` at low precision is not yet a failing build.

## Carried forward from earlier focuses

- Six trigger-query sets, `brand-logo-system` among them, are authored but have
  never been through `run-trigger-evals.ps1`.
- `WindowsAccessControl` slots 1 and 2 use the older ink-variant reading of
  dark/light, so two sets in one shared library disagree on "dark mode".
- The `brand-logo-system` integration step was measured on one project only.
- The README *Available Skills* table still has no gate.
- `Skills/german-employment-law/` is an empty untracked folder with no
  `SKILL.md`.
- The `skill-creator` description edit remains unproven: train reached 100 %
  while validation fell, which is the overfitting signal.

## Next step

Decide the unsupported red flag, then return to the route-selection eval: run
the 75 prepared prompts against one pinned model in fresh contexts, save the
strict JSON replies, and grade them. Then add separate stages for durable-write
and Decision-record selection before comparing routed and full task outcomes.
