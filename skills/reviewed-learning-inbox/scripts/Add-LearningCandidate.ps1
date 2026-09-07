#Requires -Version 5.1

<#
.SYNOPSIS
    Records a reusable-lesson candidate in a project's reviewed learning inbox.
.DESCRIPTION
    Stores a sanitized summary of a lesson observed in explicitly supplied local
    artifacts, together with project-relative evidence locators and their
    SHA-256 content identity. Observations, interpretations, and contradictory
    evidence are kept apart. An equivalent lesson is deduplicated onto the
    existing candidate and never resets a recorded rejection. Nothing recorded
    here changes agent behavior; a candidate is an untrusted observation until a
    human approves a concrete promotion preview.
.PARAMETER Path
    Existing project directory whose Memory Bank holds the learning inbox.
.PARAMETER Lesson
    Concise proposed lesson, stored as single-line prose.
.PARAMETER ScopeKind
    Intended scope: Skill, Instruction, NewSkill, NewInstruction, or NewAgent.
.PARAMETER Target
    Project-relative destination for a Skill or Instruction scope.
.PARAMETER Overlap
    Required explanation of overlap with existing Customizations for a New scope.
.PARAMETER Observation
    Facts that were observed. Keep interpretation out of these.
.PARAMETER Interpretation
    Inferences drawn from the observations.
.PARAMETER Contradiction
    Evidence that argues against the proposed lesson.
.PARAMETER Evidence
    Locators as hashtables with Path and optional Lines and Summary keys.
.PARAMETER Confidence
    Review label only: Low, Medium, or High. Never a probability.
.PARAMETER ReferenceTime
    UTC time recorded on the candidate.
.EXAMPLE
    ./Add-LearningCandidate.ps1 -Path C:/Git/MyProject -ScopeKind Skill `
        -Target skills/example/SKILL.md -Lesson 'Prefer the shared guard.' `
        -Observation 'The regression names the shared guard.' `
        -Evidence @(@{ Path = 'tests/Guard.Tests.ps1'; Lines = '10-20' })

    Records one candidate for later review.
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

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Lesson,

    [Parameter(Mandatory)]
    [ValidateSet('Skill', 'Instruction', 'NewSkill', 'NewInstruction', 'NewAgent')]
    [string]$ScopeKind,

    [Parameter()]
    [AllowEmptyString()]
    [string]$Target = '',

    [Parameter()]
    [AllowEmptyString()]
    [string]$Overlap = '',

    [Parameter()]
    [ValidateNotNull()]
    [string[]]$Observation = @(),

    [Parameter()]
    [ValidateNotNull()]
    [string[]]$Interpretation = @(),

    [Parameter()]
    [ValidateNotNull()]
    [string[]]$Contradiction = @(),

    [Parameter()]
    [ValidateNotNull()]
    [hashtable[]]$Evidence = @(),

    [Parameter()]
    [ValidateSet('Low', 'Medium', 'High')]
    [string]$Confidence = 'Low',

    [Parameter()]
    [ValidateNotNull()]
    [datetime]$ReferenceTime = [datetime]::UtcNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LearningInboxCommon.ps1')

$context = Resolve-LearningInboxContext -Path $Path
$timestamp = $ReferenceTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$isNewCustomization = $ScopeKind -like 'New*'
$scopeTarget = ''
$scopeOverlap = ''

if ($isNewCustomization)
{
    if ([string]::IsNullOrWhiteSpace($Overlap))
    {
        throw 'Overlap with existing Customizations must be explained before proposing a new Skill, Instruction, or Custom agent. Improving an existing Skill is the preferred outcome.'
    }

    $scopeOverlap = Assert-LearningInboxText -Text $Overlap -Field 'Overlap' -MaximumLength 300
}
else
{
    $scopeTarget = Assert-LearningInboxPromotionTarget `
        -Target $Target `
        -ScopeKind $ScopeKind `
        -RepositoryRoot $context.RepositoryRoot

    if (-not [string]::IsNullOrWhiteSpace($Overlap))
    {
        $scopeOverlap = Assert-LearningInboxText -Text $Overlap -Field 'Overlap' -MaximumLength 300
    }
}

$lessonText = Assert-LearningInboxText -Text $Lesson -Field 'Lesson' -MaximumLength 400

$observationText = @(
    foreach ($item in $Observation)
    {
        Assert-LearningInboxText -Text $item -Field 'Observation' -MaximumLength 300
    }
)

if ($observationText.Count -eq 0)
{
    throw 'At least one observation is required. A candidate without an observed fact is an opinion, not evidence.'
}

$interpretationText = @(
    foreach ($item in $Interpretation)
    {
        Assert-LearningInboxText -Text $item -Field 'Interpretation' -MaximumLength 300
    }
)

$contradictionText = @(
    foreach ($item in $Contradiction)
    {
        Assert-LearningInboxText -Text $item -Field 'Contradictory evidence' -MaximumLength 300
    }
)

if ($Evidence.Count -gt 10)
{
    throw 'A candidate may carry at most ten evidence locators. Summarize instead of accumulating.'
}

$evidenceEntry = @(
    foreach ($item in $Evidence)
    {
        if (-not $item.ContainsKey('Path'))
        {
            throw 'Every evidence entry requires a Path key naming a project-relative file.'
        }

        $relativePath = Assert-LearningInboxRelativePath `
            -RelativePath ([string]$item['Path']) `
            -Field 'Evidence path' `
            -RepositoryRoot $context.RepositoryRoot

        $absolutePath = Join-Path $context.RepositoryRoot (
            $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        )

        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf))
        {
            throw "Evidence file not found in the selected project: '$relativePath'."
        }

        if (Test-LearningInboxReparsePoint -LiteralPath $absolutePath)
        {
            throw "Evidence must not be a symbolic link or reparse point: '$relativePath'."
        }

        $lines = if ($item.ContainsKey('Lines'))
        {
            [string]$item['Lines']
        }
        else
        {
            ''
        }

        if (-not [string]::IsNullOrWhiteSpace($lines) -and $lines -notmatch '^\d+(-\d+)?$')
        {
            throw "Evidence line range must be a single number or a numeric range: '$lines'."
        }

        $summary = if ($item.ContainsKey('Summary') -and
            -not [string]::IsNullOrWhiteSpace([string]$item['Summary']))
        {
            Assert-LearningInboxText -Text ([string]$item['Summary']) -Field 'Evidence summary' -MaximumLength 300
        }
        else
        {
            ''
        }

        [PSCustomObject][ordered]@{
            path = $relativePath
            sha256 = Get-LearningInboxFileHash -LiteralPath $absolutePath
            lines = $lines
            summary = $summary
        }
    }
)

$scopeKey = '{0}|{1}' -f $ScopeKind, $scopeTarget
$candidateId = Get-LearningInboxCandidateId `
    -ProjectId $context.ProjectId `
    -ScopeKey $scopeKey `
    -Lesson $lessonText

$store = Read-LearningInboxStore -Context $context
if ($null -eq $store)
{
    $store = [PSCustomObject][ordered]@{
        schemaVersion = $script:LearningInboxSchemaVersion
        projectId = $context.ProjectId
        repositoryRoot = $context.RepositoryRoot
        updatedUtc = $timestamp
        candidates = @()
    }
}

$existing = @(
    $store.candidates |
        Where-Object -FilterScript { [string]$_.id -eq $candidateId }
)

if ($existing.Count -gt 0)
{
    $candidate = $existing[0]
    $action = 'Deduplicated'
    $candidate.occurrences = [int]$candidate.occurrences + 1
    $candidate.updatedUtc = $timestamp

    $candidate.observations = @(
        @($candidate.observations) + $observationText | Select-Object -Unique
    )
    $candidate.interpretations = @(
        @($candidate.interpretations) + $interpretationText | Select-Object -Unique
    )
    $candidate.contradictions = @(
        @($candidate.contradictions) + $contradictionText | Select-Object -Unique
    )

    $knownEvidence = @(
        @($candidate.evidence) |
            ForEach-Object -Process { '{0}|{1}' -f $_.path, $_.sha256 }
    )
    $candidate.evidence = @(
        @($candidate.evidence) + @(
            $evidenceEntry |
                Where-Object -FilterScript {
                    ('{0}|{1}' -f $_.path, $_.sha256) -notin $knownEvidence
                }
        )
    )
}
else
{
    $action = 'Created'
    $candidate = [PSCustomObject][ordered]@{
        id = $candidateId
        lesson = $lessonText
        scope = [PSCustomObject][ordered]@{
            kind = $ScopeKind
            target = $scopeTarget
            overlap = $scopeOverlap
        }
        evidence = $evidenceEntry
        observations = $observationText
        interpretations = $interpretationText
        contradictions = $contradictionText
        confidence = $Confidence
        confidenceNote = $script:LearningInboxConfidenceNote
        status = 'New'
        supersededBy = ''
        supersedes = @()
        occurrences = 1
        createdUtc = $timestamp
        updatedUtc = $timestamp
        decision = $null
        promotion = $null
    }

    $store.candidates = @(@($store.candidates) + $candidate)
}

$store.updatedUtc = $timestamp

if ($PSCmdlet.ShouldProcess($context.StorePath, "Record learning candidate '$candidateId'"))
{
    Write-LearningInboxStore -Context $context -Store $store
}

return [PSCustomObject]@{
    Action = $action
    Id = $candidateId
    StorePath = $context.StoreRelativePath
    Candidate = $candidate
}
