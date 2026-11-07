$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:skillRoot = Join-Path $script:repoRoot 'skills'
$script:indexPath = Join-Path $script:repoRoot 'com.github.copilot/rules/skill-index.instructions.md'
$script:indexExists = Test-Path -LiteralPath $script:indexPath -PathType Leaf
$script:indexText = if ($script:indexExists) { Get-Content -LiteralPath $script:indexPath -Raw } else { '' }

<#
    A host shows Skill descriptions only up to a size budget and lists the rest
    by name only, so the index is the one always-applied place that still says
    what each of those Skills is for. A Skill without a row is invisible again on
    every host that cuts it; a row without a Skill sends the agent after a name
    that cannot load.
#>
$script:indexEntry = @(
    $script:indexText -split '\r?\n' |
        ForEach-Object {
            if ($_ -match '^\|\s*`(?<name>[^`|]+)`\s*\|(?<use>.*)\|\s*$')
            {
                @{
                    RowName = $Matches['name'].Trim()
                    RowUse  = $Matches['use'].Trim()
                }
            }
        }
)

$script:indexName = [string[]] @($script:indexEntry | ForEach-Object { $_.RowName })
$script:orderedIndexName = [string[]] $script:indexName.Clone()
[System.Array]::Sort($script:orderedIndexName, [System.StringComparer]::Ordinal)

# Built during discovery so -ForEach expands; every value an assertion reads
# travels as case data, because a discovery-scope variable is null inside It.
$script:skillCase = @(
    Get-ChildItem -LiteralPath $script:skillRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        ForEach-Object {
            $skillName = $_.Name
            @{
                SkillName = $skillName
                RowCount  = @($script:indexName | Where-Object { $_ -ceq $skillName }).Count
            }
        }
)

$script:rowCase = @(
    $script:indexEntry |
        ForEach-Object {
            @{
                RowName     = $_.RowName
                RowUse      = $_.RowUse
                SkillExists = Test-Path -LiteralPath (Join-Path $script:skillRoot ('{0}/SKILL.md' -f $_.RowName)) -PathType Leaf
            }
        }
)

Describe 'Skill index Instruction' -Tag 'Unit' {
    It 'ships as an Instruction that applies to every request' -ForEach @(
        @{ Exists = $script:indexExists; Text = $script:indexText }
    ) {
        $Exists | Should -Be $true -Because 'only an always-applied Instruction reaches a host that hides Skill descriptions'
        $Text | Should -Match '(?m)^applyTo:\s*"\*\*"\s*$'
        $Text | Should -Match '(?m)^description:\s*"\S.*"\s*$'
    }

    It 'stays within a compact prompt budget' -ForEach @(
        @{ Length = $script:indexText.Length }
    ) {
        $Length | Should -BeGreaterThan 0
        $Length | Should -BeLessOrEqual 6000 -Because 'the index is sent with every request, so each row must stay one short line'
    }

    It 'loads a matching Skill by name, and only one the host lists' -ForEach @(
        @{ Text = $script:indexText }
    ) {
        $Text | Should -Match '(?i)by name' -Because 'a Skill listed without a description is still loaded by its name'
        $Text | Should -Match '(?i)only when the host lists' -Because 'an installation profile can leave a Skill out, and its row must not send the agent after it'
    }

    It 'parses the index table' -ForEach @(
        @{ RowCount = $script:indexEntry.Count; SkillCount = $script:skillCase.Count }
    ) {
        $SkillCount | Should -BeGreaterThan 30 -Because 'a discovery-time miss would silently skip every case'
        $RowCount | Should -BeGreaterThan 30 -Because 'zero rows means the table or the row pattern moved, not that the index is empty'
    }

    It 'lists its rows in name order' -ForEach @(
        @{ Name = $script:indexName; Ordered = $script:orderedIndexName }
    ) {
        $Name | Should -Be $Ordered -Because 'name order matches the host list and makes a missing or duplicate row easy to spot'
    }

    It '<SkillName> has exactly one index row' -ForEach $script:skillCase {
        $RowCount | Should -Be 1 -Because 'a Skill without a row stays undiscoverable on every host that lists it by name only'
    }

    It '<RowName> names a shipped Skill' -ForEach $script:rowCase {
        $SkillExists | Should -Be $true -Because 'a row for a Skill that no longer ships sends the agent after a name that cannot load'
    }

    It '<RowName> says when to load it' -ForEach $script:rowCase {
        $RowUse | Should -Not -BeNullOrEmpty -Because 'the row exists to say what the Skill serves'
    }
}
