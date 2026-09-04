BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:migrationMapPath = Join-Path $script:repoRoot (
        'skills/memory-bank/assets/role-record-migration-map.json'
    )
    $script:planScriptPath = Join-Path $script:repoRoot (
        'skills/memory-bank/scripts/New-MemoryBankRoleMigrationPlan.ps1'
    )
    $script:applyScriptPath = Join-Path $script:repoRoot (
        'skills/memory-bank/scripts/Invoke-MemoryBankRoleMigration.ps1'
    )

    function New-LegacyMemoryBankFixture
    {
        [CmdletBinding()]
        [OutputType([string])]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper writes only isolated test data.'
        )]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [hashtable]$File
        )

        $memoryBankPath = Join-Path $Path '.memory-bank'
        New-Item -ItemType Directory -Path $memoryBankPath -Force | Out-Null

        foreach ($entry in $File.GetEnumerator())
        {
            $filePath = Join-Path $memoryBankPath $entry.Key
            [IO.File]::WriteAllBytes(
                $filePath,
                [Text.Encoding]::UTF8.GetBytes([string]$entry.Value)
            )
        }

        return $memoryBankPath
    }

    function Get-MigrationEntry
    {
        [CmdletBinding()]
        [OutputType([psobject])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [psobject]$Plan,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )

        return @($Plan.Entries | Where-Object Name -eq $Name)[0]
    }

    function New-TestDirectoryLink
    {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper creates only isolated test links.'
        )]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Target
        )

        $itemType = if ($env:OS -eq 'Windows_NT')
        {
            'Junction'
        }
        else
        {
            'SymbolicLink'
        }

        New-Item -ItemType $itemType -Path $Path -Target $Target |
            Out-Null
    }
}

Describe 'New-MemoryBankRoleMigrationPlan' -Tag 'Unit' {
    It 'ships the classification map and planner' {
        Test-Path -LiteralPath $script:migrationMapPath -PathType Leaf |
            Should -BeTrue
        Test-Path -LiteralPath $script:planScriptPath -PathType Leaf |
            Should -BeTrue
    }

    It 'publishes comment-based help for both migration phases' {
        foreach ($scriptPath in @(
            $script:planScriptPath
            $script:applyScriptPath
        ))
        {
            $help = Get-Help $scriptPath

            $help.Synopsis |
                Should -Not -BeLike "$(Split-Path $scriptPath -Leaf)*"
            $help.Parameters | Should -Not -BeNullOrEmpty
        }
    }

    It 'preserves an absolute filesystem root during path normalization' {
        $filesystemRoot = [IO.Path]::GetPathRoot($script:repoRoot)
        foreach ($scriptPath in @(
            $script:planScriptPath
            $script:applyScriptPath
        ))
        {
            $tokens = $null
            $parseErrors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile(
                $scriptPath,
                [ref]$tokens,
                [ref]$parseErrors
            )
            $functionAst = $ast.Find(
                {
                    param($node)

                    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                        $node.Name -eq 'Get-NormalizedFullPath'
                },
                $true
            )
            $source = @(
                'param([string]$Root)'
                $functionAst.Extent.Text
                'Get-NormalizedFullPath -LiteralPath $Root'
            ) -join "`n"

            $normalized = & ([scriptblock]::Create($source)) $filesystemRoot

            $parseErrors | Should -BeNullOrEmpty
            $normalized | Should -BeExactly $filesystemRoot
        }
    }

    It 'classifies automatic, ambiguous, excluded, and unknown legacy files' {
        $repositoryPath = Join-Path $TestDrive 'classification'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'profile.md'       = 'career'
            'case-est-2024.md' = 'tax'
            'case-lease.md'    = 'legal'
            'deadlines.md'     = 'mixed'
            'index.md'         = 'canonical'
            'custom.md'        = 'unknown'
        } | Out-Null

        $plan = & $script:planScriptPath -Path $repositoryPath

        (Get-MigrationEntry -Plan $plan -Name 'profile.md').Role |
            Should -Be 'career'
        (Get-MigrationEntry -Plan $plan -Name 'profile.md').Status |
            Should -Be 'Ready'
        (Get-MigrationEntry -Plan $plan -Name 'case-est-2024.md').Role |
            Should -Be 'tax'
        (Get-MigrationEntry -Plan $plan -Name 'case-lease.md').Role |
            Should -Be 'legal'
        (Get-MigrationEntry -Plan $plan -Name 'deadlines.md').Status |
            Should -Be 'NeedsAssignment'
        (Get-MigrationEntry -Plan $plan -Name 'index.md').Status |
            Should -Be 'Excluded'
        (Get-MigrationEntry -Plan $plan -Name 'custom.md').Status |
            Should -Be 'Unknown'
    }

    It 'accepts explicit role, manual-split, and skip decisions' {
        $repositoryPath = Join-Path $TestDrive 'assignments'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'deadlines.md'          = 'tax deadline'
            'session-log.md'        = 'mixed sessions'
            'documents-produced.md' = 'legacy registry'
        } | Out-Null
        $assignment = @{
            'deadlines.md'          = 'tax'
            'session-log.md'        = 'ManualSplit'
            'documents-produced.md' = 'Skip'
        }

        $plan = & $script:planScriptPath `
            -Path $repositoryPath `
            -Assignment $assignment

        (Get-MigrationEntry -Plan $plan -Name 'deadlines.md').Status |
            Should -Be 'Ready'
        (Get-MigrationEntry -Plan $plan -Name 'deadlines.md').Destination |
            Should -Be '.memory-bank/tax/deadlines.md'
        (Get-MigrationEntry -Plan $plan -Name 'session-log.md').Status |
            Should -Be 'ManualSplit'
        (Get-MigrationEntry -Plan $plan -Name 'documents-produced.md').Status |
            Should -Be 'Skipped'
    }

    It 'accepts every supported explicit role assignment' {
        foreach ($role in @('career', 'legal', 'tax'))
        {
            $repositoryPath = Join-Path $TestDrive "assignment-$role"
            New-Item -ItemType Directory -Path $repositoryPath | Out-Null
            New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
                'deadlines.md' = 'role-specific deadline'
            } | Out-Null

            $plan = & $script:planScriptPath `
                -Path $repositoryPath `
                -Assignment @{ 'deadlines.md' = $role }
            $entry = Get-MigrationEntry -Plan $plan -Name 'deadlines.md'

            $entry.Status | Should -Be 'Ready' -Because $role
            $entry.Role | Should -Be $role
            $entry.Destination |
                Should -Be ".memory-bank/$role/deadlines.md"
        }
    }

    It 'rejects invalid assignments without writing a plan' {
        $repositoryPath = Join-Path $TestDrive 'invalid-assignment'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'deadlines.md' = 'deadline'
        } | Out-Null

        {
            & $script:planScriptPath `
                -Path $repositoryPath `
                -Assignment @{ 'deadlines.md' = 'finance' } `
                -SavePlan
        } | Should -Throw -ExpectedMessage '*career, legal, tax, ManualSplit, or Skip*'

        Test-Path -LiteralPath (
            Join-Path $repositoryPath '.memory-bank/session'
        ) | Should -BeFalse
    }

    It 'does not write or modify files unless SavePlan is requested' {
        $repositoryPath = Join-Path $TestDrive 'read-only'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $repositoryPath `
            -File @{ 'profile.md' = 'preserve me' }
        $sourcePath = Join-Path $memoryBankPath 'profile.md'
        $beforeHash = (Get-FileHash -LiteralPath $sourcePath).Hash

        $plan = & $script:planScriptPath -Path $repositoryPath

        $plan.PlanPath | Should -BeNullOrEmpty
        (Get-FileHash -LiteralPath $sourcePath).Hash | Should -Be $beforeHash
        Test-Path -LiteralPath (Join-Path $memoryBankPath 'session') |
            Should -BeFalse
    }

    It 'saves a metadata-only plan under the Memory Bank session directory' {
        $repositoryPath = Join-Path $TestDrive 'saved-plan'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'profile.md' = 'PRIVATE-CONTENT-MUST-NOT-ENTER-PLAN'
        } | Out-Null
        $referenceTime = [datetime]'2026-09-04T10:00:00Z'

        $plan = & $script:planScriptPath `
            -Path $repositoryPath `
            -SavePlan `
            -ReferenceTime $referenceTime

        $plan.PlanPath |
            Should -Be '.memory-bank/session/role-record-migration-2026-09-04T100000Z.json'
        $planPath = Join-Path $repositoryPath $plan.PlanPath
        Test-Path -LiteralPath $planPath -PathType Leaf | Should -BeTrue
        $planText = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8
        { $planText | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
        $planText | Should -Not -Match 'PRIVATE-CONTENT-MUST-NOT-ENTER-PLAN'
        $planText | Should -Match '"sourceSha256"'
        $bytes = [IO.File]::ReadAllBytes($planPath)
        $bytes[-1] | Should -Be 10
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
            Should -BeFalse
    }

    It 'never discovers legacy files outside the selected repository Memory Bank' {
        $repositoryPath = Join-Path $TestDrive 'selected-repository'
        $outsidePath = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-Item -ItemType Directory -Path $outsidePath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'profile.md' = 'inside'
        } | Out-Null
        New-LegacyMemoryBankFixture -Path $outsidePath -File @{
            'case-est-2023.md' = 'outside'
        } | Out-Null

        $plan = & $script:planScriptPath -Path $repositoryPath

        @($plan.Entries) | Should -HaveCount 1
        $plan.Entries[0].Name | Should -Be 'profile.md'
    }

    It 'rejects a selected repository root that is a reparse point' {
        $targetPath = Join-Path $TestDrive 'planner-root-target'
        $linkPath = Join-Path $TestDrive 'planner-root-link'
        New-Item -ItemType Directory -Path $targetPath | Out-Null
        New-LegacyMemoryBankFixture -Path $targetPath -File @{
            'profile.md' = 'career'
        } | Out-Null
        New-TestDirectoryLink -Path $linkPath -Target $targetPath

        {
            & $script:planScriptPath -Path $linkPath
        } | Should -Throw -ExpectedMessage '*repository root*reparse point*'
    }

    It 'keeps saved migration plans out of version control' {
        $ignorePath = Join-Path $script:repoRoot '.gitignore'
        $ignore = Get-Content -LiteralPath $ignorePath -Raw -Encoding UTF8

        $ignore |
            Should -Match '(?m)^\.memory-bank/session/role-record-migration-\*\.json\r?$'
    }

    It 'is wired into the portable Memory Bank Skill' {
        $skillPath = Join-Path $script:repoRoot 'skills/memory-bank/SKILL.md'
        $skill = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8

        $skill | Should -Match 'New-MemoryBankRoleMigrationPlan\.ps1'
        $skill | Should -Match 'Invoke-MemoryBankRoleMigration\.ps1'
        $skill | Should -Match '(?i)role-record migration'
        $skill | Should -Match '(?i)NeedsAssignment'
    }

    It 'documents the public workflow and saved-plan lifecycle' {
        $readmePath = Join-Path $script:repoRoot 'README.md'
        $sessionReadmePath = Join-Path $script:repoRoot (
            '.memory-bank/session/README.md'
        )
        $agentReadmePath = Join-Path $script:repoRoot (
            'com.github.copilot/agents/README.md'
        )
        $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
        $sessionReadme = Get-Content -LiteralPath $sessionReadmePath -Raw -Encoding UTF8
        $agentReadme = Get-Content -LiteralPath $agentReadmePath -Raw -Encoding UTF8

        $readme | Should -Match '## Migrating Legacy Memory Bank Records'
        $readme | Should -Match 'New-MemoryBankRoleMigrationPlan\.ps1'
        $readme | Should -Match 'Invoke-MemoryBankRoleMigration\.ps1'
        $readme | Should -Match '`-WhatIf`'
        $sessionReadme |
            Should -Match '`role-record-migration-<UTC>\.json`'
        $agentReadme | Should -Match '(?i)role-record migration'
        $agentReadme | Should -Match '\.memory-bank/legal/'
        $agentReadme | Should -Match '\.memory-bank/tax/'
    }
}

Describe 'Invoke-MemoryBankRoleMigration' -Tag 'Unit' {
    It 'ships the copy-only plan applicator' {
        Test-Path -LiteralPath $script:applyScriptPath -PathType Leaf |
            Should -BeTrue
    }

    It 'blocks the whole apply when an ambiguous file is unresolved' {
        $repositoryPath = Join-Path $TestDrive 'unresolved'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'profile.md'   = 'career'
            'deadlines.md' = 'ambiguous'
        } | Out-Null
        $plan = & $script:planScriptPath `
            -Path $repositoryPath `
            -SavePlan

        {
            & $script:applyScriptPath `
                -Path $repositoryPath `
                -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
                -Confirm:$false
        } | Should -Throw -ExpectedMessage '*NeedsAssignment*'

        Test-Path -LiteralPath (
            Join-Path $repositoryPath '.memory-bank/career/profile.md'
        ) | Should -BeFalse
    }

    It 'copies source bytes exactly and preserves the source' {
        $repositoryPath = Join-Path $TestDrive 'exact-copy'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $repositoryPath `
            -File @{ 'profile.md' = 'temporary' }
        $sourcePath = Join-Path $memoryBankPath 'profile.md'
        $payload = @(
            [byte]0xEF
            [byte]0xBB
            [byte]0xBF
        ) + [Text.Encoding]::UTF8.GetBytes(
            "Gr$([char]0x00FC)$([char]0x00DF)e`n"
        )
        [IO.File]::WriteAllBytes($sourcePath, $payload)
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath).Hash
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan

        $result = & $script:applyScriptPath `
            -Path $repositoryPath `
            -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
            -Confirm:$false

        $destinationPath = Join-Path $memoryBankPath 'career/profile.md'
        $result.Action | Should -Contain 'Copied'
        [IO.File]::ReadAllBytes($destinationPath) |
            Should -BeExactly $payload
        (Get-FileHash -LiteralPath $sourcePath).Hash |
            Should -Be $sourceHash
    }

    It 'supports WhatIf without creating a role directory or destination' {
        $repositoryPath = Join-Path $TestDrive 'whatif'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'case-est-2024.md' = 'tax'
        } | Out-Null
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan

        $result = & $script:applyScriptPath `
            -Path $repositoryPath `
            -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
            -WhatIf

        $result.Action | Should -Contain 'Planned'
        Test-Path -LiteralPath (
            Join-Path $repositoryPath '.memory-bank/tax'
        ) | Should -BeFalse
    }

    It 'blocks every write when a source changed after planning' {
        $repositoryPath = Join-Path $TestDrive 'changed-source'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $repositoryPath `
            -File @{ 'profile.md' = 'before' }
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan
        [IO.File]::WriteAllText(
            (Join-Path $memoryBankPath 'profile.md'),
            'after'
        )

        {
            & $script:applyScriptPath `
                -Path $repositoryPath `
                -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
                -Confirm:$false
        } | Should -Throw -ExpectedMessage '*source hash changed*'

        Test-Path -LiteralPath (
            Join-Path $memoryBankPath 'career/profile.md'
        ) | Should -BeFalse
    }

    It 'reports an identical destination as already migrated' {
        $repositoryPath = Join-Path $TestDrive 'identical'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $repositoryPath `
            -File @{ 'profile.md' = 'same' }
        $careerPath = Join-Path $memoryBankPath 'career'
        New-Item -ItemType Directory -Path $careerPath | Out-Null
        [IO.File]::Copy(
            (Join-Path $memoryBankPath 'profile.md'),
            (Join-Path $careerPath 'profile.md')
        )
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan

        $result = & $script:applyScriptPath `
            -Path $repositoryPath `
            -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
            -Confirm:$false

        $result.Action | Should -Contain 'AlreadyMigrated'
    }

    It 'blocks all writes when a destination has different content' {
        $repositoryPath = Join-Path $TestDrive 'conflict'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $repositoryPath `
            -File @{
                'profile.md'       = 'source'
                'case-est-2024.md' = 'tax source'
            }
        $careerPath = Join-Path $memoryBankPath 'career'
        New-Item -ItemType Directory -Path $careerPath | Out-Null
        [IO.File]::WriteAllText(
            (Join-Path $careerPath 'profile.md'),
            'different'
        )
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan

        {
            & $script:applyScriptPath `
                -Path $repositoryPath `
                -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
                -Confirm:$false
        } | Should -Throw -ExpectedMessage '*Conflict*'

        Test-Path -LiteralPath (
            Join-Path $memoryBankPath 'tax/case-est-2024.md'
        ) | Should -BeFalse
    }

    It 'is idempotent when the same plan is applied twice' {
        $repositoryPath = Join-Path $TestDrive 'idempotent'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'profile.md' = 'career'
        } | Out-Null
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan
        $planPath = Join-Path $repositoryPath $plan.PlanPath

        $first = & $script:applyScriptPath `
            -Path $repositoryPath `
            -PlanPath $planPath `
            -Confirm:$false
        $second = & $script:applyScriptPath `
            -Path $repositoryPath `
            -PlanPath $planPath `
            -Confirm:$false

        $first.Action | Should -Contain 'Copied'
        $second.Action | Should -Contain 'AlreadyMigrated'
    }

    It 'rejects a plan created for another repository' {
        $sourceRepository = Join-Path $TestDrive 'source-repository'
        $targetRepository = Join-Path $TestDrive 'target-repository'
        New-Item -ItemType Directory -Path $sourceRepository | Out-Null
        New-Item -ItemType Directory -Path $targetRepository | Out-Null
        New-LegacyMemoryBankFixture -Path $sourceRepository -File @{
            'profile.md' = 'source'
        } | Out-Null
        New-LegacyMemoryBankFixture -Path $targetRepository -File @{
            'profile.md' = 'target'
        } | Out-Null
        $plan = & $script:planScriptPath -Path $sourceRepository -SavePlan

        {
            & $script:applyScriptPath `
                -Path $targetRepository `
                -PlanPath (Join-Path $sourceRepository $plan.PlanPath) `
                -Confirm:$false
        } | Should -Throw -ExpectedMessage '*repository root*'
    }

    It 'rejects a reparse point selected as the apply repository root' {
        $targetPath = Join-Path $TestDrive 'apply-root-target'
        $linkPath = Join-Path $TestDrive 'apply-root-link'
        New-Item -ItemType Directory -Path $targetPath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $targetPath `
            -File @{ 'profile.md' = 'career' }
        $plan = & $script:planScriptPath -Path $targetPath -SavePlan
        $planPath = Join-Path $targetPath $plan.PlanPath
        New-TestDirectoryLink -Path $linkPath -Target $targetPath
        $savedPlan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $savedPlan.repositoryRoot = (Get-Item -LiteralPath $linkPath).FullName
        $savedPlan | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $planPath -Encoding UTF8

        {
            & $script:applyScriptPath `
                -Path $linkPath `
                -PlanPath (Join-Path $linkPath $plan.PlanPath) `
                -Confirm:$false
        } | Should -Throw -ExpectedMessage '*repository root*reparse point*'

        Test-Path -LiteralPath (Join-Path $memoryBankPath 'career/profile.md') |
            Should -BeFalse
    }

    It 'rejects a tampered source path that escapes the Memory Bank root' {
        $repositoryPath = Join-Path $TestDrive 'path-traversal'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-LegacyMemoryBankFixture -Path $repositoryPath -File @{
            'profile.md' = 'source'
        } | Out-Null
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan
        $planPath = Join-Path $repositoryPath $plan.PlanPath
        $tamperedPlan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $tamperedPlan.entries[0].source = '.memory-bank/../outside.md'
        $tamperedPlan | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $planPath -Encoding UTF8

        {
            & $script:applyScriptPath `
                -Path $repositoryPath `
                -PlanPath $planPath `
                -Confirm:$false
        } | Should -Throw -ExpectedMessage '*direct child*'
    }

    It 'rejects a role directory that becomes a reparse point after planning' {
        $repositoryPath = Join-Path $TestDrive 'reparse-point'
        $outsidePath = Join-Path $TestDrive 'outside-role'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        New-Item -ItemType Directory -Path $outsidePath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $repositoryPath `
            -File @{ 'profile.md' = 'source' }
        $plan = & $script:planScriptPath -Path $repositoryPath -SavePlan
        New-TestDirectoryLink `
            -Path (Join-Path $memoryBankPath 'career') `
            -Target $outsidePath

        {
            & $script:applyScriptPath `
                -Path $repositoryPath `
                -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
                -Confirm:$false
        } | Should -Throw -ExpectedMessage '*reparse point*'

        Test-Path -LiteralPath (Join-Path $outsidePath 'profile.md') |
            Should -BeFalse
    }

    It 'migrates automatic and assigned files while preserving every source' {
        $repositoryPath = Join-Path $TestDrive 'complete'
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
        $memoryBankPath = New-LegacyMemoryBankFixture `
            -Path $repositoryPath `
            -File @{
                'profile.md'          = 'career'
                'case-lease.md'       = 'legal'
                'case-est-2024.md'    = 'tax'
                'deadlines.md'        = 'tax deadline'
                'session-log.md'      = 'mixed'
                'custom.md'           = 'unknown'
                'index.md'            = 'excluded'
            }
        $plan = & $script:planScriptPath `
            -Path $repositoryPath `
            -Assignment @{
                'deadlines.md' = 'tax'
                'session-log.md' = 'ManualSplit'
            } `
            -SavePlan

        $result = & $script:applyScriptPath `
            -Path $repositoryPath `
            -PlanPath (Join-Path $repositoryPath $plan.PlanPath) `
            -Confirm:$false

        @($result | Where-Object Action -eq 'Copied') | Should -HaveCount 4
        foreach ($relativePath in @(
            'career/profile.md'
            'legal/case-lease.md'
            'tax/case-est-2024.md'
            'tax/deadlines.md'
        ))
        {
            Test-Path -LiteralPath (Join-Path $memoryBankPath $relativePath) |
                Should -BeTrue -Because $relativePath
        }
        foreach ($name in @(
            'profile.md'
            'case-lease.md'
            'case-est-2024.md'
            'deadlines.md'
            'session-log.md'
            'custom.md'
            'index.md'
        ))
        {
            Test-Path -LiteralPath (Join-Path $memoryBankPath $name) |
                Should -BeTrue -Because "source $name must be preserved"
        }
    }
}