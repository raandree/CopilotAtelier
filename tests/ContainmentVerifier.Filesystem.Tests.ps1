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
            'Get-PathChain'
            'Test-PathProtection'
            'Test-ControlImmutability'
            'Format-RelayedText'
            'Get-SearchPathProblem'
            'Get-ReplacementRight'
            'Measure-EscapePath'
            'Test-WritableRoot'
            'Test-LedgerProtection'
        ))

    # Runs a script block as the verifier runs on the platform named, through the flag its functions read, so that
    # both branches are tested on every system. The rights are mocked, so no platform call is made.
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
            [string[]]$Unknown = @(),

            [Parameter()]
            [string]$Reason = ''
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
            Reason = $Reason
        }
    }

    # The folder above a path, spelled as Get-PathChain spells it.
    function script:Get-ParentPath {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        return [System.IO.Path]::GetDirectoryName([System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($Path)))
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
            # The folder above the temp folder of these cases, where a temp folder that does not exist would be created.
            $script:aboveTemp = Get-ParentPath -Path $script:temp
            $script:closedAboveTemp = New-ObjectRight -Path $script:aboveTemp
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

        It 'treats an escape path that does not exist as closed when this identity cannot add a folder to the nearest folder above it' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = $script:closedAboveTemp
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Match 'absent'
        }

        # Brief 12, Q3: a place that does not exist is created in the nearest folder above it that does, so that folder decides.
        It 'fails an escape path that does not exist when this identity can add a folder to the nearest folder above it' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -Granted @('AppendData'))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'writable outside the declared roots'
            $result.evidence | Should -Match ([regex]::Escape($script:temp))
            $result.evidence | Should -Match ([regex]::Escape($script:aboveTemp))
        }

        It 'walks up past every folder that does not exist to the nearest one that does' {
            $deep = [System.IO.Path]::Combine($script:temp, 'one', 'two')
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -Granted @('AppendData'))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($deep)

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($script:aboveTemp))
        }

        It 'does not count the right to add a file or delete a child above an escape path that does not exist, which creates no folder' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -Granted @('WriteData', 'DeleteChild'))
            }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).status | Should -Be 'Pass'
        }

        It 'treats an escape path below a file that this identity cannot replace as closed, because a file holds no folder' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -IsDirectory $false -Granted @('WriteData', 'AppendData'))
                (Get-ParentPath -Path $script:aboveTemp) = (New-ObjectRight -Path (Get-ParentPath -Path $script:aboveTemp))
            }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).status | Should -Be 'Pass'
        }

        # Review R12-04: an identity that can delete the file can put a folder in its place.
        It 'fails an escape path below a file that this identity can delete' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -IsDirectory $false -Granted @('Delete'))
            }

            $result = Invoke-AsPlatform -Windows $true -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp) }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'DELETE'
            $result.evidence | Should -Match ([regex]::Escape($script:aboveTemp))
        }

        It 'fails an escape path below a file in a folder this identity can write, where deletion is not measured' {
            $folderOfFile = Get-ParentPath -Path $script:aboveTemp
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -IsDirectory $false -Unknown @('Delete', 'WriteDac', 'WriteOwner'))
                $folderOfFile = (New-ObjectRight -Path $folderOfFile -Granted @('WriteData') -Unknown @('Delete', 'WriteDac', 'WriteOwner'))
            }

            $result = Invoke-AsPlatform -Windows $false -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp) }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($folderOfFile))
        }

        It 'reports an escape path below a file as unmeasured when it cannot be measured whether the file can be deleted' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -IsDirectory $false -Unknown @('Delete'))
            }

            (Invoke-AsPlatform -Windows $true -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp) }).status | Should -Be 'Unavailable'
        }

        # The ruling keeps DELETE on the six places of the escape set out of the check, for a later brief.
        It 'does not count DELETE on an escape path that exists' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:temp = (New-ObjectRight -Path $script:temp -Granted @('Delete'))
            }

            (Invoke-AsPlatform -Windows $true -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp) }).status | Should -Be 'Pass'
        }

        It 'reports an escape path as unmeasured when nothing on its path exists' {
            Set-ObjectRight -Map @{ $script:work = $script:workRight }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'nothing on its path'
        }

        It 'reports an escape path as unmeasured when the nearest folder above it cannot be measured' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -State 'Unknown' -Reason 'the attributes could not be read')
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'the attributes could not be read'
        }

        It 'reports an escape path as unmeasured when the right to add a folder above it cannot be measured' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = (New-ObjectRight -Path $script:aboveTemp -Unknown @('AppendData'))
            }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).status | Should -Be 'Unavailable'
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
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = $script:closedAboveTemp
            }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet @($script:temp)).evidence | Should -Match 'not enumerated'
        }

        It 'names the escape set it measured' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:aboveTemp = $script:closedAboveTemp
            }

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

    # Brief 12: pwsh puts these places ahead of every folder a launcher names, and auto-loads modules from them into
    # every later process of this identity, the verifier included, so they are judged whether a root covers them or not.
    Context 'the places pwsh loads modules from' {
        BeforeEach {
            $script:workRight = New-ObjectRight -Path $script:work -Granted @('WriteData', 'AppendData')
            $script:modules = Join-Path $TestDrive 'account-modules'
        }

        It 'fails a module folder this identity can write, and says that pwsh loads modules from it' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:modules = (New-ObjectRight -Path $script:modules -Granted @('WriteData'))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules)

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($script:modules))
            $result.evidence | Should -Match 'auto-loads modules'
        }

        It 'fails a module folder this identity can write even when a declared root covers it, and says so' {
            $inside = Join-Path $script:work 'Modules'
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $inside = (New-ObjectRight -Path $inside -Granted @('WriteData', 'AppendData', 'DeleteChild'))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($inside)

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($inside))
            $result.evidence | Should -Match 'a declared root covers it'
        }

        It 'keeps the exemption of a covered place for the escape set while it judges the same place as a module folder' {
            $inside = Join-Path $script:work 'Modules'
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $inside = (New-ObjectRight -Path $inside -Granted @('WriteData'))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @($inside) -ModuleSet @($inside)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'writable outside the declared roots: \[\]'
        }

        It 'fails a configuration file this identity can write' {
            $file = Join-Path $script:modules 'powershell.config.json'
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $file = (New-ObjectRight -Path $file -IsDirectory $false -Granted @('WriteData'))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($file)

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'FILE_WRITE_DATA'
        }

        It 'fails a module folder that does not exist when this identity can add a folder to the nearest folder above it' {
            $above = Get-ParentPath -Path $script:modules
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $above = (New-ObjectRight -Path $above -Granted @('AppendData'))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules)

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($above))
        }

        It 'passes a module folder closed to this identity, and names it' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:modules = (New-ObjectRight -Path $script:modules)
                (Get-ParentPath -Path $script:modules) = (New-ObjectRight -Path (Get-ParentPath -Path $script:modules))
            }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules)

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($script:modules))
            $result.evidence | Should -Match 'auto-loads modules'
        }

        # Review R12-01: an identity that can delete a place can move it aside and create its own. On Windows the kernel
        # answers DELETE through FILE_DELETE_CHILD on the folder above too, whatever the place's own access list says.
        It 'fails a module place this identity can delete, because it can put its own in its place' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:modules = (New-ObjectRight -Path $script:modules -Granted @('Delete'))
            }

            $result = Invoke-AsPlatform -Windows $true -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules) }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'DELETE'
        }

        It 'reports a module place as unmeasured when DELETE on it cannot be measured' {
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:modules = (New-ObjectRight -Path $script:modules -Unknown @('Delete'))
            }

            (Invoke-AsPlatform -Windows $true -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules) }).status | Should -Be 'Unavailable'
        }

        # Off Windows DELETE is not measured, and renaming or deleting an entry takes write access to its folder.
        It 'fails a module place off Windows when this identity can write the folder above it' {
            $above = Get-ParentPath -Path $script:modules
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:modules = (New-ObjectRight -Path $script:modules -Unknown @('Delete', 'WriteDac', 'WriteOwner'))
                $above = (New-ObjectRight -Path $above -Granted @('WriteData') -Unknown @('Delete', 'WriteDac', 'WriteOwner'))
            }

            $result = Invoke-AsPlatform -Windows $false -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules) }

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($above))
        }

        It 'passes a closed module place off Windows, where DELETE is not measured, when the folder above it is closed' {
            $above = Get-ParentPath -Path $script:modules
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:modules = (New-ObjectRight -Path $script:modules -Unknown @('Delete', 'WriteDac', 'WriteOwner'))
                $above = (New-ObjectRight -Path $above -Unknown @('Delete', 'WriteDac', 'WriteOwner'))
            }

            $result = Invoke-AsPlatform -Windows $false -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules) }

            $result.status | Should -Be 'Pass' -Because 'an unmeasured DELETE must not make every run off Windows unmeasured'
        }

        It 'reports a module place off Windows as unmeasured when the folder above it cannot be measured' {
            $above = Get-ParentPath -Path $script:modules
            Set-ObjectRight -Map @{
                $script:work = $script:workRight
                $script:modules = (New-ObjectRight -Path $script:modules -Unknown @('Delete', 'WriteDac', 'WriteOwner'))
                $above = (New-ObjectRight -Path $above -State 'Unknown' -Reason 'the probe could not run')
            }

            $result = Invoke-AsPlatform -Windows $false -Action { Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($script:modules) }

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'the probe could not run'
        }

        # Review answer 3: a state the check does not name never reads as closed.
        It 'reports a place of <Set> in a state it does not know as unmeasured' -ForEach @(
            @{ Set = 'the escape set' }
            @{ Set = 'the module search set' }
        ) {
            Set-ObjectRight -Map @{ $script:work = $script:workRight }
            Mock -CommandName Measure-EscapePath -MockWith { [pscustomobject]@{ State = 'Unforeseen'; Detail = 'a state no branch names' } }
            $escape = if ($Set -eq 'the escape set') { @($script:modules) } else { @() }
            $module = if ($Set -eq 'the module search set') { @($script:modules) } else { @() }

            (Test-WritableRoot -Declared @($script:work) -EscapeSet $escape -ModuleSet $module).status | Should -Be 'Unavailable'
        }

        It 'does not open a module search entry that <Kind>, and reports it unmeasured' -ForEach @(
            @{ Kind = 'is relative'; Entry = 'relative-modules'; Reason = 'is not an absolute path' }
            if ($script:onWindows) {
                @{ Kind = 'names a network share'; Entry = '\\server\share\Modules'; Reason = 'is a network path' }
                @{ Kind = 'names a device path'; Entry = '\\?\C:\Modules'; Reason = 'is a device path' }
                @{ Kind = 'names the device namespace'; Entry = '\\.\C:\Modules'; Reason = 'is a device path' }
            } else {
                @{ Kind = 'is written as a Windows share'; Entry = '\\server\share\Modules'; Reason = 'is not an absolute path' }
            }
        ) {
            Set-ObjectRight -Map @{ $script:work = $script:workRight }

            $result = Test-WritableRoot -Declared @($script:work) -EscapeSet @() -ModuleSet @($Entry)

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape($Reason))
            $result.evidence | Should -Match 'not opened'
            Should -Invoke Get-ObjectRight -Times 1 -Exactly -Because 'only the declared root is measured'
        }
    }
}

Describe 'Containment search path entries' -Tag 'Unit' {
    It 'finds nothing wrong with a local absolute path' {
        Get-SearchPathProblem -Path (Join-Path $TestDrive 'Modules') | Should -BeNullOrEmpty
    }

    It 'calls <Entry> <Reason>' -ForEach @(
        @{ Entry = 'Modules'; Reason = 'is not an absolute path' }
        if ($script:onWindows) {
            @{ Entry = 'C:Modules'; Reason = 'is not an absolute path' }
            @{ Entry = '\Modules'; Reason = 'is not an absolute path' }
            @{ Entry = '\\server\share\Modules'; Reason = 'is a network path' }
            @{ Entry = '//server/share/Modules'; Reason = 'is a network path' }
            @{ Entry = '\\?\C:\Modules'; Reason = 'is a device path' }
            @{ Entry = '//./C:/Modules'; Reason = 'is a device path' }
            @{ Entry = '\??\C:\Modules'; Reason = 'is a device path' }
        } else {
            @{ Entry = 'relative/Modules'; Reason = 'is not an absolute path' }
            @{ Entry = '~/Modules'; Reason = 'is not an absolute path' }
        }
    ) {
        Get-SearchPathProblem -Path $Entry | Should -Be $Reason
    }
}

# Brief 12, Q4 (R11-01): a path or a reason this check did not compose reaches its evidence only relayed, as printable
# ASCII of at most 200 characters, and each list the check joins at most 1,000 (Format-RelayedText). One row for each
# place in the evidence that takes such text, and one for each joined list.
Describe 'Containment writable roots relay' -Tag 'Unit' {
    BeforeAll {
        # An escape sequence, a line break, a tag character and a zero-width space between printable letters.
        $script:hostile = 'ev' + [char]0x1B + '[31m' + "`r`n" + [char]::ConvertFromUtf32(0xE0041) + [char]0x200B + 'il'
        $script:relayed = 'ev?[31m????il'
        # Every outside text of these cases is longer than 200 characters, because a joined list is relayed too: only
        # the cut at 200 shows that the text itself was relayed before it was joined.
        $script:padding = 'z' * 300
        $script:relayBase = Join-Path $TestDrive 'relay'
        $script:relayRoot = Join-Path $script:relayBase 'root'
        $script:hostileRoot = Join-Path $script:relayBase "root-$script:hostile$script:padding"
        $script:hostilePlace = Join-Path $script:relayBase "place-$script:hostile$script:padding"
        $script:belowHostile = Join-Path (Join-Path $script:relayBase "folder-$script:hostile$script:padding") 'missing'
        $script:hostileFolder = Get-ParentPath -Path $script:belowHostile
        $script:hostileEntry = "relative-$script:hostile$script:padding"
        # The reasons Get-ObjectRight gives where it takes the text of an exception (lines 616 and 643 when R11-01 counted
        # them): a failed read of the attributes, and a native probe that could not be defined.
        $script:attributeReason = "Access to the path '$script:hostile$script:padding' is denied."
        $script:probeReason = "the native access probe could not be defined, so no right was measured: $script:hostile$script:padding"

        # The text as the relay writes it: one question mark for each character outside printable ASCII.
        function script:Get-RelayedForm {
            param(
                [Parameter(Mandatory)]
                [string]$Text
            )

            return [regex]::Replace($Text.Replace($script:hostile, $script:relayed), '[^\x20-\x7E]', '?')
        }

        function script:New-LongPath {
            param(
                [Parameter(Mandatory)]
                [string]$Tag
            )

            return Join-Path $script:relayBase ($Tag + '-' + ('y' * 180))
        }

        function script:Invoke-RelayCase {
            param(
                [Parameter(Mandatory)]
                [string]$Site
            )

            $map = @{ $script:relayRoot = (New-ObjectRight -Path $script:relayRoot -Granted @('WriteData', 'AppendData')) }
            $declared = @($script:relayRoot)
            $escape = @()
            $module = @()
            $long = @(1..8 | ForEach-Object -Process { New-LongPath -Tag "place$_" })

            switch ($Site) {
                'a declared root that does not exist' {
                    $declared = @($script:hostileRoot)
                }
                'the reason a declared root could not be measured' {
                    $declared = @($script:hostileRoot)
                    $map[$script:hostileRoot] = New-ObjectRight -Path $script:hostileRoot -State 'Unknown' -Reason $script:attributeReason
                }
                'a declared root that is a file' {
                    $declared = @($script:hostileRoot)
                    $map[$script:hostileRoot] = New-ObjectRight -Path $script:hostileRoot -IsDirectory $false -Granted @('WriteData', 'AppendData')
                }
                'a declared root this identity cannot write' {
                    $declared = @($script:hostileRoot)
                    $map[$script:hostileRoot] = New-ObjectRight -Path $script:hostileRoot
                }
                'a declared root whose rights could not be measured' {
                    $declared = @($script:hostileRoot)
                    $map[$script:hostileRoot] = New-ObjectRight -Path $script:hostileRoot -Granted @('WriteData') -Unknown @('AppendData')
                }
                'the declared roots of a Pass' {
                    $declared = @($script:hostileRoot)
                    $map[$script:hostileRoot] = New-ObjectRight -Path $script:hostileRoot -Granted @('WriteData', 'AppendData')
                }
                'an escape path a declared root covers' {
                    $declared = @($script:hostileRoot)
                    $map[$script:hostileRoot] = New-ObjectRight -Path $script:hostileRoot -Granted @('WriteData', 'AppendData')
                    $escape = @(Join-Path $script:hostileRoot 'below')
                }
                'an escape path this identity can write' {
                    $escape = @($script:hostilePlace)
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace -Granted @('WriteData')
                }
                'the reason an escape path could not be measured' {
                    $escape = @($script:hostilePlace)
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace -State 'Unknown' -Reason $script:probeReason
                }
                'an escape path whose rights could not be measured' {
                    $escape = @($script:hostilePlace)
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace -Unknown @('WriteData')
                }
                'a closed escape path' {
                    $escape = @($script:hostilePlace)
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace
                }
                'an escape path below a closed folder' {
                    $escape = @($script:belowHostile)
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder
                }
                'an escape path below a writable folder' {
                    $escape = @($script:belowHostile)
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -Granted @('AppendData')
                }
                'an escape path below a folder that could not be measured' {
                    $escape = @($script:belowHostile)
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -State 'Unknown' -Reason $script:attributeReason
                }
                'an escape path below a file' {
                    $escape = @($script:belowHostile)
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -IsDirectory $false
                    # Off Windows the verifier measures the folder that holds the file (Get-ReplacementRight).
                    $map[$script:relayBase] = New-ObjectRight -Path $script:relayBase
                }
                'a module entry that is not opened' {
                    $module = @($script:hostileEntry)
                }
                'a module folder this identity can write' {
                    $module = @($script:hostilePlace)
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace -Granted @('WriteData')
                }
                'a closed module folder' {
                    $module = @($script:hostilePlace)
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace
                    $map[$script:relayBase] = New-ObjectRight -Path $script:relayBase
                }
                'the reason a module folder could not be measured' {
                    $module = @($script:hostilePlace)
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace -State 'Unknown' -Reason $script:probeReason
                }
                'a module folder below a writable folder' {
                    $module = @($script:belowHostile)
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -Granted @('AppendData')
                }
                'a module folder whose folder above this identity can write' {
                    $module = @(Join-Path $script:hostileFolder 'Modules')
                    $map[$module[0]] = New-ObjectRight -Path $module[0] -Unknown @('Delete', 'WriteDac', 'WriteOwner')
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -Granted @('WriteData')
                }
                'the reason the folder above a module folder could not be measured' {
                    $module = @(Join-Path $script:hostileFolder 'Modules')
                    $map[$module[0]] = New-ObjectRight -Path $module[0] -Unknown @('Delete', 'WriteDac', 'WriteOwner')
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -State 'Unknown' -Reason $script:attributeReason
                }
                'an escape path below a file that this identity can delete' {
                    $escape = @($script:belowHostile)
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -IsDirectory $false -Granted @('Delete')
                }
                'an escape path below a file in a folder this identity can write' {
                    $escape = @($script:belowHostile)
                    $map[$script:hostileFolder] = New-ObjectRight -Path $script:hostileFolder -IsDirectory $false
                    $map[$script:relayBase] = New-ObjectRight -Path $script:relayBase -Granted @('WriteData')
                }
                'a path of 5,000 characters' {
                    $script:longPath = Join-Path $script:relayBase ('x' * 5000)
                    $escape = @($script:longPath)
                    $map[$script:longPath] = New-ObjectRight -Path $script:longPath -Granted @('WriteData')
                }
                'the list of roots that are unusable' {
                    $declared = $long
                }
                'the list of escape paths this identity can write' {
                    $escape = $long
                    foreach ($path in $long) { $map[$path] = New-ObjectRight -Path $path -Granted @('WriteData') }
                }
                'the list of module places this identity can write' {
                    $module = $long
                    foreach ($path in $long) { $map[$path] = New-ObjectRight -Path $path -Granted @('WriteData') }
                }
                'the list of places that could not be measured' {
                    $escape = $long
                    foreach ($path in $long) { $map[$path] = New-ObjectRight -Path $path -Unknown @('WriteData') }
                }
                'the list of places that could not be measured beside a breach' {
                    $escape = @($script:hostilePlace) + $long
                    $map[$script:hostilePlace] = New-ObjectRight -Path $script:hostilePlace -Granted @('WriteData')
                    foreach ($path in $long) { $map[$path] = New-ObjectRight -Path $path -Unknown @('WriteData') }
                }
                'the notes of the escape set' {
                    $escape = $long
                    foreach ($path in $long) { $map[$path] = New-ObjectRight -Path $path }
                }
                'the notes of the module places' {
                    $module = $long
                    foreach ($path in $long) { $map[$path] = New-ObjectRight -Path $path }
                    $map[$script:relayBase] = New-ObjectRight -Path $script:relayBase
                }
                'the declared roots of a long Pass' {
                    $declared = $long
                    foreach ($path in $long) { $map[$path] = New-ObjectRight -Path $path -Granted @('WriteData', 'AppendData') }
                }
                default {
                    throw "no relay case is named '$Site'"
                }
            }

            Set-ObjectRight -Map $map

            return Test-WritableRoot -Declared $declared -EscapeSet $escape -ModuleSet $module
        }
    }

    It 'relays <Site> as printable ASCII within its caps' -ForEach @(
        @{ Site = 'a declared root that does not exist'; Status = 'Fail'; Text = 'root' }
        @{ Site = 'the reason a declared root could not be measured'; Status = 'Unavailable'; Text = 'attributeReason' }
        @{ Site = 'a declared root that is a file'; Status = 'Fail'; Text = 'root' }
        @{ Site = 'a declared root this identity cannot write'; Status = 'Fail'; Text = 'root' }
        @{ Site = 'a declared root whose rights could not be measured'; Status = 'Unavailable'; Text = 'root' }
        @{ Site = 'the declared roots of a Pass'; Status = 'Pass'; Text = 'root' }
        @{ Site = 'an escape path a declared root covers'; Status = 'Pass'; Text = 'root' }
        @{ Site = 'an escape path this identity can write'; Status = 'Fail'; Text = 'place' }
        @{ Site = 'the reason an escape path could not be measured'; Status = 'Unavailable'; Text = 'probeReason' }
        @{ Site = 'an escape path whose rights could not be measured'; Status = 'Unavailable'; Text = 'place' }
        @{ Site = 'a closed escape path'; Status = 'Pass'; Text = 'place' }
        @{ Site = 'an escape path below a closed folder'; Status = 'Pass'; Text = 'folder' }
        @{ Site = 'an escape path below a writable folder'; Status = 'Fail'; Text = 'folder' }
        @{ Site = 'an escape path below a folder that could not be measured'; Status = 'Unavailable'; Text = 'attributeReason' }
        @{ Site = 'an escape path below a file'; Status = 'Pass'; Text = 'folder'; Platform = 'Posix' }
        @{ Site = 'an escape path below a file'; Status = 'Pass'; Text = 'folder'; Platform = 'Windows' }
        @{ Site = 'a module entry that is not opened'; Status = 'Unavailable'; Text = 'entry' }
        @{ Site = 'a module folder this identity can write'; Status = 'Fail'; Text = 'place' }
        @{ Site = 'a closed module folder'; Status = 'Pass'; Text = 'place' }
        @{ Site = 'the reason a module folder could not be measured'; Status = 'Unavailable'; Text = 'probeReason' }
        @{ Site = 'a module folder below a writable folder'; Status = 'Fail'; Text = 'folder' }
        @{ Site = 'a module folder whose folder above this identity can write'; Status = 'Fail'; Text = 'folder'; Platform = 'Posix' }
        @{ Site = 'the reason the folder above a module folder could not be measured'; Status = 'Unavailable'; Text = 'attributeReason'; Platform = 'Posix' }
        @{ Site = 'an escape path below a file that this identity can delete'; Status = 'Fail'; Text = 'folder'; Platform = 'Windows' }
        @{ Site = 'an escape path below a file in a folder this identity can write'; Status = 'Fail'; Text = 'folder'; Platform = 'Posix' }
        @{ Site = 'a path of 5,000 characters'; Status = 'Fail'; Text = 'long' }
        @{ Site = 'the list of roots that are unusable'; Status = 'Fail'; List = 'declared roots unusable: \[(?<list>[^\]]*)\]' }
        @{ Site = 'the list of escape paths this identity can write'; Status = 'Fail'; List = 'writable outside the declared roots: \[(?<list>[^\]]*)\]' }
        @{ Site = 'the list of module places this identity can write'; Status = 'Fail'; List = 'inside a declared root or not: \[(?<list>[^\]]*)\]' }
        @{ Site = 'the list of places that could not be measured'; Status = 'Unavailable'; List = '\Anot measurable: (?<list>.*)\z' }
        @{ Site = 'the list of places that could not be measured beside a breach'; Status = 'Fail'; List = 'not measurable: \[(?<list>[^\]]*)\]' }
        @{ Site = 'the notes of the escape set'; Status = 'Pass'; List = 'writable outside them: (?<list>.*); the rest of the filesystem is not enumerated\z' }
        @{ Site = 'the notes of the module places'; Status = 'Pass'; List = 'inside a declared root or not: (?<list>.*); the rest of the filesystem is not enumerated\z' }
        @{ Site = 'the declared roots of a long Pass'; Status = 'Pass'; List = '\Aevery declared root accepts new files and folders \((?<list>.*?)\), and none of the escape set' }
    ) {
        # A row that names a platform runs as the verifier runs there; the others run as on this system.
        $result = if ($_.Platform) {
            Invoke-AsPlatform -Windows ($_.Platform -eq 'Windows') -Action { Invoke-RelayCase -Site $Site }
        } else {
            Invoke-RelayCase -Site $Site
        }

        $result.status | Should -Be $Status -Because $result.evidence
        $result.evidence | Should -Match '\A[\x20-\x7E]*\z'

        # A row names only the keys it needs, so the optional ones are read from the row itself.
        if ($_.Text) {
            $outside = switch ($_.Text) {
                'root' { $script:hostileRoot }
                'place' { $script:hostilePlace }
                'folder' { $script:hostileFolder }
                'entry' { $script:hostileEntry }
                'attributeReason' { $script:attributeReason }
                'probeReason' { $script:probeReason }
                'long' { $script:longPath }
            }
            $relayedForm = Get-RelayedForm -Text $outside

            $result.evidence | Should -Match ([regex]::Escape($relayedForm.Substring(0, 200) + '...')) -Because 'the text is relayed, and cut at 200 characters'
            $result.evidence.Contains($relayedForm.Substring(0, 201)) | Should -Be $false -Because 'nothing of the text past 200 characters reaches the evidence'
        }

        if ($_.List) {
            $result.evidence -match $_.List | Should -Be $true -Because $result.evidence
            $Matches['list'] | Should -Match '\.\.\.\z'
            $Matches['list'].Length | Should -Be 1003 -Because 'a list longer than 1,000 characters is cut there and marked'
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

    It 'passes when every control and live artifact is closed, and says that the token is judged by IdentityPrivilege' {
        Mock -CommandName Test-PathProtection -MockWith { New-ClosedProtection -Path $Path }

        $result = Test-ControlImmutability -ProfilePath (Join-Path $script:controls 'profile.json') -ContainmentProfile (New-ControlProfile) -WritableRoot @()

        $result.status | Should -Be 'Pass' -Because $result.evidence
        $result.evidence | Should -Not -Match 'token is not read'
        $result.evidence | Should -Match 'IdentityPrivilege'
    }
}
