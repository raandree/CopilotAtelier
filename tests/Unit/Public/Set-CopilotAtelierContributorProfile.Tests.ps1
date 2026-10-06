BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    . (Join-Path $script:projectPath 'tests/Helpers/ContributorProfileFixture.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:emptyGitConfig = Join-Path $TestDrive 'empty.gitconfig'
    Set-Content -LiteralPath $script:emptyGitConfig -Value '' -Encoding ascii
}

Describe 'Set-CopilotAtelierContributorProfile' -Tag 'Unit' {
    BeforeEach {
        $script:layout = New-ContributorTestHome -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Canonical -WithFamiliarityScript
        $script:environment = @{
            USERPROFILE         = $script:layout.Home
            HOME                = $script:layout.Home
            LOCALAPPDATA        = $script:layout.LocalData
            GIT_CONFIG_GLOBAL   = $script:emptyGitConfig
            GIT_CONFIG_NOSYSTEM = '1'
        }
        $script:profilePath = Join-Path $script:layout.CanonicalFolder 'profile.json'
        $script:folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:folder -Force | Out-Null
        Push-Location -LiteralPath $script:folder
    }

    AfterEach {
        Pop-Location
    }

    It 'Should save several levels in one write at the path the location rule finds' {
        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Set-CopilotAtelierContributorProfile -KnowledgeArea 'Kerberos', 'Pester' -Level 'new', 'expert' -Confirm:$false
        }

        $result.Created | Should -BeTrue
        $result.ProfilePath | Should -Be $script:profilePath
        $text = Get-Content -LiteralPath $script:profilePath -Raw
        $text | Should -Match '"Kerberos": \{\s+"level": "new"'
        $text | Should -Match '"Pester": \{\s+"level": "expert"'
        $result.Registration | Should -Be 'owned'
    }

    It 'Should preview with -WhatIf and write nothing' {
        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Set-CopilotAtelierContributorProfile -KnowledgeArea 'Kerberos' -Level 'new' -WhatIf
        }

        $result.WhatIf | Should -BeTrue
        Test-Path -LiteralPath $script:profilePath | Should -BeFalse
    }

    It 'Should turn the profile off and keep the levels' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath

        $null = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Set-CopilotAtelierContributorProfile -Contributor 'ada@example.com' -State 'Off' -Confirm:$false
        }

        $text = Get-Content -LiteralPath $script:profilePath -Raw
        $text | Should -Match '"state": "off"'
        $text | Should -Match '"Kerberos"'
    }

    It 'Should write nothing without a positively chosen target, and name every way to choose one' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath
        $before = Get-Content -LiteralPath $script:profilePath -Raw

        {
            Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
                Set-CopilotAtelierContributorProfile -State 'Off' -Confirm:$false
            }
        } | Should -Throw -ExpectedMessage '*-Contributor*-NewContributor*Import-CopilotAtelierContributorProfile*'

        Get-Content -LiteralPath $script:profilePath -Raw | Should -Be $before
    }

    It 'Should create the caller''s own entry beside another with -NewContributor' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath

        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Set-CopilotAtelierContributorProfile -NewContributor -AddAlias 'cy@example.com' -KnowledgeArea 'Pester' -Level 'expert' -Confirm:$false
        }

        $result.Created | Should -BeTrue
        $entries = @((Get-Content -LiteralPath $script:profilePath -Raw | ConvertFrom-Json).contributors)
        $entries.Count | Should -Be 2
        @($entries[1].aliases) | Should -Be @('cy@example.com')
        $entries[1].id | Should -Be $result.EntryId
        $result.Messages -join ' ' | Should -Match 'only where git reports'
    }

    It 'Should refuse -NewContributor together with -Contributor before any write' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath
        $before = Get-Content -LiteralPath $script:profilePath -Raw

        {
            Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
                Set-CopilotAtelierContributorProfile -NewContributor -Contributor 'ada@example.com' -State 'Off' -Confirm:$false
            }
        } | Should -Throw -ExpectedMessage '*-NewContributor*-Contributor*'

        Get-Content -LiteralPath $script:profilePath -Raw | Should -Be $before
    }

    It 'Should fail before any write when -Contributor names no single entry' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath
        $before = Get-Content -LiteralPath $script:profilePath -Raw

        {
            Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
                Set-CopilotAtelierContributorProfile -Contributor 'eve@example.com' -State 'Off' -Confirm:$false
            }
        } | Should -Throw -ExpectedMessage '*exactly one entry*'

        Get-Content -LiteralPath $script:profilePath -Raw | Should -Be $before
    }

    It 'Should refuse a level outside new, familiar, and expert' {
        { Set-CopilotAtelierContributorProfile -KnowledgeArea 'Kerberos' -Level 'guru' -Confirm:$false } | Should -Throw
    }
}
