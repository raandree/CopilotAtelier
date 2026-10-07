<#
    Frozen copy, the yardstick of the calibration latency Meter. Decision
    record 0028, ruling A17. Copied unchanged, apart from this paragraph, from
    skills/contributor-profile/scripts/ContributorProfileReader.ps1 in the
    commit that introduced tests/Fixtures/ReferenceHook, and changed only
    together with a re-baseline of both latency tags. No drift test binds it to
    the shipped reader, and adding one would destroy the unit: the shipped
    reader is the subject and this copy the denominator, so a regression in the
    shipped reader must move the numerator while this copy stands still. The
    Meter's frozen reference is its only consumer; the product never loads it.

    Read path of the contributor-profile Skill. Decision record 0028.

    Defines functions only and writes nothing: the location rule, the strict
    schema 1 reader, the identity rule, the Knowledge areas declaration, and the
    calibration sentence. The SessionStart and PostToolUse hooks dot-source this
    file, and ContributorProfileCommon.ps1 builds every writer on it, so one
    implementation serves every entry point.

    Keep this file ASCII: Windows PowerShell 5.1 runs the VS Code hooks and reads
    a script without a byte-order mark in the system code page.
#>

function Get-ContributorProfileLimit
{
    <#
        The caps of schema 1 and of the declaration, in one place.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    @{
        ProfileBytes     = 65536
        Entries          = 16
        Aliases          = 8
        Areas            = 200
        AreaNameLength   = 48
        DeclarationBytes = 65536
        DeclaredAreas    = 16
        JsonDepth        = 16
        GitMilliseconds  = 2000
        StepMilliseconds = 3000
        LockMilliseconds = 5000
    }
}

function ConvertFrom-ContributorJson
{
    <#
        Parses RFC 8259 JSON strictly and identically in Windows PowerShell 5.1
        and PowerShell 7. ConvertFrom-Json differs between the two: PowerShell 7
        turns ISO 8601 strings into dates and rejects case-only duplicate keys,
        which would give the hooks and the commands different reason codes for
        one file. Every node keeps its JSON type: @{ T = 'o' | 'a' | 's' | 'n' |
        'b' | 'z' }. Objects keep duplicate keys in order, numbers keep their raw
        text. A syntax error throws FormatException; nesting deeper than the cap
        throws InvalidDataException, because the JSON is valid but no schema 1
        file is that deep. The parser is iterative, so a hostile file cannot
        exhaust the call stack.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Text,

        [Parameter()]
        [System.Int32]
        $MaximumDepth = 16
    )

    $tokenPattern = '\G[ \t\r\n]*(?:(?<s>"(?:[^"\\\x00-\x1F]|\\(?:["\\/bfnrt]|u[0-9A-Fa-f]{4}))*")|(?<n>-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)(?![0-9A-Za-z.+-])|(?<l>true|false|null)(?![0-9A-Za-z])|(?<p>[{}\[\]:,]))'
    $tokens = [System.Text.RegularExpressions.Regex]::Matches($Text, $tokenPattern)

    $consumed = 0
    if ($tokens.Count -gt 0)
    {
        $last = $tokens[$tokens.Count - 1]
        $consumed = $last.Index + $last.Length
    }

    if ($Text.Substring($consumed) -notmatch '\A[ \t\r\n]*\z')
    {
        throw [System.FormatException]::new('invalid-json: unexpected character at offset ' + $consumed)
    }

    if ($tokens.Count -eq 0)
    {
        throw [System.FormatException]::new('invalid-json: empty document')
    }

    $unescape = [System.Text.RegularExpressions.MatchEvaluator] {
        param ($match)

        if ($match.Groups[1].Success)
        {
            return [string][char][System.Convert]::ToInt32($match.Groups[1].Value, 16)
        }

        switch -CaseSensitive ($match.Groups[2].Value)
        {
            'b' { return [string][char]8 }
            'f' { return [string][char]12 }
            'n' { return [string][char]10 }
            'r' { return [string][char]13 }
            't' { return [string][char]9 }
            default { return $match.Groups[2].Value }
        }
    }

    $root = $null
    $rootSet = $false
    $stack = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($token in $tokens)
    {
        $node = $null
        $punctuation = $null

        if ($token.Groups['s'].Success)
        {
            $inner = $token.Groups['s'].Value
            $inner = $inner.Substring(1, $inner.Length - 2)
            if ($inner.IndexOf([char]92) -ge 0)
            {
                $inner = [System.Text.RegularExpressions.Regex]::Replace($inner, '\\(?:u([0-9A-Fa-f]{4})|(["\\/bfnrt]))', $unescape)
            }

            $node = @{ T = 's'; V = $inner }
        }
        elseif ($token.Groups['n'].Success)
        {
            $node = @{ T = 'n'; V = $token.Groups['n'].Value }
        }
        elseif ($token.Groups['l'].Success)
        {
            switch ($token.Groups['l'].Value)
            {
                'true' { $node = @{ T = 'b'; V = $true } }
                'false' { $node = @{ T = 'b'; V = $false } }
                default { $node = @{ T = 'z'; V = $null } }
            }
        }
        else
        {
            $punctuation = $token.Groups['p'].Value
        }

        $frame = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }

        if ($null -ne $frame -and $frame.Node.T -eq 'o' -and ($frame.State -eq 'start' -or $frame.State -eq 'comma'))
        {
            # An object waiting for a property name, or for its end when empty.
            if ($punctuation -eq '}' -and $frame.State -eq 'start')
            {
                $stack.RemoveAt($stack.Count - 1)
                $node = $frame.Node
                $punctuation = $null
                $frame = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }
            }
            elseif ($null -ne $node -and $node.T -eq 's')
            {
                $frame.Key = $node.V
                $frame.State = 'key'
                continue
            }
            else
            {
                throw [System.FormatException]::new('invalid-json: expected a property name')
            }
        }
        elseif ($null -ne $frame -and $frame.Node.T -eq 'o' -and $frame.State -eq 'key')
        {
            if ($punctuation -ne ':')
            {
                throw [System.FormatException]::new('invalid-json: expected a colon')
            }

            $frame.State = 'colon'
            continue
        }
        elseif ($null -ne $frame -and $frame.State -eq 'value')
        {
            if ($punctuation -eq ',')
            {
                $frame.State = 'comma'
                continue
            }

            $closing = if ($frame.Node.T -eq 'o') { '}' } else { ']' }
            if ($punctuation -ne $closing)
            {
                throw [System.FormatException]::new('invalid-json: expected a comma or ' + $closing)
            }

            $stack.RemoveAt($stack.Count - 1)
            $node = $frame.Node
            $punctuation = $null
            $frame = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }
        }
        elseif ($null -ne $frame -and $frame.Node.T -eq 'a' -and $frame.State -eq 'start' -and $punctuation -eq ']')
        {
            $stack.RemoveAt($stack.Count - 1)
            $node = $frame.Node
            $punctuation = $null
            $frame = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }
        }

        if ($punctuation -eq '{' -or $punctuation -eq '[')
        {
            if ($stack.Count -ge $MaximumDepth)
            {
                throw [System.IO.InvalidDataException]::new('invalid-schema: nesting deeper than ' + $MaximumDepth)
            }

            if ($null -eq $frame -and $rootSet)
            {
                throw [System.FormatException]::new('invalid-json: more than one top-level value')
            }

            if ($null -ne $frame -and $frame.Node.T -eq 'o' -and $frame.State -ne 'colon')
            {
                throw [System.FormatException]::new('invalid-json: expected a property name')
            }

            $container = if ($punctuation -eq '{')
            {
                @{ T = 'o'; K = [System.Collections.Generic.List[string]]::new(); V = [System.Collections.Generic.List[object]]::new() }
            }
            else
            {
                @{ T = 'a'; V = [System.Collections.Generic.List[object]]::new() }
            }

            $stack.Add(@{ Node = $container; State = 'start'; Key = $null })
            continue
        }

        if ($null -ne $punctuation)
        {
            throw [System.FormatException]::new('invalid-json: unexpected ' + $punctuation)
        }

        if ($null -eq $frame)
        {
            if ($rootSet)
            {
                throw [System.FormatException]::new('invalid-json: more than one top-level value')
            }

            $root = $node
            $rootSet = $true
            continue
        }

        if ($frame.Node.T -eq 'o')
        {
            if ($frame.State -ne 'colon')
            {
                throw [System.FormatException]::new('invalid-json: expected a property name')
            }

            $frame.Node.K.Add($frame.Key)
            $frame.Node.V.Add($node)
        }
        else
        {
            if ($frame.State -ne 'start' -and $frame.State -ne 'comma')
            {
                throw [System.FormatException]::new('invalid-json: expected a comma or ]')
            }

            $frame.Node.V.Add($node)
        }

        $frame.State = 'value'
    }

    if ($stack.Count -gt 0 -or -not $rootSet)
    {
        throw [System.FormatException]::new('invalid-json: unterminated document')
    }

    return $root
}

function ConvertTo-ContributorAreaName
{
    <#
        Applies the area-name rule of Decision record 0028 to raw text: trim,
        Unicode NFC, then 1 to 48 characters of letters of any script with their
        combining marks, decimal digits, single spaces, and . + # / & ( ) -,
        starting with a letter, a digit, or a dot directly followed by a letter
        or a digit, so .NET passes (ruling A6). Returns the normalized name, or
        $null when the text breaks the rule. The profile and projectbrief.md
        share it.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Name
    )

    if ($null -eq $Name)
    {
        return $null
    }

    $normalized = $Name.Trim()
    try
    {
        $normalized = $normalized.Normalize([System.Text.NormalizationForm]::FormC)
    }
    catch
    {
        # An unpaired surrogate cannot be normalized and is not a letter.
        return $null
    }

    $surrogatePairs = [System.Text.RegularExpressions.Regex]::Matches($normalized, '[\uD800-\uDBFF][\uDC00-\uDFFF]').Count
    $length = $normalized.Length - $surrogatePairs
    if ($length -lt 1 -or $length -gt 48)
    {
        return $null
    }

    if ($normalized -cnotmatch '\A(?:[\p{L}\p{Nd}]|\.(?=[\p{L}\p{Nd}]))(?:[\p{L}\p{M}\p{Nd}.+#/&()-]| (?! ))*\z')
    {
        return $null
    }

    return $normalized
}

function Test-ContributorAreaName
{
    <#
        True when a stored name already is its own normalized form under the
        area-name rule, so two stored spellings can never differ only by
        surrounding whitespace or Unicode normalization.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Name
    )

    $normalized = ConvertTo-ContributorAreaName -Name $Name
    return ($null -ne $normalized -and [System.String]::Equals($normalized, $Name, [System.StringComparison]::Ordinal))
}

function Test-ContributorUtcTimestamp
{
    <#
        ISO 8601 in UTC with a Z designator, optionally with up to seven
        fractional digits, naming a real calendar instant.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Value
    )

    if ([System.String]::IsNullOrEmpty($Value) -or $Value -cnotmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,7})?Z\z')
    {
        return $false
    }

    $parsed = [System.DateTime]::MinValue
    return [System.DateTime]::TryParse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal),
        [ref] $parsed
    )
}

function ConvertFrom-ContributorUtcTimestamp
{
    [CmdletBinding()]
    [OutputType([System.DateTime])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Value
    )

    return [System.DateTime]::Parse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
    )
}

function Test-ContributorAlias
{
    <#
        An alias is an email address as git reports it: one @, no whitespace,
        control characters, quotes, angle brackets, or list separators, at most
        254 characters.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Alias
    )

    return (-not [System.String]::IsNullOrEmpty($Alias) -and $Alias.Length -le 254 -and
        $Alias -cmatch '\A[^\s\p{Cc}@"<>()\[\]\\,;:`]+@[^\s\p{Cc}@"<>()\[\]\\,;:`]+\z')
}

function Get-ContributorNodeMember
{
    <#
        Returns the members of a parsed JSON object as a case-insensitive map,
        or throws invalid-schema when a name repeats in any letter case, is not
        one of the allowed names, or an allowed name is missing. Allowed names
        are matched exactly. Messages never repeat text from the file.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, object]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Node,

        [Parameter(Mandatory = $true)]
        [System.String[]]
        $Allowed,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Where
    )

    if ($Node.T -ne 'o')
    {
        throw [System.IO.InvalidDataException]::new("invalid-schema: $Where is not an object")
    }

    # Ordinal and case-insensitive on purpose: a case-only duplicate is a
    # violation, and the result must not depend on the machine's culture.
    $members = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($index = 0; $index -lt $Node.K.Count; $index++)
    {
        $name = $Node.K[$index]
        if ($members.ContainsKey($name))
        {
            throw [System.IO.InvalidDataException]::new("invalid-schema: $Where repeats a property name")
        }

        if ($Allowed -cnotcontains $name)
        {
            throw [System.IO.InvalidDataException]::new("invalid-schema: $Where has an unknown property")
        }

        $members[$name] = $Node.V[$index]
    }

    foreach ($name in $Allowed)
    {
        if (-not $members.ContainsKey($name))
        {
            throw [System.IO.InvalidDataException]::new("invalid-schema: $Where lacks '$name'")
        }
    }

    return , $members
}

function ConvertTo-ContributorProfileModel
{
    <#
        Validates a parsed document against schema 1 and returns the profile
        model. Any violation rejects the whole file: InvalidDataException for
        invalid-schema, NotSupportedException for unsupported-schema. The schema
        version is checked first, because the rules of another version are
        unknown here.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $Node
    )

    $limit = Get-ContributorProfileLimit
    $fail = {
        param ([string] $Message)
        throw [System.IO.InvalidDataException]::new('invalid-schema: ' + $Message)
    }

    if ($Node.T -ne 'o')
    {
        & $fail 'the profile is not an object'
    }

    $versionIndex = $Node.K.IndexOf('schemaVersion')
    if ($versionIndex -lt 0 -or $Node.V[$versionIndex].T -ne 'n' -or $Node.V[$versionIndex].V -cnotmatch '\A(?:0|[1-9][0-9]*)\z')
    {
        & $fail 'schemaVersion is missing or not an integer'
    }

    if ($Node.V[$versionIndex].V -cne '1')
    {
        throw [System.NotSupportedException]::new('unsupported-schema: schemaVersion is not 1')
    }

    $root = Get-ContributorNodeMember -Node $Node -Allowed @('schemaVersion', 'contributors') -Where 'the profile'
    $list = $root['contributors']
    if ($list.T -ne 'a' -or $list.V.Count -lt 1 -or $list.V.Count -gt $limit.Entries)
    {
        & $fail "contributors must hold 1 to $($limit.Entries) entries"
    }

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $allAliases = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $defaultCount = 0
    $entries = [System.Collections.Generic.List[object]]::new()

    for ($position = 0; $position -lt $list.V.Count; $position++)
    {
        $where = 'entry ' + ($position + 1)
        $member = Get-ContributorNodeMember -Node $list.V[$position] -Where $where -Allowed @(
            'id', 'default', 'state', 'stateUpdatedUtc', 'interviewSnoozedUntilUtc', 'aliases', 'areas'
        )

        $parsedId = [System.Guid]::Empty
        if ($member['id'].T -ne 's' -or -not [System.Guid]::TryParseExact($member['id'].V, 'D', [ref] $parsedId))
        {
            & $fail "$where has no GUID id"
        }

        if (-not $ids.Add($member['id'].V))
        {
            & $fail "$where repeats an id"
        }

        if ($member['default'].T -ne 'b')
        {
            & $fail "$where default is not a boolean"
        }

        if ($member['default'].V)
        {
            $defaultCount++
        }

        if ($member['state'].T -ne 's' -or @('on', 'off') -cnotcontains $member['state'].V)
        {
            & $fail "$where state is not on or off"
        }

        if ($member['stateUpdatedUtc'].T -ne 's' -or -not (Test-ContributorUtcTimestamp -Value $member['stateUpdatedUtc'].V))
        {
            & $fail "$where stateUpdatedUtc is not an ISO 8601 UTC time"
        }

        $snooze = $member['interviewSnoozedUntilUtc']
        if (-not ($snooze.T -eq 'z' -or ($snooze.T -eq 's' -and (Test-ContributorUtcTimestamp -Value $snooze.V))))
        {
            & $fail "$where interviewSnoozedUntilUtc is neither null nor an ISO 8601 UTC time"
        }

        $aliasNode = $member['aliases']
        if ($aliasNode.T -ne 'a' -or $aliasNode.V.Count -gt $limit.Aliases)
        {
            & $fail "$where aliases must be an array of at most $($limit.Aliases) addresses"
        }

        $aliases = [System.Collections.Generic.List[string]]::new()
        foreach ($aliasValue in $aliasNode.V)
        {
            if ($aliasValue.T -ne 's' -or -not (Test-ContributorAlias -Alias $aliasValue.V))
            {
                & $fail "$where has an alias that is not an email address"
            }

            if (-not $allAliases.Add($aliasValue.V))
            {
                & $fail "$where repeats an alias that one entry already holds"
            }

            $aliases.Add($aliasValue.V)
        }

        $areaNode = $member['areas']
        if ($areaNode.T -ne 'o' -or $areaNode.K.Count -gt $limit.Areas)
        {
            & $fail "$where areas must be an object of at most $($limit.Areas) Knowledge areas"
        }

        $areas = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::InvariantCultureIgnoreCase)
        for ($areaIndex = 0; $areaIndex -lt $areaNode.K.Count; $areaIndex++)
        {
            $areaName = $areaNode.K[$areaIndex]
            if (-not (Test-ContributorAreaName -Name $areaName))
            {
                & $fail "$where has a Knowledge area name that breaks the area-name rule"
            }

            if ($areas.Contains($areaName))
            {
                & $fail "$where repeats a Knowledge area name"
            }

            $areaMember = Get-ContributorNodeMember -Node $areaNode.V[$areaIndex] -Allowed @('level', 'updatedUtc') -Where "a Knowledge area of $where"
            if ($areaMember['level'].T -ne 's' -or @('new', 'familiar', 'expert') -cnotcontains $areaMember['level'].V)
            {
                & $fail "$where has a level that is not new, familiar, or expert"
            }

            if ($areaMember['updatedUtc'].T -ne 's' -or -not (Test-ContributorUtcTimestamp -Value $areaMember['updatedUtc'].V))
            {
                & $fail "$where has a Knowledge area updatedUtc that is not an ISO 8601 UTC time"
            }

            $areas[$areaName] = [pscustomobject] @{
                Name       = $areaName
                Level      = $areaMember['level'].V
                UpdatedUtc = $areaMember['updatedUtc'].V
            }
        }

        $entries.Add([pscustomobject] @{
                Id                       = $member['id'].V
                Default                  = [bool] $member['default'].V
                State                    = $member['state'].V
                StateUpdatedUtc          = $member['stateUpdatedUtc'].V
                InterviewSnoozedUntilUtc = if ($snooze.T -eq 's') { $snooze.V } else { $null }
                Aliases                  = $aliases
                Areas                    = $areas
            })
    }

    if ($defaultCount -gt 1)
    {
        & $fail 'more than one entry is marked default'
    }

    return [pscustomobject] @{
        SchemaVersion = 1
        Contributors  = $entries
    }
}

# --- ContributorProfileReader part 4 ---

function Resolve-ContributorProfileLocation
{
    <#
        The location rule of Decision record 0028, shared by every reader and
        writer. Follows ~/.copilot/hooks (USERPROFILE before HOME, as the hook
        launchers do) to its link target; when the target's parent holds
        .copilotatelier.json, that parent is the Canonical target and the profile
        lives in its contributor folder. Otherwise the profile lives under
        LocalApplicationData on this machine only. There is no override.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $UserHome,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $LocalApplicationData
    )

    if ([System.String]::IsNullOrWhiteSpace($UserHome))
    {
        $UserHome = @(
            [System.Environment]::GetEnvironmentVariable('USERPROFILE')
            [System.Environment]::GetEnvironmentVariable('HOME')
            [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        ) | Where-Object -FilterScript { -not [System.String]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    }

    if ([System.String]::IsNullOrWhiteSpace($LocalApplicationData))
    {
        $LocalApplicationData = @(
            [System.Environment]::GetEnvironmentVariable('LOCALAPPDATA')
            [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
            [System.IO.Path]::Combine([string] $UserHome, '.local', 'share')
        ) | Where-Object -FilterScript { -not [System.String]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    }

    $hooksDirectory = [System.IO.Path]::Combine($UserHome, '.copilot', 'hooks')
    $canonicalTarget = $null

    try
    {
        $hooksItem = Get-Item -LiteralPath $hooksDirectory -Force -ErrorAction Stop
        $hooksTarget = $hooksDirectory

        if ($hooksItem.LinkType -eq 'Junction' -or $hooksItem.LinkType -eq 'SymbolicLink')
        {
            $linkTarget = [string] @($hooksItem.Target)[0]
            if (-not [System.IO.Path]::IsPathRooted($linkTarget))
            {
                $linkTarget = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($hooksDirectory), $linkTarget)
            }

            $hooksTarget = [System.IO.Path]::GetFullPath($linkTarget)
        }

        $parent = [System.IO.Path]::GetDirectoryName($hooksTarget.TrimEnd([char[]] @([char]92, [char]47)))
        if ($parent -and [System.IO.File]::Exists([System.IO.Path]::Combine($parent, '.copilotatelier.json')))
        {
            $canonicalTarget = $parent
        }
    }
    catch
    {
        $canonicalTarget = $null
    }

    if ($canonicalTarget)
    {
        $kind = 'canonical'
        $directory = [System.IO.Path]::Combine($canonicalTarget, 'contributor')
    }
    else
    {
        $kind = 'local'
        $directory = [System.IO.Path]::Combine($LocalApplicationData, 'CopilotAtelier', 'contributor')
    }

    $synced = $false
    if ($canonicalTarget)
    {
        foreach ($variable in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')
        {
            $oneDriveRoot = [System.Environment]::GetEnvironmentVariable($variable)
            if (-not [System.String]::IsNullOrWhiteSpace($oneDriveRoot))
            {
                $prefix = $oneDriveRoot.TrimEnd([char[]] @([char]92, [char]47)) + [System.IO.Path]::DirectorySeparatorChar
                if ($canonicalTarget.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))
                {
                    $synced = $true
                }
            }
        }
    }

    return [pscustomobject] @{
        Kind                 = $kind
        Synced               = $synced
        CanonicalTarget      = $canonicalTarget
        ContributorDirectory = $directory
        ProfilePath          = [System.IO.Path]::Combine($directory, 'profile.json')
        LockPath             = [System.IO.Path]::Combine($directory, 'profile.lock')
        RecordPath           = [System.IO.Path]::Combine($directory, 'registration.json')
        HooksDirectory       = $hooksDirectory
        RegistrationPath     = [System.IO.Path]::Combine($hooksDirectory, 'contributor-profile.json')
        RegistrationScript   = [System.IO.Path]::Combine($hooksDirectory, 'scripts', 'Add-FamiliarityContext.ps1')
    }
}

function Test-ContributorPathInsideRepository
{
    <#
        True when any ancestor directory of the path holds a .git directory or
        file, which also covers worktrees and submodules. With -ResolveLinks the
        ancestors of every junction or symbolic link on the way count as well,
        so a link cannot carry a write into a working tree; the writers pass it,
        while the hooks' read stays one attribute-free walk. No Familiarity
        level may land under a git working tree.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $ResolveLinks
    )

    $pending = [System.Collections.Generic.Queue[string]]::new()
    $pending.Enqueue([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path)))
    $resolved = 0
    while ($pending.Count -gt 0)
    {
        $directory = $pending.Dequeue()
        while (-not [System.String]::IsNullOrEmpty($directory))
        {
            $marker = [System.IO.Path]::Combine($directory, '.git')
            if ([System.IO.Directory]::Exists($marker) -or [System.IO.File]::Exists($marker))
            {
                return $true
            }

            # The cap ends a cycle of links.
            if ($ResolveLinks -and $resolved -lt 16)
            {
                $target = Get-ContributorLinkTarget -Path $directory
                if ($target)
                {
                    $resolved++
                    $pending.Enqueue($target)
                }
            }

            $parent = [System.IO.Path]::GetDirectoryName($directory)
            if ($parent -eq $directory)
            {
                break
            }

            $directory = $parent
        }
    }

    return $false
}

function Get-ContributorLinkTarget
{
    <#
        The full target path of a directory that is a junction or a symbolic
        link, else $null. The reparse-point attribute is checked first, so an
        ordinary directory costs one attribute query; a cloud placeholder is a
        reparse point without a link target and yields $null.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    try
    {
        $info = [System.IO.DirectoryInfo]::new($Path)
        if (-not $info.Exists -or -not ($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint))
        {
            return $null
        }

        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.LinkType -ne 'Junction' -and $item.LinkType -ne 'SymbolicLink')
        {
            return $null
        }

        $target = [string] @($item.Target)[0]
        if ([System.String]::IsNullOrWhiteSpace($target))
        {
            return $null
        }

        if (-not [System.IO.Path]::IsPathRooted($target))
        {
            $target = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), $target)
        }

        return [System.IO.Path]::GetFullPath($target)
    }
    catch
    {
        return $null
    }
}

function Test-ContributorFileLocal
{
    <#
        False for a cloud placeholder whose data is not on this machine: the
        offline, recall-on-open, or recall-on-data-access attribute. Reading the
        attributes never downloads the file; reading its data would.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Int64]
        $Attributes
    )

    $remote = 0x1000 -bor 0x40000 -bor 0x400000
    return (($Attributes -band $remote) -eq 0)
}

function Get-ContributorReasonCode
{
    <#
        Maps an exception from the parser or the validator to its reason code.
        The code is the fixed prefix of the message, so wrapping across call
        boundaries cannot change it.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Exception]
        $Exception
    )

    $current = $Exception
    while ($null -ne $current)
    {
        $match = [System.Text.RegularExpressions.Regex]::Match([string] $current.Message, '\A(invalid-json|invalid-schema|unsupported-schema):')
        if ($match.Success)
        {
            return $match.Groups[1].Value
        }

        $current = $current.InnerException
    }

    return 'read-error'
}

function Read-ContributorProfile
{
    <#
        Reads and validates the profile at the location, or names exactly one
        reason code: inside-repository, not-local, too-large, invalid-json,
        invalid-schema, unsupported-schema, or read-error. A missing file is not
        an error. The data is read only after the path, attribute, and size
        checks pass, so a cloud placeholder is never downloaded.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Location
    )

    try
    {
        if (Test-ContributorPathInsideRepository -Path $Location.ProfilePath)
        {
            return [pscustomobject] @{
                Exists     = [System.IO.File]::Exists($Location.ProfilePath)
                ReasonCode = 'inside-repository'
                Detail     = 'The profile path lies inside a git working tree.'
                Profile    = $null
            }
        }
    }
    catch
    {
        return [pscustomobject] @{
            Exists     = $false
            ReasonCode = 'read-error'
            Detail     = 'The profile path could not be checked: ' + $_.Exception.GetType().Name
            Profile    = $null
        }
    }

    return Read-ContributorProfileData -Path $Location.ProfilePath
}

function Read-ContributorProfileData
{
    <#
        Reads and validates one schema 1 file at any path, without the
        repository check: Import reads an exported file from wherever the
        contributor keeps it, and only writes are confined.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $result = [pscustomobject] @{
        Exists     = $false
        ReasonCode = $null
        Detail     = $null
        Profile    = $null
    }

    try
    {
        $file = [System.IO.FileInfo]::new($Path)
        if (-not $file.Exists)
        {
            return $result
        }

        $result.Exists = $true
        if (-not (Test-ContributorFileLocal -Attributes ([System.Int64] $file.Attributes)))
        {
            $result.ReasonCode = 'not-local'
            $result.Detail = 'The profile is a cloud placeholder whose data is not on this machine.'
            return $result
        }

        $limit = (Get-ContributorProfileLimit).ProfileBytes
        if ($file.Length -gt $limit)
        {
            $result.ReasonCode = 'too-large'
            $result.Detail = "The profile is larger than $limit bytes."
            return $result
        }

        $buffer = New-Object -TypeName 'System.Byte[]' -ArgumentList ($limit + 1)
        $count = 0
        $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try
        {
            while ($count -le $limit)
            {
                $read = $stream.Read($buffer, $count, $buffer.Length - $count)
                if ($read -le 0)
                {
                    break
                }

                $count += $read
            }
        }
        finally
        {
            $stream.Dispose()
        }

        if ($count -gt $limit)
        {
            $result.ReasonCode = 'too-large'
            $result.Detail = "The profile is larger than $limit bytes."
            return $result
        }

        $offset = 0
        if ($count -ge 3 -and $buffer[0] -eq 0xEF -and $buffer[1] -eq 0xBB -and $buffer[2] -eq 0xBF)
        {
            $offset = 3
        }

        try
        {
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($buffer, $offset, $count - $offset)
        }
        catch
        {
            $result.ReasonCode = 'invalid-json'
            $result.Detail = 'The profile is not valid UTF-8.'
            return $result
        }

        try
        {
            $node = ConvertFrom-ContributorJson -Text $text -MaximumDepth (Get-ContributorProfileLimit).JsonDepth
            $result.Profile = ConvertTo-ContributorProfileModel -Node $node
        }
        catch
        {
            $result.Profile = $null
            $result.ReasonCode = Get-ContributorReasonCode -Exception $_.Exception
            $result.Detail = [string] $_.Exception.Message
            if ($result.ReasonCode -eq 'read-error')
            {
                $result.ReasonCode = 'invalid-schema'
            }
        }
    }
    catch
    {
        $result.Profile = $null
        $result.ReasonCode = 'read-error'
        $result.Detail = 'The profile could not be read: ' + $_.Exception.GetType().Name
    }

    return $result
}

# --- ContributorProfileReader part 5 ---

function Get-ContributorKnowledgeArea
{
    <#
        Reads the Knowledge areas a workspace declares: only the
        "## Knowledge areas" section of .memory-bank/projectbrief.md, at most its
        first 64 KB, and the first 16 top-level bullets that pass the area-name
        rule, without duplicates. Invalid bullets are ignored and never repeated.
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $WorkspacePath
    )

    $declared = [System.Collections.Generic.List[string]]::new()
    if ([System.String]::IsNullOrWhiteSpace($WorkspacePath))
    {
        return , $declared.ToArray()
    }

    $limit = Get-ContributorProfileLimit
    try
    {
        $briefPath = [System.IO.Path]::Combine($WorkspacePath, '.memory-bank', 'projectbrief.md')
        if (-not [System.IO.File]::Exists($briefPath))
        {
            return , $declared.ToArray()
        }

        $buffer = New-Object -TypeName 'System.Byte[]' -ArgumentList $limit.DeclarationBytes
        $count = 0
        $stream = [System.IO.FileStream]::new($briefPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try
        {
            $truncated = $stream.Length -gt $limit.DeclarationBytes
            while ($count -lt $buffer.Length)
            {
                $read = $stream.Read($buffer, $count, $buffer.Length - $count)
                if ($read -le 0)
                {
                    break
                }

                $count += $read
            }
        }
        finally
        {
            $stream.Dispose()
        }

        $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $count)
        if ($truncated)
        {
            # A line cut at the byte limit could still pass the rule as a
            # different name, so the partial last line is dropped.
            $text = $text.Substring(0, [System.Math]::Max(0, $text.LastIndexOf([char]10)))
        }
    }
    catch
    {
        return , $declared.ToArray()
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
    $inSection = $false
    foreach ($line in ($text -split '\r?\n'))
    {
        if ($line -match '\A##[ \t]+Knowledge areas[ \t]*\z')
        {
            $inSection = $true
            continue
        }

        if (-not $inSection)
        {
            continue
        }

        if ($line -match '\A#{1,2}(?!#)')
        {
            break
        }

        $bullet = [System.Text.RegularExpressions.Regex]::Match($line, '\A[-*+][ \t]+(.*)\z')
        if (-not $bullet.Success)
        {
            continue
        }

        $name = ConvertTo-ContributorAreaName -Name $bullet.Groups[1].Value
        if ($null -ne $name -and $seen.Add($name))
        {
            $declared.Add($name)
            if ($declared.Count -ge $limit.DeclaredAreas)
            {
                break
            }
        }
    }

    return , $declared.ToArray()
}

function Get-ContributorGitEmail
{
    <#
        The identity key: git config --get user.email, run in the workspace so
        includeIf applies. The path is the process working directory, never an
        argument, so a hostile path cannot inject options. Prompts are disabled,
        and git is killed after the timeout. Returns $null on any failure; the
        address is a lookup key, not proof, and never reaches any hook output.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $WorkingDirectory,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $GitExecutable,

        [Parameter()]
        [System.Int32]
        $TimeoutMilliseconds = 2000
    )

    if ([System.String]::IsNullOrWhiteSpace($WorkingDirectory) -or -not [System.IO.Directory]::Exists($WorkingDirectory))
    {
        return $null
    }

    if ([System.String]::IsNullOrWhiteSpace($GitExecutable))
    {
        $command = Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command)
        {
            return $null
        }

        $GitExecutable = $command.Source
    }

    $process = $null
    try
    {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($GitExecutable)
        $startInfo.Arguments = 'config --get user.email'
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $startInfo.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
        $startInfo.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'

        $process = [System.Diagnostics.Process]::Start($startInfo)
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutMilliseconds))
        {
            try
            {
                # A git shim can start the real git, so end the whole tree where
                # .NET can; Windows PowerShell 5.1 can only end the process.
                $process.Kill($true)
            }
            catch
            {
                try
                {
                    $process.Kill()
                }
                catch
                {
                    Write-Debug -Message 'git had already exited.'
                }
            }

            return $null
        }

        $process.WaitForExit()
        if ($process.ExitCode -ne 0)
        {
            return $null
        }

        $email = $output.Result.Trim()
        if ([System.String]::IsNullOrEmpty($email))
        {
            return $null
        }

        return $email
    }
    catch
    {
        return $null
    }
    finally
    {
        if ($null -ne $process)
        {
            $process.Dispose()
        }
    }
}

function Select-ContributorEntry
{
    <#
        The identity rule: the entry whose alias matches the email, case
        insensitively; else the only entry; else the entry marked default; else
        none. Reason is alias, single, default, or none.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ContributorProfile,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Email
    )

    if (-not [System.String]::IsNullOrEmpty($Email))
    {
        foreach ($entry in $ContributorProfile.Contributors)
        {
            foreach ($alias in $entry.Aliases)
            {
                if ([System.String]::Equals($alias, $Email, [System.StringComparison]::OrdinalIgnoreCase))
                {
                    return [pscustomobject] @{ Entry = $entry; Reason = 'alias' }
                }
            }
        }
    }

    if ($ContributorProfile.Contributors.Count -eq 1)
    {
        return [pscustomobject] @{ Entry = $ContributorProfile.Contributors[0]; Reason = 'single' }
    }

    foreach ($entry in $ContributorProfile.Contributors)
    {
        if ($entry.Default)
        {
            return [pscustomobject] @{ Entry = $entry; Reason = 'default' }
        }
    }

    return [pscustomobject] @{ Entry = $null; Reason = 'none' }
}

# --- ContributorProfileReader part 6 ---

function Get-ContributorCalibration
{
    <#
        The calibration step shared by the SessionStart and PostToolUse hooks and
        by Get-CopilotAtelierContributorProfile. State is one of:
        none        no workspace, or no declared Knowledge areas; nothing is read
        unrated     declared areas, and no profile, no selected entry, or no match
        levels      the selected entry is on and rates at least one declared area
        off         the selected entry opted out
        unreadable  ReasonCode names why, including timeout after the step cap
        Without declared areas the profile is not read and git does not run.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $WorkspacePath,

        [Parameter()]
        [AllowNull()]
        [System.Object]
        $Location,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $GitExecutable,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipGitForSingleEntry,

        [Parameter()]
        [System.Int32]
        $TimeoutMilliseconds = 3000
    )

    $result = [pscustomobject] @{
        State         = 'none'
        ReasonCode    = $null
        Detail        = $null
        Declared      = [System.String[]] @()
        Levels        = [System.Object[]] @()
        UnratedCount  = 0
        Selection     = 'none'
        Entry         = $null
        ProfileExists = $false
        Location      = $Location
    }

    if ([System.String]::IsNullOrWhiteSpace($WorkspacePath))
    {
        return $result
    }

    # The cap covers the declaration read too, so a hostile projectbrief.md cannot stretch the step.
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $timedOut = {
        if ($watch.ElapsedMilliseconds -gt $TimeoutMilliseconds)
        {
            $result.State = 'unreadable'
            $result.ReasonCode = 'timeout'
            $result.Detail = "The calibration step took longer than $TimeoutMilliseconds ms."
            $result.Levels = [System.Object[]] @()
            return $true
        }

        return $false
    }

    $result.Declared = Get-ContributorKnowledgeArea -WorkspacePath $WorkspacePath
    if ($result.Declared.Count -eq 0)
    {
        return $result
    }

    if (& $timedOut)
    {
        return $result
    }

    if ($null -eq $Location)
    {
        $Location = Resolve-ContributorProfileLocation
        $result.Location = $Location
    }

    $read = Read-ContributorProfile -Location $Location
    $result.ProfileExists = $read.Exists
    if (& $timedOut)
    {
        return $result
    }

    if ($read.ReasonCode)
    {
        $result.State = 'unreadable'
        $result.ReasonCode = $read.ReasonCode
        $result.Detail = $read.Detail
        return $result
    }

    $result.UnratedCount = $result.Declared.Count
    if (-not $read.Exists)
    {
        $result.State = 'unrated'
        return $result
    }

    $email = $null
    if (-not ($SkipGitForSingleEntry -and $read.Profile.Contributors.Count -eq 1))
    {
        # With one entry every outcome of the identity rule selects it, so a hook
        # can skip git there; a diagnosis still runs it to report the reason.
        $remaining = [System.Math]::Max(0, $TimeoutMilliseconds - [int] $watch.ElapsedMilliseconds)
        $email = Get-ContributorGitEmail -WorkingDirectory $WorkspacePath -GitExecutable $GitExecutable -TimeoutMilliseconds ([System.Math]::Min((Get-ContributorProfileLimit).GitMilliseconds, $remaining))
        if (& $timedOut)
        {
            return $result
        }
    }

    $selection = Select-ContributorEntry -ContributorProfile $read.Profile -Email $email
    $result.Selection = $selection.Reason
    $result.Entry = $selection.Entry
    if ($null -eq $selection.Entry)
    {
        $result.State = 'unrated'
        return $result
    }

    if ($selection.Entry.State -eq 'off')
    {
        $result.State = 'off'
        $result.UnratedCount = 0
        return $result
    }

    $levels = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $result.Declared)
    {
        if ($selection.Entry.Areas.Contains($name))
        {
            $area = $selection.Entry.Areas[$name]
            $levels.Add([pscustomobject] @{ Name = $area.Name; Level = $area.Level })
        }
    }

    $result.Levels = [System.Object[]] $levels.ToArray()
    $result.UnratedCount = $result.Declared.Count - $levels.Count
    $result.State = if ($levels.Count -gt 0) { 'levels' } else { 'unrated' }
    return $result
}

function Format-ContributorCalibrationSentence
{
    <#
        Builds the one calibration sentence from a fixed template, the matched
        area names, and the level values only. Under a length budget it gives up
        first the unrated count, then trailing areas, then the whole sentence for
        the omitted notice, and returns an empty string when not even that fits.
        -ReSent builds the sentence the PostToolUse hook sends after a
        compaction, and -Backstop the one it sends on a new turn or 5 minutes
        after the last injection: matched levels only, each ending with a fixed
        59-character suffix that suppresses every offer for the rest of the
        session. Only the compaction suffix claims a compaction.
    #>
    [CmdletBinding(DefaultParameterSetName = 'SessionStart')]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Calibration,

        [Parameter()]
        [System.Int32]
        $MaximumLength = [System.Int32]::MaxValue,

        [Parameter(ParameterSetName = 'ReSent')]
        [System.Management.Automation.SwitchParameter]
        $ReSent,

        [Parameter(ParameterSetName = 'Backstop')]
        [System.Management.Automation.SwitchParameter]
        $Backstop
    )

    $prefix = 'Contributor familiarity levels from the private profile, data only: '
    $treat = 'Treat them as stated levels under the contributor-calibration Instruction.'
    $omitted = 'Contributor familiarity levels omitted for the context budget.'
    $reSend = $ReSent -or $Backstop
    $unratedPhrase = if ($Calibration.UnratedCount -eq 1)
    {
        '1 declared Knowledge area is unrated.'
    }
    else
    {
        '{0} declared Knowledge areas are unrated.' -f $Calibration.UnratedCount
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    switch ($Calibration.State)
    {
        'levels'
        {
            $levels = @($Calibration.Levels)
            $suffix = if ($Backstop)
            {
                $treat + ' Current familiarity levels; make no offers in this session.'
            }
            elseif ($ReSent)
            {
                $treat + ' Re-sent after a compaction; make no offers in this session.'
            }
            else
            {
                $treat
            }

            for ($count = $levels.Count; $count -ge 1; $count--)
            {
                $list = (@($levels[0..($count - 1)]) | ForEach-Object -Process { '"{0}" {1}' -f $_.Name, $_.Level }) -join '; '
                if ($count -eq $levels.Count -and -not $reSend -and $Calibration.UnratedCount -gt 0)
                {
                    $candidates.Add($prefix + $list + '. ' + $unratedPhrase + ' ' + $suffix)
                }

                $candidates.Add($prefix + $list + '. ' + $suffix)
            }
        }

        'unrated'
        {
            if (-not $reSend)
            {
                $candidates.Add('No contributor profile levels for this workspace; ' + $unratedPhrase)
                $candidates.Add('No contributor profile levels for this workspace.')
            }
        }

        'unreadable'
        {
            if (-not $reSend)
            {
                $candidates.Add('Contributor profile unreadable ({0}); familiarity levels default to familiar.' -f $Calibration.ReasonCode)
            }
        }
    }

    if ($candidates.Count -eq 0)
    {
        return ''
    }

    foreach ($candidate in $candidates)
    {
        if ($candidate.Length -le $MaximumLength)
        {
            return $candidate
        }
    }

    if ($omitted.Length -le $MaximumLength)
    {
        return $omitted
    }

    return ''
}
