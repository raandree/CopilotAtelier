BeforeDiscovery {
    $script:discoveryRepoRoot = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')

    <#
        A tag pointing at HEAD is exempt. On a tag push the test job runs before
        the deploy job, so at that instant the release tag exists and its
        changelog section cannot: Create_ChangeLog_GitHub_PR only runs after the
        release is published. Without the exemption every release would deadlock
        on its own gate. The exemption lapses as soon as one commit lands on top,
        so main stays red until the rollover pull request is merged.
    #>
    $script:releaseTagCase = @()
    $script:tagHistoryAvailable = $false

    if (Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue)
    {
        $allTag = @(& git -C $script:discoveryRepoRoot tag --list 2>$null)

        if ($LASTEXITCODE -eq 0 -and $allTag.Count -gt 0)
        {
            $script:tagHistoryAvailable = $true

            $tagAtHead = @(& git -C $script:discoveryRepoRoot tag --list --points-at HEAD 2>$null)

            $script:releaseTagCase = @(
                & git -C $script:discoveryRepoRoot tag --list --merged HEAD 2>$null |
                    Where-Object -FilterScript { $_ -match '^v\d+\.\d+\.\d+$' -and $_ -notin $tagAtHead } |
                    ForEach-Object -Process {
                        @{
                            Tag     = $_
                            Version = $_.Substring(1)
                        }
                    }
            )
        }
    }

    <#
        A checkout without tags cannot answer the question, which is legitimate on
        a developer machine working from an archive. In CI it is not: every job
        checks out with fetch-depth 0, so an absent tag list means the checkout
        changed, and skipping would turn this gate into a green build with nothing
        behind it - the same failure the skills-ref gate had.
    #>
    if ($env:CI -and -not $script:tagHistoryAvailable)
    {
        throw 'No git tag history is available, so the release provenance gate cannot run. CI must check out with fetch-depth 0.'
    }
}

BeforeAll {
    $script:repoRoot = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:manifestPath = Join-Path -Path $script:repoRoot -ChildPath 'plugin.json'
    $script:manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
    $script:changelogPath = Join-Path -Path $script:repoRoot -ChildPath 'CHANGELOG.md'
}

Describe 'Agent plugin manifest' -Tag 'Unit' {
    It 'Should parse plugin.json as JSON' {
        { Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Should declare a name the plugin loaders accept' {
        <#
            Agent Plugins 1.0 name rules: 1-64 characters, lowercase letters,
            digits, hyphens and periods only, alphanumeric at both ends, and no
            doubled separator. A slash, colon, or uppercase letter makes the
            plugin fail to load silently.
        #>
        $script:manifest.name | Should -MatchExactly '^[a-z0-9]([a-z0-9]|-(?!-)|\.(?!\.))*[a-z0-9]$|^[a-z0-9]$'
        $script:manifest.name.Length | Should -BeLessOrEqual 64
    }

    It 'Should carry the version of the most recent released changelog section' {
        <#
            VS Code and the GitHub Copilot CLI detect a plugin update from this
            field, and nothing in the build maintains it - GitVersion only sets
            the PowerShell module version. Without this assertion the manifest
            silently keeps announcing whichever release it was last edited for.
        #>
        $released = Get-Content -LiteralPath $script:changelogPath |
            Select-String -Pattern '^## \[(?<version>\d+\.\d+\.\d+)\]' |
            Select-Object -First 1

        $released | Should -Not -BeNullOrEmpty
        $script:manifest.version | Should -Be $released.Matches[0].Groups['version'].Value
    }

    It 'Should carry a plain major.minor.patch version with no pre-release identifier' {
        <#
            Settled on 2026-08-25 so it is not renegotiated. main always sits on a
            GitVersion pre-release (4.0.0-preview0007 at the time of writing), and
            the temptation is to mirror it here. Do not: this field is committed
            and only ever moves on a release rollover, so a pre-release value would
            announce a build that was never published. Plugin loaders also compare
            this field as an opaque string, where '4.0.0-preview0007' sorts after
            '4.0.0' and would suppress the update to the real release.
        #>
        $script:manifest.version | Should -MatchExactly '^\d+\.\d+\.\d+$'
    }

    It 'Should declare the canonical Agent Plugins 1.0 schema' {
        <#
            The $schema value is the format selector, not decoration. Without
            it the manifest loads in the legacy Copilot format, where component
            paths come from the agents and skills fields this package no longer
            declares - so every component would be looked up in the wrong place.
        #>
        $script:manifest.'$schema' |
            Should -Be 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
    }

    It 'Should declare only the fields the closed manifest schema permits' {
        <#
            The 1.0 manifest schema is closed. A client reports and ignores an
            unknown top-level field, so a stale component-path field such as
            'agents' or 'skills' does not fail the build - it silently does
            nothing, which is exactly the failure this assertion catches.
        #>
        $permitted = @(
            '$schema', 'name', 'version', 'description', 'author'
            'homepage', 'repository', 'license', 'keywords', 'extensions'
        )

        $unknown = @(
            $script:manifest.PSObject.Properties.Name |
                Where-Object -FilterScript { $permitted -notcontains $_ }
        )

        $unknown -join ', ' | Should -BeNullOrEmpty
    }

    It 'Should carry a description within the manifest limit' {
        $script:manifest.description | Should -Not -BeNullOrEmpty
        $script:manifest.description.Length | Should -BeLessOrEqual 1024
    }

    It 'Should discover skills from the portable root location' {
        <#
            Agent Plugins 1.0 reads skills only from a lowercase ./skills at the
            plugin root and the location cannot be overridden. The name is
            compared case-sensitively because a case-insensitive filesystem
            would otherwise let a capitalised folder pass here and drop every
            skill on Linux.
        #>
        $skillDirectory = @(
            Get-ChildItem -LiteralPath $script:repoRoot -Directory |
                Where-Object -FilterScript { $_.Name -ceq 'skills' }
        )

        $skillDirectory | Should -HaveCount 1

        @(
            Get-ChildItem -LiteralPath $skillDirectory[0].FullName -Directory |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf }
        ) | Should -Not -BeNullOrEmpty
    }

    It 'Should expose <Component> from the Copilot client-extension namespace' -ForEach @(
        @{ Component = 'agents'; RelativePath = 'com.github.copilot/agents'; Filter = '*.agent.md' }
        @{ Component = 'rules'; RelativePath = 'com.github.copilot/rules'; Filter = '*.instructions.md' }
        @{ Component = 'commands'; RelativePath = 'com.github.copilot/commands'; Filter = '*.prompt.md' }
    ) {
        <#
            Custom agents, rules, and slash commands are not portable 1.0
            component types. VS Code and the other Copilot clients read them
            from com.github.copilot/, and a client that does not own that
            namespace ignores it without rejecting the package.
        #>
        $componentPath = Join-Path -Path $script:repoRoot -ChildPath $RelativePath

        Test-Path -LiteralPath $componentPath -PathType Container | Should -BeTrue

        @(Get-ChildItem -LiteralPath $componentPath -File -Filter $Filter) |
            Should -Not -BeNullOrEmpty -Because "$Component must ship from the namespace directory"
    }

    It 'Should place the hook configuration where the 1.0 format expects it' {
        <#
            The Copilot format reads hooks.json at the plugin root; the 1.0
            format reads com.github.copilot/hooks/hooks.json. Declaring the
            schema without moving the file drops every hook with no error.
        #>
        $hookConfigPath = Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json'

        Test-Path -LiteralPath $hookConfigPath -PathType Leaf | Should -BeTrue

        $hookConfig = Get-Content -LiteralPath $hookConfigPath -Raw | ConvertFrom-Json

        @($hookConfig.hooks.PSObject.Properties.Name) | Should -Not -BeNullOrEmpty
    }

    It 'Should resolve hook scripts from the plugin root as well as the user profile' {
        <#
            A plugin is installed outside the workspace, so a hook command
            cannot use a relative path. The same file also ships to
            ~/.copilot/hooks through the module, so each command has to resolve
            both roots - PLUGIN_ROOT when the client sets it, the user profile
            otherwise. Losing either branch breaks one distribution path
            silently.
        #>
        $hookConfigPath = Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json'
        $hookConfig = Get-Content -LiteralPath $hookConfigPath -Raw | ConvertFrom-Json

        $command = @(
            foreach ($hookEvent in $hookConfig.hooks.PSObject.Properties)
            {
                foreach ($entry in $hookEvent.Value)
                {
                    $entry.command
                    $entry.windows
                }
            }
        )

        $command | Should -Not -BeNullOrEmpty

        foreach ($commandText in $command)
        {
            $commandText | Should -Match 'PLUGIN_ROOT'
            $commandText | Should -Match '\.copilot'
        }
    }
}

Describe 'Published release provenance' -Tag 'Unit' -Skip:(-not $script:tagHistoryAvailable) {
    <#
        Between 2026-08-01 and 2026-08-24 the repository published v3.0.0 and
        v3.1.0 while CHANGELOG.md still ended at [2.0.0], so plugin.json - which
        follows the changelog - kept announcing 2.0.0 for two releases.

        The rollover was never missing from the release run. Create_ChangeLog_GitHub_PR
        ran and opened its pull requests; the branches updateChangelogAfterv3.0.0
        and updateChangelogAfterv3.1.0 still hold the commits. Nobody merged them,
        the task swallows every failure in a catch that only writes to the build
        log, and nothing downstream checked whether the section had landed.

        This is that missing check. It is deliberately not a manifest assertion:
        binding plugin.json to the newest tag instead would have made the manifest
        correct and left the changelog just as wrong.
    #>
    It 'Should find published release tags to check' -ForEach @{ ReleaseTagCount = $script:releaseTagCase.Count } {
        # Guards the parser and the tag-name convention. Without it, a renamed tag
        # scheme or a broken filter would report zero cases and pass in silence.
        # The count is injected through -ForEach because it is computed during
        # discovery, and a discovery-scope variable is not in scope inside an It.
        $ReleaseTagCount | Should -BeGreaterThan 0
    }

    It 'Should have a changelog section for published release <Tag>' -ForEach $script:releaseTagCase {
        $section = Get-Content -LiteralPath $script:changelogPath |
            Select-String -Pattern ('^## \[{0}\] - \d{{4}}-\d{{2}}-\d{{2}}' -f [System.Text.RegularExpressions.Regex]::Escape($Version))

        $section |
            Should -Not -BeNullOrEmpty -Because "$Tag is published but CHANGELOG.md has no [$Version] section; merge the updateChangelogAfter$Tag pull request or roll the section over by hand"
    }
}
