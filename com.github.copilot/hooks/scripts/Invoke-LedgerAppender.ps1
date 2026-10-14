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
    disk before the append is acknowledged, so an acknowledged record survives a
    crash and an unacknowledged one never appears to have been written.

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
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:StrictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:DigestPattern = '^[0-9a-f]{64}$'
$script:UtcPattern = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z$'
$script:IntegerPattern = '^-?(0|[1-9][0-9]*)$'
$script:SafeInteger = 9007199254740991
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
        Reads one stored line back into the fields the chain check needs. Values
        are compared in their canonical literal form, which is injective, so no
        step of the comparison has to re-parse or re-interpret the text.
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
        PreviousLiteral = ''
        DigestLiteral = ''
        TypeLiteral = ''
        ComputedDigest = ''
    }

    try {
        $document = ConvertFrom-JsonText -Text $Text
    } catch {
        $record.Error = 'is not valid JSON'
        return $record
    }

    try {
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            $record.Error = 'is not a JSON object'
            return $record
        }

        $member = Get-CanonicalMember -Element $document.RootElement
    } catch {
        $record.Error = "is not canonically representable: $($_.Exception.Message)"
        return $record
    } finally {
        $document.Dispose()
    }

    foreach ($required in @('sequence', 'prevSha256', 'recordSha256', 'type', 'runId', 'utc', 'data')) {
        if (-not $member.Contains($required)) {
            $record.Error = "is missing '$required'"
            return $record
        }
    }

    if ([string]$member['sequence'] -cnotmatch $script:IntegerPattern) {
        $record.Error = 'declares a sequence that is not a JSON integer'
        return $record
    }

    $preimageMember = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($key in $member.Keys) {
        if ($key -cne 'recordSha256') {
            $preimageMember[$key] = $member[$key]
        }
    }

    $record.Sequence = [long]$member['sequence']
    $record.PreviousLiteral = [string]$member['prevSha256']
    $record.DigestLiteral = [string]$member['recordSha256']
    $record.TypeLiteral = [string]$member['type']
    $record.ComputedDigest = Get-Sha256Hex -Text (Join-CanonicalMember -Member $preimageMember)

    return $record
}

function Read-ChainState {
    <#
        Rebuilds sequence, last digest, and sealed state by verifying the whole
        chain. A service restart therefore cannot resume onto a chain that was
        tampered with while it was down.
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

    $line = @([System.IO.File]::ReadAllLines($Path, $script:Utf8) | Where-Object { $_.Length -gt 0 })

    $expectedPrevious = $script:GenesisHash
    $priorHash = $script:GenesisHash
    $sequence = 0

    foreach ($text in $line) {
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

        if ($record.PreviousLiteral -cne (ConvertTo-JsonStringLiteral -Value $expectedPrevious)) {
            $state.Error = "record at sequence $sequence does not chain to its predecessor"
            return $state
        }

        if ($record.DigestLiteral -cne (ConvertTo-JsonStringLiteral -Value $record.ComputedDigest)) {
            $state.Error = "record at sequence $sequence fails its own digest"
            return $state
        }

        if ($record.TypeLiteral -ceq (ConvertTo-JsonStringLiteral -Value 'Seal')) {
            $state.Sealed = $true
        }

        $priorHash = $expectedPrevious
        $expectedPrevious = $record.ComputedDigest
    }

    $state.Sequence = $sequence
    $state.LastHash = $expectedPrevious
    $state.PreviousHash = $priorHash

    return $state
}

function Write-ChainHead {
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

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $bytes = $script:Utf8.GetBytes($head)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }
}

function Add-Record {
    <#
        Persist before acknowledging. The sink write is flushed through the
        operating-system cache, then the head, and only then does the caller
        learn the sequence.
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
    } finally {
        $stream.Dispose()
    }

    $sealed = [bool]$State.Sealed -or (($Record.GetProperty('type')).GetString() -ceq 'Seal')
    Write-ChainHead -Path $HeadPath -Sequence $sequence -RecordHash $stored.RecordSha256 -Sealed $sealed

    $State.Sequence = $sequence
    $State.LastHash = $stored.RecordSha256
    $State.Sealed = $sealed

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
        $sinkDirectory = Split-Path -Parent $SinkPath
        if ($sinkDirectory -and -not (Test-Path -LiteralPath $sinkDirectory)) {
            $null = New-Item -Path $sinkDirectory -ItemType Directory -Force
        }

        $state = Read-ChainState -Path $SinkPath -HeadPath $ChainHeadPath
        if ($state.Error) {
            Write-Refusal -Message "existing ledger is not valid: $($state.Error)"
            exit 2
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

        try {
            $head = Get-Content -LiteralPath $ChainHeadPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Refusal -Message 'chain head is not valid JSON'
            exit 2
        }

        if ([int]$head.sequence -ne $state.Sequence) {
            Write-Refusal -Message ("chain head names sequence {0} but the ledger ends at {1}" -f $head.sequence, $state.Sequence)
            exit 2
        }

        if ([string]$head.recordSha256 -ne $state.LastHash) {
            Write-Refusal -Message 'chain head digest does not match the final record'
            exit 2
        }

        Write-Output ('Valid: {0} records from genesis to {1}' -f $state.Sequence, $state.LastHash)
        exit 0
    }
}
