function Get-CopilotAtelierPublishedVersion
{
    <#
        .SYNOPSIS
            Returns the version of a Find-Module result including its prerelease label.

        .DESCRIPTION
            PowerShellGet 2 reports a preview as one string in Version, such as
            6.1.0-preview0024. The PowerShellGet 3 compatibility module over
            PSResourceGet reports Version 6.1.0 and the label preview0024 in a
            separate Prerelease property. This command returns the version with
            its label for either shape, and the version alone for a release.

        .PARAMETER InputObject
            One result of Find-Module.

        .OUTPUTS
            System.String

        .EXAMPLE
            Find-Module -Name CopilotAtelier -AllowPrerelease | Get-CopilotAtelierPublishedVersion

            Returns 6.1.0-preview0024 under PowerShellGet 2 and PowerShellGet 3 alike.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [System.Object]
        $InputObject
    )

    process
    {
        $version = [System.String] $InputObject.Version
        $label = $InputObject.PSObject.Properties['Prerelease']

        if ($label -and -not [System.String]::IsNullOrWhiteSpace([System.String] $label.Value) -and $version -notmatch '-')
        {
            $version = '{0}-{1}' -f $version, ([System.String] $label.Value).Trim()
        }

        $version
    }
}
