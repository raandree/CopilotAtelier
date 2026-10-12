#Requires -Version 5.1

<#
.SYNOPSIS
    Shared readers for the handoff sequence scripts.
.DESCRIPTION
    Dot-sourced by Test-HandoffSequence.ps1 and Get-HandoffSequenceInventory.ps1.
    Reads Markdown text, front matter, tables, sections, links, and the slots a
    brief has to carry. It defines functions only and changes nothing.
#>

function Read-HandoffText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # A byte order mark is detected and dropped, so the first line is the first line.
    [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
}

function Test-HandoffReparsePoint {
    <#
    .SYNOPSIS
        Tells whether a file or folder is a link, which these scripts never read through.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [IO.FileSystemInfo] $Item
    )

    ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}

function Get-HandoffFrontMatter {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $result = [pscustomobject]@{
        IsValid = $false
        Value   = @{}
        Body    = $Text
    }

    $line = @($Text -split '\r?\n')
    if ($line.Count -lt 2 -or $line[0].TrimEnd() -ne '---') {
        return $result
    }

    $end = -1
    for ($index = 1; $index -lt $line.Count; $index++) {
        if ($line[$index].TrimEnd() -eq '---') {
            $end = $index
            break
        }
    }

    if ($end -lt 0) {
        return $result
    }

    $value = @{}
    $key = $null
    for ($index = 1; $index -lt $end; $index++) {
        $current = $line[$index]
        if ($current -match '^(?<key>[A-Za-z][A-Za-z0-9_-]*):\s*(?<value>.*)$') {
            $key = $Matches['key']
            $scalar = $Matches['value'].Trim()
            if ($scalar -in @('>', '>-', '|', '|-')) {
                $scalar = ''
            } elseif ($scalar.Length -ge 2 -and (
                    ($scalar.StartsWith('"') -and $scalar.EndsWith('"')) -or
                    ($scalar.StartsWith("'") -and $scalar.EndsWith("'")))) {
                $scalar = $scalar.Substring(1, $scalar.Length - 2)
            }

            $value[$key] = $scalar
        } elseif ($null -ne $key -and $current -match '^\s+\S') {
            $value[$key] = ($value[$key] + ' ' + $current.Trim()).Trim()
        }
    }

    $result.IsValid = $true
    $result.Value = $value
    $result.Body = if ($end + 1 -lt $line.Count) { $line[($end + 1)..($line.Count - 1)] -join "`n" } else { '' }
    $result
}

function ConvertFrom-HandoffTableRow {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $inner = $Text.Trim()
    if ($inner.StartsWith('|')) {
        $inner = $inner.Substring(1)
    }

    if ($inner.EndsWith('|') -and -not $inner.EndsWith('\|')) {
        $inner = $inner.Substring(0, $inner.Length - 1)
    }

    foreach ($part in [regex]::Split($inner, '(?<!\\)\|')) {
        $part.Replace('\|', '|').Trim()
    }
}

function Get-HandoffTable {
    <#
    .SYNOPSIS
        Returns every pipe table in the lines, ignoring fenced code.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]] $Line
    )

    $table = [Collections.Generic.List[object]]::new()
    $delimiter = '^\s*\|(?:\s*:?-+:?\s*\|)+\s*$'
    $inFence = $false
    $index = 0
    while ($index -lt $Line.Count) {
        $current = $Line[$index]
        if ($current -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            $index++
            continue
        }

        if (-not $inFence -and $current -match '^\s*\|' -and ($index + 1) -lt $Line.Count -and $Line[$index + 1] -match $delimiter) {
            $header = @(ConvertFrom-HandoffTableRow -Text $current)
            $row = [Collections.Generic.List[object]]::new()
            $start = $index
            $index += 2
            while ($index -lt $Line.Count -and $Line[$index] -match '^\s*\|') {
                $row.Add([pscustomobject]@{
                        Line = $index + 1
                        Cell = @(ConvertFrom-HandoffTableRow -Text $Line[$index])
                    })
                $index++
            }

            $table.Add([pscustomobject]@{
                    Line   = $start + 1
                    Header = $header
                    Row    = $row.ToArray()
                })
            continue
        }

        $index++
    }

    $table.ToArray()
}

function Get-HandoffColumnIndex {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Header,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Pattern
    )

    for ($index = 0; $index -lt $Header.Count; $index++) {
        if ($Header[$index] -match $Pattern) {
            return $index
        }
    }

    -1
}

function Get-HandoffSection {
    <#
    .SYNOPSIS
        Returns the text under the first heading that matches, up to the next heading of the same or a higher level.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $HeadingPattern
    )

    $line = @($Text -split '\r?\n')
    $inFence = $false
    $start = -1
    $level = 0
    for ($index = 0; $index -lt $line.Count; $index++) {
        if ($line[$index] -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            continue
        }

        if ($inFence) {
            continue
        }

        if ($start -lt 0) {
            if ($line[$index] -match ('^(?<hashes>#{1,6})\s+(?:' + $HeadingPattern + ')\b[^\r\n]*$')) {
                $start = $index + 1
                $level = $Matches['hashes'].Length
            }
        } elseif ($line[$index] -match '^(?<hashes>#{1,6})\s+\S' -and $Matches['hashes'].Length -le $level) {
            if ($index - 1 -lt $start) {
                return ''
            }

            return ($line[$start..($index - 1)] -join "`n")
        }
    }

    if ($start -lt 0) {
        return $null
    }

    if ($start -ge $line.Count) {
        return ''
    }

    $line[$start..($line.Count - 1)] -join "`n"
}

function ConvertTo-HandoffProse {
    <#
    .SYNOPSIS
        Blanks fenced blocks and inline code spans, keeping every line number.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $kept = [Collections.Generic.List[string]]::new()
    $inFence = $false
    foreach ($current in ($Text -split '\r?\n')) {
        if ($current -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            $kept.Add('')
            continue
        }

        if ($inFence) {
            $kept.Add('')
            continue
        }

        $kept.Add([regex]::Replace($current, '`[^`]*`', ''))
    }

    $kept -join "`n"
}

function Get-HandoffLink {
    <#
    .SYNOPSIS
        Returns the link targets outside code, with their line numbers.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $line = @((ConvertTo-HandoffProse -Text $Text) -split '\n')
    for ($index = 0; $index -lt $line.Count; $index++) {
        # The bounds keep a line of unclosed brackets from costing time that grows with its square.
        foreach ($match in [regex]::Matches($line[$index], '!?\[[^\]]{0,300}\]\((?<target>[^)\s]+)(?:\s+"[^"]{0,300}")?\)')) {
            [pscustomobject]@{ Line = $index + 1; Target = $match.Groups['target'].Value }
        }

        if ($line[$index] -match '^\s*\[[^\]]+\]:\s*(?<target>\S+)') {
            [pscustomobject]@{ Line = $index + 1; Target = $Matches['target'] }
        }
    }
}

function Get-HandoffMissingSlot {
    <#
    .SYNOPSIS
        Names the slots a brief has to carry and this text does not.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $missing = [Collections.Generic.List[string]]::new()
    $front = Get-HandoffFrontMatter -Text $Text
    if (-not $front.IsValid -or [string]::IsNullOrWhiteSpace([string]$front.Value['description'])) {
        $missing.Add('FrontMatter')
    } elseif ([string]::IsNullOrWhiteSpace([string]$front.Value['agent'])) {
        $missing.Add('Agent')
    }

    if ($Text -notmatch '\]\(00-README\.md(?:#[^)\r\n]{0,200})?\)') {
        $missing.Add('ReadmePointer')
    }

    $heading = [ordered]@{
        Preconditions = 'Preconditions?|Prerequisites?'
        Evidence      = 'Evidence'
        AskFirst      = 'Ask (?:first|before)'
        Tasks         = 'Tasks?|Steps|Required behavior|Approach'
        Validation    = 'Validation|Verification|Tests?'
        Finish        = 'Finish'
    }

    $found = @{}
    foreach ($name in $heading.Keys) {
        $found[$name] = $null -ne (Get-HandoffSection -Text $Text -HeadingPattern $heading[$name])
    }

    if (-not $found['Preconditions']) {
        $missing.Add('Preconditions')
    }

    if ($Text -notmatch '(?i)\bown row\b') {
        $missing.Add('OwnRowCheck')
    }

    if ($Text -notmatch '(?i)\bdependency rows?\b') {
        $missing.Add('DependencyCheck')
    }

    foreach ($name in @('Evidence', 'AskFirst', 'Tasks', 'Validation')) {
        if (-not $found[$name]) {
            $missing.Add($name)
        }
    }

    if (-not $found['Finish']) {
        $missing.Add('Finish')
    } else {
        $finish = [string](Get-HandoffSection -Text $Text -HeadingPattern $heading['Finish'])
        if ($finish -notmatch '(?i)\bcommit\b') {
            $missing.Add('FinishCommit')
        }

        if ($finish -notmatch '(?i)\breports[\\/]') {
            $missing.Add('FinishReport')
        }

        if ($finish -notmatch '(?i)\bledger\b') {
            $missing.Add('FinishLedger')
        }
    }

    $missing.ToArray()
}

function Get-HandoffReportStatus {
    <#
    .SYNOPSIS
        Returns the status a report states, or $null when it states none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $status = 'Done with concerns|Done|Needs context|Blocked'
    $section = Get-HandoffSection -Text $Text -HeadingPattern 'Status'
    if ($null -ne $section) {
        foreach ($current in ($section -split '\n')) {
            if ($current -match ('^[\s`*_]*(?<status>' + $status + ')\b')) {
                return (Get-HandoffCanonicalStatus -Text $Matches['status'])
            }

            if (-not [string]::IsNullOrWhiteSpace($current)) {
                break
            }
        }
    }

    # Blanks and markers only, never a newline: a run of blank lines must not cost time that grows with its square.
    if ($Text -match ('(?im)^[ \t`*_]*status[ \t`*_]*[:\-][ \t`*_]*(?<status>' + $status + ')\b')) {
        return (Get-HandoffCanonicalStatus -Text $Matches['status'])
    }

    $null
}

function Get-HandoffCanonicalStatus {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Text
    )

    foreach ($status in @('Not started', 'Done with concerns', 'Done', 'Needs context', 'Blocked')) {
        if ($Text -ieq $status) {
            return $status
        }
    }

    $Text
}

function Get-HandoffFileHash {
    <#
    .SYNOPSIS
        Returns the SHA-256 of a file as upper-case hexadecimal.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # .NET, not Get-FileHash: Windows PowerShell 5.1 cannot resolve that cmdlet inside a Pester It.
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($algorithm.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '')
    } finally {
        $algorithm.Dispose()
    }
}

function Get-HandoffCommitToken {
    <#
    .SYNOPSIS
        Returns the commit-looking tokens a text names: a hexadecimal word of 7 to 40 characters with a digit and a letter.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $found = [Collections.Generic.List[string]]::new()
    foreach ($pattern in @('`(?<token>[0-9a-fA-F]{7,40})`', '(?i)\bcommits?\b[^\r\n]{0,40}?\b(?<token>[0-9a-f]{7,40})\b')) {
        foreach ($match in [regex]::Matches($Text, $pattern)) {
            $token = $match.Groups['token'].Value.ToLowerInvariant()
            # A digit and a letter: that leaves out words made of a-f and numbers such as a date.
            if ($token -match '[0-9]' -and $token -match '[a-f]' -and -not $found.Contains($token)) {
                $found.Add($token)
            }
        }
    }

    $found.ToArray()
}
