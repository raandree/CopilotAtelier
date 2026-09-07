#Requires -Version 5.1

<#
    .SYNOPSIS
        Reports one changed-file batch and the current standing of every receipt.

    .DESCRIPTION
        Read-only, and deliberately process-free. The report re-hashes each
        collected file, resolves the validation plan the file is due from static
        facts alone, and applies exactly the rule the validator applies: a
        receipt stands only when its hash, its plan identity, and every required
        check still match, and nothing moved underneath the run that produced it.

        No validator runs, no external process is started, and nothing is
        written. A tool is never launched merely to inspect a receipt.

    .PARAMETER Path
        The selected project root.

    .PARAMETER SessionId
        The batch to report. Ignored when AllSession is used.

    .PARAMETER AllSession
        Report every session in the store instead of one.

    .PARAMETER FailOnSeverity
        The failure severity the plan should be judged against. It must match the
        value validation used, because it is part of the plan identity.

    .PARAMETER MarkdownLintPath
        The markdownlint executable the plan should be judged against. Its
        resolved path, size, and timestamp are read; it is never run.

    .PARAMETER MarkdownLintInterface
        The linter interface the plan should be judged against.

    .OUTPUTS
        PSCustomObject

    .EXAMPLE
        ./Get-ChangedFileBatch.ps1 -Path $PWD.Path |
            Format-Table RelativePath, ValidationState, Verified

        Lists the default batch and the standing of each entry.
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [Parameter()]
    [AllowEmptyString()]
    [string]$SessionId = 'default',

    [Parameter()]
    [switch]$AllSession,

    [Parameter()]
    [ValidateSet('Error', 'Warning')]
    [string]$FailOnSeverity = 'Error',

    [Parameter()]
    [AllowEmptyString()]
    [string]$MarkdownLintPath = '',

    [Parameter()]
    [ValidateSet('markdownlint-cli', 'markdownlint-cli2')]
    [string]$MarkdownLintInterface = 'markdownlint-cli'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ChangedFileValidationCommon.ps1')

$context = Resolve-ChangedFileContext -Path $Path

$selected = if ($AllSession.IsPresent)
{
    @()
}
else
{
    @(Assert-ChangedFileSessionId -SessionId $SessionId)
}

$store = Read-ChangedFileStore -Context $context
if ($null -eq $store)
{
    return
}

$sessionName = if ($AllSession.IsPresent)
{
    @($store['sessions'].Keys | Sort-Object)
}
else
{
    $selected
}

foreach ($name in $sessionName)
{
    foreach ($entry in (Get-ChangedFileSessionEntry -Store $store -SessionId $name))
    {
        Get-ChangedFileEntryReport `
            -Context $context `
            -SessionId $name `
            -Entry $entry `
            -FailOnSeverity $FailOnSeverity `
            -MarkdownLintPath $MarkdownLintPath `
            -MarkdownLintInterface $MarkdownLintInterface
    }
}
