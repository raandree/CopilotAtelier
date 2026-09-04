---
applyTo: "**/*.ps1,**/*.psm1,**/*.psd1,**/build.yaml,**/*.yml"
description: "How to run PowerShell from VS Code without freezing it: detach and monitor Pester and build runs, keep one-shot commands synchronous, never poll in the foreground, and handle logs and interactive prompts safely."
---

# PowerShell execution safety in VS Code

## Long-Running Commands — Detach AND Monitor, Never Direct Execution

Trigger, checkable without judgement: any command expected to exceed roughly
two minutes, and unconditionally `Invoke-Pester`, `Invoke-Build`, `build.ps1`,
`test.ps1`, any other test or build entry point, any installer, and any
deployment entry point. It fires on an agent-initiated run — no user request,
no user phrasing to match — so decide from the command, not the conversation.

Detaching and monitoring are one obligation. Load `long-running-job-monitor`
before launching; it specifies the instrumented log, the status line owed on
every in-flight reply, and the stuck-versus-working classification. A detached
run that is not instrumented and monitored is non-compliant, not
half-compliant.

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
- Do not use a `Start-Sleep` polling loop and do not re-read terminal output on
    a cadence. End the turn and let the completion notification wake the next
    one; inspect process state and logs on a status check.

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

### While a long job is in flight

- Never pipe it through `Select-Object -Last` or another buffering filter.
    Nothing reaches the terminal until the process exits, so every progress
    check returns the same frozen snapshot and a working job is
    indistinguishable from a hung one.
- Never edit source files during a verification run. Build output and Pester
    discovery are fixed at launch, so the run scores a stale artifact and has to
    be repeated in full.
- Never infer elapsed time from log file metadata. `Tee-Object` overwrites
    content while NTFS keeps `CreationTime` from an earlier run; read the job's
    own `START` line.
- Never guess liveness from a process command line. A script running inside the
    terminal's own `pwsh` never appears in one; use the job's terminal marker
    and `ResultPath`.

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
- Multi-minute monitoring falls under the launch rule above; verify progress
    through an independent target plane rather than the job's own output.

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
