# Testing Patterns

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Test Directory Structure
- Unit Test Template (Pester 5)
- QA Module Test Pattern
- Integration Test Pattern
- Pester Configuration in build.yaml
- Running Tests

### Test Directory Structure

```text
tests/
├── QA/
│   └── module.tests.ps1          # Quality assurance (PSScriptAnalyzer, help)
├── Unit/
│   ├── Public/
│   │   ├── Get-Widget.tests.ps1  # One test file per public function
│   │   └── Set-Widget.tests.ps1
│   └── Private/
│       └── ConvertTo-InternalFormat.tests.ps1
└── Integration/
    └── MyModule.Integration.tests.ps1
```

### Unit Test Template (Pester 5)

```powershell
BeforeAll {
    $script:moduleName = 'MyModule'

    # Build through the detached wrapper before invoking Pester.
    if (-not (Get-Module -Name $script:moduleName -ListAvailable)) {
        throw "Module '$script:moduleName' is unavailable. Run the detached build workflow first."
    }

    Import-Module -Name $script:moduleName -Force -ErrorAction 'Stop'
}

AfterAll {
    Remove-Module -Name $script:moduleName -Force
}

Describe 'Get-Widget' -Tag 'Unit' {

    Context 'When called with a valid name' {
        BeforeAll {
            Mock -ModuleName $script:moduleName -CommandName 'Invoke-RestMethod' -MockWith {
                return @{ Name = 'TestWidget'; Status = 'Active' }
            }

            $script:result = Get-Widget -Name 'TestWidget'
        }

        It 'Should return the widget' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'Should have the correct name' {
            $script:result.Name | Should -Be 'TestWidget'
        }

        It 'Should call the REST API exactly once' {
            Should -Invoke -ModuleName $script:moduleName -CommandName 'Invoke-RestMethod' -Times 1 -Exactly
        }
    }

    Context 'When the widget does not exist' {
        BeforeAll {
            Mock -ModuleName $script:moduleName -CommandName 'Invoke-RestMethod' -MockWith {
                throw [System.Net.WebException]::new('404 Not Found')
            }
        }

        It 'Should throw an error' {
            { Get-Widget -Name 'NonExistent' } | Should -Throw
        }
    }
}
```

### QA Module Test Pattern

```powershell
BeforeDiscovery {
    $ProjectPath = "$PSScriptRoot\..\.." | Convert-Path
    $ProjectName = (Get-ChildItem $ProjectPath\*\*.psd1 | Where-Object {
            ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) -and
            $(try { Test-ModuleManifest $_.FullName -ErrorAction Stop } catch { $false })
        }
    ).BaseName

    Import-Module -Name $ProjectName -Force -ErrorAction 'Stop'
}

Describe 'Module Quality Tests' -Tag 'QA' {
    It 'Should have a valid module manifest' {
        $manifestPath = "$PSScriptRoot\..\..\source\$ProjectName.psd1"
        { Test-ModuleManifest -Path $manifestPath } | Should -Not -Throw
    }

    It 'Should pass all PSScriptAnalyzer rules' {
        $sourcePath = "$PSScriptRoot\..\..\source"
        $results = Invoke-ScriptAnalyzer -Path $sourcePath -Recurse -Severity 'Error'
        $results | Should -BeNullOrEmpty
    }
}
```

### Integration Test Pattern

```powershell
BeforeAll {
    $script:moduleName = 'MyModule'

    if (-not (Get-Module -Name $script:moduleName -ListAvailable)) {
        throw "Module '$script:moduleName' is unavailable. Run the detached build workflow first."
    }

    Import-Module -Name $script:moduleName -Force -ErrorAction 'Stop'
}

AfterAll {
    Remove-Module -Name $script:moduleName -Force
}

Describe 'End-to-end round-trip' -Tag 'Integration' {
    Context 'When performing a full operation cycle' {
        It 'Should create, retrieve, and delete successfully' {
            $widget = New-Widget -Name 'IntegrationTest'
            $widget | Should -Not -BeNullOrEmpty

            $retrieved = Get-Widget -Name 'IntegrationTest'
            $retrieved.Name | Should -Be 'IntegrationTest'

            { Remove-Widget -Name 'IntegrationTest' } | Should -Not -Throw
        }
    }
}
```

### Pester Configuration in build.yaml

```yaml
Pester:
  OutputFormat: NUnitXML
  ExcludeFromCodeCoverage:
    - Prefix.ps1                    # Exclude bootstrap code from coverage
  Script:                           # MUST use 'Script' key, not 'Path'
    - tests/Unit
    - tests/QA
  ExcludeTag:
    - helpQuality                   # Exclude tags during normal runs
    - Integration                   # Integration tests run separately
  Tag: []
  CodeCoverageOutputFile: JaCoCo_coverage.xml
  CodeCoverageOutputFileEncoding: ascii
  CodeCoverageThreshold: 85
```

### Running Tests

Use one line as the inner command of the detached build wrapper:

```text
# Run all tests (unit + QA)
./build.ps1 -Tasks test

# Run specific test file
./build.ps1 -Tasks test -PesterPath 'tests/Unit/Public/Get-Widget.tests.ps1' -CodeCoverageThreshold 0

# Run only QA tests
./build.ps1 -Tasks test -PesterPath 'tests/QA' -CodeCoverageThreshold 0

# Run integration tests
./build.ps1 -Tasks test -PesterPath 'tests/Integration' -CodeCoverageThreshold 0
```

---

