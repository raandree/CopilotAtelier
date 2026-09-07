#Requires -Version 5.1

<#
.SYNOPSIS
    Builds a concrete promotion preview for one reviewed-learning-inbox candidate.
.DESCRIPTION
    Re-validates the stored candidate against the same content rules that guard
    intake, confirms every evidence locator still matches its recorded SHA-256,
    resolves the destination against the allowed Skill and Instruction surface,
    and renders the exact lines a promotion would append. The command is
    read-only for the project: it changes no Customization, and it writes only
    the optional proposal file the reviewer approves later.
.PARAMETER Path
    Existing project directory whose Memory Bank holds the learning inbox.
.PARAMETER Id
    Candidate identifier to preview.
.PARAMETER SaveProposal
    Saves the proposal under the learning inbox so it can be approved later.
.PARAMETER ReferenceTime
    UTC time used in proposal metadata and the saved proposal file name.
.EXAMPLE
    ./New-LearningPromotionProposal.ps1 -Path C:/Git/MyProject -Id cand-0123456789ab

    Renders the preview without writing anything.
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
    [string]$Id,

    [Parameter()]
    [switch]$SaveProposal,

    [Parameter()]
    [ValidateNotNull()]
    [datetime]$ReferenceTime = [datetime]::UtcNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LearningInboxCommon.ps1')

$context = Resolve-LearningInboxContext -Path $Path
$store = Read-LearningInboxStore -Context $context

if ($null -eq $store)
{
    throw "No reviewed learning inbox was found for '$($context.RepositoryRoot)'."
}

$candidate = Get-LearningInboxCandidate -Store $store -Id $Id

if ([string]$candidate.status -in @('Rejected', 'Superseded'))
{
    throw "Candidate '$Id' is $([string]$candidate.status) and cannot be promoted. Record a new candidate instead."
}

Assert-LearningInboxCandidateContent `
    -Candidate $candidate `
    -RepositoryRoot $context.RepositoryRoot

$targetRelativePath = Assert-LearningInboxPromotionTarget `
    -Target ([string]$candidate.scope.target) `
    -ScopeKind ([string]$candidate.scope.kind) `
    -RepositoryRoot $context.RepositoryRoot

$targetPath = Join-Path $context.RepositoryRoot (
    $targetRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
)

if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf))
{
    throw "Promotion destination not found: '$targetRelativePath'."
}

if (Test-LearningInboxReparsePoint -LiteralPath $targetPath)
{
    throw "Promotion destination must not be a symbolic link or reparse point: '$targetRelativePath'."
}

$evidenceState = @(
    foreach ($item in @($candidate.evidence))
    {
        $relativePath = [string]$item.path
        $absolutePath = Join-Path $context.RepositoryRoot (
            $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        )

        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf))
        {
            throw "Candidate evidence is no longer present: '$relativePath'."
        }

        $currentHash = Get-LearningInboxFileHash -LiteralPath $absolutePath
        if ($currentHash -cne ([string]$item.sha256).ToLowerInvariant())
        {
            throw "Candidate evidence changed since it was recorded: '$relativePath'. Record a new candidate against the current content."
        }

        [PSCustomObject][ordered]@{
            path = $relativePath
            sha256 = $currentHash
        }
    }
)

$targetContent = (Read-LearningInboxTargetFile -LiteralPath $targetPath).Text
$targetSha256 = Get-LearningInboxFileHash -LiteralPath $targetPath

$mode = if ($targetContent -match [regex]::Escape("reviewed-learning-inbox:candidate $Id"))
{
    'AlreadyPromoted'
}
elseif ($targetContent -match 'reviewed-learning-inbox:section')
{
    'AppendEntry'
}
else
{
    'AppendSection'
}

$blockMode = if ($mode -eq 'AlreadyPromoted')
{
    'AppendEntry'
}
else
{
    $mode
}

$block = New-LearningInboxBlock -Candidate $candidate -Mode $blockMode
$preview = New-LearningInboxPreview `
    -Candidate $candidate `
    -TargetPath $targetRelativePath `
    -TargetSha256 $targetSha256 `
    -Block $block `
    -Mode $mode

$timestamp = $ReferenceTime.ToUniversalTime()
$proposalRelativePath = $null

if ($SaveProposal)
{
    $fileName = 'promotion-{0}-{1}.json' -f
        $Id,
        $timestamp.ToString('yyyy-MM-ddTHHmmssZ')
    $proposalRelativePath = "$($context.ProposalRelativePath)/$fileName"
}

$proposal = [PSCustomObject][ordered]@{
    schemaVersion = $script:LearningInboxSchemaVersion
    createdUtc = $timestamp.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    repositoryRoot = $context.RepositoryRoot
    projectId = $context.ProjectId
    candidateId = $Id
    candidateSha256 = Get-LearningInboxCandidateHash -Candidate $candidate
    scopeKind = [string]$candidate.scope.kind
    targetPath = $targetRelativePath
    targetSha256 = $targetSha256
    mode = $mode
    evidence = $evidenceState
    block = $block
    preview = $preview
    previewSha256 = Get-LearningInboxTextHash -Text $preview
    proposalPath = $proposalRelativePath
}

if ($SaveProposal)
{
    foreach ($directory in @($context.InboxPath, $context.ProposalPath))
    {
        $null = Assert-LearningInboxRegularPath `
            -LiteralPath $directory `
            -RepositoryRoot $context.RepositoryRoot `
            -Field 'The learning inbox directory'

        if (Test-Path -LiteralPath $directory)
        {
            if (-not (Test-Path -LiteralPath $directory -PathType Container))
            {
                throw "Learning inbox path is not a directory: '$directory'."
            }
        }
        elseif ($PSCmdlet.ShouldProcess($directory, 'Create promotion proposal directory'))
        {
            New-Item -ItemType Directory -Path $directory -ErrorAction Stop |
                Out-Null
        }
    }

    $absoluteProposalPath = Assert-LearningInboxRegularPath `
        -LiteralPath (
            Join-Path $context.RepositoryRoot (
                $proposalRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
            )
        ) `
        -RepositoryRoot $context.RepositoryRoot `
        -Field 'The promotion proposal'

    if ($PSCmdlet.ShouldProcess($absoluteProposalPath, 'Write promotion proposal'))
    {
        Write-LearningInboxFile `
            -LiteralPath $absoluteProposalPath `
            -Content ($proposal | ConvertTo-Json -Depth 12)
    }
}

return $proposal
