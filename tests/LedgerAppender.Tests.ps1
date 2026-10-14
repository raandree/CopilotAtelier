# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:appenderScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Invoke-LedgerAppender.ps1'
    $script:powerShellPath = (Get-Process -Id $PID).Path

    # The appender is a service: only its own identity may write the sink, so
    # every case drives it the way the controller does, over the pipe, rather
    # than dot-sourcing internals that production callers cannot reach.
    function script:Start-TestAppender {
        param(
            [Parameter(Mandatory)]
            [string]$PipeName,

            [Parameter(Mandatory)]
            [string]$SinkPath,

            [Parameter(Mandatory)]
            [string]$ChainHeadPath,

            [Parameter()]
            [string]$AllowedIdentity,

            # Culture is a deliberate lever: a culture-ordered sort produces a
            # different canonical form, so the vectors are driven under a
            # culture whose collation differs from ordinal.
            [Parameter()]
            [string]$Culture,

            [Parameter()]
            [switch]$SkipReadiness
        )

        $argument = @(
            "-Serve"
            "-PipeName '$PipeName'"
            "-SinkPath '$($SinkPath.Replace("'", "''"))'"
            "-ChainHeadPath '$($ChainHeadPath.Replace("'", "''"))'"
            '-IdleTimeoutSeconds 30'
        )

        if ($AllowedIdentity) {
            $argument += "-AllowedIdentity '$($AllowedIdentity.Replace("'", "''"))'"
        }

        $cultureLine = ''
        if ($Culture) {
            $cultureLine = @"
[System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('$Culture')
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('$Culture')
"@
        }

        # EncodedCommand keeps the culture assignment and the call in one
        # process without fighting Start-Process argument quoting.
        $payload = @"
$cultureLine
& '$($script:appenderScript.Replace("'", "''"))' $($argument -join ' ')
exit `$LASTEXITCODE
"@
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($payload))

        $process = Start-Process -FilePath $script:powerShellPath -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded
        )

        if ($SkipReadiness) {
            return $process
        }

        # Readiness is the pipe accepting a connection, not the process existing.
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline) {
            $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
            try {
                $client.Connect(250)
                $client.Dispose()
                return $process
            } catch {
                $client.Dispose()
                Start-Sleep -Milliseconds 100
            }
        }

        throw "Appender did not start listening on $PipeName."
    }

    function script:Invoke-Appender {
        param(
            [Parameter(Mandatory)]
            [string[]]$Argument
        )

        $arguments = @('-NoProfile', '-NonInteractive', '-File', $script:appenderScript) + $Argument

        <#
            The appender reports refusal by writing to standard error and exiting
            2. Windows PowerShell surfaces a child's standard error as an
            ErrorRecord and PowerShell 7.3+ turns a non-zero native exit code
            into a terminating error, so the expected refusal would throw instead
            of being asserted on under the build's Stop preference.
        #>
        $previousErrorActionPreference = $ErrorActionPreference
        $previousNativeCommandPreference = $null

        if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
            $previousNativeCommandPreference = $PSNativeCommandUseErrorActionPreference
        }

        try {
            $ErrorActionPreference = 'Continue'

            if ($null -ne $previousNativeCommandPreference) {
                $PSNativeCommandUseErrorActionPreference = $false
            }

            $output = & $script:powerShellPath @arguments 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference

            if ($null -ne $previousNativeCommandPreference) {
                $PSNativeCommandUseErrorActionPreference = $previousNativeCommandPreference
            }
        }

        [pscustomobject]@{
            ExitCode = $exitCode
            Output = ($output | Out-String)
        }
    }

    function script:Invoke-Append {
        param(
            [Parameter(Mandatory)]
            [string]$PipeName,

            [Parameter(Mandatory)]
            [string]$RecordJson,

            [Parameter()]
            [string]$SinkPath = $script:sinkPath,

            [Parameter()]
            [string]$ChainHeadPath = $script:headPath
        )

        Invoke-Appender -Argument @(
            '-Append', '-PipeName', $PipeName, '-RecordJson', $RecordJson,
            '-SinkPath', $SinkPath, '-ChainHeadPath', $ChainHeadPath
        )
    }

    function script:ConvertTo-ProcessArgument {
        <#
            Quotes one argument the way CommandLineToArgvW reads it back:
            Start-Process joins an array with spaces and escapes nothing, so a
            record's double quotes would reach the child as word boundaries.
            Backslashes only matter in front of a quote or at the end.
        #>
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Value
        )

        $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
        $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')

        return '"' + $escaped + '"'
    }

    function script:Invoke-AppenderSplit {
        <#
            Keeps standard output and standard error apart, because the
            -Validate contract is about what reaches standard output: on a
            refusal it must stay empty, and a refusal is one line. The streams
            go to files, so nothing wraps them to a console width.
        #>
        param(
            [Parameter(Mandatory)]
            [string[]]$Argument
        )

        $outPath = Join-Path $TestDrive "out-$([guid]::NewGuid().ToString('N')).txt"
        $errPath = Join-Path $TestDrive "err-$([guid]::NewGuid().ToString('N')).txt"

        $commandLine = (
            @('-NoProfile', '-NonInteractive', '-File', $script:appenderScript) + $Argument |
                ForEach-Object { ConvertTo-ProcessArgument -Value $_ }
        ) -join ' '

        $process = Start-Process -FilePath $script:powerShellPath -PassThru -Wait -WindowStyle Hidden `
            -RedirectStandardOutput $outPath -RedirectStandardError $errPath -ArgumentList $commandLine

        $standardOutput = ''
        if (Test-Path -LiteralPath $outPath -PathType Leaf) {
            $standardOutput = [System.IO.File]::ReadAllText($outPath)
        }

        $standardError = ''
        if (Test-Path -LiteralPath $errPath -PathType Leaf) {
            $standardError = [System.IO.File]::ReadAllText($errPath)
        }

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $standardOutput
            StandardError = $standardError
        }
    }

    function script:New-TestProfile {
        <#
            The same document shape the containment verifier reads. Only
            ledgerSink, chainHead and ledgerAppender matter to the appender.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$ProfilePath,

            [Parameter(Mandatory)]
            [string]$SinkPath,

            [Parameter(Mandatory)]
            [string]$ChainHeadPath,

            [Parameter()]
            [string]$AppenderPath = $script:appenderScript,

            [Parameter()]
            [string]$AppenderSha256
        )

        if (-not $AppenderSha256) {
            $AppenderSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:appenderScript).Hash.ToLowerInvariant()
        }

        $pinned = @{ path = $AppenderPath; sha256 = $AppenderSha256 }
        $content = [ordered]@{
            schemaVersion = 1
            verifier = $pinned
            hooksConfig = $pinned
            hookScript = $pinned
            ledgerAppender = $pinned
            ledgerSink = $SinkPath
            chainHead = $ChainHeadPath
            controllerEgressAllow = @()
            workerEgressAllow = @()
            controllerIdentity = 'CONTOSO\controller'
            workerIdentity = 'CONTOSO\worker'
            immutableControlPaths = @()
            writableRoots = @()
        } | ConvertTo-Json -Depth 8

        [System.IO.File]::WriteAllBytes($ProfilePath, [System.Text.UTF8Encoding]::new($false).GetBytes($content))

        return (Get-FileHash -Algorithm SHA256 -LiteralPath $ProfilePath).Hash.ToLowerInvariant()
    }

    function script:Invoke-RawRequest {
        <#
            Talks to the service without the client's envelope, so the server's
            own request schema is what is under test.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$PipeName,

            [Parameter(Mandatory)]
            [string]$Payload
        )

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
        try {
            $client.Connect(5000)

            $writer = [System.IO.StreamWriter]::new($client, $utf8, 4096, $true)
            $writer.AutoFlush = $true
            $writer.WriteLine($Payload)
            $writer.Dispose()

            $reader = [System.IO.StreamReader]::new($client, $utf8, $false, 4096, $true)
            try {
                return $reader.ReadLine()
            } finally {
                $reader.Dispose()
            }
        } finally {
            $client.Dispose()
        }
    }

    function script:Invoke-Seal {
        param(
            [Parameter(Mandatory)]
            [string]$PipeName,

            [Parameter(Mandatory)]
            [string]$RecordJson,

            [Parameter()]
            [string]$SinkPath = $script:sinkPath,

            [Parameter()]
            [string]$ChainHeadPath = $script:headPath
        )

        Invoke-Appender -Argument @(
            '-Seal', '-PipeName', $PipeName, '-RecordJson', $RecordJson,
            '-SinkPath', $SinkPath, '-ChainHeadPath', $ChainHeadPath
        )
    }

    function script:New-TestSealJson {
        [ordered]@{
            type = 'Seal'
            runId = 'run-0001'
            utc = '2026-09-02T22:10:00Z'
            data = @{ reason = 'run complete' }
        } | ConvertTo-Json -Depth 8 -Compress
    }

    function script:Invoke-Validate {
        param(
            [Parameter(Mandatory)]
            [string]$SinkPath,

            [Parameter(Mandatory)]
            [string]$ChainHeadPath
        )

        Invoke-Appender -Argument @('-Validate', '-SinkPath', $SinkPath, '-ChainHeadPath', $ChainHeadPath)
    }

    function script:Invoke-Serve {
        <#
            Runs the service in the foreground. Every case that uses it expects
            the start itself to be refused, so it returns rather than listens.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$PipeName,

            [Parameter(Mandatory)]
            [string]$SinkPath,

            [Parameter(Mandatory)]
            [string]$ChainHeadPath
        )

        Invoke-Appender -Argument @(
            '-Serve', '-PipeName', $PipeName, '-SinkPath', $SinkPath,
            '-ChainHeadPath', $ChainHeadPath, '-IdleTimeoutSeconds', '5'
        )
    }

    function script:New-TestRecordJson {
        param(
            [Parameter(Mandatory)]
            [string]$Type,

            [Parameter()]
            [hashtable]$Data = @{ note = 'test' }
        )

        [ordered]@{
            type = $Type
            runId = 'run-0001'
            utc = '2026-09-02T22:00:00Z'
            data = $Data
        } | ConvertTo-Json -Depth 8 -Compress
    }

    function script:Get-TestSha256 {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Text
        )

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
            return [System.Convert]::ToHexString($sha256.ComputeHash($bytes)).ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
    }

    function script:New-ForgedLine {
        <#
            Builds a stored line the way somebody with write access to the sink
            would: canonical member order and a digest computed over the same
            preimage the appender would hash. A control that only recomputes the
            digest therefore cannot tell the difference.
        #>
        param(
            [Parameter(Mandatory)]
            [string[]]$Member
        )

        $preimage = '{' + ($Member -join ',') + '}'
        $digest = Get-TestSha256 -Text $preimage

        $all = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $Member) {
            $all.Add($entry)
            if ($entry.StartsWith('"prevSha256":')) {
                $all.Add('"recordSha256":"' + $digest + '"')
            }
        }

        return [pscustomobject]@{
            Line = '{' + ($all -join ',') + '}'
            Digest = $digest
        }
    }

    function script:Set-ChainHead {
        param(
            [Parameter(Mandatory)]
            [string]$ChainHeadPath,

            [Parameter(Mandatory)]
            [int]$Sequence,

            [Parameter(Mandatory)]
            [string]$RecordSha256,

            [Parameter()]
            [switch]$Sealed
        )

        $sealedText = if ($Sealed) { 'true' } else { 'false' }
        $text = '{"recordSha256":"' + $RecordSha256 + '","sealed":' + $sealedText +
            ',"sequence":' + $Sequence + ',"updatedUtc":"2026-09-02T22:00:00Z"}'
        [System.IO.File]::WriteAllBytes($ChainHeadPath, [System.Text.UTF8Encoding]::new($false).GetBytes($text))
    }

    function script:Stop-TestAppender {
        <#
            The service holds the sink open, so a test that rewrites the sink
            has to wait for the process to be gone, not merely asked to stop.
        #>
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Process
        )

        if (-not $Process) {
            return
        }

        if (-not $Process.HasExited) {
            $Process | Stop-Process -Force -ErrorAction SilentlyContinue
        }

        $null = $Process.WaitForExit(15000)
    }

    function script:Test-PipeName {
        <#
            Enumerates the pipe namespace. Opening \\.\pipe\<name> with
            Test-Path counts as a connection and faults the server's pending
            wait, so an existence check must never touch the path itself.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$PipeName
        )

        foreach ($entry in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
            if ([System.IO.Path]::GetFileName($entry) -ceq $PipeName) {
                return $true
            }
        }

        return $false
    }

    function script:Get-SharedByte {
        <#
            The service holds its sink open for its whole life, so a reader has
            to tolerate that writer. File.ReadAllBytes does not.
        #>
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
                if ($count -le 0) { break }
                $read += $count
            }

            return $buffer
        } finally {
            $stream.Dispose()
        }
    }

    function script:Start-HostileServer {
        <#
            A squatter on the appender's pipe name, running as the test identity.
            It captures whatever a client sends and answers with a well-formed
            acknowledgement it made up. -ResponseBase64 lets a case choose the
            exact answer line; it travels encoded so that a response holding
            control characters survives the command line unchanged.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$PipeName,

            [Parameter(Mandatory)]
            [string]$CapturePath,

            [Parameter()]
            [switch]$GrantEveryone,

            [Parameter()]
            [string]$ResponseBase64 = ''
        )

        $scriptPath = Join-Path $TestDrive "hostile-$([guid]::NewGuid().ToString('N')).ps1"
        @'
param([string]$PipeName, [string]$CapturePath, [string]$GrantEveryone, [string]$ResponseBase64)

$security = [System.IO.Pipes.PipeSecurity]::new()
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new($me.User,
        [System.IO.Pipes.PipeAccessRights]::ReadWrite -bor [System.IO.Pipes.PipeAccessRights]::CreateNewInstance,
        [System.Security.AccessControl.AccessControlType]::Allow))

if ($GrantEveryone -eq 'yes') {
    $security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new(
            [System.Security.Principal.SecurityIdentifier]::new('S-1-1-0'),
            [System.IO.Pipes.PipeAccessRights]::ReadWrite,
            [System.Security.AccessControl.AccessControlType]::Allow))
}

$server = [System.IO.Pipes.NamedPipeServerStreamAcl]::Create($PipeName,
    [System.IO.Pipes.PipeDirection]::InOut, 2, [System.IO.Pipes.PipeTransmissionMode]::Byte,
    [System.IO.Pipes.PipeOptions]::Asynchronous, 0, 0, $security)

$utf8 = [System.Text.UTF8Encoding]::new($false)
$response = '{"status":"Ok","message":"","sequence":1,"recordSha256":"' + ('f' * 64) + '"}'

if (-not [string]::IsNullOrEmpty($ResponseBase64)) {
    $response = $utf8.GetString([System.Convert]::FromBase64String($ResponseBase64))
}

try {
    if (-not $server.WaitForConnectionAsync().Wait(30000)) { return }

    $reader = [System.IO.StreamReader]::new($server, $utf8, $false, 4096, $true)
    $writer = [System.IO.StreamWriter]::new($server, $utf8, 4096, $true)
    $writer.AutoFlush = $true

    $request = $reader.ReadLine()
    [System.IO.File]::WriteAllText($CapturePath, [string]$request)

    $writer.WriteLine($response)
    $server.WaitForPipeDrain()
} finally {
    $server.Dispose()
}
'@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8

        $argument = @(
            '-NoProfile', '-NonInteractive', '-File', $scriptPath, '-PipeName', $PipeName,
            '-CapturePath', $CapturePath, '-GrantEveryone', $(if ($GrantEveryone) { 'yes' } else { 'no' })
        )

        # An empty element would reach the child as a switch without a value and
        # the squatter would never start, so the response is only named when
        # there is one.
        if (-not [string]::IsNullOrEmpty($ResponseBase64)) {
            $argument += @('-ResponseBase64', $ResponseBase64)
        }

        $process = Start-Process -FilePath $script:powerShellPath -PassThru -WindowStyle Hidden -ArgumentList $argument

        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline) {
            if (Test-PipeName -PipeName $PipeName) {
                return $process
            }

            Start-Sleep -Milliseconds 100
        }

        throw "Hostile server did not take $PipeName."
    }

    function script:ConvertTo-HostileResponse {
        <#
            Encodes one response line for Start-HostileServer.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$Response
        )

        return [System.Convert]::ToBase64String([System.Text.UTF8Encoding]::new($false).GetBytes($Response))
    }

    function script:Get-SinkRecord {
        param(
            [Parameter(Mandatory)]
            [string]$SinkPath
        )

        @(
            Get-SinkLine -SinkPath $SinkPath |
                ForEach-Object { $_ | ConvertFrom-Json }
        )
    }

    function script:Get-SinkLine {
        <#
            The stored bytes are the evidence, so the tests read them rather
            than a re-serialization of a parse: Get-Content would hide a BOM,
            a CRLF, or a stray space that the canonical form forbids.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$SinkPath
        )

        if (-not (Test-Path -LiteralPath $SinkPath -PathType Leaf)) {
            return [string[]]@()
        }

        $bytes = Get-SharedByte -Path $SinkPath
        if ($bytes.Length -eq 0) {
            return [string[]]@()
        }

        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        return [string[]]@($text -split "`n" | Where-Object { $_.Length -gt 0 })
    }

    function script:Set-SinkLine {
        <#
            Writes exactly the given lines, each terminated by a single LF and
            no BOM, so a test can plant one altered byte without the writer
            adding any of its own.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$SinkPath,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line
        )

        $text = ($Line | ForEach-Object { $_ + "`n" }) -join ''
        [System.IO.File]::WriteAllBytes($SinkPath, [System.Text.UTF8Encoding]::new($false).GetBytes($text))
    }
}

Describe 'Ledger appender' -Tag 'Unit' {
    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
    }

    AfterEach {
        if ($script:appender -and -not $script:appender.HasExited) {
            $script:appender | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ships an appender script' {
        Test-Path -LiteralPath $script:appenderScript -PathType Leaf |
            Should -BeTrue -Because $script:appenderScript
    }

    It 'assigns a monotonic sequence starting at one' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        foreach ($type in @('Baseline', 'ProbeResult', 'ReviewRequested')) {
            $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type $type)
            $result.ExitCode | Should -Be 0 -Because $result.Output
        }

        $records = Get-SinkRecord -SinkPath $script:sinkPath
        $records.Count | Should -Be 3
        $records.sequence | Should -Be @(1, 2, 3)
    }

    It 'anchors the genesis record on an all-zero previous hash' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $records = Get-SinkRecord -SinkPath $script:sinkPath
        $records[0].prevSha256 | Should -Be ('0' * 64)
        $records[0].recordSha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'links every record to its predecessor' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        foreach ($step in 1..4) {
            $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")
            $result.ExitCode | Should -Be 0 -Because $result.Output
        }

        $records = Get-SinkRecord -SinkPath $script:sinkPath
        for ($index = 1; $index -lt $records.Count; $index++) {
            $records[$index].prevSha256 |
                Should -Be $records[$index - 1].recordSha256 -Because "record $($index + 1) must chain to its predecessor"
        }
    }

    It 'advances the protected chain head to the newest record' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        foreach ($step in 1..2) {
            $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")
            $result.ExitCode | Should -Be 0 -Because $result.Output
        }

        $records = Get-SinkRecord -SinkPath $script:sinkPath
        $head = Get-Content -LiteralPath $script:headPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $head.sequence | Should -Be 2
        $head.recordSha256 | Should -Be $records[-1].recordSha256
    }

    It 'validates an untouched chain from genesis' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        foreach ($step in 1..3) {
            $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")
            $result.ExitCode | Should -Be 0 -Because $result.Output
        }

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 0 -Because $validation.Output
        $validation.Output | Should -Match '"valid":true'
    }

    It 'rejects a record whose body was rewritten' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        foreach ($step in 1..3) {
            $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")
            $result.ExitCode | Should -Be 0 -Because $result.Output
        }
        Stop-TestAppender -Process $script:appender

        $lines = @(Get-SinkLine -SinkPath $script:sinkPath)
        $lines[1] = $lines[1] -replace '"note":"test"', '"note":"tampered"'
        Set-SinkLine -SinkPath $script:sinkPath -Line $lines

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'sequence 2'
    }

    It 'rejects a truncated chain' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        foreach ($step in 1..3) {
            $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")
            $result.ExitCode | Should -Be 0 -Because $result.Output
        }
        Stop-TestAppender -Process $script:appender

        $lines = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line $lines[0..1]

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'head'
    }

    It 'rejects a rewritten chain head' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Stop-TestAppender -Process $script:appender

        @{ sequence = 1; recordSha256 = ('a' * 64); updatedUtc = '2026-09-02T22:00:00Z'; sealed = $false } |
            ConvertTo-Json | Set-Content -LiteralPath $script:headPath -Encoding UTF8

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }

    It 'fails closed on a missing sink rather than reporting an empty chain valid' {
        $validation = Invoke-Validate -SinkPath (Join-Path $TestDrive 'absent.jsonl') -ChainHeadPath (Join-Path $TestDrive 'absent.json')
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }

    It 'refuses a record carrying an unknown field' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $malformed = [ordered]@{
            type = 'Baseline'
            runId = 'run-0001'
            utc = '2026-09-02T22:00:00Z'
            data = @{ note = 'test' }
            command = 'git push'
        } | ConvertTo-Json -Depth 8 -Compress

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $malformed
        $result.ExitCode | Should -Be 2 -Because $result.Output
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0 -Because 'a refused record is never stored'
    }

    It 'refuses a record missing a required field' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $malformed = [ordered]@{
            type = 'Baseline'
            utc = '2026-09-02T22:00:00Z'
            data = @{ note = 'test' }
        } | ConvertTo-Json -Depth 8 -Compress

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $malformed
        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'refuses to append after the ledger is sealed' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $sealJson = [ordered]@{
            type = 'Seal'
            runId = 'run-0001'
            utc = '2026-09-02T22:10:00Z'
            data = @{ reason = 'run complete' }
        } | ConvertTo-Json -Depth 8 -Compress

        $seal = Invoke-Appender -Argument @(
            '-Seal', '-PipeName', $script:pipeName, '-RecordJson', $sealJson,
            '-SinkPath', $script:sinkPath, '-ChainHeadPath', $script:headPath
        )
        $seal.ExitCode | Should -Be 0 -Because $seal.Output

        $late = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Late')
        $late.ExitCode | Should -Be 2 -Because $late.Output
    }
}

Describe 'Ledger appender canonical form' -Tag 'Unit' {
    BeforeDiscovery {
        <#
            Pinned vectors. The expected lines and digests were built by hand
            and hashed with an independent implementation (Node's crypto), not
            by this script, so a change in the serializer cannot quietly move
            the expectation with it. A record is the first in a fresh ledger,
            so its sequence is 1 and its prevSha256 is the genesis hash.
        #>
        $script:canonicalVector = @(
            @{
                Name = 'mixed-case keys'
                RecordJson = '{"type":"Baseline","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{"b":1,"A":2,"a":3,"B":4,"ab":5,"aB":6}}'
                ExpectedLine = '{"data":{"A":2,"B":4,"a":3,"aB":6,"ab":5,"b":1},"prevSha256":"0000000000000000000000000000000000000000000000000000000000000000","recordSha256":"e5b9ff7668b93fa59298499432d04dd6f12c53645dbb6037a869ff2d6c1502cd","runId":"run-0001","sequence":1,"type":"Baseline","utc":"2026-09-02T22:00:00Z"}'
                ExpectedSha256 = 'e5b9ff7668b93fa59298499432d04dd6f12c53645dbb6037a869ff2d6c1502cd'
            }
            @{
                Name = 'a non-ASCII key'
                RecordJson = '{"type":"Baseline","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{"caf\u00e9":"cr\u00e8me","\u6f22":"\u5b57"}}'
                ExpectedLine = '{"data":{"caf\u00E9":"cr\u00E8me","\u6F22":"\u5B57"},"prevSha256":"0000000000000000000000000000000000000000000000000000000000000000","recordSha256":"cdf9bb06976101c79a9b60ceb5598f3899bf616d24ce5de38e6a0471c277bdf3","runId":"run-0001","sequence":1,"type":"Baseline","utc":"2026-09-02T22:00:00Z"}'
                ExpectedSha256 = 'cdf9bb06976101c79a9b60ceb5598f3899bf616d24ce5de38e6a0471c277bdf3'
            }
            @{
                Name = 'a nested object'
                RecordJson = '{"type":"ProbeResult","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{"outer":{"z":{"y":[3,1,2],"x":null},"a":true},"list":[{"b":2,"a":1},"x"]}}'
                ExpectedLine = '{"data":{"list":[{"a":1,"b":2},"x"],"outer":{"a":true,"z":{"x":null,"y":[3,1,2]}}},"prevSha256":"0000000000000000000000000000000000000000000000000000000000000000","recordSha256":"df10160e5efde976345a37daca7b23903eea98503cb33ef52948bd3b8054ce8f","runId":"run-0001","sequence":1,"type":"ProbeResult","utc":"2026-09-02T22:00:00Z"}'
                ExpectedSha256 = 'df10160e5efde976345a37daca7b23903eea98503cb33ef52948bd3b8054ce8f'
            }
            @{
                Name = 'an ISO utc'
                RecordJson = '{"type":"Baseline","runId":"2026-09-02T22:00:00Z","utc":"2026-09-02T22:00:00.1234567Z","data":{"when":"2026-09-02T22:00:00Z"}}'
                ExpectedLine = '{"data":{"when":"2026-09-02T22:00:00Z"},"prevSha256":"0000000000000000000000000000000000000000000000000000000000000000","recordSha256":"314571e6bc8cb434d9a498a4571dd9f8f2c0fecae74ee9f24f90118ca9c8b22d","runId":"2026-09-02T22:00:00Z","sequence":1,"type":"Baseline","utc":"2026-09-02T22:00:00.1234567Z"}'
                ExpectedSha256 = '314571e6bc8cb434d9a498a4571dd9f8f2c0fecae74ee9f24f90118ca9c8b22d'
            }
            @{
                Name = 'a large but safe integer'
                RecordJson = '{"type":"Baseline","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{"max":9007199254740991,"min":-9007199254740991,"zero":-0}}'
                ExpectedLine = '{"data":{"max":9007199254740991,"min":-9007199254740991,"zero":0},"prevSha256":"0000000000000000000000000000000000000000000000000000000000000000","recordSha256":"b324ecfff0e74e5b118c3506dbc6463b796b62b61b0a44b68ba0821320b7ebb6","runId":"run-0001","sequence":1,"type":"Baseline","utc":"2026-09-02T22:00:00Z"}'
                ExpectedSha256 = 'b324ecfff0e74e5b118c3506dbc6463b796b62b61b0a44b68ba0821320b7ebb6'
            }
            @{
                Name = 'characters the escaper rewrites'
                RecordJson = '{"type":"Baseline","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{"s":"a<b>&''\"\\\u0001\t"}}'
                ExpectedLine = '{"data":{"s":"a\u003Cb\u003E\u0026\u0027\u0022\\\u0001\t"},"prevSha256":"0000000000000000000000000000000000000000000000000000000000000000","recordSha256":"dc1818d0d0735112b6aba02d5e4ad2bdde9f17fce8520cb3867d5fa35c6a7315","runId":"run-0001","sequence":1,"type":"Baseline","utc":"2026-09-02T22:00:00Z"}'
                ExpectedSha256 = 'dc1818d0d0735112b6aba02d5e4ad2bdde9f17fce8520cb3867d5fa35c6a7315'
            }
        )

        $script:unsafeNumber = @(
            @{ Name = 'an exponent'; Value = '1e20' }
            @{ Name = 'an integral exponent'; Value = '1E2' }
            @{ Name = 'a fraction'; Value = '1.5' }
            @{ Name = 'a trailing zero fraction'; Value = '1.0' }
            @{ Name = 'an integer above 2^53-1'; Value = '9007199254740992' }
            @{ Name = 'an integer below -(2^53-1)'; Value = '-9007199254740992' }
        )
    }

    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
    }

    AfterEach {
        if ($script:appender -and -not $script:appender.HasExited) {
            $script:appender | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    It 'stores <Name> as the pinned canonical line' -ForEach $script:canonicalVector -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $RecordJson
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        $line.Count | Should -Be 1
        $line[0] | Should -BeExactly $ExpectedLine
        $result.Output | Should -Match $ExpectedSha256
    }

    It 'stores the pinned canonical line under a culture whose collation is not ordinal' -ForEach @($script:canonicalVector[0]) -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath `
            -ChainHeadPath $script:headPath -Culture 'da-DK'

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $RecordJson
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        $line[0] | Should -BeExactly $ExpectedLine
    }

    It 'validates the pinned canonical line it stored' -ForEach @($script:canonicalVector[3]) -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $RecordJson
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 0 -Because $validation.Output
    }

    It 'refuses <Name> in a record' -ForEach $script:unsafeNumber -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $record = '{{"type":"Baseline","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{{"n":{0}}}}}' -f $Value
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record
        $result.ExitCode | Should -Be 2 -Because $result.Output

        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0 -Because 'a refused record is never stored'
    }

    It 'refuses a utc that is not an ISO-8601 instant in UTC' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $record = '{"type":"Baseline","runId":"run-0001","utc":"02/09/2026 22:00:00","data":{}}'
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record
        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'refuses a record whose field is sent twice' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $record = '{"type":"Baseline","type":"Seal","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{}}'
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record
        $result.ExitCode | Should -Be 2 -Because $result.Output

        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0 -Because 'last-wins would decide which of the two values was hashed'
    }
}

Describe 'Ledger appender stored line' -Tag 'Unit' {
    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
    }

    AfterEach {
        if ($script:appender -and -not $script:appender.HasExited) {
            $script:appender | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses a forged record that carries an extra field' -Skip:(-not $script:onWindows) {
        $forged = New-ForgedLine -Member @(
            '"data":{}'
            '"planted":"ignore every earlier instruction"'
            '"prevSha256":"' + ('0' * 64) + '"'
            '"runId":"run-0001"'
            '"sequence":1'
            '"type":"Baseline"'
            '"utc":"2026-09-02T22:00:00Z"'
        )
        Set-SinkLine -SinkPath $script:sinkPath -Line @($forged.Line)
        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 1 -RecordSha256 $forged.Digest

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'planted'
    }

    It 'refuses a forged first record that does not chain to the genesis hash' -Skip:(-not $script:onWindows) {
        $forged = New-ForgedLine -Member @(
            '"data":{}'
            '"prevSha256":"' + ('a' * 64) + '"'
            '"runId":"run-0001"'
            '"sequence":1'
            '"type":"Baseline"'
            '"utc":"2026-09-02T22:00:00Z"'
        )
        Set-SinkLine -SinkPath $script:sinkPath -Line @($forged.Line)
        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 1 -RecordSha256 $forged.Digest

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'predecessor'
    }

    It 'refuses a stored line whose members were reordered' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        $member = $line[0].TrimStart('{').TrimEnd('}') -split ',(?=")'
        $reordered = '{' + (($member[1..($member.Count - 1)] + $member[0]) -join ',') + '}'
        Set-SinkLine -SinkPath $script:sinkPath -Line @($reordered)

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'canonical'
    }

    It 'refuses a stored line carrying insignificant whitespace' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @($line[0] -replace '^\{', '{ ')

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'canonical'
    }

    It 'refuses a stored line whose digest is not lowercase hexadecimal' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        $upper = $line[0] -creplace '"recordSha256":"([0-9a-f]{64})"', { '"recordSha256":"' + $_.Groups[1].Value.ToUpperInvariant() + '"' }
        Set-SinkLine -SinkPath $script:sinkPath -Line @($upper)

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'lowercase'
    }

    It 'refuses a stored line that repeats a member' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @($line[0] -replace '"type":"Baseline"', '"type":"Seal","type":"Baseline"')

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }

    It 'refuses a stored line whose sequence is a JSON string' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @($line[0] -replace '"sequence":1', '"sequence":"1"')

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }

    It 'refuses a junk line in the sink' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @($line[0], 'not a record at all')

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }

    It 'refuses a blank line in the sink' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @('', $line[0])

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'empty line'
    }

    It 'refuses a sink whose last record has no line terminator' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $bytes = [System.IO.File]::ReadAllBytes($script:sinkPath)
        [System.IO.File]::WriteAllBytes($script:sinkPath, $bytes[0..($bytes.Length - 2)])

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'terminator|complete'
    }

    It 'refuses a sink that begins with a byte-order mark' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $bytes = [System.IO.File]::ReadAllBytes($script:sinkPath)
        [System.IO.File]::WriteAllBytes($script:sinkPath, ([byte[]]@(0xEF, 0xBB, 0xBF) + $bytes))

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }

    It 'refuses two records that were swapped' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..3) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @($line[1], $line[0], $line[2])

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }

    It 'refuses a record removed from the middle of the chain' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..3) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @($line[0], $line[2])

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }
}

Describe 'Ledger appender restart' -Tag 'Unit' {
    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
    }

    AfterEach {
        if ($script:appender -and -not $script:appender.HasExited) {
            $script:appender | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses to serve a sink that was truncated while it was down' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..3) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender
        $headBefore = [System.IO.File]::ReadAllText($script:headPath)

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line $line[0..1]

        $restart = Invoke-Serve -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $restart.ExitCode | Should -Be 2 -Because $restart.Output
        [System.IO.File]::ReadAllText($script:headPath) |
            Should -BeExactly $headBefore -Because 'a refused start must not adopt the shortened sink'
    }

    It 'refuses to serve when the head names a sequence the sink never reached' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..2) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender

        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 3 -RecordSha256 ('b' * 64)

        $restart = Invoke-Serve -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $restart.ExitCode | Should -Be 2 -Because $restart.Output
    }

    It 'refuses to serve when the head names another record at the same sequence' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 1 -RecordSha256 ('c' * 64)

        $restart = Invoke-Serve -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $restart.ExitCode | Should -Be 2 -Because $restart.Output
    }

    It 'refuses to serve when the head is missing but the sink holds several records' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..2) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender
        Remove-Item -LiteralPath $script:headPath -Force

        $restart = Invoke-Serve -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $restart.ExitCode | Should -Be 2 -Because $restart.Output
    }

    It 'resumes when the head is exactly one record behind the sink' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..2) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender

        # The state a crash between the sink flush and the head write leaves.
        $record = Get-SinkRecord -SinkPath $script:sinkPath
        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 1 -RecordSha256 $record[0].recordSha256

        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Step3')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'sequence 3'

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 0 -Because $validation.Output
    }

    It 'refuses a chain head that is not stored in canonical form' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $head = [System.IO.File]::ReadAllText($script:headPath)
        [System.IO.File]::WriteAllBytes($script:headPath,
            [System.Text.UTF8Encoding]::new($false).GetBytes(($head -replace '^\{', '{ ')))

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'canonical'
    }

    It 'refuses a chain head whose sealed flag contradicts the chain' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $record = Get-SinkRecord -SinkPath $script:sinkPath
        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 1 -RecordSha256 $record[0].recordSha256 -Sealed

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'sealed'
    }

    It 'refuses to validate a head that is one record behind' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..2) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender

        $record = Get-SinkRecord -SinkPath $script:sinkPath
        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 1 -RecordSha256 $record[0].recordSha256

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
    }
}

Describe 'Ledger appender durability' -Tag 'Unit' {
    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
    }

    AfterEach {
        if ($script:appender -and -not $script:appender.HasExited) {
            $script:appender | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates the directory of the chain head' -Skip:(-not $script:onWindows) {
        $script:headPath = Join-Path $TestDrive "protected-$([guid]::NewGuid().ToString('N'))/head.json"
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Test-Path -LiteralPath $script:headPath -PathType Leaf | Should -BeTrue
    }

    It 'does not reuse a sequence after a head write failed' -Skip:(-not $script:onWindows) {
        # A path that cannot become a file is the cheapest stand-in for the
        # review's triggers: a missing directory, an antivirus lock, an I/O error.
        $null = New-Item -Path $script:headPath -ItemType Directory -Force
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $first = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $first.ExitCode | Should -Be 2 -Because 'a record whose head write failed is never acknowledged'

        $script:appender.WaitForExit(15000) | Should -BeTrue -Because 'a head failure stops the service'
        $script:appender.ExitCode | Should -Be 2

        Remove-Item -LiteralPath $script:headPath -Recurse -Force
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $second = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Second')
        $second.ExitCode | Should -Be 0 -Because $second.Output

        $record = Get-SinkRecord -SinkPath $script:sinkPath
        @($record.sequence) | Should -Be @(1, 2) -Because 'the persisted record keeps sequence 1'

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 0 -Because $validation.Output
    }

    It 'stops serving and leaves the head untouched when the head is locked' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0

        $headBefore = [System.IO.File]::ReadAllText($script:headPath)
        $lock = [System.IO.FileStream]::new($script:headPath, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $blocked = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Blocked')
            $blocked.ExitCode | Should -Be 2 -Because $blocked.Output

            $script:appender.WaitForExit(15000) | Should -BeTrue
            $script:appender.ExitCode | Should -Be 2
        } finally {
            $lock.Dispose()
        }

        [System.IO.File]::ReadAllText($script:headPath) | Should -BeExactly $headBefore
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 2 -Because 'the record was flushed before the head was written'
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $script:headPath) -Filter '*.tmp').Count |
            Should -Be 0 -Because 'a failed head write cleans up its temporary file'

        # The restart check accepts exactly this state and continues from the sink.
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $resumed = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Resumed')
        $resumed.ExitCode | Should -Be 0 -Because $resumed.Output
        $resumed.Output | Should -Match 'sequence 3'
    }

    It 'keeps an acknowledged record across a crash' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0

        Stop-TestAppender -Process $script:appender
        $script:appender.WaitForExit(15000) | Should -BeTrue

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 0 -Because $validation.Output

        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $next = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'AfterCrash')
        $next.ExitCode | Should -Be 0 -Because $next.Output
        $next.Output | Should -Match 'sequence 2'
    }
}

Describe 'Ledger appender channel' -Tag 'Unit' {
    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:capturePath = Join-Path $TestDrive "capture-$([guid]::NewGuid().ToString('N')).txt"
        $script:appender = $null
        $script:hostile = $null
    }

    AfterEach {
        foreach ($process in @($script:appender, $script:hostile)) {
            if ($process -and -not $process.HasExited) {
                $process | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'refuses an acknowledgement the ledger does not back' -Skip:(-not $script:onWindows) {
        $script:hostile = Start-HostileServer -PipeName $script:pipeName -CapturePath $script:capturePath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'acknowledg'
    }

    It 'refuses an acknowledgement that replays a record the client did not send' -Skip:(-not $script:onWindows) {
        # One real record first, so the ledger holds something to point at.
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender
        $script:appender = $null

        $stored = Get-SinkRecord -SinkPath $script:sinkPath
        $stored.Count | Should -Be 1

        # The squatter answers a new record with the sequence and the digest of
        # the record that is already there: every field of the answer is true of
        # the ledger, and nothing of what the client sent was stored.
        $replay = '{"status":"Ok","message":"","sequence":1,"recordSha256":"' + $stored[0].recordSha256 + '"}'
        $script:hostile = Start-HostileServer -PipeName $script:pipeName -CapturePath $script:capturePath `
            -ResponseBase64 (ConvertTo-HostileResponse -Response $replay)

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Second')
        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'does not hold the record that was sent'

        @(Get-SinkLine -SinkPath $script:sinkPath).Count |
            Should -Be 1 -Because 'the record the client sent was never stored'
    }

    It 'refuses a pipe that is open to another identity' -Skip:(-not $script:onWindows) {
        $script:hostile = Start-HostileServer -PipeName $script:pipeName -CapturePath $script:capturePath -GrantEveryone

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'grants'

        $captured = ''
        if (Test-Path -LiteralPath $script:capturePath -PathType Leaf) {
            $captured = [System.IO.File]::ReadAllText($script:capturePath)
        }

        $captured | Should -Not -Match 'run-0001' -Because 'the record must never reach a server the client has not authenticated'
    }

    It 'keeps a listening instance while a connection is being serviced' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $holding = [System.IO.Pipes.NamedPipeClientStream]::new('.', $script:pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $second = [System.IO.Pipes.NamedPipeClientStream]::new('.', $script:pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        try {
            $holding.Connect(5000)
            { $second.Connect(5000) } | Should -Not -Throw -Because 'the name must never be free between connections'
        } finally {
            $second.Dispose()
            $holding.Dispose()
        }
    }

    It 'refuses to serve a pipe name that is already taken' -Skip:(-not $script:onWindows) {
        $script:hostile = Start-HostileServer -PipeName $script:pipeName -CapturePath $script:capturePath

        $second = Invoke-Serve -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $second.ExitCode | Should -Be 2 -Because $second.Output
    }

    It 'refuses to serve a sink another appender already holds' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $second = Invoke-Serve -PipeName "$($script:pipeName)-b" -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $second.ExitCode | Should -Be 2 -Because $second.Output
    }

    It 'owns the pipe and grants it to no other identity' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $script:pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        try {
            $client.Connect(5000)
            $acl = [System.IO.Pipes.PipesAclExtensions]::GetAccessControl($client)
            $me = [System.Security.Principal.WindowsIdentity]::GetCurrent()

            $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value |
                Should -BeIn @($me.Owner.Value, $me.User.Value) -Because 'the creator owns the pipe, never the client'

            $allow = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) |
                    Where-Object { $_.AccessControlType -eq 'Allow' })
            @($allow | Where-Object { $_.IdentityReference.Value -notin @($me.User.Value, $me.Owner.Value) }).Count |
                Should -Be 0 -Because 'only the appender identity may open the pipe'

            $deny = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) |
                    Where-Object { $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Value -eq 'S-1-5-2' })
            $deny.Count | Should -BeGreaterThan 0 -Because 'a network logon must never reach the appender'
        } finally {
            $client.Dispose()
        }
    }

    It 'refuses to serve when the allowed identity cannot be resolved' -Skip:(-not $script:onWindows) {
        $result = Invoke-Appender -Argument @(
            '-Serve', '-PipeName', $script:pipeName, '-SinkPath', $script:sinkPath,
            '-ChainHeadPath', $script:headPath, '-IdleTimeoutSeconds', '5',
            '-AllowedIdentity', 'NO SUCH ACCOUNT ZZZ'
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'serves under an allowed identity that is not its own account' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath `
            -ChainHeadPath $script:headPath -AllowedIdentity 'NT AUTHORITY\LOCAL SERVICE' -SkipReadiness

        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline -and -not (Test-PipeName -PipeName $script:pipeName)) {
            Start-Sleep -Milliseconds 100
        }

        Test-PipeName -PipeName $script:pipeName |
            Should -BeTrue -Because 'the pipe owner is the creator, so a third-party identity can be granted access'
        $script:appender.HasExited | Should -BeFalse
    }
}

Describe 'Ledger appender bound validation' -Tag 'Unit' {
    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:profilePath = Join-Path $TestDrive "profile-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
    }

    AfterEach {
        Stop-TestAppender -Process $script:appender
    }

    It 'reports the pinned ledger on standard output and exits 0' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        foreach ($step in 1..2) {
            (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")).ExitCode | Should -Be 0
        }
        Stop-TestAppender -Process $script:appender

        $digest = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $result = Invoke-AppenderSplit -Argument @('-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', $digest)

        $result.ExitCode | Should -Be 0 -Because $result.StandardError
        $record = Get-SinkRecord -SinkPath $script:sinkPath
        $result.StandardOutput.Trim() | Should -BeExactly (
            '{{"valid":true,"records":2,"headSequence":2,"sealed":false,"headRecordSha256":"{0}","bound":true}}' -f $record[-1].recordSha256)
    }

    It 'refuses a profile that does not match the digest it was given' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $null = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $result = Invoke-AppenderSplit -Argument @('-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', ('a' * 64))

        $result.ExitCode | Should -Be 2
        $result.StandardOutput.Trim() | Should -BeExactly '' -Because 'a refusal never writes a verdict'
        $result.StandardError | Should -Match 'digest'
    }

    It 'refuses a profile that pins another appender script' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $decoyScript = Join-Path $TestDrive "decoy-$([guid]::NewGuid().ToString('N')).ps1"
        Copy-Item -LiteralPath $script:appenderScript -Destination $decoyScript
        $digest = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath `
            -ChainHeadPath $script:headPath -AppenderPath $decoyScript

        $result = Invoke-AppenderSplit -Argument @('-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', $digest)

        $result.ExitCode | Should -Be 2
        $result.StandardOutput.Trim() | Should -BeExactly ''
        $result.StandardError | Should -Match 'pinned'
    }

    It 'refuses a profile whose appender digest does not match this script' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $digest = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath `
            -ChainHeadPath $script:headPath -AppenderSha256 ('b' * 64)

        $result = Invoke-AppenderSplit -Argument @('-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', $digest)

        $result.ExitCode | Should -Be 2
        $result.StandardOutput.Trim() | Should -BeExactly ''
    }

    It 'measures the pinned ledger and not a decoy that would validate' -Skip:(-not $script:onWindows) {
        $decoySink = Join-Path $TestDrive "decoy-$([guid]::NewGuid().ToString('N')).jsonl"
        $decoyHead = Join-Path $TestDrive "decoy-$([guid]::NewGuid().ToString('N')).json"

        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $decoySink -ChainHeadPath $decoyHead
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Decoy') `
                -SinkPath $decoySink -ChainHeadPath $decoyHead).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Real')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        # The real ledger is tampered with; the decoy stays valid.
        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        Set-SinkLine -SinkPath $script:sinkPath -Line @($line[0] -replace '"note":"test"', '"note":"edited"')

        $digest = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $result = Invoke-AppenderSplit -Argument @('-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', $digest)

        $result.ExitCode | Should -Be 2 -Because 'the paths come from the profile, so a valid decoy cannot answer for the pinned ledger'
        $result.StandardOutput.Trim() | Should -BeExactly ''

        $decoy = Invoke-AppenderSplit -Argument @('-Validate', '-SinkPath', $decoySink, '-ChainHeadPath', $decoyHead)
        $decoy.ExitCode | Should -Be 0 -Because 'the decoy really is a valid chain'
    }

    It 'refuses an unsealed ledger when a seal is required' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $digest = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $result = Invoke-AppenderSplit -Argument @(
            '-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', $digest, '-RequireSealed')

        $result.ExitCode | Should -Be 2
        $result.StandardOutput.Trim() | Should -BeExactly ''
        $result.StandardError | Should -Match 'seal'
    }

    It 'accepts a sealed ledger when a seal is required' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0

        $sealJson = [ordered]@{
            type = 'Seal'
            runId = 'run-0001'
            utc = '2026-09-02T22:10:00Z'
            data = @{ reason = 'run complete' }
        } | ConvertTo-Json -Depth 8 -Compress

        $seal = Invoke-Appender -Argument @(
            '-Seal', '-PipeName', $script:pipeName, '-RecordJson', $sealJson,
            '-SinkPath', $script:sinkPath, '-ChainHeadPath', $script:headPath
        )
        $seal.ExitCode | Should -Be 0 -Because $seal.Output
        Stop-TestAppender -Process $script:appender

        $digest = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $result = Invoke-AppenderSplit -Argument @(
            '-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', $digest, '-RequireSealed')

        $result.ExitCode | Should -Be 0 -Because $result.StandardError
        $result.StandardOutput | Should -Match '"sealed":true'
    }

    It 'keeps the contract exit code when the sink cannot be read at all' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $lock = [System.IO.FileStream]::new($script:sinkPath, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $result = Invoke-AppenderSplit -Argument @('-Validate', '-SinkPath', $script:sinkPath, '-ChainHeadPath', $script:headPath)

            $result.ExitCode | Should -Be 2 -Because 'an unreadable ledger is a refusal, not an unhandled error'
            $result.StandardOutput.Trim() | Should -BeExactly ''
            @($result.StandardError -split "`n" | Where-Object { $_.Trim().Length -gt 0 }).Count |
                Should -BeLessOrEqual 2 -Because 'a refusal is a line of reason, not a stack trace'
        } finally {
            $lock.Dispose()
        }
    }

    It 'marks the free-path form as unbound and warns about it' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $result = Invoke-AppenderSplit -Argument @('-Validate', '-SinkPath', $script:sinkPath, '-ChainHeadPath', $script:headPath)

        $result.ExitCode | Should -Be 0 -Because $result.StandardError
        $result.StandardOutput | Should -Match '"bound":false'
        $result.StandardError | Should -Match 'only'
    }
}

Describe 'Ledger appender seal' -Tag 'Unit' {
    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
    }

    AfterEach {
        Stop-TestAppender -Process $script:appender
    }

    It 'refuses an append whose record claims the seal type' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestSealJson)
        $result.ExitCode | Should -Be 2 -Because $result.Output

        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0

        $later = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $later.ExitCode | Should -Be 0 -Because 'a refused seal attempt must not seal the ledger'
    }

    It 'seals only on the seal operation and records it in the head' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0

        $head = [System.IO.File]::ReadAllText($script:headPath)
        $head | Should -Match '"sealed":false'

        $seal = Invoke-Seal -PipeName $script:pipeName -RecordJson (New-TestSealJson)
        $seal.ExitCode | Should -Be 0 -Because $seal.Output

        [System.IO.File]::ReadAllText($script:headPath) | Should -Match '"sealed":true'
    }

    It 'refuses a request that is not an operation envelope' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $response = Invoke-RawRequest -PipeName $script:pipeName -Payload (New-TestRecordJson -Type 'Baseline')
        $response | Should -Match '"status":"Error"'
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'refuses an operation it does not know' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $payload = '{"operation":"Truncate","record":' + (New-TestRecordJson -Type 'Baseline') + '}'
        $response = Invoke-RawRequest -PipeName $script:pipeName -Payload $payload
        $response | Should -Match '"status":"Error"'
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'refuses a seal operation whose record is not of type Seal' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $payload = '{"operation":"Seal","record":' + (New-TestRecordJson -Type 'Baseline') + '}'
        $response = Invoke-RawRequest -PipeName $script:pipeName -Payload $payload
        $response | Should -Match '"status":"Error"'
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'refuses a request that is larger than the cap' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $payload = '{"operation":"Append","record":' + (New-TestRecordJson -Type 'Baseline' -Data @{ note = ('x' * 300000) }) + '}'
        try {
            # The server stops reading at the cap, so the write may break first.
            $null = Invoke-RawRequest -PipeName $script:pipeName -Payload $payload
        } catch {
            $null = $_
        }

        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0

        $later = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $later.ExitCode | Should -Be 0 -Because 'an oversized request must not take the service down'
    }
}

Describe 'Ledger appender ordinal grammar' -Tag 'Unit' {
    BeforeDiscovery {
        # PowerShell's -ceq and -cin are case-sensitive but culture-ordered, so a
        # character the collation ignores compares equal to nothing at all. The
        # invisible characters are built from code points: a literal one in the
        # file would be unreadable and would not survive a copy.
        $script:unrealInstant = @(
            @{ Name = 'a day and a time that do not exist'; Utc = '2026-99-99T99:99:99Z' }
            @{ Name = 'the thirtieth of February'; Utc = '2026-02-30T00:00:00Z' }
            @{ Name = 'a thirteenth month'; Utc = '2026-13-01T00:00:00Z' }
            @{ Name = 'the twenty-fourth hour'; Utc = '2026-09-02T24:00:00Z' }
            @{ Name = 'a leap second'; Utc = '2026-06-30T23:59:60Z' }
        )

        $script:realInstant = @(
            @{ Name = 'without fractional seconds'; Utc = '2026-09-02T22:00:00Z' }
            @{ Name = 'with one fractional digit'; Utc = '2026-09-02T22:00:00.5Z' }
            @{ Name = 'with seven fractional digits'; Utc = '2026-09-02T22:00:00.1234567Z' }
            @{ Name = 'with nine fractional digits'; Utc = '2026-09-02T22:00:00.123456789Z' }
            @{ Name = 'on a leap day'; Utc = '2024-02-29T00:00:00Z' }
        )
    }

    BeforeEach {
        $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
        $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
        $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
        $script:profilePath = Join-Path $TestDrive "profile-$([guid]::NewGuid().ToString('N')).json"
        $script:appender = $null
        $script:zeroWidthSpace = [string][char]0x200B
    }

    AfterEach {
        Stop-TestAppender -Process $script:appender
    }

    It 'refuses a record whose extra field name only a culture folds into type' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $confusable = 'ty' + $script:zeroWidthSpace + 'pe'
        $record = '{"type":"Note","' + $confusable + '":"Seal","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{}}'

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record
        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'unknown field'
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0 -Because 'a smuggled field must never be stored'
    }

    It 'refuses an operation whose name only a culture folds into Seal' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $confusable = 'Seal' + $script:zeroWidthSpace
        $record = '{"type":"' + $confusable + '","runId":"run-0001","utc":"2026-09-02T22:00:00Z","data":{}}'
        $payload = '{"operation":"' + $confusable + '","record":' + $record + '}'

        $response = Invoke-RawRequest -PipeName $script:pipeName -Payload $payload
        $response | Should -Match '"status":"Error"'
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'refuses an envelope whose extra key only a culture folds into operation' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $confusable = 'oper' + $script:zeroWidthSpace + 'ation'
        $payload = '{"operation":"Append","' + $confusable + '":"Seal","record":' +
            (New-TestRecordJson -Type 'Baseline') + '}'

        $response = Invoke-RawRequest -PipeName $script:pipeName -Payload $payload
        $response | Should -Match '"status":"Error"'
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'refuses a stored line whose extra field name only a culture folds into type' -Skip:(-not $script:onWindows) {
        # The canonical form escapes the zero-width space, so the planted key has
        # to be written escaped for the line to be canonical at all; that is what
        # makes this line pass every check but the closed schema.
        $forged = New-ForgedLine -Member @(
            '"data":{}'
            '"prevSha256":"' + ('0' * 64) + '"'
            '"runId":"run-0001"'
            '"sequence":1'
            '"type":"Note"'
            '"ty\u200Bpe":"Seal"'
            '"utc":"2026-09-02T22:00:00Z"'
        )
        Set-SinkLine -SinkPath $script:sinkPath -Line @($forged.Line)
        Set-ChainHead -ChainHeadPath $script:headPath -Sequence 1 -RecordSha256 $forged.Digest

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'unknown field'
    }

    It 'refuses a utc that is <Name>' -ForEach $script:unrealInstant -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $record = '{"type":"Baseline","runId":"run-0001","utc":"' + $Utc + '","data":{}}'
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record

        $result.ExitCode | Should -Be 2 -Because $result.Output
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'refuses a utc with a trailing line feed' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        # The line feed is escaped in the JSON, so it reaches the field value as
        # one character; an anchor of $ matches in front of it.
        $record = '{"type":"Baseline","runId":"run-0001","utc":"2026-10-14T16:00:00Z\n","data":{}}'
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record

        $result.ExitCode | Should -Be 2 -Because $result.Output
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'refuses a utc with a leading space' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $record = '{"type":"Baseline","runId":"run-0001","utc":" 2026-10-14T16:00:00Z","data":{}}'
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record

        $result.ExitCode | Should -Be 2 -Because $result.Output
        @(Get-SinkLine -SinkPath $script:sinkPath).Count | Should -Be 0
    }

    It 'stores a utc <Name> exactly as it was given' -ForEach $script:realInstant -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $record = '{"type":"Baseline","runId":"run-0001","utc":"' + $Utc + '","data":{}}'
        $result = Invoke-Append -PipeName $script:pipeName -RecordJson $record
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $line = @(Get-SinkLine -SinkPath $script:sinkPath)
        $line[0] | Should -BeLike ('*"utc":"' + $Utc + '"*') -Because 'a validated instant is never rewritten'
    }

    It 'refuses a profile digest with a trailing line feed' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        (Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')).ExitCode | Should -Be 0
        Stop-TestAppender -Process $script:appender

        $digest = New-TestProfile -ProfilePath $script:profilePath -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $result = Invoke-AppenderSplit -Argument @(
            '-Validate', '-ProfilePath', $script:profilePath, '-ProfileSha256', ($digest + [string][char]0x000A))

        $result.ExitCode | Should -Be 2
        $result.StandardOutput.Trim() | Should -BeExactly ''
        $result.StandardError | Should -Match 'hexadecimal' -Because 'a digest that is not 64 hexadecimal characters is a format refusal, not a mismatch'
    }
}

Describe 'Ledger appender refusal text' -Tag 'Unit' {
    Context 'when a hostile server supplies the text' {
        BeforeEach {
            $script:pipeName = "ca-ledger-test-$([guid]::NewGuid().ToString('N'))"
            $script:sinkPath = Join-Path $TestDrive "ledger-$([guid]::NewGuid().ToString('N')).jsonl"
            $script:headPath = Join-Path $TestDrive "head-$([guid]::NewGuid().ToString('N')).json"
            $script:capturePath = Join-Path $TestDrive "capture-$([guid]::NewGuid().ToString('N')).txt"
            $script:hostile = $null
        }

        AfterEach {
            Stop-TestAppender -Process $script:hostile
        }

        It 'leaves one line on standard error with every control and format character replaced' -Skip:(-not $script:onWindows) {
            # The controller is a model reading this line, and the speaker is the
            # squatter the pipe design exists for: a carriage return, an escape,
            # a right-to-left override and a Unicode tag character would let it
            # forge a second line or hide what it wrote.
            $hostileMessage = 'alpha' + [string][char]0x000D + [string][char]0x000A +
                'beta' + [string][char]0x001B + '[31mred' + [string][char]0x202E +
                'reversed' + [char]::ConvertFromUtf32(0xE0041) + 'tagged'

            $response = [ordered]@{
                status = 'Error'
                message = $hostileMessage
                sequence = 0
                recordSha256 = ''
            } | ConvertTo-Json -Compress

            $script:hostile = Start-HostileServer -PipeName $script:pipeName -CapturePath $script:capturePath `
                -ResponseBase64 (ConvertTo-HostileResponse -Response $response)

            $result = Invoke-AppenderSplit -Argument @(
                '-Append', '-PipeName', $script:pipeName, '-RecordJson', (New-TestRecordJson -Type 'Baseline'),
                '-SinkPath', $script:sinkPath, '-ChainHeadPath', $script:headPath)

            $result.ExitCode | Should -Be 2
            $standardError = $result.StandardError

            @($standardError -split "`r?`n" | Where-Object { $_.Length -gt 0 }).Count |
                Should -Be 1 -Because 'a refusal is one line, whoever wrote the text'

            $standardError | Should -Match 'alpha'
            $standardError | Should -Match 'tagged'
            $standardError | Should -Match '\?'
            $standardError.Contains([string][char]0x001B) | Should -BeFalse -Because 'an escape sequence must not reach a terminal'
            $standardError.Contains([string][char]0x202E) | Should -BeFalse -Because 'a bidirectional override must not reorder the line'
            $standardError.Contains([char]::ConvertFromUtf32(0xE0041)) | Should -BeFalse -Because 'a Unicode tag character must not ride along invisibly'
        }
    }

    Context 'as a function' {
        BeforeAll {
            . (Join-Path $script:repoRoot 'tests/Helpers/ScriptFunction.ps1')
            . (Get-ScriptFunctionDefinition -Path $script:appenderScript -Name @(
                    'Write-Refusal'
                    'Format-RefusalText'
                ))
        }

        It 'replaces a Unicode tag character that is invisible to \p{Cf} on UTF-16' {
            Format-RefusalText -Text ('a' + [char]::ConvertFromUtf32(0xE0041) + 'b') |
                Should -BeExactly 'a?b'
        }

        It 'replaces a carriage return, a line feed and an escape with one question mark each' {
            Format-RefusalText -Text ('a' + [string][char]0x000D + [string][char]0x000A + [string][char]0x001B + 'b') |
                Should -BeExactly 'a???b'
        }

        It 'cuts a long message at two hundred characters and marks the cut' {
            $long = 'x' * 500
            $formatted = Format-RefusalText -Text $long

            $formatted.Length | Should -Be 203
            $formatted | Should -BeExactly (('x' * 200) + '...')
        }

        It 'keeps an accented letter and an emoji unchanged' {
            $text = 'na' + [string][char]0x00EF + 've ' + [char]::ConvertFromUtf32(0x2615)
            Format-RefusalText -Text $text | Should -BeExactly $text
        }

        It 'keeps an astral emoji whole when it would straddle the cut' {
            $text = ('x' * 199) + [char]::ConvertFromUtf32(0x1F600) + 'tail'
            $formatted = Format-RefusalText -Text $text

            $formatted | Should -BeExactly (('x' * 199) + '...')
            $formatted.Length | Should -Be 202 -Because 'a surrogate pair is never split to reach the cap'
        }

        It 'returns an empty string for an empty message' {
            Format-RefusalText -Text '' | Should -BeExactly ''
        }
    }
}
