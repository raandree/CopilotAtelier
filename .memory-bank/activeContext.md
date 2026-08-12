---
status: current
last-verified: 2026-08-12
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Adopted four items from a review of an external Copilot catalogue. Everything
below is a reimplementation against this repository's own conventions rather
than a file copy, so no third-party notice is carried into the tree.

## Implemented

- `Skills/pester-patterns/scripts/Find-PesterV4Pattern.ps1` — AST scan for
  legacy `Should`, `Assert-MockCalled` and `Assert-VerifiableMock(s)`,
  `Describe`/`Context`/`It` wrapped in `InModuleScope`,
  `$MyInvocation.MyCommand.Path`, commands at file top level or in a block
  body, and retired `Invoke-Pester` parameters. It reports and never rewrites,
  because two of its finding classes are legal Pester 5.
- `Skills/pester-patterns/references/migrating-pester-v4-to-v5.md` — the
  replacements, mock scoping rules, runner parameter map, and completion
  checklist. The body grew 149 to 183 lines; the `description` is untouched, so
  the trigger surface is unchanged and no eval sweep is owed.
- `tests/SkillTriggerCoverage.Tests.ps1` — every Skill needs a query set or a
  place on a shrink-only uncovered baseline, a covered Skill fails until its
  baseline entry is removed, an orphaned set is caught, and each set is checked
  for unique ids, valid splits, and three or more positives and negatives with
  both halves populated.
- Five query sets — `pester-patterns`, `test-driven-development`,
  `sampler-build-debug`, `sampler-framework`, `sampler-migration` — the cluster
  most likely to collide. Every negative is a near miss taken from a sibling.
- `tests/SecretScan.Tests.ps1` — six high-signal credential shapes across the
  payload, module source, build, and Memory Bank, with a planted-credential
  control. Generic `password = "..."` matching was rejected as unfixably noisy.
- `tests/CustomizationFrontmatter.Tests.ps1` — Custom agent `name`,
  `description`, and a `model` array carrying a fallback entry; Instruction
  `applyTo`; Prompt `description`.
- `AGENTS.md` — an *Atomic change sets* section naming every artifact a Skill
  or a Custom agent has to move in one commit, and which test catches which
  kind of drift.

## Focused evidence

- `./build.ps1 -Tasks build, test`: 603 passed, 0 failed, 105 skipped, coverage
  78.44 %, 17 tasks, 0 errors, 1 warning. The warning is the pre-existing
  failure-isolation stub in `run-trigger-evals.ps1`.
- The detector against `./tests`: 0 `BlockBodyCommand` and 18
  `TopLevelCommand` findings, every one a deliberate discovery-time `-ForEach`
  builder. A detector that called those defects would be ignored within a day.
- Two defects were caught by running the work rather than reading it.
  Statements in a script block arrive as `PipelineAst`, so the detector's
  allow-list never matched and it reported 275 false positives against a clean
  Pester 5 suite. And the coverage test read discovery-scope paths inside `It`,
  where they are null at run time — the trap Pattern 14 documents.

## Open findings

- **The five query sets are authored but unmeasured.** Nothing has been run
  against them, so the gate proves the queries exist, not that the descriptions
  pass. Expect misses on the first sweep; that is what they are for.
- **`pester-patterns` and `sampler-migration` both claim Pester 4 to 5.** The
  tooling sits in `pester-patterns` and the legacy-project walkthrough stays in
  `sampler-migration`; neither description has been swept for the boundary. It
  is recorded as a note in both query sets rather than papered over.
- `Skills/german-employment-law/` is an empty untracked folder shipping no
  `SKILL.md`. The new baseline test is what found it.
- The README *Available Skills* table has no gate and is already behind the
  shipped set. The atomic checklist names it; nothing enforces it.
- **The `skill-creator` description edit is still not proven.** Train climbed to
  100 % while validation fell, which is the overfitting signal. It remains for
  the owner to accept or revert.
- **`-Temperature 0` does not make the judge reproducible.** Any query near the
  0.5 trigger threshold moves between runs, so a single sweep cannot settle a
  marginal query. `Invoke-ShpBatch` exposes a `-Seed` the harness does not use.
- `Prompts/export-emails.prompt.md` is a generation behind the copy deployed
  under `~/.copilot/prompts/` — 106 lines against 126. A content decision, left
  to the owner.

## Next step

Run the five sets through `run-trigger-evals.ps1` and fix what the sweep
exposes, starting with the `pester-patterns` / `sampler-migration` boundary —
the one collision already known to exist.
