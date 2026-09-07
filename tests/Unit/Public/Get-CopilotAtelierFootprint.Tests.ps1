BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    function New-FootprintContent
    {
        param ([Parameter(Mandatory = $true)] [System.String] $Root)

        foreach ($directory in @('com.github.copilot/rules', 'skills/demo', 'com.github.copilot/agents', 'com.github.copilot/commands', 'com.github.copilot/hooks'))
        {
            New-Item -ItemType Directory -Path (Join-Path $Root $directory) -Force | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $Root 'com.github.copilot/rules/broad.instructions.md') -Encoding utf8 -Value @('---'; 'applyTo: "**"'; '---'; 'Always on.')
        Set-Content -LiteralPath (Join-Path $Root 'skills/demo/SKILL.md') -Encoding utf8 -Value @('---'; 'name: demo'; 'description: "demo"'; '---'; 'Body.')
        Set-Content -LiteralPath (Join-Path $Root 'com.github.copilot/agents/role.agent.md') -Encoding utf8 -Value @('---'; 'description: role'; '---'; 'Agent.')
        Set-Content -LiteralPath (Join-Path $Root 'com.github.copilot/commands/task.prompt.md') -Encoding utf8 -Value 'Prompt.'
        Set-Content -LiteralPath (Join-Path $Root 'com.github.copilot/hooks/hooks.json') -Encoding utf8 -Value '{ "hooks": {} }'
    }
}

Describe 'Get-CopilotAtelierFootprint' -Tag 'Unit' {
    BeforeEach {
        $script:content = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-FootprintContent -Root $script:content
    }

    It 'Should return a structured report with loading estimates for an explicit content path' {
        $result = Get-CopilotAtelierFootprint -ContentPath $script:content

        $result.ContentPath | Should -Be ([System.IO.Path]::GetFullPath($script:content).TrimEnd([char[]] '\/'))
        $result.Loading.AlwaysLoadedEstimateByte | Should -BeGreaterThan 0
        $result.Loading.ExecutedNotLoadedByte | Should -Be (Get-Item -LiteralPath (Join-Path $script:content 'com.github.copilot/hooks/hooks.json')).Length
        $result.Disclaimer | Should -Match 'estimate'
    }

    It 'Should throw a directed error when the content path is missing' {
        { Get-CopilotAtelierFootprint -ContentPath (Join-Path $TestDrive 'does-not-exist') } |
            Should -Throw -ExpectedMessage '*does not exist*'
    }

    It 'Should return a human-readable summary with -AsText' {
        $text = Get-CopilotAtelierFootprint -ContentPath $script:content -AsText

        $text | Should -BeOfType [System.String]
        $text | Should -Match 'Customization footprint report'
        $text | Should -Match 'Opportunities to reduce unnecessary loading'
        $text | Should -Match 'not measured session loading'
    }

    It 'Should describe automatic loading as potential in the text summary, not as observed per-session loading' {
        $text = Get-CopilotAtelierFootprint -ContentPath $script:content -AsText

        $text | Should -Not -Match 'Always loaded per session'
        $text | Should -Match 'Potential'
    }

    It 'Should describe automatic loading as potential and contingent in its help, not as content kept every session' {
        $help = Get-Help -Name Get-CopilotAtelierFootprint -Full | Out-String

        $help | Should -Not -Match 'keeps in every session'
        $help | Should -Match 'potential|contingent'
    }

    It 'Should not depend on environment variables' {
        $result1 = Get-CopilotAtelierFootprint -ContentPath $script:content
        $originalHome = [System.Environment]::GetEnvironmentVariable('HOME', 'Process')
        $originalOneDrive = [System.Environment]::GetEnvironmentVariable('OneDrive', 'Process')
        try
        {
            [System.Environment]::SetEnvironmentVariable('HOME', (Join-Path $TestDrive 'other-home'), 'Process')
            [System.Environment]::SetEnvironmentVariable('OneDrive', (Join-Path $TestDrive 'other-onedrive'), 'Process')
            $result2 = Get-CopilotAtelierFootprint -ContentPath $script:content
        }
        finally
        {
            [System.Environment]::SetEnvironmentVariable('HOME', $originalHome, 'Process')
            [System.Environment]::SetEnvironmentVariable('OneDrive', $originalOneDrive, 'Process')
        }

        ($result1 | ConvertTo-Json -Depth 8) | Should -Be ($result2 | ConvertTo-Json -Depth 8)
    }

    It 'Should not modify the content it inspects' {
        $before = @(Get-ChildItem -LiteralPath $script:content -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" })

        $null = Get-CopilotAtelierFootprint -ContentPath $script:content

        $after = @(Get-ChildItem -LiteralPath $script:content -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" })
        $after | Should -Be $before
    }

    It 'Should default to the shipped content root when no path is given' {
        $result = Get-CopilotAtelierFootprint

        $result.TotalByte | Should -BeGreaterThan 0
        @($result.Directories | Where-Object { $_.DeployedDirectory -eq 'skills' -and $_.FileCount -gt 0 }) | Should -Not -BeNullOrEmpty
    }
}
