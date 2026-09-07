#Requires -Version 5.1

<#
.SYNOPSIS
    Records a review decision on one reviewed-learning-inbox candidate.
.DESCRIPTION
    Sets a candidate to Rejected, Superseded, or back to New with a mandatory
    reason. The decision is retained, so a later repeated observation increments
    the occurrence count without resurrecting a rejected candidate. Supersession
    links both candidates. A promoted candidate is immutable here, because its
    lesson already lives in a reviewed Customization.
.PARAMETER Path
    Existing project directory whose Memory Bank holds the learning inbox.
.PARAMETER Id
    Candidate identifier to decide on.
.PARAMETER Status
    New review status: Rejected, Superseded, or New.
.PARAMETER Reason
    Short reason recorded with the decision.
.PARAMETER SupersededBy
    Identifier of the replacing candidate; required for Superseded.
.PARAMETER ReferenceTime
    UTC time recorded on the decision.
.EXAMPLE
    ./Set-LearningCandidateStatus.ps1 -Path C:/Git/MyProject -Id cand-0123456789ab `
        -Status Rejected -Reason 'The lesson restates an existing rule.'

    Rejects a candidate and keeps the decision on record.
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

    [Parameter(Mandatory)]
    [ValidateSet('New', 'Rejected', 'Superseded')]
    [string]$Status,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Reason,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SupersededBy,

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

$reasonText = Assert-LearningInboxText -Text $Reason -Field 'Reason' -MaximumLength 300
$candidate = Get-LearningInboxCandidate -Store $store -Id $Id

if ([string]$candidate.status -eq 'Promoted')
{
    throw "Candidate '$Id' was already promoted. Revise the destination Customization instead of rewriting the record."
}

$replacement = $null
if ($Status -eq 'Superseded')
{
    if (-not $PSBoundParameters.ContainsKey('SupersededBy'))
    {
        throw 'SupersededBy is required when marking a candidate as Superseded.'
    }

    if ($SupersededBy -eq $Id)
    {
        throw 'A candidate cannot supersede itself.'
    }

    $replacement = Get-LearningInboxCandidate -Store $store -Id $SupersededBy
}
elseif ($PSBoundParameters.ContainsKey('SupersededBy'))
{
    throw 'SupersededBy applies only to the Superseded status.'
}

$timestamp = $ReferenceTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$candidate.status = $Status
$candidate.updatedUtc = $timestamp
$candidate.decision = [PSCustomObject][ordered]@{
    status = $Status
    reason = $reasonText
    recordedUtc = $timestamp
}
$candidate.supersededBy = if ($Status -eq 'Superseded')
{
    $SupersededBy
}
else
{
    ''
}

if ($null -ne $replacement)
{
    $replacement.supersedes = @(
        @($replacement.supersedes) + $Id | Select-Object -Unique
    )
    $replacement.updatedUtc = $timestamp
}

$store.updatedUtc = $timestamp

if ($PSCmdlet.ShouldProcess($context.StorePath, "Record '$Status' for candidate '$Id'"))
{
    Write-LearningInboxStore -Context $context -Store $store
}

return $candidate
