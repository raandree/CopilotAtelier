function Measure-CopilotAtelierFootprint
{
    <#
        .SYNOPSIS
            Measures the loading footprint of a customization content tree.

        .DESCRIPTION
            Walks each deployed customization directory under ContentPath, reads
            every file as bytes, and classifies how that file participates in a
            Copilot session. It separates content a client may load automatically
            (broadly scoped Instructions and the Skill discovery metadata a client
            may carry in the catalog) from content that loads only when a Custom
            agent is selected, a Skill is triggered, or a Prompt is invoked, from
            hook scripts that execute rather than load as context, from files
            whose applicability cannot be determined (an Instruction with missing,
            malformed, or unsupported scope metadata), and from ancillary
            documents, scripts, and binary assets that are disk footprint rather
            than model context. Automatic loading is potential and contingent on
            discovery and on whether the client applies the file; it is never a
            claim of observed activation.

            Only recognized customization file types receive a loading class.
            Scope metadata is trusted only from a closed frontmatter block of
            simple scalars, so a missing, malformed, or unsupported block never
            produces an activation claim. Reparse points and paths outside the
            content root are reported and never followed.

            Every byte figure is a file-size estimate. It is never a measurement
            of what a model actually loaded, how much remaining context exists,
            or any billing or token consumption. Identical content hashes report
            duplicate bytes on disk, which is not evidence of duplicate runtime
            injection. Unknown applicability (an on-demand body that a session
            may never load) is reported as unknown, not as active context.

            The function reads files only. It never writes, deletes, changes the
            environment, executes a hook, or contacts the network, and repeated
            runs over the same tree return the same result.

        .PARAMETER ContentPath
            The content root that holds the customization source directories.

        .PARAMETER DirectoryMap
            The deployed directory name to source relative path map, as returned
            by Get-CopilotAtelierDirectoryMap.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Measure-CopilotAtelierFootprint -ContentPath $content -DirectoryMap (Get-CopilotAtelierDirectoryMap)

            Returns the structured footprint for the content tree.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $DirectoryMap
    )

    # Advisory thresholds in bytes. They flag contributors worth review; they do
    # not measure runtime cost. Every Skill description may be carried in the
    # catalog for discovery each session, and the open standard caps that
    # description near 1 KB, so a frontmatter block much past that is a large
    # fixed catalog entry. A broad Instruction can be loaded on every matching
    # turn, so a large one is a large potential fixed cost.
    $largeDiscoveryMetadataByte = 1536
    $largeAlwaysAppliedByte = 8192
    $largeOnDemandBodyByte = 40960

    $utf8 = [System.Text.Encoding]::UTF8
    $frontmatterPattern = [regex]::new('^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(\r?\n|$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)

    # Recognized customization file suffixes per deployed directory. A file that
    # is not a recognized type (a README, a script, a binary asset) is ancillary
    # disk footprint, never model context. Skill reference documents that a Skill
    # body may pull in on demand are limited to plain text and Markdown.
    $skillReferenceSuffix = @('.md', '.markdown', '.txt')
    $hookExecutableSuffix = @('.json', '.ps1', '.psm1', '.psd1', '.sh', '.py', '.js', '.ts', '.cmd', '.bat')

    $items = [System.Collections.Generic.List[object]]::new()
    $directorySummary = [System.Collections.Generic.List[object]]::new()
    $unsafeEntries = [System.Collections.Generic.List[object]]::new()

    $contentRootFull = [System.IO.Path]::GetFullPath($ContentPath).TrimEnd([char[]] '\/')

    # Guard the selected content root itself before enumerating any mapped
    # directory. A reparse point at the selected root could otherwise redirect
    # the entire scan into an external tree, so refuse it outright rather than
    # measure content reached through it.
    Assert-CopilotAtelierRegularPath -LiteralPath $contentRootFull -RootPath $contentRootFull -ErrorAction Stop

    foreach ($deployedName in $DirectoryMap.Keys)
    {
        $sourceRoot = Join-Path -Path $ContentPath -ChildPath $DirectoryMap[$deployedName]
        $fileCount = 0
        $directoryByte = [long] 0
        if (Test-Path -LiteralPath $sourceRoot -PathType Container)
        {
            $sourceRootFull = [System.IO.Path]::GetFullPath($sourceRoot).TrimEnd([char[]] '\/')

            # Reuse the shared regular-path guard against the selected content
            # root so a symlink or junction is never followed and content
            # outside the selected root is never read. Enforcing the mapped root
            # against ContentPath inspects every intermediate namespace folder
            # and rejects a map value that escapes the root via traversal, not
            # just the mapped leaf. A guard failure marks the entry unsafe and
            # stops descent; cloud placeholders pass the guard and are measured.
            $rootIsSafe = $true
            try
            {
                Assert-CopilotAtelierRegularPath -LiteralPath $sourceRootFull -RootPath $contentRootFull -ErrorAction Stop
            }
            catch
            {
                $rootIsSafe = $false
                $unsafeEntries.Add([pscustomobject] @{
                        RelativePath      = $deployedName
                        DeployedDirectory = $deployedName
                        Reason            = $_.Exception.Message
                    })
            }

            $pendingDirectories = [System.Collections.Generic.Stack[string]]::new()
            if ($rootIsSafe)
            {
                $pendingDirectories.Push($sourceRootFull)
            }

            while ($pendingDirectories.Count -gt 0)
            {
                $currentDirectory = $pendingDirectories.Pop()
                foreach ($child in Get-ChildItem -LiteralPath $currentDirectory -Force -ErrorAction Stop | Sort-Object -Property FullName)
                {
                    $childRelative = $deployedName + '/' + $child.FullName.Substring($sourceRootFull.Length + 1).Replace([System.IO.Path]::DirectorySeparatorChar, '/')

                    try
                    {
                        Assert-CopilotAtelierRegularPath -LiteralPath $child.FullName -RootPath $sourceRootFull -ErrorAction Stop
                    }
                    catch
                    {
                        $unsafeEntries.Add([pscustomobject] @{
                                RelativePath      = $childRelative
                                DeployedDirectory = $deployedName
                                Reason            = $_.Exception.Message
                            })
                        continue
                    }

                    if ($child.PSIsContainer)
                    {
                        $pendingDirectories.Push($child.FullName)
                        continue
                    }

                    $file = $child
                    $relativePath = $childRelative
                    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                    $totalByte = [long] $bytes.Length
                    $sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '')

                    $text = $utf8.GetString($bytes)
                    if ($text.Length -gt 0 -and $text[0] -eq [char] 0xFEFF)
                    {
                        $text = $text.Substring(1)
                    }

                    $frontmatterByte = [long] 0
                    $hasMalformedFrontmatter = $false
                    $metadataUnsupported = $false
                    $applyTo = $null
                    $description = $null
                    if ($text.StartsWith('---'))
                    {
                        $match = $frontmatterPattern.Match($text)
                        if ($match.Success -and $match.Index -eq 0)
                        {
                            $frontmatterByte = [long] $utf8.GetByteCount($match.Value)

                            # Conservative supported-metadata contract: trust only
                            # a closed block of simple single-line scalars. A block
                            # or folded scalar, a sequence, a flow collection, an
                            # empty value, or any line we cannot parse means the
                            # block is unsupported, so no key is trusted and the
                            # file must not yield an activation claim.
                            $parsedApplyTo = $null
                            $parsedDescription = $null
                            $seenKey = [System.Collections.Generic.HashSet[string]]::new()
                            foreach ($line in $match.Groups[1].Value -split '\r?\n')
                            {
                                if ($line -match '^\s*$' -or $line -match '^\s*#')
                                {
                                    continue
                                }
                                if ($line -match '^\s*-\s')
                                {
                                    $metadataUnsupported = $true
                                    continue
                                }
                                if ($line -match '^\s*(?<key>[A-Za-z][A-Za-z0-9_-]*)\s*:\s*(?<value>.*?)\s*$')
                                {
                                    # A duplicate mapping key is ambiguous: a client
                                    # cannot know which value wins, so fail closed and
                                    # trust nothing from the block.
                                    if (-not $seenKey.Add($Matches.key))
                                    {
                                        $metadataUnsupported = $true
                                        continue
                                    }
                                    $rawValue = $Matches.value
                                    if ($rawValue -match '^[|>][+-]?[0-9]*\s*$')
                                    {
                                        $metadataUnsupported = $true
                                        continue
                                    }
                                    $trimmedValue = $rawValue.Trim()
                                    if ($trimmedValue.Length -eq 0 -or $trimmedValue.StartsWith('[') -or $trimmedValue.StartsWith('{'))
                                    {
                                        $metadataUnsupported = $true
                                        continue
                                    }
                                    # A quoted scalar must open and close with the same
                                    # quote and contain no unescaped inner occurrence of
                                    # it; a leading or trailing quote with no matching
                                    # partner is ambiguous. A blind trim would silently
                                    # accept such malformed text, so reject it instead.
                                    $firstChar = $trimmedValue[0]
                                    $lastChar = $trimmedValue[$trimmedValue.Length - 1]
                                    if ($firstChar -eq "'" -or $firstChar -eq '"')
                                    {
                                        $inner = if ($trimmedValue.Length -ge 2) { $trimmedValue.Substring(1, $trimmedValue.Length - 2) } else { '' }
                                        if ($trimmedValue.Length -lt 2 -or $lastChar -ne $firstChar -or $inner.IndexOf($firstChar) -ge 0)
                                        {
                                            $metadataUnsupported = $true
                                            continue
                                        }
                                        $scalar = $inner
                                    }
                                    elseif ($lastChar -eq "'" -or $lastChar -eq '"')
                                    {
                                        $metadataUnsupported = $true
                                        continue
                                    }
                                    else
                                    {
                                        $scalar = $trimmedValue
                                    }
                                    if ($Matches.key -eq 'applyTo') { $parsedApplyTo = $scalar }
                                    elseif ($Matches.key -eq 'description') { $parsedDescription = $scalar }
                                    continue
                                }
                                # A continuation line or any other syntax we do not model.
                                $metadataUnsupported = $true
                            }
                            if (-not $metadataUnsupported)
                            {
                                $applyTo = $parsedApplyTo
                                $description = $parsedDescription
                            }
                        }
                        else
                        {
                            $hasMalformedFrontmatter = $true
                        }
                    }
                    $bodyByte = [long] [System.Math]::Max([long] 0, $totalByte - $frontmatterByte)
                    $isInstructionFile = $deployedName -eq 'instructions' -and $file.Name -like '*.instructions.md'
                    $metadataTrusted = -not $hasMalformedFrontmatter -and -not $metadataUnsupported
                    $suffix = $file.Extension.ToLowerInvariant()

                    # Unsupported metadata is only decision-relevant for an
                    # Instruction, whose activation depends on applyTo. A Skill,
                    # agent, or Prompt legitimately uses folded scalars and flow
                    # lists, and never derives an activation claim from metadata,
                    # so it is not reported as unsupported.
                    $reportUnsupportedMetadata = $isInstructionFile -and $metadataUnsupported

                    $alwaysLoadedByte = [long] 0
                    $discoveryByte = [long] 0
                    $onDemandByte = [long] 0
                    $executedByte = [long] 0
                    $unknownByte = [long] 0
                    $diskFootprintByte = [long] 0

                    switch ($deployedName)
                    {
                        'instructions'
                        {
                            if (-not $isInstructionFile)
                            {
                                $loadingClass = 'AncillaryFile'
                                $diskFootprintByte = $totalByte
                            }
                            elseif (-not $metadataTrusted -or $null -eq $applyTo)
                            {
                                # Missing, malformed, or unsupported scope metadata
                                # is not evidence of automatic loading.
                                $loadingClass = 'UnknownInstruction'
                                $unknownByte = $totalByte
                            }
                            else
                            {
                                $isBroad = @(
                                    $applyTo -split ',' |
                                        Where-Object -FilterScript { $_.Trim().Trim("'`"") -in @('**', '**/*') }
                                ).Count -gt 0
                                if ($isBroad)
                                {
                                    $loadingClass = 'AlwaysAppliedInstruction'
                                    $alwaysLoadedByte = $totalByte
                                }
                                else
                                {
                                    $loadingClass = 'ConditionalInstruction'
                                    $onDemandByte = $totalByte
                                }
                            }
                        }
                        'skills'
                        {
                            if ($file.Name -eq 'SKILL.md')
                            {
                                $loadingClass = 'SkillCatalogAndBody'
                                $discoveryByte = $frontmatterByte
                                $alwaysLoadedByte = $frontmatterByte
                                $onDemandByte = $bodyByte
                            }
                            elseif ($suffix -in $skillReferenceSuffix)
                            {
                                $loadingClass = 'SkillReference'
                                $onDemandByte = $totalByte
                            }
                            else
                            {
                                # A script or binary asset in a Skill folder is disk
                                # footprint, not necessarily model context.
                                $loadingClass = 'AncillaryFile'
                                $diskFootprintByte = $totalByte
                            }
                        }
                        'agents'
                        {
                            if ($file.Name -like '*.agent.md')
                            {
                                # One agent is selected per session and which one is
                                # unknown from disk, so this is unknown-applicability
                                # on-demand content, never a proven selection.
                                $loadingClass = 'AgentBody'
                                $onDemandByte = $totalByte
                            }
                            else
                            {
                                $loadingClass = 'AncillaryFile'
                                $diskFootprintByte = $totalByte
                            }
                        }
                        'prompts'
                        {
                            if ($file.Name -like '*.prompt.md')
                            {
                                $loadingClass = 'InvokedPrompt'
                                $onDemandByte = $totalByte
                            }
                            else
                            {
                                $loadingClass = 'AncillaryFile'
                                $diskFootprintByte = $totalByte
                            }
                        }
                        default
                        {
                            if ($suffix -in $hookExecutableSuffix)
                            {
                                $loadingClass = 'ExecutedHook'
                                $executedByte = $totalByte
                            }
                            else
                            {
                                $loadingClass = 'AncillaryFile'
                                $diskFootprintByte = $totalByte
                            }
                        }
                    }

                    $items.Add([pscustomobject] @{
                            RelativePath            = $relativePath
                            DeployedDirectory       = $deployedName
                            SourcePath              = $file.FullName
                            LoadingClass            = $loadingClass
                            TotalByte               = $totalByte
                            FrontmatterByte         = $frontmatterByte
                            BodyByte                = $bodyByte
                            AlwaysLoadedByte        = $alwaysLoadedByte
                            DiscoveryMetadataByte   = $discoveryByte
                            OnDemandByte            = $onDemandByte
                            ExecutedByte            = $executedByte
                            UnknownByte             = $unknownByte
                            DiskFootprintByte       = $diskFootprintByte
                            Sha256                  = $sha256
                            HasMalformedFrontmatter = $hasMalformedFrontmatter
                            MetadataUnsupported     = $reportUnsupportedMetadata
                            ApplyTo                 = $applyTo
                            Description             = $description
                        })
                    $fileCount++
                    $directoryByte += $totalByte
                }
            }
        }
        $directorySummary.Add([pscustomobject] @{
                DeployedDirectory = $deployedName
                SourcePath        = $DirectoryMap[$deployedName]
                FileCount         = $fileCount
                TotalByte         = $directoryByte
            })
    }

    $orderedItem = @($items | Sort-Object -Property RelativePath)

    $alwaysLoadedByte = [long] ($orderedItem | Measure-Object -Property AlwaysLoadedByte -Sum).Sum
    $discoveryMetadataByte = [long] ($orderedItem | Measure-Object -Property DiscoveryMetadataByte -Sum).Sum
    $onDemandByte = [long] ($orderedItem | Measure-Object -Property OnDemandByte -Sum).Sum
    $executedByte = [long] ($orderedItem | Measure-Object -Property ExecutedByte -Sum).Sum
    $unknownByte = [long] ($orderedItem | Measure-Object -Property UnknownByte -Sum).Sum
    $diskFootprintByte = [long] ($orderedItem | Measure-Object -Property DiskFootprintByte -Sum).Sum
    $totalByte = [long] ($orderedItem | Measure-Object -Property TotalByte -Sum).Sum

    $largestContributor = @(
        $orderedItem |
            Where-Object -FilterScript { $_.TotalByte -gt 0 } |
            Sort-Object -Property @{ Expression = 'TotalByte'; Descending = $true }, @{ Expression = 'RelativePath'; Descending = $false } |
            Select-Object -First 10 -Property RelativePath, DeployedDirectory, LoadingClass, TotalByte
    )

    $duplicateGroup = @(
        $orderedItem |
            Where-Object -FilterScript { $_.TotalByte -gt 0 } |
            Group-Object -Property Sha256 |
            Where-Object -FilterScript { $_.Count -gt 1 } |
            ForEach-Object -Process {
                [pscustomobject] @{
                    Sha256        = $_.Name
                    FileCount     = $_.Count
                    TotalByte     = [long] $_.Group[0].TotalByte
                    DuplicateByte = [long] ($_.Group[0].TotalByte * ($_.Count - 1))
                    Paths         = @($_.Group.RelativePath | Sort-Object)
                }
            } |
            Sort-Object -Property @{ Expression = 'DuplicateByte'; Descending = $true }, @{ Expression = 'Sha256'; Descending = $false }
    )

    $malformedPath = @($orderedItem | Where-Object -FilterScript { $_.HasMalformedFrontmatter } | Select-Object -ExpandProperty RelativePath | Sort-Object)
    $unsupportedMetadataPath = @($orderedItem | Where-Object -FilterScript { $_.MetadataUnsupported } | Select-Object -ExpandProperty RelativePath | Sort-Object)
    $orderedUnsafe = @($unsafeEntries | Sort-Object -Property RelativePath)

    $opportunity = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $orderedItem | Where-Object -FilterScript { $_.LoadingClass -eq 'AlwaysAppliedInstruction' -and $_.TotalByte -gt $largeAlwaysAppliedByte } | Sort-Object -Property @{ Expression = 'TotalByte'; Descending = $true }, RelativePath)
    {
        $opportunity.Add([pscustomobject] @{
                Code     = 'LargeAlwaysAppliedInstruction'
                Severity = 'Warning'
                Byte     = $item.TotalByte
                Paths    = @($item.RelativePath)
                Message  = "This broadly scoped Instruction is $([int] [System.Math]::Ceiling($item.TotalByte / 1KB)) KB and can be loaded automatically on every matching turn, contingent on the client honoring its scope. Narrow its applyTo or trim it to reduce the potential per-session context."
            })
    }
    foreach ($item in $orderedItem | Where-Object -FilterScript { $_.LoadingClass -eq 'SkillCatalogAndBody' -and $_.DiscoveryMetadataByte -gt $largeDiscoveryMetadataByte } | Sort-Object -Property @{ Expression = 'DiscoveryMetadataByte'; Descending = $true }, RelativePath)
    {
        $opportunity.Add([pscustomobject] @{
                Code     = 'LargeDiscoveryMetadata'
                Severity = 'Warning'
                Byte     = $item.DiscoveryMetadataByte
                Paths    = @($item.RelativePath)
                Message  = "This Skill's discovery metadata is $($item.DiscoveryMetadataByte) bytes and may be carried in the catalog for discovery each session, contingent on the client. Tighten the frontmatter description to shrink the potential always-present footprint."
            })
    }
    foreach ($group in $duplicateGroup)
    {
        $opportunity.Add([pscustomobject] @{
                Code     = 'DuplicateContent'
                Severity = 'Warning'
                Byte     = $group.DuplicateByte
                Paths    = $group.Paths
                Message  = "$($group.FileCount) files share identical content ($($group.TotalByte) bytes each). Identical bytes on disk are duplicate content, not proof of duplicate runtime injection; deduplicate the source if unintended."
            })
    }
    foreach ($item in $orderedItem | Where-Object -FilterScript { $_.LoadingClass -in @('SkillCatalogAndBody', 'SkillReference') -and $_.OnDemandByte -gt $largeOnDemandBodyByte } | Sort-Object -Property @{ Expression = 'OnDemandByte'; Descending = $true }, RelativePath)
    {
        $opportunity.Add([pscustomobject] @{
                Code     = 'LargeOnDemandBody'
                Severity = 'Information'
                Byte     = $item.OnDemandByte
                Paths    = @($item.RelativePath)
                Message  = "This on-demand Skill content is $([int] [System.Math]::Ceiling($item.OnDemandByte / 1KB)) KB when triggered. It is not loaded unless the Skill activates; split or reference it externally if it is rarely needed in full."
            })
    }

    return [pscustomobject] @{
        ContentPath            = ([System.IO.Path]::GetFullPath($ContentPath).TrimEnd([char[]] '\/'))
        TotalByte              = $totalByte
        Loading                = [pscustomobject] @{
            AlwaysLoadedEstimateByte = $alwaysLoadedByte
            DiscoveryMetadataByte    = $discoveryMetadataByte
            OnDemandEstimateByte     = $onDemandByte
            ExecutedNotLoadedByte    = $executedByte
            UnknownApplicabilityByte = $unknownByte
            DiskFootprintByte        = $diskFootprintByte
        }
        Directories            = @($directorySummary)
        Items                  = $orderedItem
        LargestContributors    = $largestContributor
        DuplicateContentGroups = $duplicateGroup
        Opportunities          = @($opportunity)
        MalformedFrontmatter   = $malformedPath
        UnsupportedMetadata    = $unsupportedMetadataPath
        UnsafeEntries          = $orderedUnsafe
        Disclaimer             = 'Byte figures are file-size estimates, not measured session loading, remaining context, or billing. Broad Instructions and Skill discovery metadata are potential automatic loading, not observed injection. On-demand, unknown, and ancillary content is reported by applicability, not proven activation. Identical hashes are duplicate content, not duplicate runtime injection. Reparse-point and out-of-boundary entries are reported and never followed.'
    }
}
