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
            'Test-IdentityPrivilege'
            'Test-HookContract'
            'Test-GrantRecorderUnregistered'
            'Test-EgressPolicy'
            'Test-RemoteUnreachable'
            'Test-CredentialAbsence'
            'Test-WritableRoot'
            'Get-EscapeSet'
            'Get-ModuleSearchSet'
            'Get-SearchPathProblem'
            'Get-ReplacementRight'
            'Measure-EscapePath'
            'Get-ObjectRight'
            'Get-PathChain'
            'Test-PathInside'
            'Format-RelayedText'
            'Test-LedgerProtection'
        ))

    $script:base = if ($script:onWindows) { 'C:\containment' } else { '/containment' }

    # Runs a script block as the verifier runs on the platform named, through the flag its functions read, so that
    # both branches are tested on every system.
    function script:Invoke-AsPlatform {
        param(
            [Parameter(Mandatory)]
            [bool]$Windows,

            [Parameter(Mandatory)]
            [scriptblock]$Action
        )

        $previous = $script:OnWindows

        try {
            $script:OnWindows = $Windows
            & $Action
        } finally {
            $script:OnWindows = $previous
        }
    }

    # What Get-ObjectRight reports for a folder: every right Denied except the ones named.
    function script:New-FlowRight {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter()]
            [string[]]$Granted = @()
        )

        $right = @{}
        foreach ($name in $script:RightName) {
            $right[$name] = if ($name -in $Granted) { 'Granted' } else { 'Denied' }
        }

        return [pscustomobject]@{ Path = $Path; State = 'Measured'; IsDirectory = $true; IsReparsePoint = $false; ReadOnly = $false; Right = $right; Reason = '' }
    }

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
        param(
            # Commands that run as they are, for a case that measures them through the flow.
            [Parameter()]
            [string[]]$Except = @()
        )

        Mock Test-VerifierBinding { New-CheckResult -Name 'VerifierBinding' -Status 'Pass' -Evidence 'mock' }
        Mock Test-ControlDigest { New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence 'mock' }
        Mock Test-ControlImmutability { New-CheckResult -Name 'ControlImmutability' -Status 'Pass' -Evidence 'mock' }
        Mock Test-IdentityBinding { New-CheckResult -Name 'IdentityBinding' -Status 'Pass' -Evidence 'mock' }
        Mock Test-IdentityPrivilege { New-CheckResult -Name 'IdentityPrivilege' -Status 'Pass' -Evidence 'mock' }
        Mock Test-HookContract { New-CheckResult -Name 'HookContract' -Status 'Pass' -Evidence 'mock' }
        Mock Test-GrantRecorderUnregistered { New-CheckResult -Name 'GrantRecorderUnregistered' -Status 'Pass' -Evidence 'mock' }
        Mock Test-EgressPolicy { New-CheckResult -Name 'EgressPolicy' -Status 'Pass' -Evidence 'mock' }
        Mock Test-RemoteUnreachable { New-CheckResult -Name 'RemoteUnreachable' -Status 'Pass' -Evidence 'mock' }
        Mock Test-CredentialAbsence { New-CheckResult -Name 'CredentialAbsence' -Status 'Pass' -Evidence 'mock' }

        if ('Test-WritableRoot' -notin $Except) {
            Mock Test-WritableRoot { New-CheckResult -Name 'WritableRoots' -Status 'Pass' -Evidence 'mock' }
        }

        if ('Get-EscapeSet' -notin $Except) {
            Mock Get-EscapeSet { @('escape-a', 'escape-b') }
        }

        if ('Get-ModuleSearchSet' -notin $Except) {
            Mock Get-ModuleSearchSet { @('module-a', 'module-b') }
        }

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
    It 'names the twelve checks of a run that is not live' {
        @(Get-ContainmentCheckName -LiveMode 'off') | Should -HaveCount 12
    }

    It 'adds the live artifact check last in a live mode' {
        $name = @(Get-ContainmentCheckName -LiveMode 'disposable')

        $name | Should -HaveCount 13
        $name[-1] | Should -Be 'LiveArtifacts'
    }

    It 'names the identity, token, binding and immutability checks before the hook probe that depends on them' {
        $name = @(Get-ContainmentCheckName -LiveMode 'off')

        foreach ($before in @('VerifierBinding', 'ControlDigest', 'ControlImmutability', 'IdentityBinding', 'IdentityPrivilege')) {
            $name.IndexOf($before) | Should -BeLessThan $name.IndexOf('HookContract')
        }
    }

    It 'names the token check directly after the identity binding' {
        $name = @(Get-ContainmentCheckName -LiveMode 'off')

        $name.IndexOf('IdentityPrivilege') | Should -Be ($name.IndexOf('IdentityBinding') + 1)
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

    It 'gives the grant recorder check the pinned hooks.json path and digest' {
        $null = Invoke-Flow

        Should -Invoke Test-GrantRecorderUnregistered -Times 1 -Exactly -ParameterFilter {
            $HookConfigPath -eq (Join-Path $script:base 'hooks.json') -and $HookConfigSha256 -ceq ('b' * 64)
        }
    }

    It 'measures the grant recorder even when a control it reads is unverified' {
        Mock Test-ControlDigest { New-CheckResult -Name 'ControlDigest' -Status 'Fail' -Evidence 'mock breach' }

        $result = Invoke-Flow

        ($result | Where-Object { $_.name -ceq 'GrantRecorderUnregistered' }).evidence | Should -Be 'mock'
    }

    It 'does not run the hook probe when <Gate> is <Status>' -ForEach @(
        @{ Gate = 'VerifierBinding'; Status = 'Fail' }
        @{ Gate = 'ControlDigest'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Unavailable' }
        @{ Gate = 'IdentityBinding'; Status = 'Fail' }
        @{ Gate = 'IdentityBinding'; Status = 'Unavailable' }
        @{ Gate = 'IdentityPrivilege'; Status = 'Fail' }
        @{ Gate = 'IdentityPrivilege'; Status = 'Unavailable' }
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

    It 'still measures the grant recorder when the identity cannot be bound' {
        Mock Test-IdentityBinding { New-CheckResult -Name 'IdentityBinding' -Status 'Fail' -Evidence 'mock' }

        $result = Invoke-Flow

        ($result | Where-Object { $_.name -ceq 'GrantRecorderUnregistered' }).evidence | Should -Be 'mock'
    }

    It 'still measures the grant recorder when the token is not a standard account''s' {
        Mock Test-IdentityPrivilege { New-CheckResult -Name 'IdentityPrivilege' -Status 'Fail' -Evidence 'mock' }

        $result = Invoke-Flow

        ($result | Where-Object { $_.name -ceq 'GrantRecorderUnregistered' }).evidence | Should -Be 'mock'
    }

    It 'reads the token whether or not the identity binds, because the token does not depend on the profile' {
        Mock Test-IdentityBinding { New-CheckResult -Name 'IdentityBinding' -Status 'Fail' -Evidence 'mock breach' }

        $result = Invoke-Flow

        Should -Invoke Test-IdentityPrivilege -Times 1 -Exactly
        ($result | Where-Object { $_.name -ceq 'IdentityPrivilege' }).status | Should -Be 'Pass'
    }

    # Review pass 2, S-07: git is the third program the verifier runs as the identity it measures, after the
    # hook command and the appender, and it is trusted on the same five checks.
    It 'does not let the credential check run git when <Gate> is <Status>' -ForEach @(
        @{ Gate = 'VerifierBinding'; Status = 'Fail' }
        @{ Gate = 'ControlDigest'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Fail' }
        @{ Gate = 'ControlImmutability'; Status = 'Unavailable' }
        @{ Gate = 'IdentityBinding'; Status = 'Fail' }
        @{ Gate = 'IdentityBinding'; Status = 'Unavailable' }
        @{ Gate = 'IdentityPrivilege'; Status = 'Fail' }
        @{ Gate = 'IdentityPrivilege'; Status = 'Unavailable' }
    ) {
        $script:gateName = $Gate
        $script:gateStatus = $Status
        Mock -CommandName "Test-$Gate" -MockWith { New-CheckResult -Name $script:gateName -Status $script:gateStatus -Evidence 'mock breach' }

        $null = Invoke-Flow

        Should -Invoke Test-CredentialAbsence -Times 1 -Exactly -ParameterFilter { $GitGateReason -match $script:gateName }
    }

    It 'lets the credential check run git when every control it executes is verified' {
        $null = Invoke-Flow

        Should -Invoke Test-CredentialAbsence -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($GitGateReason) }
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

    It 'gives the writable roots check the places pwsh loads modules from' {
        $null = Invoke-Flow

        Should -Invoke Get-ModuleSearchSet -Times 1 -Exactly
        Should -Invoke Test-WritableRoot -Times 1 -Exactly -ParameterFilter {
            $ModuleSet -contains 'module-a' -and $ModuleSet -contains 'module-b'
        }
    }

    # Review R12-05: a run whose module search set cannot be named still gets a report, with every other check in it.
    It 'reports WritableRoots as unmeasured, with the reason relayed, when the places pwsh loads modules from cannot be named' {
        Mock Get-ModuleSearchSet { throw ('the profile path ' + [char]0x1B + '[31m' + "`r`n" + 'is gone') }

        $result = Invoke-Flow

        @($result.name) | Should -Be @(Get-ContainmentCheckName -LiveMode 'off')
        $check = $result | Where-Object { $_.name -ceq 'WritableRoots' }
        $check.status | Should -Be 'Unavailable'
        $check.evidence | Should -Match '\A[\x20-\x7E]*\z'
        $check.evidence | Should -Match ([regex]::Escape('the profile path ?[31m??is gone'))
        Should -Invoke Test-WritableRoot -Times 0 -Exactly
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

# Brief 12, S-18: pwsh puts the module folder of the account ahead of every folder a launcher names, and auto-loads
# modules from it into the later commands of the verifier, so the writable roots check measures it. The check runs
# here as it is, through the flow, on rights this identity is given: the declared root takes files and folders, the
# folder at the front of the module path is as each case says, and every other place is a closed folder.
Describe 'Containment module folders in the flow' -Tag 'Unit' {
    BeforeAll {
        $script:accountModules = [System.IO.Path]::Combine($script:base, 'account', 'Documents', 'PowerShell', 'Modules')

        function script:Invoke-ModuleFlow {
            param(
                [Parameter(Mandatory)]
                [bool]$Writable
            )

            $script:accountModulesWritable = $Writable
            Mock Get-ObjectRight -MockWith {
                if ($Path -eq (Join-Path $script:base 'work')) {
                    return New-FlowRight -Path $Path -Granted @('WriteData', 'AppendData')
                }

                if ($Path -eq $script:accountModules -and $script:accountModulesWritable) {
                    return New-FlowRight -Path $Path -Granted @('WriteData', 'AppendData', 'DeleteChild')
                }

                return New-FlowRight -Path $Path
            }

            $previous = [System.Environment]::GetEnvironmentVariable('PSModulePath')

            try {
                [System.Environment]::SetEnvironmentVariable('PSModulePath', $script:accountModules)
                $result = Invoke-Flow
            } finally {
                [System.Environment]::SetEnvironmentVariable('PSModulePath', $previous)
            }

            return ($result | Where-Object { $_.name -ceq 'WritableRoots' })
        }
    }

    BeforeEach {
        Set-AllChecksPass -Except @('Test-WritableRoot', 'Get-EscapeSet', 'Get-ModuleSearchSet')
    }

    It 'fails WritableRoots when the module folder first on the module path is writable by this identity' {
        $check = Invoke-ModuleFlow -Writable $true

        $check.status | Should -Be 'Fail' -Because $check.evidence
        $check.evidence | Should -Match ([regex]::Escape($script:accountModules))
    }

    It 'leaves WritableRoots as it was when that folder is closed to this identity' {
        $check = Invoke-ModuleFlow -Writable $false

        $check.status | Should -Be 'Pass' -Because $check.evidence
    }
}

Describe 'Containment module search set' -Tag 'Unit' {
    BeforeAll {
        $script:search = Join-Path $TestDrive 'search'
        $script:userConfiguration = Join-Path $script:search 'user-configuration'
        $script:powerShellHome = Join-Path $script:search 'pshome'
        $null = New-Item -ItemType Directory -Path $script:userConfiguration, $script:powerShellHome -Force
        [System.IO.File]::WriteAllText((Join-Path $script:powerShellHome 'powershell.config.json'), '{}')
        $script:separator = [string][System.IO.Path]::PathSeparator

        function script:Get-TestSearchSet {
            param(
                [Parameter()]
                [AllowEmptyString()]
                [string]$ModulePath = ''
            )

            return @(Get-ModuleSearchSet -ModulePath $ModulePath -PowerShellHome $script:powerShellHome -UserConfigurationFolder $script:userConfiguration)
        }
    }

    It 'names every entry of the module path, split on the path separator of this platform and on nothing else' {
        # A drive letter puts a colon into every entry on Windows, and a semicolon is a plain character of a folder name
        # elsewhere, so both entries survive only a split on the separator the platform uses.
        $first = Join-Path $script:search 'first'
        $second = if ($script:separator -eq ';') { Join-Path $script:search 'second' } else { Join-Path $script:search 'sec;ond' }

        $set = Get-TestSearchSet -ModulePath ($first + $script:separator + $second)

        $set | Should -Contain $first
        $set | Should -Contain $second
    }

    It 'names the module folder of PSHOME even when the module path leaves it out' {
        Get-TestSearchSet -ModulePath (Join-Path $script:search 'other') | Should -Contain (Join-Path $script:powerShellHome 'Modules')
    }

    It 'names the folders of both powershell.config.json files, and a file only where it exists' {
        $set = Get-TestSearchSet

        $set | Should -Contain $script:userConfiguration
        $set | Should -Contain $script:powerShellHome
        $set | Should -Contain (Join-Path $script:powerShellHome 'powershell.config.json')
        $set | Should -Not -Contain (Join-Path $script:userConfiguration 'powershell.config.json')
    }

    It 'drops empty entries and names a place once' {
        $first = Join-Path $script:search 'first'

        $set = Get-TestSearchSet -ModulePath ($script:separator + $first + $script:separator + ' ' + $script:separator + $first + [System.IO.Path]::DirectorySeparatorChar)

        @($set | Where-Object { [string]::IsNullOrWhiteSpace($_) }) | Should -HaveCount 0
        @($set | Where-Object { [System.IO.Path]::TrimEndingDirectorySeparator($_) -eq $first }) | Should -HaveCount 1
    }

    It 'names a place once whatever the case of its letters' -Skip:(-not $script:onWindows) {
        $first = Join-Path $script:search 'first'

        $set = Get-TestSearchSet -ModulePath ($first + ';' + $first.ToUpperInvariant())

        @($set | Where-Object { $_ -eq $first }) | Should -HaveCount 1
    }

    It 'keeps an entry that <Kind> as written, so that the check can name it without opening it' -ForEach @(
        @{ Kind = 'is relative'; Entry = 'relative-modules' }
        if ($script:onWindows) {
            @{ Kind = 'names a network share'; Entry = '\\server\share\Modules' }
            @{ Kind = 'names a device path'; Entry = '\\?\C:\Modules' }
        }
    ) {
        Get-TestSearchSet -ModulePath $Entry | Should -Contain $Entry
    }

    It 'reads the folder of the user''s powershell.config.json where pwsh does, from the profile path of the host' {
        $set = @(Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome)

        $set | Should -Contain ([System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath((Split-Path -Parent $PROFILE.CurrentUserCurrentHost))))
    }

    It 'throws, rather than leave the folder of the user''s powershell.config.json out, when the host set no profile path' {
        # A profile path without the properties a host gives it, in this scope only.
        Set-Variable -Name PROFILE -Value 'a profile path without the properties of the host' -Scope Local

        { Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome } | Should -Throw -ExpectedMessage '*cannot be named: the host set no profile path*'
    }

    It 'does not ask a configuration folder it will not open whether its file exists' -Skip:(-not $script:onWindows) {
        # A device spelling of a real folder that holds the file: the folder is kept as written, and the file is not probed.
        $device = '\\?\' + $script:powerShellHome

        $set = @(Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome -UserConfigurationFolder $device)

        $set | Should -Contain $device
        $set | Should -Not -Contain ($device + '\powershell.config.json')
    }

    # Review R12-05: a profile path without a folder part names no folder either.
    It 'throws, rather than leave the folder of the user''s powershell.config.json out, when the profile path has no folder part' {
        $hostProfile = [psobject]'a profile path without a folder' | Add-Member -NotePropertyName CurrentUserCurrentHost -NotePropertyValue 'Microsoft.PowerShell_profile.ps1' -PassThru
        Set-Variable -Name PROFILE -Value $hostProfile -Scope Local

        { Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome } | Should -Throw -ExpectedMessage '*cannot be named: the profile path of the host has no folder part*'
    }

    # Review R12-02: Windows PowerShell 5.1 runs the hook line under VS Code, and it searches these two folders.
    It 'names the two module folders of Windows PowerShell 5.1 on Windows' {
        # 5.1 searches its documents folder only when that folder exists (review R12-08).
        $documents = Join-Path $script:search 'Documents'
        $null = New-Item -ItemType Directory -Path $documents -Force
        $programFiles = Join-Path $script:search 'ProgramFiles'

        $set = Invoke-AsPlatform -Windows $true -Action {
            @(Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome -UserConfigurationFolder $script:userConfiguration -DocumentsFolder $documents -ProgramFilesFolder $programFiles)
        }

        $set | Should -Contain ([System.IO.Path]::Combine($documents, 'WindowsPowerShell', 'Modules'))
        $set | Should -Contain ([System.IO.Path]::Combine($programFiles, 'WindowsPowerShell', 'Modules'))
    }

    It 'does not name the module folders of Windows PowerShell 5.1 on another system' {
        $documents = Join-Path $script:search 'Documents'
        $programFiles = Join-Path $script:search 'ProgramFiles'

        $set = Invoke-AsPlatform -Windows $false -Action {
            @(Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome -UserConfigurationFolder $script:userConfiguration -DocumentsFolder $documents -ProgramFilesFolder $programFiles)
        }

        $set | Should -Not -Contain ([System.IO.Path]::Combine($documents, 'WindowsPowerShell', 'Modules'))
        $set | Should -Not -Contain ([System.IO.Path]::Combine($programFiles, 'WindowsPowerShell', 'Modules'))
    }

    # Review R12-08: 5.1 resolves the documents folder with verification, and when that fails it puts the relative
    # WindowsPowerShell\Modules first, which resolves against its working directory. The check names the place that 5.1
    # searches, and asks no share whether it exists.
    It 'names the module folder of Windows PowerShell 5.1 where 5.1 searches when the documents folder <Case>' -ForEach @(
        @{ Case = 'is a local path that does not exist'; Kind = 'missing' }
        @{ Case = 'is on a share'; Kind = 'share' }
    ) {
        $documents = if ($Kind -eq 'share') { '\\server\share\Documents' } else { Join-Path $script:search 'no-documents' }
        $relative = [System.IO.Path]::Combine('WindowsPowerShell', 'Modules')
        $inDocuments = [System.IO.Path]::Combine($documents, 'WindowsPowerShell', 'Modules')

        $set = Invoke-AsPlatform -Windows $true -Action {
            @(Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome -UserConfigurationFolder $script:userConfiguration -DocumentsFolder $documents -ProgramFilesFolder (Join-Path $script:search 'ProgramFiles'))
        }

        if ($Kind -eq 'share') {
            $set | Should -Contain $inDocuments -Because 'a share is kept as written, so that the check does not open it'
            $set | Should -Not -Contain $relative
        } else {
            $set | Should -Contain $relative -Because '5.1 searches its working directory when the documents folder does not exist'
            $set | Should -Not -Contain $inDocuments
        }
    }

    It 'names the relative module folder of Windows PowerShell 5.1 when the documents folder cannot be named' {
        $set = Invoke-AsPlatform -Windows $true -Action {
            @(Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome -UserConfigurationFolder $script:userConfiguration -DocumentsFolder '' -ProgramFilesFolder (Join-Path $script:search 'ProgramFiles'))
        }

        $set | Should -Contain ([System.IO.Path]::Combine('WindowsPowerShell', 'Modules'))
    }

    # Review R12-08, the false Pass: in a profile closed to the identity and without a documents folder, the place in the
    # documents folder read as absent below a closed folder and passed, while every hook's 5.1 searched its working directory.
    It 'leaves WritableRoots unmeasured, not passed, for a closed profile without a documents folder' {
        $script:closedWork = Join-Path $script:search 'work'
        $script:missingDocuments = Join-Path (Join-Path $script:search 'closed-profile') 'Documents'
        Mock Get-ObjectRight -MockWith {
            if ($Path -eq $script:closedWork) {
                return New-FlowRight -Path $Path -Granted @('WriteData', 'AppendData')
            }

            $right = New-FlowRight -Path $Path

            if ($Path.StartsWith($script:missingDocuments, [System.StringComparison]::OrdinalIgnoreCase)) {
                $right.State = 'Absent'
            }

            return $right
        }

        $result = Invoke-AsPlatform -Windows $true -Action {
            $set = @(Get-ModuleSearchSet -ModulePath '' -PowerShellHome $script:powerShellHome -UserConfigurationFolder $script:userConfiguration -DocumentsFolder $script:missingDocuments -ProgramFilesFolder (Join-Path $script:search 'ProgramFiles'))
            Test-WritableRoot -Declared @($script:closedWork) -EscapeSet @() -ModuleSet $set
        }

        $result.status | Should -Be 'Unavailable' -Because $result.evidence
        $result.evidence | Should -Match ([regex]::Escape([System.IO.Path]::Combine('WindowsPowerShell', 'Modules') + ' (is not an absolute path'))
    }

    # Review R12-07: pwsh trims an entry and resolves a trailing dot, and finds its modules there.
    It 'names an entry padded with spaces as the folder it names' {
        $first = Join-Path $script:search 'first'

        Get-TestSearchSet -ModulePath "  $first  " | Should -Contain $first
    }

    It 'names an entry with a trailing dot as the folder it names' -Skip:(-not $script:onWindows) {
        $first = Join-Path $script:search 'first'

        Get-TestSearchSet -ModulePath ($first + '.') | Should -Contain $first
    }

    It 'splits the module path on the separator of <Platform> and on nothing else' -ForEach @(
        @{ Platform = 'Windows'; Windows = $true; Value = 'first;se:cond'; Expected = @('first', 'se:cond') }
        @{ Platform = 'a POSIX system'; Windows = $false; Value = 'first:se;cond'; Expected = @('first', 'se;cond') }
    ) {
        $set = Invoke-AsPlatform -Windows $Windows -Action { @(Get-TestSearchSet -ModulePath $Value) }

        foreach ($entry in $Expected) {
            $set | Should -Contain $entry
        }
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
