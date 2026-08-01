---
status: current
last-verified: 2026-07-30
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Keep every `main` build publishable: the Gallery rejected a second push of
`3.0.0-preview0001`, because the release that shipped it was never tagged.

## Implemented

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
  took it from 200 to 154 lines. `techContext.md` at 194 of 200 is now flagged.
- `german-tax-research` audited against the consolidated statutory text in force
  on 1 August 2026. Four factual defects corrected: the `§ 237 AO` AdV interest
  rate (0.5 % per month, not the `§ 233a`-only 0.15 %), the `Art. 97 § 36 Abs. 3
  Nr. 5/7 EGAO` overrides of the 14- and 15-month counts for VZ 2020 to 2024,
  the `§ 238 Abs. 1c AO` review interval, and the VZ 2025 childcare-cost rule.
  Everything else the audit touched checked out against primary sources.
- `skill-creator` classifies the baseline failure before prescribing a form.
  Discipline failures take the prohibition triad; shaping failures take a
  positive recipe; omissions take a required structural slot; conditional
  behaviour takes a predicate-keyed conditional. Nuance clauses and exemption
  clauses are banned because both reopen the negotiation.
- `agent-evals` carries a wording micro-test loop: fresh context per sample, a
  mandatory no-guidance control arm whose clean result is a stop condition, five
  or more repetitions, manual reading of every flagged match, and variance as a
  metric.
- `debugging-and-error-recovery` instruments every boundary in a layered system
  in one pass before hypothesising, and treats the third failed fix as a design
  signal rather than a cue for a fourth attempt.
- New `subagent-dispatch` Skill: model tier per task with an explicit-model rule,
  the five-part dispatch that excludes session history, artifacts handed over as
  files, no pre-judging a reviewer, a compaction-surviving ledger, a four-status
  report protocol where the diff is the evidence, and a five-round fix cap with
  model escalation and written adjudication. Skill count 40 → 41.
- A Sampler project: `source/` holds the module, `build.ps1`, `build.yaml`,
  `RequiredModules.psd1`, `Resolve-Dependency.*`, and `GitVersion.yml` drive the
  build, and `.build/Copy_Customizations_To_Output.build.ps1` copies the six
  customization directories verbatim into the built module.
- Three exported commands replace the 560-line setup script:
  `Install-CopilotAtelier`, `Update-CopilotAtelier`, and
  `Get-CopilotAtelierVersion`, over six private helpers.
  `Setup-CopilotSettings.ps1` remains as a clone entry point shim that
  dot-sources `source/` and installs from the working tree.
- `.github/workflows/ci.yml`: aligned with the shared Sampler CI template used
  by the sibling repositories (ShellPilot is the reference). A `Package Module`
  job computes the version with GitVersion, exports every GitVersion property as
  a step output, stamps `FullSemVer` into the job summary, and uploads `output/`;
  `Test` reuses that artifact on Linux, macOS, and Windows, all on PowerShell 7,
  with the non-Windows legs tag-limited to `Unit` and `QA`; `Deploy Module`
  publishes from `main` or a `v*` tag behind an upstream-owner check. Secrets are
  `GitHubToken` and `GalleryApiToken`. The Windows PowerShell 5.1 leg was dropped
  on 2026-07-30; the module is not used on that runtime.
- `tests/QA/module.tests.ps1` plus `tests/Unit/{Public,Private}/` cover the
  command surface, the shipped payload, help quality, static analysis, and the
  behavior of every exported command.
- A README Quick Start at the top of the file, plus the day-two loop in the
  Gallery section: useful switches, a `Get-Help` pointer, sample
  `Get-CopilotAtelierVersion` output, and the multi-machine story. It states
  that the Gallery package is not published yet; remove that note with the
  first release.
- A `Hooks/` Customization deployed to `~/.copilot/hooks`, a root `plugin.json`,
  model priority arrays with a GA fallback, `compatibility` on 25 Skills, and
  `context: fork` on the two Skills that ingest untrusted external content.

## Focused evidence

- `ContinuousDelivery` anchors the pre-release number on the last tag, not on
  the commit count. `ShellPilot` carries the identical configuration and tags
  every published preview, `v0.2.0-preview0001` through `v0.2.0-preview0008`.
  Proven in a throwaway clone of this repository: with the unchanged
  configuration, adding the missing `v3.0.0-preview0001` tag makes the next
  commit compute `3.0.0-preview0002`.
- `PowerShellForGitHub` resolves into `output/RequiredModules` as a dependency
  of `Sampler.GitHubTasks`, so the empty half of the
  `Publish_Release_To_GitHub` condition is `GitHubToken`.
- CI run 30526269252 failed only on the Windows PowerShell 5.1 leg, in
  `Invoke_Pester_Tests_v5`, before a test ran. The built manifest is UTF-8
  without a byte order mark and carries 63 non-ASCII bytes from the stamped
  release notes; Windows PowerShell 5.1 decodes a BOM-less file with the ANSI
  code page, so `→` (`E2 86 92`) becomes a sequence ending in `'`, which the
  tokenizer treats as a string delimiter. Reproduced locally: the same file
  imports cleanly with `Import-PowerShellDataFile` on PowerShell 7 and fails to
  parse the moment its bytes are decoded as code page 1252. The leg is removed
  rather than worked around. `./build.ps1 -Tasks test` on PowerShell 7:
  347 passed, 0 failed, coverage 70.67 percent against a 65 percent gate.
- The four changed Skill files lint clean with `markdownlint-cli2` and stay
  within the 500-line body budget; the parameterized
  `tests/SkillFrontmatter.Tests.ps1` covers the new `subagent-dispatch` Skill,
  so its `description` and `compatibility` sit within the specification caps.
- Run 30462902820 failed with `ConvertFrom-Json: Unexpected character
  encountered while parsing value: M. Path '', line 0, position 0`. GitVersion
  5.12.0 installed and ran; its standard output began with `M` instead of `{`.
  The step piped it straight into `ConvertFrom-Json`, and GitVersion logs to
  standard output, so the real message was consumed and never printed. Root
  cause still unknown; the rewritten step prints it on the next tag build.
- A GitVersion failure log begins with `INFO` on both 5.12 and 6.3, verified by
  separating the streams, so the branch-configuration path is **not** what broke
  the run. The `release-tag` entry stays as hardening: it turns a reproducible
  exit 1 on a detached tag checkout into `FullSemVer 2.0.0`, with and without
  branch refs, and leaves `main` and `ai/*` versions unchanged.
- CI after the workflow alignment: macOS failed because two test suites
  expected the Linux configuration root, and both Windows legs failed the
  untagged Memory Bank budget check. After the fix, `./build.ps1 -Tasks
  build, test` passes on PowerShell 7 (342 passed, 0 failed, 70.67 percent
  coverage) and `-Tasks test` passes on Windows PowerShell 5.1 (332 passed,
  0 failed, 21 skipped). The macOS leg is unverified locally; CI is the proof.
- `./build.ps1 -Tasks build, test`: build succeeded, 17 tasks, 0 errors;
  339 passed, 0 failed, 11 skipped; code coverage 70.77 percent against a
  65 percent gate.
- AST parse clean across all 28 changed PowerShell files; PSScriptAnalyzer
  reports zero findings on `source/`, `.build/`, and the setup shim.
- `tests/Setup-CopilotSettings.Tests.ps1` passes unchanged, proving the shim
  preserves the documented clone entry point and its parameters.
- Three real defects surfaced and were fixed while migrating: the
  `[System.Management.Automation.PSCustomObject]` cast does not convert a
  hashtable, so every returned object was broken until the `[PSCustomObject]`
  accelerator was used; `ConvertFrom-Json` rehydrates the ISO 8601 deployment
  stamp into a `DateTime`, so `DeployedOn` is now normalised to UTC rather than
  leaking a mixed type; and `CHANGELOG.md` did not parse with
  `Get-ChangelogData`, which would have broken Sampler's release tasks.
- Decision 18 records the module distribution model and its two behavior
  changes: the fixed `CopilotAtelier` target folder name and the move from
  `Write-Host` to the information stream.

## Next step

Add the `GitHubToken` repository secret. Until it exists the deploy job now
fails at the new guard instead of publishing an untagged release. The macOS
test leg remains unproven until it runs green.
