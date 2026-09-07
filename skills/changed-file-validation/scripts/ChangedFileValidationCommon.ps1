#Requires -Version 5.1

<#
    Shared helpers for changed-file validation. Dot-source this file from a
    workflow script; it defines functions only and performs no action on load.

    Every path this module touches is guarded against the selected project root
    before it is read, hashed, or written, and every validator is invoked
    through an explicit argument boundary. A file name is data: it is never
    interpolated into a command line, a script block, or a wildcard pattern.
#>

Set-StrictMode -Version Latest

$script:ChangedFileScriptRoot = $PSScriptRoot
$script:ChangedFileSchemaVersion = 1
$script:ChangedFileStateRelativeRoot = '.copilot-atelier/changed-file-validation'
$script:ChangedFileStoreFileName = 'batches.json'
$script:ChangedFileLockFileName = '.batches.lock'
$script:ChangedFileLockTimeoutMs = 15000
$script:ChangedFileSessionPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
$script:ChangedFileMaxEntryPerSession = 500
$script:ChangedFileMaxDiagnostic = 20
$script:ChangedFileMaxMessageLength = 500
$script:ChangedFileMaxOutputCharacter = 20000
$script:ChangedFileSnapshotDirectoryName = 'snapshot'
$script:ChangedFileWorkerFileName = 'Invoke-ChangedFileValidationWorker.ps1'
$script:ChangedFileSha256Pattern = '^[0-9a-f]{64}$'

# The only results a check can carry. Anything else in a receipt is a forgery or
# a record this implementation cannot interpret, and neither may become a pass.
$script:ChangedFileCheckOutcome = @('Passed', 'Failed', 'Unavailable', 'TimedOut')

# The shipped implementation the checks are actually performed by. A receipt
# that does not name it survives an edit to the checker itself.
$script:ChangedFileImplementationFile = @{
    Common = 'ChangedFileValidationCommon.ps1'
    Worker = 'Invoke-ChangedFileValidationWorker.ps1'
}

# An external entry point is identified by its content. Beyond this bound the
# hash is skipped and the weaker size-and-timestamp identity is recorded openly.
$script:ChangedFileMaxExecutableIdentityByte = 16777216

# One child process at a time, and one validation run per session. Validation is
# a background courtesy, not a build: an unbounded fan-out would compete with the
# work the user is doing, and two runs over one batch would race on the receipt.
$script:ChangedFileMaxConcurrentProcess = 1

# Only an interface that has been read, implemented, and tested is trusted. Any
# other name is reported Unavailable rather than guessed at.
$script:ChangedFileMarkdownLintInterface = @('markdownlint-cli')

$script:ChangedFileDeclarativeMarkdownConfig = @(
    '.markdownlint.jsonc'
    '.markdownlint.json'
    '.markdownlint.yaml'
    '.markdownlint.yml'
)

# The only declarative formats this workflow has a trusted, non-executing parser
# for. Everything else is reported unavailable rather than judged by a text scan.
$script:ChangedFileParsableMarkdownConfig = @('.json', '.jsonc')

# Keys that can pull code or another document into a lint run. A configuration
# naming one of these at any depth is refused, however the key is spelled: the
# document is parsed first, so a Unicode escape resolves before this comparison.
$script:ChangedFileForbiddenConfigKey = @(
    'extends'
    'customrules'
    'modulepaths'
    'markdownitplugins'
    'outputformatters'
    'plugins'
    'require'
    'import'
    'script'
    'command'
)

# A markdownlint rule map: rule identifiers and lowercase aliases at the root,
# ordinary parameter names below it, and nothing exotic anywhere.
$script:ChangedFileRootConfigKeyPattern = '^(MD\d{3}|[a-z][a-z0-9-]{0,63})$'
$script:ChangedFileConfigKeyPattern = '^[A-Za-z][A-Za-z0-9_-]{0,63}$'
$script:ChangedFileMaxConfigDepth = 4
$script:ChangedFileMaxConfigNode = 2000

# A configuration that can load or reference code is refused outright: the linter
# would execute it, and this workflow never executes project configuration.
$script:ChangedFileExecutableMarkdownConfig = @(
    '.markdownlint.js'
    '.markdownlint.cjs'
    '.markdownlint.mjs'
    '.markdownlint-cli2.js'
    '.markdownlint-cli2.cjs'
    '.markdownlint-cli2.mjs'
    '.markdownlint-cli2.jsonc'
    '.markdownlint-cli2.json'
    '.markdownlint-cli2.yaml'
    '.markdownlint-cli2.yml'
)

$script:ChangedFileCache = @{
    AnalyzerVersion = $null
    LinterVersion = @{}
    ExecutableIdentity = @{}
    ImplementationIdentity = @{}
    JsonReaderAvailable = $null
}

$script:ChangedFileValidatorPlan = @{
    '.ps1'  = @('PowerShell.Parse', 'PowerShell.ScriptAnalyzer')
    '.psm1' = @('PowerShell.Parse', 'PowerShell.ScriptAnalyzer')
    '.psd1' = @('PowerShell.Parse', 'PowerShell.ScriptAnalyzer')
    '.md'   = @('Markdown.NativeStructure', 'Markdown.Lint')
}

function Get-ChangedFileFullPath
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

function Get-ChangedFilePathComparison
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

function Test-ChangedFilePathEqual
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

    return [string]::Equals($Left, $Right, (Get-ChangedFilePathComparison))
}

<#
    Lexical containment plus a component walk. Checking only the leaf leaves a
    junction or symbolic link on an intermediate directory able to redirect a
    read or a write outside the selected project, so every existing component
    from the root down to the leaf is inspected. Components that do not exist
    are skipped, which is what makes the same guard usable for a deleted file
    and for a store file that has not been created yet.
#>
function Assert-ChangedFileRegularPath
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

    $root = Get-ChangedFileFullPath -LiteralPath $RepositoryRoot
    $full = Get-ChangedFileFullPath -LiteralPath $LiteralPath
    $comparison = Get-ChangedFilePathComparison

    if (-not (Test-ChangedFilePathEqual -Left $full -Right $root) -and
        -not $full.StartsWith(($root + [IO.Path]::DirectorySeparatorChar), $comparison))
    {
        throw "$Field must stay inside the selected project '$root': '$full'."
    }

    $chain = [Collections.Generic.List[string]]::new()
    $current = $full

    while (-not (Test-ChangedFilePathEqual -Left $current -Right $root))
    {
        $chain.Insert(0, $current)

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent))
        {
            throw "$Field must stay inside the selected project '$root': '$full'."
        }

        $current = Get-ChangedFileFullPath -LiteralPath $parent
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

function Assert-ChangedFileSessionId
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SessionId
    )

    if ($SessionId -notmatch $script:ChangedFileSessionPattern)
    {
        throw "The session identifier must be 1 to 64 characters of letters, digits, period, underscore, or hyphen, starting with a letter or digit. A separator or a traversal segment is refused so a session can never name a path."
    }

    return $SessionId
}

function Resolve-ChangedFileContext
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
    if (-not $item.PSIsContainer)
    {
        throw "The selected project root must be a directory: '$($item.FullName)'."
    }

    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    {
        throw "The selected project root must not be a symbolic link, junction, or other reparse point: '$($item.FullName)'."
    }

    $repositoryRoot = Get-ChangedFileFullPath -LiteralPath $item.FullName
    $stateDirectory = Join-Path $repositoryRoot (
        $script:ChangedFileStateRelativeRoot -replace '/', [IO.Path]::DirectorySeparatorChar
    )

    return [PSCustomObject]@{
        RepositoryRoot = $repositoryRoot
        StateDirectory = $stateDirectory
        StorePath = Join-Path $stateDirectory $script:ChangedFileStoreFileName
        LockPath = Join-Path $stateDirectory $script:ChangedFileLockFileName
        StoreRelativePath = "$script:ChangedFileStateRelativeRoot/$script:ChangedFileStoreFileName"
    }
}

function Resolve-ChangedFileRelativePath
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$InputPath
    )

    $field = 'A changed path'

    if ([string]::IsNullOrWhiteSpace($InputPath))
    {
        throw "$field must not be empty."
    }

    $candidate = $InputPath.Trim()
    $normalized = $candidate.Replace('\', '/')

    if (-not [IO.Path]::IsPathRooted($candidate))
    {
        if ($normalized -match '(^|/)\.\.(/|$)' -or $normalized.StartsWith('/') -or $normalized.Contains(':'))
        {
            throw "$field must be a project-relative path without a traversal segment, a drive qualifier, or a leading separator: '$candidate'."
        }

        $candidate = Join-Path $Context.RepositoryRoot (
            $normalized -replace '/', [IO.Path]::DirectorySeparatorChar
        )
    }

    $full = Assert-ChangedFileRegularPath `
        -LiteralPath $candidate `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field $field

    if (Test-ChangedFilePathEqual -Left $full -Right $Context.RepositoryRoot)
    {
        throw "$field must name a file inside the project, not the project root itself."
    }

    return $full.Substring($Context.RepositoryRoot.Length + 1).Replace(
        [IO.Path]::DirectorySeparatorChar, '/'
    )
}

function Get-ChangedFileContentHash
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    # Streamed rather than Get-FileHash: the hash must cover the exact bytes on
    # disk with no provider, encoding, or line-ending normalization in between.
    $stream = [IO.File]::Open(
        $LiteralPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )

    try
    {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try
        {
            return (
                $algorithm.ComputeHash($stream) |
                    ForEach-Object -Process { $_.ToString('x2') }
            ) -join ''
        }
        finally
        {
            $algorithm.Dispose()
        }
    }
    finally
    {
        $stream.Dispose()
    }
}

function Get-ChangedFileTextHash
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try
    {
        return (
            $algorithm.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)) |
                ForEach-Object -Process { $_.ToString('x2') }
        ) -join ''
    }
    finally
    {
        $algorithm.Dispose()
    }
}

function ConvertTo-ChangedFileHashtable
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject)
    {
        return $null
    }

    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive)
    {
        return $InputObject
    }

    if ($InputObject -is [Collections.IDictionary])
    {
        $map = @{}
        foreach ($key in @($InputObject.Keys))
        {
            $map[[string]$key] = ConvertTo-ChangedFileHashtable -InputObject $InputObject[$key]
        }

        return $map
    }

    if ($InputObject -is [PSCustomObject])
    {
        $map = @{}
        foreach ($property in $InputObject.PSObject.Properties)
        {
            $map[$property.Name] = ConvertTo-ChangedFileHashtable -InputObject $property.Value
        }

        return $map
    }

    if ($InputObject -is [Collections.IEnumerable])
    {
        return @(
            foreach ($element in $InputObject)
            {
                , (ConvertTo-ChangedFileHashtable -InputObject $element)
            }
        )
    }

    return $InputObject
}

function New-ChangedFileStore
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds an in-memory document and changes nothing.'
    )]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context
    )

    return @{
        schemaVersion = $script:ChangedFileSchemaVersion
        repositoryRoot = $Context.RepositoryRoot
        sessions = @{}
    }
}

function Read-ChangedFileStore
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context
    )

    # Walk the whole chain first: a junction on the state directory would
    # otherwise satisfy Test-Path from outside the project.
    $null = Assert-ChangedFileRegularPath `
        -LiteralPath $Context.StorePath `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field 'The changed-file batch store'

    if (-not (Test-Path -LiteralPath $Context.StorePath -PathType Leaf))
    {
        return $null
    }

    $raw = Get-Content -LiteralPath $Context.StorePath -Raw -Encoding UTF8
    $store = ConvertTo-ChangedFileHashtable -InputObject (
        $raw | ConvertFrom-Json -ErrorAction Stop
    )

    if ($store -isnot [Collections.IDictionary] -or
        -not $store.ContainsKey('schemaVersion') -or
        -not $store.ContainsKey('repositoryRoot') -or
        -not $store.ContainsKey('sessions'))
    {
        throw "The changed-file batch store '$($Context.StoreRelativePath)' is not a supported document. Delete it to start a new batch."
    }

    if ($store['schemaVersion'] -ne $script:ChangedFileSchemaVersion)
    {
        throw "Unsupported changed-file batch schema version '$($store['schemaVersion'])'. Expected $script:ChangedFileSchemaVersion."
    }

    $recordedRoot = Get-ChangedFileFullPath -LiteralPath ([string]$store['repositoryRoot'])
    if (-not (Test-ChangedFilePathEqual -Left $recordedRoot -Right $Context.RepositoryRoot))
    {
        throw "The changed-file batch store records project '$recordedRoot', which does not match the selected project '$($Context.RepositoryRoot)'."
    }

    if ($store['sessions'] -isnot [Collections.IDictionary])
    {
        throw "The changed-file batch store '$($Context.StoreRelativePath)' does not carry a session map."
    }

    return $store
}

<#
    A bounded mutation lock. Collection is a background courtesy that several
    processes may perform at the same time, so a contended writer waits and
    retries inside the bound instead of failing and dropping the file it was
    asked to record.
#>
function Enter-ChangedFileLock
{
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter()]
        [ValidateRange(1, 120000)]
        [int]$TimeoutMillisecond = $script:ChangedFileLockTimeoutMs
    )

    $null = Assert-ChangedFileRegularPath `
        -LiteralPath $Context.LockPath `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field 'The changed-file batch lock'

    Initialize-ChangedFileStateDirectory -Context $Context

    $deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMillisecond)

    while ($true)
    {
        try
        {
            return [IO.FileStream]::new(
                $Context.LockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException]
        {
            if ([datetime]::UtcNow -ge $deadline)
            {
                throw "Another changed-file batch mutation holds the lock '$($Context.LockPath)'. Nothing was written; run the command again."
            }

            Start-Sleep -Milliseconds 25
        }
    }
}

function Exit-ChangedFileLock
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

function Initialize-ChangedFileStateDirectory
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context
    )

    $null = Assert-ChangedFileRegularPath `
        -LiteralPath $Context.StateDirectory `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field 'The changed-file batch directory'

    if (Test-Path -LiteralPath $Context.StateDirectory)
    {
        if (-not (Test-Path -LiteralPath $Context.StateDirectory -PathType Container))
        {
            throw "The changed-file batch path is not a directory: '$($Context.StateDirectory)'."
        }

        return
    }

    New-Item -ItemType Directory -Path $Context.StateDirectory -Force | Out-Null
}

<#
    Session execution exclusion. Collection may be concurrent, but validation may
    not: two runs over one batch would start two sets of children and race on the
    same receipts. The handle is held for the whole validator loop.
#>
function Enter-ChangedFileExecutionLock
{
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId,

        [Parameter()]
        [ValidateRange(0, 600000)]
        [int]$TimeoutMillisecond = 30000
    )

    Initialize-ChangedFileStateDirectory -Context $Context

    $lockPath = Join-Path $Context.StateDirectory ('.execution-{0}.lock' -f $SessionId)
    $null = Assert-ChangedFileRegularPath -LiteralPath $lockPath `
        -RepositoryRoot $Context.RepositoryRoot -Field 'The changed-file execution lock'

    $deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMillisecond)

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
                throw "Another changed-file validation run holds the execution lock for session '$SessionId'. Nothing was validated; run the command again when it finishes."
            }

            Start-Sleep -Milliseconds 50
        }
    }
}

<#
    Copies the exact bytes to be checked into an isolated directory under a
    generated, metacharacter-free name, and hashes what was copied.

    Two properties follow from this and neither is achievable by handing a
    validator the project path. The receipt is bound to the byte sequence the
    validator actually read rather than to a path that may have moved underneath
    it, and every argument handed to an external tool is a name this workflow
    generated, so a hostile file name, a glob, or a shell metacharacter in the
    project never reaches a command line at all.
#>
function New-ChangedFileSnapshot
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Writes only to a generated directory inside the batch state, removed by Remove-ChangedFileSnapshot.'
    )]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FullPath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$ConfigPath = ''
    )

    Initialize-ChangedFileStateDirectory -Context $Context

    $directory = Join-Path $Context.StateDirectory (
        Join-Path $script:ChangedFileSnapshotDirectoryName ([guid]::NewGuid().ToString('N'))
    )
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $extension = [IO.Path]::GetExtension($FullPath).ToLowerInvariant()
    $fileName = 'snapshot{0}' -f $extension
    $snapshotPath = Join-Path $directory $fileName

    [IO.File]::WriteAllBytes($snapshotPath, [IO.File]::ReadAllBytes($FullPath))

    $configFileName = ''
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath))
    {
        $configFileName = 'markdownlint-config{0}' -f [IO.Path]::GetExtension($ConfigPath).ToLowerInvariant()
        [IO.File]::WriteAllBytes(
            (Join-Path $directory $configFileName),
            [IO.File]::ReadAllBytes($ConfigPath)
        )
    }

    return [PSCustomObject]@{
        Directory = $directory
        FileName = $fileName
        FullPath = $snapshotPath
        ConfigFileName = $configFileName
        Sha256 = Get-ChangedFileContentHash -LiteralPath $snapshotPath
        Byte = [long] (Get-Item -LiteralPath $snapshotPath -Force).Length
    }
}

function Remove-ChangedFileSnapshot
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path -LiteralPath $Directory))
    {
        return
    }

    if ($PSCmdlet.ShouldProcess($Directory, 'Remove validation snapshot'))
    {
        Remove-Item -LiteralPath $Directory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

<#
    Windows PowerShell has no ProcessStartInfo.ArgumentList, so a command line
    has to be composed. Every argument this workflow passes is a name it
    generated, and anything carrying a quote or a control character is refused
    outright rather than escaped and hoped for.
#>
function ConvertTo-ChangedFileCommandLine
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Argument
    )

    $part = foreach ($value in $Argument)
    {
        if ($value -match '["\p{Cc}]')
        {
            throw "An argument carrying a quote or a control character cannot be passed safely on this host: '$value'."
        }

        if ([string]::IsNullOrEmpty($value))
        {
            '""'
        }
        elseif ($value -notmatch '\s')
        {
            $value
        }
        else
        {
            '"{0}"' -f ($value -replace '(\\+)$', '$1$1')
        }
    }

    return @($part) -join ' '
}

function Write-ChangedFileStore
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Store
    )

    Initialize-ChangedFileStateDirectory -Context $Context

    $null = Assert-ChangedFileRegularPath `
        -LiteralPath $Context.StorePath `
        -RepositoryRoot $Context.RepositoryRoot `
        -Field 'The changed-file batch store'

    $text = (($Store | ConvertTo-Json -Depth 12) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)

    $temporaryPath = Join-Path $Context.StateDirectory (
        '.{0}.{1}.tmp' -f $script:ChangedFileStoreFileName, [guid]::NewGuid().ToString('N')
    )

    try
    {
        [IO.File]::WriteAllBytes($temporaryPath, $bytes)

        # Replace rather than truncate-and-write, so an interrupted write never
        # leaves a half-written batch behind.
        if (Test-Path -LiteralPath $Context.StorePath -PathType Leaf)
        {
            [IO.File]::Replace($temporaryPath, $Context.StorePath, [NullString]::Value)
        }
        else
        {
            [IO.File]::Move($temporaryPath, $Context.StorePath)
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

function Get-ChangedFileSessionEntry
{
    [CmdletBinding()]
    [OutputType([Collections.IList])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Store,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId
    )

    if (-not $Store['sessions'].ContainsKey($SessionId))
    {
        return @()
    }

    $session = $Store['sessions'][$SessionId]
    if ($session -isnot [Collections.IDictionary] -or -not $session.ContainsKey('entries'))
    {
        throw "The changed-file batch store holds an unsupported record for session '$SessionId'."
    }

    return @($session['entries'])
}

<#
    A bounded content identity for the shipped code that performs the checks.

    A plan built from rule identifiers and runtime versions alone survives an
    edit to the checker itself, so a receipt written by yesterday's worker keeps
    reporting Verified after the worker is changed. Hashing the shipped
    implementation files closes that: editing the common helpers or the worker
    changes the plan and every receipt made under the old code is refused.

    The identity is bounded on purpose. It covers the files this skill ships and
    nothing beneath them - not PSScriptAnalyzer's own rule implementations, and
    not the modules an external linter loads.
#>
function Get-ChangedFileImplementationIdentity
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Common', 'Worker')]
        [string[]]$Component
    )

    $selected = @($Component | Sort-Object -Unique)
    $key = $selected -join ','

    if ($script:ChangedFileCache['ImplementationIdentity'].ContainsKey($key))
    {
        return [string]$script:ChangedFileCache['ImplementationIdentity'][$key]
    }

    $material = @(
        foreach ($name in $selected)
        {
            $path = Join-Path $script:ChangedFileScriptRoot $script:ChangedFileImplementationFile[$name]

            if (Test-Path -LiteralPath $path -PathType Leaf)
            {
                '{0}={1}' -f $name, (Get-ChangedFileContentHash -LiteralPath $path)
            }
            else
            {
                '{0}=missing' -f $name
            }
        }
    )

    $identity = 'impl={0}' -f (Get-ChangedFileTextHash -Text ($material -join ';')).Substring(0, 16)
    $script:ChangedFileCache['ImplementationIdentity'][$key] = $identity

    return $identity
}

function Get-ChangedFileAnalyzerVersion
{
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    if ($null -eq $script:ChangedFileCache['AnalyzerVersion'])
    {
        $module = Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        $script:ChangedFileCache['AnalyzerVersion'] = if ($null -eq $module)
        {
            ''
        }
        else
        {
            $module.Version.ToString()
        }
    }

    return [string]$script:ChangedFileCache['AnalyzerVersion']
}

<#
    The identity of an external tool, resolved without running it. A read-only
    report has to be able to decide whether a receipt still describes the tool
    that is installed now, and it may not start a process to find out.

    The entry point is hashed rather than measured: a replacement of the same
    length with its timestamp preserved is otherwise indistinguishable. What the
    hash cannot reach is everything the entry point loads at run time - an npm
    wrapper is a few hundred bytes of shim over a dependency tree this identity
    does not see, and no supported interface exposes one that could be read.
#>
function Get-ChangedFileExecutableIdentity
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CommandName
    )

    if ([string]::IsNullOrWhiteSpace($CommandName))
    {
        return 'unconfigured'
    }

    if ($script:ChangedFileCache['ExecutableIdentity'].ContainsKey($CommandName))
    {
        return [string]$script:ChangedFileCache['ExecutableIdentity'][$CommandName]
    }

    $identity = $null
    $resolved = Get-Command -Name $CommandName -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $item = if ($null -eq $resolved)
    {
        $null
    }
    else
    {
        Get-Item -LiteralPath $resolved.Source -Force -ErrorAction SilentlyContinue
    }

    if ($null -eq $item)
    {
        $identity = "unresolved:$CommandName"
    }
    elseif ($item.Length -gt $script:ChangedFileMaxExecutableIdentityByte)
    {
        $identity = 'oversized:{0}|{1}|{2}' -f $resolved.Source, $item.Length, $item.LastWriteTimeUtc.Ticks
    }
    else
    {
        $identity = '{0}|{1}|sha256={2}' -f
            $resolved.Source,
            $item.Length,
            (Get-ChangedFileContentHash -LiteralPath $resolved.Source)
    }

    $script:ChangedFileCache['ExecutableIdentity'][$CommandName] = $identity
    return $identity
}

function Get-ChangedFileMarkdownConfig
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context
    )

    foreach ($name in $script:ChangedFileDeclarativeMarkdownConfig)
    {
        $candidate = Join-Path $Context.RepositoryRoot $name
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf))
        {
            continue
        }

        $null = Assert-ChangedFileRegularPath -LiteralPath $candidate `
            -RepositoryRoot $Context.RepositoryRoot -Field 'The markdown lint configuration'

        return [PSCustomObject]@{
            Name = $name
            FullPath = $candidate
            Sha256 = Get-ChangedFileContentHash -LiteralPath $candidate
        }
    }

    return $null
}

function Test-ChangedFileSupportedPath
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativePath
    )

    return $script:ChangedFileValidatorPlan.ContainsKey(
        [IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    )
}

function New-ChangedFilePlanCheck
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds an in-memory plan record and changes nothing.'
    )]
    param
    (
        [Parameter(Mandatory)]
        [ValidateSet('PowerShell.Parse', 'PowerShell.ScriptAnalyzer', 'Markdown.NativeStructure', 'Markdown.Lint')]
        [string]$Validator,

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string]$FailOnSeverity = 'Error',

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintPath = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintInterface = 'markdownlint-cli',

        [Parameter()]
        [AllowNull()]
        [PSCustomObject]$MarkdownConfig = $null
    )

    $workerIdentity = Get-ChangedFileImplementationIdentity -Component @('Common', 'Worker')
    $localIdentity = Get-ChangedFileImplementationIdentity -Component @('Common')

    switch ($Validator)
    {
        'PowerShell.Parse'
        {
            return @{
                Validator = $Validator
                Executable = 'worker:System.Management.Automation.Language.Parser'
                ConfigIdentity = "parser=ParseFile;mode=default;isolation=snapshot;$workerIdentity"
                ExpectedVersion = $PSVersionTable.PSVersion.ToString()
            }
        }

        'PowerShell.ScriptAnalyzer'
        {
            return @{
                Validator = $Validator
                Executable = 'worker:PSScriptAnalyzer'
                ConfigIdentity = "severity=Error,Warning;fail=$FailOnSeverity;settings=inline;customRules=none;$workerIdentity"
                ExpectedVersion = Get-ChangedFileAnalyzerVersion
            }
        }

        'Markdown.NativeStructure'
        {
            return @{
                Validator = $Validator
                Executable = 'in-process:markdown-native-structure'
                ConfigIdentity = "rules=MD047,CFV001,CFV002,CFV003;coverage=partial;$localIdentity"
                ExpectedVersion = $PSVersionTable.PSVersion.ToString()
            }
        }

        'Markdown.Lint'
        {
            $configIdentity = 'interface={0};config={1};{2}' -f $MarkdownLintInterface, $(
                if ($null -eq $MarkdownConfig) { 'none' } else { '{0}:{1}' -f $MarkdownConfig.Name, $MarkdownConfig.Sha256 }
            ), $localIdentity

            return @{
                Validator = $Validator
                Executable = Get-ChangedFileExecutableIdentity -CommandName $MarkdownLintPath
                ConfigIdentity = $configIdentity
                ExpectedVersion = ''
            }
        }
    }

    throw "Unsupported validator '$Validator'."
}

<#
    A deterministic identity for the checks one file is due, resolved from static
    facts only: the extension, the requested failure severity, the installed
    analyzer version, the linter binary's own content, the bytes of the
    declarative configuration, and the content of the shipped implementation that
    performs each check. A receipt records this identity, so any change to the
    plan - including a change to the checker itself - invalidates reuse instead
    of silently inheriting an old pass.

    Nothing here starts a process, because a read-only report resolves the same
    plan to decide whether a receipt is still current.
#>
function Resolve-ChangedFileValidationPlan
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativePath,

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string]$FailOnSeverity = 'Error',

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintPath = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintInterface = 'markdownlint-cli'
    )

    $extension = [IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    if (-not $script:ChangedFileValidatorPlan.ContainsKey($extension))
    {
        return [PSCustomObject]@{
            Validator = @()
            Check = @()
            PlanIdentity = ''
            MarkdownConfig = $null
        }
    }

    $markdownConfig = if ($extension -eq '.md')
    {
        Get-ChangedFileMarkdownConfig -Context $Context
    }
    else
    {
        $null
    }

    $check = @(
        foreach ($validator in $script:ChangedFileValidatorPlan[$extension])
        {
            New-ChangedFilePlanCheck `
                -Validator $validator `
                -FailOnSeverity $FailOnSeverity `
                -MarkdownLintPath $MarkdownLintPath `
                -MarkdownLintInterface $MarkdownLintInterface `
                -MarkdownConfig $markdownConfig
        }
    )

    $separator = [string][char]31
    $material = (
        $check | ForEach-Object -Process {
            @($_['Validator'], $_['Executable'], $_['ConfigIdentity'], $_['ExpectedVersion']) -join $separator
        }
    ) -join "`n"

    return [PSCustomObject]@{
        Validator = @($check | ForEach-Object -Process { $_['Validator'] })
        Check = $check
        PlanIdentity = Get-ChangedFileTextHash -Text $material
        MarkdownConfig = $markdownConfig
    }
}

function New-ChangedFileDiagnostic
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds an in-memory diagnostic record and changes nothing.'
    )]
    param
    (
        [Parameter()]
        [int]$Line = 0,

        [Parameter()]
        [int]$Column = 0,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RuleId,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    $text = ([string]$Message) -replace '[\p{Cc}]', ' '
    if ($text.Length -gt $script:ChangedFileMaxMessageLength)
    {
        $text = $text.Substring(0, $script:ChangedFileMaxMessageLength) + '...'
    }

    return @{
        line = $Line
        column = $Column
        severity = $Severity
        ruleId = $RuleId
        message = $text
    }
}

function New-ChangedFileCheck
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds an in-memory check record and changes nothing.'
    )]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Validator,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Executable,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Version,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigIdentity,

        [Parameter(Mandatory)]
        [ValidateSet('Passed', 'Failed', 'Unavailable', 'TimedOut')]
        [string]$Outcome,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Reason = '',

        [Parameter()]
        [AllowNull()]
        [object]$ExitStatus = $null,

        [Parameter()]
        [AllowEmptyCollection()]
        [hashtable[]]$Diagnostic = @()
    )

    $all = @($Diagnostic)
    $kept = @($all | Select-Object -First $script:ChangedFileMaxDiagnostic)

    return @{
        validator = $Validator
        executable = $Executable
        version = $Version
        configIdentity = $ConfigIdentity
        outcome = $Outcome
        reason = $Reason
        exitStatus = $ExitStatus
        diagnosticCount = $all.Count
        truncated = $all.Count -gt $kept.Count
        diagnostics = $kept
    }
}

<#
    Runs one child process with an explicit argument vector, a wall-clock bound,
    and output that is drained and capped while the child is still running.

    Draining matters as much as the cap. Reading a pipe only after the child
    exits lets a talkative or hostile tool grow the retained buffer without limit
    and can deadlock when one stream fills while the other is being read, so both
    streams are read concurrently in fixed-size chunks and only the first
    MaxOutputCharacter characters of each are kept.

    Nothing here claims success it cannot prove. A child that fails to start, one
    that outruns the bound, and one whose descendants hold the pipe open past the
    drain grace are reported as unavailable, timed out, or incomplete, with the
    exit status left null when it is genuinely unknown.
#>
function Invoke-ChangedFileExternalTool
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter',
        'MaxOutputCharacter',
        Justification = 'Read by the draining scriptblock, which the analyzer does not follow.'
    )]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Argument,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int]$TimeoutSecond = 60,

        [Parameter()]
        [ValidateRange(256, 1000000)]
        [int]$MaxOutputCharacter = $script:ChangedFileMaxOutputCharacter,

        [Parameter()]
        [AllowEmptyString()]
        [string]$WorkingDirectory = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$StandardInputText = $null,

        [Parameter()]
        [ValidateRange(100, 60000)]
        [int]$OutputDrainMillisecond = 5000
    )

    $unavailable = {
        param ($Reason)

        [PSCustomObject]@{
            Outcome = 'Unavailable'
            Reason = $Reason
            ExitCode = $null
            ProcessId = $null
            StandardOutput = ''
            StandardError = ''
            TotalOutputCharacter = 0
            OutputComplete = $false
            Truncated = $false
            DurationMillisecond = 0
        }
    }

    $resolved = Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $resolved)
    {
        return & $unavailable 'ExecutableNotFound'
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $resolved.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $null -ne $StandardInputText

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory))
    {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    if (@($startInfo.PSObject.Properties.Name) -contains 'ArgumentList')
    {
        foreach ($value in $Argument)
        {
            $startInfo.ArgumentList.Add($value)
        }
    }
    else
    {
        try
        {
            $startInfo.Arguments = ConvertTo-ChangedFileCommandLine -Argument $Argument
        }
        catch
        {
            return & $unavailable 'ArgumentNotRepresentable'
        }
    }

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    try
    {
        try
        {
            $null = $process.Start()
        }
        catch
        {
            Write-Verbose -Message "The changed-file validator child could not start: $($_.Exception.Message)"
            return & $unavailable 'StartFailed'
        }

        $processId = $process.Id

        if ($null -ne $StandardInputText)
        {
            try
            {
                $process.StandardInput.Write($StandardInputText)
                $process.StandardInput.Close()
            }
            catch
            {
                Write-Verbose -Message "The changed-file validator child closed its input early: $($_.Exception.Message)"
            }
        }

        $state = @{
            OutReader = $process.StandardOutput
            ErrReader = $process.StandardError
            OutBuffer = [char[]]::new(4096)
            ErrBuffer = [char[]]::new(4096)
            OutBuilder = [Text.StringBuilder]::new()
            ErrBuilder = [Text.StringBuilder]::new()
            OutTotal = 0
            ErrTotal = 0
            OutDone = $false
            ErrDone = $false
            OutTask = $null
            ErrTask = $null
        }

        foreach ($stream in @('Out', 'Err'))
        {
            $state["${stream}Task"] = $state["${stream}Reader"].ReadAsync(
                $state["${stream}Buffer"], 0, $state["${stream}Buffer"].Length
            )
        }

        $consume = {
            param ($Deadline)

            $exitGrace = $null

            while (-not ($state['OutDone'] -and $state['ErrDone']))
            {
                if ([datetime]::UtcNow -ge $Deadline)
                {
                    return 'Deadline'
                }

                # A descendant can inherit the pipe and hold it open long after
                # the child this function owns has gone. Reading to end would
                # then block on a process nobody is bounding.
                if ($process.HasExited)
                {
                    if ($null -eq $exitGrace)
                    {
                        $exitGrace = [datetime]::UtcNow.AddMilliseconds($OutputDrainMillisecond)
                    }
                    elseif ([datetime]::UtcNow -ge $exitGrace)
                    {
                        return 'ExitGrace'
                    }
                }

                $pending = [Collections.Generic.List[Threading.Tasks.Task]]::new()
                if (-not $state['OutDone']) { $pending.Add($state['OutTask']) }
                if (-not $state['ErrDone']) { $pending.Add($state['ErrTask']) }
                $null = [Threading.Tasks.Task]::WaitAny($pending.ToArray(), 100)

                foreach ($stream in @('Out', 'Err'))
                {
                    $task = $state["${stream}Task"]
                    if ($state["${stream}Done"] -or -not $task.IsCompleted)
                    {
                        continue
                    }

                    if ($task.IsFaulted -or $task.IsCanceled)
                    {
                        $state["${stream}Done"] = $true
                        continue
                    }

                    $count = $task.Result
                    if ($count -le 0)
                    {
                        $state["${stream}Done"] = $true
                        continue
                    }

                    $state["${stream}Total"] = $state["${stream}Total"] + $count

                    $builder = $state["${stream}Builder"]
                    if ($builder.Length -lt $MaxOutputCharacter)
                    {
                        $take = [Math]::Min($count, $MaxOutputCharacter - $builder.Length)
                        $null = $builder.Append($state["${stream}Buffer"], 0, $take)
                    }

                    $state["${stream}Task"] = $state["${stream}Reader"].ReadAsync(
                        $state["${stream}Buffer"], 0, $state["${stream}Buffer"].Length
                    )
                }
            }

            return 'Complete'
        }

        $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSecond)
        $status = & $consume $deadline
        $timedOut = $status -eq 'Deadline'

        if ($status -eq 'Complete')
        {
            $remaining = [int] [Math]::Max(0, ($deadline - [datetime]::UtcNow).TotalMilliseconds)
            if (-not $process.WaitForExit($remaining))
            {
                $timedOut = $true
            }
        }

        if ($timedOut)
        {
            # Only the child this function started is stopped, together with the
            # descendants it spawned. Nothing else on the machine is touched.
            try
            {
                $process.Kill($true)
            }
            catch
            {
                try
                {
                    $process.Kill()
                }
                catch
                {
                    Write-Verbose -Message "The changed-file validator child could not be stopped: $($_.Exception.Message)"
                }
            }

            $null = $process.WaitForExit(5000)
            $null = & $consume ([datetime]::UtcNow.AddMilliseconds($OutputDrainMillisecond))
        }

        $stopwatch.Stop()

        $outputComplete = $state['OutDone'] -and $state['ErrDone']
        $exitCode = if ($process.HasExited) { $process.ExitCode } else { $null }

        $reason = if ($timedOut)
        {
            'TimeBoundExceeded'
        }
        elseif (-not $outputComplete)
        {
            'OutputIncomplete'
        }
        else
        {
            ''
        }

        return [PSCustomObject]@{
            Outcome = if ($timedOut) { 'TimedOut' } else { 'Completed' }
            Reason = $reason
            ExitCode = $exitCode
            ProcessId = $processId
            StandardOutput = $state['OutBuilder'].ToString()
            StandardError = $state['ErrBuilder'].ToString()
            TotalOutputCharacter = $state['OutTotal'] + $state['ErrTotal']
            OutputComplete = $outputComplete
            Truncated = ($state['OutTotal'] -gt $state['OutBuilder'].Length) -or
                ($state['ErrTotal'] -gt $state['ErrBuilder'].Length)
            DurationMillisecond = [int]$stopwatch.Elapsed.TotalMilliseconds
        }
    }
    finally
    {
        $process.Dispose()
    }
}

function New-ChangedFilePlannedCheck
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds an in-memory check record and changes nothing.'
    )]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plan,

        [Parameter(Mandatory)]
        [ValidateSet('Passed', 'Failed', 'Unavailable', 'TimedOut')]
        [string]$Outcome,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Reason = '',

        [Parameter()]
        [AllowNull()]
        [object]$ExitStatus = $null,

        [Parameter()]
        [AllowEmptyCollection()]
        [hashtable[]]$Diagnostic = @(),

        # Typed [object] on purpose: a [string] parameter coerces $null to an
        # empty string, which would silently replace the planned version.
        [Parameter()]
        [AllowNull()]
        [object]$Version = $null
    )

    $recorded = if ($null -eq $Version) { [string]$Plan['ExpectedVersion'] } else { [string]$Version }

    return New-ChangedFileCheck `
        -Validator $Plan['Validator'] `
        -Executable $Plan['Executable'] `
        -Version $recorded `
        -ConfigIdentity $Plan['ConfigIdentity'] `
        -Outcome $Outcome `
        -Reason $Reason `
        -ExitStatus $ExitStatus `
        -Diagnostic $Diagnostic
}

<#
    Runs the PowerShell checks in an owned child process with a wall-clock bound.

    Parsing and static analysis are cheap until they are not: a pathological file
    or a wedged analyzer run in-process has no wall clock at all and takes the
    session with it. The worker is therefore a separate process this function
    owns, started with an explicit argument vector, handed its request over
    standard input rather than a command line, pointed at an isolated snapshot
    directory, and killed with its descendants when it outruns the bound. It
    never dot-sources, imports, or otherwise executes the file it checks, and it
    never loads project analyzer settings or custom rules.

    WorkerScriptPath exists so a test can substitute a worker that never
    finishes. No entry-point script exposes it.
#>
function Invoke-ChangedFilePowerShellCheck
{
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string]$FailOnSeverity = 'Error',

        [Parameter()]
        [ValidateRange(1, 600)]
        [int]$TimeoutSecond = 60,

        [Parameter()]
        [AllowEmptyString()]
        [string]$WorkerScriptPath = ''
    )

    $parsePlan = New-ChangedFilePlanCheck -Validator 'PowerShell.Parse'
    $analyzerPlan = New-ChangedFilePlanCheck -Validator 'PowerShell.ScriptAnalyzer' -FailOnSeverity $FailOnSeverity

    $unusable = {
        param ($Outcome, $Reason)

        @(
            New-ChangedFilePlannedCheck -Plan $parsePlan -Outcome $Outcome -Reason $Reason
            New-ChangedFilePlannedCheck -Plan $analyzerPlan -Outcome $Outcome -Reason $Reason
        )
    }

    $worker = if ([string]::IsNullOrWhiteSpace($WorkerScriptPath))
    {
        Join-Path $script:ChangedFileScriptRoot $script:ChangedFileWorkerFileName
    }
    else
    {
        $WorkerScriptPath
    }

    if (-not (Test-Path -LiteralPath $worker -PathType Leaf))
    {
        return & $unusable 'Unavailable' 'WorkerMissing'
    }

    try
    {
        $hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    catch
    {
        Write-Verbose -Message "The changed-file worker host could not be resolved: $($_.Exception.Message)"
        return & $unusable 'Unavailable' 'HostUnsupported'
    }

    $argument = [Collections.Generic.List[string]]::new()
    $argument.Add('-NoProfile')
    $argument.Add('-NonInteractive')
    $argument.Add('-NoLogo')

    if ($env:OS -eq 'Windows_NT')
    {
        # Applies to the shipped worker in this child only; the caller's policy
        # is untouched.
        $argument.Add('-ExecutionPolicy')
        $argument.Add('Bypass')
    }

    $argument.Add('-File')
    $argument.Add($worker)

    $request = @{
        fileName = $FileName
        failOnSeverity = $FailOnSeverity
        maxDiagnostic = $script:ChangedFileMaxDiagnostic
    } | ConvertTo-Json -Compress

    $run = Invoke-ChangedFileExternalTool `
        -FilePath $hostExecutable `
        -Argument $argument.ToArray() `
        -TimeoutSecond $TimeoutSecond `
        -WorkingDirectory $WorkingDirectory `
        -StandardInputText $request

    if ($run.Outcome -eq 'TimedOut')
    {
        return & $unusable 'TimedOut' 'TimeBoundExceeded'
    }

    if ($run.Outcome -eq 'Unavailable')
    {
        return & $unusable 'Unavailable' $run.Reason
    }

    if (-not $run.OutputComplete -or $null -eq $run.ExitCode)
    {
        return & $unusable 'Unavailable' 'OutputIncomplete'
    }

    if ($run.ExitCode -ne 0)
    {
        return & $unusable 'Unavailable' 'WorkerFailed'
    }

    try
    {
        $report = $run.StandardOutput | ConvertFrom-Json -ErrorAction Stop
    }
    catch
    {
        return & $unusable 'Unavailable' 'WorkerReportUnreadable'
    }

    $toDiagnostic = {
        param ($Item)

        @(
            foreach ($entry in @($Item))
            {
                New-ChangedFileDiagnostic `
                    -Line ([int]$entry.line) `
                    -Column ([int]$entry.column) `
                    -Severity ([string]$entry.severity) `
                    -RuleId ([string]$entry.ruleId) `
                    -Message ([string]$entry.message)
            }
        )
    }

    $parseCheck = New-ChangedFilePlannedCheck `
        -Plan $parsePlan `
        -Outcome $(if ([int]$report.parse.errorCount -gt 0) { 'Failed' } else { 'Passed' }) `
        -ExitStatus ([int]$report.parse.errorCount) `
        -Diagnostic (& $toDiagnostic $report.parse.diagnostics)

    $analyzerCheck = if (-not $report.analyzer.available)
    {
        New-ChangedFilePlannedCheck -Plan $analyzerPlan -Outcome 'Unavailable' `
            -Reason ([string]$report.analyzer.reason) -Version ([string]$report.analyzer.version)
    }
    else
    {
        New-ChangedFilePlannedCheck `
            -Plan $analyzerPlan `
            -Outcome $(if ([int]$report.analyzer.failingCount -gt 0) { 'Failed' } else { 'Passed' }) `
            -ExitStatus ([int]$report.analyzer.failingCount) `
            -Diagnostic (& $toDiagnostic $report.analyzer.diagnostics) `
            -Version ([string]$report.analyzer.version)
    }

    return @($parseCheck, $analyzerCheck)
}

<#
    Four structural rules that need no toolchain: MD047, plus unterminated
    frontmatter, an unterminated fence, and invalid UTF-8 or a stray control
    character.

    This is deliberately not a markdownlint substitute and must never be
    presented as one. The repository configuration never sets `default: false`,
    so most markdownlint rules remain active and are not covered here. The check
    is recorded with `coverage=partial`, and a markdown file is verified only
    when Markdown.Lint has also passed.
#>
function Invoke-ChangedFileMarkdownStructure
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plan,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FullPath
    )

    $bytes = [IO.File]::ReadAllBytes($FullPath)

    try
    {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    }
    catch
    {
        return New-ChangedFilePlannedCheck `
            -Plan $Plan `
            -Outcome 'Failed' `
            -ExitStatus 1 `
            -Diagnostic @(
                New-ChangedFileDiagnostic -Line 1 -Severity 'Error' -RuleId 'CFV003' `
                    -Message 'The file is not valid UTF-8 text.'
            )
    }

    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF)
    {
        $text = $text.Substring(1)
    }

    $normalized = $text -replace "`r`n", "`n"
    $line = $normalized -split "`n"
    $diagnostic = [Collections.Generic.List[hashtable]]::new()

    if ($normalized.Length -eq 0 -or -not $normalized.EndsWith("`n") -or $normalized.EndsWith("`n`n"))
    {
        $diagnostic.Add((
            New-ChangedFileDiagnostic -Line $line.Count -Severity 'Error' -RuleId 'MD047' `
                -Message 'Files should end with a single newline character.'
        ))
    }

    if ($line.Count -gt 0 -and $line[0] -eq '---')
    {
        $closing = -1
        for ($index = 1; $index -lt $line.Count; $index++)
        {
            if ($line[$index] -eq '---')
            {
                $closing = $index
                break
            }
        }

        if ($closing -lt 0)
        {
            $diagnostic.Add((
                New-ChangedFileDiagnostic -Line 1 -Severity 'Error' -RuleId 'CFV001' `
                    -Message 'The frontmatter block opened on line 1 is never closed.'
            ))
        }
    }

    $openFenceLine = 0
    $openFenceMarker = ''
    for ($index = 0; $index -lt $line.Count; $index++)
    {
        if ($line[$index] -notmatch '^\s{0,3}(?<marker>`{3,}|~{3,})')
        {
            continue
        }

        $marker = $Matches['marker'].Substring(0, 3)
        if ($openFenceLine -eq 0)
        {
            $openFenceLine = $index + 1
            $openFenceMarker = $marker
        }
        elseif ($marker -eq $openFenceMarker)
        {
            $openFenceLine = 0
            $openFenceMarker = ''
        }
    }

    if ($openFenceLine -gt 0)
    {
        $diagnostic.Add((
            New-ChangedFileDiagnostic -Line $openFenceLine -Severity 'Error' -RuleId 'CFV002' `
                -Message 'The fenced code block opened here is never closed.'
        ))
    }

    if ($normalized -match '[\x00-\x08\x0B\x0C\x0E-\x1F]')
    {
        $diagnostic.Add((
            New-ChangedFileDiagnostic -Severity 'Error' -RuleId 'CFV003' `
                -Message 'The file carries a control character that is not a tab or a newline.'
        ))
    }

    return New-ChangedFilePlannedCheck `
        -Plan $Plan `
        -Outcome $(if ($diagnostic.Count -gt 0) { 'Failed' } else { 'Passed' }) `
        -ExitStatus $diagnostic.Count `
        -Diagnostic $diagnostic.ToArray()
}

<#
    Walks from the directory holding the file up to the selected project root and
    refuses any markdownlint configuration file that can load or reference code.
    This covers discovery by file name only; what the chosen declarative
    configuration actually contains is decided by parsing it, not by reading it
    as text.
#>
function Test-ChangedFileExecutableMarkdownConfig
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FullPath
    )

    $current = Get-ChangedFileFullPath -LiteralPath (Split-Path -Parent $FullPath)
    $root = $Context.RepositoryRoot

    while ($true)
    {
        foreach ($name in $script:ChangedFileExecutableMarkdownConfig)
        {
            if (Test-Path -LiteralPath (Join-Path $current $name) -PathType Leaf)
            {
                return $true
            }
        }

        if (Test-ChangedFilePathEqual -Left $current -Right $root)
        {
            break
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent))
        {
            break
        }

        $current = Get-ChangedFileFullPath -LiteralPath $parent
    }

    return $false
}

function Test-ChangedFileJsonReaderAvailable
{
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    if ($null -eq $script:ChangedFileCache['JsonReaderAvailable'])
    {
        $available = $false

        try
        {
            $null = [System.Text.Json.JsonDocument]
            $available = $true
        }
        catch
        {
            Write-Verbose -Message "A comment-tolerant JSON reader is not available on this host: $($_.Exception.Message)"
        }

        $script:ChangedFileCache['JsonReaderAvailable'] = $available
    }

    return [bool]$script:ChangedFileCache['JsonReaderAvailable']
}

<#
    Reads JSONC through a real reader and writes back plain JSON: comments and
    trailing commas are dropped, and every escape in a key is resolved, so what
    the schema check sees is what the document actually says rather than how it
    was spelled. Nothing is evaluated - the reader builds a document and this
    writes it out again.
#>
function ConvertTo-ChangedFileCanonicalJson
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $options = [System.Text.Json.JsonDocumentOptions]@{
        CommentHandling = 'Skip'
        AllowTrailingCommas = $true
        MaxDepth = $script:ChangedFileMaxConfigDepth + 2
    }

    $document = [System.Text.Json.JsonDocument]::Parse($Text, $options)

    try
    {
        $stream = [IO.MemoryStream]::new()

        try
        {
            $writer = [System.Text.Json.Utf8JsonWriter]::new($stream)

            try
            {
                $document.RootElement.WriteTo($writer)
                $writer.Flush()
                return [Text.UTF8Encoding]::new($false).GetString($stream.ToArray())
            }
            finally
            {
                $writer.Dispose()
            }
        }
        finally
        {
            $stream.Dispose()
        }
    }
    finally
    {
        $document.Dispose()
    }
}

<#
    Decides whether a parsed configuration is a plain markdownlint rule map.

    The walk is breadth-first and bounded, and it refuses on the first thing it
    cannot vouch for: a key that can pull in code or another document, a key that
    is not a rule identifier, alias, or ordinary parameter name, a value that is
    not a scalar or a nested map, and a document deeper or larger than a rule map
    has any reason to be.
#>
function Test-ChangedFileMarkdownConfigShape
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Document
    )

    $verdict = {
        param ($Safe, $Reason)

        [PSCustomObject]@{ Safe = $Safe; Reason = $Reason }
    }

    if ($Document -isnot [PSCustomObject])
    {
        return & $verdict $false 'ConfigurationShapeUnsupported'
    }

    $pending = [Collections.Generic.Queue[PSCustomObject]]::new()
    $pending.Enqueue([PSCustomObject]@{ Node = $Document; Depth = 0 })
    $visited = 0

    while ($pending.Count -gt 0)
    {
        $item = $pending.Dequeue()
        $visited++

        if ($visited -gt $script:ChangedFileMaxConfigNode -or $item.Depth -gt $script:ChangedFileMaxConfigDepth)
        {
            return & $verdict $false 'ConfigurationShapeUnsupported'
        }

        foreach ($property in $item.Node.PSObject.Properties)
        {
            $name = [string]$property.Name

            if ($script:ChangedFileForbiddenConfigKey -contains $name.ToLowerInvariant())
            {
                return & $verdict $false 'ExecutableConfigurationPresent'
            }

            $pattern = if ($item.Depth -eq 0)
            {
                $script:ChangedFileRootConfigKeyPattern
            }
            else
            {
                $script:ChangedFileConfigKeyPattern
            }

            if ($name -cnotmatch $pattern)
            {
                return & $verdict $false 'ConfigurationShapeUnsupported'
            }

            foreach ($element in @($property.Value))
            {
                if ($element -is [PSCustomObject])
                {
                    $pending.Enqueue([PSCustomObject]@{ Node = $element; Depth = $item.Depth + 1 })
                    continue
                }

                if ($null -ne $element -and
                    $element -isnot [bool] -and
                    $element -isnot [string] -and
                    -not $element.GetType().IsPrimitive -and
                    $element -isnot [decimal])
                {
                    return & $verdict $false 'ConfigurationShapeUnsupported'
                }
            }
        }
    }

    return & $verdict $true ''
}

<#
    Decides whether a declarative markdown lint configuration may be handed to a
    linter, by parsing it rather than by scanning its bytes.

    A text scan is not a boundary. JSON can spell `extends` with Unicode escapes,
    and a format this workflow has no trusted parser for cannot be judged at all,
    so it is reported unavailable instead of copied to an executable unread.
#>
function Test-ChangedFileMarkdownConfigSafe
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    $verdict = {
        param ($Safe, $Reason)

        [PSCustomObject]@{ Safe = $Safe; Reason = $Reason }
    }

    $extension = [IO.Path]::GetExtension($LiteralPath).ToLowerInvariant()
    if ($script:ChangedFileParsableMarkdownConfig -notcontains $extension)
    {
        return & $verdict $false 'ConfigurationFormatUnsupported'
    }

    try
    {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($LiteralPath))
    }
    catch
    {
        Write-Verbose -Message "The markdown lint configuration could not be read as UTF-8: $($_.Exception.Message)"
        return & $verdict $false 'ConfigurationUnreadable'
    }

    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF)
    {
        $text = $text.Substring(1)
    }

    $canonical = $text
    if ($extension -eq '.jsonc')
    {
        if (-not (Test-ChangedFileJsonReaderAvailable))
        {
            return & $verdict $false 'ConfigurationFormatUnsupported'
        }

        try
        {
            $canonical = ConvertTo-ChangedFileCanonicalJson -Text $text
        }
        catch
        {
            Write-Verbose -Message "The markdown lint configuration is not valid JSONC: $($_.Exception.Message)"
            return & $verdict $false 'ConfigurationUnreadable'
        }
    }

    try
    {
        $document = $canonical | ConvertFrom-Json -ErrorAction Stop
    }
    catch
    {
        Write-Verbose -Message "The markdown lint configuration is not valid JSON: $($_.Exception.Message)"
        return & $verdict $false 'ConfigurationUnreadable'
    }

    return Test-ChangedFileMarkdownConfigShape -Document $document
}

function Get-ChangedFileMarkdownLintVersion
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MarkdownLintPath,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int]$TimeoutSecond = 30
    )

    if ($script:ChangedFileCache['LinterVersion'].ContainsKey($MarkdownLintPath))
    {
        return [string]$script:ChangedFileCache['LinterVersion'][$MarkdownLintPath]
    }

    $probe = Invoke-ChangedFileExternalTool `
        -FilePath $MarkdownLintPath `
        -Argument @('--version') `
        -TimeoutSecond ([Math]::Min($TimeoutSecond, 30))

    $version = ''
    if ($probe.Outcome -eq 'Completed' -and $probe.ExitCode -eq 0 -and $probe.OutputComplete)
    {
        $match = [regex]::Match($probe.StandardOutput.Trim(), '^\d+\.\d+\.\d+')
        if ($match.Success)
        {
            $version = $match.Value
        }
    }

    $script:ChangedFileCache['LinterVersion'][$MarkdownLintPath] = $version
    return $version
}

<#
    Runs a real markdownlint through one verified interface against an isolated
    snapshot, or reports the check unavailable.

    Every argument is a name this workflow generated and the working directory is
    the snapshot directory, so a hostile project file name, a glob, or a shell
    metacharacter never reaches a command line, which matters on Windows, where
    the shipped markdownlint entry point is a `.cmd` shim the command processor
    re-parses. The declarative configuration is copied in beside the snapshot,
    parsed and schema-checked as the exact bytes the linter would read, and
    passed explicitly, which is also what disables the linter's own nested and
    ancestor configuration discovery.

    There is no fallback. An interface this implementation has not verified, a
    missing binary, a configuration that can load code or that no trusted parser
    covers, and a version probe that does not answer are all Unavailable, and the
    entry stays unverified.
#>
function Invoke-ChangedFileMarkdownLint
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plan,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Snapshot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceFullPath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintPath = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintInterface = 'markdownlint-cli',

        [Parameter()]
        [AllowNull()]
        [PSCustomObject]$MarkdownConfig = $null,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int]$TimeoutSecond = 60
    )

    $unavailable = {
        param ($Reason)

        New-ChangedFilePlannedCheck -Plan $Plan -Outcome 'Unavailable' -Reason $Reason
    }

    if ($script:ChangedFileMarkdownLintInterface -notcontains $MarkdownLintInterface)
    {
        return & $unavailable 'UnsupportedInterface'
    }

    if ([string]::IsNullOrWhiteSpace($MarkdownLintPath))
    {
        return & $unavailable 'LinterNotConfigured'
    }

    $resolved = Get-Command -Name $MarkdownLintPath -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $resolved)
    {
        return & $unavailable 'ExecutableNotFound'
    }

    if (Test-ChangedFileExecutableMarkdownConfig -Context $Context -FullPath $SourceFullPath)
    {
        return & $unavailable 'ExecutableConfigurationPresent'
    }

    if ($null -eq $MarkdownConfig -or [string]::IsNullOrEmpty($Snapshot.ConfigFileName))
    {
        return & $unavailable 'NoDeclarativeConfiguration'
    }

    # The copy beside the snapshot is what the linter would be handed, so that is
    # the document that has to survive parsing and the schema before it can be.
    $configVerdict = Test-ChangedFileMarkdownConfigSafe -LiteralPath (
        Join-Path $Snapshot.Directory $Snapshot.ConfigFileName
    )

    if (-not $configVerdict.Safe)
    {
        return & $unavailable $configVerdict.Reason
    }

    $version = Get-ChangedFileMarkdownLintVersion -MarkdownLintPath $MarkdownLintPath -TimeoutSecond $TimeoutSecond
    if ([string]::IsNullOrEmpty($version))
    {
        return & $unavailable 'InterfaceNotVerified'
    }

    $run = Invoke-ChangedFileExternalTool `
        -FilePath $MarkdownLintPath `
        -Argument @('--config', $Snapshot.ConfigFileName, $Snapshot.FileName) `
        -TimeoutSecond $TimeoutSecond `
        -WorkingDirectory $Snapshot.Directory

    if ($run.Outcome -eq 'TimedOut')
    {
        return New-ChangedFilePlannedCheck -Plan $Plan -Outcome 'TimedOut' `
            -Reason 'TimeBoundExceeded' -Version $version
    }

    if ($run.Outcome -eq 'Unavailable')
    {
        return New-ChangedFilePlannedCheck -Plan $Plan -Outcome 'Unavailable' `
            -Reason $run.Reason -Version $version
    }

    if (-not $run.OutputComplete -or $null -eq $run.ExitCode)
    {
        return New-ChangedFilePlannedCheck -Plan $Plan -Outcome 'Unavailable' `
            -Reason 'OutputIncomplete' -Version $version
    }

    if ($run.ExitCode -gt 1 -or $run.ExitCode -lt 0)
    {
        return New-ChangedFilePlannedCheck -Plan $Plan -Outcome 'Unavailable' `
            -Reason 'InvocationFailed' -Version $version
    }

    $reported = @(
        ($run.StandardOutput + "`n" + $run.StandardError) -split "`r?`n" |
            Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $diagnostic = @(
        foreach ($line in $reported)
        {
            $match = [regex]::Match(
                $line,
                '^(?<path>.+?):(?<line>\d+)(?::(?<column>\d+))?\s+(?<rule>MD\d{3})(?:/(?<alias>\S+))?\s*(?<message>.*)$'
            )

            if ($match.Success)
            {
                New-ChangedFileDiagnostic `
                    -Line ([int]$match.Groups['line'].Value) `
                    -Column $(if ($match.Groups['column'].Success) { [int]$match.Groups['column'].Value } else { 0 }) `
                    -Severity 'Error' `
                    -RuleId $match.Groups['rule'].Value `
                    -Message $match.Groups['message'].Value
            }
            else
            {
                New-ChangedFileDiagnostic -Severity 'Error' -RuleId 'MarkdownLint' -Message $line
            }
        }
    )

    return New-ChangedFilePlannedCheck `
        -Plan $Plan `
        -Outcome $(if ($run.ExitCode -eq 0) { 'Passed' } else { 'Failed' }) `
        -ExitStatus $run.ExitCode `
        -Diagnostic $diagnostic `
        -Version $version
}

function Get-ChangedFileWorstOutcome
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Outcome
    )

    # An outcome this implementation cannot produce is not evidence of anything,
    # so it degrades the batch instead of being ignored on the way to a pass.
    foreach ($candidate in @($Outcome))
    {
        if ($script:ChangedFileCheckOutcome -notcontains $candidate)
        {
            return 'Unavailable'
        }
    }

    foreach ($candidate in @('Failed', 'TimedOut', 'Unavailable'))
    {
        if ($Outcome -contains $candidate)
        {
            return $candidate
        }
    }

    if (@($Outcome).Count -eq 0)
    {
        return 'Unavailable'
    }

    return 'Passed'
}

<#
    Decides what a stored receipt still proves, and fails closed whenever it
    cannot decide.

    A receipt is only reusable when all of it holds: the shape is intact and
    typed as this implementation writes it, the hash matches the bytes on disk
    now, nothing moved underneath the run that produced it, the validation plan
    is identical, the recorded checks are exactly the planned ones - each once,
    with the identity the plan expects and an exit status consistent with its
    result - and the recorded outcome is what those checks add up to.

    A hand-edited receipt, an emptied check list, an invented result, a duplicated
    or extra check, a replaced linter, an edited checker, and a changed failure
    severity all fall out of this rule rather than needing a rule of their own.
#>
function Test-ChangedFileReceipt
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Receipt,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Plan,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CurrentSha256
    )

    $verdict = {
        param ($State, $Reason, $IsCurrent, $Outcome)

        [PSCustomObject]@{
            State = $State
            Reason = $Reason
            IsCurrent = $IsCurrent
            Outcome = $Outcome
        }
    }

    if ($Receipt -isnot [Collections.IDictionary])
    {
        return & $verdict 'Pending' '' $false $null
    }

    foreach ($key in @('contentSha256', 'completedUtc', 'outcome', 'checks', 'planIdentity', 'contentChangedDuringValidation'))
    {
        if (-not $Receipt.Contains($key))
        {
            return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
        }
    }

    $receiptHash = [string]$Receipt['contentSha256']
    if ($receiptHash -notmatch $script:ChangedFileSha256Pattern)
    {
        return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
    }

    $stored = $Receipt['checks']
    if ($null -eq $stored -or $stored -is [string] -or $stored -isnot [Collections.IEnumerable])
    {
        return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
    }

    $check = @($stored)
    foreach ($item in $check)
    {
        if ($item -isnot [Collections.IDictionary])
        {
            return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
        }

        foreach ($key in @('validator', 'executable', 'version', 'configIdentity', 'outcome', 'exitStatus'))
        {
            if (-not $item.Contains($key))
            {
                return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$item['validator']) -or
            $script:ChangedFileCheckOutcome -notcontains [string]$item['outcome'])
        {
            return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
        }
    }

    # A Boolean by type, not by coercion: a stored zero or an empty string would
    # otherwise read as "nothing moved" and reopen the window it was added to close.
    if ($Receipt['contentChangedDuringValidation'] -isnot [bool])
    {
        return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
    }

    if ($script:ChangedFileCheckOutcome -notcontains [string]$Receipt['outcome'])
    {
        return & $verdict 'Incomplete' 'ReceiptUnreadable' $false $null
    }

    foreach ($item in $check)
    {
        $exitStatus = $item['exitStatus']
        $known = $null -ne $exitStatus -and (
            $exitStatus -is [int] -or $exitStatus -is [long] -or
            $exitStatus -is [int16] -or $exitStatus -is [byte]
        )

        # Every check this implementation records as a result reports a count or
        # an exit code with it, and a pass is always zero. A pass without one, or
        # with a nonzero one, describes a run that did not happen as recorded.
        if ([string]$item['outcome'] -eq 'Passed' -and (-not $known -or [long]$exitStatus -ne 0))
        {
            return & $verdict 'Incomplete' 'ReceiptExitStatusMismatch' $false $null
        }

        if ([string]$item['outcome'] -eq 'Failed' -and (-not $known -or [long]$exitStatus -eq 0))
        {
            return & $verdict 'Incomplete' 'ReceiptExitStatusMismatch' $false $null
        }
    }

    if ($receiptHash -ne [string]$CurrentSha256)
    {
        return & $verdict 'Stale' 'ContentChanged' $false $null
    }

    if ([bool]$Receipt['contentChangedDuringValidation'])
    {
        return & $verdict 'Stale' 'ChangedDuringValidation' $false $null
    }

    if ([string]$Receipt['planIdentity'] -ne [string]$Plan.PlanIdentity)
    {
        return & $verdict 'PlanChanged' 'ValidationPlanChanged' $false $null
    }

    # Cardinality is part of the claim. A duplicate check and a check nobody
    # planned both mean the stored list is not the list the plan describes.
    $plannedName = @($Plan.Check | ForEach-Object -Process { [string]$_['Validator'] })
    $recordedName = @($check | ForEach-Object -Process { [string]$_['validator'] })

    if ($recordedName.Count -ne $plannedName.Count -or
        @($recordedName | Sort-Object -Unique).Count -ne $recordedName.Count -or
        @($recordedName | Where-Object -FilterScript { $plannedName -notcontains $_ }).Count -gt 0)
    {
        if (@($plannedName | Where-Object -FilterScript { $recordedName -notcontains $_ }).Count -gt 0)
        {
            return & $verdict 'Incomplete' 'RequiredCheckMissing' $false $null
        }

        return & $verdict 'Incomplete' 'UnexpectedCheckPresent' $false $null
    }

    foreach ($planned in $Plan.Check)
    {
        $recorded = $check |
            Where-Object -FilterScript { [string]$_['validator'] -eq [string]$planned['Validator'] } |
            Select-Object -First 1

        if ($null -eq $recorded)
        {
            return & $verdict 'Incomplete' 'RequiredCheckMissing' $false $null
        }

        if ([string]$recorded['executable'] -ne [string]$planned['Executable'] -or
            [string]$recorded['configIdentity'] -ne [string]$planned['ConfigIdentity'])
        {
            return & $verdict 'Incomplete' 'CheckIdentityChanged' $false $null
        }

        if (-not [string]::IsNullOrEmpty([string]$planned['ExpectedVersion']) -and
            [string]$recorded['version'] -ne [string]$planned['ExpectedVersion'])
        {
            return & $verdict 'Incomplete' 'CheckIdentityChanged' $false $null
        }
    }

    $recomputed = Get-ChangedFileWorstOutcome -Outcome @(
        $check | ForEach-Object -Process { [string]$_['outcome'] }
    )

    if ($recomputed -ne [string]$Receipt['outcome'])
    {
        return & $verdict 'Incomplete' 'ReceiptOutcomeMismatch' $false $null
    }

    $state = switch ($recomputed)
    {
        'Passed' { 'Verified' }
        'Failed' { 'Failed' }
        default { 'Incomplete' }
    }

    $reason = if ($state -eq 'Incomplete')
    {
        $first = $check |
            Where-Object -FilterScript { [string]$_['outcome'] -ne 'Passed' } |
            Select-Object -First 1

        if ($null -eq $first) { $recomputed } else { [string]$first['reason'] }
    }
    else
    {
        ''
    }

    return & $verdict $state $reason $true $recomputed
}

function Get-ChangedFileEntryReport
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Entry,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Action = '',

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string]$FailOnSeverity = 'Error',

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintPath = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$MarkdownLintInterface = 'markdownlint-cli',

        [Parameter()]
        [AllowNull()]
        [PSCustomObject]$Plan = $null,

        [Parameter()]
        [AllowNull()]
        [hashtable[]]$TransientCheck = $null,

        [Parameter()]
        [AllowEmptyString()]
        [string]$TransientState = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$TransientReason = ''
    )

    $relativePath = [string]$Entry['path']
    $fullPath = Join-Path $Context.RepositoryRoot (
        $relativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    )

    if ($null -eq $Plan)
    {
        $Plan = Resolve-ChangedFileValidationPlan `
            -Context $Context `
            -RelativePath $relativePath `
            -FailOnSeverity $FailOnSeverity `
            -MarkdownLintPath $MarkdownLintPath `
            -MarkdownLintInterface $MarkdownLintInterface
    }

    $supported = @($Plan.Validator).Count -gt 0
    $present = Test-Path -LiteralPath $fullPath -PathType Leaf
    $currentHash = if ($present) { Get-ChangedFileContentHash -LiteralPath $fullPath } else { $null }

    $receipt = if ($Entry.ContainsKey('receipt')) { $Entry['receipt'] } else { $null }
    $verdict = Test-ChangedFileReceipt -Receipt $receipt -Plan $Plan -CurrentSha256 $currentHash

    $source = if ($null -ne $TransientCheck)
    {
        , @($TransientCheck)
    }
    elseif ($receipt -is [Collections.IDictionary] -and $receipt.Contains('checks'))
    {
        , @($receipt['checks'])
    }
    else
    {
        , @()
    }

    $checks = @(
        foreach ($check in $source)
        {
            [PSCustomObject]@{
                Validator = [string]$check['validator']
                Executable = [string]$check['executable']
                Version = [string]$check['version']
                ConfigIdentity = [string]$check['configIdentity']
                Outcome = [string]$check['outcome']
                Reason = [string]$check['reason']
                ExitStatus = $check['exitStatus']
                DiagnosticCount = $check['diagnosticCount']
                Truncated = $check['truncated']
                Diagnostics = @(
                    foreach ($item in @($check['diagnostics']))
                    {
                        [PSCustomObject]@{
                            Line = $item['line']
                            Column = $item['column']
                            Severity = [string]$item['severity']
                            RuleId = [string]$item['ruleId']
                            Message = [string]$item['message']
                        }
                    }
                )
            }
        }
    )

    $receiptHash = if ($receipt -is [Collections.IDictionary] -and $receipt.Contains('contentSha256'))
    {
        [string]$receipt['contentSha256']
    }
    else
    {
        $null
    }

    $state = if (-not $supported)
    {
        'Unsupported'
    }
    elseif (-not $present)
    {
        'Missing'
    }
    elseif (-not [string]::IsNullOrEmpty($TransientState))
    {
        $TransientState
    }
    else
    {
        $verdict.State
    }

    $reason = if (-not [string]::IsNullOrEmpty($TransientState)) { $TransientReason } else { $verdict.Reason }

    return [PSCustomObject]@{
        SessionId = $SessionId
        RelativePath = $relativePath
        Occurrences = [int]$Entry['occurrences']
        AddedUtc = [string]$Entry['addedUtc']
        UpdatedUtc = [string]$Entry['updatedUtc']
        Supported = $supported
        Validators = @($Plan.Validator)
        PlanIdentity = [string]$Plan.PlanIdentity
        FileState = if ($present) { 'Present' } else { 'Missing' }
        ContentSha256 = $currentHash
        ReceiptSha256 = $receiptHash
        ValidationState = $state
        ValidationReason = $reason
        Verified = $state -eq 'Verified'
        Outcome = if ($receipt -is [Collections.IDictionary] -and $receipt.Contains('outcome')) { [string]$receipt['outcome'] } else { $null }
        ValidatedUtc = if ($receipt -is [Collections.IDictionary] -and $receipt.Contains('completedUtc')) { [string]$receipt['completedUtc'] } else { $null }
        Action = $Action
        Checks = $checks
    }
}

