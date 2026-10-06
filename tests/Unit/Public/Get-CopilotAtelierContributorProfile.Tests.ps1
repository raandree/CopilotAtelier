BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    . (Join-Path $script:projectPath 'tests/Helpers/ContributorProfileFixture.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:emptyGitConfig = Join-Path $TestDrive 'empty.gitconfig'
    Set-Content -LiteralPath $script:emptyGitConfig -Value '' -Encoding ascii
}

Describe 'Get-CopilotAtelierContributorProfile' -Tag 'Unit' {
    BeforeEach {
        $script:layout = New-ContributorTestHome -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Canonical
        $script:environment = @{
            USERPROFILE         = $script:layout.Home
            HOME                = $script:layout.Home
            LOCALAPPDATA        = $script:layout.LocalData
            GIT_CONFIG_GLOBAL   = $script:emptyGitConfig
            GIT_CONFIG_NOSYSTEM = '1'
        }
        $script:profilePath = Join-Path $script:layout.CanonicalFolder 'profile.json'
    }

    It 'Should report the profile the location rule finds, with aliases masked' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath

        $report = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock { Get-CopilotAtelierContributorProfile }

        $report.ProfilePath | Should -Be $script:profilePath
        $report.Kind | Should -Be 'canonical'
        $report.Selection | Should -Be 'single'
        @($report.Aliases) | Should -Be @('a***@example.com')
        $report.Levels | Should -Contain 'Kerberos: new'
    }

    It 'Should show aliases unmasked with -ShowAliases' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath

        $report = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock { Get-CopilotAtelierContributorProfile -ShowAliases }

        @($report.Aliases) | Should -Be @('ada@example.com')
    }

    It 'Should show the sentence a relative workspace path receives' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath
        $workspace = New-ContributorTestWorkspace -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Area 'Kerberos'

        Push-Location -LiteralPath $workspace
        try
        {
            $report = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock { Get-CopilotAtelierContributorProfile -WorkspacePath . }
        }
        finally
        {
            Pop-Location
        }

        $report.Sentence | Should -Match '"Kerberos" new'
    }

    It 'Should report an unreadable profile instead of failing' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Version '2') } -Path $script:profilePath

        $report = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock { Get-CopilotAtelierContributorProfile }

        $report.ReasonCode | Should -Be 'unsupported-schema'
    }

    It 'Should report a profile saved on this machine only without the Canonical target' {
        $plugin = New-ContributorTestHome -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $environment = $script:environment.Clone()
        $environment.USERPROFILE = $plugin.Home
        $environment.HOME = $plugin.Home
        $environment.LOCALAPPDATA = $plugin.LocalData

        $report = Use-ContributorEnvironment -Variable $environment -ScriptBlock { Get-CopilotAtelierContributorProfile }

        $report.Kind | Should -Be 'local'
        $report.Storage | Should -Be 'this machine only'
        $report.Exists | Should -BeFalse
    }
}
