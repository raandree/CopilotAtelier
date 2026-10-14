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

        $document = [ordered]@{
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
            $document[$key] = $Override[$key]
        }

        foreach ($key in $Remove) {
            $document.Remove($key)
        }

        $directory = Split-Path -Parent $Path
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            $null = New-Item -Path $directory -ItemType Directory -Force
        }

        $json = $document | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -NoNewline

        return $Path
    }

    # Runs a PowerShell process with exactly the arguments given and keeps its exit code and output.
    function script:Invoke-PowerShellProcess {
        param(
            [Parameter(Mandatory)]
            [string[]]$Argument
        )

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

            $output = & $script:powerShellPath @Argument 2>&1
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

    function script:Invoke-Verifier {
        param(
            [Parameter(Mandatory)]
            [string[]]$Argument
        )

        return (Invoke-PowerShellProcess -Argument (@('-NoProfile', '-NonInteractive', '-File', $script:verifierScript) + $Argument))
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

    It 'does not run the hook probe while a control it executes is writable by the run' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p8/profile.json')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $immutability = Get-Check -Result $result -Name 'ControlImmutability'
        $hookCheck = Get-Check -Result $result -Name 'HookContract'
        $hookCheck | Should -Not -BeNullOrEmpty

        # The test identity owns and can write every control, so on a workstation the gate is closed.
        if ($immutability.status -ne 'Pass') {
            $hookCheck.status | Should -Be 'Unavailable' -Because $hookCheck.evidence
            $hookCheck.evidence | Should -Match 'not run'
            $hookCheck.evidence | Should -Match 'ControlImmutability'
        }
    }

    It 'executes nothing from a hooks.json that is not the one the profile pins' {
        $marker = Join-Path $TestDrive 'p27/marker.txt'
        $null = New-Item -Path (Split-Path -Parent $marker) -ItemType Directory -Force
        $config = Join-Path $TestDrive 'p27/hooks.json'
        $command = if ($script:onWindows) { "echo ran> `"$marker`"" } else { "touch '$marker'" }
        $json = @{ hooks = @{ PreToolUse = @(@{ type = 'command'; windows = $command; command = $command }) } } | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($config, $json)
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p27/profile.json') -Override @{
            hooksConfig = [ordered]@{ path = $config; sha256 = ('b' * 64) }
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        Test-Path -LiteralPath $marker | Should -BeFalse -Because 'a hooks.json that is not the pinned one must never run'
        (Get-Check -Result $result -Name 'ControlDigest').status | Should -Be 'Fail'
        (Get-Check -Result $result -Name 'HookContract').status | Should -Not -Be 'Pass'
    }

    It 'refuses a profile digest argument written in upper case' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p26/profile.json')
        $upper = (Get-Digest -Path $profilePath).ToUpperInvariant()

        $result = Invoke-Verifier -Argument @(
            '-Verify', '-ProfilePath', $profilePath, '-ProfileSha256', $upper, '-Role', 'Controller'
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'lowercase'
    }

    It 'refuses to run inside a session that has run other code, and measures nothing' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p29/profile.json')
        $digest = Get-Digest -Path $profilePath
        $reportPath = Join-Path $TestDrive 'p29/report.json'
        $command = "& '$($script:verifierScript)' -Verify -ProfilePath '$profilePath' -ProfileSha256 '$digest' -Role Controller -ReportPath '$reportPath'; exit `$LASTEXITCODE"

        $result = Invoke-PowerShellProcess -Argument @('-NoProfile', '-NonInteractive', '-Command', $command)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'fresh process'
        Test-Path -LiteralPath $reportPath | Should -BeFalse -Because 'a refused process measures and reports nothing'
    }

    It 'refuses a process that loaded the profile of the user, and measures nothing' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p29b/profile.json')
        $digest = Get-Digest -Path $profilePath
        $reportPath = Join-Path $TestDrive 'p29b/report.json'

        $result = Invoke-PowerShellProcess -Argument @(
            '-NonInteractive', '-File', $script:verifierScript, '-Verify', '-ProfilePath', $profilePath
            '-ProfileSha256', $digest, '-Role', 'Controller', '-ReportPath', $reportPath
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'NoProfile'
        Test-Path -LiteralPath $reportPath | Should -BeFalse -Because 'a refused process measures and reports nothing'
    }

    It 'reports every other check as not run when the profile fails its schema' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p28/profile.json') -Remove @('ledgerSink')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        (Get-Check -Result $result -Name 'ProfileSchema').status | Should -Be 'Fail'

        foreach ($name in @('VerifierBinding', 'ControlDigest', 'HookContract', 'LedgerProtection')) {
            $check = Get-Check -Result $result -Name $name
            $check | Should -Not -BeNullOrEmpty -Because "$name must be named even when it did not run"
            $check.status | Should -Be 'Unavailable'
            $check.evidence | Should -Match 'not run'
        }
    }

    It 'refuses a profile that is not a JSON object without measuring anything' {
        $profilePath = Join-Path $TestDrive 'p28b/profile.json'
        $null = New-Item -Path (Split-Path -Parent $profilePath) -ItemType Directory -Force
        [System.IO.File]::WriteAllText($profilePath, '["not","an","object"]')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        (Get-Check -Result $result -Name 'ProfileSchema').evidence | Should -Match 'not a JSON object'
    }

    It 'fails when the verifier that runs is not the pinned file' {
        $copy = Join-Path $TestDrive 'p31/Test-RunContainment.ps1'
        $null = New-Item -Path (Split-Path -Parent $copy) -ItemType Directory -Force
        Copy-Item -LiteralPath $script:verifierScript -Destination $copy
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p31/profile.json') -Override @{
            verifier = [ordered]@{ path = $copy; sha256 = (Get-Digest -Path $copy) }
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $check = Get-Check -Result $result -Name 'VerifierBinding'
        $check.status | Should -Be 'Fail' -Because $check.evidence
        $check.evidence | Should -Match ([regex]::Escape($copy))
    }

    It 'refuses a report path that is a pinned control and leaves the control untouched' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p29/profile.json')
        $before = Get-Digest -Path $script:hookScript

        $result = Invoke-Verifier -Argument @(
            '-Verify', '-ProfilePath', $profilePath, '-ProfileSha256', (Get-Digest -Path $profilePath), '-Role', 'Controller'
            '-ReportPath', $script:hookScript
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'protected'
        Get-Digest -Path $script:hookScript | Should -Be $before -Because 'the report must never overwrite a control'
    }

    It 'refuses a report path that is the profile itself and leaves the profile untouched' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p29b/profile.json')
        $before = Get-Digest -Path $profilePath

        $result = Invoke-Verifier -Argument @(
            '-Verify', '-ProfilePath', $profilePath, '-ProfileSha256', $before, '-Role', 'Controller'
            '-ReportPath', $profilePath
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        Get-Digest -Path $profilePath | Should -Be $before
    }

    It 'refuses a relative report path' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p29c/profile.json')

        $result = Invoke-Verifier -Argument @(
            '-Verify', '-ProfilePath', $profilePath, '-ProfileSha256', (Get-Digest -Path $profilePath), '-Role', 'Controller'
            '-ReportPath', 'report.json'
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'absolute'
    }

    It 'does not create the directory of a report path' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p29d/profile.json')
        $missing = Join-Path $TestDrive 'p29d/absent-directory/report.json'

        $result = Invoke-Verifier -Argument @(
            '-Verify', '-ProfilePath', $profilePath, '-ProfileSha256', (Get-Digest -Path $profilePath), '-Role', 'Controller'
            '-ReportPath', $missing
        )

        $result.ExitCode | Should -Be 2 -Because $result.Output
        Test-Path -LiteralPath (Split-Path -Parent $missing) | Should -BeFalse
    }

    It 'reports every declared check by name' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p9/profile.json')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $names = @($result.Report.checks.name)
        foreach ($expected in @(
                'ProfileDigest'
                'ProfileSchema'
                'VerifierBinding'
                'ControlDigest'
                'ControlImmutability'
                'IdentityBinding'
                'HookContract'
                'GrantRecorderUnregistered'
                'EgressPolicy'
                'RemoteUnreachable'
                'CredentialAbsence'
                'WritableRoots'
                'LedgerProtection'
            )) {
            $names | Should -Contain $expected
        }
    }

    It 'refuses the shipped hooks.json, which records Remote grants from prompt text' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p32/profile.json')

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $check = Get-Check -Result $result -Name 'GrantRecorderUnregistered'
        $check.status | Should -Be 'Fail' -Because $check.evidence
        $check.evidence | Should -Match 'UserPromptSubmit'
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

    It 'fails a read-only control in a directory the run can delete from' -Skip:(-not $script:onWindows) {
        # Review of 2026-10-12, C-02: a file that cannot be written is still replaceable
        # when the directory that holds it lets the caller delete its children.
        $directory = Join-Path $TestDrive 'p22'
        $null = New-Item -Path $directory -ItemType Directory -Force
        $flagged = Join-Path $directory 'control.json'
        [System.IO.File]::WriteAllText($flagged, '{}')
        $profilePath = New-TestProfile -Path (Join-Path $directory 'profile.json') -Override @{
            immutableControlPaths = @($flagged)
        }

        (Get-Item -LiteralPath $flagged).IsReadOnly = $true
        try {
            $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)
        } finally {
            (Get-Item -LiteralPath $flagged).IsReadOnly = $false
        }

        $check = Get-Check -Result $result -Name 'ControlImmutability'
        $check.status | Should -Be 'Fail' -Because $check.evidence
        $check.evidence | Should -Match 'FILE_DELETE_CHILD'
        $check.evidence | Should -Match ([regex]::Escape($directory))
    }

    It 'fails a control that denies writing but belongs to the run identity' -Skip:(-not $script:onWindows) {
        # Review of 2026-10-12, C-02: a deny entry does not protect a file from its owner.
        $directory = Join-Path $TestDrive 'p23'
        $null = New-Item -Path $directory -ItemType Directory -Force
        $flagged = Join-Path $directory 'control.json'
        [System.IO.File]::WriteAllText($flagged, '{}')
        $acl = Get-Acl -LiteralPath $flagged
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new([System.Security.Principal.WindowsIdentity]::GetCurrent().Name, 'Write', 'Deny'))
        Set-Acl -LiteralPath $flagged -AclObject $acl
        $profilePath = New-TestProfile -Path (Join-Path $directory 'profile.json') -Override @{
            immutableControlPaths = @($flagged)
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        $check = Get-Check -Result $result -Name 'ControlImmutability'
        $check.status | Should -Be 'Fail' -Because $check.evidence
        $check.evidence | Should -Match ([regex]::Escape("this identity holds WRITE_DAC on the file $flagged"))
    }

    It 'measures a role only when the verifier runs as the identity the profile declares for it' -Skip:(-not $script:onWindows) {
        # Review of 2026-10-12, C-01: every probe measured whoever ran the script, so -Role Worker
        # from any account read Pass.
        $caller = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p24/profile.json') -Override @{
            controllerIdentity = $caller
            workerIdentity = 'NT AUTHORITY\LOCAL SERVICE'
        }
        $digest = Get-Digest -Path $profilePath

        $asController = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest $digest -Role 'Controller'
        $asWorker = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest $digest -Role 'Worker'

        (Get-Check -Result $asController -Name 'IdentityBinding').status | Should -Be 'Pass'
        $workerCheck = Get-Check -Result $asWorker -Name 'IdentityBinding'
        $workerCheck.status | Should -Be 'Fail' -Because $workerCheck.evidence
    }

    It 'reports a role identity it cannot resolve as unmeasured' -Skip:(-not $script:onWindows) {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p25/profile.json') -Override @{
            controllerIdentity = 'CONTAINMENT\no-such-account-for-the-test'
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        (Get-Check -Result $result -Name 'IdentityBinding').status | Should -Be 'Unavailable'
    }

    It 'does not call a ledger that another process holds open protected' -Skip:(-not $script:onWindows) {
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

        # A sharing violation says another process holds the file, not that this identity lacks
        # write access; the directory above it is still measured, and this identity can write it.
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
        $check.status | Should -Not -Be 'Pass' -Because $check.evidence
        $check.evidence | Should -Match 'run.jsonl'
    }

    It 'does not call a ledger protected when its directory does not exist' {
        $missing = Join-Path $TestDrive 'p18/missing-ledger'
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'p18/profile.json') -Override @{
            ledgerSink = (Join-Path $missing 'run.jsonl')
            chainHead = (Join-Path $missing 'run.head.json')
        }

        $result = Invoke-VerifierWithReport -ProfilePath $profilePath -Digest (Get-Digest -Path $profilePath)

        # This identity can create the missing directory, so a substitute ledger could be planted.
        $check = Get-Check -Result $result -Name 'LedgerProtection'
        $check.status | Should -Not -Be 'Pass' -Because $check.evidence
        $check.evidence | Should -Match 'missing-ledger'
    }
}

Describe 'Containment revalidation command' -Tag 'Unit' {
    BeforeAll {
        function script:Invoke-Revalidation {
            param(
                [Parameter(Mandatory)]
                [string]$ProfilePath,

                [Parameter()]
                [AllowEmptyString()]
                [string]$FinalReportPath = '',

                [Parameter()]
                [string]$ReportPath = '',

                [Parameter()]
                [string]$Digest = ''
            )

            if (-not $Digest) {
                $Digest = Get-Digest -Path $ProfilePath
            }

            $argument = @('-Revalidate', '-ProfilePath', $ProfilePath, '-ProfileSha256', $Digest, '-Role', 'Controller')

            if ($FinalReportPath) {
                $argument += @('-FinalReportPath', $FinalReportPath)
            }

            if ($ReportPath) {
                $argument += @('-ReportPath', $ReportPath)
            }

            $result = Invoke-Verifier -Argument $argument
            $report = $null

            if ($ReportPath -and (Test-Path -LiteralPath $ReportPath)) {
                # In a refusal the path may be the protected file itself, which is not JSON.
                try {
                    $report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    $report = $null
                }
            }

            [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output; Report = $report }
        }

        function script:New-FinalReport {
            param(
                [Parameter(Mandatory)]
                [string]$Name
            )

            $path = Join-Path $TestDrive "$Name/final-report.md"
            $null = New-Item -Path (Split-Path -Parent $path) -ItemType Directory -Force
            [System.IO.File]::WriteAllText($path, 'the final report')

            return $path
        }
    }

    It 'refuses a revalidation that names no final report' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r1/profile.json')

        $result = Invoke-Revalidation -ProfilePath $profilePath

        $result.ExitCode | Should -Not -Be 0 -Because $result.Output
    }

    It 'refuses a relative final report path' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r2/profile.json')

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath 'final-report.md'

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'absolute'
    }

    It 'refuses a final report that does not exist' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r3/profile.json')

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath (Join-Path $TestDrive 'r3/absent.md')

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'does not exist'
    }

    It 'refuses a profile digest that does not match the direct argument' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r4/profile.json')

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath (New-FinalReport -Name 'r4') -Digest ('b' * 64)

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'digest'
    }

    It 'refuses a structured report path that is the final report, and leaves the final report untouched' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r5/profile.json')
        $finalReport = New-FinalReport -Name 'r5'
        $before = Get-Digest -Path $finalReport

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath $finalReport -ReportPath $finalReport

        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match 'protected'
        Get-Digest -Path $finalReport | Should -Be $before
    }

    It 'refuses a structured report path that is a pinned control' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r6/profile.json')
        $before = Get-Digest -Path $script:appenderScript

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath (New-FinalReport -Name 'r6') -ReportPath $script:appenderScript

        $result.ExitCode | Should -Be 2 -Because $result.Output
        Get-Digest -Path $script:appenderScript | Should -Be $before
    }

    It 'names every revalidation check and marks the mode in the report' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r7/profile.json')

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath (New-FinalReport -Name 'r7') -ReportPath (Join-Path $TestDrive 'r7/result.json')

        $result.Report | Should -Not -BeNullOrEmpty -Because $result.Output
        $result.Report.mode | Should -Be 'Revalidate'
        $names = @($result.Report.checks.name)
        foreach ($expected in @('ProfileDigest', 'ProfileSchema', 'VerifierBinding', 'ControlDigest', 'ControlImmutability', 'IdentityBinding', 'LedgerChain', 'FinalReport', 'LedgerProtection')) {
            $names | Should -Contain $expected
        }
    }

    It 'reports every other check as not run when the profile fails its schema' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r8/profile.json') -Remove @('ledgerSink')

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath (New-FinalReport -Name 'r8') -ReportPath (Join-Path $TestDrive 'r8/result.json')

        $result.ExitCode | Should -Be 2 -Because $result.Output
        foreach ($name in @('ControlDigest', 'LedgerChain', 'FinalReport', 'LedgerProtection')) {
            $check = $result.Report.checks | Where-Object name -EQ $name
            $check.status | Should -Be 'Unavailable'
            $check.evidence | Should -Match 'not run'
        }
    }

    It 'executes nothing from an appender that is not the one the profile pins' {
        $marker = Join-Path $TestDrive 'r9/marker.txt'
        $null = New-Item -Path (Split-Path -Parent $marker) -ItemType Directory -Force
        $stub = Join-Path $TestDrive 'r9/appender.ps1'
        [System.IO.File]::WriteAllText($stub, "Set-Content -LiteralPath '$marker' -Value ran`nexit 0")
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r9/profile.json') -Override @{
            ledgerAppender = [ordered]@{ path = $stub; sha256 = ('b' * 64) }
        }

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath (New-FinalReport -Name 'r9') -ReportPath (Join-Path $TestDrive 'r9/result.json')

        $result.ExitCode | Should -Be 2 -Because $result.Output
        Test-Path -LiteralPath $marker | Should -BeFalse -Because 'an appender that is not the pinned one must never run'
        ($result.Report.checks | Where-Object name -EQ 'ControlDigest').status | Should -Be 'Fail'
        ($result.Report.checks | Where-Object name -EQ 'LedgerChain').status | Should -Not -Be 'Pass'
    }

    It 'does not run the pinned appender while a control it executes is writable by the run' {
        $profilePath = New-TestProfile -Path (Join-Path $TestDrive 'r10/profile.json')

        $result = Invoke-Revalidation -ProfilePath $profilePath -FinalReportPath (New-FinalReport -Name 'r10') -ReportPath (Join-Path $TestDrive 'r10/result.json')

        $immutability = $result.Report.checks | Where-Object name -EQ 'ControlImmutability'
        $chain = $result.Report.checks | Where-Object name -EQ 'LedgerChain'

        # The test identity owns and can write every control, so on a workstation the gate is closed.
        if ($immutability.status -ne 'Pass') {
            $chain.status | Should -Be 'Unavailable' -Because $chain.evidence
            $chain.evidence | Should -Match 'not run'
        }
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

    It 'lets Pester mock the commands a loaded function calls' {
        . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @('New-CheckResult', 'Get-NotRunCheck'))
        Mock -CommandName 'New-CheckResult' -MockWith { @{ name = $Name; status = 'Mocked'; evidence = $Evidence } }

        $result = @(Get-NotRunCheck -Name 'Example' -Reason 'anything')

        $result | Should -HaveCount 1
        $result[0].status | Should -Be 'Mocked'
        Should -Invoke -CommandName 'New-CheckResult' -Times 1 -Exactly
    }

    It 'refuses a function name the script does not define' {
        { Get-ScriptFunctionDefinition -Path $script:verifierScript -Name 'Not-APresentFunction' } |
            Should -Throw -ExpectedMessage '*Not-APresentFunction*'
    }
}
