<#
    The PreToolUse guard inside the Copilot SDK runtime that VS Code bundles.

    tests/HookLauncher.Tests.ps1 reproduces how each host spawns a launcher, but
    not what the host makes of the exit code and output. This suite runs the
    real PreToolUse launcher and guard inside the real runtime and reads what
    the model would read. Fixtures/Invoke-CopilotSdkTool.mjs starts the runtime
    with its own COPILOT_HOME, so it loads only the hooks staged here, and
    executes each command through the session's native tool pipeline without a
    model. That session offers no tools, so a command the guard allows fails as
    an unknown tool instead of running.

    It needs Windows, node, and a VS Code installation that bundles
    @github/copilot-sdk-win32-x64, and skips without them, for example on a CI
    runner without VS Code.
#>

BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:nodeAvailable = [bool](Get-Command -Name 'node' -CommandType Application -ErrorAction SilentlyContinue)
    $script:sdkPackageRoot = ''

    if ($script:isWindowsPlatform) {
        # Current VS Code builds install under <install root>\<commit>\resources\app,
        # older ones directly under <install root>\resources\app.
        $installRoots = @(
            $env:ProgramFiles
            ${env:ProgramFiles(x86)}
            if ($env:LOCALAPPDATA) { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs' }
        ) | Where-Object -FilterScript { $_ }

        $packagePattern = foreach ($installRoot in $installRoots) {
            foreach ($product in 'Microsoft VS Code', 'Microsoft VS Code Insiders') {
                foreach ($layout in '*\resources\app', 'resources\app') {
                    Join-Path -Path $installRoot -ChildPath "$product\$layout\node_modules.asar.unpacked\@github\copilot-sdk-win32-x64"
                }
            }
        }

        $script:sdkPackageRoot = @(
            Resolve-Path -Path $packagePattern -ErrorAction SilentlyContinue |
                ForEach-Object -Process { $_.ProviderPath } |
                Where-Object -FilterScript {
                    (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'copilot-sdk\index.js') -PathType Leaf) -and
                    (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'prebuilds\win32-x64\copilot-runtime.exe') -PathType Leaf)
                } |
                Sort-Object -Property { (Get-Item -LiteralPath (Join-Path -Path $_ -ChildPath 'package.json')).LastWriteTimeUtc } -Descending |
                Select-Object -First 1
        ) -join ''
    }

    $script:runtimeAvailable = $script:isWindowsPlatform -and $script:nodeAvailable -and [bool]$script:sdkPackageRoot
    $script:pwshAvailable = [bool](Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue)

    # The bundled runtime always; a standalone Copilot CLI too when one is installed.
    $script:conversationRuntimes = @(@{ Runtime = 'the runtime that VS Code bundles'; RuntimePath = ''; PackageRoot = $script:sdkPackageRoot })
    if ($script:isWindowsPlatform) {
        $cliPath = @(
            Get-Command -Name 'copilot' -CommandType Application -ErrorAction SilentlyContinue |
                Where-Object -FilterScript { $_.Source -like '*.exe' } |
                Select-Object -ExpandProperty Source
            if ($env:LOCALAPPDATA) {
                Get-ChildItem -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WinGet\Packages\GitHub.Copilot_*\copilot.exe') -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName
            }
        ) | Select-Object -First 1
        if ($cliPath) {
            $script:conversationRuntimes += @{ Runtime = 'the standalone Copilot CLI'; RuntimePath = $cliPath; PackageRoot = $script:sdkPackageRoot }
        }
    }
}

Describe 'PreToolUse guard in the Copilot SDK runtime' -Tag 'Integration' -Skip:(-not $script:runtimeAvailable) -ForEach @(
    @{ PackageRoot = $script:sdkPackageRoot }
) {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $hookConfig = Get-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $utf8 = [Text.UTF8Encoding]::new($false)

        <#
            The real guard under a name no other copy on the machine has, staged
            under PLUGIN_ROOT, the launcher's first candidate. The workspace hooks
            file holds the shipped PreToolUse entry with only that name swapped,
            so the runtime runs the shipped launcher exactly as it spawns it.
        #>
        $scriptName = 'Block-RemoteMutation-{0}.ps1' -f [guid]::NewGuid().ToString('N')
        $pluginRoot = Join-Path -Path $TestDrive -ChildPath 'plugin'
        $scriptDirectory = Join-Path -Path $pluginRoot -ChildPath 'com.github.copilot\hooks\scripts'
        $workspace = Join-Path -Path $TestDrive -ChildPath 'workspace'
        $copilotHome = Join-Path -Path $TestDrive -ChildPath 'copilot-home'
        $null = New-Item -ItemType Directory -Path $scriptDirectory, (Join-Path -Path $workspace -ChildPath '.github\hooks'), $copilotHome -Force
        Copy-Item `
            -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/scripts/Block-RemoteMutation.ps1') `
            -Destination (Join-Path -Path $scriptDirectory -ChildPath $scriptName)

        $entry = @($hookConfig.hooks.PreToolUse)[0]
        foreach ($launcher in 'command', 'windows', 'powershell') {
            $entry.$launcher = $entry.$launcher.Replace('Block-RemoteMutation.ps1', $scriptName)
        }

        [IO.File]::WriteAllText(
            (Join-Path -Path $workspace -ChildPath '.github\hooks\hooks.json'),
            (@{ hooks = @{ PreToolUse = @($entry) } } | ConvertTo-Json -Depth 5),
            $utf8
        )

        $script:blockedCommand = "Write-Output 'probe: git push origin main is only text here'"
        $script:allowedCommand = 'git status --short'

        $startInfo = [Diagnostics.ProcessStartInfo]::new(
            (Get-Command -Name 'node' -CommandType Application | Select-Object -First 1 -ExpandProperty Source)
        )
        foreach ($argument in @(
                (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\Invoke-CopilotSdkTool.mjs')
                $PackageRoot
                $copilotHome
                $workspace
            )) {
            $startInfo.Arguments += ' "' + $argument + '"'
        }

        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $workspace
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $utf8
        $startInfo.StandardErrorEncoding = $utf8
        $startInfo.EnvironmentVariables['PLUGIN_ROOT'] = $pluginRoot
        $startInfo.EnvironmentVariables.Remove('COPILOT_ATELIER_ALLOW_REMOTE')

        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $inputBytes = $utf8.GetBytes((ConvertTo-Json -InputObject @($script:blockedCommand, $script:allowedCommand) -Compress))
            $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.Close()

            # The fixture stops itself after 120 seconds; this only catches a stuck node.
            if (-not $process.WaitForExit(150000)) {
                $process.Kill()
                throw 'Invoke-CopilotSdkTool.mjs did not exit within 150 seconds.'
            }

            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                throw ('Invoke-CopilotSdkTool.mjs exited with {0}: {1}' -f $process.ExitCode, $errorTask.Result)
            }

            # Assigned first: Windows PowerShell emits a JSON array as one object.
            $results = $outputTask.Result | ConvertFrom-Json
            $script:toolResult = @{}
            foreach ($result in $results) {
                $script:toolResult[$result.command] = $result
            }
        } finally {
            $process.Dispose()
        }
    }

    It 'shows the model the reason when the guard blocks a command' {
        <#
            On exit 2 the runtime merges a JSON object from standard output into
            the deny only when the object has no hookSpecificOutput; for this
            PascalCase entry it otherwise shows "hook exited with code 2", as
            Copilot SDK chats did until 2026-10-04 (SDK 1.0.15-preview.4).
        #>
        $result = $script:toolResult[$script:blockedCommand]

        $result.preToolUseHookCount | Should -BeGreaterOrEqual 1
        $result.resultType | Should -BeExactly 'denied' -Because $result.textResultForLlm
        $result.textResultForLlm | Should -Match '\ADenied by preToolUse hook: Blocked by Copilot Atelier: this command pushes to a git remote'
        $result.textResultForLlm | Should -Match 'in their own terminal'
    }

    It 'lets a command the guard allows past the hook' {
        $result = $script:toolResult[$script:allowedCommand]

        $result.preToolUseHookCount | Should -BeGreaterOrEqual 1
        $result.resultType | Should -Not -Be 'denied' -Because $result.textResultForLlm
        $result.textResultForLlm | Should -Not -Match 'preToolUse hook'
    }
}

<#
    Decision record 0028 re-sends contributor familiarity levels after a
    compaction through a PostToolUse hook that a second file in the user hooks
    folder registers. Fixtures/Invoke-CopilotSdkConversation.mjs drives real
    sessions against a fake, local model and records every request the runtime
    sends to it, so these cases read what a model would read. Probe hooks log
    their input and print distinct top-level and hookSpecificOutput markers.
    Only the host facts that design rests on are asserted.
#>
Describe 'Hook context carriers in <Runtime>' -Tag 'Integration' -Skip:(-not ($script:runtimeAvailable -and $script:pwshAvailable)) -ForEach $script:conversationRuntimes {
    BeforeAll {
        $utf8 = [Text.UTF8Encoding]::new($false)
        $runRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $copilotHome = Join-Path -Path $runRoot -ChildPath 'copilot-home'
        $hookDirectory = Join-Path -Path $copilotHome -ChildPath 'hooks'
        $script:workspace = Join-Path -Path $runRoot -ChildPath 'workspace'
        $script:logDirectory = Join-Path -Path $runRoot -ChildPath 'hook-log'
        $null = New-Item -ItemType Directory -Path $hookDirectory, $script:workspace, $script:logDirectory -Force

        $probeHook = Join-Path -Path $runRoot -ChildPath 'probe-hook.ps1'
        [IO.File]::WriteAllText($probeHook, @'
param([string]$Name, [string]$LogDirectory, [string]$Mode)
$payload = [Console]::In.ReadToEnd()
$count = @(Get-ChildItem -LiteralPath $LogDirectory -Filter "$Name-*.json").Count
[IO.File]::WriteAllText((Join-Path -Path $LogDirectory -ChildPath ('{0}-{1:D3}.json' -f $Name, $count)), $payload)
$output = switch ($Mode) {
    'session' { '{"additionalContext":"SS-TOP-MARKER","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"SS-NESTED-MARKER"}}' }
    'post' { '{"additionalContext":"PTU-TOP-MARKER","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"PTU-NESTED-MARKER"}}' }
    default { '{}' }
}
[Console]::Out.Write($output)
exit 0
'@, $utf8)

        function New-ProbeHookEntry ([string] $Name, [string] $Mode) {
            $line = 'pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Name {1} -LogDirectory "{2}" -Mode {3}' -f $probeHook, $Name, $script:logDirectory, $Mode
            [ordered]@{ type = 'command'; timeout = 20; command = $line; powershell = $line }
        }

        [IO.File]::WriteAllText(
            (Join-Path -Path $hookDirectory -ChildPath 'hooks.json'),
            (@{ hooks = [ordered]@{ SessionStart = @(New-ProbeHookEntry -Name 'SS' -Mode 'session'); PreCompact = @(New-ProbeHookEntry -Name 'PC' -Mode 'none') } } | ConvertTo-Json -Depth 6),
            $utf8
        )
        $registrationPath = Join-Path -Path $hookDirectory -ChildPath 'contributor-profile.json'
        $registration = @{ hooks = @{ PostToolUse = @(New-ProbeHookEntry -Name 'PTU' -Mode 'post') } } | ConvertTo-Json -Depth 6

        $steps = @(
            @{ op = 'newSession' }                                                    # 0 session 1 starts without the second file
            @{ op = 'send'; prompt = 'turn A1' }                                      # 1
            @{ op = 'writeFile'; path = $registrationPath; content = $registration }  # 2
            @{ op = 'send'; prompt = 'turn A2' }                                      # 3
            @{ op = 'disconnect' }                                                    # 4
            @{ op = 'newSession' }                                                    # 5 session 2 starts with it
            @{ op = 'send'; prompt = 'turn B1' }                                      # 6
            @{ op = 'compact' }                                                       # 7
            @{ op = 'send'; prompt = 'turn B2' }                                      # 8
            @{ op = 'removeFile'; path = $registrationPath }                          # 9
            @{ op = 'send'; prompt = 'turn B3' }                                      # 10
            @{ op = 'disconnect' }                                                    # 11
        )

        $startInfo = [Diagnostics.ProcessStartInfo]::new(
            (Get-Command -Name 'node' -CommandType Application | Select-Object -First 1 -ExpandProperty Source)
        )
        foreach ($argument in @(
                (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\Invoke-CopilotSdkConversation.mjs')
                $PackageRoot
                $copilotHome
                $script:workspace
                $RuntimePath
            )) {
            $startInfo.Arguments += ' "' + $argument + '"'
        }

        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $script:workspace
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $utf8
        $startInfo.StandardErrorEncoding = $utf8

        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $inputBytes = $utf8.GetBytes((ConvertTo-Json -InputObject $steps -Depth 5 -Compress))
            $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.Close()

            # The fixture stops itself after 600 seconds; this only catches a stuck node.
            if (-not $process.WaitForExit(660000)) {
                $process.Kill()
                throw 'Invoke-CopilotSdkConversation.mjs did not exit within 660 seconds.'
            }

            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                throw ('Invoke-CopilotSdkConversation.mjs exited with {0}: {1}' -f $process.ExitCode, $errorTask.Result)
            }

            $script:conversation = $outputTask.Result | ConvertFrom-Json
        } finally {
            $process.Dispose()
        }

        $script:sessionIds = @($script:conversation.steps | Where-Object -Property op -EQ -Value 'newSession' | ForEach-Object -Process { $_.sessionId })
        $script:postToolUseEnds = @(
            $script:conversation.events | Where-Object -FilterScript { $_.type -eq 'hook.end' -and $_.hookType -eq 'postToolUse' -and $_.output.additionalContext }
        )

        function Get-ProbePayload ([string] $Name) {
            Get-ChildItem -LiteralPath $script:logDirectory -Filter "$Name-*.json" | Sort-Object -Property Name | ForEach-Object -Process {
                Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            }
        }

        function Get-ToolMessage ([int] $Step) {
            foreach ($request in @($script:conversation.requests | Where-Object -Property step -EQ -Value $Step)) {
                $request.messages | Where-Object -Property role -EQ -Value 'tool'
            }
        }
    }

    It 'shows the model only the top-level SessionStart context' {
        $first = @($script:conversation.requests | Where-Object -Property step -EQ -Value 6)[0]
        $text = ($first.messages | ForEach-Object -Process { $_.text }) -join "`n"

        $text | Should -Match 'SS-TOP-MARKER'
        $text | Should -Not -Match 'SS-NESTED-MARKER'
    }

    It 'does not load a hook file that appears after the session started' {
        @($script:postToolUseEnds | Where-Object -Property session -EQ -Value 1).Count | Should -Be 0
        @(Get-ToolMessage -Step 3).text -join "`n" | Should -Not -Match 'PTU-'
    }

    It 'loads every hook file in the user hooks folder when a session starts' {
        @($script:postToolUseEnds | Where-Object -Property step -EQ -Value 6).Count | Should -Be 1
    }

    It 'shows the model the top-level PostToolUse context in the tool result, beside a hookSpecificOutput copy' {
        $toolText = @(Get-ToolMessage -Step 6).text -join "`n"

        $toolText | Should -Match 'PTU-TOP-MARKER'
        $toolText | Should -Not -Match 'PTU-NESTED-MARKER'
    }

    It 'carries PostToolUse context to the model on the first tool call after a compaction' {
        $compaction = @($script:conversation.steps | Where-Object -Property op -EQ -Value 'compact')[0]
        $afterCompaction = @($script:conversation.requests | Where-Object -Property step -EQ -Value 8)

        $compaction.success | Should -BeTrue
        $compaction.messagesRemoved | Should -BeGreaterThan 0
        $afterCompaction[0].messages.role | Should -Not -Contain 'tool'
        @(Get-ToolMessage -Step 8).text -join "`n" | Should -Match 'PTU-TOP-MARKER'
    }

    It 'keeps running a hook file that was removed during the session' {
        @($script:postToolUseEnds | Where-Object -Property step -EQ -Value 10).Count | Should -Be 1
    }

    It 'gives PreCompact, SessionStart, and PostToolUse the same session id and cwd' {
        $sessionStart = @(Get-ProbePayload -Name 'SS')[1]
        $preCompact = @(Get-ProbePayload -Name 'PC')
        $postToolUse = @(Get-ProbePayload -Name 'PTU')

        $preCompact.Count | Should -Be 1
        $postToolUse.Count | Should -Be 3
        $sessionStart.session_id | Should -BeExactly $script:sessionIds[1]
        foreach ($payload in @($preCompact) + $postToolUse) {
            $payload.session_id | Should -BeExactly $sessionStart.session_id
            $payload.cwd | Should -BeExactly $sessionStart.cwd
        }
        $sessionStart.cwd | Should -BeExactly $script:workspace
    }
}

<#
    Decision record 0028, Calibration.Delivery: the shipped hooks, the shipped
    registration template, and the contributor-profile Skill, staged in the
    deployed layout under a scratch home, delivering a saved level to the
    model at session start and again after a real compaction. The runtime and
    its hooks inherit the redirected home from the node process.
#>
Describe 'Contributor levels delivered by <Runtime>' -Tag 'Integration' -Skip:(-not ($script:runtimeAvailable -and $script:pwshAvailable)) -ForEach $script:conversationRuntimes {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path -Path $repoRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
        $utf8 = [Text.UTF8Encoding]::new($false)
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $userHome = Join-Path -Path $root -ChildPath 'home'
        $target = Join-Path -Path $root -ChildPath 'CopilotAtelier'
        $workspace = New-ContributorTestWorkspace -Path (Join-Path -Path $root -ChildPath 'workspace') -Area 'Kerberos', 'PowerShell DSC', 'Pester'
        $copilotHome = Join-Path -Path $userHome -ChildPath '.copilot'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $target -ChildPath 'hooks/scripts'), (Join-Path -Path $target -ChildPath 'skills'), $copilotHome -Force

        Set-Content -LiteralPath (Join-Path -Path $target -ChildPath '.copilotatelier.json') -Value '{}' -Encoding ascii
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json') -Destination (Join-Path -Path $target -ChildPath 'hooks')
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/scripts/*.ps1') -Destination (Join-Path -Path $target -ChildPath 'hooks/scripts')
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'skills/contributor-profile/assets/contributor-profile.hooks.json') -Destination (Join-Path -Path $target -ChildPath 'hooks/contributor-profile.json')
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'skills/contributor-profile') -Destination (Join-Path -Path $target -ChildPath 'skills') -Recurse
        foreach ($name in 'hooks', 'skills')
        {
            $null = New-Item -ItemType Junction -Path (Join-Path -Path $copilotHome -ChildPath $name) -Target (Join-Path -Path $target -ChildPath $name)
        }

        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path (Join-Path -Path $target -ChildPath 'contributor/profile.json')
        $emptyGitConfig = Join-Path -Path $root -ChildPath 'empty.gitconfig'
        Set-Content -LiteralPath $emptyGitConfig -Value '' -Encoding ascii

        $steps = @(
            @{ op = 'newSession' }
            @{ op = 'send'; prompt = 'turn before the compaction' }
            @{ op = 'compact' }
            @{ op = 'send'; prompt = 'turn after the compaction' }
            @{ op = 'disconnect' }
        )

        $startInfo = [Diagnostics.ProcessStartInfo]::new((Get-Command -Name 'node' -CommandType Application | Select-Object -First 1 -ExpandProperty Source))
        foreach ($argument in @((Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\Invoke-CopilotSdkConversation.mjs'), $PackageRoot, $copilotHome, $workspace, $RuntimePath))
        {
            $startInfo.Arguments += ' "' + $argument + '"'
        }

        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $workspace
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $utf8
        $startInfo.StandardErrorEncoding = $utf8
        $startInfo.EnvironmentVariables['USERPROFILE'] = $userHome
        $startInfo.EnvironmentVariables['HOME'] = $userHome
        $startInfo.EnvironmentVariables['LOCALAPPDATA'] = Join-Path -Path $root -ChildPath 'localappdata'
        $startInfo.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = $emptyGitConfig
        $startInfo.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
        $startInfo.EnvironmentVariables.Remove('PLUGIN_ROOT')
        $startInfo.EnvironmentVariables.Remove('COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS')

        $process = [Diagnostics.Process]::Start($startInfo)
        try
        {
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $inputBytes = $utf8.GetBytes((ConvertTo-Json -InputObject $steps -Depth 5 -Compress))
            $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.Close()

            if (-not $process.WaitForExit(660000))
            {
                $process.Kill()
                throw 'Invoke-CopilotSdkConversation.mjs did not exit within 660 seconds.'
            }

            $process.WaitForExit()
            if ($process.ExitCode -ne 0)
            {
                throw ('Invoke-CopilotSdkConversation.mjs exited with {0}: {1}' -f $process.ExitCode, $errorTask.Result)
            }

            $script:delivery = $outputTask.Result | ConvertFrom-Json
        }
        finally
        {
            $process.Dispose()
        }

        $script:levels = '"Kerberos" new; "PowerShell DSC" expert.'

        function Get-DeliveryToolMessage ([int] $Step)
        {
            foreach ($request in @($script:delivery.requests | Where-Object -Property step -EQ -Value $Step))
            {
                $request.messages | Where-Object -Property role -EQ -Value 'tool'
            }
        }
    }

    AfterAll {
        # The hooks keep their session clocks under the real LocalApplicationData,
        # which Windows resolves without the environment; remove this run's files.
        $sessions = Join-Path -Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) -ChildPath 'CopilotAtelier/sessions'
        foreach ($sessionId in @($script:delivery.steps | Where-Object -Property op -EQ -Value 'newSession' | ForEach-Object -Process { $_.sessionId }))
        {
            Get-ChildItem -Path (Join-Path -Path $sessions -ChildPath "session-$sessionId.*") -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    It 'records the levels sentence in the sessionStart hook.end event' {
        $sessionStart = @($script:delivery.events | Where-Object -FilterScript { $_.type -eq 'hook.end' -and $_.hookType -eq 'sessionStart' })

        $sessionStart.Count | Should -Be 1
        $sessionStart[0].output.additionalContext | Should -Match ([regex]::Escape($script:levels + ' 1 declared Knowledge area is unrated.'))
    }

    It 'shows the model the levels at session start' {
        $first = @($script:delivery.requests | Where-Object -Property step -EQ -Value 1)[0]

        ($first.messages | ForEach-Object -Process { $_.text }) -join "`n" | Should -Match ([regex]::Escape($script:levels))
    }

    It 'adds nothing to a tool result while no compaction is pending' {
        @(Get-DeliveryToolMessage -Step 1).text -join "`n" | Should -Not -Match 'Re-sent after a compaction'
    }

    It 'shows the model the levels again in the first tool result after a compaction' {
        $compaction = @($script:delivery.steps | Where-Object -Property op -EQ -Value 'compact')[0]
        $toolText = @(Get-DeliveryToolMessage -Step 3).text -join "`n"

        $compaction.success | Should -BeTrue
        $toolText | Should -Match ([regex]::Escape($script:levels))
        $toolText | Should -Match ([regex]::Escape('Re-sent after a compaction; make no offers in this session.'))
        $toolText | Should -Not -Match 'unrated'
    }
}

<#
    Decision record 0028, Calibration.Delivery: the two cells that are reported,
    not gated. A reply that makes no tool call after a compaction, and a
    plugin-only installation after a compaction, are known gaps of the design;
    these cases measure both in each runtime, so a host change that closes or
    widens either one shows up here. Each conversation stages its own layout.
#>
Describe 'Contributor levels in the reported delivery cells of <Runtime>' -Tag 'Integration' -Skip:(-not ($script:runtimeAvailable -and $script:pwshAvailable)) -ForEach $script:conversationRuntimes {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path -Path $repoRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
        $script:reportedSessionIds = [Collections.Generic.List[string]]::new()
        $script:reportedLevels = '"Kerberos" new; "PowerShell DSC" expert.'

        function Invoke-ReportedConversation
        {
            <#
                Runs one conversation of the fixture with the environment given
                and returns its { requests, events, steps }.
            #>
            param ([string] $Package, [string] $Runtime, [string] $CopilotHome, [string] $Workspace, [hashtable] $Environment, [object[]] $Steps)

            $utf8 = [Text.UTF8Encoding]::new($false)
            $startInfo = [Diagnostics.ProcessStartInfo]::new((Get-Command -Name 'node' -CommandType Application | Select-Object -First 1 -ExpandProperty Source))
            foreach ($argument in @((Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\Invoke-CopilotSdkConversation.mjs'), $Package, $CopilotHome, $Workspace, $Runtime))
            {
                $startInfo.Arguments += ' "' + $argument + '"'
            }

            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.WorkingDirectory = $Workspace
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.StandardOutputEncoding = $utf8
            $startInfo.StandardErrorEncoding = $utf8
            $startInfo.EnvironmentVariables.Remove('PLUGIN_ROOT')
            $startInfo.EnvironmentVariables.Remove('COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS')
            foreach ($name in $Environment.Keys)
            {
                $startInfo.EnvironmentVariables[$name] = [string] $Environment[$name]
            }

            $process = [Diagnostics.Process]::Start($startInfo)
            try
            {
                $outputTask = $process.StandardOutput.ReadToEndAsync()
                $errorTask = $process.StandardError.ReadToEndAsync()
                $inputBytes = $utf8.GetBytes((ConvertTo-Json -InputObject $Steps -Depth 5 -Compress))
                $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
                $process.StandardInput.Close()

                if (-not $process.WaitForExit(660000))
                {
                    $process.Kill()
                    throw 'Invoke-CopilotSdkConversation.mjs did not exit within 660 seconds.'
                }

                $process.WaitForExit()
                if ($process.ExitCode -ne 0)
                {
                    throw ('Invoke-CopilotSdkConversation.mjs exited with {0}: {1}' -f $process.ExitCode, $errorTask.Result)
                }

                $conversation = $outputTask.Result | ConvertFrom-Json
            }
            finally
            {
                $process.Dispose()
            }

            foreach ($sessionId in @($conversation.steps | Where-Object -Property op -EQ -Value 'newSession' | ForEach-Object -Process { $_.sessionId }))
            {
                $script:reportedSessionIds.Add($sessionId)
            }

            return $conversation
        }

        $emptyGitConfig = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N') + '.gitconfig')
        Set-Content -LiteralPath $emptyGitConfig -Value '' -Encoding ascii

        # Deployed layout: the registration exists, as the writer leaves it.
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $userHome = Join-Path -Path $root -ChildPath 'home'
        $target = Join-Path -Path $root -ChildPath 'CopilotAtelier'
        $deployedWorkspace = New-ContributorTestWorkspace -Path (Join-Path -Path $root -ChildPath 'workspace') -Area 'Kerberos', 'PowerShell DSC', 'Pester'
        $deployedHome = Join-Path -Path $userHome -ChildPath '.copilot'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $target -ChildPath 'hooks/scripts'), (Join-Path -Path $target -ChildPath 'skills'), $deployedHome -Force
        Set-Content -LiteralPath (Join-Path -Path $target -ChildPath '.copilotatelier.json') -Value '{}' -Encoding ascii
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json') -Destination (Join-Path -Path $target -ChildPath 'hooks')
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/scripts/*.ps1') -Destination (Join-Path -Path $target -ChildPath 'hooks/scripts')
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'skills/contributor-profile/assets/contributor-profile.hooks.json') -Destination (Join-Path -Path $target -ChildPath 'hooks/contributor-profile.json')
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'skills/contributor-profile') -Destination (Join-Path -Path $target -ChildPath 'skills') -Recurse
        foreach ($name in 'hooks', 'skills')
        {
            $null = New-Item -ItemType Junction -Path (Join-Path -Path $deployedHome -ChildPath $name) -Target (Join-Path -Path $target -ChildPath $name)
        }

        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path (Join-Path -Path $target -ChildPath 'contributor/profile.json')
        $script:noToolReply = Invoke-ReportedConversation -Package $PackageRoot -Runtime $RuntimePath -CopilotHome $deployedHome -Workspace $deployedWorkspace -Steps @(
            @{ op = 'newSession' }
            @{ op = 'send'; prompt = 'turn before the compaction' }
            @{ op = 'compact' }
            @{ op = 'send'; prompt = 'reply without a tool call'; noTool = $true }
            @{ op = 'send'; prompt = 'turn with a tool call' }
            @{ op = 'disconnect' }
        ) -Environment @{
            USERPROFILE         = $userHome
            HOME                = $userHome
            LOCALAPPDATA        = Join-Path -Path $root -ChildPath 'localappdata'
            GIT_CONFIG_GLOBAL   = $emptyGitConfig
            GIT_CONFIG_NOSYSTEM = '1'
        }

        <#
            Plugin-only layout: the shipped hooks.json resolves every script under
            PLUGIN_ROOT, no ~/.copilot/hooks exists, so the writers cannot create a
            registration, and the profile lives under LocalApplicationData.
        #>
        $pluginRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $plugin = Join-Path -Path $pluginRoot -ChildPath 'plugin'
        $pluginUserHome = Join-Path -Path $pluginRoot -ChildPath 'home'
        $pluginHome = Join-Path -Path $pluginUserHome -ChildPath '.copilot'
        $pluginLocalData = Join-Path -Path $pluginRoot -ChildPath 'localappdata'
        $pluginWorkspace = New-ContributorTestWorkspace -Path (Join-Path -Path $pluginRoot -ChildPath 'workspace') -Area 'Kerberos', 'PowerShell DSC', 'Pester'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $plugin -ChildPath 'com.github.copilot/hooks/scripts'), (Join-Path -Path $plugin -ChildPath 'skills'), $pluginHome, (Join-Path -Path $pluginWorkspace -ChildPath '.github/hooks') -Force
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/scripts/*.ps1') -Destination (Join-Path -Path $plugin -ChildPath 'com.github.copilot/hooks/scripts')
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'skills/contributor-profile') -Destination (Join-Path -Path $plugin -ChildPath 'skills') -Recurse
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json') -Destination (Join-Path -Path $pluginWorkspace -ChildPath '.github/hooks/hooks.json')
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path (Join-Path -Path $pluginLocalData -ChildPath 'CopilotAtelier/contributor/profile.json')
        $script:pluginOnly = Invoke-ReportedConversation -Package $PackageRoot -Runtime $RuntimePath -CopilotHome $pluginHome -Workspace $pluginWorkspace -Steps @(
            @{ op = 'newSession' }
            @{ op = 'send'; prompt = 'turn before the compaction' }
            @{ op = 'compact' }
            @{ op = 'send'; prompt = 'turn after the compaction' }
            @{ op = 'disconnect' }
        ) -Environment @{
            USERPROFILE         = $pluginUserHome
            HOME                = $pluginUserHome
            LOCALAPPDATA        = $pluginLocalData
            PLUGIN_ROOT         = $plugin
            GIT_CONFIG_GLOBAL   = $emptyGitConfig
            GIT_CONFIG_NOSYSTEM = '1'
        }

        function Get-ReportedStepText ($Conversation, [int] $Step, [string] $Role)
        {
            foreach ($request in @($Conversation.requests | Where-Object -Property step -EQ -Value $Step))
            {
                $request.messages | Where-Object -FilterScript { -not $Role -or $_.role -eq $Role } | ForEach-Object -Process { $_.text }
            }
        }
    }

    AfterAll {
        # The hooks keep their session clocks under the real LocalApplicationData,
        # which Windows resolves without the environment; remove this run's files.
        $sessions = Join-Path -Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) -ChildPath 'CopilotAtelier/sessions'
        foreach ($sessionId in $script:reportedSessionIds)
        {
            Get-ChildItem -Path (Join-Path -Path $sessions -ChildPath "session-$sessionId.*") -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    It 'gives a reply that makes no tool call after a compaction no levels (reported gap)' {
        $compaction = @($script:noToolReply.steps | Where-Object -Property op -EQ -Value 'compact')[0]
        $replyRequests = @($script:noToolReply.requests | Where-Object -Property step -EQ -Value 3)

        $compaction.success | Should -BeTrue
        $replyRequests.Count | Should -BeGreaterThan 0
        @($replyRequests | Where-Object -Property reply -Like -Value 'tool:*').Count | Should -Be 0 -Because 'the fake model answers this turn without a tool call'
        (Get-ReportedStepText -Conversation $script:noToolReply -Step 3) -join "`n" | Should -Not -Match ([regex]::Escape($script:reportedLevels))
        @($script:noToolReply.events | Where-Object -FilterScript { $_.step -eq 3 -and $_.type -eq 'hook.end' -and $_.hookType -eq 'postToolUse' }).Count | Should -Be 0
    }

    It 'gives the levels back on the next successful tool call after that reply' {
        $toolText = (Get-ReportedStepText -Conversation $script:noToolReply -Step 4 -Role 'tool') -join "`n"

        $toolText | Should -Match ([regex]::Escape($script:reportedLevels))
        $toolText | Should -Match ([regex]::Escape('Re-sent after a compaction; make no offers in this session.'))
    }

    It 'shows a plugin-only installation the levels at session start' {
        $sessionStart = @($script:pluginOnly.events | Where-Object -FilterScript { $_.type -eq 'hook.end' -and $_.hookType -eq 'sessionStart' })

        $sessionStart.Count | Should -Be 1
        $sessionStart[0].output.additionalContext | Should -Match ([regex]::Escape($script:reportedLevels))
        (Get-ReportedStepText -Conversation $script:pluginOnly -Step 1) -join "`n" | Should -Match ([regex]::Escape($script:reportedLevels))
    }

    It 'sends a plugin-only installation no levels after a compaction (reported gap)' {
        $compaction = @($script:pluginOnly.steps | Where-Object -Property op -EQ -Value 'compact')[0]
        $toolText = (Get-ReportedStepText -Conversation $script:pluginOnly -Step 3 -Role 'tool') -join "`n"

        $compaction.success | Should -BeTrue
        $toolText | Should -Not -BeNullOrEmpty -Because 'the turn after the compaction made a tool call'
        $toolText | Should -Not -Match ([regex]::Escape($script:reportedLevels))
        $toolText | Should -Not -Match 'Re-sent after a compaction'
        @($script:pluginOnly.events | Where-Object -FilterScript { $_.type -eq 'hook.end' -and $_.hookType -eq 'postToolUse' }).Count | Should -Be 0
    }
}
