BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:agentsPath = Join-Path $script:repoRoot 'com.github.copilot/agents'
    $script:postflightPath = Join-Path $script:repoRoot 'com.github.copilot/rules/postflight.instructions.md'

    function script:Get-AgentBody
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )

        $line = @(
            Get-Content -LiteralPath (Join-Path $script:agentsPath $Name) -Encoding UTF8
        )
        $delimiter = @(
            for ($index = 0; $index -lt $line.Count; $index++)
            {
                if ($line[$index] -eq '---') { $index }
            }
        )

        return ($line[($delimiter[1] + 1)..($line.Count - 1)] -join "`n")
    }

    function script:Get-AgentHandoffTarget
    {
        [CmdletBinding()]
        [OutputType([string[]])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )

        $content = Get-Content -LiteralPath (Join-Path $script:agentsPath $Name) -Raw -Encoding UTF8

        return @(
            [regex]::Matches($content, '(?m)^\s{4}agent:\s+(\S+)\r?$') |
                ForEach-Object { $_.Groups[1].Value }
        )
    }

    $script:postflightContent = Get-Content -LiteralPath $script:postflightPath -Raw -Encoding UTF8
}

Describe 'Development cycle' -Tag 'Unit' {
    $script:stageCase = @(
        @{ Agent = 'software-architect.agent.md'; Stage = 'stage 1' }
        @{ Agent = 'software-engineer.agent.md'; Stage = 'stage 2' }
        @{ Agent = 'security-reviewer.agent.md'; Stage = 'stage 3' }
        @{ Agent = 'technical-writer.agent.md'; Stage = 'final stage' }
    )

    It '<Agent> declares its place in the cycle as <Stage>' -ForEach $script:stageCase {
        $body = script:Get-AgentBody -Name $Agent

        $body | Should -Match '(?m)^## Development cycle$'
        $body | Should -Match ([regex]::Escape($Stage))
    }

    It '<Agent> keeps the cycle opt-in rather than automatic' -ForEach $script:stageCase {
        <#
            The cycle is expensive: four agents, four contexts. It may only run
            because the user asked for it, never because the work looked like it
            deserved one.
        #>
        script:Get-AgentBody -Name $Agent | Should -Match 'cycle: full'
    }

    It 'wires the four stages as a connected handoff chain' {
        script:Get-AgentHandoffTarget -Name 'software-architect.agent.md' |
            Should -Contain 'software-engineer'
        script:Get-AgentHandoffTarget -Name 'software-engineer.agent.md' |
            Should -Contain 'security-reviewer'
        script:Get-AgentHandoffTarget -Name 'security-reviewer.agent.md' |
            Should -Contain 'technical-writer'
    }

    It 'bounds the review-fail loop instead of letting it ping-pong' {
        $body = script:Get-AgentBody -Name 'security-reviewer.agent.md'

        $body | Should -Match '(?i)two rounds'
        $body | Should -Match '(?i)fix round'
        script:Get-AgentHandoffTarget -Name 'security-reviewer.agent.md' |
            Should -Contain 'software-engineer'
    }

    It 'names exactly one close-out owner across the four stages' {
        $deferring = @(
            'software-architect.agent.md'
            'software-engineer.agent.md'
            'security-reviewer.agent.md'
        )

        foreach ($agent in $deferring)
        {
            script:Get-AgentBody -Name $agent |
                Should -Match '(?i)do not close out' -Because $agent
        }

        script:Get-AgentBody -Name 'technical-writer.agent.md' |
            Should -Match '(?i)close out the (whole )?cycle'
    }

    It 'lets the shared Post-flight gate defer close-out to the final stage' {
        $script:postflightContent | Should -Match '(?i)development cycle'
        $script:postflightContent | Should -Match '(?i)final stage'
    }

    It 'recognizes more than one way to ask for the cycle' {
        <#
            "cycle: full" is the canonical switch, but nobody speaks in
            switches. The entry-point agent carries the phrase book.
        #>
        $body = script:Get-AgentBody -Name 'software-architect.agent.md'

        foreach ($phrase in @(
            'full development cycle'
            'full workflow'
            'development cycle'
            'full SDLC'
            'full pipeline'
        ))
        {
            $body | Should -Match ([regex]::Escape($phrase)) -Because $phrase
        }
    }

    It 'refuses the ambiguous phrases that would start a cycle by accident' {
        $body = script:Get-AgentBody -Name 'software-architect.agent.md'

        $body | Should -Match '(?i)do not start (a |the )?cycle'
        $body | Should -Match 'end-to-end'
    }

    It 'auto-submits every cycle-carrying handoff' {
        <#
            send: false populates the box and waits for a second confirmation.
            Inside a cycle the user already consented at the entry point, so the
            transition must not ask again.
        #>
        $cycleHandoff = @(
            @{ Agent = 'software-architect.agent.md'; Label = 'Implement the Design Concept' }
            @{ Agent = 'software-engineer.agent.md'; Label = 'Run Security Review' }
            @{ Agent = 'security-reviewer.agent.md'; Label = 'Document the Change' }
            @{ Agent = 'security-reviewer.agent.md'; Label = 'Fix Issues Found' }
        )

        foreach ($entry in $cycleHandoff)
        {
            $content = Get-Content -LiteralPath (
                Join-Path $script:agentsPath $entry.Agent
            ) -Raw -Encoding UTF8

            $pattern = '(?s)label:\s*{0}.*?send:\s*true' -f [regex]::Escape($entry.Label)
            $content |
                Should -Match $pattern -Because "$($entry.Agent): $($entry.Label)"
        }
    }

    It 'takes the next stage without asking once the cycle is running' {
        foreach ($agent in @(
            'software-architect.agent.md'
            'software-engineer.agent.md'
            'security-reviewer.agent.md'
        ))
        {
            script:Get-AgentBody -Name $agent |
                Should -Match '(?i)without asking' -Because $agent
        }
    }

    It 'routes a cycle requested mid-chain back to the architect' {
        script:Get-AgentBody -Name 'software-engineer.agent.md' |
            Should -Match '(?i)hand back to `software-architect`'
    }

    It 'gives every stage an escape hatch out of a running cycle' {
        <#
            Without a documented way out, the only exit from a four-stage chain
            is abandoning the conversation, which strands the close-out.
        #>
        foreach ($agent in @(
            'software-architect.agent.md'
            'software-engineer.agent.md'
            'security-reviewer.agent.md'
            'technical-writer.agent.md'
        ))
        {
            script:Get-AgentBody -Name $agent |
                Should -Match 'cycle: off' -Because $agent
        }
    }

    It 'documents both the cycle and the single-agent default for users' {
        $readme = Get-Content -LiteralPath (
            Join-Path $script:agentsPath 'README.md'
        ) -Raw -Encoding UTF8

        $readme | Should -Match 'cycle: full'
        $readme | Should -Match 'cycle: off'
        $readme | Should -Match 'review: on'
        $readme | Should -Match 'review: auto'
        $readme | Should -Match '(?i)one agent only'
    }
}
