# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

# The few cases that drive a real git child process; the rest never start one.
$script:hasGit = $null -ne (Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue)

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'

    . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'New-CheckResult'
            'Format-RelayedText'
            'Test-EgressPolicy'
            'Test-RemoteUnreachable'
            'Test-CredentialAbsence'
            'Test-PathProtection'
            'Get-ConfigKeyName'
            'Resolve-GitExecutable'
            'Get-ScrubbedGitEnvironment'
            'Invoke-GitConfigProcess'
            'Get-PropertyText'
            'Get-FirewallProfileState'
            'Get-OutboundAllowRule'
            'Get-CallerSecurityIdentifier'
            'Test-RuleAppliesToIdentity'
            'Test-TcpEndpoint'
            'Invoke-ProbeSelfTest'
        ))

    <#
        Stands in for the object Get-NetFirewallProfile returns. Enabled and
        DefaultOutboundAction arrive as enumerations whose string form is
        True/False and Block/Allow, so the stub carries strings.
    #>
    function script:New-FirewallProfileStub {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter()]
            [AllowEmptyString()]
            [string]$Enabled = 'True',

            [Parameter()]
            [AllowEmptyString()]
            [string]$DefaultOutboundAction = 'Block'
        )

        [pscustomobject]@{
            Name = $Name
            Enabled = $Enabled
            DefaultOutboundAction = $DefaultOutboundAction
        }
    }

    function script:New-FirewallRuleStub {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter()]
            [string]$DisplayName = $Name
        )

        [pscustomobject]@{
            Name = $Name
            InstanceID = $Name
            DisplayName = $DisplayName
            Profile = 'Any'
        }
    }

    function script:New-SecurityFilterStub {
        param(
            [Parameter(Mandatory)]
            [string]$InstanceID,

            [Parameter()]
            [string]$LocalUser = 'Any'
        )

        [pscustomobject]@{
            InstanceID = $InstanceID
            LocalUser = $LocalUser
            RemoteUser = 'Any'
            RemoteMachine = 'Any'
        }
    }

    # The real token of whoever runs the suite, so the user-condition cases
    # measure the same identity resolution the verifier performs.
    $script:callerSid = if ($script:onWindows) {
        [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    } else {
        'S-1-5-21-0-0-0-1000'
    }

    # A well-known relative identifier in a domain that cannot exist locally, so
    # it is never present in the caller's token.
    $script:otherSid = 'S-1-5-21-1111111111-2222222222-3333333333-500'

    # Everything Test-CredentialAbsence measures in the environment. The cases
    # clear the lot, so a proxy or a token that happens to be set on the machine
    # running the suite cannot decide a result.
    $script:measuredVariable = @(
        'GH_TOKEN', 'GITHUB_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'SSH_AUTH_SOCK'
        'GIT_ASKPASS', 'SSH_ASKPASS', 'GIT_SSH', 'GIT_SSH_COMMAND'
        'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS'
        'XDG_CONFIG_HOME'
    )

    function script:Clear-MeasuredEnvironment {
        [OutputType([hashtable])]
        param()

        $saved = @{}

        foreach ($name in $script:measuredVariable) {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }

        return $saved
    }

    function script:Restore-MeasuredEnvironment {
        param(
            [Parameter(Mandatory)]
            [hashtable]$Saved
        )

        foreach ($name in $Saved.Keys) {
            [Environment]::SetEnvironmentVariable($name, $Saved[$name])
        }
    }

    function script:New-GitConfigurationFile {
        param(
            [Parameter(Mandatory)]
            [string]$CaseName,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Text
        )

        $caseRoot = Join-Path $TestDrive $CaseName
        $null = New-Item -Path $caseRoot -ItemType Directory -Force
        $path = Join-Path $caseRoot 'gitconfig'
        [System.IO.File]::WriteAllText($path, $Text)

        return $path
    }

    # What Test-PathProtection reports for a path that is closed to this identity, or that is not.
    function script:New-GitProtection {
        param(
            [Parameter()]
            [string[]]$Violation = @(),

            [Parameter()]
            [string[]]$Unmeasured = @()
        )

        return [pscustomobject]@{ Path = 'C:\pinned\git.exe'; Closed = ($Violation.Count -eq 0 -and $Unmeasured.Count -eq 0); Absent = $false; Violation = $Violation; Unmeasured = $Unmeasured }
    }

    # A git child that found nothing, used wherever a case is about something
    # other than the git result itself.
    function script:Set-CleanGitMock {
        param()

        Mock -CommandName 'Resolve-GitExecutable' -MockWith { 'C:\pinned\git.exe' }
        Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection }
        Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
            @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
        } -ParameterFilter { $Argument -contains '--list' }
        Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
            @{ ExitCode = 1; Output = @(); TimedOut = $false; Failure = '' }
        } -ParameterFilter { $Argument -contains '--get-regexp' }
    }
}

Describe 'Containment verifier egress policy' -Tag 'Unit' {
    Context 'the declared allow list' {
        It 'fails a role that declares any allowed destination' {
            $result = Test-EgressPolicy -DeclaredAllow @('https://api.github.com')

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'must have none'
        }

        It 'does not reach the firewall when the declared list already fails' -Skip:(-not $script:onWindows) {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith { throw 'the firewall must not be read' }

            $result = Test-EgressPolicy -DeclaredAllow @('https://api.github.com')

            $result.status | Should -Be 'Fail' -Because $result.evidence
            Should -Invoke -CommandName 'Get-NetFirewallProfile' -Times 0 -Exactly
        }
    }

    Context 'a platform without Windows Defender Firewall' {
        It 'reports the outbound policy as unmeasured rather than clean' {
            $saved = Get-Variable -Name 'OnWindows' -Scope Script -ValueOnly

            try {
                Set-Variable -Name 'OnWindows' -Scope Script -Value $false
                $result = Test-EgressPolicy -DeclaredAllow @()
            } finally {
                Set-Variable -Name 'OnWindows' -Scope Script -Value $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'Windows Defender Firewall only'
        }
    }

    Context 'the firewall profiles' -Skip:(-not $script:onWindows) {
        BeforeEach {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { @() }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith { @() }
        }

        It 'fails a disabled profile even when its outbound default is Block' {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith {
                @(
                    New-FirewallProfileStub -Name 'Domain' -Enabled 'True'
                    New-FirewallProfileStub -Name 'Public' -Enabled 'False'
                )
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'Public'
            $result.evidence | Should -Match 'disabled'
        }

        It 'reports a profile whose enabled state cannot be read as unmeasured' {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith {
                @(New-FirewallProfileStub -Name 'Domain' -Enabled 'NotConfigured')
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'Domain'
        }

        It 'fails an outbound default that is not Block' {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith {
                @(New-FirewallProfileStub -Name 'Private' -DefaultOutboundAction 'Allow')
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'Private=Allow'
        }

        It 'reports an outbound default that cannot be read as unmeasured' {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith {
                @(New-FirewallProfileStub -Name 'Private' -DefaultOutboundAction '')
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'Private'
        }

        It 'reports a firewall it cannot read as unmeasured' {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith { throw 'access is denied' }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'access is denied'
        }

        It 'passes a policy that is enabled, blocking, and free of applicable allow rules' {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith {
                @(
                    New-FirewallProfileStub -Name 'Domain'
                    New-FirewallProfileStub -Name 'Private'
                    New-FirewallProfileStub -Name 'Public'
                )
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Match 'proxy'
        }
    }

    Context 'the outbound allow rules' -Skip:(-not $script:onWindows) {
        BeforeEach {
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith {
                @(New-FirewallProfileStub -Name 'Domain')
            }
        }

        It 'fails an enabled outbound allow rule that applies to everyone' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'AllowAll' -DisplayName 'Allow everything outbound')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                @(New-SecurityFilterStub -InstanceID 'AllowAll' -LocalUser 'Any')
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'Allow everything outbound'
        }

        It 'fails an allow rule whose user condition names the caller' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'ScopedToCaller' -DisplayName 'Scoped to the caller')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                @(New-SecurityFilterStub -InstanceID 'ScopedToCaller' -LocalUser "D:(A;;CC;;;$($script:callerSid))")
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'Scoped to the caller'
        }

        It 'ignores an allow rule whose user condition names only another principal' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'ScopedToOther' -DisplayName 'Scoped to somebody else')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                @(New-SecurityFilterStub -InstanceID 'ScopedToOther' -LocalUser "D:(A;;CC;;;$($script:otherSid))")
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'ignores an allow rule that denies the caller' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'DeniesCaller' -DisplayName 'Denies the caller')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                @(New-SecurityFilterStub -InstanceID 'DeniesCaller' -LocalUser "D:(D;;CC;;;$($script:callerSid))(A;;CC;;;$($script:otherSid))")
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'treats a user condition that names the alias <Alias> as applicable, because it cannot be resolved to the caller' -ForEach @(
            @{ Alias = 'WD' }
            @{ Alias = 'AU' }
            @{ Alias = 'BU' }
        ) {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'AliasRule' -DisplayName 'Alias user condition')
            }
            $script:aliasCondition = "D:(A;;CC;;;$Alias)"
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                @(New-SecurityFilterStub -InstanceID 'AliasRule' -LocalUser $script:aliasCondition)
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'Alias user condition'
        }

        It 'treats a deny entry that names an alias as unresolved, so the rule still applies' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'AliasDeny' -DisplayName 'Alias deny rule')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                @(New-SecurityFilterStub -InstanceID 'AliasDeny' -LocalUser "D:(D;;CC;;;BU)(A;;CC;;;$($script:otherSid))")
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
        }

        It 'treats a user condition it cannot parse as applicable' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'Unparsable' -DisplayName 'Unparsable user condition')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                @(New-SecurityFilterStub -InstanceID 'Unparsable' -LocalUser 'not an sddl string')
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'Unparsable user condition'
        }

        It 'treats a rule with no user condition at all as applicable' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'NoFilter' -DisplayName 'No user condition')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith { @() }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'No user condition'
        }

        It 'names at most ten applicable rules and counts the rest' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                1..13 | ForEach-Object { New-FirewallRuleStub -Name "Rule$_" -DisplayName "Outbound rule $_" }
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith {
                1..13 | ForEach-Object { New-SecurityFilterStub -InstanceID "Rule$_" }
            }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match '13 enabled outbound allow rule'
            $result.evidence | Should -Match 'Outbound rule 10'
            $result.evidence | Should -Not -Match 'Outbound rule 11'
            $result.evidence | Should -Match '3 more'
        }

        It 'reports outbound allow rules it cannot read as unmeasured' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { throw 'the rule store is unreadable' }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith { @() }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'the rule store is unreadable'
        }

        It 'reports user conditions it cannot read as unmeasured' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(New-FirewallRuleStub -Name 'AnyRule')
            }
            Mock -CommandName 'Get-NetFirewallSecurityFilter' -MockWith { throw 'the filters are unreadable' }

            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'the filters are unreadable'
        }
    }

    Context 'the firewall of the machine running the suite' -Skip:(-not $script:onWindows) {
        <#
            The only case that reads the real policy store. It asserts the shape
            of the measurement, never a verdict: a Pass would depend on how this
            particular machine is configured, and claiming one here is the
            mistake the whole script exists to avoid.
        #>
        It 'measures the real policy store and returns a legal result' {
            $result = Test-EgressPolicy -DeclaredAllow @()

            $result.name | Should -Be 'EgressPolicy'
            $result.status | Should -BeIn @('Pass', 'Fail', 'Unavailable') -Because $result.evidence
            $result.evidence | Should -Not -BeNullOrEmpty
        }

        It 'resolves the identity of the caller to at least its own security identifier' {
            $sid = @(Get-CallerSecurityIdentifier)

            $sid | Should -Contain ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        }
    }
}

Describe 'Containment verifier remote reachability' -Tag 'Unit' {
    Context 'the positive control' {
        It 'reports reachability as unmeasured when the probe cannot be validated' {
            Mock -CommandName 'Invoke-ProbeSelfTest' -MockWith {
                @{ Validated = $false; Detail = 'the loopback listener refused the probe' }
            }
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Denied'; Detail = 'denied' } }

            $result = Test-RemoteUnreachable

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'could not be validated'
        }

        It 'does not probe a canary when the probe is not validated' {
            Mock -CommandName 'Invoke-ProbeSelfTest' -MockWith {
                @{ Validated = $false; Detail = 'no listener' }
            }
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Denied'; Detail = 'denied' } }

            $null = Test-RemoteUnreachable

            Should -Invoke -CommandName 'Test-TcpEndpoint' -Times 0 -Exactly
        }

        It 'validates the probe against a loopback listener it opens itself' {
            $control = Invoke-ProbeSelfTest

            $control.Validated | Should -BeTrue -Because $control.Detail
        }

        It 'releases every listener it opens, so the control can run repeatedly' {
            $result = 1..25 | ForEach-Object { Invoke-ProbeSelfTest }

            @($result | Where-Object { -not $_.Validated }) | Should -BeNullOrEmpty -Because (
                ($result | Where-Object { -not $_.Validated } | ForEach-Object { $_.Detail }) -join '; '
            )
        }
    }

    Context 'the canary endpoints' {
        BeforeEach {
            Mock -CommandName 'Invoke-ProbeSelfTest' -MockWith {
                @{ Validated = $true; Detail = 'the loopback probe connected' }
            }
        }

        It 'probes both canary endpoints' {
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Denied'; Detail = 'blocked by local policy' } }

            $null = Test-RemoteUnreachable

            Should -Invoke -CommandName 'Test-TcpEndpoint' -Times 2 -Exactly
        }

        It 'fails when a canary connects' {
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Connected'; Detail = 'connected' } }

            $result = Test-RemoteUnreachable

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match '1\.1\.1\.1:443'
        }

        It 'fails when a canary refuses the connection, because the peer answered' {
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Refused'; Detail = 'connection refused' } }

            $result = Test-RemoteUnreachable

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'refused'
        }

        It 'reports a timed-out canary as unmeasured rather than closed' {
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Unreachable'; Detail = 'timed out' } }

            $result = Test-RemoteUnreachable

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'timed out'
        }

        It 'reports one unmeasured canary as unmeasured even when the other is denied' {
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Denied'; Detail = 'blocked by local policy' } } -ParameterFilter { $Address -eq '1.1.1.1' }
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Unreachable'; Detail = 'the network is down' } } -ParameterFilter { $Address -eq '8.8.8.8' }

            $result = Test-RemoteUnreachable

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match '8\.8\.8\.8:53'
        }

        It 'prefers the open verdict when one canary connects and another is unmeasured' {
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Connected'; Detail = 'connected' } } -ParameterFilter { $Address -eq '1.1.1.1' }
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Unreachable'; Detail = 'the network is down' } } -ParameterFilter { $Address -eq '8.8.8.8' }

            $result = Test-RemoteUnreachable

            $result.status | Should -Be 'Fail' -Because $result.evidence
        }

        It 'passes only when local policy denied every canary' {
            Mock -CommandName 'Test-TcpEndpoint' -MockWith { @{ Outcome = 'Denied'; Detail = 'blocked by local policy' } }

            $result = Test-RemoteUnreachable

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Match '1\.1\.1\.1:443'
            $result.evidence | Should -Match '8\.8\.8\.8:53'
        }
    }

    Context 'the socket classification' {
        It 'never reports a dead loopback port as connected or as denied by policy' {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $port = $listener.LocalEndpoint.Port
            $listener.Stop()

            $outcome = Test-TcpEndpoint -Address '127.0.0.1' -Port $port -TimeoutMilliseconds 5000

            # How fast a refusal arrives is a property of the host, so both
            # classifications are legitimate here; neither of the two that would
            # end the check is.
            $outcome.Outcome | Should -BeIn @('Refused', 'Unreachable') -Because $outcome.Detail
        }

        It 'classifies a listening loopback port as connected' {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()

            try {
                $outcome = Test-TcpEndpoint -Address '127.0.0.1' -Port $listener.LocalEndpoint.Port -TimeoutMilliseconds 2000
            } finally {
                $listener.Stop()
            }

            $outcome.Outcome | Should -Be 'Connected' -Because $outcome.Detail
        }
    }
}

Describe 'Containment verifier credential absence' -Tag 'Unit' {
    Context 'the environment of the verifier' {
        It 'fails a credential variable that is set, without printing its value' {
            $saved = Clear-MeasuredEnvironment

            try {
                Set-CleanGitMock
                [Environment]::SetEnvironmentVariable('GH_TOKEN', 'ghp-looks-like-a-token-0123456789')

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'GH_TOKEN'
            $result.evidence | Should -Not -Match 'ghp-looks-like-a-token'
        }

        It 'fails the steering variable <_>, without printing its value' -ForEach @(
            'GIT_CONFIG_GLOBAL'
            'GIT_CONFIG_SYSTEM'
            'GIT_CONFIG_COUNT'
            'GIT_CONFIG_PARAMETERS'
            'GIT_ASKPASS'
            'GIT_SSH_COMMAND'
            'GIT_SSH'
            'SSH_ASKPASS'
            'XDG_CONFIG_HOME'
        ) {
            $saved = Clear-MeasuredEnvironment

            try {
                Set-CleanGitMock
                [Environment]::SetEnvironmentVariable($_, 'steered-to-something-else')

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match $_
            $result.evidence | Should -Not -Match 'steered-to-something-else'
        }

        <#
            Both cases mock the protection probe to "closed" so that the check
            reaches the git child. Without that mock Test-PathProtection runs for
            real, is not loaded with the helpers it needs, and throws, so the
            check stops before git and the case proves nothing about git at all.
        #>
        It 'reports both the steering variable and the helper git found, each without its value' {
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection }
            Mock -CommandName 'Resolve-GitExecutable' -MockWith { 'C:\pinned\git.exe' }
            Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
            } -ParameterFilter { $Argument -contains '--list' }
            Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                @{
                    ExitCode = 0
                    Output = @("file:C:/profile/.gitconfig`tcredential.https://planted-marmalade.invalid.helper !f() { printf marmalade-lighthouse-42; }")
                    TimedOut = $false
                    Failure = ''
                }
            } -ParameterFilter { $Argument -contains '--get-regexp' }

            $configurationPath = New-GitConfigurationFile -CaseName 'steered' -Text "[user]`n`tname = nobody`n"
            $saved = Clear-MeasuredEnvironment

            try {
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $configurationPath)

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'GIT_CONFIG_GLOBAL'
            $result.evidence | Should -Match 'credential\.https://planted-marmalade\.invalid\.helper'
            $result.evidence | Should -Match 'C:/profile/\.gitconfig'
            $result.evidence | Should -Not -Match ([regex]::Escape($configurationPath))
            $result.evidence | Should -Not -Match 'marmalade-lighthouse-42'
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 1 -Exactly -ParameterFilter {
                $Argument -contains '--get-regexp'
            }
        }

        <#
            The scrub, end to end through a real git child: the caller plants a
            credential helper and points GIT_CONFIG_GLOBAL at it, and the child
            must never see it. Key and value are both distinctive and both in the
            fixture above, so either one reaching the evidence fails the case.
            Pester cannot count calls to a command it does not mock, so that the
            child ran at all is asserted one step earlier, on the protection gate
            that stands immediately in front of it and is mocked open here.
        #>
        It 'does not read a credential helper out of a configuration the caller planted, and prints nothing from it' -Skip:(-not $script:hasGit) {
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection }
            $configurationPath = New-GitConfigurationFile -CaseName 'planted' -Text @"
[credential "https://planted-marmalade.invalid"]
	helper = !f() { printf marmalade-lighthouse-42; }
"@
            $saved = Clear-MeasuredEnvironment

            try {
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $configurationPath)

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'GIT_CONFIG_GLOBAL'
            $result.evidence | Should -Not -Match 'planted-marmalade\.invalid'
            $result.evidence | Should -Not -Match 'marmalade-lighthouse-42'
            $result.evidence | Should -Not -Match ([regex]::Escape($configurationPath))
            Should -Invoke -CommandName 'Test-PathProtection' -Times 1 -Exactly -ParameterFilter {
                $Path -eq (Resolve-GitExecutable)
            }
        }
    }

    Context 'resolving git' {
        It 'reports git as unmeasured when it cannot be resolved, never as clean' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Resolve-GitExecutable' -MockWith { '' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith { throw 'git must not be started' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'could not be resolved to an absolute application path'
            $result.evidence | Should -Not -Match 'not installed'
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 0 -Exactly
        }

        It 'does not resolve git from a PATH that does not contain it' {
            $savedPath = [Environment]::GetEnvironmentVariable('PATH')

            try {
                [Environment]::SetEnvironmentVariable('PATH', '')

                $resolved = Resolve-GitExecutable
            } finally {
                [Environment]::SetEnvironmentVariable('PATH', $savedPath)
            }

            $resolved | Should -BeNullOrEmpty
        }

        <#
            Windows only: the fixture is a git.cmd, and only PATHEXT makes a
            bare "git" resolve to it. A POSIX shell would never find it, so the
            case would fail there for a reason that has nothing to do with the
            resolver.
        #>
        It 'resolves git to the absolute path of the application PATH names' -Skip:(-not $script:onWindows) {
            $applicationRoot = Join-Path $TestDrive 'pinned-git'
            $null = New-Item -Path $applicationRoot -ItemType Directory -Force
            $applicationPath = Join-Path $applicationRoot 'git.cmd'
            [System.IO.File]::WriteAllText($applicationPath, "@echo off`r`nexit /b 1`r`n")

            $savedPath = [Environment]::GetEnvironmentVariable('PATH')

            try {
                [Environment]::SetEnvironmentVariable('PATH', $applicationRoot)

                $resolved = Resolve-GitExecutable
            } finally {
                [Environment]::SetEnvironmentVariable('PATH', $savedPath)
            }

            $resolved | Should -Be $applicationPath
            [System.IO.Path]::IsPathRooted($resolved) | Should -BeTrue
        }

        It 'resolves the git of this machine to a file that exists' -Skip:(-not $script:hasGit) {
            $resolved = Resolve-GitExecutable

            $resolved | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
        }
    }

    Context 'when the controls git executes as were not verified' {
        # Review pass 2, S-07: git runs as the verifying identity. That is the identity of the role only if
        # IdentityBinding passed; otherwise a git the role can replace and the verifier cannot would run
        # before the report said so, the same reasoning as the hook probe.
        It 'does not resolve, measure or run git, and says why' {
            Mock -CommandName 'Resolve-GitExecutable' -MockWith { throw 'git must not be resolved' }
            Mock -CommandName 'Test-PathProtection' -MockWith { throw 'git must not be measured' }
            Mock -CommandName 'Invoke-GitConfigProcess' -MockWith { throw 'git must not be started' }
            $saved = Clear-MeasuredEnvironment

            try {
                $result = Test-CredentialAbsence -GitGateReason 'IdentityBinding passed'
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'git was not run'
            $result.evidence | Should -Match 'IdentityBinding passed'
            Should -Invoke -CommandName 'Resolve-GitExecutable' -Times 0 -Exactly
            Should -Invoke -CommandName 'Test-PathProtection' -Times 0 -Exactly
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 0 -Exactly
        }

        It 'still fails a credential variable that is set, and names git as not run' {
            Mock -CommandName 'Resolve-GitExecutable' -MockWith { throw 'git must not be resolved' }
            Mock -CommandName 'Invoke-GitConfigProcess' -MockWith { throw 'git must not be started' }
            $saved = Clear-MeasuredEnvironment

            try {
                [Environment]::SetEnvironmentVariable('GH_TOKEN', 'ghp-looks-like-a-token-0123456789')

                $result = Test-CredentialAbsence -GitGateReason 'IdentityBinding passed'
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'GH_TOKEN'
            $result.evidence | Should -Match 'git was not run'
            $result.evidence | Should -Not -Match 'ghp-looks-like-a-token'
        }
    }

    Context 'the git binary the check runs' {
        BeforeEach {
            Mock -CommandName 'Resolve-GitExecutable' -MockWith { 'C:\pinned\git.exe' }
            Mock -CommandName 'Invoke-GitConfigProcess' -MockWith { throw 'git must not be started' }
        }

        It 'does not run a git that this identity can replace, and fails naming how' {
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection -Violation @('C:\pinned\git.exe: this identity holds DELETE on the file C:\pinned\git.exe') }
            $saved = Clear-MeasuredEnvironment

            try {
                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape('C:\pinned\git.exe'))
            $result.evidence | Should -Match 'DELETE'
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 0 -Exactly
        }

        It 'does not run a git whose protection could not be measured, and reports it as unmeasured' {
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection -Unmeasured @('C:\pinned\git.exe could not be measured') }
            $saved = Clear-MeasuredEnvironment

            try {
                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 0 -Exactly
        }

        It 'reports a protection test that throws as unmeasured, never as clean' {
            Mock -CommandName 'Test-PathProtection' -MockWith { throw 'the probe broke' }
            $saved = Clear-MeasuredEnvironment

            try {
                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'the probe broke'
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 0 -Exactly
        }

        It 'measures the git it resolved, against the writable roots it was given' {
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection -Violation @('breach') }
            $saved = Clear-MeasuredEnvironment

            try {
                $null = Test-CredentialAbsence -WritableRoot @('C:\work')
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            Should -Invoke -CommandName 'Test-PathProtection' -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'C:\pinned\git.exe' -and $WritableRoot -contains 'C:\work'
            }
        }

        It 'still reports a credential variable when git is replaceable' {
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection -Violation @('breach') }
            $saved = Clear-MeasuredEnvironment

            try {
                [Environment]::SetEnvironmentVariable('GH_TOKEN', 'hunter2-not-a-real-secret')
                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'GH_TOKEN'
            $result.evidence | Should -Match 'breach'
            $result.evidence | Should -Not -Match 'hunter2-not-a-real-secret'
        }

        It 'runs a git that is closed to this identity' {
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection }
            Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
            } -ParameterFilter { $Argument -contains '--list' }
            Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                @{ ExitCode = 1; Output = @(); TimedOut = $false; Failure = '' }
            } -ParameterFilter { $Argument -contains '--get-regexp' }
            $saved = Clear-MeasuredEnvironment

            try {
                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Pass' -Because $result.evidence
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 2 -Exactly
        }
    }

    Context 'the git child process' {
        BeforeEach {
            Mock -CommandName 'Resolve-GitExecutable' -MockWith { 'C:\pinned\git.exe' }
            Mock -CommandName 'Test-PathProtection' -MockWith { New-GitProtection }
        }

        It 'reports a git child that was killed on its timeout as unmeasured' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = $null; Output = @(); TimedOut = $true; Failure = 'git did not finish within 10000 ms' }
                }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
        }

        It 'reports a git that could not be started as unmeasured' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = $null; Output = @(); TimedOut = $false; Failure = 'git could not be started: access is denied' }
                }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'could not be started'
        }

        It 'reports a configuration listing that printed nothing as unmeasured' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @(); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 1; Output = @(); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
        }

        It 'reports a configuration listing that exited non-zero as unmeasured' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 128; Output = @(); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 1; Output = @(); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match '128'
        }

        It 'reports an unreadable git configuration as unmeasured, not as clean' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 128; Output = @(); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match '128'
        }

        It 'reports a credential query that exited zero without a key as unmeasured' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @(); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
        }

        It 'finds a credential helper scoped to one URL and names its key and origin' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{
                        ExitCode = 0
                        Output = @("file:C:/profile/.gitconfig`tcredential.https://example.invalid.helper store")
                        TimedOut = $false
                        Failure = ''
                    }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'credential\.https://example\.invalid\.helper'
            $result.evidence | Should -Match 'C:/profile/\.gitconfig'
        }

        It 'never prints the value of a credential helper into the evidence' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{
                        ExitCode = 0
                        Output = @("file:C:/profile/.gitconfig`tcredential.helper !f() { printf marmalade-lighthouse-42; }")
                        TimedOut = $false
                        Failure = ''
                    }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'credential\.helper'
            $result.evidence | Should -Match 'C:/profile/\.gitconfig'
            $result.evidence | Should -Not -Match 'marmalade-lighthouse-42'
            $result.evidence | Should -Not -Match ([regex]::Escape('!f()'))
        }

        It 'never prints a line that carries no origin, so a multi-line value cannot leak' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{
                        ExitCode = 0
                        Output = @(
                            "file:C:/profile/.gitconfig`tcredential.helper !f() {"
                            'printf marmalade-lighthouse-42'
                            '}'
                        )
                        TimedOut = $false
                        Failure = ''
                    }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'credential\.helper'
            $result.evidence | Should -Not -Match 'marmalade-lighthouse-42'
            $result.evidence | Should -Not -Match 'printf'
        }

        It 'reports a credential query whose lines carry no origin as unmeasured' {
            $saved = Clear-MeasuredEnvironment

            try {
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @("file:C:/profile/.gitconfig`tuser.name nobody"); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--list' }
                Mock -CommandName 'Invoke-GitConfigProcess' -MockWith {
                    @{ ExitCode = 0; Output = @('printf marmalade-lighthouse-42'); TimedOut = $false; Failure = '' }
                } -ParameterFilter { $Argument -contains '--get-regexp' }

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'no line carrying an origin and a key'
            $result.evidence | Should -Not -Match 'marmalade-lighthouse-42'
        }

        It 'names exactly what it measured when it finds no credential material' {
            $saved = Clear-MeasuredEnvironment

            try {
                Set-CleanGitMock

                $result = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Match 'GH_TOKEN'
            $result.evidence | Should -Match 'GIT_CONFIG_GLOBAL'
            $result.evidence | Should -Match ([regex]::Escape('C:\pinned\git.exe'))
            $result.evidence | Should -Match 'reports no credential helper'
            $result.evidence | Should -Not -Match 'not installed'
        }

        It 'queries the URL-scoped credential keys through the sentinel first' {
            $saved = Clear-MeasuredEnvironment

            try {
                Set-CleanGitMock

                $null = Test-CredentialAbsence
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 1 -Exactly -ParameterFilter {
                $Argument -contains '--list' -and $Argument -contains '--show-origin'
            }
            Should -Invoke -CommandName 'Invoke-GitConfigProcess' -Times 1 -Exactly -ParameterFilter {
                $Argument -contains '--get-regexp' -and $Argument -contains '^credential\..*helper$'
            }
        }
    }

    Context 'the environment handed to the git child' {
        It 'removes every GIT_ variable from the child environment' {
            $saved = Clear-MeasuredEnvironment

            try {
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', 'C:\steered\gitconfig')
                [Environment]::SetEnvironmentVariable('GIT_SSH_COMMAND', 'ssh -i C:\steered\key')
                [Environment]::SetEnvironmentVariable('SSH_ASKPASS', 'C:\steered\askpass.exe')

                $childEnvironment = Get-ScrubbedGitEnvironment
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            @($childEnvironment.Keys | Where-Object { $_ -like 'GIT_*' }) | Should -BeNullOrEmpty
            $childEnvironment.ContainsKey('SSH_ASKPASS') | Should -BeFalse
        }

        It 'pins HOME and USERPROFILE to the user profile folder of the operating system' {
            $saved = Clear-MeasuredEnvironment

            try {
                $childEnvironment = Get-ScrubbedGitEnvironment
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $expected = [Environment]::GetFolderPath('UserProfile')
            $childEnvironment['HOME'] | Should -Be $expected
            $childEnvironment['USERPROFILE'] | Should -Be $expected
        }

        It 'leaves the system configuration in scope by not setting GIT_CONFIG_NOSYSTEM' {
            $childEnvironment = Get-ScrubbedGitEnvironment

            $childEnvironment.ContainsKey('GIT_CONFIG_NOSYSTEM') | Should -BeFalse
        }

        It 'drops XDG_CONFIG_HOME, which git reads instead of the configuration in the home folder' {
            $saved = Clear-MeasuredEnvironment

            try {
                [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $TestDrive 'steered-xdg'))

                $childEnvironment = Get-ScrubbedGitEnvironment
            } finally {
                Restore-MeasuredEnvironment -Saved $saved
            }

            $childEnvironment.ContainsKey('XDG_CONFIG_HOME') | Should -BeFalse
        }

        It 'pins PROGRAMDATA to the operating system folder, so a caller cannot hide the machine-wide configuration' -Skip:(-not $script:onWindows) {
            $saved = [Environment]::GetEnvironmentVariable('PROGRAMDATA')

            try {
                [Environment]::SetEnvironmentVariable('PROGRAMDATA', (Join-Path $TestDrive 'steered-programdata'))

                $childEnvironment = Get-ScrubbedGitEnvironment
            } finally {
                [Environment]::SetEnvironmentVariable('PROGRAMDATA', $saved)
            }

            $childEnvironment['PROGRAMDATA'] | Should -Be ([Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData))
        }

        It 'still carries the rest of the caller environment into the child' {
            $savedMarker = [Environment]::GetEnvironmentVariable('CONTAINMENT_TEST_MARKER')

            try {
                [Environment]::SetEnvironmentVariable('CONTAINMENT_TEST_MARKER', 'kept')

                $childEnvironment = Get-ScrubbedGitEnvironment
            } finally {
                [Environment]::SetEnvironmentVariable('CONTAINMENT_TEST_MARKER', $savedMarker)
            }

            $childEnvironment['CONTAINMENT_TEST_MARKER'] | Should -Be 'kept'
        }

        It 'runs git with an environment a planted GIT_CONFIG_GLOBAL cannot steer' -Skip:(-not $script:hasGit) {
            $configurationPath = New-GitConfigurationFile -CaseName 'scrubbed' -Text @"
[credential "https://scrubbed.invalid"]
	helper = store
"@
            $savedGlobal = [Environment]::GetEnvironmentVariable('GIT_CONFIG_GLOBAL')

            try {
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $configurationPath)

                $outcome = Invoke-GitConfigProcess -GitPath (Resolve-GitExecutable) -Argument @(
                    'config', '--show-origin', '--get-regexp', '^credential\..*helper$'
                )
            } finally {
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $savedGlobal)
            }

            $outcome.TimedOut | Should -BeFalse
            $outcome.ExitCode | Should -BeIn @(0, 1)
            ($outcome.Output -join "`n") | Should -Not -Match 'scrubbed\.invalid'
        }

        It 'reports the exit code of a real git child' -Skip:(-not $script:hasGit) {
            $outcome = Invoke-GitConfigProcess -GitPath (Resolve-GitExecutable) -Argument @('config', '--list', '--show-origin')

            $outcome.TimedOut | Should -BeFalse
            $outcome.Failure | Should -BeNullOrEmpty
            $outcome.ExitCode | Should -Not -BeNullOrEmpty
        }
    }
}
