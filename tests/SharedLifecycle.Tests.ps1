BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:agentsPath = Join-Path $script:repoRoot 'Agents'
    $script:preflightPath = Join-Path $script:repoRoot 'Instructions/preflight.instructions.md'
    $script:postflightPath = Join-Path $script:repoRoot 'Instructions/postflight.instructions.md'
    $script:memoryBankSkillPath = Join-Path $script:repoRoot 'Skills/memory-bank/SKILL.md'

    $script:preflightContent = Get-Content -LiteralPath $script:preflightPath -Raw
    $script:postflightContent = Get-Content -LiteralPath $script:postflightPath -Raw
    $script:memoryBankSkillContent = if (Test-Path -LiteralPath $script:memoryBankSkillPath) {
        Get-Content -LiteralPath $script:memoryBankSkillPath -Raw
    } else {
        ''
    }
    $emDash = [char]0x2014

    $script:agentBaseline = @{
        'career-coach.agent.md' = @{
            Tools = 29
            ToolHash = '29767FFDB6C09FA7'
            Handoffs = 2
            HandoffHash = 'DA7D3D7F53FF5A51'
            MemoryHeading = "## Memory Bank $emDash Persistent Career Knowledge"
            MemoryHash = '17404EE805887082'
        }
        'DevOps Training Writer.agent.md' = @{
            Tools = 29
            ToolHash = '29767FFDB6C09FA7'
            Handoffs = 2
            HandoffHash = '73DBF38F584D2787'
            MemoryHeading = '## 9. Memory Bank'
            MemoryHash = 'B63CB8897007F641'
        }
        'legal-researcher.agent.md' = @{
            Tools = 28
            ToolHash = 'AE7F3D50F1B6DFEE'
            Handoffs = 0
            HandoffHash = 'E3B0C44298FC1C14'
            MemoryHeading = "## Memory Bank $emDash Persistent Case Knowledge"
            MemoryHash = 'DCEEB414C2F56C4D'
        }
        'QC Inspector Agent.agent.md' = @{
            Tools = 28
            ToolHash = 'AE7F3D50F1B6DFEE'
            Handoffs = 0
            HandoffHash = 'E3B0C44298FC1C14'
            MemoryHeading = '## Memory Bank'
            MemoryHash = '9C41851E9999FEDC'
        }
        'research-analyst.agent.md' = @{
            Tools = 38
            ToolHash = '8A9BAB6EC750E34F'
            Handoffs = 2
            HandoffHash = 'DA7D3D7F53FF5A51'
            MemoryHeading = "## Memory Bank $emDash Investigation Persistence"
            MemoryHash = 'CAD590ADFA11950D'
        }
        'Security & Quality Assurance Agent.agent.md' = @{
            Tools = 38
            ToolHash = '52CDF89BF13B35FE'
            Handoffs = 1
            HandoffHash = 'E8D34666ABE6B96D'
            MemoryHeading = '## Memory Bank'
            MemoryHash = 'E5550363574EE4B8'
        }
        'Software Engineer Agent.agent.md' = @{
            Tools = 45
            ToolHash = 'D94007200A192204'
            Handoffs = 2
            HandoffHash = '54AC0FE254828B41'
            MemoryHeading = '## Memory Bank role extension'
            MemoryHash = '7FE1A3A628018B22'
        }
        'tax-researcher.agent.md' = @{
            Tools = 28
            ToolHash = 'AE7F3D50F1B6DFEE'
            Handoffs = 0
            HandoffHash = 'E3B0C44298FC1C14'
            MemoryHeading = "## Memory Bank $emDash Persistent Case Knowledge"
            MemoryHash = 'D5D3D207CC5EAB57'
        }
        'Technical Troubleshooter Agent.agent.md' = @{
            Tools = 41
            ToolHash = '86AF3D5241574039'
            Handoffs = 2
            HandoffHash = '38AF6E22FA343FDC'
            MemoryHeading = '## Memory Bank'
            MemoryHash = '30AD211A671D5598'
        }
        'Technical Writer & Documentation Agent.agent.md' = @{
            Tools = 36
            ToolHash = '55719116741CC126'
            Handoffs = 1
            HandoffHash = '8A78BAB66F6A0D49'
            MemoryHeading = '## Memory Bank'
            MemoryHash = '90EBC5F69900F153'
        }
        'Training Content Writer.agent.md' = @{
            Tools = 29
            ToolHash = '29767FFDB6C09FA7'
            Handoffs = 1
            HandoffHash = '42173AE92365EB75'
            MemoryHeading = '## 11. Memory Bank'
            MemoryHash = 'DFE92372EF752612'
        }
    }

    function Get-ShortHash {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$Value
        )

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Value -join '|')
            ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(
                0,
                16
            )
        } finally {
            $sha.Dispose()
        }
    }
}

Describe 'Shared lifecycle Customizations' {
    It 'initializes a missing or incomplete Memory Bank only for durable work' {
        $script:preflightContent | Should -Match 'memory-bank'
        $script:preflightContent | Should -Match '(?i)initialize'
        $script:preflightContent | Should -Match '(?i)missing'
        $script:preflightContent | Should -Match '(?i)never overwrite'
        $script:preflightContent | Should -Match '(?i)read-only'
        $script:preflightContent | Should -Match '(?i)do not initialize'
    }

    It 'defines the complete canonical Memory Bank base set' {
        foreach ($fileName in @(
            'index.md'
            'projectbrief.md'
            'productContext.md'
            'activeContext.md'
            'techContext.md'
            'progress.md'
            'systemPatterns.md'
            'promptHistory.md'
        )) {
            $script:preflightContent | Should -Match ([regex]::Escape($fileName))
        }
    }

    It 'provides a deployed Definition of Done gate' {
        $script:postflightContent | Should -Match '(?m)^## Definition of Done gate$'
        $script:postflightContent | Should -Match '(?i)acceptance criteria'
        $script:postflightContent | Should -Match '(?i)role-specific'
        $script:postflightContent | Should -Match '(?i)focused.*final validation'
        $script:postflightContent | Should -Match '(?i)self-review'
        $script:postflightContent | Should -Match '(?i)independent review'
        $script:postflightContent | Should -Match '(?i)residual risk'
    }

    It 'ships the Memory Bank initialization Skill with templates and safeguards' {
        Test-Path -LiteralPath $script:memoryBankSkillPath -PathType Leaf | Should -BeTrue
        $script:memoryBankSkillContent | Should -Match '(?m)^name: memory-bank\r?$'
        $script:memoryBankSkillContent | Should -Match 'USE FOR:'
        $script:memoryBankSkillContent | Should -Match 'DO NOT USE FOR:'
        $script:memoryBankSkillContent | Should -Match '(?i)never overwrite'
        $script:memoryBankSkillContent | Should -Match '(?i)role-specific'
        $script:memoryBankSkillContent | Should -Match '(?i)read-only'
        $script:memoryBankSkillContent |
            Should -Match '(?im)^- .*`promptHistory\.md`.*repository policy'
        $script:memoryBankSkillContent |
            Should -Match '(?i)initialization must not alter existing ignore rules'
        $script:memoryBankSkillContent |
            Should -Match '(?i)read `index\.md`.*apply its routes'

        foreach ($fileName in @(
            'index.md'
            'projectbrief.md'
            'productContext.md'
            'activeContext.md'
            'techContext.md'
            'progress.md'
            'systemPatterns.md'
            'promptHistory.md'
        )) {
            $script:memoryBankSkillContent | Should -Match ([regex]::Escape($fileName))
        }

        @(Get-Content -LiteralPath $script:memoryBankSkillPath).Count |
            Should -BeLessOrEqual 500
    }

    It 'keeps the Memory Bank Skill discoverable within schema limits' {
        $skillLines = @(Get-Content -LiteralPath $script:memoryBankSkillPath)
        $closingDelimiter = [array]::IndexOf($skillLines, '---', 1)
        $frontmatter = $skillLines[1..($closingDelimiter - 1)]
        $descriptionStart = [array]::IndexOf($frontmatter, 'description: >-')
        $descriptionLines = $frontmatter[($descriptionStart + 1)..($frontmatter.Count - 1)]
        $description = ($descriptionLines | ForEach-Object { $_.Trim() }) -join ' '

        Split-Path -Leaf (Split-Path -Parent $script:memoryBankSkillPath) |
            Should -Be 'memory-bank'
        $description.Length | Should -BeLessOrEqual 1024
        $description | Should -Match '^Initializes, repairs, and checks'
        $description | Should -Match 'USE FOR:'
        $description | Should -Match 'DO NOT USE FOR:'
    }

    It 'keeps deployed Customizations independent of repository-only references' {
        $deployedFiles = Get-ChildItem -Path @(
            (Join-Path $script:repoRoot 'Agents')
            (Join-Path $script:repoRoot 'Instructions')
            (Join-Path $script:repoRoot 'Skills')
            (Join-Path $script:repoRoot 'Prompts')
        ) -Recurse -File

        $referenceMatches = @(
            $deployedFiles |
                Select-String -Pattern 'Reference/definition-of-done\.md'
        )
        $referenceMatches | Should -HaveCount 0
    }
}

Describe 'Custom agent lifecycle deduplication' {
    It 'preserves valid required frontmatter in every Custom agent' {
        foreach ($name in $script:agentBaseline.Keys) {
            $agentPath = Join-Path $script:agentsPath $name
            $lines = @(Get-Content -LiteralPath $agentPath)
            $delimiters = @(
                for ($index = 0; $index -lt $lines.Count; $index++) {
                    if ($lines[$index] -eq '---') {
                        $index
                    }
                }
            )

            $delimiters.Count | Should -BeGreaterOrEqual 2 -Because $name
            $delimiters[0] | Should -Be 0 -Because $name
            $frontmatter = $lines[1..($delimiters[1] - 1)] -join "`n"
            $frontmatter | Should -Match '(?m)^name:' -Because $name
            $frontmatter | Should -Match '(?m)^description:' -Because $name
            $frontmatter | Should -Match '(?m)^model:' -Because $name
            $frontmatter | Should -Match '(?m)^tools:' -Because $name
        }
    }

    It 'preserves tools, handoffs, and role-specific Memory Bank schemas' {
        foreach ($entry in $script:agentBaseline.GetEnumerator()) {
            $agentPath = Join-Path $script:agentsPath $entry.Key
            $content = Get-Content -LiteralPath $agentPath -Raw
            $toolsMatch = [regex]::Match($content, '(?m)^tools:\s*\[(.*)\]\r?$')
            $tools = @(
                [regex]::Matches($toolsMatch.Groups[1].Value, "'([^']+)'") |
                    ForEach-Object { $_.Groups[1].Value }
            )
            $handoffs = @(
                [regex]::Matches($content, '(?m)^\s{4}agent:\s+([^\s]+)\r?$') |
                    ForEach-Object { $_.Groups[1].Value }
            )

            $tools | Should -HaveCount $entry.Value.Tools -Because $entry.Key
            (Get-ShortHash -Value $tools) |
                Should -Be $entry.Value.ToolHash -Because $entry.Key
            $handoffs |
                Should -HaveCount $entry.Value.Handoffs -Because $entry.Key
            (Get-ShortHash -Value $handoffs) |
                Should -Be $entry.Value.HandoffHash -Because $entry.Key

            if ($entry.Value.MemoryHeading) {
                $memoryHeadingPattern = [regex]::Escape(
                    $entry.Value.MemoryHeading
                )
                $content |
                    Should -Match $memoryHeadingPattern -Because $entry.Key

                $agentLines = @(Get-Content -LiteralPath $agentPath)
                $memoryStart = -1
                for ($index = 0; $index -lt $agentLines.Count; $index++) {
                    if ($agentLines[$index] -eq $entry.Value.MemoryHeading) {
                        $memoryStart = $index
                        break
                    }
                }
                $memoryStart | Should -BeGreaterOrEqual 0 -Because $entry.Key
                $memoryEnd = $agentLines.Count - 1
                for ($index = $memoryStart + 1; $index -lt $agentLines.Count; $index++) {
                    if ($agentLines[$index] -match '^## ') {
                        $memoryEnd = $index - 1
                        break
                    }
                }
                $memorySection = $agentLines[$memoryStart..$memoryEnd] -join "`n"
                (Get-ShortHash -Value @($memorySection)) |
                    Should -Be $entry.Value.MemoryHash -Because $entry.Key
            }
        }
    }

    It 'uses the shared lifecycle without duplicate process sections' {
        foreach ($name in $script:agentBaseline.Keys) {
            $content = Get-Content -LiteralPath (Join-Path $script:agentsPath $name) -Raw

            $content |
                Should -Match '(?i)shared.*lifecycle Instructions' -Because $name
            $content | Should -Not -Match 'MANDATORY PRE-FLIGHT' -Because $name
            $content | Should -Not -Match 'MANDATORY POST-FLIGHT' -Because $name
            $content | Should -Not -Match '(?m)^## Tool Usage Pattern' -Because $name
            $content | Should -Not -Match '(?i)create it if missing' -Because $name
        }
    }

    It 'keeps native memory references aligned with least-privilege tools' {
        foreach ($name in $script:agentBaseline.Keys) {
            $content = Get-Content -LiteralPath (
                Join-Path $script:agentsPath $name
            ) -Raw
            if ($content -notmatch 'VS Code native memory') {
                continue
            }

            $content |
                Should -Match '(?s)does.{0,20}not include the `memory` tool' `
                -Because $name
            $content |
                Should -Match 'Memory Bank remains authoritative' -Because $name
            $content | Should -Not -Match "tools:.*'memory'" -Because $name
        }
    }
}
