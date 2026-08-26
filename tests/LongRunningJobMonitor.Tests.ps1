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
