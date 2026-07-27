#Requires -Version 5.1

<#
.SYNOPSIS
    Evaluates Memory Bank routing against provenance-labeled task cases.
.DESCRIPTION
    Parses the routing table from .memory-bank/index.md, resolves the files for
    each inert task case, and compares routed context with the full-read
    fallback. Prompt text is never executed or treated as instructions.
.PARAMETER Path
    Repository root containing .memory-bank.
.PARAMETER EvalFile
    JSON file containing routing cases.
.PARAMETER LoadingMode
    Optional override for the index loading mode.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([PSCustomObject])]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path = (Get-Location).Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$EvalFile = (Join-Path (Split-Path -Parent $PSScriptRoot) (
        'evals/routing-cases.json'
    )),

    [Parameter()]
    [ValidateSet('routed', 'full')]
    [string]$LoadingMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MemoryBankRoutingTable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$IndexPath
    )

    $routingTable = @{}
    $routePattern = '^\|\s*`(?<route>[^`]+)`\s*\|.*?\|\s*(?<read>.*?)\s*\|$'
    foreach ($line in Get-Content -LiteralPath $IndexPath) {
        if ($line -notmatch $routePattern) {
            continue
        }

        $files = @(
            [regex]::Matches($matches.read, '`(?<file>[^`]+)`') |
                ForEach-Object { $_.Groups['file'].Value }
        )
        $routingTable[$matches.route] = $files
    }

    $routingTable
}

function Get-MemoryBankFileMetric {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$LiteralPath
    )

    $content = Get-Content -LiteralPath $LiteralPath -Raw
    [PSCustomObject]@{
        Characters = $content.Length
        Lines = @(Get-Content -LiteralPath $LiteralPath).Count
        ApproximateTokens = [Math]::Ceiling($content.Length / 4)
    }
}

function Test-CaseProperty {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Case,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $Case.PSObject.Properties.Name -contains $Name
}

$repositoryPath = (Resolve-Path -LiteralPath $Path).Path
$memoryBankPath = Join-Path $repositoryPath '.memory-bank'
$indexPath = Join-Path $memoryBankPath 'index.md'
if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "Memory Bank index not found: $indexPath"
}

$indexContent = Get-Content -LiteralPath $indexPath -Raw
$indexMode = if ($indexContent -match '(?m)^loading-mode:\s*(routed|full)\s*$') {
    $matches[1]
} else {
    'full'
}
$effectiveMode = if ($PSBoundParameters.ContainsKey('LoadingMode')) {
    $LoadingMode
} else {
    $indexMode
}

$requiredFullFileNames = @(
    'index.md'
    'projectbrief.md'
    'productContext.md'
    'activeContext.md'
    'techContext.md'
    'progress.md'
    'systemPatterns.md'
)
$fullFileNames = @($requiredFullFileNames)
$localPromptHistoryPresent = Test-Path -LiteralPath (
    Join-Path $memoryBankPath 'promptHistory.md'
) -PathType Leaf
$glossaryPresent = Test-Path -LiteralPath (
    Join-Path $memoryBankPath 'glossary.md'
) -PathType Leaf
if ($localPromptHistoryPresent) {
    $fullFileNames += 'promptHistory.md'
}
if ($glossaryPresent) {
    $fullFileNames += 'glossary.md'
}
$fullDecisionFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $memoryBankPath 'decisions') `
        -Filter '*.md' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { "decisions/$($_.Name)" }
)
$fullFileNames += $fullDecisionFiles
$optionalFileNames = @('promptHistory.md', 'glossary.md')

$missingFullFiles = @(
    $requiredFullFileNames | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $memoryBankPath $_) -PathType Leaf)
    }
)
if ($missingFullFiles.Count -gt 0) {
    throw "Complete Memory Bank base is missing: $($missingFullFiles -join ', ')"
}

$fullCharacters = 0
foreach ($fileName in $fullFileNames) {
    if ($fileName -eq 'promptHistory.md') {
        continue
    }
    $filePath = Join-Path $memoryBankPath $fileName
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        continue
    }
    $metric = Get-MemoryBankFileMetric -LiteralPath $filePath
    $fullCharacters += $metric.Characters
}

$evalSet = Get-Content -LiteralPath $EvalFile -Raw | ConvertFrom-Json
$routingTable = Get-MemoryBankRoutingTable -IndexPath $indexPath
$coverageMisses = 0
$unexpectedHistoryLoads = 0
$fallbackFailures = 0
$routedCharacters = 0
$selectedLocalHistoryCharacters = 0
$details = @()
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

foreach ($case in @($evalSet.cases)) {
    $expectFallback = (
        (Test-CaseProperty -Case $case -Name 'expectFallback') -and
        [bool]$case.expectFallback
    )
    $allowHistory = (
        (Test-CaseProperty -Case $case -Name 'allowHistory') -and
        [bool]$case.allowHistory
    )
    $durableWrite = (
        (Test-CaseProperty -Case $case -Name 'durableWrite') -and
        [bool]$case.durableWrite
    )

    $selectedFiles = [Collections.Generic.List[string]]::new()
    [void]$selectedFiles.Add('index.md')
    $usedFallback = $effectiveMode -eq 'full'

    if (-not $usedFallback) {
        foreach ($route in @($case.routes)) {
            if (-not $routingTable.ContainsKey([string]$route)) {
                $usedFallback = $true
                break
            }

            foreach ($reference in @($routingTable[[string]$route])) {
                if ($reference -eq 'decisions/*.md') {
                    if (-not (Test-CaseProperty -Case $case -Name 'decisionFiles')) {
                        $usedFallback = $true
                        break
                    }
                    foreach ($decisionFile in @($case.decisionFiles)) {
                        [void]$selectedFiles.Add(
                            "decisions/$([string]$decisionFile)"
                        )
                    }
                    continue
                }
                if ($reference -like '*`**') {
                    $matchesForReference = @(
                        Get-ChildItem -Path (
                            Join-Path $memoryBankPath $reference
                        ) -File -ErrorAction SilentlyContinue
                    )
                    if ($matchesForReference.Count -eq 0) {
                        $usedFallback = $true
                        break
                    }
                    foreach ($match in $matchesForReference) {
                        $relativePath = $match.FullName.Substring(
                            $memoryBankPath.Length
                        ).TrimStart('\', '/') -replace '\\', '/'
                        [void]$selectedFiles.Add($relativePath)
                    }
                } else {
                    [void]$selectedFiles.Add($reference)
                }
            }
        }

        if (Test-CaseProperty -Case $case -Name 'roleFiles') {
            foreach ($roleFile in @($case.roleFiles)) {
                [void]$selectedFiles.Add([string]$roleFile)
            }
        }
        if ($durableWrite) {
            [void]$selectedFiles.Add('activeContext.md')
        }

        foreach ($optionalFileName in $optionalFileNames) {
            $optionalPath = Join-Path $memoryBankPath $optionalFileName
            if (-not (Test-Path -LiteralPath $optionalPath -PathType Leaf)) {
                [void]$selectedFiles.Remove($optionalFileName)
            }
        }

        foreach ($selectedFile in @($selectedFiles)) {
            $candidatePath = Join-Path $memoryBankPath $selectedFile
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
                $usedFallback = $true
                break
            }
        }
    }

    if ($usedFallback) {
        $selectedFiles.Clear()
        foreach ($fileName in $fullFileNames) {
            [void]$selectedFiles.Add($fileName)
        }
    }

    $uniqueFiles = @($selectedFiles | Select-Object -Unique)
    foreach ($requiredFile in @($case.requiredFiles)) {
        if ($requiredFile -notin $uniqueFiles) {
            $coverageMisses++
        }
    }
    if (
        $effectiveMode -eq 'routed' -and
        -not $usedFallback -and
        -not $allowHistory -and
        'promptHistory.md' -in $uniqueFiles
    ) {
        $unexpectedHistoryLoads++
    }
    if ($effectiveMode -eq 'routed' -and $usedFallback -ne $expectFallback) {
        $fallbackFailures++
    }

    $caseCharacters = 0
    foreach ($selectedFile in $uniqueFiles) {
        $selectedPath = Join-Path $memoryBankPath $selectedFile
        if (-not (Test-Path -LiteralPath $selectedPath -PathType Leaf)) {
            continue
        }
        if ($selectedFile -eq 'promptHistory.md') {
            $selectedLocalHistoryCharacters += (
                Get-MemoryBankFileMetric -LiteralPath $selectedPath
            ).Characters
            continue
        }
        $metric = Get-MemoryBankFileMetric -LiteralPath $selectedPath
        $caseCharacters += $metric.Characters
    }
    $routedCharacters += $caseCharacters

    $details += [PSCustomObject]@{
        Id = $case.id
        Files = $uniqueFiles
        UsedFallback = $usedFallback
        ApproximateTokens = [Math]::Ceiling($caseCharacters / 4)
    }
}
$stopwatch.Stop()

$caseCount = @($evalSet.cases).Count
$fullTotalCharacters = $fullCharacters * $caseCount
$reductionPercent = if ($effectiveMode -eq 'full') {
    0
} else {
    [Math]::Round(
        (1 - ($routedCharacters / $fullTotalCharacters)) * 100,
        2
    )
}
$passed = (
    $coverageMisses -eq 0 -and
    $unexpectedHistoryLoads -eq 0 -and
    $fallbackFailures -eq 0
)

[PSCustomObject]@{
    Passed = $passed
    Mode = $effectiveMode
    CaseCount = $caseCount
    CoverageMisses = $coverageMisses
    UnexpectedHistoryLoads = $unexpectedHistoryLoads
    FallbackFailures = $fallbackFailures
    FullDecisionRecordCount = $fullDecisionFiles.Count
    LocalPromptHistoryPresent = $localPromptHistoryPresent
    BaselineApproximateTokens = [Math]::Ceiling($fullCharacters / 4)
    AverageRoutedApproximateTokens = [Math]::Ceiling(
        ($routedCharacters / $caseCount) / 4
    )
    AverageContextReductionPercent = $reductionPercent
    AverageSelectedLocalHistoryApproximateTokens = [Math]::Ceiling(
        ($selectedLocalHistoryCharacters / $caseCount) / 4
    )
    MetricScope = 'version-controlled-files'
    ResolutionMilliseconds = $stopwatch.ElapsedMilliseconds
    Details = $details
}
