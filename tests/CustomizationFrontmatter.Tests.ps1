$script:repoRoot = Split-Path -Parent $PSScriptRoot

$script:agentCase = @(
    Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Agents') -File -Filter '*.agent.md' |
        ForEach-Object { @{ FileName = $_.Name; FilePath = $_.FullName } }
)

$script:instructionCase = @(
    Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Instructions') -File -Filter '*.instructions.md' |
        ForEach-Object { @{ FileName = $_.Name; FilePath = $_.FullName } }
)

$script:promptCase = @(
    Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Prompts') -File -Filter '*.prompt.md' |
        ForEach-Object { @{ FileName = $_.Name; FilePath = $_.FullName } }
)

BeforeAll {
    <#
        Flat-map frontmatter reader. The repository takes no YAML dependency,
        and Customization frontmatter is a flat map of scalars, block scalars,
        and single-line inline sequences. A block scalar collapses to its
        joined continuation lines, which is enough to prove it is not empty.
    #>
    function script:Get-CustomizationFrontmatter
    {
        [CmdletBinding()]
        [OutputType([hashtable])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $line = Get-Content -LiteralPath $Path -Encoding UTF8
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

        $frontmatter = @{}
        $currentKey = $null

        foreach ($currentLine in $line[($delimiter[0] + 1)..($delimiter[1] - 1)])
        {
            if ($currentLine -match '^(?<key>[A-Za-z][A-Za-z0-9-]*):\s*(?<value>.*)$')
            {
                $currentKey = $Matches.key
                $value = $Matches.value.Trim()
                $frontmatter[$currentKey] = if ($value -in @('>-', '>', '|', '|-')) { '' } else { $value }
                continue
            }

            if ($currentKey -and $currentLine -match '^\s+\S')
            {
                $frontmatter[$currentKey] = ($frontmatter[$currentKey] + ' ' + $currentLine.Trim()).Trim()
            }
        }

        return $frontmatter
    }
}

Describe 'Custom agent frontmatter' -Tag 'Unit' {
    It 'discovers every shipped Custom agent' -ForEach @(
        @{ DiscoveredCount = $script:agentCase.Count }
    ) {
        $DiscoveredCount | Should -BeGreaterThan 5 -Because 'a discovery-time miss would silently skip every case'
    }

    It '<FileName> declares a slug-form name' -ForEach $script:agentCase {
        $frontmatter = script:Get-CustomizationFrontmatter -Path $FilePath

        $frontmatter['name'] | Should -Not -BeNullOrEmpty
        $frontmatter['name'].Trim("'", '"') | Should -Match '^[a-z0-9]+(-[a-z0-9]+)*$'
    }

    It '<FileName> is named after its slug' -ForEach $script:agentCase {
        <#
            A file whose stem differs from the declared name is addressed one
            way on disk and another way in a handoff, a Prompt, or a test.
        #>
        $frontmatter = script:Get-CustomizationFrontmatter -Path $FilePath

        $FileName | Should -BeExactly "$($frontmatter['name'].Trim("'", '"')).agent.md"
    }

    It '<FileName> declares a description' -ForEach $script:agentCase {
        $frontmatter = script:Get-CustomizationFrontmatter -Path $FilePath

        $frontmatter['description'] | Should -Not -BeNullOrEmpty
    }

    It '<FileName> declares a model priority array with a fallback' -ForEach $script:agentCase {
        <#
            A single-entry array breaks every agent the day that model is
            retired; the array exists so a retirement degrades instead.
        #>
        $frontmatter = script:Get-CustomizationFrontmatter -Path $FilePath

        $frontmatter['model'] | Should -Match '^\[.+\]$'

        @([regex]::Matches($frontmatter['model'], "'[^']+'")).Count |
            Should -BeGreaterOrEqual 2 -Because 'the last entry is the fallback and must be a generally available model'
    }
}

Describe 'Instruction frontmatter' -Tag 'Unit' {
    It 'discovers every shipped Instruction' -ForEach @(
        @{ DiscoveredCount = $script:instructionCase.Count }
    ) {
        $DiscoveredCount | Should -BeGreaterThan 10 -Because 'a discovery-time miss would silently skip every case'
    }

    It '<FileName> declares an applyTo scope' -ForEach $script:instructionCase {
        <#
            An Instruction with no applyTo never auto-applies and is only ever
            reachable by an explicit attachment, which is not how any of these
            are meant to be used.
        #>
        $frontmatter = script:Get-CustomizationFrontmatter -Path $FilePath

        $frontmatter['applyTo'] | Should -Not -BeNullOrEmpty
        $frontmatter['applyTo'].Trim("'", '"') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Prompt frontmatter' -Tag 'Unit' {
    It 'discovers every shipped Prompt' -ForEach @(
        @{ DiscoveredCount = $script:promptCase.Count }
    ) {
        $DiscoveredCount | Should -BeGreaterThan 5 -Because 'a discovery-time miss would silently skip every case'
    }

    It '<FileName> declares a description' -ForEach $script:promptCase {
        # The description is the whole of what the slash-command picker shows.
        $frontmatter = script:Get-CustomizationFrontmatter -Path $FilePath

        $frontmatter['description'] | Should -Not -BeNullOrEmpty
    }
}
