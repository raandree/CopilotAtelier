#Requires -Version 5.1

<#
.SYNOPSIS
    Creates a read-only plan for namespacing legacy Memory Bank role records.
.DESCRIPTION
    Inventories direct child files under a selected repository's .memory-bank,
    classifies them with the bundled migration map, and returns metadata only.
    No file is written unless SavePlan is specified.
.PARAMETER Path
    Existing repository directory whose .memory-bank will be inventoried.
.PARAMETER Assignment
    Decisions for ambiguous file names. Values are career, legal, tax,
    ManualSplit, or Skip.
.PARAMETER SavePlan
    Saves the metadata-only plan under .memory-bank/session.
.PARAMETER ReferenceTime
    UTC time used in plan metadata and the saved plan file name.
.EXAMPLE
    ./New-MemoryBankRoleMigrationPlan.ps1 -Path C:/Git/MyProject

    Returns an in-memory plan without writing files.
.EXAMPLE
    ./New-MemoryBankRoleMigrationPlan.ps1 -Path C:/Git/MyProject -Assignment @{
        'deadlines.md' = 'tax'
    } -SavePlan

    Saves a plan after assigning the ambiguous deadlines file to tax.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param
(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path = (Get-Location).Path,

    [Parameter()]
    [ValidateNotNull()]
    [hashtable]$Assignment = @{},

    [Parameter()]
    [switch]$SavePlan,

    [Parameter()]
    [ValidateNotNull()]
    [datetime]$ReferenceTime = [datetime]::UtcNow
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

function Assert-LeafName
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Field
    )

    if ($Name -match '[/\\]' -or $Name -in @('.', '..'))
    {
        throw "$Field must be a file-name pattern without a directory: '$Name'."
    }
}

function Get-NormalizedDecision
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    switch ($Value.ToLowerInvariant())
    {
        'career' { return 'career' }
        'legal' { return 'legal' }
        'tax' { return 'tax' }
        'manualsplit' { return 'ManualSplit' }
        'skip' { return 'Skip' }
        default
        {
            throw "Assignment for '$Name' must be career, legal, tax, ManualSplit, or Skip. Received '$Value'."
        }
    }
}

function Write-Utf8FileExclusive
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

    $encoding = [Text.UTF8Encoding]::new($false)
    $bytes = $encoding.GetBytes(
        ($Content -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    )
    $stream = [IO.File]::Open(
        $LiteralPath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try
    {
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally
    {
        $stream.Dispose()
    }
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
    throw "Memory Bank not found: '$memoryBankPath'. Initialize it before planning role-record migration."
}
if (Test-ReparsePoint -LiteralPath $memoryBankPath)
{
    throw "Memory Bank root must not be a symbolic link, junction, or reparse point: '$memoryBankPath'."
}

$migrationMapPath = Join-Path (Split-Path -Parent $PSScriptRoot) (
    'assets/role-record-migration-map.json'
)
if (-not (Test-Path -LiteralPath $migrationMapPath -PathType Leaf))
{
    throw "Migration map not found: '$migrationMapPath'."
}
$migrationMap = Get-Content -LiteralPath $migrationMapPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
if ($migrationMap.schemaVersion -ne 1)
{
    throw "Unsupported migration map schema version '$($migrationMap.schemaVersion)'. Expected 1."
}

$allowedRole = @('career', 'legal', 'tax')
$automaticRule = @($migrationMap.automaticRules)
if ($automaticRule.Count -eq 0)
{
    throw 'Migration map must define at least one automatic rule.'
}
foreach ($rule in $automaticRule)
{
    Assert-LeafName -Name ([string]$rule.pattern) -Field 'Automatic rule pattern'
    if ([string]$rule.role -notin $allowedRole)
    {
        throw "Automatic rule '$($rule.pattern)' has unsupported role '$($rule.role)'."
    }
}
$ambiguousName = @($migrationMap.ambiguousNames | ForEach-Object { [string]$_ })
$excludedName = @($migrationMap.excludedNames | ForEach-Object { [string]$_ })
foreach ($name in @($ambiguousName) + @($excludedName))
{
    Assert-LeafName -Name $name -Field 'Migration map name'
}

$normalizedAssignment = @{}
foreach ($entry in $Assignment.GetEnumerator())
{
    $name = [string]$entry.Key
    Assert-LeafName -Name $name -Field 'Assignment name'
    if ($name -notin $ambiguousName)
    {
        throw "Assignment '$name' is not one of the ambiguous migration files."
    }
    $normalizedAssignment[$name] = Get-NormalizedDecision `
        -Name $name `
        -Value ([string]$entry.Value)
}

$planEntry = @(
    foreach ($file in Get-ChildItem -LiteralPath $memoryBankPath -Force |
        Where-Object { -not $_.PSIsContainer } |
        Sort-Object -Property Name)
    {
        if (Test-ReparsePoint -LiteralPath $file.FullName)
        {
            throw "Legacy role record must not be a symbolic link or reparse point: '$($file.FullName)'."
        }

        $classification = 'Unknown'
        $decision = $null
        $role = $null
        $status = 'Unknown'

        if ($file.Name -in $excludedName)
        {
            $classification = 'Excluded'
            $status = 'Excluded'
        }
        elseif ($file.Name -in $ambiguousName)
        {
            $classification = 'Ambiguous'
            if ($normalizedAssignment.ContainsKey($file.Name))
            {
                $decision = $normalizedAssignment[$file.Name]
                switch ($decision)
                {
                    'ManualSplit' { $status = 'ManualSplit' }
                    'Skip' { $status = 'Skipped' }
                    default
                    {
                        $role = $decision
                        $status = 'Ready'
                    }
                }
            }
            else
            {
                $status = 'NeedsAssignment'
            }
        }
        else
        {
            foreach ($rule in $automaticRule)
            {
                if ($file.Name -like [string]$rule.pattern)
                {
                    $classification = 'Automatic'
                    $role = [string]$rule.role
                    $decision = $role
                    $status = 'Ready'
                    break
                }
            }
        }

        $sourceHash = Get-LowerFileHash -LiteralPath $file.FullName
        $destination = $null
        if ($role)
        {
            $rolePath = Join-Path $memoryBankPath $role
            if (Test-Path -LiteralPath $rolePath)
            {
                if (-not (Test-Path -LiteralPath $rolePath -PathType Container))
                {
                    throw "Role destination is not a directory: '$rolePath'."
                }
                if (Test-ReparsePoint -LiteralPath $rolePath)
                {
                    throw "Role destination must not be a symbolic link or reparse point: '$rolePath'."
                }
            }

            $destination = ".memory-bank/$role/$($file.Name)"
            $destinationPath = Join-Path $rolePath $file.Name
            if (Test-Path -LiteralPath $destinationPath)
            {
                if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf))
                {
                    $status = 'Conflict'
                }
                elseif (Test-ReparsePoint -LiteralPath $destinationPath)
                {
                    throw "Role destination file must not be a symbolic link or reparse point: '$destinationPath'."
                }
                elseif ((Get-LowerFileHash -LiteralPath $destinationPath) -eq $sourceHash)
                {
                    $status = 'AlreadyMigrated'
                }
                else
                {
                    $status = 'Conflict'
                }
            }
        }

        [PSCustomObject][ordered]@{
            name = $file.Name
            source = ".memory-bank/$($file.Name)"
            sourceSha256 = $sourceHash
            size = [long]$file.Length
            classification = $classification
            decision = $decision
            role = $role
            destination = $destination
            status = $status
        }
    }
)

$planPath = $null
if ($SavePlan)
{
    $sessionPath = Join-Path $memoryBankPath 'session'
    if (Test-Path -LiteralPath $sessionPath)
    {
        if (-not (Test-Path -LiteralPath $sessionPath -PathType Container))
        {
            throw "Memory Bank session path is not a directory: '$sessionPath'."
        }
        if (Test-ReparsePoint -LiteralPath $sessionPath)
        {
            throw "Memory Bank session path must not be a symbolic link or reparse point: '$sessionPath'."
        }
    }
    elseif ($PSCmdlet.ShouldProcess($sessionPath, 'Create migration plan directory'))
    {
        New-Item -ItemType Directory -Path $sessionPath -ErrorAction Stop |
            Out-Null
    }

    $fileName = 'role-record-migration-{0}.json' -f (
        $ReferenceTime.ToUniversalTime().ToString('yyyy-MM-ddTHHmmssZ')
    )
    $planPath = ".memory-bank/session/$fileName"
}

$plan = [PSCustomObject][ordered]@{
    schemaVersion = 1
    createdUtc = $ReferenceTime.ToUniversalTime().ToString(
        'yyyy-MM-ddTHH:mm:ss.fffZ'
    )
    repositoryRoot = $repositoryRoot
    planPath = $planPath
    entries = $planEntry
}

if ($SavePlan)
{
    $absolutePlanPath = Join-Path $repositoryRoot $planPath
    if ($PSCmdlet.ShouldProcess($absolutePlanPath, 'Write role-record migration plan'))
    {
        Write-Utf8FileExclusive `
            -LiteralPath $absolutePlanPath `
            -Content ($plan | ConvertTo-Json -Depth 10)
    }
}

return $plan