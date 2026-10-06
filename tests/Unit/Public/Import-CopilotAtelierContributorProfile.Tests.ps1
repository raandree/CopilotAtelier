BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    . (Join-Path $script:projectPath 'tests/Helpers/ContributorProfileFixture.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
}

Describe 'Import-CopilotAtelierContributorProfile' -Tag 'Unit' {
    BeforeEach {
        $script:layout = New-ContributorTestHome -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Canonical
        $script:environment = @{ USERPROFILE = $script:layout.Home; HOME = $script:layout.Home; LOCALAPPDATA = $script:layout.LocalData }
        $script:profilePath = Join-Path $script:layout.CanonicalFolder 'profile.json'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:profilePath
        $script:source = Join-Path $TestDrive ('{0}.json' -f [guid]::NewGuid().ToString('N'))
    }

    It 'Should merge an imported entry and add an unmatched one' {
        $incoming = New-ContributorFixtureProfile -Entry @(
            (New-ContributorFixtureEntry -Areas '{"Kerberos":{"level":"expert","updatedUtc":"2026-10-05T08:00:00Z"}}')
            (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]')
        )
        Write-ContributorFixture -Case @{ Text = $incoming } -Path $script:source

        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Import-CopilotAtelierContributorProfile -Path $script:source -Confirm:$false
        }

        $result.Matched | Should -Be 1
        $result.Added | Should -Be 1
        $merged = Get-Content -LiteralPath $script:profilePath -Raw | ConvertFrom-Json
        @($merged.contributors).Count | Should -Be 2
        $merged.contributors[0].areas.Kerberos.level | Should -Be 'expert'
    }

    It 'Should refuse an invalid file, name its reason code, and write nothing' {
        Write-ContributorFixture -Case @{ Text = '{"schemaVersion":1,"contributors":[],}' } -Path $script:source
        $before = Get-Content -LiteralPath $script:profilePath -Raw

        {
            Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
                Import-CopilotAtelierContributorProfile -Path $script:source -Confirm:$false
            }
        } | Should -Throw -ExpectedMessage '*invalid-json*'

        Get-Content -LiteralPath $script:profilePath -Raw | Should -Be $before
    }

    It 'Should preview the merge with -WhatIf and write nothing' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 3) -Aliases '["cy@example.com"]')) } -Path $script:source
        $before = Get-Content -LiteralPath $script:profilePath -Raw

        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Import-CopilotAtelierContributorProfile -Path $script:source -WhatIf
        }

        $result.WhatIf | Should -BeTrue
        $result.Added | Should -Be 1
        Get-Content -LiteralPath $script:profilePath -Raw | Should -Be $before
    }
}
