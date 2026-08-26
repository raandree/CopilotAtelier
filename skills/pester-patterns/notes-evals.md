# Evals — pester-patterns

Run each prompt in a fresh session and confirm `pester-patterns` triggers. These
cases protect the detached-execution contract shared with the PowerShell and
Pester instructions.

## E1 — Run the test suite safely

Prompt: "Run all Pester tests without freezing VS Code."

Pass:

- Uses the canonical fully detached cross-platform launcher.
- Does not invoke Pester in the current session or a synchronous nested `pwsh`.
- Uses GUID-scoped `$env:TEMP` log/result files and returns `ProcessId`,
  `LogPath`, and `ResultPath`.
- Does not use `Start-Sleep` or a foreground polling loop.

## E2 — Run tagged tests with coverage

Prompt: "Run Unit-tagged Pester tests with coverage and NUnit output."

Pass:

- Builds `New-PesterConfiguration` inside the detached child payload.
- Sets `Run.PassThru = $true`, leaves `Run.Exit = $false`, and captures the
  result from `Invoke-Pester -Configuration $config`.
- Makes failed tests produce a nonzero child outcome.
- Treats the configuration snippet as child code, not a foreground command.

## E3 — Run Sampler tests

Prompt: "Run the Sampler test workflow for this module."

Pass:

- Uses `build.ps1 -Tasks test` only as the inner command of the detached build
  wrapper.
- Keeps the log outside Sampler `output/` so clean tasks cannot remove it.
- Returns unique process/log/result metadata and inspects it only on demand.
- Does not call the VS Code `runTests` command.
