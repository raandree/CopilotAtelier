function Get-CopilotAtelierFootprint
{
    <#
        .SYNOPSIS
            Reports the loading footprint of a customization collection without
            modifying anything.

        .DESCRIPTION
            Produces an on-demand, read-only report of how the selected
            customization collection contributes to a Copilot session, and
            identifies concrete opportunities to reduce unnecessary loading. It
            reuses the shared directory map that Install-CopilotAtelier deploys,
            so the report and the installer never disagree about what ships.

            The report separates content a client may load automatically in a
            session, namely broadly scoped Instructions and the Skill discovery
            metadata a client may carry in the catalog, from content that loads
            only when a Custom agent is selected, a Skill is triggered, or a
            Prompt is invoked, and from hook scripts that execute rather than load
            as context. Automatic loading is potential and contingent on
            discovery and on whether the client applies the file; the report
            never counts the entire installed catalog as active session context.

            Every byte figure is a file-size estimate. It is not a measurement of
            what a model loaded, of remaining context, or of any billing or token
            use. On-demand content is reported as unknown applicability, not as
            proven activation. Identical content hashes report duplicate bytes on
            disk, which is not evidence of duplicate runtime injection.

            The command reads files only. It does not remove content, change
            settings, execute a hook, contact the network, or modify the
            installation, and its result does not depend on environment
            variables. Repeated runs over the same content return the same
            result. Use Test-CopilotAtelier for deployment, hash, and Discovery
            link health.

        .PARAMETER ContentPath
            The directory that holds the customization directories. Defaults to
            the module base, or the repository root when the source files are
            dot-sourced during development.

        .PARAMETER AsText
            Returns a deterministic, human-readable summary string instead of the
            structured report object.

        .OUTPUTS
            System.Management.Automation.PSCustomObject
            System.String

        .EXAMPLE
            Get-CopilotAtelierFootprint

            Returns the structured footprint report for the loaded collection.

        .EXAMPLE
            Get-CopilotAtelierFootprint -AsText

            Prints a human-readable footprint summary with reduction opportunities.

        .EXAMPLE
            (Get-CopilotAtelierFootprint).Opportunities | Format-Table Code, Severity, Message

            Lists the concrete opportunities to reduce unnecessary loading.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject], [System.String])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $AsText
    )

    $ErrorActionPreference = 'Stop'

    if (-not $PSBoundParameters.ContainsKey('ContentPath'))
    {
        $ContentPath = Get-CopilotAtelierContentPath
    }

    $ContentPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ContentPath)

    if (-not (Test-Path -LiteralPath $ContentPath -PathType Container))
    {
        throw "The customization content path '$ContentPath' does not exist or is not a directory."
    }

    $footprint = Measure-CopilotAtelierFootprint -ContentPath $ContentPath -DirectoryMap (Get-CopilotAtelierDirectoryMap)

    if (-not $AsText)
    {
        return $footprint
    }

    $formatByte = {
        param ([long] $Byte)
        if ($Byte -ge 1MB) { '{0:N1} MB' -f ($Byte / 1MB) }
        elseif ($Byte -ge 1KB) { '{0:N1} KB' -f ($Byte / 1KB) }
        else { "$Byte B" }
    }

    $line = [System.Collections.Generic.List[string]]::new()
    $line.Add('Customization footprint report')
    $line.Add("Content path: $($footprint.ContentPath)")
    $line.Add("Total on disk: $(& $formatByte $footprint.TotalByte)")
    $line.Add('')
    $line.Add('Session loading estimates (potential automatic loading, file sizes, contingent on discovery, not measured):')
    $line.Add("  Potential auto-load (est.) : $(& $formatByte $footprint.Loading.AlwaysLoadedEstimateByte)")
    $line.Add("    of which Skill catalog   : $(& $formatByte $footprint.Loading.DiscoveryMetadataByte)")
    $line.Add("  On demand when selected    : $(& $formatByte $footprint.Loading.OnDemandEstimateByte)")
    $line.Add("  Unknown applicability      : $(& $formatByte $footprint.Loading.UnknownApplicabilityByte)")
    $line.Add("  Executed, not loaded (hooks): $(& $formatByte $footprint.Loading.ExecutedNotLoadedByte)")
    $line.Add("  Disk footprint (not context): $(& $formatByte $footprint.Loading.DiskFootprintByte)")
    $line.Add('')
    $line.Add('Directories:')
    foreach ($directory in $footprint.Directories)
    {
        $line.Add(('  {0,-13} {1,4} files  {2}' -f $directory.DeployedDirectory, $directory.FileCount, (& $formatByte $directory.TotalByte)))
    }
    $line.Add('')
    $line.Add('Largest contributors:')
    if (@($footprint.LargestContributors).Count -eq 0)
    {
        $line.Add('  (none)')
    }
    foreach ($contributor in $footprint.LargestContributors)
    {
        $line.Add(('  {0,10}  {1}' -f (& $formatByte $contributor.TotalByte), $contributor.RelativePath))
    }
    $line.Add('')
    $line.Add('Opportunities to reduce unnecessary loading:')
    if (@($footprint.Opportunities).Count -eq 0)
    {
        $line.Add('  (none found)')
    }
    foreach ($item in $footprint.Opportunities)
    {
        $line.Add("  [$($item.Severity)] $($item.Code): $($item.Message)")
    }
    if (@($footprint.MalformedFrontmatter).Count -gt 0)
    {
        $line.Add('')
        $line.Add('Files with malformed frontmatter (counted as body, no metadata parsed):')
        foreach ($path in $footprint.MalformedFrontmatter)
        {
            $line.Add("  $path")
        }
    }
    if (@($footprint.UnsupportedMetadata).Count -gt 0)
    {
        $line.Add('')
        $line.Add('Files with unsupported metadata (no activation claim made):')
        foreach ($path in $footprint.UnsupportedMetadata)
        {
            $line.Add("  $path")
        }
    }
    if (@($footprint.UnsafeEntries).Count -gt 0)
    {
        $line.Add('')
        $line.Add('Unsafe entries skipped (reparse point or outside the content root, never followed):')
        foreach ($entry in $footprint.UnsafeEntries)
        {
            $line.Add("  $($entry.RelativePath)")
        }
    }
    $line.Add('')
    $line.Add($footprint.Disclaimer)

    return ($line -join [System.Environment]::NewLine)
}
