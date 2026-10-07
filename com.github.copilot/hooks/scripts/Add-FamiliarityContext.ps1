<#
.SYNOPSIS
    PostToolUse hook that re-sends the contributor's familiarity levels after a
    compaction, and as a backstop on a new turn or 5 minutes later.
.DESCRIPTION
    No host reruns SessionStart after a compaction, and the Copilot SDK host and
    Copilot CLI drop its context when they compact. The PreCompact hook counts
    each compaction in session-<key>.familiarity.json beside the session clock;
    this hook answers it on the next successful tool call (Decision record 0028).
    VS Code Local runs no PreCompact for a manual or a background compaction, so
    the hook also re-sends the levels as a backstop on the first successful tool
    call after a turn closes, or more than 5 minutes after the last injection
    once the first turn has closed (ruling A12). Only a session whose SessionStart
    injected levels is armed for the backstop: it seeds lastInjectionUtc.

    The registration file ~/.copilot/hooks/contributor-profile.json loads this
    hook only while a Contributor profile on this machine has an entry that is
    on and rates a Knowledge area, and it runs after every successful tool call.
    The common path therefore stays short and writes nothing: it finds
    session_id near the start of the payload, where both hosts put it ahead of
    every tool field, reads the small state file and, in an armed session, the
    turn count of the session clock, and exits when nothing is due.

    When a re-send is due, it parses the payload for cwd and rechecks the
    profile, so an opt-out or a deletion takes effect at once. It then takes the
    state lock that PreCompact also takes, re-reads the state, decides again,
    records the injection, and only then emits the matched levels under both
    host keys, so an injection that could not be recorded is never sent and
    cannot re-fire. The sentence carries no unrated count and ends with a suffix
    that suppresses every offer for the rest of the session. The compaction it
    answers is recorded by compare-and-set, so a newer compaction is never lost.
    Backstop re-sends stop once the session has received 12,000 characters of
    calibration text; compaction re-sends continue up to 60,000, above which
    nothing is sent.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER ClockRoot
    Directory holding the session clocks and the calibration state. Defaults to
    the per-user application data location. Tests override it.
.NOTES
    Never emits decision and never exits 2: every path exits 0, so this hook can
    only add context, never block or change a tool call. It reads the session
    clock and never writes it. Writes one JSON object that serves both hosts: a
    top-level additionalContext, which the Copilot SDK host and Copilot CLI
    read, and hookSpecificOutput.additionalContext, which the VS Code Local
    harness reads.
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
    <#
        Reads session-<key>.familiarity.json, the per-session calibration
        state. Duplicated verbatim, with Save-CalibrationState and
        Enter-CalibrationStateLock, in Add-SessionContext.ps1,
        Write-CompactionCheckpoint.ps1, and Add-FamiliarityContext.ps1, for the
        reason Get-SessionClockPath gives; change the copies together. A
        missing file reads as a fresh state and a missing field as absent:
        lastTurn and lastInjectionUtc stay $null until SessionStart seeds them,
        and characters reads 0. An unreadable file throws, unless
        -ReplaceUnreadable asks for a fresh state instead. Only these hooks
        write the file, as one flat object, so a pattern per field reads it:
        ConvertFrom-Json would load a module on the PostToolUse common path
        and double its cost.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter()]
        [switch]$ReplaceUnreadable
    )

    $fresh = [pscustomobject]@{
        Compactions = 0
        Injected = 0
        LastTurn = $null
        LastInjectionUtc = $null
        Characters = 0
    }

    if (-not [IO.File]::Exists($StatePath)) {
        return $fresh
    }

    try {
        $text = [IO.File]::ReadAllText($StatePath)

        if ($text -notmatch '\A\s*\{[^{}]*\}\s*\z') {
            throw 'The calibration state is not one flat JSON object.'
        }

        $field = @{}
        foreach ($match in [regex]::Matches($text, '"([A-Za-z]+)"\s*:\s*("[^"\\]*"|[^,}\s]+)')) {
            if (-not $field.ContainsKey($match.Groups[1].Value)) {
                $field[$match.Groups[1].Value] = $match.Groups[2].Value
            }
        }

        $state = [pscustomobject]@{
            Compactions = 0
            Injected = 0
            LastTurn = $null
            LastInjectionUtc = $null
            Characters = 0
        }

        foreach ($name in 'compactions', 'injected', 'lastTurn', 'characters') {
            if ($null -ne $field[$name] -and $field[$name] -ne 'null') {
                $state.$name = [Math]::Max(0, [int]::Parse($field[$name], [Globalization.NumberStyles]::AllowLeadingSign, [Globalization.CultureInfo]::InvariantCulture))
            }
        }

        $stamp = $field['lastInjectionUtc']
        if ($null -ne $stamp -and $stamp -ne 'null') {
            if ($stamp -notmatch '\A"(.+)"\z') {
                throw 'lastInjectionUtc is not a timestamp.'
            }

            $state.LastInjectionUtc = [datetimeoffset]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
        }

        return $state
    } catch {
        if (-not $ReplaceUnreadable) {
            throw
        }

        Write-Debug -Message "Unreadable calibration state replaced: $($_.Exception.Message)"
        return $fresh
    }
}

function Save-CalibrationState {
    <#
        Writes every field of the calibration state with an atomic replace,
        under the state lock the caller holds. An absent lastTurn or
        lastInjectionUtc stays absent, so only SessionStart can arm the
        backstop. Duplicated verbatim; see Read-CalibrationState.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$State
    )

    $text = '{"schemaVersion":1,"compactions":' + [int]$State.Compactions + ',"injected":' + [int]$State.Injected

    if ($null -ne $State.LastTurn) {
        $text += ',"lastTurn":' + [int]$State.LastTurn
    }

    if ($null -ne $State.LastInjectionUtc) {
        $text += ',"lastInjectionUtc":"' + ([datetime]$State.LastInjectionUtc).ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture) + '"'
    }

    $text += ',"characters":' + [int]$State.Characters + '}'
    $temporary = $StatePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'

    try {
        [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))

        if ([IO.File]::Exists($StatePath)) {
            [IO.File]::Replace($temporary, $StatePath, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [IO.File]::Move($temporary, $StatePath)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) {
            try {
                [IO.File]::Delete($temporary)
            } catch {
                Write-Debug -Message "Temporary calibration state left behind: $($_.Exception.Message)"
            }
        }
    }
}

function Enter-CalibrationStateLock {
    <#
        Opens the lock every writer of the calibration state takes, waiting up
        to 5 seconds, and returns $null when another hook still holds it.
        Duplicated verbatim; see Read-CalibrationState.
    #>
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    $lockPath = [IO.Path]::ChangeExtension($StatePath, '.lock')
    $watch = [Diagnostics.Stopwatch]::StartNew()

    while ($true) {
        try {
            return [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
        } catch {
            if ($watch.ElapsedMilliseconds -ge 5000) {
                return $null
            }

            Start-Sleep -Milliseconds 50
        }
    }
}

function Read-SessionTurn {
    <#
        The closed-turn count that the Stop hook keeps in the session clock.
        Read, never written: no calibration hook rewrites the clock. Returns
        $null when the clock is missing or unreadable. A pattern reads the one
        number, for the reason Read-CalibrationState gives; a JSON string
        escapes every quote it holds, so the workspace path cannot fake it.
    #>
    [CmdletBinding()]
    [OutputType([Nullable[int]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClockPath
    )

    try {
        $match = [regex]::Match([IO.File]::ReadAllText($ClockPath), '"turns"\s*:\s*(\d+)\s*[,}]')

        if (-not $match.Success) {
            return $null
        }

        return [Math]::Max(0, [int]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture))
    } catch {
        return $null
    }
}

function Test-BackstopDue {
    <#
        The backstop's two signals, ruling A12: a turn has closed since the
        last injection, or more than 5 minutes have passed since it. Only a
        lastInjectionUtc that SessionStart seeded arms it, and it stops once
        the session has received 12,000 characters of calibration text. The
        5-minute signal waits for the first turn boundary, so a long first turn
        cannot repeat the SessionStart sentence; without a readable session
        clock it is the only signal.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter()]
        [Nullable[int]]$Turns,

        [Parameter(Mandatory = $true)]
        [datetime]$NowUtc
    )

    if ($null -eq $State.LastInjectionUtc -or $State.Characters -ge 12000) {
        return $false
    }

    if ($null -ne $Turns -and $null -ne $State.LastTurn -and $Turns -gt $State.LastTurn) {
        return $true
    }

    return (($null -eq $Turns -or $Turns -ge 1) -and ($NowUtc - $State.LastInjectionUtc).TotalSeconds -gt 300)
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
    $nowUtc = [DateTime]::UtcNow
    $turns = $null
    $kind = $null

    # At 60,000 characters the session is outside the design's envelope, which
    # its characters field records: nothing of either kind is sent any more.
    if ($state.Characters -lt 60000) {
        if ($state.Compactions -gt $state.Injected) {
            $kind = 'compaction'
        } elseif ($null -ne $state.LastInjectionUtc -and $state.Characters -lt 12000) {
            $turns = Read-SessionTurn -ClockPath $clockPath

            if (Test-BackstopDue -State $state -Turns $turns -NowUtc $nowUtc) {
                $kind = 'backstop'
            }
        }
    }

    if (-not $kind) {
        exit 0
    }

    if ($kind -eq 'compaction') {
        $turns = Read-SessionTurn -ClockPath $clockPath
    }

    if ($null -eq $payload) {
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
    }

    # Never the spawn directory: no cwd means no calibration. Read before the
    # lock: the reader may take seconds, and PreCompact waits for the lock.
    $workspace = [string]$payload.cwd
    $calibration = $null

    if (-not [string]::IsNullOrWhiteSpace($workspace)) {
        $readerPath = @(
            [IO.Path]::Combine($PSScriptRoot, '..', '..', 'skills', 'contributor-profile', 'scripts', 'ContributorProfileReader.ps1')
            [IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'skills', 'contributor-profile', 'scripts', 'ContributorProfileReader.ps1')
        ) | Where-Object -FilterScript { [IO.File]::Exists($_) } | Select-Object -First 1

        if ($readerPath) {
            . $readerPath
            $calibration = Get-ContributorCalibration -WorkspacePath $workspace -SkipGitForSingleEntry
        }
    }

    $lock = Enter-CalibrationStateLock -StatePath $statePath

    if ($null -eq $lock) {
        # Nothing recorded, so nothing is sent: the next call decides again.
        exit 0
    }

    $sentence = ''
    $recorded = $false

    try {
        # Decide again on the state as it is now: a parallel call may have
        # answered, and PreCompact may have counted another compaction.
        $current = Read-CalibrationState -StatePath $statePath
        $due = $false

        if ($kind -eq 'compaction') {
            $due = $current.Characters -lt 60000 -and $state.Compactions -gt $current.Injected
        } else {
            $due = Test-BackstopDue -State $current -Turns $turns -NowUtc $nowUtc
        }

        if ($due) {
            if ($null -ne $calibration) {
                $sentence = if ($kind -eq 'compaction') {
                    Format-ContributorCalibrationSentence -Calibration $calibration -ReSent
                } else {
                    Format-ContributorCalibrationSentence -Calibration $calibration -Backstop
                }
            }

            # Recorded even with nothing to send, so later calls stay on the
            # short path. Only the compactions read before the calibration step
            # count as answered, so a newer one still gets its own re-send.
            if ($kind -eq 'compaction') {
                $current.Injected = [Math]::Max($current.Injected, $state.Compactions)
            }

            if ($null -ne $current.LastInjectionUtc) {
                $current.LastInjectionUtc = $nowUtc

                if ($null -ne $turns) {
                    $current.LastTurn = $turns
                }
            }

            $current.Characters = $current.Characters + $sentence.Length
            Save-CalibrationState -StatePath $statePath -State $current
            $recorded = $true
        }
    } finally {
        $lock.Dispose()
    }

    if ($recorded -and $sentence) {
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
