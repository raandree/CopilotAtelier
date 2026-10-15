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
            'Get-IdentitySid'
            'Get-CallerIdentity'
            'Test-IdentityBinding'
        ))
}

Describe 'Containment identity resolution' -Tag 'Unit' {
    It 'resolves a well-known account name to its security identifier' -Skip:(-not $script:onWindows) {
        Get-IdentitySid -Identity 'NT AUTHORITY\SYSTEM' | Should -Be 'S-1-5-18'
    }

    It 'returns a security identifier unchanged' -Skip:(-not $script:onWindows) {
        Get-IdentitySid -Identity 'S-1-5-19' | Should -Be 'S-1-5-19'
    }

    It 'returns nothing for <Reason>' -ForEach @(
        @{ Reason = 'an account that does not exist'; Identity = 'CONTAINMENT\no-such-account-for-the-test' }
        @{ Reason = 'an empty name'; Identity = '' }
        @{ Reason = 'text that is not an account'; Identity = 'not\an\account\at\all' }
    ) -Skip:(-not $script:onWindows) {
        Get-IdentitySid -Identity $Identity | Should -BeNullOrEmpty
    }

    It 'names the identity that runs the verifier' -Skip:(-not $script:onWindows) {
        $caller = Get-CallerIdentity

        $caller.Name | Should -Be ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
        $caller.Sid | Should -Be ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    }
}

Describe 'Containment identity binding' -Tag 'Unit' {
    BeforeEach {
        $script:OnWindows = $true
        $script:controllerSid = 'S-1-5-21-1-2-3-1001'
        $script:workerSid = 'S-1-5-21-1-2-3-1002'

        Mock -CommandName 'Get-CallerIdentity' -MockWith { [pscustomobject]@{ Name = 'LAB\runner'; Sid = $script:controllerSid } }
        Mock -CommandName 'Get-IdentitySid' -MockWith {
            switch ($Identity) {
                'LAB\controller' { $script:controllerSid }
                'LAB\worker' { $script:workerSid }
                'LAB\twin' { $script:controllerSid }
                default { $null }
            }
        }
    }

    It 'passes the controller role when the verifier runs as the declared controller identity' {
        $result = Test-IdentityBinding -Role 'Controller' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\worker'

        $result.name | Should -Be 'IdentityBinding'
        $result.status | Should -Be 'Pass' -Because $result.evidence
        $result.evidence | Should -Match ([regex]::Escape($script:controllerSid))
    }

    It 'fails the worker role when the verifier runs as the controller identity' {
        # Review of 2026-10-12, C-01: -Role Worker from any account read Pass.
        $result = Test-IdentityBinding -Role 'Worker' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\worker'

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match ([regex]::Escape($script:workerSid))
        $result.evidence | Should -Match ([regex]::Escape($script:controllerSid))
    }

    It 'fails when the verifier runs as an identity that neither role declares' {
        Mock -CommandName 'Get-CallerIdentity' -MockWith { [pscustomobject]@{ Name = 'LAB\someone'; Sid = 'S-1-5-21-1-2-3-4000' } }

        (Test-IdentityBinding -Role 'Controller' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\worker').status | Should -Be 'Fail'
        (Test-IdentityBinding -Role 'Worker' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\worker').status | Should -Be 'Fail'
    }

    It 'fails when the controller and the worker declare the same identity' {
        $result = Test-IdentityBinding -Role 'Controller' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\twin'

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'same identity'
    }

    It 'reports a declared identity it cannot resolve as unavailable, not as a match' {
        $result = Test-IdentityBinding -Role 'Controller' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\ghost'

        $result.status | Should -Be 'Unavailable'
        $result.evidence | Should -Match 'LAB\\ghost'
    }

    It 'reports an unresolvable controller identity as unavailable' {
        $result = Test-IdentityBinding -Role 'Controller' -ControllerIdentity 'LAB\ghost' -WorkerIdentity 'LAB\worker'

        $result.status | Should -Be 'Unavailable'
    }

    It 'reports an identity it cannot read for the caller as unavailable' {
        Mock -CommandName 'Get-CallerIdentity' -MockWith { $null }

        (Test-IdentityBinding -Role 'Controller' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\worker').status | Should -Be 'Unavailable'
    }

    It 'is unavailable on a platform whose identities it does not measure' {
        $script:OnWindows = $false

        $result = Test-IdentityBinding -Role 'Controller' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\worker'

        $result.status | Should -Be 'Unavailable'
        $result.evidence | Should -Match 'Windows'
    }

    It 'never lets the role it measures change which account runs the verifier' {
        # The verifier reads who it is; it never takes that from the profile.
        Should -Invoke -CommandName 'Get-CallerIdentity' -Times 0 -Exactly
        $null = Test-IdentityBinding -Role 'Worker' -ControllerIdentity 'LAB\controller' -WorkerIdentity 'LAB\worker'
        Should -Invoke -CommandName 'Get-CallerIdentity' -Times 1 -Exactly
    }
}
