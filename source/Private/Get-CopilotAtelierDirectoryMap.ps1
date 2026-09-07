function Get-CopilotAtelierDirectoryMap
{
    <#
        .SYNOPSIS
            Returns the deployed customization directory names and their source paths.

        .DESCRIPTION
            Every Copilot-specific component lives under the Agent Plugins 1.0
            client extension namespace, so the source layout no longer matches
            the deployed layout. This ordered map is the single source of truth
            for that translation, shared by the installer and the footprint
            report so they never drift apart.

        .OUTPUTS
            System.Collections.Specialized.OrderedDictionary

        .EXAMPLE
            Get-CopilotAtelierDirectoryMap

            Returns the deployed directory name to source relative path map.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param ()

    return [ordered] @{
        agents       = 'com.github.copilot/agents'
        instructions = 'com.github.copilot/rules'
        skills       = 'skills'
        prompts      = 'com.github.copilot/commands'
        hooks        = 'com.github.copilot/hooks'
    }
}
