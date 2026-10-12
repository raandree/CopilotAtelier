<#
    Arithmetic of the calibration latency Meter (Decision record 0028,
    rulings A9, A10, A16, A17, and A19): rotated cell order, ratios taken per
    replicate in frozen references, nearest-rank percentiles, inclusive
    thresholds, the withdrawn launch-unit levels, the re-baseline rule and its
    unit transfer check, and the rule that a verdict above Budget or Fail
    counts only when a second Meter run reproduces it; a failed launch's retry,
    its two stops, and the failure count that makes a run evidence only. It
    also pins the frozen reference, a driver with a frozen copy of the
    calibration reader and a fixed fixture (criterion 26). The measurement
    itself runs only by hand: tests/Fixtures/Measure-CalibrationLatency.ps1.
#>

BeforeDiscovery {
    $script:isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:editions = @(
        @{ Edition = 'PowerShell 7'; Executable = (Get-Command -Name 'pwsh' -CommandType Application | Select-Object -First 1 -ExpandProperty Source) }
        if ($script:isWindowsHost)
        {
            @{ Edition = 'Windows PowerShell 5.1'; Executable = (Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe') }
        }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/CalibrationMeter.ps1')
    $script:referencePath = Join-Path -Path $script:repoRoot -ChildPath 'tests/Fixtures/ReferenceHook'

    function script:Copy-Reference
    {
        <#
            Stages the frozen reference outside every git working tree, as the
            Meter does, and returns the staged folder.
        #>
        param ([string] $Name = ([guid]::NewGuid().ToString('N')))

        $staged = Join-Path -Path $TestDrive -ChildPath $Name
        Copy-Item -LiteralPath $script:referencePath -Destination $staged -Recurse -Force
        return $staged
    }

    function script:Set-LineEnding
    {
        <# Rewrites every file of a folder with the given line ending. #>
        param ([string] $Path, [string] $Ending)

        foreach ($file in [System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories))
        {
            $text = [System.IO.File]::ReadAllText($file).Replace("`r`n", "`n")
            [System.IO.File]::WriteAllText($file, $text.Replace("`n", $Ending), [System.Text.UTF8Encoding]::new($false))
        }
    }
}

Describe 'Calibration Meter arithmetic' -Tag 'Unit' {
    It 'rotates the cell order by one place per replicate, so every cell takes every position' {
        $cells = 'noop', 'reference', 'baseline', 'one', 'none', 'two', 'post', 'inject', 'guard'

        $orders = foreach ($replicate in 0..8) { , (Get-CalibrationMeterOrder -Cell $cells -Replicate $replicate) }

        $orders[0] | Should -Be $cells
        $orders[1] | Should -Be @('reference', 'baseline', 'one', 'none', 'two', 'post', 'inject', 'guard', 'noop')
        Get-CalibrationMeterOrder -Cell $cells -Replicate 9 | Should -Be $cells
        foreach ($position in 0..8)
        {
            @($orders | ForEach-Object -Process { $_[$position] } | Sort-Object -Unique).Count | Should -Be 9
        }
    }

    It 'takes the ratio inside each replicate in frozen references, before any percentile' {
        # The second replicate runs on a machine twice as slow: the ratios move
        # only where the work itself differs.
        $replicates = @(
            @{ noop = 800.0; reference = 1080.0; baseline = 820.0; one = 1240.0; post = 940.0 }
            @{ noop = 1600.0; reference = 2160.0; baseline = 1640.0; one = 1780.0; post = 1740.0 }
        )

        $added = @(Get-CalibrationMeterRatio -Replicate $replicates -Subject 'one' -Baseline 'baseline')
        $own = @(Get-CalibrationMeterRatio -Replicate $replicates -Subject 'post')

        $added | Should -Be @(1.5, 0.25)
        $own | Should -Be @(0.5, 0.25)
    }

    It 'refuses a replicate in which the reference ran no slower than the no-op hook' {
        $replicates = @(@{ noop = 900.0; reference = 900.0; post = 950.0 })

        { Get-CalibrationMeterRatio -Replicate $replicates -Subject 'post' } | Should -Throw -ExpectedMessage '*unit cannot be measured*'
    }

    It 'reads the nearest rank, so p95 of 20 replicates is the 19th smallest value and p50 the 10th' {
        $values = [double[]] (20..1)

        Get-CalibrationMeterRank -Value $values -Percent 95 | Should -Be 19
        Get-CalibrationMeterRank -Value $values -Percent 50 | Should -Be 10
        Get-CalibrationMeterRank -Value @(7.0) -Percent 95 | Should -Be 7
    }

    It 'meets a value at or below Budget and fails only a value above Fail' -ForEach @(
        @{ Value = 0.5; Expected = 'within budget' }
        @{ Value = 0.51; Expected = 'over budget' }
        @{ Value = 1.0; Expected = 'over budget' }
        @{ Value = 1.01; Expected = 'fail' }
    ) {
        Get-CalibrationMeterVerdict -Value $Value -Budget 0.5 -Fail 1.0 | Should -BeExactly $Expected
    }

    It 'counts a verdict above Budget or Fail only when another run reproduces it' -ForEach @(
        @{ Verdict = @('fail', 'fail'); Expected = 'fail' }
        @{ Verdict = @('fail', 'over budget'); Expected = 'over budget' }
        @{ Verdict = @('over budget', 'within budget'); Expected = 'within budget' }
        @{ Verdict = @('within budget', 'within budget'); Expected = 'within budget' }
        @{ Verdict = @('fail'); Expected = 'fail (unconfirmed)' }
        @{ Verdict = @('within budget'); Expected = 'within budget' }
    ) {
        Merge-CalibrationMeterVerdict -Verdict $Verdict | Should -BeExactly $Expected
    }

    It 'gates every cell of a tag at the level the re-baseline rule set from its own w' {
        <#
            Decision record 0028, step 7.3, 2026-10-08: the rule applied once,
            one w per tag (ruling A16), to the gated cells' lower-run p95
            values of the Prox1 pair of 2026-10-07 15:30 UTC and the RAANDREE3
            pair of 2026-10-08 09:42 UTC, both spawns, against the reference
            pinned below. A change to the reference re-baselines these.
        #>
        $budget = Get-CalibrationMeterBudget
        $sessionStart = Get-CalibrationMeterRebaseline -LowerRunP95 1.08, 0.49, 1.12, 0.53, 0.94, 0.45, 1.11, 0.56
        $postToolUse = Get-CalibrationMeterRebaseline -LowerRunP95 0.32, 0.38, 0.28, 0.38

        @($budget.Level.Keys | Sort-Object) | Should -Be @('PostToolUse, common path', 'SessionStart, no profile', 'SessionStart, one entry')
        foreach ($cell in 'SessionStart, one entry', 'SessionStart, no profile')
        {
            $budget.Level[$cell].Budget | Should -Be $sessionStart.Budget
            $budget.Level[$cell].Fail | Should -Be $sessionStart.Fail
        }

        $budget.Level['PostToolUse, common path'].Budget | Should -Be $postToolUse.Budget
        $budget.Level['PostToolUse, common path'].Fail | Should -Be $postToolUse.Fail
        $sessionStart.Budget | Should -Be 2.0
        $postToolUse.Budget | Should -Be 0.75
        $budget.ReferenceSha256 | Should -BeExactly '30fb3229afc003e248371b378883b2164a8ed00338c9f7647b40acfab2d29c79'
    }

    It 'sets Budget at the smallest multiple of 0.25 at least 1.75 times the worst lower run (<Case>)' -ForEach @(
        @{ Case = 'the largest lower run decides'; Lower = @(0.43, 0.31); W = 0.43; Budget = 1.0; Fail = 2.0 }
        @{ Case = 'a product just under a step'; Lower = @(0.4); W = 0.4; Budget = 0.75; Fail = 1.5 }
        @{ Case = 'a product exactly on a step'; Lower = @(1.0, 0.2); W = 1.0; Budget = 1.75; Fail = 3.5 }
        @{ Case = 'a product a rounding error above a step'; Lower = @(29 / 7); W = 29 / 7; Budget = 7.25; Fail = 14.5 }
    ) {
        $rule = Get-CalibrationMeterRebaseline -LowerRunP95 $Lower

        $rule.W | Should -Be $W
        $rule.Budget | Should -Be $Budget
        $rule.Fail | Should -Be $Fail
    }

    It 'holds the higher run of the widest 2026-10-06 pair within the Budget its lower run sets' {
        # The 1.75 factor must exceed the Meter's own run-to-run spread: the
        # widest pair moved 0.43 to 0.71, a factor of 1.65.
        (Get-CalibrationMeterRebaseline -LowerRunP95 0.43).Budget | Should -BeGreaterOrEqual 0.71
    }

    It 'refuses a lower run that is not positive' {
        { Get-CalibrationMeterRebaseline -LowerRunP95 0.4, 0 } | Should -Throw
    }

    It 'passes the unit transfer check only within 1.3 times in either direction (<Case>)' -ForEach @(
        @{ Case = 'equal scaling'; Reference = 1.2; Step = 1.2; Expected = $true }
        @{ Case = 'exactly 1.3 apart'; Reference = 1.3; Step = 1.0; Expected = $true }
        @{ Case = 'just over 1.3 apart'; Reference = 1.0; Step = 1.31; Expected = $false }
        @{ Case = 'the launch unit of 2026-10-06'; Reference = 2.4; Step = 1.2; Expected = $false }
    ) {
        Test-CalibrationMeterTransfer -ReferenceRatio $Reference -StepRatio $Step | Should -Be $Expected
    }
}

Describe 'Calibration Meter launch' -Tag 'Unit' {
    BeforeAll {
        $script:context = @{ Run = 2; Host = 'SDK'; Cell = 'SessionStart, two entries'; Replicate = 7 }

        function script:New-Launch
        {
            <# A launch that returns the given measurements in order, one per call. #>
            param ([object[]] $Measurement)

            $queue = [System.Collections.Generic.Queue[object]]::new()
            foreach ($item in $Measurement) { $queue.Enqueue($item) }
            return { $queue.Dequeue() }.GetNewClosure()
        }

        $script:crash = [pscustomobject] @{ Milliseconds = 5.0; ExitCode = -2146232797; Output = ''; Error = "Process terminated. probe`r`n   at System.Environment.FailFast(String message)`r`n" }
        $script:success = [pscustomobject] @{ Milliseconds = 900.0; ExitCode = 0; Output = '{}'; Error = '' }
    }

    It 'returns the measurement of a launch that exits 0 and records no failure' {
        $failure = [System.Collections.Generic.List[object]]::new()

        $measurement = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:success) -Failure $failure -Context $script:context

        $measurement.Milliseconds | Should -Be 900.0
        $failure.Count | Should -Be 0
    }

    It 'records a launch that exits non-zero with its exit code and standard error, then runs it once more in the same position' {
        $failure = [System.Collections.Generic.List[object]]::new()

        $measurement = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $script:success) -Failure $failure -Context $script:context -WarningAction SilentlyContinue

        $measurement.Milliseconds | Should -Be 900.0
        $failure.Count | Should -Be 1
        $failure[0].Run | Should -Be 2
        $failure[0].Host | Should -BeExactly 'SDK'
        $failure[0].Cell | Should -BeExactly 'SessionStart, two entries'
        $failure[0].Replicate | Should -Be 7
        $failure[0].Attempt | Should -Be 1
        $failure[0].ExitCode | Should -Be -2146232797
        $failure[0].ExitCodeHex | Should -BeExactly '0x80131623'
        $failure[0].Error | Should -BeExactly 'Process terminated. probe at System.Environment.FailFast(String message)'
    }

    It 'warns as soon as a launch fails, so a run in progress shows it' {
        $failure = [System.Collections.Generic.List[object]]::new()

        $null = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $script:success) -Failure $failure -Context $script:context -WarningVariable warned -WarningAction SilentlyContinue

        @($warned).Count | Should -Be 1
        [string] $warned[0] | Should -Match '0x80131623'
        [string] $warned[0] | Should -Match 'SessionStart, two entries'
    }

    It 'stops the Meter when the launch fails a second time, naming both exit codes and the standard error' {
        $failure = [System.Collections.Generic.List[object]]::new()
        $second = [pscustomobject] @{ Milliseconds = 4.0; ExitCode = 1; Output = ''; Error = 'could not resolve the script' }

        { Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $second) -Failure $failure -Context $script:context -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage "*SDK 'SessionStart, two entries'*0x80131623*0x00000001*could not resolve the script*"
        $failure.Count | Should -Be 2
    }

    It 'keeps a recorded standard error on one line and at most 2,000 characters' {
        $failure = [System.Collections.Generic.List[object]]::new()
        $long = [pscustomobject] @{ Milliseconds = 5.0; ExitCode = 1; Output = ''; Error = ("line`n" * 1000) }

        $null = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $long, $script:success) -Failure $failure -Context $script:context -WarningAction SilentlyContinue

        $failure[0].Error | Should -Not -Match '[\r\n]'
        $failure[0].Error.Length | Should -BeLessOrEqual 2000
        $failure[0].Error | Should -Match '\.\.\.\z'
    }

    It 'stops the Meter when a third launch fails in one run and spawn, even when no two fall together (A19)' {
        $failure = [System.Collections.Generic.List[object]]::new()
        $exitOne = [pscustomobject] @{ Milliseconds = 4.0; ExitCode = 1; Output = ''; Error = 'could not resolve the script' }
        $accessViolation = [pscustomobject] @{ Milliseconds = 6.0; ExitCode = -1073741819; Output = ''; Error = 'access violation' }

        $null = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $script:success) -Failure $failure -Context @{ Run = 2; Host = 'SDK'; Cell = 'SessionStart, one entry'; Replicate = 3 } -WarningAction SilentlyContinue
        $null = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $exitOne, $script:success) -Failure $failure -Context @{ Run = 2; Host = 'SDK'; Cell = 'PostToolUse, inject path'; Replicate = 9 } -WarningAction SilentlyContinue

        { Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $accessViolation, $script:success) -Failure $failure -Context @{ Run = 2; Host = 'SDK'; Cell = 'Push guard, benign tool'; Replicate = 15 } -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage "*SDK*run 2*3 failed launches*0x80131623*0x00000001*0xC0000005*access violation*"
        $failure.Count | Should -Be 3
    }

    It 'counts the run budget per run and spawn, so failures spread over others do not stop it (A19)' {
        $failure = [System.Collections.Generic.List[object]]::new()

        foreach ($context in @(
                @{ Run = 1; Host = 'SDK'; Cell = 'SessionStart, one entry'; Replicate = 4 }
                @{ Run = 1; Host = 'SDK'; Cell = 'SessionStart, two entries'; Replicate = 11 }
                @{ Run = 1; Host = 'VS Code'; Cell = 'SessionStart, two entries'; Replicate = 5 }
                @{ Run = 2; Host = 'SDK'; Cell = 'SessionStart, two entries'; Replicate = 8 }
            ))
        {
            { Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $script:success) -Failure $failure -Context $context -WarningAction SilentlyContinue } |
                Should -Not -Throw
        }

        $failure.Count | Should -Be 4
    }

    It 'marks a failure in a warm-up replicate as not measured, and any other as measured (A19)' {
        $failure = [System.Collections.Generic.List[object]]::new()

        $null = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $script:success) -Failure $failure -Context @{ Run = 1; Host = 'SDK'; Cell = 'No-op hook'; Replicate = 1; Measured = $false } -WarningAction SilentlyContinue
        $null = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $script:success) -Failure $failure -Context @{ Run = 1; Host = 'SDK'; Cell = 'No-op hook'; Replicate = 3; Measured = $true } -WarningAction SilentlyContinue
        $null = Invoke-CalibrationMeterLaunch -Launch (New-Launch -Measurement $script:crash, $script:success) -Failure $failure -Context $script:context -WarningAction SilentlyContinue

        $failure[0].Measured | Should -Be $false
        $failure[1].Measured | Should -Be $true
        $failure[2].Measured | Should -Be $true -Because 'a context that does not say counts as measured'
    }
}

Describe 'Calibration Meter failure count' -Tag 'Unit' {
    It 'counts the failed launches of one run and spawn, warm-up included unless -MeasuredOnly (A19)' {
        $failure = [System.Collections.Generic.List[object]]::new()
        $failure.Add([pscustomobject] @{ Run = 1; Host = 'SDK'; Measured = $true })
        $failure.Add([pscustomobject] @{ Run = 1; Host = 'SDK'; Measured = $false })
        $failure.Add([pscustomobject] @{ Run = 1; Host = 'VS Code'; Measured = $true })
        $failure.Add([pscustomobject] @{ Run = 2; Host = 'SDK'; Measured = $true })

        Get-CalibrationMeterFailureCount -Failure $failure -Run 1 -SpawnHost 'SDK' | Should -Be 2
        Get-CalibrationMeterFailureCount -Failure $failure -Run 1 -SpawnHost 'SDK' -MeasuredOnly | Should -Be 1
        Get-CalibrationMeterFailureCount -Failure $failure -Run 1 -SpawnHost 'VS Code' | Should -Be 1
        Get-CalibrationMeterFailureCount -Failure $failure -Run 2 -SpawnHost 'SDK' | Should -Be 1
        Get-CalibrationMeterFailureCount -Failure $failure -Run 2 -SpawnHost 'VS Code' | Should -Be 0
    }

    It 'counts zero in an empty list' {
        $failure = [System.Collections.Generic.List[object]]::new()

        Get-CalibrationMeterFailureCount -Failure $failure -Run 1 -SpawnHost 'SDK' -MeasuredOnly | Should -Be 0
    }
}

Describe 'Frozen reference' -Tag 'Unit' {
    It 'is pinned by one composite SHA-256, so a change fails until both latency tags are re-baselined (criterion 26)' {
        Get-CalibrationMeterReferenceHash -Path $script:referencePath | Should -BeExactly (Get-CalibrationMeterBudget).ReferenceSha256
    }

    It 'pins the text, not the line endings a checkout gives it' {
        $lf = Copy-Reference -Name 'lf'
        $crlf = Copy-Reference -Name 'crlf'
        Set-LineEnding -Path $lf -Ending "`n"
        Set-LineEnding -Path $crlf -Ending "`r`n"

        Get-CalibrationMeterReferenceHash -Path $crlf | Should -BeExactly (Get-CalibrationMeterReferenceHash -Path $lf)
        Get-CalibrationMeterReferenceHash -Path $lf | Should -BeExactly (Get-CalibrationMeterReferenceHash -Path $script:referencePath)
    }

    It 'covers <Change>' -ForEach @(
        @{ Change = 'the driver'; File = 'Invoke-ReferenceHook.ps1'; Action = 'Edit' }
        @{ Change = 'the frozen reader copy'; File = 'ContributorProfileReader.ps1'; Action = 'Edit' }
        @{ Change = 'the fixture profile'; File = 'fixture/CopilotAtelier/contributor/profile.json'; Action = 'Edit' }
        @{ Change = 'the fixture declaration, inside a dot folder'; File = 'fixture/workspace/.memory-bank/projectbrief.md'; Action = 'Edit' }
        @{ Change = 'a file renamed without a change to its text'; File = 'ContributorProfileReader.ps1'; Action = 'Rename' }
        @{ Change = 'a file added'; File = 'fixture/extra.txt'; Action = 'Add' }
    ) {
        $staged = Copy-Reference
        $before = Get-CalibrationMeterReferenceHash -Path $staged
        $target = Join-Path -Path $staged -ChildPath $File
        switch ($Action)
        {
            'Edit' { [System.IO.File]::AppendAllText($target, ' ') }
            'Rename' { Rename-Item -LiteralPath $target -NewName ('Renamed' + [System.IO.Path]::GetFileName($target)) }
            'Add' { [System.IO.File]::WriteAllText($target, 'x') }
        }

        Get-CalibrationMeterReferenceHash -Path $staged | Should -Not -Be $before
    }

    It 'refuses a path that is not a folder' {
        { Get-CalibrationMeterReferenceHash -Path (Join-Path -Path $script:referencePath -ChildPath 'Invoke-ReferenceHook.ps1') } | Should -Throw
    }

    It 'holds the driver, a frozen reader copy that says no drift test may bind it, and a one-entry fixture' {
        $files = @(
            foreach ($file in [System.IO.Directory]::GetFiles($script:referencePath, '*', [System.IO.SearchOption]::AllDirectories))
            {
                $file.Substring($script:referencePath.Length + 1).Replace('\', '/')
            }
        ) | Sort-Object

        $files | Should -Be @(
            'ContributorProfileReader.ps1'
            'fixture/CopilotAtelier/contributor/profile.json'
            'fixture/workspace/.memory-bank/projectbrief.md'
            'Invoke-ReferenceHook.ps1'
        )
        $copy = [System.IO.File]::ReadAllText((Join-Path -Path $script:referencePath -ChildPath 'ContributorProfileReader.ps1'))
        $copy | Should -Match 'Frozen copy'
        $copy | Should -Match 'No drift test'
        $copy | Should -Match 'function Get-ContributorCalibration'
        $fixtureProfile = Get-Content -LiteralPath (Join-Path -Path $script:referencePath -ChildPath 'fixture/CopilotAtelier/contributor/profile.json') -Raw | ConvertFrom-Json
        @($fixtureProfile.contributors).Count | Should -Be 1 -Because 'one entry keeps git out under -SkipGitForSingleEntry'
        $fixtureProfile.contributors[0].state | Should -BeExactly 'on'
    }
}

Describe 'Frozen reference in <Edition>' -Tag 'Unit' -ForEach $script:editions {
    BeforeAll {
        function script:Invoke-Reference
        {
            <# Runs the driver at Path with a SessionStart payload; returns exit code and streams. #>
            param ([string] $Path)

            $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $Path))
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $process = [System.Diagnostics.Process]::Start($startInfo)
            try
            {
                $outputTask = $process.StandardOutput.ReadToEndAsync()
                $errorTask = $process.StandardError.ReadToEndAsync()
                $process.StandardInput.Write((@{ hook_event_name = 'SessionStart'; session_id = [guid]::NewGuid().ToString(); cwd = $TestDrive; source = 'new' } | ConvertTo-Json -Compress))
                $process.StandardInput.Close()
                if (-not $process.WaitForExit(60000))
                {
                    $process.Kill()
                    throw "$Path did not exit within 60 seconds."
                }

                $process.WaitForExit()
                [pscustomobject] @{ ExitCode = $process.ExitCode; Output = $outputTask.Result; Error = $errorTask.Result }
            }
            finally
            {
                $process.Dispose()
            }
        }
    }

    It 'runs its fixed calibration from a staged copy, writing and emitting nothing, and exits 0' {
        $staged = Copy-Reference
        $before = Get-CalibrationMeterReferenceHash -Path $staged
        $filesBefore = [System.IO.Directory]::GetFiles($staged, '*', [System.IO.SearchOption]::AllDirectories).Count

        $result = Invoke-Reference -Path (Join-Path -Path $staged -ChildPath 'Invoke-ReferenceHook.ps1')

        $result.ExitCode | Should -Be 0 -Because $result.Error
        $result.Output | Should -BeNullOrEmpty
        $result.Error | Should -BeNullOrEmpty
        Get-CalibrationMeterReferenceHash -Path $staged | Should -BeExactly $before
        [System.IO.Directory]::GetFiles($staged, '*', [System.IO.SearchOption]::AllDirectories).Count | Should -Be $filesBefore
    }

    It 'exits 1 when its fixture yields no levels, <Why>' -ForEach @(
        @{ Why = 'as when it runs in place inside the repository'; Mode = 'InPlace' }
        @{ Why = 'as when the fixture profile is missing'; Mode = 'NoProfile' }
    ) {
        $path = Join-Path -Path $script:referencePath -ChildPath 'Invoke-ReferenceHook.ps1'
        if ($Mode -eq 'NoProfile')
        {
            $staged = Copy-Reference
            Remove-Item -LiteralPath (Join-Path -Path $staged -ChildPath 'fixture/CopilotAtelier/contributor/profile.json')
            $path = Join-Path -Path $staged -ChildPath 'Invoke-ReferenceHook.ps1'
        }

        $result = Invoke-Reference -Path $path

        $result.ExitCode | Should -Be 1
        $result.Output | Should -BeNullOrEmpty
    }
}
