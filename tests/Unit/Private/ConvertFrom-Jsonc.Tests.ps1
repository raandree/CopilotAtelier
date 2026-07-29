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

Describe 'ConvertFrom-Jsonc' -Tag 'Unit' {
    It 'Should ignore a full-line comment' {
        InModuleScope -ModuleName $script:moduleName {
            $result = ConvertFrom-Jsonc -Text "// header`n{ `"a`": 1 }"

            $result.a | Should -Be 1
        }
    }

    It 'Should ignore a block comment' {
        InModuleScope -ModuleName $script:moduleName {
            $result = ConvertFrom-Jsonc -Text '/* block
                                                comment */ { "a": 1 }'

            $result.a | Should -Be 1
        }
    }

    It 'Should tolerate a trailing comma before a closing brace or bracket' {
        InModuleScope -ModuleName $script:moduleName {
            $result = ConvertFrom-Jsonc -Text '{ "a": [ 1, 2, ], }'

            $result.a | Should -Be @(1, 2)
        }
    }

    It 'Should keep a URL inside a string value' {
        InModuleScope -ModuleName $script:moduleName {
            $result = ConvertFrom-Jsonc -Text '{ "a": "https://example.com/x" }'

            $result.a | Should -Be 'https://example.com/x'
        }
    }

    It 'Should return nothing for an empty document' {
        InModuleScope -ModuleName $script:moduleName {
            ConvertFrom-Jsonc -Text '' | Should -BeNullOrEmpty
        }
    }

    It 'Should return nothing for a comment-only document' {
        InModuleScope -ModuleName $script:moduleName {
            ConvertFrom-Jsonc -Text '// nothing here' | Should -BeNullOrEmpty
        }
    }
}
