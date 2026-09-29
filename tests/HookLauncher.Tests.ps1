<#
    Contract and behavior of the launcher commands in com.github.copilot/hooks/hooks.json.

    Every hook entry carries two launchers. VS Code runs `windows` on Windows and
    `command` everywhere else, but the Copilot SDK host ignores `windows` and runs
    `command` on every platform. Both launchers therefore have to find and run
    their script in every spawn mode a host uses, whatever subset of PLUGIN_ROOT,
    HOME, and USERPROFILE the host passes on. Windows does not define HOME.

    The behavioral cases never run a real hook script: SessionStart, Stop, and
    PreCompact write state. Each case swaps the script name in the launcher for a
    unique stub name and stages that stub under temporary candidate roots only,
    so no copy anywhere on the machine can match it.
#>

BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $hookConfigPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'com.github.copilot/hooks/hooks.json'
    $hookConfig = Get-Content -LiteralPath $hookConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pwshAvailable = [bool](Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue)

    $script:eventCase = @(
        foreach ($name in $hookConfig.hooks.PSObject.Properties.Name) {
            @{ Event = $name }
        }
    )

    $script:launcherCase = @(
        foreach ($name in $hookConfig.hooks.PSObject.Properties.Name) {
            foreach ($branch in 'command', 'windows') {
                $skipReason = ''
                if ($branch -eq 'windows' -and -not $script:isWindowsPlatform) {
                    $skipReason = 'powershell.exe exists only on Windows'
                } elseif ($branch -eq 'command' -and -not $pwshAvailable) {
                    $skipReason = 'pwsh is not on PATH'
                }

                @{ Event = $name; Branch = $branch; SkipReason = $skipReason }
            }
        }
    )

    # The spawn modes a host uses: Node's `shell: true` on Windows and on POSIX,
    # and a PowerShell that runs the launcher through -Command. The Copilot SDK
    # host takes the last route on Windows: it copies `command` into its
    # `powershell` field.
    $script:spawnCase = @(
        foreach ($name in $hookConfig.hooks.PSObject.Properties.Name) {
            foreach ($branch in 'command', 'windows') {
                foreach ($mode in 'cmd', 'sh', 'pwsh', 'powershell') {
                    $skipReason = ''
                    if ($branch -eq 'windows' -and -not $script:isWindowsPlatform) {
                        $skipReason = 'powershell.exe exists only on Windows'
                    } elseif ($mode -in 'cmd', 'powershell' -and -not $script:isWindowsPlatform) {
                        $skipReason = "$mode.exe exists only on Windows"
                    } elseif ($mode -eq 'sh' -and $script:isWindowsPlatform) {
                        $skipReason = '/bin/sh is not part of Windows'
                    } elseif (($branch -eq 'command' -or $mode -eq 'pwsh') -and -not $pwshAvailable) {
                        $skipReason = 'pwsh is not on PATH'
                    }

                    @{
                        Event = $name
                        Branch = $branch
                        Mode = $mode
                        # PreToolUse fails closed with 2, the lifecycle events warn
                        # with 1, and an outer PowerShell -Command reports only
                        # whether its last command succeeded, so it surfaces both as 1.
                        ObservedFailureCode = if ($name -eq 'PreToolUse' -and $mode -in 'cmd', 'sh') { 2 } else { 1 }
                        SkipReason = $skipReason
                    }
                }
            }
        }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:hookScriptRoot = Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/scripts'
    $script:hookConfig = Get-Content -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'com.github.copilot/hooks/hooks.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:pwshPath = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty Source
    $script:utf8 = [Text.UTF8Encoding]::new($false)
    $script:pluginScriptDirectory = 'com.github.copilot/hooks/scripts'
    $script:homeScriptDirectory = '.copilot/hooks/scripts'

    # The whole script is one double-quoted -Command argument, so cmd.exe, sh,
    # and an outer PowerShell each hand it to the interpreter as a single word.
    $script:launcherShape = '\A(?<interpreter>pwsh|powershell) (?<options>.+?) -Command "(?<script>[^"]+)"\z'

    function Get-HookLauncher {
        param(
            [Parameter(Mandatory)]
            [string]$EventName,

            [Parameter(Mandatory)]
            [ValidateSet('command', 'windows')]
            [string]$Branch
        )

        $entries = @($script:hookConfig.hooks.$EventName)
        $entries | Should -HaveCount 1 -Because "each case addresses the single $EventName entry"

        $entries[0].$Branch
    }

    function Get-HookScriptName {
        param(
            [Parameter(Mandatory)]
            [string]$Launcher
        )

        @([regex]::Matches($Launcher, 'scripts/(?<name>[\w\-]+\.ps1)') |
                ForEach-Object -Process { $_.Groups['name'].Value } |
                Sort-Object -Unique)
    }

    <#
        The exit code the spawning host can see. cmd.exe and sh pass the
        launcher's code through unchanged. An outer PowerShell -Command converts
        every non-zero native exit code to 1 (about_Pwsh, -Command), which no
        launcher text can prevent: a host that wraps hooks that way has to end
        its wrapper with `exit $LASTEXITCODE` to see a PreToolUse block as 2.
    #>
    function Get-ObservedExitCode {
        param(
            [Parameter(Mandatory)]
            [string]$Mode,

            [Parameter(Mandatory)]
            [int]$ExitCode
        )

        if ($Mode -in 'pwsh', 'powershell') {
            [int]($ExitCode -ne 0)
        } else {
            $ExitCode
        }
    }

    # Quotes one argument by the rules CommandLineToArgvW and .NET use to split
    # a command line, so the child receives the launcher verbatim.
    function ConvertTo-ProcessArgument {
        param(
            [Parameter(Mandatory)]
            [string]$Value
        )

        $escaped = [regex]::Replace($Value, '(\\*)"', {
                param($quoteMatch)

                ($quoteMatch.Groups[1].Value * 2) + '\"'
            })
        $escaped = [regex]::Replace($escaped, '(\\+)\z', {
                param($trailingMatch)

                $trailingMatch.Groups[1].Value * 2
            })

        '"' + $escaped + '"'
    }

    function Invoke-ChildProcess {
        param(
            [Parameter(Mandatory)]
            [string]$FilePath,

            [Parameter(Mandatory)]
            [string]$ArgumentLine,

            [Parameter(Mandatory)]
            [string]$WorkingDirectory,

            [Parameter()]
            [System.Collections.IDictionary]$Environment = @{},

            [Parameter()]
            [AllowEmptyString()]
            [string]$StandardInput = '',

            [Parameter()]
            [int]$TimeoutSecond = 120
        )

        $startInfo = [Diagnostics.ProcessStartInfo]::new($FilePath, $ArgumentLine)
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $script:utf8
        $startInfo.StandardErrorEncoding = $script:utf8

        # A console code page with a preamble would prepend a BOM to the payload.
        if ($startInfo.PSObject.Properties['StandardInputEncoding']) {
            $startInfo.StandardInputEncoding = $script:utf8
        }

        # Start from a host that sets neither variable; each case adds what it needs.
        foreach ($name in 'HOME', 'PLUGIN_ROOT', 'COPILOT_ATELIER_ALLOW_REMOTE') {
            $startInfo.EnvironmentVariables.Remove($name)
        }

        foreach ($name in $Environment.Keys) {
            if ($null -eq $Environment[$name]) {
                $startInfo.EnvironmentVariables.Remove($name)
            } else {
                $startInfo.EnvironmentVariables[$name] = [string]$Environment[$name]
            }
        }

        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo

        try {
            $null = $process.Start()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()

            try {
                $inputBytes = $script:utf8.GetBytes($StandardInput)
                $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
                $process.StandardInput.BaseStream.Flush()
                $process.StandardInput.Close()
            } catch [System.IO.IOException] {
                # The child exited before reading its input; the exit code decides.
                Write-Verbose -Message "Standard input closed early: $($_.Exception.Message)"
            }

            if (-not $process.WaitForExit($TimeoutSecond * 1000)) {
                try {
                    if ($process.GetType().GetMethod('Kill', [type[]]@([bool]))) {
                        $process.Kill($true)
                    } else {
                        $process.Kill()
                    }
                } catch [System.InvalidOperationException] {
                    Write-Verbose -Message 'The child exited between the timeout and the kill.'
                }

                throw ('{0} {1} did not exit within {2} seconds.' -f $FilePath, $ArgumentLine, $TimeoutSecond)
            }

            $process.WaitForExit()

            [pscustomobject]@{
                ExitCode = $process.ExitCode
                StandardOutput = $outputTask.Result
                StandardError = $errorTask.Result
            }
        } finally {
            $process.Dispose()
        }
    }

    function Invoke-HookLauncher {
        param(
            [Parameter(Mandatory)]
            [string]$Launcher,

            [Parameter(Mandatory)]
            [ValidateSet('cmd', 'sh', 'pwsh', 'powershell')]
            [string]$Mode,

            [Parameter(Mandatory)]
            [string]$WorkingDirectory,

            [Parameter()]
            [System.Collections.IDictionary]$Environment = @{},

            [Parameter()]
            [AllowEmptyString()]
            [string]$Payload = '{}'
        )

        switch ($Mode) {
            'cmd' {
                # Node's child_process with shell: true, passed verbatim.
                $filePath = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
                $argumentLine = '/d /s /c "' + $Launcher + '"'
            }
            'sh' {
                $filePath = '/bin/sh'
                $argumentLine = '-c ' + (ConvertTo-ProcessArgument -Value $Launcher)
            }
            'pwsh' {
                $filePath = $script:pwshPath
                $argumentLine = '-NoProfile -NonInteractive -Command ' + (ConvertTo-ProcessArgument -Value $Launcher)
            }
            'powershell' {
                $filePath = 'powershell'
                $argumentLine = '-NoProfile -NonInteractive -Command ' + (ConvertTo-ProcessArgument -Value $Launcher)
            }
        }

        Invoke-ChildProcess `
            -FilePath $filePath `
            -ArgumentLine $argumentLine `
            -WorkingDirectory $WorkingDirectory `
            -Environment $Environment `
            -StandardInput $Payload
    }

    function New-LauncherSandbox {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only creates directories under TestDrive.'
        )]
        param(
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [string]$EventName,

            [Parameter(Mandatory)]
            [string]$Branch
        )

        $caseRoot = Join-Path -Path $Root -ChildPath ([guid]::NewGuid().ToString('N'))
        $sandbox = [pscustomobject]@{
            StubName = 'Stub-{0}.ps1' -f [guid]::NewGuid().ToString('N')
            PluginRoot = Join-Path -Path $caseRoot -ChildPath 'plugin'
            HomeRoot = Join-Path -Path $caseRoot -ChildPath 'home'
            UserProfileRoot = Join-Path -Path $caseRoot -ChildPath 'userprofile'
            WorkingDirectory = Join-Path -Path $caseRoot -ChildPath 'cwd'
            RecordDirectory = Join-Path -Path $caseRoot -ChildPath 'record'
            Launcher = ''
        }

        foreach ($path in @(
                $sandbox.PluginRoot
                $sandbox.HomeRoot
                $sandbox.UserProfileRoot
                $sandbox.WorkingDirectory
                $sandbox.RecordDirectory
            )) {
            $null = New-Item -ItemType Directory -Path $path -Force
        }

        $launcher = Get-HookLauncher -EventName $EventName -Branch $Branch
        $scriptName = @(Get-HookScriptName -Launcher $launcher)
        $scriptName | Should -HaveCount 1 -Because 'a launcher runs exactly one script'
        $sandbox.Launcher = $launcher.Replace($scriptName[0], $sandbox.StubName)

        $sandbox
    }

    # The stub records the payload it read and the candidate it was staged as,
    # then exits with the code the case asks for.
    function Add-LauncherStub {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Sandbox,

            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [string]$Directory,

            [Parameter(Mandatory)]
            [ValidatePattern('\A[A-Z_]+\z')]
            [string]$Candidate,

            [Parameter()]
            [ValidatePattern('\A[\w -]*\z')]
            [string]$FailureMessage
        )

        $stubDirectory = Join-Path -Path $Root -ChildPath $Directory
        $null = New-Item -ItemType Directory -Path $stubDirectory -Force

        $stubLine = @(
            '$encoding = [Text.UTF8Encoding]::new($false)'
            '$reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), $encoding)'
            'try { $payload = $reader.ReadToEnd() } finally { $reader.Dispose() }'
            '$record = [Environment]::GetEnvironmentVariable(''COPILOT_ATELIER_STUB_RECORD'')'
            '[IO.File]::WriteAllText([IO.Path]::Combine($record, ''payload.txt''), $payload, $encoding)'
            ('[IO.File]::WriteAllText([IO.Path]::Combine($record, ''candidate.txt''), ''{0}'', $encoding)' -f $Candidate)
        )

        if ($FailureMessage) {
            $stubLine += "throw '$FailureMessage'"
        }

        $stubLine += 'exit [int][Environment]::GetEnvironmentVariable(''COPILOT_ATELIER_STUB_EXIT_CODE'')'

        [IO.File]::WriteAllText(
            (Join-Path -Path $stubDirectory -ChildPath $Sandbox.StubName),
            ($stubLine -join [Environment]::NewLine),
            $script:utf8
        )
    }

    function Invoke-SandboxLauncher {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Sandbox,

            [Parameter(Mandatory)]
            [string]$Mode,

            [Parameter()]
            [System.Collections.IDictionary]$Environment = @{},

            [Parameter()]
            [int]$ExitCode = 0,

            [Parameter()]
            [AllowEmptyString()]
            [string]$Payload = '{}'
        )

        foreach ($recordName in 'payload.txt', 'candidate.txt') {
            [IO.File]::Delete((Join-Path -Path $Sandbox.RecordDirectory -ChildPath $recordName))
        }

        $childEnvironment = @{
            COPILOT_ATELIER_STUB_RECORD = $Sandbox.RecordDirectory
            COPILOT_ATELIER_STUB_EXIT_CODE = [string]$ExitCode
        }

        foreach ($name in $Environment.Keys) {
            $childEnvironment[$name] = $Environment[$name]
        }

        Invoke-HookLauncher `
            -Launcher $Sandbox.Launcher `
            -Mode $Mode `
            -WorkingDirectory $Sandbox.WorkingDirectory `
            -Environment $childEnvironment `
            -Payload $Payload
    }

    function Get-StubRecord {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Sandbox
        )

        $candidatePath = Join-Path -Path $Sandbox.RecordDirectory -ChildPath 'candidate.txt'
        $payloadPath = Join-Path -Path $Sandbox.RecordDirectory -ChildPath 'payload.txt'

        [pscustomobject]@{
            Candidate = if (Test-Path -LiteralPath $candidatePath) { [IO.File]::ReadAllText($candidatePath) } else { '(stub did not run)' }
            Payload = if (Test-Path -LiteralPath $payloadPath) { [IO.File]::ReadAllBytes($payloadPath) } else { [byte[]]@() }
        }
    }
}

Describe 'Hook launcher contract' -Tag 'Unit' {
    It 'declares a type, both launchers, and a timeout for the <Event> hook' -ForEach $script:eventCase {
        $entries = @($script:hookConfig.hooks.$Event)
        $entries | Should -Not -BeNullOrEmpty

        foreach ($entry in $entries) {
            $entry.type | Should -BeExactly 'command'
            $entry.command | Should -BeOfType [string]
            $entry.command | Should -Not -BeNullOrEmpty
            $entry.windows | Should -BeOfType [string]
            $entry.windows | Should -Not -BeNullOrEmpty
            ($entry.timeout -is [int] -or $entry.timeout -is [long]) | Should -BeTrue -Because 'the timeout is a whole number of seconds'
            $entry.timeout | Should -BeGreaterThan 0
        }
    }

    It 'gives the <Branch> launcher of <Event> a home candidate that Windows always defines' -ForEach $script:launcherCase {
        <#
            Windows never defines HOME. The Copilot SDK host runs `command` on
            Windows, so a launcher that looks only at HOME resolves nothing there
            and a PreToolUse failure denies every tool call.
        #>
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch

        $launcher |
            Should -Match ("\[Environment\]::GetEnvironmentVariable\('USERPROFILE'\)|\[Environment\]::GetFolderPath\('UserProfile'\)")
    }

    It 'searches PLUGIN_ROOT, HOME, USERPROFILE, then the user profile folder in the <Branch> launcher of <Event>' -ForEach $script:launcherCase {
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch

        $candidate = @(
            [regex]::Matches($launcher, "GetEnvironmentVariable\('(?<name>\w+)'\)|GetFolderPath\('(?<folder>\w+)'\)") |
                ForEach-Object -Process {
                    if ($_.Groups['name'].Success) { $_.Groups['name'].Value } else { 'folder:' + $_.Groups['folder'].Value }
                }
        )

        $candidate | Should -Be @('PLUGIN_ROOT', 'HOME', 'USERPROFILE', 'folder:UserProfile')
    }

    It 'passes the <Branch> launcher of <Event> as one quoted -Command argument no outer shell expands' -ForEach $script:launcherCase {
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch

        $launcher | Should -Match $script:launcherShape
        $commandText = [regex]::Match($launcher, $script:launcherShape).Groups['script'].Value

        $commandText | Should -Not -Match '\$' -Because 'sh and PowerShell expand $ inside double quotes'
        $commandText | Should -Not -Match '`' -Because 'sh substitutes backticks and PowerShell reads them as escapes'
        $commandText | Should -Not -Match '"' -Because 'an inner double quote ends the single argument early'
        $commandText | Should -Not -Match '%' -Because 'cmd.exe expands %NAME% even inside double quotes'
    }

    It 'starts the <Branch> launcher of <Event> without a profile, without prompts, and past the execution policy' -ForEach $script:launcherCase {
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch

        $launcher | Should -Match $script:launcherShape
        [regex]::Match($launcher, $script:launcherShape).Groups['options'].Value |
            Should -BeExactly '-NoProfile -NonInteractive -ExecutionPolicy Bypass'
    }

    It 'derives the windows launcher of <Event> from command by swapping only the interpreter' -ForEach $script:eventCase {
        foreach ($entry in @($script:hookConfig.hooks.$Event)) {
            $entry.command | Should -Match '\Apwsh '
            $entry.windows | Should -BeExactly ('powershell' + $entry.command.Substring('pwsh'.Length))
        }
    }

    It 'names one shipped script in every candidate of the <Branch> launcher of <Event>' -ForEach $script:launcherCase {
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch
        $scriptName = @(Get-HookScriptName -Launcher $launcher)

        $scriptName | Should -HaveCount 1
        Test-Path -LiteralPath (Join-Path -Path $script:hookScriptRoot -ChildPath $scriptName[0]) -PathType Leaf |
            Should -BeTrue -Because "$($scriptName[0]) must ship in com.github.copilot/hooks/scripts"
    }
}

Describe 'Hook launcher behavior' -Tag 'Unit' {
    Context 'the <Branch> launcher of <Event> spawned through <Mode>' -ForEach $script:spawnCase {
        It 'runs the script from USERPROFILE with HOME unset and passes its exit code through' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.UserProfileRoot -Directory $script:homeScriptDirectory -Candidate 'USERPROFILE'

            foreach ($exitCode in 0, 1, 2) {
                $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -ExitCode $exitCode -Environment @{
                    USERPROFILE = $sandbox.UserProfileRoot
                }

                $result.ExitCode |
                    Should -Be (Get-ObservedExitCode -Mode $Mode -ExitCode $exitCode) -Because "the stub exited $exitCode. $($result.StandardError)"
                (Get-StubRecord -Sandbox $sandbox).Candidate | Should -BeExactly 'USERPROFILE'
            }
        }

        It 'prefers PLUGIN_ROOT over every home directory' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.PluginRoot -Directory $script:pluginScriptDirectory -Candidate 'PLUGIN_ROOT'
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.HomeRoot -Directory $script:homeScriptDirectory -Candidate 'HOME'
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.UserProfileRoot -Directory $script:homeScriptDirectory -Candidate 'USERPROFILE'

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Environment @{
                PLUGIN_ROOT = $sandbox.PluginRoot
                HOME = $sandbox.HomeRoot
                USERPROFILE = $sandbox.UserProfileRoot
            }

            $result.ExitCode | Should -Be 0 -Because $result.StandardError
            (Get-StubRecord -Sandbox $sandbox).Candidate | Should -BeExactly 'PLUGIN_ROOT'
        }

        It 'runs the script from HOME when USERPROFILE is absent' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.HomeRoot -Directory $script:homeScriptDirectory -Candidate 'HOME'

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Environment @{
                HOME = $sandbox.HomeRoot
                USERPROFILE = $null
            }

            $result.ExitCode | Should -Be 0 -Because $result.StandardError
            (Get-StubRecord -Sandbox $sandbox).Candidate | Should -BeExactly 'HOME'
        }

        It 'exits <ObservedFailureCode> and names the cause when no candidate holds the script' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            # Only the empty sandbox profile and the real profile folder are
            # candidates, and neither can hold a script with a fresh GUID name.
            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Environment @{
                USERPROFILE = $sandbox.UserProfileRoot
            }

            $result.ExitCode | Should -Be $ObservedFailureCode -Because $result.StandardError
            $result.StandardError |
                Should -Match ([regex]::Escape("CopilotAtelier hook $($sandbox.StubName) failed: ") + 'could not resolve')
        }

        It 'exits <ObservedFailureCode> and reports the underlying error when the script throws' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch
            $failureMessage = 'stub failure {0}' -f [guid]::NewGuid().ToString('N')
            Add-LauncherStub `
                -Sandbox $sandbox `
                -Root $sandbox.UserProfileRoot `
                -Directory $script:homeScriptDirectory `
                -Candidate 'USERPROFILE' `
                -FailureMessage $failureMessage

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Environment @{
                USERPROFILE = $sandbox.UserProfileRoot
            }

            $result.ExitCode | Should -Be $ObservedFailureCode -Because $result.StandardError
            $result.StandardError | Should -Match ([regex]::Escape("CopilotAtelier hook $($sandbox.StubName) failed: "))
            $result.StandardError | Should -Match ([regex]::Escape($failureMessage))
        }

        It 'delivers a non-ASCII payload to the script byte for byte' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.UserProfileRoot -Directory $script:homeScriptDirectory -Candidate 'USERPROFILE'

            # Built from code points so the test file itself stays ASCII.
            $text = 'Gr' + [char]0x00FC + [char]0x00DF + 'e ' + [char]0x2013 + ' ' + [char]0x65E5 + [char]0x672C +
                ' ' + [char]::ConvertFromUtf32(0x1F680) + ' cafe' + [char]0x0301
            $payload = '{"hook_event_name":"PreToolUse","tool_input":{"command":"echo ' + $text + '"}}'

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Payload $payload -Environment @{
                USERPROFILE = $sandbox.UserProfileRoot
            }

            $result.ExitCode | Should -Be 0 -Because $result.StandardError
            [BitConverter]::ToString((Get-StubRecord -Sandbox $sandbox).Payload) |
                Should -BeExactly ([BitConverter]::ToString($script:utf8.GetBytes($payload)))
        }

        It 'ignores copies reachable from the working directory' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            <#
                A workspace is untrusted content. Relative roots and unset roots
                must never resolve against it, or opening a repository that
                carries these paths would run its scripts on every tool call.
            #>
            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch
            foreach ($decoyDirectory in @(
                    $script:pluginScriptDirectory
                    $script:homeScriptDirectory
                    "relative/$($script:pluginScriptDirectory)"
                    "relative/$($script:homeScriptDirectory)"
                )) {
                Add-LauncherStub -Sandbox $sandbox -Root $sandbox.WorkingDirectory -Directory $decoyDirectory -Candidate 'WORKING_DIRECTORY'
            }
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.UserProfileRoot -Directory $script:homeScriptDirectory -Candidate 'USERPROFILE'

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Environment @{
                PLUGIN_ROOT = 'relative'
                HOME = 'relative'
                USERPROFILE = $sandbox.UserProfileRoot
            }

            $result.ExitCode | Should -Be 0 -Because $result.StandardError
            (Get-StubRecord -Sandbox $sandbox).Candidate | Should -BeExactly 'USERPROFILE'
        }
    }
}

Describe 'Hook launcher user profile fallback' -Tag 'Unit' {
    It 'resolves a rooted profile folder for the <Branch> launcher of <Event> with HOME and USERPROFILE removed' -ForEach $script:launcherCase {
        if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

        <#
            A host may pass a stripped environment. The last candidate asks the
            operating system for the profile folder, so it must evaluate to a
            real rooted path, never to the unresolvable '*' placeholder.
        #>
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch
        $expression = [regex]::Match($launcher, "\(\[string\]\[Environment\]::GetFolderPath\('UserProfile'\)\)\.PadLeft\(1, \[char\]42\)")
        $expression.Success | Should -BeTrue -Because 'the final home candidate must not depend on an environment variable'

        $interpreter = if ($Branch -eq 'windows') { 'powershell' } else { $script:pwshPath }
        $result = Invoke-ChildProcess `
            -FilePath $interpreter `
            -ArgumentLine ('-NoProfile -NonInteractive -Command ' + (ConvertTo-ProcessArgument -Value $expression.Value)) `
            -WorkingDirectory $TestDrive `
            -Environment @{ HOME = $null; USERPROFILE = $null }

        $result.ExitCode | Should -Be 0 -Because $result.StandardError
        $profileFolder = $result.StandardOutput.Trim()
        $profileFolder | Should -Not -BeExactly '*'
        [IO.Path]::IsPathRooted($profileFolder) | Should -BeTrue -Because "'$profileFolder' must be an absolute path"
        Test-Path -LiteralPath $profileFolder -PathType Container | Should -BeTrue
    }
}

Describe 'Hook launcher integration with Block-RemoteMutation' -Tag 'Integration' -Skip:(-not $script:isWindowsPlatform) {
    It '<Expectation> through the <Branch> launcher spawned by cmd.exe with HOME unset' -ForEach @(
        @{ Branch = 'command'; Command = 'git status --short'; ExitCode = 0; Expectation = 'allows a benign command' }
        @{ Branch = 'command'; Command = 'git push origin main'; ExitCode = 2; Expectation = 'blocks a push' }
        @{ Branch = 'command'; RawPayload = 'not json at all'; ExitCode = 0; Expectation = 'allows an unreadable payload' }
        @{ Branch = 'windows'; Command = 'git status --short'; ExitCode = 0; Expectation = 'allows a benign command' }
        @{ Branch = 'windows'; Command = 'git push origin main'; ExitCode = 2; Expectation = 'blocks a push' }
        @{ Branch = 'windows'; RawPayload = 'not json at all'; ExitCode = 0; Expectation = 'allows an unreadable payload' }
    ) {
        # The real guard, staged the way Install-CopilotAtelier deploys it.
        $caseRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $userProfile = Join-Path -Path $caseRoot -ChildPath 'userprofile'
        $workingDirectory = Join-Path -Path $caseRoot -ChildPath 'cwd'
        $deployedScripts = Join-Path -Path $userProfile -ChildPath $script:homeScriptDirectory
        $null = New-Item -ItemType Directory -Path $deployedScripts, $workingDirectory -Force
        Copy-Item -LiteralPath (Join-Path -Path $script:hookScriptRoot -ChildPath 'Block-RemoteMutation.ps1') -Destination $deployedScripts

        $payload = if ($RawPayload) {
            $RawPayload
        } else {
            [ordered]@{
                hook_event_name = 'PreToolUse'
                tool_name = 'run_in_terminal'
                tool_input = [ordered]@{ command = $Command }
            } | ConvertTo-Json -Depth 5 -Compress
        }

        $result = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch $Branch) `
            -Mode 'cmd' `
            -WorkingDirectory $workingDirectory `
            -Environment @{ USERPROFILE = $userProfile } `
            -Payload $payload

        $result.ExitCode | Should -Be $ExitCode -Because $result.StandardError
    }
}
