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
}

Describe 'ConvertFrom-CopilotAtelierVersion' -Tag 'Unit' {
    It 'Should split <Text> into <Number> and the label <Label>' -ForEach @(
        @{ Text = '6.1.0-preview0024'; Number = '6.1.0'; Label = 'preview0024' }
        @{ Text = '6.0.0'; Number = '6.0.0'; Label = '' }
        @{ Text = '1.0.0-rc.1+build.5'; Number = '1.0.0'; Label = 'rc.1' }
    ) {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Text = $Text } -ScriptBlock {
            param ($Text)

            ConvertFrom-CopilotAtelierVersion -Version $Text
        }

        $result.Version | Should -BeOfType ([System.Version])
        $result.Version.ToString() | Should -BeExactly $Number
        $result.Prerelease | Should -BeExactly $Label
    }

    It 'Should reject <Text>, which is not a module version' -ForEach @(
        @{ Text = 'preview0024' }
        @{ Text = '6' }
        @{ Text = '6.1.0-' }
        # ARABIC-INDIC DIGIT SIX: a Unicode digit that System.Version does not accept.
        @{ Text = ('{0}.1.0' -f [char] 0x0666) }
    ) {
        {
            InModuleScope -ModuleName $script:moduleName -Parameters @{ Text = $Text } -ScriptBlock {
                param ($Text)

                ConvertFrom-CopilotAtelierVersion -Version $Text
            }
        } | Should -Throw -ExpectedMessage "*'$Text' is not a module version*"
    }
}

Describe 'Compare-CopilotAtelierVersion' -Tag 'Unit' {
    It 'Should rank <Version> <Relation> <OtherVersion>' -ForEach @(
        @{ Version = '6.1.0-preview0024'; OtherVersion = '6.1.0-preview0018'; Relation = 'above'; Expected = 1 }
        @{ Version = '6.1.0-preview0018'; OtherVersion = '6.1.0-preview0024'; Relation = 'below'; Expected = -1 }
        @{ Version = '6.1.0'; OtherVersion = '6.1.0-preview0024'; Relation = 'above'; Expected = 1 }
        @{ Version = '6.1.0-preview0001'; OtherVersion = '6.0.0'; Relation = 'above'; Expected = 1 }
        @{ Version = '10.0.0'; OtherVersion = '9.1.0'; Relation = 'above'; Expected = 1 }
        @{ Version = '6.1.0-preview0024'; OtherVersion = '6.1.0-preview0024'; Relation = 'equal to'; Expected = 0 }
        @{ Version = '6.1'; OtherVersion = '6.1.0'; Relation = 'equal to'; Expected = 0 }
    ) {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Version = $Version; OtherVersion = $OtherVersion } -ScriptBlock {
            param ($Version, $OtherVersion)

            Compare-CopilotAtelierVersion -Version $Version -OtherVersion $OtherVersion
        }

        $result | Should -Be $Expected
    }

    It 'Should order the Semantic Versioning 2.0.0 precedence example from lowest to highest' {
        # The example chain of semver.org, section 11, plus the release it leads to.
        $chain = @('1.0.0-alpha', '1.0.0-alpha.1', '1.0.0-alpha.beta', '1.0.0-beta', '1.0.0-beta.2', '1.0.0-beta.11', '1.0.0-rc.1', '1.0.0')

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Chain = $chain } -ScriptBlock {
            param ($Chain)

            for ($index = 1; $index -lt $Chain.Count; $index++)
            {
                '{0} > {1}: {2}' -f $Chain[$index], $Chain[$index - 1], (Compare-CopilotAtelierVersion -Version $Chain[$index] -OtherVersion $Chain[$index - 1])
                '{0} < {1}: {2}' -f $Chain[$index - 1], $Chain[$index], (Compare-CopilotAtelierVersion -Version $Chain[$index - 1] -OtherVersion $Chain[$index])
            }
        }

        $expected = for ($index = 1; $index -lt $chain.Count; $index++)
        {
            '{0} > {1}: 1' -f $chain[$index], $chain[$index - 1]
            '{0} < {1}: -1' -f $chain[$index - 1], $chain[$index]
        }

        $result | Should -Be $expected
    }
}

Describe 'Get-CopilotAtelierModuleVersion' -Tag 'Unit' {
    BeforeAll {
        $script:fixtureName = 'CopilotAtelierVersionFixture'
    }

    AfterEach {
        Remove-Module -Name $script:fixtureName -Force -ErrorAction SilentlyContinue
    }

    It 'Should report <Expected> for a manifest whose prerelease label is ''<Label>''' -ForEach @(
        @{ Label = 'preview0007'; Expected = '1.2.3-preview0007' }
        @{ Label = ''; Expected = '1.2.3' }
    ) {
        $fixturePath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixturePath -Force | Out-Null
        $manifestPath = Join-Path -Path $fixturePath -ChildPath "$script:fixtureName.psd1"
        Set-Content -LiteralPath $manifestPath -Value @"
@{
    ModuleVersion = '1.2.3'
    GUID          = '6c3f1b6e-0a51-4bc0-9f7a-2f8d6f0a7e11'
    PrivateData   = @{ PSData = @{ Prerelease = '$Label' } }
}
"@
        $fixture = Import-Module -Name $manifestPath -Force -PassThru -ErrorAction Stop

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Fixture = $fixture } -ScriptBlock {
            param ($Fixture)

            Get-CopilotAtelierModuleVersion -Module $Fixture
        }

        $result | Should -BeExactly $Expected
    }

    It 'Should read the module it belongs to by default' {
        $moduleVersion = (Get-Module -Name $script:moduleName).Version.ToString()

        $result = InModuleScope -ModuleName $script:moduleName -ScriptBlock {
            Get-CopilotAtelierModuleVersion
        }

        # The build may add a prerelease label, so only the numeric part is fixed.
        $result | Should -BeLike "$moduleVersion*"
    }

    It 'Should return nothing without a module, as when the commands are dot-sourced from a clone' {
        $result = InModuleScope -ModuleName $script:moduleName -ScriptBlock {
            Get-CopilotAtelierModuleVersion -Module $null
        }

        $result | Should -BeNullOrEmpty
    }
}
