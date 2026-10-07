<#
.SYNOPSIS
    SessionStart hook that injects the deterministic part of Pre-flight.
.DESCRIPTION
    Reads the VS Code SessionStart hook payload from standard input, resolves the
    session working directory, and returns a short block of additional context on
    standard output: the current UTC timestamp and an authoritative statement of
    whether a Memory Bank exists in the workspace.

    The workspace summary supplied at session start omits dotfile folders, which
    is the recurring cause of agents concluding that no Memory Bank exists. This
    hook probes the filesystem instead of relying on the model to remember to.

    It also starts the session clock: the same timestamp is written to a small
    per-session file under LocalApplicationData, which the Stop hook reads to
    report the elapsed chat duration at the end of every turn. A model cannot
    read a clock, so neither number may be left to it. A payload with source
    'resume' keeps a readable clock of the same session and reports its start.

    COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS bounds injected context to
    1024-16384 characters (default 4096). Invalid values use the default.
    Long paths are omitted before lifecycle or safety guidance is shortened.

    When the workspace declares Knowledge areas in .memory-bank/projectbrief.md,
    one more sentence carries the contributor's saved Familiarity levels for
    them, from the private Contributor profile (Decision record 0028). It has
    the lowest budget priority and never shortens the lines above. When it
    carries levels, the hook also arms the PostToolUse backstop re-send: it
    seeds lastTurn, lastInjectionUtc, and characters in the session's
    calibration state, merging into the state a resumed session already has.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER ClockRoot
    Directory holding the session clock files. Defaults to the per-user
    application data location. Tests override it to stay off the real profile.
.NOTES
    Writes one JSON object that serves two host contracts with the same text: a
    top-level additionalContext, the only key the Copilot SDK host and Copilot
    CLI read, and hookSpecificOutput.additionalContext, the key the VS Code
    Local harness reads. Always exits 0 so a probe failure never blocks a
    session.
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
        Write-SessionClose.ps1, Write-CompactionCheckpoint.ps1, and
        Add-FamiliarityContext.ps1: VS Code launches each hook by its own path,
        so a shared helper would need the same fragile path probing that
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

$workingDirectory = if ($payload) { [string]$payload.cwd } else { $null }

if ([string]::IsNullOrWhiteSpace($workingDirectory)) {
    $workingDirectory = (Get-Location).Path
}

# The path is interpolated into the instruction channel, so strip control
# characters that a hostile workspace name could use to inject extra lines.
$workingDirectory = $workingDirectory -replace '[\p{Cc}]', ' '

<#
    The payload supplies this path, so it is untrusted and may name a drive or a
    shape this host cannot resolve. Combine and probe it through .NET rather than
    the PowerShell provider: a provider that cannot resolve the path writes to
    standard error, and the caller merges the streams, which would corrupt the
    JSON contract on standard output. [System.IO.File]::Exists returns false for
    any path it cannot read and never throws.
#>
$memoryBankExists = $false
$memoryBankIndex = $workingDirectory

try {
    $memoryBankIndex = [System.IO.Path]::Combine($workingDirectory, '.memory-bank', 'index.md')
    $memoryBankExists = [System.IO.File]::Exists($memoryBankIndex)
} catch {
    $memoryBankExists = $false
}

if ($memoryBankExists) {
    $memoryBankState = "A Memory Bank exists at $memoryBankIndex. This probe is authoritative: " +
    'do not conclude that the Memory Bank is absent. Read the index and apply its routing table ' +
    'before the first tool call.'
} else {
    $memoryBankState = "No Memory Bank exists under $workingDirectory. This probe is authoritative. " +
    'Create one only before a durable repository write, using the memory-bank Skill.'
}

$startedUtc = (Get-Date).ToUniversalTime()

<#
    Start the session clock. The Stop hook reads this file at the end of every
    turn to report the elapsed chat duration, and it has to survive compaction,
    which is why it goes to disk rather than into the injected context alone.
    A clock failure must never cost the caller its Memory Bank probe.

    A resumed session keeps its clock. The Copilot SDK runtime reruns this hook
    with source 'resume' when it reloads a chat, and restarting the clock there
    reset the elapsed duration and the turn count the Stop hook keeps. A clock
    that cannot be read, or that names no start, is replaced as before.
#>
try {
    $clockPath = $null
    $clockTurns = 0
    $clockPath = Get-SessionClockPath `
        -SessionId ([string]$payload.session_id) `
        -WorkingDirectory $workingDirectory `
        -Root $ClockRoot

    $resumedStartUtc = $null

    if ($payload -and [string]$payload.source -eq 'resume' -and [IO.File]::Exists($clockPath)) {
        try {
            $recorded = [IO.File]::ReadAllText($clockPath) | ConvertFrom-Json -ErrorAction Stop

            if (-not [string]::IsNullOrWhiteSpace([string]$recorded.startedUtc)) {
                $recordedStartUtc = ([datetimeoffset]$recorded.startedUtc).UtcDateTime

                if ($recordedStartUtc -le $startedUtc) {
                    $resumedStartUtc = $recordedStartUtc
                    $clockTurns = [Math]::Max(0, [int]$recorded.turns)
                }
            }
        } catch {
            $resumedStartUtc = $null
            $clockTurns = 0
        }
    }

    if ($null -ne $resumedStartUtc) {
        $startedUtc = $resumedStartUtc
    } else {
        $clockDirectory = [IO.Path]::GetDirectoryName($clockPath)

        if (-not [IO.Directory]::Exists($clockDirectory)) {
            [IO.Directory]::CreateDirectory($clockDirectory) | Out-Null
        }

        $clock = [ordered]@{
            startedUtc = $startedUtc.ToString('o')
            workspace = $workingDirectory
            turns = 0
        } | ConvertTo-Json -Depth 3

        [IO.File]::WriteAllText($clockPath, $clock, [Text.UTF8Encoding]::new($false))
    }
} catch {
    # A missing clock costs the closing duration line, nothing else. Reporting on
    # any other stream would corrupt the JSON contract on standard output.
    Write-Debug -Message "Session clock not started: $($_.Exception.Message)"
}

<#
    Hand the agent the absolute path of the clock reader. Post-flight closes with
    a measured duration, and the agent cannot resolve the reader itself: it sits
    under ~/.copilot when deployed and under the plugin root when installed as a
    plugin, which is the probe hooks.json already carries.
#>
$elapsedReader = [IO.Path]::Combine($PSScriptRoot, 'Get-SessionElapsed.ps1')

$line = @(
    "Session started at $($startedUtc.ToString('yyyy-MM-dd HH:mm')) UTC."
    $memoryBankState
    'Open the reply with that UTC timestamp and a one-line PRE-FLIGHT acknowledgment.'
    "Close every reply by running & '$elapsedReader' and copying its single line verbatim as the last line of the POST-FLIGHT block."
    'Never push or otherwise mutate a git remote unless the user asks in the current turn.'
)

$contextLimit = 4096
$configuredLimit = 0
if ([int]::TryParse([Environment]::GetEnvironmentVariable('COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS'), [ref]$configuredLimit) -and
    $configuredLimit -ge 1024 -and $configuredLimit -le 16384) {
    $contextLimit = $configuredLimit
}

$additionalContext = $line -join ' '
if ($additionalContext.Length -gt $contextLimit) {
    $line[1] = if ($memoryBankExists) {
        'A Memory Bank exists in the working directory. Read its index and apply its routes before the first tool call.'
    } else {
        'The Memory Bank probe found no index in the working directory. Check before initializing; create only missing files for durable work.'
    }
    $additionalContext = $line -join ' '
}
if ($additionalContext.Length -gt $contextLimit) {
    $line[3] = 'Close every reply with the measured Get-SessionElapsed.ps1 output in POST-FLIGHT. The reader is beside the SessionStart hook.'
    $additionalContext = $line -join ' '
}

<#
    Contributor calibration, Decision record 0028: one data-only sentence with
    the saved Familiarity levels for the Knowledge areas this workspace declares
    in .memory-bank/projectbrief.md. It has the lowest budget priority, so it
    gets only what the lines above leave and never shortens them. The reader
    ships with the contributor-profile Skill, found beside this script in the
    deployed and in the plugin layout, never through the payload. A workspace
    without a declaration costs one bounded read and never reaches the profile
    or git; any fault costs the sentence and nothing else.
#>
$calibrationDirectory = if ($payload) { [string]$payload.cwd } else { '' }
if (-not [string]::IsNullOrWhiteSpace($calibrationDirectory)) {
    try {
        $briefPath = [IO.Path]::Combine($calibrationDirectory, '.memory-bank', 'projectbrief.md')
        $declaresAreas = $false

        if ([IO.File]::Exists($briefPath)) {
            $briefStream = [IO.File]::OpenRead($briefPath)
            try {
                $briefBuffer = New-Object -TypeName 'System.Byte[]' -ArgumentList 65536
                $briefCount = $briefStream.Read($briefBuffer, 0, $briefBuffer.Length)
            } finally {
                $briefStream.Dispose()
            }

            # Only a declaration with at least one bullet after it is worth the reader.
            # Two linear scans: one lazy pattern from heading to bullet would
            # backtrack quadratically over a file of repeated headings.
            $briefText = [Text.Encoding]::UTF8.GetString($briefBuffer, 0, $briefCount)
            $heading = [regex]::Match($briefText, '(?mi)^##[ \t]+Knowledge areas[ \t]*\r?$')
            $declaresAreas = $heading.Success -and [regex]::IsMatch($briefText.Substring($heading.Index + $heading.Length), '(?m)^[-*+][ \t]+\S')
        }

        if ($declaresAreas) {
            $readerPath = @(
                [IO.Path]::Combine($PSScriptRoot, '..', '..', 'skills', 'contributor-profile', 'scripts', 'ContributorProfileReader.ps1')
                [IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'skills', 'contributor-profile', 'scripts', 'ContributorProfileReader.ps1')
            ) | Where-Object -FilterScript { [IO.File]::Exists($_) } | Select-Object -First 1

            if ($readerPath) {
                . $readerPath
                $calibration = Get-ContributorCalibration -WorkspacePath $calibrationDirectory -SkipGitForSingleEntry
                $calibrationSentence = Format-ContributorCalibrationSentence -Calibration $calibration -MaximumLength ($contextLimit - $additionalContext.Length - 1)

                if ($calibrationSentence) {
                    $additionalContext = $additionalContext + ' ' + $calibrationSentence

                    <#
                        Arm the backstop re-send of Add-FamiliarityContext.ps1
                        (Decision record 0028, A12), only where levels went
                        out: the unrated, unreadable, and omitted sentences
                        carry none. A resumed session merges into its state, so
                        a compaction pending across the resume keeps its
                        re-send. lastInjectionUtc is this injection's time,
                        the session start of a new session. A fault leaves the
                        backstop unarmed and costs nothing else.
                    #>
                    if ($calibration.State -eq 'levels' -and $clockPath -and
                        $calibrationSentence.StartsWith('Contributor familiarity levels from the private profile')) {
                        try {
                            $statePath = [IO.Path]::ChangeExtension($clockPath, '.familiarity.json')
                            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($statePath))
                            $stateLock = Enter-CalibrationStateLock -StatePath $statePath

                            if ($null -ne $stateLock) {
                                try {
                                    $state = Read-CalibrationState -StatePath $statePath -ReplaceUnreadable
                                    $state.LastTurn = $clockTurns
                                    $state.LastInjectionUtc = [DateTime]::UtcNow
                                    $state.Characters = $state.Characters + $calibrationSentence.Length
                                    Save-CalibrationState -StatePath $statePath -State $state
                                } finally {
                                    $stateLock.Dispose()
                                }
                            }
                        } catch {
                            Write-Debug -Message "Backstop re-send not armed: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
    } catch {
        Write-Debug -Message "Contributor calibration skipped: $($_.Exception.Message)"
    }
}

$output = [ordered]@{
    continue = $true
    # Two hosts, two contracts. The Copilot SDK host and Copilot CLI read only a
    # top-level additionalContext; the VS Code Local harness reads only
    # hookSpecificOutput. Each host ignores the other's key, so carry both.
    additionalContext = $additionalContext
    hookSpecificOutput = [ordered]@{
        hookEventName = 'SessionStart'
        additionalContext = $additionalContext
    }
}

$output | ConvertTo-Json -Depth 5 -Compress
exit 0
