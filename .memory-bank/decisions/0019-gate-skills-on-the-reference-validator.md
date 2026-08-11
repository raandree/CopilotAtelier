---
status: accepted
date: 2026-08-11
last-verified: 2026-08-11
owner: software-engineer
source: agentskills.io open standard, skills-ref reference validator at 69ef37e
---

# Gate Skills on the upstream reference validator

## Context and problem statement

`tests/SkillFrontmatter.Tests.ps1` encodes this repository's reading of the
Agent Skills specification: name shape, the 1024-character description cap, the
500-line body budget, the supported optional fields. Those assertions are ours.
Nothing checked them against the specification itself, so a drift between our
interpretation and the standard would pass every test in the suite.

The open standard ships a reference validator, `skills-ref`, which is the
authority on frontmatter and naming conformance. It is a Python package, and
this repository is a PowerShell module with no Python or package-manager
dependency of its own.

## Decision outcome

Run `skills-ref validate` over every `Skills/*/SKILL.md` as part of the test
workflow, in `tests/SkillsRefValidate.Tests.ps1`.

- **A Pester test that shells out**, not a new Sampler task. The gate is an
  assertion about repository content, so it belongs where the other content
  assertions are and it inherits their reporting, tagging, and CI wiring.
- **Hard-fail, with the validator pinned** to upstream commit `69ef37e`. A
  specification change upstream cannot turn a green build red without a
  deliberate edit here; bumping the pin is how a newer validator is adopted.
- **Fetched on demand through `uv run --with`**, not vendored and not added to
  `RequiredModules.psd1`. `uv` resolves the dependency per run and leaves no
  checked-in copy to drift.
- **One process for all Skills**, via `.build/skills-ref/validate_skills.py`.
  Per-Skill invocation costs about 50 seconds; the batch costs about 2.
- **`PYTHONUTF8=1` is set for the call.** Otherwise the validator inherits the
  Windows ANSI code page and dies on the first em-dash, which reads as a
  content error when it is really a decoding one.
- **When `uv` is absent the tests skip with a visible reason, except in CI**,
  where a missing validator throws. CI installs `uv` with `astral-sh/setup-uv`;
  a skip there would report a green build with nothing behind it.
- **Two Skills are baselined as known divergence**: `citation-integrity` and
  `social-signal-sweep` declare `context: fork`, which is a real GitHub Copilot
  feature the open specification does not define. The baseline may shrink; it
  must not grow without amending this record.

## Consequences

- The repository now depends on `uv` and, through it, Python for a full local
  test run. Neither is required to build, install, or use the module; without
  `uv` the gate reports a skip and the rest of the suite is unaffected.
- Two conformance authorities now exist. Ours stays, because it enforces house
  budgets the specification says nothing about; the reference validator covers
  the specification itself. A disagreement between them is the signal this
  gate exists to raise.
- The suite gains 46 tests, 2 of them skipped by the divergence baseline.
- Adopting a newer validator is a deliberate commit that bumps the pinned ref,
  and any new finding it produces has to be fixed or baselined here.

## Confirmation

`./build.ps1 -Tasks test` runs the validator over all 44 Skills: 42 report no
problems, 2 skip on the documented baseline. A negative test writes a fixture
with an invalid `name` to a temporary directory and asserts the validator
reports it, so the gate is proven to fail as well as to pass.
