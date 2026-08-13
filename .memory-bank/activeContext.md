---
status: current
last-verified: 2026-08-19
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Measure natural-language Memory Bank route selection independently from the
deterministic resolver that consumes human-labelled routes. Rebased onto `main`
on 2026-08-19; the `brand-logo-system` findings below were carried forward from
the focus this replaced, because nothing in this change resolves them.

## Implemented

- `Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
  modes. Prompts contain only one natural-language task and the Memory Bank
  index; human routes, required files, provenance, and resolver flags stay
  hidden.
- Grade mode accepts only exact JSON objects with a route array and Boolean
  fallback, compares routes without relying on order, and reports pass@k and
  pass^k while separating wrong, malformed, and missing replies.
- `MemoryBankRouteSelection.Tests.ps1` covers prompt isolation, label leakage,
  fallback, strict shape, reliability aggregation, and failure accounting.
- The Skill, eval notes, README catalogue, changelog, and Decision 0014 explain
  the deterministic resolver gate versus the natural-language selection gate.

## Focused evidence

- The first focused run failed because the evaluator did not exist; four tests
  now pass. A second red-green cycle proved scalar `routes` was accepted before
  the parser required an array.
- Prepare mode generated 75 isolated prompt files from all 25 real routing
  cases at three repetitions without contacting a model.
- The full build passes 607 tests with 0 failures and 105 skips, coverage
  78.44 %, 17 tasks, 0 errors, and the known simulated-backend warning.
- Memory Bank health has 0 warnings; deterministic routing has 0 misses and
  58.42 % average version-controlled context reduction.
- Both changed PowerShell files parse cleanly and have 0 PSScriptAnalyzer
  warning or error findings; editor diagnostics report 0 errors.

## Open findings

- The 75 prompts are prepared but unanswered, so no route-selection pass@k or
  pass^k result exists yet.
- The first stage infers routes and fallback only. The deterministic resolver
  still receives human labels for `durableWrite`, role files, and relevant
  Decision records.
- Total context-window cost, latency, and answer quality under routed versus
  full loading remain unmeasured.
- Grading demands an exact route set, so a safe superset that loses no context
  scores the same as a miss. The deterministic gate grades critical-file misses
  instead, and Decision 0014 now asks every case to clear pass^k against the
  stricter rule.

## Carried forward from the previous focus

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

Run the 75 prepared prompts against one pinned model in fresh contexts, save the
strict JSON replies, and grade them. Then add separate stages for durable-write
and Decision-record selection before comparing routed and full task outcomes.
