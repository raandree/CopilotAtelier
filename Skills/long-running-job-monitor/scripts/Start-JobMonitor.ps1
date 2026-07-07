<#
.SYNOPSIS
    Background sidecar that samples a long-running job's target state on a
    fixed cadence and appends timestamped status lines to a .status file.
.DESCRIPTION
    Launch this DETACHED (Start-Process, or an async terminal) so its internal
    Start-Sleep runs in a background process, never in the agent's own
    foreground command. The agent reads the .status file on demand or when
    notified. Pair it with an instrumented job log (see SKILL.md technique 1).
    -GetTargetState must be a read-only probe; see
    references/out-of-band-verification.md for per-domain examples.
.EXAMPLE
    Start-Process pwsh -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-File', 'scripts/Start-JobMonitor.ps1',
        '-JobName', 'deploy-vm01', '-DurationMinutes', '30',
        '-GetTargetState', "{ (Invoke-RestMethod 'http://host/healthz').status }"
    )
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $JobName,

    # Read-only probe returning a one-line target-state summary. Runs every
    # sample and must not mutate the target.
    [Parameter(Mandatory)]
    [scriptblock] $GetTargetState,

    [ValidateNotNullOrEmpty()]
    [string] $StatusPath = (Join-Path $env:TEMP "job-$JobName.status"),

    [ValidateNotNullOrEmpty()]
    [string] $LogPath = (Join-Path $env:TEMP "job-$JobName.log"),

    # 300 s = the ~5-minute cadence the monitoring pattern prescribes. Clamp:
    # >= 5 s so it cannot hot-loop, <= 3600 s so a sample always lands hourly.
    [ValidateRange(5, 3600)]
    [int] $IntervalSeconds = 300,

    # How long to keep sampling; size to the job's expected duration.
    [ValidateRange(1, 100000)]
    [int] $DurationMinutes = 60
)

$ErrorActionPreference = 'Stop'

function Get-HeartbeatAge {
    # Seconds since the freshest "[HH:mm:ss] ..." line in the job log, or $null.
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $line = Get-Content -LiteralPath $Path -Tail 40 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\[(\d{2}:\d{2}:\d{2})\]' } |
        Select-Object -Last 1
    if (-not $line) { return $null }

    $stamp = [regex]::Match($line, '^\[(\d{2}:\d{2}:\d{2})\]').Groups[1].Value
    try {
        $t = [datetime]::ParseExact($stamp, 'HH:mm:ss', [cultureinfo]::InvariantCulture)
        # Crossed midnight: a future stamp belongs to yesterday.
        if ($t -gt (Get-Date)) { $t = $t.AddDays(-1) }
        return [int]((Get-Date) - $t).TotalSeconds
    }
    catch {
        return $null
    }
}

$start    = Get-Date
$deadline = $start.AddMinutes($DurationMinutes)

"[{0}] MONITOR-START {1} (interval={2}s duration={3}m)" -f (Get-Date -Format 'HH:mm:ss'), $JobName, $IntervalSeconds, $DurationMinutes |
    Add-Content -LiteralPath $StatusPath

while ((Get-Date) -lt $deadline) {
    $elapsedMin = [int]((Get-Date) - $start).TotalMinutes

    try {
        $target = (& $GetTargetState) -join ' '
    }
    catch {
        $target = "probe-error: $($_.Exception.Message)"
    }

    $ageSec = Get-HeartbeatAge -Path $LogPath
    $hb = if ($null -eq $ageSec) { 'none' } else { "${ageSec}s ago" }

    "[{0}] elapsed={1}m | last-heartbeat={2} | target: {3}" -f (Get-Date -Format 'HH:mm:ss'), $elapsedMin, $hb, $target |
        Add-Content -LiteralPath $StatusPath

    # Legitimate Start-Sleep: this runs in a BACKGROUNDED process, never in the
    # agent's own foreground command. The agent must not self-sleep to wait.
    Start-Sleep -Seconds $IntervalSeconds
}

"[{0}] MONITOR-END {1}" -f (Get-Date -Format 'HH:mm:ss'), $JobName |
    Add-Content -LiteralPath $StatusPath
