BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:setupScript = Join-Path $script:repoRoot 'Setup-CopilotSettings.ps1'
}

Describe 'Setup-CopilotSettings' -Tag 'Integration' {
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
            $firstOutput = @(
                & $powerShellPath -NoProfile -NonInteractive -File $script:setupScript 2>&1
            )
            $firstExitCode = $LASTEXITCODE

            $secondOutput = @(
                & $powerShellPath -NoProfile -NonInteractive -File $script:setupScript 2>&1
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
        Test-Path -LiteralPath (Join-Path $targetPath 'Agents') -PathType Container |
            Should -BeTrue

        $agentLinkPath = Join-Path $homePath '.copilot/agents'
        $agentLink = Get-Item -LiteralPath $agentLinkPath -Force
        $agentLink.LinkType | Should -Be 'SymbolicLink'
    }
}
