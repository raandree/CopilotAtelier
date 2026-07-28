<#
.SYNOPSIS
    PreToolUse hook that blocks remote-mutating and irreversible commands.
.DESCRIPTION
    Reads the VS Code PreToolUse hook payload from standard input and inspects
    any tool input that carries executable command text for operations the
    Copilot Atelier house rules forbid without explicit per-turn authorization:
    pushing to a remote, bypassing repository hooks, discarding work with a hard
    reset or forced clean, and mutating pull requests, issues, releases,
    repositories, workflows, secrets, or the GitHub API through the GitHub CLI.

    On a match the reason is written to standard error and the script exits
    with 2, which VS Code treats as a blocking error and shows to the model.
    Every other tool call exits 0.

    This is a best-effort guardrail, not a containment boundary. It matches
    patterns in a command string, so an obfuscated or indirectly invoked push
    can evade it. It removes the accidental path; branch protection and a
    server-side policy remain the real enforcement.

    Set COPILOT_ATELIER_ALLOW_REMOTE=1 in the environment to authorize a remote
    mutation. The hook then allows the command and records the override on
    standard error.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.NOTES
    Exit codes follow the VS Code hook contract: 0 allows, 2 blocks, and any
    other value is a non-blocking warning.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$InputJson
)

# First match wins; the most consequential rule is listed first. Each git rule
# anchors on the subcommand position so a branch name, commit message, or
# --grep value that merely contains the word does not trip it.
$gitOption = '(?:\s+(?:-c\s+\S+|--?[\w-]+(?:=\S+)?))*'
$blockedOperation = [ordered]@{
    'pushes to a git remote' = "(?i)\bgit\b$gitOption\s+push\b"
    'bypasses repository hooks' = '(?i)\bgit\b[^\r\n]*\s--no-verify\b'
    'discards work with a hard reset' = "(?i)\bgit\b$gitOption\s+reset\b[^\r\n]*?\s--hard\b"
    'force-deletes untracked files' = "(?i)\bgit\b$gitOption\s+clean\b(?![^\r\n]*\s-[a-z]*n)[^\r\n]*\s-[a-z]*f"
    'mutates a GitHub remote resource' = '(?i)\bgh\s+(?:pr\s+(?:create|merge|close|comment|review|edit|ready|reopen)|issue\s+(?:create|close|comment|edit|reopen)|release\s+(?:create|delete|edit|upload)|repo\s+(?:create|delete|archive|rename|edit)|workflow\s+(?:run|enable|disable)|secret\s+(?:set|delete)|cache\s+delete)\b'
    'calls a mutating GitHub API endpoint' = '(?i)\bgh\s+api\b[^\r\n]*(?:--method\s+(?:post|put|patch|delete)\b|\s-X\s+(?:post|put|patch|delete)\b|\bmutation\b)'
}

# Field names that carry executable command text. Gating on the presence of one
# of these is tool-agnostic; gating on the tool name misses executors whose name
# lacks a shell keyword, and every miss would fail open.
$commandField = @('command', 'commandLine', 'cmd', 'script', 'args', 'arguments')

function Get-CommandText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter()]
        [int]$Depth = 0
    )

    if ($null -eq $InputObject -or $InputObject -is [string] -or $Depth -gt 4) {
        return ''
    }

    $collected = [System.Collections.Generic.List[string]]::new()

    foreach ($property in $InputObject.PSObject.Properties) {
        $value = $property.Value

        if ($property.Name -in $script:commandField) {
            if ($value -is [string]) {
                $collected.Add($value)
            } elseif ($value -is [array]) {
                $collected.Add((@($value) -join ' '))
            }
        }

        foreach ($child in @($value)) {
            if ($child -is [psobject] -and $child.PSObject.Properties.Name.Count -gt 0 -and $child -isnot [string] -and $child -isnot [ValueType]) {
                $nested = Get-CommandText -InputObject $child -Depth ($Depth + 1)
                if (-not [string]::IsNullOrWhiteSpace($nested)) {
                    $collected.Add($nested)
                }
            }
        }
    }

    return ($collected -join ' ')
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

if ([string]::IsNullOrWhiteSpace($InputJson)) {
    exit 0
}

try {
    $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    [Console]::Error.WriteLine('Block-RemoteMutation: hook payload is not valid JSON; allowing the tool call.')
    exit 1
}

$commandText = Get-CommandText -InputObject $payload.tool_input
if ([string]::IsNullOrWhiteSpace($commandText)) {
    exit 0
}

# Fold shell line continuations so a split command cannot hide the subcommand.
$commandText = $commandText -replace '[`^\\]\r?\n\s*', ' '

foreach ($operation in $blockedOperation.GetEnumerator()) {
    if ($commandText -notmatch $operation.Value) {
        continue
    }

    if ($env:COPILOT_ATELIER_ALLOW_REMOTE -eq '1') {
        [Console]::Error.WriteLine(
            "Block-RemoteMutation: allowed by COPILOT_ATELIER_ALLOW_REMOTE - command $($operation.Key)."
        )
        exit 0
    }

    [Console]::Error.WriteLine(
        "Blocked by Copilot Atelier: this command $($operation.Key), which the house rules forbid " +
        'without explicit per-turn authorization from the user. Ask the user to confirm, then ' +
        'set COPILOT_ATELIER_ALLOW_REMOTE=1 for that command. Do not rewrite the command to evade this check.'
    )
    exit 2
}

exit 0
