BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    . (Join-Path $script:projectPath 'tests/Helpers/ContributorProfileFixture.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:emptyGitConfig = Join-Path $TestDrive 'empty.gitconfig'
    Set-Content -LiteralPath $script:emptyGitConfig -Value '' -Encoding ascii
    $script:gitIsolation = @{ GIT_CONFIG_GLOBAL = $script:emptyGitConfig; GIT_CONFIG_NOSYSTEM = '1' }

    function script:Get-OwnedFileState
    {
        param ([string] $TargetPath)

        @(Get-ChildItem -LiteralPath $TargetPath -Recurse -File -Force |
                Where-Object -FilterScript { $_.FullName -notmatch '[\\/]contributor[\\/]' } |
                ForEach-Object -Process { '{0}:{1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName).Hash })
    }

    function script:Set-TestLevel
    {
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Push-Location -LiteralPath $folder
        try
        {
            Use-ContributorEnvironment -Variable $script:gitIsolation -ScriptBlock {
                $null = Set-CopilotAtelierContributorProfile -KnowledgeArea 'Kerberos' -Level 'new' -Confirm:$false
            }
        }
        finally
        {
            Pop-Location
        }
    }
}

Describe 'Uninstall-CopilotAtelier' -Tag 'Unit' {
    BeforeEach {
        $script:profile = New-CopilotAtelierTestProfile -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -ProjectPath $script:projectPath
        $script:installation = Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment
        $script:recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
    }

    AfterEach {
        Restore-CopilotAtelierTestProfile -Original $script:profile.Original
    }

    It 'Should remove owned files and empty Discovery links but preserve user configuration' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $settingsHash = (Get-FileHash -LiteralPath $script:installation.SettingsPath).Hash

        $result = Uninstall-CopilotAtelier -Confirm:$false

        $result.RemovedFiles.Count | Should -BeGreaterThan 4
        Test-Path -LiteralPath $script:profile.TargetPath | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:profile.CopilotRoot 'skills') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:profile.CopilotRoot -Force) | Should -HaveCount 0
        (Get-FileHash -LiteralPath $script:installation.SettingsPath).Hash | Should -Be $settingsHash
        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Not -Throw
    }

    It 'Should preserve modified files and untracked files with their Discovery link' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $modifiedFile = Join-Path $script:profile.TargetPath 'skills/marker.md'
        $personalFile = Join-Path $script:profile.TargetPath 'skills/personal.md'
        Set-Content -LiteralPath $modifiedFile -Value 'modified workflow'
        Set-Content -LiteralPath $personalFile -Value 'personal workflow'

        $result = Uninstall-CopilotAtelier -Confirm:$false

        Get-Content -LiteralPath $modifiedFile -Raw | Should -Match 'modified workflow'
        Get-Content -LiteralPath $personalFile -Raw | Should -Match 'personal workflow'
        $result.PreservedFiles | Should -Contain 'skills/marker.md'
        Test-Path -LiteralPath (Join-Path $script:profile.CopilotRoot 'skills') | Should -BeTrue
        Test-Path -LiteralPath $script:recordPath | Should -BeTrue
    }

    It 'Should make no filesystem changes under WhatIf' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $before = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" })

        Uninstall-CopilotAtelier -WhatIf | Out-Null

        $after = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" })
        $after | Should -Be $before
    }

    It 'Should preserve a legacy deployment with no ownership hashes' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        '{"Version":"1.0.0","ContentPath":"old"}' | Set-Content -LiteralPath $script:recordPath

        $result = Uninstall-CopilotAtelier -Confirm:$false

        $result.RemovedFiles.Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'skills/marker.md') | Should -BeTrue
    }

    It 'Should reject unsafe record path <Path> before deleting anything' -ForEach @(
        @{ Path = '../outside.md' }
        @{ Path = 'skills/../../outside.md' }
        @{ Path = 'skills/marker.md:stream' }
        @{ Path = 'skills\marker.md' }
        @{ Path = 'skills//marker.md' }
        @{ Path = 'skills/marker.md.' }
        @{ Path = 'skills/NUL' }
        @{ Path = '/skills/marker.md' }
    ) {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $record = Get-Content -LiteralPath $script:recordPath -Raw | ConvertFrom-Json
        $record.Files[-1].Path = $Path
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:recordPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*Invalid Deployment record*'

        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
    }

    It 'Should refuse a reparse-point directory without following it' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $skillPath = Join-Path $script:profile.TargetPath 'skills'
        $outside = Join-Path $TestDrive 'outside-uninstall'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'marker.md') -Value 'outside content'
        Remove-Item -LiteralPath $skillPath -Recurse -Force
        $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $skillPath -Target $outside | Out-Null
        try
        {
            { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*reparse point*'
            Get-Content -LiteralPath (Join-Path $outside 'marker.md') -Raw | Should -Match 'outside content'
            Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
        }
        finally
        {
            [IO.Directory]::Delete($skillPath, $false)
        }
    }

    It 'Should reject invalid ownership metadata <Case> before deleting files' -ForEach @(
        @{ Case = 'string schema'; Change = { param($Record) $Record.SchemaVersion = '1' } }
        @{ Case = 'Boolean schema'; Change = { param($Record) $Record.SchemaVersion = $true } }
        @{ Case = 'future schema'; Change = { param($Record) $Record.SchemaVersion = 2 } }
        @{ Case = 'duplicate path'; Change = { param($Record) $Record.Files[-1].Path = $Record.Files[0].Path } }
        @{ Case = 'invalid hash'; Change = { param($Record) $Record.Files[0].Sha256 = 'invalid' } }
    ) {
        $record = Get-Content -LiteralPath $script:recordPath -Raw | ConvertFrom-Json
        & $Change $record
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:recordPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*Invalid Deployment record*'
        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
    }

    It 'Should reject a singleton array instead of treating its element as the record' {
        $recordText = Get-Content -LiteralPath $script:recordPath -Raw
        ('[' + $recordText + ']') | Set-Content -LiteralPath $script:recordPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*Invalid Deployment record*'
        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
    }

    It 'Should reject a filesystem root even during a preview' {
        { Uninstall-CopilotAtelier -TargetPath ([IO.Path]::GetPathRoot($TestDrive)) -WhatIf } |
            Should -Throw -ExpectedMessage '*filesystem root*'
    }
}

Describe 'Uninstall-CopilotAtelier with a contributor profile' -Tag 'Unit' {
    BeforeEach {
        $script:profile = New-CopilotAtelierTestProfile -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -ProjectPath $script:projectPath
        $null = Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment -Confirm:$false
        $script:contributorFolder = Join-Path $script:profile.TargetPath 'contributor'
        $script:registrationPath = Join-Path $script:profile.CopilotRoot 'hooks/contributor-profile.json'
    }

    AfterEach {
        Restore-CopilotAtelierTestProfile -Original $script:profile.Original
    }

    It 'Should remove an unchanged registration first and keep the profile as personal content' {
        Set-TestLevel
        Test-Path -LiteralPath $script:registrationPath | Should -BeTrue
        $profilePath = Join-Path $script:contributorFolder 'profile.json'
        $profileHash = (Get-FileHash -LiteralPath $profilePath).Hash

        # Uninstall reads only the registration record, so a lock on the profile cannot stop it.
        $lock = [System.IO.FileStream]::new($profilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try
        {
            $result = Uninstall-CopilotAtelier -Confirm:$false
        }
        finally
        {
            $lock.Dispose()
        }

        $result.ContributorRegistration | Should -Be 'removed'
        Test-Path -LiteralPath (Join-Path $script:contributorFolder 'registration.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'hooks/scripts/Add-FamiliarityContext.ps1') | Should -BeFalse
        (Get-FileHash -LiteralPath $profilePath).Hash | Should -Be $profileHash
    }

    It 'Should stop before removing anything when a foreign registration exists' {
        Set-Content -LiteralPath $script:registrationPath -Value '{"hooks":{}}' -Encoding ascii
        $before = Get-OwnedFileState -TargetPath $script:profile.TargetPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*stopped before removing anything*contributor-profile.json*foreign*'

        Get-OwnedFileState -TargetPath $script:profile.TargetPath | Should -Be $before
    }

    It 'Should stop before removing anything while a registration record waits for its file' {
        # OneDrive delivered the record of a registration another machine created, but not the file yet.
        New-Item -ItemType Directory -Path $script:contributorFolder -Force | Out-Null
        $recordPath = Join-Path $script:contributorFolder 'registration.json'
        Set-Content -LiteralPath $recordPath -Encoding ascii -Value ('{{"schemaVersion":1,"operation":"create","state":"complete","sha256":"{0}","updatedUtc":"2026-10-06T09:00:00Z"}}' -f ('A' * 64))
        $record = Get-Content -LiteralPath $recordPath -Raw
        $before = Get-OwnedFileState -TargetPath $script:profile.TargetPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*stopped before removing anything*contributor-profile.json*pending*'

        Get-OwnedFileState -TargetPath $script:profile.TargetPath | Should -Be $before
        Get-Content -LiteralPath $recordPath -Raw | Should -Be $record
    }

    It 'Should remove an owned registration that an earlier template wrote' {
        Set-TestLevel
        $recordPath = Join-Path $script:contributorFolder 'registration.json'
        $earlier = (Get-Content -LiteralPath $script:registrationPath -Raw).Replace('"timeout": 20', '"timeout": 25')
        [System.IO.File]::WriteAllText($script:registrationPath, $earlier, [System.Text.UTF8Encoding]::new($false))
        $earlierHash = (Get-FileHash -LiteralPath $script:registrationPath).Hash
        Set-Content -LiteralPath $recordPath -Encoding ascii -Value ('{{"schemaVersion":1,"operation":"create","state":"complete","sha256":"{0}","updatedUtc":"2026-10-06T09:00:00Z"}}' -f $earlierHash)

        $result = Uninstall-CopilotAtelier -Confirm:$false

        $result.ContributorRegistration | Should -Be 'removed'
        Test-Path -LiteralPath $script:registrationPath | Should -BeFalse
        Test-Path -LiteralPath $recordPath | Should -BeFalse
    }

    It 'Should stop before removing anything while another writer holds the profile lock' {
        Set-TestLevel
        $before = Get-OwnedFileState -TargetPath $script:profile.TargetPath
        $lock = [System.IO.FileStream]::new((Join-Path $script:contributorFolder 'profile.lock'), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

        try
        {
            { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*stopped before removing anything*locked*'
        }
        finally
        {
            $lock.Dispose()
        }

        Get-OwnedFileState -TargetPath $script:profile.TargetPath | Should -Be $before
        Test-Path -LiteralPath $script:registrationPath | Should -BeTrue
    }

    It 'Should leave the contributor folder unread and unchanged on reinstall and repair' {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path (Join-Path $script:contributorFolder 'profile.json')
        Set-Content -LiteralPath (Join-Path $script:contributorFolder 'registration.json') -Value 'record' -Encoding ascii
        $before = @(Get-ChildItem -LiteralPath $script:contributorFolder -File | ForEach-Object -Process { '{0}:{1}' -f $_.Name, (Get-FileHash -LiteralPath $_.FullName).Hash })
        $locks = foreach ($name in 'profile.json', 'registration.json')
        {
            [System.IO.FileStream]::new((Join-Path $script:contributorFolder $name), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        }

        try
        {
            { Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment -Confirm:$false } | Should -Not -Throw
            { Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment -Repair -Confirm:$false } | Should -Not -Throw
        }
        finally
        {
            $locks | ForEach-Object -Process { $_.Dispose() }
        }

        @(Get-ChildItem -LiteralPath $script:contributorFolder -File | ForEach-Object -Process { '{0}:{1}' -f $_.Name, (Get-FileHash -LiteralPath $_.FullName).Hash }) | Should -Be $before
    }
}
