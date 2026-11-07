function Measure-CopilotAtelierSkillCatalog
{
    <#
        .SYNOPSIS
            Estimates which Skills a host lists with their description and which
            it lists by name only, given a character budget for the Skill
            catalog.

        .DESCRIPTION
            A host that offers Skills to the model, such as the Copilot CLI,
            renders one entry per Skill with its name and description, adds the
            entries in name order until the next one would exceed a character
            budget, and lists every remaining Skill by name only. A Skill listed
            by name only can still be loaded, but nothing tells the model what it
            is for. Skills from other sources that the host lists first use part
            of the budget; Offset stands for them.

            Each Skill's name and description are decoded from its frontmatter
            the way a YAML parser decodes the forms Skills use: plain and quoted
            single-line scalars, and folded or literal block scalars with their
            chomping indicator. Markup characters are escaped as the host
            escapes them, so the character count of an entry matches the text
            the host lists. A missing name falls back to the folder name, and a
            missing description lists as empty.

            The result estimates one host listing format. Other clients and
            versions use other budgets and formats.

        .PARAMETER Skill
            The Skills to list. Each object carries FolderName, RelativePath, and
            Frontmatter, the text between the frontmatter fences.

        .PARAMETER Budget
            The character budget for described entries.

        .PARAMETER Offset
            The characters already used by entries the host lists before these
            Skills.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Measure-CopilotAtelierSkillCatalog -Skill $skill -Budget 30000 -Offset 8000

            Returns the estimated catalog, naming the Skills a host lists by name
            only when other Skills already use 8,000 characters of its budget.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Skill,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [System.Int32]::MaxValue)]
        [System.Int32]
        $Budget,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [System.Int32]::MaxValue)]
        [System.Int32]
        $Offset
    )

    $utf8 = [System.Text.Encoding]::UTF8
    $escapeMarkup = {
        param ([System.String] $Text)
        $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
    }

    $entry = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Skill)
    {
        $value = @{}
        $line = @(([System.String] $item.Frontmatter) -split '\r?\n')
        for ($index = 0; $index -lt $line.Count; $index++)
        {
            if ($line[$index] -notmatch '^(?<key>[A-Za-z][A-Za-z0-9_-]*)\s*:[ \t]*(?<value>.*?)[ \t]*$')
            {
                continue
            }

            $key = $Matches.key
            $raw = $Matches.value

            if ($raw -match '^(?<style>[|>])(?<chomp>[+-]?)[1-9]?$')
            {
                $style = $Matches.style
                $chomp = $Matches.chomp
                $block = [System.Collections.Generic.List[string]]::new()
                while ($index + 1 -lt $line.Count -and $line[$index + 1] -match '^(\s+\S|\s*$)')
                {
                    $index++
                    $block.Add($line[$index])
                }

                # Trailing blank lines belong to the chomping indicator, not to the content.
                $trailingBlank = 0
                while ($block.Count -gt 0 -and $block[$block.Count - 1] -match '^\s*$')
                {
                    $block.RemoveAt($block.Count - 1)
                    $trailingBlank++
                }

                $indent = 0
                foreach ($blockLine in $block)
                {
                    if ($blockLine -notmatch '^\s*$')
                    {
                        $indent = $blockLine.Length - $blockLine.TrimStart(' ').Length
                        break
                    }
                }

                $text = [System.Text.StringBuilder]::new()
                $pendingBreak = 0
                $started = $false
                $previousMoreIndented = $false
                foreach ($blockLine in $block)
                {
                    if ($blockLine -match '^\s*$')
                    {
                        $pendingBreak++
                        continue
                    }

                    $content = if ($blockLine.Length -ge $indent) { $blockLine.Substring($indent) } else { $blockLine.TrimStart() }
                    $moreIndented = $content.StartsWith(' ') -or $content.StartsWith("`t")
                    if (-not $started)
                    {
                        $separator = "`n" * $pendingBreak
                    }
                    elseif ($style -eq '|' -or $moreIndented -or $previousMoreIndented)
                    {
                        $separator = "`n" * ($pendingBreak + 1)
                    }
                    elseif ($pendingBreak -gt 0)
                    {
                        # A folded block turns each blank line into one line break.
                        $separator = "`n" * $pendingBreak
                    }
                    else
                    {
                        $separator = ' '
                    }

                    $null = $text.Append($separator).Append($content)
                    $started = $true
                    $pendingBreak = 0
                    $previousMoreIndented = $moreIndented
                }

                $decoded = $text.ToString()
                if ($started -and $chomp -ne '-')
                {
                    $decoded += "`n"
                    if ($chomp -eq '+')
                    {
                        $decoded += "`n" * $trailingBlank
                    }
                }

                $value[$key] = $decoded
            }
            elseif ($raw.Length -ge 2 -and $raw.StartsWith("'") -and $raw.EndsWith("'"))
            {
                $value[$key] = $raw.Substring(1, $raw.Length - 2).Replace("''", "'")
            }
            elseif ($raw.Length -ge 2 -and $raw.StartsWith('"') -and $raw.EndsWith('"'))
            {
                $value[$key] = $raw.Substring(1, $raw.Length - 2).Replace('\"', '"').Replace('\\', '\')
            }
            else
            {
                $value[$key] = $raw
            }
        }

        $name = if ([System.String]::IsNullOrWhiteSpace([System.String] $value['name'])) { [System.String] $item.FolderName } else { [System.String] $value['name'] }
        $description = if ($value.ContainsKey('description')) { [System.String] $value['description'] } else { '' }

        $entry.Add([pscustomobject] @{
                Name         = $name
                RelativePath = [System.String] $item.RelativePath
                Description  = $description
            })
    }

    $entry.Sort([System.Comparison[object]] {
            param ($left, $right)
            [System.String]::CompareOrdinal($left.Name, $right.Name)
        })

    $used = [long] $Offset
    $estimated = [long] 0
    $cut = $false
    $row = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $entry)
    {
        $listed = "<skill>`n  <name>$(& $escapeMarkup $item.Name)</name>`n  <description>$(& $escapeMarkup $item.Description)</description>`n  <location>user</location>`n</skill>"

        # Each entry is followed by the line break that separates it from the next.
        $character = [long] ($listed.Length + 1)
        $estimated += $character

        # The host stops at the first entry that does not fit, so every later
        # Skill is listed by name only even when it would fit on its own.
        $described = (-not $cut) -and (($used + $character) -le $Budget)
        if ($described)
        {
            $used += $character
        }
        else
        {
            $cut = $true
        }

        $row.Add([pscustomobject] @{
                Name         = $item.Name
                RelativePath = $item.RelativePath
                Character    = $character
                Byte         = [long] ($utf8.GetByteCount($listed) + 1)
                Described    = $described
            })
    }

    return [pscustomobject] @{
        BudgetCharacter    = $Budget
        OffsetCharacter    = $Offset
        EstimatedCharacter = $estimated
        DescribedCount     = @($row | Where-Object -FilterScript { $_.Described }).Count
        NameOnlySkill      = @($row | Where-Object -FilterScript { -not $_.Described } | ForEach-Object -Process { $_.Name })
        Skills             = @($row)
    }
}
