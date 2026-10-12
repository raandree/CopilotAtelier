BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    . (Join-Path $script:projectPath 'tests/Helpers/ContributorProfileFixture.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
}

Describe 'Export-CopilotAtelierContributorProfile' -Tag 'Unit' {
    BeforeEach {
        $script:layout = New-ContributorTestHome -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Canonical
        $script:environment = @{ USERPROFILE = $script:layout.Home; HOME = $script:layout.Home; LOCALAPPDATA = $script:layout.LocalData }
        $profileText = New-ContributorFixtureProfile -Entry @(
            (New-ContributorFixtureEntry)
            (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]')
        )
        Write-ContributorFixture -Case @{ Text = $profileText } -Path (Join-Path $script:layout.CanonicalFolder 'profile.json')
        $script:destination = Join-Path $TestDrive ('{0}.json' -f [guid]::NewGuid().ToString('N'))
    }

    It 'Should write every entry to a schema-1 file' {
        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Export-CopilotAtelierContributorProfile -Path $script:destination -Confirm:$false
        }

        $result.EntryCount | Should -Be 2
        $exported = Get-Content -LiteralPath $script:destination -Raw | ConvertFrom-Json
        $exported.schemaVersion | Should -Be 1
        @($exported.contributors).Count | Should -Be 2
    }

    It 'Should write only the entry -Contributor names' {
        $null = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Export-CopilotAtelierContributorProfile -Path $script:destination -Contributor 'bob@example.com' -Confirm:$false
        }

        @((Get-Content -LiteralPath $script:destination -Raw | ConvertFrom-Json).contributors.aliases) | Should -Be @('bob@example.com')
    }

    It 'Should refuse a destination inside a git working tree' {
        $repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $repository '.git') -Force | Out-Null
        $inside = Join-Path $repository 'profile-export.json'

        {
            Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
                Export-CopilotAtelierContributorProfile -Path $inside -Confirm:$false
            }
        } | Should -Throw -ExpectedMessage '*git working tree*'

        Test-Path -LiteralPath $inside | Should -BeFalse
    }

    It 'Should write nothing with -WhatIf' {
        $null = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Export-CopilotAtelierContributorProfile -Path $script:destination -WhatIf
        }

        Test-Path -LiteralPath $script:destination | Should -BeFalse
    }
}
