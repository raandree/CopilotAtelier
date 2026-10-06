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
    BeforeAll {
        $script:sessionStart = Join-Path -Path $script:hookRoot -ChildPath 'Add-SessionContext.ps1'
        $script:preCompact = Join-Path -Path $script:hookRoot -ChildPath 'Write-CompactionCheckpoint.ps1'
        $script:postToolUse = Join-Path -Path $script:hookRoot -ChildPath 'Add-FamiliarityContext.ps1'

        function script:Invoke-Event
        {
            param ($Fixture, [string] $Event, [hashtable] $Override = @{})

            $script = switch ($Event)
            {
                'SessionStart' { $script:sessionStart }
                'PreCompact' { $script:preCompact }
                'PostToolUse' { $script:postToolUse }
            }

            $payload = @{ hook_event_name = $Event; session_id = $Fixture.SessionId; cwd = $Fixture.Workspace }
            if ($Event -eq 'PreCompact') { $payload.trigger = 'manual'; $payload.custom_instructions = '' }
            if ($Event -eq 'PostToolUse') { $payload.tool_name = 'view'; $payload.tool_input = @{ path = 'x' }; $payload.tool_result = @{ result_type = 'success'; text_result_for_llm = ('y' * 5000) } }
            if ($Event -eq 'SessionStart') { $payload.source = 'new' }

            $environment = $Fixture.Environment.Clone()
            foreach ($name in $Override.Keys) { $environment[$name] = $Override[$name] }

            Invoke-Hook -Executable $Executable -Script $script -Payload $payload -Environment $environment -Argument '-ClockRoot', $Fixture.ClockRoot
        }

        function script:Get-State
        {
            param ($Fixture)

            Get-Content -LiteralPath (Get-StatePath -Fixture $Fixture) -Raw | ConvertFrom-Json
        }
    }

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
        $fixture = New-HookFixture -Area 'Kerberos', 'PowerShell DSC', 'Pester'
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
    try { $null = & $skill -Action Set -SnoozeInterview -WhatIf } catch { $writer = $_.Exception.Message }
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
            if ($result.SkillLevels.Count -gt 0)
            {
                $result.Sentence | Should -Match ([regex]::Escape($script:expectedLevels))
                $result.Resent | Should -Match ([regex]::Escape($script:expectedLevels))
                $result.SkillLevels | Should -Be @('Kerberos: new', 'PowerShell DSC: expert')
            }
            else
            {
                $result.Sentence | Should -Match ([regex]::Escape('No contributor profile levels for this workspace; 3 declared Knowledge areas are unrated.'))
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
            try { $null = Set-CopilotAtelierContributorProfile -State 'On' -WhatIf } catch { $writer = $_.Exception.Message }
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