function Update-CopilotAtelier
{
    <#
        .SYNOPSIS
            Updates the module from a PowerShell repository and redeploys the customizations.

        .DESCRIPTION
            Compares the installed module version with the newest version
            published to the repository, installs the newer version when there
            is one, and then deploys its customization content with
            Install-CopilotAtelier so the ~/.copilot discovery folders match the
            module that is now installed.

            Without AllowPrerelease the command considers stable releases only
            and names a newer preview, such as 6.1.0-preview0024, without
            installing it; when PowerShellGet cannot list previews, as the
            PowerShellGet 1.0.0.1 of Windows PowerShell 5.1 cannot, it says that
            previews were not checked. Versions are ordered with their prerelease
            labels, so a later preview follows an earlier one and a release
            follows its previews. The result reports PreviousVersion and Version
            with their labels in PreviousPrerelease and Prerelease, and
            NewerPrerelease names a newer preview that was not considered.

            Previews of one version share its module folder, so after an update
            the command checks that the imported module reports the version it
            asked for, and stops before deploying when it does not.

            The command updates the module and the deployed customizations only,
            never repository files such as CHANGELOG.md or .memory-bank.

            The command requires the module to be installed from a repository.
            When the commands were dot-sourced from a repository clone, update
            the clone with git and run Install-CopilotAtelier instead.

        .PARAMETER Repository
            The PowerShell repository to check. Defaults to PSGallery.

        .PARAMETER AllowPrerelease
            Also considers preview versions and installs the newest version,
            preview or release. Needs PowerShellGet 2 or later: the
            PowerShellGet 1.0.0.1 that Windows PowerShell 5.1 ships with cannot
            list previews.

        .PARAMETER TargetPath
            Explicit Canonical target passed to installation. Ambiguous OneDrive
            selection fails before querying the repository and never prompts.
            Not used with SkipDeployment.

        .PARAMETER Force
            Redeploys even when the installed version is already the newest one.

        .PARAMETER Repair
            Redeploys even without a newer version and passes Repair to
            Install-CopilotAtelier. Modified Owned files still in the payload
            are replaced without backup; untracked files are never overwritten.
            Cannot be combined with SkipDeployment. This command still queries
            the repository; use Install-CopilotAtelier -Repair for offline repair.

        .PARAMETER SkipDeployment
            Installs the newer module version but does not deploy it. Use it to
            stage an update and deploy later with Install-CopilotAtelier.

        .PARAMETER IncludeClaudeCodeLinks
            Passed through to Install-CopilotAtelier so the redeployment keeps
            the Claude Code and agentskills.io links.

        .PARAMETER InstallationProfile
            Passed through to Install-CopilotAtelier. Without it the redeployment
            keeps the Skill selection the deployment already records, so an
            update never silently re-expands a narrowed installation.

        .PARAMETER IncludeSkill
            Passed through to Install-CopilotAtelier. Adds Skills, and their
            declared dependencies, to the profile selection.

        .PARAMETER ExcludeSkill
            Passed through to Install-CopilotAtelier. Drops Skills from the
            selection; mandatory lifecycle and security Skills and Skills another
            selected Skill requires are refused before anything is written.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Update-CopilotAtelier -InformationAction Continue

            Updates from the PowerShell Gallery and redeploys the customizations.

        .EXAMPLE
            Update-CopilotAtelier -Force

            Redeploys the current version even when no newer version exists.

        .EXAMPLE
            Update-CopilotAtelier -AllowPrerelease -InformationAction Continue

            Updates to the newest version, previews included, and redeploys the customizations.

        .EXAMPLE
            Update-CopilotAtelier -TargetPath ~/CopilotAtelier -Repair -WhatIf

            Previews an update and repair at an explicitly selected destination.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Repository = 'PSGallery',

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $AllowPrerelease,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Repair,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipDeployment,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IncludeClaudeCodeLinks,

        [Parameter()]
        [ValidateSet('complete', 'engineering', 'research', 'document-processing')]
        [System.String]
        $InstallationProfile,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $IncludeSkill,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $ExcludeSkill
    )

    $ErrorActionPreference = 'Stop'

    if ($Repair -and $SkipDeployment)
    {
        throw '-Repair cannot be combined with -SkipDeployment.'
    }
    $module = $ExecutionContext.SessionState.Module

    if (-not $module)
    {
        throw 'Update-CopilotAtelier requires the module to be imported from an installed copy. Running from a repository clone? Update the clone with git and run Install-CopilotAtelier.'
    }

    $installedVersion = Get-CopilotAtelierModuleVersion
    $installed = ConvertFrom-CopilotAtelierVersion -Version $installedVersion

    $deploymentTarget = $null
    if (-not $SkipDeployment)
    {
        $pathParameters = @{ NonInteractive = $true }
        if ($PSBoundParameters.ContainsKey('TargetPath'))
        {
            $pathParameters.TargetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetPath)
        }
        $deploymentTarget = (Get-CopilotAtelierPath @pathParameters).TargetPath
    }

    $findParameters = @{
        Name       = $module.Name
        Repository = $Repository
    }

    # Named only when requested: PowerShellGet 1.0.0.1 rejects the parameter even as -AllowPrerelease:$false.
    if ($AllowPrerelease)
    {
        $findParameters.AllowPrerelease = $true
    }

    # PowerShellGet writes most failures as non-terminating errors, and this function's
    # ErrorActionPreference does not reach into another module, so each call names -ErrorAction.
    try
    {
        $availableModule = Find-Module @findParameters -ErrorAction Stop
    }
    catch
    {
        if ($AllowPrerelease -and $_.Exception -is [System.Management.Automation.ParameterBindingException])
        {
            throw "-AllowPrerelease needs PowerShellGet 2 or later to list previews; this session loads an older one, such as the PowerShellGet 1.0.0.1 that Windows PowerShell 5.1 ships with. Run 'Install-Module -Name PowerShellGet -Scope CurrentUser -Force -AllowClobber', then start a new session. Reported error: $($_.Exception.Message)"
        }

        throw "Unable to query repository '$Repository' for '$($module.Name)': $($_.Exception.Message)"
    }

    if (-not $availableModule)
    {
        throw "Unable to query repository '$Repository' for '$($module.Name)': the repository returned no version."
    }

    $availableVersion = Get-CopilotAtelierPublishedVersion -InputObject $availableModule
    $available = ConvertFrom-CopilotAtelierVersion -Version $availableVersion

    $newerPrerelease = $null
    if (-not $AllowPrerelease)
    {
        # Only a hint: an older PowerShellGet or a failed query must not stop a stable update.
        $previewModule = $null

        try
        {
            $previewModule = Find-Module @findParameters -AllowPrerelease -ErrorAction Stop
        }
        catch
        {
            if ($_.Exception -is [System.Management.Automation.ParameterBindingException])
            {
                Write-Information -MessageData 'Previews were not checked: this PowerShellGet cannot list them. PowerShellGet 2 or later can.'
            }
            else
            {
                Write-Verbose -Message "Unable to check '$Repository' for a newer preview: $($_.Exception.Message)"
            }
        }

        if ($previewModule)
        {
            try
            {
                $previewVersion = Get-CopilotAtelierPublishedVersion -InputObject $previewModule

                if ((ConvertFrom-CopilotAtelierVersion -Version $previewVersion).Prerelease -and
                    (Compare-CopilotAtelierVersion -Version $previewVersion -OtherVersion $installedVersion) -gt 0 -and
                    (Compare-CopilotAtelierVersion -Version $previewVersion -OtherVersion $availableVersion) -gt 0)
                {
                    $newerPrerelease = $previewVersion
                }
            }
            catch
            {
                Write-Verbose -Message "Unable to read the newest preview of '$Repository': $($_.Exception.Message)"
            }
        }
    }

    Write-Information -MessageData "Installed version: $installedVersion"
    Write-Information -MessageData "Available version: $availableVersion ($Repository)"

    $updated = $false

    if ((Compare-CopilotAtelierVersion -Version $availableVersion -OtherVersion $installedVersion) -gt 0)
    {
        if ($PSCmdlet.ShouldProcess($module.Name, "Update to version $availableVersion from '$Repository'"))
        {
            $updateParameters = @{
                Name            = $module.Name
                RequiredVersion = $availableVersion
                Force           = $true
            }

            if ($available.Prerelease)
            {
                $updateParameters.AllowPrerelease = $true
            }

            try
            {
                Update-Module @updateParameters -ErrorAction Stop
            }
            catch
            {
                throw "Unable to update '$($module.Name)' to $availableVersion. Install it with Install-Module so it can be updated in place. Reported error: $($_.Exception.Message)"
            }

            $updated = $true

            Write-Information -MessageData "Updated to version $availableVersion."
        }
    }
    elseif ($AllowPrerelease)
    {
        Write-Information -MessageData 'Already at the newest published version, previews included.'
    }
    else
    {
        Write-Information -MessageData 'No newer stable version is published.'
    }

    if ($newerPrerelease)
    {
        Write-Information -MessageData "A newer preview is published: $newerPrerelease. Run Update-CopilotAtelier -AllowPrerelease to install it."
    }

    $deployment = $null

    if ($SkipDeployment)
    {
        Write-Information -MessageData 'Skipped deployment as requested. Run Install-CopilotAtelier to deploy.'
    }
    elseif ($updated -or $Force -or $Repair)
    {
        # Import-Module takes the numeric version only; a preview is installed under it.
        $targetVersion = $installed.Version

        if ($updated)
        {
            $targetVersion = $available.Version
        }

        $updatedModule = Import-Module -Name $module.Name -RequiredVersion $targetVersion -Force -PassThru

        if ($updated)
        {
            # Previews of one version share its folder, so only the label shows whether the update landed.
            $importedVersion = Get-CopilotAtelierModuleVersion -Module $updatedModule
            if ($importedVersion -cne $availableVersion)
            {
                throw "Update-Module did not install $($availableVersion): '$($updatedModule.ModuleBase)' still holds $importedVersion. Close editors and other PowerShell sessions that use files there, then run Update-CopilotAtelier again."
            }
        }

        $installParameter = @{
            IncludeClaudeCodeLinks = $IncludeClaudeCodeLinks
            TargetPath = $deploymentTarget
            Repair = $Repair
            WhatIf = $WhatIfPreference
        }
        if ($PSBoundParameters.ContainsKey('Confirm'))
        {
            $installParameter.Confirm = $PSBoundParameters.Confirm
        }

        # Unbound selection parameters leave the recorded selection in place.
        foreach ($parameterName in @('InstallationProfile', 'IncludeSkill', 'ExcludeSkill'))
        {
            if ($PSBoundParameters.ContainsKey($parameterName))
            {
                $installParameter[$parameterName] = $PSBoundParameters[$parameterName]
            }
        }

        $deployment = & $updatedModule {
            param
            (
                [System.Collections.Hashtable]
                $InstallParameter
            )

            Install-CopilotAtelier @InstallParameter
        } $installParameter
    }
    else
    {
        Write-Information -MessageData 'Nothing to deploy. Use -Force to redeploy the current version.'
    }

    # Version and PreviousVersion stay System.Version for existing callers; the labels are additive.
    return [PSCustomObject] @{
        Name               = $module.Name
        PreviousVersion    = $installed.Version
        PreviousPrerelease = $installed.Prerelease
        Version            = $available.Version
        Prerelease         = $available.Prerelease
        Updated            = $updated
        NewerPrerelease    = $newerPrerelease
        Deployment         = $deployment
    }
}
