BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')
    $script:moduleName = 'CopilotAtelier'

    # The subdirectory under output/ is a Sampler setting, so it is matched rather than hard-coded.
    $builtManifest = @(
        Get-ChildItem -Path (Join-Path -Path $script:projectPath -ChildPath "output/*/$script:moduleName/*/$script:moduleName.psd1") -ErrorAction SilentlyContinue |
            Sort-Object -Property { [System.Version] $_.Directory.Name } -Descending
    )

    if (-not $builtManifest)
    {
        throw "The built module '$script:moduleName' was not found. Run './build.ps1 -Tasks build' first."
    }

    Import-Module -Name $builtManifest[0].FullName -Force -ErrorAction Stop

    $script:sandboxVariableName = @(
        'APPDATA'
        'HOME'
        'OneDrive'
        'OneDriveCommercial'
        'OneDriveConsumer'
        'USERPROFILE'
        'XDG_CONFIG_HOME'
    )

    function Initialize-CustomizationContent
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.String]
            $Path
        )

        foreach ($directoryName in @('com.github.copilot/agents', 'com.github.copilot/rules', 'skills', 'com.github.copilot/commands', 'com.github.copilot/hooks'))
        {
            $directoryPath = Join-Path -Path $Path -ChildPath $directoryName

            New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null

            Set-Content -LiteralPath (Join-Path -Path $directoryPath -ChildPath 'marker.md') -Value "# $directoryName"
        }

        $keybindingPath = Join-Path -Path $Path -ChildPath 'keybindings'

        New-Item -ItemType Directory -Path $keybindingPath -Force | Out-Null

        @'
// A repository keybinding.
[
    { "key": "ctrl+k x", "command": "workbench.action.test" }
]
'@ | Set-Content -LiteralPath (Join-Path -Path $keybindingPath -ChildPath 'keybindings.json')
    }

    function Enter-Sandbox
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.String]
            $HomePath,

            [Parameter(Mandatory = $true)]
            [System.String]
            $ConfigPath
        )

        $original = @{}

        foreach ($name in $script:sandboxVariableName)
        {
            $original[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')
        }

        New-Item -ItemType Directory -Path $HomePath, $ConfigPath -Force | Out-Null

        [System.Environment]::SetEnvironmentVariable('APPDATA', $ConfigPath, 'Process')
        [System.Environment]::SetEnvironmentVariable('HOME', $HomePath, 'Process')
        [System.Environment]::SetEnvironmentVariable('OneDrive', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('OneDriveCommercial', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('OneDriveConsumer', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('USERPROFILE', $HomePath, 'Process')
        [System.Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $ConfigPath, 'Process')

        return $original
    }

    function Exit-Sandbox
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
}

Describe 'Install-CopilotAtelier' -Tag 'Unit' {
    Context 'When deploying into a clean profile' {
        BeforeAll {
            $script:contentPath = Join-Path -Path $TestDrive -ChildPath 'content'
            $script:homePath = Join-Path -Path $TestDrive -ChildPath 'clean-home'
            $script:configPath = Join-Path -Path $TestDrive -ChildPath 'clean-config'

            Initialize-CustomizationContent -Path $script:contentPath

            $script:original = Enter-Sandbox -HomePath $script:homePath -ConfigPath $script:configPath

            try
            {
                $script:result = Install-CopilotAtelier -ContentPath $script:contentPath -SkipCopilotCliEnvironment
            }
            finally
            {
                Exit-Sandbox -Original $script:original
            }

            $script:targetPath = Join-Path -Path $script:homePath -ChildPath 'CopilotAtelier'
            $script:settingsPath = $script:result.SettingsPath
            $script:settingsDirectory = Split-Path -Path $script:settingsPath -Parent
            $script:settings = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        }

        It 'Should report the canonical target' {
            $script:result.TargetPath | Should -Be $script:targetPath
        }

        It 'Should copy <_> to the canonical target' -ForEach @('agents', 'instructions', 'skills', 'prompts', 'hooks') {
            $markerPath = Join-Path -Path (Join-Path -Path $script:targetPath -ChildPath $_) -ChildPath 'marker.md'

            Test-Path -LiteralPath $markerPath -PathType Leaf | Should -BeTrue
        }

        It 'Should record the deployed version' {
            $manifestPath = Join-Path -Path $script:targetPath -ChildPath '.copilotatelier.json'

            Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue

            $manifestText = Get-Content -LiteralPath $manifestPath -Raw
            $deployment = $manifestText | ConvertFrom-Json

            $deployment.Version | Should -Be (Get-Module -Name $script:moduleName).Version.ToString()
            $deployment.ContentPath | Should -Be $script:contentPath
            $manifestText | Should -Match '"InstalledOn":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        }

        It 'Should enable <Name>' -ForEach @(
            @{ Name = 'chat.includeApplyingInstructions'; Value = $true }
            @{ Name = 'chat.includeReferencedInstructions'; Value = $true }
            @{ Name = 'github.copilot.chat.agent.thinkingTool'; Value = $true }
            @{ Name = 'github.copilot.chat.search.semanticTextResults'; Value = $true }
            @{ Name = 'github.copilot.chat.skillTool.enabled'; Value = $true }
            @{ Name = 'github.copilot.chat.agent.maxRequests'; Value = 500 }
            @{ Name = 'gitlens.ai.vscode.model'; Value = 'copilot:claude-opus-5' }
        ) {
            $script:settings.$Name | Should -Be $Value
        }

        It 'Should register the prompt and hook discovery locations' {
            $script:settings.'chat.promptFilesLocations'.PSObject.Properties.Name |
                Should -Contain '~/.copilot/prompts'

            $script:settings.'chat.hookFilesLocations'.PSObject.Properties.Name |
                Should -Contain '~/.copilot/hooks'
        }

        It 'Should merge the repository keybindings' {
            $keybindingPath = Join-Path -Path $script:settingsDirectory -ChildPath 'keybindings.json'

            $keybinding = @(Get-Content -LiteralPath $keybindingPath -Raw | ConvertFrom-Json)

            $keybinding.command | Should -Contain 'workbench.action.test'
        }

        It 'Should link <_> under the Copilot discovery root' -ForEach @('agents', 'instructions', 'skills', 'prompts', 'hooks') {
            $linkPath = Join-Path -Path (Join-Path -Path $script:homePath -ChildPath '.copilot') -ChildPath $_

            Test-Path -LiteralPath $linkPath | Should -BeTrue

            $link = Get-Item -LiteralPath $linkPath -Force

            $link.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) | Should -BeTrue
        }
    }

    Context 'When legacy location settings are present' {
        BeforeAll {
            $script:contentPath = Join-Path -Path $TestDrive -ChildPath 'legacy-content'
            $script:homePath = Join-Path -Path $TestDrive -ChildPath 'legacy-home'
            $script:configPath = Join-Path -Path $TestDrive -ChildPath 'legacy-config'

            Initialize-CustomizationContent -Path $script:contentPath

            $script:original = Enter-Sandbox -HomePath $script:homePath -ConfigPath $script:configPath

            try
            {
                # The VS Code configuration root is platform-specific, so the resolver decides where to seed.
                $settingsDirectory = (
                    InModuleScope -ModuleName $script:moduleName { Get-CopilotAtelierPath }
                ).SettingsDirectory

                New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null

                [ordered] @{
                    'chat.agentFilesLocations'        = [ordered] @{
                        '~/OneDrive/CopilotAtelier/Agents' = $true
                        '~/CopilotAtelier/Agents'          = $true
                    }
                    'chat.instructionsFilesLocations' = [ordered] @{
                        '~/CopilotAtelier/Instructions' = $true
                        '~/Other/Instructions'          = $true
                    }
                    'github.copilot.advanced.model'   = 'claude-opus-4.8'
                } |
                    ConvertTo-Json -Depth 5 |
                    Set-Content -LiteralPath (Join-Path -Path $settingsDirectory -ChildPath 'settings.json')

                Install-CopilotAtelier -ContentPath $script:contentPath -SkipCopilotCliEnvironment | Out-Null
            }
            finally
            {
                Exit-Sandbox -Original $script:original
            }

            $script:settings = Get-Content -LiteralPath (Join-Path -Path $settingsDirectory -ChildPath 'settings.json') -Raw |
                ConvertFrom-Json
        }

        It 'Should remove a location map that only held repository entries' {
            $script:settings.PSObject.Properties.Name | Should -Not -Contain 'chat.agentFilesLocations'
        }

        It 'Should remove repository entries but keep unrelated ones' {
            $locationName = @($script:settings.'chat.instructionsFilesLocations'.PSObject.Properties.Name)

            $locationName | Should -Not -Contain '~/CopilotAtelier/Instructions'
            $locationName | Should -Contain '~/Other/Instructions'
        }

        It 'Should remove the inert completions model key' {
            $script:settings.PSObject.Properties.Name | Should -Not -Contain 'github.copilot.advanced.model'
        }
    }

    Context 'When the content path holds no customization directory' {
        It 'Should throw a directed error' {
            $emptyPath = Join-Path -Path $TestDrive -ChildPath 'empty-content'

            New-Item -ItemType Directory -Path $emptyPath -Force | Out-Null

            { Install-CopilotAtelier -ContentPath $emptyPath -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage "*No customization directory found*"
        }
    }
}
