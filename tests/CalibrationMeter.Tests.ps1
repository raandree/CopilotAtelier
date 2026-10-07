<#
    Arithmetic of the calibration latency Meter (Decision record 0028,
    rulings A9 and A10): rotated cell order, ratios taken per replicate in
    frozen reference scripts, nearest-rank percentiles, inclusive thresholds,
    the withdrawn launch-unit levels, the re-baseline rule and its unit
    transfer check, and the rule that a verdict above Budget or Fail counts
    only when a second Meter run reproduces it. It also pins the frozen
    reference script (criterion 26). The measurement itself runs only by hand:
    tests/Fixtures/Measure-CalibrationLatency.ps1.
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
    $script:referencePath = Join-Path -Path $script:repoRoot -ChildPath 'tests/Fixtures/Invoke-ReferenceHook.ps1'
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

    It 'takes the ratio inside each replicate in frozen reference scripts, before any percentile' {
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

    It 'refuses a replicate in which the reference script ran no slower than the no-op hook' {
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

    It 'carries no latency level until the re-baseline, because ruling A10 withdrew the launch-unit levels' {
        $budget = Get-CalibrationMeterBudget

        $budget.Level.Count | Should -Be 0
        $budget.ReferenceSha256 | Should -Match '\A[0-9a-f]{64}\z'
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

Describe 'Frozen reference script' -Tag 'Unit' {
    It 'is pinned by its SHA-256, so a change fails until both latency tags are re-baselined (criterion 26)' {
        Get-CalibrationMeterReferenceHash -Path $script:referencePath | Should -BeExactly (Get-CalibrationMeterBudget).ReferenceSha256
    }

    It 'pins the text, not the line endings a checkout gives it' {
        $text = [System.IO.File]::ReadAllText($script:referencePath)
        $lf = Join-Path -Path $TestDrive -ChildPath 'lf.ps1'
        $crlf = Join-Path -Path $TestDrive -ChildPath 'crlf.ps1'
        [System.IO.File]::WriteAllText($lf, $text.Replace("`r`n", "`n"))
        [System.IO.File]::WriteAllText($crlf, $text.Replace("`r`n", "`n").Replace("`n", "`r`n"))

        Get-CalibrationMeterReferenceHash -Path $crlf | Should -BeExactly (Get-CalibrationMeterReferenceHash -Path $lf)
    }

    It 'runs about 4,000 syntax-tree nodes of straight-line code' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:referencePath, [ref] $tokens, [ref] $errors)

        $errors | Should -BeNullOrEmpty
        $ast.FindAll({ $true }, $true).Count | Should -BeGreaterOrEqual 3800
        $ast.FindAll({ $true }, $true).Count | Should -BeLessOrEqual 4200
        $ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.LoopStatementAst] }, $true) | Should -BeNullOrEmpty
        $ast.FindAll({ param ($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Should -BeNullOrEmpty
    }
}

Describe 'Frozen reference script in <Edition>' -Tag 'Unit' -ForEach $script:editions {
    It 'reads its payload like a hook, writes nothing, and exits 0' {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $script:referencePath))
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
            $process.WaitForExit(60000) | Should -BeTrue
            $process.WaitForExit()

            $process.ExitCode | Should -Be 0
            $outputTask.Result | Should -BeNullOrEmpty
            $errorTask.Result | Should -BeNullOrEmpty
        }
        finally
        {
            $process.Dispose()
        }
    }
}
