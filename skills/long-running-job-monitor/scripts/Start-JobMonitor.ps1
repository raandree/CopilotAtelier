<#
.SYNOPSIS
    Samples structured target liveness and progress on a fixed cadence.
.DESCRIPTION
    Launch this DETACHED (Start-Process, or an async terminal) so its internal
    Start-Sleep runs in a background process, never in the agent's own
    foreground command. The agent reads the .status file on demand or when
    notified. Pair it with an instrumented job log (see SKILL.md technique 1).
    -GetTargetState must be a read-only probe returning exactly one object with
    Summary, Liveness, and ProgressToken properties. Only ProgressToken changes
    reset the last-progress timestamp.
.EXAMPLE
    $probeText = '[pscustomobject]@{ Summary = "ready"; Liveness = $true; ProgressToken = 1 }'
    $encodedProbe = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($probeText)
    )
    $jobName = 'deploy-vm01-{0}' -f [guid]::NewGuid().ToString('N')
    $monitorScript = Join-Path $HOME '.copilot/skills/long-running-job-monitor/scripts/Start-JobMonitor.ps1'
    $escapedScript = $monitorScript.Replace("'", "''")
    $launcherPayload = "& '$escapedScript' -JobName '$jobName' -DurationMinutes 30 -GetTargetStateBase64 '$encodedProbe'"
    $encodedLauncher = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($launcherPayload)
    )
    $launcherPath = Join-Path $HOME '.copilot/skills/long-running-job-monitor/scripts/Start-DetachedPowerShell.ps1'
    & $launcherPath -EncodedCommand $encodedLauncher
#>
[CmdletBinding(DefaultParameterSetName = 'ScriptBlock')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $JobName,

    # Direct invocation: read-only probe returning one structured object.
    [Parameter(Mandatory, ParameterSetName = 'ScriptBlock')]
    [scriptblock] $GetTargetState,

    # Detached native-process invocation: UTF-16LE Base64 probe body. Do not
    # include surrounding script-block braces.
    [Parameter(Mandatory, ParameterSetName = 'EncodedProbe')]
    [ValidateNotNullOrEmpty()]
    [string] $GetTargetStateBase64,

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
    [int] $DurationMinutes = 60,

    # Duration controls normal runs. MaxSamples enables bounded smoke tests and
    # intentionally short monitoring windows without changing the cadence.
    [ValidateRange(1, [int]::MaxValue)]
    [int] $MaxSamples = [int]::MaxValue
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'EncodedProbe') {
    try {
        $probeText = [Text.Encoding]::Unicode.GetString(
            [Convert]::FromBase64String($GetTargetStateBase64)
        )
    }
    catch {
        throw "GetTargetStateBase64 is not valid UTF-16LE Base64: $($_.Exception.Message)"
    }

    $trimmedProbeText = $probeText.Trim()
    if ($trimmedProbeText.StartsWith('{') -and $trimmedProbeText.EndsWith('}')) {
        throw 'GetTargetStateBase64 must encode the probe body without surrounding script-block braces.'
    }

    try {
        $GetTargetState = [scriptblock]::Create($probeText)
    }
    catch {
        throw "GetTargetStateBase64 does not contain a valid PowerShell probe body: $($_.Exception.Message)"
    }
}

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
$lastProgressAt = $start
$previousProgressToken = $null
$hasProgressSample = $false
$sampleCount = 0

"[{0}] MONITOR-START {1} (interval={2}s duration={3}m)" -f (Get-Date -Format 'HH:mm:ss'), $JobName, $IntervalSeconds, $DurationMinutes |
    Add-Content -LiteralPath $StatusPath

while ((Get-Date) -lt $deadline -and $sampleCount -lt $MaxSamples) {
    $elapsedMin = [int]((Get-Date) - $start).TotalMinutes

    try {
        $probeResults = @(& $GetTargetState)
        if ($probeResults.Count -ne 1) {
            throw "GetTargetState returned $($probeResults.Count) objects; expected exactly one."
        }

        $probe = $probeResults[0]
        foreach ($propertyName in 'Summary', 'Liveness', 'ProgressToken') {
            if (-not $probe.PSObject.Properties[$propertyName]) {
                throw "GetTargetState result is missing '$propertyName'."
            }
        }

        $summary = [string]$probe.Summary
        $liveness = [string]$probe.Liveness
        $progressToken = $probe.ProgressToken
        $progressTokenKey = if ($null -eq $progressToken) {
            '<null>'
        }
        else {
            ConvertTo-Json -InputObject $progressToken -Compress -Depth 10
        }

        if (-not $hasProgressSample -or $progressTokenKey -ne $previousProgressToken) {
            $lastProgressAt = Get-Date
            $previousProgressToken = $progressTokenKey
            $hasProgressSample = $true
        }
    }
    catch {
        $summary = "probe-error: $($_.Exception.Message)"
        $liveness = 'false'
        $progressTokenKey = if ($hasProgressSample) { $previousProgressToken } else { '<none>' }
    }

    $ageSec = Get-HeartbeatAge -Path $LogPath
    $hb = if ($null -eq $ageSec) { 'none' } else { "${ageSec}s ago" }
    $progressAgeSec = [int]((Get-Date) - $lastProgressAt).TotalSeconds

    "[{0}] elapsed={1}m | last-progress={2}s ago | progress={3} | last-heartbeat={4} | liveness={5} | target={6}" -f (Get-Date -Format 'HH:mm:ss'), $elapsedMin, $progressAgeSec, $progressTokenKey, $hb, $liveness, $summary |
        Add-Content -LiteralPath $StatusPath

    $sampleCount++
    if ($sampleCount -ge $MaxSamples -or (Get-Date).AddSeconds($IntervalSeconds) -ge $deadline) {
        break
    }

    # Legitimate Start-Sleep: this runs in a BACKGROUNDED process, never in the
    # agent's own foreground command. The agent must not self-sleep to wait.
    Start-Sleep -Seconds $IntervalSeconds
}

"[{0}] MONITOR-END {1}" -f (Get-Date -Format 'HH:mm:ss'), $JobName |
    Add-Content -LiteralPath $StatusPath
