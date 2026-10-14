# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'
    $script:appenderScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Invoke-LedgerAppender.ps1'
    $script:powerShellPath = (Get-Process -Id $PID).Path
    . (Join-Path $script:repoRoot 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'New-CheckResult'
            'Get-BytesDigest'
            'Get-SinkSnapshot'
            'Invoke-ChainValidation'
            'Get-LedgerChainResult'
            'Test-FinalReport'
        ))

    # Runs the appender as the controller does, as its own process, and keeps its streams.
    function script:Invoke-ContractAppender {
        param(
            [Parameter(Mandatory)]
            [string[]]$Argument
        )

        $arguments = @('-NoProfile', '-NonInteractive', '-File', $script:appenderScript) + $Argument

        # A refusal is exit 2 with a line on standard error; under the build's Stop preference that
        # would throw instead of being asserted on.
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

    function script:Start-ContractService {
        param(
            [Parameter(Mandatory)]
            [string]$PipeName,

            [Parameter(Mandatory)]
            [string]$SinkPath,

            [Parameter(Mandatory)]
            [string]$ChainHeadPath
        )

        # EncodedCommand keeps the quoting of the paths out of Start-Process.
        $payload = "& '$($script:appenderScript.Replace("'", "''"))' -Serve -PipeName '$PipeName' -SinkPath '$($SinkPath.Replace("'", "''"))' -ChainHeadPath '$($ChainHeadPath.Replace("'", "''"))' -IdleTimeoutSeconds 60`nexit `$LASTEXITCODE`n"
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($payload))
        $process = Start-Process -FilePath $script:powerShellPath -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)

        # Readiness is the pipe accepting a connection, not the process existing.
        $deadline = (Get-Date).AddSeconds(30)

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

        $process | Stop-Process -Force -ErrorAction SilentlyContinue
        throw "The appender did not start listening on $PipeName."
    }

    function script:Stop-ContractService {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Process
        )

        if ($null -eq $Process) {
            return
        }

        if (-not $Process.HasExited) {
            $Process | Stop-Process -Force -ErrorAction SilentlyContinue
        }

        # The service holds the sink open, so nothing may touch the sink until it is gone.
        $null = $Process.WaitForExit(15000)
    }

    function script:New-ContractRecordJson {
        param(
            [Parameter(Mandatory)]
            [string]$Type,

            [Parameter()]
            [hashtable]$Data = @{ note = 'contract' }
        )

        return ([ordered]@{
                type = $Type
                runId = 'run-contract'
                utc = '2026-10-14T12:00:00Z'
                data = $Data
            } | ConvertTo-Json -Depth 8 -Compress)
    }

    # The document shape the verifier pins; the appender reads only ledgerSink, chainHead and ledgerAppender.
    function script:New-ContractProfile {
        param(
            [Parameter(Mandatory)]
            [string]$ProfilePath,

            [Parameter(Mandatory)]
            [string]$SinkPath,

            [Parameter(Mandatory)]
            [string]$ChainHeadPath
        )

        $pinned = @{ path = $script:appenderScript; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:appenderScript).Hash.ToLowerInvariant() }
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
            controllerIdentity = 'CONTRACT\controller'
            workerIdentity = 'CONTRACT\worker'
            immutableControlPaths = @()
            writableRoots = @()
        } | ConvertTo-Json -Depth 8

        [System.IO.File]::WriteAllBytes($ProfilePath, [System.Text.UTF8Encoding]::new($false).GetBytes($content))

        return (Get-FileHash -Algorithm SHA256 -LiteralPath $ProfilePath).Hash.ToLowerInvariant()
    }

    <#
        A ledger built the way a controller builds one: the real service, one process per append, and
        the seal as the last operation. FinalReport says which digest the FinalReport record carries:
        None leaves the record out, Lower and Upper record the report's digest in that case.
    #>
    function script:New-ContractLedger {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter()]
            [ValidateSet('None', 'Lower', 'Upper')]
            [string]$FinalReport = 'Lower',

            [Parameter()]
            [switch]$NoSeal
        )

        $directory = Join-Path $TestDrive $Name
        $null = New-Item -Path $directory -ItemType Directory -Force
        $sink = Join-Path $directory 'run.jsonl'
        $head = Join-Path $directory 'run.head.json'
        $report = Join-Path $directory 'final-report.md'
        [System.IO.File]::WriteAllText($report, "# Final report`n`nThe run is complete.`n", [System.Text.UTF8Encoding]::new($false))
        $digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $report).Hash.ToLowerInvariant()
        $pipe = "ca-contract-$([guid]::NewGuid().ToString('N'))"
        $service = Start-ContractService -PipeName $pipe -SinkPath $sink -ChainHeadPath $head

        try {
            $record = [System.Collections.Generic.List[hashtable]]::new()
            $record.Add(@{ Operation = '-Append'; Json = (New-ContractRecordJson -Type 'Baseline') })

            if ($FinalReport -ne 'None') {
                $recorded = if ($FinalReport -eq 'Upper') { $digest.ToUpperInvariant() } else { $digest }
                $record.Add(@{ Operation = '-Append'; Json = (New-ContractRecordJson -Type 'FinalReport' -Data @{ sha256 = $recorded }) })
            }

            if (-not $NoSeal) {
                $record.Add(@{ Operation = '-Seal'; Json = (New-ContractRecordJson -Type 'Seal' -Data @{ reason = 'run complete' }) })
            }

            foreach ($item in $record) {
                $result = Invoke-ContractAppender -Argument @($item.Operation, '-PipeName', $pipe, '-RecordJson', $item.Json, '-SinkPath', $sink, '-ChainHeadPath', $head)

                if ($result.ExitCode -ne 0) {
                    throw "The appender refused $($item.Operation) (exit $($result.ExitCode)): $($result.Output)"
                }
            }
        } finally {
            Stop-ContractService -Process $service
        }

        $profilePath = Join-Path $directory 'profile.json'

        return [pscustomobject]@{
            Sink = $sink
            Head = $head
            Report = $report
            ProfilePath = $profilePath
            ProfileSha256 = (New-ContractProfile -ProfilePath $profilePath -SinkPath $sink -ChainHeadPath $head)
        }
    }

    function script:Get-ContractChain {
        param(
            [Parameter(Mandatory)]
            $Ledger
        )

        return (Get-LedgerChainResult -AppenderPath $script:appenderScript -ProfilePath $Ledger.ProfilePath -ProfileSha256 $Ledger.ProfileSha256)
    }

    function script:Get-ContractFinalReport {
        param(
            [Parameter(Mandatory)]
            $Ledger,

            [Parameter(Mandatory)]
            $Chain
        )

        $snapshot = Get-SinkSnapshot -Path $Ledger.Sink

        return (Test-FinalReport -SinkBytes $snapshot.Bytes -FinalReportPath $Ledger.Report -ChainSummary $Chain.Summary)
    }
}

Describe 'Containment ledger contract' -Tag 'Unit' -Skip:(-not $script:onWindows) {
    Context 'a sealed ledger built through the real appender' {
        BeforeAll {
            $script:ledger = New-ContractLedger -Name 'sealed'
            $script:chain = Get-ContractChain -Ledger $script:ledger
        }

        It 'is a valid, bound, sealed chain to the verifier' {
            $script:chain.Check.status | Should -Be 'Pass' -Because $script:chain.Check.evidence
            $script:chain.Check.name | Should -Be 'LedgerChain'
        }

        It 'reports the records, the head sequence and the head digest the final report check reads' {
            $script:chain.Summary.records | Should -Be 3
            $script:chain.Summary.headSequence | Should -Be 3
            $script:chain.Summary.sealed | Should -BeTrue
            $script:chain.Summary.bound | Should -BeTrue
            $script:chain.Summary.headRecordSha256 | Should -Match '^[0-9a-f]{64}$'
        }

        It 'records the final report directly before the seal, which the verifier accepts' {
            $result = Get-ContractFinalReport -Ledger $script:ledger -Chain $script:chain

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'fails the final report check once the report is changed after the seal' {
            [System.IO.File]::AppendAllText($script:ledger.Report, "A line added after the run was sealed.`n")

            $result = Get-ContractFinalReport -Ledger $script:ledger -Chain $script:chain

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'hashes to'
        }
    }

    Context 'a ledger whose final report digest is written in upper case' {
        It 'is a valid chain, and the verifier does not accept the digest as the report digest' {
            $ledger = New-ContractLedger -Name 'upper' -FinalReport 'Upper'
            $chain = Get-ContractChain -Ledger $ledger

            $chain.Check.status | Should -Be 'Pass' -Because $chain.Check.evidence

            $result = Get-ContractFinalReport -Ledger $ledger -Chain $chain

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'hashes to'
        }
    }

    Context 'a sealed ledger with no final report record' {
        It 'is a valid chain, and the verifier names the record that is missing before the seal' {
            $ledger = New-ContractLedger -Name 'no-report' -FinalReport 'None'
            $chain = Get-ContractChain -Ledger $ledger

            $chain.Check.status | Should -Be 'Pass' -Because $chain.Check.evidence

            $result = Get-ContractFinalReport -Ledger $ledger -Chain $chain

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'not FinalReport'
        }
    }

    Context 'a ledger that was never sealed' {
        It 'is refused by the appender, so the verifier fails the chain and reads no summary' {
            $ledger = New-ContractLedger -Name 'unsealed' -NoSeal
            $chain = Get-ContractChain -Ledger $ledger

            $chain.Check.status | Should -Be 'Fail'
            $chain.Check.evidence | Should -Match 'exit 2'
            $chain.Check.evidence | Should -Match 'sealed'
            $chain.Summary | Should -BeNullOrEmpty
        }
    }

    Context 'a ledger whose stored bytes were changed after the run' {
        It 'is refused by the appender, so the verifier fails the chain' {
            $ledger = New-ContractLedger -Name 'tampered'
            $bytes = [System.IO.File]::ReadAllBytes($ledger.Sink)
            [System.IO.File]::WriteAllBytes($ledger.Sink, [byte[]]($bytes + [byte[]]@(0x20)))

            $chain = Get-ContractChain -Ledger $ledger

            $chain.Check.status | Should -Be 'Fail'
            $chain.Check.evidence | Should -Match 'refused'
            $chain.Summary | Should -BeNullOrEmpty
        }
    }
}
