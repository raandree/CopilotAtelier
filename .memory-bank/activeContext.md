---
status: current
last-verified: 2026-08-25
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Work the open findings on `main` without committing, at the user's explicit
request. Latest: `plugin.json` announced `2.0.0` while `v3.1.0` was the
published release, because the changelog rollover for `v3.0.0` and `v3.1.0`
never reached `main`.

## Implemented

- `CHANGELOG.md` gained `[3.0.0] - 2026-08-01` and `[3.1.0] - 2026-08-07`,
  reconstructed from the two unmerged rollover commits rather than from the
  commit log, so each entry sits under the release it shipped in. 13 entries to
  `3.0.0`, 5 to `3.1.0`, 31 stay unreleased. Compare links filled in.
- `plugin.json` moved to `3.1.0`.
- `tests/PluginManifest.Tests.ps1` gained the release provenance gate: every
  non-preview tag reachable from `HEAD` needs a matching release section, with a
  tag at `HEAD` exempt so a tag push cannot deadlock on its own gate.
- The same file pins `plugin.json.version` to `major.minor.patch`, never a
  pre-release, so the question is not renegotiated.

## Focused evidence

- Root cause is a merge gap, not a pipeline gap. `Create_ChangeLog_GitHub_PR`
  ran and produced `origin/updateChangelogAfterv3.0.0` (`e594924`) and
  `origin/updateChangelogAfterv3.1.0` (`13a16d3`). Nobody merged the pull
  requests, the task swallows failures in a `catch` that only logs, and no test
  compared tags against sections.
- Merging those branches today would misfile the July entries: `13a16d3` was cut
  from a `main` that still lacked the `3.0.0` section.
- The gate was shown to reject before it was accepted: 8 passed and 3 failed,
  naming `v3.0.0` and `v3.1.0`; after the fix 12 of 12 pass.
- Full suite after the change: 807 passed, 0 failed, 61 skipped, coverage
  78.44 % against the 65 % target, `Build succeeded with warnings` (the one
  warning is the pre-existing simulated eval backend failure).
- The changelog move is provably lossless: compared byte-exactly against the
  committed file, 0 lines lost, and the only 8 additions are the two release
  headers and their six subsection headers.
- Side effect: the `[Unreleased]` release body drops from 83,271 to 54,733
  characters, restoring headroom under the 100,000-character gate that broke a
  release on 2026-08-01.
- Writing a literal level-two release header inside changelog prose breaks
  `Get-ChangelogData`; it parsed the example as a real section and cut
  `Unreleased` to 420 characters.
- Nothing is committed. The working tree holds the three changed files plus the
  Memory Bank updates.

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
