BeforeAll {
    $script:repoRoot = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:manifestPath = Join-Path -Path $script:repoRoot -ChildPath 'plugin.json'
    $script:manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
}

Describe 'Agent plugin manifest' -Tag 'Unit' {
    It 'Should parse plugin.json as JSON' {
        { Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Should declare a name the plugin loaders accept' {
        # A slash, colon, or uppercase letter makes the plugin fail to load silently.
        $script:manifest.name | Should -Match '^[a-z0-9]+(-[a-z0-9]+)*$'
        $script:manifest.name.Length | Should -BeLessOrEqual 64
    }

    It 'Should carry the version of the most recent released changelog section' {
        <#
            VS Code and the GitHub Copilot CLI detect a plugin update from this
            field, and nothing in the build maintains it - GitVersion only sets
            the PowerShell module version. Without this assertion the manifest
            silently keeps announcing whichever release it was last edited for.
        #>
        $released = Get-Content -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'CHANGELOG.md') |
            Select-String -Pattern '^## \[(?<version>\d+\.\d+\.\d+)\]' |
            Select-Object -First 1

        $released | Should -Not -BeNullOrEmpty
        $script:manifest.version | Should -Be $released.Matches[0].Groups['version'].Value
    }

    It 'Should point the agents component path at the shipped custom agents' {
        $agentPath = Join-Path -Path $script:repoRoot -ChildPath $script:manifest.agents

        Test-Path -LiteralPath $agentPath -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $agentPath -Filter '*.agent.md' -File) | Should -Not -BeNullOrEmpty
    }

    It 'Should point the skills component path at the shipped skills' {
        $skillPath = Join-Path -Path $script:repoRoot -ChildPath $script:manifest.skills

        Test-Path -LiteralPath $skillPath -PathType Container | Should -BeTrue
        @(
            Get-ChildItem -LiteralPath $skillPath -Directory |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf }
        ) | Should -Not -BeNullOrEmpty
    }

    It 'Should not declare the Agent Plugins schema while the skills folder is capitalised' {
        <#
            Without $schema the manifest loads in the legacy Copilot format, where
            the agents and skills fields override the default component paths -
            which is the only reason the capital-S Skills folder is discovered.
            Agent Plugins 1.0 ignores those fields and reads skills solely from a
            lowercase ./skills, so adding the schema without renaming the folder
            drops every skill with no error.
        #>
        $declaresSchema = @($script:manifest.PSObject.Properties.Name) -contains '$schema'
        $hasLowercaseSkills = @(
            Get-ChildItem -LiteralPath $script:repoRoot -Directory |
                Where-Object { $_.Name -ceq 'skills' }
        ).Count -gt 0

        ($declaresSchema -and -not $hasLowercaseSkills) | Should -BeFalse
    }
}
