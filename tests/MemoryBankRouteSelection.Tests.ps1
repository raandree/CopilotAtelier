BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:evaluatorPath = Join-Path $script:repoRoot (
        'Skills/memory-bank/scripts/Invoke-MemoryBankRouteSelectionEval.ps1'
    )
    $script:fixtureRoot = Join-Path $TestDrive 'repository'
    $script:memoryBankPath = Join-Path $script:fixtureRoot '.memory-bank'
    $script:workDir = Join-Path $TestDrive 'route-selection'
    $script:evalFile = Join-Path $TestDrive 'routing-cases.json'

    New-Item -ItemType Directory -Path $script:memoryBankPath -Force |
        Out-Null

    @'
---
loading-mode: routed
---

# Memory Bank index

| Route | Task signals | Read |
|---|---|---|
| `general` | General Q&A | Index only |
| `architecture` | Design, pattern, decision | `systemPatterns.md`, relevant `decisions/*.md` |
| `status` | Progress, recent change | `progress.md`, `activeContext.md` |
| `interaction-history` | Session analysis | `promptHistory.md`, `progress.md` |
'@ | Set-Content -LiteralPath (
        Join-Path $script:memoryBankPath 'index.md'
    ) -Encoding UTF8

    @{
        schemaVersion = 1
        cases = @(
            @{
                id = 'architecture-status'
                source = 'session:00000000-0000-0000-0000-000000000001'
                prompt = 'Explain the recent architecture decision.'
                routes = @('architecture', 'status')
                requiredFiles = @('do-not-leak.md')
                durableWrite = $false
            }
            @{
                id = 'general-question'
                source = 'session:00000000-0000-0000-0000-000000000002'
                prompt = 'What does this project do?'
                routes = @('general')
                requiredFiles = @('index.md')
                durableWrite = $false
            }
            @{
                id = 'ambiguous-continuation'
                source = 'session:00000000-0000-0000-0000-000000000003'
                prompt = 'Okay, do that.'
                routes = @('unknown')
                requiredFiles = @('index.md')
                durableWrite = $true
                expectFallback = $true
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:evalFile `
        -Encoding UTF8

    function Invoke-RouteSelectionPrepare {
        & $script:evaluatorPath `
            -Mode Prepare `
            -Path $script:fixtureRoot `
            -EvalFile $script:evalFile `
            -WorkDir $script:workDir `
            -Repetitions 2
    }

    function Write-RouteSelectionReply {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Content
        )

        Set-Content -LiteralPath (Join-Path $script:workDir $Name) `
            -Value $Content -Encoding UTF8
    }
}

Describe 'Memory Bank route selection evaluation' -Tag 'Unit' {
    BeforeEach {
        Remove-Item -LiteralPath $script:workDir -Recurse -Force `
            -ErrorAction SilentlyContinue
    }

    It 'prepares one isolated natural-language prompt per case and repetition' {
        Test-Path -LiteralPath $script:evaluatorPath -PathType Leaf |
            Should -BeTrue

        $result = Invoke-RouteSelectionPrepare

        $result.Mode | Should -Be 'Prepare'
        $result.CaseCount | Should -Be 3
        $result.PromptCount | Should -Be 6
        @(Get-ChildItem -LiteralPath $script:workDir -Filter '*.prompt.txt') |
            Should -HaveCount 6
    }

    It 'does not leak human labels or resolver expectations into judge prompts' {
        Invoke-RouteSelectionPrepare | Out-Null

        $promptPath = Join-Path $script:workDir (
            'architecture-status.rep1.prompt.txt'
        )
        $prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

        $prompt | Should -Match 'Explain the recent architecture decision\.'
        $prompt | Should -Match '"fallback":false'
        $prompt | Should -Not -Match 'do-not-leak\.md'
        $prompt | Should -Not -Match '00000000-0000-0000-0000-000000000001'
    }

    It 'grades route inference with pass-at-k and pass-hat-k reliability' {
        Invoke-RouteSelectionPrepare | Out-Null

        Write-RouteSelectionReply 'architecture-status.rep1.out.json' `
            '{"routes":["status","architecture"],"fallback":false}'
        Write-RouteSelectionReply 'architecture-status.rep2.out.json' `
            '{"routes":["architecture","status"],"fallback":false}'
        Write-RouteSelectionReply 'general-question.rep1.out.json' `
            '{"routes":["general"],"fallback":false}'
        Write-RouteSelectionReply 'general-question.rep2.out.json' `
            '{"routes":["status"],"fallback":false}'
        Write-RouteSelectionReply 'ambiguous-continuation.rep1.out.json' `
            '{"routes":[],"fallback":true}'
        Write-RouteSelectionReply 'ambiguous-continuation.rep2.out.json' `
            '{"routes":["general"],"fallback":true}'

        $result = & $script:evaluatorPath `
            -Mode Grade `
            -Path $script:fixtureRoot `
            -EvalFile $script:evalFile `
            -WorkDir $script:workDir `
            -Repetitions 2

        $result.Passed | Should -BeFalse
        $result.CorrectReplies | Should -Be 5
        $result.IncorrectReplies | Should -Be 1
        $result.MissingReplies | Should -Be 0
        $result.MalformedReplies | Should -Be 0
        $result.PassAtKCaseCount | Should -Be 3
        $result.PassHatKCaseCount | Should -Be 2
    }

    It 'counts malformed and missing replies as reliability failures' {
        Invoke-RouteSelectionPrepare | Out-Null
        Write-RouteSelectionReply 'architecture-status.rep1.out.json' `
            'not-json'
        Write-RouteSelectionReply 'architecture-status.rep2.out.json' `
            '{"routes":"architecture","fallback":false}'

        $result = & $script:evaluatorPath `
            -Mode Grade `
            -Path $script:fixtureRoot `
            -EvalFile $script:evalFile `
            -WorkDir $script:workDir `
            -Repetitions 2

        $result.Passed | Should -BeFalse
        $result.MalformedReplies | Should -Be 2
        $result.MissingReplies | Should -Be 4
        $result.PassAtKCaseCount | Should -Be 0
        $result.PassHatKCaseCount | Should -Be 0
    }
}
