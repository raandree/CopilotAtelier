<#
.SYNOPSIS
    Stop hook that closes the Post-flight checklist with a measured clock line.
.DESCRIPTION
    Reads the VS Code Stop hook payload from standard input, reads the session
    clock the SessionStart hook wrote, and reports the turn's closing UTC
    timestamp together with the elapsed duration of the whole chat.

    Post-flight asks the agent to report what it did, but a model has no clock:
    any timestamp it composes is a guess, and after compaction it no longer knows
    when the session began. Both numbers therefore come from here, where they are
    measured rather than recalled.

    The turn counter advances only when the payload does not say the agent is
    already continuing from a blocking Stop hook, so a resumed run stays one turn.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER ClockRoot
    Directory holding the session clock files. Defaults to the per-user
    application data location. Tests override it to stay off the real profile.
.NOTES
    Never blocks: no decision field is emitted and every failure path exits 0, so
    a missing or unreadable clock costs the duration line and nothing else.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$InputJson,

    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$ClockRoot
)

function Get-SessionClockPath {
    <#
        Resolves the clock file for a session. Duplicated verbatim in
        Add-SessionContext.ps1: VS Code launches each hook by its own path, so a
        shared helper would need the same fragile path probing that hooks.json
        already carries. Both sides must derive the same name from the same
        payload, so change them together.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$WorkingDirectory,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        # Per-user by construction. The temp directory is world-writable on
        # Linux, where a predictable name invites another local account to
        # pre-create the path.
        $Root = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)

        if ([string]::IsNullOrWhiteSpace($Root)) {
            $Root = [IO.Path]::GetTempPath()
        }

        $Root = [IO.Path]::Combine($Root, 'CopilotAtelier', 'sessions')
    }

    # The payload supplies this value, so it becomes a path component only after
    # every character that could traverse a directory is gone.
    $key = ($SessionId -replace '[^A-Za-z0-9._-]', '')

    if ($key.Length -gt 64) {
        $key = $key.Substring(0, 64)
    }

    if ([string]::IsNullOrWhiteSpace($key)) {
        # No session id: fall back to the workspace so two concurrent windows do
        # not share one clock.
        $seed = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { 'default' } else { $WorkingDirectory }
        $sha = [Security.Cryptography.SHA256]::Create()

        try {
            $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($seed))
        } finally {
            $sha.Dispose()
        }

        $key = 'cwd-' + [BitConverter]::ToString($digest[0..7]).Replace('-', '').ToLowerInvariant()
    }

    return [IO.Path]::Combine($Root, "session-$key.json")
}

function Format-Elapsed {
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

if ([string]::IsNullOrEmpty($InputJson)) {
    # Decode explicitly: Windows PowerShell would otherwise use the console input
    # encoding, which mangles non-ASCII payloads that pwsh reads as UTF-8.
    $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
    try {
        $InputJson = $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

$payload = $null
if (-not [string]::IsNullOrWhiteSpace($InputJson)) {
    try {
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $payload = $null
    }
}

$endedUtc = (Get-Date).ToUniversalTime()
$startedUtc = $null
$turn = 0

# A Stop that fires while the agent is already continuing from a blocking hook
# closes the same turn it started, so it must not advance the counter.
$isContinuation = $false
if ($payload -and $null -ne $payload.stop_hook_active) {
    $isContinuation = [bool]$payload.stop_hook_active
}

try {
    $clockPath = Get-SessionClockPath `
        -SessionId ([string]$payload.session_id) `
        -WorkingDirectory ([string]$payload.cwd) `
        -Root $ClockRoot

    if ([IO.File]::Exists($clockPath)) {
        $clock = [IO.File]::ReadAllText($clockPath) | ConvertFrom-Json -ErrorAction Stop
        $startedUtc = ([datetimeoffset]$clock.startedUtc).UtcDateTime
        $turn = [int]$clock.turns

        if (-not $isContinuation) {
            $turn++
        }

        $updated = [ordered]@{
            startedUtc = $clock.startedUtc
            workspace = [string]$clock.workspace
            turns = $turn
            lastTurnEndedUtc = $endedUtc.ToString('o')
        } | ConvertTo-Json -Depth 3

        [IO.File]::WriteAllText($clockPath, $updated, [Text.UTF8Encoding]::new($false))
    }
} catch {
    $startedUtc = $null
}

if ($startedUtc) {
    $turnLabel = if ($turn -gt 0) { "turn $turn" } else { 'turn' }
    $message = 'POST-FLIGHT clock - {0} ended {1} UTC; chat elapsed {2} (started {3} UTC).' -f
        $turnLabel,
        $endedUtc.ToString('yyyy-MM-dd HH:mm'),
        (Format-Elapsed -Duration ($endedUtc - $startedUtc)),
        $startedUtc.ToString('HH:mm')
} else {
    $message = 'POST-FLIGHT clock - turn ended {0} UTC; no session clock on disk, so the chat duration is unavailable.' -f
        $endedUtc.ToString('yyyy-MM-dd HH:mm')
}

# No decision field: blocking here would restart the agent and bill another turn.
[ordered]@{
    continue = $true
    systemMessage = $message
} | ConvertTo-Json -Depth 5 -Compress

exit 0
