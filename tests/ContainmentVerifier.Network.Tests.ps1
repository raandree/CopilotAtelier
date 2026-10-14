# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'

    . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'New-CheckResult'
            'Test-EgressPolicy'
            'Test-RemoteUnreachable'
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
