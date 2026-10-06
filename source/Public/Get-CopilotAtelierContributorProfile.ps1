function Get-CopilotAtelierContributorProfile
{
    <#
        .SYNOPSIS
            Reports the private Contributor profile: where it lives, the entry
            this machine selects and why, its Familiarity levels, and the exact
            sentence a workspace receives.

        .DESCRIPTION
            Follows the location rule of the contributor-profile Skill: the
            profile lives in the contributor folder of the Canonical target that
            ~/.copilot/hooks links to, and syncs with it through OneDrive, or on
            machines without that folder under LocalApplicationData on this
            machine only. The report names that location and whether it syncs,
            the entry the identity rule selects and why (alias, single, default,
            or none), its levels, any reason code that makes the profile
            unreadable, files beside it that may be OneDrive conflict copies,
            and the state of the registration file that re-sends levels after a
            compaction: none, owned, outdated (written from an earlier template;
            the next write replaces it), pending (its record arrived without the
            file), orphaned (no entry wants it any more), foreign, or modified.
            RegistrationConflictCopies names, with their full paths, files in
            the hooks folder that may be conflict copies of the registration,
            which the hosts would load as a second hook.

            With -WorkspacePath the report also shows the exact sentence the
            SessionStart hook injects for that workspace. This is the
            30-second check when a session did not know a saved level.

            Aliases are masked unless -ShowAliases, because a report an agent
            runs enters the model's context. The command changes nothing, not
            even a registration record.

        .PARAMETER WorkspacePath
            A workspace whose .memory-bank/projectbrief.md may declare Knowledge
            areas. The git address configured there selects the entry, and the
            report adds the sentence that workspace receives.

        .PARAMETER ShowAliases
            Shows the selected entry's aliases unmasked. Without it every alias
            is masked, for example r***@contoso.com.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Get-CopilotAtelierContributorProfile -WorkspacePath .

            Shows where the profile lives, the selected entry and its levels,
            and the sentence the current workspace receives at session start.

        .EXAMPLE
            (Get-CopilotAtelierContributorProfile).ConflictCopies

            Lists files beside profile.json that OneDrive may have created as
            conflict copies. They are never read as the profile or deleted.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $WorkspacePath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $ShowAliases
    )

    $ErrorActionPreference = 'Stop'
    . (Get-CopilotAtelierContributorProfileScriptPath)

    $workspace = $null
    if ($PSBoundParameters.ContainsKey('WorkspacePath'))
    {
        $workspace = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspacePath)
    }

    Get-ContributorProfileReport -Location (Resolve-ContributorProfileLocation) -WorkspacePath $workspace -ShowAliases:$ShowAliases
}
