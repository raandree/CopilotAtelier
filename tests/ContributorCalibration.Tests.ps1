BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    function script:Get-RepositoryText
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$RelativePath
        )

        $path = Join-Path -Path $script:repoRoot -ChildPath $RelativePath

        if (-not (Test-Path -LiteralPath $path -PathType Leaf))
        {
            throw "Missing file: $RelativePath"
        }

        return Get-Content -LiteralPath $path -Raw -Encoding UTF8
    }
}

Describe 'Contributor calibration Instruction' -Tag 'Unit' {
    BeforeAll {
        $relativePath = 'com.github.copilot/rules/contributor-calibration.instructions.md'
        $script:instruction = Get-RepositoryText -RelativePath $relativePath
        $script:instructionLineCount = @(
            Get-Content -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath $relativePath)
        ).Count
    }

    It 'applies to every chat turn' {
        $script:instruction | Should -Match '(?m)^applyTo: "\*\*"\r?$'
    }

    It 'stays within a compact prompt budget' {
        # It loads on every turn next to Pre-flight and Post-flight.
        $script:instructionLineCount | Should -BeLessOrEqual 60
        $script:instruction.Length | Should -BeLessOrEqual 4096
    }

    It 'defines the three familiarity levels and defaults to familiar' {
        $script:instruction | Should -Match '\| `new` \|'
        $script:instruction | Should -Match '\| `familiar` \|'
        $script:instruction | Should -Match '\| `expert` \|'
        $script:instruction | Should -Match '(?i)default to `familiar`'
    }

    It 'gives every decision question a recommended answer and a delegation option' {
        $script:instruction | Should -Match '(?i)recommended answer'
        $script:instruction | Should -Match '`not sure, you pick`'
    }

    It 'records a delegated answer as a flagged assumption, never a silent one' {
        $script:instruction | Should -Match '(?i)explicit assumption flagged for expert review'
        $script:instruction | Should -Match '(?i)never let it become a silent assumption'
    }

    It 'keeps the precise term visible at every level' {
        $script:instruction | Should -Match '(?i)always show the precise term'
    }

    It 'keeps familiarity levels out of every repository file' {
        $script:instruction | Should -Match '(?i)never write a familiarity level'
    }

    It 'never lets a familiarity level weaken safety' {
        $script:instruction | Should -Match '(?i)never safety'
        $script:instruction | Should -Match '(?i)keep every warning, validation step, test, and review'
        $script:instruction | Should -Match '(?i)expert check'
    }

    It 'calibrates the chat, not the artifacts' {
        $script:instruction | Should -Match '(?i)calibrate the chat only'
    }
}

Describe 'Explanation depth Prompts' -Tag 'Unit' {
    It '<Name> moves one familiarity level and keeps it for the session' -ForEach @(
        @{
            Name         = 'simpler'
            RelativePath = 'com.github.copilot/commands/simpler.prompt.md'
            FirstStep    = 'from `expert` to `familiar`'
            SecondStep   = 'from `familiar` to `new`'
        }
        @{
            Name         = 'deeper'
            RelativePath = 'com.github.copilot/commands/deeper.prompt.md'
            FirstStep    = 'from `new` to `familiar`'
            SecondStep   = 'from `familiar` to `expert`'
        }
    ) {
        $prompt = Get-RepositoryText -RelativePath $RelativePath

        $prompt | Should -Match ([regex]::Escape($FirstStep))
        $prompt | Should -Match ([regex]::Escape($SecondStep))
        $prompt | Should -Match '`contributor-calibration` Instruction'
        $prompt | Should -Match '(?i)rest of the session'
        $prompt | Should -Match '(?i)change no files'
    }

    It 'simpler simplifies the language without dropping content' {
        Get-RepositoryText -RelativePath 'com.github.copilot/commands/simpler.prompt.md' |
            Should -Match '(?i)keep every fact, caveat, warning, and open question'
    }

    It 'deeper adds the authoritative source' {
        Get-RepositoryText -RelativePath 'com.github.copilot/commands/deeper.prompt.md' |
            Should -Match '(?i)authoritative source'
    }
}

Describe 'Delegated answers in question-heavy Customizations' -Tag 'Unit' {
    It '<RelativePath> records a not-sure answer as a flagged assumption' -ForEach @(
        @{ RelativePath = 'skills/grill-me/SKILL.md' }
        @{ RelativePath = 'com.github.copilot/agents/software-architect.agent.md' }
        @{ RelativePath = 'skills/gilb-requirements-engineering/SKILL.md' }
    ) {
        $content = Get-RepositoryText -RelativePath $RelativePath

        $content | Should -Match '`not sure, you pick`'
        $content | Should -Match '(?i)flagged for expert review'
    }
}

Describe 'Familiarity levels stay out of the Memory Bank' -Tag 'Unit' {
    It 'the memory-bank Skill never records a familiarity level' {
        Get-RepositoryText -RelativePath 'skills/memory-bank/SKILL.md' |
            Should -Match '(?i)never record a contributor''s familiarity levels'
    }

    It 'the Glossary defines <Term> as a Canonical term' -ForEach @(
        @{ Term = 'Knowledge area' }
        @{ Term = 'Familiarity level' }
    ) {
        Get-RepositoryText -RelativePath '.memory-bank/glossary.md' |
            Should -Match ('(?m)^\| {0} \|' -f [regex]::Escape($Term))
    }
}
