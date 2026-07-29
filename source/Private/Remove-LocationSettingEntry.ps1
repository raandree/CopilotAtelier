function Remove-LocationSettingEntry
{
    <#
        .SYNOPSIS
            Removes named entries from a VS Code location-map setting.

        .DESCRIPTION
            Earlier releases registered the customization directories through
            chat.*FilesLocations. Those entries now duplicate the ~/.copilot
            discovery links, so they are removed while unrelated user-defined
            paths are preserved. A location map left empty is removed entirely.

        .PARAMETER Settings
            The parsed settings object to update in place.

        .PARAMETER PropertyName
            The name of the location-map setting to clean up.

        .PARAMETER Entry
            The path entries to remove.

        .OUTPUTS
            None.

        .EXAMPLE
            Remove-LocationSettingEntry -Settings $settings -PropertyName 'chat.agentFilesLocations' -Entry '~/CopilotAtelier/Agents'

            Drops one obsolete agent location and keeps every other entry.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Settings,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $PropertyName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $Entry
    )

    $property = $Settings.PSObject.Properties[$PropertyName]

    if (-not $property)
    {
        return
    }

    foreach ($entryName in $Entry)
    {
        if ($PSCmdlet.ShouldProcess($PropertyName, "Remove location entry '$entryName'"))
        {
            $property.Value.PSObject.Properties.Remove($entryName)
        }
    }

    if (@($property.Value.PSObject.Properties).Count -eq 0)
    {
        $Settings.PSObject.Properties.Remove($PropertyName)
    }
}
