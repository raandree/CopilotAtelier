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
    Runs the appender service. This is the only mode that writes.
.PARAMETER Append
    Sends one record to a running appender and returns its assigned sequence.
.PARAMETER Seal
    Appends a final record and refuses every later append.
.PARAMETER Validate
    Recomputes the chain from genesis and compares it with the protected head.
    Reads only; safe to run from any identity that can read the sink.
.PARAMETER PipeName
    Local named pipe the service listens on and clients connect to.
.PARAMETER SinkPath
    Append-only JSONL ledger. One record per line.
.PARAMETER ChainHeadPath
    Protected head naming the newest sequence and digest.
.PARAMETER RecordJson
    One record as JSON. Exactly type, runId, utc, and data; nothing else.
.PARAMETER IdleTimeoutSeconds
    Stops the service after this long without a connection.
.PARAMETER AllowedIdentity
    Windows identity permitted to open the pipe. Defaults to the current user.
.EXAMPLE
    Invoke-LedgerAppender.ps1 -Serve -PipeName ca-ledger-run1 -SinkPath D:\ledger\run1.jsonl -ChainHeadPath D:\ledger\run1.head.json
.EXAMPLE
    Invoke-LedgerAppender.ps1 -Append -PipeName ca-ledger-run1 -RecordJson '{"type":"Baseline","runId":"run1","utc":"2026-09-02T22:00:00Z","data":{}}'
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
    [switch]$Validate,

    [Parameter(Mandatory, ParameterSetName = 'Serve')]
    [Parameter(Mandatory, ParameterSetName = 'Append')]
    [Parameter(Mandatory, ParameterSetName = 'Seal')]
    [ValidateNotNullOrEmpty()]
    [string]$PipeName,

    [Parameter(Mandatory, ParameterSetName = 'Serve')]
    [Parameter(Mandatory, ParameterSetName = 'Validate')]
    [ValidateNotNullOrEmpty()]
    [string]$SinkPath,

    [Parameter(Mandatory, ParameterSetName = 'Serve')]
    [Parameter(Mandatory, ParameterSetName = 'Validate')]
    [ValidateNotNullOrEmpty()]
    [string]$ChainHeadPath,

    [Parameter(Mandatory, ParameterSetName = 'Append')]
    [Parameter(Mandatory, ParameterSetName = 'Seal')]
    [ValidateNotNullOrEmpty()]
    [string]$RecordJson,

    [Parameter(ParameterSetName = 'Serve')]
    [ValidateRange(1, 86400)]
    [int]$IdleTimeoutSeconds = 3600,

    [Parameter(ParameterSetName = 'Serve')]
    [AllowEmptyString()]
    [string]$AllowedIdentity
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:GenesisHash = '0' * 64
$script:RequiredField = @('type', 'runId', 'utc', 'data')
$script:StoredField = @('data', 'prevSha256', 'recordSha256', 'runId', 'sequence', 'type', 'utc')
$script:HeadField = @('recordSha256', 'sealed', 'sequence', 'updatedUtc')
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:StrictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:DigestPattern = '^[0-9a-f]{64}$'
$script:UtcPattern = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z$'
$script:IntegerPattern = '^-?(0|[1-9][0-9]*)$'
$script:SafeInteger = 9007199254740991
$script:FatalError = ''
$script:JsonOption = [System.Text.Json.JsonDocumentOptions]::new()
$script:JsonOption.MaxDepth = 32

function Write-Refusal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    [Console]::Error.WriteLine("Ledger appender refused: $Message")
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
        if ($property.Name -cnotin $script:RequiredField) {
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

    if (([System.Text.Json.JsonElement]$present['utc']).GetString() -cnotmatch $script:UtcPattern) {
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
            if ($name -cnotin $script:StoredField) {
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

        if ((Join-CanonicalMember -Member $member) -cne $Text) {
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
            if ($key -cne 'recordSha256') {
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
    $bytes = [System.IO.File]::ReadAllBytes($Path)

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

        if ($record.PreviousHash -cne $expectedPrevious) {
            $state.Error = "record at sequence $sequence does not chain to its predecessor"
            return $state
        }

        if ($record.RecordSha256 -cne $record.ComputedDigest) {
            $state.Error = "record at sequence $sequence fails its own digest"
            return $state
        }

        if ($record.Type -ceq 'Seal') {
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
    $bytes = [System.IO.File]::ReadAllBytes($Path)

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
            if ($name -cnotin $script:HeadField) {
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

        if ((Join-CanonicalMember -Member $member) -cne $text) {
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
            ($root.GetProperty('updatedUtc')).GetString() -cnotmatch $script:UtcPattern) {
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
        if ($Head.RecordSha256 -cne $State.LastHash) {
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
        if ($Head.RecordSha256 -cne $State.PreviousHash) {
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
        [hashtable]$State,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$HeadPath
    )

    $sequence = [int]$State.Sequence + 1
    $stored = New-StoredRecord -Record $Record -Sequence $sequence -PreviousHash ([string]$State.LastHash)

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $bytes = $script:Utf8.GetBytes($stored.Line + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } catch {
        $script:FatalError = "could not write the ledger sink: $($_.Exception.Message)"
        throw
    } finally {
        $stream.Dispose()
    }

    $sealed = [bool]$State.Sealed -or (($Record.GetProperty('type')).GetString() -ceq 'Seal')

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

function New-RestrictedPipeServer {
    <#
        The pipe is the authentication boundary: on Windows only the allowed
        identity gets an ACE, so an unauthorized caller cannot open it at all.
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

    if (-not ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop')) {
        # On Unix a named pipe is a socket governed by filesystem permissions,
        # which the containment profile measures rather than this script.
        return [System.IO.Pipes.NamedPipeServerStream]::new(
            $Name, [System.IO.Pipes.PipeDirection]::InOut, 1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
    }

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }

    $security = [System.IO.Pipes.PipeSecurity]::new()
    $account = [System.Security.Principal.NTAccount]::new($Identity)
    $security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new(
            $account,
            [System.IO.Pipes.PipeAccessRights]::ReadWrite,
            [System.Security.AccessControl.AccessControlType]::Allow))
    $security.SetOwner($account)

    return [System.IO.Pipes.NamedPipeServerStreamAcl]::Create(
        $Name, [System.IO.Pipes.PipeDirection]::InOut, 1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous,
        0, 0, $security)
}

function Invoke-AppenderRequest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Payload
    )

    $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $Name, [System.IO.Pipes.PipeDirection]::InOut)
    try {
        $client.Connect(10000)

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

switch ($PSCmdlet.ParameterSetName) {
    'Serve' {
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

        try {
            $probe = New-RestrictedPipeServer -Name $PipeName -Identity $AllowedIdentity
            $probe.Dispose()
        } catch {
            Write-Refusal -Message "could not create a restricted pipe: $($_.Exception.Message)"
            exit 2
        }

        # One stream per connection. A broken pipe leaves the stream faulted for
        # good, so reusing it would end the service the first time a client
        # hung up mid-exchange.
        $idleDeadline = (Get-Date).AddSeconds($IdleTimeoutSeconds)

        while ((Get-Date) -lt $idleDeadline) {
            $server = New-RestrictedPipeServer -Name $PipeName -Identity $AllowedIdentity

            try {
                $remaining = $idleDeadline - (Get-Date)

                if ($remaining -le [timespan]::Zero) {
                    break
                }

                if (-not $server.WaitForConnectionAsync().Wait($remaining)) {
                    break
                }

                $reader = [System.IO.StreamReader]::new($server, $script:Utf8, $false, 4096, $true)
                $writer = [System.IO.StreamWriter]::new($server, $script:Utf8, 4096, $true)
                $writer.AutoFlush = $true

                $requestText = $reader.ReadLine()
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
                            $request = $document.RootElement
                            $schemaError = Test-RecordSchema -Record $request

                            if ($schemaError) {
                                $response.message = $schemaError
                            } elseif ($state.Sealed) {
                                $response.message = 'ledger is sealed'
                            } else {
                                $appended = Add-Record -Record $request -State $state -Path $SinkPath -HeadPath $ChainHeadPath
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

                # Disposing the stream discards anything the client has not read
                # yet, so the acknowledgement must be drained before teardown.
                $server.WaitForPipeDrain()

                # Only a served connection resets the idle window, so a client
                # that merely probes the pipe cannot keep the service alive.
                $idleDeadline = (Get-Date).AddSeconds($IdleTimeoutSeconds)
            } catch {
                if ($script:FatalError) {
                    # Never continue on stale state: the record may be durable
                    # but unpublished, and the next append would have to guess
                    # which sequence is free.
                    Write-Refusal -Message $script:FatalError
                    $server.Dispose()
                    exit 2
                }

                # A client that hangs up, times out, or sends garbage must not
                # take the ledger service down with it: losing the appender
                # mid-run would strand every later record.
                [Console]::Error.WriteLine("Ledger appender dropped a connection: $($_.Exception.Message)")
            } finally {
                $server.Dispose()
            }
        }

        exit 0
    }

    { $_ -in @('Append', 'Seal') } {
        if ($Seal) {
            # -Seal must not be a quiet alias for -Append: sealing is
            # irreversible, so the intent has to be visible in the record too.
            try {
                $intended = ConvertFrom-JsonText -Text $RecordJson
            } catch {
                Write-Refusal -Message 'record is not valid JSON'
                exit 2
            }

            try {
                $intendedType = ''
                if ($intended.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                    $typeElement = [System.Text.Json.JsonElement]::new()
                    if ($intended.RootElement.TryGetProperty('type', [ref]$typeElement) -and
                        $typeElement.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
                        $intendedType = $typeElement.GetString()
                    }
                }
            } finally {
                $intended.Dispose()
            }

            if ($intendedType -cne 'Seal') {
                Write-Refusal -Message "-Seal requires a record of type 'Seal'"
                exit 2
            }
        }

        try {
            $responseText = Invoke-AppenderRequest -Name $PipeName -Payload $RecordJson
        } catch {
            Write-Refusal -Message "could not reach the appender on pipe '$PipeName': $($_.Exception.Message)"
            exit 2
        }

        if ([string]::IsNullOrWhiteSpace($responseText)) {
            Write-Refusal -Message 'appender returned no response'
            exit 2
        }

        $response = $responseText | ConvertFrom-Json

        if ($response.status -ne 'Ok') {
            Write-Refusal -Message ([string]$response.message)
            exit 2
        }

        Write-Output ('Appended sequence {0} as {1}' -f $response.sequence, $response.recordSha256)
        exit 0
    }

    'Validate' {
        if (-not (Test-Path -LiteralPath $SinkPath -PathType Leaf)) {
            Write-Refusal -Message "ledger sink '$SinkPath' does not exist; an absent chain is never valid"
            exit 2
        }

        if (-not (Test-Path -LiteralPath $ChainHeadPath -PathType Leaf)) {
            Write-Refusal -Message "chain head '$ChainHeadPath' does not exist"
            exit 2
        }

        $state = Read-ChainState -Path $SinkPath -HeadPath $ChainHeadPath

        if ($state.Error) {
            Write-Refusal -Message $state.Error
            exit 2
        }

        if ($state.Sequence -eq 0) {
            Write-Refusal -Message 'ledger contains no records'
            exit 2
        }

        $head = Read-ChainHeadState -Path $ChainHeadPath
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

        Write-Output ('Valid: {0} records from genesis to {1}' -f $state.Sequence, $state.LastHash)
        exit 0
    }
}
