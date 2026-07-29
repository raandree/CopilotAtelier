<#
    .SYNOPSIS
        Copies the Copilot customization directories into the built module.

    .DESCRIPTION
        The customization directories are the payload this module distributes.
        They stay at the repository root so the plugin manifest, the repository
        documentation, and a plain clone keep working, and this task copies them
        into the built module so a Gallery install ships identical content.
#>

# The standard Sampler task parameters are consumed by the dot-sourced
# Set-SamplerTaskVariable script block, which the analyzer cannot follow.
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
param
(
    [Parameter()]
    [System.String]
    $ProjectName = (property ProjectName ''),

    [Parameter()]
    [System.String]
    $SourcePath = (property SourcePath ''),

    [Parameter()]
    [System.String]
    $OutputDirectory = (property OutputDirectory (Join-Path -Path $BuildRoot -ChildPath 'output')),

    [Parameter()]
    [System.String]
    $BuiltModuleSubdirectory = (property BuiltModuleSubdirectory ''),

    [Parameter()]
    [System.String]
    $ModuleVersion = (property ModuleVersion ''),

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $VersionedOutputDirectory = (property VersionedOutputDirectory $true),

    [Parameter()]
    [System.String]
    $ReleaseNotesPath = (property ReleaseNotesPath (Join-Path -Path $OutputDirectory -ChildPath 'ReleaseNotes.md')),

    [Parameter()]
    [System.String[]]
    $CustomizationDirectory = (property CustomizationDirectory @()),

    [Parameter()]
    [System.Collections.Hashtable]
    $BuildInfo = (property BuildInfo @{ })
)

task Copy_Customizations_To_Output {
    . Set-SamplerTaskVariable

    if (-not $CustomizationDirectory)
    {
        $CustomizationDirectory = @(
            'Agents'
            'Instructions'
            'Skills'
            'Prompts'
            'Hooks'
            'Keybindings'
        )
    }

    Write-Build -Color DarkGray -Text "`tBuilt Module Base          = '$BuiltModuleBase'"

    foreach ($directoryName in $CustomizationDirectory)
    {
        $sourceDirectory = Join-Path -Path $BuildRoot -ChildPath $directoryName

        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container))
        {
            throw "The customization directory '$sourceDirectory' does not exist. Update CustomizationDirectory in build.yaml or restore the directory."
        }

        $destinationDirectory = Join-Path -Path $BuiltModuleBase -ChildPath $directoryName

        if (Test-Path -LiteralPath $destinationDirectory)
        {
            Remove-Item -LiteralPath $destinationDirectory -Recurse -Force
        }

        New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null

        Copy-Item -Path (Join-Path -Path $sourceDirectory -ChildPath '*') -Destination $destinationDirectory -Recurse -Force

        $fileCount = @(Get-ChildItem -LiteralPath $destinationDirectory -Recurse -File).Count

        Write-Build -Color Green -Text "`tCopied $directoryName ($fileCount file(s))"
    }
}
