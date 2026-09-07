BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:sandboxVariableName = @(
        'APPDATA'
        'HOME'
        'OneDrive'
        'OneDriveCommercial'
        'OneDriveConsumer'
        'USERPROFILE'
        'XDG_CONFIG_HOME'
    )

    $script:fixtureSkill = @(
        'agent-security-review'
        'long-running-job-monitor'
        'memory-bank'
        'pdf-to-markdown'
        'sampler-framework'
    )

    function Initialize-ProfileFixture
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.String]
            $Root
        )

        $contentPath = Join-Path $Root 'content'
        $homePath = Join-Path $Root 'home'
        $configPath = Join-Path $Root 'config'

        foreach ($directoryName in @('com.github.copilot/agents', 'com.github.copilot/rules', 'com.github.copilot/commands'))
        {
            $directoryPath = Join-Path $contentPath $directoryName
            New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directoryPath 'marker.md') -Value "# $directoryName"
        }

        foreach ($skillName in $script:fixtureSkill)
        {
            $skillPath = Join-Path $contentPath "skills/$skillName"
            New-Item -ItemType Directory -Path (Join-Path $skillPath 'scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillPath 'SKILL.md') -Value "# $skillName"
            Set-Content -LiteralPath (Join-Path $skillPath 'scripts/helper.ps1') -Value "# $skillName helper"
        }

        $original = @{}
        foreach ($name in $script:sandboxVariableName)
        {
            $original[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')
        }

        New-Item -ItemType Directory -Path $homePath, $configPath -Force | Out-Null

        [System.Environment]::SetEnvironmentVariable('APPDATA', $configPath, 'Process')
        [System.Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
        [System.Environment]::SetEnvironmentVariable('USERPROFILE', $homePath, 'Process')
        [System.Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $configPath, 'Process')
        foreach ($name in @('OneDrive', 'OneDriveCommercial', 'OneDriveConsumer'))
        {
            [System.Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }

        [pscustomobject]@{
            Original = $original
            ContentPath = $contentPath
            TargetPath = Join-Path $homePath 'CopilotAtelier'
        }
    }

    function Exit-ProfileFixture
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.Collections.Hashtable]
            $Original
        )

        foreach ($name in $script:sandboxVariableName)
        {
            [System.Environment]::SetEnvironmentVariable($name, $Original[$name], 'Process')
        }
    }

    function Get-DeployedSkillName
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.String]
            $TargetPath
        )

        $skillRoot = Join-Path $TargetPath 'skills'

        if (-not (Test-Path -LiteralPath $skillRoot -PathType Container))
        {
            return @()
        }

        return @((Get-ChildItem -LiteralPath $skillRoot -Directory).Name | Sort-Object)
    }

    <#
        Rewrites the recorded selection at the moment the deployment lock is
        acquired, which is exactly the window a second local installer occupies,
        and then runs an argument-free install that inherits a selection.
    #>
    function Invoke-ConcurrentSelectionChange
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.PSObject]
            $Fixture,

            [Parameter(Mandatory = $true)]
            [System.String]
            $LockPath,

            [Parameter()]
            [AllowNull()]
            [System.Management.Automation.PSObject]
            $Selection
        )

        InModuleScope CopilotAtelier -Parameters @{
            ContentPath = $Fixture.ContentPath
            TargetPath = $Fixture.TargetPath
            LockPath = $LockPath
            Selection = $Selection
        } {
            $recordPath = Join-Path $TargetPath '.copilotatelier.json'
            $changeSelection = $Selection
            $changeLockPath = $LockPath

            $mockBody = {
                $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json

                if ($null -eq $changeSelection)
                {
                    $record.PSObject.Properties.Remove('Selection')
                }
                else
                {
                    $record | Add-Member -NotePropertyName Selection -NotePropertyValue $changeSelection -Force
                }

                [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))

                [System.IO.File]::Open($changeLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            }.GetNewClosure()

            Mock -CommandName Enter-CopilotAtelierDeploymentLock -MockWith $mockBody

            Install-CopilotAtelier -ContentPath $ContentPath -SkipCopilotCliEnvironment -Confirm:$false | Out-Null
        }
    }
}

Describe 'Install-CopilotAtelier installation profiles' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:fixture = Initialize-ProfileFixture -Root $script:root
    }

    AfterEach {
        Exit-ProfileFixture -Original $script:fixture.Original
    }

    It 'Should deploy every Skill without a selection argument' {
        $result = Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -SkipCopilotCliEnvironment -Confirm:$false

        $result.InstallationProfile | Should -Be 'complete'
        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Be ($script:fixtureSkill | Sort-Object)
    }

    It 'Should omit the Selection property from a complete Deployment record' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $record = Get-Content -LiteralPath (Join-Path $script:fixture.TargetPath '.copilotatelier.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json

        $record.PSObject.Properties.Name | Should -Not -Contain 'Selection'
    }

    It 'Should deploy only the selected Skills and their whole folders' {
        $result = Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false

        $result.InstallationProfile | Should -Be 'document-processing'
        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath |
            Should -Be @('agent-security-review', 'long-running-job-monitor', 'memory-bank', 'pdf-to-markdown')

        Test-Path -LiteralPath (Join-Path $script:fixture.TargetPath 'skills/pdf-to-markdown/scripts/helper.ps1') -PathType Leaf |
            Should -BeTrue -Because 'a selected Skill ships its whole folder'
    }

    It 'Should record the selection so it survives a later argument-free run' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $record = Get-Content -LiteralPath (Join-Path $script:fixture.TargetPath '.copilotatelier.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json

        $record.Selection.Profile | Should -Be 'document-processing'
        @($record.Selection.Skill) | Should -Contain 'pdf-to-markdown'

        $second = Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -SkipCopilotCliEnvironment -Confirm:$false

        $second.InstallationProfile | Should -Be 'document-processing'
        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Not -Contain 'sampler-framework'
    }

    It 'Should return to the complete installation on request' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'complete' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Be ($script:fixtureSkill | Sort-Object)

        $record = Get-Content -LiteralPath (Join-Path $script:fixture.TargetPath '.copilotatelier.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json

        $record.PSObject.Properties.Name | Should -Not -Contain 'Selection'
    }

    It 'Should drop a recorded exclusion when a new selection argument is given' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -ExcludeSkill @('sampler-framework') -SkipCopilotCliEnvironment -Confirm:$false | Out-Null
        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Not -Contain 'sampler-framework'

        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'complete' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Be ($script:fixtureSkill | Sort-Object)
    }

    It 'Should keep a recorded exclusion across an argument-free run' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -ExcludeSkill @('sampler-framework') -SkipCopilotCliEnvironment -Confirm:$false | Out-Null
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Not -Contain 'sampler-framework'
    }

    It 'Should keep the recorded profile when only an adjustment is given' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $result = Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -IncludeSkill @('sampler-framework') -SkipCopilotCliEnvironment -Confirm:$false

        $result.InstallationProfile | Should -Be 'document-processing'
        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Contain 'sampler-framework'
        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -Contain 'pdf-to-markdown'
    }

    It 'Should remove only owned files when switching to a narrower profile' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $userFile = Join-Path $script:fixture.TargetPath 'skills/sampler-framework/my-notes.md'
        Set-Content -LiteralPath $userFile -Value 'personal'

        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        Test-Path -LiteralPath $userFile -PathType Leaf | Should -BeTrue -Because 'a user-added file is never owned'
        Test-Path -LiteralPath (Join-Path $script:fixture.TargetPath 'skills/sampler-framework/SKILL.md') |
            Should -BeFalse -Because 'an unchanged owned file of a deselected Skill is retired'
    }

    It 'Should refuse a narrowing switch that would retire a locally changed file' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $ownedFile = Join-Path $script:fixture.TargetPath 'skills/sampler-framework/SKILL.md'
        Set-Content -LiteralPath $ownedFile -Value 'edited by hand'

        { Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false } |
            Should -Throw -ExpectedMessage '*retired file*sampler-framework*'

        Get-Content -LiteralPath $ownedFile -Raw | Should -Match 'edited by hand'
    }

    It 'Should write nothing when the selection is invalid' {
        { Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -ExcludeSkill @('memory-bank') -SkipCopilotCliEnvironment -Confirm:$false } |
            Should -Throw -ExpectedMessage '*mandatory*memory-bank*'

        Test-Path -LiteralPath $script:fixture.TargetPath | Should -BeFalse
    }

    It 'Should preview the selection without writing under WhatIf' {
        $result = Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'engineering' -SkipCopilotCliEnvironment -WhatIf

        $result.InstallationProfile | Should -Be 'engineering'
        $result.SelectedSkills | Should -Contain 'sampler-framework'
        $result.SelectedSkills | Should -Not -Contain 'pdf-to-markdown'
        Test-Path -LiteralPath $script:fixture.TargetPath | Should -BeFalse
    }

    It 'Should report the deployed profile through Test-CopilotAtelier' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'engineering' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $diagnostic = Test-CopilotAtelier -TargetPath $script:fixture.TargetPath

        $diagnostic.InstallationProfile | Should -Be 'engineering'
        @($diagnostic.Checks | Where-Object -FilterScript { $_.Code -eq 'InstallationProfile' }) |
            Should -Not -BeNullOrEmpty
    }

    It 'Should remove the whole deployment regardless of the installed profile' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'research' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $removal = Uninstall-CopilotAtelier -TargetPath $script:fixture.TargetPath -Confirm:$false

        @($removal.RemovedFiles) | Should -Not -BeNullOrEmpty
        Get-DeployedSkillName -TargetPath $script:fixture.TargetPath | Should -BeNullOrEmpty
    }

    It 'Should not treat a Skill the recorded Selection claims as an Owned file' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        $recordPath = Join-Path $script:fixture.TargetPath '.copilotatelier.json'
        $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $record.Files = @($record.Files | Where-Object -FilterScript { $_.Path -notlike 'skills/pdf-to-markdown/*' })
        [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))

        Uninstall-CopilotAtelier -TargetPath $script:fixture.TargetPath -Confirm:$false | Out-Null

        Test-Path -LiteralPath (Join-Path $script:fixture.TargetPath 'skills/pdf-to-markdown/SKILL.md') -PathType Leaf |
            Should -BeTrue -Because 'only the recorded Files list confers ownership, never the claimed Selection'
    }
}

Describe 'Install-CopilotAtelier selection under the deployment lock' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:fixture = Initialize-ProfileFixture -Root $script:root
    }

    AfterEach {
        Exit-ProfileFixture -Original $script:fixture.Original
    }

    It 'Should not widen an inherited selection that changed at lock acquisition' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        Invoke-ConcurrentSelectionChange -Fixture $script:fixture -LockPath (Join-Path $script:root 'concurrent.lock') -Selection ([pscustomobject]@{
                Profile = 'document-processing'
                Skill = @('agent-security-review', 'long-running-job-monitor', 'memory-bank', 'pdf-to-markdown')
                IncludeSkill = @()
                ExcludeSkill = @()
            })

        Test-Path -LiteralPath (Join-Path $script:fixture.TargetPath 'skills/pdf-to-markdown/SKILL.md') -PathType Leaf |
            Should -BeTrue -Because 'the selection recorded at lock acquisition is the one that gets deployed'
        Test-Path -LiteralPath (Join-Path $script:fixture.TargetPath 'skills/sampler-framework/SKILL.md') -PathType Leaf |
            Should -BeFalse -Because 'a stale inherited selection must not widen the deployment back out'

        $record = Get-Content -LiteralPath (Join-Path $script:fixture.TargetPath '.copilotatelier.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json

        $record.Selection.Profile | Should -Be 'document-processing'
    }

    It 'Should not roll back an inherited selection that changed at lock acquisition' {
        Install-CopilotAtelier -ContentPath $script:fixture.ContentPath -InstallationProfile 'document-processing' -SkipCopilotCliEnvironment -Confirm:$false | Out-Null

        Invoke-ConcurrentSelectionChange -Fixture $script:fixture -LockPath (Join-Path $script:root 'concurrent.lock') -Selection $null

        Test-Path -LiteralPath (Join-Path $script:fixture.TargetPath 'skills/sampler-framework/SKILL.md') -PathType Leaf |
            Should -BeTrue -Because 'a stale inherited selection must not roll the deployment back to a narrower one'

        $record = Get-Content -LiteralPath (Join-Path $script:fixture.TargetPath '.copilotatelier.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json

        $record.PSObject.Properties.Name | Should -Not -Contain 'Selection'
    }
}

Describe 'Deployment record selection compatibility' -Tag 'Unit' {
    BeforeEach {
        $script:recordTarget = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:recordTarget -Force | Out-Null
    }

    It 'Should accept a schema 1 record that predates installation profiles' {
        @{ SchemaVersion = 1; Version = '1.0.0'; Files = @() } |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $script:recordTarget '.copilotatelier.json')

        $record = InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:recordTarget } {
            Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
        }

        $record.SchemaVersion | Should -Be 1
        $record.PSObject.Properties.Name | Should -Not -Contain 'Selection'
    }

    It 'Should round-trip a recorded selection through the record writer' {
        InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:recordTarget } {
            $record = [pscustomobject]@{
                SchemaVersion = 1
                Version = '1.0.0'
                Files = @()
                Selection = [pscustomobject]@{
                    Profile = 'engineering'
                    Skill = @('memory-bank')
                    IncludeSkill = @('grammar-check')
                    ExcludeSkill = @('grill-me')
                }
            }

            Set-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -Record $record -Confirm:$false

            $stored = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath

            $stored.Selection.Profile | Should -Be 'engineering'
            @($stored.Selection.Skill) | Should -Be @('memory-bank')
            @($stored.Selection.IncludeSkill) | Should -Be @('grammar-check')
            @($stored.Selection.ExcludeSkill) | Should -Be @('grill-me')
            $stored.Selection.Skill -is [System.Array] |
                Should -BeTrue -Because 'a one-element list must survive the JSON round trip as an array on every supported host'
            $stored.Selection.IncludeSkill -is [System.Array] | Should -BeTrue
        }
    }

    It 'Should reject the malformed selection <Reason>' -ForEach @(
        @{ Reason = 'without a profile'; Selection = @{ Skill = @('memory-bank') } }
        @{ Reason = 'without a Skill list'; Selection = @{ Profile = 'engineering' } }
        @{ Reason = 'with a traversal identifier'; Selection = @{ Profile = 'engineering'; Skill = @('../escape') } }
        @{ Reason = 'with a non-string identifier'; Selection = @{ Profile = 'engineering'; Skill = @(7) } }
        @{ Reason = 'with a scalar Skill value'; Selection = @{ Profile = 'engineering'; Skill = 'memory-bank' } }
        @{ Reason = 'with a scalar IncludeSkill value'; Selection = @{ Profile = 'engineering'; Skill = @('memory-bank'); IncludeSkill = 'grammar-check' } }
        @{ Reason = 'with an object in place of a Skill list'; Selection = @{ Profile = 'engineering'; Skill = @{ Name = 'memory-bank' } } }
        @{ Reason = 'with a duplicate identifier'; Selection = @{ Profile = 'engineering'; Skill = @('memory-bank', 'Memory-Bank') } }
        @{ Reason = 'with the same Skill included and excluded'; Selection = @{ Profile = 'engineering'; Skill = @('memory-bank'); IncludeSkill = @('grammar-check'); ExcludeSkill = @('grammar-check') } }
        @{ Reason = 'with an excluded Skill in the resolved list'; Selection = @{ Profile = 'engineering'; Skill = @('memory-bank', 'grill-me'); ExcludeSkill = @('grill-me') } }
        @{ Reason = 'with a non-string profile'; Selection = @{ Profile = 7; Skill = @('memory-bank') } }
    ) {
        @{ SchemaVersion = 1; Version = '1.0.0'; Files = @(); Selection = $Selection } |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $script:recordTarget '.copilotatelier.json')

        InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:recordTarget } {
            { Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath } |
                Should -Throw -ExpectedMessage '*malformed Selection*'
        }
    }

    It 'Should accept a selection whose optional lists are absent' {
        @{ SchemaVersion = 1; Version = '1.0.0'; Files = @(); Selection = @{ Profile = 'engineering'; Skill = @('memory-bank') } } |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $script:recordTarget '.copilotatelier.json')

        $record = InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:recordTarget } {
            Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
        }

        $record.Selection.Profile | Should -Be 'engineering'
    }
}
