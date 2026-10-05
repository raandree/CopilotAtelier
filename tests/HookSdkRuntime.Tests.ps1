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
