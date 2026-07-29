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

    $script:moduleUnderTest = Import-Module -Name $builtManifest[0].FullName -Force -PassThru -ErrorAction Stop
    $script:installedVersion = $script:moduleUnderTest.Version
    $script:availableVersion = [System.Version]::new($script:installedVersion.Major + 1, 0, 0)
}

Describe 'Update-CopilotAtelier' -Tag 'Unit' {
    BeforeAll {
        Mock -CommandName Update-Module -ModuleName $script:moduleName

        Mock -CommandName Import-Module -ModuleName $script:moduleName -MockWith {
            Get-Module -Name 'CopilotAtelier'
        }

        Mock -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -MockWith {
            [PSCustomObject] @{
                TargetPath = 'TestDrive:/CopilotAtelier'
            }
        }
    }

    Context 'When the installed version is the newest one' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }

            $script:result = Update-CopilotAtelier
        }

        It 'Should not update the module' {
            $script:result.Updated | Should -BeFalse

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
        }

        It 'Should not redeploy' {
            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
        }
    }

    Context 'When a newer version is published' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                $current = (Get-Module -Name 'CopilotAtelier').Version

                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = '{0}.0.0' -f ($current.Major + 1)
                }
            }

            $script:result = Update-CopilotAtelier
        }

        It 'Should update the module' {
            $script:result.Updated | Should -BeTrue
            $script:result.PreviousVersion | Should -Be $script:installedVersion
            $script:result.Version | Should -Be $script:availableVersion

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 1 -Exactly -Scope Context
        }

        It 'Should redeploy the customizations' {
            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 1 -Exactly -Scope Context

            $script:result.Deployment | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When deployment is skipped' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                $current = (Get-Module -Name 'CopilotAtelier').Version

                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = '{0}.0.0' -f ($current.Major + 1)
                }
            }

            $script:result = Update-CopilotAtelier -SkipDeployment
        }

        It 'Should update but not deploy' {
            $script:result.Updated | Should -BeTrue

            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
        }
    }

    Context 'When redeployment is forced without a newer version' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }

            $script:result = Update-CopilotAtelier -Force
        }

        It 'Should redeploy the current version' {
            $script:result.Updated | Should -BeFalse

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 1 -Exactly -Scope Context
        }
    }

    Context 'When the repository cannot be queried' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                throw 'No match was found.'
            }
        }

        It 'Should throw a directed error' {
            { Update-CopilotAtelier } |
                Should -Throw -ExpectedMessage "*Unable to query repository 'PSGallery'*"
        }
    }
}
