BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')
    $script:moduleName = 'CopilotAtelier'
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')

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
        $script:selectionProfile = New-CopilotAtelierTestProfile -Root (Join-Path $TestDrive 'update-profile') -ProjectPath $script:projectPath

        # A successful update installs exactly the requested version.
        Mock -CommandName Update-Module -ModuleName $script:moduleName -MockWith {
            $script:installedByUpdate = $RequiredVersion
        }

        # A build can label the module as a preview; unless a case says otherwise, the installation is stable.
        Mock -CommandName Get-CopilotAtelierModuleVersion -ModuleName $script:moduleName -MockWith {
            (Get-Module -Name 'CopilotAtelier').Version.ToString()
        }

        # The module imported after an update reports what the update installed.
        Mock -CommandName Get-CopilotAtelierModuleVersion -ModuleName $script:moduleName -ParameterFilter {
            $PesterBoundParameters.ContainsKey('Module')
        } -MockWith {
            $script:installedByUpdate
        }

        Mock -CommandName Import-Module -ModuleName $script:moduleName -MockWith {
            Get-Module -Name 'CopilotAtelier'
        }

        Mock -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -MockWith {
            [PSCustomObject] @{
                TargetPath = 'TestDrive:/CopilotAtelier'
            }
        }
    }

    AfterAll {
        Restore-CopilotAtelierTestProfile -Original $script:selectionProfile.Original
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

    Context 'When choosing a deployment destination' {
        BeforeAll {
            Mock Find-Module -ModuleName CopilotAtelier {
                [pscustomobject]@{ Name = 'CopilotAtelier'; Version = (Get-Module CopilotAtelier).Version.ToString() }
            }
            Mock Read-Host -ModuleName CopilotAtelier { throw 'Unexpected account prompt.' }
        }

        BeforeEach {
            $env:OneDriveConsumer = Join-Path $script:selectionProfile.HomePath 'consumer'
            $env:OneDriveCommercial = Join-Path $script:selectionProfile.HomePath 'commercial'
            New-Item -ItemType Directory -Path $env:OneDriveConsumer, $env:OneDriveCommercial -Force | Out-Null
        }

        AfterEach {
            $env:OneDriveConsumer = $null
            $env:OneDriveCommercial = $null
        }

        It 'Should forward the normalized explicit destination to installation' {
            $selected = Join-Path $script:selectionProfile.HomePath 'selected'
            Update-CopilotAtelier -TargetPath ($selected + [IO.Path]::DirectorySeparatorChar) -Force | Out-Null
            Should -Invoke Install-CopilotAtelier -ModuleName CopilotAtelier -Times 1 -Exactly -ParameterFilter { $TargetPath -eq $selected }
            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should reject ambiguous deployment selection before querying the repository' {
            { Update-CopilotAtelier -Force } | Should -Throw -ExpectedMessage '*Specify -TargetPath*'
            Should -Invoke Find-Module -ModuleName CopilotAtelier -Times 0 -Exactly
            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should not require an account when deployment is skipped' {
            { Update-CopilotAtelier -SkipDeployment } | Should -Not -Throw
            Should -Invoke Install-CopilotAtelier -ModuleName CopilotAtelier -Times 0 -Exactly
            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should forward explicit repair and redeploy the current version' {
            $selected = Join-Path $script:selectionProfile.HomePath 'selected'
            Update-CopilotAtelier -TargetPath $selected -Repair | Out-Null
            Should -Invoke Install-CopilotAtelier -ModuleName CopilotAtelier -Times 1 -Exactly -ParameterFilter { $TargetPath -eq $selected -and $Repair }
            Should -Invoke Update-Module -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should reject repair combined with skipped deployment' {
            { Update-CopilotAtelier -Repair -SkipDeployment } | Should -Throw -ExpectedMessage '*Repair*SkipDeployment*'
            Should -Invoke Find-Module -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should expose destination, repair, and preview through the Setup script' {
            $parameters = (Get-Command (Join-Path $script:projectPath 'Setup-CopilotSettings.ps1')).Parameters.Keys
            $parameters | Should -Contain 'TargetPath'
            $parameters | Should -Contain 'Repair'
            $parameters | Should -Contain 'WhatIf'
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

        It 'Should throw a directed error when the repository reports a non-terminating error' {
            # PowerShellGet writes most query errors as non-terminating errors and honours -ErrorAction.
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                $errorAction = 'Continue'
                if ($PesterBoundParameters.ContainsKey('ErrorAction'))
                {
                    $errorAction = $PesterBoundParameters['ErrorAction']
                }

                Write-Error -Message "Unable to find repository 'NoSuchRepo'." -ErrorAction $errorAction
            }

            { Update-CopilotAtelier -Repository 'NoSuchRepo' } |
                Should -Throw -ExpectedMessage "*Unable to query repository 'NoSuchRepo'*"
        }

        It 'Should throw a directed error when the repository returns no version' {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith { }

            { Update-CopilotAtelier } |
                Should -Throw -ExpectedMessage "*Unable to query repository 'PSGallery'*"
        }
    }

    Context 'When previews are published' {
        BeforeEach {
            # A stable query sees the release; a query that allows previews sees a preview of the next minor version.
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }

            Mock -CommandName Find-Module -ModuleName $script:moduleName -ParameterFilter { $AllowPrerelease } -MockWith {
                $current = (Get-Module -Name 'CopilotAtelier').Version

                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = '{0}.{1}.0-preview0004' -f $current.Major, ($current.Minor + 1)
                }
            }

            $current = (Get-Module -Name 'CopilotAtelier').Version
            $script:nextPreview = '{0}.{1}.0-preview0004' -f $current.Major, ($current.Minor + 1)
        }

        It 'Should consider stable versions only without -AllowPrerelease and name the newer preview' {
            $result = Update-CopilotAtelier -InformationVariable information

            $result.NewerPrerelease | Should -BeExactly $script:nextPreview
            ($information.MessageData -join "`n") | Should -BeLike "*No newer stable version is published.*$script:nextPreview*-AllowPrerelease*"
            $result.Updated | Should -BeFalse

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 0 -Exactly -Scope It
        }

        It 'Should find and install the newer preview with -AllowPrerelease' {
            $result = Update-CopilotAtelier -AllowPrerelease

            $result.Updated | Should -BeTrue
            $result.Version | Should -Be ([System.Version] ($script:nextPreview -split '-')[0])
            $result.Prerelease | Should -BeExactly 'preview0004'
            $result.NewerPrerelease | Should -BeNullOrEmpty

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 1 -Exactly -Scope It -ParameterFilter {
                $RequiredVersion -eq $script:nextPreview -and $AllowPrerelease
            }
            # Import-Module takes the numeric version; the label would not convert.
            Should -Invoke -CommandName Import-Module -ModuleName $script:moduleName -Times 1 -Exactly -Scope It -ParameterFilter {
                $RequiredVersion -eq [System.Version] ($script:nextPreview -split '-')[0]
            }
            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 1 -Exactly -Scope It
        }

        It 'Should read a preview label that PowerShellGet 3 returns in a separate Prerelease property, without -AllowPrerelease' {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -ParameterFilter { $AllowPrerelease } -MockWith {
                [PSCustomObject] @{
                    Name       = 'CopilotAtelier'
                    Version    = [System.Version] ($script:nextPreview -split '-')[0]
                    Prerelease = 'preview0004'
                }
            }

            $result = Update-CopilotAtelier

            $result.NewerPrerelease | Should -BeExactly $script:nextPreview
        }

        It 'Should read a preview label that PowerShellGet 3 returns in a separate Prerelease property, with -AllowPrerelease' {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -ParameterFilter { $AllowPrerelease } -MockWith {
                [PSCustomObject] @{
                    Name       = 'CopilotAtelier'
                    Version    = [System.Version] ($script:nextPreview -split '-')[0]
                    Prerelease = 'preview0004'
                }
            }

            $result = Update-CopilotAtelier -AllowPrerelease

            $result.Prerelease | Should -BeExactly 'preview0004'
            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 1 -Exactly -Scope It -ParameterFilter {
                $RequiredVersion -eq $script:nextPreview -and $AllowPrerelease
            }
        }

        It 'Should update to a newer release and still name a newer preview' {
            $current = (Get-Module -Name 'CopilotAtelier').Version
            $script:newerRelease = '{0}.{1}.0' -f $current.Major, ($current.Minor + 1)
            $script:newestPreview = '{0}.{1}.0-preview0001' -f $current.Major, ($current.Minor + 2)
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{ Name = 'CopilotAtelier'; Version = $script:newerRelease }
            }
            Mock -CommandName Find-Module -ModuleName $script:moduleName -ParameterFilter { $AllowPrerelease } -MockWith {
                [PSCustomObject] @{ Name = 'CopilotAtelier'; Version = $script:newestPreview }
            }

            $result = Update-CopilotAtelier

            $result.Updated | Should -BeTrue
            $result.Version | Should -Be ([System.Version] $script:newerRelease)
            $result.NewerPrerelease | Should -BeExactly $script:newestPreview
        }

        It 'Should order the installed <Installed> against the published <Published> of one version by label and update: <Expected>' -ForEach @(
            @{ Installed = 'preview0018'; Published = 'preview0022'; Expected = $true }
            @{ Installed = 'preview0024'; Published = 'preview0022'; Expected = $false }
            @{ Installed = 'preview0022'; Published = 'preview0022'; Expected = $false }
        ) {
            $version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
            $script:installedPreview = '{0}-{1}' -f $version, $Installed
            $script:publishedPreview = '{0}-{1}' -f $version, $Published

            Mock -CommandName Get-CopilotAtelierModuleVersion -ModuleName $script:moduleName -MockWith { $script:installedPreview }
            Mock -CommandName Find-Module -ModuleName $script:moduleName -ParameterFilter { $AllowPrerelease } -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = $script:publishedPreview
                }
            }

            $result = Update-CopilotAtelier -AllowPrerelease -InformationVariable information

            $result.PreviousPrerelease | Should -BeExactly $Installed
            $result.Updated | Should -Be $Expected
            if (-not $Expected)
            {
                ($information.MessageData -join "`n") | Should -BeLike '*previews included*'
            }
        }

        It 'Should update an installed preview to the release of the same version' {
            $script:installedPreview = '{0}-preview0025' -f (Get-Module -Name 'CopilotAtelier').Version
            Mock -CommandName Get-CopilotAtelierModuleVersion -ModuleName $script:moduleName -MockWith { $script:installedPreview }
            Mock -CommandName Find-Module -ModuleName $script:moduleName -ParameterFilter { $AllowPrerelease } -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }

            $result = Update-CopilotAtelier

            $result.Updated | Should -BeTrue
            $result.Prerelease | Should -BeNullOrEmpty
            $result.NewerPrerelease | Should -BeNullOrEmpty

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 1 -Exactly -Scope It -ParameterFilter {
                $RequiredVersion -eq (Get-Module -Name 'CopilotAtelier').Version.ToString() -and -not $AllowPrerelease
            }
        }
    }

    Context 'When an update does not land' {
        BeforeAll {
            # The release of the installed version is published, so the update stays in one module folder.
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }
        }

        BeforeEach {
            $script:installedPreview = '{0}-preview0025' -f (Get-Module -Name 'CopilotAtelier').Version
            Mock -CommandName Get-CopilotAtelierModuleVersion -ModuleName $script:moduleName -MockWith { $script:installedPreview }
        }

        It 'Should stop with a directed error when Update-Module writes a non-terminating error' {
            # PowerShellGet 2.2.5 skips a module in use with a non-terminating error that honours -ErrorAction.
            Mock -CommandName Update-Module -ModuleName $script:moduleName -MockWith {
                $errorAction = 'Continue'
                if ($PesterBoundParameters.ContainsKey('ErrorAction'))
                {
                    $errorAction = $PesterBoundParameters['ErrorAction']
                }

                Write-Error -Message "Module 'CopilotAtelier' is in use." -ErrorId 'ModuleIsInUse' -ErrorAction $errorAction
            }

            { Update-CopilotAtelier } | Should -Throw -ExpectedMessage '*Unable to update*'

            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 0 -Exactly -Scope It
        }

        It 'Should stop before deploying when the imported module still reports the previous version' {
            Mock -CommandName Update-Module -ModuleName $script:moduleName -MockWith { }
            $script:installedByUpdate = $script:installedPreview

            { Update-CopilotAtelier } | Should -Throw -ExpectedMessage "*did not install*$script:installedPreview*"

            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 0 -Exactly -Scope It
        }
    }

    Context 'When PowerShellGet cannot list previews' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }

            # PowerShellGet 1.0.0.1, which Windows PowerShell 5.1 ships with, has no AllowPrerelease parameter.
            Mock -CommandName Find-Module -ModuleName $script:moduleName -ParameterFilter { $AllowPrerelease } -MockWith {
                throw [System.Management.Automation.ParameterBindingException]::new("A parameter cannot be found that matches parameter name 'AllowPrerelease'.")
            }
        }

        It 'Should name PowerShellGet 2 when -AllowPrerelease is requested' {
            { Update-CopilotAtelier -AllowPrerelease } | Should -Throw -ExpectedMessage '*PowerShellGet 2*'

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 0 -Exactly -Scope It
        }

        It 'Should still compare stable versions without -AllowPrerelease and say that previews were not checked' {
            $result = Update-CopilotAtelier -InformationVariable information

            $result.Updated | Should -BeFalse
            $result.NewerPrerelease | Should -BeNullOrEmpty
            ($information.MessageData -join "`n") | Should -BeLike '*Previews were not checked*PowerShellGet 2*'
        }
    }
}
