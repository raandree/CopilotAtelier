function Get-CopilotAtelierModuleVersion
{
    <#
        .SYNOPSIS
            Returns a module's version including its prerelease label.

        .DESCRIPTION
            PowerShell keeps a prerelease label outside ModuleVersion, in
            PrivateData.PSData.Prerelease of the module manifest, so the Version
            property of a module reads 6.1.0 for every 6.1.0 preview. This
            command returns the version with its label, such as
            6.1.0-preview0024, or the version alone for a stable release, so two
            previews of one version stay distinguishable.

            Without a module, as when the commands were dot-sourced from a
            repository clone, it returns nothing.

        .PARAMETER Module
            The module to read. Defaults to the module this command belongs to.

        .OUTPUTS
            System.String

        .EXAMPLE
            Get-CopilotAtelierModuleVersion

            Returns the loaded CopilotAtelier version, such as 6.1.0-preview0024.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.PSModuleInfo]
        $Module = $ExecutionContext.SessionState.Module
    )

    if ($null -eq $Module)
    {
        return
    }

    $prerelease = $null
    if ($Module.PrivateData -is [System.Collections.IDictionary] -and
        $Module.PrivateData['PSData'] -is [System.Collections.IDictionary])
    {
        $prerelease = [System.String] $Module.PrivateData['PSData']['Prerelease']
    }

    if ([System.String]::IsNullOrWhiteSpace($prerelease))
    {
        return $Module.Version.ToString()
    }

    return '{0}-{1}' -f $Module.Version, $prerelease.Trim()
}
