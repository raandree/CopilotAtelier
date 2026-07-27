BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:evalFile = Join-Path $script:repoRoot (
        'Skills/memory-bank/evals/routing-cases.json'
    )
    $script:evaluatorPath = Join-Path $script:repoRoot (
        'Skills/memory-bank/scripts/Test-MemoryBankRouting.ps1'
    )
    $script:indexPath = Join-Path $script:repoRoot '.memory-bank/index.md'
    $script:decisionsPath = Join-Path $script:repoRoot '.memory-bank/decisions'
    $script:systemPatternsPath = Join-Path $script:repoRoot (
        '.memory-bank/systemPatterns.md'
    )
}

Describe 'Memory Bank routing evaluation' {
    It 'uses 20 to 50 auditable real task intents' {
        Test-Path -LiteralPath $script:evalFile -PathType Leaf | Should -BeTrue

        $evalSet = Get-Content -LiteralPath $script:evalFile -Raw |
            ConvertFrom-Json
        @($evalSet.cases).Count | Should -BeGreaterOrEqual 20
        @($evalSet.cases).Count | Should -BeLessOrEqual 50
        @($evalSet.cases.id | Sort-Object -Unique).Count |
            Should -Be @($evalSet.cases).Count

        foreach ($case in $evalSet.cases) {
            $case.id | Should -Not -BeNullOrEmpty
            $case.prompt | Should -Not -BeNullOrEmpty -Because $case.id
            $case.source |
                Should -Match '^(session|prompt-history|git):' -Because $case.id
            if ($case.source -like 'session:*') {
                $case.source | Should -Match (
                    '^session:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-' +
                    '[0-9a-f]{4}-[0-9a-f]{12}' +
                    '(?:\+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-' +
                    '[0-9a-f]{4}-[0-9a-f]{12}|:session-start)?$'
                ) -Because $case.id
            }
            if ($case.source -like 'git:*') {
                $case.source | Should -Match '^git:[0-9a-f]{7,40}$' `
                    -Because $case.id
            }
        }
    }

    It 'routes every baseline case without a critical context miss' {
        Test-Path -LiteralPath $script:evaluatorPath -PathType Leaf |
            Should -BeTrue

        $result = & $script:evaluatorPath `
            -Path $script:repoRoot `
            -EvalFile $script:evalFile

        $result.Passed | Should -BeTrue
        $result.CaseCount | Should -BeGreaterOrEqual 20
        $result.CoverageMisses | Should -Be 0
        $result.UnexpectedHistoryLoads | Should -Be 0
        $result.FallbackFailures | Should -Be 0
        $result.AverageContextReductionPercent | Should -BeGreaterOrEqual 50
    }

    It 'retains full loading as a tested rollback' {
        $result = & $script:evaluatorPath `
            -Path $script:repoRoot `
            -EvalFile $script:evalFile `
            -LoadingMode full

        $result.Passed | Should -BeTrue
        $result.Mode | Should -Be 'full'
        $result.CoverageMisses | Should -Be 0
        $result.FallbackFailures | Should -Be 0
        $result.FullDecisionRecordCount | Should -BeGreaterThan 0
        foreach ($detail in $result.Details) {
            @($detail.Files | Where-Object { $_ -like 'decisions/*.md' }).Count |
                Should -Be $result.FullDecisionRecordCount -Because $detail.Id
        }
    }

    It 'evaluates a clean checkout without local prompt history' {
        $repositoryPath = Join-Path $TestDrive 'clean-checkout'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        $memoryBankPath = Join-Path $repositoryPath '.memory-bank'
        & (Join-Path $script:repoRoot (
            'Skills/memory-bank/scripts/Initialize-MemoryBank.ps1'
        )) -Path $repositoryPath -Confirm:$false | Out-Null
        Remove-Item -LiteralPath (Join-Path $memoryBankPath 'promptHistory.md')
        Set-Content -LiteralPath (Join-Path $memoryBankPath 'legal-case.md') `
            -Value '# Legal case'

        $evalPath = Join-Path $repositoryPath 'clean-checkout-cases.json'
        @{
            schemaVersion = 1
            cases = @(
                @{
                    id = 'general-without-history'
                    source = 'session:clean-checkout:1'
                    prompt = 'Explain the project.'
                    routes = @('general')
                    requiredFiles = @('index.md')
                    allowHistory = $false
                    durableWrite = $false
                }
                @{
                    id = 'history-without-local-log'
                    source = 'session:clean-checkout:2'
                    prompt = 'Analyze available interaction history.'
                    routes = @('interaction-history')
                    requiredFiles = @('index.md', 'progress.md')
                    allowHistory = $true
                    durableWrite = $false
                }
                @{
                    id = 'role-file-selection'
                    source = 'session:clean-checkout:3'
                    prompt = 'Continue the active legal case.'
                    routes = @('role')
                    roleFiles = @('legal-case.md')
                    requiredFiles = @('index.md', 'legal-case.md')
                    allowHistory = $false
                    durableWrite = $false
                }
                @{
                    id = 'language-without-glossary'
                    source = 'session:clean-checkout:4'
                    prompt = 'Use the repository language rules if present.'
                    routes = @('language')
                    requiredFiles = @('index.md')
                    allowHistory = $false
                    durableWrite = $false
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $evalPath

        $result = & $script:evaluatorPath `
            -Path $repositoryPath `
            -EvalFile $evalPath

        $result.Passed | Should -BeTrue
        $result.CoverageMisses | Should -Be 0
        $result.FallbackFailures | Should -Be 0
        $result.LocalPromptHistoryPresent | Should -BeFalse
        $result.Details |
            Where-Object Id -eq 'language-without-glossary' |
            Select-Object -ExpandProperty UsedFallback |
            Should -BeFalse
    }

    It 'keeps the unconditional index within a compact budget' {
        @(Get-Content -LiteralPath $script:indexPath).Count |
            Should -BeLessOrEqual 100
        (Get-Content -LiteralPath $script:indexPath -Raw).Length |
            Should -BeLessOrEqual 7000
    }

    It 'extracts every durable decision into a metadata-bearing record' {
        $decisionFiles = @(
            Get-ChildItem -LiteralPath $script:decisionsPath -Filter '*.md' -File
        )
        $indexedDecisionFiles = @(
            [regex]::Matches(
                (Get-Content -LiteralPath $script:systemPatternsPath -Raw),
                'decisions/(?<file>\d{4}-[a-z0-9-]+\.md)'
            ) |
                ForEach-Object { $_.Groups['file'].Value } |
                Sort-Object -Unique
        )
        $decisionFiles.Name | Sort-Object |
            Should -Be $indexedDecisionFiles

        foreach ($decisionFile in $decisionFiles) {
            $content = Get-Content -LiteralPath $decisionFile.FullName -Raw
            $content | Should -Match '(?m)^status: (accepted|superseded)\r?$'
            $content | Should -Match '(?m)^date: \d{4}-\d{2}-\d{2}\r?$'
            $content | Should -Match '(?m)^last-verified: \d{4}-\d{2}-\d{2}\r?$'
            $content | Should -Match '(?m)^owner: [a-z0-9-]+\r?$'
            $content | Should -Match '(?m)^source: .+\r?$'
            $content | Should -Match '(?m)^## Decision outcome\r?$'
            $content | Should -Match '(?m)^## Confirmation\r?$'
        }
    }

    It 'keeps system patterns as a compact current architecture index' {
        $content = Get-Content -LiteralPath $script:systemPatternsPath -Raw
        @(Get-Content -LiteralPath $script:systemPatternsPath).Count |
            Should -BeLessOrEqual 110
        $content | Should -Not -Match 'Local mirror, always populated'
        $content | Should -Match '(?m)^## Decision index\r?$'
        $content | Should -Match 'decisions/0015-keep-native-memory-role-gated'
    }

    It 'adds freshness and provenance metadata to every core knowledge file' {
        foreach ($fileName in @(
            'index.md'
            'projectbrief.md'
            'productContext.md'
            'activeContext.md'
            'techContext.md'
            'progress.md'
            'systemPatterns.md'
            'glossary.md'
            'promptHistory.md'
        )) {
            $content = Get-Content -LiteralPath (
                Join-Path $script:repoRoot ".memory-bank/$fileName"
            ) -Raw
            $content | Should -Match '(?m)^status: [a-z-]+\r?$' -Because $fileName
            $content |
                Should -Match '(?m)^last-verified: \d{4}-\d{2}-\d{2}\r?$' `
                -Because $fileName
            $content | Should -Match '(?m)^owner: [a-z0-9-]+\r?$' -Because $fileName
            $content | Should -Match '(?m)^source: .+\r?$' -Because $fileName
        }
    }
}
