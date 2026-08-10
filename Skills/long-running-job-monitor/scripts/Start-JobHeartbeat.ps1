<#
.SYNOPSIS
    Arms one chat-heartbeat tick for a long-running job.
.DESCRIPTION
    Run this through the terminal tool in ASYNC mode. Do not launch it through
    Start-DetachedPowerShell.ps1: only a command the harness still tracks emits
    the completion notification that spawns an agent turn, and a fully detached
    process is invisible to the harness, so it never wakes the agent.

    The script records job metadata in a JSON state file, waits one interval,
    then emits a measured tick summary that the agent renders as its status
    line. Every value the agent reports is measured here rather than recalled,
    because a model's internal clock drifts.

    The state file holds no probe scriptblock by design. It is re-read and acted
    on at every wake, so executable text stored there would become a durable
    local code-execution sink.
.EXAMPLE
    ./Start-JobHeartbeat.ps1 -JobName 'deploy-vm01' -IntervalMinutes 10

    Arms the first tick, waits ten minutes, then emits the tick summary.
.EXAMPLE
    ./Start-JobHeartbeat.ps1 -JobName 'deploy-vm01' -TouchStatus

    Records that a status line was just shown, without waiting. Keeps the
    sliding-reset window accurate when the agent reports outside a tick.
.EXAMPLE
    ./Start-JobHeartbeat.ps1 -JobName 'smoke' -IntervalMinutes 1 -NoWait

    Performs all state work and emits the summary immediately. Used for smoke
    tests and for re-arming bookkeeping without consuming an interval.
.EXAMPLE
    ./Start-JobHeartbeat.ps1 -JobName 'deploy-vm01' -Stop

    Cancels the pending tick. Required by the "stop watching" kill switch and
    on job completion, because an armed timer otherwise keeps waking the agent.
#>
[CmdletBinding(DefaultParameterSetName = 'Arm')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string] $JobName,

    # Base cadence. The backoff ladder multiplies this value.
    [Parameter(ParameterSetName = 'Arm')]
    [ValidateRange(1, 240)]
    [int] $IntervalMinutes = 10,

    # Ladder is 1x, 1x, 2x, 3x, 6x, then 6x. For the default base: 10, 10, 20,
    # 30, 60 minutes.
    [Parameter(ParameterSetName = 'Arm')]
    [switch] $NoBackoff,

    # Recorded on the first arm. Drives the low-confidence marking that stops a
    # hung job reporting as healthy.
    [Parameter(ParameterSetName = 'Arm')]
    [switch] $HasProgressProbe,

    [Parameter(ParameterSetName = 'Arm')]
    [ValidateRange(1, 100000)]
    [int] $ExpectedDurationMinutes,

    [Parameter(ParameterSetName = 'Arm')]
    [ValidateNotNullOrEmpty()]
    [string] $LogPath,

    [Parameter(ParameterSetName = 'Arm')]
    [switch] $NoWait,

    [Parameter(Mandatory, ParameterSetName = 'TouchStatus')]
    [switch] $TouchStatus,

    # Cancels a pending tick. Without it "stop watching" leaves the armed timer
    # running and it still wakes the agent.
    [Parameter(Mandatory, ParameterSetName = 'Stop')]
    [switch] $Stop,

    [ValidateNotNullOrEmpty()]
    [string] $StatePath = (Join-Path $env:TEMP "job-$JobName.state.json")
)

$ErrorActionPreference = 'Stop'

$backoffMultipliers = @(1, 1, 2, 3, 6)

function Get-HeartbeatState
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        return $null
    }

    try
    {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch
    {
        throw "Heartbeat state at '$Path' is not valid JSON: $($_.Exception.Message)"
    }
}

function Save-HeartbeatState
{
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding utf8
}

function ConvertTo-UtcDateTime
{
    # RoundtripKind keeps the trailing Z as Kind=Utc. A plain Parse yields
    # Kind=Local, and a later ToUniversalTime() then shifts the value twice.
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    [datetime]::Parse(
        $Value,
        [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    )
}

$nowUtc = (Get-Date).ToUniversalTime()
$state = Get-HeartbeatState -Path $StatePath

if ($PSCmdlet.ParameterSetName -eq 'TouchStatus')
{
    if (-not $state)
    {
        throw "No heartbeat state for job '$JobName' at '$StatePath'. Arm a tick first."
    }

    $state.LastStatusUtc = $nowUtc.ToString('o')
    Save-HeartbeatState -Path $StatePath -State $state

    "[{0}] HEARTBEAT-TOUCH {1}" -f $nowUtc.ToString('HH:mm:ss'), $JobName
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Stop')
{
    if (-not $state)
    {
        throw "No heartbeat state for job '$JobName' at '$StatePath'."
    }

    $wasKilled = $false
    if ($state.ArmedProcessId)
    {
        $armed = Get-Process -Id ([int]$state.ArmedProcessId) -ErrorAction SilentlyContinue

        # The recorded start time identifies the process as ours, so a recycled
        # process ID belonging to something else is never killed.
        if ($armed -and $state.ArmedProcessStartUtc)
        {
            $recordedStart = ConvertTo-UtcDateTime -Value $state.ArmedProcessStartUtc
            $actualStart = $armed.StartTime.ToUniversalTime()

            if ([Math]::Abs(($actualStart - $recordedStart).TotalSeconds) -lt 2)
            {
                Stop-Process -Id $armed.Id -Force
                $wasKilled = $true
            }
        }
    }

    $state.ArmedProcessId = $null
    $state.ArmedProcessStartUtc = $null
    Save-HeartbeatState -Path $StatePath -State $state

    "[{0}] HEARTBEAT-STOPPED {1} cancelled={2}" -f $nowUtc.ToString('HH:mm:ss'), $JobName, $wasKilled
    return
}

if (-not $state)
{
    $state = [pscustomobject]@{
        JobName                 = $JobName
        StartedUtc              = $nowUtc.ToString('o')
        LogPath                 = $LogPath
        BaseIntervalMinutes     = $IntervalMinutes
        Backoff                 = -not $NoBackoff.IsPresent
        HasProgressProbe        = $HasProgressProbe.IsPresent
        ExpectedDurationMinutes = if ($PSBoundParameters.ContainsKey('ExpectedDurationMinutes')) { $ExpectedDurationMinutes } else { $null }
        TickCount               = 0
        LastStatusUtc           = $nowUtc.ToString('o')
        NextTickDueUtc          = $null
        ArmedProcessId          = $null
        ArmedProcessStartUtc    = $null
    }
}
else
{
    # Only a genuine retune restarts the ladder. Re-arming with the same
    # interval must not reset it, or backoff would never engage.
    if ($PSBoundParameters.ContainsKey('IntervalMinutes') -and
        [int]$state.BaseIntervalMinutes -ne $IntervalMinutes)
    {
        $state.BaseIntervalMinutes = $IntervalMinutes
        $state.TickCount = 0
    }

    if ($PSBoundParameters.ContainsKey('ExpectedDurationMinutes'))
    {
        $state.ExpectedDurationMinutes = $ExpectedDurationMinutes
    }

    $state.LastStatusUtc = $nowUtc.ToString('o')
}

if ($state.Backoff)
{
    $ladderIndex = [Math]::Min([int]$state.TickCount, $backoffMultipliers.Count - 1)
    $waitMinutes = [int]$state.BaseIntervalMinutes * $backoffMultipliers[$ladderIndex]
}
else
{
    $waitMinutes = [int]$state.BaseIntervalMinutes
}

$dueUtc = $nowUtc.AddMinutes($waitMinutes)
$state.NextTickDueUtc = $dueUtc.ToString('o')
$state.ArmedProcessId = $PID
$state.ArmedProcessStartUtc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
Save-HeartbeatState -Path $StatePath -State $state

# Emitted before the wait so async execution gets its initial output signal.
"[{0}] HEARTBEAT-ARMED {1} wait={2}m due={3} UTC" -f
    $nowUtc.ToString('HH:mm:ss'), $JobName, $waitMinutes, $dueUtc.ToString('HH:mm')

if (-not $NoWait)
{
    Start-Sleep -Seconds ($waitMinutes * 60)
}

$tickUtc = (Get-Date).ToUniversalTime()
$state = Get-HeartbeatState -Path $StatePath

$startedUtc = ConvertTo-UtcDateTime -Value $state.StartedUtc
$lastStatusUtc = ConvertTo-UtcDateTime -Value $state.LastStatusUtc
$elapsedMinutes = [int]($tickUtc - $startedUtc).TotalMinutes
$sinceStatusMinutes = ($tickUtc - $lastStatusUtc).TotalMinutes
$remainingMinutes = [Math]::Round($waitMinutes - $sinceStatusMinutes, 2)

# Sliding reset: a status line shown mid-interval makes this tick redundant, so
# the agent re-arms for the remainder instead of reporting twice.
$isRedundant = $remainingMinutes -gt 0.25

$expectedExceeded = $false
if ($null -ne $state.ExpectedDurationMinutes)
{
    $expectedExceeded = $elapsedMinutes -gt [int]$state.ExpectedDurationMinutes
}

$state.TickCount = [int]$state.TickCount + 1
if (-not $isRedundant)
{
    $state.LastStatusUtc = $tickUtc.ToString('o')
}

$state.ArmedProcessId = $null
$state.ArmedProcessStartUtc = $null
Save-HeartbeatState -Path $StatePath -State $state

$summary = [pscustomobject]@{
    JobName                 = $state.JobName
    TickUtc                 = $tickUtc.ToString('o')
    ElapsedMinutes          = $elapsedMinutes
    ExpectedDurationMinutes = $state.ExpectedDurationMinutes
    ExpectedDurationExceeded = $expectedExceeded
    HasProgressProbe        = [bool]$state.HasProgressProbe
    TickCount               = [int]$state.TickCount
    Redundant               = $isRedundant
    RemainingMinutes        = [Math]::Max($remainingMinutes, 0)
    LogPath                 = $state.LogPath
    StatePath               = $StatePath
}

"[{0}] HEARTBEAT-TICK {1} elapsed={2}m redundant={3} probe={4}" -f
    $tickUtc.ToString('HH:mm:ss'), $state.JobName, $elapsedMinutes,
    $isRedundant, [bool]$state.HasProgressProbe

'HEARTBEAT-JSON ' + ($summary | ConvertTo-Json -Depth 4 -Compress)

$summary
