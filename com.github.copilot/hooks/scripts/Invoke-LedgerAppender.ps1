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

function Write-Refusal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    [Console]::Error.WriteLine("Ledger appender refused: $Message")
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

function ConvertTo-CanonicalJson {
    <#
        A digest is only meaningful over bytes both sides derive the same way.
        ConvertTo-Json varies its key order, spacing, and escaping between
        versions, so the preimage is built here instead: keys sorted ordinal,
        no insignificant whitespace, invariant number formatting.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return 'null'
    }

    if ($InputObject -is [string]) {
        return ConvertTo-JsonStringLiteral -Value ([string]$InputObject)
    }

    if ($InputObject -is [bool]) {
        if ($InputObject) { return 'true' } else { return 'false' }
    }

    if ($InputObject -is [byte] -or $InputObject -is [int16] -or $InputObject -is [int] -or $InputObject -is [long]) {
        return ([long]$InputObject).ToString([cultureinfo]::InvariantCulture)
    }

    if ($InputObject -is [decimal] -or $InputObject -is [double] -or $InputObject -is [single]) {
        return ([decimal]$InputObject).ToString([cultureinfo]::InvariantCulture)
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $pair = foreach ($key in @($InputObject.Keys) | Sort-Object -CaseSensitive) {
            '{0}:{1}' -f (ConvertTo-CanonicalJson -InputObject ([string]$key)), (ConvertTo-CanonicalJson -InputObject $InputObject[$key])
        }

        return '{' + ($pair -join ',') + '}'
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $property = $InputObject.PSObject.Properties
        $pair = foreach ($name in @($property.Name) | Sort-Object -CaseSensitive) {
            '{0}:{1}' -f (ConvertTo-CanonicalJson -InputObject $name), (ConvertTo-CanonicalJson -InputObject $property[$name].Value)
        }

        return '{' + ($pair -join ',') + '}'
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $item = foreach ($element in $InputObject) {
            ConvertTo-CanonicalJson -InputObject $element
        }

        return '[' + ($item -join ',') + ']'
    }

    return ConvertTo-JsonStringLiteral -Value ([string]$InputObject)
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

function Get-RecordPreimage {
    <#
        Fixed key order, and deliberately excludes recordSha256: the digest
        cannot cover itself. Validation rebuilds this from the stored line.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int]$Sequence,

        [Parameter(Mandatory)]
        [string]$PreviousHash,

        [Parameter(Mandatory)]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Utc,

        [Parameter()]
        [AllowNull()]
        $Data
    )

    $field = @(
        '"sequence":{0}' -f $Sequence
        '"prevSha256":{0}' -f (ConvertTo-CanonicalJson -InputObject $PreviousHash)
        '"type":{0}' -f (ConvertTo-CanonicalJson -InputObject $Type)
        '"runId":{0}' -f (ConvertTo-CanonicalJson -InputObject $RunId)
        '"utc":{0}' -f (ConvertTo-CanonicalJson -InputObject $Utc)
        '"data":{0}' -f (ConvertTo-CanonicalJson -InputObject $Data)
    )

    return '{' + ($field -join ',') + '}'
}

function Test-RecordSchema {
    <#
        The record schema is closed. An unknown field is refused rather than
        ignored, so a caller cannot smuggle a command, path, or authorization
        claim through the ledger into anything that later reads it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Record
    )

    if ($Record -isnot [System.Management.Automation.PSCustomObject]) {
        return 'record must be a JSON object'
    }

    $present = @($Record.PSObject.Properties.Name)

    foreach ($required in $script:RequiredField) {
        if ($required -notin $present) {
            return "missing required field '$required'"
        }
    }

    foreach ($name in $present) {
        if ($name -notin $script:RequiredField) {
            return "unknown field '$name'"
        }
    }

    foreach ($name in @('type', 'runId', 'utc')) {
        if ([string]::IsNullOrWhiteSpace([string]$Record.$name)) {
            return "field '$name' must be a non-empty string"
        }
    }

    return ''
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
        Sealed = $false
        Error = ''
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if (Test-Path -LiteralPath $HeadPath -PathType Leaf) {
            $state.Error = 'chain head exists without a ledger sink'
        }

        return $state
    }

    $line = @(
        [System.IO.File]::ReadAllLines($Path, $script:Utf8) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $expectedPrevious = $script:GenesisHash
    $sequence = 0

    foreach ($text in $line) {
        $sequence++

        try {
            $record = $text | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $state.Error = "record at sequence $sequence is not valid JSON"
            return $state
        }

        foreach ($required in @('sequence', 'prevSha256', 'recordSha256', 'type', 'runId', 'utc', 'data')) {
            if ($required -notin @($record.PSObject.Properties.Name)) {
                $state.Error = "record at sequence $sequence is missing '$required'"
                return $state
            }
        }

        if ([int]$record.sequence -ne $sequence) {
            $state.Error = "record at sequence $sequence declares sequence $($record.sequence)"
            return $state
        }

        if ([string]$record.prevSha256 -ne $expectedPrevious) {
            $state.Error = "record at sequence $sequence does not chain to its predecessor"
            return $state
        }

        $preimage = Get-RecordPreimage -Sequence $sequence -PreviousHash ([string]$record.prevSha256) `
            -Type ([string]$record.type) -RunId ([string]$record.runId) -Utc ([string]$record.utc) -Data $record.data
        $computed = Get-Sha256Hex -Text $preimage

        if ($computed -ne [string]$record.recordSha256) {
            $state.Error = "record at sequence $sequence fails its own digest"
            return $state
        }

        if ([string]$record.type -eq 'Seal') {
            $state.Sealed = $true
        }

        $expectedPrevious = $computed
    }

    $state.Sequence = $sequence
    $state.LastHash = $expectedPrevious

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

    $head = [ordered]@{
        sequence = $Sequence
        recordSha256 = $RecordHash
        updatedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        sealed = $Sealed
    } | ConvertTo-Json -Compress

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
        $Record,

        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$HeadPath
    )

    $sequence = [int]$State.Sequence + 1
    $previous = [string]$State.LastHash

    $preimage = Get-RecordPreimage -Sequence $sequence -PreviousHash $previous `
        -Type ([string]$Record.type) -RunId ([string]$Record.runId) -Utc ([string]$Record.utc) -Data $Record.data
    $recordHash = Get-Sha256Hex -Text $preimage

    # The stored line is the preimage with the digest spliced in before the
    # closing brace, so the bytes that were hashed remain literally present.
    $line = $preimage.Substring(0, $preimage.Length - 1) + (',"recordSha256":"{0}"}}' -f $recordHash)

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $bytes = $script:Utf8.GetBytes($line + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }

    $sealed = [bool]$State.Sealed -or ([string]$Record.type -eq 'Seal')
    Write-ChainHead -Path $HeadPath -Sequence $sequence -RecordHash $recordHash -Sealed $sealed

    $State.Sequence = $sequence
    $State.LastHash = $recordHash
    $State.Sealed = $sealed

    return @{
        sequence = $sequence
        recordSha256 = $recordHash
    }
}

function New-RestrictedPipeServer {
    <#
        The pipe is the authentication boundary: on Windows only the allowed
        identity gets an ACE, so an unauthorized caller cannot open it at all.
        Failing to apply the ACL is fatal rather than degraded, because a
        default DACL would silently widen who may append evidence.
    #>
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
                    $request = $null
                    try {
                        $request = $requestText | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        $response.message = 'request is not valid JSON'
                    }

                    if ($null -ne $request) {
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
                $intended = $RecordJson | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-Refusal -Message 'record is not valid JSON'
                exit 2
            }

            if ([string]$intended.type -ne 'Seal') {
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
