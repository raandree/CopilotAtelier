---
status: accepted
date: 2026-07-29
last-verified: 2026-07-29
owner: software-engineer
source: Sampler build framework and PowerShell Gallery distribution requirements
---

# Distribute the library as a Sampler-built PowerShell module

## Context and problem statement

The only supported distribution was "clone the repository and run
`Setup-CopilotSettings.ps1`". That gave the library no version identity, no
update path, and no way for a consumer to tell whether the customizations
deployed to their Canonical target were current. The agent plugin manifest
covers Custom agents and Skills only, so it cannot replace the Setup script.

Sampler is already the framework this repository documents and teaches, so
using anything else would contradict its own guidance.

## Decision outcome

Convert the repository into a Sampler project published to the PowerShell
Gallery.

- Module sources live in `source/`; the five Customization directories plus
  `Keybindings/` stay at the repository root.
- A custom build task, `.build/Copy_Customizations_To_Output.build.ps1`, copies
  those directories verbatim into the built module, so a Gallery install and a
  clone carry the same payload.
- The version comes from GitVersion. `ModuleVersion` in the source manifest is
  a placeholder the build replaces.
- Three exported commands replace the monolithic script:
  `Install-CopilotAtelier`, `Update-CopilotAtelier`, and
  `Get-CopilotAtelierVersion`.
- `Setup-CopilotSettings.ps1` remains as a thin shim that dot-sources `source/`
  and installs from the clone.
- GitHub Actions builds once on Linux and tests the same artifact on Windows
  PowerShell 5.1, PowerShell 7 on Windows, and PowerShell 7 on Linux.

Keeping the Customizations at the repository root rather than moving them under
`source/` preserves `plugin.json`, every documentation link, the Hooks
configuration, and the existing test suite. The cost is one custom build task.

## Consequences

- The Canonical target folder name is fixed to `CopilotAtelier` instead of
  being derived from the clone folder name. A Gallery-installed module has no
  clone to derive from, and a stable name is required for the Deployment record
  to be meaningful. Renaming a clone no longer renames the synced layout.
- Console output moved from `Write-Host` to the information stream, so
  `Install-CopilotAtelier` is quiet by default and returns a summary object.
  The Setup script shim passes `-InformationAction Continue` to preserve the
  familiar console experience.
- `CHANGELOG.md` must stay parseable by ChangelogManagement, because Sampler's
  release tasks depend on it.
- CI/CD moved from out of scope to in scope for this repository.
- Two distribution paths now exist beside the plugin manifest. They deploy
  identical content, so the Deployment record is the single place that reports
  what is actually installed.

## Confirmation

`./build.ps1 -Tasks build, test` succeeds with all repository tests passing.
`tests/QA/module.tests.ps1` proves the built module exports exactly the three
documented commands and ships all six customization directories non-empty.
`tests/Unit/` covers the three public commands and the two load-bearing private
helpers against a sandboxed profile. `tests/Setup-CopilotSettings.Tests.ps1`
still passes unchanged, proving the shim preserves the clone entry point.
