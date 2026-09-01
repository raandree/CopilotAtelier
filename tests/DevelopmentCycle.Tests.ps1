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

    function script:Get-AgentHandoff
    {
        <#
            Returns one object per handoff entry across every agent, so the
            handoff graph can be walked as edges rather than grepped as text.
        #>
        [CmdletBinding()]
        [OutputType([psobject[]])]
        param ()

        return @(
            foreach ($file in Get-ChildItem -LiteralPath $script:agentsPath -Filter '*.agent.md' -File)
            {
                $line = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
                $delimiter = @(
                    for ($index = 0; $index -lt $line.Count; $index++)
                    {
                        if ($line[$index] -eq '---') { $index }
                    }
                )

                $source = [System.IO.Path]::GetFileNameWithoutExtension($file.BaseName)
                $entry = $null

                foreach ($current in $line[1..($delimiter[1] - 1)])
                {
                    if ($current -match '^\s{2}-\s+label:\s*(?<label>.+?)\s*$')
                    {
                        if ($entry) { $entry }

                        $entry = [pscustomobject]@{
                            Source = $source
                            Label  = $Matches.label
                            Target = $null
                            Send   = $false
                        }

                        continue
                    }

                    if (-not $entry) { continue }

                    if ($current -match '^\s{4}agent:\s*(?<agent>\S+)\s*$')
                    {
                        $entry.Target = $Matches.agent
                    }
                    elseif ($current -match '^\s{4}send:\s*(?<send>\S+)\s*$')
                    {
                        $entry.Send = $Matches.send -eq 'true'
                    }
                }

                if ($entry) { $entry }
            }
        )
    }

    function script:Find-HandoffCycle
    {
        <#
            Depth-first walk that reports every ring reachable in an edge map.
            Any ring built only from send: true edges runs without a human.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Node,

            [Parameter(Mandatory)]
            [hashtable]$Edge,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$Path = @()
        )

        if ($Path -contains $Node)
        {
            return @((@($Path[$Path.IndexOf($Node)..($Path.Count - 1)]) + $Node) -join ' -> ')
        }

        return @(
            foreach ($next in @($Edge[$Node] | Where-Object { $_ }))
            {
                script:Find-HandoffCycle -Node $next -Edge $Edge -Path (@($Path) + $Node)
            }
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

    It 'breaks the review-fail loop at the frontmatter instead of promising a cap' {
        <#
            A prose cap ("stop after two rounds") is unenforceable: each handoff
            starts the receiving agent with fresh context, so neither side can
            count rounds. Two mutually auto-submitting handoffs plus that cap
            produced a session that never terminated. The bound is the missing
            send: true on the way back.
        #>
        $body = script:Get-AgentBody -Name 'security-reviewer.agent.md'
        $fixLeg = script:Get-AgentHandoff |
            Where-Object { $_.Source -eq 'security-reviewer' -and $_.Label -eq 'Fix Issues Found' }

        $fixLeg | Should -HaveCount 1
        $fixLeg.Target | Should -Be 'software-engineer'
        $fixLeg.Send | Should -BeFalse

        $body | Should -Match '(?i)fix (loop|round)'
        $body | Should -Match '(?i)does \*\*not\*\* auto-submit'
        $body | Should -Not -Match '(?i)after two rounds'

        script:Get-AgentBody -Name 'software-engineer.agent.md' |
            Should -Not -Match '(?i)after two rounds'
    }

    It 'leaves no cycle in the handoff graph that can close unattended' {
        <#
            The failure this guards is structural, not local: any ring of
            send: true edges runs without a human, and no agent body can see
            the ring it is part of.
        #>
        $edge = @{}
        foreach ($handoff in script:Get-AgentHandoff | Where-Object { $_.Send -and $_.Target })
        {
            $edge[$handoff.Source] = @($edge[$handoff.Source]) + $handoff.Target
        }

        # A detector that never detects would pass this test silently.
        script:Find-HandoffCycle -Node 'a' -Edge @{ a = 'b'; b = 'a' } |
            Should -Not -BeNullOrEmpty

        $found = @(
            foreach ($source in $edge.Keys)
            {
                script:Find-HandoffCycle -Node $source -Edge $edge
            }
        )

        $found | Should -BeNullOrEmpty -Because "every edge in these rings auto-submits: $($found -join '; ')"
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

    It 'auto-submits every forward handoff in the cycle' {
        <#
            send: false populates the box and waits for a second confirmation.
            Progressing through the cycle must not ask again — the user
            consented at the entry point. Only the fail path back into
            implementation is gated, because that edge closes a ring.
        #>
        $cycleHandoff = @(
            @{ Agent = 'software-architect.agent.md'; Label = 'Implement the Design Concept' }
            @{ Agent = 'software-engineer.agent.md'; Label = 'Run Security Review' }
            @{ Agent = 'security-reviewer.agent.md'; Label = 'Document the Change' }
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
