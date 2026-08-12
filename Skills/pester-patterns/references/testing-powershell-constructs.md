# Testing PowerShell constructs

Recipes for the language and cmdlet features that need a particular test
shape: DSC resources, classes, pipelines, error and warning streams, dates,
`ShouldProcess`, environment variables, module exports, private functions, and
external fixtures. The rules that apply to every Pester run stay in
[`SKILL.md`](../SKILL.md).

## Pattern 4: Testing DSC Resources

### Class-Based DSC Resource

```powershell
Describe 'MyDscResource' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..' '..' 'output' 'builtModule' 'MyModule'
        Import-Module $modulePath -Force

        # Instantiate the DSC resource class
        $script:resource = [MyDscResource]::new()
        $script:resource.Name = 'TestItem'
        $script:resource.Ensure = 'Present'
    }

    Context 'Get()' {
        BeforeAll {
            Mock -ModuleName MyModule -CommandName Get-Item -MockWith {
                [PSCustomObject]@{ Name = 'TestItem'; Exists = $true }
            }
        }

        It 'Should return the current state' {
            $result = $script:resource.Get()
            $result.Name | Should -Be 'TestItem'
            $result.Ensure | Should -Be 'Present'
        }
    }

    Context 'Test()' {
        Context 'When the resource is in desired state' {
            BeforeAll {
                Mock -ModuleName MyModule -CommandName Get-Item -MockWith {
                    [PSCustomObject]@{ Name = 'TestItem' }
                }
            }

            It 'Should return $true' {
                $script:resource.Test() | Should -BeTrue
            }
        }

        Context 'When the resource is not in desired state' {
            BeforeAll {
                Mock -ModuleName MyModule -CommandName Get-Item -MockWith { $null }
            }

            It 'Should return $false' {
                $script:resource.Test() | Should -BeFalse
            }
        }
    }

    Context 'Set()' {
        BeforeAll {
            Mock -ModuleName MyModule -CommandName New-Item
            Mock -ModuleName MyModule -CommandName Remove-Item
        }

        It 'Should create the item when Ensure is Present' {
            $script:resource.Ensure = 'Present'
            $script:resource.Set()
            Should -Invoke -ModuleName MyModule -CommandName New-Item -Times 1
        }

        It 'Should remove the item when Ensure is Absent' {
            $script:resource.Ensure = 'Absent'
            $script:resource.Set()
            Should -Invoke -ModuleName MyModule -CommandName Remove-Item -Times 1
        }
    }
}
```

### MOF-Based DSC Resource

```powershell
Describe 'DSC_MyResource' {
    BeforeAll {
        $moduleName = 'MyModule'
        $resourceName = 'DSC_MyResource'
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'output' 'builtModule' $moduleName) -Force
    }

    Context 'Get-TargetResource' {
        BeforeAll {
            Mock -ModuleName $resourceName -CommandName Get-Service -MockWith {
                [PSCustomObject]@{ Name = 'TestSvc'; Status = 'Running' }
            }
        }

        It 'Should return a hashtable' {
            $result = InModuleScope $resourceName {
                Get-TargetResource -Name 'TestSvc'
            }
            $result | Should -BeOfType [hashtable]
            $result.Name | Should -Be 'TestSvc'
            $result.Ensure | Should -Be 'Present'
        }
    }
}
```

## Pattern 5: Testing PowerShell Classes

```powershell
Describe 'Widget class' {
    BeforeAll {
        # Import the module to load the class
        $modulePath = Join-Path $PSScriptRoot '..' '..' 'output' 'builtModule' 'MyModule'
        Import-Module $modulePath -Force
    }

    Context 'Constructor' {
        It 'Should create a widget with the given name' {
            $widget = [Widget]::new('TestWidget')
            $widget.Name | Should -Be 'TestWidget'
        }

        It 'Should set default status to Inactive' {
            $widget = [Widget]::new('TestWidget')
            $widget.Status | Should -Be 'Inactive'
        }

        It 'Should throw if name is empty' {
            { [Widget]::new('') } | Should -Throw
        }
    }

    Context 'Activate method' {
        It 'Should change status to Active' {
            $widget = [Widget]::new('TestWidget')
            $widget.Activate()
            $widget.Status | Should -Be 'Active'
        }
    }

    Context 'ToString override' {
        It 'Should return formatted string' {
            $widget = [Widget]::new('TestWidget')
            $widget.ToString() | Should -Be 'Widget: TestWidget (Inactive)'
        }
    }
}
```

## Pattern 6: Testing Pipeline Functions

```powershell
Describe 'ConvertTo-Widget' {
    BeforeAll {
        # Function accepts pipeline input
        function ConvertTo-Widget {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline)]
                [string]$Name
            )
            process {
                [PSCustomObject]@{ Name = $Name; Type = 'Widget' }
            }
        }
    }

    It 'Should accept pipeline input' {
        $result = 'Test1', 'Test2' | ConvertTo-Widget
        $result | Should -HaveCount 2
    }

    It 'Should set the Type property' {
        $result = 'Test' | ConvertTo-Widget
        $result.Type | Should -Be 'Widget'
    }

    It 'Should process each input individually' {
        $result = @('A', 'B', 'C') | ConvertTo-Widget
        $result[0].Name | Should -Be 'A'
        $result[1].Name | Should -Be 'B'
        $result[2].Name | Should -Be 'C'
    }
}
```

## Pattern 7: Testing Error Handling and Warning Output

### ErrorVariable

```powershell
Describe 'Get-SafeItem' {
    BeforeAll {
        Mock -ModuleName MyModule -CommandName Get-Item -MockWith {
            throw [System.IO.FileNotFoundException]::new('Not found')
        }
    }

    It 'Should write a non-terminating error for missing files' {
        $result = Get-SafeItem -Path 'C:\nonexistent' -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -HaveCount 1
        $err[0].Exception | Should -BeOfType [System.IO.FileNotFoundException]
    }
}
```

### Warning Output

```powershell
Describe 'Update-Config' {
    BeforeAll {
        Mock -ModuleName MyModule -CommandName Set-Content
    }

    It 'Should write a warning for deprecated settings' {
        $result = Update-Config -Setting 'OldSetting' -Value 'test' 3>&1
        $warnings = $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        $warnings | Should -Not -BeNullOrEmpty
        $warnings.Message | Should -Match 'deprecated'
    }
}
```

### Verbose Output

```powershell
Describe 'Invoke-LongOperation' {
    It 'Should write verbose output' {
        $verboseOutput = Invoke-LongOperation -Verbose 4>&1
        $verboseOutput | Should -Not -BeNullOrEmpty
    }
}
```

## Pattern 8: Testing with Dates and Times

```powershell
Describe 'Get-ExpiringCertificates' {
    BeforeAll {
        # Mock Get-Date to return a fixed point in time
        Mock -ModuleName MyModule -CommandName Get-Date -MockWith {
            [datetime]'2026-03-01T00:00:00'
        }

        Mock -ModuleName MyModule -CommandName Get-ChildItem -MockWith {
            @(
                [PSCustomObject]@{
                    Subject    = 'CN=expiring.example.com'
                    NotAfter   = [datetime]'2026-03-15T00:00:00'  # 14 days away
                }
                [PSCustomObject]@{
                    Subject    = 'CN=valid.example.com'
                    NotAfter   = [datetime]'2027-01-01T00:00:00'  # Far future
                }
            )
        }
    }

    It 'Should return certificates expiring within 30 days' {
        $result = Get-ExpiringCertificates -DaysUntilExpiry 30
        $result | Should -HaveCount 1
        $result[0].Subject | Should -Be 'CN=expiring.example.com'
    }
}
```

## Pattern 9: Testing ShouldProcess (WhatIf/Confirm)

```powershell
Describe 'Remove-Widget' {
    BeforeAll {
        Mock -ModuleName MyModule -CommandName Remove-Item
    }

    It 'Should call Remove-Item when confirmed' {
        Remove-Widget -Name 'TestWidget' -Confirm:$false
        Should -Invoke -ModuleName MyModule -CommandName Remove-Item -Times 1
    }

    It 'Should not call Remove-Item with WhatIf' {
        Remove-Widget -Name 'TestWidget' -WhatIf
        Should -Invoke -ModuleName MyModule -CommandName Remove-Item -Times 0
    }
}
```

## Pattern 10: Testing with Environment Variables

```powershell
Describe 'Get-DeploymentTarget' {
    Context 'When DEPLOY_ENV is set' {
        BeforeAll {
            $script:originalValue = $env:DEPLOY_ENV
            $env:DEPLOY_ENV = 'staging'
        }

        AfterAll {
            $env:DEPLOY_ENV = $script:originalValue
        }

        It 'Should return the environment from the variable' {
            Get-DeploymentTarget | Should -Be 'staging'
        }
    }

    Context 'When DEPLOY_ENV is not set' {
        BeforeAll {
            $script:originalValue = $env:DEPLOY_ENV
            $env:DEPLOY_ENV = $null
        }

        AfterAll {
            $env:DEPLOY_ENV = $script:originalValue
        }

        It 'Should return the default environment' {
            Get-DeploymentTarget | Should -Be 'production'
        }
    }
}
```

## Pattern 11: Testing Module Exports

```powershell
Describe 'Module exports' -Tag 'QA' {
    BeforeAll {
        $moduleName = 'MyModule'
        $module = Get-Module $moduleName

        $publicFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' '..' 'source' 'Public') `
            -Filter '*.ps1' -Recurse |
            Select-Object -ExpandProperty BaseName
    }

    It 'Should export all public functions' {
        foreach ($function in $publicFunctions) {
            $module.ExportedFunctions.Keys | Should -Contain $function `
                -Because "$function is in source/Public/ and should be exported"
        }
    }

    It 'Should not export private functions' {
        $privateFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' '..' 'source' 'Private') `
            -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty BaseName

        foreach ($function in $privateFunctions) {
            $module.ExportedFunctions.Keys | Should -Not -Contain $function `
                -Because "$function is in source/Private/ and should not be exported"
        }
    }

    It 'Should not export any variables' {
        $module.ExportedVariables.Keys | Should -HaveCount 0
    }
}
```

## Pattern 12: Testing Non-Exported (Private) Functions

Private helpers in `source/Private/` are merged into the built `.psm1` but are
not exported, so they cannot be called directly from a test file. Use Pester's
**module-internal scope invocation** to reach them:

```powershell
# Inside a Describe block, after the module has been imported:
It 'ConvertFrom-MyXml aggregates values' {
    $result = & (Get-Module MyModule) {
        param($xml)
        ConvertFrom-MyXml -Xml $xml    # Private function — resolves in module scope
    } $someXmlString

    $result.Total | Should -Be 42
}
```

The `& (Get-Module Name) { ... }` form runs the scriptblock inside the module's
private session state, where non-exported functions are visible. Pass inputs
via `param()` + positional args rather than closing over `$using:` — the module
scope is a separate session state and does not inherit your `$script:` vars.

This removes the need to either export private functions for testing or rely
on `InModuleScope` (which still works but is slower and pulls in the whole
module state per call).

## Pattern 13: External Test Fixtures (Avoid Nested Here-Strings)

For tests that exercise parsers, serialisers, or format converters, **do not**
embed multi-line sample input as a here-string inside the test file. Nested
here-strings are fragile, confuse editors, and (critically) break tooling that
writes test files via terminal heredocs (`@'...'@` inside another `@'...'@`
hangs pwsh waiting for input).

**Pattern**: store fixtures as their own files under
`tests/Unit/<area>/Fixtures/<name>.<ext>` and load them in `BeforeAll`:

```
tests/
  Unit/
    Private/
      ConvertFrom-MyXml.Tests.ps1
      Fixtures/
        valid-response.xml
        error-response.xml
```

```powershell
BeforeAll {
    Import-Module -Name MyModule -Force -ErrorAction Stop
    $script:validXml = Get-Content -LiteralPath "$PSScriptRoot/Fixtures/valid-response.xml" -Raw
    $script:errorXml = Get-Content -LiteralPath "$PSScriptRoot/Fixtures/error-response.xml" -Raw
}

Describe 'ConvertFrom-MyXml' -Tag 'Unit' {
    It 'Parses a valid response' {
        & (Get-Module MyModule) { param($x) ConvertFrom-MyXml -Xml $x } $script:validXml |
            Should -Not -BeNullOrEmpty
    }

    It 'Throws on an error response' {
        { & (Get-Module MyModule) { param($x) ConvertFrom-MyXml -Xml $x } $script:errorXml } |
            Should -Throw
    }
}
```

Benefits:

- Fixtures are syntax-highlighted by the editor as the correct file type.
- Fixtures are diff-friendly and can be replaced by captured real-world output.
- Test file stays short and focused on assertions.
- Agents/tools can write the fixture and the test in two small, non-nested operations.

