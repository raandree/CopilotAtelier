BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:initializerPath = Join-Path $script:repoRoot (
        'skills/memory-bank/scripts/Initialize-MemoryBank.ps1'
    )
    $script:healthCheckPath = Join-Path $script:repoRoot (
        'skills/memory-bank/scripts/Test-MemoryBankHealth.ps1'
    )
}

Describe 'Test-MemoryBankHealth' {
    It 'passes the repository canonical files and compactness budgets' {
        Test-Path -LiteralPath $script:healthCheckPath -PathType Leaf |
            Should -BeTrue

        $result = & $script:healthCheckPath `
            -Path $script:repoRoot `
            -ReferenceDate ([datetime]'2026-07-24')

        $result.Passed | Should -BeTrue
        $result.ErrorCount | Should -Be 0

        # Surface the pre-failure signal so a passing run still reports which
        # file is about to breach its budget.
        foreach ($nearLimit in @(
            $result.Issues | Where-Object Code -eq 'LineBudgetNearLimit'
        )) {
            Write-Warning -Message $nearLimit.Message
        }

        # promptHistory.md is gitignored local ephemera, so a clean checkout
        # carries only the seven required version-controlled files.
        $promptHistoryPath = Join-Path $script:repoRoot '.memory-bank/promptHistory.md'
        $promptHistoryPresent = Test-Path -LiteralPath $promptHistoryPath -PathType Leaf

        $result.LocalPromptHistoryPresent | Should -Be $promptHistoryPresent
        $result.CanonicalFileCount | Should -Be (7 + [int]$promptHistoryPresent)
        $result.MemoryBankTopicCount | Should -Be 0
        $result.IndexLineCount | Should -BeLessOrEqual 100
        $result.IndexCharacterCount | Should -BeLessOrEqual 7000
    }

    It 'passes a clean checkout without local prompt history' {
        $repositoryPath = Join-Path $TestDrive 'clean-checkout'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        & $script:initializerPath -Path $repositoryPath -Confirm:$false |
            Out-Null
        Remove-Item -LiteralPath (Join-Path $repositoryPath (
            '.memory-bank/promptHistory.md'
        ))

        $result = & $script:healthCheckPath `
            -Path $repositoryPath `
            -ReferenceDate ([datetime]'2026-07-24')

        $result.Passed | Should -BeTrue
        $result.ErrorCount | Should -Be 0
        $result.CanonicalFileCount | Should -Be 7
        $result.LocalPromptHistoryPresent | Should -BeFalse
    }

    It 'does not require optional Memory Bank topics' {
        $repositoryPath = Join-Path $TestDrive 'without-topics'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        & $script:initializerPath -Path $repositoryPath -Confirm:$false |
            Out-Null

        $result = & $script:healthCheckPath `
            -Path $repositoryPath `
            -ReferenceDate ([datetime]'2026-07-24')

        $result.Passed | Should -BeTrue
        $result.MemoryBankTopicCount | Should -Be 0
    }

    It 'fails when a routed core file exceeds its line budget' {
        $repositoryPath = Join-Path $TestDrive 'oversized-core'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        & $script:initializerPath -Path $repositoryPath -Confirm:$false |
            Out-Null
        $activeContextPath = Join-Path $repositoryPath (
            '.memory-bank/activeContext.md'
        )
        Add-Content -LiteralPath $activeContextPath -Value (
            1..210 | ForEach-Object { "Budget line $_" }
        )

        $result = & $script:healthCheckPath `
            -Path $repositoryPath `
            -ReferenceDate ([datetime]'2026-07-24')

        $result.Passed | Should -BeFalse
        @($result.Issues | Where-Object Code -eq 'LineBudgetExceeded') |
            Should -HaveCount 1
        @($result.Issues | Where-Object File -eq 'activeContext.md') |
            Should -HaveCount 1
    }

    It 'warns before an append-only core file reaches its line budget' {
        $repositoryPath = Join-Path $TestDrive 'near-budget-core'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        & $script:initializerPath -Path $repositoryPath -Confirm:$false |
            Out-Null
        $progressPath = Join-Path $repositoryPath '.memory-bank/progress.md'
        $padding = 190 - @(Get-Content -LiteralPath $progressPath).Count
        Add-Content -LiteralPath $progressPath -Value (
            1..$padding | ForEach-Object { "Headroom line $_" }
        )

        $result = & $script:healthCheckPath `
            -Path $repositoryPath `
            -ReferenceDate ([datetime]'2026-07-24')

        $result.Passed | Should -BeTrue
        $result.ErrorCount | Should -Be 0
        @($result.Issues | Where-Object Code -eq 'LineBudgetNearLimit') |
            Should -HaveCount 1
        @($result.Issues | Where-Object File -eq 'progress.md') |
            Should -HaveCount 1
    }

    It 'requires provenance metadata on optional Memory Bank topics' {
        $repositoryPath = Join-Path $TestDrive 'invalid-topic'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        & $script:initializerPath -Path $repositoryPath -Confirm:$false |
            Out-Null
        $topicsPath = Join-Path $repositoryPath '.memory-bank/topics'
        New-Item -ItemType Directory -Path $topicsPath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $topicsPath 'api.md') -Value (
            "# API notes`n"
        )

        $result = & $script:healthCheckPath `
            -Path $repositoryPath `
            -ReferenceDate ([datetime]'2026-07-24')

        $result.Passed | Should -BeFalse
        $result.MemoryBankTopicCount | Should -Be 1
        @($result.Issues | Where-Object Code -eq 'MetadataMissing') |
            Should -HaveCount 4
    }

    It 'warns on stale verification and expired prompt history' {
        $repositoryPath = Join-Path $TestDrive 'stale-records'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        & $script:initializerPath -Path $repositoryPath -Confirm:$false |
            Out-Null
        $projectBriefPath = Join-Path $repositoryPath (
            '.memory-bank/projectbrief.md'
        )
        $projectBrief = Get-Content -LiteralPath $projectBriefPath -Raw
        $projectBrief = $projectBrief -replace (
            'last-verified: \d{4}-\d{2}-\d{2}',
            'last-verified: 2025-01-01'
        )
        Set-Content -LiteralPath $projectBriefPath -Value $projectBrief
        Add-Content -LiteralPath (Join-Path $repositoryPath (
            '.memory-bank/promptHistory.md'
        )) -Value '2025-01-01 00:00 UTC | test | expired entry'

        $result = & $script:healthCheckPath `
            -Path $repositoryPath `
            -ReferenceDate ([datetime]'2026-07-24')

        $result.Passed | Should -BeTrue
        $result.WarningCount | Should -Be 2
        @($result.Issues | Where-Object Code -eq 'VerificationStale') |
            Should -HaveCount 1
        @($result.Issues | Where-Object Code -eq 'PromptHistoryExpired') |
            Should -HaveCount 1
    }
}
