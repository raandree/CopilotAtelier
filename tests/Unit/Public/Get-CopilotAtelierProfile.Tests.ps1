BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
}

Describe 'Get-CopilotAtelierProfile' -Tag 'Unit' {
    BeforeAll {
        $script:payloadPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))

        foreach ($skillName in @('agent-security-review', 'long-running-job-monitor', 'memory-bank', 'pdf-to-markdown', 'sampler-framework'))
        {
            $skillPath = Join-Path $script:payloadPath "skills/$skillName"
            New-Item -ItemType Directory -Path $skillPath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillPath 'SKILL.md') -Value "# $skillName"
        }
    }

    It 'Should list every installation profile for the given payload' {
        $result = @(Get-CopilotAtelierProfile -ContentPath $script:payloadPath)

        $result.Name | Should -Be @('complete', 'engineering', 'research', 'document-processing')
        @($result | Where-Object -FilterScript { $_.IsDefault }).Name | Should -Be 'complete'
    }

    It 'Should resolve the Skills a named profile deploys from this payload' {
        $result = Get-CopilotAtelierProfile -Name 'document-processing' -ContentPath $script:payloadPath

        $result.Name | Should -Be 'document-processing'
        $result.Skill | Should -Contain 'pdf-to-markdown'
        $result.Skill | Should -Not -Contain 'sampler-framework'
        $result.SkillCount | Should -Be @($result.Skill).Count
    }

    It 'Should report the mandatory Skills that no profile may drop' {
        $result = Get-CopilotAtelierProfile -Name 'engineering' -ContentPath $script:payloadPath

        $result.MandatorySkill | Should -Contain 'memory-bank'
        foreach ($name in $result.MandatorySkill)
        {
            $result.Skill | Should -Contain $name
        }
    }

    It 'Should describe every profile' {
        foreach ($item in @(Get-CopilotAtelierProfile -ContentPath $script:payloadPath))
        {
            $item.Description.Length | Should -BeGreaterThan 20
        }
    }

    It 'Should reject an unknown profile name' {
        { Get-CopilotAtelierProfile -Name 'no-such-profile' -ContentPath $script:payloadPath } |
            Should -Throw
    }

    It 'Should reject a content path that does not exist' {
        { Get-CopilotAtelierProfile -ContentPath (Join-Path $TestDrive 'missing-payload') } |
            Should -Throw -ExpectedMessage '*does not exist*'
    }

    It 'Should not claim that the complete profile was validated against prerequisites' {
        $result = @(Get-CopilotAtelierProfile -ContentPath $script:payloadPath)

        @($result | Where-Object -FilterScript { $_.Name -eq 'complete' }).PrerequisiteValidated |
            Should -BeFalse -Because 'the complete installation deploys the payload as it is'
        @($result | Where-Object -FilterScript { $_.Name -eq 'engineering' }).PrerequisiteValidated |
            Should -BeTrue
    }

    It 'Should refuse a narrowed profile that this payload cannot satisfy' {
        $partialPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $skillPath = Join-Path $partialPath 'skills/memory-bank'
        New-Item -ItemType Directory -Path $skillPath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skillPath 'SKILL.md') -Value '# memory-bank'

        { Get-CopilotAtelierProfile -Name 'engineering' -ContentPath $partialPath } |
            Should -Throw -ExpectedMessage '*does not ship the mandatory*'
    }
}
