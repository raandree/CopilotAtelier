---
status: current
last-verified: 2026-07-29
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Migrate CopilotAtelier to a Sampler-built PowerShell module so it can be
distributed through the PowerShell Gallery with a version, an update command,
and a record of what is deployed.

## Implemented

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
  `Test` reuses that artifact on Linux, macOS, Windows PowerShell 7, and Windows
  PowerShell 5.1, with the non-Windows legs tag-limited to `Unit` and `QA`;
  `Deploy Module` publishes from `main` or a `v*` tag behind an upstream-owner
  check. Secrets are `GitHubToken` and `GalleryApiToken`.
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

Verify the GitHub Actions workflow on a real run, add the `GitHubToken` and
`GalleryApiToken` repository secrets, and tag the first Gallery release as
`v2.0.0` so GitVersion anchors on a tag instead of `next-version`. The macOS
test leg is new and has never run; treat its first execution as unproven.
