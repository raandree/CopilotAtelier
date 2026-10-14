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
            'Get-ContainmentCheckName'
            'Get-ContainmentCheck'
            'Get-ProtectedPath'
            'Test-ControlDigest'
            'Test-LiveArtifact'
            'Test-VerifierBinding'
            'Test-ControlImmutability'
            'Test-IdentityBinding'
            'Test-HookContract'
            'Test-GrantChannelClosed'
            'Test-EgressPolicy'
            'Test-RemoteUnreachable'
            'Test-CredentialAbsence'
            'Test-WritableRoot'
            'Get-EscapeSet'
            'Test-LedgerProtection'
        ))

    $script:base = if ($script:onWindows) { 'C:\containment' } else { '/containment' }

    function script:New-FlowProfile {
        $entry = {
            param($name, $digit)

            [pscustomobject]@{ path = (Join-Path $script:base $name); sha256 = ($digit * 64) }
        }

        return [pscustomobject]@{
            schemaVersion = 1
            verifier = & $entry 'verifier.ps1' 'a'
            hooksConfig = & $entry 'hooks.json' 'b'
            hookScript = & $entry 'hook.ps1' 'c'
            ledgerAppender = & $entry 'appender.ps1' 'd'
            ledgerSink = (Join-Path $script:base 'run.jsonl')
            chainHead = (Join-Path $script:base 'run.head.json')
            controllerEgressAllow = @()
            workerEgressAllow = @()
            controllerIdentity = 'LAB\controller'
            workerIdentity = 'LAB\worker'
            immutableControlPaths = @((Join-Path $script:base 'extra.json'))
            writableRoots = @((Join-Path $script:base 'work'))
        }
    }

    function script:Set-AllChecksPass {
        Mock Test-VerifierBinding { New-CheckResult -Name 'VerifierBinding' -Status 'Pass' -Evidence 'mock' }
        Mock Test-ControlDigest { New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence 'mock' }
        Mock Test-ControlImmutability { New-CheckResult -Name 'ControlImmutability' -Status 'Pass' -Evidence 'mock' }
        Mock Test-IdentityBinding { New-CheckResult -Name 'IdentityBinding' -Status 'Pass' -Evidence 'mock' }
        Mock Test-HookContract { New-CheckResult -Name 'HookContract' -Status 'Pass' -Evidence 'mock' }
        Mock Test-GrantChannelClosed { New-CheckResult -Name 'GrantChannelClosed' -Status 'Pass' -Evidence 'mock' }
        Mock Test-EgressPolicy { New-CheckResult -Name 'EgressPolicy' -Status 'Pass' -Evidence 'mock' }
        Mock Test-RemoteUnreachable { New-CheckResult -Name 'RemoteUnreachable' -Status 'Pass' -Evidence 'mock' }
        Mock Test-CredentialAbsence { New-CheckResult -Name 'CredentialAbsence' -Status 'Pass' -Evidence 'mock' }
        Mock Test-WritableRoot { New-CheckResult -Name 'WritableRoots' -Status 'Pass' -Evidence 'mock' }
        Mock Get-EscapeSet { @('escape-a', 'escape-b') }
        Mock Test-LedgerProtection { New-CheckResult -Name 'LedgerProtection' -Status 'Pass' -Evidence 'mock' }
        Mock Test-LiveArtifact { New-CheckResult -Name 'LiveArtifacts' -Status 'Pass' -Evidence 'mock' }
    }

    function script:Invoke-Flow {
        param(
            [Parameter()]
            [string]$LiveMode = 'off',

            [Parameter()]
            [string]$Role = 'Controller'
        )

        return @(Get-ContainmentCheck -ContainmentProfile (New-FlowProfile) -ProfilePath (Join-Path $script:base 'profile.json') `
                -Role $Role -LiveMode $LiveMode -VerifierPath (Join-Path $script:base 'verifier.ps1'))
    }
}

Describe 'Containment check names' -Tag 'Unit' {
    It 'names the eleven checks of a run that is not live' {
        @(Get-ContainmentCheckName -LiveMode 'off') | Should -HaveCount 11
    }

    It 'adds the live artifact check last in a live mode' {
        $name = @(Get-ContainmentCheckName -LiveMode 'disposable')

        $name | Should -HaveCount 12
        $name[-1] | Should -Be 'LiveArtifacts'
    }

    It 'names the identity, binding and immutability checks before the hook probe that depends on them' {
        $name = @(Get-ContainmentCheckName -LiveMode 'off')

        foreach ($before in @('VerifierBinding', 'ControlDigest', 'ControlImmutability')) {
            $name.IndexOf($before) | Should -BeLessThan $name.IndexOf('HookContract')
        }
    }
}

Describe 'Containment check flow' -Tag 'Unit' {
    BeforeEach {
        Set-AllChecksPass
    }

    It 'runs exactly the declared checks, in the declared order' {
        $result = Invoke-Flow

        @($result.name) | Should -Be @(Get-ContainmentCheckName -LiveMode 'off')
    }

    It 'adds the live artifact check only in a live mode' {
        $off = Invoke-Flow
        $live = Invoke-Flow -LiveMode 'read-only'

        @($off.name) | Should -Not -Contain 'LiveArtifacts'
        @($live.name) | Should -Be @(Get-ContainmentCheckName -LiveMode 'read-only')
        Should -Invoke Test-LiveArtifact -Times 1 -Exactly
    }

    It 'gives the hook contract the pinned paths and digests the profile declares, and the roots the run may write' {
        $null = Invoke-Flow

        Should -Invoke Test-HookContract -Times 1 -Exactly -ParameterFilter {
            $HookConfigPath -eq (Join-Path $script:base 'hooks.json') -and $HookConfigSha256 -ceq ('b' * 64) -and
            $HookScriptPath -eq (Join-Path $script:base 'hook.ps1') -and $HookScriptSha256 -ceq ('c' * 64) -and
            $WritableRoot -contains (Join-Path $script:base 'work')
        }
    }

    It 'runs the hook probe when every control it executes is verified' {
        $result = Invoke-Flow

        ($result | Where-Object { $_.name -ceq 'HookContract' }).evidence | Should -Be 'mock'
        Should -Invoke Test-HookContract -Times 1 -Exactly
    }

    It 'gives the grant channel check the pinned hooks.json path and digest' {
        $null = Invoke-Flow

        Should -Invoke Test-GrantChannelClosed -Times 1 -Exactly -ParameterFilter {
            $HookConfigPath -eq (Join-Path $script:base 'hooks.json') -and $HookConfigSha256 -ceq ('b' * 64)
        }
    }

    It 'measures the grant channel even when a control it reads is unverified' {
        Mock Test-ControlDigest { New-CheckResult -Name 'ControlDigest' -Status 'Fail' -Evidence 'mock breach' }

        $result = Invoke-Flow

        ($result | Where-Object { $_.name -ceq 'GrantChannelClosed' }).evidence | Should -Be 'mock'
    }

    It 'does not run the hook probe when <Gate> is <Status>' -ForEach @(
        @{ Gate = 'VerifierBinding'; Status = 'Fail' }
        @{ Gate = 'ControlDigest'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Unavailable' }
        @{ Gate = 'IdentityBinding'; Status = 'Fail' }
        @{ Gate = 'IdentityBinding'; Status = 'Unavailable' }
    ) {
        $script:gateName = $Gate
        $script:gateStatus = $Status
        Mock -CommandName "Test-$Gate" -MockWith { New-CheckResult -Name $script:gateName -Status $script:gateStatus -Evidence 'mock breach' }

        $result = Invoke-Flow

        Should -Invoke Test-HookContract -Times 0 -Exactly
        $hook = $result | Where-Object { $_.name -ceq 'HookContract' }
        $hook.status | Should -Be 'Unavailable'
        $hook.evidence | Should -Match 'not run'
        $hook.evidence | Should -Match $Gate
    }

    It 'still measures the grant channel when the identity cannot be bound' {
        Mock Test-IdentityBinding { New-CheckResult -Name 'IdentityBinding' -Status 'Fail' -Evidence 'mock' }

        $result = Invoke-Flow

        ($result | Where-Object { $_.name -ceq 'GrantChannelClosed' }).evidence | Should -Be 'mock'
    }

    It 'still runs every other check when one fails' {
        Mock Test-WritableRoot { New-CheckResult -Name 'WritableRoots' -Status 'Fail' -Evidence 'mock' }

        $result = Invoke-Flow

        @($result.name) | Should -Be @(Get-ContainmentCheckName -LiveMode 'off')
        Should -Invoke Test-LedgerProtection -Times 1 -Exactly
    }

    It 'gives the writable roots check the declared roots and the escape set' {
        $null = Invoke-Flow

        Should -Invoke Test-WritableRoot -Times 1 -Exactly -ParameterFilter {
            $Declared -contains (Join-Path $script:base 'work') -and $EscapeSet -contains 'escape-a' -and $EscapeSet -contains 'escape-b'
        }
    }

    It 'builds the escape set from the profile, the ledger and the head it was given' {
        $null = Invoke-Flow

        Should -Invoke Get-EscapeSet -Times 1 -Exactly -ParameterFilter {
            $ProfilePath -eq (Join-Path $script:base 'profile.json') -and
            $SinkPath -eq (Join-Path $script:base 'run.jsonl') -and
            $ChainHeadPath -eq (Join-Path $script:base 'run.head.json')
        }
    }

    It 'gives the ledger check the writable roots, so a ledger inside one fails' {
        $null = Invoke-Flow

        Should -Invoke Test-LedgerProtection -Times 1 -Exactly -ParameterFilter {
            $WritableRoot -contains (Join-Path $script:base 'work') -and $SinkPath -eq (Join-Path $script:base 'run.jsonl') -and
            $ChainHeadPath -eq (Join-Path $script:base 'run.head.json')
        }
    }

    It 'gives the credential check the writable roots, so a git inside one fails' {
        $null = Invoke-Flow

        Should -Invoke Test-CredentialAbsence -Times 1 -Exactly -ParameterFilter {
            $WritableRoot -contains (Join-Path $script:base 'work')
        }
    }
}

Describe 'Containment escape set' -Tag 'Unit' {
    It 'names the user profile, the temp folder, the folder of the profile and the folders of the ledger and the chain head' {
        $set = @(Get-EscapeSet -ProfilePath (Join-Path $script:base 'cfg/profile.json') -SinkPath (Join-Path $script:base 'ledger/run.jsonl') `
                -ChainHeadPath (Join-Path $script:base 'head/run.head.json'))

        $set | Should -Contain ([System.Environment]::GetFolderPath('UserProfile'))
        $set | Should -Contain ([System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetTempPath()))
        $set | Should -Contain (Join-Path $script:base 'cfg')
        $set | Should -Contain (Join-Path $script:base 'ledger')
        $set | Should -Contain (Join-Path $script:base 'head')
    }

    It 'lists a folder once when the ledger and the head share it' {
        $set = @(Get-EscapeSet -ProfilePath (Join-Path $script:base 'profile.json') -SinkPath (Join-Path $script:base 'run.jsonl') `
                -ChainHeadPath (Join-Path $script:base 'run.head.json'))

        @($set | Where-Object { $_ -eq $script:base }) | Should -HaveCount 1
    }

    It 'names the temp folder of the operating system when the caller has pointed the temp variables elsewhere' {
        $elsewhere = Join-Path $script:base 'caller-chosen-temp'
        $names = if ($script:onWindows) { @('TEMP', 'TMP') } else { @('TMPDIR') }
        $previous = @{}

        foreach ($name in $names) {
            $previous[$name] = [System.Environment]::GetEnvironmentVariable($name)
            [System.Environment]::SetEnvironmentVariable($name, $elsewhere)
        }

        try {
            $set = @(Get-EscapeSet -ProfilePath (Join-Path $script:base 'profile.json') -SinkPath (Join-Path $script:base 'run.jsonl') `
                    -ChainHeadPath (Join-Path $script:base 'run.head.json'))
        } finally {
            foreach ($name in $names) {
                [System.Environment]::SetEnvironmentVariable($name, $previous[$name])
            }
        }

        $osTemp = if ($script:onWindows) {
            [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData), 'Temp')
        } else {
            '/tmp'
        }

        $set | Should -Contain ([System.IO.Path]::TrimEndingDirectorySeparator($osTemp)) -Because 'the temp variables are the caller''s to set'
        $set | Should -Contain ([System.IO.Path]::TrimEndingDirectorySeparator($elsewhere)) -Because 'the folder the caller chose is still a way out'
    }
}

Describe 'Containment protected paths' -Tag 'Unit' {
    It 'lists the profile, the running verifier, every pinned control, the ledger and the declared paths' {
        $path = @(Get-ProtectedPath -ContainmentProfile (New-FlowProfile) -ProfilePath (Join-Path $script:base 'profile.json') `
                -VerifierPath (Join-Path $script:base 'running.ps1'))

        foreach ($expected in @('profile.json', 'running.ps1', 'verifier.ps1', 'hooks.json', 'hook.ps1', 'appender.ps1', 'run.jsonl', 'run.head.json', 'extra.json')) {
            @($path | Where-Object { $_ -like "*$expected" }) | Should -HaveCount 1 -Because "$expected is protected"
        }
    }

    It 'includes the live artifacts when the profile pins them' {
        $containmentProfile = New-FlowProfile
        $containmentProfile | Add-Member -NotePropertyName 'liveRunner' -NotePropertyValue ([pscustomobject]@{ path = (Join-Path $script:base 'runner.ps1'); sha256 = ('e' * 64) })

        $path = @(Get-ProtectedPath -ContainmentProfile $containmentProfile -ProfilePath (Join-Path $script:base 'profile.json') `
                -VerifierPath (Join-Path $script:base 'running.ps1'))

        @($path | Where-Object { $_ -like '*runner.ps1' }) | Should -HaveCount 1
    }

    It 'still lists the profile and the running verifier when the profile has none of the fields' {
        $path = @(Get-ProtectedPath -ContainmentProfile ([pscustomobject]@{}) -ProfilePath (Join-Path $script:base 'profile.json') `
                -VerifierPath (Join-Path $script:base 'running.ps1'))

        $path | Should -HaveCount 2
    }

    It 'still lists the profile and the running verifier when the profile is not an object' {
        $path = @(Get-ProtectedPath -ContainmentProfile 'text' -ProfilePath (Join-Path $script:base 'profile.json') `
                -VerifierPath (Join-Path $script:base 'running.ps1'))

        $path | Should -HaveCount 2
    }

    It 'lists the extra paths it is given, and ignores an empty one' {
        $path = @(Get-ProtectedPath -ContainmentProfile (New-FlowProfile) -ProfilePath (Join-Path $script:base 'profile.json') `
                -VerifierPath (Join-Path $script:base 'running.ps1') -ExtraPath @((Join-Path $script:base 'final-report.md'), $null, ''))

        @($path | Where-Object { $_ -like '*final-report.md' }) | Should -HaveCount 1
        @($path | Where-Object { [string]::IsNullOrWhiteSpace($_) }) | Should -HaveCount 0
    }

    It 'ignores an entry that is not a path' {
        $containmentProfile = New-FlowProfile
        $containmentProfile.immutableControlPaths = @('', $null, (Join-Path $script:base 'kept.json'))
        $containmentProfile.hookScript = [pscustomobject]@{ sha256 = ('c' * 64) }

        $path = @(Get-ProtectedPath -ContainmentProfile $containmentProfile -ProfilePath (Join-Path $script:base 'profile.json') `
                -VerifierPath (Join-Path $script:base 'running.ps1'))

        @($path | Where-Object { $_ -like '*kept.json' }) | Should -HaveCount 1
        @($path | Where-Object { [string]::IsNullOrWhiteSpace($_) }) | Should -HaveCount 0
    }
}

Describe 'Containment control digests' -Tag 'Unit' {
    BeforeAll {
        function script:New-PinnedProfile {
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [Parameter()]
                [hashtable]$Wrong = @{}
            )

            $null = New-Item -Path $Root -ItemType Directory -Force
            $containmentProfile = [ordered]@{}

            foreach ($name in @('verifier', 'hooksConfig', 'hookScript', 'ledgerAppender')) {
                $path = Join-Path $Root "$name.txt"
                [System.IO.File]::WriteAllText($path, "content of $name", [System.Text.UTF8Encoding]::new($false))
                $digest = Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($path))
                $containmentProfile[$name] = [pscustomobject]@{ path = $path; sha256 = $(if ($Wrong.ContainsKey($name)) { $Wrong[$name] } else { $digest }) }
            }

            return [pscustomobject]$containmentProfile
        }
    }

    It 'passes when every pinned control matches its digest' {
        $result = Test-ControlDigest -ContainmentProfile (New-PinnedProfile -Root (Join-Path $TestDrive 'ok'))

        $result.status | Should -Be 'Pass' -Because $result.evidence
        $result.name | Should -Be 'ControlDigest'
    }

    It 'fails a control whose digest differs, and names it' {
        $result = Test-ControlDigest -ContainmentProfile (New-PinnedProfile -Root (Join-Path $TestDrive 'wrong') -Wrong @{ hookScript = ('f' * 64) })

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'hookScript'
    }

    It 'fails a control whose pinned digest is spelled in upper case' {
        $root = Join-Path $TestDrive 'upper'
        $containmentProfile = New-PinnedProfile -Root $root
        $containmentProfile.hooksConfig.sha256 = $containmentProfile.hooksConfig.sha256.ToUpperInvariant()

        (Test-ControlDigest -ContainmentProfile $containmentProfile).status | Should -Be 'Fail'
    }

    It 'fails a control whose file does not exist' {
        $containmentProfile = New-PinnedProfile -Root (Join-Path $TestDrive 'gone')
        Remove-Item -LiteralPath $containmentProfile.ledgerAppender.path

        $result = Test-ControlDigest -ContainmentProfile $containmentProfile

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'ledgerAppender'
    }

    It 'fails a control the profile does not declare' {
        $containmentProfile = New-PinnedProfile -Root (Join-Path $TestDrive 'undeclared')
        $containmentProfile.PSObject.Properties.Remove('hookScript')

        $result = Test-ControlDigest -ContainmentProfile $containmentProfile

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'hookScript is not declared'
    }
}

Describe 'Containment live artifacts' -Tag 'Unit' {
    BeforeAll {
        function script:New-LiveProfile {
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [Parameter()]
                [string[]]$Omit = @(),

                [Parameter()]
                [string]$WrongDigest
            )

            $null = New-Item -Path $Root -ItemType Directory -Force
            $containmentProfile = [ordered]@{}

            foreach ($name in @('liveProfile', 'liveRunner', 'liveCommandTemplates')) {
                if ($name -in $Omit) {
                    continue
                }

                $path = Join-Path $Root "$name.txt"
                [System.IO.File]::WriteAllText($path, "content of $name", [System.Text.UTF8Encoding]::new($false))
                $digest = if ($WrongDigest -and $name -eq 'liveRunner') { $WrongDigest } else { Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($path)) }
                $containmentProfile[$name] = [pscustomobject]@{ path = $path; sha256 = $digest }
            }

            return [pscustomobject]$containmentProfile
        }
    }

    It 'passes when every live artifact is pinned and matches' {
        $result = Test-LiveArtifact -ContainmentProfile (New-LiveProfile -Root (Join-Path $TestDrive 'live-ok')) -LiveMode 'read-only'

        $result.status | Should -Be 'Pass' -Because $result.evidence
        $result.name | Should -Be 'LiveArtifacts'
    }

    It 'fails an artifact the profile does not pin' {
        $result = Test-LiveArtifact -ContainmentProfile (New-LiveProfile -Root (Join-Path $TestDrive 'live-missing') -Omit @('liveRunner')) -LiveMode 'disposable'

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match "live mode 'disposable' requires 'liveRunner'"
    }

    It 'fails an artifact whose digest differs' {
        $result = Test-LiveArtifact -ContainmentProfile (New-LiveProfile -Root (Join-Path $TestDrive 'live-wrong') -WrongDigest ('f' * 64)) -LiveMode 'read-only'

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'liveRunner'
    }
}
