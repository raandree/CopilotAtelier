<#
.SYNOPSIS
    PostToolUse hook that re-sends the contributor's familiarity levels once
    after a compaction.
.DESCRIPTION
    No host reruns SessionStart after a compaction, and the Copilot SDK host and
    Copilot CLI drop its context when they compact. The PreCompact hook counts
    each compaction in session-<key>.familiarity.json beside the session clock;
    this hook answers it on the next successful tool call (Decision record 0028).

    The registration file ~/.copilot/hooks/contributor-profile.json loads this
    hook only while a Contributor profile on this machine has an entry that is
    on and rates a Knowledge area, and it runs after every successful tool call.
    The common path therefore stays short: it finds session_id near the start
    of the payload, where both hosts put it ahead of every tool field, reads the
    small state file, and exits when no compaction is unanswered.

    When one is, it parses the payload for cwd, rechecks the profile, so an
    opt-out or a deletion takes effect at once, and emits the matched levels
    once under both host keys. The sentence carries no unrated count and ends
    with a suffix that suppresses every offer for the rest of the session. It
    then records the compaction it answered by compare-and-set under the state
    lock that PreCompact also takes, so a newer compaction is never lost.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER ClockRoot
    Directory holding the session clocks and the calibration state. Defaults to
    the per-user application data location. Tests override it.
.NOTES
    Never emits decision and never exits 2: every path exits 0, so this hook can
    only add context, never block or change a tool call. Writes one JSON object
    that serves both hosts: a top-level additionalContext, which the Copilot SDK
    host and Copilot CLI read, and hookSpecificOutput.additionalContext, which
    the VS Code Local harness reads.
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
        Add-SessionContext.ps1, Write-SessionClose.ps1, and
        Write-CompactionCheckpoint.ps1: VS Code launches each hook by its own
        path, so a shared helper would need the same fragile path probing that
        hooks.json already carries. Every copy must derive the same name from
        the same payload, so change them together.
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

function Read-CalibrationState {
    param([Parameter(Mandatory = $true)] [string]$StatePath)

    $state = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{
        Compactions = [Math]::Max(0, [int]$state.compactions)
        Injected = [Math]::Max(0, [int]$state.injected)
    }
}

function Set-CalibrationAnswered {
    <#
        Compare-and-set under the state lock: records the compaction count this
        call answered, never lowers a count, and keeps any compaction that
        PreCompact recorded in the meantime.
    #>
    param(
        [Parameter(Mandatory = $true)] [string]$StatePath,
        [Parameter(Mandatory = $true)] [int]$Answered
    )

    $lockPath = [IO.Path]::ChangeExtension($StatePath, '.lock')
    $lock = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()

    while ($null -eq $lock) {
        try {
            $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
        } catch {
            if ($watch.ElapsedMilliseconds -ge 5000) {
                # The answer goes unrecorded, so the next call re-sends once
                # more; a duplicate sentence is the accepted cost.
                return
            }

            Start-Sleep -Milliseconds 50
        }
    }

    try {
        $current = Read-CalibrationState -StatePath $StatePath
        $text = '{{"schemaVersion":1,"compactions":{0},"injected":{1}}}' -f $current.Compactions, [Math]::Max($current.Injected, $Answered)
        $temporary = $StatePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($temporary, $StatePath, [System.Management.Automation.Language.NullString]::Value)
    } finally {
        $lock.Dispose()
    }
}

try {
    if ([string]::IsNullOrEmpty($InputJson)) {
        # Decode explicitly: Windows PowerShell would otherwise use the console
        # input encoding, which mangles non-ASCII payloads that pwsh reads as UTF-8.
        $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
        try {
            $InputJson = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    }

    if ([string]::IsNullOrWhiteSpace($InputJson)) {
        exit 0
    }

    # Both hosts write session_id ahead of every tool field, so the head of the
    # payload holds it and a tool result of any size stays unparsed here.
    $head = if ($InputJson.Length -gt 4096) { $InputJson.Substring(0, 4096) } else { $InputJson }
    $sessionMatch = [regex]::Match($head, '"session_id"\s*:\s*"([^"\\]*)"')
    $payload = $null
    $sessionId = $null

    if ($sessionMatch.Success) {
        $sessionId = $sessionMatch.Groups[1].Value
    } else {
        # No plain session id: the key falls back to the workspace, so parse.
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
        $sessionId = [string]$payload.session_id
    }

    $workingDirectoryForKey = if ($payload) { [string]$payload.cwd } else { $null }
    if ([string]::IsNullOrWhiteSpace(($sessionId -replace '[^A-Za-z0-9._-]', '')) -and $null -eq $payload) {
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
        $workingDirectoryForKey = [string]$payload.cwd
    }

    $clockPath = Get-SessionClockPath -SessionId $sessionId -WorkingDirectory $workingDirectoryForKey -Root $ClockRoot
    $statePath = [IO.Path]::ChangeExtension($clockPath, '.familiarity.json')

    if (-not [IO.File]::Exists($statePath)) {
        exit 0
    }

    $state = Read-CalibrationState -StatePath $statePath
    if ($state.Compactions -le $state.Injected) {
        exit 0
    }

    if ($null -eq $payload) {
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
    }

    # Never the spawn directory: no cwd means no calibration.
    $workspace = [string]$payload.cwd
    $sentence = ''

    if (-not [string]::IsNullOrWhiteSpace($workspace)) {
        $readerPath = @(
            [IO.Path]::Combine($PSScriptRoot, '..', '..', 'skills', 'contributor-profile', 'scripts', 'ContributorProfileReader.ps1')
            [IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'skills', 'contributor-profile', 'scripts', 'ContributorProfileReader.ps1')
        ) | Where-Object -FilterScript { [IO.File]::Exists($_) } | Select-Object -First 1

        if ($readerPath) {
            . $readerPath
            $calibration = Get-ContributorCalibration -WorkspacePath $workspace -SkipGitForSingleEntry
            $sentence = Format-ContributorCalibrationSentence -Calibration $calibration -ReSent
        }
    }

    # Recorded even with nothing to re-send, so later calls stay on the short path.
    Set-CalibrationAnswered -StatePath $statePath -Answered $state.Compactions

    if ($sentence) {
        [ordered]@{
            additionalContext = $sentence
            hookSpecificOutput = [ordered]@{
                hookEventName = 'PostToolUse'
                additionalContext = $sentence
            }
        } | ConvertTo-Json -Depth 5 -Compress
    }
} catch {
    # Any fault costs the re-sent levels, nothing else; a tool call is never blocked.
    Write-Debug -Message "Familiarity context not re-sent: $($_.Exception.Message)"
}

exit 0
