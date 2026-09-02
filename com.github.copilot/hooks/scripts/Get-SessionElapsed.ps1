<#
.SYNOPSIS
    Reports the elapsed duration of the current chat as one Post-flight line.
.DESCRIPTION
    Reads the session clock the SessionStart hook wrote and prints a single
    ready-to-paste line naming the elapsed chat duration, the session start, the
    moment of measurement, and the turn in progress.

    Post-flight asks the agent to close with that duration, but a model has no
    clock: a timestamp it composes is a guess, and after a compaction it no
    longer knows when the session began. Reading it here makes both numbers
    measured. This is not a VS Code hook - the agent runs it, so the output is
    plain text on standard output rather than the hook JSON contract.

    Read-only by design. The Stop hook owns the turn counter, so this reports
    the turn in progress as one past the closed count and writes nothing back.
.PARAMETER Path
    Exact session clock file to read. Defaults to the newest clock recorded for
    the current workspace, which is what survives a compaction that dropped the
    injected session context.
.PARAMETER ClockRoot
    Directory holding the session clock files. Defaults to the per-user
    application data location. Tests override it to stay off the real profile.
.PARAMETER WorkingDirectory
    Workspace used to pick between concurrent sessions. Defaults to the current
    directory.
.EXAMPLE
    & "$HOME/.copilot/hooks/scripts/Get-SessionElapsed.ps1"

    POST-FLIGHT elapsed: 16m (started 09:15 UTC, measured 09:31 UTC, turn 3)
.NOTES
    Never fails: every path exits 0, so an unreadable clock costs the duration
    line and nothing else.
#>

[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$Path,

    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$ClockRoot,

    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$WorkingDirectory
)

function Format-Elapsed {
    <#
        Duplicated verbatim in Write-SessionClose.ps1 so both sides render the
        same duration the same way. Change them together.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [timespan]$Duration
    )

    if ($Duration.TotalSeconds -lt 0) {
        return 'unavailable'
    }

    if ($Duration.TotalMinutes -lt 1) {
        return 'under a minute'
    }

    # Floor explicitly: a cast to int rounds, so 90 minutes would report 2h 30m.
    if ($Duration.TotalHours -lt 1) {
        return '{0}m' -f [int][Math]::Floor($Duration.TotalMinutes)
    }

    return '{0}h {1:00}m' -f [int][Math]::Floor($Duration.TotalHours), $Duration.Minutes
}

$measuredUtc = (Get-Date).ToUniversalTime()
$unavailable = 'POST-FLIGHT elapsed: unavailable (no session clock on disk).'

if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
}

if ([string]::IsNullOrWhiteSpace($ClockRoot)) {
    # Per-user by construction, matching Get-SessionClockPath in the hooks. The
    # temp directory is world-writable on Linux, where a predictable name invites
    # another local account to pre-create the path.
    $ClockRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)

    if ([string]::IsNullOrWhiteSpace($ClockRoot)) {
        $ClockRoot = [IO.Path]::GetTempPath()
    }

    $ClockRoot = [IO.Path]::Combine($ClockRoot, 'CopilotAtelier', 'sessions')
}

try {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.File]::Exists($Path)) {
        $candidates = @(
            Get-ChildItem -LiteralPath $ClockRoot -Filter 'session-*.json' -File -ErrorAction Stop |
                Sort-Object -Property LastWriteTimeUtc -Descending
        )

        # Two windows on different workspaces keep separate clocks, so prefer the
        # one this workspace started before falling back to the newest overall.
        $matching = @(
            $candidates | Where-Object {
                try {
                    $recorded = [IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json -ErrorAction Stop
                    [string]$recorded.workspace -eq $WorkingDirectory
                } catch {
                    $false
                }
            }
        )

        <#
            VS Code always supplies session_id, so a live session is always keyed
            by it. The cwd hash is the fallback for a payload that omits one,
            which in practice means a test or a non-VS-Code caller - and such a
            file is newer often enough to shadow the real session.
        #>
        $Path = @(
            $matching | Where-Object { $_.Name -notlike 'session-cwd-*' }
            $matching
            $candidates
        ) | Select-Object -First 1 -ExpandProperty FullName
    }

    $clock = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
    $startedUtc = ([datetimeoffset]$clock.startedUtc).UtcDateTime

    # The Stop hook increments only once the turn is closed, so the turn being
    # reported on is one past the recorded count.
    $turn = [int]$clock.turns + 1

    Write-Output -InputObject ('POST-FLIGHT elapsed: {0} (started {1} UTC, measured {2} UTC, turn {3})' -f
        (Format-Elapsed -Duration ($measuredUtc - $startedUtc)),
        $startedUtc.ToString('HH:mm'),
        $measuredUtc.ToString('HH:mm'),
        $turn)
} catch {
    Write-Output -InputObject $unavailable
}

exit 0
