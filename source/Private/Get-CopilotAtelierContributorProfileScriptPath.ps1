function Get-CopilotAtelierContributorProfileScriptPath
{
    <#
        .SYNOPSIS
            Resolves the contributor-profile Skill script that the
            *-CopilotAtelierContributorProfile commands wrap.

        .DESCRIPTION
            The contributor-profile Skill ships inside the module, so the
            commands, the Skill, and the hooks run one implementation. A command
            dot-sources the returned path to define the shared functions in its
            own scope. Throws when the Skill is missing from the payload.

        .OUTPUTS
            System.String

        .EXAMPLE
            . (Get-CopilotAtelierContributorProfileScriptPath)

            Defines the contributor-profile functions in the calling command.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $path = Join-Path -Path (Get-CopilotAtelierContentPath) -ChildPath 'skills/contributor-profile/scripts/ContributorProfileCommon.ps1'

    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "The contributor-profile Skill is missing from '$path'. Reinstall the CopilotAtelier module."
    }

    return $path
}
