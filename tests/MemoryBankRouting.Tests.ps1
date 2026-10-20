BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:evalFile = Join-Path $script:repoRoot (
        'skills/memory-bank/evals/routing-cases.json'
    )
    $script:evaluatorPath = Join-Path $script:repoRoot (
        'skills/memory-bank/scripts/Test-MemoryBankRouting.ps1'
    )
    $script:initializerPath = Join-Path $script:repoRoot (
        'skills/memory-bank/scripts/Initialize-MemoryBank.ps1'
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
        $result.RoleFileFailures | Should -Be 0

        # Both averages are reported; the floor gates on the one without the
        # cases whose only route is general, which load the index alone.
        $result.PSObject.Properties.Name |
            Should -Contain 'AverageContextReductionPercent'
        $result.PSObject.Properties.Name |
            Should -Contain 'AverageContextReductionPercentExcludingGeneralOnly'
        $result.AverageContextReductionPercentExcludingGeneralOnly |
            Should -BeGreaterOrEqual 50
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
        $result.RoleFileFailures | Should -Be 0
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
            'skills/memory-bank/scripts/Initialize-MemoryBank.ps1'
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
        $result.RoleFileFailures | Should -Be 0
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
        $requiredFileName = @(
            'index.md'
            'projectbrief.md'
            'productContext.md'
            'activeContext.md'
            'techContext.md'
            'progress.md'
            'systemPatterns.md'
        )

        # Both are optional; promptHistory.md is gitignored and therefore absent
        # from a clean checkout.
        $optionalFileName = @('glossary.md', 'promptHistory.md')

        foreach ($fileName in ($requiredFileName + $optionalFileName)) {
            $filePath = Join-Path $script:repoRoot ".memory-bank/$fileName"

            if ($fileName -in $optionalFileName -and
                -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                continue
            }

            Test-Path -LiteralPath $filePath -PathType Leaf |
                Should -BeTrue -Because $fileName

            $content = Get-Content -LiteralPath $filePath -Raw
            $content | Should -Match '(?m)^status: [a-z-]+\r?$' -Because $fileName
            $content |
                Should -Match '(?m)^last-verified: \d{4}-\d{2}-\d{2}\r?$' `
                -Because $fileName
            $content | Should -Match '(?m)^owner: [a-z0-9-]+\r?$' -Because $fileName
            $content | Should -Match '(?m)^source: .+\r?$' -Because $fileName
        }
    }
}

Describe 'Memory Bank route coverage' {
    BeforeAll {
        <#
            Memory Bank routes that no real case exercises yet, each with the
            reason no real task covers it. Every route the index defines has a
            real case today, so the baseline is empty. A route the index gains
            without a real case fails the coverage test until it gains one or
            an entry here, and an entry whose route gains a real case fails the
            baseline test until it is removed, so the list can only shrink. A
            fixture case is never real coverage, but a reason may cite one.
        #>
        $script:uncoveredRouteBaseline = [ordered]@{}

        $script:fixtureRepository = Join-Path $TestDrive 'route-coverage'
        New-Item -ItemType Directory -Path $script:fixtureRepository -Force |
            Out-Null
        & $script:initializerPath -Path $script:fixtureRepository -Confirm:$false |
            Out-Null
        Set-Content -LiteralPath (
            Join-Path $script:fixtureRepository '.memory-bank/legal-case.md'
        ) -Value '# Legal case'

        function Invoke-RoutingFixture {
            [CmdletBinding()]
            [OutputType([PSCustomObject])]
            param(
                [Parameter(Mandatory)]
                [hashtable[]]$Case,

                [Parameter()]
                [ValidateSet('routed', 'full')]
                [string]$LoadingMode
            )

            $cases = @(
                for ($index = 0; $index -lt $Case.Count; $index++) {
                    $merged = @{
                        id = "fixture-$index"
                        source = "session:fixture:$index"
                        prompt = 'Fixture task.'
                        requiredFiles = @('index.md')
                        allowHistory = $false
                        durableWrite = $false
                    }
                    foreach ($key in $Case[$index].Keys) {
                        $merged[$key] = $Case[$index][$key]
                    }
                    $merged
                }
            )
            $evalPath = Join-Path $script:fixtureRepository (
                'cases-{0}.json' -f [guid]::NewGuid().ToString('N')
            )
            @{ schemaVersion = 1; cases = $cases } |
                ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $evalPath

            $evaluatorArguments = @{
                Path = $script:fixtureRepository
                EvalFile = $evalPath
            }
            if ($PSBoundParameters.ContainsKey('LoadingMode')) {
                $evaluatorArguments.LoadingMode = $LoadingMode
            }
            & $script:evaluatorPath @evaluatorArguments
        }

        $script:realCoverage = & $script:evaluatorPath -Path $script:repoRoot -EvalFile $script:evalFile
    }

    Context 'When the real task cases are evaluated' {
        It 'reports the routes the index defines' {
            $script:realCoverage.PSObject.Properties.Name |
                Should -Contain 'IndexRoutes'
            $script:realCoverage.PSObject.Properties.Name |
                Should -Contain 'UncoveredRoutes'
            @($script:realCoverage.IndexRoutes).Count |
                Should -BeGreaterThan 0 -Because (
                    'a parser that finds no route would report every route covered'
                )
        }

        It 'gives every route a real case or a baseline entry' {
            $script:realCoverage.PSObject.Properties.Name |
                Should -Contain 'UncoveredRoutes'

            $unbaselined = @(
                $script:realCoverage.UncoveredRoutes |
                    Where-Object { $_ -notin $script:uncoveredRouteBaseline.Keys }
            )

            $unbaselined | Should -BeNullOrEmpty -Because (
                'no real case exercises: ' + ($unbaselined -join ', ')
            )
        }

        It 'keeps every baselined route uncovered so the baseline can only shrink' {
            $covered = @(
                $script:uncoveredRouteBaseline.Keys |
                    Where-Object { $_ -notin $script:realCoverage.UncoveredRoutes }
            )

            $covered | Should -BeNullOrEmpty -Because (
                'a real case now covers these routes, or the index no longer defines ' +
                'them, so remove them from the baseline: ' + ($covered -join ', ')
            )
        }

        It 'baselines only routes the index defines' {
            $unknown = @(
                $script:uncoveredRouteBaseline.Keys |
                    Where-Object { $_ -notin $script:realCoverage.IndexRoutes }
            )

            $unknown | Should -BeNullOrEmpty -Because (
                'the index no longer defines: ' + ($unknown -join ', ')
            )
        }

        It 'states a reason for every baselined route' {
            foreach ($route in $script:uncoveredRouteBaseline.Keys) {
                [string]::IsNullOrWhiteSpace($script:uncoveredRouteBaseline[$route]) |
                    Should -Be $false -Because "the baseline needs a reason for $route"
            }
        }
    }

    Context 'When the evaluator reports coverage for a fixture checkout' {
        It 'splits the index routes into covered and uncovered routes' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @('status') }
                @{ routes = @('scope', 'status') }
            )

            $result.UncoveredRoutes | Should -Not -Contain 'status'
            $result.UncoveredRoutes | Should -Not -Contain 'scope'
            $result.UncoveredRoutes | Should -Contain 'general'
            $result.UncoveredRoutes | Should -Contain 'role'
            @($result.UncoveredRoutes + @('status', 'scope') | Sort-Object) |
                Should -Be @($result.IndexRoutes | Sort-Object)
        }

        It 'does not count a route that only an expected fallback case names' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @('unknown', 'language'); expectFallback = $true }
            )

            $result.FallbackFailures | Should -Be 0
            $result.IndexRoutes | Should -Not -Contain 'unknown'
            $result.UncoveredRoutes | Should -Contain 'language'
        }

        It 'reports the same uncovered routes in full loading mode' {
            $cases = @(@{ routes = @('status') })

            $routed = Invoke-RoutingFixture -Case $cases
            $full = Invoke-RoutingFixture -Case $cases -LoadingMode full

            $routed.UncoveredRoutes | Should -Not -BeNullOrEmpty
            $full.UncoveredRoutes | Should -Be $routed.UncoveredRoutes
        }
    }

    Context 'When a case names role files' {
        It 'reports <Name>' -ForEach @(
            @{
                Name = 'a role case without roleFiles'
                Case = @{ routes = @('role') }
            }
            @{
                Name = 'a role case with an empty roleFiles list'
                Case = @{ routes = @('role'); roleFiles = @() }
            }
            @{
                Name = 'a role case whose roleFiles are blank'
                Case = @{ routes = @('role'); roleFiles = @(' ') }
            }
            @{
                Name = 'roleFiles on a case that does not route to role'
                Case = @{ routes = @('status'); roleFiles = @('legal-case.md') }
            }
        ) {
            $result = Invoke-RoutingFixture -Case @($Case)

            $result.RoleFileFailures | Should -Be 1
            $result.Passed | Should -Be $false
        }

        It 'accepts a role case that names a role file' {
            $result = Invoke-RoutingFixture -Case @(
                @{
                    routes = @('role')
                    roleFiles = @('legal-case.md')
                    requiredFiles = @('index.md', 'legal-case.md')
                }
            )

            $result.RoleFileFailures | Should -Be 0
            $result.Passed | Should -Be $true
        }

        It 'counts every inconsistent case once' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @('role') }
                @{ routes = @('status'); roleFiles = @('legal-case.md') }
                @{
                    routes = @('role')
                    roleFiles = @('legal-case.md')
                    requiredFiles = @('index.md', 'legal-case.md')
                }
            )

            $result.RoleFileFailures | Should -Be 2
        }

        It 'applies in full loading mode as well' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @('role') }
            ) -LoadingMode full

            $result.RoleFileFailures | Should -Be 1
            $result.Passed | Should -Be $false
        }

        It 'loads the role files of a role case in full loading mode' {
            $result = Invoke-RoutingFixture -Case @(
                @{
                    routes = @('role')
                    roleFiles = @('legal-case.md')
                    requiredFiles = @('index.md', 'legal-case.md')
                }
            ) -LoadingMode full

            $result.Details[0].Files | Should -Contain 'legal-case.md' -Because (
                'the active Custom agent reads its role files in every loading mode, ' +
                'and the full base names none'
            )
            $result.CoverageMisses | Should -Be 0
            $result.Passed | Should -Be $true
        }

        It 'loads the role files of a role case that falls back' {
            $result = Invoke-RoutingFixture -Case @(
                @{
                    routes = @('role', 'unknown')
                    roleFiles = @('legal-case.md')
                    requiredFiles = @('index.md', 'legal-case.md')
                    expectFallback = $true
                }
            )

            $result.Details[0].UsedFallback | Should -Be $true
            $result.Details[0].Files | Should -Contain 'legal-case.md'
            $result.CoverageMisses | Should -Be 0
            $result.Passed | Should -Be $true
        }
    }

    Context 'When the context reduction is averaged' {
        It 'leaves a case whose only route is general out of the gated average' {
            $mixed = Invoke-RoutingFixture -Case @(
                @{ routes = @('general') }
                @{ routes = @('status') }
            )
            $statusOnly = Invoke-RoutingFixture -Case @(
                @{ routes = @('status') }
            )

            $mixed.GeneralOnlyCaseCount | Should -Be 1
            $mixed.AverageContextReductionPercentExcludingGeneralOnly |
                Should -Be $statusOnly.AverageContextReductionPercent
            $mixed.AverageContextReductionPercent |
                Should -BeGreaterThan $mixed.AverageContextReductionPercentExcludingGeneralOnly -Because (
                    'a case that loads only the index raises the average over all cases'
                )
        }

        It 'keeps a case that routes to general and another route in the gated average' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @('general', 'status') }
            )

            $result.GeneralOnlyCaseCount | Should -Be 0
            $result.AverageContextReductionPercentExcludingGeneralOnly |
                Should -Be $result.AverageContextReductionPercent
        }

        It 'leaves a case that names no route out of the gated average as well' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @() }
                @{ routes = @('status') }
            )
            $statusOnly = Invoke-RoutingFixture -Case @(
                @{ routes = @('status') }
            )

            $result.GeneralOnlyCaseCount | Should -Be 1 -Because (
                'a case without a route loads only the index, like a general one'
            )
            $result.AverageContextReductionPercentExcludingGeneralOnly |
                Should -Be $statusOnly.AverageContextReductionPercent
        }

        It 'reports no gated average when every case is general-only' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @('general') }
            )

            $result.GeneralOnlyCaseCount | Should -Be 1
            $result.AverageContextReductionPercent | Should -BeGreaterThan 0
            $result.AverageContextReductionPercentExcludingGeneralOnly |
                Should -BeNullOrEmpty -Because (
                    'no case is left to average, so the floor cannot pass on general questions alone'
                )
        }

        It 'reports both averages as zero in full loading mode' {
            $result = Invoke-RoutingFixture -Case @(
                @{ routes = @('general') }
                @{ routes = @('status') }
            ) -LoadingMode full

            $result.GeneralOnlyCaseCount | Should -Be 1
            $result.AverageContextReductionPercent | Should -Be 0
            $result.AverageContextReductionPercentExcludingGeneralOnly | Should -Be 0
        }
    }
}
