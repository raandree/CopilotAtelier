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
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.NOTES
    Emits the SessionStart output contract shared by VS Code, Copilot CLI, and
    Claude Code. Always exits 0 so a probe failure never blocks a session.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$InputJson
)

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

$workingDirectory = $null
if (-not [string]::IsNullOrWhiteSpace($InputJson)) {
    try {
        $workingDirectory = [string]($InputJson | ConvertFrom-Json -ErrorAction Stop).cwd
    } catch {
        $workingDirectory = $null
    }
}

if ([string]::IsNullOrWhiteSpace($workingDirectory)) {
    $workingDirectory = (Get-Location).Path
}

# The path is interpolated into the instruction channel, so strip control
# characters that a hostile workspace name could use to inject extra lines.
$workingDirectory = $workingDirectory -replace '[\p{Cc}]', ' '

$memoryBankIndex = Join-Path (Join-Path $workingDirectory '.memory-bank') 'index.md'

if (Test-Path -LiteralPath $memoryBankIndex -PathType Leaf) {
    $memoryBankState = "A Memory Bank exists at $memoryBankIndex. This probe is authoritative: " +
    'do not conclude that the Memory Bank is absent. Read the index and apply its routing table ' +
    'before the first tool call.'
} else {
    $memoryBankState = "No Memory Bank exists under $workingDirectory. This probe is authoritative. " +
    'Create one only before a durable repository write, using the memory-bank Skill.'
}

$line = @(
    "Session started at $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC."
    $memoryBankState
    'Open the reply with that UTC timestamp and a one-line PRE-FLIGHT acknowledgment.'
    'Never push or otherwise mutate a git remote unless the user asks in the current turn.'
)

$output = [ordered]@{
    continue = $true
    hookSpecificOutput = [ordered]@{
        hookEventName = 'SessionStart'
        additionalContext = ($line -join ' ')
    }
}

$output | ConvertTo-Json -Depth 5 -Compress
exit 0
