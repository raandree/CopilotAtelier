---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Remediate the audit findings against the Agent Skills refresh (`ff9ab0a..HEAD`).

## Implemented

- `.gitignore`, `.build/Copy_Customizations_To_Output.build.ps1` — a harness run
  had left 108 scratch files under `Skills/agent-evals/scripts/work/`. Deleted,
  ignored, and pruned from the built module; `tests/QA/module.tests.ps1` asserts
  the payload carries no `work/` or `.evalwork/`.
- `Skills/agent-evals/` — declares `compatibility` (PowerShell 7,
  `powershell-yaml`, ShellPilot for `-Mode Execute`), documents the
  prerequisites, and points the harness examples outside the payload.
- `tests/SkillFrontmatter.Tests.ps1` — derives the `compatibility` requirement
  from shipped scripts that `Import-Module`, instead of a hand-kept list.
- `.github/workflows/ci.yml`, `tests/SkillsRefValidate.Tests.ps1` — CI installs
  `uv`; the gate throws instead of skipping when `$env:CI` is set, and a
  negative fixture proves it rejects an invalid `name`.
- `Skills/skill-creator/SKILL.md` — description migrated to category-level
  `USE FOR:`, so the Skill now passes its own rule.
- `.memory-bank/decisions/0019-*.md` — records the reference-validator gate.

## Focused evidence

- `./build.ps1 -Tasks build, test`: 453 tests, 0 failed, 13 skipped, coverage
  70.67 % against the 65 % threshold. The baseline before this work was
  449/436/0/13 at the same coverage.
- The prune was verified live: a scratch file placed under the skill folder was
  reported as `Pruned scratch directory` and is absent from the built module.
- The handoff's premise that `CHANGELOG.md` does not parse is false. All four
  "pre-existing failures" pass under `build.ps1`; they appear only under a bare
  `Invoke-Pester`, which lacks `RequiredModules` on `PSModulePath`.
- The three refresh commits skipped Memory Bank and changelog bookkeeping
  entirely. That omission is what this turn closes.

## Open finding

`Prompts/export-emails.prompt.md` is a generation behind the copy deployed under
`~/.copilot/prompts/` — 106 lines against 126. The deployed version parameterises
the export script and forbids hardcoded names. A build and install would regress
a working Prompt. Back-porting is a content decision, left to the owner.

## Next step

Run the outstanding handoff prompts against the corrected baseline: prompt 07
option C, the six worst keyword-stuffed descriptions, and prompt 06's
with/without delta, which stays blocked on ShellPilot exposing `-Temperature`.

Still outstanding: add the `GitHubToken` repository secret, without which the
deploy job fails at its guard; give the routing reduction gate real headroom
rather than the roughly 1 KB it has now.
