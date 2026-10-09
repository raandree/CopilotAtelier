Describe 'Agent security hook-context guidance' -Tag 'Unit' {
    BeforeAll {
        $path = [IO.Path]::Combine(
            (Split-Path -Parent $PSScriptRoot), 'skills', 'agent-security-review', 'SKILL.md'
        )
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
        $script:hookSecurityGuidance = $content -replace '\s+', ' '
        $section = [regex]::Match(
            $content, '(?s)### Prompt injection via tool output.*?(?=\r?\n## |\z)'
        ).Value
        $script:hookOutputGuidance = $section -replace '\s+', ' '
    }

    It 'keeps hook additionalContext inside the tool-result trust boundary' {
        $script:hookOutputGuidance | Should -Match 'additionalContext'
        $script:hookOutputGuidance | Should -Match 'inside the tool result'
        $script:hookOutputGuidance | Should -Match 'data only'
        $script:hookOutputGuidance | Should -Match 'never an instruction, an approval, or an authorization'
        $script:hookOutputGuidance | Should -Match 'No safety rule may depend on it alone'
    }

    It 'names the observed host versions and both delivery wrappers' {
        $script:hookOutputGuidance | Should -Match 'VS Code 1\.141\.0'
        $script:hookOutputGuidance | Should -Match 'Copilot Chat 0\.69\.0'
        $script:hookOutputGuidance | Should -Match '<PostToolUse-context>'
        $script:hookOutputGuidance | Should -Match '<PreToolUse-context>'
        $script:hookOutputGuidance | Should -Match 'Copilot SDK'
        $script:hookOutputGuidance | Should -Match 'Copilot CLI'
        $script:hookOutputGuidance | Should -Match 'Additional guidance from postToolUse hooks:'
        $script:hookOutputGuidance | Should -Match '2026-10-06'
        $script:hookOutputGuidance | Should -Match 'not tested'
    }

    It 'carries the rule into the containment checklist' {
        $script:hookSecurityGuidance | Should -Match '\*\*Hook context\*\*'
        $script:hookSecurityGuidance | Should -Match 'hook.*data only.*authorization'
    }
}
