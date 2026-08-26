BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $agentPath = Join-Path $repoRoot 'Agents/software-architect.agent.md'
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

Describe 'Software Architect Custom agent' {
    It 'keeps the agent body within its prompt budget' {
        $script:agentBodyLineCount | Should -BeLessOrEqual 220
    }

    It 'delegates shared lifecycle rules to the global Instructions' {
        $script:agentBody | Should -Match '(?i)shared lifecycle Instructions'
        $script:agentBody | Should -Not -Match '(?m)^## .*MANDATORY PRE-FLIGHT'
        $script:agentBody | Should -Not -Match '(?m)^## .*MANDATORY POST-FLIGHT'
    }

    It 'withholds every sanctioned code-validation path' {
        <#
            The agent is not prevented from typing code; it is prevented from
            closing the Definition of Done on a code change, which is what
            makes the implementation handoff the only productive exit. Any of
            these tools returning to the list silently removes that property.
        #>
        $script:agentTools | Select-Object -Unique |
            Should -HaveCount $script:agentTools.Count

        foreach ($tool in @(
            'runTests'
            'codeInterpreter'
            'execute/runTask'
            'execute/createAndRunTask'
            'execute/runNotebookCell'
        )) {
            $script:agentTools | Should -Not -Contain $tool
        }
    }

    It 'retains the tools the shared lifecycle requires' {
        <#
            Post-flight requires a Memory Bank update, a changelog entry, and a
            local commit on every Substantive turn, so stripping these two
            would make the agent violate its own lifecycle once per turn.
        #>
        $script:agentTools | Should -Contain 'edit/editFiles'
        $script:agentTools | Should -Contain 'execute/runInTerminal'
        $script:agentTools | Should -Contain 'vscode/askQuestions'
    }

    It 'hands implementation off instead of performing it' {
        $script:agentHandoffs | Should -Contain 'software-engineer'
        $script:agentBody | Should -Match 'never an implementation'
        $script:agentBody | Should -Match '(?i)sign-off'
    }

    It 'scales interview depth to blast radius' {
        $script:agentBody | Should -Match '(?m)^## Interview depth$'
        $script:agentBody | Should -Match 'grill-me'
        $script:agentBody | Should -Match 'gilb-requirements-engineering'
    }

    It 'retains the agentic-security gate' {
        $script:agentBody | Should -Match 'agent-security-review'
        $script:agentBody | Should -Match 'lethal trifecta'
    }
}
