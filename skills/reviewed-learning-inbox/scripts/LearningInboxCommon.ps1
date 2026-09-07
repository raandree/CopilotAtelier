#Requires -Version 5.1

<#
    Shared helpers for the reviewed learning inbox. Dot-source this file from a
    workflow script; it defines functions only and performs no action on load.

    Every candidate field originates in an explicitly selected local artifact
    and is therefore untrusted observation, never policy. Intake and promotion
    both re-validate the same content rules, so editing the store by hand does
    not widen what may be written into a Customization.
#>

Set-StrictMode -Version Latest

$script:LearningInboxSchemaVersion = 1
$script:LearningInboxRelativeRoot = '.memory-bank/learning-inbox'
$script:LearningInboxLockFileName = '.candidates.lock'
$script:LearningInboxLockTimeoutMs = 1000
$script:LearningInboxConfidenceNote =
    'Confidence is a review label only. It is not a probability and not permission to apply the lesson.'

# SHA-256 of each store file as it was last read in this process, so a write can
# refuse to overwrite a mutation another writer made in between.
$script:LearningInboxStoreState = @{}

# Promotion may only append to an existing Skill body or Instruction body.
$script:LearningInboxTargetPattern = @{
    Skill = '^skills/[a-z0-9]+(-[a-z0-9]+)*/SKILL\.md$'
    Instruction = '^com\.github\.copilot/rules/[A-Za-z0-9._-]+\.instructions\.md$'
}

<#
    Printable text only. The excluded characters are the ones that turn stored
    observations into something other than prose when they reach a Markdown
    file: backtick and dollar (command substitution and fences), angle brackets
    (HTML and hook syntax), braces and pipes (YAML flow and expression syntax),
    brackets (link targets), backslash (escapes and path traversal).
#>
$script:LearningInboxAllowedText = '^[\p{L}\p{N} .,:;?!''"()/_+=%@#*-]+$'

# Frontmatter keys that would grant capability or rescope a Customization.
$script:LearningInboxPermissionKey =
    '(?i)(^|[\s(])(tools|allowed-tools|model|agents|handoffs|applyto|apply-to|name|description|target|context|compatibility|argument-hint)\s*:'

function Get-LearningInboxFullPath
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    $fullPath = [IO.Path]::GetFullPath($LiteralPath)
    $pathRoot = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -eq $pathRoot.Length)
    {
        return $fullPath
    }

    return $fullPath.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
}

function Get-LearningInboxPathComparison
{
    [CmdletBinding()]
    [OutputType([StringComparison])]
    param ()

    if ($env:OS -eq 'Windows_NT')
    {
        return [StringComparison]::OrdinalIgnoreCase
    }

    return [StringComparison]::Ordinal
}

function Test-LearningInboxPathEqual
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Left,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Right
    )

    return [string]::Equals($Left, $Right, (Get-LearningInboxPathComparison))
}

function Test-LearningInboxReparsePoint
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

<#
    Lexical containment plus a component walk. Checking only the leaf leaves a
    junction or symbolic link on an intermediate directory able to redirect a
    read or a write outside the selected project, so every existing component
    from the selected root down to the leaf is inspected. Components that do
    not exist yet are skipped, which is what makes the same guard usable before
    a directory or a file is created.
#>
function Assert-LearningInboxRegularPath
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Field
    )

    $root = Get-LearningInboxFullPath -LiteralPath $RepositoryRoot
    $full = Get-LearningInboxFullPath -LiteralPath $LiteralPath
    $comparison = Get-LearningInboxPathComparison

    if (-not (Test-LearningInboxPathEqual -Left $full -Right $root) -and
        -not $full.StartsWith(
            ($root + [IO.Path]::DirectorySeparatorChar),
            $comparison
        ))
    {
        throw "$Field must stay inside the selected project '$root': '$full'."
    }

    $chain = [Collections.Generic.List[string]]::new()
    $current = $full

    while (-not (Test-LearningInboxPathEqual -Left $current -Right $root))
    {
        $chain.Insert(0, $current)

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent))
        {
            throw "$Field must stay inside the selected project '$root': '$full'."
        }

        $current = Get-LearningInboxFullPath -LiteralPath $parent
    }

    $chain.Insert(0, $root)

    foreach ($component in $chain)
    {
        $item = Get-Item -LiteralPath $component -Force -ErrorAction SilentlyContinue
        if ($null -eq $item)
        {
            continue
        }

        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        {
            throw "$Field must not be reached through a symbolic link, junction, or other reparse point: '$component'."
        }
    }

    return $full
}

function Get-LearningInboxFileHash
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.
        ToLowerInvariant()
}

function Get-LearningInboxTextHash
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(
        ($Text -replace "`r`n", "`n")
    )
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try
    {
        return (
            $algorithm.ComputeHash($bytes) |
                ForEach-Object -Process { $_.ToString('x2') }
        ) -join ''
    }
    finally
    {
        $algorithm.Dispose()
    }
}

function Assert-LearningInboxRelativePath
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Field,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $message = "$Field must be a project-relative path inside the selected project: '$RelativePath'."

    if ([string]::IsNullOrWhiteSpace($RelativePath))
    {
        throw $message
    }

    $normalized = $RelativePath.Replace('\', '/').Trim()

    if ($normalized.Contains(':') -or
        $normalized.StartsWith('/') -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $normalized -match '(^|/)\.\.(/|$)' -or
        $normalized -match '(^|/)\.(/|$)' -or
        $normalized -match '//' -or
        $normalized.EndsWith('/'))
    {
        throw $message
    }

    $candidatePath = Get-LearningInboxFullPath -LiteralPath (
        Join-Path $RepositoryRoot $normalized.Replace(
            '/',
            [IO.Path]::DirectorySeparatorChar
        )
    )
    $rootPrefix = (Get-LearningInboxFullPath -LiteralPath $RepositoryRoot) +
        [IO.Path]::DirectorySeparatorChar

    if (-not $candidatePath.StartsWith($rootPrefix, (Get-LearningInboxPathComparison)))
    {
        throw $message
    }

    $null = Assert-LearningInboxRegularPath `
        -LiteralPath $candidatePath `
        -RepositoryRoot $RepositoryRoot `
        -Field $Field

    return $normalized
}

function Assert-LearningInboxText
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Field,

        [Parameter()]
        [ValidateRange(1, 2000)]
        [int]$MaximumLength = 400
    )

    $value = ([string]$Text).Trim()

    if ([string]::IsNullOrWhiteSpace($value))
    {
        throw "$Field must not be empty."
    }

    if ($value.Length -gt $MaximumLength)
    {
        throw "$Field must be at most $MaximumLength characters; the inbox stores summaries, not documents."
    }

    if ($value -notmatch $script:LearningInboxAllowedText)
    {
        throw "$Field contains unsupported content: only single-line printable prose is stored, so code fences, shell substitution, markup, and control characters are refused."
    }

    if ($value -match $script:LearningInboxPermissionKey)
    {
        throw "$Field contains unsupported content: a capability or scope key such as tools, model, agents, or applyTo can never be carried by a candidate."
    }

    return $value
}

function Get-LearningInboxNormalizedLesson
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Lesson
    )

    return (($Lesson -replace '\s+', ' ').Trim().TrimEnd('.') ).ToLowerInvariant()
}

function Resolve-LearningInboxContext
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (Test-LearningInboxReparsePoint -LiteralPath $item.FullName)
    {
        throw "Project root must not be a symbolic link, junction, or reparse point: '$($item.FullName)'."
    }

    $repositoryRoot = Get-LearningInboxFullPath -LiteralPath $item.FullName
    $memoryBankPath = Join-Path $repositoryRoot '.memory-bank'
    $inboxPath = Join-Path $memoryBankPath 'learning-inbox'
    $projectKey = if ($env:OS -eq 'Windows_NT')
    {
        $repositoryRoot.ToLowerInvariant()
    }
    else
    {
        $repositoryRoot
    }

    return [PSCustomObject]@{
        RepositoryRoot = $repositoryRoot
        MemoryBankPath = $memoryBankPath
        MemoryBankExists = Test-Path -LiteralPath $memoryBankPath -PathType Container
        InboxPath = $inboxPath
        StorePath = Join-Path $inboxPath 'candidates.json'
        StoreRelativePath = "$script:LearningInboxRelativeRoot/candidates.json"
        ProposalPath = Join-Path $inboxPath 'proposals'
        ProposalRelativePath = "$script:LearningInboxRelativeRoot/proposals"
        ProjectId = (Get-LearningInboxTextHash -Text $projectKey).Substring(0, 16)
    }
}

function Get-LearningInboxCandidateId
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScopeKey,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Lesson
    )

    $material = '{0}|{1}|{2}' -f
        $ProjectId,
        $ScopeKey.ToLowerInvariant(),
        (Get-LearningInboxNormalizedLesson -Lesson $Lesson)

    return 'cand-' + (Get-LearningInboxTextHash -Text $material).Substring(0, 12)
}

function Get-LearningInboxStoreKey
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context
    )

    $key = Get-LearningInboxFullPath -LiteralPath $Context.StorePath

    if ($env:OS -eq 'Windows_NT')
    {
        return $key.ToLowerInvariant()
    }

    return $key
}

function Get-LearningInboxStoreState
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context
    )

    if (Test-Path -LiteralPath $Context.StorePath -PathType Leaf)
    {
        return Get-LearningInboxFileHash -LiteralPath $Context.StorePath
    }

    return ''
}

function Read-LearningInboxStore
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context
    )

    # Walk the whole chain first: a junction on .memory-bank or on the inbox
    # directory would otherwise satisfy Test-Path from outside the project.
    $null = Assert-LearningInboxRegularPath `
        -LiteralPath $Context.StorePath `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field 'The learning inbox store'

    $script:LearningInboxStoreState[(Get-LearningInboxStoreKey -Context $Context)] =
        Get-LearningInboxStoreState -Context $Context

    if (-not (Test-Path -LiteralPath $Context.StorePath -PathType Leaf))
    {
        return $null
    }

    $store = Get-Content -LiteralPath $Context.StorePath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop

    if ($store.schemaVersion -ne $script:LearningInboxSchemaVersion)
    {
        throw "Unsupported learning inbox schema version '$($store.schemaVersion)'. Expected $script:LearningInboxSchemaVersion."
    }

    $recordedRoot = Get-LearningInboxFullPath -LiteralPath ([string]$store.repositoryRoot)
    if (-not (Test-LearningInboxPathEqual -Left $recordedRoot -Right $Context.RepositoryRoot))
    {
        throw "The learning inbox store records project '$recordedRoot', which does not match the selected project '$($Context.RepositoryRoot)'."
    }

    return $store
}

<#
    A bounded, fail-fast, per-inbox mutation lock. It is deliberately not a
    wait: a second writer that cannot take the lock within the timeout reports
    the contention and writes nothing, rather than blocking a review session.
#>
function Enter-LearningInboxLock
{
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter()]
        [ValidateRange(1, 30000)]
        [int]$TimeoutMilliseconds = $script:LearningInboxLockTimeoutMs
    )

    $lockPath = Join-Path $Context.InboxPath $script:LearningInboxLockFileName
    $null = Assert-LearningInboxRegularPath `
        -LiteralPath $lockPath `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field 'The learning inbox mutation lock'

    $deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)

    while ($true)
    {
        try
        {
            return [IO.FileStream]::new(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException]
        {
            if ([datetime]::UtcNow -ge $deadline)
            {
                throw "Another reviewed learning inbox mutation holds the lock '$lockPath'. Nothing was written; wait for it to finish and run the command again."
            }

            Start-Sleep -Milliseconds 50
        }
    }
}

function Exit-LearningInboxLock
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [IO.FileStream]$Handle
    )

    $Handle.Dispose()
}

function Write-LearningInboxStore
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Store
    )

    if (-not $Context.MemoryBankExists)
    {
        throw "Memory Bank not found: '$($Context.MemoryBankPath)'. Initialize it before recording a learning candidate."
    }

    foreach ($directory in @($Context.MemoryBankPath, $Context.InboxPath))
    {
        $null = Assert-LearningInboxRegularPath `
            -LiteralPath $directory `
            -RepositoryRoot $Context.RepositoryRoot `
            -Field 'The learning inbox directory'

        if (Test-Path -LiteralPath $directory)
        {
            if (-not (Test-Path -LiteralPath $directory -PathType Container))
            {
                throw "Learning inbox path is not a directory: '$directory'."
            }
        }
        else
        {
            New-Item -ItemType Directory -Path $directory -ErrorAction Stop |
                Out-Null
        }
    }

    $null = Assert-LearningInboxRegularPath `
        -LiteralPath $Context.StorePath `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field 'The learning inbox store'

    $key = Get-LearningInboxStoreKey -Context $Context
    $lock = Enter-LearningInboxLock -Context $Context

    try
    {
        $current = Get-LearningInboxStoreState -Context $Context
        if ($script:LearningInboxStoreState.ContainsKey($key) -and
            $script:LearningInboxStoreState[$key] -cne $current)
        {
            throw "The reviewed learning inbox store changed after it was read. Nothing was written; run the command again so the new candidate is recorded on top of the current store."
        }

        Write-LearningInboxFile `
            -LiteralPath $Context.StorePath `
            -Content ($Store | ConvertTo-Json -Depth 12)

        $script:LearningInboxStoreState[$key] = Get-LearningInboxStoreState -Context $Context
    }
    finally
    {
        Exit-LearningInboxLock -Handle $lock
    }
}

function Write-LearningInboxFile
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    $text = ($Content -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)

    $directory = Split-Path -Parent $LiteralPath
    $temporaryPath = Join-Path $directory (
        '.{0}.{1}.tmp' -f
            [IO.Path]::GetFileName($LiteralPath),
            [guid]::NewGuid().ToString('N')
    )

    try
    {
        [IO.File]::WriteAllBytes($temporaryPath, $bytes)

        # Replace rather than truncate-and-write, so an interrupted write never
        # leaves a half-written store behind. NullString keeps PowerShell from
        # binding an empty backup path, which Replace rejects.
        if (Test-Path -LiteralPath $LiteralPath -PathType Leaf)
        {
            [IO.File]::Replace($temporaryPath, $LiteralPath, [NullString]::Value)
        }
        else
        {
            [IO.File]::Move($temporaryPath, $LiteralPath)
        }
    }
    finally
    {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf)
        {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-LearningInboxCanonicalCandidate
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Candidate
    )

    $decision = if ($null -eq $Candidate.decision)
    {
        $null
    }
    else
    {
        [PSCustomObject][ordered]@{
            status = [string]$Candidate.decision.status
            reason = [string]$Candidate.decision.reason
            recordedUtc = [string]$Candidate.decision.recordedUtc
        }
    }

    return [PSCustomObject][ordered]@{
        id = [string]$Candidate.id
        lesson = [string]$Candidate.lesson
        scope = [PSCustomObject][ordered]@{
            kind = [string]$Candidate.scope.kind
            target = [string]$Candidate.scope.target
            overlap = [string]$Candidate.scope.overlap
        }
        evidence = @(
            foreach ($item in @($Candidate.evidence))
            {
                [PSCustomObject][ordered]@{
                    path = [string]$item.path
                    sha256 = [string]$item.sha256
                    lines = [string]$item.lines
                    summary = [string]$item.summary
                }
            }
        )
        observations = @($Candidate.observations | ForEach-Object -Process { [string]$_ })
        interpretations = @($Candidate.interpretations | ForEach-Object -Process { [string]$_ })
        contradictions = @($Candidate.contradictions | ForEach-Object -Process { [string]$_ })
        confidence = [string]$Candidate.confidence
        status = [string]$Candidate.status
        supersededBy = [string]$Candidate.supersededBy
        supersedes = @($Candidate.supersedes | ForEach-Object -Process { [string]$_ })
        occurrences = [int]$Candidate.occurrences
        createdUtc = [string]$Candidate.createdUtc
        decision = $decision
    }
}

function Get-LearningInboxCandidateHash
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Candidate
    )

    $canonical = New-LearningInboxCanonicalCandidate -Candidate $Candidate
    return Get-LearningInboxTextHash -Text (
        $canonical | ConvertTo-Json -Depth 12 -Compress
    )
}

function Assert-LearningInboxCandidateContent
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Candidate,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    $null = Assert-LearningInboxText -Text ([string]$Candidate.lesson) -Field 'Lesson' -MaximumLength 400

    foreach ($observation in @($Candidate.observations))
    {
        $null = Assert-LearningInboxText -Text ([string]$observation) -Field 'Observation' -MaximumLength 300
    }

    foreach ($interpretation in @($Candidate.interpretations))
    {
        $null = Assert-LearningInboxText -Text ([string]$interpretation) -Field 'Interpretation' -MaximumLength 300
    }

    foreach ($contradiction in @($Candidate.contradictions))
    {
        $null = Assert-LearningInboxText -Text ([string]$contradiction) -Field 'Contradictory evidence' -MaximumLength 300
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.scope.overlap))
    {
        $null = Assert-LearningInboxText -Text ([string]$Candidate.scope.overlap) -Field 'Overlap' -MaximumLength 300
    }

    foreach ($item in @($Candidate.evidence))
    {
        $null = Assert-LearningInboxRelativePath `
            -RelativePath ([string]$item.path) `
            -Field 'Evidence path' `
            -RepositoryRoot $RepositoryRoot

        if (([string]$item.sha256) -notmatch '^[0-9a-f]{64}$')
        {
            throw "Evidence content identity must be a SHA-256 value: '$($item.sha256)'."
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$item.summary))
        {
            $null = Assert-LearningInboxText -Text ([string]$item.summary) -Field 'Evidence summary' -MaximumLength 300
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$item.lines) -and
            ([string]$item.lines) -notmatch '^\d+(-\d+)?$')
        {
            throw "Evidence line range must be a single number or a numeric range: '$($item.lines)'."
        }
    }
}

function Assert-LearningInboxPromotionTarget
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Target,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScopeKind,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    if (-not $script:LearningInboxTargetPattern.ContainsKey($ScopeKind))
    {
        throw "Scope kind '$ScopeKind' is a suggestion for review only and is not promotable. Only Skill and Instruction targets may be appended to."
    }

    $normalized = Assert-LearningInboxRelativePath `
        -RelativePath $Target `
        -Field 'Promotion target' `
        -RepositoryRoot $RepositoryRoot

    if ($normalized -notmatch $script:LearningInboxTargetPattern[$ScopeKind])
    {
        throw "Promotion target '$normalized' is outside the allowed $ScopeKind surface. Allowed pattern: $($script:LearningInboxTargetPattern[$ScopeKind])."
    }

    return $normalized
}

function New-LearningInboxBlock
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Candidate,

        [Parameter(Mandatory)]
        [ValidateSet('AppendSection', 'AppendEntry')]
        [string]$Mode
    )

    $id = [string]$Candidate.id
    $line = [Collections.Generic.List[string]]::new()

    if ($Mode -eq 'AppendSection')
    {
        $line.Add('')
        $line.Add('<!-- reviewed-learning-inbox:section -->')
        $line.Add('## Reviewed lessons')
        $line.Add('')
        $line.Add('Promoted from the reviewed learning inbox after explicit human approval.')
    }

    $line.Add('')
    $line.Add("<!-- reviewed-learning-inbox:candidate $id -->")
    $line.Add("- $([string]$Candidate.lesson)")
    $line.Add("  - Scope: $([string]$Candidate.scope.kind) ($([string]$Candidate.scope.target))")

    foreach ($item in @($Candidate.evidence))
    {
        $range = if ([string]::IsNullOrWhiteSpace([string]$item.lines))
        {
            ''
        }
        else
        {
            " lines $([string]$item.lines)"
        }
        $summary = if ([string]::IsNullOrWhiteSpace([string]$item.summary))
        {
            ''
        }
        else
        {
            " - $([string]$item.summary)"
        }
        $line.Add(
            "  - Evidence: $([string]$item.path)$range (sha256 $(([string]$item.sha256).Substring(0, 12)))$summary"
        )
    }

    foreach ($observation in @($Candidate.observations))
    {
        $line.Add("  - Observation: $observation")
    }

    foreach ($interpretation in @($Candidate.interpretations))
    {
        $line.Add("  - Interpretation: $interpretation")
    }

    foreach ($contradiction in @($Candidate.contradictions))
    {
        $line.Add("  - Contradictory evidence: $contradiction")
    }

    $line.Add("  - Confidence label: $([string]$Candidate.confidence). $script:LearningInboxConfidenceNote")
    $line.Add("<!-- reviewed-learning-inbox:end $id -->")

    return ($line -join "`n") + "`n"
}

function New-LearningInboxPreview
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Candidate,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetSha256,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Block,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Mode
    )

    $line = [Collections.Generic.List[string]]::new()
    $line.Add('Reviewed learning inbox promotion preview')
    $line.Add("Candidate: $([string]$Candidate.id)")
    $line.Add("Target: $TargetPath")
    $line.Add("Target SHA-256: $TargetSha256")
    $line.Add("Mode: $Mode")
    $line.Add('')

    foreach ($blockLine in ($Block.TrimEnd("`n") -split "`n"))
    {
        $line.Add(('+ ' + $blockLine).TrimEnd())
    }

    return ($line -join "`n") + "`n"
}

function Get-LearningInboxCandidate
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Store,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    $match = @($Store.candidates | Where-Object -FilterScript { [string]$_.id -eq $Id })
    if ($match.Count -eq 0)
    {
        throw "Candidate '$Id' was not found in the reviewed learning inbox for this project."
    }

    return $match[0]
}

<#
    Only strict UTF-8, with or without a byte order mark, is understood. Any
    other encoding is refused rather than silently rewritten, because reading a
    file as text and writing it back changes bytes the promotion never
    reviewed.
#>
function ConvertFrom-LearningInboxTargetByte
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Byte,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    $hasByteOrderMark = $Byte.Length -ge 3 -and
        $Byte[0] -eq 0xEF -and $Byte[1] -eq 0xBB -and $Byte[2] -eq 0xBF

    if (-not $hasByteOrderMark -and $Byte.Length -ge 2 -and
        (($Byte[0] -eq 0xFF -and $Byte[1] -eq 0xFE) -or
            ($Byte[0] -eq 0xFE -and $Byte[1] -eq 0xFF)))
    {
        throw "The promotion destination '$LiteralPath' has an unsupported encoding. Only UTF-8, with or without a byte order mark, can be appended to; nothing was written."
    }

    $offset = if ($hasByteOrderMark)
    {
        3
    }
    else
    {
        0
    }

    try
    {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString(
            $Byte,
            $offset,
            $Byte.Length - $offset
        )
    }
    catch
    {
        throw "The promotion destination '$LiteralPath' has an unsupported encoding: it is not valid UTF-8 text. Nothing was written."
    }

    return [PSCustomObject]@{
        Text = $text
        Byte = $Byte
        HasByteOrderMark = $hasByteOrderMark
    }
}

function Read-LearningInboxTargetFile
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    return ConvertFrom-LearningInboxTargetByte `
        -Byte ([IO.File]::ReadAllBytes($LiteralPath)) `
        -LiteralPath $LiteralPath
}

function Get-LearningInboxStreamByte
{
    [CmdletBinding()]
    [OutputType([byte[]])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [IO.FileStream]$Stream
    )

    $length = [int]$Stream.Length
    $buffer = [byte[]]::new($length)
    $Stream.Position = 0

    $read = 0
    while ($read -lt $length)
    {
        $chunk = $Stream.Read($buffer, $read, $length - $read)
        if ($chunk -le 0)
        {
            break
        }

        $read += $chunk
    }

    return $buffer
}

function Get-LearningInboxByteHash
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Byte
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try
    {
        return (
            $algorithm.ComputeHash($Byte) |
                ForEach-Object -Process { $_.ToString('x2') }
        ) -join ''
    }
    finally
    {
        $algorithm.Dispose()
    }
}

<#
    Appends through a single write-exclusive handle. The bytes that are hashed
    and the bytes that are appended to are the same bytes, so an edit made
    between an earlier read and this write is detected instead of overwritten,
    and the original byte prefix, including any byte order mark, survives
    untouched. A failed verification truncates back to the original length.
#>
function Add-LearningInboxTargetContent
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{64}$')]
        [string]$ExpectedSha256,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Block,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RequiredMarker
    )

    $stream = [IO.FileStream]::new(
        $LiteralPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )

    try
    {
        $original = Get-LearningInboxStreamByte -Stream $stream
        $previousSha256 = Get-LearningInboxByteHash -Byte $original

        if ($previousSha256 -cne $ExpectedSha256.ToLowerInvariant())
        {
            throw "The promotion destination '$LiteralPath' changed between the review and the write. Nothing was written; generate a new proposal and review it again."
        }

        $state = ConvertFrom-LearningInboxTargetByte -Byte $original -LiteralPath $LiteralPath
        $usesCarriageReturn = $state.Text.Contains("`r`n")

        $appendBlock = if ($usesCarriageReturn)
        {
            $Block -replace "(?<!`r)`n", "`r`n"
        }
        else
        {
            $Block
        }

        $separator = if ($state.Text.EndsWith("`n"))
        {
            ''
        }
        elseif ($usesCarriageReturn)
        {
            "`r`n"
        }
        else
        {
            "`n"
        }

        $appendByte = [Text.UTF8Encoding]::new($false).GetBytes($separator + $appendBlock)

        $stream.Position = $original.Length
        $stream.Write($appendByte, 0, $appendByte.Length)
        $stream.Flush($true)

        $updated = Get-LearningInboxStreamByte -Stream $stream
        $prefixIntact = $updated.Length -ge $original.Length

        if ($prefixIntact)
        {
            for ($index = 0; $index -lt $original.Length; $index++)
            {
                if ($updated[$index] -ne $original[$index])
                {
                    $prefixIntact = $false
                    break
                }
            }
        }

        $markerPresent = $prefixIntact -and
            (ConvertFrom-LearningInboxTargetByte -Byte $updated -LiteralPath $LiteralPath).
            Text.Contains($RequiredMarker)

        if (-not $prefixIntact -or -not $markerPresent)
        {
            $stream.SetLength($original.Length)
            $stream.Flush($true)
            throw "Promotion verification failed for '$LiteralPath'. The original bytes were restored and nothing was promoted."
        }

        return [PSCustomObject]@{
            PreviousSha256 = $previousSha256
            NewSha256 = Get-LearningInboxByteHash -Byte $updated
            AppendedByteCount = $appendByte.Length
            HasByteOrderMark = $state.HasByteOrderMark
        }
    }
    finally
    {
        $stream.Dispose()
    }
}

<#
    Returns the exact marker-delimited region for one candidate, or null when
    the destination carries none. A half-marker or a duplicate is an edit no
    promotion produces, so both are refused rather than interpreted.
#>
function Get-LearningInboxBlockRegion
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CandidateId
    )

    $start = "<!-- reviewed-learning-inbox:candidate $CandidateId -->"
    $end = "<!-- reviewed-learning-inbox:end $CandidateId -->"
    $normalized = $Content -replace "`r`n", "`n"

    $matched = [regex]::Matches(
        $normalized,
        ('(?s)' + [regex]::Escape($start) + '.*?' + [regex]::Escape($end))
    )

    if ($matched.Count -gt 1)
    {
        throw "The promotion destination carries $($matched.Count) blocks for candidate '$CandidateId'. A promotion never produces a duplicate; resolve it by hand before promoting again."
    }

    if ($matched.Count -eq 1)
    {
        return $matched[0].Value
    }

    if ($normalized.Contains($start) -or $normalized.Contains($end))
    {
        throw "The promotion destination carries an incomplete reviewed-learning-inbox marker for candidate '$CandidateId'. A promotion never produces one, so the destination was edited by hand; resolve it before promoting again."
    }

    return $null
}

<#
    The candidate record is the authority for evidence. A proposal is an
    editable file, so an entry removed from it must not be able to skip the
    changed-evidence check while the candidate hash still matches.
#>
function Assert-LearningInboxEvidenceIdentity
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Candidate,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$ProposalEvidence
    )

    $expected = @(
        foreach ($item in @($Candidate.evidence))
        {
            '{0}|{1}' -f ([string]$item.path), ([string]$item.sha256).ToLowerInvariant()
        }
    )

    $actual = @(
        foreach ($item in @($ProposalEvidence))
        {
            if ($null -eq $item)
            {
                continue
            }

            '{0}|{1}' -f ([string]$item.path), ([string]$item.sha256).ToLowerInvariant()
        }
    )

    if ($expected.Count -ne $actual.Count)
    {
        throw "The promotion proposal lists $($actual.Count) evidence locators but the candidate record carries $($expected.Count). The candidate record is the authority; generate a new proposal and review it again."
    }

    for ($index = 0; $index -lt $expected.Count; $index++)
    {
        if ($expected[$index] -cne $actual[$index])
        {
            throw "The promotion proposal evidence does not match the candidate record: expected '$($expected[$index])' but found '$($actual[$index])'. Generate a new proposal and review it again."
        }
    }
}

function Assert-LearningInboxEvidenceState
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Candidate,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    foreach ($item in @($Candidate.evidence))
    {
        $relativePath = Assert-LearningInboxRelativePath `
            -RelativePath ([string]$item.path) `
            -Field 'Evidence path' `
            -RepositoryRoot $RepositoryRoot

        $absolutePath = Join-Path $RepositoryRoot (
            $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        )

        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf))
        {
            throw "The candidate evidence '$relativePath' is no longer present. Generate a new proposal and review it again."
        }

        if ((Get-LearningInboxFileHash -LiteralPath $absolutePath) -cne
            ([string]$item.sha256).ToLowerInvariant())
        {
            throw "The candidate evidence '$relativePath' changed after the preview was produced. Generate a new proposal and review it again."
        }
    }
}
