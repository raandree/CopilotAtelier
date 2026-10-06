function Import-CopilotAtelierContributorProfile
{
    <#
        .SYNOPSIS
            Validates a schema-1 Contributor profile file and merges it into the
            private profile on this machine.

        .DESCRIPTION
            Reads the file with the same strict validator the hooks use, then
            merges it: an imported entry matches the local entry with the same
            id, else the one entry that shares an alias with it, and is added
            otherwise. Per Knowledge area the newer updatedUtc wins and a tie
            keeps the local level; an area on one side only is kept. The opt-out
            state follows the newer stateUpdatedUtc, the later interview snooze
            wins, aliases form a union, and the default flag stays local.

            An ambiguous match, an alias that would belong to two entries, or a
            result over a cap refuses the whole file and writes nothing. -WhatIf
            reports how many entries would be merged and added. On a machine
            without the Canonical target the result is saved on this machine
            only, and the command says so.

        .PARAMETER Path
            The schema-1 file to import, as Export-CopilotAtelierContributorProfile
            writes it. It is only read.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Import-CopilotAtelierContributorProfile -Path .\contributor-profile.json -WhatIf

            Shows how the file would merge, without writing anything.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'The wrapped contributor-profile function calls ShouldProcess after it computes the merge.'
    )]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path
    )

    $ErrorActionPreference = 'Stop'
    . (Get-CopilotAtelierContributorProfileScriptPath)

    Import-ContributorProfile -Location (Resolve-ContributorProfileLocation) -Path ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
}
