BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    . (Join-Path $script:projectPath 'tests/Helpers/ContributorProfileFixture.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:emptyGitConfig = Join-Path $TestDrive 'empty.gitconfig'
    Set-Content -LiteralPath $script:emptyGitConfig -Value '' -Encoding ascii
}

Describe 'Remove-CopilotAtelierContributorProfile' -Tag 'Unit' {
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
        $script:registrationPath = Join-Path $script:layout.Home '.copilot/hooks/contributor-profile.json'
        $twoEntries = New-ContributorFixtureProfile -Entry @(
            (New-ContributorFixtureEntry)
            (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]')
        )
        Write-ContributorFixture -Case @{ Text = $twoEntries } -Path $script:profilePath
    }

    It 'Should remove one entry and keep the others' {
        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Remove-CopilotAtelierContributorProfile -Contributor 'bob@example.com' -Confirm:$false
        }

        $result.Removed | Should -Be 'entry'
        @((Get-Content -LiteralPath $script:profilePath -Raw | ConvertFrom-Json).contributors).Count | Should -Be 1
    }

    It 'Should delete the whole profile file without -Contributor' {
        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Remove-CopilotAtelierContributorProfile -Confirm:$false
        }

        $result.Removed | Should -Be 'file'
        Test-Path -LiteralPath $script:profilePath | Should -BeFalse
    }

    It 'Should write nothing with -WhatIf' {
        $before = Get-Content -LiteralPath $script:profilePath -Raw

        $null = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Remove-CopilotAtelierContributorProfile -Contributor 'bob@example.com' -WhatIf
        }

        Get-Content -LiteralPath $script:profilePath -Raw | Should -Be $before
    }

    It 'Should ask for confirmation at high impact' {
        $command = Get-Command -Name Remove-CopilotAtelierContributorProfile

        $binding = $command.ScriptBlock.Attributes | Where-Object -FilterScript { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $binding.ConfirmImpact | Should -Be 'High'
        $command.Parameters.Keys | Should -Contain 'WhatIf'
    }

    It 'Should remove only an orphaned registration with -RegistrationOnly' {
        Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Push-Location -LiteralPath $folder
            try
            {
                $null = Set-CopilotAtelierContributorProfile -Contributor 'bob@example.com' -KnowledgeArea 'Pester' -Level 'new' -Confirm:$false
            }
            finally
            {
                Pop-Location
            }
        }

        Test-Path -LiteralPath $script:registrationPath | Should -BeTrue
        Remove-Item -LiteralPath $script:profilePath

        $result = Use-ContributorEnvironment -Variable $script:environment -ScriptBlock {
            Remove-CopilotAtelierContributorProfile -RegistrationOnly -Confirm:$false
        }

        $result.Removed | Should -Be 'registration'
        Test-Path -LiteralPath $script:registrationPath | Should -BeFalse
    }
}
