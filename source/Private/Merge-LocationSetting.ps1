function Merge-LocationSetting
{
    <#
        .SYNOPSIS
            Merges entries into a VS Code location-map setting.

        .DESCRIPTION
            Location-map settings such as chat.promptFilesLocations are objects
            whose property names are paths. The merge preserves every path the
            user added by hand and only adds or overwrites the requested keys.

        .PARAMETER Settings
            The parsed settings object to update in place.

        .PARAMETER PropertyName
            The name of the location-map setting to merge into.

        .PARAMETER NewEntry
            The path-to-value entries to add or overwrite.

        .OUTPUTS
            None.

        .EXAMPLE
            Merge-LocationSetting -Settings $settings -PropertyName 'chat.promptFilesLocations' -NewEntry @{ '~/.copilot/prompts' = $true }

            Registers the prompt discovery path without discarding user entries.
    #>
    [CmdletBinding()]
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
        [ValidateNotNull()]
        [System.Collections.Hashtable]
        $NewEntry
    )

    $merged = [ordered] @{}

    if ($Settings.PSObject.Properties[$PropertyName])
    {
        foreach ($property in $Settings.$PropertyName.PSObject.Properties)
        {
            $merged[$property.Name] = $property.Value
        }
    }

    foreach ($key in $NewEntry.Keys)
    {
        $merged[$key] = $NewEntry[$key]
    }

    $Settings |
        Add-Member -NotePropertyName $PropertyName -NotePropertyValue ([PSCustomObject] $merged) -Force
}
