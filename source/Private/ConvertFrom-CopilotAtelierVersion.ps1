function ConvertFrom-CopilotAtelierVersion
{
    <#
        .SYNOPSIS
            Splits a module version string into its numeric version and prerelease label.

        .DESCRIPTION
            Parses a version string as the PowerShell Gallery reports it, such as
            6.0.0 or 6.1.0-preview0024, into a System.Version and the prerelease
            label, which is empty for a stable release. Build metadata after a
            plus sign is ignored. A string that is not a version throws.

            The numeric part keeps the components the string has, so 6.1.0 stays
            6.1.0 and can be passed to Import-Module -RequiredVersion.

        .PARAMETER Version
            The version string to parse.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            ConvertFrom-CopilotAtelierVersion -Version '6.1.0-preview0024'

            Returns the Version 6.1.0 and the Prerelease label preview0024.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Version
    )

    $match = [System.Text.RegularExpressions.Regex]::Match(
        $Version.Trim(),
        '\A(?<number>[0-9]+(?:\.[0-9]+){1,3})(?:-(?<label>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z.-]+)?\z'
    )

    if (-not $match.Success)
    {
        throw "'$Version' is not a module version."
    }

    return [PSCustomObject] @{
        Version    = [System.Version] $match.Groups['number'].Value
        Prerelease = $match.Groups['label'].Value
    }
}
