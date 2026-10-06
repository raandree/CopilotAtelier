<#
    Read path of the contributor-profile Skill (Decision record 0028):
    the area-name rule, strict schema 1 parsing over the shared fixture set,
    the location rule, the read guards, the identity rule, the Knowledge areas
    declaration, and the calibration sentence.
#>

BeforeDiscovery {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
    $script:fixtureCases = @(
        Get-ContributorProfileFixtureCase | ForEach-Object -Process {
            $case = $_.Clone()
            $case.Expected = if ($_.Reason) { $_.Reason } else { 'a valid profile' }
            $case
        }
    )
    $script:isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
    . (Join-Path -Path $script:repoRoot -ChildPath 'skills/contributor-profile/scripts/ContributorProfileReader.ps1')
    $script:isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    # No global or system git configuration may leak a real address into a test.
    $script:emptyGitConfig = Join-Path -Path $TestDrive -ChildPath 'empty.gitconfig'
    Set-Content -LiteralPath $script:emptyGitConfig -Value '' -Encoding ascii
    $script:gitIsolation = @{ GIT_CONFIG_GLOBAL = $script:emptyGitConfig; GIT_CONFIG_NOSYSTEM = '1' }
}

Describe 'Area-name rule' -Tag 'Unit' {
    It 'accepts <Name>' -ForEach @(
        @{ Name = 'Kerberos' }
        @{ Name = 'PowerShell DSC' }
        @{ Name = 'C#' }
        @{ Name = 'C++' }
        @{ Name = 'TCP/IP' }
        @{ Name = 'R&D (lab)' }
        @{ Name = 'Node.js' }
        @{ Name = '3D printing' }
        @{ Name = 'Vue-Router' }
        @{ Name = '.NET' }
        @{ Name = '.5G' }
        @{ Name = 'a23456789012345678901234567890123456789012345678' }
    ) {
        ConvertTo-ContributorAreaName -Name $Name | Should -BeExactly $Name
    }

    It 'accepts letters of any script together with their combining marks' {
        $names = @(
            ('B' + [char]0x00FC + 'rgerliches Recht')
            ([string][char]0x65E5 + [char]0x672C + [char]0x8A9E)
            ([string][char]0x0939 + [char]0x093F + [char]0x0928 + [char]0x094D + [char]0x0926 + [char]0x0940)
        )

        foreach ($name in $names)
        {
            ConvertTo-ContributorAreaName -Name $name | Should -BeExactly $name
        }
    }

    It 'trims and normalizes to NFC before it measures' {
        ConvertTo-ContributorAreaName -Name (' Mu' + [char]0x0308 + 'nchen ') | Should -BeExactly ('M' + [char]0x00FC + 'nchen')
    }

    It 'refuses <Why>' -ForEach @(
        @{ Why = 'an empty name'; Name = '' }
        @{ Why = 'a name of spaces'; Name = '   ' }
        @{ Why = 'a lone dot'; Name = '.' }
        @{ Why = 'two dots'; Name = '..' }
        @{ Why = 'a dot before a space'; Name = '. NET' }
        @{ Why = 'a dot before a combining mark'; Name = ".$([char]0x0308)NET" }
        @{ Why = 'a leading hyphen'; Name = '-NET' }
        @{ Why = 'a double space'; Name = 'Active  Directory' }
        @{ Why = 'a quote'; Name = 'Kerberos"' }
        @{ Why = 'a backtick'; Name = 'Power`Shell' }
        @{ Why = 'a semicolon'; Name = 'A;B' }
        @{ Why = 'an equals sign'; Name = 'A=B' }
        @{ Why = 'angle brackets'; Name = '<b>' }
        @{ Why = 'an asterisk'; Name = 'A*' }
        @{ Why = 'an underscore'; Name = 'C_Sharp' }
        @{ Why = 'a control character'; Name = "A$([char]7)B" }
        @{ Why = 'a line break'; Name = "A`nB" }
        @{ Why = '49 characters'; Name = 'a234567890123456789012345678901234567890123456789' }
        @{ Why = 'a leading combining mark'; Name = "$([char]0x0308)a" }
    ) {
        ConvertTo-ContributorAreaName -Name $Name | Should -BeNullOrEmpty
    }

    It 'requires a stored name to be its own normalized form' {
        Test-ContributorAreaName -Name 'Kerberos' | Should -BeTrue
        Test-ContributorAreaName -Name 'Kerberos ' | Should -BeFalse
        Test-ContributorAreaName -Name ('Mu' + [char]0x0308 + 'nchen') | Should -BeFalse
    }
}

Describe 'Strict JSON parsing' -Tag 'Unit' {
    It 'keeps duplicate keys, raw numbers, and ISO 8601 text as written' {
        $node = ConvertFrom-ContributorJson -Text '{"a":1.50,"a":"2026-10-01T08:00:00Z","b":[true,null]}'

        $node.K | Should -Be @('a', 'a', 'b')
        $node.V[0].V | Should -BeExactly '1.50'
        $node.V[1].T | Should -BeExactly 's'
        $node.V[1].V | Should -BeExactly '2026-10-01T08:00:00Z'
        $node.V[2].V[1].T | Should -BeExactly 'z'
    }

    It 'decodes escapes' {
        (ConvertFrom-ContributorJson -Text '"a\"b\\c\/d\u00fce\n"').V | Should -BeExactly ("a`"b\c/d$([char]0x00FC)e`n")
    }

    It 'refuses <Why> as invalid JSON' -ForEach @(
        @{ Why = 'a trailing comma'; Text = '{"a":1,}' }
        @{ Why = 'a leading zero'; Text = '{"a":01}' }
        @{ Why = 'single quotes'; Text = "{'a':1}" }
        @{ Why = 'a comment'; Text = '{"a":1 /* x */}' }
        @{ Why = 'two top-level values'; Text = '{} {}' }
        @{ Why = 'an unescaped control character'; Text = "{`"a`":`"x$([char]1)`"}" }
        @{ Why = 'a missing colon'; Text = '{"a" 1}' }
        @{ Why = 'an unterminated object'; Text = '{"a":1' }
        @{ Why = 'an empty document'; Text = '  ' }
        @{ Why = 'NaN'; Text = '{"a":NaN}' }
    ) {
        { ConvertFrom-ContributorJson -Text $Text } | Should -Throw -ExceptionType ([System.FormatException])
    }

    It 'refuses nesting deeper than any schema 1 file without exhausting the stack' {
        $deep = ('[' * 5000) + (']' * 5000)

        { ConvertFrom-ContributorJson -Text $deep } | Should -Throw -ExceptionType ([System.IO.InvalidDataException])
    }
}

Describe 'Reading the shared fixture set' -Tag 'Unit' {
    BeforeAll {
        $script:fixtureHome = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'fixtures') -Canonical
        $script:fixtureLocation = Resolve-ContributorProfileLocation -UserHome $script:fixtureHome.Home -LocalApplicationData $script:fixtureHome.LocalData
    }

    It '<Name> yields <Expected>' -ForEach $script:fixtureCases {
        Write-ContributorFixture -Case $_ -Path $script:fixtureLocation.ProfilePath

        $read = Read-ContributorProfile -Location $script:fixtureLocation

        if ($Reason)
        {
            $read.ReasonCode | Should -BeExactly $Reason
            $read.Profile | Should -BeNullOrEmpty
            $read.Detail | Should -Not -Match '(?i)likes cats|C_Sharp|ada@|bob@|kerberos'
        }
        else
        {
            $read.ReasonCode | Should -BeNullOrEmpty
            $read.Profile.Contributors.Count | Should -Be 1
            $levels = @($read.Profile.Contributors[0].Areas.Values | ForEach-Object -Process { '{0}: {1}' -f $_.Name, $_.Level })
            ($levels -join '|') | Should -BeExactly (@($_.Levels) -join '|')
        }
    }
}

# --- reader tests part 2 ---

Describe 'Location rule' -Tag 'Unit' {
    It 'follows ~/.copilot/hooks to the Canonical target that holds the Deployment record' {
        $layout = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'canonical') -Canonical

        $location = Resolve-ContributorProfileLocation -UserHome $layout.Home -LocalApplicationData $layout.LocalData

        $location.Kind | Should -BeExactly 'canonical'
        $location.ProfilePath | Should -BeExactly ([System.IO.Path]::GetFullPath((Join-Path -Path $layout.CanonicalFolder -ChildPath 'profile.json')))
        $location.RegistrationPath | Should -BeExactly ([System.IO.Path]::Combine($layout.Home, '.copilot', 'hooks', 'contributor-profile.json'))
    }

    It 'falls back to LocalApplicationData without ~/.copilot/hooks, as a plugin-only install has' {
        $layout = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'plugin')

        $location = Resolve-ContributorProfileLocation -UserHome $layout.Home -LocalApplicationData $layout.LocalData

        $location.Kind | Should -BeExactly 'local'
        $location.Synced | Should -BeFalse
        $location.ProfilePath | Should -BeExactly ([System.IO.Path]::Combine($layout.LocalData, 'CopilotAtelier', 'contributor', 'profile.json'))
    }

    It 'falls back when the linked folder has no Deployment record beside it' {
        $layout = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'unrecorded') -Canonical
        Remove-Item -LiteralPath (Join-Path -Path $layout.Target -ChildPath '.copilotatelier.json')

        (Resolve-ContributorProfileLocation -UserHome $layout.Home -LocalApplicationData $layout.LocalData).Kind | Should -BeExactly 'local'
    }

    It 'reads USERPROFILE before HOME and LOCALAPPDATA from the environment' {
        $layout = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'environment') -Canonical
        $decoy = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'decoy')

        $location = Use-ContributorEnvironment -Variable @{ USERPROFILE = $layout.Home; HOME = $decoy.Home; LOCALAPPDATA = $layout.LocalData } -ScriptBlock {
            Resolve-ContributorProfileLocation
        }

        $location.Kind | Should -BeExactly 'canonical'
        $location.HooksDirectory | Should -BeExactly ([System.IO.Path]::Combine($layout.Home, '.copilot', 'hooks'))
    }

    It 'reports a Canonical target inside OneDrive as synced' {
        $root = Join-Path -Path $TestDrive -ChildPath 'onedrive'
        $layout = New-ContributorTestHome -Root $root -Canonical

        $location = Use-ContributorEnvironment -Variable @{ OneDrive = $null; OneDriveConsumer = $root; OneDriveCommercial = $null } -ScriptBlock {
            Resolve-ContributorProfileLocation -UserHome $layout.Home -LocalApplicationData $layout.LocalData
        }

        $location.Synced | Should -BeTrue
    }
}

Describe 'Read guards' -Tag 'Unit' {
    BeforeAll {
        $script:guardHome = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'guards') -Canonical
        $script:guardLocation = Resolve-ContributorProfileLocation -UserHome $script:guardHome.Home -LocalApplicationData $script:guardHome.LocalData
        $script:validCase = @{ Text = (New-ContributorFixtureProfile) }

        function script:Use-ExclusiveLock
        {
            param ([string] $Path, [scriptblock] $ScriptBlock)

            $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try
            {
                & $ScriptBlock
            }
            finally
            {
                $stream.Dispose()
            }
        }
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:guardLocation.ProfilePath)
        {
            [System.IO.File]::SetAttributes($script:guardLocation.ProfilePath, [System.IO.FileAttributes]::Normal)
            Remove-Item -LiteralPath $script:guardLocation.ProfilePath -Force
        }
    }

    It 'treats a missing profile as no profile, not as an error' {
        $read = Read-ContributorProfile -Location $script:guardLocation

        $read.Exists | Should -BeFalse
        $read.ReasonCode | Should -BeNullOrEmpty
    }

    It 'reports inside-repository for a profile path under a git working tree, whether or not the file exists' {
        $repository = Join-Path -Path $TestDrive -ChildPath 'repository'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $repository -ChildPath '.git') -Force
        $layout = New-ContributorTestHome -Root $repository -Canonical
        $location = Resolve-ContributorProfileLocation -UserHome $layout.Home -LocalApplicationData $layout.LocalData

        (Read-ContributorProfile -Location $location).ReasonCode | Should -BeExactly 'inside-repository'

        Write-ContributorFixture -Case $script:validCase -Path $location.ProfilePath
        (Read-ContributorProfile -Location $location).ReasonCode | Should -BeExactly 'inside-repository'
    }

    It 'counts a .git file, as a worktree or submodule has, as a working tree' {
        $worktree = Join-Path -Path $TestDrive -ChildPath 'worktree'
        $null = New-Item -ItemType Directory -Path $worktree -Force
        Set-Content -LiteralPath (Join-Path -Path $worktree -ChildPath '.git') -Value 'gitdir: elsewhere' -Encoding ascii

        Test-ContributorPathInsideRepository -Path (Join-Path -Path $worktree -ChildPath 'a/b/profile.json') | Should -BeTrue
    }

    It 'treats the offline, recall-on-open, and recall-on-data-access attributes as not local' {
        Test-ContributorFileLocal -Attributes 0x20 | Should -BeTrue
        Test-ContributorFileLocal -Attributes 0x1000 | Should -BeFalse
        Test-ContributorFileLocal -Attributes 0x40000 | Should -BeFalse
        Test-ContributorFileLocal -Attributes 0x400000 | Should -BeFalse
    }

    It 'never opens an offline file and reports not-local' -Skip:(-not $script:isWindowsHost) {
        Write-ContributorFixture -Case $script:validCase -Path $script:guardLocation.ProfilePath
        [System.IO.File]::SetAttributes($script:guardLocation.ProfilePath, [System.IO.FileAttributes]::Offline)

        # Any attempt to read the data would fail with read-error under this lock.
        Use-ExclusiveLock -Path $script:guardLocation.ProfilePath -ScriptBlock {
            (Read-ContributorProfile -Location $script:guardLocation).ReasonCode | Should -BeExactly 'not-local'
        }
    }

    It 'never reads a file over 64 KB and reports too-large' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) + (' ' * 70000) } -Path $script:guardLocation.ProfilePath

        Use-ExclusiveLock -Path $script:guardLocation.ProfilePath -ScriptBlock {
            (Read-ContributorProfile -Location $script:guardLocation).ReasonCode | Should -BeExactly 'too-large'
        }
    }

    It 'reports read-error for a profile it cannot open' -Skip:(-not $script:isWindowsHost) {
        Write-ContributorFixture -Case $script:validCase -Path $script:guardLocation.ProfilePath

        Use-ExclusiveLock -Path $script:guardLocation.ProfilePath -ScriptBlock {
            (Read-ContributorProfile -Location $script:guardLocation).ReasonCode | Should -BeExactly 'read-error'
        }
    }
}

# --- reader tests part 3 ---

Describe 'Identity rule' -Tag 'Unit' {
    BeforeAll {
        $entries = @(
            (New-ContributorFixtureEntry -Aliases '["ada@example.com"]')
            (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]' -Default 'true')
            (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 3) -Aliases '[]')
        )
        $script:threeEntries = ConvertTo-ContributorProfileModel -Node (ConvertFrom-ContributorJson -Text (New-ContributorFixtureProfile -Entry $entries))
        $script:twoEntries = ConvertTo-ContributorProfileModel -Node (ConvertFrom-ContributorJson -Text (New-ContributorFixtureProfile -Entry @($entries[0], $entries[2])))
        $script:oneEntry = ConvertTo-ContributorProfileModel -Node (ConvertFrom-ContributorJson -Text (New-ContributorFixtureProfile))
    }

    It 'selects the entry whose alias matches, in any letter case' {
        $selection = Select-ContributorEntry -ContributorProfile $script:threeEntries -Email 'ADA@Example.com'

        $selection.Reason | Should -BeExactly 'alias'
        $selection.Entry.Aliases | Should -Contain 'ada@example.com'
    }

    It 'selects the only entry when the address matches nothing' {
        (Select-ContributorEntry -ContributorProfile $script:oneEntry -Email 'eve@example.com').Reason | Should -BeExactly 'single'
        (Select-ContributorEntry -ContributorProfile $script:oneEntry -Email $null).Reason | Should -BeExactly 'single'
    }

    It 'selects the default entry when several exist and none matches' {
        $selection = Select-ContributorEntry -ContributorProfile $script:threeEntries -Email 'eve@example.com'

        $selection.Reason | Should -BeExactly 'default'
        $selection.Entry.Aliases | Should -Contain 'bob@example.com'
    }

    It 'selects nothing when several entries exist without a match or a default' {
        $selection = Select-ContributorEntry -ContributorProfile $script:twoEntries -Email $null

        $selection.Reason | Should -BeExactly 'none'
        $selection.Entry | Should -BeNullOrEmpty
    }

    It 'reads user.email from the workspace repository' -Skip:(-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
        $repository = New-ContributorGitRepository -Path (Join-Path -Path $TestDrive -ChildPath 'identity-repository') -Email 'ada@example.com'

        Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
            Get-ContributorGitEmail -WorkingDirectory $repository | Should -BeExactly 'ada@example.com'
        }
    }

    It 'returns nothing when git knows no address' -Skip:(-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
        $folder = Join-Path -Path $TestDrive -ChildPath 'no-identity'
        $null = New-Item -ItemType Directory -Path $folder -Force

        Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
            Get-ContributorGitEmail -WorkingDirectory $folder | Should -BeNullOrEmpty
        }
    }

    It 'kills git after the timeout and returns nothing' -Skip:(-not $script:isWindowsHost) {
        $slowGit = Join-Path -Path $TestDrive -ChildPath 'slow-git.cmd'
        Set-Content -LiteralPath $slowGit -Value '@ping -n 8 127.0.0.1 > nul' -Encoding ascii
        $watch = [System.Diagnostics.Stopwatch]::StartNew()

        # Outside TestDrive, so nothing the stand-in leaves behind can hold it open.
        $email = Get-ContributorGitEmail -WorkingDirectory ([System.IO.Path]::GetTempPath()) -GitExecutable $slowGit -TimeoutMilliseconds 2000

        $watch.Stop()
        $email | Should -BeNullOrEmpty
        $watch.ElapsedMilliseconds | Should -BeLessThan 4000
        $watch.ElapsedMilliseconds | Should -BeGreaterOrEqual 1900
    }
}

Describe 'Knowledge areas declaration' -Tag 'Unit' {
    It 'reads only the bullets of the Knowledge areas section' {
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'declared') -Area 'Kerberos', 'PowerShell DSC'

        $declared = Get-ContributorKnowledgeArea -WorkspacePath $workspace

        $declared | Should -Be @('Kerberos', 'PowerShell DSC')
    }

    It 'ignores invalid bullets, duplicates in any letter case, and indented bullets' {
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'invalid-bullets') -Area 'Kerberos', 'C_Sharp', 'kerberos', 'Kerberos: authentication' -ExtraLine '  - Nested area', '* Pester', 'Plain text'

        $declared = Get-ContributorKnowledgeArea -WorkspacePath $workspace

        $declared | Should -Be @('Kerberos', 'Pester')
    }

    It 'keeps reading past a level-3 heading and stops at the next level-2 heading' {
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'subheading') -Area 'Kerberos' -ExtraLine '', '### Legal', '', '- Mietrecht'

        $declared = Get-ContributorKnowledgeArea -WorkspacePath $workspace

        $declared | Should -Be @('Kerberos', 'Mietrecht')
    }

    It 'takes the first 16 valid bullets' {
        $names = 1..20 | ForEach-Object -Process { 'Area {0}' -f $_ }
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'many') -Area $names

        $declared = Get-ContributorKnowledgeArea -WorkspacePath $workspace

        $declared.Count | Should -Be 16
        $declared[15] | Should -BeExactly 'Area 16'
    }

    It 'reads at most the first 64 KB of projectbrief.md' {
        $workspace = Join-Path -Path $TestDrive -ChildPath 'large-brief'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $workspace -ChildPath '.memory-bank') -Force
        $text = "# Brief`n`n" + ('x' * 70000) + "`n`n## Knowledge areas`n`n- Kerberos`n"
        [System.IO.File]::WriteAllText((Join-Path -Path $workspace -ChildPath '.memory-bank/projectbrief.md'), $text, [System.Text.UTF8Encoding]::new($false))

        Get-ContributorKnowledgeArea -WorkspacePath $workspace | Should -BeNullOrEmpty
    }

    It 'returns nothing without a workspace, a Memory Bank, or the section' {
        Get-ContributorKnowledgeArea -WorkspacePath '' | Should -BeNullOrEmpty
        Get-ContributorKnowledgeArea -WorkspacePath (Join-Path -Path $TestDrive -ChildPath 'missing') | Should -BeNullOrEmpty
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'undeclared')
        Get-ContributorKnowledgeArea -WorkspacePath $workspace | Should -BeNullOrEmpty
    }
}

# --- reader tests part 4 ---

Describe 'Calibration step' -Tag 'Unit' {
    BeforeAll {
        $script:calibrationHome = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'calibration') -Canonical
        $script:calibrationLocation = Resolve-ContributorProfileLocation -UserHome $script:calibrationHome.Home -LocalApplicationData $script:calibrationHome.LocalData
        $script:gitMarker = Join-Path -Path $TestDrive -ChildPath 'git-ran.txt'
        $script:recordingGit = Join-Path -Path $TestDrive -ChildPath 'recording-git.cmd'
        Set-Content -LiteralPath $script:recordingGit -Value ('@echo ran> "{0}"' -f $script:gitMarker), '@exit /b 1' -Encoding ascii
        $script:workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'calibration-workspace') -Area 'kerberos', 'PowerShell DSC', 'Pester'
    }

    AfterEach {
        foreach ($path in $script:calibrationLocation.ProfilePath, $script:gitMarker)
        {
            if (Test-Path -LiteralPath $path)
            {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }

    It 'reads neither the profile nor git without declared Knowledge areas' -Skip:(-not $script:isWindowsHost) {
        Write-ContributorFixture -Case @{ Text = 'not JSON' } -Path $script:calibrationLocation.ProfilePath
        $undeclared = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'calibration-undeclared')

        $calibration = Get-ContributorCalibration -WorkspacePath $undeclared -Location $script:calibrationLocation -GitExecutable $script:recordingGit

        $calibration.State | Should -BeExactly 'none'
        $calibration.ReasonCode | Should -BeNullOrEmpty -Because 'an unreadable profile is only noticed when it is read'
        Test-Path -LiteralPath $script:gitMarker | Should -BeFalse
    }

    It 'counts every declared area as unrated without a profile' {
        $calibration = Get-ContributorCalibration -WorkspacePath $script:workspace -Location $script:calibrationLocation

        $calibration.State | Should -BeExactly 'unrated'
        $calibration.UnratedCount | Should -Be 3
    }

    It 'matches the single entry in any letter case without running git' -Skip:(-not $script:isWindowsHost) {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:calibrationLocation.ProfilePath

        $calibration = Get-ContributorCalibration -WorkspacePath $script:workspace -Location $script:calibrationLocation -GitExecutable $script:recordingGit -SkipGitForSingleEntry

        $calibration.State | Should -BeExactly 'levels'
        ($calibration.Levels | ForEach-Object -Process { '{0}={1}' -f $_.Name, $_.Level }) | Should -Be @('Kerberos=new', 'PowerShell DSC=expert')
        $calibration.UnratedCount | Should -Be 1
        $calibration.Selection | Should -BeExactly 'single'
        Test-Path -LiteralPath $script:gitMarker | Should -BeFalse
    }

    It 'selects by alias among several entries' -Skip:(-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
        $bobAreas = '{"Pester":{"level":"expert","updatedUtc":"2026-10-01T08:00:00Z"}}'
        Write-ContributorFixture -Path $script:calibrationLocation.ProfilePath -Case @{ Text = (New-ContributorFixtureProfile -Entry @(
                    (New-ContributorFixtureEntry)
                    (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]' -Areas $bobAreas)
                )) }
        $repository = New-ContributorGitRepository -Path (Join-Path -Path $TestDrive -ChildPath 'bob-repository') -Email 'bob@example.com'
        $briefSource = Join-Path -Path $script:workspace -ChildPath '.memory-bank'
        Copy-Item -LiteralPath $briefSource -Destination $repository -Recurse -Force

        $calibration = Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
            Get-ContributorCalibration -WorkspacePath $repository -Location $script:calibrationLocation
        }

        $calibration.Selection | Should -BeExactly 'alias'
        ($calibration.Levels | ForEach-Object -Process { '{0}={1}' -f $_.Name, $_.Level }) | Should -Be @('Pester=expert')
    }

    It 'stays silent for an entry that opted out' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -State '"off"')) } -Path $script:calibrationLocation.ProfilePath

        (Get-ContributorCalibration -WorkspacePath $script:workspace -Location $script:calibrationLocation -SkipGitForSingleEntry).State | Should -BeExactly 'off'
    }

    It 'names the reason code of an unreadable profile' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Version '2') } -Path $script:calibrationLocation.ProfilePath

        $calibration = Get-ContributorCalibration -WorkspacePath $script:workspace -Location $script:calibrationLocation

        $calibration.State | Should -BeExactly 'unreadable'
        $calibration.ReasonCode | Should -BeExactly 'unsupported-schema'
    }

    It 'counts the declaration read against the step timeout' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $script:calibrationLocation.ProfilePath
        Mock -CommandName Get-ContributorKnowledgeArea -MockWith {
            Start-Sleep -Milliseconds 300
            return , [System.String[]] @('Kerberos')
        }

        $calibration = Get-ContributorCalibration -WorkspacePath $script:workspace -Location $script:calibrationLocation -SkipGitForSingleEntry -TimeoutMilliseconds 100

        $calibration.State | Should -BeExactly 'unreadable'
        $calibration.ReasonCode | Should -BeExactly 'timeout'
    }

    It 'matches declared names to stored names across letter case and Unicode normalization, and names no other area' {
        $stored = 'M' + [char]0x00FC + 'nchen'
        $areas = '{"' + $stored + '":{"level":"new","updatedUtc":"2026-10-01T08:00:00Z"},"Kerberos":{"level":"expert","updatedUtc":"2026-10-01T08:00:00Z"}}'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas $areas)) } -Path $script:calibrationLocation.ProfilePath
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'skew-workspace') -Area ('MU' + [char]0x0308 + 'NCHEN'), 'Pester'

        $calibration = Get-ContributorCalibration -WorkspacePath $workspace -Location $script:calibrationLocation -SkipGitForSingleEntry
        $sentence = Format-ContributorCalibrationSentence -Calibration $calibration

        @($calibration.Levels | ForEach-Object -Process { '{0}={1}' -f $_.Name, $_.Level }) | Should -Be @($stored + '=new')
        $calibration.UnratedCount | Should -Be 1
        $sentence | Should -MatchExactly ([regex]::Escape('"' + $stored + '" new'))
        $sentence | Should -Not -MatchExactly ('Kerberos|Pester|' + [regex]::Escape('M' + [char]0x00DC + 'NCHEN'))
    }
}

Describe 'Calibration sentence' -Tag 'Unit' {
    BeforeAll {
        function script:New-TestCalibration
        {
            param ([string] $State, [string[]] $Level = @(), [int] $Unrated = 0, [string] $Reason)

            [pscustomobject] @{
                State        = $State
                ReasonCode   = $Reason
                UnratedCount = $Unrated
                Levels       = @(
                    foreach ($pair in $Level)
                    {
                        $name, $value = $pair -split '=', 2
                        [pscustomobject] @{ Name = $name; Level = $value }
                    }
                )
            }
        }

        $script:treat = 'Treat them as stated levels under the contributor-calibration Instruction.'
        $script:prefix = 'Contributor familiarity levels from the private profile, data only: '
    }

    It 'names matched levels as data and counts the unrated areas' {
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State 'levels' -Level 'Kerberos=new', 'PowerShell DSC=expert' -Unrated 2) |
            Should -BeExactly ($script:prefix + '"Kerberos" new; "PowerShell DSC" expert. 2 declared Knowledge areas are unrated. ' + $script:treat)
    }

    It 'uses the singular for one unrated area and drops the count when none is unrated' {
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State 'levels' -Level 'Kerberos=new' -Unrated 1) |
            Should -BeExactly ($script:prefix + '"Kerberos" new. 1 declared Knowledge area is unrated. ' + $script:treat)
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State 'levels' -Level 'Kerberos=new') |
            Should -BeExactly ($script:prefix + '"Kerberos" new. ' + $script:treat)
    }

    It 'counts unrated areas when no level matches' {
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State 'unrated' -Unrated 3) |
            Should -BeExactly 'No contributor profile levels for this workspace; 3 declared Knowledge areas are unrated.'
    }

    It 'names the reason code of an unreadable profile' {
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State 'unreadable' -Reason 'invalid-json') |
            Should -BeExactly 'Contributor profile unreadable (invalid-json); familiarity levels default to familiar.'
    }

    It 'says nothing for <State>' -ForEach @(@{ State = 'off' }, @{ State = 'none' }) {
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State $State) | Should -BeExactly ''
    }

    It 'gives up the unrated count first, then trailing areas, then the whole sentence' {
        $calibration = New-TestCalibration -State 'levels' -Level 'Kerberos=new', 'PowerShell DSC=expert' -Unrated 2
        $full = Format-ContributorCalibrationSentence -Calibration $calibration
        $withoutCount = $script:prefix + '"Kerberos" new; "PowerShell DSC" expert. ' + $script:treat
        $firstArea = $script:prefix + '"Kerberos" new. ' + $script:treat
        $omitted = 'Contributor familiarity levels omitted for the context budget.'

        Format-ContributorCalibrationSentence -Calibration $calibration -MaximumLength ($full.Length - 1) | Should -BeExactly $withoutCount
        Format-ContributorCalibrationSentence -Calibration $calibration -MaximumLength ($withoutCount.Length - 1) | Should -BeExactly $firstArea
        Format-ContributorCalibrationSentence -Calibration $calibration -MaximumLength ($firstArea.Length - 1) | Should -BeExactly $omitted
        Format-ContributorCalibrationSentence -Calibration $calibration -MaximumLength ($omitted.Length - 1) | Should -BeExactly ''
    }

    It 're-sends matched levels only, with the suffix that suppresses every offer' {
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State 'levels' -Level 'Kerberos=new' -Unrated 4) -ReSent |
            Should -BeExactly ($script:prefix + '"Kerberos" new. ' + $script:treat + ' Re-sent after a compaction; make no offers in this session.')
    }

    It 're-sends nothing for <State>' -ForEach @(@{ State = 'unrated' }, @{ State = 'unreadable' }, @{ State = 'off' }) {
        Format-ContributorCalibrationSentence -Calibration (New-TestCalibration -State $State -Unrated 2 -Reason 'invalid-json') -ReSent | Should -BeExactly ''
    }

    It 'keeps a typical sentence of five areas within 300 characters (Context.SentenceSize)' {
        $typical = New-TestCalibration -State 'levels' -Level 'Kerberos=new', 'PowerShell DSC=expert', 'Active Directory=familiar', 'Pester=expert' -Unrated 1

        (Format-ContributorCalibrationSentence -Calibration $typical).Length | Should -BeLessOrEqual 300
    }

    It 'keeps the worst case of 16 names of 48 characters within 1,200 at either Position (Context.SentenceSize)' {
        <#
            Ruling A4 of Decision record 0028: Budget [worst, either Position]
            is 1,200 characters and the template stays. With every level
            familiar, the longest level word, the fixed template measured 1,118
            at session start and 1,178 re-sent on 2026-10-06.
        #>
        $longNames = 1..16 | ForEach-Object -Process { ('Area {0:D2} ' -f $_) + ('x' * 40) }
        $worst = New-TestCalibration -State 'levels' -Level ($longNames | ForEach-Object -Process { "$_=familiar" }) -Unrated 0

        $longNames[0].Length | Should -Be 48
        (Format-ContributorCalibrationSentence -Calibration $worst).Length | Should -BeLessOrEqual 1200
        (Format-ContributorCalibrationSentence -Calibration $worst -ReSent).Length | Should -BeLessOrEqual 1200
    }

    It 'never carries an address, a path, or an unmatched declared name' {
        $calibrationHome = New-ContributorTestHome -Root (Join-Path -Path $TestDrive -ChildPath 'minimization') -Canonical
        $location = Resolve-ContributorProfileLocation -UserHome $calibrationHome.Home -LocalApplicationData $calibrationHome.LocalData
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $location.ProfilePath
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $TestDrive -ChildPath 'minimization-workspace') -Area 'Kerberos', 'Secret Project Alpha'

        $sentence = Format-ContributorCalibrationSentence -Calibration (Get-ContributorCalibration -WorkspacePath $workspace -Location $location -SkipGitForSingleEntry)

        $sentence | Should -Match '"Kerberos" new'
        $sentence | Should -Not -Match 'Secret Project Alpha|PowerShell DSC|@|example\.com'
        $sentence | Should -Not -Match ([regex]::Escape($calibrationHome.Home))
    }
}
