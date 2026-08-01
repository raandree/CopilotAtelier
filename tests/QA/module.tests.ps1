BeforeDiscovery {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../..')
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

    Remove-Module -Name $script:moduleName -Force -ErrorAction SilentlyContinue

    $script:moduleUnderTest = Import-Module -Name $builtManifest[0].FullName -Force -PassThru -ErrorAction Stop

    $script:functionTestCase = @(
        Get-Command -Module $script:moduleUnderTest -CommandType Function |
            ForEach-Object -Process {
                @{
                    Name = $_.Name
                }
            }
    )
}

BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:moduleName = 'CopilotAtelier'
    $script:sourcePath = Join-Path -Path $script:projectPath -ChildPath 'source'
}

Describe 'Changelog management' -Tag 'QA' {
    It 'Should parse as a Keep a Changelog document' {
        { Get-ChangelogData -Path (Join-Path -Path $script:projectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'Should have an Unreleased section' {
        $changelog = Get-ChangelogData -Path (Join-Path -Path $script:projectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop

        $changelog.Unreleased | Should -Not -BeNullOrEmpty
    }

    It 'Should keep the Unreleased section within the GitHub release body limit' {
        <#
            Publish_Release_To_GitHub sends this section as the release body, and
            the REST API rejects a body over 125000 characters with HTTP 422 after
            the release tag has already been created. Fail here, with headroom.
        #>
        $changelog = Get-ChangelogData -Path (Join-Path -Path $script:projectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop

        $changelog.Unreleased.RawData.Length |
            Should -BeLessThan 100000 -Because 'the GitHub release body limit is 125000 characters; cut a release before then'
    }
}

Describe 'Release versioning' -Tag 'QA' {
    BeforeAll {
        $script:gitVersionConfiguration = Get-Content -Raw -LiteralPath (Join-Path -Path $script:projectPath -ChildPath 'GitVersion.yml') |
            ConvertFrom-Yaml
    }

    It 'Should configure a branch matching the synthetic branch name of a tag build' {
        # A tag push checks out refs/tags/<tag>, so GitVersion versions a 'tags/<tag>' branch.
        $matchingBranch = @(
            $script:gitVersionConfiguration.branches.Values |
                Where-Object -FilterScript {
                    $_.regex -and 'tags/v2.0.0' -match $_.regex
                }
        )

        $matchingBranch | Should -Not -BeNullOrEmpty -Because 'GitVersion aborts a tag build when no branch configuration matches'
    }
}

Describe 'General module control' -Tag 'QA' {
    It 'Should import without errors' {
        { Import-Module -Name $script:moduleName -Force -ErrorAction Stop } | Should -Not -Throw

        Get-Module -Name $script:moduleName | Should -Not -BeNullOrEmpty
    }

    It 'Should export exactly the documented commands' {
        $expected = @(
            'Get-CopilotAtelierVersion'
            'Install-CopilotAtelier'
            'Update-CopilotAtelier'
        )

        $actual = @(
            (Get-Command -Module $script:moduleName -CommandType Function).Name |
                Sort-Object
        )

        $actual | Should -Be $expected
    }

    It 'Should ship the customization directories inside the built module' {
        $moduleBase = (Get-Module -Name $script:moduleName).ModuleBase

        foreach ($directoryName in @('Agents', 'Instructions', 'Skills', 'Prompts', 'Hooks', 'Keybindings'))
        {
            $directoryPath = Join-Path -Path $moduleBase -ChildPath $directoryName

            Test-Path -LiteralPath $directoryPath -PathType Container |
                Should -BeTrue -Because "'$directoryName' is part of the distributed payload"

            @(Get-ChildItem -LiteralPath $directoryPath -Recurse -File) |
                Should -Not -BeNullOrEmpty -Because "'$directoryName' must not be shipped empty"
        }
    }
}

Describe 'Quality for module' -Tag 'QA' {
    It 'Should have a unit test for <Name>' -ForEach $script:functionTestCase {
        $testPath = Join-Path -Path $script:projectPath -ChildPath 'tests'

        @(Get-ChildItem -Path $testPath -Recurse -Filter "$Name.Tests.ps1") |
            Should -Not -BeNullOrEmpty
    }

    It 'Should pass PSScriptAnalyzer for <Name>' -ForEach $script:functionTestCase -Skip:(-not (Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
        $functionFile = Get-ChildItem -Path $script:sourcePath -Recurse -Filter "$Name.ps1"

        $analyzerResult = @(Invoke-ScriptAnalyzer -Path $functionFile.FullName)
        $report = $analyzerResult | Format-Table -AutoSize | Out-String -Width 120

        $analyzerResult | Should -BeNullOrEmpty -Because "some rule triggered.`r`n`r`n$report"
    }
}

Describe 'Help for module' -Tag 'QA' {
    BeforeAll {
        function Get-ParsedFunction
        {
            param
            (
                [Parameter(Mandatory = $true)]
                [System.String]
                $FunctionName,

                [Parameter(Mandatory = $true)]
                [System.String]
                $SourcePath
            )

            $functionFile = Get-ChildItem -Path $SourcePath -Recurse -Filter "$FunctionName.ps1"

            $scriptContent = Get-Content -Raw -Path $functionFile.FullName

            $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput(
                $scriptContent, [ref] $null, [ref] $null
            )

            return $abstractSyntaxTree.FindAll(
                {
                    $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true
            ) |
                Where-Object -FilterScript {
                    $_.Name -eq $FunctionName
                }
        }
    }

    It 'Should have a .SYNOPSIS for <Name>' -ForEach $script:functionTestCase {
        $help = (Get-ParsedFunction -FunctionName $Name -SourcePath $script:sourcePath).GetHelpContent()

        $help.Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'Should have a .DESCRIPTION longer than 40 characters for <Name>' -ForEach $script:functionTestCase {
        $help = (Get-ParsedFunction -FunctionName $Name -SourcePath $script:sourcePath).GetHelpContent()

        $help.Description.Length | Should -BeGreaterThan 40
    }

    It 'Should have at least one .EXAMPLE for <Name>' -ForEach $script:functionTestCase {
        $help = (Get-ParsedFunction -FunctionName $Name -SourcePath $script:sourcePath).GetHelpContent()

        $help.Examples.Count | Should -BeGreaterThan 0
    }

    It 'Should document every parameter of <Name>' -ForEach $script:functionTestCase {
        $parsedFunction = Get-ParsedFunction -FunctionName $Name -SourcePath $script:sourcePath
        $help = $parsedFunction.GetHelpContent()

        $commonParameter = [System.Management.Automation.PSCmdlet]::CommonParameters +
            [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

        $parameterName = @(
            (Get-Command -Name $Name -Module $script:moduleName).Parameters.Keys |
                Where-Object -FilterScript {
                    $_ -notin $commonParameter
                }
        )

        foreach ($name in $parameterName)
        {
            $help.Parameters.($name.ToUpper()) | Should -Not -BeNullOrEmpty -Because "the parameter '$name' must be documented"
        }
    }
}
