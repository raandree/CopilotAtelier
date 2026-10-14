<#
.SYNOPSIS
    Append-only, hash-chained ledger service for the specification completion
    workflow.
.DESCRIPTION
    The /complete-specifications controller may not be trusted to keep its own
    audit trail: it is the component under audit. This script is the pinned
    appender the containment profile names. It owns the ledger sink and the
    protected chain head, and it is the only writer of both. Callers reach it
    over an authenticated local named pipe and can only append; they cannot
    rewrite, reorder, truncate, or delete what is already stored.

    Every record is assigned a monotonic sequence, the previous record's digest,
    and its own digest over a canonical serialization. A record is flushed to
    disk before the append is acknowledged, so an acknowledged record always
    survives a crash. The reverse does not hold: a crash, a lock, or an I/O
    error between the sink flush and the head write can leave a record that is
    stored but was never acknowledged. That is why the sequence is spent when
    the record becomes durable rather than when it is acknowledged, why a head
    that cannot be written stops the service, and why a restart refuses to serve
    unless the head names the last record or the one before it.

    Verification recomputes the whole chain from genesis and compares the final
    digest with the protected head, so a rewritten body, a removed line, a
    reordered line, or an edited head all fail.

    This script stores evidence. It does not create the operating-system
    boundary that keeps the sink out of the controller's writable set; that is
    filesystem policy, measured separately by Test-RunContainment.ps1.
.PARAMETER Serve
    Runs the appender service. This is the only mode that writes. Windows only:
    the pipe cannot be restricted or authenticated anywhere else.
.PARAMETER Append
    Sends one record to a running appender and returns its assigned sequence.
    The server is authenticated before the record is sent, and the
    acknowledgement is checked against the ledger before success is reported.
.PARAMETER Seal
    Appends a final record and refuses every later append. Sealing is a server
    decision carried by the request, not by the record's own type.
.PARAMETER Validate
    Recomputes the chain from genesis and compares it with the protected head.
    Reads only; safe to run from any identity that can read the sink. Bound to
    a containment profile with -ProfilePath and -ProfileSha256, or given free
    paths, which it reports as unbound.
.PARAMETER PipeName
    Local named pipe the service listens on and clients connect to.
.PARAMETER SinkPath
    Append-only JSONL ledger. One record per line.
.PARAMETER ChainHeadPath
    Protected head naming the newest sequence and digest.
.PARAMETER RecordJson
    One record as JSON. Exactly type, runId, utc, and data; nothing else. Keys
    are case-sensitive, utc is an ISO-8601 instant in UTC, and every number is
    a JSON integer within +-(2^53-1).
.PARAMETER ProfilePath
    Containment profile naming the ledger. Its ledgerSink and chainHead are the
    only paths the bound check reads, and its ledgerAppender must be this file.
.PARAMETER ProfileSha256
    Lowercase 64-character hexadecimal SHA-256 of the profile, computed by the
    caller. It is the trust anchor and must match the bytes that are parsed.
.PARAMETER RequireSealed
    Additionally requires the chain's last record to be the seal record and the
    chain head to say so.
.PARAMETER ExpectedServerIdentity
    Identity the client requires the pipe to belong to. Defaults to the
    principal that would own objects this client creates.
.PARAMETER IdleTimeoutSeconds
    Stops the service after this long without a connection.
.PARAMETER AllowedIdentity
    Windows identity permitted to open the pipe, in addition to the appender's
    own account. Defaults to the appender's account alone.
.EXAMPLE
    Invoke-LedgerAppender.ps1 -Serve -PipeName ca-ledger-run1 -SinkPath D:\ledger\run1.jsonl -ChainHeadPath D:\ledger\run1.head.json
.EXAMPLE
    Invoke-LedgerAppender.ps1 -Append -PipeName ca-ledger-run1 -RecordJson '{"type":"Baseline","runId":"run1","utc":"2026-09-02T22:00:00Z","data":{}}' -SinkPath D:\ledger\run1.jsonl -ChainHeadPath D:\ledger\run1.head.json
.EXAMPLE
    Invoke-LedgerAppender.ps1 -Validate -ProfilePath D:\profile\containment.json -ProfileSha256 $digest -RequireSealed
.EXAMPLE
    Invoke-LedgerAppender.ps1 -Validate -SinkPath D:\ledger\run1.jsonl -ChainHeadPath D:\ledger\run1.head.json
.NOTES
    Exit codes: 0 success, 2 refusal or verification failure. A refusal is
    always a hard failure; the caller must never treat it as a warning.
#>

[CmdletBinding(DefaultParameterSetName = 'Validate')]
[OutputType([string])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'The mode switches exist to select a parameter set; the dispatch below reads $PSCmdlet.ParameterSetName.')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Serve')]
    [switch]$Serve,

    [Parameter(Mandatory, ParameterSetName = 'Append')]
    [switch]$Append,

    [Parameter(Mandatory, ParameterSetName = 'Seal')]
    [switch]$Seal,

    [Parameter(Mandatory, ParameterSetName = 'Validate')]
    [Parameter(Mandatory, ParameterSetName = 'ValidateBound')]
    [switch]$Validate,

    [Parameter(Mandatory, ParameterSetName = 'ValidateBound')]
    [ValidateNotNullOrEmpty()]
    [string]$ProfilePath,

    [Parameter(Mandatory, ParameterSetName = 'ValidateBound')]
    [ValidateNotNullOrEmpty()]
    [string]$ProfileSha256,

    [Parameter(ParameterSetName = 'Validate')]
    [Parameter(ParameterSetName = 'ValidateBound')]
    [switch]$RequireSealed,

    [Parameter(Mandatory, ParameterSetName = 'Serve')]
    [Parameter(Mandatory, ParameterSetName = 'Append')]
    [Parameter(Mandatory, ParameterSetName = 'Seal')]
    [ValidateNotNullOrEmpty()]
    [string]$PipeName,

    [Parameter(Mandatory, ParameterSetName = 'Serve')]
    [Parameter(Mandatory, ParameterSetName = 'Append')]
    [Parameter(Mandatory, ParameterSetName = 'Seal')]
    [Parameter(Mandatory, ParameterSetName = 'Validate')]
    [ValidateNotNullOrEmpty()]
    [string]$SinkPath,

    [Parameter(Mandatory, ParameterSetName = 'Serve')]
    [Parameter(Mandatory, ParameterSetName = 'Append')]
    [Parameter(Mandatory, ParameterSetName = 'Seal')]
    [Parameter(Mandatory, ParameterSetName = 'Validate')]
    [ValidateNotNullOrEmpty()]
    [string]$ChainHeadPath,

    [Parameter(Mandatory, ParameterSetName = 'Append')]
    [Parameter(Mandatory, ParameterSetName = 'Seal')]
    [ValidateNotNullOrEmpty()]
    [string]$RecordJson,

    [Parameter(ParameterSetName = 'Append')]
    [Parameter(ParameterSetName = 'Seal')]
    [AllowEmptyString()]
    [string]$ExpectedServerIdentity,

    [Parameter(ParameterSetName = 'Serve')]
    [ValidateRange(1, 86400)]
    [int]$IdleTimeoutSeconds = 3600,

    [Parameter(ParameterSetName = 'Serve')]
    [AllowEmptyString()]
    [string]$AllowedIdentity
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

trap {
    <#
        Every mode reports a refusal the same way: one line on standard error
        and exit 2. An unexpected failure must not become an exit code of its
        own or a stack trace on the stream a caller parses, so anything that
        escapes a local handler lands here. Explicit exits are flow control,
        not errors, and pass through untouched.
    #>
    Write-Refusal -Message $_.Exception.GetBaseException().Message
    exit 2
}

$script:GenesisHash = '0' * 64
$script:RequiredField = @('type', 'runId', 'utc', 'data')
$script:RequestField = @('operation', 'record')
$script:Operation = @('Append', 'Seal')
$script:StoredField = @('data', 'prevSha256', 'recordSha256', 'runId', 'sequence', 'type', 'utc')
$script:HeadField = @('recordSha256', 'sealed', 'sequence', 'updatedUtc')

# Every name that arrives from outside is matched against these sets, never with
# -ceq or -cin. PowerShell's case-sensitive operators are still culture-ordered:
# a character the collation ignores, such as a zero-width space, compares equal
# to nothing at all, so 'ty<U+200B>pe' -ceq 'type' is $true and a closed grammar
# is only closed up to culture equivalence.
$script:RequiredFieldSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:RequiredField, [System.StringComparer]::Ordinal)
$script:RequestFieldSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:RequestField, [System.StringComparer]::Ordinal)
$script:OperationSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:Operation, [System.StringComparer]::Ordinal)
$script:StoredFieldSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:StoredField, [System.StringComparer]::Ordinal)
$script:HeadFieldSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:HeadField, [System.StringComparer]::Ordinal)

$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:StrictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

# \A and \z, never ^ and $: $ also matches in front of a final line feed, so an
# anchored-looking pattern would accept a digest or an instant with one appended.
$script:DigestPattern = '\A[0-9a-f]{64}\z'
$script:UtcPattern = '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z\z'
$script:IntegerPattern = '\A-?(0|[1-9][0-9]*)\z'
$script:SidPattern = '\AS-1-[0-9-]+\z'

# The shape is not the instant: 2026-99-99T99:99:99Z has the shape. .NET parses
# at most seven fractional digits, so a longer fraction is checked for shape and
# parsed with the fraction cut to seven. The value itself is never rewritten.
$script:UtcFormat = [string[]]@("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'")
$script:UtcStyle = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
$script:LongFractionPattern = '\A(?<kept>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{7})[0-9]{1,2}Z\z'

$script:SafeInteger = 9007199254740991
$script:MaxRequestLength = 262144

# A refusal line is read by the controller, which is a model, and its text can
# come from whoever answered the pipe. Runes in these categories are replaced:
# a carriage return or line feed would forge a second line, an escape would
# drive a terminal, a bidirectional override would reorder what is shown, and a
# Unicode tag character would ride along invisibly. The enumeration is by rune,
# not by UTF-16 unit, because \p{Cf} on UTF-16 misses the tag block entirely.
$script:RefusalCategory = [System.Collections.Generic.HashSet[System.Globalization.UnicodeCategory]]::new(
    [System.Globalization.UnicodeCategory[]]@(
        [System.Globalization.UnicodeCategory]::Control
        [System.Globalization.UnicodeCategory]::Format
        [System.Globalization.UnicodeCategory]::LineSeparator
        [System.Globalization.UnicodeCategory]::ParagraphSeparator
        [System.Globalization.UnicodeCategory]::Surrogate
        [System.Globalization.UnicodeCategory]::OtherNotAssigned
        [System.Globalization.UnicodeCategory]::PrivateUse
    ))
$script:RefusalLength = 200

$script:OnWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'
$script:FatalError = ''
$script:JsonOption = [System.Text.Json.JsonDocumentOptions]::new()
$script:JsonOption.MaxDepth = 32

function Test-OrdinalEqual {
    <#
        The only string equality this script uses on text from outside it.
        [string]::Equals with StringComparison.Ordinal compares code units, so
        no character is ignorable and no culture can make two different names
        the same name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Left,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Right
    )

    return [string]::Equals($Left, $Right, [System.StringComparison]::Ordinal)
}

function Test-UtcInstant {
    <#
        An ISO-8601 instant in UTC, and a date that exists: the pattern alone
        accepts the thirtieth of February and the twenty-fourth hour. Parsing is
        invariant and exact, so nothing is inferred from the host's culture, and
        the caller keeps the original text to store.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value -or $Value -cnotmatch $script:UtcPattern) {
        return $false
    }

    $candidate = $Value
    $long = [regex]::Match($Value, $script:LongFractionPattern)
    if ($long.Success) {
        $candidate = $long.Groups['kept'].Value + 'Z'
    }

    $parsed = [datetimeoffset]::MinValue
    return [System.DateTimeOffset]::TryParseExact($candidate, $script:UtcFormat,
        [System.Globalization.CultureInfo]::InvariantCulture, $script:UtcStyle, [ref]$parsed)
}

function Format-RefusalText {
    <#
        Makes any text safe to put on one line of standard error: every rune
        whose category can break a line, drive a terminal, reorder what is
        shown or hide itself becomes a question mark, everything else stays,
        and the result is cut at a fixed length. The cut counts UTF-16 units
        but moves whole runes, so a surrogate pair is never split in half.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }

    $builder = [System.Text.StringBuilder]::new()
    $cut = $false

    foreach ($rune in $Text.EnumerateRunes()) {
        $piece = if ($script:RefusalCategory.Contains([System.Text.Rune]::GetUnicodeCategory($rune))) {
            '?'
        } else {
            $rune.ToString()
        }

        if ($builder.Length + $piece.Length -gt $script:RefusalLength) {
            $cut = $true
            break
        }

        $null = $builder.Append($piece)
    }

    if ($cut) {
        $null = $builder.Append('...')
    }

    return $builder.ToString()
}

function Write-Refusal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    [Console]::Error.WriteLine("Ledger appender refused: $(Format-RefusalText -Text $Message)")
}

function ConvertFrom-JsonText {
    <#
        System.Text.Json is the only parser used here. ConvertFrom-Json coerces
        an ISO-8601 string into a DateTime, a large integer into a BigInteger,
        and folds two keys that differ only in case into one, so the preimage
        would depend on the parser, the host culture and the PowerShell version
        instead of on the bytes the caller actually sent.
    #>
    [CmdletBinding()]
    [OutputType([System.Text.Json.JsonDocument])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    return [System.Text.Json.JsonDocument]::Parse($Text, $script:JsonOption)
}

function ConvertTo-JsonStringLiteral {
    <#
        JsonEncodedText is the non-generic escaper: PowerShell cannot resolve
        the generic JsonSerializer.Serialize<T> overload, and ConvertTo-Json
        has changed its escaping between releases, which would silently break
        every digest written by an older version.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    return '"' + [System.Text.Json.JsonEncodedText]::Encode($Value).ToString() + '"'
}

function ConvertTo-CanonicalNumber {
    <#
        Only a JSON integer token inside +-(2^53-1) is representable identically
        by every reader the evidence may pass through. A fraction, an exponent,
        or a wider integer is refused at append time rather than stored in a
        form that re-reads as a different value and breaks its own digest.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Raw
    )

    if ($Raw -cnotmatch $script:IntegerPattern) {
        throw "number '$Raw' is not a JSON integer token"
    }

    $value = [long]0
    $parsed = [long]::TryParse($Raw, [System.Globalization.NumberStyles]::AllowLeadingSign,
        [cultureinfo]::InvariantCulture, [ref]$value)

    if (-not $parsed -or $value -gt $script:SafeInteger -or $value -lt (-$script:SafeInteger)) {
        throw "number '$Raw' is outside the supported range of +-(2^53-1)"
    }

    return $value.ToString([cultureinfo]::InvariantCulture)
}

function Get-CanonicalMember {
    <#
        Returns the members of a JSON object as name -> canonical value text.
        The dictionary compares names with ordinal case sensitivity, because
        'a' and 'A' are two different JSON keys and must stay two.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Element
    )

    $member = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)

    foreach ($property in $Element.EnumerateObject()) {
        if ($member.Contains($property.Name)) {
            # System.Text.Json keeps both members of a duplicate key and every
            # reader picks one of them, so the text a reader shows and the text
            # a digest covers would differ. There is no safe resolution.
            throw "duplicate key '$($property.Name)'"
        }

        $member[$property.Name] = ConvertTo-CanonicalJson -Element $property.Value
    }

    return $member
}

function Join-CanonicalMember {
    <#
        [string]::CompareOrdinal, not Sort-Object: the default comparison is
        culture-ordered, so the same record would serialize differently under
        da-DK than under en-US and fail its own digest on another host.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Member
    )

    $name = [string[]]@($Member.Keys)
    [array]::Sort($name, [System.StringComparer]::Ordinal)

    $pair = foreach ($key in $name) {
        (ConvertTo-JsonStringLiteral -Value $key) + ':' + $Member[$key]
    }

    return '{' + ($pair -join ',') + '}'
}

function ConvertTo-CanonicalJson {
    <#
        A digest is only meaningful over bytes both sides derive the same way,
        so the canonical form is a pure function of the parsed data: keys sorted
        ordinal at every depth, no insignificant whitespace, one escaping, one
        number format, and no type coercion of any kind.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Element
    )

    switch ($Element.ValueKind) {
        ([System.Text.Json.JsonValueKind]::Object) {
            return Join-CanonicalMember -Member (Get-CanonicalMember -Element $Element)
        }

        ([System.Text.Json.JsonValueKind]::Array) {
            $item = foreach ($child in $Element.EnumerateArray()) {
                ConvertTo-CanonicalJson -Element $child
            }

            return '[' + ($item -join ',') + ']'
        }

        ([System.Text.Json.JsonValueKind]::String) {
            return ConvertTo-JsonStringLiteral -Value $Element.GetString()
        }

        ([System.Text.Json.JsonValueKind]::Number) {
            return ConvertTo-CanonicalNumber -Raw $Element.GetRawText()
        }

        ([System.Text.Json.JsonValueKind]::True) {
            return 'true'
        }

        ([System.Text.Json.JsonValueKind]::False) {
            return 'false'
        }

        ([System.Text.Json.JsonValueKind]::Null) {
            return 'null'
        }
    }

    throw "unsupported JSON value kind '$($Element.ValueKind)'"
}

function Get-Sha256HexFromByte {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Byte
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.Convert]::ToHexString($sha256.ComputeHash($Byte)).ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-Sha256Hex {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($script:Utf8.GetBytes($Text))
        return [System.Convert]::ToHexString($hash).ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function New-StoredRecord {
    <#
        The stored line is the canonical serialization of the caller's record
        with sequence, prevSha256 and recordSha256 added, so every byte on disk
        is covered by the chain except the digest itself, which cannot cover
        itself. Key order is the ordinal order of the names, which puts them at
        data, prevSha256, recordSha256, runId, sequence, type, utc.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory record; the caller decides when anything is written.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Record,

        [Parameter(Mandatory)]
        [int]$Sequence,

        [Parameter(Mandatory)]
        [string]$PreviousHash
    )

    $member = Get-CanonicalMember -Element $Record
    $member['sequence'] = ([long]$Sequence).ToString([cultureinfo]::InvariantCulture)
    $member['prevSha256'] = ConvertTo-JsonStringLiteral -Value $PreviousHash

    $preimage = Join-CanonicalMember -Member $member
    $digest = Get-Sha256Hex -Text $preimage

    $member['recordSha256'] = ConvertTo-JsonStringLiteral -Value $digest

    return @{
        Line = Join-CanonicalMember -Member $member
        RecordSha256 = $digest
        Preimage = $preimage
    }
}

function Test-RecordSchema {
    <#
        The record schema is closed. An unknown field is refused rather than
        ignored, so a caller cannot smuggle a command, path, or authorization
        claim through the ledger into anything that later reads it. Field names
        are compared case-sensitively, because 'Type' is not 'type'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Record
    )

    if ($Record.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        return 'record must be a JSON object'
    }

    $present = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)

    foreach ($property in $Record.EnumerateObject()) {
        if (-not $script:RequiredFieldSet.Contains($property.Name)) {
            return "unknown field '$($property.Name)'"
        }

        if ($present.Contains($property.Name)) {
            return "duplicate field '$($property.Name)'"
        }

        $present[$property.Name] = $property.Value
    }

    foreach ($required in $script:RequiredField) {
        if (-not $present.Contains($required)) {
            return "missing required field '$required'"
        }
    }

    foreach ($name in @('type', 'runId', 'utc')) {
        $value = [System.Text.Json.JsonElement]$present[$name]

        if ($value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
            return "field '$name' must be a string"
        }

        if ([string]::IsNullOrWhiteSpace($value.GetString())) {
            return "field '$name' must be a non-empty string"
        }
    }

    if (([System.Text.Json.JsonElement]$present['data']).ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        return "field 'data' must be a JSON object"
    }

    if (-not (Test-UtcInstant -Value ([System.Text.Json.JsonElement]$present['utc']).GetString())) {
        return "field 'utc' must be an ISO-8601 instant in UTC, for example 2026-09-02T22:00:00Z"
    }

    try {
        $null = ConvertTo-CanonicalJson -Element $Record
    } catch {
        return "record is not canonically representable: $($_.Exception.Message)"
    }

    return ''
}

function Read-StoredRecord {
    <#
        Closes the stored line. The line must parse, carry exactly the seven
        fields of the stored schema once each, and be byte-for-byte the
        canonical serialization of what it parses to. Only then is its digest
        recomputed over the stored bytes, minus the digest member, which cannot
        cover itself. Anything a reader would see is therefore covered: no
        extra field, no duplicate key, no reordering, and no spare whitespace
        can carry text the chain does not hash.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $record = @{
        Error = ''
        Sequence = 0
        PreviousHash = ''
        RecordSha256 = ''
        Type = ''
        ComputedDigest = ''
    }

    try {
        $document = ConvertFrom-JsonText -Text $Text
    } catch {
        $record.Error = 'is not valid JSON'
        return $record
    }

    try {
        $root = $document.RootElement

        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            $record.Error = 'is not a JSON object'
            return $record
        }

        try {
            $member = Get-CanonicalMember -Element $root
        } catch {
            $record.Error = "is not canonically representable: $($_.Exception.Message)"
            return $record
        }

        foreach ($name in @($member.Keys)) {
            if (-not $script:StoredFieldSet.Contains($name)) {
                $record.Error = "carries the unknown field '$name'"
                return $record
            }
        }

        foreach ($required in $script:StoredField) {
            if (-not $member.Contains($required)) {
                $record.Error = "is missing '$required'"
                return $record
            }
        }

        if (-not (Test-OrdinalEqual -Left (Join-CanonicalMember -Member $member) -Right $Text)) {
            $record.Error = 'is not stored in canonical form'
            return $record
        }

        if ([string]$member['sequence'] -cnotmatch $script:IntegerPattern) {
            $record.Error = 'declares a sequence that is not a JSON integer'
            return $record
        }

        foreach ($name in @('prevSha256', 'recordSha256')) {
            $value = $root.GetProperty($name)

            if ($value.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
                $value.GetString() -cnotmatch $script:DigestPattern) {
                $record.Error = "declares a $name that is not a lowercase 64-character hexadecimal digest"
                return $record
            }
        }

        $type = $root.GetProperty('type')
        if ($type.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
            $record.Error = 'declares a type that is not a string'
            return $record
        }

        $preimageMember = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        foreach ($key in @($member.Keys)) {
            if (-not (Test-OrdinalEqual -Left $key -Right 'recordSha256')) {
                $preimageMember[$key] = $member[$key]
            }
        }

        $record.Sequence = [long]$member['sequence']
        $record.PreviousHash = $root.GetProperty('prevSha256').GetString()
        $record.RecordSha256 = $root.GetProperty('recordSha256').GetString()
        $record.Type = $type.GetString()
        $record.ComputedDigest = Get-Sha256Hex -Text (Join-CanonicalMember -Member $preimageMember)
    } finally {
        $document.Dispose()
    }

    return $record
}

function Read-ContainmentProfile {
    <#
        The profile is read exactly once and the digest given on the command
        line is the trust anchor: a digest the run derives from the file it is
        about to trust proves nothing. The bytes that are hashed are the bytes
        that are parsed, so the paths this returns cannot come from a document
        the caller swapped in afterwards.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Sha256
    )

    $containmentProfile = @{
        Error = ''
        SinkPath = ''
        ChainHeadPath = ''
        AppenderPath = ''
        AppenderSha256 = ''
    }

    if ($Sha256 -cnotmatch $script:DigestPattern) {
        $containmentProfile.Error = 'the profile digest must be a lowercase 64-character hexadecimal string'
        return $containmentProfile
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $containmentProfile.Error = "the containment profile '$Path' does not exist"
        return $containmentProfile
    }

    $bytes = Read-FileByte -Path $Path
    if (-not (Test-OrdinalEqual -Left (Get-Sha256HexFromByte -Byte $bytes) -Right $Sha256)) {
        $containmentProfile.Error = 'the containment profile does not match the digest given on the command line'
        return $containmentProfile
    }

    try {
        $text = $script:StrictUtf8.GetString($bytes)
    } catch {
        $containmentProfile.Error = 'the containment profile is not valid UTF-8'
        return $containmentProfile
    }

    # A byte-order mark is part of the hashed bytes but is not JSON; the
    # verifier reads the same file through a reader that skips it.
    $text = $text.TrimStart([char]0xFEFF)

    try {
        $document = ConvertFrom-JsonText -Text $text
    } catch {
        $containmentProfile.Error = 'the containment profile is not valid JSON'
        return $containmentProfile
    }

    try {
        $root = $document.RootElement

        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            $containmentProfile.Error = 'the containment profile is not a JSON object'
            return $containmentProfile
        }

        foreach ($name in @('ledgerSink', 'chainHead')) {
            $value = [System.Text.Json.JsonElement]::new()

            if (-not $root.TryGetProperty($name, [ref]$value) -or
                $value.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
                [string]::IsNullOrWhiteSpace($value.GetString())) {
                $containmentProfile.Error = "the containment profile does not declare '$name' as a path"
                return $containmentProfile
            }

            if (Test-OrdinalEqual -Left $name -Right 'ledgerSink') {
                $containmentProfile.SinkPath = $value.GetString()
            } else {
                $containmentProfile.ChainHeadPath = $value.GetString()
            }
        }

        $appender = [System.Text.Json.JsonElement]::new()
        if (-not $root.TryGetProperty('ledgerAppender', [ref]$appender) -or
            $appender.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            $containmentProfile.Error = "the containment profile does not declare 'ledgerAppender'"
            return $containmentProfile
        }

        $appenderPath = [System.Text.Json.JsonElement]::new()
        $appenderDigest = [System.Text.Json.JsonElement]::new()

        if (-not $appender.TryGetProperty('path', [ref]$appenderPath) -or
            $appenderPath.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
            [string]::IsNullOrWhiteSpace($appenderPath.GetString())) {
            $containmentProfile.Error = "the containment profile does not declare 'ledgerAppender.path'"
            return $containmentProfile
        }

        if (-not $appender.TryGetProperty('sha256', [ref]$appenderDigest) -or
            $appenderDigest.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
            $appenderDigest.GetString() -cnotmatch $script:DigestPattern) {
            $containmentProfile.Error = "the containment profile does not declare 'ledgerAppender.sha256' as a lowercase 64-character hexadecimal digest"
            return $containmentProfile
        }

        $containmentProfile.AppenderPath = $appenderPath.GetString()
        $containmentProfile.AppenderSha256 = $appenderDigest.GetString()
    } finally {
        $document.Dispose()
    }

    return $containmentProfile
}

function Test-PinnedAppender {
    <#
        Binding the verdict to the profile is only worth something if the
        script producing it is the one the profile pins, so the running file
        is compared with ledgerAppender both by path and by digest.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Sha256
    )

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return 'the running appender has no file path to compare with the pinned one'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "the pinned appender '$Path' does not exist"
    }

    $pinned = [System.IO.Path]::GetFullPath($Path)
    $running = [System.IO.Path]::GetFullPath($PSCommandPath)
    $comparison = if ($script:OnWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

    if (-not [string]::Equals($pinned, $running, $comparison)) {
        return "the running appender '$running' is not the pinned appender '$pinned'"
    }

    $digest = Get-Sha256HexFromByte -Byte (Read-FileByte -Path $running)
    if (-not (Test-OrdinalEqual -Left $digest -Right $Sha256)) {
        return 'the running appender does not match the digest the profile pins'
    }

    return ''
}

function Read-FileByte {
    <#
        The service holds the sink open for its whole life, so every reader
        here has to tolerate that writer. File.ReadAllBytes asks for a share
        mode that does not, and would turn a running appender into a
        verification failure.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '',
        Justification = 'The comma wraps the array so PowerShell cannot unroll it; the caller receives the byte[] the attribute declares.')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $buffer = [byte[]]::new($stream.Length)
        $read = 0

        while ($read -lt $buffer.Length) {
            $count = $stream.Read($buffer, $read, $buffer.Length - $read)
            if ($count -le 0) {
                break
            }

            $read += $count
        }

        # The comma keeps an empty or single-byte buffer an array: PowerShell
        # would otherwise unroll it to $null or to one byte.
        return , $buffer
    } finally {
        $stream.Dispose()
    }
}

function Read-RequestLine {
    <#
        One request is one line. The cap is there because the reader is fed by
        an untrusted client: without it, a client that never sends a newline
        grows the buffer until the service dies, taking the run's evidence
        with it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.IO.StreamReader]$Reader
    )

    $builder = [System.Text.StringBuilder]::new()

    while ($true) {
        $value = $Reader.Read()

        if ($value -lt 0 -or $value -eq 10) {
            break
        }

        if ($value -eq 13) {
            continue
        }

        if ($builder.Length -ge $script:MaxRequestLength) {
            throw "request exceeds $($script:MaxRequestLength) characters"
        }

        $null = $builder.Append([char]$value)
    }

    return $builder.ToString()
}

function Read-SinkLine {
    <#
        Reads the sink as bytes rather than as text lines. A trailing record
        without its terminator is a half-written append, not a record; a blank
        line, a CR, or a byte-order mark is text nobody hashed. Each is refused
        instead of skipped, because skipping is what lets a writer park content
        between the records.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = @{ Error = ''; Line = [string[]]@() }
    $bytes = Read-FileByte -Path $Path

    if ($bytes.Length -eq 0) {
        return $result
    }

    if ($bytes[0] -eq 0xEF -and $bytes.Length -ge 3 -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $result.Error = 'the ledger sink starts with a byte-order mark'
        return $result
    }

    if ($bytes[$bytes.Length - 1] -ne 0x0A) {
        $result.Error = 'the ledger sink does not end with a complete, terminated record'
        return $result
    }

    try {
        $text = $script:StrictUtf8.GetString($bytes)
    } catch {
        $result.Error = 'the ledger sink is not valid UTF-8'
        return $result
    }

    $segment = $text.Split("`n")
    $line = [System.Collections.Generic.List[string]]::new()

    for ($index = 0; $index -lt $segment.Length - 1; $index++) {
        if ($segment[$index].Length -eq 0) {
            $result.Error = "the ledger sink holds an empty line at position $($index + 1)"
            return $result
        }

        $line.Add($segment[$index])
    }

    $result.Line = $line.ToArray()
    return $result
}

function Read-ChainState {
    <#
        Rebuilds sequence, last digest, and sealed state by verifying the whole
        chain from genesis. It reads the sink only: whether that chain is the
        one the protected head names is decided separately, by
        Test-HeadAgreement, so that a restart cannot resume onto a chain that
        was shortened or rewritten while the service was down.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$HeadPath
    )

    $state = @{
        Sequence = 0
        LastHash = $script:GenesisHash
        PreviousHash = $script:GenesisHash
        Sealed = $false
        Error = ''
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if (Test-Path -LiteralPath $HeadPath -PathType Leaf) {
            $state.Error = 'chain head exists without a ledger sink'
        }

        return $state
    }

    $sink = Read-SinkLine -Path $Path
    if ($sink.Error) {
        $state.Error = $sink.Error
        return $state
    }

    $expectedPrevious = $script:GenesisHash
    $priorHash = $script:GenesisHash
    $sequence = 0

    foreach ($text in $sink.Line) {
        $sequence++
        $record = Read-StoredRecord -Text $text

        if ($record.Error) {
            $state.Error = "record at sequence $sequence $($record.Error)"
            return $state
        }

        if ($state.Sealed) {
            $state.Error = "record at sequence $sequence follows the seal record"
            return $state
        }

        if ($record.Sequence -ne $sequence) {
            $state.Error = "record at sequence $sequence declares sequence $($record.Sequence)"
            return $state
        }

        if (-not (Test-OrdinalEqual -Left $record.PreviousHash -Right $expectedPrevious)) {
            $state.Error = "record at sequence $sequence does not chain to its predecessor"
            return $state
        }

        if (-not (Test-OrdinalEqual -Left $record.RecordSha256 -Right $record.ComputedDigest)) {
            $state.Error = "record at sequence $sequence fails its own digest"
            return $state
        }

        if (Test-OrdinalEqual -Left $record.Type -Right 'Seal') {
            $state.Sealed = $true
        }

        $priorHash = $expectedPrevious
        $expectedPrevious = $record.RecordSha256
    }

    $state.Sequence = $sequence
    $state.LastHash = $expectedPrevious
    $state.PreviousHash = $priorHash

    return $state
}

function Read-ChainHeadState {
    <#
        The head is evidence too, so it is read with the same strictness as a
        record: exactly four members, canonical bytes, a lowercase digest and a
        sequence that is a JSON integer. An unreadable head is a refusal, never
        a reason to fall back on the sink.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $head = @{
        Present = $false
        Sequence = 0
        RecordSha256 = $script:GenesisHash
        Sealed = $false
        Error = ''
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $head
    }

    $head.Present = $true
    $bytes = Read-FileByte -Path $Path

    if ($bytes.Length -eq 0) {
        $head.Error = 'the chain head is empty'
        return $head
    }

    try {
        $text = $script:StrictUtf8.GetString($bytes)
    } catch {
        $head.Error = 'the chain head is not valid UTF-8'
        return $head
    }

    try {
        $document = ConvertFrom-JsonText -Text $text
    } catch {
        $head.Error = 'the chain head is not valid JSON'
        return $head
    }

    try {
        $root = $document.RootElement

        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            $head.Error = 'the chain head is not a JSON object'
            return $head
        }

        try {
            $member = Get-CanonicalMember -Element $root
        } catch {
            $head.Error = "the chain head is not canonically representable: $($_.Exception.Message)"
            return $head
        }

        foreach ($name in @($member.Keys)) {
            if (-not $script:HeadFieldSet.Contains($name)) {
                $head.Error = "the chain head carries the unknown field '$name'"
                return $head
            }
        }

        foreach ($required in $script:HeadField) {
            if (-not $member.Contains($required)) {
                $head.Error = "the chain head is missing '$required'"
                return $head
            }
        }

        if (-not (Test-OrdinalEqual -Left (Join-CanonicalMember -Member $member) -Right $text)) {
            $head.Error = 'the chain head is not stored in canonical form'
            return $head
        }

        $digest = $root.GetProperty('recordSha256')
        if ($digest.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
            $digest.GetString() -cnotmatch $script:DigestPattern) {
            $head.Error = 'the chain head names a digest that is not a lowercase 64-character hexadecimal string'
            return $head
        }

        $sealed = $root.GetProperty('sealed')
        if ($sealed.ValueKind -ne [System.Text.Json.JsonValueKind]::True -and
            $sealed.ValueKind -ne [System.Text.Json.JsonValueKind]::False) {
            $head.Error = "the chain head's sealed flag is not a JSON boolean"
            return $head
        }

        if ([string]$member['sequence'] -cnotmatch $script:IntegerPattern -or [long]$member['sequence'] -lt 1) {
            $head.Error = 'the chain head names a sequence that is not a positive JSON integer'
            return $head
        }

        if (($root.GetProperty('updatedUtc')).ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
            -not (Test-UtcInstant -Value ($root.GetProperty('updatedUtc')).GetString())) {
            $head.Error = 'the chain head names an updatedUtc that is not an ISO-8601 instant in UTC'
            return $head
        }

        $head.Sequence = [long]$member['sequence']
        $head.RecordSha256 = $digest.GetString()
        $head.Sealed = $sealed.ValueKind -eq [System.Text.Json.JsonValueKind]::True
    } finally {
        $document.Dispose()
    }

    return $head
}

function Test-HeadAgreement {
    <#
        The head and the sink must agree before the service writes anything.
        Exactly one disagreement is survivable: a head one record behind the
        sink, which is what a crash between the sink flush and the head write
        leaves. Everything else -- a shortened sink, a head naming a record the
        sink does not end with, a missing head over a longer sink -- is a
        refusal, because adopting the sink and rewriting the head is precisely
        how a truncation would be laundered into a valid-looking ledger.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [hashtable]$Head
    )

    $agreement = @{ Error = ''; CatchUp = $false }

    if (-not $Head.Present) {
        if ($State.Sequence -eq 0) {
            return $agreement
        }

        if ($State.Sequence -eq 1) {
            $agreement.CatchUp = $true
            return $agreement
        }

        $agreement.Error = "the chain head is missing while the sink holds $($State.Sequence) records"
        return $agreement
    }

    if ($State.Sequence -eq 0) {
        $agreement.Error = 'the chain head names a record but the ledger sink holds none'
        return $agreement
    }

    if ($Head.Sequence -eq $State.Sequence) {
        if (-not (Test-OrdinalEqual -Left $Head.RecordSha256 -Right $State.LastHash)) {
            $agreement.Error = "the chain head names a different record at sequence $($State.Sequence)"
            return $agreement
        }

        if ($Head.Sealed -ne $State.Sealed) {
            $agreement.Error = "the chain head's sealed flag contradicts the chain"
            return $agreement
        }

        return $agreement
    }

    if ($Head.Sequence -eq $State.Sequence - 1) {
        if (-not (Test-OrdinalEqual -Left $Head.RecordSha256 -Right $State.PreviousHash)) {
            $agreement.Error = "the chain head names a different record at sequence $($Head.Sequence)"
            return $agreement
        }

        if ($Head.Sealed) {
            $agreement.Error = 'the chain head is sealed while the sink holds a later record'
            return $agreement
        }

        $agreement.CatchUp = $true
        return $agreement
    }

    $agreement.Error = "the chain head names sequence $($Head.Sequence) but the ledger sink ends at $($State.Sequence)"
    return $agreement
}

function Write-ChainHead {
    <#
        Written to a temporary file in the same directory, flushed through the
        operating-system cache, and then moved over the old head, so a reader
        never sees a half-written head and a failed write leaves the previous
        one in place.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$Sequence,

        [Parameter(Mandatory)]
        [string]$RecordHash,

        [Parameter(Mandatory)]
        [bool]$Sealed
    )

    $member = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    $member['sequence'] = ([long]$Sequence).ToString([cultureinfo]::InvariantCulture)
    $member['recordSha256'] = ConvertTo-JsonStringLiteral -Value $RecordHash
    $member['updatedUtc'] = ConvertTo-JsonStringLiteral -Value ([datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture))
    $member['sealed'] = if ($Sealed) { 'true' } else { 'false' }

    $head = Join-CanonicalMember -Member $member
    $temporary = '{0}.{1}.tmp' -f $Path, [guid]::NewGuid().ToString('N')

    try {
        $stream = [System.IO.FileStream]::new($temporary, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $bytes = $script:Utf8.GetBytes($head)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }

        [System.IO.File]::Move($temporary, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-AppenderRequest {
    <#
        Sealing is the server's decision, so the request says what it wants
        done, not what the record should look like. An append carrying a record
        of type 'Seal' is refused rather than honoured: that was how a caller
        could seal the ledger without ever asking to.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Element
    )

    $request = @{ Error = ''; Operation = ''; Record = [System.Text.Json.JsonElement]::new() }

    if ($Element.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        $request.Error = 'request must be a JSON object'
        return $request
    }

    $seen = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)

    foreach ($property in $Element.EnumerateObject()) {
        if (-not $script:RequestFieldSet.Contains($property.Name)) {
            $request.Error = "request carries the unknown field '$($property.Name)'"
            return $request
        }

        if ($seen.Contains($property.Name)) {
            $request.Error = "request repeats the field '$($property.Name)'"
            return $request
        }

        $seen[$property.Name] = $property.Value
    }

    foreach ($required in $script:RequestField) {
        if (-not $seen.Contains($required)) {
            $request.Error = "request is missing '$required'"
            return $request
        }
    }

    $operation = [System.Text.Json.JsonElement]$seen['operation']
    if ($operation.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
        -not $script:OperationSet.Contains($operation.GetString())) {
        $request.Error = "request names an operation that is not one of: $($script:Operation -join ', ')"
        return $request
    }

    $record = [System.Text.Json.JsonElement]$seen['record']
    $schemaError = Test-RecordSchema -Record $record
    if ($schemaError) {
        $request.Error = $schemaError
        return $request
    }

    $type = ($record.GetProperty('type')).GetString()

    if (Test-OrdinalEqual -Left $operation.GetString() -Right 'Seal') {
        if (-not (Test-OrdinalEqual -Left $type -Right 'Seal')) {
            $request.Error = "a seal operation must carry a record of type 'Seal'"
            return $request
        }
    } elseif (Test-OrdinalEqual -Left $type -Right 'Seal') {
        $request.Error = "the record type 'Seal' is reserved for the seal operation"
        return $request
    }

    $request.Operation = $operation.GetString()
    $request.Record = $record

    return $request
}

function Add-Record {
    <#
        Persist, then advance, then publish. The sink write is flushed through
        the operating-system cache and the in-memory state advances with it, so
        a sequence is spent the moment its record is durable and can never be
        handed to a second record. Publishing the head comes last and is fatal
        when it fails: the record stays unacknowledged, and the restart check
        accepts a head exactly one behind and continues from the sink.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Record,

        [Parameter(Mandatory)]
        [ValidateSet('Append', 'Seal')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [System.IO.FileStream]$Stream,

        [Parameter(Mandatory)]
        [string]$HeadPath
    )

    $sequence = [int]$State.Sequence + 1
    $stored = New-StoredRecord -Record $Record -Sequence $sequence -PreviousHash ([string]$State.LastHash)

    try {
        $bytes = $script:Utf8.GetBytes($stored.Line + "`n")
        $Stream.Write($bytes, 0, $bytes.Length)
        $Stream.Flush($true)
    } catch {
        $script:FatalError = "could not write the ledger sink: $($_.Exception.Message)"
        throw
    }

    # The operation seals, not the record's own type: the server decides.
    $sealed = [bool]$State.Sealed -or (Test-OrdinalEqual -Left $Operation -Right 'Seal')

    $State.Sequence = $sequence
    $State.PreviousHash = [string]$State.LastHash
    $State.LastHash = $stored.RecordSha256
    $State.Sealed = $sealed

    try {
        Write-ChainHead -Path $HeadPath -Sequence $sequence -RecordHash $stored.RecordSha256 -Sealed $sealed
    } catch {
        $script:FatalError = "could not write the chain head: $($_.Exception.Message)"
        throw
    }

    return @{
        sequence = $sequence
        recordSha256 = $stored.RecordSha256
    }
}

function Test-PipeNameInUse {
    <#
        The pipe namespace is enumerated rather than probed with Test-Path:
        opening the path counts as a client connection and leaves the listening
        server's pending wait faulted, so a existence check would disturb the
        very service it asks about.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    foreach ($entry in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
        if (Test-OrdinalEqual -Left ([System.IO.Path]::GetFileName($entry)) -Right $Name) {
            return $true
        }
    }

    return $false
}

function New-RestrictedPipeServer {
    <#
        The pipe is the authentication boundary. Only the appender's own
        account and the allowed identity get an Allow ACE, a network logon is
        denied outright, and the owner is left to the creator: an owner can
        rewrite the DACL, so handing ownership to the caller would hand it the
        pipe. Only the appender's own account is granted CreateNewInstance,
        which is what lets the service keep a listening instance while it works
        and what stops another identity from adding one of its own.
        Failing to apply the ACL is fatal rather than degraded, because a
        default DACL would silently widen who may append evidence.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Internal helper of a service mode that is already an explicit, non-interactive decision.')]
    [CmdletBinding()]
    [OutputType([System.IO.Pipes.NamedPipeServerStream])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Identity
    )

    $security = [System.IO.Pipes.PipeSecurity]::new()
    $current = [System.Security.Principal.WindowsIdentity]::GetCurrent()

    $security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new(
            $current.User,
            [System.IO.Pipes.PipeAccessRights]::ReadWrite -bor [System.IO.Pipes.PipeAccessRights]::CreateNewInstance,
            [System.Security.AccessControl.AccessControlType]::Allow))

    if (-not [string]::IsNullOrWhiteSpace($Identity)) {
        $account = [System.Security.Principal.NTAccount]::new($Identity)
        $allowed = $account.Translate([System.Security.Principal.SecurityIdentifier])

        if (-not (Test-OrdinalEqual -Left $allowed.Value -Right $current.User.Value)) {
            $security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new(
                    $allowed,
                    [System.IO.Pipes.PipeAccessRights]::ReadWrite,
                    [System.Security.AccessControl.AccessControlType]::Allow))
        }
    }

    $security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new(
            [System.Security.Principal.SecurityIdentifier]::new('S-1-5-2'),
            [System.IO.Pipes.PipeAccessRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Deny))

    # Two instances, so the next one can be created while this one is still
    # serving a client and the name is never unowned for an instant.
    return [System.IO.Pipes.NamedPipeServerStreamAcl]::Create(
        $Name, [System.IO.Pipes.PipeDirection]::InOut, 2,
        [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous,
        0, 0, $security)
}

function Get-ExpectedServerIdentity {
    <#
        Which principal the client requires the pipe to belong to. By default
        that is whoever would own an object this client created, which is the
        same comparison PipeOptions.CurrentUserOnly makes inside .NET; an
        explicit identity replaces it when the appender runs as another account.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Identity
    )

    $current = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $self = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($current.User.Value, $current.Owner.Value), [System.StringComparer]::Ordinal)

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        return @{ Owner = $self; Allowed = $self; Explicit = $false }
    }

    if ($Identity -cmatch $script:SidPattern) {
        $sid = [System.Security.Principal.SecurityIdentifier]::new($Identity)
    } else {
        $sid = ([System.Security.Principal.NTAccount]::new($Identity)).Translate([System.Security.Principal.SecurityIdentifier])
    }

    # The owner must be exactly the identity the caller named; the channel may
    # additionally be open to this client, and to nobody else.
    $owner = [System.Collections.Generic.HashSet[string]]::new([string[]]@($sid.Value), [System.StringComparer]::Ordinal)
    $allowed = [System.Collections.Generic.HashSet[string]]::new($self, [System.StringComparer]::Ordinal)
    $null = $allowed.Add($sid.Value)

    return @{
        Owner = $owner
        Allowed = $allowed
        Explicit = $true
    }
}

function Test-PipeServerIdentity {
    <#
        What this proves: the pipe object belongs to the expected principal and
        grants access to nobody else. Setting another account as owner needs a
        privilege an ordinary local identity does not have, so a squatter that
        is not the appender identity cannot present this security descriptor.
        What it does not prove: that the process behind the pipe is the pinned
        appender rather than another process of the same identity. That is why
        the acknowledgement is cross-checked against the ledger afterwards.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.IO.Pipes.NamedPipeClientStream]$Client,

        [Parameter(Mandatory)]
        [hashtable]$Expected
    )

    try {
        $security = [System.IO.Pipes.PipesAclExtensions]::GetAccessControl($Client)
    } catch {
        return "the pipe's security descriptor cannot be read: $($_.Exception.Message)"
    }

    $owner = $security.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($null -eq $owner -or -not $Expected.Owner.Contains($owner.Value)) {
        return "the pipe is owned by $($owner) and not by the expected appender identity"
    }

    foreach ($rule in $security.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
            continue
        }

        if (-not $Expected.Allowed.Contains($rule.IdentityReference.Value)) {
            return "the pipe grants access to $($rule.IdentityReference.Value), so the channel is not exclusive"
        }
    }

    return ''
}

function Invoke-AppenderRequest {
    <#
        Identification, never Impersonation: a server on this pipe must not be
        able to act as the caller. The server is authenticated before the
        record is handed over, because a record given to a squatter is already
        disclosed whatever the answer says.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Payload,

        [Parameter(Mandatory)]
        [hashtable]$Expected
    )

    # PipeOptions.CurrentUserOnly is deliberately not used: .NET compares the
    # pipe owner with this token's owner only after the handle is open, and the
    # check below makes the same comparison plus the DACL, before a single byte
    # of the record is written.
    $client = [System.IO.Pipes.NamedPipeClientStream]::new(
        '.', $Name, [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::None,
        [System.Security.Principal.TokenImpersonationLevel]::Identification)
    try {
        $client.Connect(10000)

        $identityError = Test-PipeServerIdentity -Client $client -Expected $Expected
        if ($identityError) {
            throw $identityError
        }

        $writer = [System.IO.StreamWriter]::new($client, $script:Utf8, 4096, $true)
        $writer.AutoFlush = $true
        $writer.WriteLine($Payload)
        $writer.Dispose()

        $reader = [System.IO.StreamReader]::new($client, $script:Utf8, $false, 4096, $true)
        try {
            return $reader.ReadLine()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

function Read-AppenderResponse {
    <#
        The response comes from the other side of the pipe, so it is parsed as
        strictly as stored evidence: a fixed shape, a status the client knows,
        a sequence that is a positive integer and a lowercase digest.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Element
    )

    $response = @{ Error = ''; Status = ''; Message = ''; Sequence = 0; RecordSha256 = '' }

    if ($Element.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
        $response.Error = 'appender returned a response that is not a JSON object'
        return $response
    }

    try {
        $member = Get-CanonicalMember -Element $Element
    } catch {
        $response.Error = "appender returned an unreadable response: $($_.Exception.Message)"
        return $response
    }

    foreach ($required in @('status', 'message', 'sequence', 'recordSha256')) {
        if (-not $member.Contains($required)) {
            $response.Error = "appender returned a response without '$required'"
            return $response
        }
    }

    $status = $Element.GetProperty('status')
    $message = $Element.GetProperty('message')

    if ($status.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
        $message.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
        $response.Error = 'appender returned a response whose status or message is not a string'
        return $response
    }

    $response.Status = $status.GetString()
    $response.Message = $message.GetString()

    if (-not (Test-OrdinalEqual -Left $response.Status -Right 'Ok')) {
        return $response
    }

    if ([string]$member['sequence'] -cnotmatch $script:IntegerPattern -or [long]$member['sequence'] -lt 1) {
        $response.Error = 'appender acknowledged a sequence that is not a positive integer'
        return $response
    }

    $digest = $Element.GetProperty('recordSha256')
    if ($digest.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
        $digest.GetString() -cnotmatch $script:DigestPattern) {
        $response.Error = 'appender acknowledged a digest that is not a lowercase 64-character hexadecimal string'
        return $response
    }

    $response.Sequence = [long]$member['sequence']
    $response.RecordSha256 = $digest.GetString()

    return $response
}

function Test-Acknowledgement {
    <#
        The acknowledgement is a claim by whoever answered the pipe, and the
        ledger alone cannot settle it: a server that answers a new record with
        the sequence and digest of a record that is already stored says only
        true things about the ledger while storing nothing. So the client
        recomputes the digest of the record it sent, at the acknowledged
        sequence and on top of the record before it, and requires that digest
        to be both what was acknowledged and what is stored.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int]$Sequence,

        [Parameter(Mandatory)]
        [string]$RecordSha256,

        [Parameter(Mandatory)]
        [System.Text.Json.JsonElement]$Record,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$HeadPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "the acknowledged record is not in the ledger: '$Path' does not exist"
    }

    $state = Read-ChainState -Path $Path -HeadPath $HeadPath
    if ($state.Error) {
        return "the acknowledged record is not in a valid ledger: $($state.Error)"
    }

    if ($state.Sequence -lt $Sequence) {
        return "the ledger ends at sequence $($state.Sequence) but the acknowledgement names $Sequence"
    }

    $sink = Read-SinkLine -Path $Path
    if ($sink.Error) {
        return "the acknowledged record cannot be read back: $($sink.Error)"
    }

    # Not $record: PowerShell variable names are case-insensitive, so that name
    # would overwrite the record this function was given.
    $stored = Read-StoredRecord -Text $sink.Line[$Sequence - 1]
    if ($stored.Error) {
        return "the acknowledged record cannot be read back: it $($stored.Error)"
    }

    $previous = $script:GenesisHash
    if ($Sequence -gt 1) {
        $earlier = Read-StoredRecord -Text $sink.Line[$Sequence - 2]
        if ($earlier.Error) {
            return "the record before the acknowledged one cannot be read back: it $($earlier.Error)"
        }

        $previous = $earlier.RecordSha256
    }

    try {
        $expected = New-StoredRecord -Record $Record -Sequence $Sequence -PreviousHash $previous
    } catch {
        return "the record that was sent cannot be rebuilt: $($_.Exception.Message)"
    }

    if (-not (Test-OrdinalEqual -Left $expected.RecordSha256 -Right $stored.RecordSha256)) {
        return "the ledger does not hold the record that was sent at sequence $Sequence"
    }

    if (-not (Test-OrdinalEqual -Left $expected.RecordSha256 -Right $RecordSha256)) {
        return "the acknowledgement names a digest that is not the record that was sent"
    }

    if (-not (Test-OrdinalEqual -Left $stored.RecordSha256 -Right $RecordSha256)) {
        return "the ledger holds a different record at sequence $Sequence than the acknowledgement names"
    }

    $head = Read-ChainHeadState -Path $HeadPath
    if ($head.Error) {
        return "the acknowledged record is not published: $($head.Error)"
    }

    if ($head.Sequence -lt $Sequence) {
        return "the chain head is behind the acknowledged sequence $Sequence"
    }

    return ''
}

switch ($PSCmdlet.ParameterSetName) {
    'Serve' {
        if (-not $script:OnWindows) {
            # A Unix named pipe is a filesystem object with no owner check the
            # client can make, so neither side could authenticate the other.
            # Refusing is the only honest answer; nothing here measures it.
            Write-Refusal -Message 'the appender service is only supported on Windows, where the pipe can be restricted by ACL'
            exit 2
        }

        # Both directories, not only the sink's: a head that cannot be written
        # is fatal, so an absent directory would stop the service on its first
        # append rather than at start.
        foreach ($directory in @((Split-Path -Parent $SinkPath), (Split-Path -Parent $ChainHeadPath))) {
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                $null = New-Item -Path $directory -ItemType Directory -Force
            }
        }

        $state = Read-ChainState -Path $SinkPath -HeadPath $ChainHeadPath
        if ($state.Error) {
            Write-Refusal -Message "existing ledger is not valid: $($state.Error)"
            exit 2
        }

        $head = Read-ChainHeadState -Path $ChainHeadPath
        if ($head.Error) {
            Write-Refusal -Message $head.Error
            exit 2
        }

        $agreement = Test-HeadAgreement -State $state -Head $head
        if ($agreement.Error) {
            Write-Refusal -Message "the ledger sink and the chain head disagree: $($agreement.Error)"
            exit 2
        }

        if ($agreement.CatchUp) {
            # The only interrupted step that can be completed: the record is
            # already durable, so the head is finished, never the sink.
            [Console]::Error.WriteLine(
                "Ledger appender completed an interrupted head write up to sequence $($state.Sequence).")
            Write-ChainHead -Path $ChainHeadPath -Sequence $state.Sequence `
                -RecordHash $state.LastHash -Sealed $state.Sealed
        }

        if (Test-PipeNameInUse -Name $PipeName) {
            Write-Refusal -Message "the pipe name '$PipeName' is already in use; another appender or an impostor holds it"
            exit 2
        }

        # The sink is held open for the whole run. It is the second-instance
        # control: a second appender on the same ledger is refused here rather
        # than racing the first one, and no other process can open it for write
        # while the service is alive.
        try {
            $sinkStream = [System.IO.FileStream]::new($SinkPath, [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        } catch {
            Write-Refusal -Message "could not take the ledger sink '$SinkPath': $($_.Exception.Message)"
            exit 2
        }

        $listening = $null

        try {
            try {
                $listening = New-RestrictedPipeServer -Name $PipeName -Identity $AllowedIdentity
            } catch {
                Write-Refusal -Message "could not create a restricted pipe: $($_.Exception.Message)"
                exit 2
            }

            $idleDeadline = (Get-Date).AddSeconds($IdleTimeoutSeconds)

            while ((Get-Date) -lt $idleDeadline) {
                $remaining = $idleDeadline - (Get-Date)

                if ($remaining -le [timespan]::Zero) {
                    break
                }

                $connected = $false
                try {
                    $connected = $listening.WaitForConnectionAsync().Wait($remaining)
                } catch {
                    # Anything that touches the pipe counts as a connection,
                    # including a bare existence probe, and leaves the instance
                    # faulted. The replacement is created before the faulted one
                    # is released, so the name stays owned throughout.
                    [Console]::Error.WriteLine(
                        "Ledger appender dropped a connection attempt: $($_.Exception.GetBaseException().Message)")

                    $faulted = $listening
                    $listening = $null

                    try {
                        $listening = New-RestrictedPipeServer -Name $PipeName -Identity $AllowedIdentity
                    } catch {
                        Write-Refusal -Message "could not keep a listening instance of '$PipeName': $($_.Exception.Message)"
                        $faulted.Dispose()
                        exit 2
                    }

                    $faulted.Dispose()
                    continue
                }

                if (-not $connected) {
                    break
                }

                # One stream per connection: a broken pipe leaves the stream
                # faulted for good. The next instance is created before this one
                # is serviced, so the name is never unowned and nobody can take
                # it in the gap.
                $server = $listening
                $listening = $null

                try {
                    try {
                        $listening = New-RestrictedPipeServer -Name $PipeName -Identity $AllowedIdentity
                    } catch {
                        Write-Refusal -Message "could not keep a listening instance of '$PipeName': $($_.Exception.Message)"
                        $server.Dispose()
                        exit 2
                    }

                    $reader = [System.IO.StreamReader]::new($server, $script:Utf8, $false, 4096, $true)
                    $writer = [System.IO.StreamWriter]::new($server, $script:Utf8, 4096, $true)
                    $writer.AutoFlush = $true

                    $requestText = Read-RequestLine -Reader $reader
                    $response = [ordered]@{ status = 'Error'; message = 'empty request'; sequence = 0; recordSha256 = '' }

                    if (-not [string]::IsNullOrWhiteSpace($requestText)) {
                        $document = $null
                        try {
                            $document = ConvertFrom-JsonText -Text $requestText
                        } catch {
                            $response.message = 'request is not valid JSON'
                        }

                        if ($null -ne $document) {
                            try {
                                $request = Read-AppenderRequest -Element $document.RootElement

                                if ($request.Error) {
                                    $response.message = $request.Error
                                } elseif ($state.Sealed) {
                                    $response.message = 'ledger is sealed'
                                } else {
                                    $appended = Add-Record -Record $request.Record -Operation $request.Operation `
                                        -State $state -Stream $sinkStream -HeadPath $ChainHeadPath
                                    $response = [ordered]@{
                                        status = 'Ok'
                                        message = ''
                                        sequence = $appended.sequence
                                        recordSha256 = $appended.recordSha256
                                    }
                                }
                            } finally {
                                $document.Dispose()
                            }
                        }
                    }

                    $writer.WriteLine(($response | ConvertTo-Json -Compress))
                    $reader.Dispose()
                    $writer.Dispose()

                    # Disposing the stream discards anything the client has not
                    # read yet, so the acknowledgement must be drained before
                    # teardown.
                    $server.WaitForPipeDrain()

                    # Only a served connection resets the idle window, so a
                    # client that merely probes the pipe cannot keep the service
                    # alive.
                    $idleDeadline = (Get-Date).AddSeconds($IdleTimeoutSeconds)
                } catch {
                    if ($script:FatalError) {
                        # Never continue on stale state: the record may be
                        # durable but unpublished, and the next append would
                        # have to guess which sequence is free.
                        Write-Refusal -Message $script:FatalError
                        $server.Dispose()
                        exit 2
                    }

                    # A client that hangs up, times out, or sends garbage must
                    # not take the ledger service down with it: losing the
                    # appender mid-run would strand every later record.
                    [Console]::Error.WriteLine("Ledger appender dropped a connection: $($_.Exception.Message)")
                } finally {
                    $server.Dispose()
                }
            }
        } finally {
            if ($null -ne $listening) {
                $listening.Dispose()
            }

            $sinkStream.Dispose()
        }

        exit 0
    }

    { $_ -in @('Append', 'Seal') } {
        if (-not $script:OnWindows) {
            # The client cannot authenticate a Unix socket's server, and
            # handing a record to an unauthenticated server is the failure
            # C-04 describes. Refusing is the only safe answer.
            Write-Refusal -Message 'the appender client is only supported on Windows, where the pipe server can be authenticated'
            exit 2
        }

        # Parsed once, and kept until the acknowledgement has been checked: the
        # client has to rebuild the digest of this exact record to know whether
        # the ledger holds what it sent.
        try {
            $sent = ConvertFrom-JsonText -Text $RecordJson
        } catch {
            Write-Refusal -Message 'record is not valid JSON'
            exit 2
        }

        try {
            if ($Seal) {
                # -Seal must not be a quiet alias for -Append: sealing is
                # irreversible, so the intent has to be visible in the record too.
                $intendedType = ''
                if ($sent.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                    $typeElement = [System.Text.Json.JsonElement]::new()
                    if ($sent.RootElement.TryGetProperty('type', [ref]$typeElement) -and
                        $typeElement.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
                        $intendedType = $typeElement.GetString()
                    }
                }

                if (-not (Test-OrdinalEqual -Left $intendedType -Right 'Seal')) {
                    Write-Refusal -Message "-Seal requires a record of type 'Seal'"
                    exit 2
                }
            }

            try {
                $expected = Get-ExpectedServerIdentity -Identity $ExpectedServerIdentity
            } catch {
                Write-Refusal -Message "could not resolve the expected appender identity: $($_.Exception.Message)"
                exit 2
            }

            # The record is forwarded byte for byte inside an envelope that states
            # the operation. Re-serializing it here would change the bytes the
            # server hashes; a record crafted to close the envelope early produces
            # a repeated field, which the server refuses.
            $operation = if ($Seal) { 'Seal' } else { 'Append' }
            $payload = '{"operation":"' + $operation + '","record":' + $RecordJson + '}'

            try {
                $responseText = Invoke-AppenderRequest -Name $PipeName -Payload $payload -Expected $expected
            } catch {
                Write-Refusal -Message "could not reach a trusted appender on pipe '$PipeName': $($_.Exception.Message)"
                exit 2
            }

            if ([string]::IsNullOrWhiteSpace($responseText)) {
                Write-Refusal -Message 'appender returned no response'
                exit 2
            }

            try {
                $document = ConvertFrom-JsonText -Text $responseText
            } catch {
                Write-Refusal -Message 'appender returned a response that is not valid JSON'
                exit 2
            }

            try {
                $response = Read-AppenderResponse -Element $document.RootElement
            } finally {
                $document.Dispose()
            }

            if ($response.Error) {
                Write-Refusal -Message $response.Error
                exit 2
            }

            if (-not (Test-OrdinalEqual -Left $response.Status -Right 'Ok')) {
                Write-Refusal -Message $response.Message
                exit 2
            }

            # The answer came from the pipe, so it is a claim, not evidence. Only
            # the ledger itself can show that the record the client sent was
            # stored and published.
            $acknowledgementError = Test-Acknowledgement -Sequence $response.Sequence `
                -RecordSha256 $response.RecordSha256 -Record $sent.RootElement `
                -Path $SinkPath -HeadPath $ChainHeadPath
            if ($acknowledgementError) {
                Write-Refusal -Message "the acknowledgement is not backed by the ledger: $acknowledgementError"
                exit 2
            }

            Write-Output ('Appended sequence {0} as {1}' -f $response.Sequence, $response.RecordSha256)
            exit 0
        } finally {
            $sent.Dispose()
        }
    }

    { $_ -in @('Validate', 'ValidateBound') } {
        $bound = Test-OrdinalEqual -Left $PSCmdlet.ParameterSetName -Right 'ValidateBound'
        $resolvedSink = $SinkPath
        $resolvedHead = $ChainHeadPath

        if ($bound) {
            $containmentProfile = Read-ContainmentProfile -Path $ProfilePath -Sha256 $ProfileSha256
            if ($containmentProfile.Error) {
                Write-Refusal -Message $containmentProfile.Error
                exit 2
            }

            $pinnedError = Test-PinnedAppender -Path $containmentProfile.AppenderPath -Sha256 $containmentProfile.AppenderSha256
            if ($pinnedError) {
                Write-Refusal -Message $pinnedError
                exit 2
            }

            $resolvedSink = $containmentProfile.SinkPath
            $resolvedHead = $containmentProfile.ChainHeadPath
        } else {
            [Console]::Error.WriteLine(
                'Ledger appender warning: an unbound check proves only that the given files form a valid chain, not that they are the ledger a run was contained to.')
        }

        if (-not (Test-Path -LiteralPath $resolvedSink -PathType Leaf)) {
            Write-Refusal -Message "ledger sink '$resolvedSink' does not exist; an absent chain is never valid"
            exit 2
        }

        if (-not (Test-Path -LiteralPath $resolvedHead -PathType Leaf)) {
            Write-Refusal -Message "chain head '$resolvedHead' does not exist"
            exit 2
        }

        $state = Read-ChainState -Path $resolvedSink -HeadPath $resolvedHead

        if ($state.Error) {
            Write-Refusal -Message $state.Error
            exit 2
        }

        if ($state.Sequence -eq 0) {
            Write-Refusal -Message 'ledger contains no records'
            exit 2
        }

        $head = Read-ChainHeadState -Path $resolvedHead
        if ($head.Error) {
            Write-Refusal -Message $head.Error
            exit 2
        }

        $agreement = Test-HeadAgreement -State $state -Head $head
        if ($agreement.Error) {
            Write-Refusal -Message $agreement.Error
            exit 2
        }

        if ($agreement.CatchUp) {
            # Validation proves a finished ledger. A head that still has to
            # catch up is a chain the service has not finished writing.
            Write-Refusal -Message ("the chain head names sequence {0} but the ledger ends at {1}" -f $head.Sequence, $state.Sequence)
            exit 2
        }

        if ($RequireSealed -and -not ($state.Sealed -and $head.Sealed)) {
            Write-Refusal -Message 'the ledger is not sealed: the last record is not a seal record or the chain head does not say so'
            exit 2
        }

        # Exactly one JSON object, and only when everything above held.
        Write-Output ('{{"valid":true,"records":{0},"headSequence":{1},"sealed":{2},"headRecordSha256":"{3}","bound":{4}}}' -f
            $state.Sequence,
            $head.Sequence,
            $(if ($state.Sealed) { 'true' } else { 'false' }),
            $state.LastHash,
            $(if ($bound) { 'true' } else { 'false' }))
        exit 0
    }
}
