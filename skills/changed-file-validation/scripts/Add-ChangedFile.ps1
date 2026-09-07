#Requires -Version 5.1

<#
    .SYNOPSIS
        Adds explicitly named changed files to one validation batch.

    .DESCRIPTION
        Collection is manual and opt-in. Nothing observes the editor, no hook is
        wired, and no file is read beyond the guard that proves it sits inside
        the selected project. Repeated adds of the same file collapse onto one
        entry and increment an occurrence count, so a batch stays one entry per
        file no matter how often it was edited.

        A path outside the selected project, a traversal segment, a drive
        qualifier, and any path reached through a symbolic link, junction, or
        other reparse point are refused before anything is recorded.

    .PARAMETER Path
        The selected project root. Every collected path must resolve inside it.

    .PARAMETER ChangedPath
        One or more changed files, absolute or project-relative.

    .PARAMETER SessionId
        The batch this collection belongs to. Sessions are isolated from each
        other; the identifier is letters, digits, period, underscore, and hyphen
        only, so it can never name a path.

    .OUTPUTS
        PSCustomObject

    .EXAMPLE
        ./Add-ChangedFile.ps1 -Path $PWD.Path -ChangedPath 'source/Public/Get-Thing.ps1'

        Records one changed file in the default batch.
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ChangedPath,

    [Parameter()]
    [AllowEmptyString()]
    [string]$SessionId = 'default'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ChangedFileValidationCommon.ps1')

$context = Resolve-ChangedFileContext -Path $Path
$session = Assert-ChangedFileSessionId -SessionId $SessionId

$requested = [Collections.Generic.List[string]]::new()
foreach ($candidate in $ChangedPath)
{
    $relative = Resolve-ChangedFileRelativePath -Context $context -InputPath $candidate
    if (-not $requested.Contains($relative))
    {
        $requested.Add($relative)
    }
}

$timestamp = [datetime]::UtcNow.ToString('o')
$lock = Enter-ChangedFileLock -Context $context
$recorded = [Collections.Generic.List[hashtable]]::new()

try
{
    # Re-read under the lock so a concurrent collector's entries are merged
    # rather than overwritten. A lost update silently drops a changed file.
    $store = Read-ChangedFileStore -Context $context
    if ($null -eq $store)
    {
        $store = New-ChangedFileStore -Context $context
    }

    if (-not $store['sessions'].ContainsKey($session))
    {
        $store['sessions'][$session] = @{
            sessionId = $session
            createdUtc = $timestamp
            updatedUtc = $timestamp
            entries = @()
        }
    }

    $entries = [Collections.Generic.List[hashtable]]::new()
    foreach ($entry in (Get-ChangedFileSessionEntry -Store $store -SessionId $session))
    {
        $entries.Add($entry)
    }

    foreach ($relative in $requested)
    {
        $existing = $entries | Where-Object { [string]$_['path'] -eq $relative } | Select-Object -First 1

        if ($null -eq $existing)
        {
            if ($entries.Count -ge $script:ChangedFileMaxEntryPerSession)
            {
                throw "Session '$session' already holds $script:ChangedFileMaxEntryPerSession changed files, which is the documented batch bound. Validate and clear the batch before collecting more."
            }

            $existing = @{
                path = $relative
                addedUtc = $timestamp
                updatedUtc = $timestamp
                occurrences = 0
                receipt = $null
            }

            $entries.Add($existing)
        }

        $existing['occurrences'] = [int]$existing['occurrences'] + 1
        $existing['updatedUtc'] = $timestamp
        $recorded.Add($existing)
    }

    $store['sessions'][$session]['entries'] = $entries.ToArray()
    $store['sessions'][$session]['updatedUtc'] = $timestamp

    Write-ChangedFileStore -Context $context -Store $store
}
finally
{
    Exit-ChangedFileLock -Handle $lock
}

foreach ($entry in $recorded)
{
    $relativePath = [string]$entry['path']
    $fullPath = Join-Path $context.RepositoryRoot (
        $relativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    )

    $state = if (-not (Test-ChangedFileSupportedPath -RelativePath $relativePath))
    {
        'Unsupported'
    }
    elseif (-not (Test-Path -LiteralPath $fullPath -PathType Leaf))
    {
        'Missing'
    }
    else
    {
        'Collected'
    }

    [PSCustomObject]@{
        SessionId = $session
        RelativePath = $relativePath
        State = $state
        Occurrences = [int]$entry['occurrences']
        AddedUtc = [string]$entry['addedUtc']
        UpdatedUtc = [string]$entry['updatedUtc']
        StorePath = $context.StoreRelativePath
    }
}
