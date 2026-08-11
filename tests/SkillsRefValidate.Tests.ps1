$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:skillRoot = Join-Path $script:repoRoot 'Skills'

# The upstream reference validator is a Python package. It is fetched on demand
# by `uv` rather than vendored, so the gate reports a clearly-visible skip when
# `uv` is absent instead of silently passing.
$script:uvCommand = Get-Command -Name 'uv' -CommandType Application -ErrorAction SilentlyContinue
$script:hasUv = $null -ne $script:uvCommand

# Skills that fail the reference validator today. `context: fork` is a real
# GitHub Copilot feature that the open specification does not define, so these
# are a deliberate divergence rather than a defect. The list may shrink; it must
# never grow without a recorded decision.
$script:knownDivergenceBaseline = @(
    'citation-integrity'
    'social-signal-sweep'
)

# Discovery-scope case data so -ForEach expands one It per skill; a failure then
# names the offending skill instead of collapsing 44 results into one assertion.
$script:skillCase = @(
    Get-ChildItem -LiteralPath $script:skillRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        ForEach-Object {
            @{
                SkillName = $_.Name
                IsKnownDivergence = ($_.Name -in $script:knownDivergenceBaseline)
            }
        }
)

Describe 'Skills reference-validator conformance' -Tag 'Unit' {

    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:skillRoot = Join-Path $script:repoRoot 'Skills'
        $script:uvCommand = Get-Command -Name 'uv' -CommandType Application -ErrorAction SilentlyContinue
        $script:hasUv = $null -ne $script:uvCommand

        # Pinned so an upstream change cannot turn a green build red without a
        # deliberate commit here. Bump this ref to adopt a newer validator.
        $script:skillsRefSource = 'git+https://github.com/agentskills/agentskills.git@69ef37e9424c0a7ea9dd2293b559e43ec8176379#subdirectory=skills-ref'
        $script:runner = Join-Path $script:repoRoot '.build/skills-ref/validate_skills.py'

        $script:validationResult = @{}
        $script:validatorError = $null

        if ($script:hasUv) {
            $skillPath = @(
                Get-ChildItem -LiteralPath $script:skillRoot -Directory |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
                    ForEach-Object { $_.FullName }
            )

            # SKILL.md is UTF-8. Without this the validator inherits the Windows
            # ANSI code page and dies on the first non-ASCII byte, which reads as
            # a content error when it is really a decoding one.
            $previousUtf8 = $env:PYTHONUTF8
            $env:PYTHONUTF8 = '1'
            try {
                # One process for all skills: per-skill invocation costs ~50s.
                $output = & uv run --quiet --with $script:skillsRefSource python $script:runner @skillPath 2>&1
                $exitCode = $LASTEXITCODE
            }
            finally {
                $env:PYTHONUTF8 = $previousUtf8
            }

            if ($exitCode -ne 0) {
                $script:validatorError = ($output | Out-String).Trim()
            }
            else {
                foreach ($line in $output) {
                    $field = ([string]$line) -split "`t"
                    if ($field.Count -lt 2) { continue }

                    $name = $field[1]
                    if (-not $script:validationResult.ContainsKey($name)) {
                        $script:validationResult[$name] = [System.Collections.Generic.List[string]]::new()
                    }
                    if ($field[0] -eq 'ERR') {
                        $script:validationResult[$name].Add($field[2])
                    }
                }
            }
        }
    }

    It 'runs the reference validator' {
        if (-not $script:hasUv) {
            Set-ItResult -Skipped -Because 'uv is not installed, so the reference validator cannot be fetched'
            return
        }

        $script:validatorError | Should -BeNullOrEmpty -Because 'the validator must run to completion before its findings mean anything'
    }

    It 'reports no problems for <SkillName>' -ForEach $script:skillCase {
        if (-not $script:hasUv) {
            Set-ItResult -Skipped -Because 'uv is not installed, so the reference validator cannot be fetched'
            return
        }

        if ($script:validatorError) {
            Set-ItResult -Skipped -Because 'the validator did not run; see the runner test'
            return
        }

        if ($IsKnownDivergence) {
            Set-ItResult -Skipped -Because 'the skill diverges from the open specification in the documented baseline'
            return
        }

        $script:validationResult.ContainsKey($SkillName) |
            Should -BeTrue -Because "the validator must return a verdict for $SkillName"

        $problem = $script:validationResult[$SkillName]
        $problem -join '; ' | Should -BeNullOrEmpty -Because "skills-ref validate reported a conformance problem for $SkillName"
    }
}
