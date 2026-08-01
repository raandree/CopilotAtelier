---
status: current
last-verified: 2026-07-30
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Stop the same CI failure recurring: bound the Memory Bank append the Post-flight
gate mandates, and make a CI-only failure cheap to reproduce.

## Implemented

- Post-flight step 2 now bounds the `progress.md` append — curate the oldest
  entries in the same edit when the file is at or near its line budget. That
  mandated, previously unbounded append is what breached the budget twice.
- `Skills/memory-bank/SKILL.md` runs the health check after any Memory Bank
  edit, not only after initialization; the append path never reached the
  initialization-scoped gate.
- `sampler-build-debug` gained "Reproduce a CI-Only Failure": derive the built
  commit from the GitVersion `+n` suffix, reproduce in a clean clone rather than
  the worktree, and the two known divergences (gitignored files present locally,
  and Sampler falling back to `0.0.1` without GitVersion).
- `.github/workflows/ci.yml` verifies `GitHubToken` and `GalleryApiToken` before
  `Publish Release`. A missing token used to let `Publish_Release_To_GitHub`
  skip while the Gallery publish still ran, shipping a version with no `v*` tag
  for the next build to anchor on. `tests/Workflows.Tests.ps1` asserts the
  guard precedes the publish step.
- Memory Bank line budgets now warn before they fail.
  `Test-MemoryBankHealth.ps1` raises `LineBudgetNearLimit` at 90 percent of a
  line budget, `MemoryBankHealth.Tests.ps1` prints those warnings so a passing
  run names the file about to breach, and `Skills/memory-bank/SKILL.md` makes
  the warning a same-turn curation task. Retention applied to `progress.md`
  took it from 200 to 154 lines; `techContext.md` was curated to 171.
- `[Unreleased]` was split so the shipped `2.0.0` sits in its own dated section,
  and `tests/QA/module.tests.ps1` fails the build past 100000 characters, which
  is the limit the GitHub release body hits.

## Focused evidence

- The GitHub release body is the changelog `[Unreleased]` section, and the REST
  API caps it at 125000 characters. It stood at 143697 because `2.0.0` shipped
  on 2026-07-29 without ever being recorded; the split left 18212.
- `ContinuousDelivery` anchors the pre-release number on the last tag, not on
  the commit count. `ShellPilot` carries the identical configuration and tags
  every published preview, `v0.2.0-preview0001` through `v0.2.0-preview0008`.
  Proven in a throwaway clone of this repository: with the unchanged
  configuration, adding the missing `v3.0.0-preview0001` tag makes the next
  commit compute `3.0.0-preview0002`.
- `PowerShellForGitHub` resolves into `output/RequiredModules` as a dependency
  of `Sampler.GitHubTasks`, so the empty half of the
  `Publish_Release_To_GitHub` condition is `GitHubToken`.
- The Memory Bank budget broke CI twice, at 205 and at 220 lines, both times in
  `progress.md`. Reproduced the second one by cloning to a temporary directory
  and checking out the commit the failing run built, derived from the `+4`
  suffix in `3.0.0-preview.1+4`; `main` had already moved on.
- Two divergences make a local run disagree with CI: a worktree carries
  gitignored files a clean checkout never has, and without `dotnet-gitversion`
  Sampler builds version `0.0.1`. The second inverted the
  `Get-CopilotAtelierVersion` staleness test, which had hard-coded `0.0.1` as
  the older version; the sentinel is now `0.0.0-behind`.
- `./build.ps1 -Tasks build, test`: build succeeded, 17 tasks, 0 errors;
  358 passed, 0 failed, 11 skipped; coverage 70.67 percent against a 65 percent
  gate.

## Next step

Add the `GitHubToken` repository secret. Until it exists the deploy job now
fails at the new guard instead of publishing an untagged release. The macOS
test leg remains unproven until it runs green.
