$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:skillRoot = Join-Path $script:repoRoot 'Skills'

# Skills whose body already exceeds the 500-line progressive-disclosure budget.
# The list may shrink as bodies are split into references; it must never grow.
$script:oversizedBodyBaseline = @(
    'dsc-troubleshooting'
    'german-legal-research'
    'marp-slide-overflow'
    'mecm-dsc-deployment'
    'outlook-email-export'
    'pandoc-docx-export'
    'pdf-to-markdown'
    'pester-patterns'
    'sampler-migration'
    'whisper-pyannote-transcription'
)

# Built during discovery so -ForEach expands. Building it in BeforeAll would
# silently generate zero test cases, and a discovery-scope variable read inside
# an It block is null at run time, so every flag travels as case data.
$script:skillCase = @(
    Get-ChildItem -LiteralPath $script:skillRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        ForEach-Object {
            @{
                SkillName = $_.Name
                SkillPath = Join-Path $_.FullName 'SKILL.md'
                IsOversizedBaseline = ($_.Name -in $script:oversizedBodyBaseline)
            }
        }
)

# Skills whose shipped scripts import a module the consumer has to install.
# The hand-maintained list below catches environment-bound Skills a human
# noticed; this one catches the dependency a script acquired without anyone
# updating the frontmatter, which is how agent-evals shipped undeclared.
$script:moduleImportingSkillCase = @(
    Get-ChildItem -LiteralPath $script:skillRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        Where-Object {
            $scriptRoot = Join-Path $_.FullName 'scripts'

            (Test-Path -LiteralPath $scriptRoot -PathType Container) -and
            @(
                Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter '*.ps1' |
                    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^\s*Import-Module\s+\S' }
            ).Count -gt 0
        } |
        ForEach-Object {
            @{
                SkillName = $_.Name
                SkillPath = Join-Path $_.FullName 'SKILL.md'
            }
        }
)

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skillRoot = Join-Path $script:repoRoot 'Skills'

    # Minimal frontmatter reader: the repository has no YAML module dependency,
    # and SKILL.md frontmatter is a flat map with optional block scalars.
    function script:Get-SkillFrontmatter {
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $lines = Get-Content -LiteralPath $Path
        $delimiter = @(
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -eq '---') { $index }
            }
        )

        if ($delimiter.Count -lt 2) {
            throw "Missing frontmatter delimiters: $Path"
        }

        $frontmatter = @{}
        $currentKey = $null

        foreach ($line in $lines[($delimiter[0] + 1)..($delimiter[1] - 1)]) {
            if ($line -match '^(?<key>[A-Za-z][A-Za-z0-9-]*):\s*(?<value>.*)$') {
                $currentKey = $Matches.key
                $value = $Matches.value.Trim()
                $frontmatter[$currentKey] = if ($value -in @('>-', '>', '|', '|-')) { '' } else { $value.Trim("'", '"') }
                continue
            }

            if ($currentKey -and $line -match '^\s+\S') {
                $frontmatter[$currentKey] = ($frontmatter[$currentKey] + ' ' + $line.Trim()).Trim()
            }
        }

        $frontmatter['__bodyLineCount'] = $lines.Count - ($delimiter[1] + 1)
        return $frontmatter
    }
}

Describe 'Skill frontmatter' -Tag 'Unit' {
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

    It '<SkillName> declares a spec-compliant name' -ForEach $script:skillCase {
        $frontmatter = script:Get-SkillFrontmatter -Path $SkillPath

        $frontmatter['name'] | Should -Be $SkillName -Because 'the name must match the parent directory'
        $frontmatter['name'] | Should -Match '^[a-z0-9]+(-[a-z0-9]+)*$'
        $frontmatter['name'].Length | Should -BeLessOrEqual 64
    }

    It '<SkillName> declares a description within the 1024-character cap' -ForEach $script:skillCase {
        $frontmatter = script:Get-SkillFrontmatter -Path $SkillPath

        $frontmatter['description'] | Should -Not -BeNullOrEmpty
        $frontmatter['description'].Length | Should -BeLessOrEqual 1024
    }

    It '<SkillName> keeps the body within the 500-line budget' -ForEach $script:skillCase {
        if ($IsOversizedBaseline) {
            Set-ItResult -Skipped -Because 'the body is over budget in the documented baseline'
            return
        }

        $frontmatter = script:Get-SkillFrontmatter -Path $SkillPath
        $frontmatter['__bodyLineCount'] | Should -BeLessOrEqual 500
    }

    It '<SkillName> is still over the body budget and must stay on the baseline' -ForEach @(
        $script:oversizedBodyBaseline | ForEach-Object { @{ SkillName = $_ } }
    ) {
        $skillPath = Join-Path (Join-Path $script:skillRoot $SkillName) 'SKILL.md'
        $frontmatter = script:Get-SkillFrontmatter -Path $skillPath

        $frontmatter['__bodyLineCount'] |
            Should -BeGreaterThan 500 -Because 'a Skill trimmed under budget must be removed from the baseline'
    }

    It '<SkillName> uses only supported optional fields' -ForEach $script:skillCase {
        $frontmatter = script:Get-SkillFrontmatter -Path $SkillPath

        if ($frontmatter.ContainsKey('compatibility')) {
            $frontmatter['compatibility'] | Should -Not -BeNullOrEmpty
            $frontmatter['compatibility'].Length | Should -BeLessOrEqual 500
        }

        if ($frontmatter.ContainsKey('context')) {
            $frontmatter['context'] | Should -BeIn @('fork', 'inline')
        }
    }
}

Describe 'Skill environment declarations' -Tag 'Unit' {
    It '<SkillName> declares compatibility because it is environment-bound' -ForEach @(
        @{ SkillName = 'automatedlab-deployment' }
        @{ SkillName = 'automatedlab-proxmox' }
        @{ SkillName = 'create-outlook-draft' }
        @{ SkillName = 'dsc-troubleshooting' }
        @{ SkillName = 'mecm-dsc-deployment' }
        @{ SkillName = 'outlook-calendar-export' }
        @{ SkillName = 'outlook-email-export' }
        @{ SkillName = 'send-outlook-email' }
        @{ SkillName = 'whisper-pyannote-transcription' }
        @{ SkillName = 'windows-gui-screenshot-capture' }
        @{ SkillName = 'winrm-troubleshooting' }
    ) {
        $skillPath = Join-Path (Join-Path $script:skillRoot $SkillName) 'SKILL.md'
        $frontmatter = script:Get-SkillFrontmatter -Path $skillPath

        $frontmatter['compatibility'] |
            Should -Not -BeNullOrEmpty -Because 'a Windows-only or toolchain-bound Skill must say so'
    }

    It 'discovers the Skills whose scripts import a module' -ForEach @(
        @{ DiscoveredCount = $script:moduleImportingSkillCase.Count }
    ) {
        $DiscoveredCount |
            Should -BeGreaterThan 0 -Because 'a silently empty discovery would make the rule below vacuous'
    }

    It '<SkillName> declares compatibility because a shipped script imports a module' -ForEach $script:moduleImportingSkillCase {
        $frontmatter = script:Get-SkillFrontmatter -Path $SkillPath

        $frontmatter['compatibility'] |
            Should -Not -BeNullOrEmpty -Because 'the consumer must install that module before the script runs'
    }
}
