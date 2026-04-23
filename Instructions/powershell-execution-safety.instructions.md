---
applyTo: "**/*.ps1,**/*.psm1,**/*.psd1,**/*.Tests.ps1,**/build.yaml,**/build.ps1,**/RequiredModules.psd1,**/Resolve-Dependency.psd1,**/*.yml"
---

# PowerShell Execution Safety — VS Code Terminal

## MANDATORY: Detached Process for All Long-Running Commands

**NEVER** run any of these commands directly in the VS Code integrated terminal:

- `./build.ps1` (any parameters)
- `Invoke-Pester` (any parameters)
- `Invoke-Build` (any parameters)
- Any command that imports modules, runs tests, or compiles DSC configurations

This includes `pwsh -NoProfile -Command '...'` — it still blocks the terminal.

**ALWAYS** use `Start-Process` (fully detached) with log file polling.

> **WARNING — Log path**: NEVER put the log file inside the project's `output/` folder.
> Sampler's Clean task deletes everything in `output/` at the start of a build, which
> locks/deletes the log file and fails the build. Always use `$env:TEMP`.

```powershell
# Step 1: Start build detached — log MUST go to $env:TEMP (NOT output/)
$logPath = "$env:TEMP\sampler_build.log"
Remove-Item $logPath -ErrorAction SilentlyContinue
Start-Process -FilePath pwsh -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command',
    "Set-Location '$PWD'; .\build.ps1 -Tasks test *>&1 | Out-File -FilePath '$logPath' -Encoding utf8"
) -WindowStyle Hidden -PassThru

# Step 2: Poll for completion (non-blocking)
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep 3
    if (Test-Path $logPath) {
        $c = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
        if ($c -match 'Build (FAILED|succeeded)') {
            Get-Content $logPath -Tail 30
            break
        }
    }
    if ($i % 10 -eq 0) { Write-Host "Waiting... ($($i*3)s)" }
}
```

## Why This Matters

VS Code's terminal thread synchronously waits for child processes. Pester and ModuleBuilder
output can stall the pipe, freezing the entire VS Code UI. `Start-Process` creates a fully
detached process with no parent-child pipe, so VS Code never blocks.

## Common Mistakes That Still Crash VS Code

| Pattern | Why It Fails |
|---|---|
| `pwsh -Command "./build.ps1"` | Terminal still waits synchronously for the child process |
| `run_in_terminal` with `./build.ps1` directly | Same — blocks the terminal pipe |
| `runTests` tool | Runs Pester inside the PS Extension Host — instant freeze |
| Log in `output/` folder | Sampler Clean task deletes it mid-build, causing lock errors |
