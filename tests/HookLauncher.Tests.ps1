<#
    Contract and behavior of the launcher commands in com.github.copilot/hooks/hooks.json.

    Every hook entry carries three launchers. VS Code runs `windows` on Windows
    and `command` everywhere else; it ignores `powershell` while `windows` is
    present. The Copilot SDK host ignores `windows`: it runs `powershell` on
    Windows and `command` everywhere else. Every launcher therefore has to find
    and run its script in every spawn mode a host uses, whatever subset of
    PLUGIN_ROOT, HOME, and USERPROFILE the host passes on. Windows does not
    define HOME.

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
            foreach ($branch in 'command', 'windows', 'powershell') {
                $skipReason = ''
                if ($branch -eq 'windows' -and -not $script:isWindowsPlatform) {
                    $skipReason = 'powershell.exe exists only on Windows'
                } elseif ($branch -in 'command', 'powershell' -and -not $pwshAvailable) {
                    $skipReason = 'pwsh is not on PATH'
                }

                @{ Event = $name; Branch = $branch; SkipReason = $skipReason }
            }
        }
    )

    # The spawn modes a host uses: Node's `shell: true` on Windows and on POSIX,
    # and a PowerShell that runs the launcher through -Command. `vscode` is the
    # exact spawn of VS Code's Local harness on Windows, which runs only the
    # `windows` launcher, and `sdk` the one the Copilot SDK host's
    # copilot-runtime.exe used on Windows in a process capture on 2026-10-02.
    $script:spawnCase = @(
        foreach ($name in $hookConfig.hooks.PSObject.Properties.Name) {
            foreach ($branch in 'command', 'windows', 'powershell') {
                foreach ($mode in 'cmd', 'sh', 'pwsh', 'powershell', 'vscode', 'sdk') {
                    if (($mode -eq 'vscode' -and $branch -ne 'windows') -or
                        ($mode -eq 'sdk' -and $branch -ne 'powershell') -or
                        ($branch -eq 'powershell' -and $mode -notin 'cmd', 'sdk')) {
                        continue
                    }

                    $skipReason = ''
                    if ($branch -eq 'windows' -and -not $script:isWindowsPlatform) {
                        $skipReason = 'powershell.exe exists only on Windows'
                    } elseif ($mode -in 'cmd', 'powershell', 'vscode', 'sdk' -and -not $script:isWindowsPlatform) {
                        $skipReason = "$mode spawns exist only on Windows"
                    } elseif ($mode -eq 'sh' -and $script:isWindowsPlatform) {
                        $skipReason = '/bin/sh is not part of Windows'
                    } elseif (($branch -in 'command', 'powershell' -or $mode -in 'pwsh', 'sdk') -and -not $pwshAvailable) {
                        $skipReason = 'pwsh is not on PATH'
                    }

                    # PreToolUse fails closed with 2 and the lifecycle events warn
                    # with 1. An outer PowerShell -Command reports only whether its
                    # last command succeeded, so it surfaces both as 1, unless the
                    # launcher passes the inner exit code on, as `windows` and
                    # `powershell` do.
                    $passesExitCodeOn = $mode -in 'cmd', 'sh' -or $branch -in 'windows', 'powershell'

                    @{
                        Event = $name
                        Branch = $branch
                        Mode = $mode
                        ObservedFailureCode = if ($name -eq 'PreToolUse' -and $passesExitCodeOn) { 2 } else { 1 }
                        SkipReason = $skipReason
                    }
                }
            }
        }
    )

    # A module planted where a run identity could put one, with the PreToolUse guard as the hosts run it on Windows:
    # VS Code runs `windows` under Windows PowerShell, the Copilot SDK host runs `powershell` under pwsh, and Node's
    # `shell: true`, which HookContract approximates, runs `windows` under cmd.exe. Each spawn gets the places its
    # interpreters search: Windows PowerShell 5.1 does not read pwsh's personal folder, and pwsh does not read 5.1's
    # or fall back to its working directory.
    $plantedSpawn = @(
        @{ Mode = 'vscode'; Branch = 'windows'; Place = @('FirstEntry', 'Personal51', 'WorkingDirectory') }
        @{ Mode = 'sdk'; Branch = 'powershell'; Place = @('FirstEntry', 'PersonalPwsh') }
        @{ Mode = 'cmd'; Branch = 'windows'; Place = @('FirstEntry', 'Personal51', 'WorkingDirectory') }
    )
    $plantedPayload = @(
        @{ Payload = 'deny'; Command = 'git push origin main'; ExitCode = 2 }
        @{ Payload = 'allow'; Command = 'git status --short'; ExitCode = 0 }
    )

    $script:plantedPlaceCase = @(
        foreach ($spawn in $plantedSpawn) {
            foreach ($place in $spawn.Place) {
                foreach ($payload in $plantedPayload) {
                    $skipReason = if ($spawn.Mode -eq 'sdk' -and -not $pwshAvailable) { 'pwsh is not on PATH' } else { '' }

                    @{ Mode = $spawn.Mode; Branch = $spawn.Branch; Place = $place; Payload = $payload.Payload; Command = $payload.Command; ExitCode = $payload.ExitCode; SkipReason = $skipReason }
                }
            }
        }
    )

    # One control per spawn and place: the launcher without its pins has to load the planted module (R18-08).
    $script:plantedControlCase = @(
        foreach ($spawn in $plantedSpawn) {
            foreach ($place in $spawn.Place) {
                $skipReason = if ($spawn.Mode -eq 'sdk' -and -not $pwshAvailable) { 'pwsh is not on PATH' } else { '' }

                @{ Mode = $spawn.Mode; Branch = $spawn.Branch; Place = $place; SkipReason = $skipReason }
            }
        }
    )

    # Every name the launchers and the guard leave to name resolution once the module path is pinned. A module that exports
    # one of them is imported first through a pass-through Get-Item, so that it reaches every name and not only the first.
    $script:plantedNameCase = @(
        foreach ($spawn in $plantedSpawn) {
            foreach ($name in 'Get-Variable', 'Set-Variable', 'Get-Item', 'Select-Object', 'Sort-Object', 'ConvertFrom-Json', 'ConvertTo-Json', 'Write-Verbose') {
                foreach ($payload in $plantedPayload) {
                    $skipReason = if ($spawn.Mode -eq 'sdk' -and -not $pwshAvailable) { 'pwsh is not on PATH' } else { '' }

                    @{ Mode = $spawn.Mode; Branch = $spawn.Branch; Name = $name; Payload = $payload.Payload; Command = $payload.Command; ExitCode = $payload.ExitCode; SkipReason = $skipReason }
                }
            }
        }
    )

    $script:plantedRecorderCase = @(
        foreach ($spawn in $plantedSpawn | Where-Object -FilterScript { $_.Mode -ne 'cmd' }) {
            foreach ($kind in 'reads', 'runs') {
                $skipReason = if ($spawn.Mode -eq 'sdk' -and -not $pwshAvailable) { 'pwsh is not on PATH' } else { '' }

                @{ Mode = $spawn.Mode; Branch = $spawn.Branch; Kind = $kind; SkipReason = $skipReason }
            }
        }
    )

    # The closing statement of `windows` under the VS Code wrapper and of `powershell` under the Copilot SDK host's.
    $script:closingCase = @(
        foreach ($spawn in @(
                @{ Mode = 'vscode'; Branch = 'windows' }
                @{ Mode = 'sdk'; Branch = 'powershell' }
            )) {
            foreach ($head in @(
                    @{ Head = 'cmd /d /c exit 0'; Expected = 0 }
                    @{ Head = 'cmd /d /c exit 1'; Expected = 1 }
                    @{ Head = 'cmd /d /c exit 2'; Expected = 2 }
                    @{ Head = 'cmd /d /c exit 7'; Expected = 7 }
                    @{ Head = 'cmd /d /c exit -1'; Expected = -1 }
                    @{ Head = "& '{absent}'"; Expected = 2; Why = 'a program that does not start' }
                    @{ Head = "[Console]::Out.Write('')"; Expected = 2; Why = 'no native command' }
                )) {
                $skipReason = if ($spawn.Mode -eq 'sdk' -and -not $pwshAvailable) { 'pwsh is not on PATH' } else { '' }

                @{ Mode = $spawn.Mode; Branch = $spawn.Branch; Head = $head.Head; Expected = $head.Expected; Why = if ($head.Why) { $head.Why } else { $head.Head }; SkipReason = $skipReason }
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
    # What a logon environment hands a process on this machine. Windows PowerShell 5.1 puts its own personal folder first
    # when PSModulePath is this value, and also when the variable is not set at all, so a machine without one runs without it.
    $script:machineModulePath = if ($script:isWindowsPlatform) { [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') }
    $script:utf8 = [Text.UTF8Encoding]::new($false)

    <#
        Text from a child process, made safe for a test message: pwsh colours its errors with ANSI escape
        sequences, and Pester's NUnit report stops at the first character that XML cannot hold, so one
        failing case would cut off the report of every case after it. Escape sequences are dropped, and
        every other character outside printable ASCII, line breaks and tabs apart, becomes a question mark.
    #>
    function Format-ChildText {
        param(
            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Text
        )

        if ([string]::IsNullOrEmpty($Text)) {
            return ''
        }

        [regex]::Replace([regex]::Replace($Text, '\x1B\[[0-?]*[ -/]*[@-~]', ''), '[^\x09\x0A\x0D\x20-\x7E]', '?')
    }
    $script:pluginScriptDirectory = 'com.github.copilot/hooks/scripts'
    $script:homeScriptDirectory = '.copilot/hooks/scripts'

    # The whole script is one double-quoted -Command argument, so cmd.exe, sh,
    # and an outer PowerShell each hand it to the interpreter as a single word.
    # Only the windows and powershell launchers continue after it, with
    # Get-ExitPassThrough.
    $script:launcherShape = '\A(?<interpreter>pwsh|powershell) (?<options>.+?) -Command "(?<script>[^"]+)"(?<suffix>.*)\z'

    <#
        The statement every PowerShell process of a launcher runs before it
        resolves a command by name. Windows PowerShell 5.1 and pwsh load a
        command from the first module on PSModulePath that exports it, and the
        account's own module folders, or with 5.1 its working directory, come
        first, so a module planted there would answer for the guard. The pin
        sets the module path to the interpreter's own Modules folder through
        [Environment], [IO.Path] and [AppContext] alone, which no module can
        answer for, and without a $, which sh and cmd.exe would read.
    #>
    $script:modulePathPin = "[Environment]::SetEnvironmentVariable('PSModulePath', [IO.Path]::Combine([AppContext]::BaseDirectory, 'Modules'))"

    <#
        The statement the windows and powershell launchers end with. VS Code runs
        `windows`, and the Copilot SDK host `powershell`, as the -Command text of
        an outer PowerShell, which reports only whether its last command
        succeeded, so the launcher hands the inner exit code on itself. A
        missing code means the inner interpreter never ran and falls back to the
        launcher's own failure code. The outer PowerShell pins its own module
        path first, inside the same expression, so that Get-Variable cannot come
        from a module it inherited. Under cmd.exe the text only reaches the
        inner -Command after a try block that always exits.
    #>
    function Get-ExitPassThrough {
        param(
            [Parameter(Mandatory)]
            [ValidateSet(1, 2)]
            [int]$FailureCode
        )

        ' ; exit (@({0}) + @(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + {1})[0]' -f $script:modulePathPin, $FailureCode
    }

    <#
        A module that a planted-module case puts where PowerShell looks for
        modules, as a run identity could. Importing it appends 'imported' to the
        marker file, and ExitOnImport then ends the process with exit 0, as a
        module that answers for the guard would. Each command in Shadow appends
        'called <name>' and ends the process with exit 0. With PassThroughGetItem
        the module also exports a Get-Item that calls the built-in one, so that
        it is imported at the launcher's first Get-Item without changing what
        that does, and its other functions then come before the built-in
        cmdlets. Function adds commands with a body of their own.
    #>
    function New-PlantedModule {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only writes files under TestDrive.'
        )]
        param(
            [Parameter(Mandatory)]
            [string]$Directory,

            [Parameter(Mandatory)]
            [string]$Marker,

            [Parameter()]
            [string[]]$Shadow = @(),

            [Parameter()]
            [switch]$PassThroughGetItem,

            [Parameter()]
            [System.Collections.IDictionary]$Function = @{},

            [Parameter()]
            [switch]$ExitOnImport
        )

        $moduleFolder = Join-Path -Path $Directory -ChildPath 'PlantedModule'
        $null = New-Item -ItemType Directory -Path $moduleFolder -Force
        $quotedMarker = $Marker.Replace("'", "''")
        $line = [System.Collections.Generic.List[string]]::new()
        $exported = [System.Collections.Generic.List[string]]::new()

        $line.Add("[IO.File]::AppendAllText('$quotedMarker', 'imported' + [Environment]::NewLine)")
        if ($ExitOnImport) {
            $line.Add('[Environment]::Exit(0)')
        }

        foreach ($name in $Shadow) {
            $line.Add("function $name { [IO.File]::AppendAllText('$quotedMarker', 'called $name' + [Environment]::NewLine); [Environment]::Exit(0) }")
            $exported.Add($name)
        }

        if ($PassThroughGetItem -and $Shadow -notcontains 'Get-Item') {
            $line.Add('function Get-Item { Microsoft.PowerShell.Management\Get-Item @args }')
            $exported.Add('Get-Item')
        }

        foreach ($name in $Function.Keys) {
            $line.Add("function $name { $($Function[$name]) }")
            $exported.Add($name)
        }

        $line.Add('Export-ModuleMember -Function ' + (@($exported | ForEach-Object -Process { "'$_'" }) -join ', '))
        [IO.File]::WriteAllText((Join-Path -Path $moduleFolder -ChildPath 'PlantedModule.psm1'), ($line -join [Environment]::NewLine), $script:utf8)
    }

    <#
        Where a planted-module case puts its module, and the environment that
        makes the interpreter look there first:
        - FirstEntry: the first entry of PSModulePath. pwsh puts its own module
          folders ahead of an inherited value only when that value lacks them,
          so its value names $PSHOME\Modules after the planted folder, as the
          value a pwsh hands its children does.
        - Personal51: Windows PowerShell 5.1's folder in the documents folder;
          5.1 puts it first when PSModulePath equals the machine's value, as in
          a logon environment, and when the variable is not set, which is what a
          machine without a value of its own hands on.
        - PersonalPwsh: pwsh's folder in the documents folder, which pwsh
          always puts first.
        - WorkingDirectory: WindowsPowerShell\Modules in the working directory,
          which 5.1 puts first in place of its documents folder when that does
          not exist (R12-08).
        The hook script is staged under USERPROFILE, which the launcher searches,
        so the case never reaches a deployed copy.
    #>
    function New-PlantedCase {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only creates files under TestDrive.'
        )]
        param(
            [Parameter(Mandatory)]
            [ValidateSet('FirstEntry', 'Personal51', 'PersonalPwsh', 'WorkingDirectory')]
            [string]$Place,

            [Parameter(Mandatory)]
            [ValidateSet('vscode', 'sdk', 'cmd')]
            [string]$Mode,

            [Parameter(Mandatory)]
            [string]$ScriptName
        )

        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $userProfile = Join-Path -Path $root -ChildPath 'userprofile'
        $workingDirectory = Join-Path -Path $root -ChildPath 'cwd'
        $deployedScripts = Join-Path -Path $userProfile -ChildPath $script:homeScriptDirectory
        $null = New-Item -ItemType Directory -Path $deployedScripts, $workingDirectory -Force
        Copy-Item -LiteralPath (Join-Path -Path $script:hookScriptRoot -ChildPath $ScriptName) -Destination $deployedScripts

        if ($Place -ne 'WorkingDirectory') {
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $userProfile -ChildPath 'Documents') -Force
        }

        $systemModules = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\Modules'
        $pwshModules = Join-Path -Path (Split-Path -Parent $script:pwshPath) -ChildPath 'Modules'
        $logonModulePath = if ([string]::IsNullOrWhiteSpace($script:machineModulePath)) { $null } else { $script:machineModulePath }

        switch ($Place) {
            'FirstEntry' {
                $moduleDirectory = Join-Path -Path $root -ChildPath 'modules'
                $modulePath = if ($Mode -eq 'sdk') { "$moduleDirectory;$pwshModules;$systemModules" } else { "$moduleDirectory;$systemModules" }
            }
            'Personal51' {
                $moduleDirectory = Join-Path -Path $userProfile -ChildPath 'Documents\WindowsPowerShell\Modules'
                $modulePath = $logonModulePath
            }
            'PersonalPwsh' {
                $moduleDirectory = Join-Path -Path $userProfile -ChildPath 'Documents\PowerShell\Modules'
                $modulePath = "$pwshModules;$systemModules"
            }
            'WorkingDirectory' {
                $moduleDirectory = Join-Path -Path $workingDirectory -ChildPath 'WindowsPowerShell\Modules'
                $modulePath = $logonModulePath
            }
        }

        [pscustomobject]@{
            ModuleDirectory = $moduleDirectory
            Marker = Join-Path -Path $root -ChildPath 'planted.txt'
            WorkingDirectory = $workingDirectory
            Environment = @{ USERPROFILE = $userProfile; PSModulePath = $modulePath }
        }
    }

    function Get-PlantedRecord {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Case
        )

        if (Test-Path -LiteralPath $Case.Marker) { ([IO.File]::ReadAllText($Case.Marker) -replace '\s+', ' ').Trim() } else { '' }
    }

    function Get-HookLauncher {
        param(
            [Parameter(Mandatory)]
            [string]$EventName,

            [Parameter(Mandatory)]
            [ValidateSet('command', 'windows', 'powershell')]
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
        text inside the quoted -Command argument can prevent; the windows
        launcher therefore ends with a statement the outer PowerShell runs.
    #>
    function Get-ObservedExitCode {
        param(
            [Parameter(Mandatory)]
            [string]$Mode,

            [Parameter(Mandatory)]
            [string]$Branch,

            [Parameter(Mandatory)]
            [int]$ExitCode
        )

        if ($Mode -in 'pwsh', 'powershell', 'vscode', 'sdk' -and $Branch -notin 'windows', 'powershell') {
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
            [ValidateSet('cmd', 'sh', 'pwsh', 'powershell', 'vscode', 'sdk')]
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
            'vscode' {
                # HookExecutor in VS Code's built-in extensions/copilot/dist/extension.js
                # on Windows with ComSpec set to cmd.exe, arguments verbatim.
                $filePath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
                $argumentLine = '-ExecutionPolicy Bypass -NoProfile -NoLogo -Command ' + (ConvertTo-ProcessArgument -Value $Launcher)
            }
            'sdk' {
                # copilot-runtime.exe of the Copilot SDK host on Windows, as a
                # process capture showed on 2026-10-02.
                $filePath = $script:pwshPath
                $argumentLine = '-nop -nol -c ' + (ConvertTo-ProcessArgument -Value $Launcher)
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
    It 'declares a type, the three launchers, and a timeout for the <Event> hook' -ForEach $script:eventCase {
        $entries = @($script:hookConfig.hooks.$Event)
        $entries | Should -Not -BeNullOrEmpty

        foreach ($entry in $entries) {
            $entry.type | Should -BeExactly 'command'
            foreach ($launcherKey in 'command', 'windows', 'powershell') {
                $entry.$launcherKey | Should -BeOfType [string] -Because "$launcherKey is a launcher a host runs"
                $entry.$launcherKey | Should -Not -BeNullOrEmpty -Because "$launcherKey is a launcher a host runs"
            }
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

    It 'searches PLUGIN_ROOT, USERPROFILE, HOME, then the user profile folder in the <Branch> launcher of <Event>' -ForEach $script:launcherCase {
        <#
            USERPROFILE comes before HOME: Windows always defines USERPROFILE,
            while HOME there is whatever a tool such as Git for Windows set, so a
            HOME pointing at a writable tree would otherwise run a planted script
            instead of the deployed guard (post-release review SEC-02).
        #>
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch

        $candidate = @(
            [regex]::Matches($launcher, "GetEnvironmentVariable\('(?<name>\w+)'\)|GetFolderPath\('(?<folder>\w+)'\)") |
                ForEach-Object -Process {
                    if ($_.Groups['name'].Success) { $_.Groups['name'].Value } else { 'folder:' + $_.Groups['folder'].Value }
                }
        )

        $candidate | Should -Be @('PLUGIN_ROOT', 'USERPROFILE', 'HOME', 'folder:UserProfile')
    }

    It 'passes the <Branch> launcher of <Event> as one quoted -Command argument no outer shell expands' -ForEach $script:launcherCase {
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch

        $launcher | Should -Match $script:launcherShape
        $commandText = [regex]::Match($launcher, $script:launcherShape).Groups['script'].Value

        $commandText | Should -Not -Match '\$' -Because 'sh and PowerShell expand $ inside double quotes'
        $commandText | Should -Not -Match '`' -Because 'sh substitutes backticks and PowerShell reads them as escapes'
        $commandText | Should -Not -Match '"' -Because 'an inner double quote ends the single argument early'
        $commandText | Should -Not -Match '%' -Because 'cmd.exe expands %NAME% even inside double quotes'

        $suffix = [regex]::Match($launcher, $script:launcherShape).Groups['suffix'].Value
        $suffix | Should -Not -Match '[$`"%]' -Because 'the text after the argument reaches the same shells unquoted'
    }

    It 'pins the module path before the <Branch> launcher of <Event> resolves a command by name' -ForEach $script:launcherCase {
        <#
            Windows PowerShell 5.1 and pwsh load a command from the first module on
            PSModulePath that exports it, and the account's own module folders, or
            with 5.1 its working directory, come first: a module a run identity
            plants there answered for Get-Item, Select-Object and Get-Variable, and
            turned the guard's exit 2 into 0 (R12-02, R12-08, brief 18). The first
            statement of the -Command text therefore sets the module path to the
            interpreter's own Modules folder.
        #>
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch
        $commandText = [regex]::Match($launcher, $script:launcherShape).Groups['script'].Value
        $expected = "try { $($script:modulePathPin); "

        $commandText.Substring(0, [Math]::Min($commandText.Length, $expected.Length)) | Should -BeExactly $expected
    }

    It 'starts the <Branch> launcher of <Event> without a profile, without prompts, and past the execution policy' -ForEach $script:launcherCase {
        $launcher = Get-HookLauncher -EventName $Event -Branch $Branch

        $launcher | Should -Match $script:launcherShape
        [regex]::Match($launcher, $script:launcherShape).Groups['options'].Value |
            Should -BeExactly '-NoProfile -NonInteractive -ExecutionPolicy Bypass'
    }

    It 'derives the windows launcher of <Event> from command by swapping the interpreter and passing the exit code on' -ForEach $script:eventCase {
        foreach ($entry in @($script:hookConfig.hooks.$Event)) {
            $entry.command | Should -Match '\Apwsh '
            [regex]::Match($entry.command, $script:launcherShape).Groups['suffix'].Value |
                Should -BeExactly '' -Because 'sh runs command on Linux and macOS and rejects a PowerShell statement after it'

            $failureCode = [int][regex]::Match($entry.command, 'exit (?<code>\d) \}"\z').Groups['code'].Value
            $entry.windows |
                Should -BeExactly ('powershell' + $entry.command.Substring('pwsh'.Length) + (Get-ExitPassThrough -FailureCode $failureCode))
        }
    }

    It 'derives the powershell launcher of <Event> from command by passing the exit code on' -ForEach $script:eventCase {
        <#
            The Copilot SDK host prefers `powershell` on Windows and runs it as
            the -c text of an outer pwsh, so only a passed-on exit code lets a
            PreToolUse block arrive as 2 with its reason instead of `hook errored`.
        #>
        foreach ($entry in @($script:hookConfig.hooks.$Event)) {
            $failureCode = [int][regex]::Match($entry.command, 'exit (?<code>\d) \}"\z').Groups['code'].Value
            $entry.powershell | Should -BeExactly ($entry.command + (Get-ExitPassThrough -FailureCode $failureCode))
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
                    Should -Be (Get-ObservedExitCode -Mode $Mode -Branch $Branch -ExitCode $exitCode) -Because "the stub exited $exitCode. $(Format-ChildText $result.StandardError)"
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

            $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
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

            $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
            (Get-StubRecord -Sandbox $sandbox).Candidate | Should -BeExactly 'HOME'
        }

        It 'prefers USERPROFILE over HOME' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.HomeRoot -Directory $script:homeScriptDirectory -Candidate 'HOME'
            Add-LauncherStub -Sandbox $sandbox -Root $sandbox.UserProfileRoot -Directory $script:homeScriptDirectory -Candidate 'USERPROFILE'

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Environment @{
                HOME = $sandbox.HomeRoot
                USERPROFILE = $sandbox.UserProfileRoot
            }

            $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
            (Get-StubRecord -Sandbox $sandbox).Candidate | Should -BeExactly 'USERPROFILE'
        }

        It 'exits <ObservedFailureCode> and names the cause when no candidate holds the script' {
            if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

            # Only the empty sandbox profile and the real profile folder are
            # candidates, and neither can hold a script with a fresh GUID name.
            $sandbox = New-LauncherSandbox -Root $TestDrive -EventName $Event -Branch $Branch

            $result = Invoke-SandboxLauncher -Sandbox $sandbox -Mode $Mode -Environment @{
                USERPROFILE = $sandbox.UserProfileRoot
            }

            $result.ExitCode | Should -Be $ObservedFailureCode -Because (Format-ChildText $result.StandardError)
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

            $result.ExitCode | Should -Be $ObservedFailureCode -Because (Format-ChildText $result.StandardError)
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

            $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
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

            $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
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

        $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
        $profileFolder = $result.StandardOutput.Trim()
        $profileFolder | Should -Not -BeExactly '*'
        [IO.Path]::IsPathRooted($profileFolder) | Should -BeTrue -Because "'$profileFolder' must be an absolute path"
        Test-Path -LiteralPath $profileFolder -PathType Container | Should -BeTrue
    }
}

Describe 'Hook launcher integration with Block-RemoteMutation' -Tag 'Integration' -Skip:(-not $script:isWindowsPlatform) {
    BeforeAll {
        <#
            The guard blocks any command it cannot inspect within five seconds,
            and its first Windows PowerShell run on a cold CI runner can take
            that long: there it blocked a benign command with exit 2 (CI runs
            104 and 106, 2026-10-04), the first case below that runs the real
            guard under Windows PowerShell. That is the guard failing closed as
            designed, not a launcher defect, so one unasserted run through the
            same spawn pays the cold start before the cases below.
        #>
        $warmUpProfile = Join-Path -Path $TestDrive -ChildPath 'warm-up\userprofile'
        $warmUpDirectory = Join-Path -Path $TestDrive -ChildPath 'warm-up\cwd'
        $warmUpScripts = Join-Path -Path $warmUpProfile -ChildPath $script:homeScriptDirectory
        $null = New-Item -ItemType Directory -Path $warmUpScripts, $warmUpDirectory -Force
        Copy-Item -LiteralPath (Join-Path -Path $script:hookScriptRoot -ChildPath 'Block-RemoteMutation.ps1') -Destination $warmUpScripts

        $null = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch 'windows') `
            -Mode 'cmd' `
            -WorkingDirectory $warmUpDirectory `
            -Environment @{ USERPROFILE = $warmUpProfile } `
            -Payload '{"hook_event_name":"PreToolUse","tool_name":"run_in_terminal","tool_input":{"command":"git status --short"}}'
    }

    It '<Expectation> through the <Branch> launcher spawned by <Mode> with HOME unset' -ForEach @(
        @{ Branch = 'command'; Mode = 'cmd'; Command = 'git status --short'; ExitCode = 0; Expectation = 'allows a benign command' }
        @{ Branch = 'command'; Mode = 'cmd'; Command = 'git push origin main'; ExitCode = 2; Expectation = 'blocks a push' }
        @{ Branch = 'command'; Mode = 'cmd'; RawPayload = 'not json at all'; ExitCode = 0; Expectation = 'allows an unreadable payload' }
        @{ Branch = 'windows'; Mode = 'cmd'; Command = 'git status --short'; ExitCode = 0; Expectation = 'allows a benign command' }
        @{ Branch = 'windows'; Mode = 'cmd'; Command = 'git push origin main'; ExitCode = 2; Expectation = 'blocks a push' }
        @{ Branch = 'windows'; Mode = 'cmd'; RawPayload = 'not json at all'; ExitCode = 0; Expectation = 'allows an unreadable payload' }
        # VS Code treats only exit 2 as a block and any other failure as a warning.
        @{ Branch = 'windows'; Mode = 'vscode'; Command = 'git status --short'; ExitCode = 0; Expectation = 'allows a benign command' }
        @{ Branch = 'windows'; Mode = 'vscode'; Command = 'git push origin main'; ExitCode = 2; Expectation = 'blocks a push' }
        @{ Branch = 'windows'; Mode = 'vscode'; RawPayload = 'not json at all'; ExitCode = 0; Expectation = 'allows an unreadable payload' }
        # The Copilot SDK host denies on any non-zero exit, but only exit 2 carries the reason.
        @{ Branch = 'powershell'; Mode = 'sdk'; Command = 'git status --short'; ExitCode = 0; Expectation = 'allows a benign command' }
        @{ Branch = 'powershell'; Mode = 'sdk'; Command = 'git push origin main'; ExitCode = 2; Expectation = 'blocks a push' }
        @{ Branch = 'powershell'; Mode = 'sdk'; RawPayload = 'not json at all'; ExitCode = 0; Expectation = 'allows an unreadable payload' }
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
            -Mode $Mode `
            -WorkingDirectory $workingDirectory `
            -Environment @{ USERPROFILE = $userProfile } `
            -Payload $payload

        $result.ExitCode | Should -Be $ExitCode -Because (Format-ChildText $result.StandardError)
    }

    It 'hands the Copilot SDK host the block reason on standard output' {
        <#
            On exit 2 the SDK host merges one JSON object from standard output
            into the deny; its top-level permissionDecisionReason is what the
            model reads. Before 2026-10-02 the model saw only "(hook errored)",
            and until 2026-10-04 only "hook exited with code 2", because the
            runtime drops the object of a PascalCase event when it also carries
            hookSpecificOutput. HookSdkRuntime.Tests.ps1 checks the real runtime.
        #>
        $caseRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $userProfile = Join-Path -Path $caseRoot -ChildPath 'userprofile'
        $workingDirectory = Join-Path -Path $caseRoot -ChildPath 'cwd'
        $deployedScripts = Join-Path -Path $userProfile -ChildPath $script:homeScriptDirectory
        $null = New-Item -ItemType Directory -Path $deployedScripts, $workingDirectory -Force
        Copy-Item -LiteralPath (Join-Path -Path $script:hookScriptRoot -ChildPath 'Block-RemoteMutation.ps1') -Destination $deployedScripts

        $payload = [ordered]@{
            hook_event_name = 'PreToolUse'
            tool_name = 'powershell'
            tool_input = [ordered]@{ command = 'git push origin main' }
        } | ConvertTo-Json -Depth 5 -Compress

        $result = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch 'powershell') `
            -Mode 'sdk' `
            -WorkingDirectory $workingDirectory `
            -Environment @{ USERPROFILE = $userProfile } `
            -Payload $payload

        $result.ExitCode | Should -Be 2 -Because (Format-ChildText $result.StandardError)
        $decision = $result.StandardOutput | ConvertFrom-Json
        $decision.PSObject.Properties.Name | Should -Be @('permissionDecision', 'permissionDecisionReason')
        $decision.permissionDecision | Should -BeExactly 'deny'
        $decision.permissionDecisionReason | Should -Match '\ABlocked by Copilot Atelier: this command pushes to a git remote'
    }

    It 'never probes an unreachable HOME while USERPROFILE holds the guard through the <Branch> launcher spawned by <Mode>' -ForEach @(
        @{ Branch = 'command'; Mode = 'cmd' }
        @{ Branch = 'windows'; Mode = 'vscode' }
    ) {
        <#
            Probing a UNC home that does not answer took 21.7 seconds, past the
            20-second hook timeout, and the Copilot SDK host fails open on a
            timeout (post-release review SEC-04). 192.0.2.1 is TEST-NET-1, which
            is never routed.
        #>
        $caseRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $userProfile = Join-Path -Path $caseRoot -ChildPath 'userprofile'
        $workingDirectory = Join-Path -Path $caseRoot -ChildPath 'cwd'
        $deployedScripts = Join-Path -Path $userProfile -ChildPath $script:homeScriptDirectory
        $null = New-Item -ItemType Directory -Path $deployedScripts, $workingDirectory -Force
        Copy-Item -LiteralPath (Join-Path -Path $script:hookScriptRoot -ChildPath 'Block-RemoteMutation.ps1') -Destination $deployedScripts

        $payload = [ordered]@{
            hook_event_name = 'PreToolUse'
            tool_name = 'run_in_terminal'
            tool_input = [ordered]@{ command = 'git status --short' }
        } | ConvertTo-Json -Depth 5 -Compress

        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch $Branch) `
            -Mode $Mode `
            -WorkingDirectory $workingDirectory `
            -Environment @{ USERPROFILE = $userProfile; HOME = '\\192.0.2.1\profile' } `
            -Payload $payload
        $stopwatch.Stop()

        $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
        $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 10 -Because 'the launcher must not wait on the unreachable HOME'
    }
}

Describe 'Hook launcher closing statement' -Tag 'Unit' -Skip:(-not $script:isWindowsPlatform) {
    BeforeAll {
        # A module first on the module path of the outer PowerShell that exports Get-Variable, the one command the
        # closing statement resolves by name. Its function records the call and ends the process with exit 0.
        $script:closingRoot = Join-Path -Path $TestDrive -ChildPath 'closing'
        $script:closingProfile = Join-Path -Path $script:closingRoot -ChildPath 'userprofile'
        $script:closingDirectory = Join-Path -Path $script:closingRoot -ChildPath 'cwd'
        $script:closingModules = Join-Path -Path $script:closingRoot -ChildPath 'modules'
        $script:closingMarker = Join-Path -Path $script:closingRoot -ChildPath 'planted.txt'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:closingProfile -ChildPath 'Documents'), $script:closingDirectory -Force
        New-PlantedModule -Directory $script:closingModules -Marker $script:closingMarker -Shadow 'Get-Variable'
    }

    It 'exits <Expected> after <Why> under the <Mode> wrapper while a module that exports Get-Variable comes first' -ForEach $script:closingCase {
        if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

        <#
            The outer PowerShell of VS Code and of the Copilot SDK host runs the
            closing statement and nothing else of the launcher, so the statement
            pins that process's module path before it resolves Get-Variable, and
            keeps the codes: the inner one, or the failure code when no native
            command ran or the program did not start.
        #>
        [IO.File]::Delete($script:closingMarker)
        $launcher = Get-HookLauncher -EventName 'PreToolUse' -Branch $Branch
        $suffix = [regex]::Match($launcher, $script:launcherShape).Groups['suffix'].Value
        $line = $Head.Replace('{absent}', (Join-Path -Path $script:closingRoot -ChildPath 'absent\program.exe')) + $suffix
        $systemModules = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\Modules'
        $pwshModules = Join-Path -Path (Split-Path -Parent $script:pwshPath) -ChildPath 'Modules'
        $modulePath = if ($Mode -eq 'sdk') { "$($script:closingModules);$pwshModules;$systemModules" } else { "$($script:closingModules);$systemModules" }

        $result = Invoke-HookLauncher -Launcher $line -Mode $Mode -WorkingDirectory $script:closingDirectory -Payload '' -Environment @{
            USERPROFILE = $script:closingProfile
            PSModulePath = $modulePath
        }

        $called = if (Test-Path -LiteralPath $script:closingMarker) { [IO.File]::ReadAllText($script:closingMarker).Trim() } else { 'nothing' }
        $result.ExitCode | Should -Be $Expected -Because "the planted module recorded: $called. $(Format-ChildText $result.StandardError)"
        $called | Should -BeExactly 'nothing' -Because 'the closing statement pins the module path before it resolves Get-Variable'
    }
}

Describe 'Hook launcher under a planted module' -Tag 'Integration' -Skip:(-not $script:isWindowsPlatform) {
    BeforeAll {
        # The guard blocks what it cannot inspect within five seconds, and a cold start of Windows PowerShell on a CI runner
        # can take that long, so one unasserted run pays it first, as in the integration cases above.
        $warmUpProfile = Join-Path -Path $TestDrive -ChildPath 'planted-warm-up\userprofile'
        $warmUpDirectory = Join-Path -Path $TestDrive -ChildPath 'planted-warm-up\cwd'
        $warmUpScripts = Join-Path -Path $warmUpProfile -ChildPath $script:homeScriptDirectory
        $null = New-Item -ItemType Directory -Path $warmUpScripts, $warmUpDirectory -Force
        Copy-Item -LiteralPath (Join-Path -Path $script:hookScriptRoot -ChildPath 'Block-RemoteMutation.ps1') -Destination $warmUpScripts

        $null = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch 'windows') `
            -Mode 'vscode' `
            -WorkingDirectory $warmUpDirectory `
            -Environment @{ USERPROFILE = $warmUpProfile } `
            -Payload '{"hook_event_name":"PreToolUse","tool_name":"run_in_terminal","tool_input":{"command":"git status --short"}}'

        <#
            The names a module has to export to answer for whatever a launcher
            resolves first: every command the launchers and the two hook scripts
            name, apart from the scripts' own functions, and every command of
            the modules that Windows PowerShell loads on demand.
        #>
        $name = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $addName = {
            param($Ast, [string[]]$Defined)

            foreach ($command in $Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $commandName = $command.GetCommandName()
                if ($commandName -and $commandName -match '\A[A-Za-z]+-[A-Za-z0-9]+\z' -and $Defined -notcontains $commandName) {
                    $null = $name.Add($commandName)
                }
            }
        }

        foreach ($scriptName in 'Block-RemoteMutation.ps1', 'Add-RemoteGrant.ps1') {
            $tokens = $null
            $parseError = $null
            $tree = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $script:hookScriptRoot -ChildPath $scriptName), [ref]$tokens, [ref]$parseError)
            $defined = @($tree.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object -Process { $_.Name })
            & $addName $tree $defined
        }

        foreach ($eventName in 'PreToolUse', 'UserPromptSubmit') {
            foreach ($branch in 'windows', 'powershell') {
                $shape = [regex]::Match((Get-HookLauncher -EventName $eventName -Branch $branch), $script:launcherShape)
                foreach ($text in $shape.Groups['script'].Value, $shape.Groups['suffix'].Value.TrimStart(' ', ';')) {
                    $tokens = $null
                    $parseError = $null
                    & $addName ([System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseError)) @()
                }
            }
        }

        foreach ($command in Get-Command -Module 'Microsoft.PowerShell.Utility', 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Security' -CommandType Cmdlet, Function) {
            if ($command.Name -match '\A[A-Za-z]+-[A-Za-z0-9]+\z') {
                $null = $name.Add($command.Name)
            }
        }

        $script:everyName = @($name | Sort-Object)

        function script:New-PlantedPayload {
            param(
                [Parameter(Mandatory)]
                [string]$Command
            )

            [ordered]@{
                hook_event_name = 'PreToolUse'
                tool_name = 'run_in_terminal'
                tool_input = [ordered]@{ command = $Command }
            } | ConvertTo-Json -Depth 5 -Compress
        }

        # The launcher as it shipped before brief 18: the same text without the pin in the inner command and in the closing
        # statement, so that it resolves its commands through the module path it inherits.
        function script:Get-UnpinnedLauncher {
            param(
                [Parameter(Mandatory)]
                [string]$Launcher
            )

            $unpinned = $Launcher.Replace("try { $($script:modulePathPin); ", 'try { ').Replace("@($($script:modulePathPin)) + ", '')
            if ([string]::Equals($unpinned, $Launcher, [StringComparison]::Ordinal)) {
                throw 'the launcher holds no pin to remove, so the control would test nothing'
            }

            $unpinned
        }
    }

    # R18-08: the positive control of the place cases below. They pass when a pinned launcher loads nothing, and that would
    # also hold where the interpreter never looks in the planted place, as on a runner whose PSModulePath or documents folder
    # differs from this one. The same launcher without its pins has to load the module from each place.
    It 'loads the module from <Place> under <Mode> for the launcher without its pins (control)' -ForEach $script:plantedControlCase {
        if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

        $case = New-PlantedCase -Place $Place -Mode $Mode -ScriptName 'Block-RemoteMutation.ps1'
        New-PlantedModule -Directory $case.ModuleDirectory -Marker $case.Marker -Shadow $script:everyName -ExitOnImport

        $result = Invoke-HookLauncher `
            -Launcher (Get-UnpinnedLauncher -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch $Branch)) `
            -Mode $Mode `
            -WorkingDirectory $case.WorkingDirectory `
            -Environment $case.Environment `
            -Payload (New-PlantedPayload -Command 'git status --short')

        Get-PlantedRecord -Case $case | Should -Match 'imported' -Because "$Mode has to look in $Place before its own folders, or the cases of that place test nothing here. $(Format-ChildText $result.StandardError)"
    }

    It 'gives <ExitCode> for the <Payload> payload under <Mode> and never loads a module that answers for every command from <Place>' -ForEach $script:plantedPlaceCase {
        if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

        $case = New-PlantedCase -Place $Place -Mode $Mode -ScriptName 'Block-RemoteMutation.ps1'
        New-PlantedModule -Directory $case.ModuleDirectory -Marker $case.Marker -Shadow $script:everyName -ExitOnImport

        $result = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch $Branch) `
            -Mode $Mode `
            -WorkingDirectory $case.WorkingDirectory `
            -Environment $case.Environment `
            -Payload (New-PlantedPayload -Command $Command)

        $record = Get-PlantedRecord -Case $case
        $result.ExitCode | Should -Be $ExitCode -Because "the planted module recorded '$record'. $(Format-ChildText $result.StandardError)"
        $record | Should -BeExactly '' -Because 'every PowerShell process of the launcher pins its module path before it resolves a command'
    }

    It 'gives <ExitCode> for the <Payload> payload under <Mode> while a module that exports <Name> comes first' -ForEach $script:plantedNameCase {
        if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

        $case = New-PlantedCase -Place 'FirstEntry' -Mode $Mode -ScriptName 'Block-RemoteMutation.ps1'
        New-PlantedModule -Directory $case.ModuleDirectory -Marker $case.Marker -Shadow $Name -PassThroughGetItem

        $result = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'PreToolUse' -Branch $Branch) `
            -Mode $Mode `
            -WorkingDirectory $case.WorkingDirectory `
            -Environment $case.Environment `
            -Payload (New-PlantedPayload -Command $Command)

        $record = Get-PlantedRecord -Case $case
        $result.ExitCode | Should -Be $ExitCode -Because "the planted module recorded '$record'. $(Format-ChildText $result.StandardError)"
        $record | Should -BeExactly '' -Because "no module on the inherited path is imported, so none can answer for $Name"
    }

    It 'lets the grant recorder <Kind> the payload it is given under <Mode> while a planted module comes first' -ForEach $script:plantedRecorderCase {
        if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason }

        <#
            The recorder writes a Remote grant from what ConvertFrom-Json hands it.
            A module imported ahead of the built-in one can hand it a session and
            a prompt of the module's choosing, and one that ends the process
            before the recorder runs drops the grant that a prompt carries. The
            payload names no session, so a recorder that ran on it says so and
            records nothing, and no case writes a grant file.
        #>
        $case = New-PlantedCase -Place 'FirstEntry' -Mode $Mode -ScriptName 'Add-RemoteGrant.ps1'
        if ($Kind -eq 'reads') {
            New-PlantedModule -Directory $case.ModuleDirectory -Marker $case.Marker -PassThroughGetItem -Function @{
                'ConvertFrom-Json' = "[pscustomobject]@{ session_id = 'planted-session'; prompt = 'a prompt the module chose' }"
            }
        } else {
            New-PlantedModule -Directory $case.ModuleDirectory -Marker $case.Marker -Shadow 'Select-Object'
        }

        $result = Invoke-HookLauncher `
            -Launcher (Get-HookLauncher -EventName 'UserPromptSubmit' -Branch $Branch) `
            -Mode $Mode `
            -WorkingDirectory $case.WorkingDirectory `
            -Environment $case.Environment `
            -Payload '{"hook_event_name":"UserPromptSubmit","prompt":"hello"}'

        $record = Get-PlantedRecord -Case $case
        $result.ExitCode | Should -Be 0 -Because (Format-ChildText $result.StandardError)
        $result.StandardError | Should -Match 'names no usable session; recording no grant' -Because "the recorder has to run on the payload it was given; the planted module recorded '$record'"
        $record | Should -BeExactly '' -Because 'no module on the inherited path is imported'
    }
}
