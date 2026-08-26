BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $agentPath = Join-Path $repoRoot 'Agents/software-engineer.agent.md'
    $script:agentContent = Get-Content -LiteralPath $agentPath -Raw

    $agentLines = @(Get-Content -LiteralPath $agentPath)
    $frontmatterDelimiters = @(
        for ($index = 0; $index -lt $agentLines.Count; $index++) {
            if ($agentLines[$index] -eq '---') {
                $index
            }
        }
    )
    $bodyStart = $frontmatterDelimiters[1] + 1
    $script:agentBody = $agentLines[$bodyStart..($agentLines.Count - 1)] -join "`n"
    $script:agentBodyLineCount = $agentLines.Count - $bodyStart

    $toolsLine = [regex]::Match($script:agentContent, '(?m)^tools:\s*\[(.*)\]\r?$')
    $script:agentTools = @(
        [regex]::Matches($toolsLine.Groups[1].Value, "'([^']+)'") |
            ForEach-Object { $_.Groups[1].Value }
    )
    $script:agentHandoffs = @(
        [regex]::Matches($script:agentContent, '(?m)^\s{4}agent:\s+([^\s]+)\r?$') |
            ForEach-Object { $_.Groups[1].Value }
    )
}

Describe 'Software Engineer Custom agent' {
    It 'keeps the agent body within its prompt budget' {
        $script:agentBodyLineCount | Should -BeLessOrEqual 220
    }

    It 'delegates shared lifecycle rules to the global Instructions' {
        $script:agentBody | Should -Not -Match '(?m)^## .*MANDATORY PRE-FLIGHT'
        $script:agentBody | Should -Not -Match '(?m)^## .*MANDATORY POST-FLIGHT'
        $script:agentBody | Should -Not -Match '(?m)^## Tool Usage Pattern'
    }

    It 'preserves the complete tool and handoff surface' {
        $script:agentTools | Should -HaveCount 45
        $script:agentTools | Select-Object -Unique | Should -HaveCount 45
        $script:agentTools | Should -Contain 'agent'
        $script:agentTools | Should -Contain 'edit/createFile'
        $script:agentTools | Should -Contain 'execute/runInTerminal'
        $script:agentTools | Should -Contain 'runTests'
        $script:agentTools | Should -Contain 'thinking'
        $script:agentHandoffs | Should -HaveCount 3
        $script:agentHandoffs | Should -Contain 'security-reviewer'
        $script:agentHandoffs | Should -Contain 'technical-writer'
        $script:agentHandoffs | Should -Contain 'software-architect'
    }

    It 'requires immediate focused executable validation and final validation' {
        $script:agentBody | Should -Match 'focused executable validation'
        $script:agentBody | Should -Match '(?s)Validate immediately.*focused executable validation'
        $script:agentBody | Should -Match 'final validation'
    }

    It 'keeps behavior changes and bug fixes test-first' {
        $script:agentBody | Should -Match 'test-first'
        $script:agentBody | Should -Match 'bug fix'
        $script:agentBody | Should -Match 'regression'
    }

    It 'scales independent review to risk without skipping self-review' {
        $script:agentBody | Should -Match 'self-review'
        $script:agentBody | Should -Match '(?s)independent review.*high-risk work'
    }

    It 'retains the agentic-security gate' {
        $script:agentBody | Should -Match 'agent-security-review'
        $script:agentBody | Should -Match 'lethal trifecta'
    }

    It 'retains the no-push boundary' {
        $script:agentContent | Should -Match '(?i)never push'
    }
}
