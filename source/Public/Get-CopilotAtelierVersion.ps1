function Get-CopilotAtelierVersion
{
    <#
        .SYNOPSIS
            Reports the installed module version and the deployed customization version.

        .DESCRIPTION
            Compares the version of the currently loaded CopilotAtelier module
            with the version recorded in the canonical target the last time
            Install-CopilotAtelier ran. Use it to find out whether a module
            update still needs to be deployed to the discovery folders.

            DeployedVersion is null when the target has never been written, and
            Version is null when the commands were dot-sourced from a repository
            clone instead of imported as a module.

            Prerelease is the label of a preview, such as preview0024, and empty
            for a release. DeployedVersion keeps the label it was deployed with,
            such as 6.1.0-preview0024, so IsCurrent is false when another preview
            of the same version is deployed.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Get-CopilotAtelierVersion

            Returns the module version, the deployed version, and whether they match.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param ()

    $path = Get-CopilotAtelierPath

    $moduleVersion = $null
    $prerelease = $null
    $loadedVersion = Get-CopilotAtelierModuleVersion

    if ($loadedVersion)
    {
        $parsedVersion = ConvertFrom-CopilotAtelierVersion -Version $loadedVersion
        $moduleVersion = $parsedVersion.Version
        $prerelease = $parsedVersion.Prerelease
    }

    $deployedVersion = $null
    $deployedOn = $null

    if (Test-Path -LiteralPath $path.DeploymentManifestPath -PathType Leaf)
    {
        try
        {
            $deployment = Get-Content -LiteralPath $path.DeploymentManifestPath -Raw |
                ConvertFrom-Json

            $deployedVersion = $deployment.Version

            if ($deployment.InstalledOn)
            {
                # ConvertFrom-Json turns the ISO 8601 stamp into a local DateTime.
                $deployedOn = ([System.DateTime] $deployment.InstalledOn).ToUniversalTime()
            }
        }
        catch
        {
            Write-Warning -Message "Unable to read the deployment record at '$($path.DeploymentManifestPath)': $($_.Exception.Message)"
        }
    }

    $isCurrent = $null

    if ($loadedVersion -and $deployedVersion)
    {
        $isCurrent = $loadedVersion -ceq [System.String] $deployedVersion
    }

    return [PSCustomObject] @{
        Version         = $moduleVersion
        Prerelease      = $prerelease
        DeployedVersion = $deployedVersion
        DeployedOn      = $deployedOn
        TargetPath      = $path.TargetPath
        IsCurrent       = $isCurrent
    }
}
