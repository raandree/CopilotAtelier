# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:hookRoot = Join-Path $script:repoRoot 'com.github.copilot/hooks'
    $script:verifierScript = Join-Path $script:hookRoot 'scripts/Test-RunContainment.ps1'
    $script:appenderScript = Join-Path $script:hookRoot 'scripts/Invoke-LedgerAppender.ps1'
    $script:hookConfig = Join-Path $script:hookRoot 'hooks.json'
    $script:hookScript = Join-Path $script:hookRoot 'scripts/Block-RemoteMutation.ps1'
    $script:powerShellPath = (Get-Process -Id $PID).Path

    function script:Get-Digest {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    }

    <#
        A profile that is internally consistent with the real control files, so
        each case can invalidate exactly one property and attribute the refusal
        to that property alone.
    #>
    function script:New-TestProfile {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter()]
            [hashtable]$Override = @{},

            [Parameter()]
            [string[]]$Remove = @()
        )

        $profile = [ordered]@{
            schemaVersion = 1
            verifier = [ordered]@{ path = $script:verifierScript; sha256 = (Get-Digest -Path $script:verifierScript) }
            hooksConfig = [ordered]@{ path = $script:hookConfig; sha256 = (Get-Digest -Path $script:hookConfig) }
            hookScript = [ordered]@{ path = $script:hookScript; sha256 = (Get-Digest -Path $script:hookScript) }
            ledgerAppender = [ordered]@{ path = $script:appenderScript; sha256 = (Get-Digest -Path $script:appenderScript) }
            ledgerSink = (Join-Path $TestDrive 'ledger/run.jsonl')
            chainHead = (Join-Path $TestDrive 'ledger/run.head.json')
            controllerEgressAllow = @()
            workerEgressAllow = @()
            controllerIdentity = 'CONTAINMENT\controller'
            workerIdentity = 'CONTAINMENT\worker'
            immutableControlPaths = @($script:hookConfig, $script:hookScript)
            writableRoots = @((Join-Path $TestDrive 'worktree'))
        }

        foreach ($key in $Override.Keys) {
            $profile[$key] = $Override[$key]
        }

        foreach ($key in $Remove) {
            $profile.Remove($key)
        }

        $directory = Split-Path -Parent $Path
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            $null = New-Item -Path $directory -ItemType Directory -Force
        }

        $json = $profile | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -NoNewline

        return $Path
    }

    function script:Invoke-Verifier {
        param(
            [Parameter(Mandatory)]
            [string[]]$Argument
        )

        $arguments = @('-NoProfile', '-NonInteractive', '-File', $script:verifierScript) + $Argument

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

    function script:Invoke-VerifierWithReport {
        param(
            [Parameter(Mandatory)]
            [string]$ProfilePath,

            [Parameter(Mandatory)]
            [string]$Digest,

            [Parameter()]
            [string]$Role = 'Controller'
        )

        $reportPath = Join-Path $TestDrive "report-$([guid]::NewGuid().ToString('N')).json"
        $result = Invoke-Verifier -Argument @(
            '-Verify'
            '-ProfilePath', $ProfilePath
            '-ProfileSha256', $Digest
            '-Role', $Role
            '-ReportPath', $reportPath
        )

        $report = $null
        if (Test-Path -LiteralPath $reportPath) {
            $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }

        [pscustomobject]@{
            ExitCode = $result.ExitCode
            Output = $result.Output
            Report = $report
        }
    }

    function script:Get-Check {
        param(
            [Parameter(Mandatory)]
            $Result,

            [Parameter(Mandatory)]
            [string]$Name
        )

        $Result.Report.checks | Where-Object name -EQ $Name
    }
}

Describe 'Containment verifier' -Tag 'Unit' {
    It 'ships a verifier script' {
        Test-Path -LiteralPath $script:verifierScript -PathType Leaf |
            Should -BeTrue -Because $script:verifierScript
    }

    It 'refuses a profile whose digest differs from the direct argument' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p1/profile.json')

        $result = Invoke-Verifier -Argument @(
            '-Verify', '-ProfilePath', $profilePath, '-ProfileSha256', ('b' * 64), '-Role', 'Controller'
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'digest'
    }

    It 'refuses a profile digest that is not lowercase 64-hex' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p2/profile.json')

        $result = Invoke-Verifier -Argument @(
            '-Verify', '-ProfilePath', $profilePath, '-ProfileSha256', 'not-a-digest', '-Role', 'Controller'
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
    }

    It 'refuses a profile carrying an unknown field' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p3/profile.json') -Override @{
            command = 'git push'
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        ($result.Report.checks | Where-Object name -EQ 'ProfileSchema').status |
            Should -Be 'Fail'
    }

    It 'refuses a profile missing a required field' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p4/profile.json') -Remove @('ledgerAppender')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        ($result.Report.checks | Where-Object name -EQ 'ProfileSchema').status |
            Should -Be 'Fail'
    }

    It 'refuses a non-empty controller egress allow list' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p5/profile.json') -Override @{
            controllerEgressAllow = @('10.0.0.1:443')
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        ($result.Report.checks | Where-Object name -EQ 'ProfileSchema').status |
            Should -Be 'Fail'
    }

    It 'refuses a pinned control whose digest no longer matches' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p6/profile.json') -Override @{
            hookScript = [ordered]@{ path = $script:hookScript; sha256 = ('c' * 64) }
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        ($result.Report.checks | Where-Object name -EQ 'ControlDigest').status |
            Should -Be 'Fail'
    }

    It 'refuses a pinned control path that does not exist' {
        $absent = Join-Path $TestDrive 'absent/Block-RemoteMutation.ps1'
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p7/profile.json') -Override @{
            hookScript = [ordered]@{ path = $absent; sha256 = ('d' * 64) }
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        ($result.Report.checks | Where-Object name -EQ 'ControlDigest').status |
            Should -Be 'Fail'
    }

    It 'exercises the pinned hook with safe, push, and issue payloads' -Skip:(-not $script:onWindows) {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p8/profile.json')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $hookCheck = $result.Report.checks | Where-Object name -EQ 'HookContract'
        $hookCheck | Should -Not -BeNullOrEmpty
        $hookCheck.status | Should -Be 'Pass' -Because $hookCheck.evidence
        $hookCheck.evidence | Should -Match '0'
        $hookCheck.evidence | Should -Match '2'
    }

    It 'reports every declared check by name' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p9/profile.json')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $names = @($result.Report.checks.name)
        foreach ($expected in @(
                'ProfileDigest'
                'ProfileSchema'
                'ControlDigest'
                'ControlImmutability'
                'HookContract'
                'OverrideAbsent'
                'EgressPolicy'
                'RemoteUnreachable'
                'CredentialAbsence'
                'WritableRoots'
                'LedgerProtection'
            )) {
            $names | Should -Contain $expected
        }
    }

    It 'never passes overall while any check is unmeasured' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p10/profile.json')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $unmeasured = @($result.Report.checks | Where-Object status -EQ 'Unavailable')
        if ($unmeasured.Count -gt 0) {
            $result.Report.verdict | Should -Be 'Fail' -Because 'an unmeasured control is not a passed control'
            $result.ExitCode | Should -Be 2
        }
    }

    It 'treats a failing check as a blocking exit code' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p11/profile.json')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        if ($result.Report.verdict -eq 'Fail') {
            $result.ExitCode | Should -Be 2
        } else {
            $result.ExitCode | Should -Be 0
        }
    }

    It 'refuses a live mode without the live artifacts pinned' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p12/profile.json')

        $result = Invoke-Verifier -Argument @(
            '-Verify'
            '-ProfilePath', $profilePath
            '-ProfileSha256', (Get-Digest -Path $profilePath)
            '-Role', 'Controller'
            '-LiveMode', 'read-only'
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'live'
    }

    It 'refuses to repair anything it finds broken' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p13/profile.json')
        $before = Get-Digest -Path $script:hookScript

        $null = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        Get-Digest -Path $script:hookScript |
            Should -Be $before -Because 'a verifier measures controls and never modifies them'
    }

    It 'measures the profile and every pinned control even when none is declared immutable' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p14/profile.json') -Override @{
            immutableControlPaths = @()
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        # The test identity can write every one of them, so each must be named.
        $check = Get-Check -Result $result -Name 'ControlImmutability'
        $check.status | Should -Be 'Fail' -Because $check.evidence
        foreach ($path in @(
                (Resolve-Path -LiteralPath $profilePath).ProviderPath
                $script:verifierScript
                $script:hookConfig
                $script:hookScript
                $script:appenderScript
            )) {
            $check.evidence | Should -Match ([regex]::Escape($path))
        }
    }

    It 'refuses an immutable control path that does not exist' {
        $absent = Join-Path $TestDrive 'p15/absent.json'
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p15/profile.json') -Override @{
            immutableControlPaths = @($absent)
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $check = Get-Check -Result $result -Name 'ControlImmutability'
        $check.status | Should -Be 'Fail' -Because $check.evidence
        $check.evidence | Should -Match ([regex]::Escape($absent))
    }

    It 'does not mistake a read-only attribute for an access control' -Skip:(-not $script:onWindows) {
        $flagged = Join-Path $TestDrive 'p16/flagged.json'
        $null = New-Item -Path (Split-Path -Parent $flagged) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($flagged, '{}')
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p16/profile.json') -Override @{
            immutableControlPaths = @($flagged)
        }

        (Get-Item -LiteralPath $flagged).IsReadOnly = $true
        try {
            $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)
        } finally {
            (Get-Item -LiteralPath $flagged).IsReadOnly = $false
        }

        # The attribute refuses the probe, yet any identity that may change
        # attributes can clear it, so it proves nothing about access control.
        $check = Get-Check -Result $result -Name 'ControlImmutability'
        $check.evidence | Should -Match ([regex]::Escape($flagged))
    }

    It 'reports a locked ledger as unmeasured rather than protected' -Skip:(-not $script:onWindows) {
        $ledgerRoot = Join-Path $TestDrive 'p17/ledger'
        $null = New-Item -Path $ledgerRoot -ItemType Directory -Force
        $sink = Join-Path $ledgerRoot 'run.jsonl'
        $head = Join-Path $ledgerRoot 'run.head.json'
        [System.IO.File]::WriteAllText($sink, '')
        [System.IO.File]::WriteAllText($head, '')
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p17/profile.json') -Override @{
            ledgerSink = $sink
            chainHead = $head
        }

        # A sharing violation says another process holds the file, not that
        # this identity lacks write access.
        $lock = @(
            [System.IO.File]::Open($sink, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            [System.IO.File]::Open($head, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        )
        try {
            $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)
        } finally {
            $lock | ForEach-Object { $_.Dispose() }
        }

        $check = Get-Check -Result $result -Name 'LedgerProtection'
        $check.status | Should -Be 'Unavailable' -Because $check.evidence
    }

    It 'does not call a ledger protected when its directory does not exist' {
        $missing = Join-Path $TestDrive 'p18/missing-ledger'
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p18/profile.json') -Override @{
            ledgerSink = (Join-Path $missing 'run.jsonl')
            chainHead = (Join-Path $missing 'run.head.json')
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $check = Get-Check -Result $result -Name 'LedgerProtection'
        $check.status | Should -Be 'Unavailable' -Because $check.evidence
    }
}

Describe 'Containment verifier function loading' -Tag 'Unit' {
    BeforeAll {
        . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/ScriptFunction.ps1')
    }

    It 'loads a verifier function and the constants it reads without running the script' {
        . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name 'New-CheckResult')

        $result = New-CheckResult -Name 'Example' -Status 'Pass' -Evidence 'measured'

        $result.name | Should -Be 'Example'
        $result.status | Should -Be 'Pass'
        (Get-Variable -Name 'PinnedControl' -Scope Script -ValueOnly) | Should -Contain 'hooksConfig'
    }

    It 'lets Pester mock the cmdlets a loaded function calls' {
        . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name 'Get-Digest')
        Mock -CommandName 'Get-FileHash' -MockWith { [pscustomobject]@{ Hash = 'ABCDEF' } }

        Get-Digest -Path 'anything' | Should -Be 'abcdef'
        Should -Invoke -CommandName 'Get-FileHash' -Times 1 -Exactly
    }

    It 'refuses a function name the script does not define' {
        { Get-ScriptFunctionDefinition -Path $script:verifierScript -Name 'Not-APresentFunction' } |
            Should -Throw -ExpectedMessage '*Not-APresentFunction*'
    }
}
