# Mocking external dependencies

Recipes for isolating a test from the file system, an HTTP API, or a
credential store. The rules that apply to every Pester run — how to launch it
and where helpers must live — stay in [`SKILL.md`](../SKILL.md).

## Pattern 1: Mocking the File System

### Read Operations

```powershell
Describe 'Get-ConfigValue' {
    BeforeAll {
        Mock -ModuleName MyModule -CommandName Get-Content -MockWith {
            @'
            {
                "setting1": "value1",
                "setting2": "value2"
            }
'@
        }

        Mock -ModuleName MyModule -CommandName Test-Path -MockWith { $true }
    }

    It 'Should return the config value' {
        $result = Get-ConfigValue -Key 'setting1'
        $result | Should -Be 'value1'
    }

    It 'Should call Get-Content with the config path' {
        Get-ConfigValue -Key 'setting1'
        Should -Invoke -ModuleName MyModule -CommandName Get-Content -Times 1
    }
}
```

### Write Operations

```powershell
Describe 'Export-Report' {
    BeforeAll {
        Mock -ModuleName MyModule -CommandName Set-Content
        Mock -ModuleName MyModule -CommandName New-Item
        Mock -ModuleName MyModule -CommandName Test-Path -MockWith { $false }
    }

    It 'Should create the output directory if it does not exist' {
        Export-Report -Path 'C:\Reports\report.txt' -Content 'Test'
        Should -Invoke -ModuleName MyModule -CommandName New-Item -Times 1 `
            -ParameterFilter { $ItemType -eq 'Directory' }
    }

    It 'Should write the content to the file' {
        Export-Report -Path 'C:\Reports\report.txt' -Content 'Test'
        Should -Invoke -ModuleName MyModule -CommandName Set-Content -Times 1 `
            -ParameterFilter { $Value -eq 'Test' }
    }
}
```

### Using TestDrive for Real File Operations

```powershell
Describe 'Import-CsvData' {
    BeforeAll {
        # Create test CSV in TestDrive
        $csvPath = Join-Path TestDrive: 'data.csv'
        @(
            [PSCustomObject]@{ Name = 'Alice'; Age = 30 }
            [PSCustomObject]@{ Name = 'Bob'; Age = 25 }
        ) | Export-Csv -Path $csvPath -NoTypeInformation
    }

    It 'Should import all rows' {
        $result = Import-CsvData -Path $csvPath
        $result | Should -HaveCount 2
    }

    It 'Should parse names correctly' {
        $result = Import-CsvData -Path $csvPath
        $result[0].Name | Should -Be 'Alice'
    }
}
```

## Pattern 2: Mocking REST APIs

### Invoke-RestMethod

```powershell
Describe 'Get-GitHubUser' {
    BeforeAll {
        Mock -ModuleName MyModule -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{
                login      = 'octocat'
                name       = 'The Octocat'
                public_repos = 8
            }
        }
    }

    It 'Should return the user object' {
        $result = Get-GitHubUser -Username 'octocat'
        $result.login | Should -Be 'octocat'
        $result.name | Should -Be 'The Octocat'
    }

    It 'Should call the correct API endpoint' {
        Get-GitHubUser -Username 'octocat'
        Should -Invoke -ModuleName MyModule -CommandName Invoke-RestMethod -Times 1 `
            -ParameterFilter { $Uri -eq 'https://api.github.com/users/octocat' }
    }
}
```

### Invoke-WebRequest

```powershell
Describe 'Test-WebEndpoint' {
    Context 'When the endpoint is healthy' {
        BeforeAll {
            Mock -ModuleName MyModule -CommandName Invoke-WebRequest -MockWith {
                [PSCustomObject]@{
                    StatusCode = 200
                    Content    = '{"status": "healthy"}'
                    Headers    = @{ 'Content-Type' = 'application/json' }
                }
            }
        }

        It 'Should return $true' {
            Test-WebEndpoint -Url 'https://api.example.com/health' | Should -BeTrue
        }
    }

    Context 'When the endpoint returns an error' {
        BeforeAll {
            Mock -ModuleName MyModule -CommandName Invoke-WebRequest -MockWith {
                throw [System.Net.WebException]::new('404 Not Found')
            }
        }

        It 'Should return $false' {
            Test-WebEndpoint -Url 'https://api.example.com/health' | Should -BeFalse
        }
    }
}
```

### Paginated API Responses

```powershell
Describe 'Get-AllItems' {
    BeforeAll {
        $script:callCount = 0
        Mock -ModuleName MyModule -CommandName Invoke-RestMethod -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) {
                [PSCustomObject]@{
                    items     = @('item1', 'item2')
                    nextToken = 'page2'
                }
            }
            else {
                [PSCustomObject]@{
                    items     = @('item3')
                    nextToken = $null
                }
            }
        }
    }

    BeforeEach {
        $script:callCount = 0
    }

    It 'Should return all items across pages' {
        $result = Get-AllItems
        $result | Should -HaveCount 3
    }

    It 'Should make two API calls' {
        Get-AllItems
        Should -Invoke -ModuleName MyModule -CommandName Invoke-RestMethod -Times 2
    }
}
```

## Pattern 3: Mocking Credentials and Secrets

### PSCredential

```powershell
Describe 'Connect-MyService' {
    BeforeAll {
        $securePassword = ConvertTo-SecureString 'FakePassword123!' -AsPlainText -Force
        $script:testCredential = [PSCredential]::new('TestUser', $securePassword)

        Mock -ModuleName MyModule -CommandName Invoke-RestMethod -MockWith {
            [PSCustomObject]@{ Token = 'fake-jwt-token' }
        }
    }

    It 'Should authenticate with the provided credential' {
        $result = Connect-MyService -Credential $script:testCredential
        $result.Token | Should -Not -BeNullOrEmpty
    }

    It 'Should pass the username in the request' {
        Connect-MyService -Credential $script:testCredential
        Should -Invoke -ModuleName MyModule -CommandName Invoke-RestMethod -Times 1 `
            -ParameterFilter { $Body.username -eq 'TestUser' }
    }
}
```

### SecureString Parameters

```powershell
Describe 'Set-ApiKey' {
    BeforeAll {
        $script:testKey = ConvertTo-SecureString 'sk-test-key-12345' -AsPlainText -Force
        Mock -ModuleName MyModule -CommandName Set-Content
    }

    It 'Should not throw with a valid SecureString' {
        { Set-ApiKey -ApiKey $script:testKey } | Should -Not -Throw
    }
}
```

