BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $preflightPath = Join-Path $repoRoot 'instructions/preflight.instructions.md'
    $memoryBankIndexPath = Join-Path $repoRoot '.memory-bank/index.md'
    $script:preflightContent = Get-Content -LiteralPath $preflightPath -Raw
    $script:preflightLineCount = @(Get-Content -LiteralPath $preflightPath).Count
    $script:memoryBankIndexContent = if (
        Test-Path -LiteralPath $memoryBankIndexPath -PathType Leaf
    ) {
        Get-Content -LiteralPath $memoryBankIndexPath -Raw
    } else {
        ''
    }
}

Describe 'Pre-flight Instruction' {
    It 'stays within a compact prompt budget' {
        $script:preflightLineCount | Should -BeLessOrEqual 60
    }

    It 'reuses Instruction content already supplied in context' {
        $script:preflightContent | Should -Match 'already supplied'
        $script:preflightContent | Should -Match 'absent or incomplete'
        $script:preflightContent | Should -Match 'Do not re-read'
    }

    It 'loads each matching Skill body at most once per turn' {
        $script:preflightContent | Should -Match '`?SKILL\.md`? at most once'
        $script:preflightContent | Should -Match 'full body is already supplied'
    }

    It 'routes Memory Bank reads through a compact index' {
        $script:preflightContent | Should -Match 'index\.md`'
        $script:preflightContent | Should -Match '(?i)only unconditional.*read'
        $script:preflightContent | Should -Match '(?i)task-relevant'
        $script:memoryBankIndexContent | Should -Match '(?m)^loading-mode: routed\r?$'
    }

    It 'fails open and retains a full-read rollback' {
        $script:preflightContent | Should -Match '(?i)fail open'
        $script:preflightContent | Should -Match '(?i)loading-mode.*full'
        $script:memoryBankIndexContent | Should -Match '(?i)full-read fallback'
    }

    It 'does not load prompt history during routine pre-flight' {
        $script:preflightContent |
            Should -Match '(?i)promptHistory\.md.*history.*eval'
        $script:preflightContent |
            Should -Match '(?i)do not read.*promptHistory\.md.*routine'
    }
}
