# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

# The runtime's own answer to "is this process elevated", computed on its own path. It exists from .NET 8.
$script:hasRuntimeElevation = $null -ne [System.Environment].GetProperty('IsPrivilegedProcess', [System.Reflection.BindingFlags]'Public, Static')

# A real filtered token can be made only from a token whose Administrators group is enabled, which an
# administrator's is (the Windows runner of CI, and the owner's host). A standard account skips those cases.
$script:adminHost = $script:onWindows -and [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

BeforeDiscovery {
    # Every row is plain ASCII. A parameterized test that is skipped on a platform keeps its unexpanded
    # name, and Pester's NUnit writer appends the row's data to it, so a character that XML forbids in
    # a row would fail the build on that platform. Odd characters are built inside the test body.
    $outsideFive = foreach ($name in @(
            'SeBackupPrivilege', 'SeRestorePrivilege', 'SeTakeOwnershipPrivilege', 'SeDebugPrivilege'
            'SeImpersonatePrivilege', 'SeCreateGlobalPrivilege', 'SeLoadDriverPrivilege', 'SeSecurityPrivilege'
            'SeTcbPrivilege', 'SeAssignPrimaryTokenPrivilege', 'SeCreateSymbolicLinkPrivilege', 'SeManageVolumePrivilege'
        )) {
        @{ Name = $name; State = 'disabled'; Attributes = 0 }
        @{ Name = $name; State = 'enabled'; Attributes = 2 }
    }

    # Every other privilege that winnt.h names, so that a name added to the five by mistake is caught
    # whichever one it is. The five themselves are SeChangeNotify, SeShutdown, SeUndock, SeIncreaseWorkingSet and SeTimeZone.
    $otherPrivilege = foreach ($name in @(
            'SeCreateTokenPrivilege', 'SeAssignPrimaryTokenPrivilege', 'SeLockMemoryPrivilege', 'SeIncreaseQuotaPrivilege'
            'SeUnsolicitedInputPrivilege', 'SeMachineAccountPrivilege', 'SeTcbPrivilege', 'SeSecurityPrivilege'
            'SeTakeOwnershipPrivilege', 'SeLoadDriverPrivilege', 'SeSystemProfilePrivilege', 'SeSystemtimePrivilege'
            'SeProfileSingleProcessPrivilege', 'SeIncreaseBasePriorityPrivilege', 'SeCreatePagefilePrivilege'
            'SeCreatePermanentPrivilege', 'SeBackupPrivilege', 'SeRestorePrivilege', 'SeDebugPrivilege', 'SeAuditPrivilege'
            'SeSystemEnvironmentPrivilege', 'SeRemoteShutdownPrivilege', 'SeSyncAgentPrivilege', 'SeEnableDelegationPrivilege'
            'SeManageVolumePrivilege', 'SeImpersonatePrivilege', 'SeCreateGlobalPrivilege', 'SeTrustedCredManAccessPrivilege'
            'SeRelabelPrivilege', 'SeCreateSymbolicLinkPrivilege', 'SeDelegateSessionUserImpersonatePrivilege'
        )) {
        @{ Name = $name }
    }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'
    . (Join-Path $script:repoRoot 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'New-CheckResult'
            'Format-LimitedList'
            'Format-RelayedText'
            'Initialize-NativeToken'
            'ConvertTo-TokenFact'
            'Get-CallerTokenFact'
            'Get-IntegrityLevelName'
            'Get-TokenFactProblem'
            'Test-IdentityPrivilege'
        ))

    function script:New-Group {
        param(
            [Parameter(Mandatory)]
            [string]$Sid,

            [Parameter()]
            [uint32]$Attributes = 7
        )

        return [pscustomobject]@{ Sid = $Sid; Attributes = $Attributes }
    }

    function script:New-Privilege {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Name,

            [Parameter()]
            [uint32]$Attributes = 0
        )

        return [pscustomobject]@{ Name = $Name; Attributes = $Attributes }
    }

    # The facts of a standard account's token unless a case changes one of them: not elevated, the
    # default elevation type, Medium integrity, none of the administrative groups, and the five
    # privileges a standard account holds.
    function script:New-TokenFact {
        param(
            [Parameter()]
            [bool]$Elevated = $false,

            [Parameter()]
            [int]$ElevationType = 1,

            [Parameter()]
            [int]$IntegrityRid = 0x2000,

            [Parameter()]
            [object[]]$Group = @(
                (New-Group -Sid 'S-1-1-0')
                (New-Group -Sid 'S-1-5-32-545')
                (New-Group -Sid 'S-1-5-4')
                (New-Group -Sid 'S-1-5-11')
                (New-Group -Sid 'S-1-5-5-0-1234567' -Attributes 3221225479)
            ),

            [Parameter()]
            [object[]]$Privilege = @(
                (New-Privilege -Name 'SeChangeNotifyPrivilege' -Attributes 3)
                (New-Privilege -Name 'SeShutdownPrivilege')
                (New-Privilege -Name 'SeUndockPrivilege')
                (New-Privilege -Name 'SeIncreaseWorkingSetPrivilege')
                (New-Privilege -Name 'SeTimeZonePrivilege')
            )
        )

        return [pscustomobject]@{
            Elevated = $Elevated
            ElevationType = $ElevationType
            IntegrityRid = $IntegrityRid
            Group = $Group
            Privilege = $Privilege
        }
    }

    function script:Use-TokenFact {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Fact
        )

        $script:fact = $Fact
        Mock -CommandName 'Get-CallerTokenFact' -MockWith { $script:fact }
    }

    # A function with no parameter of its own: the parameters every advanced function gets.
    function script:Get-NoParameterReference {
        [CmdletBinding()]
        param()
    }
}

Describe 'Containment identity privilege' -Tag 'Unit' {
    BeforeAll {
        # The cases below say they run on Windows, on every platform, and that must not outlast this block:
        # the blocks after it read the constant at run time and decide from it what to define.
        $script:savedOnWindows = $script:OnWindows
    }

    AfterAll {
        $script:OnWindows = $script:savedOnWindows
    }

    BeforeEach {
        # The verifier runs in strict mode, and a fact that is missing must not be read as false here.
        Set-StrictMode -Version 3.0
        $script:OnWindows = $true
        $script:TokenReadProblem = ''
        Use-TokenFact -Fact (New-TokenFact)
    }

    Context 'a token that is a standard account''s' {
        It 'passes, and names the facts it saw' {
            $result = Test-IdentityPrivilege

            $result.name | Should -Be 'IdentityPrivilege'
            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Match 'standard account'
            $result.evidence | Should -Match 'Medium \(S-1-16-8192\)'
            $result.evidence | Should -Match 'SeChangeNotifyPrivilege \(enabled\)'
            $result.evidence | Should -Match 'SeShutdownPrivilege \(disabled\)'
        }

        It 'passes a token that holds only some of the five privileges' {
            Use-TokenFact -Fact (New-TokenFact -Privilege @(New-Privilege -Name 'SeChangeNotifyPrivilege' -Attributes 3))

            (Test-IdentityPrivilege).status | Should -Be 'Pass'
        }

        It 'passes a token that holds no privilege' {
            Use-TokenFact -Fact (New-TokenFact -Privilege @())

            (Test-IdentityPrivilege).status | Should -Be 'Pass'
        }

        It 'allows exactly the five privileges of a standard account, and no other' {
            @($script:StandardPrivilege | Sort-Object) | Should -Be @(
                'SeChangeNotifyPrivilege'
                'SeIncreaseWorkingSetPrivilege'
                'SeShutdownPrivilege'
                'SeTimeZonePrivilege'
                'SeUndockPrivilege'
            )
        }

        It 'passes integrity level <Name>, which is not above Medium' -ForEach @(
            @{ Name = 'Untrusted'; Rid = 0 }
            @{ Name = 'Low'; Rid = 4096 }
            @{ Name = 'Medium'; Rid = 8192 }
        ) {
            Use-TokenFact -Fact (New-TokenFact -IntegrityRid $Rid)

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Match ([regex]::Escape("$Name (S-1-16-$Rid)"))
        }

        It 'does not take a group other than Administrators for Administrators' -ForEach @(
            @{ Sid = 'S-1-5-32-5440' }
            @{ Sid = 'S-1-5-32-54' }
            @{ Sid = 'S-1-5-32-551' }
            @{ Sid = 'S-1-5-21-1-2-3-544' }
        ) {
            Use-TokenFact -Fact (New-TokenFact -Group @(New-Group -Sid $Sid))

            (Test-IdentityPrivilege).status | Should -Be 'Pass'
        }
    }

    Context 'a token that is not a standard account''s' {
        It 'refuses an elevated token' {
            Use-TokenFact -Fact (New-TokenFact -Elevated $true)

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'not a standard account'
            $result.evidence | Should -Match 'elevated'
        }

        It 'refuses elevation type <Name>, the mark of a split administrator token' -ForEach @(
            @{ Name = 'Full'; Value = 2 }
            @{ Name = 'Limited'; Value = 3 }
        ) {
            Use-TokenFact -Fact (New-TokenFact -ElevationType $Value)

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match "elevation type is $Name"
        }

        It 'refuses integrity level <Name>, which is above Medium' -ForEach @(
            @{ Name = 'Medium Plus'; Rid = 8448 }
            @{ Name = 'High'; Rid = 12288 }
            @{ Name = 'System'; Rid = 16384 }
            @{ Name = 'Protected'; Rid = 20480 }
            @{ Name = 'an unnamed level'; Rid = 4660 + 8192 }
        ) {
            Use-TokenFact -Fact (New-TokenFact -IntegrityRid $Rid)

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match ([regex]::Escape("$Name (S-1-16-$Rid), above Medium"))
        }

        It 'refuses the Administrators group in the state <State>, which the probes never show' -ForEach @(
            @{ State = 'enabled'; Attributes = 7 }
            @{ State = 'deny-only'; Attributes = 16 }
            @{ State = 'disabled'; Attributes = 0 }
        ) {
            $group = @(New-Group -Sid 'S-1-1-0') + @(New-Group -Sid 'S-1-5-32-544' -Attributes ([uint32]$Attributes))
            Use-TokenFact -Fact (New-TokenFact -Group $group)

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match ([regex]::Escape("the Administrators group (S-1-5-32-544) is in the token, $State"))
        }

        It 'refuses <Name> when it is <State>, because a disabled privilege can be enabled' -ForEach $outsideFive {
            $privilege = @(New-Privilege -Name 'SeChangeNotifyPrivilege' -Attributes 3) + @(New-Privilege -Name $Name -Attributes ([uint32]$Attributes))
            Use-TokenFact -Fact (New-TokenFact -Privilege $privilege)

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match ([regex]::Escape("outside the five of a standard account: $Name ($State)"))
        }

        It 'refuses <Name>, which no standard account holds' -ForEach $otherPrivilege {
            Use-TokenFact -Fact (New-TokenFact -Privilege @(New-Privilege -Name $Name))

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match ([regex]::Escape("outside the five of a standard account: $Name (disabled)"))
        }

        It 'cuts a long privilege name, so a name cannot fill the report' {
            $name = 'Se' + ('A' * 100) + 'Privilege'
            Use-TokenFact -Fact (New-TokenFact -Privilege @(New-Privilege -Name $name))

            $evidence = (Test-IdentityPrivilege).evidence

            $evidence | Should -Match ([regex]::Escape('Se' + ('A' * 58) + '... (disabled)'))
            $evidence | Should -Not -Match 'A{59}'
        }

        It 'compares a privilege name exactly, so <Spelling> is not one of the five' -ForEach @(
            @{ Spelling = 'a name in lower case' }
            @{ Spelling = 'a name in upper case' }
            @{ Spelling = 'a name with a zero-width space' }
            @{ Spelling = 'a name with a trailing space' }
            @{ Spelling = 'a name with a leading space' }
            @{ Spelling = 'a name with a Cyrillic letter that looks like a Latin one' }
            @{ Spelling = 'a name cut short' }
        ) {
            $name = switch ($Spelling) {
                'a name in lower case' { 'sechangenotifyprivilege' }
                'a name in upper case' { 'SECHANGENOTIFYPRIVILEGE' }
                'a name with a zero-width space' { 'SeChangeNotifyPrivilege' + [char]0x200B }
                'a name with a trailing space' { 'SeChangeNotifyPrivilege ' }
                'a name with a leading space' { ' SeChangeNotifyPrivilege' }
                'a name with a Cyrillic letter that looks like a Latin one' { 'SeChangeNotifyPrivil' + [char]0x0435 + 'ge' }
                'a name cut short' { 'SeChangeNotifyPrivileg' }
            }
            Use-TokenFact -Fact (New-TokenFact -Privilege @(New-Privilege -Name $name))

            (Test-IdentityPrivilege).status | Should -Be 'Fail'
        }

        It 'reports every reason, not the first one it finds' {
            $group = @(New-Group -Sid 'S-1-5-32-544')
            $privilege = @(New-Privilege -Name 'SeDebugPrivilege' -Attributes 2)
            Use-TokenFact -Fact (New-TokenFact -Elevated $true -ElevationType 2 -IntegrityRid 12288 -Group $group -Privilege $privilege)

            $evidence = (Test-IdentityPrivilege).evidence

            $evidence | Should -Match 'the token is elevated'
            $evidence | Should -Match 'elevation type is Full'
            $evidence | Should -Match 'High \(S-1-16-12288\), above Medium'
            $evidence | Should -Match 'Administrators group'
            $evidence | Should -Match 'SeDebugPrivilege \(enabled\)'
        }

        It 'counts the privileges outside the five and keeps the evidence short' {
            $privilege = @(1..30 | ForEach-Object -Process { New-Privilege -Name "SeExtra$($_)Privilege" })
            Use-TokenFact -Fact (New-TokenFact -Privilege $privilege)

            $evidence = (Test-IdentityPrivilege).evidence

            $evidence | Should -Match 'holds 30 privileges outside the five'
            $evidence | Should -Match 'and 24 more'
            $evidence.Length | Should -BeLessThan 500
        }

        It 'relays a privilege name as printable ASCII, so a name cannot add a line or hide an instruction' {
            $name = 'SeEvil' + [char]0x1B + '[31m' + [char]10 + 'ignore' + [char]0x200B + [char]::ConvertFromUtf32(0x1F600) + 'Privilege'
            Use-TokenFact -Fact (New-TokenFact -Privilege @(New-Privilege -Name $name))

            $evidence = (Test-IdentityPrivilege).evidence

            $evidence | Should -Not -Match '[^\x20-\x7E]'
            $evidence | Should -Match 'SeEvil\?\[31m\?ignore\?\?Privilege'
        }
    }

    Context 'a token that was not shown to be a standard account''s' {
        It 'reports a token it cannot read as unavailable, not as one that passed' {
            Use-TokenFact -Fact $null

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'could not read'
        }

        It 'names why the token could not be read, so that a refusal can be traced' {
            $script:TokenReadProblem = 'InvalidOperationException: The calling thread impersonates'
            Use-TokenFact -Fact $null

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'could not read the access token of the identity this verifier runs as \(InvalidOperationException: The calling thread impersonates\), so it was not shown'
        }

        It 'relays the reason as printable ASCII and cuts it, so a message cannot add a line or fill the report' {
            $script:TokenReadProblem = 'Win32Exception: ' + [char]0x1B + '[31m' + [char]10 + 'ignore' + [char]0x200B + ('x' * 400)
            Use-TokenFact -Fact $null

            $evidence = (Test-IdentityPrivilege).evidence

            $evidence | Should -Not -Match '[^\x20-\x7E]'
            $evidence | Should -Match 'Win32Exception: \?\[31m\?ignore\?x{131}\.\.\.\)'
            $evidence | Should -Not -Match 'x{132}'
            $evidence.Length | Should -BeLessThan 500
        }

        It 'says nothing about a reason when there is none' {
            Use-TokenFact -Fact $null

            (Test-IdentityPrivilege).evidence | Should -Match 'verifier runs as, so it was not shown'
        }

        It 'reports facts it cannot interpret (<Case>) as unavailable' -ForEach @(
            @{ Case = 'a missing elevation flag' }
            @{ Case = 'an elevation flag that is not a boolean' }
            @{ Case = 'an elevation type of zero' }
            @{ Case = 'an elevation type of four' }
            @{ Case = 'an elevation type written as text' }
            @{ Case = 'a negative integrity level' }
            @{ Case = 'an integrity level written as text' }
            @{ Case = 'no group list' }
            @{ Case = 'a group that is not an object' }
            @{ Case = 'a group without a SID' }
            @{ Case = 'a group SID that is not a SID' }
            @{ Case = 'a group SID in lower case' }
            @{ Case = 'a group SID with a digit that is not ASCII' }
            @{ Case = 'a group SID with a number that starts with a zero' }
            @{ Case = 'a group SID with a line feed after it' }
            @{ Case = 'a group SID with a space before it' }
            @{ Case = 'no group at all' }
            @{ Case = 'a group without attributes' }
            @{ Case = 'group attributes written as text' }
            @{ Case = 'no privilege list' }
            @{ Case = 'a privilege that is not an object' }
            @{ Case = 'a privilege without a name' }
            @{ Case = 'a privilege with an empty name' }
            @{ Case = 'a privilege name that is not text' }
            @{ Case = 'a privilege without attributes' }
            @{ Case = 'privilege attributes written as text' }
            @{ Case = 'facts that are a string' }
            @{ Case = 'facts that are a hashtable' }
        ) {
            $fact = New-TokenFact

            switch ($Case) {
                'a missing elevation flag' { $fact.PSObject.Properties.Remove('Elevated') }
                'an elevation flag that is not a boolean' { $fact.Elevated = 'yes' }
                'an elevation type of zero' { $fact.ElevationType = 0 }
                'an elevation type of four' { $fact.ElevationType = 4 }
                'an elevation type written as text' { $fact.ElevationType = '1' }
                'a negative integrity level' { $fact.IntegrityRid = -1 }
                'an integrity level written as text' { $fact.IntegrityRid = 'High' }
                'no group list' { $fact.Group = $null }
                'a group that is not an object' { $fact.Group = @('S-1-1-0') }
                'a group without a SID' { $fact.Group = @([pscustomobject]@{ Attributes = [uint32]7 }) }
                'a group SID that is not a SID' { $fact.Group = @(New-Group -Sid 'Everyone') }
                'a group SID in lower case' { $fact.Group = @(New-Group -Sid 's-1-1-0') }
                'a group SID with a digit that is not ASCII' { $fact.Group = @(New-Group -Sid ('S-1-5-32-' + [char]0x0665 + [char]0x0664 + [char]0x0664)) }
                'a group SID with a number that starts with a zero' { $fact.Group = @(New-Group -Sid 'S-1-5-32-0544') }
                'a group SID with a line feed after it' { $fact.Group = @(New-Group -Sid ('S-1-5-32-544' + [char]10)) }
                'a group SID with a space before it' { $fact.Group = @(New-Group -Sid ' S-1-5-32-544') }
                'no group at all' { $fact.Group = @() }
                'a group without attributes' { $fact.Group = @([pscustomobject]@{ Sid = 'S-1-1-0' }) }
                'group attributes written as text' { $fact.Group = @([pscustomobject]@{ Sid = 'S-1-1-0'; Attributes = '7' }) }
                'no privilege list' { $fact.Privilege = $null }
                'a privilege that is not an object' { $fact.Privilege = @('SeChangeNotifyPrivilege') }
                'a privilege without a name' { $fact.Privilege = @([pscustomobject]@{ Attributes = [uint32]0 }) }
                'a privilege with an empty name' { $fact.Privilege = @(New-Privilege -Name '') }
                'a privilege name that is not text' { $fact.Privilege = @([pscustomobject]@{ Name = 5; Attributes = [uint32]0 }) }
                'a privilege without attributes' { $fact.Privilege = @([pscustomobject]@{ Name = 'SeChangeNotifyPrivilege' }) }
                'privilege attributes written as text' { $fact.Privilege = @([pscustomobject]@{ Name = 'SeChangeNotifyPrivilege'; Attributes = '2' }) }
                'facts that are a string' { $fact = 'a token' }
                'facts that are a hashtable' { $fact = @{ Elevated = $false; ElevationType = 1; IntegrityRid = 8192; Group = @(); Privilege = @() } }
            }

            Use-TokenFact -Fact $fact

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'could not be interpreted'
        }

        It 'is unavailable on a platform whose tokens it does not read, and does not try' {
            $script:OnWindows = $false

            $result = Test-IdentityPrivilege

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'Windows'
            Should -Invoke -CommandName 'Get-CallerTokenFact' -Times 0 -Exactly
        }
    }

    Context 'where the token comes from' {
        It 'reads the token once, so one read decides the whole result' {
            $null = Test-IdentityPrivilege

            Should -Invoke -CommandName 'Get-CallerTokenFact' -Times 1 -Exactly
        }

        It 'takes no parameter, so neither the profile nor the caller can say what the token holds' {
            $reference = @((Get-Command -Name 'Get-NoParameterReference').Parameters.Keys)

            @((Get-Command -Name 'Test-IdentityPrivilege').Parameters.Keys | Where-Object -FilterScript { $_ -notin $reference }) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Containment integrity level names' -Tag 'Unit' {
    It 'names <Rid> <Name>' -ForEach @(
        @{ Rid = 0; Name = 'Untrusted' }
        @{ Rid = 4096; Name = 'Low' }
        @{ Rid = 8192; Name = 'Medium' }
        @{ Rid = 8448; Name = 'Medium Plus' }
        @{ Rid = 12288; Name = 'High' }
        @{ Rid = 16384; Name = 'System' }
        @{ Rid = 20480; Name = 'Protected' }
        @{ Rid = 12345; Name = 'an unnamed level' }
    ) {
        Get-IntegrityLevelName -Rid $Rid | Should -Be $Name
    }
}

Describe 'Containment token facts' -Tag 'Unit' {
    # The native reader returns an object of public fields whose arrays line up, and the check reads
    # objects of the types it validates. The conversion is plain PowerShell, so it is tested here with
    # objects of the native shape, on every platform.
    BeforeAll {
        function script:New-Native {
            param(
                [Parameter()]
                [int]$Elevated = 0,

                [Parameter()]
                [int]$ElevationType = 1,

                [Parameter()]
                [int]$IntegrityRid = 8192,

                [Parameter()]
                [string[]]$GroupSid = @(),

                [Parameter()]
                [uint32[]]$GroupAttribute = @(),

                [Parameter()]
                [string[]]$PrivilegeName = @(),

                [Parameter()]
                [uint32[]]$PrivilegeAttribute = @()
            )

            return [pscustomobject]@{
                Elevated = $Elevated
                ElevationType = $ElevationType
                IntegrityRid = $IntegrityRid
                GroupSid = $GroupSid
                GroupAttribute = $GroupAttribute
                PrivilegeName = $PrivilegeName
                PrivilegeAttribute = $PrivilegeAttribute
            }
        }
    }

    It 'turns the native elevation flag <Native> into the boolean <Expected>' -ForEach @(
        @{ Native = 0; Expected = $false }
        @{ Native = 1; Expected = $true }
        @{ Native = 2; Expected = $true }
    ) {
        $fact = ConvertTo-TokenFact -Native (New-Native -Elevated $Native)

        $fact.Elevated | Should -BeOfType ([bool])
        $fact.Elevated | Should -Be $Expected
    }

    It 'keeps the elevation type and the integrity level as numbers' {
        $fact = ConvertTo-TokenFact -Native (New-Native -ElevationType 3 -IntegrityRid 12288)

        $fact.ElevationType | Should -BeOfType ([int])
        $fact.ElevationType | Should -Be 3
        $fact.IntegrityRid | Should -BeOfType ([int])
        $fact.IntegrityRid | Should -Be 12288
    }

    It 'pairs each group SID with its own attributes' {
        $fact = ConvertTo-TokenFact -Native (New-Native -GroupSid @('S-1-1-0', 'S-1-5-32-544') -GroupAttribute @(7, 16))

        @($fact.Group) | Should -HaveCount 2
        $fact.Group[0].Sid | Should -Be 'S-1-1-0'
        $fact.Group[0].Attributes | Should -Be 7
        $fact.Group[1].Sid | Should -Be 'S-1-5-32-544'
        $fact.Group[1].Attributes | Should -Be 16
        $fact.Group[1].Attributes | Should -BeOfType ([uint32])
    }

    It 'pairs each privilege name with its own attributes' {
        $fact = ConvertTo-TokenFact -Native (New-Native -PrivilegeName @('SeChangeNotifyPrivilege', 'SeDebugPrivilege') -PrivilegeAttribute @(3, 2))

        @($fact.Privilege) | Should -HaveCount 2
        $fact.Privilege[0].Name | Should -Be 'SeChangeNotifyPrivilege'
        $fact.Privilege[0].Attributes | Should -Be 3
        $fact.Privilege[1].Name | Should -Be 'SeDebugPrivilege'
        $fact.Privilege[1].Attributes | Should -Be 2
        $fact.Privilege[1].Attributes | Should -BeOfType ([uint32])
    }

    It 'keeps a single group and a single privilege as lists of one, and none as an empty list' {
        $one = ConvertTo-TokenFact -Native (New-Native -GroupSid @('S-1-1-0') -GroupAttribute @(7) -PrivilegeName @('SeChangeNotifyPrivilege') -PrivilegeAttribute @(3))
        $none = ConvertTo-TokenFact -Native (New-Native)

        $one.Group.GetType().IsArray | Should -BeTrue
        $one.Privilege.GetType().IsArray | Should -BeTrue
        $none.Group.GetType().IsArray | Should -BeTrue
        $none.Privilege.GetType().IsArray | Should -BeTrue
        @($none.Group) | Should -HaveCount 0
        @($none.Privilege) | Should -HaveCount 0
    }

    It 'gives facts that the check''s own validation accepts' {
        $fact = ConvertTo-TokenFact -Native (New-Native -Elevated 1 -ElevationType 2 -IntegrityRid 12288 -GroupSid @('S-1-5-32-544') -GroupAttribute @(15) -PrivilegeName @('SeDebugPrivilege') -PrivilegeAttribute @(2))

        Get-TokenFactProblem -Fact $fact | Should -BeNullOrEmpty
    }

    It 'accepts only an object of the shape the reader returns, so <Case> is not interpreted' -ForEach @(
        @{ Case = 'nothing' }
        @{ Case = 'a string' }
        @{ Case = 'a number' }
        @{ Case = 'a hashtable with the right keys' }
        @{ Case = 'an object of another type with the right properties' }
    ) {
        $fact = switch ($Case) {
            'nothing' { $null }
            'a string' { 'a token' }
            'a number' { 5 }
            'a hashtable with the right keys' { @{ Elevated = $false; ElevationType = 1; IntegrityRid = 8192; Group = @(); Privilege = @() } }
            'an object of another type with the right properties' {
                $typeName = 'TokenFactLike' + [guid]::NewGuid().ToString('N')
                Add-Type -TypeDefinition "public class $typeName { public bool Elevated = false; public int ElevationType = 1; public int IntegrityRid = 8192; public object[] Group = new object[0]; public object[] Privilege = new object[0]; }"
                New-Object -TypeName $typeName
            }
        }

        Get-TokenFactProblem -Fact $fact | Should -Be 'the facts are not an object'
    }
}

Describe 'Containment token reader bounds' -Tag 'Unit' {
    # The SIDs of a token structure lie in the buffer that holds it, after the array. A pointer that does not
    # is a structure that was misread, and following it could read memory that is not the token's, so it must
    # stop the read with an exception, which the reader turns into an unmeasured check. The method that reads
    # one SID is public so that a test can give it a buffer of its own.
    BeforeAll {
        if ($script:onWindows) {
            Initialize-NativeToken
        }

        # A buffer of the length given with the SID bytes written at the offset, zero elsewhere, and the pointer
        # to the SID handed to the script block with the buffer and its length.
        function script:Use-SidBuffer {
            param(
                [Parameter(Mandatory)]
                [byte[]]$SidByte,

                [Parameter(Mandatory)]
                [int]$Offset,

                [Parameter(Mandatory)]
                [int]$Length,

                [Parameter(Mandatory)]
                [scriptblock]$Action
            )

            $buffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($Length)

            try {
                for ($index = 0; $index -lt $Length; $index++) {
                    [System.Runtime.InteropServices.Marshal]::WriteByte($buffer, $index, 0)
                }

                for ($index = 0; $index -lt $SidByte.Length -and ($Offset + $index) -lt $Length; $index++) {
                    [System.Runtime.InteropServices.Marshal]::WriteByte($buffer, $Offset + $index, $SidByte[$index])
                }

                & $Action $buffer $Length ([System.IntPtr]::Add($buffer, $Offset))
            } finally {
                [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
            }
        }

        # S-1-5-32-544: revision 1, two sub-authorities, authority 5, then 32 and 544 in little-endian. The name
        # must differ from $script:AdministratorsSid, the constant of the verifier that the check reads:
        # variable names are case-insensitive, so a byte array under that name would replace the constant.
        $script:administratorsSidBytes = [byte[]]@(1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 32, 2, 0, 0)
    }

    It 'reads a SID that lies inside the buffer' -Skip:(-not $script:onWindows) {
        $text = Use-SidBuffer -SidByte $script:administratorsSidBytes -Offset 24 -Length 64 -Action {
            param($Buffer, $Length, $Pointer)

            $script:NativeToken::SidText($Buffer, $Length, $Pointer)
        }

        $text | Should -Be 'S-1-5-32-544'
    }

    It 'reads a SID that ends exactly at the end of the buffer' -Skip:(-not $script:onWindows) {
        $text = Use-SidBuffer -SidByte $script:administratorsSidBytes -Offset 48 -Length 64 -Action {
            param($Buffer, $Length, $Pointer)

            $script:NativeToken::SidText($Buffer, $Length, $Pointer)
        }

        $text | Should -Be 'S-1-5-32-544'
    }

    It 'refuses a pointer before the buffer' -Skip:(-not $script:onWindows) {
        {
            Use-SidBuffer -SidByte $script:administratorsSidBytes -Offset 24 -Length 64 -Action {
                param($Buffer, $Length)

                $script:NativeToken::SidText($Buffer, $Length, [System.IntPtr]::Subtract($Buffer, 8))
            }
        } | Should -Throw -ExpectedMessage '*outside the buffer*'
    }

    It 'refuses a pointer past the end of the buffer' -Skip:(-not $script:onWindows) {
        {
            Use-SidBuffer -SidByte $script:administratorsSidBytes -Offset 24 -Length 64 -Action {
                param($Buffer, $Length)

                $script:NativeToken::SidText($Buffer, $Length, [System.IntPtr]::Add($Buffer, 64))
            }
        } | Should -Throw -ExpectedMessage '*outside the buffer*'
    }

    It 'refuses a SID whose header does not fit before the end of the buffer' -Skip:(-not $script:onWindows) {
        {
            Use-SidBuffer -SidByte $script:administratorsSidBytes -Offset 24 -Length 64 -Action {
                param($Buffer, $Length)

                $script:NativeToken::SidText($Buffer, $Length, [System.IntPtr]::Add($Buffer, 57))
            }
        } | Should -Throw -ExpectedMessage '*outside the buffer*'
    }

    It 'refuses a SID whose sub-authorities run past the end of the buffer' -Skip:(-not $script:onWindows) {
        {
            Use-SidBuffer -SidByte $script:administratorsSidBytes -Offset 52 -Length 64 -Action {
                param($Buffer, $Length, $Pointer)

                $script:NativeToken::SidText($Buffer, $Length, $Pointer)
            }
        } | Should -Throw -ExpectedMessage '*does not fit*'
    }

    It 'refuses a SID that claims more sub-authorities than a SID can have' -Skip:(-not $script:onWindows) {
        $claims = [byte[]]@(1, 16, 0, 0, 0, 0, 0, 5)

        {
            Use-SidBuffer -SidByte $claims -Offset 8 -Length 256 -Action {
                param($Buffer, $Length, $Pointer)

                $script:NativeToken::SidText($Buffer, $Length, $Pointer)
            }
        } | Should -Throw -ExpectedMessage '*does not fit*'
    }
}

Describe 'Containment token structures read from crafted buffers' -Tag 'Unit' {
    # The lists of a token are read from a buffer the operating system fills: a count, an array whose entries
    # point at SIDs, and the SIDs after the array. The parsers are public so that a test can give one a buffer of
    # its own, with a count, a length or a pointer that no real token has, and see that it stops with an
    # exception, which the reader turns into an unmeasured check, and does not read what is not the token's.
    BeforeAll {
        if ($script:onWindows) {
            Initialize-NativeToken
        }

        # The array of a TOKEN_GROUPS starts on the alignment of a pointer, and an entry is a pointer and a DWORD
        # rounded up to the alignment of a pointer.
        $script:craftedFirst = [System.IntPtr]::Size
        $script:craftedStride = 2 * [System.IntPtr]::Size

        # S-1-1-0, S-1-5-32-544 and S-1-16-8192 as the operating system writes them.
        $script:craftedEveryoneSid = [byte[]]@(1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0)
        $script:craftedAdministratorsSid = [byte[]]@(1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 32, 2, 0, 0)
        $script:craftedMediumLabel = [byte[]]@(1, 1, 0, 0, 0, 0, 0, 16, 0, 32, 0, 0)

        # A zeroed buffer of the length given, handed to the script block with the length, and freed afterwards.
        function script:Use-CraftedBuffer {
            param(
                [Parameter(Mandatory)]
                [int]$Length,

                [Parameter(Mandatory)]
                [scriptblock]$Action
            )

            $buffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($Length)

            try {
                for ($index = 0; $index -lt $Length; $index++) {
                    [System.Runtime.InteropServices.Marshal]::WriteByte($buffer, $index, 0)
                }

                & $Action $buffer $Length
            } finally {
                [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
            }
        }

        function script:Write-CraftedByte {
            param(
                [Parameter(Mandatory)]
                [System.IntPtr]$Buffer,

                [Parameter(Mandatory)]
                [int]$Offset,

                [Parameter(Mandatory)]
                [byte[]]$Byte
            )

            [System.Runtime.InteropServices.Marshal]::Copy($Byte, 0, [System.IntPtr]::Add($Buffer, $Offset), $Byte.Length)
        }

        # One entry of the array of a TOKEN_GROUPS: a pointer to a SID, and a DWORD of attributes.
        function script:Write-CraftedGroup {
            param(
                [Parameter(Mandatory)]
                [System.IntPtr]$Buffer,

                [Parameter(Mandatory)]
                [int]$Index,

                [Parameter(Mandatory)]
                [int]$SidOffset,

                [Parameter(Mandatory)]
                [int]$Attributes
            )

            $at = $script:craftedFirst + $Index * $script:craftedStride

            [System.Runtime.InteropServices.Marshal]::WriteIntPtr($Buffer, $at, [System.IntPtr]::Add($Buffer, $SidOffset))
            [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, $at + [System.IntPtr]::Size, $Attributes)
        }

        # One entry of the array of a TOKEN_PRIVILEGES: the two parts of a LUID and a DWORD of attributes, 12 bytes.
        function script:Write-CraftedPrivilege {
            param(
                [Parameter(Mandatory)]
                [System.IntPtr]$Buffer,

                [Parameter(Mandatory)]
                [int]$Index,

                [Parameter(Mandatory)]
                [int]$Luid,

                [Parameter(Mandatory)]
                [int]$Attributes
            )

            $at = 4 + $Index * 12

            [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, $at, $Luid)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, $at + 4, 0)
            [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, $at + 8, $Attributes)
        }

        function script:New-NativeFact {
            return [System.Activator]::CreateInstance($script:NativeToken.GetNestedType('Fact'))
        }
    }

    Context 'the groups' {
        It 'reads each group with its own SID and attributes' -Skip:(-not $script:onWindows) {
            $fact = Use-CraftedBuffer -Length 128 -Action {
                param($Buffer, $Length)

                $sidOffset = $script:craftedFirst + 2 * $script:craftedStride

                [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, 2)
                Write-CraftedGroup -Buffer $Buffer -Index 0 -SidOffset $sidOffset -Attributes 7
                Write-CraftedGroup -Buffer $Buffer -Index 1 -SidOffset ($sidOffset + 12) -Attributes 16
                Write-CraftedByte -Buffer $Buffer -Offset $sidOffset -Byte $script:craftedEveryoneSid
                Write-CraftedByte -Buffer $Buffer -Offset ($sidOffset + 12) -Byte $script:craftedAdministratorsSid

                $read = New-NativeFact
                $script:NativeToken::ParseGroups($Buffer, $Length, $read)
                $read
            }

            @($fact.GroupSid) | Should -Be @('S-1-1-0', 'S-1-5-32-544')
            @($fact.GroupAttribute) | Should -Be @(7, 16)
        }

        It 'reads a list of no group, whose array is empty and ends at the end of the buffer' -Skip:(-not $script:onWindows) {
            $fact = Use-CraftedBuffer -Length $script:craftedFirst -Action {
                param($Buffer, $Length)

                $read = New-NativeFact
                $script:NativeToken::ParseGroups($Buffer, $Length, $read)
                $read
            }

            $fact.GroupSid.Length | Should -Be 0
            $fact.GroupAttribute.Length | Should -Be 0
        }

        It 'refuses a count of <Count>, which no array of the buffer can hold' -Skip:(-not $script:onWindows) -ForEach @(
            @{ Count = 1000 }
            @{ Count = -1 }
            @{ Count = 2147483647 }
        ) {
            {
                Use-CraftedBuffer -Length 64 -Action {
                    param($Buffer, $Length)

                    [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, $Count)
                    $script:NativeToken::ParseGroups($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw -ExpectedMessage '*does not fit*'
        }

        It 'refuses an array that ends one byte past the end of the buffer' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length ($script:craftedFirst + $script:craftedStride - 1) -Action {
                    param($Buffer, $Length)

                    [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, 1)
                    $script:NativeToken::ParseGroups($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw -ExpectedMessage '*does not fit*'
        }

        It 'refuses a buffer too short to hold the count' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 3 -Action {
                    param($Buffer, $Length)

                    $script:NativeToken::ParseGroups($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw -ExpectedMessage '*too short*'
        }

        It 'refuses a SID that lies in the array and not after it' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 128 -Action {
                    param($Buffer, $Length)

                    # A well-formed SID that starts inside the entry, after the pointer that names it.
                    $inside = $script:craftedFirst + [System.IntPtr]::Size

                    [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, 1)
                    Write-CraftedGroup -Buffer $Buffer -Index 0 -SidOffset $inside -Attributes 7
                    Write-CraftedByte -Buffer $Buffer -Offset $inside -Byte $script:craftedEveryoneSid
                    $script:NativeToken::ParseGroups($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw -ExpectedMessage '*after the structure*'
        }
    }

    Context 'the privileges' {
        It 'reads each privilege with its own name and attributes' -Skip:(-not $script:onWindows) {
            # 23, 20 and 19 are the numbers the system gives SeChangeNotifyPrivilege, SeDebugPrivilege and SeShutdownPrivilege.
            $fact = Use-CraftedBuffer -Length 64 -Action {
                param($Buffer, $Length)

                [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, 3)
                Write-CraftedPrivilege -Buffer $Buffer -Index 0 -Luid 23 -Attributes 3
                Write-CraftedPrivilege -Buffer $Buffer -Index 1 -Luid 20 -Attributes 2
                Write-CraftedPrivilege -Buffer $Buffer -Index 2 -Luid 19 -Attributes 0

                $read = New-NativeFact
                $script:NativeToken::ParsePrivileges($Buffer, $Length, $read)
                $read
            }

            @($fact.PrivilegeName) | Should -Be @('SeChangeNotifyPrivilege', 'SeDebugPrivilege', 'SeShutdownPrivilege')
            @($fact.PrivilegeAttribute) | Should -Be @(3, 2, 0)
        }

        It 'reads a list of no privilege, whose array is empty and ends at the end of the buffer' -Skip:(-not $script:onWindows) {
            $fact = Use-CraftedBuffer -Length 4 -Action {
                param($Buffer, $Length)

                $read = New-NativeFact
                $script:NativeToken::ParsePrivileges($Buffer, $Length, $read)
                $read
            }

            $fact.PrivilegeName.Length | Should -Be 0
        }

        It 'reads an array that ends exactly at the end of the buffer' -Skip:(-not $script:onWindows) {
            $fact = Use-CraftedBuffer -Length 16 -Action {
                param($Buffer, $Length)

                [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, 1)
                Write-CraftedPrivilege -Buffer $Buffer -Index 0 -Luid 23 -Attributes 3

                $read = New-NativeFact
                $script:NativeToken::ParsePrivileges($Buffer, $Length, $read)
                $read
            }

            @($fact.PrivilegeName) | Should -Be @('SeChangeNotifyPrivilege')
        }

        It 'refuses a count of <Count>, which no array of the buffer can hold' -Skip:(-not $script:onWindows) -ForEach @(
            @{ Count = 100 }
            @{ Count = -1 }
            @{ Count = 2147483647 }
        ) {
            {
                Use-CraftedBuffer -Length 40 -Action {
                    param($Buffer, $Length)

                    [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, $Count)
                    $script:NativeToken::ParsePrivileges($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw -ExpectedMessage '*does not fit*'
        }

        It 'refuses an array that ends one byte past the end of the buffer' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 15 -Action {
                    param($Buffer, $Length)

                    [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, 1)
                    Write-CraftedPrivilege -Buffer $Buffer -Index 0 -Luid 23 -Attributes 3
                    $script:NativeToken::ParsePrivileges($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw -ExpectedMessage '*does not fit*'
        }

        It 'refuses a buffer too short to hold the count' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 3 -Action {
                    param($Buffer, $Length)

                    $script:NativeToken::ParsePrivileges($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw -ExpectedMessage '*too short*'
        }

        It 'refuses a privilege that has no name, and does not read it as an empty one' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 32 -Action {
                    param($Buffer, $Length)

                    [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, 0, 1)
                    Write-CraftedPrivilege -Buffer $Buffer -Index 0 -Luid 99999 -Attributes 0
                    $script:NativeToken::ParsePrivileges($Buffer, $Length, (New-NativeFact))
                }
            } | Should -Throw
        }
    }

    Context 'the integrity label' {
        It 'reads the level of a label whose SID follows it' -Skip:(-not $script:onWindows) {
            $rid = Use-CraftedBuffer -Length 64 -Action {
                param($Buffer, $Length)

                $sidOffset = $script:craftedStride

                [System.Runtime.InteropServices.Marshal]::WriteIntPtr($Buffer, 0, [System.IntPtr]::Add($Buffer, $sidOffset))
                [System.Runtime.InteropServices.Marshal]::WriteInt32($Buffer, [System.IntPtr]::Size, 96)
                Write-CraftedByte -Buffer $Buffer -Offset $sidOffset -Byte $script:craftedMediumLabel

                $script:NativeToken::ParseIntegrityRid($Buffer, $Length)
            }

            $rid | Should -Be 8192
        }

        It 'refuses a SID that is not an integrity level' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 64 -Action {
                    param($Buffer, $Length)

                    [System.Runtime.InteropServices.Marshal]::WriteIntPtr($Buffer, 0, [System.IntPtr]::Add($Buffer, $script:craftedStride))
                    Write-CraftedByte -Buffer $Buffer -Offset $script:craftedStride -Byte $script:craftedEveryoneSid
                    $script:NativeToken::ParseIntegrityRid($Buffer, $Length)
                }
            } | Should -Throw -ExpectedMessage '*not an integrity SID*'
        }

        It 'refuses an integrity level of more than one sub-authority' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 64 -Action {
                    param($Buffer, $Length)

                    $label = [byte[]]@(1, 2, 0, 0, 0, 0, 0, 16, 0, 32, 0, 0, 5, 0, 0, 0)

                    [System.Runtime.InteropServices.Marshal]::WriteIntPtr($Buffer, 0, [System.IntPtr]::Add($Buffer, $script:craftedStride))
                    Write-CraftedByte -Buffer $Buffer -Offset $script:craftedStride -Byte $label
                    $script:NativeToken::ParseIntegrityRid($Buffer, $Length)
                }
            } | Should -Throw
        }

        It 'refuses a SID that lies in the label and not after it' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 64 -Action {
                    param($Buffer, $Length)

                    [System.Runtime.InteropServices.Marshal]::WriteIntPtr($Buffer, 0, $Buffer)
                    $script:NativeToken::ParseIntegrityRid($Buffer, $Length)
                }
            } | Should -Throw -ExpectedMessage '*after the structure*'
        }

        It 'refuses a buffer too short to hold the label' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length ($script:craftedStride - 1) -Action {
                    param($Buffer, $Length)

                    $script:NativeToken::ParseIntegrityRid($Buffer, $Length)
                }
            } | Should -Throw -ExpectedMessage '*too short*'
        }
    }

    Context 'the SID that follows a structure' {
        It 'reads a SID that starts exactly where the structure before it ends' -Skip:(-not $script:onWindows) {
            $text = Use-CraftedBuffer -Length 64 -Action {
                param($Buffer, $Length)

                Write-CraftedByte -Buffer $Buffer -Offset 40 -Byte $script:craftedAdministratorsSid
                $script:NativeToken::SidText($Buffer, $Length, [System.IntPtr]::Add($Buffer, 40), 40)
            }

            $text | Should -Be 'S-1-5-32-544'
        }

        It 'refuses a SID that starts one byte before the end of the structure before it' -Skip:(-not $script:onWindows) {
            {
                Use-CraftedBuffer -Length 64 -Action {
                    param($Buffer, $Length)

                    Write-CraftedByte -Buffer $Buffer -Offset 39 -Byte $script:craftedAdministratorsSid
                    $script:NativeToken::SidText($Buffer, $Length, [System.IntPtr]::Add($Buffer, 39), 40)
                }
            } | Should -Throw -ExpectedMessage '*after the structure*'
        }
    }

    Context 'the buffer of a read' {
        # The first buffer of a read is 512 bytes, which holds every list of a token here, so a read never grows
        # it. The public method that takes the size of the first buffer makes it grow, and the answer must not
        # depend on it.
        It 'reads the same token when its first buffer holds <FirstSize> bytes, and grows the buffer when it must' -Skip:(-not $script:onWindows) -ForEach @(
            @{ FirstSize = 1; MustGrow = $true }
            @{ FirstSize = 16; MustGrow = $true }
            @{ FirstSize = 100; MustGrow = $true }
            @{ FirstSize = 4096; MustGrow = $false }
        ) {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

            try {
                $handle = $identity.AccessToken.DangerousGetHandle()
                $whole = $script:NativeToken::Read($handle)
                $before = $script:NativeToken::Growths
                $sized = $script:NativeToken::Read($handle, $FirstSize)
                $grown = $script:NativeToken::Growths - $before
            } finally {
                $identity.Dispose()
            }

            if ($MustGrow) {
                $grown | Should -BeGreaterThan 0 -Because 'a first buffer of that size cannot hold the groups of a token'
            }

            $sized.Elevated | Should -Be $whole.Elevated
            $sized.ElevationType | Should -Be $whole.ElevationType
            $sized.IntegrityRid | Should -Be $whole.IntegrityRid
            ($sized.GroupSid -join ',') | Should -Be ($whole.GroupSid -join ',')
            ($sized.GroupAttribute -join ',') | Should -Be ($whole.GroupAttribute -join ',')
            ($sized.PrivilegeName -join ',') | Should -Be ($whole.PrivilegeName -join ',')
            ($sized.PrivilegeAttribute -join ',') | Should -Be ($whole.PrivilegeAttribute -join ',')
        }

        It 'refuses a first buffer of <FirstSize> bytes' -Skip:(-not $script:onWindows) -ForEach @(
            @{ FirstSize = 0 }
            @{ FirstSize = -5 }
            @{ FirstSize = 1048576 }
        ) {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

            try {
                $handle = $identity.AccessToken.DangerousGetHandle()

                { $script:NativeToken::Read($handle, $FirstSize) } | Should -Throw
            } finally {
                $identity.Dispose()
            }
        }

        It 'refuses a handle that is not a token' -Skip:(-not $script:onWindows) {
            { $script:NativeToken::Read([System.IntPtr]::Zero) } | Should -Throw
        }
    }
}

Describe 'Containment token reader and a thread that impersonates' -Tag 'Unit' {
    # The check reads the token of the process, which every program the verifier starts inherits. The binding
    # and the probes that ask for access answer for the thread. They are one identity until the thread
    # impersonates, and then the token read would not be the one they measured, so the read refuses.
    BeforeAll {
        if ($script:onWindows) {
            Initialize-NativeToken
        }

        # Runs the script block on this thread while it impersonates a copy of the token of this process.
        function script:Use-Impersonation {
            param(
                [Parameter(Mandatory)]
                [scriptblock]$Action
            )

            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

            try {
                [System.Security.Principal.WindowsIdentity]::RunImpersonated($identity.AccessToken, [System.Action]$Action)
            } finally {
                $identity.Dispose()
            }
        }
    }

    It 'sees no impersonation on a thread that does not impersonate' -Skip:(-not $script:onWindows) {
        $script:NativeToken::ThreadImpersonates() | Should -BeFalse
    }

    It 'sees a thread that impersonates, and sees it end' -Skip:(-not $script:onWindows) {
        $script:whileImpersonating = $null

        Use-Impersonation -Action { $script:whileImpersonating = $script:NativeToken::ThreadImpersonates() }

        $script:whileImpersonating | Should -BeTrue
        $script:NativeToken::ThreadImpersonates() | Should -BeFalse -Because 'the impersonation ended with the block'
    }

    It 'does not read the token of the process while the thread impersonates, and reads it again afterwards' -Skip:(-not $script:onWindows) {
        $script:refusal = $null

        Use-Impersonation -Action {
            try {
                $null = $script:NativeToken::ReadProcess()
            } catch {
                $script:refusal = $_.Exception.Message
            }
        }

        $script:refusal | Should -Match 'impersonates'
        $script:NativeToken::ReadProcess() | Should -Not -BeNullOrEmpty
    }

    It 'turns an impersonating thread into an unmeasured check that says why' -Skip:(-not $script:onWindows) {
        $script:impersonatedResult = $null
        $script:impersonatedFact = 'unset'

        Use-Impersonation -Action {
            $script:impersonatedFact = Get-CallerTokenFact
            $script:impersonatedResult = Test-IdentityPrivilege
        }

        $script:impersonatedFact | Should -BeNullOrEmpty
        $script:impersonatedResult.status | Should -Be 'Unavailable'
        $script:impersonatedResult.evidence | Should -Match 'could not read the access token of the identity this verifier runs as \(InvalidOperationException: The calling thread impersonates, so the token'
    }
}

Describe 'Containment token reader on real filtered tokens' -Tag 'Unit' {
    BeforeAll {
        # Tokens the operating system makes from the token of this process with CreateRestrictedToken, read by
        # handle: nothing impersonates, and nothing about the running process changes. LUA_TOKEN does what the
        # user account control does for the filtered half of an administrator's token: the Administrators group
        # turns deny-only and every privilege but the five that a filtered token keeps is removed. The integrity
        # level is lowered to Medium, as a filtered token has it, so that the token is one that every probe that
        # asks for access reads as a standard account's. No test host here runs as a standard account, and a
        # filtered token is refused for its Administrators group, so this is the nearest real token to the Pass,
        # which only the facts of a seam reach: a throwaway local account read through LogonUser would close that.
        # The question that $script:adminHost answers when the file is discovered. The variables of the top of
        # this file do not exist when the blocks run (the constants of the verifier script, which the
        # BeforeAll above loads, are what define $script:onWindows then), so a block that must decide asks
        # again, from the platform itself and not from a variable a test may have changed.
        function script:Test-AdministratorHost {
            $windows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

            return ($windows -and [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
        }

        if (Test-AdministratorHost) {
            $helperName = 'ContainmentTokenTest' + [guid]::NewGuid().ToString('N')

            Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class $helperName
{
    [StructLayout(LayoutKind.Sequential)]
    private struct SidAndAttributes
    {
        public IntPtr Sid;
        public uint Attributes;
    }

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool CreateRestrictedToken(IntPtr existing, uint flags, uint disableSidCount, IntPtr sidsToDisable, uint deletePrivilegeCount, IntPtr privilegesToDelete, uint restrictedSidCount, IntPtr sidsToRestrict, out IntPtr newToken);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool SetTokenInformation(IntPtr token, int informationClass, IntPtr information, int length);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool ConvertStringSidToSidW(string text, out IntPtr sid);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    // A token made from the token of this process. The access asked for is TOKEN_DUPLICATE, TOKEN_QUERY and
    // TOKEN_ADJUST_DEFAULT, the last so that the integrity level can be lowered.
    public static IntPtr Restrict(uint flags)
    {
        IntPtr process;

        if (!OpenProcessToken(GetCurrentProcess(), 0x8A, out process))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        try
        {
            IntPtr restricted;

            if (!CreateRestrictedToken(process, flags, 0, IntPtr.Zero, 0, IntPtr.Zero, 0, IntPtr.Zero, out restricted))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            return restricted;
        }
        finally
        {
            CloseHandle(process);
        }
    }

    public static void LowerIntegrity(IntPtr token, string sidText)
    {
        IntPtr sid;

        if (!ConvertStringSidToSidW(sidText, out sid))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        try
        {
            SidAndAttributes label = new SidAndAttributes();
            label.Sid = sid;
            label.Attributes = 0x20;

            int size = Marshal.SizeOf(typeof(SidAndAttributes));
            IntPtr buffer = Marshal.AllocHGlobal(size);

            try
            {
                Marshal.StructureToPtr(label, buffer, false);

                if (!SetTokenInformation(token, 25, buffer, size))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            LocalFree(sid);
        }
    }

    public static void Close(IntPtr token)
    {
        CloseHandle(token);
    }
}
"@

            $script:tokenHelper = $helperName -as [type]
            Initialize-NativeToken
        }

        # The facts of one restricted token, and what the operating system says about its membership of the
        # Administrators role, which it answers from the token on its own path.
        function script:Get-RestrictedToken {
            param(
                [Parameter(Mandatory)]
                [uint32]$Flag,

                [Parameter()]
                [AllowEmptyString()]
                [string]$Integrity = ''
            )

            $token = $script:tokenHelper::Restrict($Flag)

            try {
                if ($Integrity) {
                    $script:tokenHelper::LowerIntegrity($token, $Integrity)
                }

                $identity = [System.Security.Principal.WindowsIdentity]::new($token)

                try {
                    $inRole = [System.Security.Principal.WindowsPrincipal]::new($identity).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
                } finally {
                    $identity.Dispose()
                }

                return [pscustomobject]@{
                    Fact = (ConvertTo-TokenFact -Native ($script:NativeToken::Read($token)))
                    InAdministratorsRole = $inRole
                }
            } finally {
                $script:tokenHelper::Close($token)
            }
        }
    }

    It 'reads a real filtered administrator token: the Administrators group deny-only, and the five privileges of a standard account' -Skip:(-not $script:adminHost) {
        $token = Get-RestrictedToken -Flag 0x4 -Integrity 'S-1-16-8192'
        $fact = $token.Fact

        $fact.Elevated | Should -BeFalse
        $fact.IntegrityRid | Should -Be 0x2000
        $token.InAdministratorsRole | Should -BeFalse -Because 'the operating system does not count a deny-only group as membership'
        $administrators = @($fact.Group | Where-Object -FilterScript { $_.Sid -ceq 'S-1-5-32-544' })
        $administrators | Should -HaveCount 1
        ($administrators[0].Attributes -band 0x10) | Should -Not -Be 0
        ($administrators[0].Attributes -band 0x4) | Should -Be 0
        @($fact.Privilege.Name | Sort-Object) | Should -Be @('SeChangeNotifyPrivilege', 'SeIncreaseWorkingSetPrivilege', 'SeShutdownPrivilege', 'SeTimeZonePrivilege', 'SeUndockPrivilege')
    }

    It 'refuses that token for its Administrators group alone, though no probe that asks for access can tell it from a standard account''s' -Skip:(-not $script:adminHost) {
        Use-TokenFact -Fact (Get-RestrictedToken -Flag 0x4 -Integrity 'S-1-16-8192').Fact

        $result = Test-IdentityPrivilege

        $result.status | Should -Be 'Fail' -Because $result.evidence
        $result.evidence | Should -Match ([regex]::Escape('the Administrators group (S-1-5-32-544) is in the token, deny-only'))
        $result.evidence | Should -Not -Match 'elevated|above Medium|outside the five|elevation type'
    }

    It 'refuses a real administrator token that kept one privilege, for its enabled Administrators group' -Skip:(-not $script:adminHost) {
        $token = Get-RestrictedToken -Flag 0x1

        $token.Fact.Privilege.Name | Should -Be 'SeChangeNotifyPrivilege'
        $token.InAdministratorsRole | Should -BeTrue
        Use-TokenFact -Fact $token.Fact

        $result = Test-IdentityPrivilege

        $result.status | Should -Be 'Fail' -Because $result.evidence
        $result.evidence | Should -Match ([regex]::Escape('the Administrators group (S-1-5-32-544) is in the token, enabled'))
        $result.evidence | Should -Not -Match 'outside the five'
    }
}

Describe 'Containment token reader' -Tag 'Unit' {
    BeforeAll {
        # The facts of the process that runs these tests, read once. Every case below compares what the
        # reader says with an oracle that does not use the reader: whoami reads the token on its own path.
        function script:Get-WhoamiPrivilege {
            return @(& (Join-Path $env:SystemRoot 'System32\whoami.exe') /priv /fo csv /nh | ConvertFrom-Csv -Header 'Name', 'Description', 'State')
        }

        function script:Get-WhoamiGroup {
            return @(& (Join-Path $env:SystemRoot 'System32\whoami.exe') /groups /fo csv /nh | ConvertFrom-Csv -Header 'Name', 'Type', 'Sid', 'Attributes')
        }

        $script:realFact = if ($script:onWindows) { Get-CallerTokenFact } else { $null }
    }

    It 'reads the token of the running process' -Skip:(-not $script:onWindows) {
        $script:realFact | Should -Not -BeNullOrEmpty -Because 'the native reader could not be defined or the token could not be read'
    }

    It 'returns facts of the types the check reads' -Skip:(-not $script:onWindows) {
        $script:realFact.Elevated | Should -BeOfType ([bool])
        $script:realFact.ElevationType | Should -BeOfType ([int])
        $script:realFact.IntegrityRid | Should -BeOfType ([int])
        $script:realFact.Group.Count | Should -BeGreaterThan 0
        $script:realFact.Group[0].Sid | Should -BeOfType ([string])
        $script:realFact.Group[0].Attributes | Should -BeOfType ([uint32])
        $script:realFact.Privilege.Count | Should -BeGreaterThan 0
        $script:realFact.Privilege[0].Name | Should -BeOfType ([string])
        $script:realFact.Privilege[0].Attributes | Should -BeOfType ([uint32])
    }

    It 'reports the elevation that the runtime reports' -Skip:(-not ($script:onWindows -and $script:hasRuntimeElevation)) {
        $script:realFact.Elevated | Should -Be ([System.Environment]::IsPrivilegedProcess)
    }

    It 'reports an elevation type that agrees with the elevation flag' -Skip:(-not $script:onWindows) {
        # Full is the elevated half of a split token and Limited the filtered half; Default is either, so a
        # token of that type, which is every token a host here has, says nothing about the flag.
        if ($script:realFact.ElevationType -eq 1) {
            Set-ItResult -Skipped -Because 'the elevation type of this token is Default, which holds for an elevated and a filtered flag alike'
            return
        }

        $script:realFact.Elevated | Should -Be ($script:realFact.ElevationType -eq 2)
    }

    It 'reports the privileges that whoami reports, by name' -Skip:(-not $script:onWindows) {
        $expected = @((Get-WhoamiPrivilege).Name | Sort-Object)

        @($script:realFact.Privilege.Name | Sort-Object) | Should -Be $expected
    }

    It 'reports whether each privilege is enabled the way whoami does' -Skip:(-not $script:onWindows) {
        $row = @(Get-WhoamiPrivilege | Where-Object -FilterScript { $_.State -in 'Enabled', 'Disabled' })

        if ($row.Count -eq 0) {
            Set-ItResult -Skipped -Because 'whoami writes the state in the language of this machine'
            return
        }

        foreach ($entry in $row) {
            $held = @($script:realFact.Privilege | Where-Object -FilterScript { $_.Name -ceq $entry.Name })

            $held | Should -HaveCount 1 -Because $entry.Name
            (($held[0].Attributes -band 2) -ne 0) | Should -Be ($entry.State -eq 'Enabled') -Because $entry.Name
        }
    }

    It 'reports every group that whoami and the runtime report, and no group besides the logon session and the integrity label' -Skip:(-not $script:onWindows) {
        # Neither oracle is the whole list. whoami hides the primary group and the logon session, and the
        # runtime lists only the enabled groups and leaves out the logon session and the integrity label.
        # Between them they leave for the token alone the logon session, which whoami names with /logonid.
        $reader = @($script:realFact.Group.Sid)
        $whoami = @((Get-WhoamiGroup).Sid)
        $runtime = @([System.Security.Principal.WindowsIdentity]::GetCurrent().Groups | ForEach-Object -Process { $_.Value })
        $logon = @(& (Join-Path $env:SystemRoot 'System32\whoami.exe') /logonid | ForEach-Object -Process { $_.Trim() })

        foreach ($sid in $whoami) {
            $reader | Should -Contain $sid -Because "whoami lists $sid"
        }

        foreach ($sid in $runtime) {
            $reader | Should -Contain $sid -Because "the runtime lists $sid"
        }

        $unexplained = @($reader | Where-Object -FilterScript { $_ -notin $whoami -and $_ -notin $runtime -and $_ -notin $logon })

        $unexplained | Should -BeNullOrEmpty -Because 'the reader lists a group that nothing else reports'
    }

    It 'reports the attributes of each group the way whoami spells them' -Skip:(-not $script:onWindows) {
        $row = @(Get-WhoamiGroup | Where-Object -FilterScript { $_.Attributes -match 'Enabled group|Group used for deny only|Mandatory group' })

        if ($row.Count -eq 0) {
            Set-ItResult -Skipped -Because 'whoami writes the attributes in the language of this machine'
            return
        }

        foreach ($entry in $row) {
            $held = @($script:realFact.Group | Where-Object -FilterScript { $_.Sid -ceq $entry.Sid })

            $held | Should -HaveCount 1 -Because $entry.Sid
            (($held[0].Attributes -band 0x1) -ne 0) | Should -Be ($entry.Attributes -match 'Mandatory group') -Because "$($entry.Sid) mandatory"
            (($held[0].Attributes -band 0x4) -ne 0) | Should -Be ($entry.Attributes -match 'Enabled group') -Because "$($entry.Sid) enabled"
            (($held[0].Attributes -band 0x8) -ne 0) | Should -Be ($entry.Attributes -match 'Group owner') -Because "$($entry.Sid) owner"
            (($held[0].Attributes -band 0x10) -ne 0) | Should -Be ($entry.Attributes -match 'Group used for deny only') -Because "$($entry.Sid) deny-only"
        }
    }

    It 'reports the integrity level that whoami reports' -Skip:(-not $script:onWindows) {
        $label = @((Get-WhoamiGroup).Sid | Where-Object -FilterScript { $_ -like 'S-1-16-*' })

        $label | Should -HaveCount 1
        $script:realFact.IntegrityRid | Should -Be ([int]($label[0] -replace '^S-1-16-', ''))
    }

    It 'returns nothing, and does not throw, when the native reader cannot be defined' -Skip:(-not $script:onWindows) {
        # A host that refuses Add-Type (constrained language, application control) must end in an
        # unmeasured check and not in a stack trace.
        Mock -CommandName 'Initialize-NativeToken' -MockWith { throw 'Cannot add type: language mode refuses it' }

        Get-CallerTokenFact | Should -BeNullOrEmpty
        $script:TokenReadProblem | Should -Match 'language mode refuses it'
    }

    It 'clears the reason of an earlier failure when a read works' -Skip:(-not $script:onWindows) {
        $script:TokenReadProblem = 'left over from a read that failed'

        Get-CallerTokenFact | Should -Not -BeNullOrEmpty
        $script:TokenReadProblem | Should -BeNullOrEmpty
    }

    It 'does not take its reader from a type the session defined under the name the script uses' -Skip:(-not $script:onWindows) {
        # In a child process, so that the decoy is there before the script's own type is defined, whatever
        # ran earlier in this one. Its facts are impossible for a real token: elevation type 99.
        $command = @"
Add-Type -TypeDefinition 'public static class ContainmentToken { public sealed class Fact { public int Elevated = 0; public int ElevationType = 99; public int IntegrityRid = 123456; public string[] GroupSid = new string[0]; public uint[] GroupAttribute = new uint[0]; public string[] PrivilegeName = new string[0]; public uint[] PrivilegeAttribute = new uint[0]; } public static Fact Read(System.IntPtr token) { return new Fact(); } public static Fact ReadProcess() { return new Fact(); } }'
`$script:OnWindows = `$true
. '$($script:repoRoot)/tests/Helpers/ScriptFunction.ps1'
. (Get-ScriptFunctionDefinition -Path '$($script:verifierScript)' -Name @('Initialize-NativeToken', 'ConvertTo-TokenFact', 'Get-CallerTokenFact'))
(Get-CallerTokenFact).ElevationType
"@

        $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command 2>&1

        ($output | Out-String).Trim() | Should -BeIn @('1', '2', '3') -Because 'a type of an old name must not answer for the token'
    }

    It 'defines its type once, under a name made for this process alone' -Skip:(-not $script:onWindows) {
        Initialize-NativeToken
        $first = $script:NativeToken
        Initialize-NativeToken

        $script:NativeToken | Should -Be $first
        $first.Name | Should -Match '^ContainmentToken[0-9a-f]{32}$'
    }
}
