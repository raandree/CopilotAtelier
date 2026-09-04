#Requires -Version 5.1

<#
.SYNOPSIS
    Applies a validated Memory Bank role-record migration plan by copying files.
.DESCRIPTION
    Validates the complete saved plan before writing, copies ready source files
    into career, legal, or tax namespaces without overwriting destinations,
    verifies SHA-256 after every copy, and never removes a source file.
.PARAMETER Path
    Existing repository directory that must match the plan repository root.
.PARAMETER PlanPath
    Saved role-record migration plan under .memory-bank/session.
.EXAMPLE
    ./Invoke-MemoryBankRoleMigration.ps1 -Path C:/Git/MyProject `
        -PlanPath C:/Git/MyProject/.memory-bank/session/role-record-migration-2026-09-04T100000Z.json `
        -WhatIf

    Validates and previews the complete migration without writing files.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[OutputType([PSCustomObject])]
param
(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path = (Get-Location).Path,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$PlanPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath
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

function Test-PathEqual
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

    $comparison = if ($env:OS -eq 'Windows_NT')
    {
        [StringComparison]::OrdinalIgnoreCase
    }
    else
    {
        [StringComparison]::Ordinal
    }
    return [string]::Equals($Left, $Right, $comparison)
}

function Test-ReparsePoint
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
    return [bool](
        $item.Attributes -band [IO.FileAttributes]::ReparsePoint
    )
}

function Get-LowerFileHash
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

function Get-RepositoryPath
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativePath
    )

    $platformPath = $RelativePath.Replace(
        '/',
        [IO.Path]::DirectorySeparatorChar
    )
    return Get-NormalizedFullPath -LiteralPath (
        Join-Path $RepositoryRoot $platformPath
    )
}

$repositoryItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
if (Test-ReparsePoint -LiteralPath $repositoryItem.FullName)
{
    throw "Repository root must not be a symbolic link, junction, or reparse point: '$($repositoryItem.FullName)'."
}
$repositoryRoot = Get-NormalizedFullPath -LiteralPath $repositoryItem.FullName
$memoryBankPath = Join-Path $repositoryRoot '.memory-bank'
if (-not (Test-Path -LiteralPath $memoryBankPath -PathType Container))
{
    throw "Memory Bank not found: '$memoryBankPath'."
}
if (Test-ReparsePoint -LiteralPath $memoryBankPath)
{
    throw "Memory Bank root must not be a symbolic link, junction, or reparse point: '$memoryBankPath'."
}

$absolutePlanPath = Get-NormalizedFullPath -LiteralPath (
    (Get-Item -LiteralPath $PlanPath -Force -ErrorAction Stop).FullName
)
if (Test-ReparsePoint -LiteralPath $absolutePlanPath)
{
    throw "Migration plan must not be a symbolic link or reparse point: '$absolutePlanPath'."
}

$plan = Get-Content -LiteralPath $absolutePlanPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
if ($plan.schemaVersion -ne 1)
{
    throw "Unsupported migration plan schema version '$($plan.schemaVersion)'. Expected 1."
}
$plannedRepositoryRoot = Get-NormalizedFullPath -LiteralPath (
    [string]$plan.repositoryRoot
)
if (-not (Test-PathEqual -Left $repositoryRoot -Right $plannedRepositoryRoot))
{
    throw "Migration plan repository root '$plannedRepositoryRoot' does not match selected repository root '$repositoryRoot'."
}

$sessionPath = Join-Path $memoryBankPath 'session'
if (-not (Test-Path -LiteralPath $sessionPath -PathType Container))
{
    throw "Memory Bank session directory not found: '$sessionPath'."
}
if (Test-ReparsePoint -LiteralPath $sessionPath)
{
    throw "Memory Bank session directory must not be a symbolic link or reparse point: '$sessionPath'."
}
$planParent = Get-NormalizedFullPath -LiteralPath (
    Split-Path -Parent $absolutePlanPath
)
if (-not (Test-PathEqual -Left $planParent -Right (
    Get-NormalizedFullPath -LiteralPath $sessionPath
)))
{
    throw "Migration plan must be a direct child of '$sessionPath'."
}
if ([IO.Path]::GetFileName($absolutePlanPath) -notlike (
    'role-record-migration-*.json'
))
{
    throw "Migration plan file name must match 'role-record-migration-*.json'."
}

$allowedRole = @('career', 'legal', 'tax')
$passiveStatus = @('Excluded', 'Unknown', 'ManualSplit', 'Skipped')
$candidateStatus = @('Ready', 'AlreadyMigrated')
$blockingMessage = [Collections.Generic.List[string]]::new()
$validatedEntry = [Collections.Generic.List[object]]::new()
$sourceKey = @{}
$destinationKey = @{}

foreach ($entry in @($plan.entries))
{
    $name = [string]$entry.name
    $source = ([string]$entry.source).Replace('\', '/')
    $status = [string]$entry.status
    if ([string]::IsNullOrWhiteSpace($name) -or
        $name -match '[/\\]' -or
        $name -in @('.', '..'))
    {
        $blockingMessage.Add("Invalid migration entry name '$name'.")
        continue
    }
    if ($source -notmatch '^\.memory-bank/[^/]+$' -or
        [IO.Path]::GetFileName($source) -cne $name)
    {
        $blockingMessage.Add(
            "Source '$source' must identify the named direct child of .memory-bank."
        )
        continue
    }

    $normalizedSourceKey = if ($env:OS -eq 'Windows_NT')
    {
        $source.ToLowerInvariant()
    }
    else
    {
        $source
    }
    if ($sourceKey.ContainsKey($normalizedSourceKey))
    {
        $blockingMessage.Add("Duplicate source '$source'.")
        continue
    }
    $sourceKey[$normalizedSourceKey] = $true

    $sourcePath = Get-RepositoryPath `
        -RepositoryRoot $repositoryRoot `
        -RelativePath $source
    $sourceParent = Get-NormalizedFullPath -LiteralPath (
        Split-Path -Parent $sourcePath
    )
    if (-not (Test-PathEqual -Left $sourceParent -Right (
        Get-NormalizedFullPath -LiteralPath $memoryBankPath
    )))
    {
        $blockingMessage.Add(
            "Source '$source' must remain a direct child of the Memory Bank root."
        )
        continue
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf))
    {
        $blockingMessage.Add("Source file not found: '$sourcePath'.")
        continue
    }
    if (Test-ReparsePoint -LiteralPath $sourcePath)
    {
        $blockingMessage.Add(
            "Source must not be a symbolic link or reparse point: '$sourcePath'."
        )
        continue
    }
    $sourceHash = Get-LowerFileHash -LiteralPath $sourcePath
    if ($sourceHash -cne ([string]$entry.sourceSha256).ToLowerInvariant())
    {
        $blockingMessage.Add(
            "Migration source hash changed after planning: '$source'."
        )
        continue
    }
    if ([long](Get-Item -LiteralPath $sourcePath).Length -ne [long]$entry.size)
    {
        $blockingMessage.Add(
            "Migration source size changed after planning: '$source'."
        )
        continue
    }

    if ($status -eq 'NeedsAssignment')
    {
        $blockingMessage.Add("NeedsAssignment: '$source'.")
        continue
    }
    if ($status -eq 'Conflict')
    {
        $blockingMessage.Add("Conflict: '$source'.")
        continue
    }
    if ($status -notin @($passiveStatus) + @($candidateStatus))
    {
        $blockingMessage.Add(
            "Unsupported migration entry status '$status' for '$source'."
        )
        continue
    }

    if ($status -in $passiveStatus)
    {
        $validatedEntry.Add([PSCustomObject]@{
            Entry = $entry
            SourcePath = $sourcePath
            DestinationPath = $null
            Action = 'Preserved'
        })
        continue
    }

    $role = [string]$entry.role
    if ($role -notin $allowedRole)
    {
        $blockingMessage.Add(
            "Migration role for '$source' must be career, legal, or tax. Received '$role'."
        )
        continue
    }
    $expectedDestination = ".memory-bank/$role/$name"
    $destination = ([string]$entry.destination).Replace('\', '/')
    if ($destination -cne $expectedDestination)
    {
        $blockingMessage.Add(
            "Destination '$destination' does not match expected '$expectedDestination'."
        )
        continue
    }

    $normalizedDestinationKey = if ($env:OS -eq 'Windows_NT')
    {
        $destination.ToLowerInvariant()
    }
    else
    {
        $destination
    }
    if ($destinationKey.ContainsKey($normalizedDestinationKey))
    {
        $blockingMessage.Add("Duplicate destination '$destination'.")
        continue
    }
    $destinationKey[$normalizedDestinationKey] = $true

    $rolePath = Join-Path $memoryBankPath $role
    if (Test-Path -LiteralPath $rolePath)
    {
        if (-not (Test-Path -LiteralPath $rolePath -PathType Container))
        {
            $blockingMessage.Add("Role destination is not a directory: '$rolePath'.")
            continue
        }
        if (Test-ReparsePoint -LiteralPath $rolePath)
        {
            $blockingMessage.Add(
                "Role destination must not be a symbolic link or reparse point: '$rolePath'."
            )
            continue
        }
    }

    $destinationPath = Get-RepositoryPath `
        -RepositoryRoot $repositoryRoot `
        -RelativePath $destination
    $currentAction = 'Ready'
    if (Test-Path -LiteralPath $destinationPath)
    {
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf))
        {
            $blockingMessage.Add("Conflict: destination is not a file '$destinationPath'.")
            continue
        }
        if (Test-ReparsePoint -LiteralPath $destinationPath)
        {
            $blockingMessage.Add(
                "Destination must not be a symbolic link or reparse point: '$destinationPath'."
            )
            continue
        }
        if ((Get-LowerFileHash -LiteralPath $destinationPath) -eq $sourceHash)
        {
            $currentAction = 'AlreadyMigrated'
        }
        else
        {
            $blockingMessage.Add("Conflict: destination content differs '$destinationPath'.")
            continue
        }
    }

    $validatedEntry.Add([PSCustomObject]@{
        Entry = $entry
        SourcePath = $sourcePath
        DestinationPath = $destinationPath
        Action = $currentAction
    })
}

if ($blockingMessage.Count -gt 0)
{
    throw "Migration plan validation failed:`n- $($blockingMessage -join "`n- ")"
}

foreach ($validated in $validatedEntry)
{
    $entry = $validated.Entry
    if ($validated.Action -eq 'Preserved')
    {
        [PSCustomObject]@{
            Source = [string]$entry.source
            Destination = [string]$entry.destination
            Action = 'Preserved'
            Status = [string]$entry.status
        }
        continue
    }
    if ($validated.Action -eq 'AlreadyMigrated')
    {
        [PSCustomObject]@{
            Source = [string]$entry.source
            Destination = [string]$entry.destination
            Action = 'AlreadyMigrated'
            Status = 'Verified'
        }
        continue
    }

    $destinationPath = $validated.DestinationPath
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container))
    {
        if ($PSCmdlet.ShouldProcess(
            $destinationDirectory,
            'Create role-record directory'
        ))
        {
            New-Item `
                -ItemType Directory `
                -Path $destinationDirectory `
                -ErrorAction Stop |
                Out-Null
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        $destinationPath,
        "Copy role record from '$($validated.SourcePath)'"
    ))
    {
        [PSCustomObject]@{
            Source = [string]$entry.source
            Destination = [string]$entry.destination
            Action = 'Planned'
            Status = 'Ready'
        }
        continue
    }

    if (Test-ReparsePoint -LiteralPath $destinationDirectory)
    {
        throw "Role destination became a symbolic link or reparse point: '$destinationDirectory'."
    }

    $destinationCreated = $false
    try
    {
        [IO.File]::Copy(
            $validated.SourcePath,
            $destinationPath,
            $false
        )
        $destinationCreated = $true
        $expectedHash = ([string]$entry.sourceSha256).ToLowerInvariant()
        $sourceHashAfterCopy = Get-LowerFileHash `
            -LiteralPath $validated.SourcePath
        $destinationHash = Get-LowerFileHash -LiteralPath $destinationPath
        if ($sourceHashAfterCopy -cne $expectedHash -or
            $destinationHash -cne $expectedHash)
        {
            throw "Hash verification failed after copying '$($entry.source)'."
        }
    }
    catch
    {
        $copyError = $_
        if ($destinationCreated -and
            (Test-Path -LiteralPath $destinationPath -PathType Leaf))
        {
            [IO.File]::Delete($destinationPath)
        }
        throw $copyError
    }

    [PSCustomObject]@{
        Source = [string]$entry.source
        Destination = [string]$entry.destination
        Action = 'Copied'
        Status = 'Verified'
    }
}