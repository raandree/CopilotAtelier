#Requires -Version 5.1

<#
.SYNOPSIS
    Waits for the result of a short detached PowerShell job.
.DESCRIPTION
    Run through the terminal tool in async mode only. A synchronous wait blocks
    the chat, and a detached waiter notifies nobody. Polls in 500 ms steps with
    a bounded timeout. Reads only; writes and deletes nothing.
.PARAMETER ResultPath
    The ResultPath returned by Start-DetachedPowerShell.ps1, containing 0 or 1.
.PARAMETER LogPath
    Optional job log whose last TailLines lines are printed after the result.
.PARAMETER TimeoutSeconds
    Maximum wait from 1 to 600 seconds. Defaults to 120 seconds.
.PARAMETER TailLines
    Number of log lines from 0 to 500. Defaults to 40; 0 disables log reading.
.EXAMPLE
    .\Wait-DetachedResult.ps1 -ResultPath $launch.ResultPath -LogPath $logPath

    Run this command through the terminal tool in async mode only.
.OUTPUTS
    System.String
    DETACHED-RESULT <0|1|timeout> after <seconds> s, followed by the log tail.
.NOTES
    Exits with 0 or 1 for the job result, or 124 on timeout.
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ResultPath,

    [ValidateNotNullOrEmpty()]
    [string] $LogPath,

    [ValidateRange(1, 600)]
    [int] $TimeoutSeconds = 120,

    [ValidateRange(0, 500)]
    [int] $TailLines = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ResultPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultPath)
$clock = [Diagnostics.Stopwatch]::StartNew()
$outcome = 'timeout'
$exitCode = 124

while ($true) {
    if ([IO.File]::Exists($ResultPath)) {
        $stream = $null
        $reader = $null
        $text = $null
        try {
            $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
            $stream = [IO.File]::Open($ResultPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
            if ($stream.Length -gt 64) {
                throw "ResultPath '$ResultPath' must contain 0 or 1; the file exceeds 64 bytes."
            }
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
            $text = $reader.ReadToEnd().Trim()
        }
        catch [IO.FileNotFoundException] {
            Write-Verbose -Message 'ResultPath disappeared during the read; waiting for completion.'
        }
        catch [IO.IOException] {
            $nativeCode = $_.Exception.HResult -band 0xffff
            if ($nativeCode -notin 32, 33) { throw }
            Write-Verbose -Message 'ResultPath is still held by its writer; waiting for completion.'
        }
        finally {
            if ($reader) { $reader.Dispose() }
            elseif ($stream) { $stream.Dispose() }
        }

        if ($null -ne $text -and $text.Length -gt 0) {
            if ($text -notin '0', '1') {
                throw "ResultPath '$ResultPath' must contain 0 or 1; received '$text'."
            }
            $outcome = $text
            $exitCode = [int]$text
            break
        }
    }

    if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
    Start-Sleep -Milliseconds 500
}

$seconds = $clock.Elapsed.TotalSeconds.ToString('0.0', [cultureinfo]::InvariantCulture)
'DETACHED-RESULT {0} after {1} s' -f $outcome, $seconds

if ($LogPath -and $TailLines -gt 0) {
    try {
        Get-Content -LiteralPath $LogPath -Tail $TailLines -Encoding UTF8 -ErrorAction Stop
    }
    catch [System.Management.Automation.RuntimeException] {
        Write-Warning -Message "Could not read detached log '$LogPath': $($_.Exception.Message)"
    }
}

exit $exitCode
