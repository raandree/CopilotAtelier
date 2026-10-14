# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'
    . (Join-Path $script:repoRoot 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'New-CheckResult'
            'Get-BytesDigest'
            'Get-GateFailure'
            'Get-NotRunCheck'
            'Get-RevalidationCheckName'
            'Get-RevalidationCheck'
            'Invoke-ChainValidation'
            'Lock-LedgerSink'
            'Get-LedgerChainResult'
            'Test-FinalReport'
            'Test-VerifierBinding'
            'Test-ControlDigest'
            'Test-ControlImmutability'
            'Test-IdentityBinding'
            'Test-LedgerProtection'
        ))

    $script:good = 'a' * 64
    $script:head = 'b' * 64

    # A stand-in for the pinned appender: it answers the way the real one is specified to.
    function script:New-StubAppender {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Body
        )

        $path = Join-Path $TestDrive "$Name.ps1"
        [System.IO.File]::WriteAllText($path, $Body, [System.Text.UTF8Encoding]::new($false))

        return $path
    }

    function script:New-Summary {
        param(
            [Parameter()]
            [hashtable]$Override = @{}
        )

        $summary = [ordered]@{ valid = $true; records = 3; headSequence = 3; sealed = $true; headRecordSha256 = $script:head; bound = $true }

        foreach ($key in $Override.Keys) {
            $summary[$key] = $Override[$key]
        }

        return [pscustomobject]$summary
    }

    function script:New-Run {
        param(
            [Parameter()]
            [int]$ExitCode = 0,

            [Parameter()]
            [string]$Output = '',

            [Parameter()]
            [string]$ErrorText = ''
        )

        return [pscustomobject]@{ ExitCode = $ExitCode; Output = $Output; Error = $ErrorText }
    }

    # One canonical ledger line of the shape the appender writes.
    function script:New-LedgerLine {
        param(
            [Parameter(Mandatory)]
            [int]$Sequence,

            [Parameter(Mandatory)]
            [string]$Previous,

            [Parameter(Mandatory)]
            [string]$Digest,

            [Parameter(Mandatory)]
            [string]$Type,

            [Parameter()]
            [hashtable]$Data = @{}
        )

        return ([ordered]@{
                sequence = $Sequence
                prevSha256 = $Previous
                type = $Type
                runId = 'run-1'
                utc = '2026-10-14T12:00:00Z'
                data = $Data
                recordSha256 = $Digest
            } | ConvertTo-Json -Compress -Depth 6)
    }
}

Describe 'Revalidation check names' -Tag 'Unit' {
    It 'names the seven checks of a revalidation, the chain and the report after the controls that gate them' {
        $name = @(Get-RevalidationCheckName)

        $name | Should -Be @('VerifierBinding', 'ControlDigest', 'ControlImmutability', 'IdentityBinding', 'LedgerChain', 'FinalReport', 'LedgerProtection')
    }
}

Describe 'Pinned appender validation' -Tag 'Unit' {
    It 'runs the pinned appender with the profile, its digest and the demand that the ledger is sealed' {
        $stub = New-StubAppender -Name 'echo-args' -Body @'
[Console]::Out.Write(($args -join '|'))
exit 0
'@

        $run = Invoke-ChainValidation -AppenderPath $stub -ProfilePath (Join-Path $TestDrive 'p.json') -ProfileSha256 $script:good

        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match '-Validate'
        $run.Output | Should -Match '-ProfilePath\|'
        $run.Output | Should -Match ([regex]::Escape($script:good))
        $run.Output | Should -Match '-RequireSealed'
    }

    It 'returns what the appender wrote and its exit code' {
        $stub = New-StubAppender -Name 'refuses' -Body @'
[Console]::Error.WriteLine('the ledger does not chain')
exit 2
'@

        $run = Invoke-ChainValidation -AppenderPath $stub -ProfilePath (Join-Path $TestDrive 'p.json') -ProfileSha256 $script:good

        $run.ExitCode | Should -Be 2
        $run.Error | Should -Match 'does not chain'
        $run.Output | Should -BeNullOrEmpty
    }

    It 'stops an appender that does not finish in time' {
        $stub = New-StubAppender -Name 'hangs' -Body 'Start-Sleep -Seconds 60'

        { Invoke-ChainValidation -AppenderPath $stub -ProfilePath (Join-Path $TestDrive 'p.json') -ProfileSha256 $script:good -TimeoutSecond 3 } |
            Should -Throw -ExpectedMessage '*did not finish*'
    }

    It 'runs the appender with the host that runs the verifier, not whatever PATH names' {
        $stub = New-StubAppender -Name 'host' -Body @'
[Console]::Out.Write([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
exit 0
'@
        $previous = $env:PATH
        try {
            $env:PATH = Join-Path $TestDrive 'nowhere'
            $run = Invoke-ChainValidation -AppenderPath $stub -ProfilePath (Join-Path $TestDrive 'p.json') -ProfileSha256 $script:good
        } finally {
            $env:PATH = $previous
        }

        $run.Output | Should -Be ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    }
}

Describe 'Ledger chain result' -Tag 'Unit' {
    It 'passes a sealed, bound chain and returns what the appender validated' {
        Mock -CommandName Invoke-ChainValidation -MockWith { New-Run -Output ((New-Summary) | ConvertTo-Json -Compress) }

        $result = Get-LedgerChainResult -AppenderPath 'a' -ProfilePath 'p' -ProfileSha256 $script:good

        $result.Check.status | Should -Be 'Pass' -Because $result.Check.evidence
        $result.Check.name | Should -Be 'LedgerChain'
        $result.Summary.records | Should -Be 3
        $result.Summary.headRecordSha256 | Should -Be $script:head
    }

    It 'fails when the appender refuses the ledger, and says why' {
        Mock -CommandName Invoke-ChainValidation -MockWith { New-Run -ExitCode 2 -ErrorText 'record at sequence 2 fails its own digest' }

        $result = Get-LedgerChainResult -AppenderPath 'a' -ProfilePath 'p' -ProfileSha256 $script:good

        $result.Check.status | Should -Be 'Fail'
        $result.Check.evidence | Should -Match 'fails its own digest'
        $result.Summary | Should -BeNullOrEmpty
    }

    It 'fails a summary whose <Field> is <Value>' -ForEach @(
        @{ Field = 'valid'; Value = $false }
        @{ Field = 'sealed'; Value = $false }
        @{ Field = 'bound'; Value = $false }
        @{ Field = 'records'; Value = 0 }
        @{ Field = 'headRecordSha256'; Value = ('A' * 64) }
        @{ Field = 'headRecordSha256'; Value = 'short' }
    ) {
        $script:override = @{ $Field = $Value }
        Mock -CommandName Invoke-ChainValidation -MockWith { New-Run -Output ((New-Summary -Override $script:override) | ConvertTo-Json -Compress) }

        $result = Get-LedgerChainResult -AppenderPath 'a' -ProfilePath 'p' -ProfileSha256 $script:good

        $result.Check.status | Should -Be 'Fail'
        $result.Check.evidence | Should -Match $Field
        $result.Summary | Should -BeNullOrEmpty
    }

    It 'fails a summary that lacks a field' {
        Mock -CommandName Invoke-ChainValidation -MockWith { New-Run -Output '{"valid":true,"records":3}' }

        (Get-LedgerChainResult -AppenderPath 'a' -ProfilePath 'p' -ProfileSha256 $script:good).Check.status | Should -Be 'Fail'
    }

    It 'fails output that is not one JSON object' {
        Mock -CommandName Invoke-ChainValidation -MockWith { New-Run -Output 'all is well' }

        (Get-LedgerChainResult -AppenderPath 'a' -ProfilePath 'p' -ProfileSha256 $script:good).Check.status | Should -Be 'Fail'
    }

    It 'reports an appender that could not run as unmeasured' {
        Mock -CommandName Invoke-ChainValidation -MockWith { throw 'the appender did not finish within 60 seconds' }

        $result = Get-LedgerChainResult -AppenderPath 'a' -ProfilePath 'p' -ProfileSha256 $script:good

        $result.Check.status | Should -Be 'Unavailable'
        $result.Check.evidence | Should -Match 'did not finish'
    }
}

Describe 'Final report' -Tag 'Unit' {
    BeforeAll {
        $script:reportText = 'the final report'
        $script:report = Join-Path $TestDrive 'revalidate/final-report.md'
        $null = New-Item -Path (Split-Path -Parent $script:report) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($script:report, $script:reportText, [System.Text.UTF8Encoding]::new($false))
        $script:reportDigest = Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($script:report))

        # records: 1 Started, 2 FinalReport, 3 Seal
        function script:Write-Ledger {
            param(
                [Parameter(Mandatory)]
                [string]$Name,

                [Parameter()]
                [string]$ReportDigestInLedger = $script:reportDigest,

                [Parameter()]
                [string]$SealType = 'Seal',

                [Parameter()]
                [string]$FinalType = 'FinalReport',

                [Parameter()]
                [string]$SealPrevious = ('2' * 64),

                [Parameter()]
                [string]$HeadDigest = $script:head
            )

            $path = Join-Path $TestDrive "revalidate/$Name.jsonl"
            $lines = @(
                (New-LedgerLine -Sequence 1 -Previous ('0' * 64) -Digest ('1' * 64) -Type 'Started')
                (New-LedgerLine -Sequence 2 -Previous ('1' * 64) -Digest ('2' * 64) -Type $FinalType -Data @{ sha256 = $ReportDigestInLedger })
                (New-LedgerLine -Sequence 3 -Previous $SealPrevious -Digest $HeadDigest -Type $SealType)
            )
            [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))

            return $path
        }
    }

    It 'passes when the record before the seal carries the digest of the report' {
        $result = Test-FinalReport -SinkPath (Write-Ledger -Name 'good') -FinalReportPath $script:report -ChainSummary (New-Summary)

        $result.status | Should -Be 'Pass' -Because $result.evidence
        $result.name | Should -Be 'FinalReport'
        $result.evidence | Should -Match $script:reportDigest
    }

    It 'fails a report that is not the one the ledger recorded' {
        $result = Test-FinalReport -SinkPath (Write-Ledger -Name 'other-report' -ReportDigestInLedger ('9' * 64)) -FinalReportPath $script:report -ChainSummary (New-Summary)

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match $script:reportDigest
        $result.evidence | Should -Match ('9' * 64)
    }

    It 'fails a report that was changed after the ledger recorded it' {
        $changed = Join-Path $TestDrive 'revalidate/changed-report.md'
        [System.IO.File]::WriteAllText($changed, 'a different report', [System.Text.UTF8Encoding]::new($false))

        (Test-FinalReport -SinkPath (Write-Ledger -Name 'changed') -FinalReportPath $changed -ChainSummary (New-Summary)).status | Should -Be 'Fail'
    }

    It 'fails a ledger whose last record is not the seal' {
        (Test-FinalReport -SinkPath (Write-Ledger -Name 'no-seal' -SealType 'Note') -FinalReportPath $script:report -ChainSummary (New-Summary)).status | Should -Be 'Fail'
    }

    It 'fails a ledger whose record before the seal is not a final report' {
        $result = Test-FinalReport -SinkPath (Write-Ledger -Name 'no-final' -FinalType 'Note') -FinalReportPath $script:report -ChainSummary (New-Summary)

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'FinalReport'
    }

    It 'fails a seal that does not chain to the final report' {
        (Test-FinalReport -SinkPath (Write-Ledger -Name 'unchained' -SealPrevious ('8' * 64)) -FinalReportPath $script:report -ChainSummary (New-Summary)).status | Should -Be 'Fail'
    }

    It 'fails a last record that is not the head the appender validated' {
        $result = Test-FinalReport -SinkPath (Write-Ledger -Name 'other-head' -HeadDigest ('7' * 64)) -FinalReportPath $script:report -ChainSummary (New-Summary)

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'validated'
    }

    It 'fails a ledger with a different number of records than the appender validated' {
        $result = Test-FinalReport -SinkPath (Write-Ledger -Name 'count') -FinalReportPath $script:report -ChainSummary (New-Summary -Override @{ records = 4 })

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'records'
    }

    It 'fails a final report that does not exist' {
        (Test-FinalReport -SinkPath (Write-Ledger -Name 'no-file') -FinalReportPath (Join-Path $TestDrive 'revalidate/absent.md') -ChainSummary (New-Summary)).status | Should -Be 'Fail'
    }

    It 'reports a ledger it cannot read as unmeasured' {
        (Test-FinalReport -SinkPath (Join-Path $TestDrive 'revalidate/absent.jsonl') -FinalReportPath $script:report -ChainSummary (New-Summary)).status | Should -Be 'Unavailable'
    }

    It 'fails a ledger with fewer than two records' {
        $path = Join-Path $TestDrive 'revalidate/one.jsonl'
        [System.IO.File]::WriteAllText($path, ((New-LedgerLine -Sequence 1 -Previous ('0' * 64) -Digest $script:head -Type 'Seal') + "`n"))

        (Test-FinalReport -SinkPath $path -FinalReportPath $script:report -ChainSummary (New-Summary -Override @{ records = 1 })).status | Should -Be 'Fail'
    }

    It 'does not accept an earlier final report followed by other records before the seal' {
        $path = Join-Path $TestDrive 'revalidate/earlier.jsonl'
        $lines = @(
            (New-LedgerLine -Sequence 1 -Previous ('0' * 64) -Digest ('1' * 64) -Type 'FinalReport' -Data @{ sha256 = $script:reportDigest })
            (New-LedgerLine -Sequence 2 -Previous ('1' * 64) -Digest ('2' * 64) -Type 'Note')
            (New-LedgerLine -Sequence 3 -Previous ('2' * 64) -Digest $script:head -Type 'Seal')
        )
        [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"))

        (Test-FinalReport -SinkPath $path -FinalReportPath $script:report -ChainSummary (New-Summary)).status | Should -Be 'Fail'
    }
}

Describe 'Revalidation flow' -Tag 'Unit' {
    BeforeAll {
        $script:base = if ($script:onWindows) { 'C:\containment' } else { '/containment' }

        function script:New-FlowProfile {
            $entry = { param($name) [pscustomobject]@{ path = (Join-Path $script:base $name); sha256 = ('a' * 64) } }

            return [pscustomobject]@{
                schemaVersion = 1
                verifier = & $entry 'verifier.ps1'
                hooksConfig = & $entry 'hooks.json'
                hookScript = & $entry 'hook.ps1'
                ledgerAppender = [pscustomobject]@{ path = (Join-Path $script:base 'appender.ps1'); sha256 = ('d' * 64) }
                ledgerSink = (Join-Path $script:base 'run.jsonl')
                chainHead = (Join-Path $script:base 'run.head.json')
                controllerEgressAllow = @()
                workerEgressAllow = @()
                controllerIdentity = 'LAB\controller'
                workerIdentity = 'LAB\worker'
                immutableControlPaths = @()
                writableRoots = @((Join-Path $script:base 'work'))
            }
        }

        function script:Invoke-Revalidation {
            return @(Get-RevalidationCheck -ContainmentProfile (New-FlowProfile) -ProfilePath (Join-Path $script:base 'profile.json') -ProfileSha256 $script:good `
                    -Role 'Controller' -VerifierPath (Join-Path $script:base 'verifier.ps1') -FinalReportPath (Join-Path $script:base 'final-report.md'))
        }
    }

    BeforeEach {
        Mock -CommandName Lock-LedgerSink -MockWith { [System.IO.MemoryStream]::new() }
        Mock -CommandName Test-VerifierBinding -MockWith { New-CheckResult -Name 'VerifierBinding' -Status 'Pass' -Evidence 'mock' }
        Mock -CommandName Test-ControlDigest -MockWith { New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence 'mock' }
        Mock -CommandName Test-ControlImmutability -MockWith { New-CheckResult -Name 'ControlImmutability' -Status 'Pass' -Evidence 'mock' }
        Mock -CommandName Test-IdentityBinding -MockWith { New-CheckResult -Name 'IdentityBinding' -Status 'Pass' -Evidence 'mock' }
        Mock -CommandName Get-LedgerChainResult -MockWith { [pscustomobject]@{ Check = (New-CheckResult -Name 'LedgerChain' -Status 'Pass' -Evidence 'mock'); Summary = (New-Summary) } }
        Mock -CommandName Test-FinalReport -MockWith { New-CheckResult -Name 'FinalReport' -Status 'Pass' -Evidence 'mock' }
        Mock -CommandName Test-LedgerProtection -MockWith { New-CheckResult -Name 'LedgerProtection' -Status 'Pass' -Evidence 'mock' }
    }

    It 'runs exactly the declared checks, in the declared order' {
        @((Invoke-Revalidation).name) | Should -Be @(Get-RevalidationCheckName)
    }

    It 'runs the pinned appender on the pinned profile and its direct digest' {
        $null = Invoke-Revalidation

        Should -Invoke Get-LedgerChainResult -Times 1 -Exactly -ParameterFilter {
            $AppenderPath -eq (Join-Path $script:base 'appender.ps1') -and $ProfilePath -eq (Join-Path $script:base 'profile.json') -and $ProfileSha256 -ceq $script:good
        }
    }

    It 'does not run the appender when <Gate> is <Status>' -ForEach @(
        @{ Gate = 'VerifierBinding'; Status = 'Fail' }
        @{ Gate = 'ControlDigest'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Unavailable' }
    ) {
        $script:gateName = $Gate
        $script:gateStatus = $Status
        Mock -CommandName "Test-$Gate" -MockWith { New-CheckResult -Name $script:gateName -Status $script:gateStatus -Evidence 'mock breach' }

        $result = Invoke-Revalidation

        Should -Invoke Get-LedgerChainResult -Times 0 -Exactly
        $chain = $result | Where-Object { $_.name -ceq 'LedgerChain' }
        $chain.status | Should -Be 'Unavailable'
        $chain.evidence | Should -Match 'not run'
        $chain.evidence | Should -Match $Gate
    }

    It 'gives the final report check the sink, the report and what the appender validated' {
        $null = Invoke-Revalidation

        Should -Invoke Test-FinalReport -Times 1 -Exactly -ParameterFilter {
            $SinkPath -eq (Join-Path $script:base 'run.jsonl') -and $FinalReportPath -eq (Join-Path $script:base 'final-report.md') -and $ChainSummary.records -eq 3
        }
    }

    It 'does not look for the report in a chain that did not validate' {
        Mock -CommandName Get-LedgerChainResult -MockWith { [pscustomobject]@{ Check = (New-CheckResult -Name 'LedgerChain' -Status 'Fail' -Evidence 'mock breach'); Summary = $null } }

        $result = Invoke-Revalidation

        Should -Invoke Test-FinalReport -Times 0 -Exactly
        $report = $result | Where-Object { $_.name -ceq 'FinalReport' }
        $report.status | Should -Be 'Unavailable'
        $report.evidence | Should -Match 'not run'
    }

    It 'measures the ledger protection even when a control is unverified' {
        Mock -CommandName Test-ControlImmutability -MockWith { New-CheckResult -Name 'ControlImmutability' -Status 'Fail' -Evidence 'mock breach' }

        $null = Invoke-Revalidation

        Should -Invoke Test-LedgerProtection -Times 1 -Exactly -ParameterFilter { $WritableRoot -contains (Join-Path $script:base 'work') }
    }

    It 'reports a sink it cannot hold as unmeasured and validates nothing' {
        Mock -CommandName Lock-LedgerSink -MockWith { throw 'The process cannot access the file because it is being used by another process.' }

        $result = Invoke-Revalidation

        Should -Invoke Get-LedgerChainResult -Times 0 -Exactly
        $chain = $result | Where-Object { $_.name -ceq 'LedgerChain' }
        $chain.status | Should -Be 'Unavailable'
        $chain.evidence | Should -Match 'hold'
        ($result | Where-Object { $_.name -ceq 'FinalReport' }).evidence | Should -Match 'not run'
    }

    It 'holds the sink while the chain is validated and the report is read, and releases it afterwards' {
        $script:lockStream = [System.IO.MemoryStream]::new()
        $script:heldDuringChain = $null
        $script:heldDuringReport = $null
        Mock -CommandName Lock-LedgerSink -MockWith { $script:lockStream }
        Mock -CommandName Get-LedgerChainResult -MockWith {
            $script:heldDuringChain = $script:lockStream.CanRead
            [pscustomobject]@{ Check = (New-CheckResult -Name 'LedgerChain' -Status 'Pass' -Evidence 'mock'); Summary = (New-Summary) }
        }
        Mock -CommandName Test-FinalReport -MockWith {
            $script:heldDuringReport = $script:lockStream.CanRead
            New-CheckResult -Name 'FinalReport' -Status 'Pass' -Evidence 'mock'
        }

        $null = Invoke-Revalidation

        $script:heldDuringChain | Should -BeTrue
        $script:heldDuringReport | Should -BeTrue
        $script:lockStream.CanRead | Should -BeFalse -Because 'the hold ends with the revalidation'
    }

    It 'releases the sink when the validation throws' {
        $script:lockStream = [System.IO.MemoryStream]::new()
        Mock -CommandName Lock-LedgerSink -MockWith { $script:lockStream }
        Mock -CommandName Get-LedgerChainResult -MockWith { throw 'boom' }

        { Invoke-Revalidation } | Should -Throw
        $script:lockStream.CanRead | Should -BeFalse
    }
}

Describe 'Ledger sink lock' -Tag 'Unit' -Skip:(-not $script:onWindows) {
    BeforeAll {
        function script:New-Sink {
            param(
                [Parameter(Mandatory)]
                [string]$Name
            )

            $path = Join-Path $TestDrive "lock/$Name.jsonl"
            $null = New-Item -Path (Split-Path -Parent $path) -ItemType Directory -Force
            [System.IO.File]::WriteAllText($path, 'x')

            return $path
        }
    }

    It 'lets the sink be read but not written while it is held, and lets it be written afterwards' {
        $path = New-Sink -Name 'held'
        $lock = Lock-LedgerSink -Path $path

        try {
            [System.IO.File]::ReadAllText($path) | Should -Be 'x'
            { [System.IO.File]::AppendAllText($path, 'y') } | Should -Throw
        } finally {
            $lock.Dispose()
        }

        { [System.IO.File]::AppendAllText($path, 'y') } | Should -Not -Throw
    }

    It 'cannot hold a sink that someone has open for writing' {
        $path = New-Sink -Name 'busy'
        $writer = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)

        try {
            { Lock-LedgerSink -Path $path } | Should -Throw
        } finally {
            $writer.Dispose()
        }
    }

    It 'cannot hold a sink that does not exist' {
        { Lock-LedgerSink -Path (Join-Path $TestDrive 'lock/absent.jsonl') } | Should -Throw
    }
}
