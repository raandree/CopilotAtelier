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

    function Enter-Sandbox
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.Collections.Hashtable]
            $Value
        )

        $original = @{}

        foreach ($name in $script:sandboxVariableName)
        {
            $original[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')

            [System.Environment]::SetEnvironmentVariable($name, $Value[$name], 'Process')
        }

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

    function Get-ExpectedConfigRoot
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

        # VS Code on macOS ignores XDG_CONFIG_HOME and uses Application Support.
        $isMacOSVariable = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue

        if ($isMacOSVariable -and [System.Boolean] $isMacOSVariable.Value)
        {
            return (Join-Path -Path $HomePath -ChildPath 'Library/Application Support')
        }

        return $ConfigPath
    }
}

Describe 'Get-CopilotAtelierPath' -Tag 'Unit' {
    Context 'When OneDrive is not available' {
        BeforeAll {
            $homePath = Join-Path -Path $TestDrive -ChildPath 'no-onedrive-home'
            $configPath = Join-Path -Path $TestDrive -ChildPath 'no-onedrive-config'

            New-Item -ItemType Directory -Path $homePath, $configPath -Force | Out-Null

            $original = Enter-Sandbox -Value @{
                APPDATA         = $configPath
                HOME            = $homePath
                USERPROFILE     = $homePath
                XDG_CONFIG_HOME = $configPath
            }

            try
            {
                $script:result = InModuleScope -ModuleName $script:moduleName {
                    Get-CopilotAtelierPath
                }
            }
            finally
            {
                Exit-Sandbox -Original $original
            }

            $script:homePath = $homePath
            $script:configPath = $configPath
            $script:expectedConfigRoot = Get-ExpectedConfigRoot -HomePath $homePath -ConfigPath $configPath
        }

        It 'Should fall back to the user profile' {
            $script:result.OneDriveRoot | Should -BeNullOrEmpty
            $script:result.TargetPath | Should -Be (Join-Path -Path $script:homePath -ChildPath 'CopilotAtelier')
        }

        It 'Should resolve the VS Code settings paths' {
            $expected = Join-Path -Path $script:expectedConfigRoot -ChildPath 'Code'
            $expected = Join-Path -Path $expected -ChildPath 'User'

            $script:result.SettingsDirectory | Should -Be $expected
            $script:result.SettingsPath | Should -Be (Join-Path -Path $expected -ChildPath 'settings.json')
            $script:result.KeybindingsPath | Should -Be (Join-Path -Path $expected -ChildPath 'keybindings.json')
        }

        It 'Should place the deployment record inside the target' {
            $script:result.DeploymentManifestPath |
                Should -Be (Join-Path -Path $script:result.TargetPath -ChildPath '.copilotatelier.json')
        }

        It 'Should choose the platform link type' {
            $expected = 'SymbolicLink'

            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
            {
                $expected = 'Junction'
            }

            $script:result.LinkItemType | Should -Be $expected
        }
    }

    Context 'When a single OneDrive root is available' {
        BeforeAll {
            $homePath = Join-Path -Path $TestDrive -ChildPath 'onedrive-home'
            $configPath = Join-Path -Path $TestDrive -ChildPath 'onedrive-config'
            $oneDrivePath = Join-Path -Path $homePath -ChildPath 'OneDriveCommercial'

            New-Item -ItemType Directory -Path $homePath, $configPath, $oneDrivePath -Force | Out-Null

            $original = Enter-Sandbox -Value @{
                APPDATA            = $configPath
                HOME               = $homePath
                USERPROFILE        = $homePath
                XDG_CONFIG_HOME    = $configPath
                OneDriveCommercial = $oneDrivePath
            }

            try
            {
                $script:result = InModuleScope -ModuleName $script:moduleName {
                    Get-CopilotAtelierPath
                }
            }
            finally
            {
                Exit-Sandbox -Original $original
            }

            $script:oneDrivePath = $oneDrivePath
        }

        It 'Should prefer OneDrive for the canonical target' {
            $script:result.OneDriveRoot | Should -Be $script:oneDrivePath
            $script:result.TargetPath | Should -Be (Join-Path -Path $script:oneDrivePath -ChildPath 'CopilotAtelier')
        }
    }
}
