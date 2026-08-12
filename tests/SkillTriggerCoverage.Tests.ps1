$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:skillRoot = Join-Path $script:repoRoot 'Skills'
$script:queryRoot = Join-Path $script:skillRoot 'agent-evals/assets'

# Query files that deliberately do not name a shipped Skill.
$script:nonSkillQuerySet = @('sample')

<#
    Skills with no trigger-query set yet. Coverage is rolled out a cluster at a
    time because every set costs a paid judge sweep to be worth anything, so
    this list is the honest record of what is not measured. It may only shrink:
    adding a Skill without a query set fails the coverage test, and covering a
    Skill fails the baseline test until its entry is removed.
#>
$script:uncoveredSkillBaseline = @(
    'agent-evals'
    'agent-security-review'
    'authenticated-web-extraction'
    'automatedlab-deployment'
    'automatedlab-proxmox'
    'citation-integrity'
    'code-review-and-quality'
    'create-outlook-draft'
    'datum-configuration'
    'debugging-and-error-recovery'
    'devils-advocate-review'
    'doc-coauthoring'
    'docx-to-markdown'
    'dsc-troubleshooting'
    'evidence-package-assembly'
    'german-legal-research'
    'german-tax-research'
    'gilb-requirements-engineering'
    'grammar-check'
    'grill-me'
    'long-running-job-monitor'
    'marp-slide-overflow'
    'mcp-builder'
    'mecm-dsc-deployment'
    'memory-bank'
    'microsoft-todo-tasks'
    'outlook-calendar-export'
    'outlook-email-export'
    'pandoc-docx-export'
    'pdf-to-markdown'
    'pswritehtml-reporting'
    'send-outlook-email'
    'social-signal-sweep'
    'subagent-dispatch'
    'whisper-pyannote-transcription'
    'windows-gui-screenshot-capture'
    'winrm-troubleshooting'
    'xlsx-to-markdown'
)

# Built during discovery so -ForEach expands; a BeforeAll would produce zero cases.
$script:skillCase = @(
    Get-ChildItem -LiteralPath $script:skillRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        ForEach-Object {
            @{
                SkillName = $_.Name
                QueryPath = Join-Path $script:queryRoot ('trigger-queries.{0}.json' -f $_.Name)
                IsUncoveredBaseline = $script:uncoveredSkillBaseline -contains $_.Name
            }
        }
)

$script:queryFileCase = @(
    Get-ChildItem -LiteralPath $script:queryRoot -File -Filter 'trigger-queries.*.json' |
        ForEach-Object {
            $target = $_.BaseName -replace '^trigger-queries\.', ''

            @{
                QueryName = $target
                QueryPath = $_.FullName
                IsSkillSet = $script:nonSkillQuerySet -notcontains $target
            }
        }
)

BeforeAll {
    # Discovery-scope variables are not visible inside It; every path an
    # assertion touches has to be re-established here.
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skillRoot = Join-Path $script:repoRoot 'Skills'
    $script:queryRoot = Join-Path $script:skillRoot 'agent-evals/assets'
}

Describe 'Skill trigger coverage' -Tag 'Unit' {
    It 'generates a test case for every shipped Skill' -ForEach @(
        @{ DiscoveredCount = $script:skillCase.Count }
    ) {
        $shipped = @(
            Get-ChildItem -LiteralPath $script:skillRoot -Directory |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf }
        ).Count

        $shipped | Should -BeGreaterThan 30
        $DiscoveredCount |
            Should -Be $shipped -Because 'a discovery-time miss would silently skip every case'
    }

    It '<SkillName> has a trigger-query set' -ForEach $script:skillCase {
        if ($IsUncoveredBaseline) {
            Set-ItResult -Skipped -Because 'the Skill is on the documented uncovered baseline'
            return
        }

        Test-Path -LiteralPath $QueryPath -PathType Leaf |
            Should -BeTrue -Because 'a Skill with no labelled queries has never been measured for discovery'
    }

    It '<SkillName> is still uncovered and must stay on the baseline' -ForEach @(
        $script:uncoveredSkillBaseline |
            ForEach-Object {
                @{
                    SkillName = $_
                    QueryPath = Join-Path $script:queryRoot ('trigger-queries.{0}.json' -f $_)
                }
            }
    ) {
        Test-Path -LiteralPath $QueryPath -PathType Leaf |
            Should -BeFalse -Because 'a Skill that gained a query set must be removed from the uncovered baseline'
    }

    It 'baselines only Skills that exist' -ForEach @(
        @{ Baseline = $script:uncoveredSkillBaseline }
    ) {
        foreach ($skillName in $Baseline) {
            Test-Path -LiteralPath (Join-Path $script:skillRoot "$skillName/SKILL.md") -PathType Leaf |
                Should -BeTrue -Because "the baseline names $skillName, which no longer ships"
        }
    }
}

Describe 'Trigger-query sets' -Tag 'Unit' {
    It '<QueryName> names a shipped Skill' -ForEach $script:queryFileCase {
        if (-not $IsSkillSet) {
            Set-ItResult -Skipped -Because 'the set is a documented non-Skill example'
            return
        }

        Test-Path -LiteralPath (Join-Path $script:skillRoot "$QueryName/SKILL.md") -PathType Leaf |
            Should -BeTrue -Because 'a query set that outlives its Skill measures nothing'
    }

    It '<QueryName> parses and labels every case' -ForEach $script:queryFileCase {
        if (-not $IsSkillSet) {
            Set-ItResult -Skipped -Because 'the set is a documented non-Skill example'
            return
        }

        $case = @(Get-Content -LiteralPath $QueryPath -Raw -Encoding UTF8 | ConvertFrom-Json)

        $case.Count | Should -BeGreaterOrEqual 8 -Because 'a handful of queries cannot separate a trigger from a coin flip'

        foreach ($currentCase in $case) {
            $currentCase.id | Should -Not -BeNullOrEmpty
            $currentCase.query | Should -Not -BeNullOrEmpty
            $currentCase.should_trigger | Should -BeOfType [bool]
            $currentCase.split | Should -BeIn @('train', 'validation')
        }

        @($case.id | Sort-Object -Unique).Count |
            Should -Be $case.Count -Because 'the harness correlates replies on id, so a duplicate silently overwrites a result'
    }

    It '<QueryName> carries positives and near-miss negatives in both splits' -ForEach $script:queryFileCase {
        if (-not $IsSkillSet) {
            Set-ItResult -Skipped -Because 'the set is a documented non-Skill example'
            return
        }

        $case = @(Get-Content -LiteralPath $QueryPath -Raw -Encoding UTF8 | ConvertFrom-Json)

        @($case | Where-Object { $_.should_trigger }).Count |
            Should -BeGreaterOrEqual 3 -Because 'a set with almost no positives cannot show the Skill is reachable'

        @($case | Where-Object { -not $_.should_trigger }).Count |
            Should -BeGreaterOrEqual 3 -Because 'without negatives, a description that matches everything scores perfectly'

        foreach ($split in @('train', 'validation')) {
            @($case | Where-Object { $_.split -eq $split }).Count |
                Should -BeGreaterThan 0 -Because 'the split exists to expose overfitting and needs both halves populated'
        }
    }
}
