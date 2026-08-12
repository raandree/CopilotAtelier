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

    # Junctions never need elevation on Windows and symbolic links never need it
    # on Linux or macOS, so the reparse-point cases run for real on every
    # platform rather than through a seam.
    $script:linkItemType = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }

    function New-LinkScenario
    {
        <#
            Builds a link path holding a real, non-empty directory plus a
            populated target, and returns both paths. That is the only shape in
            which Set-CustomizationLink merges anything.
        #>
        param
        (
            [Parameter(Mandatory = $true)]
            [System.String]
            $Root,

            [Parameter()]
            [System.Collections.Hashtable]
            $LinkContent = @{},

            [Parameter()]
            [System.Collections.Hashtable]
            $TargetContent = @{}
        )

        $linkPath = Join-Path -Path $Root -ChildPath 'link'
        $targetPath = Join-Path -Path $Root -ChildPath 'target'

        New-Item -ItemType Directory -Path $linkPath, $targetPath -Force | Out-Null

        foreach ($map in @(@{ Path = $linkPath; Content = $LinkContent }, @{ Path = $targetPath; Content = $TargetContent }))
        {
            foreach ($name in $map.Content.Keys)
            {
                Set-Content -LiteralPath (Join-Path -Path $map.Path -ChildPath $name) -Value $map.Content[$name] -NoNewline
            }
        }

        return @{
            LinkPath   = $linkPath
            TargetPath = $targetPath
        }
    }

    function Invoke-SetCustomizationLink
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.Collections.Hashtable]
            $Parameter
        )

        InModuleScope -ModuleName $script:moduleName -Parameters @{ Parameter = $Parameter } -ScriptBlock {
            param ($Parameter)

            Set-CustomizationLink @Parameter -InformationVariable information -InformationAction SilentlyContinue

            , @($information | ForEach-Object -Process { [System.String] $_.MessageData })
        }
    }
}

Describe 'Set-CustomizationLink' -Tag 'Unit' {
    Context 'When a non-empty directory occupies the link path' {
        BeforeEach {
            $script:root = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))

            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        }

        # An unattended caller reaches this function through the shipped
        # Update-CopilotAtelier -Force path, where there is no console to read
        # from. A prompt there does not fail, it hangs forever.
        It 'Never reads from the console' {
            $scenario = New-LinkScenario -Root $script:root -LinkContent @{ 'own.md' = 'mine' }

            Mock -CommandName Read-Host -ModuleName $script:moduleName -MockWith { throw 'Set-CustomizationLink must not prompt.' }

            $null = Invoke-SetCustomizationLink -Parameter @{
                LinkPath     = $scenario.LinkPath
                TargetPath   = $scenario.TargetPath
                LinkItemType = $script:linkItemType
            }

            Should -Invoke -CommandName Read-Host -ModuleName $script:moduleName -Times 0 -Exactly
        }

        It 'Leaves the directory alone and names -Force when it is not supplied' {
            $scenario = New-LinkScenario -Root $script:root -LinkContent @{ 'own.md' = 'mine' }

            $information = Invoke-SetCustomizationLink -Parameter @{
                LinkPath     = $scenario.LinkPath
                TargetPath   = $scenario.TargetPath
                LinkItemType = $script:linkItemType
            }

            (Get-Item -LiteralPath $scenario.LinkPath).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) |
                Should -BeFalse -Because 'nothing may be replaced without an explicit opt-in'

            Test-Path -LiteralPath (Join-Path -Path $scenario.LinkPath -ChildPath 'own.md') | Should -BeTrue
            $information -join "`n" | Should -Match '-Force'
        }

        It 'Merges and links when -Force is supplied' {
            $scenario = New-LinkScenario -Root $script:root -LinkContent @{ 'own.md' = 'mine' }

            $null = Invoke-SetCustomizationLink -Parameter @{
                LinkPath     = $scenario.LinkPath
                TargetPath   = $scenario.TargetPath
                LinkItemType = $script:linkItemType
                Force        = $true
            }

            (Get-Item -LiteralPath $scenario.LinkPath).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) |
                Should -BeTrue

            Get-Content -LiteralPath (Join-Path -Path $scenario.TargetPath -ChildPath 'own.md') -Raw |
                Should -Be 'mine'
        }
    }

    Context 'When a child exists in both the directory and the target' {
        BeforeEach {
            $script:root = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))

            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        }

        # The recorded drift this guards: a deployed prompt file was 126 lines
        # against the repository's 106. The old code skipped such a child and
        # then deleted the directory it lived in, so the newer copy was lost.
        It 'Refuses the merge and keeps both copies when the child differs' {
            $scenario = New-LinkScenario -Root $script:root `
                -LinkContent @{ 'shared.md' = 'deployed copy' } `
                -TargetContent @{ 'shared.md' = 'repository copy' }

            $information = Invoke-SetCustomizationLink -Parameter @{
                LinkPath     = $scenario.LinkPath
                TargetPath   = $scenario.TargetPath
                LinkItemType = $script:linkItemType
                Force        = $true
            }

            Get-Content -LiteralPath (Join-Path -Path $scenario.LinkPath -ChildPath 'shared.md') -Raw |
                Should -Be 'deployed copy' -Because 'the differing copy must survive'

            Get-Content -LiteralPath (Join-Path -Path $scenario.TargetPath -ChildPath 'shared.md') -Raw |
                Should -Be 'repository copy' -Because 'the target is never overwritten'

            (Get-Item -LiteralPath $scenario.LinkPath).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) |
                Should -BeFalse

            $information -join "`n" | Should -Match 'shared\.md'
        }

        It 'Completes when the child is byte-identical' {
            $scenario = New-LinkScenario -Root $script:root `
                -LinkContent @{ 'shared.md' = 'same'; 'extra.md' = 'new' } `
                -TargetContent @{ 'shared.md' = 'same' }

            $null = Invoke-SetCustomizationLink -Parameter @{
                LinkPath     = $scenario.LinkPath
                TargetPath   = $scenario.TargetPath
                LinkItemType = $script:linkItemType
                Force        = $true
            }

            (Get-Item -LiteralPath $scenario.LinkPath).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) |
                Should -BeTrue

            Get-Content -LiteralPath (Join-Path -Path $scenario.TargetPath -ChildPath 'extra.md') -Raw |
                Should -Be 'new'
        }
    }

    Context 'When a reparse point is inside the directory' {
        BeforeEach {
            $script:root = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))

            New-Item -ItemType Directory -Path $script:root -Force | Out-Null

            $script:outside = Join-Path -Path $script:root -ChildPath 'outside'

            New-Item -ItemType Directory -Path $script:outside -Force | Out-Null

            Set-Content -LiteralPath (Join-Path -Path $script:outside -ChildPath 'secret.md') -Value 'not ours' -NoNewline
        }

        It 'Refuses the merge when a child is itself a reparse point' {
            $scenario = New-LinkScenario -Root $script:root

            New-Item -ItemType $script:linkItemType `
                -Path (Join-Path -Path $scenario.LinkPath -ChildPath 'escape') `
                -Target $script:outside | Out-Null

            $information = Invoke-SetCustomizationLink -Parameter @{
                LinkPath     = $scenario.LinkPath
                TargetPath   = $scenario.TargetPath
                LinkItemType = $script:linkItemType
                Force        = $true
            }

            Test-Path -LiteralPath (Join-Path -Path $scenario.TargetPath -ChildPath 'escape') |
                Should -BeFalse -Because 'a reparse point takes the copy outside the intended tree'

            (Get-Item -LiteralPath $scenario.LinkPath).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) |
                Should -BeFalse

            $information -join "`n" | Should -Match 'escape'
        }

        It 'Refuses the merge when a reparse point is nested below a child' {
            $scenario = New-LinkScenario -Root $script:root

            $nested = Join-Path -Path $scenario.LinkPath -ChildPath 'tree'

            New-Item -ItemType Directory -Path $nested -Force | Out-Null

            New-Item -ItemType $script:linkItemType `
                -Path (Join-Path -Path $nested -ChildPath 'escape') `
                -Target $script:outside | Out-Null

            $information = Invoke-SetCustomizationLink -Parameter @{
                LinkPath     = $scenario.LinkPath
                TargetPath   = $scenario.TargetPath
                LinkItemType = $script:linkItemType
                Force        = $true
            }

            Test-Path -LiteralPath (Join-Path -Path $scenario.TargetPath -ChildPath 'tree') |
                Should -BeFalse

            $information -join "`n" | Should -Match 'tree'
        }
    }
}
