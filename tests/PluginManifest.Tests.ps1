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
