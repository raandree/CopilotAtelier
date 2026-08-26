$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:skillRoot = Join-Path $script:repoRoot 'skills'
$script:readmePath = Join-Path $script:repoRoot 'README.md'

<#
    Rows are read from the "Available Skills" section only. README carries other
    tables whose first cell is bold as well, so a whole-file scan would report
    "Agents" and "Instructions" as Skills and the orphan check would fail on
    rows that were never meant to name one.
#>
$script:catalogueLine = @()
$script:inCatalogue = $false

foreach ($line in (Get-Content -LiteralPath $script:readmePath))
{
    if ($line -match '^##\s')
    {
        $script:inCatalogue = $line -match '^##\s+Available Skills\s*$'
        continue
    }

    if ($script:inCatalogue)
    {
        $script:catalogueLine += $line
    }
}

$script:catalogueEntry = @(
    $script:catalogueLine |
        ForEach-Object {
            if ($_ -match '^\|\s*\*\*(?<name>[^*|]+)\*\*\s*\|(?<description>.*)\|\s*$')
            {
                @{
                    RowName = $Matches['name'].Trim()
                    RowDescription = $Matches['description'].Trim()
                }
            }
        }
)

$script:catalogueName = @($script:catalogueEntry | ForEach-Object { $_.RowName })

# Built during discovery so -ForEach expands; a BeforeAll would produce zero
# cases. Every value an assertion reads travels as case data, because a
# discovery-scope variable is null inside It.
$script:skillCase = @(
    Get-ChildItem -LiteralPath $script:skillRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        ForEach-Object {
            @{
                SkillName = $_.Name
                IsListed = $script:catalogueName -contains $_.Name
            }
        }
)

$script:rowCase = @(
    $script:catalogueEntry |
        ForEach-Object {
            @{
                RowName = $_.RowName
                RowDescription = $_.RowDescription
                SkillExists = Test-Path -LiteralPath (Join-Path $script:skillRoot ('{0}/SKILL.md' -f $_.RowName)) -PathType Leaf
            }
        }
)

Describe 'README Skill catalogue' -Tag 'Unit' {
    It 'parses the Available Skills section' -ForEach @(
        @{ RowCount = $script:catalogueEntry.Count; SkillCount = $script:skillCase.Count }
    ) {
        $SkillCount |
            Should -BeGreaterThan 30 -Because 'a discovery-time miss would silently skip every case'

        $RowCount |
            Should -BeGreaterThan 30 -Because 'zero rows means the heading or the row pattern moved, not that the catalogue is empty'
    }

    It '<SkillName> has a catalogue row' -ForEach $script:skillCase {
        $IsListed |
            Should -BeTrue -Because 'a Skill absent from the README ships invisible to anyone reading the repository'
    }

    It '<RowName> names a shipped Skill' -ForEach $script:rowCase {
        $SkillExists |
            Should -BeTrue -Because 'a row for a Skill that no longer ships advertises something nobody can load'
    }

    It '<RowName> carries a description' -ForEach $script:rowCase {
        $RowDescription |
            Should -Not -BeNullOrEmpty -Because 'the catalogue exists to say what the Skill is for'
    }
}
