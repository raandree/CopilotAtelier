<#
    The contributor-profile hooks of Decision record 0028, run as the hosts run
    them: a child process of each PowerShell edition fed the payload on
    standard input. Covers the SessionStart sentence, the PreCompact counter,
    the PostToolUse re-injection, the session clock path every script derives,
    the registration template, and the agreement of every entry point on the
    shared fixture set.
#>

BeforeDiscovery {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
    $script:isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:editions = @(
        @{ Edition = 'PowerShell 7'; Executable = (Get-Command -Name 'pwsh' -CommandType Application | Select-Object -First 1 -ExpandProperty Source) }
        if ($script:isWindowsHost)
        {
            @{ Edition = 'Windows PowerShell 5.1'; Executable = (Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe') }
        }
    )
    $script:fixtureCases = @(Get-ContributorProfileFixtureCase)
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:hookRoot = Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/scripts'
    . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
    $script:isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:emptyGitConfig = Join-Path -Path $TestDrive -ChildPath 'empty.gitconfig'
    Set-Content -LiteralPath $script:emptyGitConfig -Value '' -Encoding ascii

    function script:Invoke-Hook
    {
        <#
            Runs one hook script in a fresh process of the given edition, the
            payload on standard input, and returns the exit code, the raw
            output, and the parsed JSON object when there is one.
        #>
        param
        (
            [string] $Executable,
            [string] $Script,
            [hashtable] $Payload,
            [hashtable] $Environment = @{},
            [string[]] $Argument = @()
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable)
        $startInfo.Arguments = (@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $Script)) + @($Argument | ForEach-Object -Process { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } })) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        foreach ($name in $Environment.Keys)
        {
            $startInfo.EnvironmentVariables[$name] = [string] $Environment[$name]
        }

        $process = [System.Diagnostics.Process]::Start($startInfo)
        try
        {
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($Payload | ConvertTo-Json -Depth 6 -Compress))
            $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(60000))
            {
                $process.Kill()
                throw "$Script did not exit within 60 seconds."
            }

            $process.WaitForExit()
            $output = $outputTask.Result.Trim()
            $json = $null
            if ($output.StartsWith('{') -or $output.StartsWith('['))
            {
                $json = $output | ConvertFrom-Json
            }

            [pscustomobject] @{ ExitCode = $process.ExitCode; Output = $output; Error = $errorTask.Result; Json = $json }
        }
        finally
        {
            $process.Dispose()
        }
    }

    function script:New-HookFixture
    {
        <#
            A deployed-layout home with a profile, a workspace declaring areas,
            a clock root, and the environment a hook process needs.
        #>
        param ([string[]] $Area = @('Kerberos', 'PowerShell DSC', 'Pester'), [string] $ProfileText, [switch] $WithoutScript)

        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $layout = New-ContributorTestHome -Root $root -Canonical -WithFamiliarityScript:(-not $WithoutScript)
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $root -ChildPath 'workspace') -Area $Area
        $clockRoot = Join-Path -Path $root -ChildPath 'clock'
        $profilePath = Join-Path -Path $layout.CanonicalFolder -ChildPath 'profile.json'
        if ($ProfileText)
        {
            Write-ContributorFixture -Case @{ Text = $ProfileText } -Path $profilePath
        }

        [pscustomobject] @{
            Layout      = $layout
            Workspace   = $workspace
            ClockRoot   = $clockRoot
            ProfilePath = $profilePath
            SessionId   = [guid]::NewGuid().ToString()
            Environment = @{
                USERPROFILE                                 = $layout.Home
                HOME                                        = $layout.Home
                LOCALAPPDATA                                = $layout.LocalData
                GIT_CONFIG_GLOBAL                           = $script:emptyGitConfig
                GIT_CONFIG_NOSYSTEM                         = '1'
                COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS = $null
            }
        }
    }

    function script:Get-StatePath
    {
        param ($Fixture)

        Join-Path -Path $Fixture.ClockRoot -ChildPath ('session-{0}.familiarity.json' -f $Fixture.SessionId)
    }

    $script:sessionStart = Join-Path -Path $script:hookRoot -ChildPath 'Add-SessionContext.ps1'
    $script:preCompact = Join-Path -Path $script:hookRoot -ChildPath 'Write-CompactionCheckpoint.ps1'
    $script:postToolUse = Join-Path -Path $script:hookRoot -ChildPath 'Add-FamiliarityContext.ps1'
    $script:stop = Join-Path -Path $script:hookRoot -ChildPath 'Write-SessionClose.ps1'

    function script:Invoke-Event
    {
        <#
            Runs one lifecycle hook of the fixture's session in the edition the
            calling Describe names in $Executable.
        #>
        param ($Fixture, [string] $Event, [hashtable] $Override = @{}, [string] $Source = 'new')

        $script = switch ($Event)
        {
            'SessionStart' { $script:sessionStart }
            'PreCompact' { $script:preCompact }
            'PostToolUse' { $script:postToolUse }
            'Stop' { $script:stop }
        }

        $payload = @{ hook_event_name = $Event; session_id = $Fixture.SessionId; cwd = $Fixture.Workspace }
        if ($Event -eq 'PreCompact') { $payload.trigger = 'manual'; $payload.custom_instructions = '' }
        if ($Event -eq 'PostToolUse') { $payload.tool_name = 'view'; $payload.tool_input = @{ path = 'x' }; $payload.tool_result = @{ result_type = 'success'; text_result_for_llm = ('y' * 5000) } }
        if ($Event -eq 'SessionStart') { $payload.source = $Source }
        if ($Event -eq 'Stop') { $payload.stop_hook_active = $false }

        $environment = $Fixture.Environment.Clone()
        foreach ($name in $Override.Keys) { $environment[$name] = $Override[$name] }

        Invoke-Hook -Executable $Executable -Script $script -Payload $payload -Environment $environment -Argument '-ClockRoot', $Fixture.ClockRoot
    }

    function script:Get-State
    {
        param ($Fixture)

        Get-Content -LiteralPath (Get-StatePath -Fixture $Fixture) -Raw | ConvertFrom-Json
    }

    function script:Set-State
    {
        <#
            Writes the calibration state of the fixture's session as a hook
            would find it, for the cases a real session takes too long to reach.
        #>
        param ($Fixture, [System.Collections.IDictionary] $State)

        $null = New-Item -ItemType Directory -Path $Fixture.ClockRoot -Force
        [System.IO.File]::WriteAllText((Get-StatePath -Fixture $Fixture), ($State | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
    }

    function script:Get-ClockPath
    {
        param ($Fixture)

        Join-Path -Path $Fixture.ClockRoot -ChildPath ('session-{0}.json' -f $Fixture.SessionId)
    }

    function script:Set-ClockTurn
    {
        <# Stands in for the Stop hook: a session clock whose closed turn count is Turn. #>
        param ($Fixture, [int] $Turn)

        $null = New-Item -ItemType Directory -Path $Fixture.ClockRoot -Force
        $clock = [ordered] @{ startedUtc = [System.DateTime]::UtcNow.AddMinutes(-30).ToString('o'); workspace = $Fixture.Workspace; turns = $Turn }
        [System.IO.File]::WriteAllText((Get-ClockPath -Fixture $Fixture), ($clock | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
    }

    function script:Get-StateField
    {
        <# One field of the state file as written, so a timestamp is compared as text in every edition. #>
        param ($Fixture, [string] $Name)

        $match = [regex]::Match([System.IO.File]::ReadAllText((Get-StatePath -Fixture $Fixture)), ('"{0}"\s*:\s*("[^"]*"|-?\d+|null)' -f [regex]::Escape($Name)))
        if ($match.Success) { $match.Groups[1].Value } else { $null }
    }

    $script:prefix = 'Contributor familiarity levels from the private profile, data only: '
    $script:treat = 'Treat them as stated levels under the contributor-calibration Instruction.'
}

Describe 'SessionStart calibration sentence in <Edition>' -Tag 'Unit' -ForEach $script:editions {
    BeforeAll {
        $script:sessionStart = Join-Path -Path $script:hookRoot -ChildPath 'Add-SessionContext.ps1'

        function script:Invoke-SessionStart
        {
            param ($Fixture, [hashtable] $Override = @{}, [switch] $WithoutCwd)

            $payload = @{ hook_event_name = 'SessionStart'; session_id = $Fixture.SessionId; source = 'new' }
            if (-not $WithoutCwd)
            {
                $payload.cwd = $Fixture.Workspace
            }

            $environment = $Fixture.Environment.Clone()
            foreach ($name in $Override.Keys)
            {
                $environment[$name] = $Override[$name]
            }

            Invoke-Hook -Executable $Executable -Script $script:sessionStart -Payload $payload -Environment $environment -Argument '-ClockRoot', $Fixture.ClockRoot
        }
    }

    It 'appends the matched levels as data after the existing lines, under both host keys' {
        $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)

        $result = Invoke-SessionStart -Fixture $fixture

        $result.ExitCode | Should -Be 0
        $context = $result.Json.additionalContext
        $context | Should -BeExactly $result.Json.hookSpecificOutput.additionalContext
        $context | Should -Match ('Never push or otherwise mutate a git remote unless the user asks in the current turn\. ' + [regex]::Escape($script:prefix))
        $context | Should -Match ([regex]::Escape('"Kerberos" new; "PowerShell DSC" expert. 1 declared Knowledge area is unrated. ' + $script:treat) + '\z')
    }

    It 'counts unrated areas without a profile' {
        $fixture = New-HookFixture

        (Invoke-SessionStart -Fixture $fixture).Json.additionalContext |
            Should -Match ([regex]::Escape('No contributor profile levels for this workspace; 3 declared Knowledge areas are unrated.') + '\z')
    }

    It 'names the reason code of an unreadable profile' {
        $fixture = New-HookFixture -ProfileText '{"schemaVersion":1,'

        (Invoke-SessionStart -Fixture $fixture).Json.additionalContext |
            Should -Match ([regex]::Escape('Contributor profile unreadable (invalid-json); familiarity levels default to familiar.') + '\z')
    }

    It 'adds nothing for <Why>' -ForEach @(
        @{ Why = 'an entry that opted out'; Off = $true; Area = @('Kerberos'); WithoutCwd = $false }
        @{ Why = 'a workspace without declared areas'; Off = $false; Area = @(); WithoutCwd = $false }
        @{ Why = 'a payload without cwd'; Off = $false; Area = @('Kerberos'); WithoutCwd = $true }
    ) {
        $text = if ($Off) { New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -State '"off"') } else { New-ContributorFixtureProfile }
        $fixture = New-HookFixture -Area $Area -ProfileText $text

        $result = Invoke-SessionStart -Fixture $fixture -WithoutCwd:$WithoutCwd

        $result.ExitCode | Should -Be 0
        $result.Json.additionalContext | Should -Not -Match 'Contributor|contributor profile'
    }

    It 'neither reads the profile nor runs git without declared areas' -Skip:(-not $script:isWindowsHost) {
        $twoEntries = New-ContributorFixtureProfile -Entry @(
            (New-ContributorFixtureEntry)
            (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]')
        )
        $gitFolder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $marker = Join-Path -Path $gitFolder -ChildPath 'ran.txt'
        $null = New-Item -ItemType Directory -Path $gitFolder -Force
        Set-Content -LiteralPath (Join-Path -Path $gitFolder -ChildPath 'git.cmd') -Value ('@echo ran>> "{0}"' -f $marker), '@exit /b 1' -Encoding ascii
        $path = @{ PATH = $gitFolder + [System.IO.Path]::PathSeparator + $env:PATH }

        $undeclared = New-HookFixture -Area @() -ProfileText $twoEntries
        $declared = New-HookFixture -ProfileText $twoEntries

        $null = Invoke-SessionStart -Fixture $undeclared -Override $path
        Test-Path -LiteralPath $marker | Should -BeFalse -Because 'a workspace without declared areas must not run git'

        $null = Invoke-SessionStart -Fixture $declared -Override $path
        Test-Path -LiteralPath $marker | Should -BeTrue -Because 'the recording git proves this test can observe a run'
    }

    It 'gives the sentence the lowest budget priority and never shortens an existing line' {
        $names = 1..16 | ForEach-Object -Process { ('Area {0:D2} ' -f $_) + ('x' * 40) }
        $areas = '{' + (($names | ForEach-Object -Process { '"{0}":{{"level":"expert","updatedUtc":"2026-10-01T08:00:00Z"}}' -f $_ }) -join ',') + '}'
        $fixture = New-HookFixture -Area $names -ProfileText (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas $areas))
        $plain = New-HookFixture -Area @()
        $limit = @{ COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS = '1024' }

        $withSentence = (Invoke-SessionStart -Fixture $fixture -Override $limit).Json.additionalContext
        $withoutSentence = (Invoke-SessionStart -Fixture $plain -Override $limit).Json.additionalContext

        $withSentence.Length | Should -BeLessOrEqual 1024
        $existing = $withSentence.Substring(0, $withSentence.IndexOf('Contributor familiarity levels'))
        $existing.TrimEnd() -replace [regex]::Escape($fixture.Workspace), '<ws>' -replace '\d{4}-\d{2}-\d{2} \d{2}:\d{2}', '<t>' |
            Should -BeExactly ($withoutSentence -replace [regex]::Escape($plain.Workspace), '<ws>' -replace '\d{4}-\d{2}-\d{2} \d{2}:\d{2}', '<t>')
        $withSentence | Should -Match '"Area 01 x+" expert'
        $withSentence | Should -Not -Match '"Area 16 x+"' -Because 'trailing areas give way first under a tight budget'
    }

    It 'never puts an alias, the profile path, or an unmatched declared name into its output' {
        $fixture = New-HookFixture -Area 'Kerberos', 'Secret Project Alpha' -ProfileText (New-ContributorFixtureProfile)

        $output = (Invoke-SessionStart -Fixture $fixture).Output

        $output | Should -Match '\\"Kerberos\\" new|"Kerberos\\?" new'
        $output | Should -Not -Match 'ada@example\.com|Secret Project Alpha|PowerShell DSC|contributor\\\\profile\.json|contributor/profile\.json'
    }
}

# --- hook tests part 2 ---

Describe 'Compaction re-injection in <Edition>' -Tag 'Unit' -ForEach $script:editions {
    It 'counts a compaction in the calibration state beside the clock and never rewrites the clock' {
        $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
        $null = Invoke-Event -Fixture $fixture -Event 'SessionStart'
        $clockPath = Join-Path -Path $fixture.ClockRoot -ChildPath ('session-{0}.json' -f $fixture.SessionId)
        $clockBefore = [System.IO.File]::ReadAllBytes($clockPath)

        $result = Invoke-Event -Fixture $fixture -Event 'PreCompact'

        $result.ExitCode | Should -Be 0
        $state = Get-State -Fixture $fixture
        $state.compactions | Should -Be 1
        $state.injected | Should -Be 0
        [System.IO.File]::ReadAllBytes($clockPath) | Should -Be $clockBefore
    }

    It 're-sends the levels on the first tool call after it, under both host keys, then stays silent' {
        $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
        $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'

        $first = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
        $second = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

        $first.ExitCode | Should -Be 0
        $expected = $script:prefix + '"Kerberos" new; "PowerShell DSC" expert. ' + $script:treat + ' Re-sent after a compaction; make no offers in this session.'
        $first.Json.additionalContext | Should -BeExactly $expected
        $first.Json.hookSpecificOutput.additionalContext | Should -BeExactly $expected
        $first.Json.hookSpecificOutput.hookEventName | Should -BeExactly 'PostToolUse'
        $first.Json.PSObject.Properties.Name | Should -Not -Contain 'decision'
        $second.ExitCode | Should -Be 0
        $second.Output | Should -BeNullOrEmpty
        (Get-State -Fixture $fixture).injected | Should -Be 1
    }

    It 'stays silent without a pending compaction' {
        $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)

        $result = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -BeNullOrEmpty
    }

    It 'rechecks the profile, so an opt-out after the compaction sends nothing' {
        $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
        $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -State '"off"')) } -Path $fixture.ProfilePath

        $result = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

        $result.Output | Should -BeNullOrEmpty
        (Get-State -Fixture $fixture).injected | Should -Be 1 -Because 'an answered compaction keeps later calls on the short path'
    }

    It 'never loses a newer compaction to a stale PostToolUse write' -Skip:(-not $script:isWindowsHost) {
        $twoEntries = New-ContributorFixtureProfile -Entry @(
            (New-ContributorFixtureEntry -Default 'true')
            (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]')
        )
        $fixture = New-HookFixture -ProfileText $twoEntries
        $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'

        # A slow git marks the moment the PostToolUse hook has read the state and
        # started its calibration; PreCompact then records a newer compaction.
        $gitFolder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $marker = Join-Path -Path $gitFolder -ChildPath 'started.txt'
        $null = New-Item -ItemType Directory -Path $gitFolder -Force
        Set-Content -LiteralPath (Join-Path -Path $gitFolder -ChildPath 'git.cmd') -Value ('@echo started> "{0}"' -f $marker), '@ping -n 4 127.0.0.1 > nul' -Encoding ascii

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ClockRoot "{1}"' -f $script:postToolUse, $fixture.ClockRoot))
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($name in $fixture.Environment.Keys)
        {
            $startInfo.EnvironmentVariables[$name] = [string] $fixture.Environment[$name]
        }

        $startInfo.EnvironmentVariables['PATH'] = $gitFolder + [System.IO.Path]::PathSeparator + $env:PATH
        $stale = [System.Diagnostics.Process]::Start($startInfo)
        try
        {
            $staleOutput = $stale.StandardOutput.ReadToEndAsync()
            $null = $stale.StandardError.ReadToEndAsync()
            $stale.StandardInput.Write((@{ hook_event_name = 'PostToolUse'; session_id = $fixture.SessionId; cwd = $fixture.Workspace; tool_name = 'view' } | ConvertTo-Json -Compress))
            $stale.StandardInput.Close()

            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not (Test-Path -LiteralPath $marker) -and $watch.ElapsedMilliseconds -lt 20000)
            {
                Start-Sleep -Milliseconds 50
            }

            Test-Path -LiteralPath $marker | Should -BeTrue -Because 'the PostToolUse hook must have read the state and reached its calibration step'
            $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'
            $stale.WaitForExit(60000) | Should -BeTrue
            $stale.WaitForExit()
        }
        finally
        {
            $stale.Dispose()
        }

        $staleOutput.Result | Should -Match 'Re-sent after a compaction' -Because 'the stale call still answers the compaction it read'
        $state = Get-State -Fixture $fixture
        $state.compactions | Should -Be 2
        $state.injected | Should -Be 1

        $again = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
        $again.Json.additionalContext | Should -Match 'Re-sent after a compaction'
        (Get-State -Fixture $fixture).injected | Should -Be 2
    }

    It 'exits 0 and stays silent for <Why>' -ForEach @(
        @{ Why = 'a payload that is not JSON'; Text = 'not json' }
        @{ Why = 'an empty payload'; Text = '' }
    ) {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $script:postToolUse))
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $process.StandardInput.Write($Text)
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()

        $process.ExitCode | Should -Be 0
        $output.Trim() | Should -BeNullOrEmpty
    }
}

Describe 'Backstop re-send in <Edition>' -Tag 'Unit' -ForEach $script:editions {
    <#
        Ruling A12 of Decision record 0028: where no PreCompact runs, the
        PostToolUse hook re-sends the levels on a new turn or 5 minutes after
        the last injection, bounded by the session's character budget.
    #>
    BeforeAll {
        $script:levelList = '"Kerberos" new; "PowerShell DSC" expert. '
        $script:backstopSentence = $script:prefix + $script:levelList + $script:treat + ' Current familiarity levels; make no offers in this session.'
        $script:compactionSentence = $script:prefix + $script:levelList + $script:treat + ' Re-sent after a compaction; make no offers in this session.'
        $script:stamp = '2026-10-07T10:00:00.0000000Z'

        function script:Get-CalibrationSentence
        {
            <# The calibration sentence at the end of a SessionStart context. #>
            param ($Result)

            $context = [string] $Result.Json.additionalContext
            $context.Substring($context.IndexOf($script:prefix))
        }
    }

    Context 'every writer of the state file' {
        It 'keeps lastTurn, lastInjectionUtc, and characters when PreCompact counts a compaction' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            Set-State -Fixture $fixture -State ([ordered] @{ schemaVersion = 1; compactions = 1; injected = 1; lastTurn = 2; lastInjectionUtc = $script:stamp; characters = 1500 })

            $result = Invoke-Event -Fixture $fixture -Event 'PreCompact'

            $result.ExitCode | Should -Be 0
            Get-StateField -Fixture $fixture -Name 'compactions' | Should -Be '2'
            Get-StateField -Fixture $fixture -Name 'injected' | Should -Be '1'
            Get-StateField -Fixture $fixture -Name 'lastTurn' | Should -Be '2'
            Get-StateField -Fixture $fixture -Name 'lastInjectionUtc' | Should -Be ('"{0}"' -f $script:stamp)
            Get-StateField -Fixture $fixture -Name 'characters' | Should -Be '1500'
        }

        It 'keeps the three fields current when PostToolUse answers a compaction' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            Set-ClockTurn -Fixture $fixture -Turn 2
            $before = [System.DateTime]::UtcNow
            Set-State -Fixture $fixture -State ([ordered] @{ schemaVersion = 1; compactions = 1; injected = 0; lastTurn = 2; lastInjectionUtc = $before.AddMinutes(-1).ToString('o'); characters = 1500 })

            $result = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            $result.Json.additionalContext | Should -BeExactly $script:compactionSentence
            $state = Get-State -Fixture $fixture
            $state.injected | Should -Be 1
            $state.lastTurn | Should -Be 2
            ([System.DateTimeOffset] $state.lastInjectionUtc).UtcDateTime | Should -BeGreaterOrEqual $before.AddSeconds(-1)
            $state.characters | Should -Be (1500 + $script:compactionSentence.Length)
        }

        It 'keeps the three fields when a PreCompact follows a backstop injection' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $null = Invoke-Event -Fixture $fixture -Event 'SessionStart'
            $null = Invoke-Event -Fixture $fixture -Event 'Stop'
            (Invoke-Event -Fixture $fixture -Event 'PostToolUse').Json.additionalContext | Should -BeExactly $script:backstopSentence
            $lastTurn = Get-StateField -Fixture $fixture -Name 'lastTurn'
            $lastInjection = Get-StateField -Fixture $fixture -Name 'lastInjectionUtc'
            $characters = Get-StateField -Fixture $fixture -Name 'characters'

            $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'

            Get-StateField -Fixture $fixture -Name 'compactions' | Should -Be '1'
            Get-StateField -Fixture $fixture -Name 'lastTurn' | Should -Be $lastTurn
            Get-StateField -Fixture $fixture -Name 'lastInjectionUtc' | Should -Be $lastInjection
            Get-StateField -Fixture $fixture -Name 'characters' | Should -Be $characters
        }
    }

    Context 'an injection after its own state write' {
        It 'emits nothing while another hook holds the state lock past its timeout, and re-sends on the next call' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'
            $lockPath = [System.IO.Path]::ChangeExtension((Get-StatePath -Fixture $fixture), '.lock')
            $lock = [System.IO.FileStream]::new($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try
            {
                $blocked = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
            }
            finally
            {
                $lock.Dispose()
            }

            $blocked.ExitCode | Should -Be 0
            $blocked.Output | Should -BeNullOrEmpty
            (Get-State -Fixture $fixture).injected | Should -Be 0
            $retry = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
            $retry.Json.additionalContext | Should -BeExactly $script:compactionSentence
            (Get-State -Fixture $fixture).injected | Should -Be 1
        }
    }

    Context 'SessionStart' {
        It 'seeds lastTurn, lastInjectionUtc, and characters when it injects levels' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $before = [System.DateTime]::UtcNow

            $result = Invoke-Event -Fixture $fixture -Event 'SessionStart'

            $state = Get-State -Fixture $fixture
            $state.compactions | Should -Be 0
            $state.injected | Should -Be 0
            $state.lastTurn | Should -Be 0
            ([System.DateTimeOffset] $state.lastInjectionUtc).UtcDateTime | Should -BeGreaterOrEqual $before.AddSeconds(-1)
            $state.characters | Should -Be (Get-CalibrationSentence -Result $result).Length
        }

        It 'seeds nothing when it injects no levels (<Why>)' -ForEach @(
            @{ Why = 'no profile'; State = $null }
            @{ Why = 'an entry that is off'; State = '"off"' }
        ) {
            $text = if ($State) { New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -State $State) } else { $null }
            $fixture = New-HookFixture -ProfileText $text

            $result = Invoke-Event -Fixture $fixture -Event 'SessionStart'

            $result.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Get-StatePath -Fixture $fixture) | Should -BeFalse
        }

        It 'merges into the state of a resumed session and leaves compactions and injected alone' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $first = Invoke-Event -Fixture $fixture -Event 'SessionStart'
            $null = Invoke-Event -Fixture $fixture -Event 'Stop'
            $null = Invoke-Event -Fixture $fixture -Event 'Stop'
            $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'

            $resumed = Invoke-Event -Fixture $fixture -Event 'SessionStart' -Source 'resume'

            $state = Get-State -Fixture $fixture
            $state.compactions | Should -Be 1
            $state.injected | Should -Be 0
            $state.lastTurn | Should -Be 2
            $state.characters | Should -Be ((Get-CalibrationSentence -Result $first).Length + (Get-CalibrationSentence -Result $resumed).Length)
            (Invoke-Event -Fixture $fixture -Event 'PostToolUse').Json.additionalContext | Should -BeExactly $script:compactionSentence -Because 'a compaction pending across the resume still gets its re-send'
        }
    }

    Context 'the two signals' {
        It 'sends the backstop on the first tool call after a turn ends, without the unrated count or a compaction claim, then waits for the next turn' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $start = Invoke-Event -Fixture $fixture -Event 'SessionStart'
            $inTurnOne = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
            $null = Invoke-Event -Fixture $fixture -Event 'Stop'
            $clockBefore = [System.IO.File]::ReadAllBytes((Get-ClockPath -Fixture $fixture))

            $backstop = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
            $again = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            (Get-CalibrationSentence -Result $start) | Should -Match 'unrated' -Because 'the fixture declares one area the profile does not rate'
            $inTurnOne.Output | Should -BeNullOrEmpty
            $backstop.ExitCode | Should -Be 0
            $backstop.Json.additionalContext | Should -BeExactly $script:backstopSentence
            $backstop.Json.hookSpecificOutput.additionalContext | Should -BeExactly $script:backstopSentence
            $backstop.Json.hookSpecificOutput.hookEventName | Should -BeExactly 'PostToolUse'
            $backstop.Json.PSObject.Properties.Name | Should -Not -Contain 'decision'
            $again.Output | Should -BeNullOrEmpty
            $state = Get-State -Fixture $fixture
            $state.lastTurn | Should -Be 1
            $state.characters | Should -Be ((Get-CalibrationSentence -Result $start).Length + $script:backstopSentence.Length)
            [System.IO.File]::ReadAllBytes((Get-ClockPath -Fixture $fixture)) | Should -Be $clockBefore -Because 'no calibration hook rewrites the session clock'
        }

        It '<Expectation> when the last injection was <Minutes> minutes ago and <Turns> turns have closed' -ForEach @(
            @{ Expectation = 'sends the backstop'; Minutes = 6; Turns = 1; Sent = $true }
            @{ Expectation = 'waits'; Minutes = 4; Turns = 1; Sent = $false }
            @{ Expectation = 'never fires the five-minute signal within the first turn'; Minutes = 6; Turns = 0; Sent = $false }
        ) {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            Set-ClockTurn -Fixture $fixture -Turn $Turns
            Set-State -Fixture $fixture -State ([ordered] @{ schemaVersion = 1; compactions = 0; injected = 0; lastTurn = $Turns; lastInjectionUtc = [System.DateTime]::UtcNow.AddMinutes(-$Minutes).ToString('o'); characters = 300 })

            $result = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            if ($Sent)
            {
                $result.Json.additionalContext | Should -BeExactly $script:backstopSentence
            }
            else
            {
                $result.Output | Should -BeNullOrEmpty
            }
        }

        It 'lets the five-minute signal alone drive the backstop without a readable session clock, and writes no clock' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            Set-State -Fixture $fixture -State ([ordered] @{ schemaVersion = 1; compactions = 0; injected = 0; lastTurn = 0; lastInjectionUtc = [System.DateTime]::UtcNow.AddMinutes(-6).ToString('o'); characters = 300 })

            $result = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            $result.Json.additionalContext | Should -BeExactly $script:backstopSentence
            Test-Path -LiteralPath (Get-ClockPath -Fixture $fixture) | Should -BeFalse
        }

        It 'fires no backstop where SessionStart injected nothing, though PreCompact created the state file' {
            $fixture = New-HookFixture
            $null = Invoke-Event -Fixture $fixture -Event 'SessionStart'
            $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'
            $answered = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
            $null = Invoke-Event -Fixture $fixture -Event 'Stop'
            Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path $fixture.ProfilePath

            $later = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            Test-Path -LiteralPath (Get-StatePath -Fixture $fixture) | Should -BeTrue
            $answered.Output | Should -BeNullOrEmpty
            $later.Output | Should -BeNullOrEmpty -Because 'only a seeded lastInjectionUtc arms the backstop'
            Get-StateField -Fixture $fixture -Name 'lastInjectionUtc' | Should -BeNullOrEmpty
        }

        It 'sends one backstop and counts its characters once when two tool calls race for it' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $start = Invoke-Event -Fixture $fixture -Event 'SessionStart'
            $null = Invoke-Event -Fixture $fixture -Event 'Stop'

            $runs = foreach ($index in 1..2)
            {
                $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ClockRoot "{1}"' -f $script:postToolUse, $fixture.ClockRoot))
                $startInfo.UseShellExecute = $false
                $startInfo.CreateNoWindow = $true
                $startInfo.RedirectStandardInput = $true
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true
                foreach ($name in $fixture.Environment.Keys)
                {
                    $startInfo.EnvironmentVariables[$name] = [string] $fixture.Environment[$name]
                }

                $process = [System.Diagnostics.Process]::Start($startInfo)
                [pscustomobject] @{ Process = $process; Output = $process.StandardOutput.ReadToEndAsync(); Error = $process.StandardError.ReadToEndAsync() }
            }

            try
            {
                foreach ($run in $runs)
                {
                    $run.Process.StandardInput.Write((@{ hook_event_name = 'PostToolUse'; session_id = $fixture.SessionId; cwd = $fixture.Workspace; tool_name = 'view' } | ConvertTo-Json -Compress))
                    $run.Process.StandardInput.Close()
                }

                foreach ($run in $runs)
                {
                    $run.Process.WaitForExit(60000) | Should -BeTrue
                    $run.Process.WaitForExit()
                }

                $outputs = @($runs | ForEach-Object -Process { $_.Output.Result.Trim() } | Where-Object -FilterScript { $_ })
            }
            finally
            {
                $runs | ForEach-Object -Process { $_.Process.Dispose() }
            }

            $outputs.Count | Should -Be 1
            ($outputs[0] | ConvertFrom-Json).additionalContext | Should -BeExactly $script:backstopSentence
            (Get-State -Fixture $fixture).characters | Should -Be ((Get-CalibrationSentence -Result $start).Length + $script:backstopSentence.Length)
        }
    }

    Context 'the choices ruling A18 confirmed' {
        It 'seeds lastInjectionUtc from the injection, so a resumed session whose start is hours old makes no re-send on its first tool call' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $null = New-Item -ItemType Directory -Path $fixture.ClockRoot -Force
            $clock = [ordered] @{ startedUtc = [System.DateTime]::UtcNow.AddHours(-3).ToString('o'); workspace = $fixture.Workspace; turns = 2 }
            [System.IO.File]::WriteAllText((Get-ClockPath -Fixture $fixture), ($clock | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
            $before = [System.DateTime]::UtcNow

            $resumed = Invoke-Event -Fixture $fixture -Event 'SessionStart' -Source 'resume'
            $first = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            (Get-CalibrationSentence -Result $resumed) | Should -Match '"Kerberos" new'
            $first.ExitCode | Should -Be 0
            $first.Output | Should -BeNullOrEmpty
            $state = Get-State -Fixture $fixture
            $state.lastTurn | Should -Be 2
            ([System.DateTimeOffset] $state.lastInjectionUtc).UtcDateTime | Should -BeGreaterOrEqual $before.AddSeconds(-1)
        }

        It 'records a due backstop that finds nothing to send after an opt-out, advancing lastTurn and lastInjectionUtc and leaving characters unchanged' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            $null = Invoke-Event -Fixture $fixture -Event 'SessionStart'
            $null = Invoke-Event -Fixture $fixture -Event 'Stop'
            $seeded = Get-State -Fixture $fixture
            Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -State '"off"')) } -Path $fixture.ProfilePath

            $due = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            $due.ExitCode | Should -Be 0
            $due.Output | Should -BeNullOrEmpty
            $state = Get-State -Fixture $fixture
            $state.lastTurn | Should -Be 1
            $state.characters | Should -Be $seeded.characters
            ([System.DateTimeOffset] $state.lastInjectionUtc) | Should -BeGreaterThan ([System.DateTimeOffset] $seeded.lastInjectionUtc)
            (Invoke-Event -Fixture $fixture -Event 'PostToolUse').Output | Should -BeNullOrEmpty
        }
    }

    Context 'the session character budget (Context.SessionBudget)' {
        It 'stops backstop re-sends at 12,000 characters while compaction re-sends continue' {
            $longNames = 1..16 | ForEach-Object -Process { ('Area {0:D2} ' -f $_) + ('x' * 40) }
            $areas = '{' + (($longNames | ForEach-Object -Process { '"{0}":{{"level":"familiar","updatedUtc":"2026-10-01T08:00:00Z"}}' -f $_ }) -join ',') + '}'
            $fixture = New-HookFixture -Area $longNames -ProfileText (New-ContributorFixtureProfile -Entry (New-ContributorFixtureEntry -Areas $areas))
            $start = Invoke-Event -Fixture $fixture -Event 'SessionStart'
            $total = (Get-CalibrationSentence -Result $start).Length
            $sent = 0
            while ($total -lt 12000)
            {
                Set-ClockTurn -Fixture $fixture -Turn ($sent + 1)
                $result = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
                $result.Json.additionalContext | Should -Match 'Current familiarity levels; make no offers in this session\.\z'
                $total += $result.Json.additionalContext.Length
                $sent++
            }

            Set-ClockTurn -Fixture $fixture -Turn ($sent + 1)
            $suppressed = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
            $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'
            $compaction = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            (Get-CalibrationSentence -Result $start).Length | Should -Be 1118 -Because 'the worst case of Context.SentenceSize at session start'
            $sent | Should -Be 10 -Because 'each worst-case backstop is 1,178 characters'
            $suppressed.Output | Should -BeNullOrEmpty
            $compaction.Json.additionalContext | Should -Match 'Re-sent after a compaction; make no offers in this session\.\z'
            (Get-State -Fixture $fixture).characters | Should -Be ($total + $compaction.Json.additionalContext.Length)
        }

        It 'emits nothing of either kind at 60,000 characters and leaves the condition on record in the state file' {
            $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
            Set-ClockTurn -Fixture $fixture -Turn 1
            Set-State -Fixture $fixture -State ([ordered] @{ schemaVersion = 1; compactions = 1; injected = 0; lastTurn = 1; lastInjectionUtc = [System.DateTime]::UtcNow.ToString('o'); characters = 59990 })

            $last = Invoke-Event -Fixture $fixture -Event 'PostToolUse'
            $null = Invoke-Event -Fixture $fixture -Event 'PreCompact'
            Set-ClockTurn -Fixture $fixture -Turn 2
            $beyond = Invoke-Event -Fixture $fixture -Event 'PostToolUse'

            $last.Json.additionalContext | Should -BeExactly $script:compactionSentence -Because 'a compaction re-send is never suppressed below 60,000'
            $beyond.ExitCode | Should -Be 0
            $beyond.Output | Should -BeNullOrEmpty
            $state = Get-State -Fixture $fixture
            $state.characters | Should -Be (59990 + $script:compactionSentence.Length)
            $state.compactions | Should -BeGreaterThan $state.injected -Because 'the unanswered compaction stays on record'
        }
    }
}

# --- hook tests part 3 ---

Describe 'Session clock path in <Edition>' -Tag 'Unit' -ForEach $script:editions {
    BeforeAll {
        $script:scripts = @{
            SessionStart = Join-Path -Path $script:hookRoot -ChildPath 'Add-SessionContext.ps1'
            Stop         = Join-Path -Path $script:hookRoot -ChildPath 'Write-SessionClose.ps1'
            PreCompact   = Join-Path -Path $script:hookRoot -ChildPath 'Write-CompactionCheckpoint.ps1'
            PostToolUse  = Join-Path -Path $script:hookRoot -ChildPath 'Add-FamiliarityContext.ps1'
            Elapsed      = Join-Path -Path $script:hookRoot -ChildPath 'Get-SessionElapsed.ps1'
        }
    }

    It 'derives one clock and one calibration state for <Case> in every script' -ForEach @(
        @{ Case = 'a plain session id'; SessionId = 'b1946ac9-2a55-4f71-9a7d-1a5e5f1c6d01' }
        @{ Case = 'a session id with unsafe characters'; SessionId = '../evil id:1' }
        @{ Case = 'a session id over 64 characters'; SessionId = ('s' * 70) }
        @{ Case = 'no session id'; SessionId = $null }
    ) {
        $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
        $base = @{ cwd = $fixture.Workspace }
        if ($SessionId) { $base.session_id = $SessionId }
        $invoke = {
            param ([string] $Name, [hashtable] $Extra)
            $payload = $base.Clone()
            foreach ($key in $Extra.Keys) { $payload[$key] = $Extra[$key] }
            Invoke-Hook -Executable $Executable -Script $script:scripts[$Name] -Payload $payload -Environment $fixture.Environment -Argument '-ClockRoot', $fixture.ClockRoot
        }

        $null = & $invoke 'SessionStart' @{ hook_event_name = 'SessionStart'; source = 'new' }
        $clocks = @(Get-ChildItem -LiteralPath $fixture.ClockRoot -Filter 'session-*.json' | Where-Object -FilterScript { $_.Name -notlike '*.familiarity.json' })
        $clocks.Count | Should -Be 1
        $clockName = $clocks[0].Name
        $clockName | Should -Match '\Asession-[A-Za-z0-9._-]{1,64}\.json\z'

        $null = & $invoke 'Stop' @{ hook_event_name = 'Stop'; stop_hook_active = $false }
        (Get-Content -LiteralPath $clocks[0].FullName -Raw | ConvertFrom-Json).turns | Should -Be 1

        $null = & $invoke 'PreCompact' @{ hook_event_name = 'PreCompact'; trigger = 'manual' }
        $statePath = Join-Path -Path $fixture.ClockRoot -ChildPath ($clockName -replace '\.json\z', '.familiarity.json')
        Test-Path -LiteralPath $statePath | Should -BeTrue

        $post = & $invoke 'PostToolUse' @{ hook_event_name = 'PostToolUse'; tool_name = 'view' }
        $post.Json.additionalContext | Should -Match 'Re-sent after a compaction'
        (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).injected | Should -Be 1

        @(Get-ChildItem -LiteralPath $fixture.ClockRoot -Filter 'session-*.json').Count | Should -Be 2 -Because 'no script derived a second key'
        $elapsed = Invoke-Hook -Executable $Executable -Script $script:scripts.Elapsed -Payload @{} -Argument '-ClockRoot', $fixture.ClockRoot, '-WorkingDirectory', $fixture.Workspace
        $elapsed.Output | Should -Match '\APOST-FLIGHT elapsed: .+ turn 2\)\z'
    }

    It 'never reads a newer calibration state as the session clock' {
        $fixture = New-HookFixture -ProfileText (New-ContributorFixtureProfile)
        $payload = @{ session_id = $fixture.SessionId; cwd = $fixture.Workspace }
        $null = Invoke-Hook -Executable $Executable -Script $script:scripts.SessionStart -Payload ($payload + @{ hook_event_name = 'SessionStart' }) -Environment $fixture.Environment -Argument '-ClockRoot', $fixture.ClockRoot
        Start-Sleep -Milliseconds 50
        $null = Invoke-Hook -Executable $Executable -Script $script:scripts.PreCompact -Payload ($payload + @{ hook_event_name = 'PreCompact' }) -Environment $fixture.Environment -Argument '-ClockRoot', $fixture.ClockRoot

        # Another workspace finds no matching clock and falls back to the newest file.
        $elapsed = Invoke-Hook -Executable $Executable -Script $script:scripts.Elapsed -Payload @{} -Argument '-ClockRoot', $fixture.ClockRoot, '-WorkingDirectory', $TestDrive

        $elapsed.Output | Should -Match '\APOST-FLIGHT elapsed: .+ turn 1\)\z'
    }
}

Describe 'Calibration state helpers' -Tag 'Unit' {
    BeforeDiscovery {
        $script:helperCases = @('Read-CalibrationState', 'Save-CalibrationState', 'Enter-CalibrationStateLock') | ForEach-Object -Process { @{ Name = $_ } }
    }

    It 'keeps <Name> verbatim in every script that writes the calibration state' -ForEach $script:helperCases {
        <#
            Every writer must preserve all five fields (Decision record 0028,
            A12); each hook carries its own copy, because VS Code launches a
            hook by its own path.
        #>
        $texts = foreach ($file in 'Add-SessionContext.ps1', 'Write-CompactionCheckpoint.ps1', 'Add-FamiliarityContext.ps1')
        {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $script:hookRoot -ChildPath $file), [ref] $tokens, [ref] $errors)
            $definition = @($ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $false))
            $definition.Count | Should -Be 1 -Because "$file defines $Name once"
            $definition[0].Extent.Text.Replace("`r`n", "`n")
        }

        @($texts | Sort-Object -Unique).Count | Should -Be 1
    }
}

Describe 'Registration template' -Tag 'Unit' {
    BeforeAll {
        $script:template = Get-Content -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'skills/contributor-profile/assets/contributor-profile.hooks.json') -Raw | ConvertFrom-Json
        $script:hooksJson = Get-Content -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json') -Raw | ConvertFrom-Json
    }

    It 'registers only the PostToolUse script, with the launchers of hooks.json' {
        @($script:template.hooks.PSObject.Properties.Name) | Should -Be @('PostToolUse')
        $entry = @($script:template.hooks.PostToolUse)
        $entry.Count | Should -Be 1
        $reference = @($script:hooksJson.hooks.SessionStart)[0]

        foreach ($launcher in 'command', 'windows', 'powershell')
        {
            $entry[0].$launcher | Should -BeExactly ($reference.$launcher.Replace('Add-SessionContext.ps1', 'Add-FamiliarityContext.ps1'))
        }

        $entry[0].timeout | Should -Be $reference.timeout
    }

    It 'leaves PostToolUse out of hooks.json, so only a machine with an active profile pays the per-call cost' {
        @($script:hooksJson.hooks.PSObject.Properties.Name) | Should -Not -Contain 'PostToolUse'
    }

    It 'never ships as hooks/contributor-profile.json in any payload' {
        Test-Path -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/contributor-profile.json') | Should -BeFalse
        @(Get-ChildItem -Path (Join-Path -Path $script:repoRoot -ChildPath 'output/module/CopilotAtelier/*/com.github.copilot/hooks') -Filter 'contributor-profile.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'ships the PostToolUse script beside the other hooks' {
        Test-Path -LiteralPath (Join-Path -Path $script:hookRoot -ChildPath 'Add-FamiliarityContext.ps1') | Should -BeTrue
    }
}

Describe 'Every entry point agrees on the shared fixture set in <Edition>' -Tag 'Unit' -ForEach $script:editions {
    BeforeAll {
        $fixture = New-HookFixture -Area 'Kerberos', 'PowerShell DSC', 'Pester', '.NET'
        $script:driverHome = $fixture
        $casesPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N') + '.json')
        $cases = foreach ($case in (Get-ContributorProfileFixtureCase))
        {
            $bytes = if ($case.ContainsKey('Bytes')) { [byte[]] $case.Bytes } else { [System.Text.UTF8Encoding]::new($false).GetBytes($case.Text) }
            @{ Name = $case.Name; Reason = $case.Reason; Base64 = [System.Convert]::ToBase64String($bytes) }
        }

        [System.IO.File]::WriteAllText($casesPath, (ConvertTo-Json -InputObject @($cases) -Depth 3), [System.Text.UTF8Encoding]::new($false))

        $driver = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $driver -Encoding ascii -Value @'
param ($RepoRoot, $CasesPath, $Workspace, $ProfilePath, $ClockRoot, $ResultPath)
$ErrorActionPreference = 'Stop'
$hooks = Join-Path $RepoRoot 'com.github.copilot\hooks\scripts'
$skill = Join-Path $RepoRoot 'skills\contributor-profile\scripts\ContributorProfile.ps1'
$results = foreach ($case in (Get-Content -LiteralPath $CasesPath -Raw | ConvertFrom-Json)) {
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ProfilePath))
    [IO.File]::WriteAllBytes($ProfilePath, [Convert]::FromBase64String($case.Base64))
    $session = [guid]::NewGuid().ToString()
    $payload = '{{"hook_event_name":"{0}","session_id":"{1}","cwd":{2},"source":"new"}}'
    $cwd = ConvertTo-Json -InputObject $Workspace -Compress
    $hookOut = & (Join-Path $hooks 'Add-SessionContext.ps1') -InputJson ($payload -f 'SessionStart', $session, $cwd) -ClockRoot $ClockRoot | ConvertFrom-Json
    $null = & (Join-Path $hooks 'Write-CompactionCheckpoint.ps1') -InputJson ($payload -f 'PreCompact', $session, $cwd) -ClockRoot $ClockRoot
    $postText = & (Join-Path $hooks 'Add-FamiliarityContext.ps1') -InputJson ($payload -f 'PostToolUse', $session, $cwd) -ClockRoot $ClockRoot
    $report = & $skill -Action Get -WorkspacePath $Workspace
    $writer = $null
    # The fixture entry's id: a write goes only to a positively chosen target.
    try { $null = & $skill -Action Set -Contributor '11111111-1111-4111-8111-111111111111' -SnoozeInterview -WhatIf } catch { $writer = $_.Exception.Message }
    [pscustomobject]@{
        Name = $case.Name
        Sentence = [string]$hookOut.additionalContext
        Resent = if ($postText) { [string]($postText | ConvertFrom-Json).additionalContext } else { '' }
        SkillReason = $report.ReasonCode
        SkillLevels = @($report.Levels)
        SkillPath = $report.ProfilePath
        Writer = $writer
    }
}
[IO.File]::WriteAllText($ResultPath, ($results | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
'@

        $environment = $fixture.Environment.Clone()
        $resultPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N') + '.result.json')
        $process = Invoke-Hook -Executable $Executable -Script $driver -Payload @{} -Environment $environment -Argument $script:repoRoot, $casesPath, $fixture.Workspace, $fixture.ProfilePath, $fixture.ClockRoot, $resultPath
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $resultPath))
        {
            throw "The driver failed: $($process.Error) $($process.Output)"
        }

        $script:driverResults = @{}
        foreach ($item in (Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json))
        {
            $script:driverResults[$item.Name] = $item
        }

        $script:expectedLevels = '"Kerberos" new; "PowerShell DSC" expert.'
    }

    It 'resolves the same profile path in the hook, the Skill script, and the module (<Case>)' -ForEach @(@{ Case = 'valid profile' }) {
        $result = $script:driverResults[$Case]

        $result.SkillPath | Should -BeExactly $script:driverHome.ProfilePath
        $result.Sentence | Should -Match ([regex]::Escape($script:expectedLevels)) -Because 'the hook read the profile at the same path'
    }

    It '<Name> yields the same outcome in every entry point' -ForEach $script:fixtureCases {
        $result = $script:driverResults[$Name]

        if ($Reason)
        {
            $result.Sentence | Should -Match ([regex]::Escape("Contributor profile unreadable ($Reason)"))
            $result.SkillReason | Should -BeExactly $Reason
            $result.Writer | Should -Match ([regex]::Escape("($Reason)"))
            $result.Resent | Should -BeNullOrEmpty -Because 'no levels are re-sent from an unreadable profile'
        }
        else
        {
            $result.SkillReason | Should -BeNullOrEmpty
            $result.Writer | Should -BeNullOrEmpty
            (@($result.SkillLevels) -join '|') | Should -BeExactly (@($_.Levels) -join '|')
            if (@($_.Levels).Count -gt 0)
            {
                # The workspace declares every rated fixture area in profile order.
                $matched = (@($_.Levels) | ForEach-Object -Process { $areaName, $areaLevel = $_ -split ': ', 2; '"{0}" {1}' -f $areaName, $areaLevel }) -join '; '
                $result.Sentence | Should -Match ([regex]::Escape($script:prefix + $matched + '. '))
                $result.Resent | Should -Match ([regex]::Escape($script:prefix + $matched + '. '))
            }
            else
            {
                $result.Sentence | Should -Match ([regex]::Escape('No contributor profile levels for this workspace; 4 declared Knowledge areas are unrated.'))
                $result.Resent | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'The module commands agree with the hooks on the shared fixture set' -Tag 'Unit' -Skip:(-not (Test-Path -Path (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'output/*/CopilotAtelier/*/CopilotAtelier.psd1'))) {
    BeforeAll {
        . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/DeploymentProfile.ps1')
        Import-CopilotAtelierTestModule -ProjectPath $script:repoRoot
        $script:moduleFixture = New-HookFixture
    }

    It '<Name> yields the same reason code in Get- and Set-CopilotAtelierContributorProfile' -ForEach $script:fixtureCases {
        Write-ContributorFixture -Case $_ -Path $script:moduleFixture.ProfilePath

        $outcome = Use-ContributorEnvironment -Variable $script:moduleFixture.Environment -ScriptBlock {
            $report = Get-CopilotAtelierContributorProfile
            $writer = $null
            try { $null = Set-CopilotAtelierContributorProfile -Contributor '11111111-1111-4111-8111-111111111111' -State 'On' -WhatIf } catch { $writer = $_.Exception.Message }
            [pscustomobject]@{ Report = $report; Writer = $writer }
        }

        $outcome.Report.ProfilePath | Should -BeExactly $script:moduleFixture.ProfilePath
        if ($Reason)
        {
            $outcome.Report.ReasonCode | Should -BeExactly $Reason
            $outcome.Writer | Should -Match ([regex]::Escape("($Reason)"))
        }
        else
        {
            $outcome.Report.ReasonCode | Should -BeNullOrEmpty
            $outcome.Writer | Should -BeNullOrEmpty
        }
    }
}

Describe 'SessionStart declaration check' -Tag 'Unit' {
    BeforeAll {
        $script:sessionStartScript = Join-Path -Path $script:hookRoot -ChildPath 'Add-SessionContext.ps1'

        function script:Measure-SessionStart
        {
            <#
                Runs the SessionStart hook in this process, so the measurement
                holds the script's own work and no process start.
            #>
            param ([string] $Workspace, [string] $ClockRoot)

            $payload = @{ hook_event_name = 'SessionStart'; session_id = [guid]::NewGuid().ToString(); cwd = $Workspace; source = 'new' } | ConvertTo-Json -Compress
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $null = & $script:sessionStartScript -InputJson $payload -ClockRoot $ClockRoot
            $watch.Stop()
            $watch.Elapsed.TotalMilliseconds
        }
    }

    It 'checks a projectbrief.md full of Knowledge areas headings without bullets in linear time' {
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $plain = New-ContributorTestWorkspace -Path (Join-Path -Path $root -ChildPath 'plain')
        $hostile = Join-Path -Path $root -ChildPath 'hostile'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $hostile -ChildPath '.memory-bank') -Force
        # About 64 KB: every heading restarts a lazy search for a bullet that never comes.
        [System.IO.File]::WriteAllText((Join-Path -Path $hostile -ChildPath '.memory-bank/projectbrief.md'), ("## Knowledge areas`n" * 3400), [System.Text.UTF8Encoding]::new($false))
        $clockRoot = Join-Path -Path $root -ChildPath 'clock'

        $null = Measure-SessionStart -Workspace $plain -ClockRoot $clockRoot
        $plainBest = (1..3 | ForEach-Object -Process { Measure-SessionStart -Workspace $plain -ClockRoot $clockRoot } | Measure-Object -Minimum).Minimum
        $hostileBest = (1..3 | ForEach-Object -Process { Measure-SessionStart -Workspace $hostile -ClockRoot $clockRoot } | Measure-Object -Minimum).Minimum

        ($hostileBest - $plainBest) | Should -BeLessThan 300 -Because 'the check before the reader must stay linear in the declaration size'
    }
}