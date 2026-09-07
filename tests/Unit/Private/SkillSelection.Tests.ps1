BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:catalogFacts = InModuleScope CopilotAtelier {
        $catalog = Get-CopilotAtelierProfileCatalog

        [pscustomobject]@{
            ProfileName = @($catalog.Profile.Keys)
            MandatorySkill = @($catalog.MandatorySkill)
            DependencySource = @($catalog.Dependency.Keys)
        }
    }

    $script:skillName = @(
        (Get-ChildItem -LiteralPath (Join-Path $script:projectPath 'skills') -Directory).Name
    )

    $script:profileCase = @(
        $script:catalogFacts.ProfileName |
            ForEach-Object -Process { @{ ProfileName = $_ } }
    )

    $script:dependencyCase = @(
        InModuleScope CopilotAtelier {
            $catalog = Get-CopilotAtelierProfileCatalog

            foreach ($source in $catalog.Dependency.Keys)
            {
                foreach ($target in $catalog.Dependency[$source])
                {
                    @{ Source = $source; Target = $target }
                }
            }
        }
    )

    $script:mandatoryCase = @(
        $script:catalogFacts.MandatorySkill |
            ForEach-Object -Process { @{ SkillName = $_ } }
    )
}

Describe 'Installation profile catalog' -Tag 'Unit' {
    It 'Should offer the complete profile plus the three initial selections' {
        $script:catalogFacts.ProfileName |
            Should -Be @('complete', 'engineering', 'research', 'document-processing')
    }

    It 'Should expose every catalog profile through the Install-CopilotAtelier ValidateSet' {
        $validateSet = @(
            (Get-Command -Name Install-CopilotAtelier).Parameters['InstallationProfile'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        )

        $validateSet | Should -HaveCount 1
        @($validateSet[0].ValidValues) | Should -Be $script:catalogFacts.ProfileName
    }

    It 'Should name only Skills that exist in this catalog for profile <ProfileName>' -ForEach $script:profileCase {
        $declared = InModuleScope CopilotAtelier -Parameters @{ ProfileName = $ProfileName } {
            @((Get-CopilotAtelierProfileCatalog).Profile[$ProfileName].Skill)
        }

        foreach ($name in $declared)
        {
            $script:skillName | Should -Contain $name -Because "profile '$ProfileName' selects '$name'"
        }
    }

    It 'Should ground the mandatory Skill <SkillName> in a deployed Instruction or Custom agent' -ForEach $script:mandatoryCase {
        $script:skillName | Should -Contain $SkillName

        $referencePath = @(
            Get-ChildItem -LiteralPath (Join-Path $script:projectPath 'com.github.copilot/rules') -Filter '*.md' -File
            Get-ChildItem -LiteralPath (Join-Path $script:projectPath 'com.github.copilot/agents') -Filter '*.agent.md' -File
        )

        $referencing = @(
            $referencePath |
                Where-Object -FilterScript {
                    (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) -match [regex]::Escape($SkillName)
                }
        )

        $referencing | Should -Not -BeNullOrEmpty -Because 'a mandatory Skill must be one the deployed lifecycle or security content loads by name'
    }

    It 'Should ground the dependency <Source> -> <Target> in the source SKILL.md' -ForEach $script:dependencyCase {
        $script:skillName | Should -Contain $Source
        $script:skillName | Should -Contain $Target

        $body = Get-Content -LiteralPath (Join-Path $script:projectPath "skills/$Source/SKILL.md") -Raw -Encoding UTF8

        $body | Should -Match ([regex]::Escape($Target)) -Because 'a declared dependency must be one the Skill itself names'
    }

    It 'Should declare profile <ProfileName> already closed over its dependencies' -ForEach $script:profileCase {
        $unclosed = InModuleScope CopilotAtelier -Parameters @{ ProfileName = $ProfileName } {
            $catalog = Get-CopilotAtelierProfileCatalog
            $declared = @($catalog.Profile[$ProfileName].Skill) + @($catalog.MandatorySkill)
            $missing = [System.Collections.Generic.List[string]]::new()

            foreach ($name in $declared)
            {
                if (-not $catalog.Dependency.Contains($name))
                {
                    continue
                }

                foreach ($target in $catalog.Dependency[$name])
                {
                    if ($declared -notcontains $target)
                    {
                        $missing.Add("$name -> $target")
                    }
                }
            }

            @($missing)
        }

        $unclosed | Should -BeNullOrEmpty -Because 'a shipped profile must not need closure to become usable'
    }
}

Describe 'Resolve-CopilotAtelierSkillSelection' -Tag 'Unit' {
    BeforeAll {
        function Resolve-TestSelection
        {
            param
            (
                [System.Collections.Hashtable]
                $Parameter = @{}
            )

            InModuleScope CopilotAtelier -Parameters @{ ContentPath = $script:projectPath; Parameter = $Parameter } {
                Resolve-CopilotAtelierSkillSelection -ContentPath $ContentPath @Parameter
            }
        }
    }

    It 'Should select every available Skill by default' {
        $selection = Resolve-TestSelection

        $selection.Profile | Should -Be 'complete'
        $selection.IsComplete | Should -BeTrue
        @($selection.Skill) | Should -HaveCount $script:skillName.Count
    }

    It 'Should narrow the selection to the requested profile' {
        $selection = Resolve-TestSelection -Parameter @{ InstallationProfile = 'document-processing' }

        $selection.IsComplete | Should -BeFalse
        @($selection.Skill).Count | Should -BeLessThan $script:skillName.Count
        $selection.Skill | Should -Contain 'pdf-to-markdown'
        $selection.Skill | Should -Not -Contain 'sampler-framework'
    }

    It 'Should always keep the mandatory lifecycle and security Skills' {
        $selection = Resolve-TestSelection -Parameter @{ InstallationProfile = 'document-processing' }

        foreach ($name in $script:catalogFacts.MandatorySkill)
        {
            $selection.Skill | Should -Contain $name
        }
    }

    It 'Should pull the dependencies of an explicitly included Skill into the selection' {
        $selection = Resolve-TestSelection -Parameter @{
            InstallationProfile = 'research'
            IncludeSkill = @('mcp-builder', 'automatedlab-proxmox')
        }

        $selection.Skill | Should -Contain 'mcp-builder'
        $selection.Skill | Should -Contain 'automatedlab-proxmox'
        $selection.Skill | Should -Contain 'long-running-job-monitor'
    }

    It 'Should return a deterministic ordinal ordering' {
        $selection = Resolve-TestSelection -Parameter @{ InstallationProfile = 'engineering' }
        $sorted = [string[]] @($selection.Skill)
        [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)

        @($selection.Skill) | Should -Be $sorted
    }

    It 'Should reject the unknown identifier in <Parameter> with an actionable message' -ForEach @(
        @{ Parameter = 'IncludeSkill' }
        @{ Parameter = 'ExcludeSkill' }
    ) {
        { Resolve-TestSelection -Parameter @{ $Parameter = @('no-such-skill') } } |
            Should -Throw -ExpectedMessage "*Unknown Skill identifier*no-such-skill*Get-CopilotAtelierProfile*"
    }

    It 'Should reject excluding the mandatory Skill <SkillName>' -ForEach $script:mandatoryCase {
        { Resolve-TestSelection -Parameter @{ ExcludeSkill = @($SkillName) } } |
            Should -Throw -ExpectedMessage "*mandatory*$SkillName*"
    }

    It 'Should reject excluding a Skill that a selected Skill requires' {
        { Resolve-TestSelection -Parameter @{ InstallationProfile = 'engineering'; ExcludeSkill = @('pester-patterns') } } |
            Should -Throw -ExpectedMessage "*test-driven-development*requires*pester-patterns*"
    }

    It 'Should accept excluding a Skill together with its dependent' {
        $selection = Resolve-TestSelection -Parameter @{
            InstallationProfile = 'engineering'
            ExcludeSkill = @('pester-patterns', 'test-driven-development')
        }

        $selection.Skill | Should -Not -Contain 'pester-patterns'
        $selection.Skill | Should -Not -Contain 'test-driven-development'
        $selection.IsComplete | Should -BeFalse
    }

    It 'Should reject a Skill that is both included and excluded' {
        { Resolve-TestSelection -Parameter @{ IncludeSkill = @('grammar-check'); ExcludeSkill = @('grammar-check') } } |
            Should -Throw -ExpectedMessage '*both included and excluded*grammar-check*'
    }

    It 'Should reject an unknown installation profile' {
        { Resolve-TestSelection -Parameter @{ InstallationProfile = 'no-such-profile' } } |
            Should -Throw -ExpectedMessage '*Unknown installation profile*no-such-profile*'
    }

    It 'Should reject a dependency cycle in the catalog' {
        InModuleScope CopilotAtelier -Parameters @{ ContentPath = $script:projectPath } {
            Mock Get-CopilotAtelierProfileCatalog {
                [pscustomobject]@{
                    MandatorySkill = @('memory-bank')
                    Dependency = [ordered] @{
                        'grammar-check' = @('grill-me')
                        'grill-me' = @('doc-coauthoring')
                        'doc-coauthoring' = @('grammar-check')
                    }
                    Profile = [ordered] @{
                        complete = [pscustomobject]@{ Description = 'All'; IncludesEverySkill = $true; Skill = @() }
                    }
                }
            }

            { Resolve-CopilotAtelierSkillSelection -ContentPath $ContentPath } |
                Should -Throw -ExpectedMessage '*dependency cycle*grammar-check*'
        }
    }

    It 'Should ignore a catalog Skill that this payload does not ship' {
        $payloadPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        foreach ($name in @($script:catalogFacts.MandatorySkill) + @('sampler-framework'))
        {
            $skillPath = Join-Path $payloadPath "skills/$name"
            New-Item -ItemType Directory -Path $skillPath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillPath 'SKILL.md') -Value "# $name"
        }

        $selection = InModuleScope CopilotAtelier -Parameters @{ ContentPath = $payloadPath } {
            Resolve-CopilotAtelierSkillSelection -ContentPath $ContentPath -InstallationProfile 'engineering'
        }

        @($selection.Skill) | Should -Be @('agent-security-review', 'long-running-job-monitor', 'memory-bank', 'sampler-framework')
        $selection.Skill | Should -Not -Contain 'grill-me'
    }
}

Describe 'Skill selection prerequisites' -Tag 'Unit' {
    BeforeAll {
        function Initialize-SkillPayload
        {
            param
            (
                [System.String[]]
                $SkillName = @(),

                [System.String[]]
                $BareDirectory = @()
            )

            $payloadPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))

            foreach ($name in $SkillName)
            {
                $skillPath = Join-Path $payloadPath "skills/$name"
                New-Item -ItemType Directory -Path $skillPath -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $skillPath 'SKILL.md') -Value "# $name"
            }

            foreach ($name in $BareDirectory)
            {
                New-Item -ItemType Directory -Path (Join-Path $payloadPath "skills/$name") -Force | Out-Null
            }

            return $payloadPath
        }

        function Resolve-PayloadSelection
        {
            param
            (
                [System.String]
                $PayloadPath,

                [System.Collections.Hashtable]
                $Parameter = @{}
            )

            InModuleScope CopilotAtelier -Parameters @{ ContentPath = $PayloadPath; Parameter = $Parameter } {
                Resolve-CopilotAtelierSkillSelection -ContentPath $ContentPath @Parameter
            }
        }

        $script:mandatoryName = @($script:catalogFacts.MandatorySkill)
    }

    It 'Should refuse a narrowed selection when the payload omits a mandatory Skill' {
        $payloadPath = Initialize-SkillPayload -SkillName @('memory-bank', 'pdf-to-markdown')

        { Resolve-PayloadSelection -PayloadPath $payloadPath -Parameter @{ InstallationProfile = 'document-processing' } } |
            Should -Throw -ExpectedMessage '*does not ship the mandatory*agent-security-review*long-running-job-monitor*'
    }

    It 'Should refuse a selected Skill whose required Skill the payload omits' {
        $payloadPath = Initialize-SkillPayload -SkillName ($script:mandatoryName + @('test-driven-development'))

        { Resolve-PayloadSelection -PayloadPath $payloadPath -Parameter @{ IncludeSkill = @('test-driven-development') } } |
            Should -Throw -ExpectedMessage "*'test-driven-development' requires 'pester-patterns'*does not ship*"
    }

    It 'Should refuse an explicitly included directory without a SKILL.md entry point' {
        $payloadPath = Initialize-SkillPayload -SkillName $script:mandatoryName -BareDirectory @('not-a-skill')

        { Resolve-PayloadSelection -PayloadPath $payloadPath -Parameter @{ IncludeSkill = @('not-a-skill') } } |
            Should -Throw -ExpectedMessage '*not-a-skill*SKILL.md*'
    }

    It 'Should not select a directory without a SKILL.md entry point for a named profile' {
        $payloadPath = Initialize-SkillPayload -SkillName $script:mandatoryName -BareDirectory @('pdf-to-markdown')

        $selection = Resolve-PayloadSelection -PayloadPath $payloadPath -Parameter @{ InstallationProfile = 'document-processing' }

        $selection.Skill | Should -Not -Contain 'pdf-to-markdown'
        $selection.AvailableSkill | Should -Not -Contain 'pdf-to-markdown'
    }

    It 'Should keep deploying a reduced payload completely when nothing narrows it' {
        $payloadPath = Initialize-SkillPayload -SkillName @('pdf-to-markdown') -BareDirectory @('legacy-notes')

        $selection = Resolve-PayloadSelection -PayloadPath $payloadPath

        $selection.IsComplete | Should -BeTrue
        $selection.PrerequisiteValidated | Should -BeFalse -Because 'the compatibility path must not claim it validated the payload'
        @($selection.Skill) | Should -Be @('legacy-notes', 'pdf-to-markdown')
    }

    It 'Should report that a narrowed selection was validated against its prerequisites' {
        $payloadPath = Initialize-SkillPayload -SkillName ($script:mandatoryName + @('pdf-to-markdown'))

        $selection = Resolve-PayloadSelection -PayloadPath $payloadPath -Parameter @{ InstallationProfile = 'document-processing' }

        $selection.PrerequisiteValidated | Should -BeTrue
        $selection.Skill | Should -Contain 'pdf-to-markdown'
    }

    It 'Should validate prerequisites when only an exclusion narrows the complete profile' {
        $payloadPath = Initialize-SkillPayload -SkillName @('memory-bank', 'pdf-to-markdown')

        { Resolve-PayloadSelection -PayloadPath $payloadPath -Parameter @{ ExcludeSkill = @('pdf-to-markdown') } } |
            Should -Throw -ExpectedMessage '*does not ship the mandatory*'
    }
}
