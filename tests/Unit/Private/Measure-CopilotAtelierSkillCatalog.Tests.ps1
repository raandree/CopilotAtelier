BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    # The entry a host lists for one Skill, plus the line break that separates
    # it from the next entry.
    function Get-CatalogEntryLength
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $Name,
            [Parameter(Mandatory = $true)] [AllowEmptyString()] [System.String] $ListedDescription
        )

        return ("<skill>`n  <name>$Name</name>`n  <description>$ListedDescription</description>`n  <location>user</location>`n</skill>").Length + 1
    }

    function New-CatalogSkill
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $FolderName,
            [Parameter(Mandatory = $true)] [AllowEmptyString()] [System.String[]] $Frontmatter
        )

        return [pscustomobject] @{
            FolderName   = $FolderName
            RelativePath = "skills/$FolderName/SKILL.md"
            Frontmatter  = $Frontmatter -join "`n"
        }
    }
}

Describe 'Measure-CopilotAtelierSkillCatalog' -Tag 'Unit' {
    It 'Should list a literal description with its line breaks' {
        $skill = New-CatalogSkill -FolderName 'literal' -Frontmatter @('name: literal', 'description: |-', '  Line one', '  Line two')

        $result = InModuleScope CopilotAtelier -Parameters @{ Skill = @($skill) } {
            Measure-CopilotAtelierSkillCatalog -Skill $Skill -Budget 30000 -Offset 0
        }

        $result.Skills[0].Character | Should -Be (Get-CatalogEntryLength -Name 'literal' -ListedDescription "Line one`nLine two")
    }

    It 'Should keep one final line break for a clipped block and every one for a kept block' {
        $clipped = New-CatalogSkill -FolderName 'clipped' -Frontmatter @('name: clipped', 'description: >', '  Text.', '', '')
        $kept = New-CatalogSkill -FolderName 'kept' -Frontmatter @('name: kept', 'description: >+', '  Text.', '', '')

        $result = InModuleScope CopilotAtelier -Parameters @{ Skill = @($clipped, $kept) } {
            Measure-CopilotAtelierSkillCatalog -Skill $Skill -Budget 30000 -Offset 0
        }

        ($result.Skills | Where-Object { $_.Name -eq 'clipped' }).Character | Should -Be (Get-CatalogEntryLength -Name 'clipped' -ListedDescription "Text.`n")
        ($result.Skills | Where-Object { $_.Name -eq 'kept' }).Character | Should -Be (Get-CatalogEntryLength -Name 'kept' -ListedDescription "Text.`n`n`n")
    }

    It 'Should unescape a single-quoted description before the host escapes it' {
        $skill = New-CatalogSkill -FolderName 'quoted' -Frontmatter @('name: quoted', "description: 'It''s <here>.'")

        $result = InModuleScope CopilotAtelier -Parameters @{ Skill = @($skill) } {
            Measure-CopilotAtelierSkillCatalog -Skill $Skill -Budget 30000 -Offset 0
        }

        $result.Skills[0].Character | Should -Be (Get-CatalogEntryLength -Name 'quoted' -ListedDescription 'It&apos;s &lt;here&gt;.')
    }

    It 'Should fall back to the folder name and an empty description' {
        $skill = New-CatalogSkill -FolderName 'bare' -Frontmatter @('compatibility: Windows only.')

        $result = InModuleScope CopilotAtelier -Parameters @{ Skill = @($skill) } {
            Measure-CopilotAtelierSkillCatalog -Skill $Skill -Budget 30000 -Offset 0
        }

        $result.Skills[0].Name | Should -Be 'bare'
        $result.Skills[0].Character | Should -Be (Get-CatalogEntryLength -Name 'bare' -ListedDescription '')
    }

    It 'Should return an empty catalog when there is no Skill' {
        $result = InModuleScope CopilotAtelier {
            Measure-CopilotAtelierSkillCatalog -Skill @() -Budget 100 -Offset 0
        }

        $result.EstimatedCharacter | Should -Be 0
        $result.DescribedCount | Should -Be 0
        @($result.NameOnlySkill) | Should -HaveCount 0
        @($result.Skills) | Should -HaveCount 0
    }

    It 'Should report the UTF-8 size of each listed entry next to its characters' {
        $skill = New-CatalogSkill -FolderName 'umlaut' -Frontmatter @('name: umlaut', ('description: "Pr{0}fung."' -f [char] 0x00FC))

        $result = InModuleScope CopilotAtelier -Parameters @{ Skill = @($skill) } {
            Measure-CopilotAtelierSkillCatalog -Skill $Skill -Budget 30000 -Offset 0
        }

        $result.Skills[0].Byte | Should -Be ($result.Skills[0].Character + 1)
    }
}
