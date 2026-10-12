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
            [string]$ChainHeadPath
        )

        $arguments = @(
            '-NoProfile'
            '-NonInteractive'
            '-File', $script:appenderScript
            '-Serve'
            '-PipeName', $PipeName
            '-SinkPath', $SinkPath
            '-ChainHeadPath', $ChainHeadPath
            '-IdleTimeoutSeconds', '30'
        )

        $process = Start-Process -FilePath $script:powerShellPath -ArgumentList $arguments -PassThru -WindowStyle Hidden

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
            [string]$RecordJson
        )

        Invoke-Appender -Argument @('-Append', '-PipeName', $PipeName, '-RecordJson', $RecordJson)
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

    function script:Get-SinkRecord {
        param(
            [Parameter(Mandatory)]
            [string]$SinkPath
        )

        @(
            Get-Content -LiteralPath $SinkPath -Encoding UTF8 |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_ | ConvertFrom-Json }
        )
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
        $validation.Output | Should -Match 'Valid'
    }

    It 'rejects a record whose body was rewritten' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        foreach ($step in 1..3) {
            $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type "Step$step")
            $result.ExitCode | Should -Be 0 -Because $result.Output
        }
        $script:appender | Stop-Process -Force

        $lines = @(Get-Content -LiteralPath $script:sinkPath -Encoding UTF8)
        $lines[1] = $lines[1] -replace '"note":"test"', '"note":"tampered"'
        Set-Content -LiteralPath $script:sinkPath -Value $lines -Encoding UTF8

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
        $script:appender | Stop-Process -Force

        $lines = @(Get-Content -LiteralPath $script:sinkPath -Encoding UTF8)
        Set-Content -LiteralPath $script:sinkPath -Value $lines[0..1] -Encoding UTF8

        $validation = Invoke-Validate -SinkPath $script:sinkPath -ChainHeadPath $script:headPath
        $validation.ExitCode | Should -Be 2 -Because $validation.Output
        $validation.Output | Should -Match 'head'
    }

    It 'rejects a rewritten chain head' -Skip:(-not $script:onWindows) {
        $script:appender = Start-TestAppender -PipeName $script:pipeName -SinkPath $script:sinkPath -ChainHeadPath $script:headPath

        $result = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Baseline')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $script:appender | Stop-Process -Force

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
        Test-Path -LiteralPath $script:sinkPath | Should -BeFalse
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

        $seal = Invoke-Appender -Argument @('-Seal', '-PipeName', $script:pipeName, '-RecordJson', $sealJson)
        $seal.ExitCode | Should -Be 0 -Because $seal.Output

        $late = Invoke-Append -PipeName $script:pipeName -RecordJson (New-TestRecordJson -Type 'Late')
        $late.ExitCode | Should -Be 2 -Because $late.Output
    }
}
