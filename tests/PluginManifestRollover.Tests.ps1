<#
    Create_ChangeLog_GitHub_PR (Sampler.GitHubTasks) rolls the [Unreleased]
    changelog section over after a full release and commits only the files in
    GitHubConfig.GitHubFilesToAdd. plugin.json must carry the most recent
    released changelog version, so a rollover that leaves it behind fails its
    own pull request, as the v5.0.0 rollover did in CI run 36549550887.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:taskFilePath = Join-Path $script:repoRoot '.build/Update_PluginManifest_Version.build.ps1'
    $script:fixtureBuildPath = Join-Path $PSScriptRoot 'Fixtures/PluginManifestRollover.build.ps1'
    $script:manifestTemplate = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot 'plugin.json'))
    $script:utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    Import-Module InvokeBuild -ErrorAction Stop
    Import-Module powershell-yaml -ErrorAction Stop
    $script:fixtureBuildInvoker = New-Module -ScriptBlock {
        Import-Module InvokeBuild -ErrorAction Stop
    }

    $buildConfiguration = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath (Join-Path $script:repoRoot 'build.yaml') -Raw)
    $script:filesToAdd = @($buildConfiguration.GitHubConfig.GitHubFilesToAdd)

    # Keep global and system git configuration, such as a developer's own
    # rebase.autoStash, out of the repositories these tests create.
    $script:savedGitEnvironment = @{}
    foreach ($name in 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM') {
        $script:savedGitEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    $emptyGlobalConfig = Join-Path $TestDrive 'empty.gitconfig'
    New-Item -ItemType File -Path $emptyGlobalConfig -Force | Out-Null
    $env:GIT_CONFIG_GLOBAL = $emptyGlobalConfig
    $env:GIT_CONFIG_NOSYSTEM = '1'

    function Invoke-TestGit {
        param ([string] $Path, [string[]] $Argument)

        $output = & git -C $Path @Argument 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git $($Argument -join ' ') failed with exit code $LASTEXITCODE`: $($output -join [Environment]::NewLine)"
        }
        $output | Where-Object { $_ -is [string] }
    }

    function Get-TestGitConfig {
        param ([string] $Path, [string] $Name)

        $value = & git -C $Path config --local --get $Name
        if ($LASTEXITCODE -eq 1) { return $null }
        if ($LASTEXITCODE -ne 0) { throw "git config --get $Name failed with exit code $LASTEXITCODE." }
        $value
    }

    function Get-ManifestFingerprint {
        param ([string] $ProjectPath)

        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $ProjectPath 'plugin.json')))
    }

    function Initialize-RolloverRepository {
        param ([string] $ManifestVersion = '5.0.0', [string] $ManifestText)

        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $origin = Join-Path $root 'origin.git'
        $project = Join-Path $root 'project'
        New-Item -ItemType Directory -Path $project -Force | Out-Null

        Invoke-TestGit $root @('init', '--quiet', '--bare', '--initial-branch=main', $origin)
        Invoke-TestGit $project @('init', '--quiet', '--initial-branch=main')
        Invoke-TestGit $project @('config', 'user.name', 'Rollover Test')
        Invoke-TestGit $project @('config', 'user.email', 'rollover@example.invalid')

        if (-not $ManifestText) {
            $ManifestText = [regex]::new('"version": "[^"]*"').Replace($script:manifestTemplate, "`"version`": `"$ManifestVersion`"", 1)
        }
        [System.IO.File]::WriteAllText((Join-Path $project 'plugin.json'), $ManifestText, $script:utf8NoBom)
        [System.IO.File]::WriteAllText((Join-Path $project 'CHANGELOG.md'), "# Changelog`n`n## [Unreleased]`n`n### Fixed`n`n- Example fix.`n", $script:utf8NoBom)

        Invoke-TestGit $project @('add', '--', 'plugin.json', 'CHANGELOG.md')
        Invoke-TestGit $project @('commit', '--quiet', '-m', 'Initial commit')
        Invoke-TestGit $project @('remote', 'add', 'origin', $origin)
        Invoke-TestGit $project @('push', '--quiet', '--set-upstream', 'origin', 'main')
        $project
    }

    function Invoke-RolloverBuild {
        param ([string] $ProjectPath, [bool] $RolloverEnabled = $true)

        $recordPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.version')
        $parameters = @{
            File = $script:fixtureBuildPath
            TaskFilePath = $script:taskFilePath
            ProjectPath = $ProjectPath
            MainGitBranch = 'main'
            RolloverEnabled = $RolloverEnabled
            RecordPath = $recordPath
        }
        & $script:fixtureBuildInvoker {
            param ($BuildParameters)
            Invoke-Build @BuildParameters
        } $parameters | Out-Null
        $recordPath
    }
}

AfterAll {
    foreach ($name in $script:savedGitEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:savedGitEnvironment[$name])
    }
}

Describe 'Plugin manifest release rollover' -Tag 'Unit' {
    It 'Sets the manifest to the full release at the head of main before the rollover runs' {
        $project = Initialize-RolloverRepository -ManifestVersion '5.0.0'
        Invoke-TestGit $project @('tag', 'v6.0.0')
        $expected = [System.IO.File]::ReadAllText((Join-Path $project 'plugin.json')).Replace('"version": "5.0.0"', '"version": "6.0.0"')

        $recordPath = Invoke-RolloverBuild -ProjectPath $project

        Get-Content -LiteralPath $recordPath | Should -Be '6.0.0' -Because 'the rollover must see the new version before it commits'
        Get-ManifestFingerprint $project | Should -Be ([Convert]::ToBase64String($script:utf8NoBom.GetBytes($expected))) -Because 'only the version value may change'
        Get-TestGitConfig $project 'rebase.autoStash' | Should -Be 'true' -Because 'the rollover pulls with rebase before it commits'
    }

    It 'Leaves the manifest untouched for <Case>' -ForEach @(
        @{ Case = 'a pre-release'; Tag = 'v6.0.0-preview0001'; MainMovesOn = $false }
        @{ Case = 'a release that is no longer the head of main'; Tag = 'v6.0.0'; MainMovesOn = $true }
        @{ Case = 'a tag that is not a version'; Tag = 'nightly'; MainMovesOn = $false }
    ) {
        $project = Initialize-RolloverRepository -ManifestVersion '5.0.0'
        Invoke-TestGit $project @('tag', $Tag)
        if ($MainMovesOn) {
            [System.IO.File]::AppendAllText((Join-Path $project 'CHANGELOG.md'), "- Later fix.`n", $script:utf8NoBom)
            Invoke-TestGit $project @('commit', '--quiet', '--all', '-m', 'Later commit')
            Invoke-TestGit $project @('push', '--quiet', 'origin', 'main')
        }
        $before = Get-ManifestFingerprint $project

        Invoke-RolloverBuild -ProjectPath $project | Out-Null

        Get-ManifestFingerprint $project | Should -Be $before
        Get-TestGitConfig $project 'rebase.autoStash' | Should -BeNullOrEmpty
    }

    It 'Leaves a manifest that already carries the release untouched' {
        $project = Initialize-RolloverRepository -ManifestVersion '6.0.0'
        Invoke-TestGit $project @('tag', 'v6.0.0')
        $before = Get-ManifestFingerprint $project

        Invoke-RolloverBuild -ProjectPath $project | Out-Null

        Get-ManifestFingerprint $project | Should -Be $before
        Get-TestGitConfig $project 'rebase.autoStash' | Should -BeNullOrEmpty
    }

    It 'Runs only when the changelog rollover runs' {
        $project = Initialize-RolloverRepository -ManifestVersion '5.0.0'
        Invoke-TestGit $project @('tag', 'v6.0.0')
        $before = Get-ManifestFingerprint $project

        $recordPath = Invoke-RolloverBuild -ProjectPath $project -RolloverEnabled $false

        Test-Path -LiteralPath $recordPath | Should -BeFalse -Because 'the stand-in rollover task is skipped'
        Get-ManifestFingerprint $project | Should -Be $before
    }

    It 'Refuses a manifest whose version it cannot rewrite in place: <Case>' -ForEach @(
        @{ Case = 'invalid JSON'; ManifestText = '{ "name": "copilot-atelier", "version": ' }
        @{ Case = 'no version'; ManifestText = "{`n    `"name`": `"copilot-atelier`"`n}`n" }
        @{ Case = 'a nested copy of the version'; ManifestText = "{`n    `"version`": `"5.0.0`",`n    `"engines`": {`n        `"version`": `"5.0.0`"`n    }`n}`n" }
    ) {
        $project = Initialize-RolloverRepository -ManifestText $ManifestText
        Invoke-TestGit $project @('tag', 'v6.0.0')
        $before = Get-ManifestFingerprint $project

        { Invoke-RolloverBuild -ProjectPath $project } | Should -Throw '*plugin.json*'

        Get-ManifestFingerprint $project | Should -Be $before
    }

    It 'Commits the manifest with the changelog when the rollover starts from the <Checkout>' -ForEach @(
        @{ Checkout = 'main branch' }
        @{ Checkout = 'detached release tag' }
    ) {
        $project = Initialize-RolloverRepository -ManifestVersion '5.0.0'
        Invoke-TestGit $project @('tag', 'v6.0.0')
        if ($Checkout -eq 'detached release tag') {
            Invoke-TestGit $project @('checkout', '--quiet', '--detach', 'v6.0.0')
        }

        Invoke-RolloverBuild -ProjectPath $project | Out-Null

        # The git sequence Create_ChangeLog_GitHub_PR runs, with Update-Changelog
        # reduced to appending the release heading.
        Invoke-TestGit $project @('config', 'pull.rebase', 'true')
        Invoke-TestGit $project @('pull', 'origin', 'main', '--tag')
        Invoke-TestGit $project @('checkout', '-B', 'updateChangelogAfterv6.0.0')
        [System.IO.File]::AppendAllText((Join-Path $project 'CHANGELOG.md'), "`n## [6.0.0] - 2026-09-29`n", $script:utf8NoBom)
        Invoke-TestGit $project (@('add') + $script:filesToAdd)
        Invoke-TestGit $project @('commit', '--quiet', '-m', 'Updating ChangeLog since v6.0.0 +semver:skip')

        @(Invoke-TestGit $project @('diff', '--name-only', 'HEAD~1', 'HEAD')) | Sort-Object |
            Should -Be @('CHANGELOG.md', 'plugin.json') -Because 'GitHubFilesToAdd must carry the manifest into the rollover commit'
        ((Invoke-TestGit $project @('show', 'HEAD:plugin.json')) -join "`n" | ConvertFrom-Json).version | Should -Be '6.0.0'
        Invoke-TestGit $project @('status', '--porcelain') | Should -BeNullOrEmpty
    }
}
