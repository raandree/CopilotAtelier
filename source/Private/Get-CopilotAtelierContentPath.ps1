function Get-CopilotAtelierContentPath
{
    <#
        .SYNOPSIS
            Resolves the directory that holds the customization content.

        .DESCRIPTION
            The customization directories ship inside the module, so an
            installed module deploys from its own module base. When the source
            files are dot-sourced from a repository clone there is no module
            context and the repository root is used instead.

        .OUTPUTS
            System.String

        .EXAMPLE
            Get-CopilotAtelierContentPath

            Returns the module base, or the repository root during development.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $module = $ExecutionContext.SessionState.Module

    if ($module -and -not [System.String]::IsNullOrWhiteSpace($module.ModuleBase))
    {
        return $module.ModuleBase
    }

    # Dot-sourced from source/Private during development.
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
