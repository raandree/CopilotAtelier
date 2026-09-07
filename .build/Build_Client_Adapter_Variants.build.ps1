<#
    .SYNOPSIS
        Emits the client-specific Custom agent variants as a build artifact.

    .DESCRIPTION
        The VS Code profiles under com.github.copilot/agents are the only source
        of the shared workflow. This task composes the adapted profiles for
        every non-authoritative client through the allow-listed mapping and
        writes them under output/clientAdapters/<client>/.

        The output is deliberately outside the built module and outside the
        repository tree the plugin channel publishes, so a variant can never
        reach a discovery folder and register a second profile for the same
        agent. It is review and packaging evidence for the module and clone
        channels, not deployed content.

        The directory is owned rather than swept: an ownership manifest records
        exactly which files this task generated and the SHA-256 of each of them,
        so a rebuild removes only files that are still byte for byte what it
        wrote, and a directory the task does not own is refused instead of
        deleted. A variant left behind by a profile that is no longer adapted
        cannot survive as a stale artifact, and nothing else in output/ is at
        risk. Every path component along the way is checked by the shared
        regular-path guard, so a link at any level is refused rather than
        followed.
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
    [System.String]
    $ClientAdapterSubdirectory = (property ClientAdapterSubdirectory 'clientAdapters'),

    [Parameter()]
    [System.Collections.Hashtable]
    $BuildInfo = (property BuildInfo @{ })
)

task Build_Client_Adapter_Variants {
    . Set-SamplerTaskVariable

    <#
        Dot-sourcing the composer keeps the task from importing the built module
        while later tasks still rewrite its manifest.
    #>
    foreach ($functionPath in @(
            'Private/Get-CopilotAtelierReparseTag.ps1'
            'Private/Assert-CopilotAtelierRegularPath.ps1'
            'Private/Get-CopilotAtelierClientContract.ps1'
            'Private/Get-CopilotAtelierDirectoryMap.ps1'
            'Private/ConvertFrom-CopilotAtelierAgentFrontmatter.ps1'
            'Private/ConvertTo-CopilotAtelierAgentFrontmatter.ps1'
            'Private/ConvertTo-CopilotAtelierClientAgent.ps1'
            'Private/Export-CopilotAtelierClientAdapterArtifact.ps1'
            'Public/Get-CopilotAtelierClientAdapter.ps1'
        ))
    {
        . (Join-Path -Path $SourcePath -ChildPath $functionPath)
    }

    $adapterRoot = Join-Path -Path $OutputDirectory -ChildPath $ClientAdapterSubdirectory

    <#
        The value names a directory this task owns. Everything else about the
        deletion bound - direct child, reserved names, the shared regular-path
        guard on every path component, and the hashed ownership manifest that
        limits removal to unmodified generated files - is enforced by
        Export-CopilotAtelierClientAdapterArtifact.
    #>
    if ($ClientAdapterSubdirectory -notmatch '^[A-Za-z][A-Za-z0-9._-]*$')
    {
        throw "ClientAdapterSubdirectory must be a simple directory name, but was '$ClientAdapterSubdirectory'."
    }

    $contract = Get-CopilotAtelierClientContract

    $variantClient = @(
        $contract.Client.Keys |
            Where-Object -FilterScript { -not $contract.Client[$_].IsAuthoritativeSource }
    )

    Write-Build -Color DarkGray -Text "`tClient Adapter Root        = '$adapterRoot'"

    $variant = @(
        foreach ($client in $variantClient)
        {
            Get-CopilotAtelierClientAdapter -Client $client -ContentPath $BuildRoot
        }
    )

    $written = @(
        Export-CopilotAtelierClientAdapterArtifact -Path $adapterRoot -ParentPath $OutputDirectory -Variant $variant
    )

    foreach ($current in $variant)
    {
        Write-Build -Color Green -Text "`tComposed $($current.Client)/$($current.FileName) (tools: $($current.Tool -join ', '); withheld: $(if ($current.WithheldTool) { $current.WithheldTool -join ', ' } else { 'none' }); unsupported capabilities: $(@($current.UnsupportedCapability).Count); unsupported workflows: $($current.UnsupportedWorkflow -join ', '))"
    }

    Write-Build -Color DarkGray -Text "`tOwned Artifact Files       = $($written.Count)"
}
