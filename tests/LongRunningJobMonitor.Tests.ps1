Describe 'Start-JobHeartbeat' -Tag 'Unit' {
    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot (
            '../skills/long-running-job-monitor/scripts/Start-JobHeartbeat.ps1'
        )
        $script:scriptContent = Get-Content -LiteralPath $script:scriptPath -Raw -Encoding UTF8

        # Start-Process rejects -WindowStyle on non-Windows PowerShell.
        $script:isWindowsPlatform =
            [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

        $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
            'hb-tests-{0}' -f [guid]::NewGuid().ToString('N')
        )
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null

        function New-TestStatePath
        {
            Join-Path $script:tempRoot ('{0}.json' -f [guid]::NewGuid().ToString('N'))
        }

        function Get-ArmWait
        {
            param($Output)

            $line = $Output |
                Where-Object { $_ -is [string] -and $_ -match 'HEARTBEAT-ARMED' } |
                Select-Object -First 1

            [int][regex]::Match($line, 'wait=(\d+)m').Groups[1].Value
        }

        function Get-TickSummary
        {
            param($Output)

            $Output | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'State file' {
        It 'Should create the state file on the first arm' {
            $statePath = New-TestStatePath

            & $script:scriptPath -JobName 'job1' -StatePath $statePath -NoWait | Out-Null

            Test-Path -LiteralPath $statePath | Should -BeTrue
        }

        It 'Should record only the documented metadata keys' {
            $statePath = New-TestStatePath

            & $script:scriptPath -JobName 'job2' -StatePath $statePath -NoWait | Out-Null
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

            $expected = @(
                'ArmedProcessId', 'ArmedProcessStartUtc', 'Backoff',
                'BaseIntervalMinutes', 'ExpectedDurationMinutes',
                'HasProgressProbe', 'JobName', 'LastStatusUtc', 'LogPath',
                'NextTickDueUtc', 'StartedUtc', 'TickCount'
            )
            $actual = $state.PSObject.Properties.Name | Sort-Object

            $actual | Should -Be $expected
        }

        It 'Should never persist an executable probe' {
            # Regression guard: the state file is re-read and acted on at every
            # wake, so a stored scriptblock would be a code-execution sink.
            $statePath = New-TestStatePath

            & $script:scriptPath -JobName 'job3' -StatePath $statePath -NoWait | Out-Null
            $raw = Get-Content -LiteralPath $statePath -Raw

            $raw | Should -Not -Match 'Probe(Text|Base64|ScriptBlock)'
            $raw | Should -Not -Match 'GetTargetState'
        }

        It 'Should never expose a partially written state file to a concurrent reader' {
            # Regression guard: the state was written in place, which truncates
            # the file first, so a reader polling it could parse an empty or
            # cut-off file. The Cancellation test hit exactly that.
            $definition = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:scriptPath, [ref]$null, [ref]$null
            ).Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Save-HeartbeatState'
            }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))

            $directory = Join-Path $script:tempRoot 'concurrent-reader'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $statePath = Join-Path $directory 'state.json'

            # A large payload widens the window in which a write in progress is visible.
            $state = [pscustomobject]@{ JobName = 'race'; Padding = 'x' * 1MB }
            Save-HeartbeatState -Path $statePath -State $state

            $signal = [hashtable]::Synchronized(@{ Started = $false; Done = $false })
            $reader = [powershell]::Create().AddScript({
                param($Path, $Signal)

                $reads = 0
                $torn = 0
                $refused = 0
                $Signal.Started = $true
                while (-not $Signal.Done)
                {
                    try
                    {
                        $text = [IO.File]::ReadAllText($Path)
                        $reads++
                        if (-not $text.TrimEnd().EndsWith('}'))
                        {
                            $torn++
                        }
                    }
                    catch [System.IO.IOException], [System.UnauthorizedAccessException]
                    {
                        # A sharing conflict is a refused read, not a torn one.
                        $refused++
                    }
                }

                [pscustomobject]@{ Reads = $reads; Torn = $torn; Refused = $refused }
            }).AddArgument($statePath).AddArgument($signal)

            $handle = $reader.BeginInvoke()
            $failedWrites = 0
            try
            {
                $deadline = (Get-Date).AddSeconds(10)
                while (-not $signal.Started -and (Get-Date) -lt $deadline)
                {
                    Start-Sleep -Milliseconds 10
                }

                foreach ($write in 1..25)
                {
                    try
                    {
                        Save-HeartbeatState -Path $statePath -State $state -ErrorAction Stop
                    }
                    catch
                    {
                        # On Windows an in-place write is also refused while a reader holds the file.
                        $failedWrites++
                    }
                }
            }
            finally
            {
                $signal.Done = $true
                $result = $reader.EndInvoke($handle) | Select-Object -Last 1
                $reader.Dispose()
            }

            $result.Reads | Should -BeGreaterThan 0
            $result.Torn | Should -Be 0 -Because 'a reader must see the old or the new state, never a fragment'
            $failedWrites | Should -Be 0 -Because 'a reader holding the file open must not make the write fail'
            Get-ChildItem -LiteralPath $directory -Filter '*.tmp' | Should -BeNullOrEmpty
        }
    }

    Context 'Measured elapsed time' {
        It 'Should report zero elapsed minutes for a job that just started' {
            # Regression guard: parsing the round-trip timestamp without
            # RoundtripKind yields Kind=Local, and the later conversion then
            # shifts the value a second time by the local UTC offset.
            $statePath = New-TestStatePath

            $output = & $script:scriptPath -JobName 'job4' -StatePath $statePath -NoWait
            $summary = Get-TickSummary -Output $output

            $summary.ElapsedMinutes | Should -Be 0
        }

        It 'Should flag a job that outruns its declared duration' {
            $statePath = New-TestStatePath

            & $script:scriptPath -JobName 'job5' -StatePath $statePath -NoWait | Out-Null

            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $state.StartedUtc = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('o')
            $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8

            $output = & $script:scriptPath -JobName 'job5' -StatePath $statePath `
                -ExpectedDurationMinutes 60 -NoWait
            $summary = Get-TickSummary -Output $output

            $summary.ElapsedMinutes | Should -BeGreaterThan 60
            $summary.ExpectedDurationExceeded | Should -BeTrue
        }
    }

    Context 'Backoff ladder' {
        It 'Should follow the 1x, 1x, 2x, 3x, 6x ladder and then hold' {
            $statePath = New-TestStatePath
            $waits = @()

            $waits += Get-ArmWait -Output (
                & $script:scriptPath -JobName 'job6' -IntervalMinutes 10 -StatePath $statePath -NoWait
            )
            1..5 | ForEach-Object {
                $waits += Get-ArmWait -Output (
                    & $script:scriptPath -JobName 'job6' -StatePath $statePath -NoWait
                )
            }

            $waits | Should -Be @(10, 10, 20, 30, 60, 60)
        }

        It 'Should hold the base interval when backoff is disabled' {
            $statePath = New-TestStatePath
            $waits = @()

            $waits += Get-ArmWait -Output (
                & $script:scriptPath -JobName 'job7' -IntervalMinutes 10 -NoBackoff -StatePath $statePath -NoWait
            )
            1..3 | ForEach-Object {
                $waits += Get-ArmWait -Output (
                    & $script:scriptPath -JobName 'job7' -StatePath $statePath -NoWait
                )
            }

            $waits | Should -Be @(10, 10, 10, 10)
        }

        It 'Should not restart the ladder when re-armed with the same interval' {
            $statePath = New-TestStatePath

            & $script:scriptPath -JobName 'job8' -IntervalMinutes 10 -StatePath $statePath -NoWait | Out-Null
            & $script:scriptPath -JobName 'job8' -IntervalMinutes 10 -StatePath $statePath -NoWait | Out-Null
            $wait = Get-ArmWait -Output (
                & $script:scriptPath -JobName 'job8' -IntervalMinutes 10 -StatePath $statePath -NoWait
            )

            $wait | Should -Be 20
        }

        It 'Should restart the ladder when the interval is retuned' {
            $statePath = New-TestStatePath

            1..3 | ForEach-Object {
                & $script:scriptPath -JobName 'job9' -IntervalMinutes 10 -StatePath $statePath -NoWait | Out-Null
            }
            $wait = Get-ArmWait -Output (
                & $script:scriptPath -JobName 'job9' -IntervalMinutes 2 -StatePath $statePath -NoWait
            )

            $wait | Should -Be 2
        }
    }

    Context 'Sliding reset' {
        It 'Should mark a tick redundant while the interval has not elapsed' {
            $statePath = New-TestStatePath

            $output = & $script:scriptPath -JobName 'job10' -IntervalMinutes 10 -StatePath $statePath -NoWait
            $summary = Get-TickSummary -Output $output

            $summary.Redundant | Should -BeTrue
            $summary.RemainingMinutes | Should -BeGreaterThan 9
        }

        It 'Should advance the last-status stamp on TouchStatus' {
            $statePath = New-TestStatePath

            & $script:scriptPath -JobName 'job11' -StatePath $statePath -NoWait | Out-Null
            $before = (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).LastStatusUtc

            Start-Sleep -Milliseconds 20
            & $script:scriptPath -JobName 'job11' -StatePath $statePath -TouchStatus | Out-Null
            $after = (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).LastStatusUtc

            $after | Should -BeGreaterThan $before
        }

        It 'Should refuse TouchStatus before a tick is armed' {
            $statePath = New-TestStatePath

            { & $script:scriptPath -JobName 'job12' -StatePath $statePath -TouchStatus } |
                Should -Throw '*Arm a tick first*'
        }
    }

    Context 'Cancellation' {
        It 'Should cancel a pending tick and clear the armed process' {
            $statePath = New-TestStatePath
            $startProcess = @{
                FilePath = 'pwsh'
                PassThru = $true
                ArgumentList = @(
                    '-NoProfile', '-NonInteractive', '-File', $script:scriptPath,
                    '-JobName', 'stop1', '-IntervalMinutes', '1', '-StatePath', $statePath
                )
            }
            if ($script:isWindowsPlatform)
            {
                $startProcess['WindowStyle'] = 'Hidden'
            }
            $armed = Start-Process @startProcess

            $deadline = (Get-Date).AddSeconds(15)
            while (-not (Test-Path -LiteralPath $statePath) -and (Get-Date) -lt $deadline)
            {
                Start-Sleep -Milliseconds 100
            }
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $state.ArmedProcessId | Should -Be $armed.Id

            $output = & $script:scriptPath -JobName 'stop1' -StatePath $statePath -Stop
            $armed.WaitForExit(15000) | Should -BeTrue

            $output | Should -Match 'cancelled=True'
            (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).ArmedProcessId |
                Should -BeNullOrEmpty
        }

        It 'Should report nothing cancelled when no tick is armed' {
            $statePath = New-TestStatePath

            & $script:scriptPath -JobName 'stop2' -StatePath $statePath -NoWait | Out-Null
            $output = & $script:scriptPath -JobName 'stop2' -StatePath $statePath -Stop

            $output | Should -Match 'cancelled=False'
        }

        It 'Should refuse to stop a job it has no state for' {
            $statePath = New-TestStatePath

            { & $script:scriptPath -JobName 'stop3' -StatePath $statePath -Stop } |
                Should -Throw '*No heartbeat state*'
        }
    }

    Context 'Contract' {
        It 'Should reject a job name that is not path-safe' {
            $statePath = New-TestStatePath

            { & $script:scriptPath -JobName 'bad name/../x' -StatePath $statePath -NoWait } |
                Should -Throw
        }

        It 'Should reject an interval outside the supported range' {
            $statePath = New-TestStatePath

            { & $script:scriptPath -JobName 'job13' -IntervalMinutes 0 -StatePath $statePath -NoWait } |
                Should -Throw
        }

        It 'Should warn against detaching the timer from the harness' {
            # A fully detached process emits no completion notification, so the
            # agent is never woken and the heartbeat dies silently.
            $script:scriptContent | Should -Match 'ASYNC mode'
            $script:scriptContent | Should -Match 'Start-DetachedPowerShell'
        }
    }
}

Describe 'Wait-DetachedResult' -Tag 'Unit' {
    BeforeAll {
        $script:waiterPath = [IO.Path]::Combine(
            (Split-Path -Parent $PSScriptRoot), 'skills', 'long-running-job-monitor',
            'scripts', 'Wait-DetachedResult.ps1'
        )
        $script:waiterShell = (Get-Process -Id $PID).Path
        $script:waiterContent = Get-Content -LiteralPath $script:waiterPath -Raw -Encoding UTF8

        function Invoke-WaiterScript {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param(
                [hashtable] $Arguments = @{},
                [scriptblock] $OnReady
            )

            $parts = @("& '" + $script:waiterPath.Replace("'", "''") + "'")
            foreach ($key in $Arguments.Keys) {
                $parts += '-' + $key
                $parts += "'" + ([string]$Arguments[$key]).Replace("'", "''") + "'"
            }
            # EncodedCommand otherwise reduces every nonzero script exit to 1.
            $payload = '$ErrorActionPreference = ''Stop''; $ProgressPreference = ''SilentlyContinue''; ' +
                '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); ' +
                '[Console]::Out.WriteLine(''WAITER-READY''); [Console]::Out.Flush(); ' +
                ($parts -join ' ') + '; exit $LASTEXITCODE'
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
            $start = [Diagnostics.ProcessStartInfo]::new(
                $script:waiterShell, '-NoProfile -NonInteractive -EncodedCommand ' + $encoded
            )
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.WorkingDirectory = $TestDrive
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
            $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
            $process = [Diagnostics.Process]::Start($start)
            try {
                $errorTask = $process.StandardError.ReadToEndAsync()
                $ready = $process.StandardOutput.ReadLineAsync()
                if (-not $ready.Wait(15000) -or $ready.Result -ne 'WAITER-READY') {
                    throw 'Waiter child did not reach its readiness marker.'
                }
                $outputTask = $process.StandardOutput.ReadToEndAsync()
                if ($OnReady) { & $OnReady }
                if (-not $process.WaitForExit(15000)) {
                    throw 'Waiter exceeded the 15-second test budget.'
                }
                [pscustomobject]@{
                    ExitCode = $process.ExitCode
                    Output = $outputTask.GetAwaiter().GetResult()
                    Error = $errorTask.GetAwaiter().GetResult()
                }
            }
            finally {
                if (-not $process.HasExited) {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    $process.WaitForExit()
                }
                $process.Dispose()
            }
        }

        function Start-TestResultWriter {
            [CmdletBinding(SupportsShouldProcess)]
            [OutputType([pscustomobject])]
            param([Parameter(Mandatory)] [string] $Path)

            if (-not $PSCmdlet.ShouldProcess($Path, 'Write a delayed test result')) {
                return
            }

            $writer = [powershell]::Create().AddScript({
                param($ResultPath)
                Start-Sleep -Milliseconds 1100
                [IO.File]::WriteAllText($ResultPath, '0')
            }).AddArgument($Path)
            [pscustomobject]@{ Writer = $writer; Handle = $writer.BeginInvoke() }
        }
    }

    It 'ships the bounded detached-result waiter' {
        Test-Path -LiteralPath $script:waiterPath -PathType Leaf | Should -Be $true
    }

    It 'reports and preserves job result <Value>' -ForEach @(
        @{ Value = '0'; Expected = 0 }
        @{ Value = '1'; Expected = 1 }
    ) {
        $path = Join-Path $TestDrive 'completed.exit'
        [IO.File]::WriteAllText($path, $Value)
        $result = Invoke-WaiterScript -Arguments @{ ResultPath = $path }
        $result.ExitCode | Should -Be $Expected
        $result.Output | Should -Match "^DETACHED-RESULT $Value after \d+\.\d+ s\r?\n$"
        $result.Error | Should -BeNullOrEmpty
    }

    It 'waits for a delayed result in measured half-second steps' {
        $path = Join-Path $TestDrive 'delayed.exit'
        $writerState = @{}
        try {
            $result = Invoke-WaiterScript -Arguments @{ ResultPath = $path; TimeoutSeconds = 5 } -OnReady {
                $writerState.Job = Start-TestResultWriter -Path $path
            }
            $result.ExitCode | Should -Be 0
            $match = [regex]::Match($result.Output, '^DETACHED-RESULT 0 after (?<Seconds>\d+\.\d+) s')
            $match.Success | Should -Be $true
            $seconds = [double]::Parse($match.Groups['Seconds'].Value, [cultureinfo]::InvariantCulture)
            $seconds | Should -BeGreaterOrEqual 1
            $seconds | Should -BeLessThan 5
        }
        finally {
            if ($writerState.Job) {
                $writerState.Job.Writer.EndInvoke($writerState.Job.Handle) | Out-Null
                $writerState.Job.Writer.Dispose()
            }
        }
    }

    It 'does not mistake an empty result being written for success' {
        $path = Join-Path $TestDrive 'empty.exit'
        [IO.File]::WriteAllText($path, '')
        $writerState = @{}
        try {
            $result = Invoke-WaiterScript -Arguments @{ ResultPath = $path; TimeoutSeconds = 5 } -OnReady {
                $writerState.Job = Start-TestResultWriter -Path $path
            }
            $result.ExitCode | Should -Be 0
            $match = [regex]::Match($result.Output, '^DETACHED-RESULT 0 after (?<Seconds>\d+\.\d+) s')
            $match.Success | Should -Be $true
            $seconds = [double]::Parse($match.Groups['Seconds'].Value, [cultureinfo]::InvariantCulture)
            $seconds | Should -BeGreaterOrEqual 1
            $seconds | Should -BeLessThan 5
            $script:waiterContent | Should -Match 'Start-Sleep -Milliseconds 500'
        }
        finally {
            if ($writerState.Job) {
                $writerState.Job.Writer.EndInvoke($writerState.Job.Handle) | Out-Null
                $writerState.Job.Writer.Dispose()
            }
        }
    }

    It 'times out with code 124 and still tails the log' {
        $path = Join-Path $TestDrive 'missing.exit'
        $log = Join-Path $TestDrive 'timeout.log'
        [IO.File]::WriteAllLines($log, @('first', 'second', 'third'))
        $result = Invoke-WaiterScript -Arguments @{
            ResultPath = $path; LogPath = $log; TimeoutSeconds = 1; TailLines = 2
        }
        $result.ExitCode | Should -Be 124 -Because $result.Error
        $result.Output | Should -Match '^DETACHED-RESULT timeout after 1\.[0-5] s\r?\nsecond\r?\nthird\r?\n$'
        Test-Path -LiteralPath $path | Should -Be $false
    }

    It 'defaults to the last forty log lines' {
        $path = Join-Path $TestDrive 'default-tail.exit'
        $log = Join-Path $TestDrive 'default-tail.log'
        [IO.File]::WriteAllText($path, '0')
        [IO.File]::WriteAllLines($log, [string[]](1..60 | ForEach-Object { "line-$_" }))
        $result = Invoke-WaiterScript -Arguments @{ ResultPath = $path; LogPath = $log }
        $lines = $result.Output.TrimEnd() -split '\r?\n'
        $result.ExitCode | Should -Be 0
        $lines | Should -HaveCount 41
        $lines[1] | Should -Be 'line-21'
        $lines[-1] | Should -Be 'line-60'
    }

    It 'accepts literal relative paths with spaces and brackets' {
        $path = Join-Path $TestDrive 'result [one].exit'
        $log = Join-Path $TestDrive 'log [one].txt'
        [IO.File]::WriteAllText($path, '1')
        [IO.File]::WriteAllLines($log, @('first', 'last'))
        $result = Invoke-WaiterScript -Arguments @{
            ResultPath = 'result [one].exit'; LogPath = 'log [one].txt'; TailLines = 1
        }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '^DETACHED-RESULT 1 after \d+\.\d+ s\r?\nlast\r?\n$'
    }

    It 'does not open the log when TailLines is zero' {
        $path = Join-Path $TestDrive 'no-tail.exit'
        $log = Join-Path $TestDrive 'locked.log'
        [IO.File]::WriteAllText($path, '0')
        [IO.File]::WriteAllText($log, 'not read')
        $lock = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $result = Invoke-WaiterScript -Arguments @{ ResultPath = $path; LogPath = $log; TailLines = 0 }
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match '^DETACHED-RESULT 0 after \d+\.\d+ s\r?\n$'
            $result.Error | Should -BeNullOrEmpty
        }
        finally { $lock.Dispose() }
    }

    It 'rejects invalid result content <Value> explicitly' -ForEach @(
        @{ Value = '2' }
        @{ Value = 'Passed' }
        @{ Value = "0`n1" }
    ) {
        $path = Join-Path $TestDrive 'invalid.exit'
        [IO.File]::WriteAllText($path, $Value)
        $result = Invoke-WaiterScript -Arguments @{ ResultPath = $path; TimeoutSeconds = 1 }
        $result.ExitCode | Should -Be 1
        $result.Error | Should -Match 'must contain 0 or 1'
        $result.Output | Should -Not -Match 'DETACHED-RESULT 0'
    }

    It 'rejects out-of-range <Name>=<Value>' -ForEach @(
        @{ Name = 'TimeoutSeconds'; Value = 0 }
        @{ Name = 'TimeoutSeconds'; Value = 601 }
        @{ Name = 'TailLines'; Value = -1 }
        @{ Name = 'TailLines'; Value = 501 }
    ) {
        $arguments = @{ ResultPath = (Join-Path $TestDrive 'unused.exit') }
        $arguments[$Name] = $Value
        $result = Invoke-WaiterScript -Arguments $arguments
        $result.ExitCode | Should -Be 1
        $result.Error | Should -Match $Name
    }

    It 'only reads and preserves all input files and their write times' {
        $directory = Join-Path $TestDrive 'read-only'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $path = Join-Path $directory 'result.exit'
        $log = Join-Path $directory 'job.log'
        [IO.File]::WriteAllText($path, '0')
        [IO.File]::WriteAllText($log, "first`nlast`n")
        $resultTime = [IO.File]::GetLastWriteTimeUtc($path)
        $logTime = [IO.File]::GetLastWriteTimeUtc($log)
        $before = @([IO.Directory]::GetFiles($directory) | Sort-Object)
        $result = Invoke-WaiterScript -Arguments @{ ResultPath = $path; LogPath = $log }
        $result.ExitCode | Should -Be 0
        [IO.File]::ReadAllText($path) | Should -Be '0'
        [IO.File]::ReadAllText($log) | Should -Be "first`nlast`n"
        [IO.File]::GetLastWriteTimeUtc($path) | Should -Be $resultTime
        [IO.File]::GetLastWriteTimeUtc($log) | Should -Be $logTime
        @([IO.Directory]::GetFiles($directory) | Sort-Object) | Should -Be $before
    }

    It 'documents async-only terminal execution and exact defaults' {
        $script:waiterContent | Should -Match 'async mode only'
        $script:waiterContent | Should -Match 'synchronous wait blocks'
        $script:waiterContent | Should -Match 'detached waiter notifies nobody'
        $command = Get-Command -Name $script:waiterPath
        $command.Parameters['ResultPath'].Attributes.Mandatory | Should -Contain $true
        $script:waiterContent | Should -Match '\$TimeoutSeconds = 120'
        $script:waiterContent | Should -Match '\$TailLines = 40'
    }

    It '<Name> sanctions the bounded async waiter' -ForEach @(
        @{
            Name = 'Monitor Skill'
            Segments = @('skills', 'long-running-job-monitor', 'SKILL.md')
        }
        @{
            Name = 'Execution-safety Instruction'
            Segments = @('com.github.copilot', 'rules', 'powershell-execution-safety.instructions.md')
        }
        @{
            Name = 'Pester Instruction'
            Segments = @('com.github.copilot', 'rules', 'pester.instructions.md')
        }
    ) {
        $path = Split-Path -Parent $PSScriptRoot
        foreach ($segment in $Segments) { $path = Join-Path -Path $path -ChildPath $segment }
        $content = (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -replace '\s+', ' '
        $content | Should -Match 'Wait-DetachedResult\.ps1'
        $content | Should -Match 'async mode'
        $content | Should -Match 'two minutes'
        $content | Should -Match '500 ms'
    }
}
