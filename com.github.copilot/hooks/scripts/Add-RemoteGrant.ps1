<#
.SYNOPSIS
    UserPromptSubmit hook that records a Remote grant when the user's own prompt
    carries a Grant marker.
.DESCRIPTION
    Block-RemoteMutation blocks every push and every mutating GitHub CLI call.
    A hook cannot ask the user instead: the Copilot Agent Host approves a hook
    ask itself under Allow all and chat.tools.global.autoApprove, so the guard
    would turn into a silent allow there (Decision 0016, revision 2026-10-12).
    The authorization therefore travels in the user's prompt. A prompt that
    contains

        [[allow-remote: git push, gh pr create]]

    as plain text makes this hook write a Remote grant for that session: each
    operation the marker names may run once, an operation followed by x2 twice
    (at most 20). The guard consumes the grant. The grant ends with the user's
    next prompt, which this hook always begins by removing the previous grant
    of the session, and after 15 minutes at the latest.

    A marker inside an inline code span or a fenced code block is ignored, so
    quoting the documentation grants nothing. Operations the guard does not
    list are ignored, and the destructive local blocks (git reset --hard,
    git clean -f, --no-verify) are not listed, so no marker lifts them.

    The grant file is plain JSON under the per-user application data folder:
    schema 1, the session key, issuedAt and expiresAt in Unix seconds, the
    SHA-256 of the prompt, and the operations with their remaining counts. An
    agent that can write files could forge one, so a Remote grant prevents
    accidents; it is not a containment boundary.

    Nothing is written to standard output, so a host reads no decision from
    this hook, and every path exits 0: exit 2 would block the user's prompt in
    VS Code, and a grant that cannot be written simply leaves the guard
    blocking.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER GrantRoot
    Directory holding the grant files. Defaults to CopilotAtelier/grants under
    the per-user application data folder. Tests override it to stay off the
    real profile; the hook itself never passes it.
.PARAMETER LifetimeMinute
    How long a grant lasts, in minutes. Defaults to 15 and is clamped to 1
    through 60; a value that is not a number falls back to 15 rather than being
    rejected, because a rejected parameter would exit 1. The hook never passes
    it; tests lower it.
.NOTES
    The list of grantable operations and the file name rules are duplicated in
    Block-RemoteMutation.ps1, which reads what this script writes: VS Code
    launches each hook by its own path, so a shared helper would need the same
    fragile path probing that hooks.json already carries. Change both together;
    tests/RemoteMutationGrant.Tests.ps1 compares them.
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
    [string]$GrantRoot,

    [Parameter()]
    [string]$LifetimeMinute = '15'
)

# Every operation a Grant marker may name. Keep identical to Block-RemoteMutation.ps1.
$grantableOperation = @(
    'git push'
    'git push --force'
    'gh pr create'
    'gh pr merge'
    'gh pr close'
    'gh pr comment'
    'gh pr review'
    'gh pr edit'
    'gh pr ready'
    'gh pr reopen'
    'gh issue create'
    'gh issue close'
    'gh issue comment'
    'gh issue edit'
    'gh issue reopen'
    'gh release create'
    'gh release delete'
    'gh release edit'
    'gh release upload'
    'gh repo create'
    'gh repo delete'
    'gh repo archive'
    'gh repo rename'
    'gh repo edit'
    'gh workflow run'
    'gh workflow enable'
    'gh workflow disable'
    'gh secret set'
    'gh secret delete'
    'gh cache delete'
    'gh api'
)

# Compared ordinally: a culture-sensitive -in treats a zero-width space or a soft hyphen as nothing, so
# [[allow-remote: git<ZWSP> push]] would be stored as a phrase that no command ever matches.
$grantableOperationSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$grantableOperation, [System.StringComparer]::Ordinal)

$maximumUsePerOperation = 20
$staleAfterDay = 1
$matchTimeout = [TimeSpan]::FromSeconds(2)

# [[allow-remote: <operation>, <operation> x2, ...]] on one line, in any case.
$markerPattern = '(?i)\[\[\s*allow-remote\s*:\s*([^\[\]\r\n]{1,400})\]\]'

# Parse and clamp rather than validate: a rejected parameter exits 1, which hosts
# treat as a warning on every prompt.
$lifetimeValue = 15.0
$isNumber = [double]::TryParse(
    $LifetimeMinute,
    [System.Globalization.NumberStyles]::Float,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [ref]$lifetimeValue
)
if (-not $isNumber) {
    $lifetimeValue = 15
}
if (-not ($lifetimeValue -ge 1)) {
    $lifetimeValue = 1
} elseif ($lifetimeValue -gt 60) {
    $lifetimeValue = 60
}
$lifetimeSecond = [long][Math]::Round($lifetimeValue * 60)

function Get-GrantKey {
    <#
        The file name part for a session. Duplicated in Block-RemoteMutation.ps1. The
        payload supplies the id, so it becomes a path component only when it is already
        a safe file name in lower case (a file system may not tell SESSX from sessx); any
        other id becomes h- and its SHA-256, so two ids never share
        a grant file and no character that could traverse a directory survives. An id with
        no usable character at all gets no key. -creplace, because -replace ignores case
        and so lets U+0130 and U+212A through the class.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionId
    )

    $usable = $SessionId -creplace '[^A-Za-z0-9._-]', ''
    if ([string]::IsNullOrEmpty($usable)) {
        return ''
    }

    if ($SessionId -cmatch '\A[a-z0-9_-]{1,64}\z') {
        return $SessionId
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SessionId))
    } finally {
        $sha.Dispose()
    }

    return 'h-' + [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
}

function Hide-CodeText {
    <#
        Blanks the parts of a prompt that Markdown renders as code, so a marker
        quoted from the documentation grants nothing. An unclosed fence runs to the
        end of the prompt: whatever follows it counts as quoted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $result = $Text
    foreach ($pattern in @('(?s)```.*?(?:```|\z)', '(?s)~~~.*?(?:~~~|\z)', '``[^\r\n]*?``', '`[^`\r\n]*`')) {
        $result = [regex]::Replace($result, $pattern, ' ', [System.Text.RegularExpressions.RegexOptions]::None, $script:matchTimeout)
    }

    return $result
}

function Get-GrantOperation {
    <#
        The operations a prompt asks for, in the order it first names them, with
        their counts. Empty when the prompt carries no valid marker.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Prompt
    )

    $operation = [ordered]@{}

    if ($Prompt.IndexOf('allow-remote', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return $operation
    }

    $markerText = [System.Collections.Generic.List[string]]::new()
    try {
        $text = Hide-CodeText -Text $Prompt

        # Match and NextMatch rather than Matches: a MatchCollection matches lazily, so a
        # timeout would surface in the loop below, outside this try.
        $markerRegex = [regex]::new($script:markerPattern, [System.Text.RegularExpressions.RegexOptions]::None, $script:matchTimeout)
        $current = $markerRegex.Match($text)
        while ($current.Success) {
            $markerText.Add($current.Groups[1].Value)
            $current = $current.NextMatch()
        }
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        # A prompt built to stall the matcher gets no grant.
        return [ordered]@{}
    }

    foreach ($markerBody in $markerText) {
        foreach ($item in $markerBody.Split(',')) {
            $name = ($item.Trim().ToLowerInvariant() -replace '\s+', ' ')
            $count = 1

            $counted = [regex]::Match($name, '^(?<phrase>.+?) x(?<count>\d{1,3})$')
            if ($counted.Success) {
                $name = $counted.Groups['phrase'].Value
                $count = [int]$counted.Groups['count'].Value
            }

            if ($count -lt 1 -or -not $script:grantableOperationSet.Contains($name)) {
                continue
            }

            $already = 0
            if ($operation.Contains($name)) {
                $already = $operation[$name]
            }

            $operation[$name] = [Math]::Min($script:maximumUsePerOperation, $already + $count)
        }
    }

    return $operation
}

function Revoke-GrantFile {
    <#
        Removes a grant file. The guard holds a file it is consuming exclusively
        for a moment, so a sharing violation is retried for about a second.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            if ([System.IO.File]::Exists($Path)) {
                [System.IO.File]::Delete($Path)
            }

            return $true
        } catch [System.IO.IOException] {
            [System.Threading.Thread]::Sleep(100)
        } catch [System.UnauthorizedAccessException] {
            [System.Threading.Thread]::Sleep(100)
        }
    }

    return $false
}

function Write-GrantFile {
    <#
        Writes the grant next to its final name and moves it into place, so a
        reader sees the old file, the new file, or no file, never half of one.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Json
    )

    $directory = [System.IO.Path]::GetDirectoryName($Path)
    $null = [System.IO.Directory]::CreateDirectory($directory)
    $temporary = '{0}.{1}.tmp' -f $Path, [guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllText($temporary, $Json, [System.Text.UTF8Encoding]::new($false))

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            if ([System.IO.File]::Exists($Path)) {
                [System.IO.File]::Delete($Path)
            }

            [System.IO.File]::Move($temporary, $Path)
            return $true
        } catch [System.IO.IOException] {
            [System.Threading.Thread]::Sleep(100)
        } catch [System.UnauthorizedAccessException] {
            [System.Threading.Thread]::Sleep(100)
        }
    }

    try {
        [System.IO.File]::Delete($temporary)
    } catch {
        Write-Verbose -Message 'The temporary grant file could not be removed.'
    }

    return $false
}

function Clear-StaleGrantFile {
    <#
        Grant files of finished sessions: a day is far past any grant's lifetime.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    if (-not [System.IO.Directory]::Exists($Root)) {
        return
    }

    $cutoff = [DateTime]::UtcNow.AddDays(-$script:staleAfterDay)
    foreach ($file in [System.IO.Directory]::GetFiles($Root, 'grant-*')) {
        try {
            if ([System.IO.File]::GetLastWriteTimeUtc($file) -lt $cutoff) {
                [System.IO.File]::Delete($file)
            }
        } catch {
            Write-Verbose -Message 'A stale grant file could not be removed.'
        }
    }
}

if ([string]::IsNullOrEmpty($InputJson)) {
    # Decode explicitly: Windows PowerShell would otherwise use the console input
    # encoding, which mangles non-ASCII prompts that pwsh reads as UTF-8.
    $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), [System.Text.UTF8Encoding]::new($false))
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
    [Console]::Error.WriteLine('Add-RemoteGrant: hook payload is not valid JSON; recording no grant.')
    exit 0
}

if ($payload -isnot [pscustomobject]) {
    exit 0
}

try {
    $sessionId = ''
    foreach ($name in 'session_id', 'sessionId') {
        if ($payload.PSObject.Properties[$name] -and $payload.$name -is [string]) {
            $sessionId = [string]$payload.$name
            break
        }
    }

    $key = Get-GrantKey -SessionId $sessionId
    if ([string]::IsNullOrEmpty($key)) {
        [Console]::Error.WriteLine('Add-RemoteGrant: the payload names no usable session; recording no grant.')
        exit 0
    }

    $prompt = ''
    if ($payload.PSObject.Properties['prompt'] -and $payload.prompt -is [string]) {
        $prompt = [string]$payload.prompt
    }

    $root = $GrantRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        $profileRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($profileRoot)) {
            [Console]::Error.WriteLine('Add-RemoteGrant: no per-user application data folder; recording no grant.')
            exit 0
        }

        $root = [System.IO.Path]::Combine($profileRoot, 'CopilotAtelier', 'grants')
    }

    Clear-StaleGrantFile -Root $root

    $path = [System.IO.Path]::Combine($root, "grant-$key.json")
    $operation = Get-GrantOperation -Prompt $prompt

    # The previous prompt's grant ends here, whether or not this prompt asks for a new one.
    if ($operation.Count -eq 0) {
        if (-not (Revoke-GrantFile -Path $path)) {
            [Console]::Error.WriteLine('Add-RemoteGrant: the previous grant could not be removed; it lapses at its expiry.')
        }

        exit 0
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($prompt))
    } finally {
        $sha.Dispose()
    }

    $issuedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $grant = [ordered]@{
        schema = 1
        sessionKey = $key
        issuedAt = $issuedAt
        expiresAt = $issuedAt + $lifetimeSecond
        promptSha256 = [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
        operations = $operation
    }

    if (Write-GrantFile -Path $path -Json ($grant | ConvertTo-Json -Depth 4)) {
        $summary = foreach ($name in $operation.Keys) {
            if ($operation[$name] -gt 1) { '{0} x{1}' -f $name, $operation[$name] } else { $name }
        }
        [Console]::Error.WriteLine(('Add-RemoteGrant: recorded a Remote grant for this session: {0} (lasts {1} minutes or until your next prompt).' -f ($summary -join ', '), ($lifetimeSecond / 60)))
    } else {
        [Console]::Error.WriteLine('Add-RemoteGrant: the grant file could not be written; the guard keeps blocking.')
    }
} catch {
    [Console]::Error.WriteLine("Add-RemoteGrant: recording a grant failed: $_")
}

exit 0
