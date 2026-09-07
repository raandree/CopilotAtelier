#Requires -Version 5.1

<#
.SYNOPSIS
    Reads reviewed-learning-inbox candidates for one project without changing them.
.DESCRIPTION
    Returns the stored candidates for the selected project. The command is
    read-only: it creates no directory, writes no file, and reports nothing when
    the project has no learning inbox. Candidates from another project are never
    visible, because the store records the project it belongs to.
.PARAMETER Path
    Existing project directory whose Memory Bank holds the learning inbox.
.PARAMETER Id
    Optional candidate identifier filter.
.PARAMETER Status
    Optional review-status filter.
.EXAMPLE
    ./Get-LearningCandidate.ps1 -Path C:/Git/MyProject -Status New

    Lists the candidates still awaiting review.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([PSCustomObject])]
param
(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path = (Get-Location).Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Id,

    [Parameter()]
    [ValidateSet('New', 'Rejected', 'Superseded', 'Promoted')]
    [string]$Status
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LearningInboxCommon.ps1')

$context = Resolve-LearningInboxContext -Path $Path
$store = Read-LearningInboxStore -Context $context

if ($null -eq $store)
{
    return
}

$result = @($store.candidates)

if ($PSBoundParameters.ContainsKey('Id'))
{
    $result = @($result | Where-Object -FilterScript { [string]$_.id -eq $Id })
}

if ($PSBoundParameters.ContainsKey('Status'))
{
    $result = @($result | Where-Object -FilterScript { [string]$_.status -eq $Status })
}

return $result
