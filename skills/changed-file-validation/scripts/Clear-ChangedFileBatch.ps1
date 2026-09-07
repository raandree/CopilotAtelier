#Requires -Version 5.1

<#
    .SYNOPSIS
        Clears one changed-file batch, or every batch in the selected project.

    .DESCRIPTION
        Removes collected entries and their receipts. It touches only the batch
        store: no file the batch names is read, changed, or deleted.

    .PARAMETER Path
        The selected project root.

    .PARAMETER SessionId
        The batch to clear. Ignored when AllSession is used.

    .PARAMETER AllSession
        Clear every batch in the store.

    .OUTPUTS
        PSCustomObject

    .EXAMPLE
        ./Clear-ChangedFileBatch.ps1 -Path $PWD.Path

        Empties the default batch and leaves every other batch untouched.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
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
    [switch]$AllSession
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ChangedFileValidationCommon.ps1')

$context = Resolve-ChangedFileContext -Path $Path
$session = if ($AllSession.IsPresent) { '' } else { Assert-ChangedFileSessionId -SessionId $SessionId }

$target = if ($AllSession.IsPresent) { 'every changed-file batch' } else { "changed-file batch '$session'" }
if (-not $PSCmdlet.ShouldProcess($context.RepositoryRoot, "Clear $target"))
{
    return
}

$lock = Enter-ChangedFileLock -Context $context
$removed = 0
$cleared = @()

try
{
    $store = Read-ChangedFileStore -Context $context
    if ($null -eq $store)
    {
        return
    }

    $names = if ($AllSession.IsPresent) { @($store['sessions'].Keys) } else { @($session) }

    foreach ($name in $names)
    {
        if (-not $store['sessions'].ContainsKey($name))
        {
            continue
        }

        $removed += @(Get-ChangedFileSessionEntry -Store $store -SessionId $name).Count
        $cleared += $name
        $store['sessions'].Remove($name)
    }

    Write-ChangedFileStore -Context $context -Store $store
}
finally
{
    Exit-ChangedFileLock -Handle $lock
}

[PSCustomObject]@{
    RepositoryRoot = $context.RepositoryRoot
    ClearedSession = $cleared
    RemovedEntryCount = $removed
}
