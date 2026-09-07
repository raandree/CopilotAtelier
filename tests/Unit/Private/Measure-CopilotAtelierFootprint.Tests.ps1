BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    function New-FootprintFixture
    {
        param ([Parameter(Mandatory = $true)] [System.String] $Root)

        $map = @{
            rules    = Join-Path $Root 'com.github.copilot/rules'
            skills   = Join-Path $Root 'skills'
            agents   = Join-Path $Root 'com.github.copilot/agents'
            commands = Join-Path $Root 'com.github.copilot/commands'
            hooks    = Join-Path $Root 'com.github.copilot/hooks'
        }
        foreach ($path in $map.Values)
        {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        # A broadly scoped Instruction that loads on every turn.
        Set-Content -LiteralPath (Join-Path $map.rules 'broad.instructions.md') -Encoding utf8 -Value @(
            '---'
            'applyTo: "**"'
            'description: "always on"'
            '---'
            'Broad body content that is present every session.'
        )
        # A narrowly scoped Instruction that loads only for matching files.
        Set-Content -LiteralPath (Join-Path $map.rules 'narrow.instructions.md') -Encoding utf8 -Value @(
            '---'
            'applyTo: "**/*.ps1"'
            '---'
            'Only for PowerShell files.'
        )
        # A Skill: frontmatter is catalog metadata, the body is on demand.
        Set-Content -LiteralPath (Join-Path (New-Item -ItemType Directory -Path (Join-Path $map.skills 'demo') -Force).FullName 'SKILL.md') -Encoding utf8 -Value @(
            '---'
            'name: demo'
            'description: "A demo skill for footprint measurement."'
            '---'
            'On-demand body loaded only when the Skill triggers.'
        )
        Set-Content -LiteralPath (Join-Path (Join-Path $map.skills 'demo') 'reference.md') -Encoding utf8 -Value 'Reference material.'

        Set-Content -LiteralPath (Join-Path $map.agents 'role.agent.md') -Encoding utf8 -Value @('---'; 'description: role'; '---'; 'Agent body.')
        Set-Content -LiteralPath (Join-Path $map.commands 'task.prompt.md') -Encoding utf8 -Value 'Prompt body.'
        Set-Content -LiteralPath (Join-Path $map.hooks 'hooks.json') -Encoding utf8 -Value '{ "hooks": {} }'

        return $map
    }

    function Get-FrontmatterByte
    {
        param ([Parameter(Mandatory = $true)] [System.String] $Path)

        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char] 0xFEFF) { $text = $text.Substring(1) }
        $match = [regex]::Match($text, '^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(\r?\n|$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $match.Success) { return [long] 0 }
        return [long] [System.Text.Encoding]::UTF8.GetByteCount($match.Value)
    }
}

Describe 'Measure-CopilotAtelierFootprint' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:map = New-FootprintFixture -Root $script:root
        $script:directoryMap = [ordered] @{
            agents       = 'com.github.copilot/agents'
            instructions = 'com.github.copilot/rules'
            skills       = 'skills'
            prompts      = 'com.github.copilot/commands'
            hooks        = 'com.github.copilot/hooks'
        }
    }

    It 'Should classify always-loaded content as the broad Instruction plus Skill discovery metadata' {
        $expectedAlways = (Get-Item -LiteralPath (Join-Path $script:map.rules 'broad.instructions.md')).Length +
            (Get-FrontmatterByte -Path (Join-Path (Join-Path $script:map.skills 'demo') 'SKILL.md'))

        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        $result.Loading.AlwaysLoadedEstimateByte | Should -Be $expectedAlways
        $result.Loading.DiscoveryMetadataByte | Should -Be (Get-FrontmatterByte -Path (Join-Path (Join-Path $script:map.skills 'demo') 'SKILL.md'))
    }

    It 'Should route hook scripts to executed-not-loaded and never to loaded context' {
        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        $result.Loading.ExecutedNotLoadedByte | Should -Be (Get-Item -LiteralPath (Join-Path $script:map.hooks 'hooks.json')).Length
        @($result.Items | Where-Object { $_.DeployedDirectory -eq 'hooks' -and $_.AlwaysLoadedByte -ne 0 }) | Should -HaveCount 0
    }

    It 'Should preserve the total as the sum of the loading buckets' {
        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        ($result.Loading.AlwaysLoadedEstimateByte + $result.Loading.OnDemandEstimateByte + $result.Loading.ExecutedNotLoadedByte) |
            Should -Be $result.TotalByte
    }

    It 'Should not count the whole Skill catalog body as always-loaded context' {
        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        $skill = $result.Items | Where-Object { $_.RelativePath -eq 'skills/demo/SKILL.md' }
        $skill.OnDemandByte | Should -BeGreaterThan 0
        $skill.AlwaysLoadedByte | Should -Be $skill.DiscoveryMetadataByte
        $skill.AlwaysLoadedByte | Should -BeLessThan $skill.TotalByte
    }

    It 'Should report identical content as duplicate content, not duplicate injection' {
        Copy-Item -LiteralPath (Join-Path $script:map.agents 'role.agent.md') -Destination (Join-Path $script:map.agents 'role-copy.agent.md')

        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        @($result.DuplicateContentGroups) | Should -HaveCount 1
        $result.DuplicateContentGroups[0].FileCount | Should -Be 2
        @($result.Opportunities | Where-Object { $_.Code -eq 'DuplicateContent' }) | Should -HaveCount 1
    }

    It 'Should count Unicode text by UTF-8 byte length, not character count' {
        $unicode = 'Grüße — Ünïcödé ☃'
        Set-Content -LiteralPath (Join-Path (Join-Path $script:map.skills 'demo') 'unicode.md') -Encoding utf8 -Value $unicode -NoNewline

        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        $item = $result.Items | Where-Object { $_.RelativePath -eq 'skills/demo/unicode.md' }
        $item.TotalByte | Should -Be (Get-Item -LiteralPath (Join-Path (Join-Path $script:map.skills 'demo') 'unicode.md')).Length
        $item.TotalByte | Should -BeGreaterThan $unicode.Length
    }

    It 'Should tolerate malformed frontmatter and count it as body' {
        Set-Content -LiteralPath (Join-Path (New-Item -ItemType Directory -Path (Join-Path $script:map.skills 'broken') -Force).FullName 'SKILL.md') -Encoding utf8 -Value @('---'; 'description: never closed'; 'still body')

        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        $result.MalformedFrontmatter | Should -Contain 'skills/broken/SKILL.md'
        $broken = $result.Items | Where-Object { $_.RelativePath -eq 'skills/broken/SKILL.md' }
        $broken.FrontmatterByte | Should -Be 0
        $broken.BodyByte | Should -Be $broken.TotalByte
    }

    It 'Should tolerate a missing mapped directory' {
        Remove-Item -LiteralPath $script:map.commands -Recurse -Force

        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        ($result.Directories | Where-Object { $_.DeployedDirectory -eq 'prompts' }).FileCount | Should -Be 0
    }

    It 'Should tolerate an empty mapped directory' {
        Get-ChildItem -LiteralPath $script:map.agents -File | Remove-Item -Force

        $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        ($result.Directories | Where-Object { $_.DeployedDirectory -eq 'agents' }).FileCount | Should -Be 0
    }

    It 'Should produce identical results on repeated runs over the same content' {
        $first = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }
        $second = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
            Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
        }

        ($first | ConvertTo-Json -Depth 8) | Should -Be ($second | ConvertTo-Json -Depth 8)
    }

    Context 'Metadata trust and activation classification' {
        It 'Should treat an Instruction with no applyTo as unknown, not always-loaded' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'nometa.instructions.md') -Encoding utf8 -Value @('---'; 'description: "no scope declared"'; '---'; 'Body without a scope pattern.')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/nometa.instructions.md' }
            $item.LoadingClass | Should -Be 'UnknownInstruction'
            $item.AlwaysLoadedByte | Should -Be 0
            $item.UnknownByte | Should -Be $item.TotalByte
        }

        It 'Should treat an Instruction with an unclosed frontmatter fence as unknown, not always-loaded' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'unclosed.instructions.md') -Encoding utf8 -Value @('---'; 'applyTo: "**"'; 'body with no closing fence')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/unclosed.instructions.md' }
            $item.LoadingClass | Should -Be 'UnknownInstruction'
            $item.AlwaysLoadedByte | Should -Be 0
            $result.MalformedFrontmatter | Should -Contain 'instructions/unclosed.instructions.md'
        }

        It 'Should not trust a closed but unsupported applyTo block that is a YAML list' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'list.instructions.md') -Encoding utf8 -Value @('---'; 'applyTo:'; '  - "**"'; '  - "src/**"'; '---'; 'Body.')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/list.instructions.md' }
            $item.LoadingClass | Should -Be 'UnknownInstruction'
            $item.AlwaysLoadedByte | Should -Be 0
            $result.UnsupportedMetadata | Should -Contain 'instructions/list.instructions.md'
        }

        It 'Should not trust a folded scalar metadata value' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'folded.instructions.md') -Encoding utf8 -Value @('---'; 'applyTo: "**"'; 'description: >'; '  a folded'; '  description value'; '---'; 'Body.')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/folded.instructions.md' }
            $item.LoadingClass | Should -Be 'UnknownInstruction'
            $item.AlwaysLoadedByte | Should -Be 0
            $item.Description | Should -BeNullOrEmpty
            $result.UnsupportedMetadata | Should -Contain 'instructions/folded.instructions.md'
        }

        It 'Should still classify an explicit broad applyTo as always-applied' {
            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/broad.instructions.md' }
            $item.LoadingClass | Should -Be 'AlwaysAppliedInstruction'
            $item.AlwaysLoadedByte | Should -Be $item.TotalByte
        }

        It 'Should not trust an applyTo value with an unmatched quote' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'unmatched.instructions.md') -Encoding utf8 -Value @('---'; 'applyTo: "**'; '---'; 'Body with a malformed scope value.')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/unmatched.instructions.md' }
            $item.LoadingClass | Should -Be 'UnknownInstruction'
            $item.AlwaysLoadedByte | Should -Be 0
            $item.ApplyTo | Should -BeNullOrEmpty
            $result.UnsupportedMetadata | Should -Contain 'instructions/unmatched.instructions.md'
        }

        It 'Should not trust a frontmatter block with a duplicate applyTo key' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'duplicate.instructions.md') -Encoding utf8 -Value @('---'; 'applyTo: "**"'; 'applyTo: "src/**"'; '---'; 'Body with ambiguous duplicate scope keys.')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/duplicate.instructions.md' }
            $item.LoadingClass | Should -Be 'UnknownInstruction'
            $item.AlwaysLoadedByte | Should -Be 0
            $item.ApplyTo | Should -BeNullOrEmpty
            $result.UnsupportedMetadata | Should -Contain 'instructions/duplicate.instructions.md'
        }
    }

    Context 'Customization file-type recognition' {
        It 'Should treat a non-Instruction document under rules as ancillary disk footprint' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'README.md') -Encoding utf8 -Value 'Documentation, not an Instruction.'

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'instructions/README.md' }
            $item.LoadingClass | Should -Be 'AncillaryFile'
            $item.AlwaysLoadedByte | Should -Be 0
            $item.OnDemandByte | Should -Be 0
            $item.DiskFootprintByte | Should -Be $item.TotalByte
        }

        It 'Should treat a script or asset inside a Skill as ancillary, not a Skill reference' {
            Set-Content -LiteralPath (Join-Path (Join-Path $script:map.skills 'demo') 'helper.ps1') -Encoding utf8 -Value 'Write-Output 1'

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'skills/demo/helper.ps1' }
            $item.LoadingClass | Should -Be 'AncillaryFile'
            $item.OnDemandByte | Should -Be 0
            $item.DiskFootprintByte | Should -Be $item.TotalByte
        }

        It 'Should classify an agent body without claiming it was selected' {
            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'agents/role.agent.md' }
            $item.LoadingClass | Should -Be 'AgentBody'
            @($result.Items | Where-Object { $_.LoadingClass -eq 'SelectedAgent' }) | Should -HaveCount 0
        }

        It 'Should treat a README under agents as ancillary, not an agent body' {
            Set-Content -LiteralPath (Join-Path $script:map.agents 'README.md') -Encoding utf8 -Value 'Directory overview.'

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $item = $result.Items | Where-Object { $_.RelativePath -eq 'agents/README.md' }
            $item.LoadingClass | Should -Be 'AncillaryFile'
            $item.OnDemandByte | Should -Be 0
        }
    }

    Context 'Loading accounting across all buckets' {
        It 'Should preserve the total as the sum of the five loading buckets' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'README.md') -Encoding utf8 -Value 'Ancillary doc.'
            Set-Content -LiteralPath (Join-Path $script:map.rules 'nometa.instructions.md') -Encoding utf8 -Value @('---'; 'description: "no scope"'; '---'; 'Unknown applicability.')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $result.Loading.UnknownApplicabilityByte | Should -BeGreaterThan 0
            $result.Loading.DiskFootprintByte | Should -BeGreaterThan 0
            (
                $result.Loading.AlwaysLoadedEstimateByte +
                $result.Loading.OnDemandEstimateByte +
                $result.Loading.ExecutedNotLoadedByte +
                $result.Loading.UnknownApplicabilityByte +
                $result.Loading.DiskFootprintByte
            ) | Should -Be $result.TotalByte
        }
    }

    Context 'Filesystem boundary safety' {
        It 'Should skip a directory reparse point and report it without scanning its target' {
            $externalTarget = Join-Path $script:root 'external-target'
            New-Item -ItemType Directory -Path $externalTarget -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $externalTarget 'secret.md') -Encoding utf8 -Value 'External content that must never be scanned through a link.'
            $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path (Join-Path $script:map.skills 'linked') -Target $externalTarget | Out-Null

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            @($result.Items | Where-Object { $_.RelativePath -like 'skills/linked*' }) | Should -HaveCount 0
            $result.UnsafeEntries.RelativePath | Should -Contain 'skills/linked'
        }

        It 'Should skip a directory link whose target is outside the content root' {
            $outsideRoot = Join-Path $TestDrive ('outside-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $outsideRoot 'foreign.md') -Encoding utf8 -Value 'Content outside the content root.'
            $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path (Join-Path $script:map.agents 'escape') -Target $outsideRoot | Out-Null

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            @($result.Items | Where-Object { $_.RelativePath -like 'agents/escape*' }) | Should -HaveCount 0
            $result.UnsafeEntries.RelativePath | Should -Contain 'agents/escape'
        }

        It 'Should skip a file reparse point where file links are supported' {
            $probeTarget = Join-Path $script:root 'probe-target.txt'
            Set-Content -LiteralPath $probeTarget -Encoding utf8 -Value 'probe'
            $probeLink = Join-Path $script:root 'probe-link.txt'
            try
            {
                New-Item -ItemType SymbolicLink -Path $probeLink -Target $probeTarget -ErrorAction Stop | Out-Null
                Remove-Item -LiteralPath $probeLink -Force
            }
            catch
            {
                Set-ItResult -Skipped -Because 'file symbolic links require privilege on this host'
                return
            }

            $realFile = Join-Path $script:root 'link-target.md'
            Set-Content -LiteralPath $realFile -Encoding utf8 -Value 'Linked file body that must not be read through a link.'
            New-Item -ItemType SymbolicLink -Path (Join-Path $script:map.commands 'aliased.prompt.md') -Target $realFile -ErrorAction Stop | Out-Null

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            @($result.Items | Where-Object { $_.RelativePath -eq 'prompts/aliased.prompt.md' }) | Should -HaveCount 0
            $result.UnsafeEntries.RelativePath | Should -Contain 'prompts/aliased.prompt.md'
        }

        It 'Should refuse a selected content root that is itself a reparse point and read nothing through it' {
            $externalRoot = Join-Path $TestDrive ('ext-root-' + [guid]::NewGuid().ToString('N'))
            $externalMap = New-FootprintFixture -Root $externalRoot
            Set-Content -LiteralPath (Join-Path $externalMap.agents 'secret.agent.md') -Encoding utf8 -Value @('---'; 'description: secret'; '---'; 'External agent body that must never be read through a root link.')
            $linkedRoot = Join-Path $TestDrive ('linked-root-' + [guid]::NewGuid().ToString('N'))
            $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path $linkedRoot -Target $externalRoot | Out-Null

            {
                InModuleScope CopilotAtelier -Parameters @{ Root = $linkedRoot; DirectoryMap = $script:directoryMap } {
                    Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
                }
            } | Should -Throw -ExpectedMessage '*reparse point*'
        }

        It 'Should refuse an intermediate namespace directory that is a reparse point and read nothing through it' {
            $externalTree = Join-Path $TestDrive ('ext-tree-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $externalTree 'agents') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $externalTree 'agents/secret.agent.md') -Encoding utf8 -Value @('---'; 'description: secret'; '---'; 'External body reached only through an intermediate link.')

            Remove-Item -LiteralPath (Join-Path $script:root 'com.github.copilot') -Recurse -Force
            $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path (Join-Path $script:root 'com.github.copilot') -Target $externalTree | Out-Null

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            @($result.Items | Where-Object { $_.SourcePath -like '*secret.agent.md' }) | Should -HaveCount 0
            @($result.Items | Where-Object { $_.DeployedDirectory -eq 'agents' }) | Should -HaveCount 0
            $result.UnsafeEntries.DeployedDirectory | Should -Contain 'agents'
        }

        It 'Should refuse a mapped directory that escapes the content root via traversal and read nothing outside' {
            $outside = Join-Path $TestDrive ('traversal-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $outside 'leak.agent.md') -Encoding utf8 -Value @('---'; 'description: leak'; '---'; 'Outside content reached by a traversal map.')

            $traversalMap = [ordered] @{
                agents       = '../' + [System.IO.Path]::GetFileName($outside)
                instructions = 'com.github.copilot/rules'
                skills       = 'skills'
                prompts      = 'com.github.copilot/commands'
                hooks        = 'com.github.copilot/hooks'
            }

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $traversalMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            @($result.Items | Where-Object { $_.SourcePath -like '*leak.agent.md' }) | Should -HaveCount 0
            $result.UnsafeEntries.DeployedDirectory | Should -Contain 'agents'
        }
    }

    Context 'Advisory wording reflects potential, not observed, loading' {
        It 'Should describe a large broad Instruction as potential automatic loading, not observed per-turn loading' {
            Set-Content -LiteralPath (Join-Path $script:map.rules 'huge.instructions.md') -Encoding utf8 -Value @('---'; 'applyTo: "**"'; '---'; ('x' * 9000))

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $opportunity = @($result.Opportunities | Where-Object { $_.Code -eq 'LargeAlwaysAppliedInstruction' })
            $opportunity | Should -HaveCount 1
            $opportunity[0].Message | Should -Not -Match 'loads on every matching turn'
            $opportunity[0].Message | Should -Match 'potential|contingent|can be loaded'
        }

        It 'Should describe large Skill discovery metadata as potentially carried, not observed every session' {
            $bigDescription = 'd' * 1700
            Set-Content -LiteralPath (Join-Path (New-Item -ItemType Directory -Path (Join-Path $script:map.skills 'heavy') -Force).FullName 'SKILL.md') -Encoding utf8 -Value @('---'; 'name: heavy'; ('description: "' + $bigDescription + '"'); '---'; 'Body.')

            $result = InModuleScope CopilotAtelier -Parameters @{ Root = $script:root; DirectoryMap = $script:directoryMap } {
                Measure-CopilotAtelierFootprint -ContentPath $Root -DirectoryMap $DirectoryMap
            }

            $opportunity = @($result.Opportunities | Where-Object { $_.Code -eq 'LargeDiscoveryMetadata' })
            $opportunity | Should -HaveCount 1
            $opportunity[0].Message | Should -Not -Match 'carried in the catalog every session'
            $opportunity[0].Message | Should -Match 'potential|contingent|may be carried'
        }
    }
}
