#Requires -Version 5.1

<#
.SYNOPSIS
    Applies an approved reviewed-learning-inbox promotion to one Customization.
.DESCRIPTION
    Validates the whole proposal before any write: the proposal must belong to
    the selected project, no path may be reached through a symbolic link or
    junction, its destination must agree with the candidate scope and stay
    inside the allowed Skill and Instruction surface, the proposal evidence
    must be identical to the authoritative candidate evidence, and the
    candidate record, its evidence, and the destination bytes must all still
    match the values captured in the preview. Without Approve and the SHA-256
    of the reviewed preview nothing is written. Application appends through a
    write-exclusive handle, so the original bytes are preserved exactly and a
    concurrent edit is refused instead of overwritten. Repeat application is
    bound to the verified block content, not to the presence of a marker: an
    apply that appended the block but never recorded it is reconciled with the
    same approval, and an edited or forged block is refused.
.PARAMETER Path
    Existing project directory whose Memory Bank holds the learning inbox.
.PARAMETER ProposalPath
    Saved promotion proposal under the learning inbox proposals directory.
.PARAMETER Approve
    Explicit human approval of the previewed change.
.PARAMETER ApprovedPreviewSha256
    SHA-256 of the preview the approver actually read.
.PARAMETER ReferenceTime
    UTC time recorded with the promotion.
.EXAMPLE
    ./Invoke-LearningPromotion.ps1 -Path C:/Git/MyProject `
        -ProposalPath C:/Git/MyProject/.memory-bank/learning-inbox/proposals/promotion-cand-0123456789ab-2026-09-07T101500Z.json

    Validates the proposal and reports the preview without writing.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

# The approval gate is Approve plus the SHA-256 of the reviewed preview, not an
# interactive prompt: a prompt can be answered blind and suppressed wholesale.
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Preview')]
[OutputType([PSCustomObject])]
param
(
    [Parameter(ParameterSetName = 'Preview')]
    [Parameter(ParameterSetName = 'Approve')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path = (Get-Location).Path,

    [Parameter(Mandatory, ParameterSetName = 'Preview')]
    [Parameter(Mandatory, ParameterSetName = 'Approve')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ProposalPath,

    [Parameter(Mandatory, ParameterSetName = 'Approve')]
    [switch]$Approve,

    [Parameter(Mandatory, ParameterSetName = 'Approve')]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ApprovedPreviewSha256,

    [Parameter(ParameterSetName = 'Preview')]
    [Parameter(ParameterSetName = 'Approve')]
    [ValidateNotNull()]
    [datetime]$ReferenceTime = [datetime]::UtcNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LearningInboxCommon.ps1')

$context = Resolve-LearningInboxContext -Path $Path

$absoluteProposalPath = Get-LearningInboxFullPath -LiteralPath (
    (Get-Item -LiteralPath $ProposalPath -Force -ErrorAction Stop).FullName
)

# Location and name are settled before the file is opened, so a proposal from
# another project is refused rather than parsed.
$proposalParent = Get-LearningInboxFullPath -LiteralPath (
    Split-Path -Parent $absoluteProposalPath
)
if (-not (Test-LearningInboxPathEqual -Left $proposalParent -Right (
            Get-LearningInboxFullPath -LiteralPath $context.ProposalPath
        )))
{
    throw "The promotion proposal '$absoluteProposalPath' does not match the selected project: it must be a direct child of '$($context.ProposalPath)'."
}

if ([IO.Path]::GetFileName($absoluteProposalPath) -notlike 'promotion-*.json')
{
    throw "Promotion proposal file name must match 'promotion-*.json'."
}

$null = Assert-LearningInboxRegularPath `
    -LiteralPath $absoluteProposalPath `
    -RepositoryRoot $context.RepositoryRoot `
    -Field 'The promotion proposal'

$proposal = Get-Content -LiteralPath $absoluteProposalPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop

if ($proposal.schemaVersion -ne $script:LearningInboxSchemaVersion)
{
    throw "Unsupported promotion proposal schema version '$($proposal.schemaVersion)'. Expected $script:LearningInboxSchemaVersion."
}

$proposedRoot = Get-LearningInboxFullPath -LiteralPath ([string]$proposal.repositoryRoot)
if (-not (Test-LearningInboxPathEqual -Left $proposedRoot -Right $context.RepositoryRoot))
{
    throw "Promotion proposal names project '$proposedRoot', which does not match the selected project '$($context.RepositoryRoot)'."
}

$store = Read-LearningInboxStore -Context $context
if ($null -eq $store)
{
    throw "No reviewed learning inbox was found for '$($context.RepositoryRoot)'."
}

$candidateId = [string]$proposal.candidateId
$candidate = Get-LearningInboxCandidate -Store $store -Id $candidateId

# The destination is checked against the candidate before the surface
# allow-list so a rewritten proposal reports the contradiction it introduced.
$proposedTarget = Assert-LearningInboxRelativePath `
    -RelativePath ([string]$proposal.targetPath) `
    -Field 'Promotion target' `
    -RepositoryRoot $context.RepositoryRoot

if ($proposedTarget -cne ([string]$candidate.scope.target))
{
    throw "Promotion target '$proposedTarget' contradicts the candidate scope target '$([string]$candidate.scope.target)'."
}

$targetRelativePath = Assert-LearningInboxPromotionTarget `
    -Target $proposedTarget `
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

$targetContent = (Read-LearningInboxTargetFile -LiteralPath $targetPath).Text
$marker = "reviewed-learning-inbox:candidate $candidateId"

# Content, evidence identity, and evidence state are checked before any marker
# is trusted, so a marker written by hand can never claim a promotion.
Assert-LearningInboxCandidateContent `
    -Candidate $candidate `
    -RepositoryRoot $context.RepositoryRoot

Assert-LearningInboxEvidenceIdentity `
    -Candidate $candidate `
    -ProposalEvidence @($proposal.evidence)

Assert-LearningInboxEvidenceState `
    -Candidate $candidate `
    -RepositoryRoot $context.RepositoryRoot

$expectedRegion = Get-LearningInboxBlockRegion `
    -Content (New-LearningInboxBlock -Candidate $candidate -Mode 'AppendEntry') `
    -CandidateId $candidateId

$appliedRegion = Get-LearningInboxBlockRegion `
    -Content $targetContent `
    -CandidateId $candidateId

if ($null -ne $appliedRegion)
{
    $currentTargetHash = Get-LearningInboxFileHash -LiteralPath $targetPath

    if ($appliedRegion -cne $expectedRegion)
    {
        throw "The block already in '$targetRelativePath' for candidate '$candidateId' does not match the candidate record. A promotion never produces that difference, so the destination or the record was edited; resolve it by hand before promoting again."
    }

    $proposedRegion = Get-LearningInboxBlockRegion `
        -Content ([string]$proposal.block) `
        -CandidateId $candidateId

    if ($proposedRegion -cne $expectedRegion)
    {
        throw "The promotion proposal block does not match the candidate record. Generate a new proposal and review it again."
    }

    $promotion = $candidate.PSObject.Properties['promotion']

    if ([string]$candidate.status -eq 'Promoted')
    {
        if ($null -eq $promotion -or $null -eq $promotion.Value -or
            ([string]$promotion.Value.targetPath) -cne $targetRelativePath)
        {
            throw "Candidate '$candidateId' is recorded as promoted but carries no promotion record for '$targetRelativePath'. Resolve the record by hand before promoting again."
        }

        return [PSCustomObject]@{
            Action = 'AlreadyPromoted'
            CandidateId = $candidateId
            TargetPath = $targetRelativePath
            PreviousSha256 = $currentTargetHash
            NewSha256 = $currentTargetHash
            PreviewSha256 = [string]$proposal.previewSha256
            ProposalPath = $absoluteProposalPath
            RecordedSha256 = [string]$promotion.Value.newSha256
        }
    }

    # The block is verified but unrecorded: an apply that appended and then
    # failed before the store was saved. Reconcile the store only, and keep the
    # original human approval requirement for doing so.
    if ([string]$candidate.status -in @('Rejected', 'Superseded'))
    {
        throw "The candidate is $([string]$candidate.status) but its block is already present in '$targetRelativePath'. Remove the block by hand; nothing was changed."
    }

    $currentCandidateHash = Get-LearningInboxCandidateHash -Candidate $candidate
    if ($currentCandidateHash -cne ([string]$proposal.candidateSha256).ToLowerInvariant())
    {
        throw "The block in '$targetRelativePath' matches the candidate record, but the candidate changed after this proposal was approved. Nothing was changed; generate a new proposal and review it again."
    }

    if (-not $Approve)
    {
        return [PSCustomObject]@{
            Action = 'ReconciliationRequired'
            CandidateId = $candidateId
            TargetPath = $targetRelativePath
            PreviousSha256 = $currentTargetHash
            NewSha256 = $currentTargetHash
            PreviewSha256 = [string]$proposal.previewSha256
            ProposalPath = $absoluteProposalPath
            Recovery = "The approved block is already present in '$targetRelativePath' but the store never recorded it. Re-run this command with -Approve and -ApprovedPreviewSha256 $([string]$proposal.previewSha256) to record the promotion; the destination will not be written to again."
        }
    }

    if ($ApprovedPreviewSha256.ToLowerInvariant() -cne ([string]$proposal.previewSha256).ToLowerInvariant())
    {
        throw 'The supplied approval does not match the previewed change. Approve the SHA-256 of the preview that was actually reviewed.'
    }

    if (-not $PSCmdlet.ShouldProcess($context.StorePath, "Reconcile the recorded promotion of '$candidateId'"))
    {
        return [PSCustomObject]@{
            Action = 'Planned'
            CandidateId = $candidateId
            TargetPath = $targetRelativePath
            PreviousSha256 = $currentTargetHash
            NewSha256 = $currentTargetHash
            PreviewSha256 = [string]$proposal.previewSha256
            ProposalPath = $absoluteProposalPath
        }
    }

    $reconciledUtc = $ReferenceTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $candidate.status = 'Promoted'
    $candidate.updatedUtc = $reconciledUtc
    $candidate | Add-Member -NotePropertyName 'promotion' -NotePropertyValue (
        [PSCustomObject][ordered]@{
            targetPath = $targetRelativePath
            previousSha256 = ([string]$proposal.targetSha256).ToLowerInvariant()
            newSha256 = $currentTargetHash
            previewSha256 = [string]$proposal.previewSha256
            proposalPath = ([string]$proposal.proposalPath)
            promotedUtc = $reconciledUtc
        }
    ) -Force

    $store.updatedUtc = $reconciledUtc
    Write-LearningInboxStore -Context $context -Store $store

    return [PSCustomObject]@{
        Action = 'Reconciled'
        CandidateId = $candidateId
        TargetPath = $targetRelativePath
        PreviousSha256 = $currentTargetHash
        NewSha256 = $currentTargetHash
        PreviewSha256 = [string]$proposal.previewSha256
        ProposalPath = $absoluteProposalPath
    }
}

if ([string]$candidate.status -in @('Rejected', 'Superseded'))
{
    throw "The candidate is $([string]$candidate.status) and cannot be promoted."
}

$currentCandidateHash = Get-LearningInboxCandidateHash -Candidate $candidate
if ($currentCandidateHash -cne ([string]$proposal.candidateSha256).ToLowerInvariant())
{
    throw "The candidate record changed after the preview was produced. Generate a new proposal and review it again."
}

if ([string]$candidate.status -eq 'Promoted')
{
    throw "Candidate '$candidateId' is recorded as promoted but no promoted block is present in '$targetRelativePath'. Resolve the record by hand before promoting again."
}

$currentTargetHash = Get-LearningInboxFileHash -LiteralPath $targetPath
if ($currentTargetHash -cne ([string]$proposal.targetSha256).ToLowerInvariant())
{
    throw "The promotion destination changed after the preview was produced. Generate a new proposal and review it again."
}

$mode = if ($targetContent -match 'reviewed-learning-inbox:section')
{
    'AppendEntry'
}
else
{
    'AppendSection'
}

$block = New-LearningInboxBlock -Candidate $candidate -Mode $mode
$preview = New-LearningInboxPreview `
    -Candidate $candidate `
    -TargetPath $targetRelativePath `
    -TargetSha256 $currentTargetHash `
    -Block $block `
    -Mode $mode
$previewSha256 = Get-LearningInboxTextHash -Text $preview

if ($previewSha256 -cne ([string]$proposal.previewSha256).ToLowerInvariant())
{
    throw 'The recorded preview no longer matches the change this promotion would make. Generate a new proposal and review it again.'
}

if (-not $Approve)
{
    return [PSCustomObject]@{
        Action = 'PreviewOnly'
        CandidateId = $candidateId
        TargetPath = $targetRelativePath
        PreviousSha256 = $currentTargetHash
        NewSha256 = $currentTargetHash
        PreviewSha256 = $previewSha256
        ProposalPath = $absoluteProposalPath
        Preview = $preview
    }
}

if ($ApprovedPreviewSha256.ToLowerInvariant() -cne $previewSha256)
{
    throw 'The supplied approval does not match the previewed change. Approve the SHA-256 of the preview that was actually reviewed.'
}

if (-not $PSCmdlet.ShouldProcess($targetPath, "Append approved lesson '$candidateId'"))
{
    return [PSCustomObject]@{
        Action = 'Planned'
        CandidateId = $candidateId
        TargetPath = $targetRelativePath
        PreviousSha256 = $currentTargetHash
        NewSha256 = $currentTargetHash
        PreviewSha256 = $previewSha256
        ProposalPath = $absoluteProposalPath
        Preview = $preview
    }
}

$applied = Add-LearningInboxTargetContent `
    -LiteralPath $targetPath `
    -ExpectedSha256 $currentTargetHash `
    -Block $block `
    -RequiredMarker $marker

$timestamp = $ReferenceTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$candidate.status = 'Promoted'
$candidate.updatedUtc = $timestamp
$candidate | Add-Member -NotePropertyName 'promotion' -NotePropertyValue (
    [PSCustomObject][ordered]@{
        targetPath = $targetRelativePath
        previousSha256 = $applied.PreviousSha256
        newSha256 = $applied.NewSha256
        previewSha256 = $previewSha256
        proposalPath = ([string]$proposal.proposalPath)
        promotedUtc = $timestamp
    }
) -Force

$store.updatedUtc = $timestamp

try
{
    Write-LearningInboxStore -Context $context -Store $store
}
catch
{
    throw "The approved lesson was appended to '$targetRelativePath', but the reviewed learning inbox store could not be updated: $($_.Exception.Message) The destination is correct; re-run this command with the same approved proposal to record the promotion."
}

return [PSCustomObject]@{
    Action = 'Promoted'
    CandidateId = $candidateId
    TargetPath = $targetRelativePath
    PreviousSha256 = $applied.PreviousSha256
    NewSha256 = $applied.NewSha256
    PreviewSha256 = $previewSha256
    ProposalPath = $absoluteProposalPath
    Preview = $preview
}
