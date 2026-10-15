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
            'Test-PathInside'
            'Test-PathOverlap'
            'Get-ObjectRight'
            'Test-PathProtection'
            'Test-ControlImmutability'
            'Test-WritableRoot'
            'Test-LedgerProtection'
        ))

    # What Get-ObjectRight reports for one object: every right Denied except the ones named.
    function script:New-ObjectRight {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter()]
            [string]$State = 'Measured',

            [Parameter()]
            [bool]$IsDirectory = $true,

            [Parameter()]
            [string[]]$Granted = @(),

            [Parameter()]
            [string[]]$Unknown = @()
        )

        $right = @{}
        foreach ($name in $script:RightName) {
            $right[$name] = if ($name -in $Granted) { 'Granted' } elseif ($name -in $Unknown) { 'Unknown' } else { 'Denied' }
        }

        return [pscustomobject]@{
            Path = $Path
            State = $State
            IsDirectory = $IsDirectory
            IsReparsePoint = $false
            ReadOnly = $false
            Right = $right
            Reason = ''
        }
    }

    # Every path is Absent unless a case says otherwise.
    function script:Set-ObjectRight {
        param(
            [Parameter(Mandatory)]
            [hashtable]$Map
        )

        $script:rightMap = $Map
        Mock -CommandName Get-ObjectRight -MockWith {
            if ($script:rightMap.ContainsKey($Path)) { return $script:rightMap[$Path] }

            return New-ObjectRight -Path $Path -State 'Absent'
        }
    }
}

Describe 'Containment path inside' -Tag 'Unit' {
    BeforeAll {
        $script:base = Join-Path $TestDrive 'inside'
    }

    It 'is true for the root itself' {
        Test-PathInside -Path $script:base -Root @($script:base) | Should -BeTrue
    }

    It 'is true for a path below the root' {
        Test-PathInside -Path (Join-Path $script:base 'a/b') -Root @($script:base) | Should -BeTrue
    }

    It 'is false for a path that merely shares the root as a prefix' {
        Test-PathInside -Path ($script:base + '-other') -Root @($script:base) | Should -BeFalse
    }

    It 'is false for a path that contains the root, unlike an overlap' {
        $child = Join-Path $script:base 'child'

        Test-PathInside -Path $script:base -Root @($child) | Should -BeFalse
        Test-PathOverlap -Path $script:base -WritableRoot @($child) | Should -BeTrue
    }

    It 'is false when there is no root' {
        Test-PathInside -Path $script:base -Root @() | Should -BeFalse
    }
}

Describe 'Containment writable roots' -Tag 'Unit' {
    BeforeAll {
        $script:work = Join-Path $TestDrive 'writable/work'
        $script:temp = Join-Path $TestDrive 'writable/temp'
        $script:wide = Join-Path $TestDrive 'writable/wide'
    }

    Context 'the declared roots' {
        It 'passes when every declared root takes new files and folders and the escape set is closed' {
            Set-ObjectRight -Map @{
                $script:work = (New-ObjectRight -Path $script:work -Granted @('WriteData', 'AppendData'))
                $script:temp = (New-ObjectRight -Path $script:temp)
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.name | Should -Be 'WritableRoots'
        }

        It 'fails a profile that declares no writable root' {
            Set-ObjectRight -Map @{}

            $result = Test-WritableRoot -Declared @() -EscapeSet @($script:temp)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'no writable root'
        }

        It 'fails a declared root that does not exist' {
            Set-ObjectRight -Map @{}

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @()

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'does not exist'
            $result.evidence | Should -Match ([regex]::Escape($script:work))
        }

        It 'fails a declared root that is a file' {
            Set-ObjectRight -Map @{ $script:work = (New-ObjectRight -Path $script:work -IsDirectory $false -Granted @('WriteData', 'AppendData')) }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @()

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'not a directory'
        }

        It 'fails a declared root this identity cannot <Right>' -ForEach @(
            @{ Right = 'create a file in'; Granted = @('AppendData') }
            @{ Right = 'create a folder in'; Granted = @('WriteData') }
        ) {
            Set-ObjectRight -Map @{ $script:work = (New-ObjectRight -Path $script:work -Granted $Granted) }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @()

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'not writable'
        }

        It 'reports a declared root it could not measure as unmeasured' {
            Set-ObjectRight -Map @{ $script:work = (New-ObjectRight -Path $script:work -Granted @('WriteData') -Unknown @('AppendData')) }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @()

            $result.status | Should -Be 'Unavailable'
        }
    }

    Context 'the escape set' {
        BeforeEach {
            $script:workRight = New-ObjectRight -Path $script:work -Granted @('WriteData', 'AppendData')
        }

        It 'fails an escape path where this identity can <Right>' -ForEach @(
            @{ Right = 'create a file'; Granted = @('WriteData') }
            @{ Right = 'create a folder'; Granted = @('AppendData') }
            @{ Right = 'delete children'; Granted = @('DeleteChild') }
        ) {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:temp = (New-ObjectRight -Path $script:temp -Granted $Granted)
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'writable outside the declared roots'
            $result.evidence | Should -Match ([regex]::Escape($script:temp))
        }

        It 'does not count an escape path that a declared root covers' {
            Set-ObjectRight -Map @{ $script:temp = (New-ObjectRight -Path $script:temp -Granted @('WriteData', 'AppendData', 'DeleteChild')) }

            $result = Test-WritableRoot -Declared @($script:temp) -EscapeSet @($script:temp, (Join-Path $script:temp 'below'))

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'counts an escape path that contains a declared root, because it is wider than the declaration' {
            $inner = Join-Path $script:wide 'work'
            Set-ObjectRight -Map @{
                $inner = (New-ObjectRight -Path $inner -Granted @('WriteData', 'AppendData'))
                $script:wide = (New-ObjectRight -Path $script:wide -Granted @('WriteData', 'AppendData'))
            }

            $result = Test-WritableRoot -Declared @($inner) -EscapeSet @($script:wide)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match ([regex]::Escape($script:wide))
        }

        It 'treats an escape path that does not exist as closed' {
            Set-ObjectRight -Map @{ $script:work = $script:workRight }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).status | Should -Be 'Pass'
        }

        It 'reports an escape path it could not measure as unmeasured' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:temp = (New-ObjectRight -Path $script:temp -Unknown @('WriteData'))
            }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).status | Should -Be 'Unavailable'
        }

        It 'prefers a measured breach to an unmeasured path' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:temp = (New-ObjectRight -Path $script:temp -Granted @('WriteData'))
                $script:wide = (New-ObjectRight -Path $script:wide -Unknown @('WriteData'))
            }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp, $script:wide)).status | Should -Be 'Fail'
        }

        It 'says in its evidence that the rest of the filesystem was not enumerated' {
            Set-ObjectRight -Map @{ $script:work = $script:workRight }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).evidence | Should -Match 'not enumerated'
        }

        It 'names the escape set it measured' {
            Set-ObjectRight -Map @{ $script:work = $script:workRight }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).evidence | Should -Match ([regex]::Escape($script:temp))
        }

        It 'creates no probe file anywhere' {
            $root = Join-Path $TestDrive 'real-root'
            $null = New-Item -Path $root -ItemType Directory -Force
            Set-ObjectRight -Map @{ $root = (New-ObjectRight -Path $root -Granted @('WriteData', 'AppendData')) }

            $null = Test-WritableRoot -Declared @($root) -EscapeSet @()

            @(Get-ChildItem -LiteralPath $root -Force) | Should -HaveCount 0
        }
    }
}

Describe 'Containment ledger protection' -Tag 'Unit' {
    BeforeAll {
        $script:sink = Join-Path $TestDrive 'ledger/run.jsonl'
        $script:head = Join-Path $TestDrive 'ledger/run.head.json'

        function script:New-Protection {
            param(
                [Parameter(Mandatory)]
                [string]$Path,

                [Parameter()]
                [string[]]$Violation = @(),

                [Parameter()]
                [string[]]$Unmeasured = @(),

                [Parameter()]
                [bool]$Absent = $false
            )

            return [pscustomobject]@{ Path = $Path; Closed = ($Violation.Count -eq 0 -and $Unmeasured.Count -eq 0); Absent = $Absent; Violation = $Violation; Unmeasured = $Unmeasured }
        }
    }

    It 'passes when neither the sink nor the chain head can be replaced or loosened' {
        Mock -CommandName Test-PathProtection -MockWith { New-Protection -Path $Path }

        $result = Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head

        $result.status | Should -Be 'Pass' -Because $result.evidence
        $result.name | Should -Be 'LedgerProtection'
    }

    It 'judges both files by the same protection test as the controls' {
        Mock -CommandName Test-PathProtection -MockWith { New-Protection -Path $Path }

        $null = Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head

        Should -Invoke Test-PathProtection -Times 1 -Exactly -ParameterFilter { $Path -eq $script:sink }
        Should -Invoke Test-PathProtection -Times 1 -Exactly -ParameterFilter { $Path -eq $script:head }
    }

    It 'fails a sink this identity can replace, and names how' {
        Mock -CommandName Test-PathProtection -MockWith {
            if ($Path -eq $script:sink) { New-Protection -Path $Path -Violation @("${Path}: this identity holds DELETE on the file $Path") } else { New-Protection -Path $Path }
        }

        $result = Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'DELETE'
    }

    It 'fails a chain head this identity can replace' {
        Mock -CommandName Test-PathProtection -MockWith {
            if ($Path -eq $script:head) { New-Protection -Path $Path -Violation @("${Path}: overlaps the writable root x") } else { New-Protection -Path $Path }
        }

        (Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head).status | Should -Be 'Fail'
    }

    It 'reports an unmeasured ledger as unmeasured, not as protected' {
        Mock -CommandName Test-PathProtection -MockWith {
            if ($Path -eq $script:sink) { New-Protection -Path $Path -Unmeasured @("${Path}: could not be measured") } else { New-Protection -Path $Path }
        }

        (Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head).status | Should -Be 'Unavailable'
    }

    It 'prefers a measured breach to an unmeasured file' {
        Mock -CommandName Test-PathProtection -MockWith {
            if ($Path -eq $script:sink) { New-Protection -Path $Path -Unmeasured @('x') } else { New-Protection -Path $Path -Violation @('y') }
        }

        (Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head).status | Should -Be 'Fail'
    }

    It 'accepts a ledger that does not exist yet when nothing on the way lets this identity create it' {
        Mock -CommandName Test-PathProtection -MockWith { New-Protection -Path $Path -Absent $true }

        (Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head).status | Should -Be 'Pass'
    }

    It 'gives the writable roots to the protection test, so a ledger inside one fails' {
        Mock -CommandName Test-PathProtection -MockWith { New-Protection -Path $Path }
        $root = Join-Path $TestDrive 'work'

        $null = Test-LedgerProtection -SinkPath $script:sink -ChainHeadPath $script:head -WritableRoot @($root)

        Should -Invoke Test-PathProtection -Times 2 -Exactly -ParameterFilter { $WritableRoot -contains $root }
    }
}

Describe 'Containment control immutability of live artifacts' -Tag 'Unit' {
    BeforeAll {
        $script:controls = Join-Path $TestDrive 'immutable'

        function script:New-ControlProfile {
            $entry = { param($name) [pscustomobject]@{ path = (Join-Path $script:controls $name); sha256 = ('a' * 64) } }

            return [pscustomobject]@{
                verifier = & $entry 'verifier.ps1'
                hooksConfig = & $entry 'hooks.json'
                hookScript = & $entry 'hook.ps1'
                ledgerAppender = & $entry 'appender.ps1'
                liveProfile = & $entry 'live-profile.json'
                liveRunner = & $entry 'live-runner.exe'
                liveCommandTemplates = & $entry 'templates.json'
                immutableControlPaths = @()
            }
        }

        function script:New-ClosedProtection {
            param(
                [Parameter(Mandatory)]
                [string]$Path
            )

            return [pscustomobject]@{ Path = $Path; Closed = $true; Absent = $false; Violation = @(); Unmeasured = @() }
        }
    }

    It 'measures every live artifact the profile pins, not only the four controls' {
        Mock -CommandName Test-PathProtection -MockWith { New-ClosedProtection -Path $Path }

        $null = Test-ControlImmutability -ProfilePath (Join-Path $script:controls 'profile.json') -ContainmentProfile (New-ControlProfile) -WritableRoot @()

        foreach ($name in @('live-profile.json', 'live-runner.exe', 'templates.json', 'verifier.ps1', 'hooks.json', 'hook.ps1', 'appender.ps1', 'profile.json')) {
            Should -Invoke Test-PathProtection -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $script:controls $name) } -Because "$name must be measured"
        }
    }

    It 'fails a live runner this identity can write' {
        Mock -CommandName Test-PathProtection -MockWith {
            if ($Path -like '*live-runner.exe') {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $false; Violation = @("${Path}: this identity holds FILE_WRITE_DATA on the file $Path"); Unmeasured = @() }
            } else {
                New-ClosedProtection -Path $Path
            }
        }

        $result = Test-ControlImmutability -ProfilePath (Join-Path $script:controls 'profile.json') -ContainmentProfile (New-ControlProfile) -WritableRoot @()

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match 'live-runner.exe'
    }

    It 'passes when every control and live artifact is closed' {
        Mock -CommandName Test-PathProtection -MockWith { New-ClosedProtection -Path $Path }

        (Test-ControlImmutability -ProfilePath (Join-Path $script:controls 'profile.json') -ContainmentProfile (New-ControlProfile) -WritableRoot @()).status | Should -Be 'Pass'
    }
}
