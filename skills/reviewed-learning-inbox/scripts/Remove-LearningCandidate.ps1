#Requires -Version 5.1

<#
.SYNOPSIS
    Discards one reviewed-learning-inbox candidate from a project's store.
.DESCRIPTION
    Removes a candidate the user does not want kept, together with any
    supersession links other candidates hold to it. Nothing outside the store is
    touched: no Customization, no Memory Bank base file, and no other project's
    records. Use Set-LearningCandidateStatus instead when the decision itself is
    worth keeping.
.PARAMETER Path
    Existing project directory whose Memory Bank holds the learning inbox.
.PARAMETER Id
    Candidate identifier to discard.
.PARAMETER ReferenceTime
    UTC time recorded on the store after the change.
.EXAMPLE
    ./Remove-LearningCandidate.ps1 -Path C:/Git/MyProject -Id cand-0123456789ab

    Discards one candidate and leaves every other record intact.
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
    [string]$Id,

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

$null = Get-LearningInboxCandidate -Store $store -Id $Id

$timestamp = $ReferenceTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$store.candidates = @(
    $store.candidates |
        Where-Object -FilterScript { [string]$_.id -ne $Id }
)

foreach ($candidate in @($store.candidates))
{
    if ([string]$candidate.supersededBy -eq $Id)
    {
        $candidate.supersededBy = ''
    }

    $candidate.supersedes = @(
        @($candidate.supersedes) |
            Where-Object -FilterScript { [string]$_ -ne $Id }
    )
}

$store.updatedUtc = $timestamp

if ($PSCmdlet.ShouldProcess($context.StorePath, "Discard learning candidate '$Id'"))
{
    Write-LearningInboxStore -Context $context -Store $store
}

return [PSCustomObject]@{
    Action = 'Removed'
    Id = $Id
    StorePath = $context.StoreRelativePath
    RemainingCount = @($store.candidates).Count
}
