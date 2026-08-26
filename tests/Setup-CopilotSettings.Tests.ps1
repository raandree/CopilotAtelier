BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    # The canonical target folder is the module name, not the clone folder name.
    $script:repoName = 'CopilotAtelier'

    $script:setupScript = Join-Path $script:repoRoot 'Setup-CopilotSettings.ps1'
}

Describe 'Setup-CopilotSettings' -Tag 'Integration' {
    It 'removes legacy CopilotAtelier locations and preserves unrelated locations' {
        $homePath = Join-Path $TestDrive 'cleanup-home'
        $configPath = Join-Path $TestDrive 'cleanup-config'
        $settingsDirectory = Join-Path $configPath 'Code/User'
        New-Item -ItemType Directory -Path $homePath, $settingsDirectory -Force | Out-Null

        $settingsPath = Join-Path $settingsDirectory 'settings.json'
        $seedSettings = [ordered]@{
            'chat.agentFilesLocations' = [ordered]@{
                "~/OneDrive/$($script:repoName)/Agents" = $true
                "~/$($script:repoName)/Agents" = $true
            }
            'chat.instructionsFilesLocations' = [ordered]@{
                "~/OneDrive/$($script:repoName)/Instructions" = $true
                "~/$($script:repoName)/Instructions" = $true
                '~/Other/Instructions' = $true
            }
            'chat.agentSkillsLocations' = [ordered]@{
                "~/OneDrive/$($script:repoName)/Skills" = $true
                "~/$($script:repoName)/Skills" = $true
                '~/Other/Skills' = $true
            }
            'chat.promptFilesLocations' = [ordered]@{
                "~/OneDrive/$($script:repoName)/Prompts" = $true
                "~/$($script:repoName)/Prompts" = $true
                '~/Other/Prompts' = $true
            }
        }
        $seedSettings |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $settingsPath -Encoding utf8

        $environmentNames = @(
            'APPDATA'
            'HOME'
            'OneDrive'
            'OneDriveCommercial'
            'OneDriveConsumer'
            'USERPROFILE'
            'XDG_CONFIG_HOME'
        )
        $originalEnvironment = @{}
        foreach ($name in $environmentNames) {
            $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }

        try {
            [Environment]::SetEnvironmentVariable('APPDATA', $configPath, 'Process')
            [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
            [Environment]::SetEnvironmentVariable('OneDrive', $null, 'Process')
            [Environment]::SetEnvironmentVariable('OneDriveCommercial', $null, 'Process')
            [Environment]::SetEnvironmentVariable('OneDriveConsumer', $null, 'Process')
            [Environment]::SetEnvironmentVariable('USERPROFILE', $homePath, 'Process')
            [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $configPath, 'Process')

            $powerShellPath = (Get-Process -Id $PID).Path
            $setupArguments = @(
                '-NoProfile'
                '-NonInteractive'
                '-File'
                $script:setupScript
                '-SkipCopilotCliEnvironment'
                '-Verbose'
            )
            $output = @(
                & $powerShellPath @setupArguments 2>&1
            )
            $exitCode = $LASTEXITCODE
        } finally {
            foreach ($name in $environmentNames) {
                [Environment]::SetEnvironmentVariable(
                    $name,
                    $originalEnvironment[$name],
                    'Process'
                )
            }
        }

        $outputText = $output -join [Environment]::NewLine
        $exitCode | Should -Be 0 -Because $outputText
        $outputText | Should -Match 'Skipped environment variable: COPILOT_ALLOW_ALL'

        $actualSettings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $actualSettings.PSObject.Properties.Name |
            Should -Not -Contain 'chat.agentFilesLocations'

        $locationCases = @(
            @{
                Property = 'chat.instructionsFilesLocations'
                Legacy = @(
                    "~/OneDrive/$($script:repoName)/Instructions"
                    "~/$($script:repoName)/Instructions"
                )
                Preserved = '~/Other/Instructions'
            }
            @{
                Property = 'chat.agentSkillsLocations'
                Legacy = @(
                    "~/OneDrive/$($script:repoName)/Skills"
                    "~/$($script:repoName)/Skills"
                )
                Preserved = '~/Other/Skills'
            }
            @{
                Property = 'chat.promptFilesLocations'
                Legacy = @(
                    "~/OneDrive/$($script:repoName)/Prompts"
                    "~/$($script:repoName)/Prompts"
                )
                Preserved = '~/Other/Prompts'
            }
        )

        foreach ($case in $locationCases) {
            $locationNames = @(
                $actualSettings.($case.Property).PSObject.Properties.Name
            )
            foreach ($legacyLocation in $case.Legacy) {
                $locationNames | Should -Not -Contain $legacyLocation
            }
            $locationNames | Should -Contain $case.Preserved
        }

        $promptLocationNames = @(
            $actualSettings.'chat.promptFilesLocations'.PSObject.Properties.Name
        )
        $promptLocationNames | Should -Contain '~/.copilot/prompts'
    }

    It 'uses Linux profile paths and recreates symbolic links' -Skip:(
        [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    ) {
        $homePath = Join-Path $TestDrive 'home'
        $configPath = Join-Path $TestDrive 'config'
        $ignoredAppDataPath = Join-Path $TestDrive 'appdata'
        New-Item -ItemType Directory -Path $homePath, $configPath, $ignoredAppDataPath -Force | Out-Null

        $environmentNames = @(
            'APPDATA'
            'HOME'
            'OneDrive'
            'OneDriveCommercial'
            'OneDriveConsumer'
            'USERPROFILE'
            'XDG_CONFIG_HOME'
        )
        $originalEnvironment = @{}
        foreach ($name in $environmentNames) {
            $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }

        try {
            [Environment]::SetEnvironmentVariable('APPDATA', $ignoredAppDataPath, 'Process')
            [Environment]::SetEnvironmentVariable('HOME', $homePath, 'Process')
            [Environment]::SetEnvironmentVariable('OneDrive', $null, 'Process')
            [Environment]::SetEnvironmentVariable('OneDriveCommercial', $null, 'Process')
            [Environment]::SetEnvironmentVariable('OneDriveConsumer', $null, 'Process')
            [Environment]::SetEnvironmentVariable('USERPROFILE', $null, 'Process')
            [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $configPath, 'Process')

            $powerShellPath = (Get-Process -Id $PID).Path
            $setupArguments = @(
                '-NoProfile'
                '-NonInteractive'
                '-File'
                $script:setupScript
                '-SkipCopilotCliEnvironment'
                '-Verbose'
            )
            $firstOutput = @(
                & $powerShellPath @setupArguments 2>&1
            )
            $firstExitCode = $LASTEXITCODE

            $secondOutput = @(
                & $powerShellPath @setupArguments 2>&1
            )
            $secondExitCode = $LASTEXITCODE
        } finally {
            foreach ($name in $environmentNames) {
                [Environment]::SetEnvironmentVariable(
                    $name,
                    $originalEnvironment[$name],
                    'Process'
                )
            }
        }

        $firstOutputText = $firstOutput -join [Environment]::NewLine
        $secondOutputText = $secondOutput -join [Environment]::NewLine
        $firstExitCode | Should -Be 0 -Because $firstOutputText
        $secondExitCode | Should -Be 0 -Because $secondOutputText

        $settingsPath = Join-Path $configPath 'Code/User/settings.json'
        $keybindingsPath = Join-Path $configPath 'Code/User/keybindings.json'
        Test-Path -LiteralPath $settingsPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $keybindingsPath -PathType Leaf | Should -BeTrue

        $targetPath = Join-Path $homePath 'CopilotAtelier'
        Test-Path -LiteralPath (Join-Path $targetPath 'agents') -PathType Container |
            Should -BeTrue

        $agentLinkPath = Join-Path $homePath '.copilot/agents'
        $agentLink = Get-Item -LiteralPath $agentLinkPath -Force
        $agentLink.LinkType | Should -Be 'SymbolicLink'
    }
}
