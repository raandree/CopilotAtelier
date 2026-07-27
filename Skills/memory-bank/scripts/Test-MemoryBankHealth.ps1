#Requires -Version 5.1

<#
.SYNOPSIS
    Tests Memory Bank structure, provenance, freshness, and compactness.
.DESCRIPTION
    Validates seven required version-controlled files, optional local prompt
    history, routing mode, metadata, line budgets, Decision records, Memory
    Bank topics, and retention. The script does not modify the repository and
    returns one structured summary object.
.PARAMETER Path
    Existing repository directory containing .memory-bank.
.PARAMETER ReferenceDate
    UTC date used for deterministic freshness and retention calculations.
.PARAMETER StaleAfterDays
    Age after which last-verified metadata produces a warning.
.PARAMETER PromptHistoryRetentionDays
    Age after which a prompt-history entry produces a warning.
.EXAMPLE
    ./Test-MemoryBankHealth.ps1 -Path C:/Git/MyProject

    Returns Memory Bank health findings without changing files.
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
    [datetime]$ReferenceDate = [datetime]::UtcNow.Date,

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$StaleAfterDays = 180,

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$PromptHistoryRetentionDays = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issues = [Collections.Generic.List[object]]::new()

function Add-MemoryBankIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Code,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$File,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $issues.Add([PSCustomObject]@{
        Severity = $Severity
        Code = $Code
        File = $File
        Message = $Message
    })
}

function Get-MemoryBankRecordHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $metadata = @{}
    foreach ($key in @(
        'schema-version'
        'loading-mode'
        'status'
        'date'
        'last-verified'
        'owner'
        'source'
        'supersedes'
    )) {
        $pattern = '(?m)^{0}:\s*(?<value>.+?)\r?$' -f [regex]::Escape($key)
        if ($Content -match $pattern) {
            $metadata[$key] = $Matches.value.Trim()
        }
    }

    $metadata
}

$memoryBankPath = Join-Path $Path '.memory-bank'
$canonicalFiles = [ordered]@{
    'index.md' = @{ LineBudget = 100; CharacterBudget = 7000 }
    'projectbrief.md' = @{ LineBudget = 200 }
    'productContext.md' = @{ LineBudget = 200 }
    'activeContext.md' = @{ LineBudget = 200 }
    'techContext.md' = @{ LineBudget = 200 }
    'progress.md' = @{ LineBudget = 200 }
    'systemPatterns.md' = @{ LineBudget = 110 }
    'promptHistory.md' = @{}
}
$optionalCanonicalFiles = @('promptHistory.md')
$requiredMetadata = @('status', 'last-verified', 'owner', 'source')
$canonicalFileCount = 0
$indexLineCount = 0
$indexCharacterCount = 0
$memoryBankTopicCount = 0
$decisionRecordCount = 0

if (-not (Test-Path -LiteralPath $memoryBankPath -PathType Container)) {
    Add-MemoryBankIssue `
        -Severity Error `
        -Code 'MemoryBankMissing' `
        -File '.memory-bank' `
        -Message 'The repository has no .memory-bank directory.'
} else {
    foreach ($entry in $canonicalFiles.GetEnumerator()) {
        $fileName = [string]$entry.Key
        $filePath = Join-Path $memoryBankPath $fileName
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            if ($fileName -notin $optionalCanonicalFiles) {
                Add-MemoryBankIssue `
                    -Severity Error `
                    -Code 'CanonicalFileMissing' `
                    -File $fileName `
                    -Message "Canonical file is missing: $fileName"
            }
            continue
        }

        $canonicalFileCount++
        $content = Get-Content -LiteralPath $filePath -Raw
        $lineCount = @(Get-Content -LiteralPath $filePath).Count
        if ([string]::IsNullOrWhiteSpace($content)) {
            Add-MemoryBankIssue `
                -Severity Error `
                -Code 'CanonicalFileEmpty' `
                -File $fileName `
                -Message "Canonical file is empty: $fileName"
        }

        if ($entry.Value.ContainsKey('LineBudget') -and
            $lineCount -gt $entry.Value.LineBudget) {
            Add-MemoryBankIssue `
                -Severity Error `
                -Code 'LineBudgetExceeded' `
                -File $fileName `
                -Message (
                    '{0} has {1} lines; budget is {2}.' -f
                    $fileName,
                    $lineCount,
                    $entry.Value.LineBudget
                )
        }

        if ($entry.Value.ContainsKey('CharacterBudget') -and
            $content.Length -gt $entry.Value.CharacterBudget) {
            Add-MemoryBankIssue `
                -Severity Error `
                -Code 'CharacterBudgetExceeded' `
                -File $fileName `
                -Message (
                    '{0} has {1} characters; budget is {2}.' -f
                    $fileName,
                    $content.Length,
                    $entry.Value.CharacterBudget
                )
        }

        if ($fileName -eq 'index.md') {
            $indexLineCount = $lineCount
            $indexCharacterCount = $content.Length
        }

        $metadata = Get-MemoryBankRecordHeader -Content $content
        foreach ($key in $requiredMetadata) {
            if (-not $metadata.ContainsKey($key)) {
                Add-MemoryBankIssue `
                    -Severity Error `
                    -Code 'MetadataMissing' `
                    -File $fileName `
                    -Message "Required metadata is missing: $key"
            }
        }

        if ($metadata.ContainsKey('last-verified')) {
            $lastVerified = [datetime]::MinValue
            $parsed = [datetime]::TryParseExact(
                $metadata['last-verified'],
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal,
                [ref]$lastVerified
            )
            if (-not $parsed) {
                Add-MemoryBankIssue `
                    -Severity Error `
                    -Code 'MetadataInvalid' `
                    -File $fileName `
                    -Message 'last-verified must use YYYY-MM-DD.'
            } elseif (($ReferenceDate.Date - $lastVerified.Date).Days -gt
                $StaleAfterDays) {
                Add-MemoryBankIssue `
                    -Severity Warning `
                    -Code 'VerificationStale' `
                    -File $fileName `
                    -Message (
                        'last-verified is older than {0} days.' -f
                        $StaleAfterDays
                    )
            }
        }

        if ($fileName -eq 'index.md') {
            if (-not $metadata.ContainsKey('loading-mode') -or
                $metadata['loading-mode'] -notin @('routed', 'full')) {
                Add-MemoryBankIssue `
                    -Severity Error `
                    -Code 'LoadingModeInvalid' `
                    -File $fileName `
                    -Message 'loading-mode must be routed or full.'
            }
        }
    }

    foreach ($directoryName in @('decisions', 'topics')) {
        $directoryPath = Join-Path $memoryBankPath $directoryName
        if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
            continue
        }

        $files = @(
            Get-ChildItem -LiteralPath $directoryPath -Filter '*.md' -File `
                -Recurse |
                Where-Object Name -ne 'README.md'
        )
        if ($directoryName -eq 'decisions') {
            $decisionRecordCount = $files.Count
        } else {
            $memoryBankTopicCount = $files.Count
        }

        foreach ($file in $files) {
            $relativePath = '{0}/{1}' -f $directoryName, (
                $file.FullName.Substring($directoryPath.Length + 1) -replace
                '\\',
                '/'
            )
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $metadata = Get-MemoryBankRecordHeader -Content $content
            foreach ($key in $requiredMetadata) {
                if (-not $metadata.ContainsKey($key)) {
                    Add-MemoryBankIssue `
                        -Severity Error `
                        -Code 'MetadataMissing' `
                        -File $relativePath `
                        -Message "Required metadata is missing: $key"
                }
            }
        }
    }

    $promptHistoryPath = Join-Path $memoryBankPath 'promptHistory.md'
    if (Test-Path -LiteralPath $promptHistoryPath -PathType Leaf) {
        $promptHistory = Get-Content -LiteralPath $promptHistoryPath -Raw
        $entryPattern = '(?m)^(?<date>\d{4}-\d{2}-\d{2}) ' +
            '\d{2}:\d{2} UTC \|'
        foreach ($match in [regex]::Matches($promptHistory, $entryPattern)) {
            $entryDate = [datetime]::ParseExact(
                $match.Groups['date'].Value,
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture
            )
            if (($ReferenceDate.Date - $entryDate.Date).Days -gt
                $PromptHistoryRetentionDays) {
                Add-MemoryBankIssue `
                    -Severity Warning `
                    -Code 'PromptHistoryExpired' `
                    -File 'promptHistory.md' `
                    -Message (
                        'Entry from {0} exceeds the {1}-day retention.' -f
                        $entryDate.ToString('yyyy-MM-dd'),
                        $PromptHistoryRetentionDays
                    )
            }
        }
    }
}

$errorCount = @($issues | Where-Object Severity -eq 'Error').Count
$warningCount = @($issues | Where-Object Severity -eq 'Warning').Count

[PSCustomObject]@{
    Passed = $errorCount -eq 0
    ErrorCount = $errorCount
    WarningCount = $warningCount
    CanonicalFileCount = $canonicalFileCount
    LocalPromptHistoryPresent = Test-Path -LiteralPath (
        Join-Path $memoryBankPath 'promptHistory.md'
    ) -PathType Leaf
    MemoryBankTopicCount = $memoryBankTopicCount
    DecisionRecordCount = $decisionRecordCount
    IndexLineCount = $indexLineCount
    IndexCharacterCount = $indexCharacterCount
    Issues = @($issues)
}
