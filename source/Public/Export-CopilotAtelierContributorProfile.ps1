function Export-CopilotAtelierContributorProfile
{
    <#
        .SYNOPSIS
            Writes the private Contributor profile, or one entry of it, to a
            schema-1 file for import on another machine.

        .DESCRIPTION
            Machines without the synced Canonical target, such as a lab VM, a
            remote window, or a container, keep their own profile under
            LocalApplicationData. Export writes every entry, or only the one
            -Contributor names, to a file that
            Import-CopilotAtelierContributorProfile reads on the other machine.

            The destination must not lie inside a git working tree: the file
            holds Familiarity levels and aliases, and no Familiarity level may
            land in a repository. A profile the reader cannot accept is not
            exported.

        .PARAMETER Path
            The file to write. An existing file is replaced atomically.

        .PARAMETER Contributor
            An entry id or alias. It must name exactly one entry, which is then
            the only entry exported.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Export-CopilotAtelierContributorProfile -Path "$HOME/Documents/contributor-profile.json"

            Writes every entry to a file outside any repository.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'The wrapped contributor-profile function calls ShouldProcess after it validates the export.'
    )]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Contributor
    )

    $ErrorActionPreference = 'Stop'
    . (Get-CopilotAtelierContributorProfileScriptPath)

    $arguments = @{
        Location = Resolve-ContributorProfileLocation
        Path     = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    if ($PSBoundParameters.ContainsKey('Contributor'))
    {
        $arguments.Contributor = $Contributor
    }

    Export-ContributorProfile @arguments
}
