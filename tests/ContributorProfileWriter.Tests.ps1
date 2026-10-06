<#
    Writers of the contributor-profile Skill (Decision record 0028): Set,
    Export, Import with every merge rule, Remove, the registration file and its
    two-phase record, the diagnosis report, and the rule that no Familiarity
    level ever lands under a git working tree.
#>

BeforeDiscovery {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
    $script:isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:gitAvailable = [bool](Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
    . (Join-Path -Path $script:repoRoot -ChildPath 'skills/contributor-profile/scripts/ContributorProfileCommon.ps1')
    $script:isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:templatePath = Join-Path -Path $script:repoRoot -ChildPath 'skills/contributor-profile/assets/contributor-profile.hooks.json'

    # No global or system git configuration may put a real address into any
    # entry this file creates, so the whole file runs isolated.
    $script:emptyGitConfig = Join-Path -Path $TestDrive -ChildPath 'empty.gitconfig'
    Set-Content -LiteralPath $script:emptyGitConfig -Value '' -Encoding ascii
    $script:gitIsolation = @{ GIT_CONFIG_GLOBAL = $script:emptyGitConfig; GIT_CONFIG_NOSYSTEM = '1' }
    $script:savedGitEnvironment = @{}
    foreach ($name in $script:gitIsolation.Keys)
    {
        $script:savedGitEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name)
        [System.Environment]::SetEnvironmentVariable($name, $script:gitIsolation[$name])
    }

    $script:plainFolder = Join-Path -Path $TestDrive -ChildPath 'plain-folder'
    $null = New-Item -ItemType Directory -Path $script:plainFolder -Force

    function script:New-WriterLocation
    {
        param ([string] $Name, [switch] $Plugin, [switch] $WithoutScript)

        $layout = if ($Plugin)
        {
            New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath $Name)
        }
        else
        {
            New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath $Name) -Canonical -WithFamiliarityScript:(-not $WithoutScript)
        }

        Resolve-ContributorProfileLocation -UserHome $layout.Home -LocalApplicationData $layout.LocalData
    }

    function script:Get-WriterProfile
    {
        param ($Location)

        $read = Read-ContributorProfile -Location $Location
        if ($read.ReasonCode)
        {
            throw "unexpected reason $($read.ReasonCode)"
        }

        $read.Profile
    }

    function script:Get-FileText
    {
        param ([string] $Path)

        if (Test-Path -LiteralPath $Path)
        {
            [System.IO.File]::ReadAllText($Path)
        }
    }

    function script:Get-Sha256
    {
        param ([string] $Path)

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try
        {
            [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path))).Replace('-', '')
        }
        finally
        {
            $sha.Dispose()
        }
    }

    $script:twoEntryText = New-ContributorFixtureProfile -Entry @(
        (New-ContributorFixtureEntry -Default 'true')
        (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]' -Areas '{"Pester":{"level":"familiar","updatedUtc":"2026-10-01T08:00:00Z"}}')
    )
}

Describe 'Setting a contributor profile' -Tag 'Unit' {
    It 'creates the profile and an entry whose first alias is the git address' -Skip:(-not $script:gitAvailable) {
        $location = New-WriterLocation -Name 'set-create'
        $repository = New-ContributorGitRepository -Path (Join-Path -Path $TestDrive -ChildPath 'set-create-repo') -Email 'ada@example.com'

        $result = Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
            Set-ContributorProfile -Location $location -WorkspacePath $repository -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
        }

        $result.Created | Should -BeTrue
        $entry = @((Get-WriterProfile -Location $location).Contributors)
        $entry.Count | Should -Be 1
        [guid]::Parse($entry[0].Id) | Should -Not -Be ([guid]::Empty)
        @($entry[0].Aliases) | Should -Be @('ada@example.com')
        $entry[0].State | Should -BeExactly 'on'
        $entry[0].Default | Should -BeFalse
        $entry[0].Areas['Kerberos'].Level | Should -BeExactly 'new'
    }

    It 'creates an entry without an alias where git knows no address' {
        $location = New-WriterLocation -Name 'set-no-identity'

        Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
            $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
        }

        @((Get-WriterProfile -Location $location).Contributors[0].Aliases).Count | Should -Be 0
    }

    It 'updates the selected entry, keeps its stored spelling, and stamps updatedUtc' {
        $location = New-WriterLocation -Name 'set-update'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath

        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea ' kerberos ' -Level 'expert' -Confirm:$false

        $areas = (Get-WriterProfile -Location $location).Contributors[0].Areas
        $areas['Kerberos'].Name | Should -BeExactly 'Kerberos'
        $areas['Kerberos'].Level | Should -BeExactly 'expert'
        (ConvertFrom-ContributorUtcTimestamp -Value $areas['Kerberos'].UpdatedUtc) | Should -BeGreaterThan ([datetime]'2026-10-02')
        $areas['PowerShell DSC'].UpdatedUtc | Should -BeExactly '2026-10-01T08:00:00Z'
    }

    It 'rates several areas in one write' {
        $location = New-WriterLocation -Name 'set-several'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Pester', 'Kerberos' -Level 'familiar', 'expert' -Confirm:$false

        $areas = (Get-WriterProfile -Location $location).Contributors[0].Areas
        $areas['Pester'].Level | Should -BeExactly 'familiar'
        $areas['Kerberos'].Level | Should -BeExactly 'expert'
        $result.Changes | Should -Contain 'set Pester to familiar'
    }

    It 'refuses areas and levels that do not pair up' {
        $location = New-WriterLocation -Name 'set-unpaired'

        { Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Pester', 'Kerberos' -Level 'new' -Confirm:$false } | Should -Throw '*together*'
        Test-Path -LiteralPath $location.ProfilePath | Should -BeFalse
    }

    It 'refuses a name that breaks the area-name rule and writes nothing' {
        $location = New-WriterLocation -Name 'set-bad-name'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath
        $before = Get-FileText -Path $location.ProfilePath

        { Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'C_Sharp' -Level 'new' -Confirm:$false } | Should -Throw '*area-name rule*'

        Get-FileText -Path $location.ProfilePath | Should -BeExactly $before
    }

    It 'opts out and back in without losing a level' {
        $location = New-WriterLocation -Name 'set-state'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath

        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -State 'Off' -Confirm:$false
        $off = (Get-WriterProfile -Location $location).Contributors[0]
        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -State 'On' -Confirm:$false
        $on = (Get-WriterProfile -Location $location).Contributors[0]

        $off.State | Should -BeExactly 'off'
        $off.Areas.Count | Should -Be 2
        $off.StateUpdatedUtc | Should -Not -BeExactly '2026-10-01T08:00:00Z'
        $on.State | Should -BeExactly 'on'
        $on.Areas['Kerberos'].Level | Should -BeExactly 'new'
    }

    It 'adds and removes aliases, and refuses one that another entry holds' {
        $location = New-WriterLocation -Name 'set-alias'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $before = Get-FileText -Path $location.ProfilePath

        { Set-ContributorProfile -Location $location -Contributor 'ada@example.com' -AddAlias 'BOB@example.com' -Confirm:$false } | Should -Throw '*another entry*'
        Get-FileText -Path $location.ProfilePath | Should -BeExactly $before

        $null = Set-ContributorProfile -Location $location -Contributor 'ada@example.com' -AddAlias 'ada@work.example.com' -Confirm:$false
        @((Get-WriterProfile -Location $location).Contributors[0].Aliases) | Should -Be @('ada@example.com', 'ada@work.example.com')

        $null = Set-ContributorProfile -Location $location -Contributor 'ada@work.example.com' -RemoveAlias 'ada@example.com' -Confirm:$false
        @((Get-WriterProfile -Location $location).Contributors[0].Aliases) | Should -Be @('ada@work.example.com')
    }

    It 'refuses a ninth alias' {
        $location = New-WriterLocation -Name 'set-alias-cap'
        $aliases = '[' + ((1..8 | ForEach-Object -Process { '"a{0}@example.com"' -f $_ }) -join ',') + ']'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Aliases $aliases)) } -Path $location.ProfilePath

        { Set-ContributorProfile -Location $location -Contributor 'a1@example.com' -AddAlias 'a9@example.com' -Confirm:$false } | Should -Throw '*8*'
    }

    It 'marks one entry default and clears the others' {
        $location = New-WriterLocation -Name 'set-default'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath

        $null = Set-ContributorProfile -Location $location -Contributor 'bob@example.com' -Default -Confirm:$false

        $entries = (Get-WriterProfile -Location $location).Contributors
        $entries[0].Default | Should -BeFalse
        $entries[1].Default | Should -BeTrue
    }

    It 'resolves -Contributor by id or alias and fails before any write otherwise' {
        $location = New-WriterLocation -Name 'set-selector'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $before = Get-FileText -Path $location.ProfilePath

        { Set-ContributorProfile -Location $location -Contributor 'eve@example.com' -State 'Off' -Confirm:$false } | Should -Throw '*exactly one entry*'
        Get-FileText -Path $location.ProfilePath | Should -BeExactly $before

        $null = Set-ContributorProfile -Location $location -Contributor (New-ContributorFixtureId -Number 2) -State 'Off' -Confirm:$false
        $null = Set-ContributorProfile -Location $location -Contributor 'ADA@example.com' -KnowledgeArea 'Pester' -Level 'new' -Confirm:$false

        $entries = (Get-WriterProfile -Location $location).Contributors
        $entries[1].State | Should -BeExactly 'off'
        $entries[0].Areas['Pester'].Level | Should -BeExactly 'new'
    }

    It 'previews with -WhatIf and writes nothing' {
        $location = New-WriterLocation -Name 'set-whatif'

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -WhatIf

        $result.WhatIf | Should -BeTrue
        $result.Changes -join ' ' | Should -Match 'Kerberos'
        Test-Path -LiteralPath $location.ProfilePath | Should -BeFalse
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeFalse
    }

    It 'refuses to change a profile it cannot read, naming the reason code' -ForEach @(
        @{ Reason = 'unsupported-schema'; Text = (New-ContributorFixtureProfile -Version '2') }
        @{ Reason = 'invalid-json'; Text = '{"schemaVersion":1,' }
    ) {
        $location = New-WriterLocation -Name ('set-unreadable-' + $Reason)
        Write-ContributorFixture -Case @{ Text = $Text } -Path $location.ProfilePath

        { Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false } | Should -Throw "*$Reason*"
        Get-FileText -Path $location.ProfilePath | Should -BeExactly $Text
    }

    It 'says so when it saves on this machine only' {
        $location = New-WriterLocation -Name 'set-local' -Plugin

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false

        $result.Kind | Should -BeExactly 'local'
        $result.Messages -join ' ' | Should -Match 'saved on this machine only'
        $result.Messages -join ' ' | Should -Match 'Export-CopilotAtelierContributorProfile'
    }

    It 'snoozes the interview for 14 days on the entry' {
        $location = New-WriterLocation -Name 'set-snooze'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath

        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -SnoozeInterview -Confirm:$false

        $until = ConvertFrom-ContributorUtcTimestamp -Value (Get-WriterProfile -Location $location).Contributors[0].InterviewSnoozedUntilUtc
        ($until - [datetime]::UtcNow).TotalDays | Should -BeGreaterThan 13.9
        ($until - [datetime]::UtcNow).TotalDays | Should -BeLessOrEqual 14
    }

    It 'adds an entry for an unmatched address when several entries exist without a default' -Skip:(-not $script:gitAvailable) {
        $location = New-WriterLocation -Name 'set-shared'
        Write-ContributorFixture -Case @{ Text = ($script:twoEntryText -replace '"default":true', '"default":false') } -Path $location.ProfilePath
        $repository = New-ContributorGitRepository -Path (Join-Path -Path $TestDrive -ChildPath 'set-shared-repo') -Email 'cy@example.com'

        $result = Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
            Set-ContributorProfile -Location $location -WorkspacePath $repository -KnowledgeArea 'Kerberos' -Level 'expert' -Confirm:$false
        }

        $result.Created | Should -BeTrue
        $entries = (Get-WriterProfile -Location $location).Contributors
        $entries.Count | Should -Be 3
        @($entries[2].Aliases) | Should -Be @('cy@example.com')
    }

    It 'fails when it cannot tell whose entry to change' {
        $location = New-WriterLocation -Name 'set-ambiguous'
        Write-ContributorFixture -Case @{ Text = ($script:twoEntryText -replace '"default":true', '"default":false') } -Path $location.ProfilePath

        {
            Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
                Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
            }
        } | Should -Throw '*-Contributor*'
    }

    It 'writes nothing and fails clearly when another writer holds the lock for 5 seconds' {
        $location = New-WriterLocation -Name 'set-lock'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath
        $before = Get-FileText -Path $location.ProfilePath
        $lock = [System.IO.FileStream]::new($location.LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $watch = [System.Diagnostics.Stopwatch]::StartNew()

        try
        {
            { Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'expert' -Confirm:$false } | Should -Throw '*locked*'
        }
        finally
        {
            $lock.Dispose()
        }

        $watch.ElapsedMilliseconds | Should -BeGreaterOrEqual 4900
        Get-FileText -Path $location.ProfilePath | Should -BeExactly $before
    }

    It 'replaces the file atomically and leaves no temporary or lock file behind' {
        $location = New-WriterLocation -Name 'set-atomic'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath

        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Pester' -Level 'familiar' -Confirm:$false

        $names = @(Get-ChildItem -LiteralPath $location.ContributorDirectory -Force | ForEach-Object -Process { $_.Name })
        $names | Should -Not -Contain 'profile.lock'
        @($names | Where-Object -FilterScript { $_ -like '*.tmp' }).Count | Should -Be 0
        (Read-ContributorProfile -Location $location).ReasonCode | Should -BeNullOrEmpty
    }
}

# --- writer tests part 2 ---

Describe 'Registration file' -Tag 'Unit' {
    BeforeAll {
        $script:templateHash = Get-Sha256 -Path $script:templatePath

        function script:Write-RegistrationRecord
        {
            param ($Location, [string] $Operation, [string] $State, [string] $Sha256)

            $null = New-Item -ItemType Directory -Path $Location.ContributorDirectory -Force
            $text = '{{"schemaVersion":1,"operation":"{0}","state":"{1}","sha256":"{2}","updatedUtc":"2026-10-06T09:00:00Z"}}' -f $Operation, $State, $Sha256
            [System.IO.File]::WriteAllText($Location.RecordPath, $text, [System.Text.UTF8Encoding]::new($false))
        }
    }

    It 'creates the registration, byte for byte the shipped template, when an entry is on and rates an area' {
        $location = New-WriterLocation -Name 'registration-create'

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false

        $result.Registration | Should -BeExactly 'owned'
        Get-Sha256 -Path $location.RegistrationPath | Should -BeExactly $script:templateHash
        $record = Get-Content -LiteralPath $location.RecordPath -Raw | ConvertFrom-Json
        $record.operation | Should -BeExactly 'create'
        $record.state | Should -BeExactly 'complete'
        $record.sha256 | Should -BeExactly $script:templateHash
        (Get-Content -LiteralPath $location.RecordPath -Raw) | Should -Not -Match 'hooks|contributor-profile\.json|[A-Za-z]:\\'
    }

    It 'does not register an entry without levels' {
        $location = New-WriterLocation -Name 'registration-no-levels'

        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -SnoozeInterview -Confirm:$false

        Test-Path -LiteralPath $location.RegistrationPath | Should -BeFalse
    }

    It 'removes the registration when no entry is on and rates an area' {
        $location = New-WriterLocation -Name 'registration-remove'
        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -State 'Off' -Confirm:$false

        $result.Registration | Should -BeExactly 'none'
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeFalse
        Test-Path -LiteralPath $location.RecordPath | Should -BeFalse
    }

    It 'keeps the registration while another entry is still on with levels' {
        $location = New-WriterLocation -Name 'registration-shared'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $null = Set-ContributorProfile -Location $location -Contributor 'ada@example.com' -KnowledgeArea 'Pester' -Level 'new' -Confirm:$false

        $null = Set-ContributorProfile -Location $location -Contributor 'ada@example.com' -State 'Off' -Confirm:$false

        Test-Path -LiteralPath $location.RegistrationPath | Should -BeTrue
    }

    It 'never overwrites or deletes a file it did not create, even one with the template bytes' {
        $location = New-WriterLocation -Name 'registration-foreign'
        Copy-Item -LiteralPath $script:templatePath -Destination $location.RegistrationPath

        $created = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
        $stopped = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -State 'Off' -Confirm:$false

        $created.Registration | Should -BeExactly 'foreign'
        $stopped.Registration | Should -BeExactly 'foreign'
        $stopped.Messages -join ' ' | Should -Match ([regex]::Escape($location.RegistrationPath))
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeTrue
        Test-Path -LiteralPath $location.RecordPath | Should -BeFalse
    }

    It 'never deletes a registration that was modified after it was written' {
        $location = New-WriterLocation -Name 'registration-modified'
        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
        Add-Content -LiteralPath $location.RegistrationPath -Value ' '

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -State 'Off' -Confirm:$false

        $result.Registration | Should -BeExactly 'modified'
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeTrue
    }

    It 'creates no registration where the PostToolUse script is not deployed' {
        $location = New-WriterLocation -Name 'registration-unavailable' -WithoutScript

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false

        $result.Registration | Should -BeExactly 'unavailable'
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeFalse
        Test-Path -LiteralPath $location.RecordPath | Should -BeFalse
    }

    It 'recovers from a crash after the pending create record, before the file' {
        $location = New-WriterLocation -Name 'crash-create-before-file'
        Write-RegistrationRecord -Location $location -Operation 'create' -State 'pending' -Sha256 $script:templateHash

        $result = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false

        $result.Registration | Should -BeExactly 'owned'
        (Get-Content -LiteralPath $location.RecordPath -Raw | ConvertFrom-Json).state | Should -BeExactly 'complete'
    }

    It 'recovers from a crash after the file, before the record was completed' {
        $location = New-WriterLocation -Name 'crash-create-after-file'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath
        Write-RegistrationRecord -Location $location -Operation 'create' -State 'pending' -Sha256 $script:templateHash
        Copy-Item -LiteralPath $script:templatePath -Destination $location.RegistrationPath

        $report = Get-ContributorProfileReport -Location $location

        $report.Registration | Should -BeExactly 'owned'
        (Get-Content -LiteralPath $location.RecordPath -Raw | ConvertFrom-Json).state | Should -BeExactly 'complete'
    }

    It 'recovers from a crash during deletion, before the file was removed' {
        $location = New-WriterLocation -Name 'crash-delete-before-file'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -State '"off"')) } -Path $location.ProfilePath
        Write-RegistrationRecord -Location $location -Operation 'delete' -State 'pending' -Sha256 $script:templateHash
        Copy-Item -LiteralPath $script:templatePath -Destination $location.RegistrationPath

        $result = Set-ContributorProfile -Location $location -Contributor 'ada@example.com' -SnoozeInterview -Confirm:$false

        $result.Registration | Should -BeExactly 'none'
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeFalse
        Test-Path -LiteralPath $location.RecordPath | Should -BeFalse
    }

    It 'recovers from a crash during deletion, after the file was removed' {
        $location = New-WriterLocation -Name 'crash-delete-after-file'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath
        Write-RegistrationRecord -Location $location -Operation 'delete' -State 'pending' -Sha256 $script:templateHash

        $report = Get-ContributorProfileReport -Location $location

        Test-Path -LiteralPath $location.RecordPath | Should -BeFalse
        $report.Registration | Should -BeExactly 'none'
    }

    It 'reports an orphaned registration and removes it with -RegistrationOnly' {
        $location = New-WriterLocation -Name 'registration-orphaned'
        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
        Remove-Item -LiteralPath $location.ProfilePath

        (Get-ContributorProfileReport -Location $location).Registration | Should -BeExactly 'orphaned'
        $result = Remove-ContributorProfile -Location $location -RegistrationOnly -Confirm:$false

        $result.Removed | Should -BeExactly 'registration'
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeFalse
        Test-Path -LiteralPath $location.RecordPath | Should -BeFalse
    }

    It 'refuses -RegistrationOnly for a modified registration' {
        $location = New-WriterLocation -Name 'registration-only-modified'
        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
        Add-Content -LiteralPath $location.RegistrationPath -Value ' '

        { Remove-ContributorProfile -Location $location -RegistrationOnly -Confirm:$false } | Should -Throw '*modified*'
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeTrue
    }
}

# --- writer tests part 3 ---

Describe 'Exporting a contributor profile' -Tag 'Unit' {
    It 'writes a schema-1 file of every entry' {
        $location = New-WriterLocation -Name 'export-all'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $destination = Join-Path -Path $TestDrive -ChildPath 'export-all.json'

        $result = Export-ContributorProfile -Location $location -Path $destination -Confirm:$false

        $result.EntryCount | Should -Be 2
        (Read-ContributorProfileData -Path $destination).Profile.Contributors.Count | Should -Be 2
    }

    It 'writes only the entry -Contributor names' {
        $location = New-WriterLocation -Name 'export-one'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $destination = Join-Path -Path $TestDrive -ChildPath 'export-one.json'

        $null = Export-ContributorProfile -Location $location -Path $destination -Contributor 'bob@example.com' -Confirm:$false

        @((Read-ContributorProfileData -Path $destination).Profile.Contributors.Aliases) | Should -Be @('bob@example.com')
    }

    It 'previews with -WhatIf and writes nothing' {
        $location = New-WriterLocation -Name 'export-whatif'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $destination = Join-Path -Path $TestDrive -ChildPath 'export-whatif.json'

        $null = Export-ContributorProfile -Location $location -Path $destination -WhatIf

        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'refuses to export a profile it cannot read' {
        $location = New-WriterLocation -Name 'export-unreadable'
        Write-ContributorFixture -Case @{ Text = 'not JSON' } -Path $location.ProfilePath

        { Export-ContributorProfile -Location $location -Path (Join-Path -Path $TestDrive -ChildPath 'export-unreadable.json') -Confirm:$false } | Should -Throw '*invalid-json*'
    }
}

Describe 'Importing a contributor profile' -Tag 'Unit' {
    BeforeAll {
        function script:Invoke-TestImport
        {
            param ([string] $Name, [string[]] $Entry, [switch] $WhatIf)

            $location = New-WriterLocation -Name $Name
            Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
            $source = Join-Path -Path $TestDrive -ChildPath "$Name-source.json"
            Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry $Entry) } -Path $source

            [pscustomobject] @{
                Location = $location
                Before   = Get-FileText -Path $location.ProfilePath
                Result   = Import-ContributorProfile -Location $location -Path $source -WhatIf:$WhatIf -Confirm:$false
            }
        }

        function script:Get-AreaText
        {
            param ($Entry)

            @($Entry.Areas.Values | ForEach-Object -Process { '{0}={1}' -f $_.Name, $_.Level })
        }

        $script:adaId = '11111111-1111-4111-8111-111111111111'
    }

    It 'merges an entry with the same id' {
        $import = Invoke-TestImport -Name 'import-id' -Entry (New-ContributorFixtureEntry -Aliases '["ada@home.example.com"]' -Areas '{}')

        $entries = (Get-WriterProfile -Location $import.Location).Contributors
        $entries.Count | Should -Be 2
        @($entries[0].Aliases) | Should -Be @('ada@example.com', 'ada@home.example.com')
    }

    It 'merges by a shared alias when the id differs, keeping the local id' {
        $import = Invoke-TestImport -Name 'import-alias' -Entry (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 3) -Aliases '["ADA@example.com"]' -Areas '{"Mietrecht":{"level":"new","updatedUtc":"2026-10-03T08:00:00Z"}}')

        $entries = (Get-WriterProfile -Location $import.Location).Contributors
        $entries.Count | Should -Be 2
        $entries[0].Id | Should -BeExactly $script:adaId
        @($entries[0].Aliases) | Should -Be @('ada@example.com')
        $entries[0].Areas.Contains('Mietrecht') | Should -BeTrue
    }

    It 'adds an unmatched entry, never as the default' {
        $import = Invoke-TestImport -Name 'import-add' -Entry (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 4) -Aliases '["cy@example.com"]' -Default 'true')

        $entries = (Get-WriterProfile -Location $import.Location).Contributors
        $entries.Count | Should -Be 3
        $entries[2].Default | Should -BeFalse
        $entries[0].Default | Should -BeTrue
        $import.Result.Added | Should -Be 1
    }

    It 'takes the newer level per area and keeps the local one on a tie' {
        $import = Invoke-TestImport -Name 'import-areas' -Entry (New-ContributorFixtureEntry -Areas '{"Kerberos":{"level":"expert","updatedUtc":"2026-10-05T08:00:00Z"},"PowerShell DSC":{"level":"new","updatedUtc":"2026-10-01T08:00:00Z"}}')

        Get-AreaText -Entry (Get-WriterProfile -Location $import.Location).Contributors[0] | Should -Be @('Kerberos=expert', 'PowerShell DSC=expert')
    }

    It 'keeps an older local level against an older import' {
        $import = Invoke-TestImport -Name 'import-older' -Entry (New-ContributorFixtureEntry -Areas '{"Kerberos":{"level":"expert","updatedUtc":"2026-09-01T08:00:00Z"}}')

        (Get-WriterProfile -Location $import.Location).Contributors[0].Areas['Kerberos'].Level | Should -BeExactly 'new'
    }

    It 'keeps an area that only one side has' {
        $import = Invoke-TestImport -Name 'import-union' -Entry (New-ContributorFixtureEntry -Areas '{"Mietrecht":{"level":"new","updatedUtc":"2026-10-01T08:00:00Z"}}')

        Get-AreaText -Entry (Get-WriterProfile -Location $import.Location).Contributors[0] | Should -Be @('Kerberos=new', 'PowerShell DSC=expert', 'Mietrecht=new')
    }

    It 'follows the newer stateUpdatedUtc' {
        $newer = Invoke-TestImport -Name 'import-state-newer' -Entry (New-ContributorFixtureEntry -State '"off"' -StateUpdatedUtc '"2026-10-05T08:00:00Z"')
        $older = Invoke-TestImport -Name 'import-state-older' -Entry (New-ContributorFixtureEntry -State '"off"' -StateUpdatedUtc '"2026-09-01T08:00:00Z"')

        (Get-WriterProfile -Location $newer.Location).Contributors[0].State | Should -BeExactly 'off'
        (Get-WriterProfile -Location $older.Location).Contributors[0].State | Should -BeExactly 'on'
    }

    It 'keeps the later interview snooze' {
        $import = Invoke-TestImport -Name 'import-snooze' -Entry (New-ContributorFixtureEntry -Snooze '"2026-12-01T00:00:00Z"')

        (Get-WriterProfile -Location $import.Location).Contributors[0].InterviewSnoozedUntilUtc | Should -BeExactly '2026-12-01T00:00:00Z'
    }

    It 'keeps the default flag local' {
        $import = Invoke-TestImport -Name 'import-default' -Entry (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]' -Default 'true')

        $entries = (Get-WriterProfile -Location $import.Location).Contributors
        $entries[0].Default | Should -BeTrue
        $entries[1].Default | Should -BeFalse
    }

    It 'refuses the whole file and writes nothing for <Why>' -ForEach @(
        @{ Why = 'an entry whose aliases point to two local entries'; Entry = @((New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 5) -Aliases '["ada@example.com","bob@example.com"]')) }
        @{ Why = 'an alias that would belong to two entries'; Entry = @((New-ContributorFixtureEntry -Aliases '["bob@example.com"]')) }
        @{ Why = 'two imported entries that match one local entry'; Entry = @(
                (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 6) -Aliases '["ada@example.com"]')
                (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 7) -Aliases '["ada@home.example.com"]' -Areas '{}')
                (New-ContributorFixtureEntry -Aliases '["ada@office.example.com"]' -Areas '{}')
            ) }
        @{ Why = 'an alias union over the cap of 8'; Entry = @((New-ContributorFixtureEntry -Aliases ('[' + ((1..8 | ForEach-Object -Process { '"ada{0}@example.com"' -f $_ }) -join ',') + ']'))) }
    ) {
        $location = New-WriterLocation -Name ('import-refuse-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $before = Get-FileText -Path $location.ProfilePath
        $source = Join-Path -Path $TestDrive -ChildPath ('refuse-{0}.json' -f [guid]::NewGuid().ToString('N'))
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry $Entry) } -Path $source

        { Import-ContributorProfile -Location $location -Path $source -Confirm:$false } | Should -Throw '*nothing was written*'
        Get-FileText -Path $location.ProfilePath | Should -BeExactly $before
    }

    It 'refuses a file that breaks schema 1, naming its reason code' {
        $location = New-WriterLocation -Name 'import-invalid'
        $source = Join-Path -Path $TestDrive -ChildPath 'import-invalid.json'
        Write-ContributorFixture -Case @{ Text = '{"schemaVersion":1,"contributors":[],}' } -Path $source

        { Import-ContributorProfile -Location $location -Path $source -Confirm:$false } | Should -Throw '*invalid-json*'
        Test-Path -LiteralPath $location.ProfilePath | Should -BeFalse
    }

    It 'previews with -WhatIf and writes nothing' {
        $import = Invoke-TestImport -Name 'import-whatif' -Entry (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 8) -Aliases '["dee@example.com"]') -WhatIf

        Get-FileText -Path $import.Location.ProfilePath | Should -BeExactly $import.Before
        $import.Result.Added | Should -Be 1
    }

    It 'imports into this machine only where no Canonical target exists, and says so' {
        $location = New-WriterLocation -Name 'import-local' -Plugin
        $source = Join-Path -Path $TestDrive -ChildPath 'import-local.json'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $source

        $result = Import-ContributorProfile -Location $location -Path $source -Confirm:$false

        $result.Kind | Should -BeExactly 'local'
        $result.Messages -join ' ' | Should -Match 'saved on this machine only'
        (Get-WriterProfile -Location $location).Contributors.Count | Should -Be 1
    }
}

Describe 'Removing a contributor profile' -Tag 'Unit' {
    It 'removes one entry' {
        $location = New-WriterLocation -Name 'remove-entry'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath

        $result = Remove-ContributorProfile -Location $location -Contributor 'bob@example.com' -Confirm:$false

        $result.Removed | Should -BeExactly 'entry'
        @((Get-WriterProfile -Location $location).Contributors.Aliases) | Should -Be @('ada@example.com')
    }

    It 'deletes the file, and the registration, with the last entry' {
        $location = New-WriterLocation -Name 'remove-last'
        $null = Set-ContributorProfile -Location $location -WorkspacePath $script:plainFolder -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
        $id = (Get-WriterProfile -Location $location).Contributors[0].Id

        $result = Remove-ContributorProfile -Location $location -Contributor $id -Confirm:$false

        $result.Removed | Should -BeExactly 'file'
        Test-Path -LiteralPath $location.ProfilePath | Should -BeFalse
        Test-Path -LiteralPath $location.RegistrationPath | Should -BeFalse
    }

    It 'deletes the whole file without -Contributor, even one it cannot read' {
        $location = New-WriterLocation -Name 'remove-file'
        Write-ContributorFixture -Case @{ Text = 'not JSON' } -Path $location.ProfilePath

        (Remove-ContributorProfile -Location $location -Confirm:$false).Removed | Should -BeExactly 'file'
        Test-Path -LiteralPath $location.ProfilePath | Should -BeFalse
    }

    It 'fails before any write when -Contributor names no single entry' {
        $location = New-WriterLocation -Name 'remove-unknown'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $before = Get-FileText -Path $location.ProfilePath

        { Remove-ContributorProfile -Location $location -Contributor 'eve@example.com' -Confirm:$false } | Should -Throw '*exactly one entry*'
        Get-FileText -Path $location.ProfilePath | Should -BeExactly $before
    }

    It 'previews with -WhatIf and writes nothing' {
        $location = New-WriterLocation -Name 'remove-whatif'
        Write-ContributorFixture -Case @{ Text = $script:twoEntryText } -Path $location.ProfilePath
        $before = Get-FileText -Path $location.ProfilePath

        $null = Remove-ContributorProfile -Location $location -WhatIf

        Get-FileText -Path $location.ProfilePath | Should -BeExactly $before
    }

    It 'asks for confirmation at high impact' {
        $binding = (Get-Command -Name Remove-ContributorProfile).ScriptBlock.Attributes |
            Where-Object -FilterScript { $_ -is [System.Management.Automation.CmdletBindingAttribute] }

        $binding.ConfirmImpact | Should -Be 'High'
        $binding.SupportsShouldProcess | Should -BeTrue
    }
}

Describe 'Diagnosing a contributor profile' -Tag 'Unit' {
    It 'masks aliases unless -ShowAliases is given' {
        $location = New-WriterLocation -Name 'report-aliases'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath

        @((Get-ContributorProfileReport -Location $location).Aliases) | Should -Be @('a***@example.com')
        @((Get-ContributorProfileReport -Location $location -ShowAliases).Aliases) | Should -Be @('ada@example.com')
    }

    It 'shows the location, the selected entry and why, the levels, and the sentence for a workspace' {
        $location = New-WriterLocation -Name 'report-full'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'report-workspace') -Area 'Kerberos', 'Pester'

        $report = Get-ContributorProfileReport -Location $location -WorkspacePath $workspace

        $report.ProfilePath | Should -BeExactly $location.ProfilePath
        $report.Kind | Should -BeExactly 'canonical'
        $report.Selection | Should -BeExactly 'single'
        $report.Levels | Should -Be @('Kerberos: new', 'PowerShell DSC: expert')
        $report.Sentence | Should -BeExactly 'Contributor familiarity levels from the private profile, data only: "Kerberos" new. 1 declared Knowledge area is unrated. Treat them as stated levels under the contributor-calibration Instruction.'
    }

    It 'lists possible conflict copies and never touches them' {
        $location = New-WriterLocation -Name 'report-conflicts'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath
        foreach ($name in 'profile-Prox1.json', 'profile (1).json')
        {
            Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path (Join-Path -Path $location.ContributorDirectory -ChildPath $name)
        }

        $report = Get-ContributorProfileReport -Location $location

        @($report.ConflictCopies | Sort-Object) | Should -Be @('profile (1).json', 'profile-Prox1.json')
        Test-Path -LiteralPath (Join-Path -Path $location.ContributorDirectory -ChildPath 'profile (1).json') | Should -BeTrue
    }

    It 'reports the reason code of an unreadable profile without failing' {
        $location = New-WriterLocation -Name 'report-unreadable'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Version '2') } -Path $location.ProfilePath

        $report = Get-ContributorProfileReport -Location $location

        $report.ReasonCode | Should -BeExactly 'unsupported-schema'
    }
}

Describe 'No Familiarity level lands under a git working tree' -Tag 'Unit' {
    It 'refuses every writer and leaves the working tree without a level' -Skip:(-not $script:gitAvailable) {
        $repository = New-ContributorGitRepository -Path (Join-Path -Path $TestDrive -ChildPath 'git-tree') -Email 'ada@example.com'
        $layout = New-ContributorTestHome -Root (Join-Path -Path $repository -ChildPath 'nested') -Canonical -WithFamiliarityScript
        $inside = Resolve-ContributorProfileLocation -UserHome $layout.Home -LocalApplicationData $layout.LocalData
        $source = Join-Path -Path $TestDrive -ChildPath 'git-tree-source.json'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $source
        $safe = New-WriterLocation -Name 'git-tree-safe'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $safe.ProfilePath

        { Set-ContributorProfile -Location $inside -WorkspacePath $repository -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false } | Should -Throw '*git working tree*'
        { Import-ContributorProfile -Location $inside -Path $source -Confirm:$false } | Should -Throw '*git working tree*'
        { Remove-ContributorProfile -Location $inside -Contributor 'ada@example.com' -Confirm:$false } | Should -Throw '*git working tree*'
        { Export-ContributorProfile -Location $safe -Path (Join-Path -Path $repository -ChildPath 'exported.json') -Confirm:$false } | Should -Throw '*git working tree*'

        $leaked = @(
            Get-ChildItem -LiteralPath $repository -Recurse -File -Force |
                Where-Object -FilterScript { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
                Where-Object -FilterScript { [System.IO.File]::ReadAllText($_.FullName) -match '"level"' }
        )
        $leaked.FullName | Should -BeNullOrEmpty
    }
}

AfterAll {
    foreach ($name in $script:savedGitEnvironment.Keys)
    {
        [System.Environment]::SetEnvironmentVariable($name, $script:savedGitEnvironment[$name])
    }
}
