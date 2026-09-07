function Get-CopilotAtelierProfile
{
    <#
        .SYNOPSIS
            Lists the opt-in installation profiles and the Skills each one
            deploys from a customization payload.

        .DESCRIPTION
            Resolves every installation profile against the Skills a payload
            actually ships and reports the result without changing anything.
            Use it to see what -InstallationProfile would deploy before running
            Install-CopilotAtelier, to find the identifier of a Skill for
            -IncludeSkill or -ExcludeSkill, and to see which Skills are
            mandatory because the deployed Instructions and Custom agents load
            them by name.

            The complete profile is the default: an Install-CopilotAtelier run
            without a selection argument deploys every Skill in the payload, and
            passing -InstallationProfile complete returns a narrowed deployment
            to that state. Only a narrowing profile is validated against the
            payload's prerequisites, which PrerequisiteValidated reports; a
            narrowed profile this payload cannot satisfy is refused rather than
            reported as usable.

            The command reads files only. It does not contact the network,
            inspect an existing deployment, or change any setting. Use
            Test-CopilotAtelier to report the profile that is actually deployed.

        .PARAMETER Name
            One profile to report. Without it, every profile is returned in
            catalog order.

        .PARAMETER ContentPath
            The directory that holds the customization directories. Defaults to
            the module base, or the repository root when the source files are
            dot-sourced during development.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Get-CopilotAtelierProfile | Format-Table Name, SkillCount, Description

            Lists every installation profile and how many Skills it deploys.

        .EXAMPLE
            (Get-CopilotAtelierProfile -Name research).Skill

            Shows the Skills the research profile would deploy.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Position = 0)]
        [ValidateSet('complete', 'engineering', 'research', 'document-processing')]
        [System.String]
        $Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath
    )

    $ErrorActionPreference = 'Stop'

    if (-not $PSBoundParameters.ContainsKey('ContentPath'))
    {
        $ContentPath = Get-CopilotAtelierContentPath
    }

    $ContentPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ContentPath)

    if (-not (Test-Path -LiteralPath $ContentPath -PathType Container))
    {
        throw "The customization content path '$ContentPath' does not exist or is not a directory."
    }

    $catalog = Get-CopilotAtelierProfileCatalog

    $profileName = if ($PSBoundParameters.ContainsKey('Name'))
    {
        @($Name)
    }
    else
    {
        @($catalog.Profile.Keys)
    }

    foreach ($currentName in $profileName)
    {
        $selection = Resolve-CopilotAtelierSkillSelection -ContentPath $ContentPath -InstallationProfile $currentName

        [pscustomobject] @{
            Name = $selection.Profile
            Description = $catalog.Profile[$currentName].Description
            IsDefault = $selection.Profile -eq $catalog.DefaultProfile
            IsComplete = $selection.IsComplete
            PrerequisiteValidated = $selection.PrerequisiteValidated
            SkillCount = @($selection.Skill).Count
            Skill = @($selection.Skill)
            MandatorySkill = @($selection.MandatorySkill)
            AvailableSkillCount = @($selection.AvailableSkill).Count
            ContentPath = $ContentPath
        }
    }
}
