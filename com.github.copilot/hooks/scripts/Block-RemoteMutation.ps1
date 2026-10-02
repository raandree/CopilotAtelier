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
    The same reason goes to standard output as one JSON deny object, which the
    Copilot SDK host reads on exit 2. Every other tool call exits 0.

    This is a best-effort guardrail, not a containment boundary. It matches
    patterns in a command string, so an obfuscated or indirectly invoked push
    can evade it. It removes the accidental path; branch protection and a
    server-side policy remain the real enforcement.

    The command-bearing fields are walked up to 64 levels deep. When the walk
    cannot cover the payload, because it is nested deeper or is not valid JSON,
    the raw payload text is also scanned, with its JSON escapes decoded and
    without its JSON punctuation, before the call is allowed. That errs toward
    blocking: there, a payload that only mentions a blocked command is blocked.

    COPILOT_ATELIER_ALLOW_REMOTE=1 in the hook's own environment allows a
    blocked command and records the override on standard error. An agent
    cannot set it: each host starts the hook with its own environment, not the
    agent terminal's, so an authorized push runs in the user's own terminal.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.NOTES
    Exit codes follow the VS Code hook contract: 0 allows, 2 blocks, and any
    other value is a non-blocking warning. The Copilot SDK host instead denies
    a preToolUse call on every non-zero exit, so this script uses only 0 and 2:
    an unreadable payload is allowed with a warning on standard error unless
    its raw text carries a blocked command.
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
$gitCommand = '(?i)\bgit(?:\.exe)?[''"]?(?=\s)'
$gitOption = '(?:\s+(?:-c\s+\S+|--?[\w-]+(?:=\S+)?))*'
$ghCommand = '(?i)\bgh(?:\.exe)?[''"]?(?=\s)'
$ghOption = '(?:\s+(?:-R\s+\S+|--(?:repo|hostname)\s+\S+|--?[\w-]+(?:=\S+)?))*'
$blockedOperation = [ordered]@{
    'pushes to a git remote' = "$gitCommand$gitOption\s+push\b"
    'bypasses repository hooks' = "$gitCommand[^\r\n]*\s--no-verify\b"
    'discards work with a hard reset' = "$gitCommand$gitOption\s+reset\b[^\r\n]*?\s--hard\b"
    'force-deletes untracked files' = "$gitCommand$gitOption\s+clean\b(?![^\r\n]*\s-[a-z]*n)[^\r\n]*\s-[a-z]*f"
    'mutates a GitHub remote resource' = "$ghCommand$ghOption\s+(?:pr\s+(?:create|merge|close|comment|review|edit|ready|reopen)|issue\s+(?:create|close|comment|edit|reopen)|release\s+(?:create|delete|edit|upload)|repo\s+(?:create|delete|archive|rename|edit)|workflow\s+(?:run|enable|disable)|secret\s+(?:set|delete)|cache\s+delete)\b"
    'calls a mutating GitHub API endpoint' = "$ghCommand$ghOption\s+api\b[^\r\n]*(?:--method\s+(?:post|put|patch|delete)\b|\s-X\s+(?:post|put|patch|delete)\b|\bmutation\b)"
}

# Field names that carry executable command text. Gating on the presence of one
# of these is tool-agnostic; gating on the tool name misses executors whose name
# lacks a shell keyword, and every miss would fail open.
$commandField = @('command', 'commandLine', 'cmd', 'script', 'args', 'arguments')

# The field walk stops below this depth. Whatever it cannot reach, it reports,
# and the raw payload text is scanned instead, so nesting cannot carry a
# command past the guard.
$maximumDepth = 64
$isWalkComplete = $true

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

    if ($null -eq $InputObject -or $InputObject -is [string]) {
        return ''
    }

    if ($Depth -gt $script:maximumDepth) {
        $script:isWalkComplete = $false
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

$isPayloadReadable = $true
try {
    $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
    $commandText = Get-CommandText -InputObject $payload.tool_input
} catch {
    # Windows PowerShell rejects JSON nested past 100 levels and PowerShell 7
    # past 1024, so an unreadable payload is not necessarily a harmless one.
    $isPayloadReadable = $false
    $isWalkComplete = $false
    $commandText = ''
}

if (-not $isWalkComplete) {
    # Scan what the walk could not reach as raw text, also with its JSON escapes
    # decoded, so neither nesting nor malformed JSON hides a blocked command.
    $rawText = [System.Collections.Generic.List[string]]::new()
    $rawText.Add($InputJson)
    try {
        $rawText.Add([regex]::Unescape($InputJson))
    } catch [System.ArgumentException] {
        Write-Verbose -Message 'The payload holds an escape Regex.Unescape rejects; it is scanned as written.'
    }

    # An argument array reads as ["git","push"] in raw JSON. Without the JSON
    # punctuation it reads as the command line the walk would have joined.
    foreach ($text in @($rawText)) {
        $rawText.Add(($text -replace '["\[\],]', ' '))
    }

    $commandText = $commandText + ' ' + ($rawText -join ' ')
}

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

    $reason = "Blocked by Copilot Atelier: this command $($operation.Key), which the house rules forbid " +
        'without explicit per-turn authorization from the user. If the user asked for it in this turn, ' +
        'hand them the exact command to run in their own terminal; an agent cannot lift this block. ' +
        'Do not rewrite the command to evade this check.'

    # VS Code reads the reason from standard error on exit 2. The Copilot SDK host
    # ignores standard error then and merges one JSON object from standard output
    # into the deny, so the same reason also goes there, in both hosts' shapes.
    [Console]::Error.WriteLine($reason)
    $decision = [ordered]@{
        permissionDecision = 'deny'
        permissionDecisionReason = $reason
        hookSpecificOutput = [ordered]@{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = $reason
        }
    }
    [Console]::Out.WriteLine(($decision | ConvertTo-Json -Depth 3 -Compress))
    exit 2
}

if (-not $isPayloadReadable) {
    # Exit 0, not 1: the Copilot SDK host denies a preToolUse call on any other
    # non-zero exit, so a payload schema change would block every tool call.
    [Console]::Error.WriteLine('Block-RemoteMutation: hook payload is not valid JSON; allowing the tool call.')
} elseif (-not $isWalkComplete) {
    [Console]::Error.WriteLine(
        "Block-RemoteMutation: hook payload is nested deeper than $maximumDepth levels and its raw text holds no blocked command; allowing the tool call."
    )
}

exit 0
