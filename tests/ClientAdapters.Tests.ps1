BeforeAll {
    $script:projectPath = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:representative = 'software-engineer'
    $script:agentPath = Join-Path $script:projectPath "com.github.copilot/agents/$script:representative.agent.md"
    $script:adapterRoot = Join-Path $script:projectPath 'output/clientAdapters'

    $script:contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }

    $script:variant = Get-CopilotAtelierClientAdapter -Name $script:representative -Client 'copilot-cli' `
        -ContentPath $script:projectPath
}

Describe 'Shipped VS Code profile against the Copilot CLI contract' -Tag 'Unit' {
    <#
        This is the mismatch the adapter exists for. The representative profile
        is authored in the VS Code shape and is discovered by the Copilot CLI
        from the same ~/.copilot/agents directory, but the documented CLI and
        cloud agent contract accepts neither the model priority array nor the
        product-qualified tool identifiers, and has no subagent allow-list.
    #>
    It 'Should declare a model priority array the Copilot CLI contract cannot accept' {
        $line = @(Get-Content -LiteralPath $script:agentPath -Encoding UTF8)
        $model = @($line | Where-Object -FilterScript { $_ -match '^model:' })

        $model.Count | Should -Be 1
        $model[0] | Should -Match "^model:\s*\["
        @([regex]::Matches($model[0], "'[^']+'")).Count |
            Should -BeGreaterOrEqual 2 -Because 'the VS Code fallback array must stay intact'

        $script:contract.Client['copilot-cli'].ModelShape | Should -Be 'SingleString'
    }

    It 'Should declare tool identifiers the Copilot CLI contract does not recognize' {
        $toolMap = $script:contract.Client['copilot-cli'].ToolMap
        $sourceTool = InModuleScope CopilotAtelier -Parameters @{ Path = $script:agentPath } {
            param ($Path)
            (ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'vscode').Tool
        }

        $unrecognized = @($sourceTool | Where-Object -FilterScript { -not $toolMap[$_] })

        $unrecognized.Count |
            Should -BeGreaterThan 0 -Because 'an unrecognized identifier is silently ignored by the client, which is a capability loss rather than an error'
        $unrecognized | Should -Contain 'useMcp'
    }

    It 'Should bound delegation with a subagent allow-list the Copilot CLI contract cannot express' {
        $line = @(Get-Content -LiteralPath $script:agentPath -Encoding UTF8)

        @($line | Where-Object -FilterScript { $_ -match '^agents:\s*\[' }).Count | Should -Be 1
        $script:contract.Client['copilot-cli'].UnsupportedField['agents'].Kind | Should -Be 'Restriction'
    }
}

Describe 'Copilot CLI variant of the representative profile' -Tag 'Unit' {
    It 'Should keep the shared workflow body byte for byte' {
        $sourceBody = InModuleScope CopilotAtelier -Parameters @{ Path = $script:agentPath } {
            param ($Path)
            (ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'vscode').Body
        }

        $script:variant.Body | Should -BeExactly $sourceBody
        $script:variant.Body | Should -Not -BeNullOrEmpty
    }

    It 'Should emit only documented client tool aliases' {
        foreach ($name in $script:variant.Tool)
        {
            $name |
                Should -BeIn @('agent', 'edit', 'execute', 'read', 'search', 'todo', 'web') -Because "'$name' must be a documented alias"
        }

        $script:variant.Tool | Should -Contain 'execute'
        $script:variant.Tool | Should -Contain 'read'
        $script:variant.Tool | Should -Contain 'edit'
        $script:variant.Tool | Should -Contain 'search'
    }

    It 'Should withhold delegation instead of inheriting it unrestricted' {
        $script:variant.Tool | Should -Not -Contain 'agent'
        $script:variant.WithheldTool | Should -Contain 'agent'
    }

    It 'Should keep every capability the shared body declares mandatory' {
        $script:variant.RequiredCapability | Should -Not -BeNullOrEmpty

        foreach ($capability in $script:variant.RequiredCapability)
        {
            $script:variant.Tool | Should -Contain $capability
        }
    }

    It 'Should report <Capability> as an unsupported capability' -ForEach @(
        @{ Capability = 'model' }
        @{ Capability = 'argument-hint' }
        @{ Capability = 'handoffs' }
        @{ Capability = 'agents' }
        @{ Capability = 'useMcp' }
        @{ Capability = 'runTests' }
        @{ Capability = 'execute/getTerminalOutput' }
    ) {
        $reported = @($script:variant.UnsupportedCapability | Where-Object -FilterScript { $_.Capability -eq $Capability })

        $reported | Should -Not -BeNullOrEmpty
        $reported[0].Reason | Should -Not -BeNullOrEmpty
    }

    It 'Should carry its client limitations inside the composed file' {
        <#
            The shared body promises an independent review on review: on and a
            four-stage chain on cycle: full. A file that travels without that
            limitation is a file that promises work this client cannot do.
        #>
        $script:variant.Preamble | Should -Not -BeNullOrEmpty
        $script:variant.Content | Should -Match 'review: on'
        $script:variant.Content | Should -Match 'cycle: full'
        $script:variant.Content | Should -Match '(?i)refuse'
        $script:variant.Content | Should -Match '(?i)VS Code'

        foreach ($workflow in @($script:variant.UnsupportedWorkflow))
        {
            $script:variant.Content | Should -Match ([regex]::Escape($workflow.Replace(':', ': ')))
        }
    }

    It 'Should keep the preamble boundary explicit and the shared body last' {
        $marker = '<!-- copilot-atelier:client-limitations:end'
        $endIndex = $script:variant.Content.IndexOf($marker)

        $endIndex | Should -BeGreaterThan 0
        $script:variant.Content.IndexOf('<!-- copilot-atelier:client-limitations:begin') |
            Should -BeLessThan $endIndex
        $script:variant.Content.EndsWith($script:variant.Body) |
            Should -BeTrue -Because 'everything after the end marker is the authoritative shared body'
    }

    It 'Should bind the boundary to the shared body hash so drift is detectable' {
        $expected = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($script:variant.Body))).Replace('-', '').ToLowerInvariant()

        $script:variant.SharedBodyHash | Should -Be $expected
        $script:variant.Content | Should -Match $expected

        $sourceBody = InModuleScope CopilotAtelier -Parameters @{ Path = $script:agentPath } {
            param ($Path)
            (ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'vscode').Body
        }

        $script:variant.Body |
            Should -BeExactly $sourceBody -Because 'the preamble is additive; it never edits the shared body'
    }

    It 'Should not claim the workflow runs unchanged on an unverified client' {
        $script:variant.VerificationState | Should -Be 'StructurallyChecked'
        $script:variant.VerifiedClientVersion | Should -BeNullOrEmpty
    }

    It 'Should emit frontmatter that carries no VS Code-only field' {
        $frontmatter = $script:variant.Frontmatter

        foreach ($field in @('model', 'argument-hint', 'handoffs', 'agents'))
        {
            $frontmatter.Contains($field) | Should -BeFalse -Because "'$field' is not part of the client contract"
        }

        $frontmatter['target'] | Should -Be 'github-copilot'
        $frontmatter['name'].Trim("'", '"') | Should -Be $script:representative
        $frontmatter['description'] | Should -Not -BeNullOrEmpty
    }

    It 'Should emit a well-formed frontmatter block that reparses to the same shape' {
        $reparsePath = Join-Path $TestDrive 'reparse.agent.md'
        [System.IO.File]::WriteAllText($reparsePath, $script:variant.Content, [System.Text.UTF8Encoding]::new($false))

        $reparsed = InModuleScope CopilotAtelier -Parameters @{ Path = $reparsePath } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'vscode'
        }

        $reparsed.Name | Should -Be $script:representative
        $reparsed.Body | Should -BeExactly ($script:variant.Preamble + $script:variant.Body)
        @($reparsed.Frontmatter.Keys) | Should -Be @($script:variant.Frontmatter.Keys)
    }
}

Describe 'Client adapter build artifact' -Tag 'Unit' {
    BeforeAll {
        $script:variantClient = @(
            $script:contract.Client.Keys |
                Where-Object -FilterScript { -not $script:contract.Client[$_].IsAuthoritativeSource }
        )
    }

    It 'Should emit a variant directory for every non-authoritative client' {
        Test-Path -LiteralPath $script:adapterRoot -PathType Container |
            Should -BeTrue -Because 'Build_Client_Adapter_Variants runs as part of the build task'

        foreach ($client in $script:variantClient)
        {
            Test-Path -LiteralPath (Join-Path $script:adapterRoot $client) -PathType Container |
                Should -BeTrue -Because $client
        }
    }

    It 'Should match a freshly composed variant byte for byte' {
        <#
            A stale artifact is a variant that no longer reflects the profile it
            was composed from, which is exactly the drift the single-source rule
            exists to prevent.
        #>
        foreach ($client in $script:variantClient)
        {
            foreach ($current in @(Get-CopilotAtelierClientAdapter -Client $client -ContentPath $script:projectPath))
            {
                $emitted = Join-Path (Join-Path $script:adapterRoot $client) $current.FileName

                Test-Path -LiteralPath $emitted -PathType Leaf | Should -BeTrue -Because $emitted

                ([System.IO.File]::ReadAllText($emitted) -replace "`r`n", "`n") |
                    Should -BeExactly $current.Content -Because "$emitted is stale; rerun the build"
            }
        }
    }

    It 'Should contain no variant for a profile outside the adapted rollout' {
        $adapted = @($script:contract.AdaptedAgent.Keys)

        foreach ($client in $script:variantClient)
        {
            $emitted = @(
                Get-ChildItem -LiteralPath (Join-Path $script:adapterRoot $client) -File -Filter '*.agent.md' |
                    ForEach-Object -Process { $_.Name -replace '\.agent\.md$', '' }
            )

            foreach ($name in $emitted)
            {
                $adapted | Should -Contain $name -Because "$client/$name is left over from an earlier rollout"
            }
        }
    }

    It 'Should mark the artifact directory as owned and list exactly what it generated' {
        <#
            The build removes what it wrote. The manifest is what makes that
            bounded: without it, a rebuild would be a recursive delete of a
            directory the build does not own.
        #>
        $manifestPath = Join-Path $script:adapterRoot '.copilot-atelier-adapter-manifest.json'

        Test-Path -LiteralPath $manifestPath -PathType Leaf |
            Should -BeTrue -Because 'the build task writes an ownership marker'

        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $manifest.owner | Should -Match 'CopilotAtelier'
        $manifest.schema | Should -Be 2

        $expected = @(
            foreach ($client in $script:variantClient)
            {
                foreach ($current in @(Get-CopilotAtelierClientAdapter -Client $client -ContentPath $script:projectPath))
                {
                    "$client/$($current.FileName)"
                }
            }
        )

        @($manifest.file).path | Sort-Object | Should -Be (@($expected) | Sort-Object)

        foreach ($entry in @($manifest.file))
        {
            $entry.sha256 |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $script:adapterRoot $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant() -Because 'ownership is proved by content, not by a file name'
        }
    }

    It 'Should never delete outside the directory it owns' {
        $taskPath = Join-Path $script:projectPath '.build/Build_Client_Adapter_Variants.build.ps1'
        $task = Get-Content -Raw -LiteralPath $taskPath -Encoding UTF8

        $task | Should -Match 'Export-CopilotAtelierClientAdapterArtifact'
        $task |
            Should -Match 'Assert-CopilotAtelierRegularPath' -Because 'the exporter guards every path component through the shared guard, which the task must dot-source'
        $task |
            Should -Not -Match 'Remove-Item[^\r\n]*-Recurse' -Because 'deletion is bounded by the ownership manifest, not by a recursive sweep'
    }
}

Describe 'Client adapter packaging isolation' -Tag 'Unit' {
    It 'Should not expose the variant output as a deployed directory' {
        $map = InModuleScope CopilotAtelier { Get-CopilotAtelierDirectoryMap }

        foreach ($sourceRelativePath in $map.Values)
        {
            $sourceRelativePath | Should -Not -Match 'clientAdapters'
        }
    }

    It 'Should not add the variant output to the distributed customization payload' {
        $buildConfiguration = Get-Content -Raw -LiteralPath (Join-Path $script:projectPath 'build.yaml') -Encoding UTF8

        $buildConfiguration | Should -Not -Match 'CustomizationDirectory[\s\S]*?clientAdapters'
    }

    It 'Should keep the composed variants out of the built module' {
        $moduleBase = (Get-Module -Name 'CopilotAtelier').ModuleBase

        Test-Path -LiteralPath (Join-Path $moduleBase 'clientAdapters') |
            Should -BeFalse -Because 'the plugin and module payloads carry the authoritative profiles only'

        $deployedAgent = @(
            Get-ChildItem -LiteralPath (Join-Path $moduleBase 'com.github.copilot/agents') -File -Filter '*.agent.md'
        )

        @($deployedAgent.Name | Group-Object | Where-Object -FilterScript { $_.Count -gt 1 }) |
            Should -BeNullOrEmpty -Because 'one agent name may resolve to exactly one discovered profile'
    }

    It 'Should not publish the variant output through the plugin channel' {
        <#
            The plugin channel installs the repository itself, so anything the
            repository tracks is published. output/ is build scratch and is
            excluded, which is what keeps a second profile out of the package.
        #>
        $ignore = Get-Content -Raw -LiteralPath (Join-Path $script:projectPath '.gitignore') -Encoding UTF8

        $ignore | Should -Match '(?m)^/?output/?\s*$'
    }
}

Describe 'Client adapter documentation' -Tag 'Unit' {
    BeforeAll {
        $script:readme = Get-Content -Raw -LiteralPath (Join-Path $script:projectPath 'README.md') -Encoding UTF8

        $sectionMatch = [regex]::Match($script:readme, '(?ms)^### Client-specific adapters\r?$.*?(?=^## )')
        $script:adapterSection = $sectionMatch.Value
    }

    It 'Should document the adapter command and its read-only scope' {
        $script:readme | Should -Match 'Get-CopilotAtelierClientAdapter'
    }

    It 'Should state that the composed variants are not deployed' {
        $script:readme | Should -Match '(?i)not deployed'
    }

    It 'Should keep the existing cross-client capability warning intact' {
        $script:readme | Should -Match '(?i)capabilit(?:y|ies).*vary.*client'
        $script:readme | Should -Match '(?i)product-specific tool'
        $script:readme | Should -Match '(?i)model priority'
    }

    It 'Should document the unsupported review and cycle workflows' {
        $script:adapterSection | Should -Not -BeNullOrEmpty
        $script:adapterSection | Should -Match 'review: on'
        $script:adapterSection | Should -Match 'cycle: full'
        $script:adapterSection | Should -Match '(?i)refuse'
    }

    It 'Should not claim a runtime verification the repository cannot show' {
        $script:adapterSection | Should -Not -Match '(?i)runtime.?verified'
        $script:adapterSection | Should -Not -Match '(?i)cloud agent'
    }
}
