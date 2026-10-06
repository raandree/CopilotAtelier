function Remove-CopilotAtelierContributorProfile
{
    <#
        .SYNOPSIS
            Deletes one entry of the private Contributor profile, the whole
            profile file, or only an orphaned or pending registration.

        .DESCRIPTION
            With -Contributor, removes that one entry; removing the last entry
            deletes the file. Without it, deletes the whole profile file, even
            one the reader cannot accept. Either way the registration file that
            re-sends levels after a compaction is removed when no entry on this
            machine is on and rates a Knowledge area any more.

            With -RegistrationOnly, removes only the registration file, for
            example after the profile was deleted by hand. A registration is
            deleted only when its record says this module created it and its
            bytes still match the hash the record holds, whichever template it
            came from; a foreign or modified file is named and never touched.
            The same switch clears a pending registration, a record whose file
            never arrived, such as one left by a crash or by a sync that never
            completed.

            The command asks for confirmation by default. Already-open chats
            keep the hooks they loaded until they are restarted.

        .PARAMETER Contributor
            An entry id or alias. It must name exactly one entry; anything else
            fails before any write.

        .PARAMETER RegistrationOnly
            Removes only the registration file ~/.copilot/hooks/contributor-profile.json,
            or clears a pending registration whose file never arrived.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Remove-CopilotAtelierContributorProfile -Contributor 'r.smith@contoso.com'

            Removes that person's entry and keeps every other entry.

        .EXAMPLE
            Remove-CopilotAtelierContributorProfile -RegistrationOnly

            Repairs a registration left behind by a profile that was deleted by
            hand.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'The wrapped contributor-profile function calls ShouldProcess once it knows what it would delete.'
    )]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Contributor,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $RegistrationOnly
    )

    $ErrorActionPreference = 'Stop'
    . (Get-CopilotAtelierContributorProfileScriptPath)

    $arguments = @{ Location = Resolve-ContributorProfileLocation }
    foreach ($name in 'Contributor', 'RegistrationOnly')
    {
        if ($PSBoundParameters.ContainsKey($name))
        {
            $arguments[$name] = $PSBoundParameters[$name]
        }
    }

    Remove-ContributorProfile @arguments
}
