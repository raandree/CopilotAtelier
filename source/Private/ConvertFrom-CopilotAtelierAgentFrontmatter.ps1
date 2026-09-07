function ConvertFrom-CopilotAtelierAgentFrontmatter
{
    <#
        .SYNOPSIS
            Parses the frontmatter of a Custom agent profile as a deliberately
            strict YAML subset, and rejects anything it cannot map exactly.

        .DESCRIPTION
            Composing a client variant from a profile means re-emitting its
            frontmatter, so a parser that quietly misses a field is worse than
            one that fails. A regular expression that only finds single-quoted
            list items, for example, turns a double-quoted or block tool list
            into an empty one and composes a profile with no capabilities at
            all, while a new safety field disappears without a diagnostic.

            This parser therefore supports one small, unambiguous subset and
            refuses the rest. It accepts plain, single-quoted and double-quoted
            scalars, plain booleans, flow and block sequences, and one opaque
            nested block per field. It rejects an unknown top-level field, a
            duplicate field, a block scalar, an anchor, an alias, an explicit
            tag, a flow mapping, an unterminated sequence, an unbalanced quote,
            and a trailing comment on a plain scalar. Every rejection names the
            field and the source, because the caller has to be able to fix it.

            A field whose nested block is a mapping rather than a scalar list,
            such as handoffs, is reported as Structured. Its presence is known,
            its shape is not interpreted, and it can never be re-emitted.

        .PARAMETER Content
            The whole profile text, including the frontmatter delimiters.

        .PARAMETER KnownField
            The top-level fields that may appear. Defaults to the fields the
            client contract knows about.

        .PARAMETER Source
            A name for the parsed content, used in error messages.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            ConvertFrom-CopilotAtelierAgentFrontmatter -Content (Get-Content -Raw ./software-engineer.agent.md)

            Returns the parsed fields and the untouched body.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [System.String]
        $Content,

        [Parameter()]
        [System.String[]]
        $KnownField,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Source = 'the Custom agent profile'
    )

    $ErrorActionPreference = 'Stop'

    if (-not $PSBoundParameters.ContainsKey('KnownField'))
    {
        $KnownField = (Get-CopilotAtelierClientContract).KnownField
    }

    $readScalar = {
        param
        (
            [System.String] $Text,
            [System.String] $Field
        )

        $trimmed = $Text.Trim()

        if ($trimmed -eq '')
        {
            return [pscustomobject] @{ Type = 'String'; Value = '' }
        }

        $indicator = $trimmed.Substring(0, 1)

        if ($indicator -in @('|', '>'))
        {
            throw "The field '$Field' in $Source uses a block scalar, which this strict parser does not support. Rewrite it as a quoted scalar."
        }

        if ($indicator -in @('&', '*', '!', '%', '@', '`', '{', '}'))
        {
            throw "The field '$Field' in $Source starts with the unsupported YAML indicator '$indicator'. Anchors, aliases, tags and flow mappings are rejected rather than guessed at."
        }

        if ($indicator -eq "'")
        {
            if ($trimmed.Length -lt 2 -or -not $trimmed.EndsWith("'"))
            {
                throw "The field '$Field' in $Source has an unbalanced single quote."
            }

            $inner = $trimmed.Substring(1, $trimmed.Length - 2)
            $builder = [System.Text.StringBuilder]::new()
            $position = 0

            while ($position -lt $inner.Length)
            {
                if ($inner[$position] -eq "'")
                {
                    if ($position + 1 -lt $inner.Length -and $inner[$position + 1] -eq "'")
                    {
                        $null = $builder.Append("'")
                        $position += 2

                        continue
                    }

                    throw "The field '$Field' in $Source has an unbalanced single quote. Escape a literal quote by doubling it."
                }

                $null = $builder.Append($inner[$position])
                $position++
            }

            return [pscustomobject] @{ Type = 'String'; Value = $builder.ToString() }
        }

        if ($indicator -eq '"')
        {
            if ($trimmed.Length -lt 2 -or -not $trimmed.EndsWith('"'))
            {
                throw "The field '$Field' in $Source has an unbalanced double quote."
            }

            $inner = $trimmed.Substring(1, $trimmed.Length - 2)

            if ($inner.Contains('\'))
            {
                throw "The field '$Field' in $Source uses a double-quoted escape sequence, which this strict parser does not decode. Use a single-quoted scalar."
            }

            if ($inner.Contains('"'))
            {
                throw "The field '$Field' in $Source has an unbalanced double quote."
            }

            return [pscustomobject] @{ Type = 'String'; Value = $inner }
        }

        if ($trimmed -match '\s#')
        {
            throw "The field '$Field' in $Source has a trailing comment on a plain scalar, which is ambiguous. Quote the value instead."
        }

        if ($trimmed -match '[\[\]{}]' -or $trimmed -match ':(\s|$)')
        {
            throw "The plain scalar of field '$Field' in $Source contains a YAML structural character. Quote the value instead."
        }

        if ($trimmed -in @('true', 'false'))
        {
            return [pscustomobject] @{ Type = 'Boolean'; Value = ($trimmed -eq 'true') }
        }

        return [pscustomobject] @{ Type = 'String'; Value = $trimmed }
    }

    $readFlowSequence = {
        param
        (
            [System.String] $Text,
            [System.String] $Field
        )

        $trimmed = $Text.Trim()

        if (-not $trimmed.EndsWith(']'))
        {
            throw "The sequence of field '$Field' in $Source is not terminated."
        }

        $inner = $trimmed.Substring(1, $trimmed.Length - 2)
        $item = [System.Collections.Generic.List[string]]::new()
        $current = [System.Text.StringBuilder]::new()
        $quote = $null
        $position = 0

        while ($position -lt $inner.Length)
        {
            $character = $inner[$position]

            if ($quote)
            {
                $null = $current.Append($character)

                if ($character -eq $quote)
                {
                    if ($quote -eq "'" -and $position + 1 -lt $inner.Length -and $inner[$position + 1] -eq "'")
                    {
                        $null = $current.Append("'")
                        $position += 2

                        continue
                    }

                    $quote = $null
                }

                $position++

                continue
            }

            if ($character -in @("'", '"'))
            {
                $quote = $character
                $null = $current.Append($character)
            }
            elseif ($character -eq ',')
            {
                $null = $item.Add($current.ToString())
                $current = [System.Text.StringBuilder]::new()
            }
            elseif ($character -in @('[', ']', '{', '}'))
            {
                throw "The sequence of field '$Field' in $Source nests another structure, which this strict parser does not support."
            }
            else
            {
                $null = $current.Append($character)
            }

            $position++
        }

        if ($quote)
        {
            throw "The sequence of field '$Field' in $Source has an unbalanced quote."
        }

        if ($current.ToString().Trim() -ne '' -or $item.Count -gt 0)
        {
            $item.Add($current.ToString())
        }

        return @(
            $item |
                ForEach-Object -Process {
                    if ($_.Trim() -eq '')
                    {
                        throw "The sequence of field '$Field' in $Source has an empty item."
                    }

                    [System.String] (& $readScalar $_ $Field).Value
                }
        )
    }

    $normalized = $Content -replace "`r`n", "`n"

    if (-not $normalized.StartsWith("---`n"))
    {
        throw "$Source does not start with a frontmatter delimiter."
    }

    $marker = $normalized.IndexOf("`n---`n", 3)

    if ($marker -lt 0)
    {
        throw "$Source has no closing frontmatter delimiter."
    }

    $frontmatterText = if ($marker -lt 4)
    {
        ''
    }
    else
    {
        $normalized.Substring(4, $marker - 4)
    }

    $body = $normalized.Substring($marker + 5)

    $field = [ordered] @{}
    $line = @(
        if ($frontmatterText)
        {
            $frontmatterText -split "`n"
        }
    )

    $index = 0

    while ($index -lt $line.Count)
    {
        $current = $line[$index]

        if ($current.Trim() -eq '' -or $current -match '^\s*#')
        {
            $index++

            continue
        }

        if ($current -match '^\s')
        {
            throw "$Source has an indented line that belongs to no field: '$($current.Trim())'."
        }

        if ($current -notmatch '^(?<key>[A-Za-z][A-Za-z0-9_-]*):(?<rest>\s.*|)$')
        {
            throw "$Source has a frontmatter line that is not a top-level field: '$current'."
        }

        $key = $Matches.key
        $value = $Matches.rest.Trim()

        if ($field.Contains($key))
        {
            throw "$Source declares the field '$key' more than once. A duplicate field silently overwrites the first one, so it is rejected."
        }

        if ($key -notin $KnownField)
        {
            throw "$Source declares the unknown top-level field '$key'. An unrecognized field may carry a restriction, so it is rejected rather than dropped."
        }

        $continuation = [System.Collections.Generic.List[string]]::new()
        $next = $index + 1

        while ($next -lt $line.Count -and $line[$next] -match '^\s+\S')
        {
            $continuation.Add($line[$next])
            $next++
        }

        if ($value -ne '')
        {
            if ($value.StartsWith('|') -or $value.StartsWith('>'))
            {
                throw "The field '$key' in $Source uses a block scalar, which this strict parser does not support. Rewrite it as a quoted scalar."
            }

            if ($continuation.Count -gt 0)
            {
                throw "The field '$key' in $Source has both an inline value and an indented block."
            }

            $field[$key] = if ($value.StartsWith('['))
            {
                [pscustomobject] @{
                    Name  = $key
                    Type  = 'Sequence'
                    Value = @(& $readFlowSequence $value $key)
                }
            }
            else
            {
                $scalar = & $readScalar $value $key

                [pscustomobject] @{
                    Name  = $key
                    Type  = $scalar.Type
                    Value = $scalar.Value
                }
            }
        }
        elseif ($continuation.Count -eq 0)
        {
            $field[$key] = [pscustomobject] @{
                Name  = $key
                Type  = 'String'
                Value = ''
            }
        }
        else
        {
            $isScalarSequence = -not (
                @($continuation | Where-Object -FilterScript {
                        $_ -notmatch '^\s+-\s+\S' -or $_ -match '^\s+-\s+[A-Za-z][A-Za-z0-9_-]*:(\s|$)'
                    }).Count
            )

            $field[$key] = if ($isScalarSequence)
            {
                [pscustomobject] @{
                    Name  = $key
                    Type  = 'Sequence'
                    Value = @(
                        $continuation |
                            ForEach-Object -Process {
                                [System.String] (& $readScalar ($_ -replace '^\s+-\s+', '') $key).Value
                            }
                    )
                }
            }
            else
            {
                [pscustomobject] @{
                    Name  = $key
                    Type  = 'Structured'
                    Value = ($continuation -join "`n")
                }
            }
        }

        $index = $next
    }

    return [pscustomobject] @{
        Field           = $field
        Body            = $body
        FrontmatterText = $frontmatterText
    }
}
