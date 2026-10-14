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
            'Initialize-NativeAccess'
            'Get-PathChain'
            'Get-ObjectRight'
            'Test-PathOverlap'
            'Test-PathProtection'
        ))

    # Every right set to one state, so a case can change exactly the right it is about.
    function script:New-RightSet {
        param(
            [Parameter()]
            [ValidateSet('Granted', 'Denied', 'Unknown')]
            [string]$Default = 'Denied',

            [Parameter()]
            [hashtable]$Override = @{}
        )

        $set = @{}
        foreach ($name in 'WriteData', 'AppendData', 'DeleteChild', 'Delete', 'WriteDac', 'WriteOwner') {
            $set[$name] = $Default
        }

        foreach ($name in $Override.Keys) {
            $set[$name] = $Override[$name]
        }

        return $set
    }

    function script:New-ObjectRight {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter()]
            [string]$State = 'Measured',

            [Parameter()]
            [switch]$Directory,

            [Parameter()]
            [switch]$Reparse,

            [Parameter()]
            [hashtable]$Right = (New-RightSet)
        )

        [pscustomobject]@{
            Path = $Path
            State = $State
            IsDirectory = [bool]$Directory
            IsReparsePoint = [bool]$Reparse
            ReadOnly = $false
            Right = $Right
            Reason = ''
        }
    }

    # A fake file system for Test-PathProtection: a map from path to its object.
    function script:Set-FakeRight {
        param(
            [Parameter(Mandatory)]
            [hashtable]$Map
        )

        $script:fakeRight = $Map
    }
}

Describe 'Containment path chain' -Tag 'Unit' {
    It 'lists a file and every ancestor up to the root' -Skip:(-not $script:onWindows) {
        $chain = @(Get-PathChain -Path 'C:\alpha\beta\gamma.json')

        $chain | Should -Be @('C:\alpha\beta\gamma.json', 'C:\alpha\beta', 'C:\alpha', 'C:\')
    }

    It 'lists a file and every ancestor up to the root on a POSIX system' -Skip:($script:onWindows) {
        $chain = @(Get-PathChain -Path '/alpha/beta/gamma.json')

        $chain | Should -Be @('/alpha/beta/gamma.json', '/alpha/beta', '/alpha', '/')
    }

    It 'resolves dot segments before it lists the ancestors' -Skip:(-not $script:onWindows) {
        $chain = @(Get-PathChain -Path 'C:\alpha\beta\..\gamma.json')

        $chain | Should -Be @('C:\alpha\gamma.json', 'C:\alpha', 'C:\')
    }
}

Describe 'Containment path overlap' -Tag 'Unit' {
    It 'finds <Reason>' -ForEach @(
        @{ Reason = 'a path inside a writable root'; Path = 'C:\work\sub\file.json'; Root = 'C:\work'; Expected = $true }
        @{ Reason = 'a path equal to a writable root'; Path = 'C:\work'; Root = 'C:\work\'; Expected = $true }
        @{ Reason = 'a writable root inside a protected directory'; Path = 'C:\protected'; Root = 'C:\protected\run\work'; Expected = $true }
        @{ Reason = 'no overlap for a sibling that shares a prefix'; Path = 'C:\work-protected\file.json'; Root = 'C:\work'; Expected = $false }
        @{ Reason = 'no overlap for unrelated paths'; Path = 'D:\ledger\run.jsonl'; Root = 'C:\work'; Expected = $false }
        @{ Reason = 'an overlap that differs only in case'; Path = 'C:\WORK\file.json'; Root = 'c:\work'; Expected = $true }
    ) -Skip:(-not $script:onWindows) {
        Test-PathOverlap -Path $Path -WritableRoot $Root | Should -Be $Expected
    }
}

Describe 'Containment path protection' -Tag 'Unit' {
    BeforeEach {
        # The fake file system: a leaf in a directory in a directory, all closed.
        $script:leaf = if ($script:onWindows) { 'C:\control\scripts\hook.ps1' } else { '/control/scripts/hook.ps1' }
        $script:parent = Split-Path -Parent $script:leaf
        $script:grandparent = Split-Path -Parent $script:parent
        $script:root = Split-Path -Parent $script:grandparent
        $script:object = @{}
        $script:object[$script:leaf] = New-ObjectRight -Path $script:leaf
        foreach ($directory in $script:parent, $script:grandparent, $script:root) {
            $script:object[$directory] = New-ObjectRight -Path $directory -Directory
        }

        Mock -CommandName 'Get-ObjectRight' -MockWith { $script:object[$Path] }
    }

    It 'passes a file and a chain of ancestors that grant this identity nothing' {
        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeTrue -Because ($result.Violation -join '; ')
        @($result.Violation) | Should -HaveCount 0
        @($result.Unmeasured) | Should -HaveCount 0
    }

    It 'fails a file this identity can <Right>' -ForEach @(
        @{ Right = 'WriteData' }
        @{ Right = 'AppendData' }
        @{ Right = 'Delete' }
        @{ Right = 'WriteDac' }
        @{ Right = 'WriteOwner' }
    ) {
        $script:object[$script:leaf].Right[$Right] = 'Granted'

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match ([regex]::Escape($script:leaf))
    }

    It 'fails a read-only file in a directory whose children this identity can delete' {
        # Review of 2026-10-12, C-02: a file the caller cannot open for write is still
        # replaceable when the directory that holds it lets the caller delete children.
        $script:object[$script:parent].Right['DeleteChild'] = 'Granted'

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'FILE_DELETE_CHILD'
        ($result.Violation -join '; ') | Should -Match ([regex]::Escape($script:parent))
    }

    It 'fails a file whose owner is this identity, because the owner can rewrite its access list' {
        # Review of 2026-10-12, C-02: a deny-write entry does not protect a file from its owner.
        $script:object[$script:leaf].Right['WriteDac'] = 'Granted'

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'WRITE_DAC'
    }

    It 'fails when this identity can <Right> an ancestor directory' -ForEach @(
        @{ Right = 'Delete' }
        @{ Right = 'DeleteChild' }
        @{ Right = 'WriteDac' }
        @{ Right = 'WriteOwner' }
    ) {
        $script:object[$script:grandparent].Right[$Right] = 'Granted'

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match ([regex]::Escape($script:grandparent))
    }

    It 'fails a path that crosses a reparse point' {
        $script:object[$script:grandparent].IsReparsePoint = $true

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'reparse point'
    }

    It 'reports a right it could not measure as unmeasured, not as closed' {
        $script:object[$script:parent].Right['DeleteChild'] = 'Unknown'

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        @($result.Violation) | Should -HaveCount 0
        ($result.Unmeasured -join '; ') | Should -Match ([regex]::Escape($script:parent))
    }

    It 'reports an object it could not read as unmeasured' {
        $script:object[$script:leaf].State = 'Unknown'
        $script:object[$script:leaf].Reason = 'the object could not be opened'

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        ($result.Unmeasured -join '; ') | Should -Match 'could not be opened'
    }

    It 'lets a violation outrank an unmeasured right' {
        $script:object[$script:leaf].Right['Delete'] = 'Granted'
        $script:object[$script:parent].Right['DeleteChild'] = 'Unknown'

        $result = Test-PathProtection -Path $script:leaf

        $result.Closed | Should -BeFalse
        @($result.Violation) | Should -HaveCount 1
        @($result.Unmeasured) | Should -HaveCount 1
    }

    It 'marks an absent file and still fails when this identity can create it' {
        $script:object[$script:leaf] = New-ObjectRight -Path $script:leaf -State 'Absent'
        $script:object[$script:parent].Right['WriteData'] = 'Granted'

        $result = Test-PathProtection -Path $script:leaf

        $result.Absent | Should -BeTrue
        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'FILE_ADD_FILE'
    }

    It 'passes an absent file whose directory this identity cannot add to' {
        $script:object[$script:leaf] = New-ObjectRight -Path $script:leaf -State 'Absent'

        $result = Test-PathProtection -Path $script:leaf

        $result.Absent | Should -BeTrue
        $result.Closed | Should -BeTrue -Because ($result.Violation -join '; ')
    }

    It 'fails a file whose directory and parents do not exist when this identity can create one' {
        $script:object[$script:leaf] = New-ObjectRight -Path $script:leaf -State 'Absent'
        $script:object[$script:parent] = New-ObjectRight -Path $script:parent -State 'Absent' -Directory
        $script:object[$script:grandparent].Right['AppendData'] = 'Granted'

        $result = Test-PathProtection -Path $script:leaf

        $result.Absent | Should -BeTrue
        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'FILE_ADD_SUBDIRECTORY'
    }

    It 'fails a file inside a writable root' {
        $result = Test-PathProtection -Path $script:leaf -WritableRoot @($script:grandparent)

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'writable root'
    }

    It 'fails a protected directory that contains a writable root' {
        $result = Test-PathProtection -Path $script:grandparent -WritableRoot @($script:leaf)

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'writable root'
    }

    It 'checks a directory for adding and deleting children, not only for writing' {
        $script:object[$script:parent].Right['WriteData'] = 'Granted'

        $result = Test-PathProtection -Path $script:parent

        $result.Closed | Should -BeFalse
        ($result.Violation -join '; ') | Should -Match 'FILE_ADD_FILE'
    }
}

Describe 'Containment access rights of a real object' -Tag 'Unit' {
    BeforeAll {
        $script:caller = if ($script:onWindows) { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } else { '' }
        $script:room = Join-Path $TestDrive 'rights'
        $null = New-Item -Path $script:room -ItemType Directory -Force
    }

    It 'reports an object that does not exist as absent' -Skip:(-not $script:onWindows) {
        $result = Get-ObjectRight -Path (Join-Path $script:room 'missing.json')

        $result.State | Should -Be 'Absent'
    }

    It 'grants the owner of a file every right it can use to replace the file' -Skip:(-not $script:onWindows) {
        $path = Join-Path $script:room 'owned.json'
        [System.IO.File]::WriteAllText($path, '{}')

        $result = Get-ObjectRight -Path $path

        $result.State | Should -Be 'Measured'
        $result.IsDirectory | Should -BeFalse
        foreach ($name in 'WriteData', 'AppendData', 'Delete', 'WriteDac') {
            $result.Right[$name] | Should -Be 'Granted' -Because $name
        }
    }

    It 'sees a deny entry for writing, and still sees that the owner can change the access list' -Skip:(-not $script:onWindows) {
        # Review of 2026-10-12, C-02: "deny-write file owned by the caller".
        $path = Join-Path $script:room 'deny-write.json'
        [System.IO.File]::WriteAllText($path, '{}')
        $acl = Get-Acl -LiteralPath $path
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($script:caller, 'Write', 'Deny'))
        Set-Acl -LiteralPath $path -AclObject $acl

        $result = Get-ObjectRight -Path $path

        $result.Right['WriteData'] | Should -Be 'Denied'
        $result.Right['AppendData'] | Should -Be 'Denied'
        $result.Right['WriteDac'] | Should -Be 'Granted' -Because 'the owner may always rewrite the access list'
    }

    It 'sees a read-only file as unmeasured for writing while the attribute can be cleared' -Skip:(-not $script:onWindows) {
        $path = Join-Path $script:room 'read-only.json'
        [System.IO.File]::WriteAllText($path, '{}')
        (Get-Item -LiteralPath $path).IsReadOnly = $true
        try {
            $result = Get-ObjectRight -Path $path
        } finally {
            (Get-Item -LiteralPath $path).IsReadOnly = $false
        }

        $result.ReadOnly | Should -BeTrue
        # The attribute refuses the open whatever the access list says, so the open
        # proves nothing about access control; the owner can clear it.
        $result.Right['WriteData'] | Should -Be 'Unknown'
        $result.Right['WriteDac'] | Should -Be 'Granted'
    }

    It 'reads a right as granted, not unmeasured, while another process holds the file without sharing' -Skip:(-not $script:onWindows) {
        # The live appender holds the sink open for appending the whole run. The kernel checks the
        # access list before it compares share modes, so a sharing violation (error 32) means the
        # right was granted and only the other handle's sharing blocked this open.
        $path = Join-Path $script:room 'held-open.jsonl'
        [System.IO.File]::WriteAllText($path, '')
        $hold = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $result = Get-ObjectRight -Path $path
        } finally {
            $hold.Dispose()
        }

        $result.State | Should -Be 'Measured'
        foreach ($name in 'WriteData', 'AppendData', 'Delete') {
            $result.Right[$name] | Should -Be 'Granted' -Because "$name was granted and only the share mode blocked the probe"
        }

        $result.Reason | Should -BeNullOrEmpty
    }

    It 'still reads a right the access list denies as denied while another process holds the file' -Skip:(-not $script:onWindows) {
        # This is what lets a closed ledger sink pass while the appender is running: the run
        # identity is denied, and a held file must not turn that denial into an unmeasured right.
        $path = Join-Path $script:room 'held-and-denied.jsonl'
        [System.IO.File]::WriteAllText($path, '')
        $hold = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $acl = Get-Acl -LiteralPath $path
            $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($script:caller, 'Write', 'Deny'))
            Set-Acl -LiteralPath $path -AclObject $acl

            $result = Get-ObjectRight -Path $path
        } finally {
            $hold.Dispose()
        }

        $result.Right['WriteData'] | Should -Be 'Denied'
        $result.Right['AppendData'] | Should -Be 'Denied'
        $result.Reason | Should -BeNullOrEmpty
    }

    It 'reports a directory with the rights that matter for its children' -Skip:(-not $script:onWindows) {
        $result = Get-ObjectRight -Path $script:room

        $result.IsDirectory | Should -BeTrue
        foreach ($name in 'WriteData', 'AppendData', 'DeleteChild', 'WriteDac') {
            $result.Right[$name] | Should -Be 'Granted' -Because $name
        }
    }

    It 'sees a deny entry for creating files in a directory' -Skip:(-not $script:onWindows) {
        $directory = Join-Path $script:room 'no-create'
        $null = New-Item -Path $directory -ItemType Directory -Force
        $acl = Get-Acl -LiteralPath $directory
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($script:caller, 'CreateFiles', 'Deny'))
        Set-Acl -LiteralPath $directory -AclObject $acl

        $result = Get-ObjectRight -Path $directory

        $result.Right['WriteData'] | Should -Be 'Denied'
        $result.Right['AppendData'] | Should -Be 'Granted'
    }

    It 'recognizes a symbolic link as a reparse point' -Skip:(-not $script:onWindows) {
        $target = Join-Path $script:room 'link-target.json'
        $link = Join-Path $script:room 'link.json'
        [System.IO.File]::WriteAllText($target, '{}')
        try {
            $null = New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop
        } catch {
            Set-ItResult -Skipped -Because "a symbolic link could not be made here: $($_.Exception.Message)"
            return
        }

        (Get-ObjectRight -Path $link).IsReparsePoint | Should -BeTrue
    }

    It 'reports a system file as denied for writing and deleting by a caller that is not its owner' -Skip:(-not $script:onWindows) {
        # No test can plant a Pass: the identity that runs the suite owns its own files. A file
        # of the operating system proves that the probe returns Denied for a real denial.
        $path = [System.IO.Path]::Combine([Environment]::GetFolderPath('System'), 'kernel32.dll')

        $result = Get-ObjectRight -Path $path

        $result.State | Should -Be 'Measured'
        $result.Right['WriteData'] | Should -Be 'Denied'
        $result.Right['Delete'] | Should -Be 'Denied'
    }
}
