<#
.SYNOPSIS
    Reads and changes the private Contributor profile. The one command line the
    contributor-profile Skill runs, and the implementation the
    *-CopilotAtelierContributorProfile commands wrap.

.DESCRIPTION
    Get reports where the profile lives, the selected entry and why, its levels,
    the exact sentence the SessionStart hook would inject for a workspace,
    possible conflict copies, and the registration state. Aliases are masked
    unless -ShowAliases.

    Set changes one entry: a Knowledge area level, the opt-out state, aliases,
    the default flag, or the interview snooze. A write goes only to a
    positively chosen target: the entry -Contributor names, else the entry
    whose alias matches the git address of the workspace, else a new entry,
    the first one when no profile exists or the one -NewContributor creates.
    It never falls back to the only or the default entry. Export writes a
    schema-1 file for another machine; Import validates and merges one. Remove
    deletes an entry, the whole file, or only an orphaned or pending
    registration.

    Every write takes the profile lock, writes atomically, never lands under a
    git working tree, and supports -WhatIf. Run a write with -WhatIf first, show
    the preview, and run it again only after the contributor approves it.

.PARAMETER Action
    Get, Set, Export, Import, or Remove.

.PARAMETER WorkspacePath
    The workspace whose Knowledge areas the report and the sentence use, and
    whose git address selects the entry. Defaults to the current location.

.PARAMETER Contributor
    An entry id or alias. It must name exactly one entry; anything else fails
    before any write.

.PARAMETER NewContributor
    With Set: creates the caller's own entry with a new id, taking the git
    address of the workspace as its first alias. Beside other entries it needs
    an alias, from git or from -AddAlias, or -Default, because the hooks select
    entries by git address. Excludes -Contributor.

.PARAMETER KnowledgeArea
    The Knowledge areas to rate, paired in order with -Level. The area-name
    rule applies. Several pairs are saved in one write.

.PARAMETER Level
    new, familiar, or expert, one for each -KnowledgeArea.

.PARAMETER State
    On or Off. Off is the sticky, reversible opt-out; levels are kept.

.PARAMETER AddAlias
    Email addresses to add to the entry. One alias selects at most one entry.

.PARAMETER RemoveAlias
    Email addresses to remove from the entry.

.PARAMETER Default
    Marks the entry as the one used when no alias matches.

.PARAMETER SnoozeInterview
    Records "not now": no interview offer on this entry for 14 days.

.PARAMETER Path
    The file Export writes or Import reads.

.PARAMETER RegistrationOnly
    With Remove: deletes only an orphaned registration file, or clears a
    pending registration whose file never arrived.

.PARAMETER ShowAliases
    With Get: shows aliases unmasked.

.EXAMPLE
    & ./ContributorProfile.ps1 -Action Get -WorkspacePath .

.EXAMPLE
    & ./ContributorProfile.ps1 -Action Set -KnowledgeArea 'Kerberos' -Level new -WhatIf

.EXAMPLE
    & ./ContributorProfile.ps1 -Action Set -NewContributor -AddAlias 'cy@example.com' -KnowledgeArea 'Kerberos' -Level new -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Set', 'Export', 'Import', 'Remove')]
    [System.String]
    $Action,

    [Parameter()]
    [System.String]
    $WorkspacePath,

    [Parameter()]
    [System.String]
    $Contributor,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $NewContributor,

    [Parameter()]
    [System.String[]]
    $KnowledgeArea,

    [Parameter()]
    [ValidateSet('new', 'familiar', 'expert')]
    [System.String[]]
    $Level,

    [Parameter()]
    [ValidateSet('On', 'Off')]
    [System.String]
    $State,

    [Parameter()]
    [System.String[]]
    $AddAlias,

    [Parameter()]
    [System.String[]]
    $RemoveAlias,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $Default,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $SnoozeInterview,

    [Parameter()]
    [System.String]
    $Path,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $RegistrationOnly,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $ShowAliases
)

$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'ContributorProfileCommon.ps1')

$location = Resolve-ContributorProfileLocation
$workspace = if ($PSBoundParameters.ContainsKey('WorkspacePath'))
{
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspacePath)
}
else
{
    (Get-Location).ProviderPath
}

$forward = @{}
foreach ($name in 'Contributor', 'NewContributor', 'KnowledgeArea', 'Level', 'State', 'AddAlias', 'RemoveAlias', 'Default', 'SnoozeInterview', 'RegistrationOnly', 'ShowAliases')
{
    if ($PSBoundParameters.ContainsKey($name))
    {
        $forward[$name] = $PSBoundParameters[$name]
    }
}

function Select-ContributorForward
{
    param ([hashtable] $Source, [string[]] $Name)

    $selected = @{}
    foreach ($key in $Name)
    {
        if ($Source.ContainsKey($key))
        {
            $selected[$key] = $Source[$key]
        }
    }

    return $selected
}

switch ($Action)
{
    'Get'
    {
        $arguments = Select-ContributorForward -Source $forward -Name 'ShowAliases'
        Get-ContributorProfileReport -Location $location -WorkspacePath $workspace @arguments
    }

    'Set'
    {
        $arguments = Select-ContributorForward -Source $forward -Name 'Contributor', 'NewContributor', 'KnowledgeArea', 'Level', 'State', 'AddAlias', 'RemoveAlias', 'Default', 'SnoozeInterview'
        Set-ContributorProfile -Location $location -WorkspacePath $workspace @arguments
    }

    'Export'
    {
        if ([System.String]::IsNullOrWhiteSpace($Path))
        {
            throw 'Export needs -Path.'
        }

        $arguments = Select-ContributorForward -Source $forward -Name 'Contributor'
        Export-ContributorProfile -Location $location -Path $Path @arguments
    }

    'Import'
    {
        if ([System.String]::IsNullOrWhiteSpace($Path))
        {
            throw 'Import needs -Path.'
        }

        Import-ContributorProfile -Location $location -Path $Path
    }

    'Remove'
    {
        $arguments = Select-ContributorForward -Source $forward -Name 'Contributor', 'RegistrationOnly'
        Remove-ContributorProfile -Location $location @arguments
    }
}
