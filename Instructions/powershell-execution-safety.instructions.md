---
applyTo: "**/*.ps1,**/*.psm1,**/*.psd1,**/*.Tests.ps1,**/build.yaml,**/build.ps1,**/RequiredModules.psd1,**/Resolve-Dependency.psd1,**/*.yml"
---

# PowerShell execution safety in VS Code

## Running Tests & Builds — NEVER Use Direct Execution

- Always run `Invoke-Pester`, `Invoke-Build`, and build entry points such as
    `build.ps1` in a new, fully detached process. The canonical helper uses
    `Start-Process` on Windows and `nohup` on non-Windows systems.
- Never invoke them in the current PowerShell session or through a synchronous
    nested `pwsh -Command`. Their module loading and output can block the
    PowerShell Extension or terminal pipe and freeze VS Code.
- Never use the VS Code `runTests` command for PowerShell tests.
- Launch with `Start-DetachedPowerShell.ps1`, write merged PowerShell streams
    to a persistent log under `$env:TEMP`, and return `ProcessId`, `LogPath`,
    and `ResultPath` metadata.
- Do not use a `Start-Sleep` polling loop. Inspect process state and logs only
    on a later status check, or apply `long-running-job-monitor` when ongoing
    progress reporting is required.

```powershell
$runId = [guid]::NewGuid().ToString('N')
$logPath = Join-Path $env:TEMP "sampler-build-$runId.log"

$workingDirectory = $PWD.Path.Replace("'", "''")
$escapedLogPath = $logPath.Replace("'", "''")
$payload = @"
Set-Location -LiteralPath '$workingDirectory'
`$ErrorActionPreference = 'Stop'
try {
    & {
        .\build.ps1 -Tasks test
    } *>&1 | Out-File -LiteralPath '$escapedLogPath' -Encoding utf8
}
catch {
    `$_ | Format-List * -Force | Out-String |
        Out-File -LiteralPath '$escapedLogPath' -Encoding utf8 -Append
    throw
}
"@
$encodedPayload = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($payload)
)
$launcherPath = Join-Path $HOME (
    '.copilot/skills/long-running-job-monitor/scripts/Start-DetachedPowerShell.ps1'
)
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Detached launcher not found: $launcherPath"
}
$launch = & $launcherPath -EncodedCommand $encodedPayload

[pscustomobject]@{
    ProcessId = $launch.ProcessId
    LogPath   = $logPath
    Platform  = $launch.Platform
    ResultPath = $launch.ResultPath
}
```

Use the same detached wrapper with an inner `Invoke-Pester` or `Invoke-Build`
command. The child catch appends terminating errors and exits nonzero. Do not
route child streams through `Start-Process` redirection. PowerShell can serialize
non-output streams as CLIXML; merge them inside the child command as shown.

On a later status check, `ResultPath` absent means no completion result is
available yet; content `0` means success and `1` means failure. Read the log for
details. Never poll either path in a foreground sleep loop.

## Other One-Shot Commands

- Run other installs, module imports, scripts, and DSC compilation through the
    terminal tool in synchronous mode.
- Omit the timeout unless the command has a known hang risk.
- Treat synchronous output as final. Read terminal output again only when the
    tool explicitly reports backgrounding, timeout, or input required.
- Do not start a nested process merely to make an ordinary one-shot command
    asynchronous.

## Indefinite processes

- Use asynchronous mode only for servers, watchers, daemons, and other
    processes that must remain running while work continues.
- Wait for terminal completion notifications. Do not poll background commands.
- For detached builds, tests, or multi-minute deployment monitoring, apply
    `long-running-job-monitor` and verify progress through an independent target
    plane.

## Persistent logs

- Write persistent logs under `$env:TEMP`, never the repository `output/`
    directory. Sampler clean tasks can remove or lock files under `output/`.
- Give every detached run a unique log name so overlapping runs cannot delete
    or interleave each other's output.
- Use the child-side stream merge in the canonical detached launcher above.
- Avoid `Start-Process -RedirectStandardError` for a PowerShell child when a
    plain-text log is expected; redirect inside the child command instead.
- Let the terminal tool spill oversized output to its managed temporary file;
    read or search that file only when needed.

## Interactive commands

- Run interactive commands without output filters so prompts remain visible.
- Collect non-secret prompt values one at a time.
- Require the user to type passwords, tokens, and passphrases directly into the
    terminal; never route secrets through chat tools.
