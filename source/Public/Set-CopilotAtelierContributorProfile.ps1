function Set-CopilotAtelierContributorProfile
{
    <#
        .SYNOPSIS
            Saves Familiarity levels, the opt-out state, aliases, or the default
            flag in the private Contributor profile.

        .DESCRIPTION
            Changes one entry of the Contributor profile, the private file that
            keeps each contributor's Familiarity levels outside every
            repository. Without -Contributor, the git address configured in the
            current folder selects the entry by alias; without a match the only
            entry, else the default entry, applies. When the profile has no
            entry yet, or an unmatched address meets several entries without a
            default, a new entry is created with that address as its first
            alias.

            The write takes the profile lock, replaces the file atomically, and
            fails without writing when another writer holds the lock for five
            seconds or when the profile path lies inside a git working tree. A
            profile the reader cannot accept, such as one from a newer release,
            is never overwritten.

            The command also manages the registration file
            ~/.copilot/hooks/contributor-profile.json, which re-sends levels
            after a compaction. It exists exactly while an entry is on and rates
            a Knowledge area, and a file this command did not create is never
            touched. Sessions started afterwards pick up the change.

        .PARAMETER KnowledgeArea
            The Knowledge areas to rate, paired in order with -Level. A name has
            1 to 48 letters, digits, single spaces, and . + # / & ( ) -, and
            starts with a letter or a digit.

        .PARAMETER Level
            new, familiar, or expert, one for each -KnowledgeArea.

        .PARAMETER State
            On or Off. Off is the sticky, reversible opt-out: no level reaches
            any session, and the levels are kept for a later On.

        .PARAMETER AddAlias
            Email addresses that select this entry. One alias selects at most
            one entry, and an entry holds at most eight.

        .PARAMETER RemoveAlias
            Email addresses to remove from the entry.

        .PARAMETER Default
            Marks the entry as the one used when no alias matches, and clears
            the flag on every other entry.

        .PARAMETER Contributor
            An entry id or alias. It must name exactly one entry; anything else
            fails before any write.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Set-CopilotAtelierContributorProfile -KnowledgeArea 'Kerberos' -Level new

            Saves that the contributor wants Kerberos explained as to a
            newcomer, in every later session of a workspace that declares it.

        .EXAMPLE
            Set-CopilotAtelierContributorProfile -State Off -WhatIf

            Previews turning the profile off without writing anything.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'The wrapped contributor-profile function calls ShouldProcess after it computes the change, so -WhatIf previews the exact write.'
    )]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
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
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $AddAlias,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $RemoveAlias,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Default,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Contributor
    )

    $ErrorActionPreference = 'Stop'
    . (Get-CopilotAtelierContributorProfileScriptPath)

    $arguments = @{
        Location      = Resolve-ContributorProfileLocation
        WorkspacePath = (Get-Location).ProviderPath
    }

    foreach ($name in 'Contributor', 'KnowledgeArea', 'Level', 'State', 'AddAlias', 'RemoveAlias', 'Default')
    {
        if ($PSBoundParameters.ContainsKey($name))
        {
            $arguments[$name] = $PSBoundParameters[$name]
        }
    }

    Set-ContributorProfile @arguments
}
