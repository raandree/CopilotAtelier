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

Describe 'Get-CopilotAtelierVersion' -Tag 'Unit' {
    Context 'When nothing has been deployed yet' {
        BeforeAll {
            $homePath = Join-Path -Path $TestDrive -ChildPath 'empty-home'
            $configPath = Join-Path -Path $TestDrive -ChildPath 'empty-config'

            $original = Enter-Sandbox -HomePath $homePath -ConfigPath $configPath

            try
            {
                $script:result = Get-CopilotAtelierVersion
            }
            finally
            {
                Exit-Sandbox -Original $original
            }
        }

        It 'Should report the module version' {
            $script:result.Version | Should -Be (Get-Module -Name $script:moduleName).Version
        }

        It 'Should report no deployed version' {
            $script:result.DeployedVersion | Should -BeNullOrEmpty
            $script:result.DeployedOn | Should -BeNullOrEmpty
        }

        It 'Should not claim the deployment is current' {
            $script:result.IsCurrent | Should -BeNullOrEmpty
        }
    }

    Context 'When a deployment record exists' {
        BeforeAll {
            $homePath = Join-Path -Path $TestDrive -ChildPath 'deployed-home'
            $configPath = Join-Path -Path $TestDrive -ChildPath 'deployed-config'
            $targetPath = Join-Path -Path $homePath -ChildPath 'CopilotAtelier'

            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null

            $script:moduleVersion = (Get-Module -Name $script:moduleName).Version.ToString()

            [ordered] @{
                Version     = $script:moduleVersion
                InstalledOn = '2026-07-29T08:41:00Z'
                ContentPath = 'C:\somewhere'
            } |
                ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path -Path $targetPath -ChildPath '.copilotatelier.json')

            $original = Enter-Sandbox -HomePath $homePath -ConfigPath $configPath

            try
            {
                $script:result = Get-CopilotAtelierVersion
            }
            finally
            {
                Exit-Sandbox -Original $original
            }
        }

        It 'Should report the deployed version and timestamp' {
            $script:result.DeployedVersion | Should -Be $script:moduleVersion
            $script:result.DeployedOn.Kind | Should -Be 'Utc'
            $script:result.DeployedOn.ToString('yyyy-MM-ddTHH:mm:ss') | Should -Be '2026-07-29T08:41:00'
        }

        It 'Should report the deployment as current' {
            $script:result.IsCurrent | Should -BeTrue
        }
    }

    Context 'When the deployed version is behind the module' {
        BeforeAll {
            $homePath = Join-Path -Path $TestDrive -ChildPath 'stale-home'
            $configPath = Join-Path -Path $TestDrive -ChildPath 'stale-config'
            $targetPath = Join-Path -Path $homePath -ChildPath 'CopilotAtelier'

            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null

            [ordered] @{
                Version     = '0.0.1'
                InstalledOn = '2026-01-01T00:00:00Z'
                ContentPath = 'C:\somewhere'
            } |
                ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path -Path $targetPath -ChildPath '.copilotatelier.json')

            $original = Enter-Sandbox -HomePath $homePath -ConfigPath $configPath

            try
            {
                $script:result = Get-CopilotAtelierVersion
            }
            finally
            {
                Exit-Sandbox -Original $original
            }
        }

        It 'Should report the deployment as stale' {
            $script:result.IsCurrent | Should -BeFalse
        }
    }
}
