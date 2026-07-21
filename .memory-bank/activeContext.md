# Active context

## Current work focus

Fixed cross-platform path resolution in `Setup-CopilotSettings.ps1`. The script
now runs on Linux without `APPDATA` or `USERPROFILE`, follows each operating
system's VS Code configuration convention, and uses symbolic links where NTFS
junctions are unavailable.

## What changed this session

- Resolve `$userHome` from `USERPROFILE` on Windows and `HOME` elsewhere, with
  a validated platform fallback.
- Resolve the VS Code user directory from `APPDATA` on Windows,
  `~/Library/Application Support` on macOS, and `XDG_CONFIG_HOME` or `~/.config`
  on Linux.
- Reuse the resolved paths for settings, keybindings, OneDrive fallback, target
  copy, and `.copilot` discovery paths.
- Create NTFS junctions on Windows and symbolic links on Unix.
- Add `tests/Setup-CopilotSettings.Tests.ps1`, which runs the real script twice
  in an isolated Linux home and verifies the XDG files, copied tree, and link.
- Confirmed the pre-fix failure also flattened customization contents into the
  repository root: `Copy-Item -Destination $null` targets the current directory.
  The root `README.md` is currently byte-for-byte identical to
  `Agents/README.md`; generated root-level copies remain pending cleanup.

## Verification

- Red: the focused Pester test failed because the XDG settings file was absent.
- Green: Pester 5.7.1 passed 1/1 tests, including the idempotent second run.
- Both changed PowerShell files parse with zero AST errors.
- PSScriptAnalyzer reports no findings for the new test and no new findings in
  the setup script relative to its committed baseline (34 existing interactive
  `Write-Host` warnings in both).
- A real `pwsh -NoProfile -File ./Setup-CopilotSettings.ps1` run completed on
  Linux and created all four symbolic links without path errors.
- A disposable reproduction confirmed that `Copy-Item -Destination $null`
  copies into the current directory. Representative root-level files and skill
  directories are byte-for-byte identical to their canonical sources, and the
  setup-fix commit does not contain `README.md`.

## Next step

Restore the root `README.md` from `HEAD` and remove only flattened root artifacts
that are proven identical to canonical files after explicit user approval.
