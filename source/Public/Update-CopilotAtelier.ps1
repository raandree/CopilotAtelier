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

            The command requires the module to be installed from a repository.
            When the commands were dot-sourced from a repository clone, update
            the clone with git and run Install-CopilotAtelier instead.

        .PARAMETER Repository
            The PowerShell repository to check. Defaults to PSGallery.

        .PARAMETER Force
            Redeploys even when the installed version is already the newest one.

        .PARAMETER SkipDeployment
            Installs the newer module version but does not deploy it. Use it to
            stage an update and deploy later with Install-CopilotAtelier.

        .PARAMETER IncludeClaudeCodeLinks
            Passed through to Install-CopilotAtelier so the redeployment keeps
            the Claude Code and agentskills.io links.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Update-CopilotAtelier -InformationAction Continue

            Updates from the PowerShell Gallery and redeploys the customizations.

        .EXAMPLE
            Update-CopilotAtelier -Force

            Redeploys the current version even when no newer version exists.

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
        $Force,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipDeployment,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IncludeClaudeCodeLinks
    )

    $ErrorActionPreference = 'Stop'

    $module = $ExecutionContext.SessionState.Module

    if (-not $module)
    {
        throw 'Update-CopilotAtelier requires the module to be imported from an installed copy. Running from a repository clone? Update the clone with git and run Install-CopilotAtelier.'
    }

    $installedVersion = $module.Version

    try
    {
        $availableModule = Find-Module -Name $module.Name -Repository $Repository
    }
    catch
    {
        throw "Unable to query repository '$Repository' for '$($module.Name)': $($_.Exception.Message)"
    }

    $availableVersion = [System.Version] $availableModule.Version

    Write-Information -MessageData "Installed version: $installedVersion"
    Write-Information -MessageData "Available version: $availableVersion ($Repository)"

    $updated = $false

    if ($availableVersion -gt $installedVersion)
    {
        if ($PSCmdlet.ShouldProcess($module.Name, "Update to version $availableVersion from '$Repository'"))
        {
            try
            {
                Update-Module -Name $module.Name -RequiredVersion $availableVersion -Force
            }
            catch
            {
                throw "Unable to update '$($module.Name)' to $availableVersion. Install it with Install-Module so it can be updated in place. Reported error: $($_.Exception.Message)"
            }

            $updated = $true

            Write-Information -MessageData "Updated to version $availableVersion."
        }
    }
    else
    {
        Write-Information -MessageData 'Already at the newest published version.'
    }

    $deployment = $null

    if ($SkipDeployment)
    {
        Write-Information -MessageData 'Skipped deployment as requested. Run Install-CopilotAtelier to deploy.'
    }
    elseif ($updated -or $Force)
    {
        $targetVersion = $installedVersion

        if ($updated)
        {
            $targetVersion = $availableVersion
        }

        $updatedModule = Import-Module -Name $module.Name -RequiredVersion $targetVersion -Force -PassThru

        $installParameter = @{
            IncludeClaudeCodeLinks = $IncludeClaudeCodeLinks
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

    return [PSCustomObject] @{
        Name            = $module.Name
        PreviousVersion = $installedVersion
        Version         = $availableVersion
        Updated         = $updated
        Deployment      = $deployment
    }
}
