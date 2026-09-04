$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:agentsPath = Join-Path $script:repoRoot 'com.github.copilot/agents'
$script:agentFiles = @(
    Get-ChildItem -LiteralPath $script:agentsPath -File -Filter '*.agent.md'
)

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:agentsPath = Join-Path $script:repoRoot 'com.github.copilot/agents'
    $script:agentFiles = @(
        Get-ChildItem -LiteralPath $script:agentsPath -File -Filter '*.agent.md'
    )

    function script:Get-AgentFrontmatterLine
    {
        [CmdletBinding()]
        [OutputType([string[]])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $line = @(Get-Content -LiteralPath $Path -Encoding UTF8)
        $delimiter = @(
            for ($index = 0; $index -lt $line.Count; $index++)
            {
                if ($line[$index] -eq '---') { $index }
            }
        )

        if ($delimiter.Count -lt 2)
        {
            throw "Missing frontmatter delimiters: $Path"
        }

        return $line[($delimiter[0] + 1)..($delimiter[1] - 1)]
    }

    function script:Get-AgentInlineSequence
    {
        [CmdletBinding()]
        [OutputType([string[]])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )

        $frontmatter = script:Get-AgentFrontmatterLine -Path $Path
        $property = $frontmatter |
            Where-Object { $_ -match "^$([regex]::Escape($Name)):\s*\[" } |
            Select-Object -First 1

        if (-not $property)
        {
            return @()
        }

        return @(
            [regex]::Matches($property, "'([^']+)'") |
                ForEach-Object { $_.Groups[1].Value }
        )
    }

    function script:Get-AgentHandoff
    {
        [CmdletBinding()]
        [OutputType([psobject[]])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $frontmatter = script:Get-AgentFrontmatterLine -Path $Path
        $entry = $null

        return @(
            foreach ($currentLine in $frontmatter)
            {
                if ($currentLine -match '^\s{2}-\s+label:\s*(?<label>.+?)\s*$')
                {
                    if ($entry) { $entry }

                    $entry = [pscustomobject]@{
                        Label  = $Matches.label.Trim("'", '"')
                        Agent  = $null
                        Prompt = $null
                    }

                    continue
                }

                if (-not $entry) { continue }

                if ($currentLine -match '^\s{4}agent:\s*(?<agent>\S+)\s*$')
                {
                    $entry.Agent = $Matches.agent.Trim("'", '"')
                }
                elseif ($currentLine -match '^\s{4}prompt:\s*(?<prompt>.+?)\s*$')
                {
                    $entry.Prompt = $Matches.prompt.Trim("'", '"')
                }
            }

            if ($entry) { $entry }
        )
    }

    function script:Get-AgentBody
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $line = @(Get-Content -LiteralPath $Path -Encoding UTF8)
        $delimiter = @(
            for ($index = 0; $index -lt $line.Count; $index++)
            {
                if ($line[$index] -eq '---') { $index }
            }
        )

        return $line[($delimiter[1] + 1)..($line.Count - 1)] -join "`n"
    }
}

Describe 'Custom agent semantic contracts' -Tag 'Unit' {
    It 'requires every handoff to target an existing Custom agent' {
        $agentName = @(
            $script:agentFiles |
                ForEach-Object { $_.BaseName -replace '\.agent$', '' }
        )

        foreach ($file in $script:agentFiles)
        {
            foreach ($handoff in script:Get-AgentHandoff -Path $file.FullName)
            {
                $handoff.Agent |
                    Should -Not -BeNullOrEmpty -Because "$($file.Name): $($handoff.Label)"
                $agentName |
                    Should -Contain $handoff.Agent -Because "$($file.Name): $($handoff.Label)"
            }
        }
    }

    It 'gives agents that require delegation an allow-list and the agent tool' {
        foreach ($name in @('security-reviewer', 'technical-writer'))
        {
            $path = Join-Path $script:agentsPath "$name.agent.md"
            $tools = script:Get-AgentInlineSequence -Path $path -Name 'tools'
            $agent = script:Get-AgentInlineSequence -Path $path -Name 'agents'

            $tools | Should -Contain 'agent' -Because $name
            $agent | Should -Contain 'research-analyst' -Because $name
        }
    }

    It 'composes DevOps training through delegation rather than fictitious inheritance' {
        $path = Join-Path $script:agentsPath 'devops-training-writer.agent.md'
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8

        $content | Should -Not -Match '(?i)\binherit(?:s|ed|ance)?\b'
        $content | Should -Match '(?is)delegate.*training-writer'
    }

    It 'keeps role-specific case and career records in separate namespaces' {
        $role = @{
            'career-coach'    = 'career'
            'legal-researcher' = 'legal'
            'tax-researcher'   = 'tax'
        }

        foreach ($entry in $role.GetEnumerator())
        {
            $path = Join-Path $script:agentsPath "$($entry.Key).agent.md"
            $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            $sharedPath = '\.memory-bank/(deadlines|session-log|documents-produced)\.md'

            $content | Should -Not -Match $sharedPath -Because $entry.Key
            $content |
                Should -Match "\.memory-bank/$($entry.Value)/" -Because $entry.Key
        }
    }

    It 'detects and resolves legacy role records before creating replacements' {
        foreach ($name in @(
            'career-coach'
            'legal-researcher'
            'tax-researcher'
        ))
        {
            $path = Join-Path $script:agentsPath "$name.agent.md"
            $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8

            $content | Should -Match '(?i)before creating.*legacy' -Because $name
            $content | Should -Match '`memory-bank`' -Because $name
            $content | Should -Match '#tool:vscode/askQuestions' -Because $name
            $content | Should -Match '`-WhatIf`' -Because $name
            $content | Should -Match '(?i)explicit confirmation' -Because $name
            $content |
                Should -Match '(?is)never move,\s+delete,\s+or split.*silently' -Because $name
        }
    }

    It 'does not expose the retired preview-only browser tool' {
        foreach ($file in $script:agentFiles)
        {
            Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 |
                Should -Not -Match "'openSimpleBrowser'" -Because $file.Name
        }
    }

    It 'preserves browser capability only for agents that own web journeys' {
        $browserAgent = @(
            'career-coach'
            'devops-training-writer'
            'legal-researcher'
            'qc-inspector'
            'research-analyst'
            'security-reviewer'
            'software-architect'
            'software-engineer'
            'tax-researcher'
            'technical-writer'
            'training-writer'
            'troubleshooter'
        )

        foreach ($file in $script:agentFiles)
        {
            $name = $file.BaseName -replace '\.agent$', ''
            $tools = script:Get-AgentInlineSequence -Path $file.FullName -Name 'tools'

            if ($name -in $browserAgent)
            {
                $tools | Should -Contain 'browser' -Because $name
            }
            else
            {
                $tools | Should -Not -Contain 'browser' -Because $name
            }
        }
    }

    It 'documents that Custom agent capabilities vary across Copilot clients' {
        $readmePath = Join-Path $script:repoRoot 'README.md'
        $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8

        $readme | Should -Match '(?i)capabilit(?:y|ies).*vary.*client'
        $readme | Should -Match '(?i)product-specific tool'
        $readme | Should -Match '(?i)model priority'
    }

    It 'keeps the agent catalogue aligned with composition and role namespaces' {
        $catalogPath = Join-Path $script:agentsPath 'README.md'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8
        $devops = [regex]::Match(
            $catalog,
            '(?s)### 11\. DevOps Training Writer Agent(?<section>.*?)(?=\r?\n---\r?\n\r?\n### 12\.)'
        ).Groups['section'].Value
        $career = [regex]::Match(
            $catalog,
            '(?s)### 10\. Career Coach Agent(?<section>.*?)(?=\r?\n---\r?\n\r?\n### 11\.)'
        ).Groups['section'].Value

        $devops | Should -Not -BeNullOrEmpty
        $devops | Should -Not -Match '(?i)\binherit(?:s|ed|ance)?\b'
        $devops | Should -Match '(?is)delegat.*training-writer'
        $career | Should -Not -BeNullOrEmpty
        $career | Should -Match '\.memory-bank/career/'
    }
}

Describe 'Custom agent prompt budgets' -Tag 'Unit' {
    BeforeAll {
        $script:oversizedAgentBaseline = @{
            'career-coach.agent.md'     = 35728
            'research-analyst.agent.md' = 43376
            'security-reviewer.agent.md' = 43772
            'technical-writer.agent.md' = 35018
        }
    }

    It '<Name> stays within the cross-client prompt limit or its shrink-only baseline' -ForEach @(
        $script:agentFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $bodyLength = (script:Get-AgentBody -Path $Path).Length

        if ($script:oversizedAgentBaseline.ContainsKey($Name))
        {
            $bodyLength |
                Should -BeLessOrEqual $script:oversizedAgentBaseline[$Name] `
                -Because 'an oversized agent must not grow before its dedicated refactor'
        }
        else
        {
            $bodyLength |
                Should -BeLessOrEqual 30000 -Because 'GitHub limits a Custom agent prompt to 30,000 characters'
        }
    }
}