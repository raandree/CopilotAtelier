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
    server-side policy remain the real enforcement. Known evasions include a
    variable or alias standing in for the subcommand (git $verb, or git -c
    alias.p=push p), a field name spelled with JSON escapes whose value hides
    the program behind an escaped quote, and arguments nested in arrays of
    arrays.

    The command-bearing fields are walked up to 64 levels deep and 20,000
    values, in payloads up to 1 MB. When the walk cannot cover the payload,
    because it is nested deeper, larger, holds more values, or is not valid
    JSON, the raw payload text is also scanned, with its JSON escapes decoded
    and without its JSON punctuation, before the call is allowed. That errs
    toward blocking: there, a payload that only mentions a blocked command is
    blocked. The whole decision has a time limit, five seconds by default, of
    which the walk may use half. A payload not inspected within it is blocked,
    and so is one larger than 4 MB, so no payload outlasts the hook timeout,
    which fails open.

    COPILOT_ATELIER_ALLOW_REMOTE=1 in the hook's own environment allows a
    blocked command and records the override on standard error. An agent
    cannot set it for the running host: each host starts the hook with its own
    environment, not the agent terminal's, so an authorized push runs in the
    user's own terminal. A value persisted in the user environment, for example
    with setx, reaches every host started later and turns the guard off there,
    so never persist it.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER TimeLimitSecond
    Longest time, in seconds, the guard may take to decide, counted from its
    start. Defaults to 5. A value outside 0.1 to 10 is clamped into that range,
    and one that is not a number falls back to 5, rather than being rejected:
    a rejected parameter would exit 1, which VS Code treats as a warning. The
    hook never passes it; tests lower it.
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
    [string]$InputJson,

    [Parameter()]
    [string]$TimeLimitSecond = '5'
)

# The time limit counts from here, so it also covers reading and parsing the payload.
$decisionClock = [System.Diagnostics.Stopwatch]::StartNew()

# Parse and clamp rather than validate: a rejected parameter exits 1, which
# VS Code treats as a warning, so a bad value would let a blocked command through.
$timeLimitValue = 0.0
$isNumber = [double]::TryParse(
    $TimeLimitSecond,
    [System.Globalization.NumberStyles]::Float,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [ref]$timeLimitValue
)
if (-not $isNumber) {
    $timeLimitValue = 5
}
if (-not ($timeLimitValue -ge 0.1)) {
    $timeLimitValue = 0.1
} elseif ($timeLimitValue -gt 10) {
    $timeLimitValue = 10
}

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

# Of those, the fields that name what runs; the others carry its arguments.
$executableField = @('command', 'commandLine', 'cmd', 'script')

# The same fields in raw JSON text: the field name, then a string value or a
# flat array of values.
$rawFieldPattern = '"(' + (($commandField | ForEach-Object { [regex]::Escape($_) }) -join '|') +
    ')"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|\[([^\[\]]*)\])'

# Some patterns scan to the end of the line from every git word, which grows
# quadratically: 64 KB of git words took 21.5 seconds, past the 20-second hook
# timeout, and a timeout fails open in the Copilot SDK host. Many matches that
# each stay under a second add up the same way, so the limit covers the whole
# decision: every match gets only the time left, and a payload not inspected in
# time is blocked.
$timeLimit = [TimeSpan]::FromSeconds($timeLimitValue)
$notInspectedInTime = 'this command could not be inspected within the time limit'

# Parsing and the field walk cannot be interrupted, and 300,000 small objects
# kept the walk busy past the hook timeout. So only a payload up to 1 MB is
# parsed, and the walk stops after 20,000 values or half the time limit; what
# it did not cover is scanned as raw text, which the time limit does bound. A
# payload over 4 MB is blocked unscanned: no model writes a tool call that
# large, and even the linear passes over it take seconds. Those passes run
# between the field join and the pattern scan and do not read the clock, so a
# decision can overrun the limit by about 1.5 seconds (6.3 seconds measured at
# worst). Reading the payload is linear as well: 96 MB took 15.9 seconds, so
# outlasting the hook timeout would take about 120 MB.
$maximumParseLength = 1MB
$maximumPayloadLength = 4MB
$maximumVisitCount = 20000
$walkTimeLimit = [TimeSpan]::FromTicks([long]($timeLimit.Ticks / 2))
$visitCount = 0

# The field walk stops below this depth. Whatever it cannot reach, it reports,
# and the raw payload text is scanned instead, so nesting cannot carry a
# command past the guard.
$maximumDepth = 64
$isWalkComplete = $true
$walkStopReason = $null

# The walk collects the command-bearing values here in document order, and
# again by kind, so they can be joined in more than one order.
$commandPart = [System.Collections.Generic.List[string]]::new()
$executablePart = [System.Collections.Generic.List[string]]::new()
$argumentPart = [System.Collections.Generic.List[string]]::new()

function Add-CommandPart {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter()]
        [int]$Depth = 0
    )

    if ($null -eq $InputObject -or $InputObject -is [string]) {
        return
    }

    if ($Depth -gt $script:maximumDepth) {
        $script:isWalkComplete = $false
        $script:walkStopReason = "is nested deeper than $script:maximumDepth levels"
        return
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $script:visitCount++
        if ($script:visitCount -gt $script:maximumVisitCount -or $script:decisionClock.Elapsed -gt $script:walkTimeLimit) {
            $script:isWalkComplete = $false
            $script:walkStopReason = 'has too many values to walk in time'
            break
        }

        $value = $property.Value

        if ($property.Name -in $script:commandField) {
            $text = if ($value -is [string]) { $value } elseif ($value -is [array]) { @($value) -join ' ' } else { $null }
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $script:commandPart.Add($text)
                if ($property.Name -in $script:executableField) {
                    $script:executablePart.Add($text)
                } else {
                    $script:argumentPart.Add($text)
                }
            }
        }

        foreach ($child in @($value)) {
            $script:visitCount++
            if ($script:visitCount -gt $script:maximumVisitCount -or $script:decisionClock.Elapsed -gt $script:walkTimeLimit) {
                $script:isWalkComplete = $false
                $script:walkStopReason = 'has too many values to walk in time'
                break
            }

            if ($child -is [psobject] -and $child.PSObject.Properties.Name.Count -gt 0 -and $child -isnot [string] -and $child -isnot [ValueType]) {
                Add-CommandPart -InputObject $child -Depth ($Depth + 1)
            }
        }
    }
}

function Join-CommandPart {
    <#
        Joins command-bearing values three ways, because a tool may write the
        executable and its arguments in either order, for example with its keys
        sorted: as written, executables before arguments, and in reverse.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Part,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ExecutablePart,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ArgumentPart
    )

    if ($Part.Count -eq 0) {
        return
    }

    $Part -join ' '
    if ($Part.Count -gt 1) {
        ([string[]]$ExecutablePart.ToArray() + [string[]]$ArgumentPart.ToArray()) -join ' '
        $reversed = $Part.ToArray()
        [array]::Reverse($reversed)
        $reversed -join ' '
    }
}

function Block-ToolCall {
    <#
        Ends the script with exit 2 and the reason, or with exit 0 when the
        override is set in the hook's own environment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Because
    )

    if ($env:COPILOT_ATELIER_ALLOW_REMOTE -eq '1') {
        [Console]::Error.WriteLine(
            "Block-RemoteMutation: allowed by COPILOT_ATELIER_ALLOW_REMOTE - $Because."
        )
        exit 0
    }

    $reason = "Blocked by Copilot Atelier: $Because, and the house rules forbid remote-mutating " +
        'or irreversible commands without explicit per-turn authorization from the user. If the user ' +
        'asked for it in this turn, hand them the exact command to run in their own terminal; an agent ' +
        'cannot lift this block. Do not rewrite the command to evade this check.'

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

function Get-RawCommandText {
    <#
        Pulls the command-bearing fields out of raw JSON text and joins them the
        way the walk does, so a command split across fields, such as
        {"command":"git","args":["push"]}, reads as one command line there too.
        It shares the decision's time limit and blocks the call when that runs
        out.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter()]
        [switch]$DecodeValue
    )

    $part = [System.Collections.Generic.List[string]]::new()
    $executable = [System.Collections.Generic.List[string]]::new()
    $argument = [System.Collections.Generic.List[string]]::new()
    try {
        $timeLeft = $script:timeLimit - $script:decisionClock.Elapsed
        if ($timeLeft -le [TimeSpan]::Zero) {
            Block-ToolCall -Because $script:notInspectedInTime
        }

        $fieldPattern = [regex]::new(
            $script:rawFieldPattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
            $timeLeft
        )

        # Match and NextMatch rather than enumerating Matches: a timeout raised
        # inside foreach's enumeration would not reach the catch below as itself.
        $match = $fieldPattern.Match($Text)
        while ($match.Success) {
            if ($script:decisionClock.Elapsed -gt $script:timeLimit) {
                Block-ToolCall -Because $script:notInspectedInTime
            }

            $isString = $match.Groups[2].Success
            $value = if ($isString) { $match.Groups[2].Value } else { $match.Groups[3].Value }
            if ($DecodeValue -and $value.Contains('\')) {
                try {
                    $value = [regex]::Unescape($value)
                } catch [System.ArgumentException] {
                    Write-Verbose -Message 'A field holds an escape Regex.Unescape rejects; it is joined as written.'
                }
            }

            if (-not $isString) {
                $value = $value -replace '["\[\],]', ' '
            }

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $part.Add($value)
                if ($match.Groups[1].Value -in $script:executableField) {
                    $executable.Add($value)
                } else {
                    $argument.Add($value)
                }
            }

            $match = $match.NextMatch()
        }
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        Block-ToolCall -Because $script:notInspectedInTime
    }

    Join-CommandPart -Part $part -ExecutablePart $executable -ArgumentPart $argument
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

if ($InputJson.Length -gt $maximumPayloadLength) {
    Block-ToolCall -Because 'this tool call is too large to inspect'
}

$isPayloadReadable = $true
if ($InputJson.Length -gt $maximumParseLength) {
    $isWalkComplete = $false
    $walkStopReason = 'is too large to walk field by field'
} else {
    try {
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
        Add-CommandPart -InputObject $payload.tool_input
    } catch {
        # Windows PowerShell rejects JSON nested past 100 levels and PowerShell 7
        # past 1024, so an unreadable payload is not necessarily a harmless one.
        $isPayloadReadable = $false
        $isWalkComplete = $false
    }
}

$scanText = [System.Collections.Generic.List[string]]::new()
foreach ($text in @(Join-CommandPart -Part $commandPart -ExecutablePart $executablePart -ArgumentPart $argumentPart)) {
    $scanText.Add($text)
}

if (-not $isWalkComplete) {
    # Scan what the walk could not reach as raw text, also with its JSON escapes
    # decoded, so neither nesting nor malformed JSON hides a blocked command.
    # Each text is scanned on its own: one joined text would only make the
    # quadratic patterns slower.
    $rawText = [System.Collections.Generic.List[string]]::new()
    $rawText.Add($InputJson)
    if ($InputJson.Contains('\')) {
        try {
            $rawText.Add([regex]::Unescape($InputJson))
        } catch [System.ArgumentException] {
            Write-Verbose -Message 'The payload holds an escape Regex.Unescape rejects; it is scanned as written.'
        }
    }

    # The walk joins every command-bearing field it finds, which the raw text
    # cannot: there, field names and other fields sit between the parts of a
    # command split across fields. So the same fields are pulled out of the raw
    # text and joined, as written with each value decoded and, for a key spelled
    # with escapes, from the decoded text. They are short, so they go first.
    $fieldText = [System.Collections.Generic.List[string]]::new()
    foreach ($text in @(Get-RawCommandText -Text $InputJson -DecodeValue)) {
        $fieldText.Add($text)
    }
    if ($rawText.Count -gt 1) {
        foreach ($text in @(Get-RawCommandText -Text $rawText[1])) {
            $fieldText.Add($text)
        }
    }

    # An argument array reads as ["git","push"] in raw JSON. Without the JSON
    # punctuation it reads as the command line the walk would have joined.
    foreach ($text in @($rawText)) {
        $rawText.Add(($text -replace '["\[\],]', ' '))
    }

    $scanText.AddRange($fieldText)
    $scanText.AddRange($rawText)
}

if ($scanText.Count -eq 0) {
    exit 0
}

# Fold shell line continuations so a split command cannot hide the subcommand.
for ($index = 0; $index -lt $scanText.Count; $index++) {
    $scanText[$index] = $scanText[$index] -replace '[`^\\]\r?\n\s*', ' '
}

# Every pattern needs a git or gh word. Searching for one costs a fraction of a
# pattern scan, which under PowerShell 7 takes about 70 ms per MB, so a text
# without either is not scanned at all.
$scanText = @(
    $scanText | Where-Object {
        $_.IndexOf('git', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $_.IndexOf('gh', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }
)

$blockedBecause = $null
:operation foreach ($operation in $blockedOperation.GetEnumerator()) {
    foreach ($text in $scanText) {
        $timeLeft = $timeLimit - $decisionClock.Elapsed
        if ($timeLeft -le [TimeSpan]::Zero) {
            $blockedBecause = $notInspectedInTime
            break operation
        }

        try {
            $pattern = [regex]::new(
                $operation.Value,
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
                $timeLeft
            )
            if ($pattern.IsMatch($text)) {
                $blockedBecause = "this command $($operation.Key)"
                break operation
            }
        } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
            $blockedBecause = $notInspectedInTime
            break operation
        }
    }
}

if ($blockedBecause) {
    Block-ToolCall -Because $blockedBecause
}

if (-not $isPayloadReadable) {
    # Exit 0, not 1: the Copilot SDK host denies a preToolUse call on any other
    # non-zero exit, so a payload schema change would block every tool call.
    [Console]::Error.WriteLine('Block-RemoteMutation: hook payload is not valid JSON; allowing the tool call.')
} elseif (-not $isWalkComplete) {
    [Console]::Error.WriteLine(
        "Block-RemoteMutation: hook payload $walkStopReason and its raw text holds no blocked command; allowing the tool call."
    )
}

exit 0
